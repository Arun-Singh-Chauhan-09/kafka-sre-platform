# StreamConsumerDown

**Severity:** critical &nbsp;·&nbsp; **Summary:** No price-indexer consumer running

## What it means
Prometheus has no `up == 1` target for `job="price-indexer"` for 1 minute.

## Impact
Nothing is stored in Redis; events accumulate in Kafka. No data is lost while the backlog is inside the topic's 24 h retention. Lag, stall and freshness alerts are inhibited: this is the cause.

## Diagnose
```bash
kubectl --context kind-kafka-sre -n streaming get deploy price-indexer          # replicas wanted vs ready
kubectl --context kind-kafka-sre -n streaming get pods -l app=price-indexer
kubectl --context kind-kafka-sre -n streaming logs deploy/price-indexer --tail=50
make lag                                            # how big is the backlog?
```

## Mitigate
- Scaled to 0: `make chaos-off`, or let ArgoCD self-heal restore 3 replicas.
- Crash-looping: logs; roll back with `git revert` of the last change to `k8s/` (ArgoCD deploys the revert).
- Once running, the backlog drains at the consumers' spare capacity; watch lag fall.

## Verify
`make lag` shows LAG falling to near 0 on all 6 partitions.

## Practise it
`make chaos-consumer`, then `make chaos-off`.
