"""The event contract: one JSON object per price update.

    {"event_id": "...", "hotel_id": "hotel-00042", "partner": "partner-03",
     "price_eur": 129.5, "produced_at": 1791898273.403}

hotel_id is also the Kafka message key, so every update for one hotel lands
in the same partition and is consumed in order.
"""

import json
import random
import uuid

PARTNERS = tuple(f"partner-{n:02d}" for n in range(1, 9))
REQUIRED = ("event_id", "hotel_id", "partner", "price_eur", "produced_at")


class InvalidEventError(ValueError):
    """The payload is not a valid price event. Retrying will not fix it."""


def make_event(rng: random.Random, hotels: int, now: float) -> dict:
    return {
        "event_id": str(uuid.UUID(int=rng.getrandbits(128), version=4)),
        "hotel_id": f"hotel-{rng.randrange(hotels):05d}",
        "partner": rng.choice(PARTNERS),
        "price_eur": round(rng.uniform(40.0, 450.0), 2),
        "produced_at": now,
    }


def encode(event: dict) -> bytes:
    return json.dumps(event, separators=(",", ":")).encode()


def decode(raw: bytes | None) -> dict:
    if not raw:
        raise InvalidEventError("empty payload")
    try:
        event = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidEventError(f"not JSON: {exc}") from None
    if not isinstance(event, dict):
        raise InvalidEventError("payload is not a JSON object")
    missing = [field for field in REQUIRED if field not in event]
    if missing:
        raise InvalidEventError(f"missing fields: {', '.join(missing)}")
    for field in ("event_id", "hotel_id", "partner"):
        if not isinstance(event[field], str) or not event[field]:
            raise InvalidEventError(f"{field} must be a non-empty string")
    for field in ("price_eur", "produced_at"):
        if isinstance(event[field], bool) or not isinstance(event[field], int | float):
            raise InvalidEventError(f"{field} must be a number")
    if event["price_eur"] <= 0:
        raise InvalidEventError("price_eur must be positive")
    return event


def end_to_end_seconds(event: dict, now: float) -> float:
    """Produce-to-stored latency. Clamped at 0 in case of small clock skew."""
    return max(0.0, now - float(event["produced_at"]))
