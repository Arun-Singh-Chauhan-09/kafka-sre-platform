#!/usr/bin/env bash
# One screen: Kafka health, apps, consumer lag, ArgoCD sync, firing alerts.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

step "Kafka cluster ($KAFKA_NS)"
k -n "$KAFKA_NS" get kafka "$KAFKA_CLUSTER" 2>/dev/null || die "cluster not found; run scripts/setup.sh"
k -n "$KAFKA_NS" get pods -l strimzi.io/cluster="$KAFKA_CLUSTER" -o wide

step "Topics"
k -n "$KAFKA_NS" get kafkatopics

step "Apps ($APPS_NS)"
k -n "$APPS_NS" get pods -o wide
k -n "$APPS_NS" get deployment "$CONSUMER" -o jsonpath='    image: {.spec.template.spec.containers[0].image}{"\n"}'

step "Consumer group $GROUP"
kafka_cli kafka-consumer-groups.sh --describe --group "$GROUP" 2>/dev/null || info "not available (brokers starting?)"

step "ArgoCD"
if argocd_app_exists streaming-apps; then
  k -n argocd get applications \
    -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision,SELF-HEAL:.spec.syncPolicy.automated.selfHeal'
else
  info "no ArgoCD applications (SKIP_ARGOCD=1, or the repo is not pushed yet)"
fi

step "Alerts firing (via Prometheus on localhost:${PROM_PORT})"
if json="$(curl -fsS --max-time 5 "http://localhost:${PROM_PORT}/api/v1/alerts" 2>/dev/null)"; then
  printf '%s' "$json" | python3 -c '
import json, sys
alerts = [a for a in json.load(sys.stdin)["data"]["alerts"]
          if a["labels"].get("alertname") not in ("Watchdog", "InfoInhibitor")]
if not alerts:
    print("    none")
for a in sorted(alerts, key=lambda a: a["state"]):
    labels = a["labels"]
    # %-formatting, not f-strings: works on every Python 3 (Ubuntu 22.04 ships 3.10)
    print("    %-8s %-8s %-32s %s" % (
        a["state"],
        labels.get("severity", "-"),
        labels["alertname"],
        a["annotations"].get("summary", ""),
    ))
'
else
  info "Prometheus not reachable; re-run scripts/setup.sh to restart port-forwards"
fi
