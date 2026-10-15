# StreamProcessingErrorsHigh

**Severity:** warning &nbsp;·&nbsp; **Summary:** Many events going to the dead-letter topic

## What it means
More than 5% of consumed events were invalid or failed processing over 5 minutes, and were parked on `price-updates.dlq`.

## Impact
Those hotels' prices are not updated. The partitions keep moving (one bad event does not block the others).

## Diagnose
```bash
make dlq          # last events in the DLQ, with headers: dlq.reason, dlq.source (topic/partition/offset)
```
- Same reason on every event (`not JSON`, `missing fields`): a producer released a contract change, or the consumer has a bug.
- `injected failure (FAILURE_RATE)`: someone left the drill on: `make chaos-off`.

## Mitigate
- Roll back the release that introduced the bad events or the bug.
- After the fix, replay the DLQ into the main topic (the headers say where each event came from).

## Verify
Error ratio back under 5%; DLQ events/min in Grafana back to 0.

## Practise it
`make chaos-errors`, then `make dlq`, then `make chaos-off`.
