import random

import pytest
from prometheus_client import REGISTRY

from stream.config import load
from stream.consumer import RedisStore, StoreError, consumer_config, process, redis_options
from stream.events import encode, make_event


class FakeStore:
    def __init__(self, fail: bool = False):
        self.saved = []
        self.fail = fail

    def save(self, event):
        if self.fail:
            raise StoreError("connection refused")
        self.saved.append(event)


def an_event():
    return make_event(random.Random(7), hotels=10, now=100.0)


def test_valid_event_is_stored():
    store = FakeStore()
    result = process(encode(an_event()), store, random.Random(0), failure_rate=0.0)
    assert result.status == "ok"
    assert store.saved == [result.event]


def test_invalid_event_goes_to_dlq_not_store():
    store = FakeStore()
    result = process(b"{broken", store, random.Random(0), failure_rate=0.0)
    assert result.status == "invalid"
    assert "not JSON" in result.reason
    assert store.saved == []


def test_injected_failure_is_not_stored():
    store = FakeStore()
    result = process(encode(an_event()), store, random.Random(0), failure_rate=1.0)
    assert result.status == "failed"
    assert store.saved == []


def test_sink_outage_raises_so_the_event_is_retried():
    # A Redis outage must not turn into "skip and commit": that would lose data.
    with pytest.raises(StoreError):
        process(encode(an_event()), FakeStore(fail=True), random.Random(0), failure_rate=0.0)


class FakeRedis:
    def __init__(self, error: Exception | None = None):
        self.calls = []
        self.error = error

    def hset(self, key, mapping):
        if self.error:
            raise self.error
        self.calls.append((key, mapping))

    def ping(self):
        if self.error:
            raise self.error
        return True


def test_redis_store_writes_latest_price_per_hotel_and_partner():
    client = FakeRedis()
    event = an_event()
    RedisStore(client, (ConnectionError,)).save(event)
    key, mapping = client.calls[0]
    assert key == f"price:{event['hotel_id']}"
    assert mapping[event["partner"]] == event["price_eur"]
    assert mapping["updated_at"] == event["produced_at"]


def test_redis_errors_become_store_errors():
    store = RedisStore(FakeRedis(ConnectionError("refused")), (ConnectionError,))
    with pytest.raises(StoreError):
        store.save(an_event())
    assert store.ping() is False


def test_offsets_are_stored_manually_for_at_least_once():
    cfg = consumer_config(load({}))
    assert cfg["enable.auto.offset.store"] is False
    assert cfg["group.id"] == "price-indexer"
    assert cfg["partition.assignment.strategy"] == "cooperative-sticky"


def test_metrics_are_registered():
    # The names the alerts and dashboards depend on.
    for name in ("consumer_store_errors_total", "stream_end_to_end_latency_seconds_count"):
        assert REGISTRY.get_sample_value(name) is not None


def test_local_redis_needs_no_password_or_tls():
    options = redis_options(load({"REDIS_HOST": "redis"}))
    assert options["host"] == "redis"
    assert "password" not in options and "ssl" not in options


def test_memorystore_uses_auth_and_verified_tls():
    options = redis_options(
        load(
            {
                "REDIS_HOST": "10.0.0.3",
                "REDIS_PORT": "6378",
                "REDIS_PASSWORD": "secret",
                "REDIS_TLS": "true",
                "REDIS_CA_FILE": "/etc/redis-ca/ca.pem",
            }
        )
    )
    assert options["port"] == 6378
    assert options["password"] == "secret"
    assert options["ssl"] is True and options["ssl_cert_reqs"] == "required"
    assert options["ssl_ca_certs"] == "/etc/redis-ca/ca.pem"
