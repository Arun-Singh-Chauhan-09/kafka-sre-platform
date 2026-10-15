# KafkaUnderReplicatedPartitions

**Severity:** warning &nbsp;·&nbsp; **Summary:** Under-replicated partitions

## What it means
Some partitions have fewer in-sync replicas (ISR) than their replication factor (3) for 2 minutes.

## Impact
None yet: data is still on at least `min.insync.replicas` nodes. But the safety margin is gone for those partitions.

## Diagnose
```bash
make urp          # which partitions, which replica is missing from the ISR
make topics       # leaders and ISR for every partition
```
If every URP misses the same broker id, that node is down or slow (see KafkaBrokerDown). If it is spread out, look at network or disk on the nodes (followers cannot fetch fast enough).

## Mitigate
- Node down: see [KafkaBrokerDown](KafkaBrokerDown.md); URP clears when it rejoins.
- Slow follower: check CPU throttling and disk I/O of the node pods (Grafana: *Kubernetes / Compute Resources / Pod*).
- After a long outage, catch-up can take minutes; the count should fall steadily.

## Verify
`make urp` prints `no under-replicated partitions`.

## Practise it
`make chaos-broker`; watch Grafana *Replication health*.
