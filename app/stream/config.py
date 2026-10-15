"""Settings from environment variables, read once at start-up.

Chaos knobs (PROCESSING_DELAY_MS, FAILURE_RATE) are plain env vars, so a
drill is `kubectl set env ...`, which also rolls the pods: the change is
visible in the Deployment and in ArgoCD as drift from git.
"""

import os
from collections.abc import Mapping
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    bootstrap_servers: str
    topic: str
    dlq_topic: str
    group_id: str
    redis_host: str
    redis_port: int
    redis_password: str  # Memorystore AUTH string on GCP; empty locally
    redis_tls: bool  # Memorystore with transit encryption
    redis_ca_file: str  # Memorystore server CA, mounted from a Secret
    produce_rate: float  # events per second (producer)
    hotels: int  # distinct hotel ids, one message key each
    processing_delay_ms: float  # extra work per event (consumer chaos knob)
    failure_rate: float  # 0.0-1.0, events that fail processing -> DLQ (chaos knob)
    metrics_port: int
    version: str


def _float(env: Mapping[str, str], name: str, default: float) -> float:
    try:
        return float(env.get(name, default))
    except ValueError:
        return default


def _int(env: Mapping[str, str], name: str, default: int) -> int:
    try:
        return int(env.get(name, default))
    except ValueError:
        return default


def load(env: Mapping[str, str] | None = None) -> Settings:
    env = os.environ if env is None else env
    return Settings(
        bootstrap_servers=env.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
        topic=env.get("KAFKA_TOPIC", "price-updates"),
        dlq_topic=env.get("KAFKA_DLQ_TOPIC", "price-updates.dlq"),
        group_id=env.get("KAFKA_GROUP_ID", "price-indexer"),
        redis_host=env.get("REDIS_HOST", "localhost"),
        redis_port=_int(env, "REDIS_PORT", 6379),
        redis_password=env.get("REDIS_PASSWORD", ""),
        redis_tls=env.get("REDIS_TLS", "false").lower() == "true",
        redis_ca_file=env.get("REDIS_CA_FILE", ""),
        produce_rate=max(_float(env, "PRODUCE_RATE", 50.0), 0.1),
        hotels=max(_int(env, "HOTELS", 8000), 1),
        processing_delay_ms=max(_float(env, "PROCESSING_DELAY_MS", 0.0), 0.0),
        failure_rate=min(max(_float(env, "FAILURE_RATE", 0.0), 0.0), 1.0),
        metrics_port=_int(env, "METRICS_PORT", 8000),
        version=env.get("APP_VERSION", "dev"),
    )
