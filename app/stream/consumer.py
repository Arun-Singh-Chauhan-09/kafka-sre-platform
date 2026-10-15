"""Consumer: reads price updates and keeps the latest price per hotel in Redis.

Delivery semantics: at-least-once.
  - An offset is stored only after the event is fully handled (written to
    Redis, or parked on the dead-letter topic). Kafka commits stored offsets
    every second, so a crash replays at most the last second of events.
  - Redis writes are idempotent (HSET of the same value), so a replay is
    harmless.

Two kinds of failure are handled differently, on purpose:
  - Bad data (invalid payload, or a processing error injected by
    FAILURE_RATE): retrying will not help, so the event goes to the DLQ and
    the consumer moves on. One poison message must not stop a partition.
  - A broken dependency (Redis down): every event would fail, and skipping
    them would lose data. The consumer rewinds to the failed offset and
    retries with backoff. Lag grows, the lag alert fires, and nothing is lost.
"""

import random
import socket
import time
from dataclasses import dataclass

from prometheus_client import Counter, Histogram

from stream import config
from stream.events import InvalidEventError, decode, end_to_end_seconds
from stream.health import BUILD_INFO, Health, RateLimitedLog, serve, stop_on_signals

MESSAGES = Counter(
    "consumer_messages_total",
    "Events handled by the consumer, by result",
    ["result"],  # ok | invalid | failed
)
END_TO_END = Histogram(
    "stream_end_to_end_latency_seconds",
    "From the producer creating an event to the consumer storing it in Redis",
    buckets=(0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0),
)
PROCESSING = Histogram(
    "consumer_processing_seconds",
    "Time to handle one event inside the consumer",
    buckets=(0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0),
)
STORE_ERRORS = Counter(
    "consumer_store_errors_total",
    "Failed writes to Redis; the event is retried, not dropped",
)
DLQ = Counter(
    "consumer_dlq_messages_total",
    "Events parked on the dead-letter topic, by reason",
    ["reason"],  # invalid | failed
)

log = RateLimitedLog("consumer")


class StoreError(Exception):
    """The sink is unavailable. Retry the same event later."""


class RedisStore:
    """Latest price per hotel and partner: HSET price:<hotel> <partner> <price>."""

    def __init__(self, client, errors: tuple[type[BaseException], ...]):
        self._client = client
        self._errors = errors

    @classmethod
    def from_settings(cls, s: config.Settings) -> "RedisStore":
        import redis  # imported here so unit tests don't need a Redis client

        return cls(redis.Redis(**redis_options(s)), (redis.exceptions.RedisError,))

    def save(self, event: dict) -> None:
        try:
            self._client.hset(
                f"price:{event['hotel_id']}",
                mapping={event["partner"]: event["price_eur"], "updated_at": event["produced_at"]},
            )
        except self._errors as exc:
            raise StoreError(str(exc)) from exc

    def ping(self) -> bool:
        try:
            return bool(self._client.ping())
        except self._errors:
            return False


def redis_options(s: config.Settings) -> dict:
    """Plain Redis locally; AUTH + TLS for Memorystore on GCP."""
    options = {
        "host": s.redis_host,
        "port": s.redis_port,
        "socket_timeout": 2,
        "socket_connect_timeout": 2,
    }
    if s.redis_password:
        options["password"] = s.redis_password
    if s.redis_tls:
        options["ssl"] = True
        options["ssl_cert_reqs"] = "required"
        if s.redis_ca_file:
            options["ssl_ca_certs"] = s.redis_ca_file
    return options


@dataclass
class Result:
    status: str  # ok | invalid | failed
    event: dict | None = None
    reason: str = ""


def process(raw: bytes | None, store, rng: random.Random, failure_rate: float) -> Result:
    """Handle one event. Raises StoreError if the sink is down (caller retries)."""
    try:
        event = decode(raw)
    except InvalidEventError as exc:
        return Result("invalid", None, str(exc))
    if failure_rate and rng.random() < failure_rate:
        return Result("failed", event, "injected failure (FAILURE_RATE)")
    store.save(event)
    return Result("ok", event)


def consumer_config(s: config.Settings) -> dict:
    return {
        "bootstrap.servers": s.bootstrap_servers,
        "group.id": s.group_id,
        "client.id": f"price-indexer-{socket.gethostname()}",
        "auto.offset.reset": "earliest",
        # At-least-once: we store an offset only after handling the event;
        # librdkafka commits stored offsets every second in the background.
        "enable.auto.commit": True,
        "enable.auto.offset.store": False,
        "auto.commit.interval.ms": 1000,
        # Incremental rebalancing: a pod restart only moves its own partitions.
        "partition.assignment.strategy": "cooperative-sticky",
        # A killed pod's partitions move to the others within ~10 s.
        "session.timeout.ms": 10000,
        "heartbeat.interval.ms": 3000,
    }


def main() -> None:
    # Imported here so unit tests don't need librdkafka.
    from confluent_kafka import Consumer, Producer, TopicPartition

    s = config.load()
    BUILD_INFO.labels("consumer", s.version).set(1)
    health = Health(stale_after=30)
    serve(s.metrics_port, health)
    stop = stop_on_signals()
    rng = random.Random()

    store = RedisStore.from_settings(s)
    consumer = Consumer(consumer_config(s))
    dlq = Producer({"bootstrap.servers": s.bootstrap_servers, "acks": "all"})
    consumer.subscribe([s.topic])
    health.set_ready(store.ping())
    log(
        "info",
        "started",
        topic=s.topic,
        group=s.group_id,
        failure_rate=s.failure_rate,
        processing_delay_ms=s.processing_delay_ms,
        version=s.version,
    )

    backoff = 0.5
    while not stop.is_set():
        health.beat()
        msg = consumer.poll(1.0)
        if msg is None:
            continue
        if msg.error():
            log("warn", "consumer error", key="poll", error=str(msg.error()))
            continue

        started = time.perf_counter()
        if s.processing_delay_ms:
            time.sleep(s.processing_delay_ms / 1000)  # chaos: a slow consumer

        try:
            result = process(msg.value(), store, rng, s.failure_rate)
        except StoreError as exc:
            STORE_ERRORS.inc()
            health.set_ready(False)
            log("error", "redis write failed, retrying", key="store", error=str(exc))
            # Rewind so the same event is fetched again: nothing is skipped.
            consumer.seek(TopicPartition(msg.topic(), msg.partition(), msg.offset()))
            stop.wait(backoff)
            backoff = min(backoff * 2, 10.0)
            continue
        backoff = 0.5
        health.set_ready(True)

        if result.status == "ok":
            END_TO_END.observe(end_to_end_seconds(result.event, time.time()))
        else:
            dlq.produce(
                s.dlq_topic,
                key=msg.key(),
                value=msg.value(),
                headers={
                    "dlq.reason": result.reason,
                    "dlq.source": f"{msg.topic()}/{msg.partition()}/{msg.offset()}",
                },
            )
            dlq.poll(0)
            DLQ.labels(result.status).inc()
            log("warn", "event sent to DLQ", key=f"dlq-{result.status}", reason=result.reason)

        MESSAGES.labels(result.status).inc()
        PROCESSING.observe(time.perf_counter() - started)
        consumer.store_offsets(message=msg)

    log("info", "stopping: committing offsets and leaving the group")
    consumer.close()  # commits stored offsets; the group rebalances right away
    dlq.flush(5)
    log("info", "stopped")


if __name__ == "__main__":
    main()
