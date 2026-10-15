# StreamProducerErrors

**Severity:** critical &nbsp;·&nbsp; **Summary:** Produce requests failing

## What it means
More than 1% of the producer's events were not acknowledged by Kafka over 5 minutes.

## Impact
Price updates are being dropped at the source (after 30 s of retries). This is data loss for those updates.

## Diagnose
```bash
kubectl --context kind-kafka-sre -n streaming logs deploy/price-producer --tail=20   # error text from the broker
make status
make urp
```
- `NOT_ENOUGH_REPLICAS`: partitions below min ISR, see [KafkaUnderMinIsrPartitions](KafkaUnderMinIsrPartitions.md) (that alert inhibits this one).
- `Local: Message timed out` / connection errors: brokers unreachable or overloaded.
- `Local: Queue full`: the producer's buffer is full; brokers are too slow to accept.

## Mitigate
Fix the Kafka-side cause first. The producer recovers on its own once the brokers accept writes.

## Verify
Grafana *Producer errors* back to 0.

## Practise it
Not automated; happens with two nodes down.
