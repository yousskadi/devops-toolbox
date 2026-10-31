# Vault : troubleshooting

Format : **symptôme** → cause → solution. J'ajoute une entrée à chaque nouvelle erreur.

## `curl -s ... $VAULT_ADDR/...` ne renvoie rien

- **Cause :** `$VAULT_ADDR` est vide (nouveau terminal sans `source labs/env.sh`). L'URL devient `/v1/...` sans hôte, et `-s` masque l'erreur.
- **Solution :** `echo "[$VAULT_ADDR]"`, puis `source labs/env.sh`. Pour déboguer : retirer `-s` ou ajouter `-v`.
- **Vu le :** 2026-10-31 (lab 01)

## Les secrets ont disparu, ESO en `SecretSyncedError`

- **Cause :** le mode `-dev` stocke tout **en mémoire**. Un redémarrage du conteneur (ou du PC) efface tout.
- **Solution :** `bash labs/bootstrap-eso-demo.sh` pour le tuto ESO. Pour un stockage persistant, voir le mode serveur (lab 09).
- **Vu le :** 2026-10-30

## `flag provided but not defined: -field` sur `kv metadata get`

- **Cause :** `vault kv metadata get` ne supporte pas `-field`.
- **Solution :** `vault kv metadata get -format=json lab/app | jq .data.current_version`
- **Vu le :** 2026-10-31 (lab 01)

## `check-and-set parameter did not match the current version` (code 400)

- **Cause :** `-cas=N` alors que la version courante n'est plus N (quelqu'un a écrit entre-temps), ou `-cas=0` sur un secret qui existe déjà.
- **Solution :** relire le secret et sa version, puis réécrire avec le bon N. C'est le comportement voulu (verrouillage optimiste).
- **Vu le :** 2026-10-31 (lab 01)

## Un `kv put` a effacé des clés

- **Cause :** `put` **remplace** tout le secret.
- **Solution :** utiliser `vault kv patch` pour modifier une clé. Pour récupérer la version précédente : `vault kv get -version=N`, puis la réécrire.
- **Vu le :** 2026-10-31 (lab 01)

## `permission denied` (403) alors que la policy semble bonne

- **Cause fréquente :** en KV v2, la policy doit viser `lab/data/...` (lecture/écriture) et `lab/metadata/...` (list), **pas** `lab/...`.
- **Solution :** `vault token capabilities <token> lab/data/app/config` pour voir les droits effectifs.

## `vault kv get -wrap-ttl=... -field=wrapping_token` → `No data found`

- **Cause :** `-field` cherche dans les données, mais une réponse wrappée n'en contient pas.
- **Solution :** `vault kv get -wrap-ttl=60s -format=json lab/app | jq -r .wrap_info.token`

## Un token ne peut pas créer de token enfant (403 sur `auth/token/create`)

- **Cause :** la policy `default` ne donne pas ce droit.
- **Solution :** ajouter une policy avec `path "auth/token/create" { capabilities = ["create", "update"] }`.

## Vault serveur (`vault-prod`) : `bind: address already in use` au démarrage

- **Cause :** l'entrypoint de l'image ajoute déjà `-config=/vault/config`. Mettre `server -config=/vault/config/vault.hcl` charge le fichier deux fois, donc deux listeners sur le même port.
- **Solution :** `command: server` dans le docker-compose.

## `vault-prod` : `connection refused` juste après `docker compose up`

- **Cause :** le premier démarrage avec Raft prend environ 30 s.
- **Solution :** `wait-vault-prod` (dans `env.sh`).

## `vault operator unseal` : `file descriptor 0 is not a terminal`

- **Cause :** sans argument, unseal demande la clé de façon interactive, ce qui échoue sans TTY. Arrive aussi si la variable contenant la clé est vide.
- **Solution :** passer la clé en argument : `vault-prod operator unseal <clé>`.

## Écriture transit en lot : `source data must be an array or slice, got string`

- **Cause :** `batch_input='[...]'` en `clé=valeur` est envoyé comme une chaîne.
- **Solution :** passer le JSON par stdin : `echo '{"batch_input":[...]}' | vault write transit/encrypt/<key> -`

## `openssl verify` : `bad end line`

- **Cause :** un PEM obtenu avec `vault write -field=certificate` n'a pas de saut de ligne final, ce qui casse la concaténation `cat a.crt b.crt`.
- **Solution :** `vault read -field=certificate pki/cert/ca > ca.crt` et `openssl verify -CAfile root.crt -untrusted int.crt cert.crt`.

## Auth Kubernetes : Vault n'atteint pas l'API du cluster kind

- **Cause :** le conteneur Vault n'est pas sur le réseau Docker `kind`.
- **Solution :** `docker network connect kind vault`, puis `kubernetes_host=https://vault-control-plane:6443`.
