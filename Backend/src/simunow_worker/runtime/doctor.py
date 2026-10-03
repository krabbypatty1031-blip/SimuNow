"""Truthful engine availability; no network, pulls, case generation or solving."""
from importlib.resources import files
import json
import re
import shlex
import uuid
from .probe import CommandResult, Probe, SystemProbe


class ConfigurationError(ValueError):
    pass


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate manifest key")
        result[key] = value
    return result


def _check_shape(value, reference):
    # Stdlib-only CLI: require the v1 profile's full field/type structure.
    # Independent JSON Schema validation lives in contracts, not in App startup.
    if isinstance(reference, dict):
        if not isinstance(value, dict) or set(value) != set(reference):
            raise ValueError
        for key in reference:
            _check_shape(value[key], reference[key])
    elif isinstance(reference, list):
        if not isinstance(value, list) or not value:
            raise ValueError
        for entry in value:
            _check_shape(entry, reference[0])
    elif reference is None:
        if value is not None and (type(value) is not int or value <= 0):
            raise ValueError
    elif type(value) is not type(reference) or isinstance(value, str) and not value:
        raise ValueError


def load_manifest(path=None) -> dict:
    try:
        text = files(__package__).joinpath("manifest.json").read_text()
        reference = json.loads(text)
        data = json.loads(path.read_text() if path else text, object_pairs_hook=_unique_object)
        _check_shape(data, reference)
        # The runtime accepts only the implemented route and explicit immutable identities.
        if data["manifest_version"] != 1 or data["profile"] != "mac-arm64-colima" or data["host"]["os"] != "Darwin" or data["host"]["architecture"] != "arm64":
            raise ValueError
        container = data["container"]
        if (container["command"], container["platform"], container["context"]) != ("docker", "linux/arm64", "colima"):
            raise ValueError
        foam, ep = data["engines"]["openfoam"], data["engines"]["energyplus"]
        if foam["execution"] != "docker" or ep["execution"] != "native":
            raise ValueError
        if not re.fullmatch(r"opencfd/openfoam-dev@sha256:[0-9a-f]{64}", foam["image"]):
            raise ValueError
        if not re.fullmatch(r"\d{4}", foam["version"]):
            raise ValueError
        if foam["environment_script"] != f'/usr/lib/openfoam/openfoam{foam["version"]}/etc/bashrc':
            raise ValueError
        if (foam["version_command"], foam["solver_candidate"]) != ("buoyantSimpleFoam", "buoyantSimpleFoam"):
            raise ValueError
        if (foam["os"], foam["architecture"], ep["os"], ep["architecture"]) != ("linux", "arm64", "Darwin", "arm64"):
            raise ValueError
        if not re.fullmatch(r"\d+\.\d+\.\d+", ep["version"]) or not re.fullmatch(r"[0-9a-f]{10}", ep["build"]):
            raise ValueError
        if (ep["command"], ep["executable_env"]) != ("energyplus", "SIMUNOW_ENERGYPLUS_EXECUTABLE"):
            raise ValueError
        for name in ("provider_version", "lima_version", "client_version"):
            if not re.fullmatch(r"\d+\.\d+\.\d+", container[name]):
                raise ValueError
        if not re.fullmatch(r"\d+\.\d+\.\d+", data["python"]["version"]):
            raise ValueError
        if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", data["host"]["minimum_os_version"]):
            raise ValueError
        if (container["provider"], data["python"]["environment"], data["python"]["dependency_lock"]) != ("colima", "Backend/.venv", "Backend/requirements-dev.lock"):
            raise ValueError
        if foam["image_tag"] != f'opencfd/openfoam-dev:{foam["version"]}' or not re.fullmatch(r"sha256:[0-9a-f]{64}", foam["index_digest"]):
            raise ValueError
        if not re.fullmatch(r"[0-9a-f]{64}", ep["asset_sha256"]):
            raise ValueError
        if data["paths"]["implemented"] or data["paths"]["base"] != "project_root_or_project_package":
            raise ValueError
        if set(data["python"]["dependencies"]) != set(reference["python"]["dependencies"]):
            raise ValueError
        for dependency in data["python"]["dependencies"].values():
            if not isinstance(dependency, str) or not re.fullmatch(r"\d+\.\d+\.\d+", dependency):
                raise ValueError
        return data
    except (OSError, ValueError, TypeError, KeyError):
        raise ConfigurationError("Invalid/unreadable runtime manifest or unsupported execution profile.") from None


def architecture(value):
    return {"aarch64": "arm64", "x86_64": "amd64"}.get(value, value)


def failure(result: CommandResult, *, daemon=False, image=False) -> str:
    # Recognize errors internally. Never expose arbitrary stderr or socket paths.
    if result.state in ("timeout", "command_missing", "probe_failed"):
        return result.state
    lower = result.stderr.lower()
    if "permission denied" in lower or "operation not permitted" in lower:
        return "permission_denied"
    if daemon and any(t in lower for t in ("cannot connect", "is the docker daemon running", "connection refused")):
        return "unreachable"
    if image and ("no such image" in lower or "no such object" in lower):
        return "not_installed"
    return "process_failed"


def evidence(result, command):
    return {"command": command, "state": result.state, "exit_code": result.returncode}


def item(state, hint, **extra):
    return {"state": state, "hint": hint, **extra}


def engine_base(target):
    return {"target": {k: target[k] for k in ("distribution", "execution", "version", "os", "architecture")},
            "discovered_version": None, "version_matches": None, "executable": False, "evidence": []}


def probe_container(probe, manifest, timeout):
    target = manifest["container"]
    cmd = [target["command"], "--context", target["context"]]
    report = {"target": target, "os": None, "architecture": None, "memory_bytes": None,
              "client_version": None, "server_version": None, "evidence": []}
    cli = probe.run(cmd + ["--version"], timeout)
    report["evidence"].append(evidence(cli, "docker --version"))
    if cli.state != "ok":
        return item("not_installed" if cli.state == "command_missing" else failure(cli),
                    "Install/configure the Docker CLI, then rerun doctor.", **report)
    match = re.search(r"Docker version (\d+\.\d+\.\d+)", cli.stdout)
    report["client_version"] = match[1] if match else None
    fmt = '{"os":{{json .OSType}},"architecture":{{json .Architecture}},"memory_bytes":{{.MemTotal}},"server_version":{{json .ServerVersion}}}'
    info = probe.run(cmd + ["info", "--format", fmt], timeout)
    report["evidence"].append(evidence(info, "docker --context colima info (selected fields)"))
    if info.state != "ok":
        return item(failure(info, daemon=True), "Check Colima state and Docker context/socket permissions; provision/start the VM explicitly before retrying.", **report)
    try:
        data = json.loads(info.stdout)
        if not isinstance(data["memory_bytes"], int) or data["memory_bytes"] <= 0:
            raise ValueError
        report.update({"os": data["os"], "architecture": architecture(data["architecture"]),
                       "memory_bytes": data["memory_bytes"], "server_version": data["server_version"]})
        if not re.fullmatch(r"\d+\.\d+\.\d+", data["server_version"]):
            raise ValueError
    except (ValueError, TypeError, KeyError):
        return item("probe_failed", "Docker info returned invalid selected fields; check the CLI/daemon pair.", **report)
    if report["os"] != target["os"] or report["architecture"] != target["architecture"]:
        return item("unsupported", "Use a native Linux arm64 VM; this profile does not validate x86 emulation.", **report)
    report["client_version_matches"] = report["client_version"] == target["client_version"]
    if not report["client_version_matches"]:
        return item("version_mismatch", "Docker is connected but CLI version differs from the manifest; explicitly review/update the runtime pin.", **report)
    return item("verified_available", "Daemon connection and Linux arm64 architecture verified.", **report)


def probe_openfoam(probe, manifest, runtime, timeout):
    target = manifest["engines"]["openfoam"]
    report = engine_base(target)
    report["target"]["image"] = target["image"]
    report.update({"image_present": None, "discovered_architecture": None, "execution_architecture": None, "distribution_matches": None})
    if runtime["state"] != "verified_available":
        return item("not_configured", "Resolve the Docker runtime blocker first; local image inventory is unknown.", **report)
    cmd = ["docker", "--context", manifest["container"]["context"]]
    fmt = '{"os":{{json .Os}},"architecture":{{json .Architecture}},"digests":{{json .RepoDigests}}}'
    inspect = probe.run(cmd + ["image", "inspect", target["image"], "--format", fmt], timeout)
    report["evidence"].append(evidence(inspect, "docker image inspect (pinned digest)"))
    if inspect.state != "ok":
        state = failure(inspect, image=True)
        report["image_present"] = False if state == "not_installed" else None
        return item(state, "Explicitly pull the manifest's pinned arm64 image after installation approval, or fix Docker access.", **report)
    try:
        data = json.loads(inspect.stdout)
        report["image_present"] = True
        report["discovered_architecture"] = architecture(data["architecture"])
        if data["os"] != target["os"] or report["discovered_architecture"] != target["architecture"]:
            return item("unsupported", "Pinned image must be Linux arm64; no emulation is accepted.", **report)
        if target["image"] not in data["digests"]:
            return item("identity_mismatch", "Image RepoDigests do not contain the pinned identity; recheck the local image.", **report)
    except (ValueError, TypeError, KeyError):
        return item("probe_failed", "Invalid Docker image metadata; rerun image inspect.", **report)
    name = "simunow-doctor-" + uuid.uuid4().hex
    # No mount, network or case. The bashrc path must NOT be a positional parameter:
    # with $1 set to the bashrc path, the OpenFOAM config chain re-sources it recursively
    # (measured: ~11 s hang then SIGSEGV in the pinned v2506 image). Embed it literally.
    script = ('source ' + shlex.quote(target["environment_script"])
              + ' >/dev/null && uname -m && buoyantSimpleFoam -help >/dev/null && (buoyantSimpleFoam 2>&1 || true)')
    argv = cmd + ["run", "--pull=never", "--rm", "--name", name, "--platform", "linux/arm64",
                  "--network", "none", "--read-only", "--cap-drop", "ALL",
                  "--security-opt", "no-new-privileges", "--entrypoint", "/bin/bash",
                  target["image"], "-c", script]
    result = probe.run(argv, timeout)
    report["evidence"].append(evidence(result, "docker run --pull=never: uname -m + buoyantSimpleFoam -help + solver banner"))
    # Killing a Docker CLI does not stop a daemon-side container. Always bounded cleanup.
    cleanup = probe.run(cmd + ["rm", "-f", name], min(timeout, 3))
    report["evidence"].append(evidence(cleanup, "docker rm -f (only this probe's container)"))
    absent = cleanup.state == "process_failed" and "no such container" in cleanup.stderr.lower()
    report["cleanup_state"] = "ok" if cleanup.state == "ok" or absent else failure(cleanup)
    if result.state != "ok":
        return item(failure(result), "Check the pinned image's bashrc, solver -help and version banner; timed-out probes may need container cleanup if the daemon was lost.", **report)
    output = result.stdout + "\n" + result.stderr
    arch = re.search(r"^(aarch64|arm64|x86_64|amd64)$", result.stdout, re.MULTILINE)
    report["execution_architecture"] = architecture(arch[1]) if arch else None
    if arch is None:
        return item("probe_failed", "Container uname did not return a recognized execution architecture.", **report)
    if report["execution_architecture"] != target["architecture"]:
        return item("unsupported", "Container execution architecture must be arm64; metadata alone is insufficient.", **report)
    versions = set(re.findall(r"(?:OpenFOAM[- ]v?|Version:\s*v?|^v)(\d{4})(?!\d)", output, re.MULTILINE))
    discovered = next(iter(versions)) if len(versions) == 1 else None
    report["discovered_version"] = discovered
    report["distribution_matches"] = "www.openfoam.com" in output
    if discovered is None or not report["distribution_matches"]:
        return item("probe_failed", "Expected OpenCFD version/website in successful solver help; inspect the installation manually.", **report)
    report["executable"] = True
    report["version_matches"] = discovered == target["version"]
    if not report["version_matches"]:
        return item("version_mismatch", "Use the pinned OpenCFD release; startup is executable but the version differs.", **report)
    if report["cleanup_state"] != "ok":
        return item("probe_failed", "Startup succeeded but probe-container cleanup was not confirmed; inspect Docker before retrying.", **report)
    return item("verified_available", "Version and solver help executed; physical validation and the SimuNow pipeline remain pending.", **report)


def probe_energyplus(probe, manifest, host, timeout):
    target = manifest["engines"]["energyplus"]
    report = engine_base(target)
    report["target"]["build"] = target["build"]
    report.update({"discovered_build": None, "discovered_architecture": None})
    if host["os"] != target["os"] or architecture(host["architecture"]) != target["architecture"]:
        return item("unsupported", "This profile requires the native macOS arm64 EnergyPlus asset.", **report)
    setting = probe.setting(target["executable_env"])
    executable = probe.resolve(setting or target["command"])
    if executable is None:
        return item("not_configured" if setting else "not_installed", "Set SIMUNOW_ENERGYPLUS_EXECUTABLE to the installed binary, or add energyplus to PATH. No selected binary was found.", **report)
    binary = probe.run(["file", "-b", executable], timeout)
    report["evidence"].append(evidence(binary, "file -b <selected EnergyPlus binary>"))
    if binary.state != "ok":
        return item(failure(binary), "Install/configure the file utility to verify binary architecture.", **report)
    if "Mach-O" not in binary.stdout or not re.search(r"\barm64\b", binary.stdout):
        report["discovered_architecture"] = "amd64" if "x86_64" in binary.stdout else None
        return item("unsupported", "Use the official Mach-O arm64 binary; wrappers/x86 emulation are not validated.", **report)
    report["discovered_architecture"] = "arm64"
    result = probe.run([executable, "--version"], timeout)
    report["evidence"].append(evidence(result, "energyplus --version"))
    if result.state != "ok":
        return item(failure(result), "Check executable permissions, dependent libraries and macOS installation approval/quarantine.", **report)
    match = re.search(r"EnergyPlus,?\s+Version\s+(\d+\.\d+\.\d+)-([0-9a-f]{10})(?![0-9a-f])", result.stdout, re.IGNORECASE)
    if not match:
        return item("probe_failed", "Version command succeeded but no recognized EnergyPlus version/build was returned.", **report)
    report.update({"executable": True, "discovered_version": match[1], "discovered_build": match[2].lower(),
                   "version_matches": (match[1], match[2].lower()) == (target["version"], target["build"])})
    return item("verified_available" if report["version_matches"] else "version_mismatch",
                "Version command executed; physical validation and the SimuNow pipeline remain pending." if report["version_matches"] else "Install the exact manifest version/build, then rerun doctor.", **report)


def inventory(probe, timeout):
    report = {}
    timeout = min(timeout, 2)
    for tool, args in (("colima", ["version"]), ("limactl", ["--version"]), ("podman", ["--version"]), ("multipass", ["version"]),
                       ("foamVersion", []), ("energyplus", ["--version"])):
        result = probe.run([tool, *args], timeout)
        # Real tools print either "0.10.3" or "v0.10.3"; \b before the digits fails on the v form.
        match = re.search(r"\bv?(\d+\.\d+\.\d+)\b", result.stdout) if result.state == "ok" else None
        report[tool] = item("not_installed" if result.state == "command_missing" else "discovered" if result.state == "ok" else failure(result),
                            "PATH command inventory only; not a target-runtime or physics validation.",
                            version=match[1] if match else None, evidence=[evidence(result, " ".join([tool, *args]))])
    if report["colima"]["state"] == "discovered":
        status = probe.run(["colima", "status"], timeout)
        report["colima"]["connection_state"] = "available" if status.state == "ok" else "unreachable" if "not running" in status.stderr.lower() else failure(status)
        report["colima"]["evidence"].append(evidence(status, "colima status"))
    # Do not inspect SSH files, credentials, private hosts, or guess remote availability.
    report["remote"] = item("not_configured", "No remote adapter exists in this profile; remote capability is unknown.")
    return report


def doctor(manifest, probe: Probe | None = None, timeout=5.0):
    probe = probe or SystemProbe()
    host = probe.host()
    supported = host["os"] == manifest["host"]["os"] and architecture(host["architecture"]) == manifest["host"]["architecture"]
    try:
        os_supported = tuple(map(int, host["os_version"].split("."))) >= tuple(map(int, manifest["host"]["minimum_os_version"].split(".")))
    except ValueError:
        os_supported = False
    supported = supported and os_supported
    runtime = probe_container(probe, manifest, timeout) if supported else item("unsupported", "Use a macOS 14+ arm64 host for this selected profile.")
    engines = {"openfoam": probe_openfoam(probe, manifest, runtime, timeout),
               "energyplus": probe_energyplus(probe, manifest, host, timeout) if supported else item("unsupported", "Host does not match the selected profile.", **engine_base(manifest["engines"]["energyplus"]))}
    python_ready = (host["python_version"] == manifest["python"]["version"] and host["python_isolated"]
                    and host["dependencies"] == manifest["python"]["dependencies"])
    tools = inventory(probe, timeout)
    for key, version_key in (("colima", "provider_version"), ("limactl", "lima_version")):
        tools[key]["target_version"] = manifest["container"][version_key]
        tools[key]["version_matches"] = tools[key]["version"] == tools[key]["target_version"]
    blockers = []
    if not supported:
        blockers.append({"component": "host", "state": "unsupported", "hint": "Use macOS 14+ arm64."})
    if not python_ready:
        blockers.append({"component": "python", "state": "not_configured", "hint": "Use the manifest Python version in an independent environment and install requirements-dev.lock."})
    for key in ("colima", "limactl"):
        if not tools[key]["version_matches"]:
            blockers.append({"component": key, "state": "version_mismatch" if tools[key]["state"] == "discovered" else tools[key]["state"], "hint": "Configure the pinned VM provider/tool version or review the manifest explicitly."})
    for key, value in {"container": runtime, **engines}.items():
        if value["state"] != "verified_available":
            blockers.append({"component": key, "state": value["state"], "hint": value["hint"]})
    return {"report_version": 1, "manifest_version": manifest["manifest_version"], "profile": manifest["profile"],
            "status": "blocked" if blockers else "ready", "host": host, "host_matches": supported,
            "python_target": manifest["python"], "python_matches": python_ready,
            "container": runtime, "engine_checks": engines, "inventory": tools,
            "blockers": blockers, "physical_validation": "not_performed", "simulation_pipeline": "not_implemented"}
