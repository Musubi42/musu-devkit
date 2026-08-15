#!/usr/bin/env bash
# Échoue si un secret a fini dans les octets servis au navigateur.
#
#   ./scripts/front-guard.sh [dist]
#   ./scripts/front-guard.sh --self-test
#
# ⚠️ LE PIÈGE QU'IL GARDE
#
# Un bundler front inline dans le code servi toute variable portant le préfixe
# convenu (`VITE_` pour Vite, `NEXT_PUBLIC_` pour Next, `PUBLIC_` pour
# SvelteKit). C'est documenté, c'est voulu, et ça se retourne toujours de la
# même façon : une valeur manque côté front, quelqu'un la préfixe pour « la
# rendre visible », le build passe, l'application marche — et la clé est en
# ligne.
#
# Mesuré sur Vite : la variable n'est inlinée QUE si une ligne de code écrit
# `import.meta.env.VITE_X`. Le danger n'est donc pas dans le fichier de
# configuration — l'auditer ne prouve rien — mais dans une ligne de code qui
# marche du premier coup et ne se distingue pas d'une lecture légitime.
#
# ⚠️ DEUX PASSES, ET ELLES NE CHERCHENT PAS LA MÊME CHOSE
#
#   1. VALEURS EXACTES — les vraies valeurs de secrets/*.env comparées aux
#      octets produits. Aucun faux négatif dû à un fournisseur au format
#      inhabituel : on ne devine rien, on compare ce qu'on possède.
#      Angle mort : une clé qu'on ne possède pas — celle d'un collègue, une
#      valeur codée en dur par quelqu'un d'autre — passe au travers.
#
#   2. shhh scan — ~222 règles de fournisseurs. Attrape précisément l'angle
#      mort de la passe 1 : les secrets qu'on ne connaît pas.
#      Angle mort symétrique : une clé au format non répertorié.
#
# Les deux angles morts sont complémentaires, et c'est la raison d'être des
# deux passes. Réécrire la passe 2 à la main produirait une liste de motifs
# toujours en retard d'un fournisseur : c'est le travail de shhh, pas le nôtre.
set -uo pipefail

cd "$(dirname "$0")/.."

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; Z=$'\033[0m'
else
  R=''; G=''; Y=''; D=''; Z=''
fi

# Le cœur du contrôle, isolé pour être testable sans secret réel.
# -F : la valeur n'est pas une expression régulière. -q : la ligne trouvée
# CONTIENT le secret, elle ne doit jamais atteindre une sortie.
contient() { grep -rqF -- "$2" "$1" 2>/dev/null; }

# --- Auto-test ------------------------------------------------------------
#
# ⚠️ POURQUOI CE MODE EXISTE — c'est une leçon payée.
#
# Pour vérifier que ce garde-fou attrapait bien une fuite, la première méthode
# a été de rejouer la fuite en vrai : la vraie clé exportée dans un build, puis
# nettoyée. Le contrôle a fonctionné, mais la valeur avait alors transité par
# la sortie d'outils et par une transcription — on avait brûlé une clé pour
# prouver qu'on savait détecter les clés brûlées.
#
# Un garde-fou se teste avec une valeur JETABLE. Le mécanisme testé est le
# même : `contient` ne sait pas d'où vient la chaîne qu'on lui donne.
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  canari="canari-$(openssl rand -hex 16)"
  mkdir -p "$tmp/propre" "$tmp/contamine"
  printf 'const a="rien a voir";\n' > "$tmp/propre/index.js"
  printf 'const k="%s";\n' "$canari" > "$tmp/contamine/index.js"

  echec=0
  contient "$tmp/contamine" "$canari" \
    && echo "  ✓ une valeur présente est détectée" \
    || { echo "  ✗ FAUX NÉGATIF" >&2; echec=1; }
  contient "$tmp/propre" "$canari" \
    && { echo "  ✗ FAUX POSITIF" >&2; echec=1; } \
    || echo "  ✓ un bundle sain n'est pas signalé"

  [ "$echec" -eq 0 ] && echo "✓ garde-fou opérationnel (valeur jetable)"
  exit "$echec"
fi

# --- Contrôle réel --------------------------------------------------------

DIST="${1:-apps/front/dist}"
SECRETS="${SECRETS_FILE:-secrets/dev.env}"

if [ ! -d "$DIST" ]; then
  echo "→ $DIST absent — rien à inspecter. Construire le front d'abord." >&2
  exit 0
fi

FOUND=0

# Passe 1 — valeurs exactes.
if [ -f "$SECRETS" ] && command -v sops >/dev/null; then
  PLAIN="$(sops --decrypt "$SECRETS")" || { echo "✗ $SECRETS non déchiffrable" >&2; exit 1; }
  while IFS= read -r line; do
    name="${line%%=*}"
    value="${line#*=}"
    value="$(printf '%s' "$value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/")"
    # Une valeur trop courte produirait des collisions fortuites dans du JS minifié.
    [ ${#value} -ge 12 ] || continue
    if contient "$DIST" "$value"; then
      echo "${R}✗${Z} $name est présent dans $DIST — publié au navigateur" >&2
      FOUND=$((FOUND + 1))
    fi
  done <<<"$(printf '%s\n' "$PLAIN" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=')"
  unset PLAIN
else
  echo "${Y}!${Z} $SECRETS absent — passe « valeurs exactes » ignorée" >&2
fi

# Passe 2 — motifs de fournisseurs, délégués à shhh.
#
# ⚠️ `shhh scan` SORT TOUJOURS EN 0, y compris quand il trouve. Vérifié.
# C'est cohérent avec son métier — il inspecte, il ne juge pas — mais un
# `if ! shhh scan …` serait donc un contrôle qui ne déclenche jamais : vert en
# toutes circonstances, et faux exactement le jour où il compte. On lit sa
# sortie `-format json`, qui rend `[]` quand il n'y a rien.
if command -v shhh >/dev/null; then
  rapport="$(shhh scan -format json "$DIST" 2>/dev/null)"
  if printf '%s' "$rapport" | grep -q '"findings"'; then
    echo "${R}✗${Z} shhh signale des valeurs de forme secrète dans $DIST :" >&2
    # La sortie texte de shhh rend des valeurs tronquées (`ghp_•••`), jamais
    # les valeurs entières : elle est sûre à afficher, contrairement à ce que
    # rendrait un grep maison.
    shhh scan "$DIST" 2>&1 | sed -n '/detected/,/━━━/p' | head -20 >&2
    FOUND=$((FOUND + 1))
  fi
else
  echo "${Y}!${Z} shhh absent — passe « motifs fournisseurs » ignorée (direnv allow)" >&2
fi

if [ "$FOUND" -gt 0 ]; then
  printf '\n%s%d signalement(s). Ces clés sont à considérer comme BRÛLÉES : les rotater.%s\n' "$R" "$FOUND" "$Z" >&2
  printf '%sLe correctif n%est pas de retirer la variable du .env — c%est de retirer la ligne de code qui la lit, et de passer par un appel serveur.%s\n' "$D" "'" "'" "$Z" >&2
  exit 1
fi
echo "${G}✓${Z} $DIST : aucune valeur exacte, aucun motif de fournisseur"
