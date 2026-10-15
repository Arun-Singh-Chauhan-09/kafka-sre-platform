#!/usr/bin/env bash
# Everyday Kafka operations, using the CLI tools inside a broker pod.
#
#   scripts/kafka.sh lag        consumer group: offsets and lag per partition
#   scripts/kafka.sh topics     topic layout: partitions, leaders, replicas, ISR
#   scripts/kafka.sh urp        only partitions that are under-replicated
#   scripts/kafka.sh dlq [N]    read the last N events from the dead-letter topic
#   scripts/kafka.sh tail [N]   read N live events from price-updates
#   scripts/kafka.sh redis      a few stored prices from Redis
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

case "${1:-}" in
  lag)
    kafka_cli kafka-consumer-groups.sh --describe --group "$GROUP"
    ;;
  topics)
    kafka_cli kafka-topics.sh --describe --topic "$TOPIC"
    kafka_cli kafka-topics.sh --describe --topic "$DLQ_TOPIC"
    ;;
  urp)
    out="$(kafka_cli kafka-topics.sh --describe --under-replicated-partitions)"
    if [ -n "$out" ]; then echo "$out"; else echo "no under-replicated partitions"; fi
    ;;
  dlq)
    n="${2:-5}"
    # Read from the start; headers show why each event failed and where it came from.
    kafka_cli kafka-console-consumer.sh --topic "$DLQ_TOPIC" --from-beginning \
      --max-messages "$n" --timeout-ms 10000 \
      --property print.headers=true --property print.key=true 2>/dev/null || true
    ;;
  tail)
    n="${2:-5}"
    kafka_cli kafka-console-consumer.sh --topic "$TOPIC" \
      --max-messages "$n" --timeout-ms 10000 --property print.key=true 2>/dev/null || true
    ;;
  redis)
    # shellcheck disable=SC2016  # $key expands inside the pod, not here
    k -n "$APPS_NS" exec deploy/redis -- sh -c \
      'redis-cli dbsize; for key in $(redis-cli --scan --pattern "price:*" --count 100 | head -3); do echo "$key"; redis-cli hgetall "$key"; done'
    ;;
  *)
    # Print the comment header (everything up to the first non-comment line).
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 1
    ;;
esac
