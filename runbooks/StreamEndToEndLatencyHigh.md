# StreamEndToEndLatencyHigh

**Severity:** warning &nbsp;·&nbsp; **Summary:** p99 produce-to-Redis latency above 5 s

## What it means
For 3 minutes, the slowest 1% of events took more than 5 s from creation by the producer to being stored in Redis.

## Impact
Users may see prices that are more than 5 s old. The freshness SLO is at risk.

## Diagnose
Latency = time waiting in Kafka (lag) + processing time.
```bash
make lag          # high lag -> consumers too slow (most common)
```
Grafana: *Producer acknowledgement latency* high -> the brokers are slow; *Consumer results* shows retries -> Redis.

## Mitigate
Same as [KafkaConsumerLagHigh](KafkaConsumerLagHigh.md): add consumers (max 6), roll back a slow release, fix the slow dependency.

## Verify
p99 under the 5 s line in Grafana *End-to-end latency*.

## Practise it
`make chaos-slow`.
