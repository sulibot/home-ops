#!/usr/bin/env python3
"""Verify manual and automatic same-Pod CRIU sleep/wake cycles."""

import argparse
import json
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def request(base, path, method="GET"):
    try:
        with urlopen(Request(base + path, method=method), timeout=75) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"{method} {path}: HTTP {error.code}: {error.read().decode()}") from error


def wait_for_status(base, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            return request(base, "/status")
        except (URLError, ConnectionError):
            time.sleep(0.2)
    raise RuntimeError("kubectl port-forward did not become ready")


def wait_for_phase(base, expected, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = request(base, "/status")
        if status["phase"] == expected:
            return status
        time.sleep(0.5)
    raise RuntimeError(f"Pod did not enter phase {expected} within {timeout}s")


def freed_bytes(before, after, key):
    first = before["cgroup_memory_bytes"].get(key)
    second = after["cgroup_memory_bytes"].get(key)
    return first - second if first is not None and second is not None else None


def assert_freed(before, after):
    freed = {key: freed_bytes(before, after, key) for key in ("anon", "current")}
    for key, amount in freed.items():
        if amount is None or amount < 64 * 1024 * 1024:
            raise RuntimeError(f"less than 64 MiB of {key} cgroup memory was freed: {freed}")
    return freed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--namespace", default="criu-experiment")
    parser.add_argument("--pod", default="process-checkpoint")
    parser.add_argument("--local-port", type=int, default=18080)
    args = parser.parse_args()

    command = [
        "kubectl", "--kubeconfig", args.kubeconfig,
        "--namespace", args.namespace, "port-forward",
        "--address", "127.0.0.1", f"pod/{args.pod}",
        f"{args.local_port}:8080",
    ]
    forward = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = f"http://127.0.0.1:{args.local_port}"
    try:
        wait_for_status(base)
        original = request(base, "/request")["child"]
        time.sleep(1.2)
        baseline = request(base, "/status")
        if baseline["phase"] != "running" or baseline["child_rss_kib"] is None:
            raise RuntimeError(f"child was not running at baseline: {baseline}")

        sleep_result = request(base, "/sleep", "POST")
        asleep = request(base, "/status")
        time.sleep(1.5)
        still_asleep = request(base, "/status")
        if asleep["phase"] != "asleep" or asleep["checkpoint_bytes"] == 0:
            raise RuntimeError(f"checkpoint did not leave a sleeping child: {asleep}")
        if still_asleep["counter"] != asleep["counter"]:
            raise RuntimeError("counter advanced while child was supposed to be stopped")

        wake_start = time.perf_counter()
        wake_result = request(base, "/request")
        wake_request_ms = round((time.perf_counter() - wake_start) * 1000)
        if not wake_result["woke"] or wake_result["child"]["identity"] != original["identity"]:
            raise RuntimeError("request did not restore the original child identity")
        deadline = time.monotonic() + 8
        while True:
            child_after = request(base, "/request")["child"]
            restored = request(base, "/status")
            if child_after["counter"] > asleep["counter"] and restored["child_rss_kib"] is not None:
                break
            if time.monotonic() >= deadline:
                raise RuntimeError(f"restored child did not advance its counter: {restored}")
            time.sleep(0.25)

        first_freed = assert_freed(baseline, asleep)
        auto_asleep = wait_for_phase(base, "asleep", restored["idle_after_seconds"] + 15)
        auto_freed = assert_freed(restored, auto_asleep)
        auto_wake_start = time.perf_counter()
        auto_wake = request(base, "/request")
        auto_request_ms = round((time.perf_counter() - auto_wake_start) * 1000)
        if not auto_wake["woke"] or auto_wake["child"]["identity"] != original["identity"]:
            raise RuntimeError("automatic sleep did not restore the original child identity")
        deadline = time.monotonic() + 8
        while auto_wake["child"]["counter"] <= auto_asleep["counter"]:
            if time.monotonic() >= deadline:
                raise RuntimeError("child counter did not advance after automatic wake")
            time.sleep(0.25)
            auto_child = request(base, "/request")["child"]
            auto_wake["child"] = auto_child
        final = request(base, "/status")
        outcome = {
            "baseline": baseline,
            "original_child": original,
            "sleep_result": sleep_result,
            "asleep": asleep,
            "wake_result": wake_result,
            "wake_request_ms": wake_request_ms,
            "restored": restored,
            "first_cycle_bytes_freed": first_freed,
            "auto_asleep": auto_asleep,
            "auto_cycle_bytes_freed": auto_freed,
            "auto_wake_result": auto_wake,
            "auto_request_ms": auto_request_ms,
            "final": final,
        }
        print(json.dumps(outcome, indent=2))
        if final["child_rss_kib"] is None or final["child_rss_kib"] < 64 * 1024:
            raise RuntimeError("restored child RSS is unexpectedly low")
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
    except (RuntimeError, URLError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
