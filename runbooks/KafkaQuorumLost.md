# KafkaQuorumLost

**Severity:** critical &nbsp;·&nbsp; **Summary:** The KRaft controller quorum is lost

## What it means
Fewer than 2 of the 3 nodes are up. KRaft needs a majority of controllers (2 of 3) to elect leaders and accept metadata changes.

## Impact
Severe: partitions cannot get new leaders, producers fail, consumers stop. This is an outage of the whole pipeline.

## Diagnose
```bash
kubectl --context kind-kafka-sre -n kafka get pods -l strimzi.io/cluster=kafka-cluster
kubectl --context kind-kafka-sre -n kafka get events --sort-by=.lastTimestamp | tail -20
kubectl --context kind-kafka-sre get nodes                                                     # lost a Kubernetes node?
kubectl --context kind-kafka-sre -n kafka logs deploy/strimzi-cluster-operator | tail -50
```

## Mitigate
- Get any two nodes running first; quorum returns as soon as 2 controllers see each other.
- If pods are Pending for capacity: free resources or add a node.
- If pods crash-loop: read `--previous` logs (disk full? corrupted metadata?). Escalate before touching PVCs.

## Verify
`KafkaQuorumLost` resolves; `kafka_controller_kafkacontroller_activecontrollercount` sums to 1; producer errors stop.

## Practise it
Not automated (it takes the whole cluster down). On a spare cluster: delete two node pods at once.
