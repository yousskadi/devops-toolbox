# Lab 05 : Transit (Encryption as a Service)

**Objectif :** Vault chiffre et déchiffre **sans jamais stocker les données**, et la clé ne sort jamais de Vault. L'appli stocke le texte chiffré dans sa propre DB.

Cas d'usage : chiffrer des numéros de carte, des données personnelles (RGPD), des champs sensibles d'une DB.

```bash
source labs/env.sh
vault secrets enable transit
vault write -f transit/keys/orders               # clé AES-256-GCM par défaut
vault read transit/keys/orders
```

## 1. Chiffrer et déchiffrer

Transit travaille en **base64** (pour supporter les données binaires) :

```bash
CT=$(vault write -field=ciphertext transit/encrypt/orders plaintext=$(echo -n "4111-1111-1111-1111" | base64))
echo $CT                                     # vault:v1:xxxx... (v1 = version de la clé)

vault write -field=plaintext transit/decrypt/orders ciphertext=$CT | base64 -d; echo
```

## 2. Rotation de clé et rewrap

```bash
vault write -f transit/keys/orders/rotate
vault read -field=latest_version transit/keys/orders    # 2

# Les anciens chiffrés (v1) se déchiffrent toujours
vault write -field=plaintext transit/decrypt/orders ciphertext=$CT | base64 -d; echo

# Rewrap : re-chiffrer avec la nouvelle version SANS voir le texte en clair
CT2=$(vault write -field=ciphertext transit/rewrap/orders ciphertext=$CT)
echo $CT2                                    # vault:v2:...

# Une fois tous les chiffrés rewrappés, on interdit les vieilles versions
vault write transit/keys/orders/config min_decryption_version=2
vault write transit/decrypt/orders ciphertext=$CT        # ❌ v1 refusée
```

Rotation automatique : `vault write transit/keys/orders/config auto_rotate_period=720h`

## 3. Séparation des rôles via les policies

L'appli frontend peut **chiffrer** mais pas déchiffrer ; seul le backend de paiement déchiffre :

```bash
cat > labs/policies/transit-encrypt-only.hcl <<'EOF'
path "transit/encrypt/orders" { capabilities = ["update"] }
EOF
vault policy write transit-encrypt-only - < labs/policies/transit-encrypt-only.hcl
T=$(vault token create -policy=transit-encrypt-only -field=token)

VAULT_TOKEN=$T vault write transit/encrypt/orders plaintext=$(echo -n test | base64)  # ✅
VAULT_TOKEN=$T vault write transit/decrypt/orders ciphertext=$CT2                       # ❌
```

## 4. Signature et HMAC

```bash
vault write transit/keys/signer type=ecdsa-p256
SIG=$(vault write -field=signature transit/sign/signer input=$(echo -n "release-v1.2.3" | base64))
vault write transit/verify/signer input=$(echo -n "release-v1.2.3" | base64) signature=$SIG   # valid=true
vault write transit/verify/signer input=$(echo -n "release-HACKED" | base64) signature=$SIG   # valid=false

# HMAC : empreinte pour comparer/indexer des données sensibles sans les stocker
vault write transit/hmac/orders input=$(echo -n "user@mail.com" | base64)

# Bonus : générer des données aléatoires
vault write -field=random_bytes transit/random/32 format=hex
```

## 5. Chiffrement en lot

```bash
# Les paramètres complexes (tableaux) se passent en JSON sur stdin avec "-"
echo '{"batch_input":[{"plaintext":"YQ=="},{"plaintext":"Yg=="}]}' \
  | vault write -format=json transit/encrypt/orders - | jq .data.batch_results
```

> 🧠 **Transit ou KV ?** KV stocke un secret pour le *redonner* (mot de passe, clé API). Transit ne stocke rien : il *chiffre tes données* qui restent chez toi. Une DB volée ne contient alors que des `vault:v2:...` inutilisables.

## Exercices

1. Crée une clé `exportable=false` (par défaut) et essaie `vault read transit/export/encryption-key/orders`. Pourquoi est-ce refusé ?
2. Utilise une clé `derived=true` avec un `context` (par exemple l'ID client) : le même texte chiffré pour deux clients donne-t-il le même résultat ?
3. Écris un mini script bash qui chiffre chaque ligne d'un fichier CSV (une colonne) et produit un CSV chiffré.
