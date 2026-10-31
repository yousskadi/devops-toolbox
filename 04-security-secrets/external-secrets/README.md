# External Secrets Operator (ESO)

> Synchronise des secrets d'un coffre externe (Vault, AWS Secrets Manager…) vers des **Secrets Kubernetes**.

Basé sur le tuto de **Rayan Slim** : [YouTube](https://youtu.be/CF6ARIXdA4A) · [article](https://rslim087a.github.io/rayanslim/lesson.html?course=vault-external-secrets-course&lesson=introduction) · [repo d'origine](https://github.com/rslim087a/vault-kubernetes-external-secrets-tutorial). Le README d'origine est conservé dans [`README.upstream.md`](README.upstream.md).

## Mes adaptations

- `apiVersion: external-secrets.io/v1` (au lieu de `v1beta1`, retiré dans les versions récentes d'ESO)
- `path: "kv/org"` dans le ClusterSecretStore (le mount KV v2 s'appelle `kv/org`)
- `version: "2"` sur l'ExternalSecret dev : épingle une version précise du secret Vault

## Mise en place

```bash
# 1. ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# 2. Vault dev + secrets de démo (voir ../vault/)
cd ../vault && docker compose up -d && bash labs/bootstrap-eso-demo.sh && cd -

# 3. Auth vers Vault (token root : pour la démo uniquement !)
kubectl create namespace demo
kubectl create secret generic vault-token -n demo --from-literal=token=root

# 4. Store, ExternalSecrets et pod de test
kubectl apply -f manifests/secret-store.yaml
kubectl apply -f manifests/external-secret-dev.yaml -f manifests/external-secret-prod.yaml
kubectl apply -f manifests/pod.yml
kubectl -n demo get externalsecret
kubectl -n demo logs api-consumer
```

> ⚠️ Le token `root` stocké dans un Secret Kubernetes n'est **pas** acceptable en prod. La bonne pratique (auth Kubernetes par ServiceAccount) est expliquée dans le [lab Vault 07](../vault/labs/07-kubernetes-auth.md).

## Fichiers

| Fichier | Rôle |
|---|---|
| `manifests/secret-store.yaml` | `ClusterSecretStore` : comment joindre Vault et s'y authentifier |
| `manifests/external-secret-dev.yaml` | `kv/org/dev` (version 2) → Secret `dev-api-credentials` |
| `manifests/external-secret-prod.yaml` | `kv/org/prod` → Secret `prod-api-credentials` |
| `manifests/pod.yml` | Pod qui consomme le secret en variable d'environnement |
