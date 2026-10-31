# Lire les secrets de l'appli
path "lab/data/app/*" {
  capabilities = ["read"]
}

# Lister les secrets de l'appli
path "lab/metadata/app/*" {
  capabilities = ["list", "read"]
}
