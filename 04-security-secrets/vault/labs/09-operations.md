# Lab 09 : opérations (le Vault « de prod »)

**Objectif :** comprendre ce que le mode `-dev` te cache : initialisation, scellement (seal/unseal), persistance, sauvegarde et audit.

| | Mode dev (`docker-compose.yml`) | Mode serveur (`labs/vault-prod/`) |
|---|---|---|
| Stockage | Mémoire (perdu au redémarrage) | Raft sur disque (volume Docker) |
| Init | Automatique | `vault operator init` à faire soi-même |
| Unseal | Automatique | Manuel, après chaque démarrage |
| Token root | `root` | Généré à l'init |
| TLS | Non | Oui en prod (désactivé ici pour le lab) |

## 1. Démarrer un Vault en mode serveur (port 8210)

```bash
source labs/env.sh
cat labs/vault-prod/config/vault.hcl          # lis la config : storage raft, listener, ui
docker compose -f labs/vault-prod/docker-compose.yml up -d
wait-vault-prod                                # le 1er démarrage prend ~30 s
vault-prod status                              # Initialized false, Sealed true
```

## 2. Init : Shamir's Secret Sharing

```bash
vault-prod operator init -key-shares=3 -key-threshold=2 | tee labs/vault-prod/init.txt
```

La clé maître est découpée en 3 parts, et il en faut 2 pour déverrouiller. En vrai, chaque part est confiée à une personne différente, et ce fichier ne doit **jamais** traîner sur un disque.

```bash
vault-prod status          # Initialized true, Sealed true
```

## 3. Unseal

```bash
vault-prod operator unseal <clé 1>
vault-prod status          # Unseal Progress 1/2
vault-prod operator unseal <clé 2>
vault-prod status          # Sealed false 🎉
export VAULT_PROD_TOKEN=<Initial Root Token>
vault-prod secrets list    # pas de secret/ ici : rien n'est monté par défaut
```

Ouvre aussi l'UI : http://localhost:8210

## 4. Persistance et seal d'urgence

```bash
vault-prod secrets enable -path=lab kv-v2
vault-prod kv put lab/persist hello=world

docker restart vault-prod; wait-vault-prod
vault-prod status                 # Sealed true : à chaque redémarrage, il faut unseal
vault-prod operator unseal <clé 1>; vault-prod operator unseal <clé 3>   # n'importe quelles 2 clés
vault-prod kv get lab/persist     # ✅ la donnée a survécu

# Incident de sécurité : on scelle tout, plus personne n'accède à rien
vault-prod operator seal
vault-prod kv get lab/persist     # ❌ Vault is sealed
```

> 💡 En prod, on utilise l'**auto-unseal** (AWS KMS, GCP KMS, Azure Key Vault, HSM ou Transit d'un autre Vault) pour éviter l'unseal manuel. Défi : configure un `seal "transit"` qui utilise ton Vault dev comme KMS.

## 5. Sauvegarde et restauration (snapshot Raft)

```bash
vault-prod operator raft snapshot save /vault/file/backup.snap
docker cp vault-prod:/vault/file/backup.snap labs/vault-prod/backup.snap

vault-prod kv put lab/persist hello=OOPS     # "erreur" à annuler
docker cp labs/vault-prod/backup.snap vault-prod:/tmp/backup.snap
vault-prod operator raft snapshot restore -force /tmp/backup.snap
vault-prod kv get lab/persist                # hello=world
```

## 6. Audit : qui a lu quoi ?

À faire sur le Vault **dev** :

```bash
vault audit enable file file_path=/tmp/vault-audit.log
VAULT_TOKEN=$(vault token create -policy=default -display-name=suspect -field=token) vault kv get secret/foo 2>/dev/null
vault kv put secret/foo bar=baz

docker exec vault tail -n 8 /tmp/vault-audit.log | jq -c '{type, path: .request.path, op: .request.operation, who: .auth.display_name, err: .error}'
```

Les valeurs sensibles (tokens, secrets) sont **hashées** (HMAC) dans le log. Pour retrouver si une valeur donnée apparaît dans le log :

```bash
vault write sys/audit-hash/file input=baz
docker exec vault grep -c "$(vault write -field=hash sys/audit-hash/file input=baz)" /tmp/vault-audit.log
```

⚠️ Si **tous** les audit devices échouent (disque plein…), Vault refuse de répondre aux requêtes. C'est un choix de sécurité.

## 7. Observabilité et santé

```bash
curl -s $VAULT_ADDR/v1/sys/health | jq                  # utilisé par les load balancers (200 / 429 / 503)
curl -s -H "X-Vault-Token: root" "$VAULT_ADDR/v1/sys/metrics?format=prometheus" | grep -v '^#' | head
vault-prod operator raft list-peers                     # topologie du cluster Raft (1 nœud ici)
```

## 8. Root token : révoquer et régénérer

```bash
vault-prod token revoke $VAULT_PROD_TOKEN          # bonne pratique après l'installation
vault-prod operator generate-root -init            # nécessite le quorum des clés unseal → nonce + OTP
# puis chaque détenteur : vault-prod operator generate-root -nonce=<nonce> <clé>
# enfin : vault-prod operator generate-root -decode=<encoded> -otp=<otp>
```

## Nettoyage

```bash
docker compose -f labs/vault-prod/docker-compose.yml down -v
rm -f labs/vault-prod/init.txt labs/vault-prod/backup.snap
```

## Exercices

1. Fais tourner les clés unseal (`operator rekey`) pour passer de 3/2 à 5/3.
2. Ajoute un second audit device (`socket` ou `syslog`) et vérifie que les deux reçoivent les événements.
3. Monte un cluster Raft à 3 nœuds avec docker compose (`retry_join`), tue le leader et observe l'élection.
