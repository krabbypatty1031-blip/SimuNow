"""System /usr/bin/python3 is 3.9. Worker must start without PEP 604 at runtime."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "Backend" / "src" / "simunow_worker" / "__main__.py"


class SystemPythonWorkerTests(unittest.TestCase):
    def test_system_python_compiles_main(self):
        proc = subprocess.run(
            ["/usr/bin/python3", "-m", "py_compile", str(MAIN)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_system_python_runs_doctor(self):
        import os

        env = os.environ.copy()
        env["PYTHONPATH"] = str(ROOT / "Backend" / "src")
        proc = subprocess.run(
            ["/usr/bin/python3", "-m", "simunow_worker", "doctor"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("not_configured", proc.stdout)


if __name__ == "__main__":
    unittest.main()
