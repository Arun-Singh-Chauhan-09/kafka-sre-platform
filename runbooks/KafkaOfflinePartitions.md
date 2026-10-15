# KafkaOfflinePartitions

**Severity:** critical &nbsp;·&nbsp; **Summary:** Offline partitions (no leader)

## What it means
The active controller reports partitions with no live leader.

## Impact
Those partitions can be neither read nor written. Events keyed to them (some hotels) stop flowing.

## Diagnose
```bash
make topics       # look for "Leader: none"
make status
```

## Mitigate
- Restore the nodes that hold the replicas. A leader is elected from the ISR as soon as one replica is back.
- Unclean leader election (`unclean.leader.election.enable`) would bring them online from an out-of-sync replica **and lose data**. Never as a first step.

## Verify
`make topics` shows a leader for every partition; alert resolves.

## Practise it
Not automated.
