#!/usr/bin/env bash
# Recrée les secrets du tuto ESO d'origine (perdus à chaque redémarrage du Vault dev).
# Usage : bash labs/bootstrap-eso-demo.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"

vault secrets list | grep -q '^kv/org/' || vault secrets enable -path=kv/org kv-v2
vault kv put kv/org/dev  api-key=dev-key-v1  >/dev/null
vault kv put kv/org/dev  api-key=dev-key-v2  >/dev/null   # l'ExternalSecret dev pointe sur la version 2
vault kv put kv/org/prod api-key=prod-key-v1 >/dev/null

# Force ESO à resynchroniser tout de suite
kubectl -n demo annotate externalsecret dev-api-key prod-api-key force-sync="$(date +%s)" --overwrite >/dev/null
echo "OK : kv/org/dev (v2) et kv/org/prod recréés."
