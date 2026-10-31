# Lab 02 : policies et tokens

**Objectif :** appliquer le moindre privilège. Par défaut, Vault **refuse tout** : les policies ouvrent des droits sur des chemins.

## 🎯 Comprendre avant de pratiquer

**En une phrase :** le **token** est un badge, la **policy** est la liste des portes que ce badge ouvre. Sans policy, le badge n'ouvre rien.

**Analogie, le badge d'entreprise :**
| Vault | Entreprise |
|---|---|
| Token | Le badge |
| Policy | Les portes autorisées sur ce badge |
| `ttl` | Badge visiteur valable jusqu'au soir (on peut le prolonger à l'accueil) |
| `explicit-max-ttl` | Badge prestataire : 1 mois maximum, prolongations comprises |
| `revoke` | Désactiver le badge |
| Accessor | Le **numéro** du badge, que la sécurité peut désactiver sans l'avoir en main |
| Token root | Le passe-partout du directeur, gardé au coffre |
| Response wrapping | Un ticket de consigne à usage unique pour remettre un objet à quelqu'un |

**Exemple concret :**
```hcl
# Policy "shop-prod" : l'appli shop lit SES secrets de prod, rien d'autre
path "shop/data/prod/*"     { capabilities = ["read"] }

# Policy "shop-deployer" : la CI peut aussi écrire, mais pas toucher au secret root
path "shop/data/prod/*"     { capabilities = ["create", "read", "update", "patch"] }
path "shop/data/prod/root"  { capabilities = ["deny"] }

# Policy "dev" : les développeurs ne voient que la dev
path "shop/data/dev/*"      { capabilities = ["create", "read", "update", "patch", "delete"] }
path "shop/metadata/dev/*"  { capabilities = ["list", "read"] }
```

**À quoi ça sert en prod :**
- **Moindre privilège** : chaque appli a sa policy et ne voit que ses secrets. Une appli piratée ne fuit que ses propres secrets, pas ceux de toute l'entreprise.
- **Une modif de policy s'applique tout de suite** à tous les tokens qui la portent. Retirer un droit à 200 applis prend une seule commande.
- **TTL courts** : un token volé expire vite. `explicit-max-ttl` oblige les applis à se ré-authentifier régulièrement.
- **Incident** : on révoque un token, et toute sa descendance tombe en cascade. Avec l'accessor, un admin agit sans connaître le token.
- **Response wrapping** : on livre un secret initial (par exemple un `secret_id` AppRole à une CI) sans qu'il traîne dans les logs, et on **détecte** une interception.
- Les policies sont stockées dans **Git** et appliquées par Terraform, avec revue de code comme pour le reste de l'infra.

**Pièges en prod :**
- Oublier le `/data/` (KV v2) dans les chemins : la policy ne donne alors aucun droit.
- Tester avec le token `root` : tout marche, puis tout casse en prod avec le vrai token. Teste **toujours** avec un token portant la vraie policy (`vault token capabilities`).
- `path "*"` ou des jokers trop larges, qui ouvrent bien plus que prévu.
- Le token root utilisé au quotidien : il se révoque après l'installation (lab 09).

Prérequis : lab 01 (mount `lab/` existant).

```bash
source labs/env.sh
vault kv put lab/app/config user=admin password=s3cr3t
vault kv put lab/app/other  foo=bar
vault kv put lab/billing/stripe key=sk_test_123
```

## 1. Anatomie d'une policy

Crée le fichier `labs/policies/app-ro.hcl` :

```bash
mkdir -p labs/policies
cat > labs/policies/app-ro.hcl <<'EOF'
# Lire les secrets de l'appli (attention au /data/ !)
path "lab/data/app/*" {
  capabilities = ["read"]
}

# Lister les clés et voir les versions (pour l'UI ou kv list)
path "lab/metadata/app/*" {
  capabilities = ["list", "read"]
}
EOF
vault policy write app-ro - < labs/policies/app-ro.hcl
vault policy list
vault policy read app-ro
```

Capabilities disponibles : `create`, `read`, `update`, `patch`, `delete`, `list`, `sudo`, `deny`.
- `*` en fin de chemin = préfixe (glob). `+` = un seul segment (`lab/data/+/config`).
- `deny` l'emporte toujours sur tout le reste.

## 2. Créer un token limité et tester

```bash
APP_TOKEN=$(vault token create -policy=app-ro -ttl=30m -field=token)
echo $APP_TOKEN

VAULT_TOKEN=$APP_TOKEN vault kv get lab/app/config          # ✅
VAULT_TOKEN=$APP_TOKEN vault kv get lab/billing/stripe      # ❌ 403 permission denied
VAULT_TOKEN=$APP_TOKEN vault kv put lab/app/config x=1      # ❌ lecture seule
VAULT_TOKEN=$APP_TOKEN vault kv list lab/app                # ✅ grâce à metadata

# Vérifier les droits SANS faire l'action (indispensable pour déboguer)
vault token capabilities $APP_TOKEN lab/data/app/config
vault token capabilities $APP_TOKEN lab/data/billing/stripe
```

## 3. Policy avancée : deny et paramètres

```bash
cat > labs/policies/app-rw.hcl <<'EOF'
path "lab/data/app/*" {
  capabilities = ["create", "read", "update", "patch"]
}
# Exception : même en rw, interdiction totale sur ce secret
path "lab/data/app/root-creds" {
  capabilities = ["deny"]
}
EOF
vault policy write app-rw - < labs/policies/app-rw.hcl
vault kv put lab/app/root-creds pw=topsecret

RW=$(vault token create -policy=app-rw -field=token)
VAULT_TOKEN=$RW vault kv put lab/app/new k=v            # ✅
VAULT_TOKEN=$RW vault kv get lab/app/root-creds         # ❌ deny
```

## 4. Cycle de vie d'un token

```bash
vault token create -policy=app-ro -ttl=2m -explicit-max-ttl=5m -format=json | jq .auth
T=$(vault token create -policy=app-ro -ttl=2m -explicit-max-ttl=5m -field=token)

VAULT_TOKEN=$T vault token lookup         # TTL restant, policies, accessor
VAULT_TOKEN=$T vault token renew          # renouvelle le TTL (sans dépasser explicit-max-ttl)
vault token revoke $T
VAULT_TOKEN=$T vault token lookup         # ❌ token révoqué
```

**Hiérarchie des tokens :** un token créé par un autre en est l'*enfant*. Révoquer le parent révoque tous ses enfants.

```bash
# Pour créer des tokens, il faut le droit sur auth/token/create (absent de app-ro)
vault policy write token-creator - <<'EOF'
path "auth/token/create" { capabilities = ["create", "update"] }
EOF

PARENT=$(vault token create -policy=app-ro -policy=token-creator -field=token)
CHILD=$(VAULT_TOKEN=$PARENT vault token create -policy=app-ro -field=token)   # un enfant ne peut avoir que des policies du parent
vault token revoke $PARENT
VAULT_TOKEN=$CHILD vault token lookup     # ❌ révoqué en cascade
# Sinon : -orphan ou un token "periodic" (-period=24h) pour les services longue durée
```

**Accessor :** un identifiant qui permet de gérer un token (lookup, revoke) **sans connaître le token lui-même**. Pratique pour un admin.

```bash
ACC=$(vault token create -policy=app-ro -format=json | jq -r .auth.accessor)
vault token lookup -accessor $ACC
vault token revoke -accessor $ACC
```

## 5. Response wrapping : transmettre un secret sans l'exposer

Problème : comment donner un secret à quelqu'un sans qu'il transite en clair (Slack, logs CI) ?

```bash
WRAP=$(vault kv get -wrap-ttl=120s -format=json lab/app/config | jq -r .wrap_info.token)
echo $WRAP                                 # un token à usage unique qui ne contient pas le secret

vault unwrap $WRAP                         # ✅ révèle le secret
vault unwrap $WRAP                         # ❌ déjà consommé : si ça arrive, c'est que quelqu'un l'a intercepté
```

## 6. La policy `default` et le token root

```bash
vault policy read default       # attachée à tous les tokens : lookup-self, renew-self, cubbyhole...
```

Le token **root** contourne toutes les policies. En prod, on le révoque après l'installation et on en régénère un seulement en cas d'urgence (`vault operator generate-root`).

## ✅ Ce qu'il faut retenir

| Notion | À retenir |
|---|---|
| Par défaut | **Tout est refusé.** Une policy est une liste blanche : chemin → capabilities. |
| Capabilities | Ce sont des opérations d'API, **pas** des noms de commandes : `read` (et non « get »), `create`, `update`, `patch`, `delete`, `list`, `sudo`, `deny`. |
| `read` et `list` | Deux droits distincts sur `/metadata/` : `list` donne les **noms** des secrets (`kv list`), `read` donne leur **historique** (`kv metadata get`). |
| Debug | `vault token capabilities <token> <chemin>` montre les droits effectifs sans faire l'action. |
| Modification | Le token ne porte que le **nom** de ses policies, que Vault relit à chaque requête. Une policy modifiée s'applique **immédiatement**. |
| Plusieurs policies | Elles sont fusionnées, et la règle la plus **spécifique** gagne (un chemin exact bat un joker). **`deny` l'emporte toujours.** |
| `ttl` / `explicit-max-ttl` | `ttl` est une **minuterie** remise à zéro par `renew`. `explicit-max-ttl` est un **mur** absolu compté depuis la création : un `renew` ne le dépasse jamais. |
| Hiérarchie | Révoquer un parent révoque tous ses enfants. Un enfant ne peut avoir **qu'un sous-ensemble** des policies du parent (pas d'élévation de privilèges). |
| Accessor | Il permet de consulter et révoquer un token **sans pouvoir l'utiliser**. On le trouve en clair dans l'audit log. |
| Wrapping | Un ticket à usage unique, avec TTL, qui ne contient pas le secret. Chaque `-wrap-ttl` crée un **nouveau** ticket. Si le ticket est déjà consommé avant son destinataire, c'est une **interception**. |

## Exercices

1. Écris une policy `team-a` qui permet de tout faire sous `lab/data/team-a/*`, de lister `lab/metadata/team-a/*`, mais **pas** de détruire définitivement des versions (indice : le chemin `lab/destroy/...`).
2. Utilise `+` pour autoriser la lecture de `lab/data/<n'importe quelle appli>/config` uniquement.
3. Crée un token `-use-limit=2` et vérifie qu'il meurt après 2 requêtes.
4. Ouvre l'UI avec un token `app-ro` : que vois-tu ? que ne vois-tu pas ?
