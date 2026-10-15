"""Probes, metrics endpoint and JSON logs, shared by producer and consumer.

    GET /healthz  liveness: the main loop has run recently (not stuck)
    GET /ready    readiness: the service is connected and doing its job
    GET /metrics  Prometheus exposition

Uses only the standard library HTTP server: these endpoints are hit by the
kubelet and Prometheus a few times a minute, not by users.
"""

import json
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import CONTENT_TYPE_LATEST, REGISTRY, Gauge, generate_latest

# Constant 1, labelled with the running version: shows in Grafana which
# version each pod runs while a rollout is in progress.
BUILD_INFO = Gauge("stream_build_info", "Build information", ["component", "version"])


class Health:
    def __init__(self, stale_after: float = 30.0, clock=time.monotonic):
        self._clock = clock
        self._stale_after = stale_after
        self._last_beat = clock()
        self._ready = False
        self._lock = threading.Lock()

    def beat(self) -> None:
        with self._lock:
            self._last_beat = self._clock()

    def set_ready(self, ready: bool) -> None:
        with self._lock:
            self._ready = ready

    @property
    def ready(self) -> bool:
        with self._lock:
            return self._ready

    def live(self) -> bool:
        with self._lock:
            return self._clock() - self._last_beat < self._stale_after


def _handler(health: Health):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # method name required by BaseHTTPRequestHandler
            if self.path == "/metrics":
                self._send(200, generate_latest(REGISTRY), CONTENT_TYPE_LATEST)
            elif self.path == "/healthz":
                ok = health.live()
                self._send(200 if ok else 503, b"ok\n" if ok else b"stuck\n")
            elif self.path == "/ready":
                ok = health.ready
                self._send(200 if ok else 503, b"ready\n" if ok else b"not ready\n")
            else:
                self._send(404, b"not found\n")

        def _send(self, status: int, body: bytes, ctype: str = "text/plain; charset=utf-8"):
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):  # probes every few seconds: keep stdout clean
            pass

    return Handler


def serve(port: int, health: Health) -> ThreadingHTTPServer:
    # 0.0.0.0: the kubelet and Prometheus connect from outside the pod.
    server = ThreadingHTTPServer(("0.0.0.0", port), _handler(health))
    threading.Thread(target=server.serve_forever, name="http", daemon=True).start()
    return server


class RateLimitedLog:
    """JSON log lines on stdout; the same message key at most once per interval.

    A broken dependency fails every event. Without a limit, one outage would
    write tens of thousands of identical lines per minute.
    """

    def __init__(self, component: str, interval: float = 10.0, clock=time.monotonic):
        self.component = component
        self._interval = interval
        self._clock = clock
        self._last: dict[str, float] = {}

    def __call__(self, level: str, msg: str, key: str | None = None, **fields) -> bool:
        if key is not None:
            now = self._clock()
            if now - self._last.get(key, float("-inf")) < self._interval:
                return False
            self._last[key] = now
        line = {"ts": round(time.time(), 3), "level": level, "component": self.component}
        line["msg"] = msg
        line.update(fields)
        print(json.dumps(line, default=str), file=sys.stdout, flush=True)
        return True


def stop_on_signals() -> threading.Event:
    """SIGTERM (kubelet) or Ctrl+C sets the event; the main loop then drains and exits."""
    stop = threading.Event()

    def _stop(signum, _frame):
        stop.set()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    return stop
