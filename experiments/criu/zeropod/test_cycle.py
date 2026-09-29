"""One real TCP request, 45 idle seconds, then one wake request."""

import argparse
import json
import socket
import time


def get_state(host: str, port: int, timeout: float):
    start = time.monotonic()
    with socket.create_connection((host, port), timeout=timeout) as connection:
        connection.settimeout(timeout)
        connection.sendall(
            b"GET /state HTTP/1.1\r\nHost: zeropod-memory-canary\r\nConnection: close\r\n\r\n"
        )
        chunks = []
        while chunk := connection.recv(4096):
            chunks.append(chunk)
    response = b"".join(chunks)
    header, separator, body = response.partition(b"\r\n\r\n")
    if not separator or not header.startswith(b"HTTP/1.0 200 "):
        raise RuntimeError(f"unexpected HTTP response: {header[:120]!r}")
    state = json.loads(body)
    return state, time.monotonic() - start


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, help="target Pod IP, IPv6 or IPv4")
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--idle-seconds", type=int, default=45)
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()

    before, first_seconds = get_state(args.host, args.port, args.timeout)
    print(json.dumps({"phase": "before", "state": before, "latency_s": first_seconds}), flush=True)
    print(f"idle for {args.idle_seconds}s; inspect checkpoint and memory now", flush=True)
    time.sleep(args.idle_seconds)
    after, wake_seconds = get_state(args.host, args.port, args.timeout)
    print(json.dumps({"phase": "after", "state": after, "latency_s": wake_seconds}), flush=True)

    if before["identity"] != after["identity"]:
        raise RuntimeError("memory-only identity changed: process restarted instead of restoring")
    if before["pid"] != after["pid"]:
        raise RuntimeError("PID changed across checkpoint and restore")
    if after["counter"] < before["counter"]:
        raise RuntimeError("counter moved backwards")
    print("PASS: memory-only identity and PID survived the TCP wake", flush=True)


if __name__ == "__main__":
    main()
