#!/usr/bin/env bash
# Break the pipeline on purpose and watch the platform notice.
#
#   scripts/chaos.sh broker      kill one Kafka node -> under-replicated partitions,
#                                KafkaBrokerDown; Strimzi brings it back by itself
#   scripts/chaos.sh consumer    scale consumers to 0 -> lag grows,
#                                StreamConsumerDown + KafkaConsumerLagHigh
#   scripts/chaos.sh slow        150 ms extra per event -> consumers fall behind,
#                                StreamEndToEndLatencyHigh, freshness budget burn
#   scripts/chaos.sh errors      20% of events fail -> DLQ, StreamProcessingErrorsHigh
#   scripts/chaos.sh redis       stop Redis -> StreamSinkUnavailable; events are
#                                retried, not lost (lag grows, then drains)
#   scripts/chaos.sh off         undo all of the above, re-enable GitOps self-heal
#
# Drills that change a Deployment pause ArgoCD self-heal first; otherwise
# ArgoCD would restore the git state within seconds and no alert would fire.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }
case "${1:-}" in
  broker | consumer | slow | errors | redis | off) ;;
  *) usage; exit 1 ;;
esac

require kubectl
k get namespace "$APPS_NS" >/dev/null 2>&1 || die "namespace $APPS_NS not found; run scripts/setup.sh first"

mode="${1:-}"
case "$mode" in
  broker)
    pod="${KAFKA_CLUSTER}-dual-role-${2:-2}"
    info "before:"
    kafka_cli kafka-topics.sh --describe --topic "$TOPIC" | sed 's/^/      /'
    k -n "$KAFKA_NS" delete pod "$pod" --wait=false
    info "deleted $pod. Leadership moves to the other nodes; its replicas drop out of the ISR."
    info "Watch: make urp (under-replicated partitions), Grafana 'Replication health'."
    info "Strimzi recreates the pod; it catches up and rejoins the ISR on its own."
    k -n "$KAFKA_NS" get pods -l strimzi.io/cluster="$KAFKA_CLUSTER" -w
    ;;
  consumer)
    set_self_heal streaming-apps false
    k -n "$APPS_NS" scale deployment/"$CONSUMER" --replicas=0
    info "consumers gone. Lag grows by ~50 events/s; alerts after 1-3 minutes."
    info "Watch: make lag, Grafana 'Consumer lag by partition'"
    ;;
  slow)
    ms="${2:-150}"
    set_self_heal streaming-apps false
    k -n "$APPS_NS" set env deployment/"$CONSUMER" PROCESSING_DELAY_MS="$ms"
    k -n "$APPS_NS" rollout status deployment/"$CONSUMER" --timeout=180s
    info "PROCESSING_DELAY_MS=$ms: 3 consumers now handle ~$((3 * 1000 / ms)) events/s, the producer sends 50."
    info "Watch: lag climbing, end-to-end latency crossing the 5 s line"
    ;;
  errors)
    rate="${2:-0.2}"
    set_self_heal streaming-apps false
    k -n "$APPS_NS" set env deployment/"$CONSUMER" FAILURE_RATE="$rate"
    k -n "$APPS_NS" rollout status deployment/"$CONSUMER" --timeout=180s
    info "FAILURE_RATE=$rate: failed events go to $DLQ_TOPIC, the partition keeps moving."
    info "Inspect them: make dlq"
    ;;
  redis)
    set_self_heal streaming-apps false
    k -n "$APPS_NS" scale deployment/redis --replicas=0
    info "Redis gone. Consumers retry with backoff instead of skipping events."
    info "Watch: StreamSinkUnavailable, consumer pods turning 0/1 READY, lag growing"
    ;;
  off)
    k -n "$APPS_NS" set env deployment/"$CONSUMER" FAILURE_RATE=0 PROCESSING_DELAY_MS=0 >/dev/null
    k -n "$APPS_NS" scale deployment/redis --replicas=1 >/dev/null
    k -n "$APPS_NS" scale deployment/"$CONSUMER" --replicas=3 >/dev/null
    set_self_heal streaming-apps true
    k -n "$APPS_NS" rollout status deployment/redis --timeout=180s
    k -n "$APPS_NS" rollout status deployment/"$CONSUMER" --timeout=180s
    info "back to normal. Lag drains within a minute; alerts resolve once their windows are clean."
    ;;
esac
