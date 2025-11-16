#!/usr/bin/env python3
"""Validate Terraform-generated talenv.yaml files before rendering."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ModuleNotFoundError:  # pragma: no cover - optional dependency
    yaml = None


REQUIRED_GLOBAL_KEYS = [
    "clusterName",
    "talosVersion",
    "kubernetesVersion",
    "endpoint",
    "pods_ipv4",
    "pods_ipv6",
    "services_ipv4",
    "services_ipv6",
]
REQUIRED_NODE_KEYS = ["hostname", "controlPlane"]


def validate_file(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"talenv file not found: {path}")

    data = _load_yaml(path)

    missing = [key for key in REQUIRED_GLOBAL_KEYS if not data.get(key)]
    if missing:
        raise ValueError(
            f"Missing required keys in {path}: {', '.join(sorted(missing))}"
        )

    nodes = data.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        raise ValueError(f"'nodes' must be a non-empty list in {path}")

    for idx, node in enumerate(nodes, start=1):
        if not isinstance(node, dict):
            raise ValueError(f"Node #{idx} is not a mapping")
        node_missing = [key for key in REQUIRED_NODE_KEYS if key not in node]
        if node_missing:
            raise ValueError(
                f"Node #{idx} missing keys: {', '.join(sorted(node_missing))}"
            )
        ip_address = node.get("ipAddress") or node.get("publicIPv4") or node.get(
            "publicIPv6"
        )
        if not ip_address:
            raise ValueError(f"Node #{idx} ({node.get('hostname')}) missing IP address")


def _load_yaml(path: Path) -> dict:
    if yaml is not None:
        return yaml.safe_load(path.read_text()) or {}

    # Fall back to yq CLI if PyYAML is unavailable.
    try:
        result = subprocess.run(
            ["yq", "-o=json", str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:  # pragma: no cover - env specific
        raise RuntimeError(
            "PyYAML module missing and 'yq' CLI not found. "
            "Install one of them to validate talenv.yaml files."
        ) from exc
    return json.loads(result.stdout or "{}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate talenv.yaml structure")
    parser.add_argument(
        "--file",
        "-f",
        required=True,
        dest="env_file",
        help="Path to talenv.yaml (e.g. clusters/cluster-101/talenv.yaml)",
    )
    args = parser.parse_args()
    try:
        validate_file(Path(args.env_file))
    except Exception as exc:  # pragma: no cover - CLI reporting
        sys.stderr.write(f"talenv validation failed: {exc}\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
