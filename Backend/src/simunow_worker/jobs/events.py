"""Run event stream (Protocols/run-events-v1.md).

stdout carries only JSONL events; the same events are teed into the run
directory's events.jsonl. Sequence numbers are strictly monotonic per run.
"""
import json
import sys
from datetime import datetime, timezone

PROTOCOL = "run-event/1"
EVENT_TYPES = ("accepted", "progress", "log", "quality", "completed", "failed", "cancelled")


def _timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class EventStream:
    """Monotonic JSONL event emitter for one run. Unknown event types are rejected here."""

    def __init__(self, run_id, tee_path=None):
        self.run_id = str(run_id)
        self.sequence = 0
        self._tee = open(tee_path, "a", encoding="utf-8") if tee_path else None

    def emit(self, event_type, stage=None, payload=None):
        if event_type not in EVENT_TYPES:
            raise ValueError(f"unknown event type: {event_type}")
        self.sequence += 1
        event = {"protocol": PROTOCOL, "runID": self.run_id, "sequence": self.sequence,
                 "timestamp": _timestamp(), "eventType": event_type}
        if stage is not None:
            event["stage"] = stage
        if payload is not None:
            event["payload"] = payload
        line = json.dumps(event, ensure_ascii=False)
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
        if self._tee:
            self._tee.write(line + "\n")
            self._tee.flush()
        return event

    def close(self):
        if self._tee:
            self._tee.close()
            self._tee = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
