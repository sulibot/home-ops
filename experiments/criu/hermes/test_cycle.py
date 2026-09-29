#!/usr/bin/env python3
"""Disposable Hermes dashboard two-cycle Zeropod smoke; prints no credentials."""

import argparse
import http.cookiejar
import json
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPCookieProcessor, Request, build_opener, urlopen


CLIENT_PROBE = r"""
import http.client, json, sys, time
host = sys.argv[1]
def get(port, path):
    conn = http.client.HTTPConnection(host, port, timeout=120)
    start = time.monotonic()
    conn.request('GET', path)
    response = conn.getresponse()
    body = response.read()
    elapsed = round((time.monotonic() - start) * 1000)
    conn.close()
    if response.status != 200:
        raise RuntimeError(f'GET {path} returned HTTP {response.status}: {body[:120]!r}')
    return json.loads(body), elapsed
status, wake_ms = get(9119, '/api/status')
identity, _ = get(9118, '/identity')
print(json.dumps({'auth_required': status.get('auth_required'),
                  'auth_providers': status.get('auth_providers'),
                  'identity': identity['identity'], 'counter': identity['counter'],
                  'dashboard_request_ms': wake_ms}))
"""


def run(command, timeout=30):
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command[:5])}: {result.stderr.strip()}")
    return result.stdout


def probe_from_client(kubectl, pod_ip):
    output = run(kubectl + ["exec", "pod/hermes-tcp-client", "--", "python3", "-c", CLIENT_PROBE, pod_ip], 150)
    value = json.loads(output)
    if value["auth_required"] is not True or "basic" not in value["auth_providers"]:
        raise RuntimeError(f"dashboard authentication gate is not active: {value}")
    return value


def pod_ipv4(kubectl):
    pod = json.loads(run(kubectl + ["get", "pod/hermes-dashboard-checkpoint", "-o", "json"]))
    for item in pod["status"].get("podIPs", []):
        address = item["ip"]
        if ":" not in address:
            return address
    raise RuntimeError("dashboard Pod has no IPv4 address for its 0.0.0.0 listener")


def memory_mib(kubectl):
    output = run(kubectl + ["top", "pod", "hermes-dashboard-checkpoint", "--containers", "--no-headers"])
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 4 and fields[1] == "dashboard":
            match = re.fullmatch(r"(\d+)(Ki|Mi|Gi)", fields[3])
            if not match:
                raise RuntimeError(f"unexpected kubectl top memory unit: {fields[3]}")
            multiplier = {"Ki": 1 / 1024, "Mi": 1, "Gi": 1024}[match.group(2)]
            return int(match.group(1)) * multiplier
    raise RuntimeError("dashboard container not found in kubectl top output")


def wait_sleep_memory(kubectl, baseline_mib, timeout):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = memory_mib(kubectl)
            if baseline_mib - last >= 64 and last <= 64:
                return last
        except RuntimeError:
            pass
        time.sleep(5)
    raise RuntimeError(f"no convincing memory reduction before wake: baseline={baseline_mib} MiB, last={last} MiB")


def wait_awake_memory(kubectl, timeout=90):
    # Metrics-server can briefly keep the previous asleep sample after wake.
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = memory_mib(kubectl)
            if last >= 80:
                return last
        except RuntimeError:
            pass
        time.sleep(5)
    raise RuntimeError(f"no fresh awake memory sample (last={last} MiB)")


def auth_check(kubectl, password, local_port):
    command = kubectl + ["port-forward", "--address", "127.0.0.1",
                         "pod/hermes-dashboard-checkpoint", f"{local_port}:9119"]
    forward = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base = f"http://127.0.0.1:{local_port}"
    try:
        for _ in range(60):
            if forward.poll() is not None:
                raise RuntimeError(f"kubectl port-forward exited ({forward.returncode})")
            try:
                with urlopen(base + "/api/status", timeout=3) as response:
                    status = json.load(response)
                break
            except (URLError, TimeoutError):
                time.sleep(0.5)
        else:
            raise RuntimeError("port-forwarded dashboard status did not become reachable")
        if status.get("auth_required") is not True or "basic" not in status.get("auth_providers", []):
            raise RuntimeError("dashboard did not advertise the basic auth gate")
        cookies = http.cookiejar.CookieJar()
        opener = build_opener(HTTPCookieProcessor(cookies))
        body = json.dumps({"provider": "basic", "username": "pilot", "password": password}).encode()
        request = Request(base + "/auth/password-login", data=body,
                          headers={"Content-Type": "application/json"}, method="POST")
        with opener.open(request, timeout=15) as response:
            response.read()
            if response.status != 200:
                raise RuntimeError(f"login returned HTTP {response.status}")
        if not list(cookies):
            raise RuntimeError("login issued no session cookie")
        with opener.open(base + "/api/auth/me", timeout=15) as response:
            response.read()
            if response.status != 200:
                raise RuntimeError(f"authenticated /api/auth/me returned HTTP {response.status}")
        return True
    except HTTPError as error:
        raise RuntimeError(f"dashboard login/auth check returned HTTP {error.code}") from error
    finally:
        forward.terminate()
        try:
            forward.wait(timeout=5)
        except subprocess.TimeoutExpired:
            forward.kill()
            forward.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kubeconfig", required=True)
    parser.add_argument("--cycles", type=int, default=2)
    parser.add_argument("--local-port", type=int, default=19119)
    parser.add_argument("--sleep-timeout", type=int, default=150)
    args = parser.parse_args()
    kubectl = ["kubectl", "--kubeconfig", args.kubeconfig, "-n", "criu-hermes-pilot"]
    for pod in ("hermes-dashboard-checkpoint", "hermes-tcp-client"):
        run(kubectl + ["wait", "--for=condition=Ready", f"pod/{pod}", "--timeout=600s"], 610)
    pod_ip = pod_ipv4(kubectl)
    # Capture the throwaway password in memory only; never print it or its hash.
    password = run(kubectl + ["exec", "pod/hermes-dashboard-checkpoint", "--",
                              "cat", "/auth/password"]).strip()
    if not password:
        raise RuntimeError("pilot bootstrap did not create a password")
    initial = probe_from_client(kubectl, pod_ip)
    auth_check(kubectl, password, args.local_port)
    identity = initial["identity"]
    prior_counter = initial["counter"]
    results = []
    for cycle in range(1, args.cycles + 1):
        baseline = wait_awake_memory(kubectl)
        asleep = wait_sleep_memory(kubectl, baseline, args.sleep_timeout)
        restored = probe_from_client(kubectl, pod_ip)
        if restored["identity"] != identity or restored["counter"] <= prior_counter:
            raise RuntimeError(f"cycle {cycle}: memory-only identity/counter did not survive restore")
        auth_check(kubectl, password, args.local_port)
        results.append({"cycle": cycle, "before_mib": baseline, "asleep_mib": asleep,
                        "dashboard_wake_request_ms": restored["dashboard_request_ms"],
                        "identity_preserved": True, "old_password_still_valid": True})
        prior_counter = restored["counter"]
    print(json.dumps({"initial_auth_gate": True, "initial_login": True,
                      "cycles": results,
                      "note": "Confirm matching Zeropod checkpoint/restore logs before calling CRIU validated."}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
