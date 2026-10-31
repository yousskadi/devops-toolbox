#!/bin/bash

set -e


if [ -z "$FEATURES" ]; then
  echo "Aucune feature définie, rien à installer."
  exit 0
fi

echo "Features demandées: $FEATURES"

for feature in $FEATURES; do
  SCRIPT="/workspace/.devcontainer/features/${feature}.sh"

  if [ -f "$SCRIPT" ]; then
    echo "Activation de $feature"
    bash "$SCRIPT"
  else
    echo "Feature inconnue: $feature"
  fi
done