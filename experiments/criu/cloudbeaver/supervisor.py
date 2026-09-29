"""Disposable same-Pod CloudBeaver checkpoint experiment; not a production proxy."""

import http.client
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


STATE = Path("/state")
SNAPSHOTS = STATE / "checkpoints"
WORKSPACE = Path("/opt/cloudbeaver/workspace")
APP_UID = APP_GID = 8978
APP_PORT = 8978
FRONT_PORT = 8080
CONTROL_PORT = 8082
IDLE_SECONDS = int(os.environ.get("IDLE_SECONDS", "45"))
LOCK = threading.RLock()
HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
               "te", "trailer", "transfer-encoding", "upgrade"}


def read_number(path):
    try:
        return int(Path(path).read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def cgroup_memory():
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
    except (FileNotFoundError, PermissionError):
        pass
    return values


def process_start_ticks(pid):
    try:
        # The comm field is parenthesized and can contain spaces.
        return int(Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[19])
    except (FileNotFoundError, ValueError, IndexError):
        return None


def pilot_identity(pid):
    try:
        for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
            if item.startswith(b"CRIU_PILOT_ID="):
                return item.partition(b"=")[2].decode()
    except (FileNotFoundError, PermissionError):
        pass
    return None


def flush_checkpoint(directory):
    for path in directory.rglob("*"):
        if path.is_file():
            fd = os.open(path, os.O_RDONLY)
            try:
                os.fsync(fd)
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
            finally:
                os.close(fd)


def criu(command):
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/opt/criu-libs"
    return subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)


class Supervisor:
    def __init__(self):
        STATE.mkdir(exist_ok=True)
        SNAPSHOTS.mkdir(exist_ok=True)
        WORKSPACE.mkdir(exist_ok=True)
        os.chown(WORKSPACE, APP_UID, APP_GID)
        env = os.environ.copy()
        env["HOME"] = "/home/dbeaver"
        env["CRIU_PILOT_ID"] = secrets.token_hex(16)  # Only the child retains this identity.
        # Original image's launch-product.sh enters the same UID before execing this script.
        with open(os.devnull, "rb") as stdin, open(STATE / "cloudbeaver.log", "ab") as output:
            self.child = subprocess.Popen(
                ["./run-cloudbeaver-server.sh"], cwd="/opt/cloudbeaver", env=env,
                stdin=stdin, stdout=output, stderr=subprocess.STDOUT,
                user=APP_UID, group=APP_GID, start_new_session=True, close_fds=True,
            )
        self.pid = self.child.pid
        del env
        self.phase = "running"
        self.checkpoint = None
        self.cycle = 0
        self.last_request = time.monotonic()
        self.has_served_request = False
        self.last_error = None

    def backend_ready(self):
        if self.phase != "running":
            return False
        try:
            connection = http.client.HTTPConnection("127.0.0.1", APP_PORT, timeout=2)
            connection.request("GET", "/status", headers={"Connection": "close"})
            response = connection.getresponse()
            response.read()
            connection.close()
            return 200 <= response.status < 400
        except (OSError, http.client.HTTPException):
            return False

    def status(self):
        archive_bytes = 0
        if self.checkpoint is not None:
            archive_bytes = sum(p.stat().st_size for p in self.checkpoint.rglob("*") if p.is_file())
        return {
            "phase": self.phase, "pid": self.pid if self.phase == "running" else None,
            "pilot_identity": pilot_identity(self.pid) if self.phase == "running" else None,
            "process_start_ticks": process_start_ticks(self.pid) if self.phase == "running" else None,
            "backend_ready": self.backend_ready(),
            "cgroup_memory_bytes": cgroup_memory(), "checkpoint_bytes": archive_bytes,
            "cycle": self.cycle, "idle_after_seconds": IDLE_SECONDS,
            "idle_seconds": round(time.monotonic() - self.last_request, 2),
            "last_error": self.last_error,
        }

    def reap(self):
        if self.child is not None:
            self.child.wait(timeout=10)
            self.child = None
            return
        deadline = time.monotonic() + 10
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
        raise RuntimeError(f"dumped process {self.pid} did not exit")

    def sleep(self):
        if self.phase != "running":
            raise RuntimeError(f"cannot checkpoint from {self.phase}")
        if not self.backend_ready():
            raise RuntimeError("CloudBeaver /status is not ready")
        start = time.monotonic()
        if self.checkpoint is not None:
            shutil.rmtree(self.checkpoint)  # A prior successfully restored archive only.
        self.cycle += 1
        self.checkpoint = SNAPSHOTS / f"cycle-{self.cycle}"
        self.checkpoint.mkdir()
        result = criu(["criu", "dump", "--tree", str(self.pid),
                       "--images-dir", str(self.checkpoint), "--log-file", "dump.log",
                       "--verbosity=4", "--file-locks"])
        if result.returncode:
            raise RuntimeError(f"CRIU dump failed: {result.stderr[-500:]} (see {self.checkpoint}/dump.log)")
        self.phase = "asleep"  # Archive is authoritative once dump killed the process.
        self.reap()
        flush_checkpoint(self.checkpoint)
        self.last_error = None
        return {"phase": self.phase, "cycle": self.cycle,
                "dump_ms": round((time.monotonic() - start) * 1000)}

    def wake(self):
        if self.phase != "asleep":
            raise RuntimeError(f"cannot restore from {self.phase}")
        start = time.monotonic()
        pidfile = self.checkpoint / "restored.pid"
        result = criu(["criu", "restore", "--images-dir", str(self.checkpoint),
                       "--log-file", "restore.log", "--verbosity=4", "--restore-detached",
                       "--pidfile", str(pidfile), "--manage-cgroups=ignore", "--file-locks"])
        if result.returncode:
            self.phase = "restore_failed"  # Do not retry an ambiguous partial restore.
            raise RuntimeError(f"CRIU restore failed: {result.stderr[-500:]} (see {self.checkpoint}/restore.log)")
        self.pid = read_number(pidfile) or self.pid
        self.phase = "running"
        self.last_request = time.monotonic()
        flush_checkpoint(self.checkpoint)
        self.last_error = None
        return {"phase": self.phase, "pid": self.pid, "cycle": self.cycle,
                "restore_ms": round((time.monotonic() - start) * 1000)}


SUPERVISOR = Supervisor()


class BaseHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_json(self, code, value):
        payload = json.dumps(value).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.close_connection = True


class ControlHandler(BaseHandler):
    def do_GET(self):
        if self.path != "/status":
            return self.send_json(404, {"error": "unknown path"})
        with LOCK:
            status = SUPERVISOR.status()
        self.send_json(503 if status["phase"] == "restore_failed" else 200, status)

    def do_POST(self):
        with LOCK:
            try:
                if self.path == "/sleep":
                    return self.send_json(200, SUPERVISOR.sleep())
                if self.path == "/wake":
                    return self.send_json(200, SUPERVISOR.wake())
                self.send_json(404, {"error": "unknown path"})
            except Exception as error:
                SUPERVISOR.last_error = str(error)
                self.send_json(500, {"error": str(error)})


class FrontHandler(BaseHandler):
    def do_GET(self):
        self.proxy()

    def do_HEAD(self):
        self.proxy()

    def do_POST(self):
        self.proxy()

    def proxy(self):
        # Deliberately HTTP/1.1 only; WebSocket/streaming and concurrent app traffic
        # are out of scope for this app-compatibility pilot.
        if self.headers.get("Transfer-Encoding"):
            return self.send_json(501, {"error": "chunked request not supported by pilot proxy"})
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1024 * 1024:
            return self.send_json(413, {"error": "pilot request exceeds 1 MiB"})
        body = self.rfile.read(length) if length else None
        with LOCK:  # Do not dump while proxying a request or its response.
            try:
                if SUPERVISOR.phase == "asleep":
                    SUPERVISOR.wake()
                if SUPERVISOR.phase != "running":
                    raise RuntimeError(f"CloudBeaver is {SUPERVISOR.phase}")
                connection = http.client.HTTPConnection("127.0.0.1", APP_PORT, timeout=30)
                headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}
                headers["Connection"] = "close"
                connection.request(self.command, self.path, body=body, headers=headers)
                response = connection.getresponse()
                payload = response.read()
                self.send_response(response.status, response.reason)
                for name, value in response.getheaders():
                    if name.lower() not in HOP_HEADERS and name.lower() != "content-length":
                        self.send_header(name, value)
                self.send_header("Content-Length", str(len(payload)))
                self.send_header("Connection", "close")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(payload)
                self.close_connection = True
                connection.close()
                SUPERVISOR.last_request = time.monotonic()
                SUPERVISOR.has_served_request = True
            except Exception as error:
                SUPERVISOR.last_error = str(error)
                self.send_json(502, {"error": str(error)})


def serve(server):
    server.daemon_threads = True
    server.serve_forever(poll_interval=0.2)


front = ThreadingHTTPServer(("0.0.0.0", FRONT_PORT), FrontHandler)
control = ThreadingHTTPServer(("127.0.0.1", CONTROL_PORT), ControlHandler)
threading.Thread(target=serve, args=(front,), daemon=True).start()
threading.Thread(target=serve, args=(control,), daemon=True).start()

while True:
    time.sleep(1)
    with LOCK:
        if (SUPERVISOR.phase == "running" and SUPERVISOR.has_served_request
                and time.monotonic() - SUPERVISOR.last_request >= IDLE_SECONDS):
            try:
                SUPERVISOR.sleep()
            except Exception as error:
                SUPERVISOR.last_error = str(error)
                SUPERVISOR.last_request = time.monotonic()  # Back off before retry.
