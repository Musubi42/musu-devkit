#!/usr/bin/env bash
# Rend le rôle de la machine courante : `dev` ou `ci`.
#
# ⚠️ POURQUOI PAS LE HOSTNAME
#
# Le parc compte plusieurs machines NixOS qui portent le nom par défaut
# `nixos`. Un test sur le hostname ferait donc croire à une machine de dev
# qu'elle est une autre — et les vérifications de secrets rendent des verdicts
# OPPOSÉS selon le rôle (une clé restreinte doit échouer là où elle n'est pas
# autorisée). Se tromper de rôle, c'est se tromper de verdict.
#
# musuPlate n'a pas de production : les seuls rôles utiles sont `dev` (un poste)
# et `ci` (pas de clé age, pas de trousseau, tout doit échouer proprement).
# On garde la forme du script de référence pour que le motif soit transposable.
#
# MUSU_ROLE reste prioritaire : une variable explicite doit toujours pouvoir
# trancher, ne serait-ce que pour tester le comportement de l'autre rôle.
set -u

case "${MUSU_ROLE:-}" in
  dev|ci) printf '%s\n' "$MUSU_ROLE"; exit 0 ;;
  '') ;;
  *) echo "MUSU_ROLE invalide : ${MUSU_ROLE} (attendu dev ou ci)" >&2; exit 2 ;;
esac

# Signal stable et intentionnel : un runner CI pose CI=true. Aucun poste de
# développement ne le fait par accident.
if [ -n "${CI:-}" ]; then
  printf 'ci\n'
else
  printf 'dev\n'
fi
