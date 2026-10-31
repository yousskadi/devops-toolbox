# Lab 04 : secrets dynamiques (PostgreSQL)

**Objectif :** la vraie force de Vault. Au lieu de stocker un mot de passe DB partagé et éternel, Vault **crée un utilisateur à la demande**, avec une durée de vie, et le supprime automatiquement.

## 🎯 Comprendre avant de pratiquer

**En une phrase :** au lieu d'un mot de passe DB partagé et éternel, Vault **crée un utilisateur DB unique à la demande**, avec une date d'expiration, et le **supprime automatiquement**.

**Analogie, l'hôtel :** fini le passe-partout distribué à tout le monde. Chaque client reçoit une **carte-clé programmée pour son séjour**. Au check-out, elle ne marche plus. Si un client perd sa carte, on désactive **la sienne**, sans changer toutes les serrures.

**Exemple concret :** l'appli `shop` tourne sur 10 pods.
```
Sans Vault : 10 pods → 1 user "shop" / mot de passe "Shop2019!" (jamais changé depuis 2019)
Avec Vault : pod-1 → v-k8s-shop-a8f2  (expire dans 1 h, renouvelé tant que le pod vit)
             pod-2 → v-k8s-shop-91cd
             ...
             pod supprimé → son user disparaît à expiration du lease
```

**À quoi ça sert en prod :**
- **Plus aucun mot de passe DB** dans les configs, le code ou les variables d'environnement.
- **Traçabilité** : dans les logs Postgres, tu vois `v-k8s-shop-a8f2` faire une requête suspecte, et l'audit Vault te dit quel pod ou quelle appli l'a obtenu.
- **Incident** : `vault lease revoke -prefix database/creds/shop` coupe **tous** les accès de l'appli en une commande.
- **Conformité** (PCI-DSS, SOC 2, ISO 27001) : la rotation des mots de passe est automatique et prouvable.
- **Rotation du mot de passe root** : plus personne ne connaît le mot de passe admin de la base, seul Vault le connaît.
- Même principe pour **MySQL, MongoDB, Redis, RabbitMQ**, et pour les **identifiants cloud** (clés AWS IAM temporaires, comptes de service GCP, Azure).

**Pièges en prod :**
- L'appli doit savoir **se reconnecter** quand ses identifiants changent. Un pool de connexions ouvert avec un user expiré finit par échouer.
- Un TTL trop court multiplie les créations d'utilisateurs, et donc la charge sur la DB. Il y a un équilibre à trouver (souvent 1 h à 24 h).
- Crée un **compte dédié à Vault** dans la DB, avec juste le droit de créer et supprimer des rôles, pas le superuser.

## 0. Lancer un PostgreSQL à côté de Vault

On le met sur le même réseau Docker que Vault (`vault_default`) pour que Vault le joigne par son nom :

```bash
source labs/env.sh
docker run -d --name vault-pg --network vault_default \
  -e POSTGRES_PASSWORD=rootpass -p 5432:5432 postgres:16-alpine
sleep 8 && docker exec vault-pg pg_isready
```

## 1. Configurer le database secrets engine

```bash
vault secrets enable database

# Connexion de Vault à la DB (Vault utilise ce compte pour créer/supprimer des users)
vault write database/config/appdb \
  plugin_name=postgresql-database-plugin \
  allowed_roles="readonly,readwrite" \
  connection_url='postgresql://{{username}}:{{password}}@vault-pg:5432/postgres?sslmode=disable' \
  username=postgres password=rootpass

# Un "role" Vault = un modèle d'utilisateur DB
vault write database/roles/readonly \
  db_name=appdb default_ttl=2m max_ttl=10m \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT pg_read_all_data TO \"{{name}}\";"
```

## 2. Obtenir des identifiants éphémères

```bash
vault read database/creds/readonly
```

Note le `lease_id`, le `username` et le `password`. Vérifie côté Postgres :

```bash
docker exec vault-pg psql -U postgres -c "select usename, valuntil from pg_user where usename like 'v-%';"
```

Teste la connexion avec ces identifiants :

```bash
CREDS=$(vault read -format=json database/creds/readonly)
U=$(echo $CREDS | jq -r .data.username); P=$(echo $CREDS | jq -r .data.password)
docker run --rm --network vault_default -e PGPASSWORD="$P" postgres:16-alpine \
  psql -h vault-pg -U "$U" -d postgres -c "select current_user;"
```

## 3. Leases : renouveler, révoquer, expirer

```bash
LEASE=$(echo $CREDS | jq -r .lease_id)
vault lease lookup $LEASE
vault lease renew -increment=5m $LEASE       # plafonné par max_ttl=10m

vault lease revoke $LEASE                    # l'user disparaît immédiatement de Postgres
docker exec vault-pg psql -U postgres -tc "select count(*) from pg_user where usename='$U';"

# Attends 2 minutes sans renouveler : l'user expire tout seul
vault read database/creds/readonly && sleep 130
docker exec vault-pg psql -U postgres -c "select usename from pg_user where usename like 'v-%';"
```

**Scénario incident :** une fuite est suspectée, on révoque *tous* les identifiants émis par ce rôle d'un coup :

```bash
for i in 1 2 3; do vault read -field=username database/creds/readonly; echo; done
vault lease revoke -prefix database/creds/readonly
```

> 🧠 C'est le concept clé : **chaque client a ses propres identifiants**, traçables (l'audit log relie le lease au token et à l'auth method) et révocables individuellement.

## 4. Rotation du mot de passe root

Vault peut changer le mot de passe du compte `postgres` qu'il utilise, et plus personne ne le connaît :

```bash
vault write -f database/rotate-root/appdb

# L'ancien mot de passe ne marche plus (via le réseau) :
docker run --rm --network vault_default -e PGPASSWORD=rootpass postgres:16-alpine \
  psql -h vault-pg -U postgres -c 'select 1'      # ❌ password authentication failed
vault read database/creds/readonly                 # ✅ Vault, lui, fonctionne toujours
```

⚠️ En vrai, on crée un compte dédié à Vault plutôt que d'utiliser le superuser `postgres`.

## 5. Bonus : static roles

Pour une appli legacy qui ne supporte pas de changer d'utilisateur, Vault peut gérer un **utilisateur existant** et faire tourner son mot de passe périodiquement :

```bash
docker exec vault-pg psql -U postgres -c "CREATE ROLE legacy_app LOGIN PASSWORD 'initial';"
vault write database/config/appdb allowed_roles="readonly,readwrite,legacy"
vault write database/static-roles/legacy db_name=appdb username=legacy_app rotation_period=1h
vault read database/static-creds/legacy        # mot de passe actuel et prochaine rotation
vault write -f database/rotate-role/legacy     # rotation forcée
```

## Exercices

1. Crée le rôle `readwrite` (ajoute `GRANT ALL ON ALL TABLES IN SCHEMA public`) et une policy qui ne donne accès qu'à `database/creds/readonly`. Vérifie qu'un token avec cette policy ne peut pas lire `readwrite`.
2. Génère des identifiants via AppRole (lab 03), puis révoque le token AppRole : que deviennent les leases DB ? (indice : les leases sont rattachés au token qui les a créés.)
3. Nettoyage : `docker rm -f vault-pg`.
