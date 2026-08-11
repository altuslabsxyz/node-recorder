#!/usr/bin/env python3
"""Fake CometBFT RPC server for tests only; not shipped in production.

mempool_collect always requests the fixed path "/num_unconfirmed_txs", so
this fake's response is controlled by the FAKE_RPC_MODE environment
variable (set before the process starts) rather than by the request path:

  ok         -> 200 with a valid JSON body (default)
  slow       -> sleeps 3 seconds, then 200 with a valid JSON body (used to
                trigger client-side timeouts)
  error      -> 500 with an empty body
  empty      -> 200 with an empty body
  malformed  -> 200 with a non-JSON body
"""
import http.server
import os
import sys
import time

MODE = os.environ.get("FAKE_RPC_MODE", "ok")
OK_BODY = b'{"jsonrpc":"2.0","id":-1,"result":{"n_txs":"0","total":"0","total_bytes":"0"}}'


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if not self.path.startswith("/num_unconfirmed_txs"):
            self._respond(404, b"")
            return
        if MODE == "slow":
            time.sleep(3)
            self._respond(200, OK_BODY)
        elif MODE == "error":
            self._respond(500, b"")
        elif MODE == "empty":
            self._respond(200, b"")
        elif MODE == "malformed":
            self._respond(200, b"not json")
        else:
            self._respond(200, OK_BODY)

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
