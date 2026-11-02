# HashiCorp Vault

> Un coffre centralisé pour les secrets : il les **stocke**, les **génère à la demande** (identifiants DB, certificats), **chiffre** des données pour les applis, et **trace** chaque accès.

## Quand l'utiliser

- ✅ Plusieurs applis, équipes ou environnements partagent des secrets, et il faut savoir qui accède à quoi.
- ✅ Tu veux des identifiants **éphémères** (DB, cloud, certificats TLS) plutôt que des mots de passe éternels.
- ✅ Tu as besoin de chiffrer des données applicatives sans gérer les clés toi-même (transit).
- ❌ Un seul projet avec 3 variables d'environnement : un secret manager cloud ou SOPS suffit, car Vault demande de l'exploitation (unseal, sauvegardes, HA).

## Concepts clés

| Concept | En une phrase |
|---|---|
| **Chemin** | Tout est un chemin d'API (`lab/data/app/config`, `auth/userpass/login/alice`, `sys/...`). |
| **Secrets engine** | Plugin monté sur un chemin : `kv` (stocke), `database` / `pki` (génèrent), `transit` (chiffre). |
| **Auth method** | Façon de prouver qui on est (userpass, AppRole, Kubernetes, OIDC…). Le résultat est un **token**. |
| **Token** | Porte des **policies** et a un TTL. Le token `root` contourne tout et ne s'utilise jamais en appli. |
| **Policy** | Liste de chemins et de *capabilities* (`read`, `create`, `list`…). Par défaut, **tout est refusé**. |
| **Lease** | Durée de vie d'un secret dynamique : renouvelable, révocable, et qui expire tout seul. |
| **Seal / Unseal** | Vault démarre **scellé**. Il faut un quorum de clés (Shamir) ou un KMS (auto-unseal) pour l'ouvrir. |
| **Audit device** | Journal de toutes les requêtes, avec les valeurs sensibles hashées. |

## Démarrage rapide

```bash
bash ~/TP/04-security-secrets/stack/stack-up.sh   # toute la stack : kind + Vault + ESO (voir ../stack/)
# ou Vault seul :
cd ~/TP/04-security-secrets/vault
docker compose up -d                 # Vault 1.19 en mode dev → http://localhost:8200 (token : root)
source labs/env.sh                   # fonction `vault` : le CLI s'exécute dans le conteneur
vault status
```

> ⚠️ Mode **dev** = stockage en mémoire : tout est perdu au redémarrage du conteneur. Pour restaurer le tuto ESO : `bash labs/bootstrap-eso-demo.sh`.

## Labs

Parcours complet et checklist de compétences : **[labs/README.md](labs/README.md)**

Chaque lab commence par une section **🎯 Comprendre avant de pratiquer** (explication simple, analogie, exemple concret, usage en prod, pièges), puis les étapes pratiques.

| # | Lab | Ce que j'apprends | Fait |
|---|---|---|---|
| 01 | [KV v2](labs/01-kv-v2.md) | Stocker, versionner, supprimer, check-and-set, API HTTP | ✅ |
| 02 | [Policies & tokens](labs/02-policies-tokens.md) | Moindre privilège, TTL, hiérarchie, response wrapping | ✅ |
| 03 | [Auth methods](labs/03-auth-methods.md) | userpass, AppRole, identity, templated policies | ⏳ |
| 04 | [Secrets dynamiques DB](labs/04-database-dynamic-secrets.md) | Users PostgreSQL éphémères, leases, rotation root | |
| 05 | [Transit](labs/05-transit.md) | Encryption as a Service, rotation, rewrap, signature | |
| 06 | [PKI](labs/06-pki.md) | CA racine et intermédiaire, certificats courts, révocation | |
| 07 | [Auth Kubernetes](labs/07-kubernetes-auth.md) | Pod → Vault via ServiceAccount, ESO sans token root | |
| 08 | [Agent Injector](labs/08-agent-injector.md) | Secrets en fichier via sidecar, rotation à chaud | |
| 09 | [Opérations](labs/09-operations.md) | Raft, init/unseal, seal, snapshot, audit | |
| 10 | [Défis](labs/10-defis.md) | Exercices de synthèse | |

- 📊 Diagrammes interactifs (générés avec [Archify](https://github.com/tt-a1i/archify), à ouvrir en local) :
  - [Authentification Kubernetes, séquence](diagrams/sequence-auth-kubernetes/auth-kubernetes.html)
  - [Cycle de vie d'un token](diagrams/lifecycle-token/cycle-vie-token.html)
  - [Connexion OIDC avec Keycloak, séquence](diagrams/sequence-oidc-keycloak/connexion-oidc-keycloak.html)
- 📄 [cheatsheet.md](cheatsheet.md) : les commandes
- 🔧 [troubleshooting.md](troubleshooting.md) : les erreurs déjà rencontrées

## Arborescence

```
vault/
├── docker-compose.yml        # Vault dev (port 8200)
└── labs/
    ├── 01..10-*.md           # les tutos
    ├── env.sh                # fonctions vault / vault-prod / wait-vault-prod
    ├── bootstrap-eso-demo.sh # recrée kv/org/dev et kv/org/prod
    ├── manifests/            # YAML Kubernetes des labs 07-08
    └── vault-prod/           # Vault en mode serveur, Raft (lab 09, port 8210)
└── diagrams/                 # diagrammes Archify : <nom>.html + candidate.json (source)
```

## Ressources

- Doc : https://developer.hashicorp.com/vault/docs
- Tutoriels officiels : https://developer.hashicorp.com/vault/tutorials
- Certification : *HashiCorp Certified: Vault Associate*
