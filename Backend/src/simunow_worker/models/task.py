"""P3 task wire format. camelCase keys match Swift Codable."""

from __future__ import annotations

import hashlib
import json

IDENTITY_KEYS = ("runID", "scenarioID", "inputHash")
EVENT_TYPES = {"accepted", "progress", "log", "quality", "completed", "failed", "cancelled"}


class TaskProtocolError(ValueError):
    hash_mismatch = "hashMismatch"
    unsafe_snapshot_path = "unsafeSnapshotPath"
    stale_sequence = "staleSequence"
    truncated_line = "truncatedLine"
    wrong_run = "wrongRun"
    invalid_json = "invalidJSON"

    def __init__(self, code: str, message: str = ""):
        self.code = code
        super().__init__(message or code)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def is_safe_snapshot_path(path: str) -> bool:
    trimmed = path.strip()
    if not trimmed or trimmed.startswith("/") or "://" in trimmed:
        return False
    if ".." in trimmed.split("/"):
        return False
    lowered = trimmed.lower()
    if "/users/" in lowered or lowered.startswith("users/"):
        return False
    if "/downloads/" in lowered or "/desktop/" in lowered:
        return False
    return True


def validate_request(request: dict, snapshot: bytes) -> None:
    """Reject absolute paths and hash drift. Does not run a solver."""
    path = request.get("snapshotPath", "")
    if not is_safe_snapshot_path(path):
        raise TaskProtocolError(TaskProtocolError.unsafe_snapshot_path)
    weather = request.get("weatherPath")
    if weather is not None and not is_safe_snapshot_path(weather):
        raise TaskProtocolError(TaskProtocolError.unsafe_snapshot_path)
    digest = sha256_hex(snapshot)
    if digest != request.get("snapshotHash") or digest != request.get("identity", {}).get("inputHash"):
        raise TaskProtocolError(TaskProtocolError.hash_mismatch)


def parse_event(line: str) -> dict:
    try:
        event = json.loads(line)
    except json.JSONDecodeError as error:
        raise TaskProtocolError(TaskProtocolError.invalid_json) from error
    if event.get("eventType") not in EVENT_TYPES:
        raise TaskProtocolError(TaskProtocolError.invalid_json, "unknown eventType")
    return event


class EventStream:
    def __init__(self, expected_run_id: str):
        self.expected_run_id = expected_run_id
        self.events: list[dict] = []
        self._buffer = ""

    def ingest(self, chunk: str) -> list[dict]:
        self._buffer += chunk
        accepted: list[dict] = []
        while "\n" in self._buffer:
            line, self._buffer = self._buffer.split("\n", 1)
            if not line.strip():
                continue
            accepted.append(self._accept(line))
        return accepted

    def finish(self) -> None:
        if self._buffer.strip():
            raise TaskProtocolError(TaskProtocolError.truncated_line)

    def _accept(self, line: str) -> dict:
        event = parse_event(line)
        if event.get("runID") != self.expected_run_id:
            raise TaskProtocolError(TaskProtocolError.wrong_run)
        if self.events and event["sequence"] <= self.events[-1]["sequence"]:
            raise TaskProtocolError(TaskProtocolError.stale_sequence)
        self.events.append(event)
        return event


def parse_result(payload: dict) -> dict:
    """Copy metrics. omitted or null values stay missing, never coerced to 0."""
    metrics = []
    for item in payload.get("metrics", []):
        omitted = bool(item.get("omitted"))
        value = None if omitted else item.get("value")
        metrics.append({**item, "value": value, "omitted": omitted})
    result = {
        "schemaVersion": payload["schemaVersion"],
        "identity": {key: payload["identity"][key] for key in IDENTITY_KEYS},
        "state": payload["state"],
        "quality": payload["quality"],
        "metrics": metrics,
    }
    for key in (
        "period",
        "weatherPath",
        "weatherHash",
        "supplyTemperatureC",
        "setpointC",
        "schedule",
        "hvacSchedule",
        "scheduleHash",
        # L2 evidence: gate detail and seat samples ride with the result;
        # seats exist only when the quality gates passed.
        "qualityDetail",
        "seatSamples",
    ):
        if key in payload:
            result[key] = payload[key]
    return result
