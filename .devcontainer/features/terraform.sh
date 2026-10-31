#!/bin/bash

if command -v terraform &> /dev/null; then
  echo "Terraform déjà installé"
  exit 0
fi

echo "Installation Terraform..."

curl -LO https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
unzip -o terraform_1.7.0_linux_amd64.zip

if [ -e /usr/local/bin/terraform ]; then
  if [ -d /usr/local/bin/terraform ]; then
    echo "Suppression du répertoire existant /usr/local/bin/terraform"
    rm -rf /usr/local/bin/terraform
  else
    echo "Suppression du fichier existant /usr/local/bin/terraform"
    rm -f /usr/local/bin/terraform
  fi
fi

install -m 0755 terraform /usr/local/bin/terraform
rm -f terraform terraform_1.7.0_linux_amd64.zip