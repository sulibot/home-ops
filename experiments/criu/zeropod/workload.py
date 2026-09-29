"""Disposable HTTP process with 128 MiB of resident state and no supervisor."""

import json
import os
import secrets
import socket
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


memory = bytearray(128 * 1024 * 1024)
for offset in range(0, len(memory), 4096):
    memory[offset] = 1

identity = secrets.token_hex(16)  # Never written to disk by this app.
counter = 0
last_tick = time.monotonic()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/state":
            self.send_error(404)
            return
        payload = json.dumps(
            {"identity": identity, "pid": os.getpid(), "counter": counter}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class DualStackHTTPServer(HTTPServer):
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


server = DualStackHTTPServer(("::", 8081), Handler)
server.timeout = 0.2
while True:
    server.handle_request()
    now = time.monotonic()
    if now - last_tick >= 1:
        counter += 1
        last_tick = now
        fd = os.open("/state/counter", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            os.write(fd, str(counter).encode())
        finally:
            os.close(fd)
