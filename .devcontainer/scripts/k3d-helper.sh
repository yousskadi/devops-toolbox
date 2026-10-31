#!/bin/bash
# Script d'aide pour utiliser k3d dans le conteneur DevContainer
# Ce script facilite la création et la gestion de clusters k3d

set -e

CLUSTER_NAME=${1:-"dev"}

echo "=== Gestionnaire k3d pour DevContainer ==="
echo ""

# Fonction pour créer un cluster
create_cluster() {
    local name=$1
    echo "Création du cluster k3d '$name'..."

    # Vérifie que k3d est installé
    if ! command -v k3d &> /dev/null; then
        echo "Erreur : k3d n'est pas installé"
        echo "Installez d'abord k3d via le menu principal (option 3)"
        exit 1
    fi

    if k3d cluster list | grep -q "^$name"; then
        echo "Le cluster '$name' existe déjà. Suppression..."
        k3d cluster delete "$name"
    fi

    k3d cluster create "$name" \
        --agents 1 \
        --k3s-arg "--disable=traefik@server:0" \
        --wait

    echo "Cluster '$name' créé avec succès"
    echo ""

    # Configure kubectl
    echo "Configuration de kubectl..."
    k3d kubeconfig merge "$name" --kubeconfig-switch-context

    echo ""
    echo "=== Cluster prêt ! ==="
    kubectl get nodes
    echo ""
    echo "Commandes utiles :"
    echo "  kubectl get pods -A"
    echo "  kubectl get services -A"
    echo "  k3d cluster delete $name  # pour supprimer le cluster"
}

# Fonction pour supprimer un cluster
delete_cluster() {
    local name=$1

    # Vérifie que k3d est installé
    if ! command -v k3d &> /dev/null; then
        echo "Erreur : k3d n'est pas installé"
        exit 1
    fi

    echo "Suppression du cluster '$name'..."
    k3d cluster delete "$name"
    echo "Cluster supprimé"
}

# Fonction pour lister les clusters
list_clusters() {
    # Vérifie que k3d est installé
    if ! command -v k3d &> /dev/null; then
        echo "Erreur : k3d n'est pas installé"
        echo "Installez d'abord k3d via le menu principal (option 3)"
        exit 1
    fi

    echo "Clusters k3d existants :"
    k3d cluster list
}

# Menu principal
case "${2:-create}" in
    create)
        create_cluster "$CLUSTER_NAME"
        ;;
    delete)
        delete_cluster "$CLUSTER_NAME"
        ;;
    list)
        list_clusters
        ;;
    *)
        echo "Usage: $0 [cluster_name] [create|delete|list]"
        echo "Exemples:"
        echo "  $0                    # crée cluster 'dev'"
        echo "  $0 mycluster create   # crée cluster 'mycluster'"
        echo "  $0 mycluster delete   # supprime cluster 'mycluster'"
        echo "  $0 list               # liste les clusters"
        exit 1
        ;;
esac