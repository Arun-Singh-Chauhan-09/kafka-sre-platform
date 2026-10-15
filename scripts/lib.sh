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

# Drills change the cluster on purpose, so GitOps must not undo them.
# Turning off only selfHeal is not enough: ArgoCD still runs ONE automated
# sync per new git revision, and it does so the moment the app drifts. If
# that revision was never synced before (e.g. a commit that only touched
# other folders), the drill is reverted within a minute. So drills switch
# automated sync off completely, and "chaos off" switches it back on.
set_self_heal() { # application true|false
  local app="$1" value="$2" patch
  argocd_app_exists "$app" || return 0
  if [ "$value" = "true" ]; then
    patch='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
  else
    patch='{"spec":{"syncPolicy":{"automated":null}}}'
  fi
  k -n argocd patch application "$app" --type merge -p "$patch" >/dev/null
  if [ "$value" = "true" ]; then
    info "ArgoCD automated sync for ${app}: on (prune + self-heal)"
  else
    info "ArgoCD automated sync for ${app}: paused (drill in progress)"
  fi
}
