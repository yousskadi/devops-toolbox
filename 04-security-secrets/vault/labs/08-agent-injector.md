# Lab 08 : Vault Agent Injector (sidecar)

**Objectif :** injecter les secrets **en fichier** dans le pod via un sidecar Vault Agent, sans jamais créer de Secret Kubernetes.

## 🎯 Comprendre avant de pratiquer

**En une phrase :** un **sidecar Vault Agent** est ajouté automatiquement dans le pod. Il s'authentifie auprès de Vault, écrit les secrets dans un **fichier en mémoire** (`/vault/secrets/...`) et les **tient à jour**.

**Analogie :** un **assistant personnel** attaché à chaque employé. Il va chercher les documents au coffre, les pose sur le bureau dans le bon format, et remplace ceux qui sont périmés, sans que l'employé n'ait jamais à aller au coffre.

**Exemple concret :** une appli Java legacy qui lit un fichier `application.properties` et ne sait rien de Vault :
```properties
# généré par le template Vault Agent dans /vault/secrets/application.properties
spring.datasource.username=v-k8s-shop-a8f2      ← identifiant DB dynamique (lab 04)
spring.datasource.password=Qm8...               ← renouvelé automatiquement
stripe.key=sk_live_...                          ← lu dans KV
```
L'appli n'a **aucune ligne de code Vault**.

**À quoi ça sert en prod :**
- Les **secrets ne passent jamais dans etcd** (pas de Secret Kubernetes) : c'est souvent une exigence de conformité.
- Les **secrets dynamiques** (DB, PKI) sont **renouvelés** tant que le pod vit, puis révoqués à sa mort.
- **Templating** : on génère n'importe quel fichier de config (properties, JSON, .env, nginx.conf).
- **Rechargement** : on peut lancer une commande après chaque changement (par exemple recharger nginx quand le certificat change).

**ESO ou Agent Injector ?**
- **ESO** est plus simple et multi-fournisseur (AWS, GCP, Azure…). L'appli lit un Secret Kubernetes classique. Mais ce secret est stocké dans etcd.
- **Agent Injector** est plus sécurisé et plus riche (dynamique, templates), mais il ajoute un sidecar par pod.

**Pièges en prod :**
- Un sidecar **par pod**, soit des centaines de conteneurs en plus : il faut fixer leurs limites CPU et mémoire.
- **Jobs et CronJobs** : utilise `agent-pre-populate-only`, sinon le sidecar empêche le Job de se terminer.
- L'appli doit **relire le fichier** quand il change, ou être redémarrée.

Prérequis : lab 07 fait (auth Kubernetes, rôle `webapp`, secret `lab/webapp/db`).

## ESO, Agent Injector ou CSI : lequel choisir ?

| | External Secrets Operator | Vault Agent Injector | Secrets Store CSI / VSO |
|---|---|---|---|
| Résultat | Secret Kubernetes | Fichier dans un volume partagé (tmpfs) | Volume monté, ou Secret k8s (VSO) |
| Secret visible dans etcd | Oui | **Non** | Non (CSI) / Oui (VSO) |
| Templating | Oui | Oui, très riche (Consul Template) | Limité |
| Secrets dynamiques (DB, PKI) avec renouvellement | Limité | **Oui** (renouvelle les leases) | VSO : oui |
| Multi-provider (AWS, GCP…) | **Oui** | Vault seulement | CSI : oui |
| Coût | 1 opérateur | 1 sidecar par pod | 1 DaemonSet |

## 1. Installer l'injecteur (sans serveur Vault dans le cluster)

On installe uniquement le webhook d'injection, qui pointe vers ton Vault externe :

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update hashicorp
helm install vault hashicorp/vault -n vault --create-namespace \
  --set global.externalVaultAddr=http://host.docker.internal:8200 \
  --set server.enabled=false --wait
kubectl -n vault get pods
kubectl get mutatingwebhookconfiguration | grep vault
```

## 2. Déployer une appli annotée

```bash
kubectl apply -f labs/manifests/08-webapp-injected.yaml
kubectl -n demo rollout status deploy/webapp
kubectl -n demo get pods -l app=webapp     # READY 2/2 : app + vault-agent
```

Regarde ce que l'injecteur a ajouté au pod :

```bash
POD=$(kubectl -n demo get pod -l app=webapp -o name | head -1)
kubectl -n demo get $POD -o jsonpath='{.spec.initContainers[*].name}{"\n"}{.spec.containers[*].name}{"\n"}'
kubectl -n demo logs $POD -c app --tail=4
kubectl -n demo exec $POD -c app -- ls -la /vault/secrets/
```

## 3. Rotation à chaud

```bash
vault kv put lab/webapp/db user=web password=hot-rotated
kubectl -n demo logs -f $POD -c app        # le fichier change après le prochain rendu (~5 min par défaut pour KV)
```

Pour accélérer pendant le test, ajoute l'annotation `vault.hashicorp.com/template-static-secret-render-interval: "15s"` au Deployment.

Les annotations utiles :

| Annotation | Effet |
|---|---|
| `agent-pre-populate-only: "true"` | Init container seulement, pas de sidecar (pour les Jobs) |
| `agent-inject-file-<nom>` | Nom du fichier |
| `agent-inject-command-<nom>` | Commande lancée après chaque rendu (par exemple un reload nginx) |
| `agent-run-as-user` / `agent-limits-cpu` | Sécurité et ressources du sidecar |

## 4. Bonus : secrets dynamiques DB dans le pod

Si tu as fait le lab 04, ajoute à la policy `webapp` `path "database/creds/readonly" { capabilities = ["read"] }`, puis :

```yaml
vault.hashicorp.com/agent-inject-secret-pg: "database/creds/readonly"
vault.hashicorp.com/agent-inject-template-pg: |
  {{- with secret "database/creds/readonly" -}}
  postgresql://{{ .Data.username }}:{{ .Data.password }}@vault-pg:5432/postgres
  {{- end }}
```

L'agent renouvelle le lease tant que le pod vit, et Vault supprime l'utilisateur DB quand le pod disparaît (fin du lease).

## Debug

```bash
kubectl -n demo logs $POD -c vault-agent-init     # problèmes d'auth au démarrage
kubectl -n demo logs $POD -c vault-agent
kubectl -n vault logs deploy/vault-agent-injector
```

Pod bloqué en `Init:0/1` : en général le rôle ou la policy est mauvais, ou Vault est injoignable.

## Nettoyage

```bash
kubectl -n demo delete deploy webapp
helm uninstall vault -n vault && kubectl delete ns vault
```

## Exercices

1. Génère un fichier `config.json` pour l'appli avec un template qui mélange plusieurs secrets.
2. Crée un Job avec `agent-pre-populate-only` et vérifie qu'il se termine bien (pas de sidecar qui bloque).
3. Supprime la policy `webapp` dans Vault et redémarre le pod : observe l'échec dans `vault-agent-init`.
