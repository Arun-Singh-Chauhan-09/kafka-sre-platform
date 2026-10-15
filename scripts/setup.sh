#!/usr/bin/env bash
# One command from nothing to a running, observed, GitOps-managed Kafka
# pipeline on a local kind cluster:
#
#   cluster -> image -> monitoring -> logs -> Strimzi -> Kafka -> apps
#           -> GitOps -> access -> verify
#
# Safe to re-run: every step is idempotent (helm upgrade --install, kubectl
# apply), so running it again repairs a half-finished setup or restarts the
# port-forwards after a reboot.
#
# Options (environment variables):
#   SKIP_LOKI=1            no Loki/Promtail (saves ~300 MB of RAM)
#   SKIP_ARGOCD=1          deploy with kubectl only, no ArgoCD
#   ARGOCD_VERSION=v3.x.y  pin ArgoCD (default: stable)

set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

SKIP_LOKI="${SKIP_LOKI:-0}"
SKIP_ARGOCD="${SKIP_ARGOCD:-0}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
IMAGE_NAME="$(awk '/newName:/ {print $2}' k8s/kustomization.yaml)"
IMAGE_TAG="$(awk '/newTag:/ {print $2}' k8s/kustomization.yaml)"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
REPO_URL="$(awk '/repoURL:/ {print $2}' argocd/streaming-apps.yaml)"

require docker kind kubectl helm curl
docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop)"

# Two full stacks don't fit in a laptop's memory, and they share ports.
for other in $(kind get clusters 2>/dev/null); do
  [ "$other" = "$CLUSTER" ] && continue
  for node in $(kind get nodes --name "$other" 2>/dev/null); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$node" 2>/dev/null)" = "true" ]; then
      die "kind cluster '$other' is running. Pause it first:  docker stop \$(kind get nodes --name $other)"
    fi
  done
done

# ---------------------------------------------------------------------------
step "1/10 Cluster '$CLUSTER'"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  info "already exists, reusing"
  # A cluster paused with 'docker stop' is still listed by kind: start it.
  for node in $(kind get nodes --name "$CLUSTER"); do
    [ "$(docker inspect -f '{{.State.Running}}' "$node")" = "true" ] || { info "starting $node"; docker start "$node" >/dev/null; }
  done
elif command -v terraform >/dev/null 2>&1; then
  info "creating with Terraform (infra/local-kind)"
  terraform -chdir=infra/local-kind init -input=false >/dev/null
  terraform -chdir=infra/local-kind apply -auto-approve -input=false
else
  info "Terraform not found, creating with kind directly"
  kind create cluster --config infra/local-kind/kind-config.yaml
fi
kind export kubeconfig --name "$CLUSTER" >/dev/null # adds context $CTX
k wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
info "context: $CTX"

# ---------------------------------------------------------------------------
step "2/10 Build image $IMAGE and load it into the cluster"
# The tag comes from k8s/kustomization.yaml, the same tag ArgoCD deploys, so
# the first run needs no registry at all.
docker build --build-arg VERSION="$IMAGE_TAG" -t "$IMAGE" ./app
kind load docker-image "$IMAGE" --name "$CLUSTER"

# ---------------------------------------------------------------------------
step "3/10 Monitoring: Prometheus, Alertmanager, Grafana (takes a few minutes)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
helm repo add strimzi https://strimzi.io/charts/ >/dev/null 2>&1 || true
helm repo update >/dev/null
h upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values platform/kube-prometheus-values.yaml \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
if [ "$SKIP_LOKI" = "1" ]; then
  step "4/10 Logs skipped (SKIP_LOKI=1)"
else
  step "4/10 Logs: Loki + Promtail"
  h upgrade --install loki grafana/loki-stack \
    --namespace monitoring \
    --values platform/loki-values.yaml \
    --wait --timeout 5m
fi

# ---------------------------------------------------------------------------
step "5/10 Strimzi operator $STRIMZI_VERSION (manages Kafka on Kubernetes)"
# The namespace comes from git (kafka/namespace.yaml) so its Pod Security
# labels are in place before the operator starts.
k apply -f kafka/namespace.yaml >/dev/null
h upgrade --install strimzi strimzi/strimzi-kafka-operator \
  --version "$STRIMZI_VERSION" \
  --namespace "$KAFKA_NS" \
  --values platform/strimzi-values.yaml \
  --wait --timeout 5m

# ---------------------------------------------------------------------------
step "6/10 Kafka: 3 KRaft nodes, topics, metrics, alerts (first start: 3-5 minutes)"
# Applied directly first so Kafka runs even before the repo is on GitHub.
# ArgoCD (step 8) then adopts these resources and owns them from git.
k apply -k kafka
k -n "$KAFKA_NS" wait kafka/"$KAFKA_CLUSTER" --for=condition=Ready --timeout=900s
k -n "$KAFKA_NS" wait kafkatopic --all --for=condition=Ready --timeout=180s
info "cluster ready: $(k -n "$KAFKA_NS" get pods -l strimzi.io/cluster="$KAFKA_CLUSTER" --no-headers | wc -l | tr -d ' ') pods"

# ---------------------------------------------------------------------------
step "7/10 Apps: Redis, producer, consumers, dashboard, alerts"
k apply -k k8s
k -n "$APPS_NS" rollout status deployment/redis --timeout=180s
k -n "$APPS_NS" rollout status deployment/"$PRODUCER" --timeout=180s
k -n "$APPS_NS" rollout status deployment/"$CONSUMER" --timeout=180s

# ---------------------------------------------------------------------------
if [ "$SKIP_ARGOCD" = "1" ]; then
  step "8/10 ArgoCD skipped (SKIP_ARGOCD=1)"
else
  step "8/10 GitOps: ArgoCD ($ARGOCD_VERSION)"
  k create namespace argocd --dry-run=client -o yaml | k apply -f - >/dev/null
  # --server-side: the ArgoCD CRDs are too large for client-side apply.
  k apply --server-side --force-conflicts -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml" >/dev/null
  k -n argocd rollout status deployment/argocd-server --timeout=300s
  if git ls-remote "$REPO_URL" >/dev/null 2>&1; then
    k apply -f argocd/kafka-cluster.yaml -f argocd/streaming-apps.yaml
    info "ArgoCD now syncs $REPO_URL (kafka/ and k8s/)"
  else
    info "Repo $REPO_URL is not reachable yet, so ArgoCD has nothing to sync."
    info "Push the project to GitHub, then run:"
    info "  kubectl --context $CTX apply -f argocd/"
  fi
fi

# ---------------------------------------------------------------------------
step "9/10 Port-forwards"
: >"$PF_PIDFILE"
start_pf() { # description local-port namespace service remote-port
  local desc="$1" lport="$2" ns="$3" svc="$4" rport="$5"
  if port_in_use "$lport"; then
    info "$desc: port $lport already in use, skipped (stop the other process first)"
    return
  fi
  k port-forward -n "$ns" "svc/$svc" "$lport:$rport" >/dev/null 2>&1 &
  echo $! >>"$PF_PIDFILE"
  info "$desc -> localhost:$lport (pid $!)"
}
start_pf "Grafana     " "$GRAFANA_PORT" monitoring monitoring-grafana 80
start_pf "Prometheus  " "$PROM_PORT" monitoring monitoring-kube-prometheus-prometheus 9090
start_pf "Alertmanager" "$ALERTMANAGER_PORT" monitoring monitoring-kube-prometheus-alertmanager 9093
if [ "$SKIP_ARGOCD" != "1" ]; then
  start_pf "ArgoCD      " "$ARGOCD_PORT" argocd argocd-server 443
fi

# ---------------------------------------------------------------------------
step "10/10 Verify"
for pair in "$GRAFANA_PORT:Grafana" "$PROM_PORT:Prometheus" "$ALERTMANAGER_PORT:Alertmanager"; do
  # kubectl port-forward needs a moment to open its port: retry up to 15s.
  up=0
  for _ in $(seq 1 15); do
    if port_in_use "${pair%%:*}"; then up=1; break; fi
    sleep 1
  done
  if [ "$up" = "1" ]; then
    info "${pair##*:} listening on ${pair%%:*}"
  else
    info "${pair##*:} NOT reachable on ${pair%%:*}"
  fi
done
info "consumer group (give it ~30 s after the first start):"
kafka_cli kafka-consumer-groups.sh --describe --group "$GROUP" 2>/dev/null | sed 's/^/      /' || info "group not visible yet"

ARGO_PW="(ArgoCD skipped)"
if [ "$SKIP_ARGOCD" != "1" ]; then
  ARGO_PW="$(k -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '(not ready yet)')"
fi

cat <<EOF

======================================================================
 Ready. Endpoints:
======================================================================
  Grafana       http://localhost:${GRAFANA_PORT}        admin / admin
                -> Dashboards -> "Kafka SRE - Price Pipeline"
  Prometheus    http://localhost:${PROM_PORT}/alerts
  Alertmanager  http://localhost:${ALERTMANAGER_PORT}
  ArgoCD        https://localhost:${ARGOCD_PORT}       admin / ${ARGO_PW}

 Next:
  make status              pods, Kafka health, lag, firing alerts
  make lag                 consumer group lag per partition
  make chaos-consumer      stop the consumers -> lag + KafkaConsumerLagHigh
  make chaos-broker        kill a Kafka node   -> URP, then self-healing
  make chaos-off           undo every drill (ArgoCD restores git state)
  make down                delete the cluster and everything in it
======================================================================
EOF
