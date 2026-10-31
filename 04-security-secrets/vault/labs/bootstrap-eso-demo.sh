#!/usr/bin/env bash
# Recrée les secrets du tuto ESO d'origine (perdus à chaque redémarrage du Vault dev).
# Idempotent : ne réécrit rien si les secrets existent déjà.
# Usage : bash labs/bootstrap-eso-demo.sh        (KUBECTL_CONTEXT=<ctx> pour viser un autre cluster)
set -euo pipefail
source "$(dirname "$0")/env.sh"
K="kubectl ${KUBECTL_CONTEXT:+--context $KUBECTL_CONTEXT}"

mounts="$(vault secrets list)"   # pas de pipe vers grep -q : avec pipefail, il peut casser le tuyau
grep -q '^kv/org/' <<<"$mounts" || vault secrets enable -path=kv/org kv-v2 >/dev/null
if vault kv get kv/org/dev >/dev/null 2>&1; then
  echo "kv/org/dev existe déjà : rien à réécrire."
else
  vault kv put kv/org/dev  api-key=dev-key-v1  >/dev/null
  vault kv put kv/org/dev  api-key=dev-key-v2  >/dev/null   # l'ExternalSecret dev pointe sur la version 2
  vault kv put kv/org/prod api-key=prod-key-v1 >/dev/null
  echo "OK : kv/org/dev (v2) et kv/org/prod recréés."
fi

# Force ESO à resynchroniser tout de suite (si les ExternalSecrets existent)
for es in dev-api-key prod-api-key; do
  $K -n demo annotate externalsecret "$es" force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
done
