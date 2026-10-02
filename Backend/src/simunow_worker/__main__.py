"""A truthful capability probe. Does not simulate or emit numerical results."""
import argparse
import json
from pathlib import Path
from . import __version__
from .runtime.doctor import ConfigurationError, doctor, load_manifest


def main(argv=None):
    parser = argparse.ArgumentParser(prog="simunow-worker")
    parser.add_argument("command", choices=["doctor"])
    parser.add_argument("--manifest", type=Path, help="Runtime manifest JSON; defaults to the bundled pinned profile")
    parser.add_argument("--timeout", type=float, default=5, help="Per-process timeout in seconds (0.1–15)")
    parser.add_argument("--strict", action="store_true", help="Exit 2 when the target environment is blocked")
    args = parser.parse_args(argv)
    if not 0.1 <= args.timeout <= 15:
        parser.error("--timeout must be between 0.1 and 15 seconds")
    try:
        environment = doctor(load_manifest(args.manifest), timeout=args.timeout)
    except ConfigurationError as error:
        environment = {"report_version": 1, "status": "invalid_configuration", "hint": str(error)}
    report = {
        "protocol_version": 1,
        "worker_version": __version__,
        "status": "scaffold",
        "engines": {"l0": "not_configured", "l1": "not_configured", "l2": "not_configured", "l3": "not_configured"},
        "environment": environment,
    }
    print(json.dumps(report, ensure_ascii=False))
    if environment["status"] == "invalid_configuration":
        return 3
    return 2 if args.strict and environment["status"] != "ready" else 0


if __name__ == "__main__":
    raise SystemExit(main())
