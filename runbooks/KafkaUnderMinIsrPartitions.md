# KafkaUnderMinIsrPartitions

**Severity:** critical &nbsp;·&nbsp; **Summary:** Partitions below min.insync.replicas: writes failing

## What it means
Some partitions have fewer than 2 in-sync replicas. With `acks=all`, the broker rejects writes to them with `NOT_ENOUGH_REPLICAS`.

## Impact
Producers fail for those partitions (StreamProducerErrors is inhibited by this alert: same incident). Reads still work.

## Diagnose
```bash
make urp          # partitions and their ISR
make status       # how many nodes are up?
```
Usually two nodes are down or both followers of a partition are stuck.

## Mitigate
- Bring nodes back (see [KafkaBrokerDown](KafkaBrokerDown.md)). Writes resume as soon as a second replica is in sync.
- Lowering `min.insync.replicas` to 1 would make writes succeed **but** risks data loss on the next failure. Only as a deliberate, recorded decision, and revert after.

## Verify
Alert resolves; `producer_messages_total{result="error"}` stops increasing.

## Practise it
Not automated (needs two nodes down).
