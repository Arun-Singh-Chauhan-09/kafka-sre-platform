# KafkaBrokerDown

**Severity:** warning &nbsp;·&nbsp; **Summary:** One Kafka node is down

## What it means
Fewer than 3 of the 3 KRaft nodes (`kafka-cluster-dual-role-0..2`) answer Prometheus scrapes for 1 minute.

## Impact
None yet for users. Leadership has moved to the remaining nodes; with replication 3 and `min.insync.replicas=2`, writes with `acks=all` still succeed. One more failure would stop writes to some partitions.

## Diagnose
```bash
kubectl --context kind-kafka-sre -n kafka get pods -l strimzi.io/cluster=kafka-cluster      # which node, what state?
kubectl --context kind-kafka-sre -n kafka describe pod kafka-cluster-dual-role-N              # events: OOMKilled? Pending? image pull?
kubectl --context kind-kafka-sre -n kafka logs kafka-cluster-dual-role-N -c kafka --previous  # why did the last run end?
make urp                                                          # partitions waiting for this node
```
Common causes: OOMKilled (memory limit too low for heap + page cache), the node it was scheduled on is gone, a PVC that cannot attach, a rolling restart by Strimzi (expected, short).

## Mitigate
- Restarting or rescheduling: wait; Strimzi recreates the pod from its StrimziPodSet and the node rejoins the ISR on its own.
- OOMKilled: raise `resources.limits.memory` in `kafka/kafka.yaml` (pull request; ArgoCD applies it, Strimzi rolls one node at a time).
- Pending: check node capacity (`kubectl describe node`) and PVC events.
- Do **not** delete the PVC: the node would have to re-replicate everything.

## Verify
Grafana *Kafka nodes up* back to 3; `make urp` prints `no under-replicated partitions`.

## Practise it
`make chaos-broker` (the pod usually returns within 1-2 minutes, so the alert may resolve before it fires: that is the self-healing working).
