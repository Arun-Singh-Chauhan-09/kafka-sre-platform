# Runbooks

One page per alert. Every alert carries a `runbook_url` annotation that
links here, so the page is one click from the notification.

Each runbook answers the same questions in the same order: **what it
means, what users feel, how to diagnose, how to fix, how to confirm it is
fixed, and how to practise it** with a chaos drill.

Commands use the project's kube context, `kubectl --context kind-kafka-sre`,
and the `make` shortcuts (`make lag`, `make urp`, `make topics`, `make dlq`,
`make status`).

## Kafka cluster (kafka/prometheusrule.yaml)

| Alert | Severity | Summary |
|---|---|---|
| [KafkaQuorumLost](KafkaQuorumLost.md) | critical | The KRaft controller quorum is lost |
| [KafkaNoActiveController](KafkaNoActiveController.md) | critical | No (or more than one) active Kafka controller |
| [KafkaUnderMinIsrPartitions](KafkaUnderMinIsrPartitions.md) | critical | Partitions below min.insync.replicas: writes failing |
| [KafkaOfflinePartitions](KafkaOfflinePartitions.md) | critical | Offline partitions (no leader) |
| [KafkaBrokerDown](KafkaBrokerDown.md) | warning | One Kafka node is down |
| [KafkaUnderReplicatedPartitions](KafkaUnderReplicatedPartitions.md) | warning | Under-replicated partitions |

## Pipeline (k8s/prometheusrule.yaml)

| Alert | Severity | Summary |
|---|---|---|
| [StreamProducerDown](StreamProducerDown.md) | critical | No price producer running |
| [StreamConsumerDown](StreamConsumerDown.md) | critical | No price-indexer consumer running |
| [StreamSinkUnavailable](StreamSinkUnavailable.md) | critical | Consumer cannot write to Redis |
| [StreamProducerErrors](StreamProducerErrors.md) | critical | Produce requests failing |
| [KafkaConsumerGroupStalled](KafkaConsumerGroupStalled.md) | critical | Consumer group stopped making progress |
| [KafkaConsumerLagHigh](KafkaConsumerLagHigh.md) | warning | Consumer lag above 1000 events |
| [StreamProcessingErrorsHigh](StreamProcessingErrorsHigh.md) | warning | Many events going to the dead-letter topic |
| [StreamEndToEndLatencyHigh](StreamEndToEndLatencyHigh.md) | warning | p99 produce-to-Redis latency above 5 s |
| [StreamFreshnessBudgetBurn](StreamFreshnessBudgetBurn.md) | warning | Freshness error budget burning fast |

