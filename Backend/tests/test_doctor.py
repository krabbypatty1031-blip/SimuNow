"""Behavior/CLI contracts. Fakes are never evidence of installed engines."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from jsonschema import Draft202012Validator
from simunow_worker.__main__ import main
from simunow_worker.runtime.doctor import ConfigurationError, doctor, load_manifest
from simunow_worker.runtime.probe import CommandResult, SystemProbe

ROOT = Path(__file__).resolve().parents[2]


class FakeProbe:
    def __init__(self):
        self.calls = []
        self.settings = {}
        self.local = {"os": "Darwin", "os_version": "27.0", "architecture": "arm64",
                      "physical_memory_bytes": 34359738368, "memory_probe_state": "ok",
                      "python_version": "3.13.7", "python_isolated": True,
                      "dependencies": deepcopy(load_manifest()["python"]["dependencies"])}
        self.ep_present = True
        self.results = {
            "docker_version": CommandResult("ok", 0, "Docker version 29.6.2, build public"),
            "info": CommandResult("ok", 0, json.dumps({"os": "linux", "architecture": "aarch64", "memory_bytes": 8589934592, "server_version": "29.6.2"})),
            "inspect": CommandResult("ok", 0, json.dumps({"os": "linux", "architecture": "arm64", "digests": [load_manifest()["engines"]["openfoam"]["image"]]})),
            "run": CommandResult("ok", 0, "aarch64\nOpenFOAM-v2506\nVersion: v2506\nWebsite: www.openfoam.com\nUsage: buoyantSimpleFoam -help"),
            "rm": CommandResult("process_failed", 1, stderr="No such container: ephemeral"),
            "file": CommandResult("ok", 0, "Mach-O 64-bit executable arm64"),
            "ep": CommandResult("ok", 0, "EnergyPlus, Version 26.1.0-6f2e40d102"),
            "colima": CommandResult("ok", 0, "colima version 0.10.3"),
            "limactl": CommandResult("ok", 0, "limactl version 2.1.4"),
            "colima_status": CommandResult("ok", 0),
        }

    def setting(self, name):
        return self.settings.get(name)

    def resolve(self, command):
        return "/private/fake-engine" if self.ep_present and command == "energyplus" else None

    def host(self):
        return self.local

    def run(self, argv, timeout):
        self.calls.append((argv, timeout))
        if argv[0] == "docker":
            key = "docker_version" if argv[3] == "--version" else "info" if argv[3] == "info" else "inspect" if argv[3] == "image" else argv[3]
        elif argv[0] == "file":
            key = "file"
        elif argv[0] == "/private/fake-engine":
            key = "ep"
        elif argv == ["colima", "status"]:
            key = "colima_status"
        else:
            key = argv[0]
        return self.results.get(key, CommandResult("command_missing"))


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.manifest = load_manifest()
        self.probe = FakeProbe()

    def report(self):
        return doctor(self.manifest, self.probe, timeout=0.5)

    def test_empty_environment_is_blocked_without_container_execution(self):
        self.probe.results.clear()
        self.probe.ep_present = False
        report = self.report()
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["container"]["state"], "not_installed")
        self.assertEqual(report["engine_checks"]["energyplus"]["state"], "not_installed")
        self.assertIsNone(report["engine_checks"]["openfoam"]["image_present"])
        self.assertFalse(any("run" in c for c, _ in self.probe.calls))

    def test_verified_startup_does_not_enable_physics(self):
        report = self.report()
        self.assertEqual(report["status"], "ready")
        self.assertEqual(report["physical_validation"], "not_performed")
        self.assertEqual(report["simulation_pipeline"], "not_implemented")
        self.assertEqual(report["engine_checks"]["openfoam"]["execution_architecture"], "arm64")
        for result in report["engine_checks"].values():
            self.assertTrue(result["executable"])
            self.assertTrue(result["version_matches"])
            self.assertEqual(result["state"], "verified_available")
        run = next(c for c, _ in self.probe.calls if "run" in c)
        self.assertIn("--pull=never", run)
        self.assertIn("--read-only", run)
        self.assertIn("none", run)
        self.assertNotIn("-v", run)
        self.assertTrue(all(0 < t <= 0.5 for _, t in self.probe.calls))

    def test_openfoam_version_mismatch_is_still_executable(self):
        self.probe.results["run"] = CommandResult("ok", 0, "aarch64\nOpenFOAM-v2412\nWebsite: www.openfoam.com")
        report = self.report()["engine_checks"]["openfoam"]
        self.assertEqual(report["state"], "version_mismatch")
        self.assertTrue(report["executable"])
        self.assertFalse(report["version_matches"])

    def test_energyplus_version_and_build_mismatch(self):
        for version in ("25.2.0-6f2e40d102", "26.1.0-aaaaaaaaaa"):
            with self.subTest(version=version):
                self.probe.results["ep"] = CommandResult("ok", 0, "EnergyPlus, Version " + version)
                result = self.report()["engine_checks"]["energyplus"]
                self.assertEqual(result["state"], "version_mismatch")
                self.assertTrue(result["executable"])

    def test_daemon_errors_are_distinct_and_sanitized(self):
        for result, state in ((CommandResult("timeout"), "timeout"),
                              (CommandResult("command_missing"), "command_missing"),
                              (CommandResult("probe_failed"), "probe_failed"),
                              (CommandResult("process_failed", 1, stderr="Cannot connect to /private/secret/socket"), "unreachable"),
                              (CommandResult("process_failed", 1, stderr="permission denied: secret-token"), "permission_denied"),
                              (CommandResult("process_failed", 7, stderr="arbitrary secret-token"), "process_failed")):
            with self.subTest(state=state):
                self.probe.results["info"] = result
                report = self.report()
                self.assertEqual(report["container"]["state"], state)
                self.assertEqual(report["status"], "blocked")
                self.assertNotIn("secret", json.dumps(report))

    def test_bad_daemon_metadata_fails_probe(self):
        for output in ("garbage", "{}", '{"os":"linux","architecture":"arm64","memory_bytes":0}'):
            self.probe.results["info"] = CommandResult("ok", 0, output)
            self.assertEqual(self.report()["container"]["state"], "probe_failed")

    def test_wrong_daemon_architecture_is_unsupported(self):
        self.probe.results["info"] = CommandResult("ok", 0, '{"os":"linux","architecture":"x86_64","memory_bytes":1024,"server_version":"29.6.2"}')
        self.assertEqual(self.report()["container"]["state"], "unsupported")

    def test_provider_and_cli_version_mismatch_blocks_ready(self):
        self.probe.results["docker_version"] = CommandResult("ok", 0, "Docker version 28.0.0")
        self.assertEqual(self.report()["container"]["state"], "version_mismatch")
        self.probe.results["colima"] = CommandResult("ok", 0, "colima version 0.9.0")
        self.assertFalse(self.report()["inventory"]["colima"]["version_matches"])

    def test_missing_image_differs_from_failed_inspect(self):
        self.probe.results["inspect"] = CommandResult("process_failed", 1, stderr="No such image")
        result = self.report()["engine_checks"]["openfoam"]
        self.assertEqual(result["state"], "not_installed")
        self.assertFalse(result["image_present"])
        self.probe.results["inspect"] = CommandResult("timeout")
        self.assertIsNone(self.report()["engine_checks"]["openfoam"]["image_present"])

    def test_image_identity_or_architecture_prevents_execution(self):
        for value, state in (({"os": "linux", "architecture": "arm64", "digests": []}, "identity_mismatch"),
                              ({"os": "linux", "architecture": "amd64", "digests": []}, "unsupported")):
            self.probe.calls.clear()
            self.probe.results["inspect"] = CommandResult("ok", 0, json.dumps(value))
            self.assertEqual(self.report()["engine_checks"]["openfoam"]["state"], state)
            self.assertFalse(any("run" in c for c, _ in self.probe.calls))

    def test_solver_failures_and_timeouts_trigger_bounded_cleanup(self):
        for state in ("timeout", "process_failed", "command_missing", "probe_failed"):
            self.probe.calls.clear()
            self.probe.results["run"] = CommandResult(state, 1 if state == "process_failed" else None)
            result = self.report()["engine_checks"]["openfoam"]
            self.assertEqual(result["state"], state)
            self.assertFalse(result["executable"])
            cleanup = next((c, t) for c, t in self.probe.calls if "rm" in c)
            self.assertTrue(cleanup[0][-1].startswith("simunow-doctor-"))
            self.assertLessEqual(cleanup[1], 0.5)

    def test_successful_startup_with_unconfirmed_cleanup_is_blocked(self):
        self.probe.results["rm"] = CommandResult("timeout")
        result = self.report()["engine_checks"]["openfoam"]
        self.assertTrue(result["executable"])
        self.assertEqual(result["state"], "probe_failed")

    def test_successful_unrecognized_output_cannot_verify_engine(self):
        for key, engine in (("run", "openfoam"), ("ep", "energyplus")):
            original = self.probe.results[key]
            self.probe.results[key] = CommandResult("ok", 0, "hello world")
            self.assertEqual(self.report()["engine_checks"][engine]["state"], "probe_failed")
            self.probe.results[key] = original

    def test_conflicting_foam_version_and_help_cannot_verify_engine(self):
        self.probe.results["run"] = CommandResult("ok", 0, "aarch64\nOpenFOAM-v2506\nVersion: v2412\nwww.openfoam.com")
        self.assertEqual(self.report()["engine_checks"]["openfoam"]["state"], "probe_failed")
        self.probe.results["run"] = CommandResult("ok", 0, "x86_64\nOpenFOAM-v2506\nwww.openfoam.com")
        self.assertEqual(self.report()["engine_checks"]["openfoam"]["state"], "unsupported")

    def test_energyplus_override_missing_and_x86_binary(self):
        self.probe.settings["SIMUNOW_ENERGYPLUS_EXECUTABLE"] = "/private/missing"
        self.assertEqual(self.report()["engine_checks"]["energyplus"]["state"], "not_configured")
        self.probe.settings.clear()
        self.probe.results["file"] = CommandResult("ok", 0, "Mach-O 64-bit executable x86_64")
        self.assertEqual(self.report()["engine_checks"]["energyplus"]["state"], "unsupported")
        self.assertFalse(any(c[0] == "/private/fake-engine" for c, _ in self.probe.calls))

    def test_native_command_errors_remain_distinct(self):
        for state in ("command_missing", "timeout", "process_failed", "probe_failed"):
            self.probe.results["ep"] = CommandResult(state)
            self.assertEqual(self.report()["engine_checks"]["energyplus"]["state"], state)

    def test_host_python_and_unknown_memory(self):
        self.probe.local["dependencies"]["referencing"] = "0.36.0"
        self.assertFalse(self.report()["python_matches"])
        self.probe.local["dependencies"] = deepcopy(self.manifest["python"]["dependencies"])
        self.probe.local["python_isolated"] = False
        self.probe.local["physical_memory_bytes"] = None
        self.probe.local["memory_probe_state"] = "probe_failed"
        self.assertEqual(self.report()["status"], "blocked")
        self.assertIsNone(self.report()["host"]["physical_memory_bytes"])
        self.probe.local["os_version"] = "13.0"
        self.assertEqual(self.report()["container"]["state"], "unsupported")
        self.probe.local["os"] = "Linux"
        self.assertFalse(self.report()["host_matches"])

    def test_manifest_and_reports_satisfy_independent_schemas(self):
        locked = dict(line.split("==", 1) for line in (ROOT / "Backend/requirements-dev.lock").read_text().splitlines() if line)
        self.assertEqual(self.manifest["python"]["dependencies"], locked)
        schema = json.loads((ROOT / "Protocols/Schemas/runtime-manifest.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        Draft202012Validator(schema).validate(self.manifest)
        schema = json.loads((ROOT / "Protocols/Schemas/doctor-report.schema.json").read_text())
        Draft202012Validator.check_schema(schema)
        for empty in (False, True):
            if empty:
                self.probe.results.clear()
                self.probe.ep_present = False
            report = self.report()
            for strict, code in ((False, 0), (True, 2 if empty else 0)):
                with patch("simunow_worker.__main__.doctor", return_value=report), redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(["doctor"] + (["--strict"] if strict else [])), code)
                lines = output.getvalue().splitlines()
                self.assertEqual(len(lines), 1)
                wire = json.loads(lines[0])
                Draft202012Validator(schema).validate(wire)
                self.assertEqual(wire["protocol_version"], 1)
                self.assertEqual(wire["status"], "scaffold")
                self.assertEqual(set(wire["engines"].values()), {"not_configured"})

    def test_invalid_config_json_exit_and_no_raw_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "private-config.json"
            path.write_text('{"manifest_version":99}')
            with self.assertRaises(ConfigurationError):
                load_manifest(path)
            with redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(["doctor", "--manifest", str(path)]), 3)
            report = json.loads(output.getvalue())
            self.assertEqual(report["environment"]["status"], "invalid_configuration")
            self.assertNotIn(directory, output.getvalue())
            schema = json.loads((ROOT / "Protocols/Schemas/doctor-report.schema.json").read_text())
            Draft202012Validator(schema).validate(report)

    def test_mutable_image_or_arbitrary_script_rejected(self):
        for key, value in (("image", "opencfd/openfoam-dev:latest"), ("environment_script", "/private/untrusted.sh")):
            manifest = deepcopy(self.manifest)
            manifest["engines"]["openfoam"][key] = value
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "manifest.json"
                path.write_text(json.dumps(manifest))
                with self.assertRaises(ConfigurationError):
                    load_manifest(path)

    def test_invalid_manifest_structure_produces_configuration_json(self):
        cases = []
        missing = deepcopy(self.manifest)
        del missing["engines"]["openfoam"]["distribution"]
        cases.append(json.dumps(missing))
        extra = deepcopy(self.manifest)
        extra["container"]["credential"] = "private-token"
        cases.append(json.dumps(extra))
        invalid_type = deepcopy(self.manifest)
        invalid_type["manifest_version"] = True
        cases.append(json.dumps(invalid_type))
        cases.append(json.dumps(self.manifest).replace('"manifest_version": 1', '"manifest_version": 1, "manifest_version": 1'))
        for content in cases:
            with self.subTest(content=content[:20]), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "manifest.json"
                path.write_text(content)
                with redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(["doctor", "--manifest", str(path)]), 3)
                self.assertEqual(json.loads(output.getvalue())["environment"]["status"], "invalid_configuration")
                self.assertNotIn("private-token", output.getvalue())


class ProcessTests(unittest.TestCase):
    def test_missing_failed_and_successful_processes(self):
        probe = SystemProbe()
        self.assertEqual(probe.run(["/no-such-simunow-command"], 0.5).state, "command_missing")
        failed = probe.run([sys.executable, "-c", "import sys; print('diagnostic',file=sys.stderr); sys.exit(7)"], 1)
        self.assertEqual((failed.state, failed.returncode), ("process_failed", 7))
        self.assertIn("diagnostic", failed.stderr)
        self.assertEqual(probe.run([sys.executable, "-c", "print('ok')"], 1).stdout.strip(), "ok")

    def test_timeout_terminates_local_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = str(Path(directory) / "descendant-survived")
            child = f"import time,pathlib; time.sleep(0.5); pathlib.Path({marker!r}).write_text('bad')"
            parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); time.sleep(30)"
            start = time.monotonic()
            result = SystemProbe().run([sys.executable, "-c", parent], 0.15)
            self.assertEqual(result.state, "timeout")
            self.assertLess(time.monotonic() - start, 2)
            time.sleep(0.6)
            self.assertFalse(Path(marker).exists())

    def test_invalid_timeout_cli_fails_before_probe(self):
        for value in ("0", "16", "nan", "inf"):
            result = subprocess.run([sys.executable, "-m", "simunow_worker", "doctor", "--timeout", value], capture_output=True, text=True, timeout=3)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
