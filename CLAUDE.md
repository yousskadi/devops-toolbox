# Contexte pour Claude : devops-toolbox

Ce fichier garde la mémoire de notre travail, d'une session à l'autre. Claude Code le lit automatiquement quand il est lancé depuis `~/TP`.

## Qui / quoi

- Youssef apprend les outils DevOps en pratique. On échange **en français**.
- Repo : https://github.com/yousskadi/devops-toolbox (public). Racine locale : `~/TP`.
- Structure : un dossier par domaine (`01-linux` … `08-cloud`). Chaque outil a `README.md`, `cheatsheet.md`, `troubleshooting.md` et `labs/` (modèle dans `_template/`). Notes de séance dans `journal/`.

## Environnement

- WSL2, Docker, cluster **kind** nommé `vault` (conteneur `vault-control-plane`).
- **Vault 1.19 en mode dev** : conteneur `vault`, port 8200, token `root`, compose dans `04-security-secrets/vault/docker-compose.yml` (`name: vault`, réseau `vault_default`).
  - Stockage **en mémoire** : tout est perdu au redémarrage → `bash labs/bootstrap-eso-demo.sh` recrée `kv/org/dev` et `kv/org/prod` pour le tuto ESO.
  - Commandes Vault : `cd ~/TP/04-security-secrets/vault && source labs/env.sh`, puis `vault ...` (le CLI tourne dans le conteneur, `VAULT_TOKEN=<t> vault ...` pour changer d'identité).
- ESO installé dans le namespace `external-secrets`. Namespace de démo : `demo`.

## Avancement

| Parcours | Où on en est |
|---|---|
| Vault (`04-security-secrets/vault/labs/`) | Labs **01 et 02 terminés** (2026-10-31). **Prochaine séance : lab 03 (auth methods)**, étape 1 userpass. |

Les détails de chaque séance sont dans `journal/`.

## Façon de travailler (préférences de Youssef)

- **Guider pas à pas** : une étape à la fois, donner les commandes, puis Youssef les lance et colle la sortie.
- Faire **prédire** le résultat avant de lancer (✅/❌), puis expliquer les écarts.
- Explications **claires et simples** : une phrase, une analogie, un exemple concret, **l'utilité en prod**.
- Corriger les réponses avec bienveillance : ✅ juste, 🟡 à nuancer, ❌ faux, avec la bonne explication.
- Après chaque séance : mettre à jour `journal/`, le `troubleshooting.md` de l'outil et l'avancement, puis commit et push **seulement après accord**.

## Règles

- **Ne jamais écrire dans le Vault de Youssef sans lui demander.** Pour vérifier un comportement, utiliser un conteneur jetable : `docker run -d --rm --name vault-scratch -e VAULT_DEV_ROOT_TOKEN_ID=root hashicorp/vault:1.19.0`.
- Ne pas relancer `docker compose up` sur le Vault dev sans prévenir (une recréation du conteneur efface tout).
- Tester chaque commande avant de la mettre dans un tuto.
- Ne rien publier qui ressemble à un secret réel. Le `.gitignore` exclut `init.txt`, `*.snap`, `*.key`, `*.crt`, `*.pem`.
