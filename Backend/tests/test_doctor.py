"""Doctor JSON contract for the P1 runtime lock.

Why subprocess instead of importing main: the acceptance command is
`python3 -m simunow_worker doctor`, and stdout must stay parseable JSON
even when probes log. Fixtures are scripts on PATH so we see real
process launches without downloading engines or running a solver.
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import unittest
from pathlib import Path


BACKEND = Path(__file__).resolve().parents[1]
SRC = BACKEND / "src"
REPAIR_PATH = "test/engines/install_engines.sh"
EP_VERSION = "25.2.0-cf7368216c"
OF_TAG = "simunow/openfoam:2512"


def _write_executable(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class DoctorJsonTests(unittest.TestCase):
    """L1 is EnergyPlus and L2 is the pinned OpenFOAM image."""

    def _doctor(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        # Drop a developer engines root so the missing-root case is real.
        merged.pop("SIMUNOW_ENGINES_ROOT", None)
        merged.update(env)
        merged["PYTHONPATH"] = str(SRC)
        return subprocess.run(
            [sys.executable, "-m", "simunow_worker", "doctor"],
            cwd=BACKEND,
            env=merged,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )

    def _load(self, proc: subprocess.CompletedProcess[str]) -> dict:
        self.assertEqual(proc.returncode, 0, proc.stderr)
        # Logs belong on stderr; a trailing newline is fine, extra text is not.
        return json.loads(proc.stdout)

    def _engine(self, report: dict, name: str) -> dict:
        # P0 stored a string. Fail here when that shape is still in place.
        value = report["engines"][name]
        self.assertIsInstance(value, dict, f"{name} should be an object, got {value!r}")
        return value

    def test_unset_root_marks_l1_and_l2_not_configured_with_repair(self) -> None:
        proc = self._doctor({})
        report = self._load(proc)
        self.assertEqual(report["protocol_version"], 1)
        self.assertEqual(report["engines"]["l0"], "not_configured")
        self.assertEqual(report["engines"]["l3"], "not_configured")
        l1 = self._engine(report, "l1")
        l2 = self._engine(report, "l2")
        self.assertEqual(l1["status"], "not_configured")
        self.assertEqual(l2["status"], "not_configured")
        self.assertIn(REPAIR_PATH, l1["repair"])
        self.assertIn(REPAIR_PATH, l2["repair"])

    def test_present_pin_is_configured_without_solver_or_download(self) -> None:
        with self._fixture(arch="linux/arm64", version_line=f"EnergyPlus, Version {EP_VERSION}") as fx:
            proc = self._doctor(fx.env)
            report = self._load(proc)
            l1 = self._engine(report, "l1")
            l2 = self._engine(report, "l2")
            self.assertEqual(l1["status"], "configured")
            self.assertEqual(l2["status"], "configured")
            self.assertNotIn("repair", l1)
            self.assertNotIn("repair", l2)
            self.assertEqual(report["engines"]["l0"], "not_configured")
            self.assertEqual(report["engines"]["l3"], "not_configured")
            calls = fx.docker_log.read_text(encoding="utf-8")
            self.assertIn("image inspect", calls)
            self.assertNotIn("\nrun ", f"\n{calls}")
            self.assertNotRegex(calls, r"(^|\s)(pull|build)(\s|$)")
            ep_calls = fx.ep_log.read_text(encoding="utf-8")
            self.assertIn("--version", ep_calls)
            self.assertNotIn("-w", ep_calls)
            self.assertEqual(fx.curl_log.read_text(encoding="utf-8"), "")

    def test_missing_binary_stays_not_configured(self) -> None:
        with self._fixture(arch="linux/arm64", version_line=f"EnergyPlus, Version {EP_VERSION}", write_binary=False) as fx:
            proc = self._doctor(fx.env)
            report = self._load(proc)
            l1 = self._engine(report, "l1")
            l2 = self._engine(report, "l2")
            self.assertEqual(l1["status"], "not_configured")
            self.assertIn(REPAIR_PATH, l1["repair"])
            self.assertEqual(l2["status"], "configured")

    def test_wrong_energyplus_version_is_not_configured(self) -> None:
        with self._fixture(arch="linux/arm64", version_line="EnergyPlus, Version 9.4.0") as fx:
            proc = self._doctor(fx.env)
            report = self._load(proc)
            l1 = self._engine(report, "l1")
            self.assertEqual(l1["status"], "not_configured")
            self.assertIn(REPAIR_PATH, l1["repair"])

    def test_amd64_image_is_not_configured(self) -> None:
        with self._fixture(arch="linux/amd64", version_line=f"EnergyPlus, Version {EP_VERSION}") as fx:
            proc = self._doctor(fx.env)
            report = self._load(proc)
            l2 = self._engine(report, "l2")
            self.assertEqual(l2["status"], "not_configured")
            self.assertIn(REPAIR_PATH, l2["repair"])
            calls = fx.docker_log.read_text(encoding="utf-8")
            self.assertNotIn("\nrun ", f"\n{calls}")

    def test_foamrun_solver_is_refused(self) -> None:
        with self._fixture(
            arch="linux/arm64",
            version_line=f"EnergyPlus, Version {EP_VERSION}",
            solver="foamRun",
        ) as fx:
            proc = self._doctor(fx.env)
            report = self._load(proc)
            l2 = self._engine(report, "l2")
            self.assertEqual(l2["status"], "not_configured")
            self.assertIn(REPAIR_PATH, l2["repair"])
            calls = fx.docker_log.read_text(encoding="utf-8")
            self.assertNotIn("\nrun ", f"\n{calls}")

    def test_unset_root_does_not_invoke_docker_or_curl(self) -> None:
        with self._fixture(arch="linux/arm64", version_line="unused", write_binary=False) as fx:
            env = {"PATH": fx.env["PATH"]}
            proc = self._doctor(env)
            report = self._load(proc)
            self.assertEqual(self._engine(report, "l1")["status"], "not_configured")
            self.assertEqual(self._engine(report, "l2")["status"], "not_configured")
            self.assertEqual(fx.docker_log.read_text(encoding="utf-8"), "")
            self.assertEqual(fx.curl_log.read_text(encoding="utf-8"), "")

    def _fixture(
        self,
        *,
        arch: str,
        version_line: str,
        solver: str | None = None,
        write_binary: bool = True,
    ):
        return _EnginesFixture(self, arch=arch, version_line=version_line, solver=solver, write_binary=write_binary)


class _EnginesFixture:
    """Temp engines root plus PATH shims that record every invocation."""

    def __init__(self, test: unittest.TestCase, **kwargs: object) -> None:
        self._test = test
        self._kwargs = kwargs
        self.env: dict[str, str] = {}
        self.docker_log = Path()
        self.ep_log = Path()
        self.curl_log = Path()
        self._tmpdir = None

    def __enter__(self) -> _EnginesFixture:
        import tempfile

        self._tmpdir = tempfile.TemporaryDirectory(prefix="simunow-doctor-")
        root = Path(self._tmpdir.name)
        engines = root / "engines"
        bindir = root / "bin"
        engines.mkdir()
        bindir.mkdir()
        self.docker_log = root / "docker.log"
        self.ep_log = root / "energyplus.log"
        self.curl_log = root / "curl.log"
        self.docker_log.write_text("", encoding="utf-8")
        self.ep_log.write_text("", encoding="utf-8")
        self.curl_log.write_text("", encoding="utf-8")

        arch = str(self._kwargs["arch"])
        _write_executable(
            bindir / "docker",
            "\n".join(
                [
                    "#!/bin/sh",
                    f'printf "%s\\n" "$*" >> "{self.docker_log}"',
                    'if [ "$1" = "run" ]; then exit 97; fi',
                    'if [ "$1" = "pull" ] || [ "$1" = "build" ]; then exit 98; fi',
                    'if [ "$1" = "image" ] && [ "$2" = "inspect" ]; then',
                    f'  printf "%s\\n" "{arch}"',
                    "  exit 0",
                    "fi",
                    "exit 96",
                    "",
                ]
            ),
        )
        _write_executable(
            bindir / "curl",
            "\n".join(
                [
                    "#!/bin/sh",
                    f'printf "%s\\n" "$*" >> "{self.curl_log}"',
                    "exit 99",
                    "",
                ]
            ),
        )
        if self._kwargs.get("write_binary", True):
            version_line = str(self._kwargs["version_line"])
            _write_executable(
                engines / "EnergyPlus" / "energyplus",
                "\n".join(
                    [
                        "#!/bin/sh",
                        f'printf "%s\\n" "$*" >> "{self.ep_log}"',
                        'if [ "$1" != "--version" ]; then exit 99; fi',
                        f'printf "%s\\n" "{version_line}"',
                        "",
                    ]
                ),
            )
        openfoam: dict[str, str] = {
            "image": "opencfd/openfoam-run:2512",
            "local_tag": OF_TAG,
            "platform": "linux/arm64",
        }
        solver = self._kwargs.get("solver")
        if isinstance(solver, str):
            openfoam["solver"] = solver
        (engines / "MANIFEST.json").write_text(
            json.dumps({"openfoam": openfoam}),
            encoding="utf-8",
        )
        self.env = {
            "SIMUNOW_ENGINES_ROOT": str(engines),
            "PATH": f"{bindir}{os.pathsep}{os.environ.get('PATH', '')}",
        }
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self._tmpdir is not None:
            self._tmpdir.cleanup()


if __name__ == "__main__":
    unittest.main()
