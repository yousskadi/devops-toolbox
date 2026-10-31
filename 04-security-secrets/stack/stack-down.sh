#!/usr/bin/env bash
# Arrête la stack. Par défaut : simple arrêt (tout redémarre avec stack-up.sh).
#   bash stack-down.sh            → docker stop (cluster conservé ; données Vault dev perdues)
#   bash stack-down.sh --delete   → supprime le cluster kind ET le conteneur Vault (demande confirmation)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-vault}"
NODE="${CLUSTER_NAME}-control-plane"

if [ "${1:-}" = "--delete" ]; then
  echo "⚠️  Suppression définitive du cluster kind '$CLUSTER_NAME' et du conteneur vault."
  read -r -p "Tape 'oui' pour confirmer : " answer
  [ "$answer" = "oui" ] || { echo "Annulé."; exit 1; }
  kind delete cluster --name "$CLUSTER_NAME"
  docker compose -f "$HERE/../vault/docker-compose.yml" down
  echo "✔ Supprimé. Pour tout recréer : bash $HERE/stack-up.sh"
else
  docker stop vault "$NODE" 2>/dev/null || true
  echo "✔ Arrêté (cluster conservé). Pour relancer : bash $HERE/stack-up.sh"
  echo "  Rappel : Vault est en mode dev, ses données sont perdues (stack-up.sh recrée la démo ESO)."
fi
