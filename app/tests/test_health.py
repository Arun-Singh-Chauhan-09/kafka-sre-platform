import json
import urllib.error
import urllib.request

from prometheus_client import Counter, Gauge, Histogram

import stream.consumer
import stream.health
import stream.producer
from stream.health import Health, RateLimitedLog, serve


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def test_liveness_fails_when_the_main_loop_stops_beating():
    clock = FakeClock()
    health = Health(stale_after=30, clock=clock)
    assert health.live()
    clock.now = 31
    assert not health.live()
    health.beat()
    assert health.live()


def get(port, path):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def test_http_endpoints():
    health = Health()
    server = serve(0, health)
    port = server.server_address[1]
    try:
        assert get(port, "/healthz")[0] == 200
        assert get(port, "/ready")[0] == 503  # not ready until connected
        health.set_ready(True)
        assert get(port, "/ready")[0] == 200
        status, body = get(port, "/metrics")
        assert status == 200 and b"stream_build_info" in body
        assert get(port, "/nope")[0] == 404
    finally:
        server.shutdown()


def test_rate_limited_log_drops_repeats(capsys):
    clock = FakeClock()
    log = RateLimitedLog("test", interval=10, clock=clock)
    assert log("error", "redis down", key="store")
    assert not log("error", "redis down", key="store")  # suppressed
    clock.now = 11
    assert log("error", "redis down", key="store")
    lines = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert len(lines) == 2
    assert lines[0]["component"] == "test" and lines[0]["level"] == "error"


# Labels Prometheus (and the Prometheus Operator) attach to every scraped
# series. If a metric used one of these, Prometheus would rename it to
# exported_<name> and every alert filtering on it would silently match
# nothing. This bit the previous project; the guard keeps it from coming back.
RESERVED_TARGET_LABELS = {"job", "instance", "namespace", "pod", "service", "endpoint", "container"}


def test_metrics_do_not_use_reserved_target_labels():
    metrics = [
        value
        for module in (stream.health, stream.producer, stream.consumer)
        for value in vars(module).values()
        if isinstance(value, Counter | Gauge | Histogram)
    ]
    assert len(metrics) >= 7
    for metric in metrics:
        clash = set(metric._labelnames) & RESERVED_TARGET_LABELS
        assert not clash, f"{metric._name}: reserved Prometheus label used: {clash}"
