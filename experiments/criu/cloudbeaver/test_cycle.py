#!/usr/bin/env python3
"""Two-cycle, real-HTTP CloudBeaver checkpoint test via kubectl port-forward."""

import argparse
import http.client
import json
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def control(base, path, method="GET"):
    try:
        with urlopen(Request(base + path, method=method), timeout=150) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"{method} {path}: HTTP {error.code}: {error.read().decode()}") from error


def app_request(port):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=150)
    start = time.perf_counter()
    connection.request("GET", "/", headers={"Host": "127.0.0.1"})
    response = connection.getresponse()
    body = response.read()
    elapsed = round((time.perf_counter() - start) * 1000)
    result = {"status": response.status, "content_type": response.getheader("Content-Type"),
              "bytes": len(body), "request_ms": elapsed}
    connection.close()
    if not 200 <= result["status"] < 400:
        raise RuntimeError(f"CloudBeaver GET / returned {result}")
    return result


def wait_status(base, predicate, timeout, description, forward=None):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        if forward is not None and forward.poll() is not None:
            raise RuntimeError(f"kubectl port-forward exited while waiting for {description} (exit {forward.returncode})")
        try:
            last = control(base, "/status")
            if predicate(last):
                return last
        except (URLError, ConnectionError):
            pass
        time.sleep(0.5)
    raise RuntimeError(f"timed out waiting for {description}; last status={last}")


def assert_reclaimed(before, after):
    reclaimed = {}
    for key in ("anon", "current"):
        a = before["cgroup_memory_bytes"].get(key)
        b = after["cgroup_memory_bytes"].get(key)
        if a is None or b is None or a - b < 64 * 1024 * 1024:
            raise RuntimeError(f"less than 64 MiB of {key} freed: baseline={a}, asleep={b}")
        reclaimed[key] = a - b
    return reclaimed


def assert_same_process(initial, restored):
    if restored["phase"] != "running" or not restored["backend_ready"]:
        raise RuntimeError(f"CloudBeaver is not ready after restore: {restored}")
    if (restored["pid"] != initial["pid"] or restored["pilot_identity"] is None
            or restored["pilot_identity"] != initial["pilot_identity"]):
        raise RuntimeError("the original Java process and its memory-only identity were not preserved")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--namespace", default="criu-cloudbeaver-pilot")
    parser.add_argument("--pod", default="cloudbeaver-checkpoint")
    parser.add_argument("--front-port", type=int, default=18080)
    parser.add_argument("--control-port", type=int, default=18082)
    args = parser.parse_args()
    base_command = ["kubectl", "--kubeconfig", args.kubeconfig, "--namespace", args.namespace]
    ready = subprocess.run(base_command + ["wait", "--for=condition=Ready",
                                           f"pod/{args.pod}", "--timeout=180s"],
                           capture_output=True, text=True, timeout=190)
    if ready.returncode:
        raise RuntimeError(f"pilot Pod did not become Ready: {ready.stderr.strip()}")
    command = base_command + ["port-forward", "--address", "127.0.0.1", f"pod/{args.pod}",
               f"{args.front_port}:8080", f"{args.control_port}:8082"]
    forward = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = f"http://127.0.0.1:{args.control_port}"
    try:
        initial = wait_status(base, lambda s: s["backend_ready"], 180,
                              "initial CloudBeaver readiness", forward)
        first_request = app_request(args.front_port)
        before = control(base, "/status")
        sleep_result = control(base, "/sleep", "POST")
        asleep = control(base, "/status")
        if asleep["phase"] != "asleep" or asleep["checkpoint_bytes"] == 0:
            raise RuntimeError(f"no restorable checkpoint: {asleep}")
        freed_first = assert_reclaimed(before, asleep)
        time.sleep(2)
        if control(base, "/status")["phase"] != "asleep":
            raise RuntimeError("control-plane status check woke the JVM")
        first_wake = app_request(args.front_port)
        restored = wait_status(base, lambda s: s["backend_ready"], 20, "first restore", forward)
        assert_same_process(initial, restored)
        second_asleep = wait_status(base, lambda s: s["phase"] == "asleep", 90,
                                    "automatic checkpoint", forward)
        freed_second = assert_reclaimed(restored, second_asleep)
        second_wake = app_request(args.front_port)
        final = wait_status(base, lambda s: s["backend_ready"], 20, "second restore", forward)
        assert_same_process(initial, final)
        print(json.dumps({"initial": initial, "first_request": first_request,
                          "sleep_result": sleep_result, "asleep": asleep,
                          "first_cycle_bytes_freed": freed_first, "first_wake": first_wake,
                          "restored": restored, "automatic_asleep": second_asleep,
                          "second_cycle_bytes_freed": freed_second, "second_wake": second_wake,
                          "final": final}, indent=2))
    finally:
        forward.terminate()
        try:
            forward.wait(timeout=5)
        except subprocess.TimeoutExpired:
            forward.kill()
            forward.wait()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, URLError, OSError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
