# 2026-11-02 : Vault, lab bonus OIDC avec Keycloak

Connexion à Vault avec un compte Keycloak du NAS, dans un realm de test `vault-lab`. Le realm `homelab` n'a pas été touché.

Schéma : [connexion OIDC](../04-security-secrets/vault/diagrams/sequence-oidc-keycloak/connexion-oidc-keycloak.html).

## Ce que j'ai appris

- Keycloak vérifie qui je suis, Vault décide ce que je peux faire. **Vault ne voit jamais le mot de passe.**
- Côté Keycloak : un **realm** (l'annuaire), un **client** (Vault), un **groupe**, un **utilisateur** et un **mapper** qui met les groupes dans le jeton d'identité.
- Côté Vault : `auth/oidc/config` (où est Keycloak, et comment lui faire confiance), un **rôle** (comment lire la réponse) et un **groupe externe** avec sa policy.
- L'**alias de groupe** fait le lien. Il doit avoir **le nom exact du groupe Keycloak** et **l'accessor de la méthode OIDC**.
- Un groupe `external` n'a pas de membres ajoutés à la main : Vault les met à jour quand la personne se connecte.
- Vault ne réaffiche jamais le secret du client. `read -rs` évite de l'afficher ou de le laisser dans l'historique du shell.
- Le login OIDC se fait sur la machine où Vault est sur `localhost:8200`, car Keycloak renvoie le navigateur vers cette adresse.

## Retirer quelqu'un d'un groupe : ce que j'ai observé

| Étape | Ancien token |
|---|---|
| Retiré de `vault-devs` dans Keycloak, sans reconnexion | Garde `read` : Vault n'est pas prévenu |
| Plus aucun groupe, puis tentative de connexion | Connexion refusée, rien n'est mis à jour, le token garde `read` |
| Connexion réussie avec un autre groupe | **`deny`** : Vault met à jour l'entité, et même l'ancien token perd le droit |

Conclusion : pour couper un accès tout de suite, il faut révoquer le token. Des TTL courts limitent le délai.

## Les commandes côté Vault

```bash
vault auth enable oidc

KC_CA=$(openssl s_client -connect sso.homelab.local:8443 -servername sso.homelab.local </dev/null 2>/dev/null | openssl x509)
read -rs KC_SECRET; echo

printf '%s' "$KC_SECRET" | vault write auth/oidc/config \
    oidc_discovery_url=https://sso.homelab.local:8443/realms/vault-lab \
    oidc_discovery_ca_pem="$KC_CA" \
    oidc_client_id=vault \
    oidc_client_secret=- \
    default_role=dev
unset KC_SECRET

vault write auth/oidc/role/dev \
    role_type=oidc \
    user_claim=preferred_username \
    groups_claim=groups \
    oidc_scopes=profile,email \
    allowed_redirect_uris=http://localhost:8200/ui/vault/auth/oidc/oidc/callback \
    token_policies=default \
    token_ttl=1h

OIDC_ACC=$(vault auth list -format=json | jq -r '."oidc/".accessor')
GID=$(vault write -field=id identity/group name=keycloak-devs type=external policies=app-ro)
vault write identity/group-alias name=vault-devs mount_accessor=$OIDC_ACC canonical_id=$GID
```

## Erreurs rencontrées

- `sso.homelab.local` inconnu sur le laptop : le nom manquait dans le fichier `hosts` de Windows, lui-même en lecture seule.
- Le groupe Keycloak s'appelait `vault-group` alors que l'alias attendait `vault-devs`.
- L'alias pointait vers `userpass` au lieu d'OIDC, sans doute à cause d'un ancien `$ACC` : les noms étaient bons, mais `member_entity_ids` restait `<nil>`.
- `"groups" claim not found in token` quand l'utilisateur n'a plus aucun groupe.

## Prochaine étape

Lab 04 : secrets dynamiques avec une base de données. Plus tard : un vrai Vault sur le NAS, relié au realm `homelab`.
