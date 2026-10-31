#!/usr/bin/env bash
# Monte (ou redémarre) toute la stack : cluster kind + Vault dev + ESO + démo.
# Idempotent : relançable à tout moment, il ne recrée que ce qui manque.
#
# Usage : bash 04-security-secrets/stack/stack-up.sh
# Variables (optionnelles) : CLUSTER_NAME, KIND_IMAGE, ESO_VERSION
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VAULT_DIR="$HERE/../vault"
ESO_DIR="$HERE/../external-secrets"

CLUSTER_NAME="${CLUSTER_NAME:-vault}"
KIND_IMAGE="${KIND_IMAGE:-kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5}"
ESO_VERSION="${ESO_VERSION:-2.14.0}"
NODE="${CLUSTER_NAME}-control-plane"
CTX="kind-${CLUSTER_NAME}"
K="kubectl --context $CTX"
START="$(date +%s)"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }

step "0. Prérequis"
for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null || { echo "  ✘ $bin introuvable"; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "  ✘ Docker ne répond pas (Docker Desktop démarré ?)"; exit 1; }
ok "docker, kind, kubectl, helm"

step "1. Cluster kind '$CLUSTER_NAME'"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  if [ "$(docker inspect -f '{{.State.Running}}' "$NODE")" != "true" ]; then
    docker start "$NODE" >/dev/null
    ok "nœud $NODE redémarré"
  else
    ok "déjà démarré"
  fi
else
  kind create cluster --name "$CLUSTER_NAME" --image "$KIND_IMAGE" --config "$HERE/kind-config.yaml"
  ok "cluster créé"
fi
printf '  attente de l API'
for _ in $(seq 90); do $K get --raw /readyz >/dev/null 2>&1 && break; printf '.'; sleep 2; done; echo
$K wait --for=condition=Ready node --all --timeout=180s >/dev/null
ok "nœud Ready"

step "2. Vault (mode dev, port 8200)"
if docker inspect vault >/dev/null 2>&1; then
  docker start vault >/dev/null
  ok "conteneur vault démarré"
else
  docker compose -f "$VAULT_DIR/docker-compose.yml" up -d
  ok "conteneur vault créé"
fi
# Vault doit joindre l'API du cluster (auth Kubernetes, lab 07)
docker network connect kind vault 2>/dev/null && ok "vault connecté au réseau kind" || ok "vault déjà sur le réseau kind"
# shellcheck source=/dev/null
source "$VAULT_DIR/labs/env.sh"
for _ in $(seq 30); do vault status >/dev/null 2>&1 && break; sleep 1; done
vault status >/dev/null || { echo "  ✘ Vault ne répond pas : docker logs vault"; exit 1; }
ok "Vault descellé"

step "3. External Secrets Operator $ESO_VERSION"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
if helm --kube-context "$CTX" status external-secrets -n external-secrets >/dev/null 2>&1; then
  ok "déjà installé ($(helm --kube-context "$CTX" list -n external-secrets -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["chart"])'))"
else
  helm repo update external-secrets >/dev/null
  helm --kube-context "$CTX" install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace --version "$ESO_VERSION" --wait --timeout 5m >/dev/null
  ok "installé"
fi
$K -n external-secrets rollout status deploy --timeout=180s >/dev/null
ok "pods ESO prêts"

step "4. Démo ESO (namespace demo)"
$K create namespace demo --dry-run=client -o yaml | $K apply -f - >/dev/null
# Token root dans un Secret : acceptable pour la démo uniquement (voir lab 07)
$K -n demo create secret generic vault-token --from-literal=token=root --dry-run=client -o yaml | $K apply -f - >/dev/null
$K apply -f "$ESO_DIR/manifests/secret-store.yaml" \
         -f "$ESO_DIR/manifests/external-secret-dev.yaml" \
         -f "$ESO_DIR/manifests/external-secret-prod.yaml" >/dev/null
ok "ClusterSecretStore et ExternalSecrets appliqués"
KUBECTL_CONTEXT="$CTX" bash "$VAULT_DIR/labs/bootstrap-eso-demo.sh" | sed 's/^/  /'
$K apply -f "$ESO_DIR/manifests/pod.yml" >/dev/null
ok "pod api-consumer appliqué"

step "5. État"
# Les statuts Ready gardés dans etcd peuvent dater d'avant l'arrêt : on attend une synchro
# réussie POSTÉRIEURE au lancement du script, en la forçant régulièrement (ESO peut être
# en backoff s'il a échoué pendant que Vault était arrêté).
synced_since_start() {
  local es="$1" ready t
  ready="$($K -n demo get externalsecret "$es" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)"
  t="$($K -n demo get externalsecret "$es" -o jsonpath='{.status.refreshTime}' 2>/dev/null)"
  [ "$ready" = "True" ] && [ -n "$t" ] && [ "$(date -d "$t" +%s)" -ge "$START" ]
}
printf '  attente de la synchro ESO'
synced=false
for i in $(seq 60); do
  if synced_since_start dev-api-key && synced_since_start prod-api-key; then synced=true; break; fi
  if [ $((i % 5)) -eq 1 ]; then
    $K -n demo annotate externalsecret dev-api-key prod-api-key force-sync="$(date +%s)" --overwrite >/dev/null 2>&1 || true
  fi
  printf '.'; sleep 2
done; echo
$synced && ok "secrets synchronisés depuis Vault" || echo "  ✘ pas de synchro réussie en 2 min : kubectl -n demo describe externalsecret dev-api-key"
$K -n demo get externalsecret
echo
echo "  Vault UI : http://localhost:8200 (token root)"
echo "  Labs     : cd $(cd "$VAULT_DIR" && pwd) && source labs/env.sh"
