# Stack locale : kind + Vault + External Secrets Operator

Deux scripts pour monter et arrêter tout l'environnement des labs Vault/ESO.

| Script | Effet |
|---|---|
| `bash stack-up.sh` | Démarre **ou recrée** tout ce qui manque : cluster kind `vault`, Vault dev (port 8200), ESO 2.14.0, démo ESO (namespace `demo`). Idempotent, relançable à volonté. |
| `bash stack-down.sh` | **Arrête** Vault et le nœud kind. Le cluster est conservé, les données Vault (mode dev) sont perdues. |
| `bash stack-down.sh --delete` | **Supprime** le cluster kind et le conteneur Vault (confirmation demandée). `stack-up.sh` recrée tout. |

## Ce que fait `stack-up.sh`

```
0. Prérequis   docker, kind, kubectl, helm ; Docker répond
1. kind        cluster existant → démarre le nœud ; absent → le crée (kindest/node v1.37.0)
2. Vault       conteneur existant → docker start ; absent → docker compose up
               + docker network connect kind vault (pour l'auth Kubernetes, lab 07)
3. ESO         helm install 2.14.0 s'il n'est pas déjà installé, attend les pods
4. Démo        namespace demo, Secret vault-token, ClusterSecretStore, ExternalSecrets,
               secrets kv/org/dev (v2) et kv/org/prod dans Vault, pod api-consumer
5. État        attend une synchro ESO réussie POSTÉRIEURE au lancement du script
```

| Situation | Durée mesurée |
|---|---|
| Stack arrêtée → relance | ~1 min 30 |
| Depuis zéro (cluster et Vault à créer) | ~6 min |

## Variables

| Variable | Défaut | Usage |
|---|---|---|
| `CLUSTER_NAME` | `vault` | Nom du cluster kind (contexte `kind-<nom>`) |
| `KIND_IMAGE` | `kindest/node:v1.37.0@sha256:…` | Version de Kubernetes |
| `ESO_VERSION` | `2.14.0` | Version du chart ESO |

Exemple : `CLUSTER_NAME=vault-test bash stack-up.sh` monte une stack de test à côté (elle partage le même Vault).

## Bon à savoir

- **Vault est en mode dev** : chaque arrêt efface ses données. `stack-up.sh` ne recrée que la démo ESO. Les policies des labs se rechargent depuis `vault/labs/policies/`.
- La création d'un cluster kind **change le contexte kubectl courant** vers `kind-<nom>`.
- Les avertissements `Kubernetes configuration file is group-readable` viennent de helm. Pour les faire disparaître : `chmod 600 ~/.kube/config`.
