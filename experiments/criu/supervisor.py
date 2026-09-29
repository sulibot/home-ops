"""Same-Pod CRIU probe: auto-sleep an HTTP child and wake on a request."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.request import urlopen


STATE = Path("/state")
SNAPSHOTS = STATE / "checkpoints"
STATE.mkdir(exist_ok=True)
SNAPSHOTS.mkdir(exist_ok=True)
IDLE_SECONDS = int(os.environ.get("IDLE_SECONDS", "30"))
LOCK = threading.RLock()


def launch():
    with open(os.devnull, "rb") as stdin, open(os.devnull, "ab") as output:
        return subprocess.Popen(
            ["python3", "/opt/criu-demo/workload.py"],
            stdin=stdin,
            stdout=output,
            stderr=output,
            start_new_session=True,
            close_fds=True,
        )


def read_number(path):
    try:
        return int(Path(path).read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def rss_kib(process_id):
    try:
        for line in Path(f"/proc/{process_id}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    except FileNotFoundError:
        pass
    return None


def cgroup_memory():
    # Privileged Pods can see the host cgroup mount; resolve our own path.
    root = Path("/sys/fs/cgroup")
    for line in Path("/proc/self/cgroup").read_text().splitlines():
        if line.startswith("0::"):
            root = root / line.partition("0::")[2].lstrip("/")
            break
    values = {"current": read_number(root / "memory.current")}
    try:
        for line in (root / "memory.stat").read_text().splitlines():
            name, number = line.split()
            if name in ("anon", "file", "shmem"):
                values[name] = int(number)
    except FileNotFoundError:
        pass
    return values


def flush_checkpoint(directory):
    # Evict only this archive's file cache; do not drop node-wide caches.
    for path in directory.rglob("*"):
        if path.is_file():
            fd = os.open(path, os.O_RDONLY)
            try:
                os.fsync(fd)
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            finally:
                os.close(fd)


class Supervisor:
    def __init__(self):
        self.child = launch()
        self.pid = self.child.pid
        self.phase = "running"
        self.checkpoint = None
        self.cycle = 0
        self.last_request = time.monotonic()
        self.last_error = None

    def status(self):
        checkpoint_bytes = 0
        if self.checkpoint is not None:
            checkpoint_bytes = sum(path.stat().st_size for path in self.checkpoint.rglob("*") if path.is_file())
        return {
            "phase": self.phase,
            "pid": self.pid if self.phase == "running" else None,
            "child_rss_kib": rss_kib(self.pid) if self.phase == "running" else None,
            "counter": read_number(STATE / "counter"),
            "cgroup_memory_bytes": cgroup_memory(),
            "checkpoint_bytes": checkpoint_bytes,
            "cycle": self.cycle,
            "idle_seconds": round(time.monotonic() - self.last_request, 2),
            "idle_after_seconds": IDLE_SECONDS,
            "last_error": self.last_error,
        }

    def reap_child(self):
        if self.child is not None:
            self.child.wait(timeout=5)
            self.child = None
            return
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                reaped, _ = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                if not Path(f"/proc/{self.pid}").exists():
                    return
                raise
            if reaped == self.pid:
                return
            time.sleep(0.05)
        raise RuntimeError(f"dumped child PID {self.pid} did not exit")

    def sleep(self):
        if self.phase != "running":
            raise RuntimeError(f"cannot sleep from {self.phase}")
        start = time.monotonic()
        if self.checkpoint is not None:
            shutil.rmtree(self.checkpoint)  # Only our prior, successfully restored archive.
        self.cycle += 1
        self.checkpoint = SNAPSHOTS / f"cycle-{self.cycle}"
        self.checkpoint.mkdir()
        command = ["criu", "dump", "--tree", str(self.pid), "--images-dir", str(self.checkpoint),
                   "--log-file", "dump.log", "--verbosity=4"]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError(f"dump failed: {result.stderr[-1000:]} (log {self.checkpoint / 'dump.log'})")
        self.phase = "asleep"  # CRIU has terminated the child; archive is now authoritative.
        self.reap_child()
        flush_checkpoint(self.checkpoint)
        self.last_error = None
        return {"phase": self.phase, "cycle": self.cycle,
                "dump_ms": round((time.monotonic() - start) * 1000)}

    def wake(self):
        if self.phase != "asleep":
            raise RuntimeError(f"cannot wake from {self.phase}")
        start = time.monotonic()
        pidfile = self.checkpoint / "restored.pid"
        command = ["criu", "restore", "--images-dir", str(self.checkpoint),
                   "--log-file", "restore.log", "--verbosity=4",
                   "--restore-detached", "--pidfile", str(pidfile),
                   "--manage-cgroups=ignore"]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError(f"restore failed: {result.stderr[-1000:]} (log {self.checkpoint / 'restore.log'})")
        self.pid = read_number(pidfile) or self.pid
        self.phase = "running"
        self.last_request = time.monotonic()
        flush_checkpoint(self.checkpoint)
        self.last_error = None
        return {"phase": self.phase, "pid": self.pid, "cycle": self.cycle,
                "restore_ms": round((time.monotonic() - start) * 1000)}

    def request_child(self):
        wake_result = self.wake() if self.phase == "asleep" else None
        with urlopen("http://127.0.0.1:8081/state", timeout=5) as response:
            child_state = json.load(response)
        self.last_request = time.monotonic()
        return {"child": child_state, "woke": wake_result is not None,
                "restore_ms": wake_result["restore_ms"] if wake_result else None}


SUPERVISOR = Supervisor()


class Handler(BaseHTTPRequestHandler):
    def respond(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        with LOCK:
            if self.path == "/status":
                return self.respond(200, SUPERVISOR.status())
            if self.path == "/request":
                try:
                    return self.respond(200, SUPERVISOR.request_child())
                except Exception as error:
                    SUPERVISOR.last_error = str(error)
                    return self.respond(500, {"error": str(error)})
            self.respond(404, {"error": "unknown path"})

    def do_POST(self):
        with LOCK:
            try:
                if self.path == "/sleep":
                    return self.respond(200, SUPERVISOR.sleep())
                if self.path == "/wake":
                    return self.respond(200, SUPERVISOR.wake())
                self.respond(404, {"error": "unknown path"})
            except Exception as error:
                SUPERVISOR.last_error = str(error)
                self.respond(500, {"error": str(error)})


server = HTTPServer(("127.0.0.1", 8080), Handler)
server.timeout = 0.5
while True:
    server.handle_request()
    with LOCK:
        if SUPERVISOR.phase == "running" and time.monotonic() - SUPERVISOR.last_request >= IDLE_SECONDS:
            try:
                SUPERVISOR.sleep()
            except Exception as error:
                SUPERVISOR.last_error = str(error)
                SUPERVISOR.last_request = time.monotonic()  # Back off before retrying.
