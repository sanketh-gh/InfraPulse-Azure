"""Endpoint tests for the InfraPulse HTTP server."""

from http.client import HTTPConnection
from threading import Thread

from server import PulseHandler
from http.server import ThreadingHTTPServer


def request(path: str) -> tuple[int, str, str]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), PulseHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        connection = HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        connection.request("GET", path)
        response = connection.getresponse()
        result = (response.status, response.getheader("Content-Type", ""), response.read().decode())
        connection.close()
        return result
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def test_root_returns_greeting() -> None:
    status, content_type, body = request("/")
    assert status == 200
    assert content_type.startswith("text/plain")
    assert body == "Hello from InfraPulse\n"


def test_health_returns_json() -> None:
    status, content_type, body = request("/health")
    assert status == 200
    assert content_type == "application/json"
    assert body == '{"status":"ok"}\n'


def test_unknown_path_returns_404() -> None:
    status, _content_type, body = request("/missing")
    assert status == 404
    assert body == "Not found\n"
