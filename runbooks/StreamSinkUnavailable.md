# StreamSinkUnavailable

**Severity:** critical &nbsp;·&nbsp; **Summary:** Consumer cannot write to Redis

## What it means
`consumer_store_errors_total` is increasing: Redis writes fail.

## Impact
Nothing is stored, but nothing is lost either: the consumer rewinds to the failed offset and retries with backoff (0.5 s -> 10 s). Lag grows until Redis is back. Consumer pods report not-ready while failing.

## Diagnose
```bash
kubectl --context kind-kafka-sre -n streaming get pods -l app=redis
kubectl --context kind-kafka-sre -n streaming logs deploy/price-indexer --tail=20   # "redis write failed, retrying"
kubectl --context kind-kafka-sre -n streaming exec deploy/redis -- redis-cli ping
```

## Mitigate
- Redis down: bring it back (`make chaos-off` if it was the drill; otherwise check its pod events, memory limit, node).
- Redis full (`OOM command not allowed`): `maxmemory` is 64 MB with `allkeys-lru`, so this should not happen; check the args in `k8s/redis.yaml`.
- After recovery the backlog drains automatically.

## Verify
Store errors stop; consumers READY again; `make lag` falling.

## Practise it
`make chaos-redis`, then `make chaos-off`.
