#!/bin/bash
# Ce script installe k3d, un outil pour créer des clusters Kubernetes locaux
# basés sur K3s et Docker. Idéal pour les tests rapides dans un conteneur.
set -e

if command -v k3d &> /dev/null; then
  echo "k3d déjà installé"
  exit 0
fi

echo "Installation k3d..."

# Vérifie que Docker est accessible
echo "Vérification de l'accès à Docker..."
if ! docker info &> /dev/null; then
  echo "⚠️  Docker n'est pas accessible dans ce conteneur"
  echo "Détails du problème :"

  # Vérifications de diagnostic
  echo "- Socket Docker monté : $(ls -la /var/run/docker.sock 2>/dev/null || echo 'NON')"
  echo "- Docker daemon accessible : $(curl -s --unix-socket /var/run/docker.sock http://localhost/_ping 2>/dev/null || echo 'NON')"
  echo "- Utilisateur actuel : $(whoami)"
  echo "- Groupes : $(groups)"

  echo ""
  echo "Solutions possibles :"
  echo "1. Assurez-vous que Docker Desktop est démarré sur l'hôte"
  echo "2. Vérifiez que le socket Docker est correctement monté"
  echo "3. Redémarrez le conteneur DevContainer"
  echo ""
  echo "Alternatives sans Docker :"
  echo "  bash .devcontainer/scripts/k8s-alternatives.sh"
  echo "  # ou choisissez l'option 5) kubectl seul dans le menu"
  echo ""
  echo "Installation de k3d annulée - Docker requis"
  exit 1
fi

echo "✅ Docker accessible"

# Ajoute l'utilisateur au groupe docker si nécessaire
if ! groups | grep -q docker; then
  echo "Ajout de l'utilisateur au groupe docker..."
  sudo usermod -aG docker $USER 2>/dev/null || true
fi

# Installe k3d via le script officiel
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

if ! command -v k3d &> /dev/null; then
  echo "Erreur : k3d n'a pas été installé correctement"
  exit 1
fi

# Rend les scripts helper exécutables
chmod +x /workspace/.devcontainer/scripts/k3d-helper.sh 2>/dev/null || true
chmod +x /workspace/.devcontainer/scripts/k8s-alternatives.sh 2>/dev/null || true

echo "k3d installé avec succès"
echo "Utilisation :"
echo "  bash .devcontainer/scripts/k3d-helper.sh  # crée un cluster automatiquement"
echo "  ou manuellement :"
echo "  k3d cluster create mycluster"
echo "  k3d kubeconfig merge mycluster --kubeconfig-switch-context"
echo "  kubectl get nodes"