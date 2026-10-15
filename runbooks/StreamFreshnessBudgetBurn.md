# StreamFreshnessBudgetBurn

**Severity:** warning &nbsp;·&nbsp; **Summary:** Freshness error budget burning fast

## What it means
Over **both** the last hour and the last 5 minutes, more than 14.4% of events took longer than 5 s to reach Redis. The SLO allows 1%; at this rate a 30-day budget is gone in about 2 days.

## Impact
A sustained freshness problem, not a blip: the 1 h window proves it lasted, the 5 m window proves it is still happening.

## Diagnose
Start with [StreamEndToEndLatencyHigh](StreamEndToEndLatencyHigh.md) and [KafkaConsumerLagHigh](KafkaConsumerLagHigh.md); this alert tells you *how much* it matters, they tell you *why*.

## Mitigate
Fix the underlying slowness. The 5 m window clears within minutes of the fix, so the alert resolves quickly.

## Verify
Grafana *Freshness SLI (5m)* back above 99%.

## Practise it
`make chaos-slow` and wait ~10 minutes (the 1 h window has to accumulate 14.4% slow events).
