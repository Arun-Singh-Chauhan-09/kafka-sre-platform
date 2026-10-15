# KafkaConsumerGroupStalled

**Severity:** critical &nbsp;·&nbsp; **Summary:** Consumer group stopped making progress

## What it means
There is lag, and the group's committed offsets have not moved for ~5 minutes.

## Impact
Nothing is being stored. Different from high lag: here the consumers are not slow, they are stuck (or gone).

## Diagnose
```bash
make lag          # "Consumer group has no active members"? -> StreamConsumerDown
make status
```
If members exist but offsets do not move: the consumers are retrying something (Redis down, see StreamSinkUnavailable), deadlocked, or rebalancing in a loop (look for repeated rebalance logs).

## Mitigate
- No members: start the consumers ([StreamConsumerDown](StreamConsumerDown.md)).
- Members but stuck: restart one pod at a time (`kubectl rollout restart deploy/price-indexer`).
- Rebalance loop: check `max.poll.interval.ms` vs processing time per batch.

## Verify
Committed offsets moving again (`make lag`, CURRENT-OFFSET increases).

## Practise it
`make chaos-consumer` (the alert is inhibited by StreamConsumerDown in Alertmanager, but visible in Prometheus).
