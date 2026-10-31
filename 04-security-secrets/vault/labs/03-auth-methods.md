# Lab 03 : auth methods (humains et machines)

**Objectif :** ne plus jamais distribuer de tokens à la main. On s'authentifie avec une méthode adaptée à chaque client, et Vault délivre un token avec les bonnes policies.

Prérequis : lab 02 (policies `app-ro` et `app-rw`).

```bash
source labs/env.sh
vault auth list
```

## 1. userpass : pour les humains (en entreprise, plutôt OIDC ou LDAP)

```bash
vault auth enable userpass
vault write auth/userpass/users/alice password=alicepass token_policies=app-ro token_ttl=1h
vault write auth/userpass/users/bob   password=bobpass   token_policies=app-rw

# Login : on récupère un token
ALICE=$(vault login -method=userpass -token-only username=alice password=alicepass)
VAULT_TOKEN=$ALICE vault token lookup | grep -E 'policies|ttl|display_name'
VAULT_TOKEN=$ALICE vault kv get lab/app/config      # ✅
VAULT_TOKEN=$ALICE vault kv put lab/app/config x=1  # ❌

# La même chose en API
curl -s -X POST -d '{"password":"bobpass"}' $VAULT_ADDR/v1/auth/userpass/login/bob | jq .auth
```

Connecte-toi aussi dans l'UI (http://localhost:8200, méthode *Username*) en tant qu'alice.

## 2. AppRole : pour les machines (CI/CD, VM, scripts)

AppRole repose sur deux éléments :
- **role_id** : l'identifiant, peu sensible (comme un login). On peut le mettre dans la config de l'appli.
- **secret_id** : le mot de passe, sensible et à durée limitée. Il est livré au dernier moment par un système de confiance (la CI, Terraform…).

```bash
vault auth enable approle

vault write auth/approle/role/ci-deploy \
    token_policies=app-ro \
    token_ttl=10m token_max_ttl=30m \
    secret_id_ttl=1h secret_id_num_uses=5

ROLE_ID=$(vault read -field=role_id auth/approle/role/ci-deploy/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/ci-deploy/secret-id)
echo "role_id=$ROLE_ID  secret_id=$SECRET_ID"

# Ce que fait le job de CI :
CI_TOKEN=$(vault write -field=token auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID)
VAULT_TOKEN=$CI_TOKEN vault kv get -field=password lab/app/config
```

Pour aller plus loin en sécurité :

```bash
# secret_id livré wrappé (le pipeline ne voit jamais le secret_id en clair)
WRAPPED=$(vault write -f -wrap-ttl=60s -field=wrapping_token auth/approle/role/ci-deploy/secret-id)
vault unwrap -field=secret_id $WRAPPED

# Fuite suspectée : lister les secret_id émis (par accessor) et en détruire un
vault list auth/approle/role/ci-deploy/secret-id
vault write auth/approle/role/ci-deploy/secret-id-accessor/destroy secret_id_accessor=<accessor>

# Restreindre les IP autorisées à se loguer
vault write auth/approle/role/ci-deploy secret_id_bound_cidrs="172.16.0.0/12" token_bound_cidrs="172.16.0.0/12"
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/ci-deploy/secret-id)
vault write auth/approle/login role_id=$ROLE_ID secret_id=$SECRET_ID   # ❌ tu viens de 127.0.0.1, hors du CIDR
vault write auth/approle/role/ci-deploy secret_id_bound_cidrs="" token_bound_cidrs=""   # on remet sans restriction
```

> 🧠 C'est le « secret zéro » : pour obtenir un secret, il faut déjà un secret. AppRole + wrapping le réduit au minimum, et l'auth Kubernetes (lab 07) le supprime, car c'est la plateforme qui prouve l'identité du pod.

## 3. Identity : entités et groupes

Une même personne peut se connecter via plusieurs méthodes (userpass, OIDC…). Vault la regroupe dans une **entité** à laquelle on attache des policies, souvent via des **groupes**.

```bash
# Créer un groupe "devs" avec la policy app-rw
vault write identity/group name=devs policies=app-rw

# Retrouver l'entité d'alice (créée automatiquement à son premier login)
ENTITY_ID=$(VAULT_TOKEN=$ALICE vault token lookup -format=json | jq -r .data.entity_id)
vault write identity/group/name/devs member_entity_ids=$ENTITY_ID

# Nouveau login : alice hérite maintenant d'app-rw via son groupe
ALICE=$(vault login -method=userpass -token-only username=alice password=alicepass)
VAULT_TOKEN=$ALICE vault kv put lab/app/from-alice ok=true    # ✅
VAULT_TOKEN=$ALICE vault token lookup | grep -i polic          # identity_policies [app-rw]
```

## 4. Bonus : templated policies (une policy pour tous les utilisateurs)

```bash
ACC=$(vault auth list -format=json | jq -r '."userpass/".accessor')
cat > labs/policies/user-home.hcl <<EOF
# Chaque utilisateur a son espace privé lab/data/users/<son-username>/*
path "lab/data/users/{{identity.entity.aliases.$ACC.name}}/*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOF
vault policy write user-home - < labs/policies/user-home.hcl
vault write auth/userpass/users/alice token_policies=app-ro,user-home

ALICE=$(vault login -method=userpass -token-only username=alice password=alicepass)
VAULT_TOKEN=$ALICE vault kv put lab/users/alice/notes x=1     # ✅
VAULT_TOKEN=$ALICE vault kv put lab/users/bob/notes x=1       # ❌
```

## Exercices

1. Crée un AppRole `batch` dont le secret_id n'est utilisable **qu'une fois** et dont le token expire en 5 min. Vérifie les deux limites.
2. Désactive un utilisateur userpass sans le supprimer (indice : rien de direct… quelles options as-tu ?).
3. Trouve dans l'UI la page *Access → Entities* et observe l'entité d'alice et ses alias.
