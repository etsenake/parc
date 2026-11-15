# Adapted from Ardia's scripts/lib/instance.mjs, scripts/lib/launchEnv.mjs and apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import os
from pathlib import Path
import plistlib

INSTANCE_KEYS = [
    "jsLocation", "chromiumSwitches", "downloadsDir", "updateFeed", "allowAudio", "allowOcclusion", "releaseNotes",
    "cliHome", "cliBinDir", "cliUrl", "syncFolder", "sharedFolders", "importSourceDir", "importSafariHome",
]
TEST_KEYS = [
    "keychain", "keychainHiddenReads", "keychainFail", "safeStorageAnswer", "reauth", "bluetoothChooser",
    "externalProtocolNoLaunch", "externalProtocolApp", "mediaRouteProvider", "systemMediaPermission", "applyProfileGate", "contextMenu",
    "loginsDelay", "loginsReleaseAfter", "cdpTabsVisible", "nativeDragRefused",
    "pipSelfTest", "pipHover", "fakeFullScreenMs", "shadersKeyWindow", "peekStrict", "importSecret", "importDiaBundleId", "importDiaWindows",
    "cliInstallScript", "legacySource", "legacyCrashAfter", "bangsUrl", "onboarding", "whatsNew", "telemetry",
    "liveMock", "calendarFixture", "appMenu", "appDialog", "loginsTimeout", "screenRecording", "systemLocationPermission",
]
COMMA_KEYS = [
    "chromiumSwitches", "downloadsDir", "updateFeed", "cliHome", "cliBinDir", "cliUrl", "syncFolder", "sharedFolders", "importSourceDir",
    "importSafariHome", "importSecret", "cliInstallScript", "legacySource", "bangsUrl", "liveMock",
]
LIST_VARIABLES = {"ARDIA_INSTANCE", "ARDIA_TEST", "ARDIA_TRACE", "ARDIA_SWITCHES"}

OLD_INSTANCE = {
    "jsLocation": "ARDIA_JS_LOCATION", "chromiumSwitches": "ARDIA_CHROMIUM_SWITCHES", "downloadsDir": "ARDIA_DOWNLOADS_DIR",
    "updateFeed": "ARDIA_UPDATE_FEED_URL", "allowAudio": "ARDIA_ALLOW_AUDIO", "allowOcclusion": "ARDIA_ALLOW_OCCLUSION",
    "releaseNotes": "ARDIA_RELEASE_NOTES", "cliHome": "ARDIA_CLI_HOME", "cliBinDir": "ARDIA_CLI_BIN_DIR", "cliUrl": "ARDIA_CLI_URL",
    "syncFolder": "ARDIA_SYNC_DEFAULT_FOLDER", "importSourceDir": "ARDIA_IMPORT_SOURCE_DIR", "importSafariHome": "ARDIA_IMPORT_SAFARI_HOME",
}
OLD_TEST = {
    "keychain": "ARDIA_TEST_KEYCHAIN", "keychainHiddenReads": "ARDIA_TEST_KEYCHAIN_HIDDEN_READS", "keychainFail": "ARDIA_TEST_KEYCHAIN_FAIL",
    "safeStorageAnswer": "ARDIA_TEST_SAFE_STORAGE_ANSWER", "reauth": "ARDIA_TEST_REAUTH", "pipSelfTest": "ARDIA_PIP_SELFTEST",
    "pipHover": "ARDIA_PIP_HOVER", "fakeFullScreenMs": "ARDIA_FAKE_FULLSCREEN_MS", "shadersKeyWindow": "ARDIA_SHADERS_FORCE_KEY",
    "peekStrict": "ARDIA_PEEK_STRICT", "importSecret": "ARDIA_IMPORT_TEST_SECRET", "importDiaBundleId": "ARDIA_IMPORT_DIA_BUNDLE_ID",
    "cliInstallScript": "ARDIA_CLI_INSTALL_SCRIPT", "legacySource": "ARDIA_LEGACY_SOURCE", "legacyCrashAfter": "ARDIA_LEGACY_CRASH_AFTER",
    "bangsUrl": "ARDIA_BANGS_URL", "onboarding": "ARDIA_ONBOARDING", "whatsNew": "ARDIA_WHATS_NEW", "telemetry": "ARDIA_TELEMETRY",
    "liveMock": "ARDIA_LIVE_MOCK", "calendarFixture": "ARDIA_CALENDAR_FIXTURE",
}
OLD_TEST_SWITCH = {
    "bluetoothChooser": "--ardia-test-bluetooth-chooser", "externalProtocolNoLaunch": "--ardia-test-external-protocol-no-launch",
    "mediaRouteProvider": "--ardia-test-media-route-provider", "systemMediaPermission": "--ardia-test-system-media-permission",
    "applyProfileGate": "--ardia-apply-profile-gate",
}
OLD_TRACE = {"visibility": "ARDIA_TRACE_VISIBILITY", "pip": "ARDIA_TRACE_PIP", "pipZoom": "ARDIA_PIP_ZOOM_TRACE"}

SHARED_SWITCHES = ["--no-first-run", "--no-default-browser-check", "--password-store=basic",
                   "--disable-backgrounding-occluded-windows", "--mute-audio"]
PARC_PROFILE = "profile"
PARC_MARKS = "perf-marks.jsonl"


def _text(value) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    return str(value)


def _listed(entries: dict) -> str:
    return ",".join(key if value is True else f"{key}={_text(value)}"
                    for key, value in entries.items() if value is not None and value is not False)


def launch_variables(instance=None, test=None, trace=(), switch_overrides=None) -> dict:
    env = {}
    instance_list = _listed(instance or {})
    test_list = _listed(test or {})
    switch_list = ",".join(f"{name}={'on' if on else 'off'}" for name, on in (switch_overrides or {}).items())
    if instance_list:
        env["ARDIA_INSTANCE"] = instance_list
    if test_list:
        env["ARDIA_TEST"] = test_list
    if trace:
        env["ARDIA_TRACE"] = ",".join(trace)
    if switch_list:
        env["ARDIA_SWITCHES"] = switch_list
    return env


def entries_of(text, known) -> dict:
    entries = {}
    last = None
    for piece in (text if text is not None else "").split(","):
        key = piece.split("=")[0].strip()
        if key not in known and last in COMMA_KEYS:
            entries[last] += f",{piece}"
            continue
        at = piece.find("=")
        if key:
            entries[key] = "1" if at < 0 else piece[at + 1:].strip()
        last = key
    return entries


def merge_launch_env(*envs) -> dict:
    out = {}
    instance, test, switches = {}, {}, {}
    trace = []
    for env in envs:
        for name, value in (env or {}).items():
            if name not in LIST_VARIABLES or value is None:
                out[name] = value
                continue
            if name == "ARDIA_INSTANCE":
                instance.update(entries_of(value, INSTANCE_KEYS))
            elif name == "ARDIA_TEST":
                test.update(entries_of(value, TEST_KEYS))
            elif name == "ARDIA_TRACE":
                for area in (a.strip() for a in value.split(",")):
                    if area and area not in trace:
                        trace.append(area)
            else:
                for piece in value.split(","):
                    parts = [s.strip() for s in piece.split("=")]
                    switch_name = parts[0]
                    on = parts[1] if len(parts) > 1 else ""
                    if switch_name and on:
                        switches[switch_name] = on in ("on", "1", "true")

    def bare(entries):
        return {key: True if value == "1" else value for key, value in entries.items()}

    return {**out, **launch_variables(instance=bare(instance), test=bare(test), trace=trace, switch_overrides=switches)}


_reads_launch_config = {}


def binary_reads_launch_config(binary: str) -> bool:
    debug = f"{binary}.debug.dylib"
    if os.path.exists(debug):
        binary = debug
    if binary in _reads_launch_config:
        return _reads_launch_config[binary]
    needle = b"ARDIA_INSTANCE"
    chunk = 1 << 22
    found = False
    with open(binary, "rb") as handle:
        size = os.fstat(handle.fileno()).st_size
        at = 0
        while at < size and not found:
            handle.seek(at)
            found = needle in handle.read(chunk)
            at += chunk - len(needle)
    _reads_launch_config[binary] = found
    return found


def for_build(binary: str, env: dict) -> dict:
    if binary_reads_launch_config(binary):
        return env
    rest = {k: v for k, v in env.items() if k not in ("ARDIA_INSTANCE", "ARDIA_TEST", "ARDIA_TRACE")}
    instance = entries_of(env.get("ARDIA_INSTANCE"), INSTANCE_KEYS)
    test = entries_of(env.get("ARDIA_TEST"), TEST_KEYS)
    out = dict(rest)
    for key, value in instance.items():
        if key in OLD_INSTANCE:
            out[OLD_INSTANCE[key]] = value
    for key, value in test.items():
        if key in OLD_TEST:
            out[OLD_TEST[key]] = value
    switches = [OLD_TEST_SWITCH[key] if value == "1" else f"{OLD_TEST_SWITCH[key]}={value}"
                for key, value in test.items() if key in OLD_TEST_SWITCH]
    data = env.get("ARDIA_DATA_DIR")
    if test.get("contextMenu") and data:
        out["ARDIA_CONTEXT_MENU_LOG"] = f"{data}/context-menu.json"
    for area in (a for a in (env.get("ARDIA_TRACE") or "").split(",") if a):
        if area in OLD_TRACE:
            out[OLD_TRACE[area]] = "1"
        if area == "trafficLights" and data:
            out["ARDIA_TRAFFIC_LIGHTS_LOG"] = f"{data}/traffic-lights.log"
        if area == "profileGate":
            switches.append("--ardia-show-profile-gate")
    if switches:
        out["ARDIA_CHROMIUM_SWITCHES"] = " ".join(s for s in [out.get("ARDIA_CHROMIUM_SWITCHES"), *switches] if s)
    return out


def bundle_info(app) -> dict:
    with open(Path(app) / "Contents/Info.plist", "rb") as handle:
        return plistlib.load(handle)


def binary_of(app) -> str:
    return os.path.join(app, "Contents/MacOS", bundle_info(app)["CFBundleExecutable"])


def app_env(app, env: dict) -> dict:
    binary = binary_of(app)
    for_this_build = for_build(binary, env)
    if os.path.basename(binary) != "Netnyahoo":
        return for_this_build
    legacy = {f"NETNYAHOO_{k[len('ARDIA_'):]}": v for k, v in for_this_build.items() if k.startswith("ARDIA_")}
    return {**for_this_build, **legacy}


def extra_env(entries, name: str) -> list[dict]:
    chosen = [e[len(name) + 1:] for e in entries if e.startswith(f"{name}=")]
    return [{e[:e.find("=")]: e[e.find("=") + 1:]} for e in chosen]


def launch_env(browser: str, home: str, port: int, page_base: str, extra=(), app=None) -> dict:
    env = {"HOME": home, "CFFIXED_USER_HOME": home}
    if browser == "ardia":
        env.update({"ARDIA_BACKGROUND": "1", "ARDIA_DATA_DIR": os.path.join(home, "data"), "ARDIA_REMOTE_DEBUGGING_PORT": str(port),
                    **launch_variables(instance={"updateFeed": f"{page_base}/appcast.xml"})})
    merged = merge_launch_env(env, *extra)
    return app_env(app, merged) if browser == "ardia" else merged


def parc_profile(home: str) -> str:
    return os.path.join(home, PARC_PROFILE)


def launch_args(browser: str, home: str, port: int, window, restore_switch: bool = False) -> list[str]:
    x, y, w, h = window
    if browser == "ardia":
        return [*SHARED_SWITCHES, "-NSAppSleepDisabled", "YES"]
    if browser == "parc":
        return ["--parc-profile", parc_profile(home), "--parc-test-instance", f"--parc-perf-marks={os.path.join(home, PARC_MARKS)}",
                f"--remote-debugging-port={port}", "--remote-allow-origins=*",
                "--mute-audio", "--disable-backgrounding-occluded-windows", "--no-first-run", "--no-default-browser-check",
                "--password-store=basic", "--use-mock-keychain", f"--window-size={w},{h}", f"--window-position={x},{y}"]
    return [f"--user-data-dir={os.path.join(home, 'udd')}", f"--remote-debugging-port={port}", "--remote-allow-origins=*",
            *SHARED_SWITCHES, "--use-mock-keychain", f"--window-size={w},{h}", f"--window-position={x},{y}",
            *(["--restore-last-session"] if restore_switch else [])]


def open_argv(app: str, env: dict, url, args) -> list[str]:
    pairs = [part for key, value in env.items() if value is not None for part in ("--env", f"{key}={value}")]
    return ["open", "-g", "-n", *pairs, "-a", app, *([url] if url else []), "--args", *args]


def chromium_dirs(browser: str, home: str) -> list[str]:
    dirs = [os.path.join(home, "udd")]
    if browser == "parc":
        dirs.append(os.path.join(parc_profile(home), "Chromium-v1"))
    return dirs


def debug_logs(browser: str, home: str) -> list[str]:
    logs = [os.path.join(home, "data/Chromium/chrome_debug.log")]
    if browser == "parc":
        logs.append(os.path.join(parc_profile(home), "Chromium-v1/chrome_debug.log"))
    return logs


def profile_used(browser: str, home: str) -> bool:
    if browser == "ardia":
        return os.path.exists(os.path.join(home, "data/Chromium/Default"))
    if browser == "parc":
        return os.path.exists(os.path.join(parc_profile(home), "Chromium-v1"))
    return os.path.exists(os.path.join(home, "udd/Default")) or os.path.exists(os.path.join(home, "udd/User Data/Default"))
