from prometheus_client import REGISTRY

from stream.config import load
from stream.health import Health
from stream.producer import on_delivery, producer_config


def sample(result):
    return REGISTRY.get_sample_value("producer_messages_total", {"result": result}) or 0.0


def test_successful_delivery_counts_ok_and_marks_ready():
    health = Health()
    before = sample("ok")
    on_delivery(health, sent_at=0.0, err=None, msg=object())
    assert sample("ok") == before + 1
    assert health.ready


def test_failed_delivery_counts_error_and_stays_not_ready():
    health = Health()
    before = sample("error")
    on_delivery(health, sent_at=0.0, err="Broker: Not enough in-sync replicas", msg=object())
    assert sample("error") == before + 1
    assert not health.ready


def test_producer_is_configured_for_durability():
    cfg = producer_config(load({}))
    assert cfg["acks"] == "all"
    assert cfg["enable.idempotence"] is True
