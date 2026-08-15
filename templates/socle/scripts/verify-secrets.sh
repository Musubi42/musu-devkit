#!/usr/bin/env bash
# Vérifie que les secrets de musuPlate sont PRÉSENTS et VIVANTS.
#
# ⚠️ POURQUOI CE SCRIPT EXISTE
#
# Un secret mort ne se voit pas : il est présent, bien orthographié, chiffré
# comme il faut — et il échoue au premier appel réel. La seule preuve qu'une
# clé fonctionne est un appel qui réussit. C'est la première commande à lancer
# en rouvrant un projet dormant (03 §7), avant de déboguer la moindre ligne
# d'application.
#
#   task secrets:verify
#
# ⚠️ ON NE SOURCE PAS LE DÉCHIFFRÉ DANS L'ENVIRONNEMENT.
#
# Une variable ABSENTE du fichier sops serait quand même lue — depuis .env.public
# ou depuis un shell MUSU_SECRETS=1 resté ouvert. Le script rendrait alors un
# verdict sur l'environnement du poste au lieu du fichier qu'il prétend
# vérifier, et il le rendrait faux dans le sens le plus dangereux : « tout est
# bon » pour un secret qui n'existe pas. `sget` lit UNIQUEMENT le texte
# déchiffré, gardé en mémoire.
#
# Aucun effet de bord : rien n'est écrit, aucun email n'est envoyé.
set -uo pipefail

cd "$(dirname "$0")/.."

SECRETS_FILE="secrets/dev.env"
REF_FILE=".env.ref"

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; Z=''
fi

FAILED=0; WARNED=0
ok()    { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; FAILED=$((FAILED + 1)); }
warn()  { printf '  %s!%s %s\n' "$Y" "$Z" "$1"; WARNED=$((WARNED + 1)); }
note()  { printf '    %s%s%s\n' "$D" "$1" "$Z"; }
head_() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }

command -v sops >/dev/null || { echo "✗ sops introuvable" >&2; exit 1; }
[ -f "$SECRETS_FILE" ] || { echo "✗ $SECRETS_FILE introuvable — rien à vérifier." >&2; exit 1; }

PLAIN="$(sops --decrypt "$SECRETS_FILE")" || {
  echo "✗ $SECRETS_FILE non déchiffrable — clé age de cette machine absente de .sops.yaml ?" >&2
  exit 1
}

# Rend la valeur d'une clé, ou une chaîne vide. `cut -f2-` préserve les `=`
# internes (les jetons en contiennent) ; le sed retire les guillemets que
# certains éditeurs ajoutent.
sget() {
  printf '%s\n' "$PLAIN" \
    | grep -m1 "^$1=" \
    | cut -d= -f2- \
    | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

# Empreinte non réversible, pour distinguer deux valeurs sans en montrer une.
# ⚠️ Jamais la valeur elle-même, jamais dans un log, jamais dans un message.
fp() { printf '%s' "$1" | shasum -a 256 | cut -c1-8; }

# --- 1. Couverture : tout ce que .env.ref annonce est-il présent ? ----------
#
# C'est la panne la plus fréquente et la moins visible : une variable ajoutée
# au code, documentée dans .env.ref, jamais ajoutée au fichier chiffré. Elle ne
# se manifeste qu'au premier appel qui en a besoin.

head_ "Couverture (.env.ref → $SECRETS_FILE)"

expected="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=sops://' "$REF_FILE" 2>/dev/null | cut -d= -f1)"
if [ -z "$expected" ]; then
  warn "aucune variable sops:// déclarée dans $REF_FILE"
else
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if [ -n "$(sget "$k")" ]; then
      ok "$k présent  ${D}[$(fp "$(sget "$k")")]${Z}"
    else
      bad "$k déclaré dans $REF_FILE, absent de $SECRETS_FILE"
    fi
  done <<<"$expected"
fi

# --- 2. Vivacité : la clé répond-elle vraiment ? ---------------------------
#
# ⚠️ LA SEULE PARTIE PROPRE AU PROJET EST DANS UN AUTRE FICHIER.
#
# Tout ce qui précède et tout ce qui suit — couverture, hygiène, déchiffrement,
# présentation — est identique dans n'importe quel dépôt. Les SONDES, elles,
# dépendent des fournisseurs utilisés. Les mélanger dans un seul script est ce
# qui fait qu'on recopie 200 lignes pour en changer 15, puis qu'on corrige un
# bug dans un dépôt sur vingt.
#
# `secrets.probes.sh` est sourcé, pas exécuté : il hérite de `sget`, `ok`,
# `bad`, `warn` et `note`, et n'a donc à contenir QUE la connaissance
# fournisseur — l'appel le moins cher, et la lecture du code de retour.

head_ "Vivacité (appel réel au fournisseur)"

if [ -f secrets.probes.sh ]; then
  # shellcheck disable=SC1091
  . ./secrets.probes.sh
else
  warn "secrets.probes.sh absent — aucune sonde fournisseur"
  note "sans lui, ce script dit que les secrets sont PRÉSENTS, jamais qu'ils sont VIVANTS"
fi

# --- 3. Hygiène : le clair a-t-il reflué sur le disque ? -------------------
#
# La panne que ce dépôt existe pour éprouver. On la teste au lieu de la
# supposer absente.

head_ "Hygiène"

if [ -f .env ]; then
  bad ".env en clair présent à la racine"
  note "task secrets:clean le détruit — il n'a de raison d'exister que pendant une édition"
else
  ok "pas de .env en clair"
fi

if grep -qE '^\.env$' .gitignore 2>/dev/null; then
  ok ".env couvert par .gitignore"
else
  bad ".env NON couvert par .gitignore"
fi

for f in secrets/*.env; do
  [ -e "$f" ] || continue
  if head -c 4000 "$f" | grep -q 'sops'; then
    ok "$(basename "$f") est chiffré"
  else
    bad "$(basename "$f") ne porte pas de métadonnées sops — EN CLAIR ?"
  fi
done

unset PLAIN RESEND_KEY

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%s%d échec(s)%s, %d avertissement(s)\n' "$R" "$FAILED" "$Z" "$WARNED"
  exit 1
fi
printf '%stout est vert%s, %d avertissement(s)\n' "$G" "$Z" "$WARNED"
