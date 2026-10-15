"""Producer: publishes hotel price updates to Kafka at a steady rate.

Durability settings are the ones you would use for data you cannot lose:
acks=all (every in-sync replica has the event) and idempotence (a retry
after a timeout never writes the same event twice). With the topic's
min.insync.replicas=2, losing one of three brokers is invisible; losing two
makes produce() fail, and that shows up as producer errors.
"""

import random
import socket
import time
from functools import partial

from prometheus_client import Counter, Histogram

from stream import config
from stream.events import encode, make_event
from stream.health import BUILD_INFO, Health, RateLimitedLog, serve, stop_on_signals

MESSAGES = Counter(
    "producer_messages_total",
    "Events the producer tried to publish, by delivery result",
    ["result"],  # ok | error
)
DELIVERY_LATENCY = Histogram(
    "producer_delivery_latency_seconds",
    "Time from produce() to the broker acknowledging the event (acks=all)",
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0, 30.0),
)

log = RateLimitedLog("producer")


def on_delivery(health: Health, sent_at: float, err, msg) -> None:
    """Delivery report from librdkafka, called from producer.poll()."""
    if err is not None:
        MESSAGES.labels("error").inc()
        log("error", "delivery failed", key="delivery", error=str(err))
        return
    MESSAGES.labels("ok").inc()
    DELIVERY_LATENCY.observe(time.monotonic() - sent_at)
    health.set_ready(True)


def producer_config(s: config.Settings) -> dict:
    return {
        "bootstrap.servers": s.bootstrap_servers,
        "client.id": f"price-producer-{socket.gethostname()}",
        "acks": "all",
        "enable.idempotence": True,
        "linger.ms": 20,  # small batches: better throughput, ~20 ms extra latency
        "compression.type": "lz4",
        "delivery.timeout.ms": 30000,  # give up (and count an error) after 30 s
    }


def main() -> None:
    from confluent_kafka import Producer  # imported here so unit tests don't need librdkafka

    s = config.load()
    BUILD_INFO.labels("producer", s.version).set(1)
    health = Health(stale_after=30)
    serve(s.metrics_port, health)
    stop = stop_on_signals()
    producer = Producer(producer_config(s))
    rng = random.Random()
    interval = 1.0 / s.produce_rate
    log("info", "started", topic=s.topic, rate_per_s=s.produce_rate, version=s.version)

    next_send = time.monotonic()
    while not stop.is_set():
        health.beat()
        event = make_event(rng, s.hotels, time.time())
        try:
            producer.produce(
                s.topic,
                key=event["hotel_id"],
                value=encode(event),
                on_delivery=partial(on_delivery, health, time.monotonic()),
            )
        except BufferError:
            # Local queue full: the brokers are not keeping up or are unreachable.
            MESSAGES.labels("error").inc()
            log("warn", "local queue full, backing off", key="buffer")
            producer.poll(0.5)
            continue
        producer.poll(0)  # serve delivery reports

        next_send += interval
        delay = next_send - time.monotonic()
        if delay > 0:
            stop.wait(delay)
        elif delay < -1.0:
            next_send = time.monotonic()  # fell behind by >1 s: don't burst to catch up

    log("info", "stopping, flushing in-flight events")
    remaining = producer.flush(10)
    log("info", "stopped", undelivered=remaining)


if __name__ == "__main__":
    main()
