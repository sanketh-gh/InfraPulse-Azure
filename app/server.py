"""A tiny standard-library HTTP service for the InfraPulse demo."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import logging
from urllib.parse import urlsplit


HOST = "0.0.0.0"
PORT = 8080


class PulseHandler(BaseHTTPRequestHandler):
    """Serve the two documented endpoints and reject all others."""

    def do_GET(self) -> None:  # noqa: N802 - required by BaseHTTPRequestHandler
        route = urlsplit(self.path).path
        if route == "/":
            self._send(200, "text/plain; charset=utf-8", b"Hello from InfraPulse\n")
        elif route == "/health":
            self._send(200, "application/json", b'{"status":"ok"}\n')
        else:
            self._send(404, "text/plain; charset=utf-8", b"Not found\n")

        # Log only method, path, and status; never request headers or credentials.
        # Route names are safe to log; query strings can contain caller secrets.
        route_name = {"/": "root", "/health": "health"}.get(route, "unknown")
        logging.info("request method=GET route=%s status=%d", route_name, self._last_status)

    def _send(self, status: int, content_type: str, body: bytes) -> None:
        self._last_status = status
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: object) -> None:
        """Disable BaseHTTPRequestHandler's default address/header-style log."""


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    server = ThreadingHTTPServer((HOST, PORT), PulseHandler)
    logging.info("InfraPulse listening on %s:%d", HOST, PORT)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("shutdown requested")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
