# À sourcer dans chaque terminal :  source labs/env.sh
# Le CLI vault est exécuté DANS le conteneur "vault" (pas besoin de l'installer).
# Pour agir avec un autre token :  VAULT_TOKEN=<token> vault ...
#
# Attention : les chemins "@fichier" sont lus DANS le conteneur.
# Utilise plutôt stdin :  vault policy write ma-policy - < ma-policy.hcl
#                ou :     clé="$(cat fichier)"

vault() {
  docker exec -i \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="${VAULT_TOKEN:-root}" \
    vault vault "$@"
}

# Vault en mode serveur (lab 09), port 8210
vault-prod() {
  docker exec -i \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="${VAULT_PROD_TOKEN:-}" \
    vault-prod vault "$@"
}

# Pour l'API HTTP depuis ton terminal
export VAULT_ADDR=http://127.0.0.1:8200

# Attend que vault-prod réponde (scellé ou non). Le 1er démarrage peut prendre ~30 s.
wait-vault-prod() {
  for _ in $(seq 60); do
    vault-prod status >/dev/null 2>&1; [ $? -ne 1 ] && { echo "vault-prod prêt"; return 0; }
    sleep 1
  done
  echo "vault-prod ne répond pas : docker logs vault-prod" >&2; return 1
}
