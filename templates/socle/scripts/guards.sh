#!/usr/bin/env bash
# Les garde-fous du poste : shhh (fuite vers le modèle) et aegis (destruction
# par l'agent). Ce script les câble, les interroge, et rien d'autre.
#
#   ./scripts/guards.sh status     # que protège-t-on, ici, maintenant ?
#   ./scripts/guards.sh install    # câble les deux sur ce projet
#   ./scripts/guards.sh scan       # secrets présents dans l'arbre de travail
#   ./scripts/guards.sh audit      # ce qui a DÉJÀ atteint le modèle
#
# ⚠️ LA DOCTRINE COMMUNE, ET POURQUOI ELLE JUSTIFIE DE LES METTRE ENSEMBLE
#
# Sécurité positive (aegis, ADR 0001) : l'état sûr s'atteint par ABSENCE de
# signal. Il faut un signal pour assouplir, jamais pour protéger. Le frein
# serre quand la liaison se coupe.
#
# Les trois garde-fous de ce socle appliquent la même règle à trois surfaces :
#
#   fuite vers le modèle      shhh    redige avant que la sortie n'atteigne le modèle
#   destruction par l'agent   aegis   snapshote AVANT chaque action, sans classer
#   secret en clair           sops    rien n'est chargé sans commande explicite
#
# Et aucun des trois ne parie sur la reconnaissance de la menace : aegis refuse
# d'énumérer les commandes dangereuses (liste toujours incomplète), sops ne
# suppose pas quel processus est de confiance, et le contrôle de bundle
# ci-dessous cherche les VRAIES valeurs plutôt que des motifs de clés.
#
# ⚠️ OÙ ÉCRIT `install`, EXACTEMENT
# `shhh install --scope project` écrit dans ./.claude/settings.json, DANS le
# projet. `aegis init` écrit HORS du projet, à deux endroits : le shadow sous
# ~/.config/aegis, et un hook PreToolUse GLOBAL dans ~/.claude/settings.json.
# Tout est annoncé et confirmé avant d'être fait — le détail dans le texte de
# `install`, qui est ce que l'opérateur lit au moment de répondre.
set -uo pipefail

cd "$(dirname "$0")/.."

if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; D=$'\033[2m'; Z=$'\033[0m'
else
  R=''; G=''; Y=''; B=''; D=''; Z=''
fi
ok()    { printf '  %s✓%s %s\n' "$G" "$Z" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; }
warn()  { printf '  %s!%s %s\n' "$Y" "$Z" "$1"; }
note()  { printf '    %s%s%s\n' "$D" "$1" "$Z"; }
head_() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }

CMD="${1:-status}"
shift || true

case "$CMD" in

  status)
    # --quiet : une ligne, seulement s'il manque quelque chose (shellHook).
    # --embed : sans entête, l'appelant a déjà écrit le sien (doctor).
    QUIET=0; EMBED=0
    case "${1:-}" in --quiet) QUIET=1 ;; --embed) EMBED=1 ;; esac
    [ "$QUIET" -eq 1 ] || [ "$EMBED" -eq 1 ] || head_ "Garde-fous"

    manquants=0

    if command -v shhh >/dev/null; then
      # ⚠️ UN BINAIRE PRÉSENT NE PROUVE PAS QU'IL EST CÂBLÉ.
      # C'est le genre exact de ligne verte que personne n'a vérifiée : shhh
      # est dans le PATH, donc « on est protégé » — alors que le hook n'a
      # jamais été écrit. On regarde le réglage, pas le binaire.
      #
      # Deux portées possibles, et on vérifie les deux : `--scope project`
      # écrit dans ./.claude/settings.json, `--scope global` dans ~/.claude.
      if grep -q 'shhh' ./.claude/settings.json 2>/dev/null; then
        [ "$QUIET" -eq 1 ] || ok "shhh $(shhh version 2>/dev/null | awk '{print $2}') — hook câblé (projet)"
      elif grep -q 'shhh' "$HOME/.claude/settings.json" 2>/dev/null; then
        [ "$QUIET" -eq 1 ] || ok "shhh $(shhh version 2>/dev/null | awk '{print $2}') — hook câblé (global)"
      else
        [ "$QUIET" -eq 1 ] || warn "shhh présent mais NON câblé — le binaire ne protège rien tout seul"
        note "task guards:install"
        manquants=$((manquants + 1))
      fi
    else
      [ "$QUIET" -eq 1 ] || bad "shhh absent — entrer dans le devShell (direnv allow)"
      manquants=$((manquants + 1))
    fi

    if command -v aegis >/dev/null; then
      # ⚠️ DEUX PIÈGES ICI, ET LE SECOND N'EST APPARU QU'À L'USAGE.
      #
      # 1. `aegis status` LISTE TOUS LES PROJETS ENREGISTRÉS ET SORT EN 0.
      #    Un `if aegis status >/dev/null` répond « protégé » dès qu'aegis
      #    connaît UN projet, fût-ce une démo dans /tmp datant de six semaines.
      #    Le premier jet faisait ça, et affichait « shadow actif » sur un
      #    dossier qui n'avait jamais vu `aegis init`.
      #
      # 2. `aegis status --json` prend ~45 s dès qu'un projet réel est
      #    enregistré (mesuré le 2026-08-16, un seul projet, shadow de 456 Ko).
      #    Appelé depuis `doctor`, il rendait le diagnostic inutilisable — et
      #    un `doctor` qui met une minute est un `doctor` que personne ne
      #    lance, donc un garde-fou qui n'existe pas.
      #
      # On lit donc le registre, qui est un simple fichier : aegis y écrit
      # ~/.config/aegis/projects/<nom>.json avec le chemin du projet. Coût
      # nul, et la question posée reste la bonne — « CE dossier-ci, pas un
      # autre ».
      ici="$(pwd -P)"
      reg="${XDG_CONFIG_HOME:-$HOME/.config}/aegis/projects/$(basename "$ici").json"
      if [ -f "$reg" ] && grep -qF "\"$ici\"" "$reg"; then
        [ "$QUIET" -eq 1 ] || ok "aegis — ce projet est enregistré, shadow actif"
      else
        [ "$QUIET" -eq 1 ] || warn "aegis présent, mais CE projet n'est pas enregistré"
        note "task guards:install"
        manquants=$((manquants + 1))
      fi
    else
      [ "$QUIET" -eq 1 ] || bad "aegis absent — entrer dans le devShell (direnv allow)"
      manquants=$((manquants + 1))
    fi

    if [ "$QUIET" -eq 1 ]; then
      [ "$manquants" -gt 0 ] && printf '%s! %d garde-fou(s) non câblé(s) — task guards:install%s\n' "$Y" "$manquants" "$Z"
      exit 0
    fi
    exit $(( manquants > 0 ))
    ;;

  install)
    head_ "Câblage des garde-fous"
    cat <<'AVERT'

  shhh  → hook écrit dans ./.claude/settings.json, DANS ce projet.
          Portée `project` et non `global` : le socle décrit ce que CE dépôt
          exige, et un clone sur une autre machine doit hériter de la même
          protection sans dépendre de ce que son propriétaire a configuré
          chez lui. Retrait : shhh uninstall claude-code --scope project

  aegis → écrit à DEUX endroits, tous deux hors du projet :
            · ~/.config/aegis/shadow/<projet>  — le filet lui-même. Hors de
              l'arbre à dessein : un filet rangé dans ce qu'il protège
              disparaît avec lui. Empreinte nulle dans le working tree.
            · ./.claude/settings.json          — le hook PreToolUse, posé en
              portée PROJET grâce à `aegis init --local`.
          ⚠️ Le défaut d'aegis est GLOBAL (~/.claude/settings.json, son ADR
          0005) : il s'appliquerait alors à tous vos dépôts. Ce socle décrit
          ce que CE dépôt exige — il utilise donc `--local`, symétrique de
          `shhh --scope project`. Un dépôt cloné hérite de sa protection sans
          rien imposer à la machine qui l'accueille.
          Sans hook du tout : aegis init --no-hook (le shadow reste, la
          capture avant chaque action d'agent, non).

AVERT
    if [ "${1:-}" != "--yes" ]; then
      printf 'Continuer ? [o/N] '
      read -r rep
      case "$rep" in o|O|oui|y|Y) ;; *) echo "abandon."; exit 1 ;; esac
    fi

    if command -v shhh >/dev/null; then
      shhh install claude-code --scope project --cwd "$PWD" && ok "shhh câblé (projet)"
    else bad "shhh introuvable — direnv allow"; fi

    if command -v aegis >/dev/null; then
      # `--local` : le hook va dans ./.claude/settings.json, comme celui de shhh.
      # Le défaut d'aegis est GLOBAL (son ADR 0005) — ce socle décrit ce que CE
      # dépôt exige, pas ce que la machine impose à tous les autres.
      aegis init --local && ok "aegis : projet enregistré (hook local)"
    else bad "aegis introuvable — direnv allow"; fi

    # ⚠️ LE CHIFFRE D'ABORD, L'INSTALLATION ENSUITE.
    #
    # Un garde-fou qu'on installe « au cas où » se désinstalle au premier
    # frottement. `shhh audit` lit les transcriptions de Claude Code déjà
    # présentes sur ce disque et compte les secrets qui ont DÉJÀ atteint un
    # modèle. Ce nombre-là n'est pas une hypothèse, et c'est lui qui fait
    # garder le hook.
    head_ "Ce qui a déjà fui"
    if command -v shhh >/dev/null; then
      shhh audit --no-select --no-serve 2>&1 | tail -25
    fi
    ;;

  scan)
    # Détection de secrets dans l'arbre de travail. On délègue : shhh porte
    # ~222 règles de fournisseurs (gitleaks) plus une couche native qui
    # repère une valeur de `.env` recopiée dans le code. Réécrire ça à la
    # main produirait une liste de motifs toujours en retard d'un fournisseur.
    command -v shhh >/dev/null || { bad "shhh absent"; exit 1; }
    exec shhh scan "${1:-.}"
    ;;

  audit)
    command -v shhh >/dev/null || { bad "shhh absent"; exit 1; }
    exec shhh audit
    ;;

  *)
    echo "usage : $0 <status|install|scan|audit>" >&2
    exit 2
    ;;
esac
