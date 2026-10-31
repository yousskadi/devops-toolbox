#!/bin/bash
# Ce script installe kubectl sans nécessiter Docker
# Utile pour se connecter à des clusters Kubernetes externes
set -e

if command -v kubectl &> /dev/null; then
  echo "kubectl déjà installé"
  exit 0
fi

echo "Installation kubectl..."

# Installe kubectl depuis les releases officielles
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

if ! command -v kubectl &> /dev/null; then
  echo "Erreur : kubectl n'a pas été installé correctement"
  exit 1
fi

echo "kubectl installé avec succès"
echo "Utilisation :"
echo "  kubectl version --client"
echo "  kubectl config use-context <context>"
echo "  # Configurez votre kubeconfig pour un cluster externe"