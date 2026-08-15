#!/usr/bin/env bash
# État du squelette : outils, clé age, chiffrement, hygiène.
#
# ⚠️ NE DÉCHIFFRE RIEN et n'affiche aucune valeur. C'est la commande qu'on lance
# en arrivant, y compris quand on n'a pas encore le droit de déchiffrer — elle
# doit dire « ta clé n'est pas dans .sops.yaml » plutôt que d'échouer sur une
# erreur de sops incompréhensible.
set -uo pipefail

cd "$(dirname "$0")/.."

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; Z=''
fi

FAILED=0
ok()    { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; FAILED=$((FAILED + 1)); }
warn()  { printf '  %s!%s %s\n' "$Y" "$Z" "$1"; }
note()  { printf '    %s%s%s\n' "$D" "$1" "$Z"; }
head_() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }

# ⚠️ UN TEMPLATE NON CONFIGURÉ DOIT LE DIRE, PAS AVOIR L'AIR SAIN.
#
# Sécurité positive : l'état sûr s'atteint par absence de signal. Tant que les
# placeholders sont là, l'absence de configuration EST le signal d'alarme — et
# non un silence qu'on interprète comme « rien à faire ». Un socle fraîchement
# posé qui affiche « tout est vert » est le pire départ possible : il apprend
# dès la première minute que le vert ne veut rien dire.
head_ "Configuration du socle"
if [ -f .musu-template ]; then
  bad "socle NON configuré — le marqueur .musu-template est encore là"
  note "il liste ce qui reste à remplacer ; le supprimer est le dernier geste"
else
  ok "socle configuré (marqueur .musu-template retiré)"
fi

head_ "Outils"
for t in sops age task node docker curl jq; do
  if command -v "$t" >/dev/null; then ok "$t"; else bad "$t manquant"; fi
done

head_ "Identité age de cette machine"
KEYS="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [ ! -f "$KEYS" ]; then
  bad "aucun trousseau age ($KEYS)"
  note "age-keygen -o $KEYS, puis ajouter la pubkey à .sops.yaml"
else
  # On ne lit QUE les lignes de commentaire `# public key:`. Le fichier
  # contient aussi les clés privées, qui ne doivent jamais transiter par une
  # sortie standard.
  mine="$(grep -oE 'age1[a-z0-9]{58}' <(grep '^# public key:' "$KEYS") | sort -u)"
  declared="$(grep -oE 'age1[a-z0-9]{58}' .sops.yaml | sort -u)"
  n=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if printf '%s\n' "$declared" | grep -qF "$k"; then
      ok "clé locale autorisée par .sops.yaml  ${D}${k:0:12}…${Z}"
      n=$((n + 1))
    fi
  done <<<"$mine"
  [ "$n" -gt 0 ] || {
    bad "aucune clé locale n'est recipient de .sops.yaml — déchiffrement impossible"
    note "ajouter la pubkey à .sops.yaml depuis une machine autorisée, puis : sops updatekeys secrets/dev.env"
  }
fi

head_ "Chiffrement"
if [ -f secrets/dev.env ]; then
  if head -c 4000 secrets/dev.env | grep -q 'sops'; then
    ok "secrets/dev.env chiffré ($(grep -oE 'age1[a-z0-9]{58}' secrets/dev.env | sort -u | wc -l | tr -d ' ') recipients)"
  else
    bad "secrets/dev.env NE PORTE PAS de métadonnées sops — en clair ?"
  fi
else
  warn "secrets/dev.env absent — la stack locale tourne, les appels aux fournisseurs échoueront"
fi

head_ "Hygiène"
if [ -f .env ]; then
  bad ".env en clair à la racine"
  note "task secrets:clean"
else
  ok "pas de .env en clair"
fi
grep -qE '^\.env$' .gitignore 2>/dev/null && ok ".env gitignoré" || bad ".env non gitignoré"
[ -d .git ] && ok "dépôt git initialisé" || warn "pas encore un dépôt git"

# ⚠️ Le grief central contre le chargement des secrets par le shell : direnv
# recopie tout ce qu'il pose dans DIRENV_DIFF, variable héritée par tous les
# processus enfants. Un `unset` sur une clé ne la retire donc PAS de
# l'environnement — elle y reste jusqu'à la sortie du dossier. On le signale
# plutôt que de le supposer absent.
if [ -n "${DIRENV_DIFF:-}" ] && [ -f .env.ref ]; then
  fuites=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    eval "val=\${$v:-}"
    [ -n "$val" ] && { warn "$v est dans CE shell (MUSU_SECRETS=1 ?)"; fuites=$((fuites + 1)); }
  done <<<"$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=sops://' .env.ref | cut -d= -f1)"
  [ "$fuites" -gt 0 ] && note "ils survivent à un \`unset\` : direnv en garde une copie dans DIRENV_DIFF"
fi

head_ "Garde-fous"
# Délégué : guards.sh sait distinguer « binaire présent » de « hook câblé ».
#
# ⚠️ Son code de sortie dit « il manque un garde-fou », PAS « le script est
# absent ». Confondre les deux — ce que faisait un `|| warn "absent"` — produit
# un diagnostic qui accuse le mauvais coupable, et on va chercher un fichier
# qui est là.
GARDES=0
if [ -x ./scripts/guards.sh ]; then
  ./scripts/guards.sh status --embed || GARDES=1
else
  bad "scripts/guards.sh manquant — le socle ne sait plus dire ce qu'il protège"
fi

# ⚠️ AUCUN OUTIL EXTERNE POUR SONDER UN PORT.
#
# Ce bloc appelait `lsof` une fois par port. Le 2026-08-16, sur une machine
# par ailleurs saine, un SEUL appel a dépassé trois minutes — `lsof` interroge
# tout l'espace des descripteurs, et un point de montage réseau lent suffit à
# le figer. `doctor` ne rendait plus son verdict.
#
# Un diagnostic qui peut se bloquer est un diagnostic qu'on cesse de lancer,
# donc un garde-fou qui n'existe plus. La sonde ci-dessous est native à bash :
# une tentative de connexion sur la boucle locale, refusée instantanément si
# rien n'écoute. Aucun processus, rien à installer, rien qui puisse pendre.
port_ouvert() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && exec 3>&-; }

# ⚠️ LES PORTS SE LISENT, ILS NE S'ÉCRIVENT PAS ICI.
#
# Ce bloc a d'abord contenu la liste en dur. Ça marchait — dans ce dépôt-là.
# Instancié dans un projet voisin par l'amorceur, le même script
# affichait fidèlement les ports du projet SOURCE : un diagnostic qui parle
# d'une autre machine que celle qu'on regarde, et qui a l'air juste. C'est le
# défaut de conception qu'un socle recopié produit en série, et il se voit
# d'autant moins que la sortie est verte.
#
# La tranche vient d'actions.yml, les ports de .env.public. Les deux sont des
# fichiers du projet : le script n'a plus rien à savoir de lui.
TRANCHE="$(grep -m1 '^ports:' actions.yml 2>/dev/null | sed -E 's/^ports: *([0-9]+-[0-9]+).*/\1/')"
head_ "Ports ${TRANCHE:-non déclarés}"

PORTS="$(grep -hoE '^[A-Z_]*PORT[A-Z_]*=[0-9]+' .env.public 2>/dev/null | cut -d= -f2 | sort -un)"
if [ -z "$PORTS" ]; then
  warn "aucun port déclaré dans .env.public"
else
  occupes=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # Un port hors de la tranche annoncée est un empiètement sur le voisin :
    # deux projets qui se marchent dessus au prochain `up` simultané.
    if [ -n "$TRANCHE" ] && { [ "$p" -lt "${TRANCHE%%-*}" ] || [ "$p" -gt "${TRANCHE##*-}" ]; }; then
      bad "$p est hors de la tranche $TRANCHE"
    fi
    if port_ouvert "$p"; then
      note "$p occupé"; occupes=$((occupes + 1))
    fi
  done <<<"$PORTS"
  ok "$(printf '%s\n' "$PORTS" | grep -c .) ports déclarés, $occupes en écoute"
fi
note "l'allocation de la tranche se valide au registre musu-os fs/03-ops/ports.md"

# ⚠️ « SAIN » NE DOIT PAS VOULOIR DIRE « NON PROTÉGÉ ».
#
# Sécurité positive : tant qu'un garde-fou n'est pas câblé, l'absence de
# protection est le fait saillant — pas une note de bas de page sous un verdict
# vert. Un socle qui affiche « sain » sur un projet qu'aucun filet ne couvre
# apprend dès le premier jour que le vert ne veut rien dire.
printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%s%d problème(s)%s\n' "$R" "$FAILED" "$Z"
elif [ "$GARDES" -ne 0 ]; then
  printf '%ssocle sain, GARDE-FOUS NON CÂBLÉS%s — task guards:install\n' "$Y" "$Z"
else
  printf '%ssocle sain et gardé%s\n' "$G" "$Z"
fi
exit $(( FAILED > 0 ))
