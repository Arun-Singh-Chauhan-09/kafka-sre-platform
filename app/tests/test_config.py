from stream.config import load


def test_defaults():
    s = load({})
    assert s.topic == "price-updates"
    assert s.dlq_topic == "price-updates.dlq"
    assert s.group_id == "price-indexer"
    assert s.failure_rate == 0.0
    assert s.processing_delay_ms == 0.0


def test_overrides():
    s = load(
        {
            "KAFKA_BOOTSTRAP_SERVERS": "kafka-cluster-kafka-bootstrap.kafka:9092",
            "PRODUCE_RATE": "200",
            "FAILURE_RATE": "0.2",
            "PROCESSING_DELAY_MS": "100",
        }
    )
    assert s.bootstrap_servers == "kafka-cluster-kafka-bootstrap.kafka:9092"
    assert s.produce_rate == 200.0
    assert s.failure_rate == 0.2
    assert s.processing_delay_ms == 100.0


def test_bad_values_fall_back_or_clamp():
    s = load({"PRODUCE_RATE": "fast", "FAILURE_RATE": "7", "HOTELS": "-3", "REDIS_PORT": "x"})
    assert s.produce_rate == 50.0  # unparsable -> default
    assert s.failure_rate == 1.0  # clamped to 0..1
    assert s.hotels == 1
    assert s.redis_port == 6379
