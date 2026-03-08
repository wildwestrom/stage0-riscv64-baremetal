#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 Christian Westrom
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import argparse
import json
import os
import queue
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
BUILD_DIR = REPO_ROOT / "build"
SESSION_ROOT = BUILD_DIR / "debug" / "current"
MANIFEST_PATH = SESSION_ROOT / "manifest.json"
CONTROL_SOCKET_PATH = SESSION_ROOT / "control.sock"
QEMU_SERIAL_PREFIX = SESSION_ROOT / "serial"
QEMU_SERIAL_IN = SESSION_ROOT / "serial.in"
QEMU_SERIAL_OUT = SESSION_ROOT / "serial.out"
QEMU_LOG_PATH = SESSION_ROOT / "qemu.log"
GDB_LOG_PATH = SESSION_ROOT / "gdb.log"
DAEMON_LOG_PATH = SESSION_ROOT / "daemon.log"
DAEMON_PID_PATH = SESSION_ROOT / "daemon.pid"
DERZFORTH_DEBUG_ELF = BUILD_DIR / "derzforth.debug.elf"
DEFAULT_GDB_PORT = 1234
DEFAULT_TIMEOUT = 10.0
PROMPT_MARKER = " ok"
DEFAULT_LISP_FILES = (
    REPO_ROOT / "derzforth/lexicons/prelude.forth",
    REPO_ROOT / "lexicons/control.forth",
    REPO_ROOT / "lexicons/lisp.forth",
)


class DebugSessionError(RuntimeError):
    pass


def now() -> float:
    return time.time()


def json_dumps(data: Any) -> str:
    return json.dumps(data, sort_keys=True)


def print_json(data: Any) -> None:
    print(json_dumps(data))


def ensure_session_root() -> None:
    SESSION_ROOT.mkdir(parents=True, exist_ok=True)


def write_manifest(data: dict[str, Any]) -> None:
    ensure_session_root()
    MANIFEST_PATH.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def read_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        raise DebugSessionError("no active debug session")
    return json.loads(MANIFEST_PATH.read_text())


def cleanup_session_root() -> None:
    if SESSION_ROOT.exists():
        shutil.rmtree(SESSION_ROOT)


def choose_free_tcp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return int(sock.getsockname()[1])


def terminate_pid(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 2.0
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return


def best_effort_stop_existing_session() -> None:
    try:
        manifest = read_manifest()
    except DebugSessionError:
        cleanup_session_root()
        return

    try:
        send_request({"command": "stop", "args": {}})
        time.sleep(0.2)
    except Exception:
        pid = manifest.get("daemon_pid")
        if isinstance(pid, int):
            terminate_pid(pid)
    cleanup_session_root()


def wait_for_socket(path: Path, timeout: float) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
                    sock.settimeout(0.2)
                    sock.connect(str(path))
                return
            except OSError:
                pass
        time.sleep(0.05)
    raise DebugSessionError(f"timed out waiting for control socket at {path}")


def send_request(payload: dict[str, Any]) -> dict[str, Any]:
    manifest = read_manifest()
    socket_path = Path(manifest["control_socket"])
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(str(socket_path))
        message = json.dumps(payload).encode("utf-8") + b"\n"
        sock.sendall(message)
        chunks: list[bytes] = []
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    if not chunks:
        raise DebugSessionError("daemon closed the control socket without a response")
    return json.loads(b"".join(chunks).decode("utf-8"))


class MiParser:
    def __init__(self, text: str):
        self.text = text
        self.pos = 0

    def parse_result_list(self) -> dict[str, Any]:
        result: dict[str, Any] = {}
        while self.pos < len(self.text):
            key, value = self.parse_result()
            if key in result:
                existing = result[key]
                if isinstance(existing, list):
                    existing.append(value)
                else:
                    result[key] = [existing, value]
            else:
                result[key] = value
            if self.pos >= len(self.text) or self.text[self.pos] != ",":
                break
            self.pos += 1
        return result

    def parse_result(self) -> tuple[str, Any]:
        key = self.parse_identifier()
        self.expect("=")
        return key, self.parse_value()

    def parse_value(self) -> Any:
        self.skip_ws()
        if self.pos >= len(self.text):
            return ""
        ch = self.text[self.pos]
        if ch == '"':
            return self.parse_string()
        if ch == "{":
            return self.parse_tuple()
        if ch == "[":
            return self.parse_list()
        return self.parse_identifier(stop_chars=",}]")

    def parse_tuple(self) -> dict[str, Any]:
        self.expect("{")
        result: dict[str, Any] = {}
        while self.pos < len(self.text) and self.text[self.pos] != "}":
            key, value = self.parse_result()
            if key in result:
                existing = result[key]
                if isinstance(existing, list):
                    existing.append(value)
                else:
                    result[key] = [existing, value]
            else:
                result[key] = value
            if self.pos < len(self.text) and self.text[self.pos] == ",":
                self.pos += 1
        self.expect("}")
        return result

    def parse_list(self) -> list[Any]:
        items: list[Any] = []
        self.expect("[")
        while self.pos < len(self.text) and self.text[self.pos] != "]":
            if self.looks_like_result():
                key, value = self.parse_result()
                items.append({key: value})
            else:
                items.append(self.parse_value())
            if self.pos < len(self.text) and self.text[self.pos] == ",":
                self.pos += 1
        self.expect("]")
        return items

    def parse_identifier(self, stop_chars: str = "=,}]") -> str:
        start = self.pos
        while self.pos < len(self.text) and self.text[self.pos] not in stop_chars:
            self.pos += 1
        return self.text[start:self.pos]

    def parse_string(self) -> str:
        self.expect('"')
        chars: list[str] = []
        while self.pos < len(self.text):
            ch = self.text[self.pos]
            self.pos += 1
            if ch == '"':
                break
            if ch != "\\":
                chars.append(ch)
                continue
            if self.pos >= len(self.text):
                break
            esc = self.text[self.pos]
            self.pos += 1
            mapping = {
                '"': '"',
                "\\": "\\",
                "/": "/",
                "b": "\b",
                "f": "\f",
                "n": "\n",
                "r": "\r",
                "t": "\t",
            }
            if esc in mapping:
                chars.append(mapping[esc])
                continue
            if esc.isdigit():
                oct_digits = esc
                for _ in range(2):
                    if self.pos < len(self.text) and self.text[self.pos].isdigit():
                        oct_digits += self.text[self.pos]
                        self.pos += 1
                    else:
                        break
                chars.append(chr(int(oct_digits, 8)))
                continue
            chars.append(esc)
        return "".join(chars)

    def looks_like_result(self) -> bool:
        i = self.pos
        while i < len(self.text):
            ch = self.text[i]
            if ch == "=":
                return True
            if ch in ",]}":
                return False
            if ch in '"[{':
                return False
            i += 1
        return False

    def expect(self, value: str) -> None:
        if self.pos >= len(self.text) or self.text[self.pos] != value:
            raise DebugSessionError(f"expected {value!r} in MI payload: {self.text!r}")
        self.pos += 1

    def skip_ws(self) -> None:
        while self.pos < len(self.text) and self.text[self.pos].isspace():
            self.pos += 1


def parse_mi_record(line: str) -> dict[str, Any]:
    if line.strip() == "(gdb)":
        return {"kind": "prompt"}
    if not line:
        return {"kind": "empty"}
    if line[0] in "~@&":
        parser = MiParser(line[1:])
        return {
            "kind": "stream",
            "stream": {"~": "console", "@": "target", "&": "log"}[line[0]],
            "payload": parser.parse_value(),
            "raw": line,
        }

    pos = 0
    while pos < len(line) and line[pos].isdigit():
        pos += 1
    token = int(line[:pos]) if pos else None
    if pos >= len(line):
        return {"kind": "other", "raw": line}

    record_type = line[pos]
    rest = line[pos + 1 :]
    if record_type in "^*=+":
        if "," in rest:
            record_class, payload_text = rest.split(",", 1)
            payload = MiParser(payload_text).parse_result_list()
        else:
            record_class = rest
            payload = {}
        return {
            "kind": {"^": "result", "*": "exec", "=": "notify", "+": "status"}[record_type],
            "token": token,
            "class": record_class,
            "payload": payload,
            "raw": line,
        }
    return {"kind": "other", "raw": line}


class GdbMiClient:
    def __init__(self, executable: Path, port: int, log_path: Path):
        self.executable = executable
        self.port = port
        self.log_file = log_path.open("w", buffering=1, encoding="utf-8")
        self.proc = subprocess.Popen(
            [
                "riscv64-none-elf-gdb",
                "--quiet",
                "--nx",
                "--nh",
                "--interpreter=mi2",
                str(self.executable),
            ],
            cwd=REPO_ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        if self.proc.stdin is None or self.proc.stdout is None:
            raise DebugSessionError("failed to start gdb/mi")
        self.stdin = self.proc.stdin
        self.queue: queue.Queue[dict[str, Any]] = queue.Queue()
        self.command_lock = threading.Lock()
        self.token = 1
        self.closed = False
        self.reader = threading.Thread(target=self._reader_loop, daemon=True)
        self.reader.start()
        self.last_stop: dict[str, Any] | None = None
        self.state = "starting"
        self.register_names: list[str] | None = None
        self._drain_initial_output()
        self.send("-gdb-set mi-async on")
        self.send("-gdb-set architecture riscv:rv64")
        self.send(f"-target-select remote localhost:{self.port}")
        self.state = "stopped"

    def _reader_loop(self) -> None:
        assert self.proc.stdout is not None
        for raw_line in self.proc.stdout:
            line = raw_line.rstrip("\n")
            self.log_file.write(line + "\n")
            record = parse_mi_record(line)
            if record["kind"] == "exec" and record.get("class") == "stopped":
                self.last_stop = record
                self.state = "stopped"
            self.queue.put(record)
        self.closed = True
        self.queue.put({"kind": "eof"})

    def _drain_initial_output(self) -> None:
        deadline = time.time() + 10.0
        while time.time() < deadline:
            try:
                record = self.queue.get(timeout=0.5)
            except queue.Empty:
                continue
            if record["kind"] == "prompt":
                return
            if record["kind"] == "eof":
                raise DebugSessionError("gdb/mi exited before becoming ready")
        raise DebugSessionError("timed out waiting for the initial gdb/mi prompt")

    def _next_token(self) -> int:
        token = self.token
        self.token += 1
        return token

    def _write_command(self, command: str) -> int:
        if self.closed or self.proc.poll() is not None:
            raise DebugSessionError("gdb/mi is not running")
        token = self._next_token()
        self.stdin.write(f"{token}{command}\n")
        self.stdin.flush()
        return token

    def _await_result(self, token: int, timeout: float) -> dict[str, Any]:
        deadline = time.time() + timeout
        records: list[dict[str, Any]] = []
        while time.time() < deadline:
            remaining = max(0.05, deadline - time.time())
            try:
                record = self.queue.get(timeout=remaining)
            except queue.Empty as exc:
                raise DebugSessionError(f"timed out waiting for gdb response to token {token}") from exc
            if record["kind"] == "eof":
                raise DebugSessionError("gdb/mi exited unexpectedly")
            if record["kind"] == "prompt":
                continue
            records.append(record)
            if record["kind"] == "result" and record.get("token") == token:
                return {
                    "result": record,
                    "records": records,
                }
        raise DebugSessionError(f"timed out waiting for gdb response to token {token}")

    def _await_stop(self, timeout: float) -> dict[str, Any]:
        deadline = time.time() + timeout
        records: list[dict[str, Any]] = []
        while time.time() < deadline:
            remaining = max(0.05, deadline - time.time())
            try:
                record = self.queue.get(timeout=remaining)
            except queue.Empty as exc:
                raise DebugSessionError("timed out waiting for target stop") from exc
            if record["kind"] == "eof":
                raise DebugSessionError("gdb/mi exited unexpectedly")
            if record["kind"] == "prompt":
                continue
            records.append(record)
            if record["kind"] == "exec" and record.get("class") == "stopped":
                self.last_stop = record
                self.state = "stopped"
                return {
                    "stop": record,
                    "records": records,
                }
        raise DebugSessionError("timed out waiting for target stop")

    def send(self, command: str, timeout: float = DEFAULT_TIMEOUT) -> dict[str, Any]:
        with self.command_lock:
            token = self._write_command(command)
            reply = self._await_result(token, timeout)
            result = reply["result"]
            if result["class"] == "error":
                message = result["payload"].get("msg", "gdb command failed")
                raise DebugSessionError(message)
            if result["class"] == "running":
                self.state = "running"
            return reply

    def continue_until_stop(self, command: str, timeout: float = DEFAULT_TIMEOUT) -> dict[str, Any]:
        with self.command_lock:
            token = self._write_command(command)
            reply = self._await_result(token, timeout)
            result = reply["result"]
            if result["class"] == "error":
                message = result["payload"].get("msg", "gdb command failed")
                raise DebugSessionError(message)
            if result["class"] != "running":
                return reply
            self.state = "running"
            stop = self._await_stop(timeout)
            reply["stop"] = stop["stop"]
            reply["records"].extend(stop["records"])
            return reply

    def interrupt(self, timeout: float = DEFAULT_TIMEOUT) -> dict[str, Any]:
        with self.command_lock:
            token = self._write_command("-exec-interrupt --all")
            reply = self._await_result(token, timeout)
            result = reply["result"]
            if result["class"] == "error":
                message = result["payload"].get("msg", "gdb interrupt failed")
                raise DebugSessionError(message)
            if self.state == "stopped":
                return reply
            stop = self._await_stop(timeout)
            reply["stop"] = stop["stop"]
            reply["records"].extend(stop["records"])
            return reply

    def get_breakpoints(self) -> list[dict[str, Any]]:
        reply = self.send("-break-list")
        payload = reply["result"]["payload"]
        body = payload.get("BreakpointTable", {})
        entries = body.get("body", [])
        breakpoints: list[dict[str, Any]] = []
        for entry in entries:
            if isinstance(entry, dict) and "bkpt" in entry:
                breakpoints.append(entry["bkpt"])
        return breakpoints

    def get_register_names(self) -> list[str]:
        if self.register_names is not None:
            return self.register_names
        reply = self.send("-data-list-register-names")
        names = reply["result"]["payload"].get("register-names", [])
        if not isinstance(names, list):
            raise DebugSessionError("unexpected gdb register name payload")
        self.register_names = [name if isinstance(name, str) and name else f"r{i}" for i, name in enumerate(names)]
        return self.register_names

    def close(self) -> None:
        if self.closed:
            return
        try:
            self.send("-gdb-exit", timeout=2.0)
        except Exception:
            pass
        try:
            self.proc.terminate()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=2.0)
        except Exception:
            self.proc.kill()
        self.closed = True
        self.log_file.close()


class SerialChannel:
    def __init__(self, in_path: Path, out_path: Path):
        self.in_path = in_path
        self.out_path = out_path
        # Open both FIFOs read/write so the harness does not deadlock waiting
        # for QEMU to open the opposite end in a particular order.
        self.in_fd = self._open_with_retry(self.in_path, os.O_RDWR | os.O_NONBLOCK, "serial input")
        self.out_fd = self._open_with_retry(self.out_path, os.O_RDWR | os.O_NONBLOCK, "serial output")
        self.buffer = bytearray()
        self.last_activity = now()
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.reader = threading.Thread(target=self._reader_loop, daemon=True)
        self.reader.start()

    def _open_with_retry(self, path: Path, flags: int, label: str) -> int:
        deadline = time.time() + 5.0
        while time.time() < deadline:
            try:
                return os.open(path, flags)
            except FileNotFoundError:
                time.sleep(0.05)
            except OSError as exc:
                if exc.errno in (6, 11):
                    time.sleep(0.05)
                    continue
                raise DebugSessionError(f"failed to open {label} at {path}: {exc}") from exc
        raise DebugSessionError(f"timed out opening {label} at {path}")

    def _reader_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                chunk = os.read(self.out_fd, 4096)
            except BlockingIOError:
                time.sleep(0.02)
                continue
            except OSError:
                return
            if not chunk:
                time.sleep(0.02)
                continue
            with self.lock:
                self.buffer.extend(chunk)
                self.last_activity = now()

    def write_text(self, text: str) -> int:
        data = text.encode("utf-8")
        total = 0
        while total < len(data):
            try:
                written = os.write(self.in_fd, data[total:])
            except BlockingIOError:
                time.sleep(0.02)
                continue
            total += written
        return total

    def read_text(self, clear: bool = True) -> str:
        with self.lock:
            data = bytes(self.buffer)
            if clear:
                self.buffer.clear()
        return data.decode("utf-8", errors="replace")

    def peek_text(self) -> str:
        with self.lock:
            return bytes(self.buffer).decode("utf-8", errors="replace")

    def clear(self) -> None:
        with self.lock:
            self.buffer.clear()

    def wait_for_marker(self, marker: str, timeout: float) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            text = self.peek_text()
            if marker in text:
                return text
            time.sleep(0.05)
        raise DebugSessionError(f"timed out waiting for serial marker {marker!r}")

    def wait_for_idle(self, idle_seconds: float, timeout: float) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self.lock:
                idle_for = now() - self.last_activity
                text = bytes(self.buffer).decode("utf-8", errors="replace")
            if idle_for >= idle_seconds:
                return text
            time.sleep(0.05)
        raise DebugSessionError("timed out waiting for serial to go idle")

    def close(self) -> None:
        self.stop_event.set()
        try:
            os.close(self.in_fd)
        except OSError:
            pass
        try:
            os.close(self.out_fd)
        except OSError:
            pass


@dataclass
class SessionConfig:
    mode: str
    break_location: str | None
    gdb_port: int
    startup_timeout: float
    pause_after_load: bool


class DebugDaemon:
    def __init__(self, config: SessionConfig):
        self.config = config
        self.shutdown_requested = False
        self.qemu_proc: subprocess.Popen[str] | None = None
        self.gdb: GdbMiClient | None = None
        self.serial: SerialChannel | None = None
        self.last_error: str | None = None

    def setup(self) -> None:
        ensure_session_root()
        DAEMON_PID_PATH.write_text(f"{os.getpid()}\n")
        for fifo in (QEMU_SERIAL_IN, QEMU_SERIAL_OUT):
            try:
                os.mkfifo(fifo)
            except FileExistsError:
                pass

        qemu_log = QEMU_LOG_PATH.open("w", buffering=1, encoding="utf-8")
        self.qemu_proc = subprocess.Popen(
            [
                "qemu-system-riscv64-purecap",
                "-nographic",
                "-monitor",
                "none",
                "-serial",
                f"pipe:{QEMU_SERIAL_PREFIX}",
                "-machine",
                "virt",
                "-bios",
                "none",
                "-kernel",
                str(DERZFORTH_DEBUG_ELF),
                "-gdb",
                f"tcp::{self.config.gdb_port}",
                "-S",
            ],
            cwd=REPO_ROOT,
            stdin=subprocess.DEVNULL,
            stdout=qemu_log,
            stderr=subprocess.STDOUT,
            text=True,
        )

        self.serial = SerialChannel(QEMU_SERIAL_IN, QEMU_SERIAL_OUT)
        self.gdb = GdbMiClient(DERZFORTH_DEBUG_ELF, self.config.gdb_port, GDB_LOG_PATH)

        try:
            if self.config.mode in ("raw", "lisp"):
                self._boot_to_prompt()
            if self.config.mode == "lisp":
                self._load_lisp_files()
        except Exception as exc:
            self.last_error = f"bootstrap failed: {exc}"
        finally:
            if self.config.pause_after_load:
                try:
                    self.gdb.interrupt(timeout=self.config.startup_timeout)
                except Exception as exc:
                    if self.last_error is None:
                        self.last_error = f"interrupt failed: {exc}"
        if self.config.break_location:
            self.gdb.send(f"-break-insert {self.config.break_location}")
        write_manifest(self._manifest(ready=True))

    def _boot_to_prompt(self) -> None:
        assert self.gdb is not None
        assert self.serial is not None
        self.serial.clear()
        self.gdb.send("-exec-continue", timeout=self.config.startup_timeout)
        self.serial.write_text("\n")
        self.serial.wait_for_marker(PROMPT_MARKER, timeout=self.config.startup_timeout)

    def _load_lisp_files(self) -> None:
        assert self.serial is not None
        for forth_file in DEFAULT_LISP_FILES:
            payload = forth_file.read_text() + "\n"
            self.serial.clear()
            self.serial.write_text(payload)
            self.serial.wait_for_idle(idle_seconds=0.2, timeout=self.config.startup_timeout)
            self.serial.wait_for_marker(PROMPT_MARKER, timeout=self.config.startup_timeout)

    def _manifest(self, ready: bool) -> dict[str, Any]:
        return {
            "break_location": self.config.break_location,
            "control_socket": str(CONTROL_SOCKET_PATH),
            "daemon_pid": os.getpid(),
            "elf": str(DERZFORTH_DEBUG_ELF),
            "gdb_log": str(GDB_LOG_PATH),
            "gdb_port": self.config.gdb_port,
            "last_error": self.last_error,
            "mode": self.config.mode,
            "pause_after_load": self.config.pause_after_load,
            "qemu_log": str(QEMU_LOG_PATH),
            "qemu_pid": self.qemu_proc.pid if self.qemu_proc is not None else None,
            "ready": ready,
            "serial_in": str(QEMU_SERIAL_IN),
            "serial_out": str(QEMU_SERIAL_OUT),
            "session_root": str(SESSION_ROOT),
            "target_state": self.gdb.state if self.gdb is not None else "unknown",
        }

    def handle_status(self) -> dict[str, Any]:
        assert self.gdb is not None
        assert self.serial is not None
        breakpoints = self.gdb.get_breakpoints()
        return {
            "breakpoints": breakpoints,
            "last_stop": self.gdb.last_stop,
            "manifest": self._manifest(ready=True),
            "serial_preview": self.serial.peek_text()[-4096:],
            "target_state": self.gdb.state,
        }

    def handle_command(self, command: str, args: dict[str, Any]) -> dict[str, Any]:
        assert self.gdb is not None
        assert self.serial is not None

        if command == "status":
            return self.handle_status()

        if command == "continue":
            timeout = float(args.get("timeout", DEFAULT_TIMEOUT))
            reply = self.gdb.continue_until_stop("-exec-continue", timeout=timeout)
            return {"stop": reply.get("stop"), "target_state": self.gdb.state}

        if command == "interrupt":
            timeout = float(args.get("timeout", DEFAULT_TIMEOUT))
            reply = self.gdb.interrupt(timeout=timeout)
            return {"stop": reply.get("stop"), "target_state": self.gdb.state}

        if command == "stepi":
            count = int(args.get("count", 1))
            timeout = float(args.get("timeout", DEFAULT_TIMEOUT))
            stop = None
            for _ in range(count):
                reply = self.gdb.continue_until_stop("-exec-step-instruction", timeout=timeout)
                stop = reply.get("stop")
            return {"count": count, "stop": stop}

        if command == "nexti":
            count = int(args.get("count", 1))
            timeout = float(args.get("timeout", DEFAULT_TIMEOUT))
            stop = None
            for _ in range(count):
                reply = self.gdb.continue_until_stop("-exec-next-instruction", timeout=timeout)
                stop = reply.get("stop")
            return {"count": count, "stop": stop}

        if command == "break":
            location = str(args["location"])
            reply = self.gdb.send(f"-break-insert {location}")
            return {"breakpoint": reply["result"]["payload"].get("bkpt")}

        if command == "delete-break":
            breakpoint_id = str(args["breakpoint_id"])
            self.gdb.send(f"-break-delete {breakpoint_id}")
            return {"deleted": breakpoint_id}

        if command == "regs":
            names = self.gdb.get_register_names()
            reply = self.gdb.send("-data-list-register-values x")
            values = reply["result"]["payload"].get("register-values", [])
            registers: dict[str, str] = {}
            for item in values:
                if not isinstance(item, dict):
                    continue
                number = int(item["number"])
                value = item["value"]
                registers[names[number] if number < len(names) else f"r{number}"] = value
            return {"registers": registers}

        if command == "mem":
            address = str(args["address"])
            length = int(args["length"])
            reply = self.gdb.send(f"-data-read-memory-bytes {address} {length}")
            memory = reply["result"]["payload"].get("memory", [])
            if not memory:
                raise DebugSessionError("gdb did not return memory bytes")
            block = memory[0]
            contents = block.get("contents", "")
            bytes_out = [contents[i : i + 2] for i in range(0, len(contents), 2)]
            return {
                "address": block.get("begin", address),
                "bytes": bytes_out,
                "length": len(bytes_out),
            }

        if command == "disassemble":
            location = str(args.get("location", "$pc"))
            count = int(args.get("count", 8))
            expr = self.gdb.send(f"-data-evaluate-expression {location}")
            start_text = expr["result"]["payload"]["value"]
            start = int(start_text, 16)
            end = start + (count * 4)
            reply = self.gdb.send(f"-data-disassemble -s 0x{start:x} -e 0x{end:x} -- 0")
            asm_insns = reply["result"]["payload"].get("asm_insns", [])
            instructions: list[dict[str, Any]] = []
            for item in asm_insns:
                if isinstance(item, dict) and "src_and_asm_line" in item:
                    instructions.append(item["src_and_asm_line"])
                elif isinstance(item, dict):
                    instructions.append(item)
            return {"start": f"0x{start:x}", "instructions": instructions}

        if command == "bt":
            reply = self.gdb.send("-stack-list-frames")
            return {"frames": reply["result"]["payload"].get("stack", [])}

        if command == "serial-read":
            clear = bool(args.get("clear", True))
            text = self.serial.read_text(clear=clear)
            return {"text": text}

        if command == "serial-drain":
            idle = float(args.get("idle", 0.2))
            timeout = float(args.get("timeout", DEFAULT_TIMEOUT))
            clear = bool(args.get("clear", True))
            text = self.serial.wait_for_idle(idle_seconds=idle, timeout=timeout)
            if clear:
                text = self.serial.read_text(clear=True)
            return {"text": text}

        if command == "serial-write":
            text = str(args.get("text", ""))
            bytes_written = self.serial.write_text(text)
            return {"bytes_written": bytes_written}

        if command == "stop":
            self.shutdown_requested = True
            return {"stopped": True}

        raise DebugSessionError(f"unknown command: {command}")

    def serve(self) -> None:
        if CONTROL_SOCKET_PATH.exists():
            CONTROL_SOCKET_PATH.unlink()
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(CONTROL_SOCKET_PATH))
        server.listen(1)
        write_manifest(self._manifest(ready=True))
        try:
            while not self.shutdown_requested:
                conn, _ = server.accept()
                with conn:
                    data = b""
                    while not data.endswith(b"\n"):
                        chunk = conn.recv(65536)
                        if not chunk:
                            break
                        data += chunk
                    if not data:
                        continue
                    request = json.loads(data.decode("utf-8"))
                    try:
                        result = self.handle_command(request["command"], request.get("args", {}))
                        response = {"ok": True, "command": request["command"], "result": result}
                    except Exception as exc:
                        self.last_error = str(exc)
                        write_manifest(self._manifest(ready=True))
                        response = {"ok": False, "command": request["command"], "error": str(exc)}
                    conn.sendall(json.dumps(response).encode("utf-8"))
        finally:
            server.close()
            try:
                CONTROL_SOCKET_PATH.unlink()
            except FileNotFoundError:
                pass
            self.teardown()

    def teardown(self) -> None:
        if self.gdb is not None:
            self.gdb.close()
        if self.serial is not None:
            self.serial.close()
        if self.qemu_proc is not None:
            self.qemu_proc.terminate()
            try:
                self.qemu_proc.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.qemu_proc.kill()


def build_debug_elf() -> None:
    subprocess.run(["just", "derzforth_debug_elf"], cwd=REPO_ROOT, check=True)


def handle_start(args: argparse.Namespace) -> int:
    best_effort_stop_existing_session()
    build_debug_elf()
    ensure_session_root()
    daemon_log = DAEMON_LOG_PATH.open("w", buffering=1, encoding="utf-8")
    gdb_port = args.gdb_port or choose_free_tcp_port()
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "__serve",
        "--mode",
        args.mode,
        "--gdb-port",
        str(gdb_port),
        "--startup-timeout",
        str(args.startup_timeout),
    ]
    if args.pause_after_load:
        command.append("--pause-after-load")
    if args.break_location:
        command.extend(["--break-location", args.break_location])
    subprocess.Popen(
        command,
        cwd=REPO_ROOT,
        stdin=subprocess.DEVNULL,
        stdout=daemon_log,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    wait_for_socket(CONTROL_SOCKET_PATH, timeout=args.startup_timeout)
    response = send_request({"command": "status", "args": {}})
    print_json(response)
    return 0


def handle_forwarded_command(command: str, args: dict[str, Any]) -> int:
    response = send_request({"command": command, "args": args})
    print_json(response)
    return 0 if response.get("ok") else 1


def bool_arg(value: str) -> bool:
    lowered = value.lower()
    if lowered in ("1", "true", "yes", "on"):
        return True
    if lowered in ("0", "false", "no", "off"):
        return False
    raise argparse.ArgumentTypeError(f"invalid boolean value: {value}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Agent-friendly DerzForth/QEMU/GDB debug harness")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    start = subparsers.add_parser("start")
    start.add_argument("--mode", choices=("raw", "lisp"), default="lisp")
    start.add_argument("--break-location")
    start.add_argument("--gdb-port", type=int, default=0)
    start.add_argument("--startup-timeout", type=float, default=15.0)
    start.add_argument("--pause-after-load", action="store_true", default=True)

    serve = subparsers.add_parser("__serve")
    serve.add_argument("--mode", choices=("raw", "lisp"), default="lisp")
    serve.add_argument("--break-location")
    serve.add_argument("--gdb-port", type=int, default=DEFAULT_GDB_PORT)
    serve.add_argument("--startup-timeout", type=float, default=15.0)
    serve.add_argument("--pause-after-load", action="store_true", default=False)

    subparsers.add_parser("status")
    subparsers.add_parser("stop")

    cont = subparsers.add_parser("continue")
    cont.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)

    interrupt = subparsers.add_parser("interrupt")
    interrupt.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)

    stepi = subparsers.add_parser("stepi")
    stepi.add_argument("--count", type=int, default=1)
    stepi.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)

    nexti = subparsers.add_parser("nexti")
    nexti.add_argument("--count", type=int, default=1)
    nexti.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)

    add_break = subparsers.add_parser("break")
    add_break.add_argument("location")

    delete_break = subparsers.add_parser("delete-break")
    delete_break.add_argument("breakpoint_id")

    subparsers.add_parser("regs")

    mem = subparsers.add_parser("mem")
    mem.add_argument("address")
    mem.add_argument("length", type=int)

    disassemble = subparsers.add_parser("disassemble")
    disassemble.add_argument("--location", default="$pc")
    disassemble.add_argument("--count", type=int, default=8)

    subparsers.add_parser("bt")

    serial_read = subparsers.add_parser("serial-read")
    serial_read.add_argument("--clear", type=bool_arg, default=True)

    serial_drain = subparsers.add_parser("serial-drain")
    serial_drain.add_argument("--idle", type=float, default=0.2)
    serial_drain.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    serial_drain.add_argument("--clear", type=bool_arg, default=True)

    serial_write = subparsers.add_parser("serial-write")
    serial_group = serial_write.add_mutually_exclusive_group(required=True)
    serial_group.add_argument("--text")
    serial_group.add_argument("--file")

    return parser


def namespace_args(args: argparse.Namespace) -> dict[str, Any]:
    result = vars(args).copy()
    result.pop("subcommand", None)
    return {key: value for key, value in result.items() if value is not None}


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.subcommand == "start":
            return handle_start(args)

        if args.subcommand == "__serve":
            config = SessionConfig(
                mode=args.mode,
                break_location=args.break_location,
                gdb_port=args.gdb_port,
                startup_timeout=args.startup_timeout,
                pause_after_load=args.pause_after_load,
            )
            daemon = DebugDaemon(config)
            try:
                daemon.setup()
            except Exception as exc:
                ensure_session_root()
                DAEMON_LOG_PATH.write_text(f"{exc!r}\n{traceback.format_exc()}")
                write_manifest(
                    {
                        "control_socket": str(CONTROL_SOCKET_PATH),
                        "daemon_pid": os.getpid(),
                        "elf": str(DERZFORTH_DEBUG_ELF),
                        "gdb_port": args.gdb_port,
                        "last_error": str(exc),
                        "mode": args.mode,
                        "ready": False,
                        "session_root": str(SESSION_ROOT),
                    }
                )
                raise
            daemon.serve()
            return 0

        if args.subcommand == "serial-write":
            payload = namespace_args(args)
            if "file" in payload:
                file_path = Path(payload.pop("file"))
                payload["text"] = file_path.read_text()
            return handle_forwarded_command("serial-write", payload)

        return handle_forwarded_command(args.subcommand, namespace_args(args))
    except Exception as exc:
        print_json(
            {
                "ok": False,
                "command": args.subcommand,
                "error": str(exc),
            }
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
