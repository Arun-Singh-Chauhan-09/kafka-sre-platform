# KafkaNoActiveController

**Severity:** critical &nbsp;·&nbsp; **Summary:** No (or more than one) active Kafka controller

## What it means
`sum(kafka_controller_kafkacontroller_activecontrollercount)` is not exactly 1 for a minute.

## Impact
0: no leader elections, topic changes or partition reassignments; a failure now cannot be healed. 2+: split brain in metrics, usually a short transition.

## Diagnose
```bash
make topics                                                        # do partitions still have leaders?
kubectl --context kind-kafka-sre -n kafka exec kafka-cluster-dual-role-0 -c kafka -- \
  /opt/kafka/bin/kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status
```
`describe --status` shows the leader id, epoch and how far each voter lags.

## Mitigate
- Often caused by nodes restarting at the same time: let the quorum settle (1-2 minutes).
- If a voter is far behind or stuck, restart that pod (one at a time).

## Verify
The metric sums to 1 again; `kafka-metadata-quorum.sh describe --status` shows a LeaderId.

## Practise it
Not automated.
