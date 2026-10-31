# Lab 06 : PKI, ta propre autorité de certification

**Objectif :** émettre des certificats TLS **courts** (heures ou jours) à la demande, au lieu de certificats d'un an gérés à la main.

## 🎯 Comprendre avant de pratiquer

**En une phrase :** Vault devient **ta propre autorité de certification** et délivre des certificats TLS en quelques millisecondes, avec des **durées courtes** (heures ou jours).

**Analogie, la préfecture express :** au lieu d'une carte d'identité valable 10 ans (qu'un voleur peut utiliser 10 ans), tu reçois une carte **valable 24 h**, renouvelée automatiquement chaque matin. Volée, elle ne sert plus à rien le lendemain.

**Exemple concret :**
```
Lab Root CA (10 ans, gardée hors ligne en vrai)
 └── Lab Intermediate CA (5 ans, dans Vault)
      ├── api.shop.svc.cluster.local      (24 h)  ← mTLS entre microservices
      ├── grafana.internal.lab.local      (72 h)  ← renouvelé par cert-manager
      └── db-replica-2.internal           (24 h)
```

**À quoi ça sert en prod :**
- **mTLS entre services** : chaque microservice prouve son identité et le trafic interne est chiffré (zero trust).
- **Certificats internes** pour les noms que Let's Encrypt ne peut pas valider (`*.svc.cluster.local`, `*.internal`).
- **Fin des pannes « certificat expiré »** oublié dans un coin : tout est automatisé et court.
- **Révocation presque inutile** : un certificat de 24 h volé expire tout seul.
- Intégration avec **cert-manager** (Kubernetes), **Vault Agent**, **Consul** et les service mesh.

**Pièges en prod :**
- Les clients doivent faire **confiance à ta CA racine** : il faut la distribuer dans les trust stores (OS, conteneurs, navigateurs internes).
- On ne signe jamais de certificats finaux avec la **racine** : on passe par une intermédiaire, et la racine reste idéalement hors ligne.
- Lance `tidy` régulièrement, sinon le stockage et la CRL grossissent sans fin.

```bash
source labs/env.sh
```

## 1. CA racine

```bash
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki        # 10 ans max pour la racine

vault write -field=certificate pki/root/generate/internal \
  common_name="Lab Root CA" issuer_name=root-2026 ttl=87600h

vault read -field=certificate pki/cert/ca > labs/root-ca.crt     # récupérer la CA à tout moment
openssl x509 -in labs/root-ca.crt -noout -subject -dates

vault write pki/config/urls \
  issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" \
  crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"
```

## 2. CA intermédiaire (la bonne pratique)

On ne signe jamais de certificats serveur avec la racine : on crée une intermédiaire signée par la racine.

```bash
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int

# 1) l'intermédiaire génère un CSR
vault write -field=csr pki_int/intermediate/generate/internal common_name="Lab Intermediate CA" > labs/int.csr

# 2) la racine le signe
vault write -field=certificate pki/root/sign-intermediate csr="$(cat labs/int.csr)" format=pem_bundle ttl=43800h > labs/int-signed.pem

# 3) on importe le certificat signé dans l'intermédiaire
vault write pki_int/intermediate/set-signed certificate="$(cat labs/int-signed.pem)"
vault read -field=certificate pki_int/cert/ca > labs/int.crt
```

## 3. Rôle et émission de certificats

```bash
vault write pki_int/roles/lab-local \
  allowed_domains=lab.local allow_subdomains=true max_ttl=72h

vault write -format=json pki_int/issue/lab-local common_name=web.lab.local ttl=1h > labs/web.json
jq -r .data.certificate labs/web.json > labs/web.crt
jq -r .data.private_key labs/web.json > labs/web.key
jq -r .data.serial_number labs/web.json

openssl x509 -in labs/web.crt -noout -subject -issuer -dates
openssl verify -CAfile labs/root-ca.crt -untrusted labs/int.crt labs/web.crt   # web.crt: OK

# Hors de la liste autorisée → refusé
vault write pki_int/issue/lab-local common_name=evil.com     # ❌
```

## 4. Tester un vrai serveur TLS

```bash
# -cert_chain : le serveur doit envoyer l'intermédiaire, le client n'a que la racine
openssl s_server -cert labs/web.crt -cert_chain labs/int.crt -key labs/web.key -accept 8443 -www &
sleep 1
curl --cacert labs/root-ca.crt --resolve web.lab.local:8443:127.0.0.1 https://web.lab.local:8443 | head -3
kill %1
```

## 5. Révocation

```bash
SERIAL=$(jq -r .data.serial_number labs/web.json)
vault write pki_int/revoke serial_number=$SERIAL
curl -s $VAULT_ADDR/v1/pki_int/crl/pem | openssl crl -noout -text | grep -A1 Serial

# Nettoyage des certificats expirés
vault write pki_int/tidy tidy_cert_store=true tidy_revoked_certs=true safety_buffer=1m
```

> 🧠 Avec des certificats d'1 h renouvelés automatiquement (par cert-manager, Vault Agent…), la révocation devient presque inutile : un certificat volé expire tout seul. C'est le même principe que les secrets dynamiques.

## 6. Pour aller plus loin : cert-manager + Vault dans kind

cert-manager peut utiliser Vault comme `Issuer` pour fournir des certificats aux Ingress. Une fois le lab 07 fait (auth Kubernetes), c'est un très bon exercice : https://cert-manager.io/docs/configuration/vault/

## Exercices

1. Crée un rôle `internal-svc` qui autorise `*.svc.cluster.local` pour 24 h maximum et émets un certificat pour `api.demo.svc.cluster.local`.
2. Émets un certificat avec un SAN IP (`ip_sans=127.0.0.1`).
3. Signe un CSR généré **localement** avec openssl (`pki_int/sign/lab-local`) : la clé privée ne passe jamais par Vault.
4. Nettoyage : `rm -f labs/*.crt labs/*.key labs/*.json labs/*.csr labs/*.pem`.
