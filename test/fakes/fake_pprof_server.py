#!/usr/bin/env python3
"""Fake pprof HTTP server for tests only; not shipped in production.

Routes:
  /slow/<secs>   -> sleeps <secs> seconds, then 200 with a fixed body
                    (used to trigger client-side timeouts)
  /error         -> 500 with an empty body
  /empty         -> 200 with an empty body
  anything else  -> 200 with a fixed non-empty body, UNLESS the file at
                    $FAKE_PPROF_FAIL_MARKER_FILE exists and its trimmed
                    contents are a substring of the request path, in which
                    case 500. This lets tests toggle which named endpoint
                    (goroutine/heap/mutex/profile) fails without changing
                    the fixed paths production code requests.
"""
import http.server
import os
import sys
import time

FAIL_MARKER_FILE = os.environ.get("FAKE_PPROF_FAIL_MARKER_FILE", "")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/slow/"):
            seconds = float(self.path.rsplit("/", 1)[-1])
            time.sleep(seconds)
            self._respond(200, b"slow-profile-data")
            return
        if self.path.startswith("/error"):
            self._respond(500, b"")
            return
        if self.path.startswith("/empty"):
            self._respond(200, b"")
            return
        if FAIL_MARKER_FILE and os.path.exists(FAIL_MARKER_FILE):
            with open(FAIL_MARKER_FILE) as f:
                marker = f.read().strip()
            if marker and marker in self.path:
                self._respond(500, b"")
                return
        self._respond(200, b"fake-profile-data")

    def _respond(self, code, body):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # keep test output quiet


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    print(server.server_port)
    sys.stdout.flush()
    server.serve_forever()
