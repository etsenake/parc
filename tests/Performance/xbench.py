#!/usr/bin/env python3
# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import argparse
from datetime import datetime, timezone
from decimal import ROUND_HALF_UP, Decimal
import errno
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

from cdp import Cdp
from instance import (bundle_info, chromium_dirs, debug_logs, extra_env, launch_args, launch_env, open_argv,
                      profile_used)
from pages import PageServer
from rivals import MISSING, RivalsRefused, merge_rivals, rival_warnings

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
NATIVE = HERE / "native"
DEFAULT_ROOT = REPO / "build" / "perf" / "xbench"
SETTLE_TEMPLATE_MS = 90_000
STEADY_MS = 120_000
HARNESS = 1
WINDOW_SIZE = (1280, 800)
METHOD = "docs/perf/vs-browsers.md"
LOCK_FILE = "/tmp/parc-perflab.lock"
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PARC_RELEASES = "https://github.com/etsenake/parc-releases/releases/download"
PARC_ID = "org.parc.Browser"
PARC_COPY_ID = "org.parc.Browser.bench"

BROWSERS = {
    "parc": {"name": "Parc", "bundle": "parc/Parc.app", "installed_id": PARC_ID, "copy_id": PARC_COPY_ID,
             "test_targets_only": True, "await_window": True, "quit_tool": True,
             "download_url": lambda i: f"{PARC_RELEASES}/v{i['version']}/Parc-{i['version']}-arm64.dmg"},
    "ardia": {"name": "Ardia", "bundle": "ardia/Ardia.app", "hidden": True},
    "dia": {"name": "Dia", "bundle": "dia/Dia.app", "read_only": True, "guard_prefs": True,
            "download_url": lambda i: f"https://releases.diabrowser.com/release/Dia-{i['version']}-{i['build']}.dmg"},
    "helium": {"name": "Helium", "bundle": "helium/Helium.app", "restore_switch": True,
               "download_url": lambda i: f"https://github.com/imputnet/helium-macos/releases/download/{i['version']}/helium_{i['version']}_arm64-macos.dmg"},
    "chrome": {"name": "Google Chrome", "bundle": "chrome/Google Chrome.app", "restore_switch": True,
               "download_url": lambda i: "https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg"},
}

NOTES = [
    "One harness drives every browser from outside the app over CDP, the same local test pages served from 127.0.0.1, one instance at a time, browsers interleaved per run and rotated each round.",
    "Every run starts from its own copy of a template profile made once per browser (one launch, the test page open, 90 s to settle, quit), with HOME pointed into it; default settings, built-in ad blockers as shipped.",
    "Chrome and Helium get --restore-last-session so every browser restores the same one-tab session (Parc, Ardia and Dia restore by default).",
    "Window 1280×800 at the same place for every browser that takes --window-size; Ardia's window frame is set in its session to the same size; Dia ignores --window-size and opens full-screen-sized (1512×949).",
    "Chrome and Helium run as shipped: they bring themselves to the front at launch and on a tab switch, and fetch their Finch (variations) seed and components as usual. Dia runs in view without taking focus, signed in with a throwaway account. Ardia runs in its background test mode: it can't become the active app, its windows sit behind the owner's and report themselves as not occluded, and App Nap is off for it.",
    "Parc runs as a clone with its own bundle identifier (org.parc.Browser.bench), signed ad hoc, with its test-instance switches (--parc-test-instance, its own profile folder, the window size and position on the command line); it restores its last session by default and may come to the front like Chrome.",
    "Memory is phys_footprint summed over every process of the browser (app, helpers, GPU, renderers, utilities, anything running from its bundle); CPU and wakeups are rusage over the same processes.",
    "Measured on the owner's working Mac, in normal use: browsers interleaved run by run and rotated each round so the owner's activity falls on all of them alike; each figure is the median of the runs, with min–max and n.",
    "Median, min–max and n over runs; a row is a win when the ranges don't overlap.",
]

DESCRIPTION = """Cross-browser benchmark: Parc against Ardia, Helium and Google Chrome (and Dia) on the release gate's rows that
every Chromium browser can be measured on the same way. One harness drives them all from outside the app, over CDP,
with the same local pages, window size, fresh profile per run and number of runs, interleaved browser by browser
(A B C D, then rotated).

  xbench.py run    --out <dir> [options]   measure (resumable: done items are skipped)
  xbench.py check  --out <dir> [options]   one quick look per browser, nothing kept
  xbench.py report --out <dir> [--json <file>] [--md <file>] [--rivals-from <bench.json>]
  xbench.py clean  --out <dir>             quit leftovers, unregister the copies, delete runs
  xbench.py signin --browsers dia --base dia=<home>   open the browser on that HOME, in view, for the owner to sign
                   in by hand; returns when they quit it (or at --deadline)
  xbench.py prepare-bg --browsers <a,b>    make <apps>/<name>-bg/: the copy with LSBackgroundOnly set, signed ad hoc
                   with its entitlements and without the hardened runtime; run it as the browser <name>-bg
  xbench.py prepare-parc --app parc=<Parc.app>   make <apps>/parc/Parc.app: a clone of that Parc with the bundle
                   identifier org.parc.Browser.bench (so links and AppleScript can't reach the installed Parc), signed
                   ad hoc with its entitlements and without the hardened runtime. Runs refuse a Parc copy that still
                   has org.parc.Browser"""

EPILOG = """What every instance gets: its own copy of a template profile (made once per browser by one launch that opens the
test page, settles 90 s and quits), HOME and CFFIXED_USER_HOME pointed into it (nothing reaches the real ~/Library),
the CDP port, and --disable-backgrounding-occluded-windows --mute-audio --no-first-run --no-default-browser-check
--password-store=basic. Chromium browsers: --user-data-dir --use-mock-keychain --window-size --window-position, and
Chrome and Helium also --restore-last-session. Parc: --parc-profile --parc-test-instance --parc-perf-marks
--remote-debugging-port --remote-allow-origins=* --use-mock-keychain --window-size --window-position (it restores its
session by default). Ardia: ARDIA_BACKGROUND=1, ARDIA_DATA_DIR, ARDIA_REMOTE_DEBUGGING_PORT, onboarding done.

Rows:
  launch → page painted (link)  link     `open -a <app> <url>` with the browser closed: the URL's first-contentful-paint
  launch → window on screen     restore  the pid's first on-screen window ≥ 300×200 with alpha > 0 (CGWindowList)
  launch → restored tab painted restore  `open -a <app>`: the restored test page's first-contentful-paint
  new tab → first paint         session  Target.createTarget(url) → the page's FCP (median of 5 per run)
  tab switch → shown            session  Target.activateTarget → visibilitychange to visible + 2 rAFs (16 per run, 20 tabs)
  new window → first paint      session  Target.createTarget(url, newWindow) → FCP, only if a new window opened (3 per run)
  memory                        session  phys_footprint summed over every process of the instance at 1, 10, 20 tabs and
                                         30 s after closing back to 1
  idle CPU, idle wakeups/s      session  rusage of every process over --idle secs, at 1 and at 20 tabs
  download, on disk             size     the DMG's bytes; du of the bundle
Results: <out>/samples.jsonl (one line per finished item), report → bench.json and the table."""

THROTTLE_PROBE = """document.visibilityState !== "visible" ? -1 : new Promise((done) => { let n = 0; const t0 = performance.now();
      (function f() { n++; if (performance.now() - t0 < 250) requestAnimationFrame(f); else done(n); })(); })"""

ENTITLEMENT = re.compile(r"<key>([^<]+)</key>\s*(<true/>|<false/>|<string>[^<]*</string>|<array>[\s\S]*?</array>|<array/>)")
RESTRICTED = re.compile(r"com\.apple\.application-identifier|com\.apple\.developer\..*|keychain-access-groups")
LAUNCHD_VENDORS = re.compile(r"google|keystone|helium|thebrowser|org\.parc", re.IGNORECASE)


class Aborted(Exception):
    pass


class Fatal(Exception):
    pass


def base_of(name: str) -> str:
    return name.split("-")[0]


def spec(name: str):
    return BROWSERS.get(base_of(name))


def is_ardia(name: str) -> bool:
    return base_of(name) == "ardia"


def now_ms() -> int:
    return int(time.time() * 1000)


def sleep_ms(ms: float):
    time.sleep(max(0, ms) / 1000)


def iso(ms=None) -> str:
    ms = now_ms() if ms is None else int(ms)
    return datetime.fromtimestamp(ms // 1000, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{ms % 1000:03d}Z"


def utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def log(*parts):
    print(f"[xbench {datetime.now(timezone.utc).strftime('%H:%M:%S')}]", *parts, file=sys.stderr, flush=True)


def finite(x) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def num(x) -> float:
    return x if isinstance(x, (int, float)) and not isinstance(x, bool) else math.nan


def median(xs) -> float:
    s = sorted(x for x in xs if finite(x))
    if not s:
        return math.nan
    m = len(s) >> 1
    return s[m] if len(s) % 2 else (s[m - 1] + s[m]) / 2


def js_round(x):
    if not finite(x):
        return math.nan
    floor = math.floor(x)
    return floor + 1 if x - floor >= 0.5 else floor


def round_figure(x):
    if not finite(x):
        return None
    return js_round(x) if abs(x) >= 100 else js_round(x * 100) / 100


def to_fixed(x, digits: int) -> str:
    if not finite(x):
        return "NaN"
    return str(Decimal(x).quantize(Decimal(1).scaleb(-digits), rounding=ROUND_HALF_UP))


def js_number(x) -> str:
    if isinstance(x, int):
        return str(x)
    if not math.isfinite(x):
        return "null"
    if x.is_integer() and abs(x) < 1e21:
        return str(int(x))
    text = repr(x)
    if "e" not in text:
        return text
    mantissa, exponent = text.split("e")
    sign = "-" if mantissa.startswith("-") else ""
    digits = mantissa.lstrip("-").replace(".", "")
    point = int(exponent) + 1
    if -6 < point <= 0:
        return f"{sign}0.{'0' * -point}{digits}"
    power = point - 1
    head = digits[0] + (f".{digits[1:]}" if len(digits) > 1 else "")
    return f"{sign}{head}e{'+' if power >= 0 else '-'}{abs(power)}"


def js_text(value) -> str:
    if value is MISSING:
        return "undefined"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and not math.isfinite(value):
        return "NaN" if math.isnan(value) else ("Infinity" if value > 0 else "-Infinity")
    if isinstance(value, (int, float)):
        return js_number(value)
    return str(value)


def _key(key) -> str:
    return json.dumps(str(key), ensure_ascii=False)


def stringify(value, indent=None, level=0) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return js_number(value)
    if isinstance(value, (str, os.PathLike)):
        return json.dumps(os.fspath(value), ensure_ascii=False)
    if isinstance(value, dict):
        items = [(_key(k), stringify(v, indent, level + 1)) for k, v in value.items()]
        if not items:
            return "{}"
        if indent is None:
            return "{" + ",".join(f"{k}:{v}" for k, v in items) + "}"
        inner, outer = " " * (indent * (level + 1)), " " * (indent * level)
        return "{\n" + ",\n".join(f"{inner}{k}: {v}" for k, v in items) + f"\n{outer}}}"
    if isinstance(value, (list, tuple)):
        items = [stringify(v, indent, level + 1) for v in value]
        if not items:
            return "[]"
        if indent is None:
            return "[" + ",".join(items) + "]"
        inner, outer = " " * (indent * (level + 1)), " " * (indent * level)
        return "[\n" + ",\n".join(f"{inner}{v}" for v in items) + f"\n{outer}]"
    raise TypeError(f"can't write {type(value).__name__} as JSON")


def js_regex_escape(text: str) -> str:
    return re.sub(r"[.*+?^${}()|\[\]\\]", lambda m: "\\" + m.group(0), text)


def dig(value, *keys):
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def kill(pid: int, sig):
    try:
        os.kill(pid, sig)
    except OSError:
        pass


def rm_rf(path):
    def ignore_missing(function, failed, error):
        if not isinstance(error, FileNotFoundError):
            raise error

    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path, onexc=ignore_missing)
    elif os.path.lexists(path):
        os.unlink(path)


def run_text(argv, **options) -> str:
    return subprocess.run([str(a) for a in argv], capture_output=True, text=True, errors="replace", **options).stdout


def tool(name: str) -> Path:
    import native
    return native.compiled(name, NATIVE / f"{name}.swift")


def process_rows() -> list[dict]:
    rows = []
    for line in subprocess.run(["ps", "-axww", "-o", "pid=,ppid=,command="], capture_output=True, text=True,
                               errors="replace", check=True).stdout.split("\n"):
        m = re.match(r"^(\d+)\s+(\d+)\s+(.*)$", line.strip())
        if m:
            rows.append({"pid": int(m[1]), "ppid": int(m[2]), "command": m[3]})
    return rows


def kind_of(command: str) -> str:
    m = re.search(r"--type=(\S+)", command)
    if not m:
        return "crashpad" if "crashpad_handler" in command else "browser"
    kind = m.group(1)
    if kind == "utility":
        sub = re.search(r"--utility-sub-type=([A-Za-z0-9_.]+)", command)
        return f"utility:{sub.group(1).split('.')[0] if sub else '?'}"
    if kind == "renderer" and "--extension-process" in command:
        return "extension"
    return kind


def outside_name(command: str) -> str:
    m = re.search(r"([^/]+)\.(?:app|xpc)/Contents/MacOS/", command)
    return m.group(1) if m else os.path.basename(command.split(" ")[0])


def app_info(app) -> dict:
    plist = bundle_info(app)
    text = lambda key: "" if plist.get(key) is None else str(plist.get(key))
    return {"exe": os.path.join(os.path.realpath(app), "Contents/MacOS", text("CFBundleExecutable")),
            "version": text("CFBundleShortVersionString"), "build": text("CFBundleVersion"), "id": text("CFBundleIdentifier")}


def du(path) -> int:
    return int(run_text(["du", "-sk", path], check=True).split("\t")[0]) * 1024


def machine() -> dict:
    hw = run_text(["system_profiler", "SPHardwareDataType"], check=True)

    def field(key):
        m = re.search(f"{key}: (.+)", hw)
        return m.group(1).strip() if m else None

    memsize = int(run_text(["sysctl", "-n", "hw.memsize"], check=True).strip())
    product = run_text(["sw_vers", "-productVersion"], check=True).strip()
    build = run_text(["sw_vers", "-buildVersion"], check=True).strip()
    result = {"model": f"{js_text(field('Model Name') or MISSING)} ({js_text(field('Model Identifier') or MISSING)})",
              "chip": field("Chip"), "cores": os.cpu_count(), "ram": f"{js_round(memsize / 2 ** 30)} GB",
              "macOS": f"{product} ({build})"}
    if result["chip"] is None:
        del result["chip"]
    return result


def chromium_of(app, template):
    m = re.search(r"/(\d+\.\d+\.\d+\.\d+)$", str((template or {}).get("browser") or ""))
    if m:
        return m.group(1)
    frameworks = os.path.join(app, "Contents/Frameworks")
    for fw in sorted(f for f in (os.listdir(frameworks) if os.path.isdir(frameworks) else []) if f.endswith(".framework")):
        versions_dir = os.path.join(frameworks, fw, "Versions")
        versions = sorted(os.listdir(versions_dir)) if os.path.exists(versions_dir) else []
        dotted = next((v for v in versions if re.fullmatch(r"\d+\.\d+\.\d+\.\d+", v)), None)
        if dotted:
            return dotted
    arc = os.path.join(frameworks, "ArcCore.framework/Resources/Info.plist")
    if not os.path.exists(arc):
        return None
    with open(arc, "rb") as handle:
        import plistlib
        return str(plistlib.load(handle).get("CFBundleShortVersionString", ""))


def plan(names, rows, rounds: int, launches: int) -> list[dict]:
    items = []
    for r in range(rounds):
        order = [names[(i + r) % len(names)] for i in range(len(names))]
        for kind in ("link", "restore"):
            if kind in rows:
                for k in range(launches):
                    for n in order:
                        items.append({"key": f"r{r}/{kind}{k}/{n}", "round": r, "kind": kind, "browser": n})
        if "session" in rows:
            for n in order:
                items.append({"key": f"r{r}/session/{n}", "round": r, "kind": "session", "browser": n})
    return items


def estimate_ms(kind: str, idle: float) -> float:
    return {"link": 25_000, "restore": 25_000, "session": 5 * 60_000 + 4 * idle * 1000}[kind]


def read_samples(file) -> list[dict]:
    if not os.path.exists(file):
        return []
    return [json.loads(line) for line in Path(file).read_text().split("\n") if line]


def record(file, sample: dict):
    with open(file, "a") as handle:
        handle.write(stringify(sample) + "\n")


def done_keys(samples) -> set:
    return {s["key"] for s in samples if s.get("ok")}


def pending(names, samples, rows, rounds: int, launches: int) -> list[dict]:
    done = done_keys(samples)
    return [i for i in plan(names, rows, rounds, launches) if i["key"] not in done]


def usage_delta(a, b) -> dict:
    before = {u["pid"]: u for u in a}
    kinds = {}
    total = {"cpu": 0, "wakeups": 0}
    for u in b:
        p = before.get(u["pid"])
        if not p:
            continue
        secs = (u["at"] - p["at"]) / 1000
        cpu = ((u["cpuNs"] - p["cpuNs"]) / 1e9 / secs) * 100
        wakeups = (u["idleWakeups"] + u["interruptWakeups"] - p["idleWakeups"] - p["interruptWakeups"]) / secs
        k = kinds.setdefault(u.get("kind"), {"cpu": 0, "wakeups": 0, "count": 0})
        k["cpu"] += cpu
        k["wakeups"] += wakeups
        k["count"] += 1
        total["cpu"] += cpu
        total["wakeups"] += wakeups
    return {"total": total, "kinds": kinds, "processes": len(b)}


def summary_line(s: dict) -> dict:
    if s["kind"] != "session":
        return {"window": js_round(s.get("window")), "paint": js_round(s.get("firstPaint")), "pages": s.get("pages"),
                "focus": s.get("focusTaken")}
    return {
        "idle1": [to_fixed(dig(s, "idle", "tabs1", "total", "cpu"), 2), to_fixed(dig(s, "idle", "tabs1", "total", "wakeups"), 1)],
        "idle20": [to_fixed(dig(s, "idle", "tabs20", "total", "cpu"), 2), to_fixed(dig(s, "idle", "tabs20", "total", "wakeups"), 1)],
        "mem": [js_round(dig(s, "memory", k, "totalMB")) for k in ("tabs1", "tabs10", "tabs20", "closed")],
        "sw": js_round(median(s["tabSwitch"])), "nt": js_round(median(s["newTab"])),
        "nw": [js_round(x) for x in s["newWindow"]], "opened": s["newWindowOpened"],
    }


def per_million(x):
    return x / 1e6 if finite(x) else None


ROWS = [
    {"id": "launch-link", "label": "Cold launch → page painted (link opened from another app)", "unit": "ms", "lowerIsBetter": True, "kind": "link", "get": lambda s: s.get("firstPaint")},
    {"id": "launch-window", "label": "Cold launch → window on screen", "unit": "ms", "lowerIsBetter": True, "kind": "restore", "get": lambda s: s.get("window")},
    {"id": "launch-restore", "label": "Cold launch → restored tab painted", "unit": "ms", "lowerIsBetter": True, "kind": "restore", "get": lambda s: s.get("firstPaint")},
    {"id": "newtab", "label": "New tab → first paint", "unit": "ms", "lowerIsBetter": True, "kind": "session", "get": lambda s: median(s.get("newTab") or [])},
    {"id": "switch", "label": "Tab switch → shown", "unit": "ms", "lowerIsBetter": True, "kind": "session", "get": lambda s: median(s.get("tabSwitch") or [])},
    {"id": "newwindow", "label": "New window → first paint", "unit": "ms", "lowerIsBetter": True, "kind": "session", "get": lambda s: median(s.get("newWindow") or [])},
    {"id": "memory-1", "label": "Memory, 1 tab", "unit": "MB", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "memory", "tabs1", "totalMB")},
    {"id": "memory-10", "label": "Memory, 10 tabs", "unit": "MB", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "memory", "tabs10", "totalMB")},
    {"id": "memory-20", "label": "Memory, 20 tabs", "unit": "MB", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "memory", "tabs20", "totalMB")},
    {"id": "memory-closed", "label": "Memory, back to 1 tab after 20", "unit": "MB", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "memory", "closed", "totalMB")},
    {"id": "idle-cpu-1", "label": "Idle CPU, 1 tab", "unit": "%", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs1", "total", "cpu")},
    {"id": "idle-cpu-20", "label": "Idle CPU, 20 tabs", "unit": "%", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs20", "total", "cpu")},
    {"id": "idle-wakeups-1", "label": "Idle wakeups, 1 tab", "unit": "/s", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs1", "total", "wakeups")},
    {"id": "idle-wakeups-20", "label": "Idle wakeups, 20 tabs", "unit": "/s", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs20", "total", "wakeups")},
    {"id": "idle-cpu-1-steady", "label": "Idle CPU, 1 tab, settled (2 min after load)", "unit": "%", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs1steady", "total", "cpu")},
    {"id": "idle-cpu-20-steady", "label": "Idle CPU, 20 tabs, settled (2 min after the last load)", "unit": "%", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs20steady", "total", "cpu")},
    {"id": "idle-wakeups-1-steady", "label": "Idle wakeups, 1 tab, settled", "unit": "/s", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs1steady", "total", "wakeups")},
    {"id": "idle-wakeups-20-steady", "label": "Idle wakeups, 20 tabs, settled", "unit": "/s", "lowerIsBetter": True, "kind": "session", "get": lambda s: dig(s, "idle", "tabs20steady", "total", "wakeups")},
    {"id": "download", "label": "Download (DMG)", "unit": "MB", "lowerIsBetter": True, "kind": "size", "context": True, "get": lambda s: per_million(s.get("download"))},
    {"id": "on-disk", "label": "App on disk", "unit": "MB", "lowerIsBetter": True, "kind": "size", "context": True, "get": lambda s: per_million(s.get("bundle"))},
]

DIA_RESTORE_NOTE = "Dia opens on its start view at launch; the restored tab stays hidden until it's chosen, so it never paints on its own"
NEW_WINDOW_NOTE = "Target.createTarget with newWindow opens a tab in the current window, not a new window"


def build_rows(samples, names, browsers) -> list[dict]:
    ok = [s for s in samples if s.get("ok")]
    rows = []
    for row in ROWS:
        per = {}
        for n in names:
            xs = [v for v in (row["get"](s) for s in ok if s.get("browser") == n and s.get("kind") == row["kind"]) if finite(v)]
            per[n] = {**browsers[n], "median": round_figure(median(xs)), "min": round_figure(min(xs)) if xs else None,
                      "max": round_figure(max(xs)) if xs else None, "n": len(xs)}
        rows.append({"id": row["id"], "label": row["label"], "unit": row["unit"], "lowerIsBetter": row["lowerIsBetter"],
                     **({"context": True} if row.get("context") else {}), "browsers": per})
    rows = [r for r in rows if any(b["n"] for b in r["browsers"].values())]
    for row in rows:
        ranked = sorted(((n, b) for n, b in row["browsers"].items() if b["median"] is not None),
                        key=lambda e: e[1]["median"], reverse=not row["lowerIsBetter"])
        row["best"] = ranked[0][0] if ranked else None
        if row["id"] == "launch-restore":
            for n, b in row["browsers"].items():
                if b["median"] is None and base_of(n) == "dia":
                    b["note"] = DIA_RESTORE_NOTE
        if row["id"] == "newwindow":
            for b in row["browsers"].values():
                if b["median"] is None:
                    b["note"] = NEW_WINDOW_NOTE
    return rows


def build_report(samples, names, browsers, machine_info, date) -> dict:
    return {"date": date, "machine": machine_info, "harness": HARNESS, "browsers": browsers,
            "rows": build_rows(samples, names, browsers), "method": METHOD, "notes": list(NOTES)}


def key_of(name: str, names) -> str:
    if name != base_of(name) and sum(1 for m in names if base_of(m) == base_of(name)) == 1:
        return base_of(name)
    return name


def bench_json(result: dict, names) -> dict:
    data = {**result, "rows": [r for r in result["rows"] if not r.get("context")]}
    data["browsers"] = {key_of(n, names): b for n, b in data["browsers"].items()}
    for row in data["rows"]:
        row["browsers"] = {key_of(n, names): b for n, b in row["browsers"].items()}
        row["best"] = row["best"] and key_of(row["best"], names)
    return data


def table(result: dict, names) -> str:
    head = "| Row | " + " | ".join(f"{result['browsers'][n]['name']} {result['browsers'][n]['version']}" for n in names) + " |"
    lines = [head, "|---|" + "|".join("---" for _ in names) + "|"]
    for row in result["rows"]:
        cells = []
        for n in names:
            b = row["browsers"][n]
            if b["median"] is None:
                cells.append("–")
            elif b["n"] > 1:
                cells.append(f"{js_text(b['median'])} {row['unit']} ({js_text(b['min'])}–{js_text(b['max'])}, n={b['n']})")
            else:
                cells.append(f"{js_text(b['median'])} {row['unit']}")
        lines.append(f"| {row['label']} | {' | '.join(cells)} |")
    return "\n".join(lines)


def map_kinds(kinds, f) -> dict:
    return {k: f(v) for k, v in (kinds or {}).items()}


BREAKDOWN = [
    ("memory at 20 tabs, MB", lambda s: map_kinds(dig(s, "memory", "tabs20", "kinds"), lambda v: v)),
    ("memory at 1 tab, MB", lambda s: map_kinds(dig(s, "memory", "tabs1", "kinds"), lambda v: v)),
    ("idle wakeups/s at 1 tab", lambda s: map_kinds(dig(s, "idle", "tabs1", "kinds"), lambda v: v["wakeups"])),
    ("idle wakeups/s at 20 tabs", lambda s: map_kinds(dig(s, "idle", "tabs20", "kinds"), lambda v: v["wakeups"])),
    ("idle CPU % at 20 tabs", lambda s: map_kinds(dig(s, "idle", "tabs20", "kinds"), lambda v: v["cpu"])),
]


def breakdown(samples, names) -> str:
    sessions = [s for s in samples if s.get("ok") and s.get("kind") == "session"]
    lines = []
    for label, get in BREAKDOWN:
        lines.append(f"\n{label} (median per process kind)")
        for n in names:
            per = [get(s) for s in sessions if s.get("browser") == n]
            kinds = sorted({k for p in per for k in p})
            figures = (f"{k} {js_text(round_figure(median([0 if p.get(k) is None else p[k] for p in per])))}" for k in kinds)
            lines.append(f"  {n}: {', '.join(figures)}")
    return "\n".join(lines)


def launchd_jobs() -> list[str]:
    return [line.split("\t")[-1] for line in run_text(["launchctl", "list"]).split("\n") if LAUNCHD_VENDORS.search(line)]


def pids_using(directory: str) -> list[int]:
    found = [int(p) for p in run_text(["pgrep", "-f", directory]).split("\n") if p.strip().isdigit()]
    return list(dict.fromkeys(p for p in found if p and p != os.getpid()))


class PerflabLock:
    def __init__(self, path: str = LOCK_FILE):
        self.path = path
        self.handle = None

    @property
    def held(self) -> bool:
        return self.handle is not None

    def take(self, wait_secs: float = 120) -> bool:
        if self.handle:
            return True
        handle = open(self.path, "a+")
        end = time.monotonic() + wait_secs
        while True:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= end:
                    handle.close()
                    return False
                time.sleep(1)
        handle.seek(0)
        handle.truncate()
        handle.write(f"xbench-{os.getpid()}\n")
        handle.flush()
        self.handle = handle
        return True

    def release(self):
        if self.handle:
            fcntl.flock(self.handle, fcntl.LOCK_UN)
            self.handle.close()
            self.handle = None


class Gate:
    def __init__(self, harness):
        self.h = harness
        self.state = None
        self.on = harness.opt.gate != "off"
        self.input = 0
        self.proc = None

    def start(self):
        if self.proc:
            return
        self.proc = subprocess.Popen([str(self.h.probe_bin()), "watch"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True)
        threading.Thread(target=self.read, args=(self.proc,), daemon=True).start()

    def read(self, proc):
        for line in proc.stdout:
            try:
                s = json.loads(line)
                if self.state and s["hid"] < self.state["hid"] and s["hid"] < 1:
                    self.input += 1
                self.state = s
            except (ValueError, KeyError, TypeError):
                pass

    def stop(self):
        if self.proc:
            self.proc.kill()
            self.proc.wait()
            self.proc = None

    def away(self, s=MISSING) -> bool:
        s = self.state if s is MISSING else s
        if not s or s.get("asleep") or not finite(s.get("hid")):
            return False
        return s["hid"] >= 60 if s.get("locked") else s["hid"] >= self.h.opt.away

    def wait(self, deadline: float) -> bool:
        if not self.on:
            return True
        said = 0
        while now_ms() < deadline:
            if self.away():
                return True
            if now_ms() - said > 300_000:
                said = now_ms()
                state = self.state or {}
                hid = "?" if state.get("hid") is None else js_text(state["hid"])
                log(f"waiting for the owner to be away (input {hid} s ago, locked {js_text(state.get('locked', MISSING))})")
            sleep_ms(5000)
        return False

    def cond(self) -> dict:
        s = self.state or {}
        cond = {"locked": bool(s.get("locked")), "asleep": bool(s.get("asleep"))}
        if "hid" in s:
            cond["hid"] = s["hid"]
        cond["load"] = js_round(os.getloadavg()[0] * 10) / 10
        return cond


class PrefsGuard:
    def __init__(self, out: str, domain: str):
        self.domain = domain
        self.dir = os.path.join(out, "prefs-guard")
        self.file = os.path.join(self.dir, f"{domain}.plist")
        self.existed = False

    def save(self):
        os.makedirs(self.dir, mode=0o700, exist_ok=True)
        self.existed = os.path.exists(os.path.join(os.environ["HOME"], "Library/Preferences", f"{self.domain}.plist"))
        if self.existed:
            rm_rf(self.file)
            subprocess.run(["sh", "-c", 'umask 077 && exec defaults export "$0" "$1"', self.domain, self.file], check=True)
            first = os.path.join(self.dir, f"{self.domain}.first.plist")
            if not os.path.exists(first):
                subprocess.run(["cp", "-p", self.file, first], check=True)
        return self

    def restore(self):
        subprocess.run(["defaults", "delete", self.domain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.existed:
            subprocess.run(["defaults", "import", self.domain, self.file], check=True)
        rm_rf(self.file)


class Instance:
    def __init__(self, harness, name: str, directory: str):
        self.h = harness
        self.name = name
        self.b = spec(name)
        self.app = harness.bundle_of(name)
        self.info = app_info(self.app)
        self.dir = directory
        self.home = os.path.join(directory, "home")
        self.cdp = Cdp(harness.port)
        self.input_at_start = harness.gate.input
        self.pid = None
        self.front = 0
        self.t0 = 0
        self.focus_seen = False
        self.prefs = None
        self.window_proc = None
        self.window_at = None

    def watched(self):
        gate = self.h.gate
        if gate.on and gate.input > self.input_at_start:
            raise Aborted("the owner came back")
        if self.pid and gate.state and gate.state.get("front") == self.pid:
            if not self.h.opt.allow_focus:
                raise Fatal(f"{self.name} took focus (it became the frontmost app): stopping")
            self.focus_seen = True
        if self.pid and not self.alive():
            raise RuntimeError(f"{self.name} (pid {self.pid}) died")

    def alive(self) -> bool:
        try:
            os.kill(self.pid, 0)
            return True
        except (OSError, TypeError):
            return False

    def env(self) -> dict:
        return launch_env(base_of(self.name), self.home, self.h.port, self.h.base(), extra_env(self.h.opt.env, self.name), self.app)

    def args(self) -> list[str]:
        return launch_args(base_of(self.name), self.home, self.h.port, self.h.window, bool(self.b.get("restore_switch")))

    def own_pids(self) -> list[dict]:
        rows = process_rows()
        prefix = os.path.dirname(os.path.dirname(self.info["exe"]))
        short = prefix[len("/private"):] if prefix.startswith("/private") else prefix
        children = {}
        for r in rows:
            children.setdefault(r["ppid"], []).append(r["pid"])
        pids = set()

        def walk(pid):
            stack = [pid]
            while stack:
                for child in children.get(stack.pop(), []):
                    if child not in pids:
                        pids.add(child)
                        stack.append(child)

        if self.pid and any(r["pid"] == self.pid for r in rows):
            pids.add(self.pid)
            walk(self.pid)
        for r in rows:
            if r["command"].startswith(prefix + "/") or r["command"].startswith(short + "/"):
                pids.add(r["pid"])
                walk(r["pid"])
        by_pid = {r["pid"]: r for r in rows}
        owned = []
        for r in rows:
            if r["pid"] not in pids:
                continue
            in_tree = r["pid"] == self.pid or self.is_descendant(by_pid, r["pid"])
            owned.append({"pid": r["pid"], "ppid": r["ppid"], "inTree": in_tree,
                          "kind": kind_of(r["command"]) if in_tree else f"outside:{outside_name(r['command'])}"})
        return owned

    def is_descendant(self, by_pid: dict, pid: int) -> bool:
        p = by_pid.get(pid)
        for _ in range(4096):
            if not p or p["ppid"] <= 1:
                return False
            if p["ppid"] == self.pid:
                return True
            p = by_pid.get(p["ppid"])
        return False

    def usage(self) -> list[dict]:
        procs = self.own_pids()
        by_pid = {p["pid"]: p for p in procs}
        lines = [l for l in self.h.parcperf("rusage", *(str(p["pid"]) for p in procs))["out"].split("\n") if l] if procs else []
        used = []
        for line in lines:
            u = json.loads(line)
            p = by_pid.get(u.get("pid")) or {}
            used.append({**u, "kind": p.get("kind"), "inTree": p.get("inTree")})
        return used

    def footprint(self) -> dict:
        kinds = {}
        total = 0
        snap = self.usage()
        for u in snap:
            kinds[u["kind"]] = kinds.get(u["kind"], 0) + u["footprint"] / 1048576
            total += u["footprint"] / 1048576
        renderers = [{"pid": u["pid"], "kind": u["kind"], "mb": js_round((u["footprint"] / 1048576) * 10) / 10}
                     for u in snap if u["kind"] in ("renderer", "extension")]
        return {"totalMB": total, "processes": len(snap), "outsideTree": len([u for u in snap if not u["inTree"]]),
                "kinds": kinds, "renderers": renderers}

    def check_copy(self):
        if self.b.get("read_only") and os.access(os.path.join(self.app, "Contents"), os.W_OK):
            raise RuntimeError(f"{self.name}'s copy is writable: chmod -R a-w it so it can't update itself")
        if self.b.get("installed_id") and self.info["id"] == self.b["installed_id"]:
            raise RuntimeError(f"{self.name}'s copy has the installed app's bundle identifier {self.info['id']}: "
                               f"make it with prepare-parc so links and AppleScript can't reach the installed {self.b['name']}")

    def main_pattern(self) -> str:
        return f"^{js_regex_escape(self.info['exe'])}( |$)"

    def launch(self, url):
        if subprocess.run(["pgrep", "-f", self.main_pattern()], capture_output=True).returncode == 0:
            raise RuntimeError(f"a {self.name} instance is still running")
        if self.cdp.get("/json/version") is not None:
            raise RuntimeError(f"port {self.h.port} is already taken")
        self.check_copy()
        if self.b.get("guard_prefs"):
            self.prefs = PrefsGuard(self.h.out, self.info["id"]).save()
        argv = open_argv(self.app, self.env(), url, self.args())
        self.front = self.h.probe("state")["front"]
        self.t0 = now_ms()
        subprocess.run(argv, check=True)
        for _ in range(1000):
            if self.pid:
                break
            found = subprocess.run(["pgrep", "-f", self.main_pattern()], capture_output=True, text=True)
            if found.returncode == 0:
                self.pid = int(found.stdout.strip().split("\n")[0])
            else:
                sleep_ms(5)
        if not self.pid:
            raise RuntimeError(f"{self.name} didn't start")
        self.h.live.add(self)
        self.window_proc = subprocess.Popen([str(self.h.parcperf_bin()), "waitwindow", str(self.pid), "60"],
                                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        return self

    def wait_window(self) -> float:
        if self.window_at is None:
            said, _ = self.window_proc.communicate()
            self.window_at = math.nan if self.window_proc.returncode != 0 else float(said.strip() or 0)
        return self.window_at

    def window_shown(self) -> bool:
        return self.window_proc is not None and self.window_proc.poll() == 0

    def await_page_target(self, timeout: float = 30_000):
        end = now_ms() + timeout
        while now_ms() < end:
            self.watched()
            if self.window_shown() and self.cdp.pages():
                return
            sleep_ms(100)
        raise RuntimeError(f"{self.name}: no window with a page target after {js_number(timeout / 1000)} s")

    def ready(self, timeout: float = 60_000) -> dict:
        end = now_ms() + timeout
        while now_ms() < end:
            self.watched()
            try:
                if self.cdp.browser():
                    return self.cdp.version
            except Exception:
                pass
            sleep_ms(50)
        raise RuntimeError(f"{self.name}: no CDP endpoint on {self.h.port}")

    def page(self, page_id: str, timeout: float = 30_000, accept=None):
        end = now_ms() + timeout
        while now_ms() < end:
            self.watched()
            found = self.cdp.page(page_id, min(1000, end - now_ms()), accept)
            if found:
                return found
        return None

    def hold(self, ms: float):
        end = now_ms() + ms
        while now_ms() < end:
            self.watched()
            sleep_ms(min(250, end - now_ms()))

    def focus_taken(self) -> int:
        now = self.h.probe("state")["front"]
        return now if now != self.front and any(p["pid"] == now for p in self.own_pids()) else 0

    def quit(self):
        def pids():
            return [p["pid"] for p in self.own_pids()]

        left = pids()
        if left:
            try:
                self.cdp.call("Browser.close")
            except Exception:
                if self.b.get("quit_tool") and self.pid:
                    self.h.parcperf("quit", str(self.pid))
            for sig, wait in ((signal.SIGTERM, 15_000), (signal.SIGKILL, 5000)):
                end = now_ms() + wait
                while now_ms() < end:
                    left = pids()
                    if not left:
                        break
                    sleep_ms(200)
                for p in left:
                    kill(p, sig)
        self.cdp.close()
        end = now_ms() + 10_000
        while now_ms() < end and self.cdp.get("/json/version") is not None:
            sleep_ms(200)
        if self.prefs:
            self.prefs.restore()
        self.h.live.discard(self)
        version = app_info(self.app)["version"]
        if version != self.info["version"]:
            raise Fatal(f"{self.name}'s copy changed version ({self.info['version']} → {version}): it updated itself")


class Harness:
    def __init__(self, opt):
        self.opt = opt
        self.out = os.path.abspath(opt.out)
        self.port = opt.port
        x, y = (number(v) for v in opt.window.split(",")[:2])
        self.window = (x, y, *WINDOW_SIZE)
        self.gate = Gate(self)
        self.server = None
        self.live = set()
        self.lock = PerflabLock()
        self.samples_file = os.path.join(self.out, "samples.jsonl")

    def probe_bin(self) -> Path:
        return tool("xbench_probe")

    def parcperf_bin(self) -> Path:
        return tool("parcperf")

    def probe(self, *args):
        text = subprocess.run([str(self.probe_bin()), *args], capture_output=True, text=True, timeout=20, check=True).stdout.strip()
        return json.loads(text or "null")

    def parcperf(self, *args) -> dict:
        try:
            done = subprocess.run([str(self.parcperf_bin()), *args], capture_output=True, text=True, timeout=120)
            return {"code": done.returncode, "out": (done.stdout or "").strip()}
        except subprocess.TimeoutExpired as e:
            out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
            return {"code": None, "out": out.strip()}

    def start_server(self):
        self.server = PageServer(self.opt.page_port)

    def close_server(self):
        if self.server:
            self.server.close()

    def base(self) -> str:
        return self.server.base

    def page_url(self, page_id: str) -> str:
        return self.server.url(page_id)

    def option_for(self, entries, name: str):
        return next((e[len(name) + 1:] for e in entries if e.startswith(f"{name}=")), None)

    def bundle_of(self, name: str) -> str:
        given = self.option_for(self.opt.app, name)
        app = os.path.abspath(given if given else os.path.join(self.opt.apps, name, os.path.basename(spec(name)["bundle"])))
        if os.path.realpath(app).startswith("/Applications/"):
            raise RuntimeError(f"{app} is in /Applications: run a copy")
        if not os.path.exists(app):
            raise RuntimeError(f"no {name} copy at {app}")
        return app

    def is_test_page(self, target: dict) -> bool:
        return str(target.get("url", "")).startswith(f"{self.base()}/static?")

    def own_targets(self, app) -> list[dict]:
        pages = app.cdp.pages()
        return [t for t in pages if self.is_test_page(t)] if app.b.get("test_targets_only") else pages

    def close_all_but_seed(self, app):
        for t in self.own_targets(app):
            if not str(t.get("url", "")).endswith("id=seed"):
                self.quiet_call(app, "Target.closeTarget", {"targetId": t["id"]})

    def first_target(self, app, page_id: str, timeout: float = 30_000) -> dict:
        end = now_ms() + timeout
        while True:
            try:
                return app.cdp.call("Target.createTarget", {"url": self.page_url(page_id)})
            except RuntimeError:
                if now_ms() >= end:
                    raise
                app.hold(250)

    def template_dir(self, name: str) -> str:
        return os.path.join(self.out, "templates", name)

    def read_samples(self) -> list[dict]:
        return read_samples(self.samples_file)

    def record(self, sample: dict):
        record(self.samples_file, sample)

    def plan(self, names) -> list[dict]:
        return plan(names, set(self.opt.rows.split(",")), self.opt.rounds, self.opt.launches)

    def prepare_home(self, name: str, directory: str):
        base_home = self.option_for(self.opt.base, name)
        if base_home:
            subprocess.run(["cp", "-Rc", os.path.abspath(base_home), os.path.join(directory, "home")], check=True)
        else:
            os.makedirs(os.path.join(directory, "home"), exist_ok=True)
        if is_ardia(name):
            os.makedirs(os.path.join(directory, "home/data"), exist_ok=True)
            Path(directory, "home/data/onboarding.json").write_text(stringify({"version": 1, "completedAt": 1}))

    def make_template(self, name: str):
        directory = self.template_dir(name)
        rm_rf(directory)
        os.makedirs(directory)
        self.prepare_home(name, directory)
        log(f"making {name}'s template profile")
        app = Instance(self, name, directory).launch(None)
        version = {}
        try:
            version = app.ready()
            app.hold(3000)
            if app.b.get("await_window"):
                app.await_page_target()
                self.first_target(app, "seed")
            else:
                app.cdp.call("Target.createTarget", {"url": self.page_url("seed")})
            if not app.page("seed", 30_000):
                raise RuntimeError(f"{name}: the template's page never painted")
            self.close_all_but_seed(app)
            app.hold(max(0, app.t0 + SETTLE_TEMPLATE_MS - now_ms()))
            left = [t.get("url") for t in app.cdp.pages()]
            made = {"made": iso(), **({"browser": version["Browser"]} if "Browser" in version else {}),
                    **({"userAgent": version["User-Agent"]} if "User-Agent" in version else {}), "pages": left, "info": app.info}
            Path(directory, "template.json").write_text(stringify(made, 2))
        finally:
            app.quit()
        if is_ardia(name):
            self.fix_ardia_session(os.path.join(directory, "home/data/session.json"))
        for chromium in chromium_dirs(base_of(name), os.path.join(directory, "home")):
            for f in ("SingletonLock", "SingletonSocket", "SingletonCookie"):
                rm_rf(os.path.join(chromium, f))
        log(f"{name} template: {js_text(version.get('Browser', MISSING))}")

    def fix_ardia_session(self, file: str):
        session = json.loads(Path(file).read_text())
        height = self.probe("screen")["h"]
        x, y, w, h = self.window
        blank = {t["id"] for t in session["tabs"] if not t.get("url")}
        seed = next((t for t in session["tabs"] if str(t.get("url") or "").endswith("id=seed")), None)
        if seed and self.opt.launch_tab == "on":
            profile = seed.get("profileId", MISSING)
            session["launchTab"] = {"id": seed["id"], "url": seed["url"],
                                    **({} if profile is MISSING else {"profile": "" if profile == "default" else profile})}
        if len(blank) < len(session["tabs"]):
            session["tabs"] = [t for t in session["tabs"] if t["id"] not in blank]
        for window in session.get("windows") or []:
            window["tabIds"] = [i for i in window["tabIds"] if any(t["id"] == i for t in session["tabs"])]
            if not window.get("kind"):
                window["frame"] = [x, height - y - h, w, h]
        Path(file).write_text(stringify(session))

    def run_dir(self, item: str) -> str:
        directory = os.path.join(self.out, "runs", item.replace("/", "-"))
        rm_rf(directory)
        os.makedirs(os.path.dirname(directory), exist_ok=True)
        subprocess.run(["cp", "-Rc", self.template_dir(item.split("/")[2]), directory], check=True)
        return directory

    def keep_logs(self, name: str, item: str, directory: str):
        for log_file in debug_logs(base_of(name), os.path.join(directory, "home")):
            if os.path.exists(log_file):
                os.makedirs(os.path.join(self.out, "logs"), exist_ok=True)
                subprocess.run(["cp", log_file, os.path.join(self.out, "logs", f"{item.replace('/', '-')}.chrome_debug.log")], check=True)
                return

    def remove_run_dir(self, directory: str):
        for sig in (signal.SIGTERM, signal.SIGKILL):
            for pid in pids_using(directory):
                kill(pid, sig)
            end = now_ms() + 3000
            while now_ms() < end and pids_using(directory):
                sleep_ms(200)
        for _ in range(10):
            try:
                rm_rf(directory)
                return
            except OSError as e:
                if e.errno not in (errno.ENOTEMPTY, errno.EBUSY, errno.EACCES, errno.EPERM):
                    raise
                subprocess.run(["chmod", "-R", "u+w", directory], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                sleep_ms(300)
        aside = os.path.join(self.out, "runs-aside", f"{os.path.basename(directory)}-{now_ms()}")
        os.makedirs(os.path.dirname(aside), exist_ok=True)
        os.rename(directory, aside)
        log(f"{directory} couldn't be removed after its browser quit; moved to {aside}")

    def launch_item(self, name: str, item: str, kind: str) -> dict:
        directory = self.run_dir(item)
        app = Instance(self, name, directory)
        link_id = item.replace("/", "-")
        try:
            app.launch(self.page_url(link_id) if kind == "link" else None)
            page = app.page(link_id if kind == "link" else "seed", 30_000 if kind == "link" else 15_000)
            window_at = app.wait_window()
            state = page["state"] if page else {}
            visible = next((v[0] for v in (state.get("vis") or []) if len(v) > 1 and v[1] == "visible"), None)
            r = {
                "window": window_at - app.t0,
                "firstPaint": num(state.get("fcp")) - app.t0,
                "firstFrame": num(state.get("frame")) - app.t0,
                "navigationStart": num(state.get("origin")) - app.t0,
                "visibleAt": num(visible) - app.t0,
                "viewport": [state.get("w"), state.get("h")] if page else None,
                "pages": len(app.cdp.pages()),
                "focusTaken": app.focus_taken() or bool(app.focus_seen),
            }
            app.hold(1500)
            return r
        finally:
            app.quit()
            self.keep_logs(name, item, directory)
            self.remove_run_dir(directory)

    def throttled(self, app):
        for t in self.own_targets(app):
            frames = app.cdp.evaluate(t, THROTTLE_PROBE)
            if finite(frames) and frames >= 0:
                return frames < 5
        return None

    def idle_window(self, app, secs: float) -> dict:
        a = app.usage()
        cover = self.probe("cover", str(app.pid))
        app.hold(secs * 1000)
        b = app.usage()
        return {**usage_delta(a, b), "cover": cover}

    def open_tab(self, app, page_id: str) -> dict:
        at = now_ms()
        target_id = app.cdp.call("Target.createTarget", {"url": self.page_url(page_id)})["targetId"]
        return {"targetId": target_id, "at": at, "page": app.page(page_id, 30_000)}

    def quiet_call(self, app, method: str, params: dict):
        try:
            return app.cdp.call(method, params)
        except Exception:
            return None

    def session_item(self, name: str, item: str) -> dict:
        directory = self.run_dir(item)
        app = Instance(self, name, directory)
        secs = self.opt.idle
        r = {"memory": {}, "idle": {}, "tabSwitch": [], "newTab": [], "newTabFrame": [], "newWindow": [], "newWindowOpened": [],
             "throttled": {"tabSwitch": 0, "newTab": 0}}
        try:
            app.launch(None)
            app.ready()
            seed = app.page("seed", 15_000)
            if not seed:
                target = app.cdp.find("seed")
                if target:
                    self.quiet_call(app, "Target.activateTarget", {"targetId": target["id"]})
                seed = app.page("seed", 30_000)
                r["seedShownByActivate"] = True
            if not seed:
                raise RuntimeError(f"{name}: the restored page never painted, even activated")
            r["focusTaken"] = app.focus_taken()
            seed_at = now_ms()
            app.hold(30_000)
            r["idle"]["tabs1"] = self.idle_window(app, secs)
            r["memory"]["tabs1"] = app.footprint()
            app.hold(max(0, seed_at + STEADY_MS - now_ms()))
            r["idle"]["tabs1steady"] = self.idle_window(app, secs)
            tabs = [self.open_tab(app, f"t{i}") for i in range(1, 10)]
            app.hold(10_000)
            r["memory"]["tabs10"] = app.footprint()
            tabs += [self.open_tab(app, f"t{i}") for i in range(10, 20)]
            loaded_at = now_ms()
            app.hold(15_000)
            r["memory"]["tabs20"] = app.footprint()
            r["idle"]["tabs20"] = self.idle_window(app, secs)
            app.hold(max(0, loaded_at + STEADY_MS - now_ms()))
            r["idle"]["tabs20steady"] = self.idle_window(app, secs)
            r["memory"]["tabs20steady"] = app.footprint()
            r["pagesAt20"] = len(app.cdp.pages())

            for k in range(16):
                index = (k * 7 + 3) % len(tabs)
                tab = tabs[index]
                page_id = f"t{index + 1}"
                target = app.cdp.find(page_id)
                before = len((app.cdp.state(target) or {}).get("shown") or [])
                hidden = self.throttled(app)
                at = now_ms()
                app.cdp.call("Target.activateTarget", {"targetId": tab["targetId"]})
                s = app.page(page_id, 5000, lambda st, before=before: len(st.get("shown") or []) > before)
                shown = s["state"]["shown"][-1] if s and s["state"].get("shown") else None
                if hidden:
                    r["throttled"]["tabSwitch"] += 1
                r["tabSwitch"].append(shown[1] - at if shown and not hidden else math.nan)
                app.hold(400)

            for k in range(5):
                hidden = self.throttled(app)
                t = self.open_tab(app, f"n{k}")
                if hidden:
                    r["throttled"]["newTab"] += 1
                state = t["page"]["state"] if t["page"] else {}
                r["newTab"].append(state["fcp"] - t["at"] if t["page"] and not hidden else math.nan)
                r["newTabFrame"].append(state["frame"] - t["at"] if state.get("frame") and not hidden else math.nan)
                app.hold(800)
                self.quiet_call(app, "Target.closeTarget", {"targetId": t["targetId"]})
                app.hold(400)

            main_window = (self.quiet_call(app, "Browser.getWindowForTarget", {"targetId": seed["target"]["id"]}) or {}).get("windowId")
            for k in range(3):
                at = now_ms()
                target_id = app.cdp.call("Target.createTarget", {"url": self.page_url(f"w{k}"), "newWindow": True})["targetId"]
                p = app.page(f"w{k}", 20_000)
                window = (self.quiet_call(app, "Browser.getWindowForTarget", {"targetId": target_id}) or {}).get("windowId")
                opened = bool(window) and window != main_window
                r["newWindowOpened"].append(opened)
                r["newWindow"].append(p["state"]["fcp"] - at if p and opened else math.nan)
                app.hold(1000)
                self.quiet_call(app, "Target.closeTarget", {"targetId": target_id})
                app.hold(1500)

            self.quiet_call(app, "Target.activateTarget", {"targetId": seed["target"]["id"]})
            self.close_all_but_seed(app)
            app.hold(30_000)
            r["memory"]["closed"] = app.footprint()
            r["focusTaken"] = r["focusTaken"] or bool(app.focus_seen)
            r["pagesClosed"] = len(app.cdp.pages())
        finally:
            app.quit()
            self.keep_logs(name, item, directory)
            self.remove_run_dir(directory)
        return r

    def size_item(self, name: str) -> dict:
        app = self.bundle_of(name)
        i = app_info(app)
        given = self.option_for(self.opt.dmg, name)
        local = str(REPO / f"dist/{i['version']}/Ardia-{i['version']}.dmg") if is_ardia(name) else None
        download_url = spec(name).get("download_url")
        source = given if given is not None else (local if local and os.path.exists(local) else (download_url(i) if download_url else None))
        download = math.nan
        if source and re.match(r"^https?:", source):
            head = run_text(["curl", "-sIL", "--max-time", "30", source])
            statuses = re.findall(r"^HTTP/[\d.]+ (\d+)", head, re.MULTILINE)
            lengths = re.findall(r"^content-length: *(\d+)", head, re.MULTILINE | re.IGNORECASE)
            if statuses and statuses[-1] == "200":
                download = int(lengths[-1]) if lengths else math.nan
        elif source and os.path.exists(source):
            download = os.stat(source).st_size
        return {"download": download, "bundle": du(app), **({"source": source} if source is not None else {}),
                "archs": run_text(["lipo", "-archs", i["exe"]], check=True).strip()}

    def run(self, names) -> int:
        deadline = now_ms() + self.opt.deadline * 60_000
        rows = set(self.opt.rows.split(","))
        os.makedirs(self.out, exist_ok=True)
        done = done_keys(self.read_samples())
        if "size" in rows:
            for n in names:
                if f"size/{n}" not in done:
                    self.record({"key": f"size/{n}", "kind": "size", "browser": n, "ok": True, "at": iso(), **self.size_item(n)})
        items = [i for i in self.plan(names) if i["key"] not in done]
        log(f"{len(items)} items to run ({len(done)} done)")
        self.gate.start()
        sleep_ms(500)
        locked = False
        try:
            for item in items:
                estimate = estimate_ms(item["kind"], self.opt.idle)
                if now_ms() + estimate > deadline:
                    log("deadline: stopping; run again to resume")
                    break
                waited = True
                while True:
                    waited = self.gate.wait(deadline - estimate)
                    if not waited:
                        break
                    locked = self.lock.take()
                    if not locked:
                        log("perflab is busy; waiting")
                        sleep_ms(30_000)
                        continue
                    if not os.path.exists(os.path.join(self.template_dir(item["browser"]), "template.json")):
                        try:
                            self.make_template(item["browser"])
                        except Fatal:
                            raise
                        except Exception as e:
                            log(f"template of {item['browser']} {'thrown away' if isinstance(e, Aborted) else 'failed'}: {e}")
                            if isinstance(e, Aborted):
                                continue
                            break
                    cond = self.gate.cond()
                    started = now_ms()
                    try:
                        if item["kind"] == "session":
                            data = self.session_item(item["browser"], item["key"])
                        else:
                            data = self.launch_item(item["browser"], item["key"], item["kind"])
                        sample = {**item, "ok": True, "at": iso(started), "cond": cond, "condAfter": self.gate.cond(), **data}
                        self.record(sample)
                        log(f"{item['key']}:", stringify(summary_line(sample)))
                        sleep_ms(3000)
                        break
                    except Fatal:
                        raise
                    except Exception as e:
                        aborted = isinstance(e, Aborted)
                        self.record({**item, "ok": False, "at": iso(started), ("aborted" if aborted else "failed"): str(e)})
                        log(f"{item['key']} {'thrown away' if aborted else 'failed (retried on the next run)'}: {e}")
                        if not aborted:
                            break
                        if locked:
                            self.lock.release()
                            locked = False
                if not waited:
                    log("deadline while waiting for the owner to be away; run again to resume")
                    break
                if self.gate.on and not self.gate.away() and locked:
                    self.lock.release()
                    locked = False
        finally:
            self.gate.stop()
            if locked:
                self.lock.release()
        left = len(pending(names, self.read_samples(), set(self.opt.rows.split(",")), self.opt.rounds, self.opt.launches))
        log(f"{left} items left" if left else "all items done")
        return left

    def prefs_stamp(self, name: str):
        file = os.path.join(os.environ["HOME"], "Library/Preferences", f"{app_info(self.bundle_of(name))['id']}.plist")
        return os.stat(file).st_mtime_ns if os.path.exists(file) else None

    def check(self, names):
        deadline = now_ms() + self.opt.deadline * 60_000
        self.gate.start()
        sleep_ms(500)
        try:
            for name in names:
                if not self.gate.wait(deadline):
                    raise RuntimeError("the owner wasn't away before the deadline")
                directory = os.path.join(self.out, "check", name)
                rm_rf(directory)
                os.makedirs(directory)
                self.prepare_home(name, directory)
                app = Instance(self, name, directory)
                report = {"name": name, "version": app.info["version"], "window": self.opt.window}
                prefs = self.prefs_stamp(name)
                jobs_before = launchd_jobs()
                try:
                    app.launch(self.page_url("check"))
                    report["cdp"] = app.ready().get("Browser")
                    p = app.page("check", 30_000)
                    report["linkPaint"] = js_round(p["state"]["fcp"] - app.t0) if p else None
                    report["viewport"] = [p["state"].get("w"), p["state"].get("h")] if p else None
                    report["windowAt"] = app.wait_window() - app.t0
                    app.hold(4000)
                    listed = app.cdp.get("/json/list")
                    report["targets"] = [f"{js_text(t.get('type', MISSING))} {str(t.get('url', ''))[:90]}" for t in (listed if isinstance(listed, list) else [])]
                    t = self.open_tab(app, "check-nt")
                    report["newTab"] = js_round(t["page"]["state"]["fcp"] - t["at"]) if t["page"] else None
                    visibility = t["page"]["state"].get("visibility") if t["page"] else None
                    if visibility is None:
                        visibility = (app.cdp.state(app.cdp.find("check-nt")) or {}).get("visibility")
                    report["newTabVisibility"] = visibility
                    report["cover"] = self.probe("cover", str(app.pid))
                    report["focusTaken"] = app.focus_taken()
                    report["processes"] = [f"{p['kind']}{'' if p['inTree'] else ' (outside the tree)'}" for p in app.own_pids()]
                    report["uddUsed"] = profile_used(base_of(name), app.home)
                    library = os.path.join(app.home, "Library")
                    report["homeLibrary"] = sorted(os.listdir(library)) if os.path.exists(library) else []
                except Exception as e:
                    report["error"] = str(e)
                finally:
                    try:
                        app.quit()
                    except Exception as e:
                        report["quitError"] = str(e)
                    report["realPrefsWritten"] = self.prefs_stamp(name) != prefs
                    report["newLaunchdJobs"] = [j for j in launchd_jobs() if j not in jobs_before]
                print(stringify(report, 2), flush=True)
                rm_rf(directory)
                if re.search(r"took focus|updated itself", f"{js_text(report.get('error', MISSING))} {js_text(report.get('quitError', MISSING))}"):
                    reason = report["error"] if report.get("error") is not None else report.get("quitError")
                    raise RuntimeError(f"{name}: {reason}; stopping the check")
        finally:
            self.gate.stop()

    def report(self, names) -> dict:
        browsers = {}
        for n in names:
            template_file = os.path.join(self.template_dir(n), "template.json")
            template = json.loads(Path(template_file).read_text()) if os.path.exists(template_file) else None
            app = self.bundle_of(n)
            label = self.option_for(self.opt.version_label, n)
            browsers[n] = {"name": spec(n)["name"], "version": label if label is not None else app_info(app)["version"],
                           "chromium": chromium_of(app, template)}
            if n != base_of(n):
                browsers[n]["variant"] = ("background-only copy (LSBackgroundOnly, ad hoc signed)" if n.endswith("-bg")
                                          else n[len(base_of(n)) + 1:])
        return build_report(self.read_samples(), names, browsers, machine(), utc_date())

    def report_command(self, names) -> int:
        result = self.report(names)
        file = os.path.abspath(self.opt.json or os.path.join(self.out, "bench.json"))
        md = f"{table(result, names)}\n{breakdown(self.read_samples(), names)}\n"
        data = bench_json(result, names)
        written = data
        if self.opt.rivals_from:
            stored = json.loads(Path(self.opt.rivals_from).resolve().read_text())
            try:
                written = merge_rivals(data, stored, force=bool(self.opt.force))
            except RivalsRefused as e:
                log(str(e))
                return 65
            if written.get("forced"):
                log(f"merged with --force despite: {'; '.join(written['forced'])}")
            stored_macos = stored["machine"].get("macOS", MISSING) if isinstance(stored.get("machine"), dict) else MISSING
            if written["machine"].get("macOS") != stored_macos:
                log(f"note: macOS was {js_text(stored_macos)} for the stored rivals, {written['machine'].get('macOS')} now")
            for key, b in written["browsers"].items():
                kept = " (this run)" if key in data["browsers"] else " (kept)"
                log(f"{js_text(b.get('name', MISSING))} {js_text(b.get('version', MISSING))}: measured {js_text(b.get('measured', MISSING))}{kept}")
            installed = {}
            for k in written["browsers"]:
                if k in data["browsers"] or not spec(k):
                    continue
                app = os.path.join("/Applications", os.path.basename(spec(k)["bundle"]))
                if os.path.exists(os.path.join(app, "Contents/Info.plist")):
                    installed[k] = str(bundle_info(app).get("CFBundleShortVersionString", ""))
            warnings = rival_warnings(written, installed=installed)
            for w in warnings:
                log(f"full rerun due: {w}")
            if not warnings:
                log("stored rivals are current: no full rerun due")
        Path(file).write_text(stringify(written, 2) + "\n")
        if self.opt.md:
            Path(self.opt.md).resolve().write_text(md)
        else:
            print(md)
        log(f"wrote {file}")
        return 0

    def signin(self, names):
        for name in names:
            home = self.option_for(self.opt.base, name)
            if not home:
                raise RuntimeError(f"signin needs --base {name}=<home>")
            os.makedirs(home, exist_ok=True)
            app = Instance(self, name, os.path.dirname(os.path.abspath(home)))
            app.home = os.path.abspath(home)
            app.launch(None)
            log(f"{name} is open (pid {app.pid}) on {app.home}: sign in, then quit it (⌘Q)")
            deadline = now_ms() + self.opt.deadline * 60_000
            while app.alive() and now_ms() < deadline:
                sleep_ms(1000)
            app.quit()
            log(f"{name} quit; its HOME is {app.home}")

    def prepare_background_only(self, names):
        for name in names:
            if spec(name).get("hidden") or name != base_of(name):
                raise RuntimeError(f"prepare-bg takes a competitor's own name, not {name}")
            src = self.bundle_of(name)
            dst = os.path.join(self.opt.apps, f"{name}-bg", os.path.basename(src))
            rm_rf(os.path.dirname(dst))
            os.makedirs(os.path.dirname(dst))
            subprocess.run(["cp", "-Rc", src, dst], check=True)
            plist = os.path.join(dst, "Contents/Info.plist")
            subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Delete :LSBackgroundOnly", plist], capture_output=True)
            subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Add :LSBackgroundOnly bool true", plist], capture_output=True, check=True)
            subprocess.run(["xattr", "-rd", "com.apple.FinderInfo", dst], capture_output=True)
            entitlements = self.entitlements_without_restricted(src, os.path.dirname(dst))
            subprocess.run(["codesign", "--force", "--sign", "-", *entitlements, "--preserve-metadata=identifier", dst], check=True)
            log(f"{name}-bg: {dst} ({self.signature_summary(dst)}, version {app_info(dst)['version']})")

    def entitlements_without_restricted(self, src: str, directory: str) -> list[str]:
        granted = run_text(["codesign", "-d", "--entitlements", "-", "--xml", src], check=True)
        kept = ENTITLEMENT.sub(lambda m: "" if RESTRICTED.fullmatch(m.group(1)) else m.group(0), granted)
        if not kept.strip():
            return []
        entitlements = os.path.join(directory, "entitlements.plist")
        Path(entitlements).write_text(kept)
        return ["--entitlements", entitlements]

    def signature_summary(self, app: str) -> str:
        verify = subprocess.run(["codesign", "--verify", "--strict", app], capture_output=True, text=True)
        flags = re.search(r"flags=\S+", subprocess.run(["codesign", "-dvv", app], capture_output=True, text=True).stderr)
        signature = "signature valid" if verify.returncode == 0 else f"signature: {verify.stderr.strip()}"
        return f"{signature}, {flags.group(0) if flags else 'undefined'}"

    def prepare_parc(self, names):
        for name in names:
            copy_id = spec(name).get("copy_id")
            if not copy_id:
                raise RuntimeError(f"prepare-parc makes Parc's copy, not {name}'s")
            given = self.option_for(self.opt.app, name)
            if not given:
                raise RuntimeError(f"prepare-parc needs --app {name}=<the Parc.app to copy>")
            src = os.path.abspath(given)
            if not os.path.exists(os.path.join(src, "Contents/Info.plist")):
                raise RuntimeError(f"no app at {src}")
            dst = os.path.join(os.path.abspath(self.opt.apps), name, os.path.basename(spec(name)["bundle"]))
            folder = os.path.realpath(os.path.dirname(dst))
            real_src = os.path.realpath(src)
            if folder.startswith("/Applications/"):
                raise RuntimeError(f"{dst} is in /Applications: keep copies under --apps")
            if real_src == folder or real_src.startswith(folder + "/") or folder.startswith(real_src + "/"):
                raise RuntimeError(f"{src} and {os.path.dirname(dst)} overlap: copy from another folder")
            rm_rf(os.path.dirname(dst))
            os.makedirs(os.path.dirname(dst))
            subprocess.run(["cp", "-Rc", src, dst], check=True)
            subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {copy_id}",
                            os.path.join(dst, "Contents/Info.plist")], capture_output=True, check=True)
            subprocess.run(["xattr", "-rd", "com.apple.FinderInfo", dst], capture_output=True)
            entitlements = self.entitlements_without_restricted(src, os.path.dirname(dst))
            subprocess.run(["codesign", "--force", "--sign", "-", *entitlements, dst], check=True)
            log(f"{name}: {dst} ({self.signature_summary(dst)}, {app_info(dst)['id']}, version {app_info(dst)['version']})")

    def clean(self, names):
        for n in names:
            try:
                app = self.bundle_of(n)
            except Exception:
                continue
            exe = app_info(app)["exe"]
            found = run_text(["pgrep", "-f", f"^{js_regex_escape(exe)}( |$)"])
            for pid in (p for p in found.strip().split("\n") if p):
                log(f"quitting a leftover {n} (pid {pid})")
                kill(int(pid), signal.SIGTERM)
            subprocess.run([LSREGISTER, "-u", app], capture_output=True)
        rm_rf(os.path.join(self.out, "runs"))
        rm_rf(os.path.join(self.out, "check"))
        for n in names:
            if not spec(n).get("guard_prefs"):
                continue
            guard = PrefsGuard(self.out, app_info(self.bundle_of(n))["id"])
            if os.path.exists(guard.file):
                log(f"restoring {guard.domain} from the snapshot a stopped run left")
                guard.existed = True
                guard.restore()

    def on_signal(self, signum, frame):
        for app in list(self.live):
            for p in app.own_pids():
                kill(p["pid"], signal.SIGTERM)
            if app.prefs:
                time.sleep(3)
            try:
                if app.prefs:
                    app.prefs.restore()
            except Exception:
                pass
        self.gate.stop()
        if self.lock.held:
            self.lock.release()
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(130)


def number(text: str):
    value = float(text)
    return int(value) if value.is_integer() else value


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="xbench.py", description=DESCRIPTION, epilog=EPILOG, allow_abbrev=False,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", nargs="?", help="run, check, report, clean, signin, prepare-bg or prepare-parc")
    p.add_argument("extra", nargs="*", help=argparse.SUPPRESS)
    p.add_argument("--out", default=str(DEFAULT_ROOT / "out"), help="results, templates and runs (default build/perf/xbench/out)")
    p.add_argument("--browsers", default="parc,ardia,helium,chrome",
                   help="parc,ardia,dia,helium,chrome (default: parc,ardia,helium,chrome, in that order); <name>-bg runs prepare-bg's copy")
    p.add_argument("--apps", default=str(DEFAULT_ROOT / "apps"),
                   help="where the copies live (default build/perf/xbench/apps): parc/Parc.app, ardia/Ardia.app, dia/Dia.app, "
                        "helium/Helium.app, chrome/Google Chrome.app. Never a bundle in /Applications")
    p.add_argument("--app", action="append", default=[], metavar="NAME=PATH",
                   help="repeatable: another copy for one browser (Parc built from main, say); prepare-parc: the Parc.app to clone")
    p.add_argument("--rounds", type=int, default=3, help="rounds (default 3). A round is every launch, then every session, browser by browser")
    p.add_argument("--launches", type=int, default=2, help="launches of each kind per browser per round (default 2)")
    p.add_argument("--rows", default="link,restore,session,size", help="link,restore,session,size (default all). session = idle, memory, newtab, switch, newwindow")
    p.add_argument("--idle", type=float, default=60, help="each idle window, in seconds (default 60)")
    p.add_argument("--port", type=int, default=9461, help="the instances' CDP port (default 9461). One instance runs at a time")
    p.add_argument("--page-port", type=int, default=9462, help="the test pages' server port (default 9462); templates restore pages from it, so keep it fixed")
    p.add_argument("--deadline", type=float, default=100, help="stop starting items after this many minutes (default 100); run again to resume")
    p.add_argument("--gate", default="away",
                   help="away (default): every item waits until the owner is away (screen locked with no input for 60 s, or no keyboard, "
                        "mouse or trackpad input for --away secs) and is thrown away, its browser quit at once, the moment input comes. "
                        "off: run now, with the Mac in use (competitors' windows show on screen)")
    p.add_argument("--away", type=float, default=600, help="idle seconds that count as away (default 600)")
    p.add_argument("--window", default="40,80", help="the windows' top-left corner (default 40,80)")
    p.add_argument("--env", action="append", default=[], metavar="NAME=K=V",
                   help="repeatable: extra environment for one browser's instances (ardia=ARDIA_INSTANCE=chromiumSwitches=…)")
    p.add_argument("--launch-tab", default="on",
                   help="Ardia's template session names its active tab as launchTab, as a user's session written with that kill switch on does (default on)")
    p.add_argument("--allow-focus", action="store_true",
                   help="record a browser making itself the active app instead of stopping (only for an A/B the owner agreed to, run while they're away)")
    p.add_argument("--base", action="append", default=[], metavar="NAME=HOME",
                   help="repeatable: the template starts from a copy of this HOME (a signed-in profile) instead of an empty one")
    p.add_argument("--dmg", action="append", default=[], metavar="NAME=FILE|URL", help="repeatable: the download whose size the size row reports")
    p.add_argument("--version-label", action="append", default=[], metavar="NAME=TEXT", help="report: show this instead of the app's version (a dev build, say)")
    p.add_argument("--json", help="report: where the results JSON goes (default <out>/bench.json)")
    p.add_argument("--md", help="report: where the markdown table goes (default stdout)")
    p.add_argument("--rivals-from", metavar="FILE",
                   help="report: measure only some browsers and take every other browser's rows from this bench.json, each keeping its own "
                        "version and measured date. Refuses when the machine's model or chip, or the harness revision, differ from the "
                        "file's; warns (never fails) when a kept rival is over 60 days old or the copy in /Applications is a new major or minor version")
    p.add_argument("--force", action="store_true", help="report: merge with --rivals-from despite a different machine or harness (recorded as forced)")
    return p


def main(argv=None) -> int:
    cli = parser()
    opt = cli.parse_args(argv)
    if not opt.command:
        cli.print_help()
        return 64
    names = [n for n in opt.browsers.split(",") if n]
    for n in names:
        if not spec(n):
            raise SystemExit(f"unknown browser {n}")
    harness = Harness(opt)
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, harness.on_signal)
    command = opt.command
    if command == "report":
        return harness.report_command(names)
    if command == "prepare-bg":
        harness.prepare_background_only(names)
        return 0
    if command == "prepare-parc":
        harness.prepare_parc(names)
        return 0
    if command == "clean":
        harness.clean(names)
        return 0
    if command in ("signin", "run", "check"):
        harness.start_server()
        try:
            if command == "signin":
                harness.signin(names)
                return 0
            if command == "run":
                return 75 if harness.run(names) else 0
            harness.check(names)
            return 0
        finally:
            harness.close_server()
    print(f"unknown command {command}", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main())
