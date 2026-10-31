# Parcours Vault : de zéro à l'intégration Kubernetes

Parcours pratique sur **ton** environnement : Vault 1.19 en mode dev dans Docker (`docker-compose.yml` de ce dossier, port 8200, token `root`) et le cluster kind `vault`.

Toutes les commandes de ces labs ont été testées sur cet environnement.

## Avant de commencer (à chaque session)

```bash
cd ~/TP/04-security-secrets/vault           # toutes les commandes des labs partent d'ici
docker start vault vault-control-plane      # si arrêtés (ou : docker compose up -d)
source labs/env.sh                           # définit la fonction `vault`
vault status                                 # Sealed = false
```

> ⚠️ **Le mode `-dev` stocke tout en mémoire.** Chaque redémarrage du conteneur efface tous les secrets, policies et auth methods.
> Pour remettre en place le tuto ESO d'origine : `bash labs/bootstrap-eso-demo.sh`.
> Le lab 09 montre comment un vrai Vault persiste ses données.

UI web : http://localhost:8200 (méthode *Token*, valeur `root`). Après chaque lab, va voir le résultat dans l'UI pour faire le lien entre CLI et interface.

## Le modèle mental (à garder en tête)

```
             ┌─────────────── Vault ───────────────┐
 client ──►  │ Auth method ──► Token + Policies ──► Secrets engine │
 (humain,    │ (userpass,      (qui a le droit     (kv, database,  │
  appli,     │  approle, k8s)   de faire quoi       transit, pki)  │
  pod)       │                  sur quel chemin)                   │
             └───────── tout est tracé dans l'Audit log ───────────┘
```

1. **Tout est un chemin** (`lab/data/app/config`, `auth/userpass/login/alice`, `sys/policies/...`). Le CLI n'est qu'un client de l'API HTTP.
2. **On s'authentifie** avec une *auth method* et on obtient un **token**.
3. Le token porte des **policies**, qui donnent des droits (*capabilities*) sur des chemins. Par défaut, tout est refusé.
4. Les **secrets engines** sont montés sur des chemins : ils stockent des secrets (KV), en **génèrent** à la demande (database, PKI) ou fournissent du chiffrement (transit).
5. Tout ce qui est dynamique a un **lease**, c'est-à-dire une durée de vie (TTL) : renouvelable, révocable, et qui expire tout seul.

## Plan de montée en compétence

| # | Lab | Ce que tu apprends | Durée |
|---|-----|-------------------|-------|
| 01 | [KV v2](01-kv-v2.md) | Stocker, versionner, supprimer, restaurer des secrets ; CLI et API HTTP | 45 min |
| 02 | [Policies & tokens](02-policies-tokens.md) | Moindre privilège, capabilities, TTL, renouvellement, révocation, response wrapping | 1 h |
| 03 | [Auth methods](03-auth-methods.md) | userpass (humains), AppRole (machines/CI), identity | 1 h |
| 04 | [Secrets dynamiques (PostgreSQL)](04-database-dynamic-secrets.md) | Identifiants DB éphémères, leases, rotation du mot de passe root | 1 h |
| 05 | [Transit](05-transit.md) | Encryption as a Service, rotation et rewrap de clé, signature | 45 min |
| 06 | [PKI](06-pki.md) | Ta propre CA, émission de certificats courts, révocation | 1 h |
| 07 | [Auth Kubernetes](07-kubernetes-auth.md) | Un pod s'authentifie avec son ServiceAccount ; ESO sans token root | 1 h 30 |
| 08 | [Vault Agent Injector](08-agent-injector.md) | Secrets injectés en fichier dans le pod via un sidecar | 1 h |
| 09 | [Opérations](09-operations.md) | Mode serveur, Raft, init/unseal, seal, snapshot, audit | 1 h 30 |
| 10 | [Défis finaux](10-defis.md) | Exercices sans solution guidée pour valider tes acquis | libre |

**Ordre conseillé :** 01 → 02 → 03 sont la base, à faire dans l'ordre. Ensuite 04, 05 et 06 sont indépendants. 07 puis 08 pour Kubernetes. 09 à tout moment après 02.

## Checklist de compétences

Tu maîtrises Vault quand tu sais, sans regarder :

- [ ] expliquer la différence entre `lab/data/...` et `lab/metadata/...` en KV v2
- [ ] écrire une policy en moindre privilège et la tester avec `vault token capabilities`
- [ ] expliquer pourquoi le token root ne doit jamais être utilisé par une application
- [ ] configurer AppRole pour une CI et expliquer le rôle de `role_id` et de `secret_id`
- [ ] générer des identifiants DB dynamiques et les révoquer d'un coup avec `lease revoke -prefix`
- [ ] chiffrer et déchiffrer avec transit, puis faire tourner la clé sans casser les anciens chiffrés
- [ ] créer une CA et émettre un certificat de 1 h
- [ ] configurer l'auth Kubernetes et faire lire un secret à un pod via son ServiceAccount
- [ ] choisir entre ESO, Agent Injector et CSI/VSO selon le besoin
- [ ] initialiser, unseal et sauvegarder (snapshot) un Vault non-dev
- [ ] lire un audit log et retrouver qui a lu quel secret

## Réinitialiser

```bash
docker restart vault && sleep 5 && bash labs/bootstrap-eso-demo.sh   # Vault vierge et tuto ESO restauré
```
