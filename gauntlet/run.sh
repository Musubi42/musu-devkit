#!/usr/bin/env bash
# Gauntlet du devkit — les scénarios qui définissent l'outil, exécutés.
#
#   ./devkit/gauntlet/run.sh
#
# ⚠️ POURQUOI DES SCÉNARIOS PLUTÔT QUE DES TESTS UNITAIRES
#
# Repris de l'ADR 0008 d'aegis : écrire les scénarios exécutables AVANT le
# moteur, et laisser les scénarios trancher les choix de conception plutôt que
# l'intuition. Ce qu'on veut savoir n'est pas « la fonction sed est-elle
# correcte » mais « un projet amorcé ce matin protège-t-il quelque chose ce
# soir ».
#
# ⚠️ CHAQUE SCÉNARIO ICI EST UN DÉFAUT QUI A EXISTÉ.
#
# Aucun n'est hypothétique. G3, G5 et G6 en particulier sont trois faux verts
# écrits de bonne foi pendant cette session, et trouvés seulement en instanciant
# un deuxième projet ou en lisant un code de sortie. C'est la raison d'être du
# fichier : un garde-fou non testé est une affirmation, pas une protection.
#
# Le gauntlet écrit UNIQUEMENT sous .tmp-gauntlet/ dans ce dépôt, et n'installe
# aucun hook — `guards install` écrirait dans ~/.config/aegis et dans les
# réglages de Claude Code, ce qu'un test n'a pas à faire.
set -uo pipefail

# Le gauntlet a d'abord vécu dans musuPlate/devkit/ ; il remontait donc de deux
# niveaux et cherchait un sous-dossier `devkit`. Le devkit ayant son dépôt, la
# racine du dépôt EST le devkit — un niveau de moins, et plus de sous-dossier.
cd "$(dirname "$0")/.."             # racine du dépôt = le devkit
DEVKIT="$PWD"
BAC="$DEVKIT/.tmp-gauntlet"

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else R=''; G=''; B=''; D=''; Z=''; fi

PASS=0; FAIL=0
scenario() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; PASS=$((PASS + 1)); }
ko()   { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; FAIL=$((FAIL + 1)); }
note() { printf '    %s%s%s\n' "$D" "$1" "$Z"; }

# assert <description> <commande…>  — vrai si la commande réussit
assert()     { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }
assert_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ko "$d"; else ok "$d"; fi; }

# ⚠️ `cmd | grep -q` EST UN PIÈGE ICI, ET IL A RENDU CE GAUNTLET ROUGE À TORT.
#
# `set -o pipefail` donne au pipeline le statut de la commande échouée, pas
# celui de `grep`. Or presque tout ce qu'on vérifie ici sort en 1 EXPRÈS :
# doctor sur un socle non configuré, verify-secrets sans sondes, front-guard
# qui a trouvé une fuite. Le pipeline échouait donc au moment précis où la
# sortie contenait ce qu'on cherchait — et le harnais accusait le socle.
#
# On capture la sortie, puis on la lit. Le code de sortie se teste à part,
# quand c'est lui qui est en cause.
sortie() { ( cd "$1" && shift && "$@" 2>&1 ) || true; }
dit()    { local d="$1" motif="$2"; shift 2
           if printf '%s' "$(sortie "$@")" | grep -q "$motif"; then ok "$d"; else ko "$d"; fi; }
dit_pas() { local d="$1" motif="$2"; shift 2
           if printf '%s' "$(sortie "$@")" | grep -q "$motif"; then ko "$d"; else ok "$d"; fi; }

rm -rf "$BAC"; mkdir -p "$BAC"
trap 'rm -rf "$BAC"' EXIT

# Les garde-fous, depuis le devkit et non depuis la machine : c'est la version
# épinglée qu'on veut exercer.
S="$(cd "$DEVKIT" && nix build .#shhh  --print-out-paths --no-link 2>/dev/null)"
A="$(cd "$DEVKIT" && nix build .#aegis --print-out-paths --no-link 2>/dev/null)"
[ -n "$S" ] && [ -n "$A" ] || { echo "✗ shhh/aegis non constructibles — gauntlet impossible" >&2; exit 1; }
export PATH="$S/bin:$A/bin:$PATH"

# ─────────────────────────────────────────────────────────────────────────────
scenario "G1 — l'amorce non interactive pose un socle complet"

P="$BAC/g1"
if bash "$DEVKIT/lib/musu-init.sh" --nom mon-api --base 7600 --dest "$P" --yes >/dev/null 2>&1; then
  ok "musu-init termine sans erreur"
else
  ko "musu-init échoue"; fi

for f in flake.nix .envrc .sops.yaml .gitignore Taskfile.yml .env.public .env.ref \
         secrets.probes.sh actions.yml scripts/guards.sh scripts/with-secrets.sh; do
  [ -f "$P/$f" ] && ok "$f posé" || ko "$f manquant"
done
assert "les scripts sont exécutables" test -x "$P/scripts/doctor.sh"
for f in "$P"/scripts/*.sh; do
  bash -n "$f" 2>/dev/null || ko "syntaxe cassée : $(basename "$f")"
done
ok "tous les scripts passent bash -n"

# ─────────────────────────────────────────────────────────────────────────────
scenario "G2 — la substitution est complète et cohérente"

assert     "le nom est substitué dans le flake"      grep -q 'mon-api' "$P/flake.nix"
assert_not "aucun placeholder de nom ne subsiste"    grep -rq 'MON-PROJET' "$P"
assert_not "aucun placeholder de ports ne subsiste"  grep -rq '7900-7999' "$P"
assert     "les ports dérivent de la base"           grep -q 'API_PORT=7642' "$P/.env.public"
# Un tiret dans un identifiant Postgres est légal mais exige des guillemets
# doubles dans toute requête. Le défaut se paie au premier `create table`.
assert     "les identifiants SQL prennent des underscores" grep -q 'PGUSER=mon_api' "$P/.env.public"
assert_not "aucun tiret dans les identifiants SQL"   grep -q 'PGUSER=mon-api' "$P/.env.public"

# ─────────────────────────────────────────────────────────────────────────────
scenario "G3 — un socle non configuré REFUSE de se dire sain"
note "régression : la 1re version cherchait des placeholders écrits en dur dans"
note "doctor.sh — que l'amorceur substituait aussi. Le contrôle se corrompait."

Q="$BAC/g3"; mkdir -p "$Q"
(cd "$DEVKIT/templates/socle" && find . -type f -print0) | while IFS= read -r -d '' f; do
  mkdir -p "$Q/$(dirname "$f")"; cp "$DEVKIT/templates/socle/$f" "$Q/$f"
done
chmod +x "$Q"/scripts/*.sh
assert "le marqueur .musu-template est livré par le template" test -f "$Q/.musu-template"
dit "doctor signale le socle non configuré" 'socle NON configuré' "$Q" ./scripts/doctor.sh
dit "doctor reconnaît un socle configuré"    'socle configuré'     "$P" ./scripts/doctor.sh

# ─────────────────────────────────────────────────────────────────────────────
scenario "G4 — un contrôle qui ne peut pas échouer n'est pas un contrôle"

dit "verify-secrets refuse de conclure sans fichier de secrets" 'introuvable' "$P" ./scripts/verify-secrets.sh

# Avec des secrets mais sans sonde, il ne doit PAS rendre un verdict vert :
# sinon il dirait « tout est bon » sur un jeu de clés entièrement mortes.
# ⚠️ `sops` CHERCHE `.sops.yaml` DEPUIS LE RÉPERTOIRE COURANT, PAS DEPUIS
# `--filename-override`. Vérifié — et c'est un piège pour tout script qui
# chiffre pour le compte d'un autre dossier.
#
# Ce gauntlet chiffrait donc, tant qu'il vivait dans musuPlate/devkit/, avec
# les recipients de MUSUPLATE : il passait au vert en prouvant quelque chose
# sur le mauvais dépôt. La sortie du devkit vers son propre dépôt — qui n'a
# pas de `.sops.yaml` — a fait tomber la béquille et rendu le gauntlet rouge.
# C'est exactement ce qu'un gauntlet doit faire.
mkdir -p "$P/secrets"
if ( cd "$P" && printf 'MA_CLE=valeur-jetable-de-gauntlet-0000\n' \
     | sops --encrypt --input-type dotenv --output-type dotenv \
            --filename-override secrets/dev.env /dev/stdin > secrets/dev.env ) 2>/dev/null; then
  dit "verify-secrets échoue tant qu'aucune sonde n'est écrite" 'aucune sonde écrite' "$P" ./scripts/verify-secrets.sh
else
  note "chiffrement impossible (clé age absente de .sops.yaml) — scénario ignoré"
fi

# ─────────────────────────────────────────────────────────────────────────────
scenario "G5 — le garde-fou de bundle détecte, et ne se croit pas sur parole"
note "régression : la 1re vérification a rejoué la fuite avec une VRAIE clé."

dit "front-guard --self-test passe (valeur jetable, jamais un vrai secret)" 'opérationnel' "$P" ./scripts/front-guard.sh --self-test

# Fuite simulée : une valeur jetable, présente dans secrets/dev.env, retrouvée
# dans un faux bundle. C'est le chemin réel, sans brûler quoi que ce soit.
mkdir -p "$P/dist"
printf 'const k="valeur-jetable-de-gauntlet-0000";\n' > "$P/dist/index.js"
dit "front-guard attrape une valeur exacte publiée dans le bundle" 'MA_CLE' "$P" ./scripts/front-guard.sh dist

printf 'const k="rien a voir";\n' > "$P/dist/index.js"
# Ici c'est bien le CODE DE SORTIE qui est en cause : un bundle sain doit
# rendre 0, c'est ce qui fait qu'un build ne casse pas pour rien.
if ( cd "$P" && ./scripts/front-guard.sh dist >/dev/null 2>&1 ); then
  ok "front-guard ne signale pas un bundle sain"
else ko "front-guard signale un bundle sain (faux positif)"; fi

# ─────────────────────────────────────────────────────────────────────────────
scenario "G6 — « installé quelque part » n'est pas « protège ici »"
note "régression : \`aegis status\` liste TOUS les projets et sort en 0 ; le"
note "premier contrôle validait donc un dossier jamais enregistré."

dit "guards status distingue ce projet des autres projets aegis" "CE projet n'est pas enregistré" "$P" ./scripts/guards.sh status
dit "doctor refuse le verdict vert tant que les garde-fous ne sont pas câblés" 'GARDE-FOUS NON CÂBLÉS' "$P" ./scripts/doctor.sh

# ─────────────────────────────────────────────────────────────────────────────
scenario "G7 — l'amorce refuse d'écrire par-dessus du travail existant"

assert_not "musu-init refuse un dossier non vide" \
  bash "$DEVKIT/lib/musu-init.sh" --nom autre --base 7700 --dest "$P" --yes

# ─────────────────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '%sgauntlet VERT%s — %d assertions\n' "$G" "$Z" "$PASS"
  exit 0
fi
printf '%sgauntlet ROUGE%s — %d passées, %d échouées\n' "$R" "$Z" "$PASS" "$FAIL"
exit 1
