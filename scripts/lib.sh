#!/usr/bin/env bash
# Shared settings and helpers, sourced by the other scripts.
#
# Every kubectl/helm call goes through k()/h(), which pin the kube context to
# this project's cluster. Other clusters in your kubeconfig are never
# touched, whatever your current context is.

# shellcheck disable=SC2034  # used by the scripts that source this file
CLUSTER="${CLUSTER:-kafka-sre}"
CTX="kind-${CLUSTER}"

KAFKA_NS="kafka"
APPS_NS="streaming"
KAFKA_CLUSTER="kafka-cluster"
BROKER_POD="${KAFKA_CLUSTER}-dual-role-0" # any node works for CLI tools
TOPIC="price-updates"
DLQ_TOPIC="price-updates.dlq"
GROUP="price-indexer"
PRODUCER="price-producer"
CONSUMER="price-indexer"

STRIMZI_VERSION="0.51.0"

GRAFANA_PORT=3030 # all port-forwards
PROM_PORT=9090
ALERTMANAGER_PORT=9093
ARGOCD_PORT=8443

PF_PIDFILE="${TMPDIR:-/tmp}/kafka-sre-portforwards.pids"

k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require() {
  local bin
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "'$bin' is not installed (see README: prerequisites)"
  done
}

port_in_use() { (echo >"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1; }

# Kafka's own CLI tools, run inside a broker pod: nothing to install locally.
kafka_cli() { # tool args...
  local tool="$1"; shift
  k -n "$KAFKA_NS" exec "$BROKER_POD" -c kafka -- "/opt/kafka/bin/${tool}" \
    --bootstrap-server localhost:9092 "$@"
}

argocd_app_exists() { k -n argocd get application "$1" >/dev/null 2>&1; }

set_self_heal() { # application true|false
  local app="$1" value="$2"
  argocd_app_exists "$app" || return 0
  k -n argocd patch application "$app" --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":${value}}}}}" >/dev/null
  info "ArgoCD self-heal for ${app}: ${value}"
}
