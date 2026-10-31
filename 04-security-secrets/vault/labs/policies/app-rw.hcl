path "lab/data/app/*" {
  capabilities = ["create", "read", "update", "patch"]
}

path "lab/data/app/root-creds" {
  capabilities = ["deny"]
}
