"""In-process L0 self-check for doctor. Lazily imports the locked dependencies so the
doctor module stays importable with the standard library alone.

The self-check runs the real L0 adapter twice on a fixed minimal snapshot and
verifies determinism, quality state and key metrics. It proves the Python compute
path works; it is not a physical validation and says nothing about L1/L2 engines.
"""
import json


def _self_check_snapshot():
    """Minimal but structurally complete snapshot; every value is an explicit assumption."""
    def known(value, unit):
        return {"state": "known", "value": value, "unit": unit,
                "source": {"kind": "assumed", "note": "doctor L0 self-check fixture; not a physical case"}}
    surfaces = [{"id": f"00000000-0000-4000-8000-0000000000{i:02X}", "face": face}
                for i, face in enumerate(("xMin", "xMax", "yMin", "yMax", "floor", "ceiling"), start=1)]
    return {
        "schemaVersion": 2,
        "projectID": "00000000-0000-4000-8000-0000000000A1",
        "scenarioID": "00000000-0000-4000-8000-0000000000A2",
        "lengthUnit": "m", "coordinateSystem": "rightHandedZUp",
        "geometry": {"rooms": [{
            "id": "00000000-0000-4000-8000-0000000000A3", "name": "self-check",
            "shape": {"kind": "simunow.geometry.rectangularRoom", "payloadVersion": 1,
                      "payload": {"dimensions": {"width": known(2, "m"), "depth": known(2, "m"),
                                                 "height": known(2.5, "m")}}},
            "northAngle": {"state": "unknown", "reason": "irrelevant for the L0 self-check"},
            "surfaces": surfaces, "openings": []}], "obstacles": []},
        "inputs": {
            "usage": {"seats": [], "occupants": [], "equipment": []},
            "hvac": [{
                "id": "00000000-0000-4000-8000-0000000000A4",
                "roomID": "00000000-0000-4000-8000-0000000000A3", "name": "self-check unit",
                "position": {"x": 1, "y": 1, "z": 2},
                "definition": {"kind": "simunow.hvac.singleSplit", "payloadVersion": 1,
                               "payload": {"coolingCapacity": known(2000, "W"),
                                           "electricalPower": known(700, "W"), "cop": known(3, "1")}},
                "ports": [
                    {"id": "00000000-0000-4000-8000-0000000000A5", "role": "supply",
                     "position": {"x": 1, "y": 1, "z": 2}, "direction": {"x": 0, "y": -1, "z": 0},
                     "area": known(0.05, "m2"), "volumeFlow": known(0.1, "m3/s"),
                     "speed": known(2, "m/s"), "density": known(1.2, "kg/m3")},
                    {"id": "00000000-0000-4000-8000-0000000000A6", "role": "return",
                     "position": {"x": 1, "y": 1, "z": 2.2}, "direction": {"x": 0, "y": 1, "z": 0},
                     "area": known(0.05, "m2"), "volumeFlow": known(0.1, "m3/s"),
                     "speed": known(2, "m/s"), "density": known(1.2, "kg/m3")}],
                "supplyTemperature": known(13, "degC")}],
            "controls": [{
                "id": "00000000-0000-4000-8000-0000000000A7",
                "deviceID": "00000000-0000-4000-8000-0000000000A4",
                "setpoint": known(24, "degC"), "sensorPosition": {"x": 1, "y": 1, "z": 1.1},
                "schedule": {"intervals": [{"startMinute": 0, "endMinute": 1440, "fraction": known(1, "1")}]}}],
            "envelope": {
                "surfaces": [
                    {"surfaceID": surfaces[0]["id"], "exposure": "outdoors", "uValue": known(1.5, "W/(m2.K)"),
                     "boundary": {"mode": "temperature", "temperature": known(32, "degC")}}] + [
                    {"surfaceID": s["id"], "exposure": "adiabatic", "uValue": known(1.5, "W/(m2.K)"),
                     "boundary": {"mode": "heatFlux", "heatFlux": known(0, "W/m2")}} for s in surfaces[1:]],
                "windows": []},
            "ventilation": [{
                "roomID": "00000000-0000-4000-8000-0000000000A3",
                "outdoorAir": known(0, "m3/s"), "exhaustAir": known(0, "m3/s"),
                "infiltration": known(0, "m3/s"), "exfiltration": known(0, "m3/s"),
                "density": known(1.2, "kg/m3"), "openings": []}],
            "environment": {"outdoorTemperature": known(32, "degC"),
                            "outdoorHumidity": known(0.6, "1"), "indoorHumidity": known(0.5, "1")}},
        "evaluation": {"cost": {"currency": None, "tariffs": [], "quotes": []}}}


def l0_check():
    """Run the real L0 adapter twice; verified_available only on deterministic clean output."""
    evidence = {"command": "in-process: steady_state.run(self-check snapshot) twice; compare determinism, quality and metrics",
                "state": "ok", "exit_code": 0}
    try:
        from ..adapters.l0 import steady_state
        from ..models.codec import ProjectCodec
    except ImportError as error:
        return {"state": "not_configured",
                "hint": f"Locked development dependencies are not importable ({error}); install requirements-dev.lock.",
                "evidence": [dict(evidence, state="command_missing", exit_code=None)]}
    try:
        snapshot = ProjectCodec().decode_snapshot(json.dumps(_self_check_snapshot()))
        first = steady_state.run(snapshot)
        second = steady_state.run(snapshot)
        assert first == second, "L0 is not deterministic"
        assert first["quality"]["state"] == "passed", f"quality not passed: {first['quality']}"
        metrics = {m["name"]: m for m in first["metrics"]}
        peak = metrics["coolingLoadPeak"]["value"]
        assert isinstance(peak, (int, float)) and peak > 0, "coolingLoadPeak missing or non-positive"
        assert metrics["capacityAdequate"]["value"] is True, "self-check unit should be adequate"
    except Exception as error:
        return {"state": "probe_failed",
                "hint": f"L0 self-check failed: {error}",
                "evidence": [dict(evidence, state="probe_failed", exit_code=None)]}
    return {"state": "verified_available",
            "hint": "L0 representative-day balance executed twice with identical passed output. Not a physical validation; L1/L2 remain unconfigured.",
            "evidence": [evidence]}
