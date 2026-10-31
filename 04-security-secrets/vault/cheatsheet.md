# Vault : cheatsheet

> Avec `source labs/env.sh`, `vault` = CLI dans le conteneur (token `root` par défaut).
> Agir avec un autre token : `VAULT_TOKEN=<token> vault ...`

## Les indispensables

```bash
vault status                                  # Sealed ? Storage ? Version ?
vault secrets list                            # engines montés
vault auth list                               # auth methods activées
vault policy list
vault token lookup                            # qui suis-je, quelles policies, quel TTL
vault token capabilities <token> <chemin>     # debug des droits SANS faire l'action
vault <cmd> -output-curl-string ...           # l'équivalent curl de n'importe quelle commande
```

## KV v2

| Commande | Effet |
|---|---|
| `vault secrets enable -path=lab kv-v2` | Monter un KV v2 sur `lab/` |
| `vault kv put lab/app k=v` | Écrire. ⚠️ **remplace** tout le secret, nouvelle version |
| `vault kv patch lab/app k=v` | Modifier une clé, garder les autres (nouvelle version) |
| `vault kv get [-version=N] [-field=k] lab/app` | Lire |
| `vault kv list lab/` | Lister |
| `vault kv delete [-versions=N] lab/app` | Soft delete (réversible) de la dernière version |
| `vault kv undelete -versions=N lab/app` | Annuler le soft delete |
| `vault kv destroy -versions=N lab/app` | Effacer **définitivement** une version |
| `vault kv metadata get lab/app` | Historique des versions |
| `vault kv metadata put -max-versions=3 lab/app` | Limiter l'historique |
| `vault kv metadata delete lab/app` | Tout supprimer (versions et métadonnées) |
| `vault kv put -cas=N lab/app ...` | N'écrit que si la version courante est N (`-cas=0` : seulement si le secret n'existe pas) |
| `vault kv metadata get -format=json lab/app \| jq .data.current_version` | Version courante (`-field` non supporté ici) |

**Chemins réels (API et policies) :** `lab/data/<chemin>` (valeurs), `lab/metadata/<chemin>` (versions, list), `lab/delete/`, `lab/undelete/`, `lab/destroy/`.

## API HTTP

```bash
H="X-Vault-Token: root"
curl -s -H "$H" $VAULT_ADDR/v1/lab/data/app/config | jq .data.data          # lire
curl -s -H "$H" -X POST -d '{"data":{"k":"v"}}' $VAULT_ADDR/v1/lab/data/app/config   # écrire
curl -s -H "$H" -X LIST $VAULT_ADDR/v1/lab/metadata/app | jq .data.keys      # lister
curl -s $VAULT_ADDR/v1/sys/health | jq                                         # santé (sans token)
```

Codes : `200` OK · `204` OK sans contenu · `400` requête invalide (CAS…) · `403` refus **générique** (token invalide **ou** pas de droit, jamais de 404 qui révélerait l'existence d'un secret) · `503` Vault scellé.

## Policies et tokens

```bash
vault policy write app-ro - < policies/app-ro.hcl    # "-" = stdin (le CLI est dans le conteneur)
vault policy read app-ro
vault token create -policy=app-ro -ttl=30m [-explicit-max-ttl=1h] [-use-limit=N] [-orphan] [-period=24h]
vault token renew <token> | vault token revoke <token> | vault token lookup -accessor <acc>
vault kv get -wrap-ttl=60s -format=json lab/app | jq -r .wrap_info.token   # response wrapping
vault unwrap <wrapping_token>                        # usage unique
```

```hcl
path "lab/data/app/*"     { capabilities = ["read"] }          # * = préfixe
path "lab/metadata/app/*" { capabilities = ["list"] }
path "lab/data/+/config"  { capabilities = ["read"] }          # + = un segment
path "lab/data/app/root"  { capabilities = ["deny"] }          # deny l'emporte toujours
```

## Auth methods

```bash
vault auth enable userpass
vault write auth/userpass/users/alice password=x token_policies=app-ro
vault login -method=userpass -token-only username=alice password=x

vault auth enable approle
vault write auth/approle/role/ci token_policies=app-ro token_ttl=10m secret_id_ttl=1h
vault read  -field=role_id   auth/approle/role/ci/role-id
vault write -f -field=secret_id auth/approle/role/ci/secret-id
vault write -field=token auth/approle/login role_id=... secret_id=...
```

## Secrets dynamiques, transit, PKI

```bash
vault read database/creds/<role>                     # identifiants DB éphémères
vault lease renew|revoke <lease_id> ; vault lease revoke -prefix database/creds/<role>
vault write -f database/rotate-root/<db>

vault write -field=ciphertext transit/encrypt/<key> plaintext=$(echo -n "x" | base64)
vault write -field=plaintext  transit/decrypt/<key> ciphertext=vault:v1:... | base64 -d
vault write -f transit/keys/<key>/rotate ; vault write transit/rewrap/<key> ciphertext=...

vault write pki_int/issue/<role> common_name=web.lab.local ttl=1h
vault read -field=certificate pki/cert/ca > ca.crt
```

## Opérations

```bash
vault operator init -key-shares=3 -key-threshold=2
vault operator unseal <clé>          # × seuil
vault operator seal                  # urgence : tout est bloqué
vault operator raft snapshot save|restore <fichier>
vault audit enable file file_path=/tmp/vault-audit.log
vault write sys/audit-hash/file input=<valeur>     # retrouver une valeur dans l'audit log
```

Codes de sortie de `vault status` : `0` descellé · `2` scellé · `1` erreur (injoignable).
