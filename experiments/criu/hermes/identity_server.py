"""Memory-only sentinel: a cold container restart changes this identity."""

import http.server
import json
import secrets


IDENTITY = secrets.token_hex(16)
COUNTER = 0


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global COUNTER
        if self.path != "/identity":
            self.send_error(404)
            return
        COUNTER += 1
        body = json.dumps({"identity": IDENTITY, "counter": COUNTER}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


http.server.HTTPServer(("0.0.0.0", 9118), Handler).serve_forever()
