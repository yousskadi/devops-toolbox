# Sécurité et gestion des secrets

| Outil | Description | État |
|---|---|---|
| [vault](vault/) | HashiCorp Vault : coffre de secrets, secrets dynamiques, chiffrement, PKI | 🟢 10 labs |
| [stack](stack/) | Scripts `stack-up.sh` / `stack-down.sh` : monte toute la stack locale (kind + Vault + ESO) | 🟢 testé |
| [external-secrets](external-secrets/) | External Secrets Operator : synchronise Vault (ou le cloud) vers des Secrets Kubernetes | 🟢 tuto de base |

À venir : cert-manager, Trivy, Kyverno, SOPS.
