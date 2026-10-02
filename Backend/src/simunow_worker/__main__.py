"""A truthful capability probe. Does not simulate or emit numerical results."""
import argparse
import json
from . import __version__


def main():
    parser = argparse.ArgumentParser(prog="simunow-worker")
    parser.add_argument("command", choices=["doctor"])
    parser.parse_args()
    print(json.dumps({
        "protocol_version": 1,
        "worker_version": __version__,
        "status": "scaffold",
        "engines": {"l0": "not_configured", "l1": "not_configured", "l2": "not_configured", "l3": "not_configured"},
    }))


if __name__ == "__main__":
    main()
