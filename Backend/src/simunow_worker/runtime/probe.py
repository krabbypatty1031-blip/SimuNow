"""Injectable, bounded process and host probes; never emit raw diagnostics."""
from dataclasses import dataclass
from importlib.metadata import PackageNotFoundError, version
import os
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
from typing import Protocol


@dataclass(frozen=True)
class CommandResult:
    state: str
    returncode: int | None = None
    stdout: str = ""
    stderr: str = ""


class Probe(Protocol):
    def run(self, argv: list[str], timeout: float) -> CommandResult: ...
    def resolve(self, command: str) -> str | None: ...
    def host(self) -> dict: ...
    def setting(self, name: str) -> str | None: ...


class SystemProbe:
    def setting(self, name: str) -> str | None:
        return os.environ.get(name) or None

    def resolve(self, command: str) -> str | None:
        return shutil.which(command)

    def run(self, argv: list[str], timeout: float) -> CommandResult:
        # Disk-backed capture avoids unbounded memory use. Only inspect 64 KiB.
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
            try:
                proc = subprocess.Popen(argv, stdout=out, stderr=err, stdin=subprocess.DEVNULL,
                                        start_new_session=True)
            except FileNotFoundError:
                return CommandResult("command_missing")
            except OSError:
                return CommandResult("probe_failed")
            try:
                proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                # Also terminate local descendants. Docker containers are separately cleaned.
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=2)
                return CommandResult("timeout")
            out.seek(0)
            err.seek(0)
            return CommandResult("ok" if proc.returncode == 0 else "process_failed",
                                 proc.returncode, out.read(65536).decode("utf-8", "replace"),
                                 err.read(65536).decode("utf-8", "replace"))

    def host(self) -> dict:
        system = platform.system()
        memory = None
        memory_state = "unsupported"
        if system == "Darwin":
            result = self.run(["sysctl", "-n", "hw.memsize"], 3)
            memory_state = result.state
            if result.state == "process_failed" and any(s in result.stderr.lower() for s in ("permission denied", "operation not permitted")):
                memory_state = "permission_denied"
            if result.state == "ok":
                try:
                    memory = int(result.stdout.strip())
                    if memory <= 0:
                        raise ValueError
                except ValueError:
                    memory_state = "probe_failed"
                    memory = None
        elif system == "Linux":
            try:
                memory = os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
                memory_state = "ok"
            except (OSError, ValueError):
                memory_state = "probe_failed"
        dependencies = {}
        for package in ("annotated-types", "attrs", "jsonschema", "jsonschema-specifications", "pydantic",
                        "pydantic_core", "referencing", "rpds-py", "typing-inspection", "typing_extensions"):
            try:
                dependencies[package] = version(package)
            except PackageNotFoundError:
                dependencies[package] = None
        return {"os": system, "os_version": platform.mac_ver()[0] if system == "Darwin" else platform.release(),
                "architecture": platform.machine(), "physical_memory_bytes": memory,
                "memory_probe_state": memory_state,
                "memory_hint": "Physical memory read successfully." if memory_state == "ok" else "Memory is unknown; check system-query permissions outside the restricted process and rerun doctor.",
                "python_version": platform.python_version(),
                "python_isolated": sys.prefix != sys.base_prefix, "dependencies": dependencies}
