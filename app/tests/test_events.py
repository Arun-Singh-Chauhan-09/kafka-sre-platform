import json
import random

import pytest

from stream.events import (
    REQUIRED,
    InvalidEventError,
    decode,
    encode,
    end_to_end_seconds,
    make_event,
)


def test_make_event_has_contract_fields():
    event = make_event(random.Random(1), hotels=10, now=1000.0)
    assert set(REQUIRED) <= set(event)
    assert event["hotel_id"].startswith("hotel-")
    assert 40.0 <= event["price_eur"] <= 450.0
    assert event["produced_at"] == 1000.0


def test_hotel_ids_stay_within_range():
    rng = random.Random(2)
    ids = {make_event(rng, hotels=3, now=0.0)["hotel_id"] for _ in range(200)}
    assert ids <= {"hotel-00000", "hotel-00001", "hotel-00002"}


def test_encode_decode_roundtrip():
    event = make_event(random.Random(3), hotels=100, now=1234.5)
    assert decode(encode(event)) == event


@pytest.mark.parametrize(
    "raw",
    [
        None,
        b"",
        b"not json",
        b"\xff\xfe",
        b"[1, 2, 3]",
        json.dumps({"hotel_id": "hotel-00001"}).encode(),
    ],
)
def test_decode_rejects_garbage(raw):
    with pytest.raises(InvalidEventError):
        decode(raw)


@pytest.mark.parametrize(
    "field, value",
    [
        ("price_eur", -5),
        ("price_eur", 0),
        ("price_eur", "129.50"),
        ("price_eur", True),
        ("produced_at", None),
        ("hotel_id", ""),
        ("partner", 7),
    ],
)
def test_decode_rejects_bad_field_values(field, value):
    event = make_event(random.Random(4), hotels=10, now=1.0)
    event[field] = value
    with pytest.raises(InvalidEventError):
        decode(encode(event))


def test_end_to_end_latency_never_negative():
    event = {"produced_at": 100.0}
    assert end_to_end_seconds(event, now=102.5) == 2.5
    assert end_to_end_seconds(event, now=99.0) == 0.0  # clock skew between pods
