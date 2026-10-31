# Lab 07 : auth Kubernetes (pods ↔ Vault)

**Objectif :** un pod prouve son identité à Vault **avec son ServiceAccount**, sans aucun secret pré-partagé. Ensuite, on améliore ton tuto ESO, qui utilise aujourd'hui le token `root` stocké dans un Secret Kubernetes (à ne jamais faire en prod).

## 🎯 Comprendre avant de pratiquer

**En une phrase :** un pod prouve qui il est avec le jeton de son **ServiceAccount**. Vault demande à Kubernetes « ce jeton est-il valide, et à qui appartient-il ? » puis délivre un token Vault. **Aucun secret à distribuer.**

**Analogie :** un salarié se présente à l'accueil d'un autre site du groupe. L'accueil **appelle les RH** (l'API Kubernetes *TokenReview*), qui confirment : « oui, c'est bien Alice, du service Paiement ». L'accueil lui donne alors un badge avec les accès du service Paiement.

**Exemple concret :**
```
ServiceAccount "shop" dans le namespace "prod"
   → rôle Vault "shop-prod" (bound_service_account_names=shop, namespaces=prod)
   → policy "shop-prod" : lecture de shop/data/prod/*

Un pod du namespace "dev", même avec un SA nommé "shop", est refusé.
```

**À quoi ça sert en prod :**
- C'est **la** méthode standard pour Kubernetes : elle supprime le « secret zéro » (lab 03).
- C'est la base de tous les outils d'intégration : **ESO**, **Vault Agent Injector**, **Vault Secrets Operator**, **CSI driver**.
- Isolation par **namespace** et par **appli** : un rôle Vault par couple (SA, namespace).
- Elle remplace la mauvaise pratique de ton tuto ESO d'origine : le **token root stocké dans un Secret Kubernetes**, qui donne tout Vault à quiconque peut lire ce Secret.

**Pièges en prod :**
- Réseau dans les **deux sens** : pod → Vault, et Vault → API Kubernetes.
- `bound_service_account_names=*` : n'importe quel pod du namespace devient l'appli.
- Avec plusieurs clusters, il faut un mount d'auth par cluster (`auth/k8s-prod/`, `auth/k8s-staging/`).

## Comment ça marche

> 📊 **Diagramme :** [séquence complète de l'auth Kubernetes](../diagrams/sequence-auth-kubernetes/auth-kubernetes.html) (login, TokenReview, vérification du rôle, lecture du secret). Ouvre le fichier `.html` en local dans un navigateur.

```
 Pod (SA webapp)                     Vault (conteneur Docker)                kind API server
  │ 1. JWT du ServiceAccount ──────►  auth/kubernetes/login role=webapp
  │                                     │ 2. TokenReview(JWT) ─────────────────►  "valide : demo/webapp"
  │                                     │ 3. vérifie que le rôle autorise demo/webapp
  │ ◄────── 4. token Vault (policy webapp)
  │ 5. lit lab/data/webapp/db
```

Il faut donc une connexion réseau **dans les deux sens** :
- Pod → Vault : `http://host.docker.internal:8200` (déjà utilisé par ton ClusterSecretStore)
- Vault → API Kubernetes : on connecte le conteneur Vault au réseau Docker `kind`, l'API répond alors sur `https://vault-control-plane:6443`

## 1. Réseau Vault ↔ kind

```bash
source labs/env.sh
docker network connect kind vault 2>/dev/null; docker inspect vault -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
docker exec vault wget -qO- --no-check-certificate https://vault-control-plane:6443/version | head -4
```

## 2. Côté Kubernetes : le ServiceAccount de Vault et celui de l'appli

```bash
kubectl apply -f labs/manifests/07-vault-auth-sa.yaml
```

Lis le manifest : `vault-auth` sert à Vault pour valider les tokens (rôle `system:auth-delegator`), et `webapp` est l'identité de l'application.

## 3. Côté Vault : activer et configurer l'auth method

```bash
vault auth enable kubernetes

REVIEWER_JWT=$(kubectl -n demo get secret vault-auth-token -o jsonpath='{.data.token}' | base64 -d)
K8S_CA=$(kubectl -n demo get secret vault-auth-token -o jsonpath='{.data.ca\.crt}' | base64 -d)

vault write auth/kubernetes/config \
  kubernetes_host=https://vault-control-plane:6443 \
  kubernetes_ca_cert="$K8S_CA" \
  token_reviewer_jwt="$REVIEWER_JWT"
```

Le secret et la policy de l'appli :

```bash
vault secrets list | grep -q '^lab/' || vault secrets enable -path=lab kv-v2
vault kv put lab/webapp/db user=web password=fromvault

vault policy write webapp - <<'EOF'
path "lab/data/webapp/*" { capabilities = ["read"] }
EOF

# Le rôle : QUEL ServiceAccount de QUEL namespace obtient QUELLE policy
vault write auth/kubernetes/role/webapp \
  bound_service_account_names=webapp \
  bound_service_account_namespaces=demo \
  token_policies=webapp ttl=20m
```

## 4. Tester depuis un pod (à la main, avec curl)

```bash
kubectl -n demo run k8sauth-test --rm -it --restart=Never --image=curlimages/curl \
  --overrides='{"spec":{"serviceAccountName":"webapp"}}' --command -- sh
```

Dans le pod :

```sh
JWT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -s -X POST -d "{\"role\":\"webapp\",\"jwt\":\"$JWT\"}" http://host.docker.internal:8200/v1/auth/kubernetes/login
# copie le client_token, puis :
TOKEN=hvs.xxxxx
curl -s -H "X-Vault-Token: $TOKEN" http://host.docker.internal:8200/v1/lab/data/webapp/db
exit
```

**Test négatif :** relance le pod avec `serviceAccountName: default`. Le login doit échouer avec `service account name not authorized`. C'est la preuve que l'identité Kubernetes est bien vérifiée.

## 5. Améliorer ton tuto ESO : plus de token root

```bash
vault write auth/kubernetes/role/eso-reader \
  bound_service_account_names=eso-reader \
  bound_service_account_namespaces=demo \
  token_policies=webapp ttl=10m

kubectl apply -f labs/manifests/07-eso-k8s-auth.yaml
kubectl -n demo get secretstore vault-k8s                 # STATUS Valid
kubectl -n demo get externalsecret webapp-db              # SecretSynced
kubectl -n demo get secret webapp-db -o jsonpath='{.data.password}' | base64 -d; echo
```

Observe la synchronisation (refreshInterval de 30 s) :

```bash
vault kv put lab/webapp/db user=web password=rotated
sleep 35; kubectl -n demo get secret webapp-db -o jsonpath='{.data.password}' | base64 -d; echo
```

Compare avec le `secret-store.yaml` d'origine (`../external-secrets/manifests/`) : `tokenSecretRef` (token root en clair dans le cluster) a été remplacé par `kubernetes` + `serviceAccountRef`. Si quelqu'un vole ce SA, il n'obtient que la policy `webapp`, en lecture seule sur un seul chemin.

## Debug courant

| Erreur | Cause probable |
|---|---|
| `permission denied` au login | Le rôle n'autorise pas ce SA ou ce namespace, ou `token_reviewer_jwt` est invalide |
| `connection refused` ou timeout depuis Vault | Le conteneur Vault n'est pas sur le réseau `kind` |
| `x509: certificate signed by unknown authority` | Mauvais `kubernetes_ca_cert` |
| L'ESO reste `SecretSyncedError` après un redémarrage de Vault | Mode dev : tout est perdu, il faut refaire la config |

```bash
vault read auth/kubernetes/config
vault read auth/kubernetes/role/webapp
kubectl -n demo describe externalsecret webapp-db | tail -5
```

## Exercices

1. Crée un namespace `staging` avec un SA `webapp` : peut-il se loguer avec le rôle `webapp` ? Modifie le rôle pour accepter `bound_service_account_namespaces=demo,staging`.
2. Convertis ton ClusterSecretStore `vault-backend` (tuto d'origine) pour qu'il utilise l'auth Kubernetes, puis supprime le Secret `vault-token`.
3. Utilise ESO pour créer un secret Kubernetes à partir de **plusieurs** chemins Vault (`dataFrom` avec plusieurs `extract`).
