#!/usr/bin/env bash
# musu-init — pose le socle gardé dans un dossier, en posant des questions.
#
#   nix run github:Musubi42/musu-devkit
#   nix run github:Musubi42/musu-devkit -- --nom mon-api --base 7600 --dest ./mon-api
#
# ⚠️ POURQUOI DEUX CHEMINS D'AMORÇAGE ET PAS UN
#
# `nix flake init -t` copie le template tel quel : reproductible, scriptable,
# mais il laisse une douzaine de placeholders à remplacer à la main, et on en
# oublie toujours un.
#
# Un amorceur interactif est agréable et ne se rejoue pas : impossible de
# reproduire une amorce, impossible de la tester.
#
# D'où la superposition : ce script n'est qu'un GÉNÉRATEUR D'ARGUMENTS pour la
# substitution, et il accepte tous ses choix en ligne de commande. Le mode
# interactif ne fait que remplir ces arguments. Le gauntlet appelle la forme
# non interactive — donc ce qui est testé est bien ce qui tourne.
#
# ⚠️ CE SCRIPT N'EXÉCUTE NI git NI L'INSTALLATION DES GARDE-FOUS.
# Il écrit des fichiers et AFFICHE les commandes suivantes. Un amorceur qui
# commite et installe des hooks à votre place est un amorceur dont on ne relit
# jamais la sortie.
set -euo pipefail

if [ -t 1 ]; then
  G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else
  G=''; Y=''; B=''; D=''; Z=''
fi

NOM=""; BASE=""; DEST=""; ASSUME_YES=0
TEMPLATE="${MUSU_TEMPLATE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --nom)      NOM="$2"; shift 2 ;;
    --base)     BASE="$2"; shift 2 ;;
    --dest)     DEST="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --yes)      ASSUME_YES=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

demander() { # <invite> <défaut>
  local rep
  if [ "$ASSUME_YES" -eq 1 ]; then printf '%s' "$2"; return; fi
  printf '%s' "$1" >&2
  [ -n "$2" ] && printf ' %s[%s]%s' "$D" "$2" "$Z" >&2
  printf ' › ' >&2
  read -r rep
  printf '%s' "${rep:-$2}"
}

printf '\n%s musu-init %s— un projet neuf naît déjà gardé\n\n' "$B" "$Z"

# --- Nom -------------------------------------------------------------------
while :; do
  [ -n "$NOM" ] || NOM="$(demander 'Nom du projet (minuscules, tirets)' '')"
  if printf '%s' "$NOM" | grep -qE '^[a-z][a-z0-9-]*$'; then break; fi
  echo "  ✗ minuscules, chiffres et tirets uniquement" >&2; NOM=""
done

# `mon-api` est un identifiant Postgres légal mais qui exige des guillemets
# doubles dans toute requête SQL. On l'apprend au premier `create table`, loin
# d'ici. Les identifiants de base prennent donc des underscores.
NOM_SQL="$(printf '%s' "$NOM" | tr '-' '_')"

# --- Tranche de ports ------------------------------------------------------
#
# ⚠️ LE REGISTRE FAIT AUTORITÉ, ET IL N'EST PAS ICI.
#
# `fs/03-ops/ports.md` dans musu-os est la source de vérité des allocations.
# Ce script le LIT s'il le trouve, pour proposer la prochaine tranche libre —
# mais il ne l'écrit jamais. Une allocation qu'un générateur inscrit tout seul
# est une allocation que personne n'a arbitrée, et deux projets finissent sur
# la même tranche.
REGISTRE="${MUSU_PORTS_REGISTRY:-$HOME/Documents/Musubi42/musu-os/fs/03-ops/ports.md}"
SUGGERE=""
if [ -f "$REGISTRE" ]; then
  SUGGERE="$(grep -oE 'prochaine allocation *: *[0-9]{4}' "$REGISTRE" 2>/dev/null | grep -oE '[0-9]{4}$' | head -1)"
fi
[ -n "$SUGGERE" ] && printf '  %s→ registre : prochaine tranche libre %s%s\n' "$D" "$SUGGERE" "$Z"

while :; do
  [ -n "$BASE" ] || BASE="$(demander 'Base de la tranche de 100 ports' "$SUGGERE")"
  if printf '%s' "$BASE" | grep -qE '^[0-9]{4}$' && [ $((BASE % 100)) -eq 0 ]; then break; fi
  echo "  ✗ quatre chiffres, multiple de 100 (ex. 7600)" >&2; BASE=""
done

# Suffixes conventionnels du registre : front +73, api +42, db +32, redis +79,
# mail +25 (SMTP +26).
P_API=$((BASE + 42)); P_FRONT=$((BASE + 73)); P_PG=$((BASE + 32))
P_REDIS=$((BASE + 79)); P_MAIL=$((BASE + 25)); P_SMTP=$((BASE + 26))

# --- Destination -----------------------------------------------------------
[ -n "$DEST" ] || DEST="$(demander 'Dossier de destination' "./$NOM")"
if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "✗ $DEST existe et n'est pas vide — refus d'écrire par-dessus" >&2
  exit 1
fi

# --- Clé age ---------------------------------------------------------------
#
# Le .sops.yaml du template porte un placeholder. Le remplacer par la vraie
# clé publique de cette machine est le geste qui rend le chiffrement utilisable
# tout de suite ; ne pas le faire produit un fichier que personne ne déchiffre,
# et on ne s'en aperçoit qu'au moment d'en avoir besoin.
#
# ⚠️ On ne lit QUE les lignes `# public key:`. Le trousseau contient aussi les
# clés privées, qui ne doivent jamais transiter par une sortie standard.
KEYS="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
PUBKEY=""
if [ -f "$KEYS" ]; then
  PUBKEY="$(grep '^# public key:' "$KEYS" 2>/dev/null | grep -oE 'age1[a-z0-9]{58}' | head -1)"
fi
if [ -n "$PUBKEY" ]; then
  printf '  %s→ clé age locale trouvée : %s…%s\n' "$D" "${PUBKEY:0:16}" "$Z"
else
  printf '  %s! aucune clé age locale — .sops.yaml gardera son placeholder%s\n' "$Y" "$Z"
fi

# --- Écriture --------------------------------------------------------------

TEMPLATE="${TEMPLATE:-$(dirname "$(dirname "$(readlink -f "$0")")")/templates/socle}"
[ -d "$TEMPLATE" ] || { echo "✗ template introuvable : $TEMPLATE" >&2; exit 1; }

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd -P)"

printf '\n%s→%s %s vers %s (ports %s-%s)\n\n' "$B" "$Z" "$NOM" "$DEST" "$BASE" "$((BASE + 99))"

# `find` plutôt que `cp -r` : les fichiers du template commencent pour moitié
# par un point, et `cp template/* ` les manquerait silencieusement.
(cd "$TEMPLATE" && find . -type f -print0) | while IFS= read -r -d '' f; do
  mkdir -p "$DEST/$(dirname "$f")"
  sed -e "s/MON-PROJET/$NOM/g" \
      -e "s/mon_projet/$NOM_SQL/g" \
      -e "s/7900-7999/$BASE-$((BASE + 99))/g" \
      -e "s/7942/$P_API/g" -e "s/7973/$P_FRONT/g" -e "s/7932/$P_PG/g" \
      -e "s/7979/$P_REDIS/g" -e "s/7925/$P_MAIL/g" -e "s/7926/$P_SMTP/g" \
      ${PUBKEY:+-e "s|age1REMPLACER000000000000000000000000000000000000000000000000|$PUBKEY|g"} \
      "$TEMPLATE/$f" > "$DEST/$f"
  printf '  %s\n' "${f#./}"
done

chmod +x "$DEST"/scripts/*.sh
mkdir -p "$DEST/secrets"

# Le marqueur atteste qu'un socle n'a pas été configuré ; il vient de l'être.
# `nix flake init -t` le laisse en place, et c'est voulu : par ce chemin-là,
# personne n'a encore remplacé quoi que ce soit.
rm -f "$DEST/.musu-template"

cat <<FIN

${G}Socle posé.${Z} Ce que musu-init ne fait PAS à votre place :

  ${B}1.${Z} Réserver la tranche ${BASE}-$((BASE + 99)) au registre — il fait autorité :
     ${D}musu-os/fs/03-ops/ports.md${Z}

  ${B}2.${Z} cd $DEST && direnv allow

  ${B}3.${Z} task guards:install
     ${D}câble shhh (fuite vers le modèle) et aegis (destruction par l'agent).
     Affiche d'abord ce qui a DÉJÀ fui — c'est ce chiffre qui fait garder le hook.${Z}

  ${B}4.${Z} Créer les secrets. Le .gitignore est déjà en place, avant tout git add :
     ${D}printf 'MA_CLE=...\\n' | sops --encrypt --input-type dotenv \\
       --output-type dotenv --filename-override secrets/dev.env /dev/stdin \\
       > secrets/dev.env${Z}
     puis déclarer les mêmes noms dans .env.ref.

  ${B}5.${Z} Écrire secrets.probes.sh — tant qu'il est vide, ${D}task secrets:verify${Z}
     échoue exprès : un contrôle qui vérifie la seule présence dirait
     « tout est vert » sur des clés mortes.

  ${B}6.${Z} task doctor

FIN
