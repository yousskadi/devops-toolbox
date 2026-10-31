# 🧰 devops-toolbox

Ma boîte à outils DevOps : des tutos pratiques, des cheatsheets et des notes de dépannage pour monter en compétence sur les outils DevOps, et pour **retrouver vite** une commande ou une solution quand j'en ai besoin.

Tout est testé sur un environnement local : WSL2, Docker et un cluster [kind](https://kind.sigs.k8s.io/).

## Sommaire

| Domaine | Outils | État |
|---|---|---|
| [01 · Linux](01-linux/) | shell, réseau, systemd, permissions | 📋 à venir |
| [02 · Conteneurs](02-containers/) | Docker, Docker Compose | 📋 à venir |
| [03 · Kubernetes](03-kubernetes/) | [OPA Gatekeeper](03-kubernetes/opa-gatekeeper/) | 🟡 en cours |
| [04 · Sécurité & secrets](04-security-secrets/) | [**Vault**](04-security-secrets/vault/), [External Secrets Operator](04-security-secrets/external-secrets/) | 🟢 Vault : 10 labs |
| [05 · Infrastructure as Code](05-iac/) | Terraform, Ansible | 📋 à venir |
| [06 · CI/CD](06-ci-cd/) | GitHub Actions, Argo CD | 📋 à venir |
| [07 · Observabilité](07-observability/) | Prometheus, Grafana, Loki | 📋 à venir |
| [08 · Cloud](08-cloud/) | AWS, Azure, GCP | 📋 à venir |

📓 [Journal d'apprentissage](journal/) : mes notes datées, ce que j'ai appris et les questions que je me suis posées.

## Organisation

Chaque outil suit la même structure (voir [`_template/`](_template/)) :

```
<outil>/
├── README.md            # c'est quoi, quand l'utiliser, concepts clés, démarrage rapide
├── cheatsheet.md        # les commandes à retrouver en 10 secondes
├── troubleshooting.md   # erreurs rencontrées → cause → solution
└── labs/                # tutos pas à pas, numérotés
```

**Comment s'en servir :**
- je cherche une commande → `cheatsheet.md`
- j'ai une erreur → `troubleshooting.md` (et je la note si elle n'y est pas !)
- je veux apprendre ou réviser → `labs/`

Ajouter un outil : `cp -r _template 0X-domaine/mon-outil`

## Environnement

- **Local** : WSL2 (Ubuntu), Docker, kind, kubectl, helm
- **Devcontainer** : [`.devcontainer/`](.devcontainer/), un conteneur Debian avec kubectl et, au choix, terraform, helm/kustomize ou k3d (`bash .devcontainer/scripts/menu.sh`)
