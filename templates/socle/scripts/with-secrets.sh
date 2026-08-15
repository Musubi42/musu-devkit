#!/usr/bin/env bash
# Exécute une commande avec les secrets d'un environnement injectés — sans
# jamais écrire de fichier en clair sur le disque.
#
#   ./scripts/with-secrets.sh dev node apps/api/server.js
#   ./scripts/with-secrets.sh dev ./scripts/verify-secrets.sh
#
# ⚠️ POURQUOI PAR COMMANDE ET PAS PAR SHELL
#
# C'est LA décision que ce dépôt éprouve. Un secret posé dans le shell est
# hérité par tout ce qui s'y lance ensuite : éditeur, serveur de langage,
# `npm install`, agent. Personne ne l'a décidé, et personne ne peut le retirer
# — direnv recopie ce qu'il pose dans DIRENV_DIFF, qu'un `unset` ne nettoie pas
# (voir .envrc). Injecter par commande borne la fuite à la durée du processus
# qui en a besoin.
#
# `exec` remplace ce shell par la commande : pas de processus intermédiaire
# porteur des variables, et Ctrl-C atteint directement l'application.
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_NAME="${1:-}"
shift || true

case "$ENV_NAME" in
  dev) ;;
  *) echo "usage : $0 dev <commande…>" >&2; exit 2 ;;
esac

[ $# -gt 0 ] || { echo "usage : $0 $ENV_NAME <commande…>" >&2; exit 2; }

FILE="secrets/$ENV_NAME.env"

# Absence tolérée : un poste fraîchement cloné doit pouvoir lancer la stack
# locale (postgres, redis, mailpit) avant d'avoir la moindre clé externe. Ce
# qui échouera alors, c'est l'appel à Resend — et il échouera en disant
# pourquoi, ce qui est le comportement recherché.
if [ ! -f "$FILE" ]; then
  echo "→ $FILE absent — exécution sans secrets partagés" >&2
  exec "$@"
fi

command -v sops >/dev/null || { echo "✗ sops introuvable" >&2; exit 1; }

# `set -a` exporte tout ce qui est assigné ; sourcer depuis un here-string
# évite le fichier temporaire. Les valeurs ne touchent jamais le disque.
PLAIN="$(sops --decrypt "$FILE")" || {
  echo "✗ déchiffrement impossible — la clé age de cette machine est-elle dans .sops.yaml ?" >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source /dev/stdin <<<"$PLAIN"
set +a
unset PLAIN

exec "$@"
