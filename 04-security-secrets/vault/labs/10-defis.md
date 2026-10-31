# Lab 10 : défis finaux (sans solution guidée)

Chaque défi combine plusieurs labs. Pars d'un Vault dev vierge (`docker restart vault`) et note tes commandes dans un script `defi-N.sh` : si tu peux tout rejouer d'un coup, c'est acquis.

## Défi 1 : plateforme multi-équipes

- Deux équipes, `alpha` et `beta`, chacune avec son propre mount KV (`alpha/`, `beta/`).
- Groupes identity `alpha-devs` (lecture/écriture sur `alpha/`) et `alpha-readers` (lecture seule).
- Utilisateurs userpass : `ana` (alpha-devs), `ben` (alpha-readers), `carl` (beta).
- ✅ Validation : `vault token capabilities` prouve chaque droit et chaque refus, et personne ne voit l'espace de l'autre équipe dans l'UI.

## Défi 2 : pipeline CI sans secret en clair

- Un AppRole `ci` dont le secret_id est livré wrappé (TTL 60 s, usage unique).
- Un script `ci.sh` qui unwrap, se logue, récupère `lab/ci/registry` et affiche uniquement « login OK ».
- ✅ Validation : relancer `ci.sh` avec le même wrapping token échoue, et l'audit log montre les deux tentatives.

## Défi 3 : appli Kubernetes « zéro secret statique »

- Deployment `shop` dans le namespace `shop` avec son propre ServiceAccount.
- Il reçoit via l'Agent Injector :
  - des identifiants **PostgreSQL dynamiques** (lab 04),
  - un **certificat TLS** de 1 h émis par `pki_int` (lab 06).
- Il chiffre une donnée via **transit** avant de l'écrire en DB.
- ✅ Validation : supprimer le pod fait disparaître son utilisateur Postgres une fois le lease expiré.

## Défi 4 : migration du tuto ESO d'origine

- Remplace `tokenSecretRef` (token root) par l'auth Kubernetes dans le ClusterSecretStore `vault-backend`.
- Policy minimale : lecture de `kv/org/data/dev` et `kv/org/data/prod` uniquement.
- Supprime le Secret `demo/vault-token`.
- ✅ Validation : `dev-api-key` et `prod-api-key` restent `SecretSynced`.

## Défi 5 : incident

Simule une fuite : un token `app-rw` a été publié sur GitHub.
1. Retrouve dans l'audit log tout ce qu'il a fait (à partir de son accessor).
2. Révoque-le, ainsi que tous les leases DB qu'il a générés.
3. Fais tourner les secrets KV qu'il a pu lire.
4. Rédige un post-mortem de 10 lignes.

## Défi 6 : Infrastructure as Code

Recrée toute la config du défi 1 avec **Terraform** (provider `hashicorp/vault`) : mounts, policies, auth, groupes. Après `terraform destroy` puis `apply`, tout doit revenir à l'identique. C'est la façon dont Vault est géré en entreprise.

---

## Pour aller plus loin

- Documentation officielle et tutoriels : https://developer.hashicorp.com/vault/tutorials
- Vault Secrets Operator (VSO), l'alternative officielle à ESO : https://developer.hashicorp.com/vault/docs/platform/k8s/vso
- Certification **HashiCorp Certified: Vault Associate** : ces labs couvrent la majorité du programme.
