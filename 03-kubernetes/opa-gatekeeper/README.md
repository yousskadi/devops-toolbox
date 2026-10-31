# OPA Gatekeeper

> Contrôleur d'admission Kubernetes : il refuse les ressources qui ne respectent pas des règles écrites en Rego.

## Ce qu'il y a ici

| Fichier | Rôle |
|---|---|
| `constraintTemplate.yml` | Définit le type de règle `K8sRequiredLabels` (logique Rego) |
| `constraints.yml` | Instance de la règle : tout Namespace doit avoir le label `owner` |
| `namespace-test.yaml` | Namespace conforme (avec `owner: devops`) pour tester |

## Tester

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace

kubectl apply -f constraintTemplate.yml
kubectl apply -f constraints.yml

kubectl apply -f namespace-test.yaml      # ✅ accepté
kubectl create namespace sans-label        # ❌ refusé : label owner manquant
```
