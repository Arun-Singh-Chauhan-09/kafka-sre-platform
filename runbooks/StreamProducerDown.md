# StreamProducerDown

**Severity:** critical &nbsp;·&nbsp; **Summary:** No price producer running

## What it means
Prometheus has no `up == 1` target for `job="price-producer"` for 1 minute.

## Impact
No new price updates enter Kafka. Prices in Redis get older; the consumers sit idle (no lag, but no freshness either).

## Diagnose
```bash
kubectl --context kind-kafka-sre -n streaming get pods -l app=price-producer
kubectl --context kind-kafka-sre -n streaming describe pod -l app=price-producer
kubectl --context kind-kafka-sre -n streaming logs deploy/price-producer --tail=50
```

## Mitigate
- CrashLoopBackOff: read the logs (bad config? cannot reach Kafka?).
- Not ready: the producer turns ready after its first acknowledged event; if Kafka rejects every write, see [StreamProducerErrors](StreamProducerErrors.md).
- Scaled to 0 by hand: ArgoCD self-heal restores the replica count from git.

## Verify
Grafana *Events in / s* back to ~50.

## Practise it
`kubectl --context kind-kafka-sre -n streaming scale deploy/price-producer --replicas=0` (pause ArgoCD self-heal first, see scripts/chaos.sh).
