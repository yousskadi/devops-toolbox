#!/bin/bash

echo "=============================="
echo "   DevOps Container Menu"
echo "=============================="
echo ""
echo "Choisis les features à installer :"
echo ""

echo "1) Terraform"
echo "2) Helm + Kustomize + kubectl"
echo "3) k3d (cluster Kubernetes local)"
echo "4) Tout installer"
echo "5) kubectl seul (pour clusters externes)"
echo "0) Rien (mode minimal)"
echo ""

read -p "Ton choix (ex: 1 2 3) : " choices

FEATURES=""

for choice in $choices; do
  case $choice in
    1)
      FEATURES="$FEATURES terraform"
      ;;
    2)
      FEATURES="$FEATURES devtools"
      ;;
    3)
      FEATURES="$FEATURES k3d"
      ;;
    4)
      FEATURES="terraform devtools k3d"
      ;;
    5)
      FEATURES="$FEATURES kubectl"
      ;;
    0)
      FEATURES=""
      ;;
    *)
      echo "Choix invalide: $choice"
      ;;
  esac
done

echo ""
echo "Features sélectionnées : $FEATURES"

export FEATURES

bash /workspace/.devcontainer/scripts/bootstrap.sh