# KafkaConsumerLagHigh

**Severity:** warning &nbsp;·&nbsp; **Summary:** Consumer lag above 1000 events

## What it means
The price-indexer group is more than 1000 events behind the end of `price-updates` for 2 minutes (about 20 s of data at 50 events/s).

## Impact
Prices in Redis are older than they should be. The freshness SLO starts burning if this continues.

## Diagnose
```bash
make lag          # lag per partition: all partitions, or one?
make status
```
- **All partitions lag:** consumers are too slow overall (CPU limit, slow sink, a bad deploy). Compare *produced vs consumed* in Grafana.
- **One or two partitions lag:** a hot key, or one stuck consumer instance (see CONSUMER-ID in `make lag`).
- **Lag and store errors:** see [StreamSinkUnavailable](StreamSinkUnavailable.md).

## Mitigate
- Slow consumers: scale out (up to 6 = number of partitions): change `replicas` in `k8s/consumer.yaml`.
- A recent deploy made processing slower: roll back (`git revert`).
- Traffic spike: lag will drain on its own if consumed > produced; watch the trend before acting.

## Verify
Lag trending down in Grafana; alert resolves below 1000.

## Practise it
`make chaos-slow` or `make chaos-consumer`.
