#!/usr/bin/env python3
"""FairPlay GPU-sandbox check. Builds the probe (probe_main.cc, probe_helper.mm,
probe_player.mm) with the FairPlay core (clang only, like
scripts/test-fairplay-core.sh) and plays FairPlay media inside Chromium's real
GPU seatbelt profile: the pinned common.sb + gpu.sb, with and without the
FairPlay rules that Engine/ParcHost/integration/fairplay-media.patch adds.

  with rules     every scenario must PASS
  without rules  h264 must FAIL (or time out) with a sandbox denial naming a
                 service the FairPlay rules grant
  --ablate       also replaces each FairPlay grant on its own with one that
                 never matches, and reports which ones playback needs
  --ablate-groups  the same for each commented group of grants

A grant counts as NEEDED only when playback fails without it and the kernel
logged a denial naming it; any other failure is reported as inconclusive.
Needs network access (the unsandboxed helper downloads media and licenses).
Writes only to a temporary directory and the media cache.
"""
import argparse
import datetime
import importlib.util
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[3]
DEFAULT_SOURCE = pathlib.Path(
    "/Users/josh/Documents/Codex/2026-10-23/re/work/engine-source/chromium/src")
PROBE_NAME = "fpsbprobe"
SCENARIOS = ["h264", "hevc", "dolby-vision", "eac3", "ac3", "audio-switch", "video-switch", "hls-ts", "hls-fmp4"]
CHROMIUM_MEDIA = ["glass-blowing2-dolby-vision-profile-5-frag.mp4",
                  "bear-eac3-only-frag.mp4", "bear-ac3-only-frag.mp4",
                  "bear-640x360-v_frag.mp4", "bear-320x240-v_frag-hevc.mp4"]
OUTCOMES = {0: "PASS", 1: "FAIL", 2: "SETUP-FAIL", 3: "INCONCLUSIVE", 4: "TIMEOUT"}
GRANT = re.compile(r'\((global-name|xpc-service-name|iokit-user-client-class|subpath|literal|path)'
                   r'\s+"([^"]*)"\)')
NEEDED = {"com.apple.lskdd", "com.apple.lskdd.xpc", "com.apple.audio.audiohald",
          "com.apple.coremedia.routingcontext.xpc", "AppleAVDUserClient",
          "IOMobileFramebufferUserClient", "/System/Library/Components/CoreAudio.component"}
NEVER = {"global-name": "org.parc.ablated", "xpc-service-name": "org.parc.ablated",
         "iokit-user-client-class": "ParcAblatedUserClient", "subpath": "/nonexistent/parc-ablated",
         "literal": "/nonexistent/parc-ablated", "path": "/nonexistent/parc-ablated"}


def pinned(source, rev, path, binary=False):
    out = subprocess.run(["git", "-C", str(source), "show", f"{rev}:{path}"],
                         check=True, capture_output=True).stdout
    return out if binary else out.decode()


def patched_gpu_sb(source, rev):
    spec = importlib.util.spec_from_file_location("engine_source", REPO / "scripts/engine-source.py")
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    patch = (REPO / "Engine/ParcHost/integration/fairplay-media.patch").read_text()
    sections = re.split(r"(?m)^(?=--- a/)", patch)
    section = next(s for s in sections if s.startswith("--- a/sandbox/policy/mac/gpu.sb\n"))
    original = pinned(source, rev, "sandbox/policy/mac/gpu.sb").encode()
    return engine.apply_context_patch(section, {"sandbox/policy/mac/gpu.sb": original})[
        "sandbox/policy/mac/gpu.sb"].decode()


def compile_all(output):
    core = REPO / "Engine/ParcNative/fairplay"
    tests = REPO / "tests/FairPlay"
    probe = tests / "sandbox"
    flags = ["-std=c++20", "-Wall", "-Wextra", "-Werror", "-mmacosx-version-min=13.0",
             "-I", str(core), "-I", str(tests), "-I", str(probe)]
    objects = {}
    jobs = [(core / "fairplay_bitstream.cc", []), (core / "fairplay_hls_timeline.cc", []),
            (tests / "fmp4_parser.cc", []),
            (probe / "probe_main.cc", []), (probe / "probe_helper.mm", ["-fobjc-arc"]),
            (probe / "probe_player.mm", ["-fobjc-arc", "-fvisibility=hidden"])]
    jobs += [(core / f"{n}.mm", ["-fobjc-arc"]) for n in
             ("fairplay_init_data", "fairplay_key_session", "fairplay_renderer", "fairplay_hls_player",
              "fairplay_hls_player_layer", "fairplay_hls_frame_stats", "fairplay_hls_keys")]
    for source, extra in jobs:
        obj = output / (source.stem + ".o")
        subprocess.run(["xcrun", "clang++", *flags, *extra, "-c", str(source), "-o", str(obj)],
                       check=True)
        objects[source.stem] = str(obj)

    def link(name, names, extra):
        subprocess.run(["xcrun", "clang++", *[objects[n] for n in names], *extra, "-o",
                        str(output / name)], check=True)

    link(PROBE_NAME, ["probe_main", "fmp4_parser", "fairplay_bitstream"], [])
    link("fpsbhelper", ["probe_helper"], ["-framework", "Foundation"])
    frameworks = []
    for f in ("Foundation", "AVFoundation", "AudioToolbox", "CoreAudio", "CoreGraphics", "CoreMedia", "QuartzCore", "VideoToolbox"):
        frameworks += ["-framework", f]
    link("libfpsbplayer.dylib", ["probe_player", "fmp4_parser", "fairplay_bitstream", "fairplay_init_data",
                                 "fairplay_key_session", "fairplay_renderer", "fairplay_hls_player",
                                 "fairplay_hls_player_layer", "fairplay_hls_timeline", "fairplay_hls_frame_stats", "fairplay_hls_keys"],
         ["-dynamiclib", *frameworks])
    libraries = subprocess.run(["otool", "-L", str(output / PROBE_NAME)], check=True,
                               capture_output=True, text=True).stdout.splitlines()[1:]
    if any(".framework/" in line for line in libraries):
        raise SystemExit(f"{PROBE_NAME} links a framework:\n" + "\n".join(libraries))
    return output / PROBE_NAME


def denials(pid, since):
    deadline = time.time() + 10
    lines = []
    time.sleep(1)
    while time.time() < deadline:
        out = subprocess.run(
            ["/usr/bin/log", "show", "--style", "compact", "--start", since, "--predicate",
             f'eventMessage CONTAINS "({pid})" AND eventMessage CONTAINS "deny"'],
            capture_output=True, text=True).stdout
        lines = [l for l in out.splitlines() if f"({pid})" in l and "deny" in l]
        if any("network-outbound" not in l for l in lines):
            break
        time.sleep(1)
    found = []
    for line in lines:
        m = re.search(r"deny\(\d+\) (\S+)(?: (.*))?$", line)
        if m:
            item = f"{m.group(1)} {m.group(2) or ''}".strip()
            if item not in found:
                found.append(item)
    return found


def names_denial(item, name):
    if name.startswith("/"):
        return name in item
    return name in re.split(r"[\s()]+", item)


def run(binary, profile_text, label, scenario, args, workdir):
    profile = workdir / f"{label}.sb"
    profile.write_text(profile_text)
    since = (datetime.datetime.now() - datetime.timedelta(seconds=2)).strftime("%Y-%m-%d %H:%M:%S")
    cmd = [str(binary), "--profile", str(profile), "--scenario", scenario, "--cache", args.cache,
           "--media-dir", str(workdir / "media"), "--play-seconds", str(args.play_seconds),
           "--timeout", str(args.timeout), "--setup-timeout", str(args.setup_timeout),
           "--log", str(workdir / "probe.log")]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=args.setup_timeout + args.timeout + 30)
        out, code = proc.stdout, proc.returncode
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        code = None
    pid = next((m.group(1) for m in re.finditer(r"^pid (\d+) ", out, re.M)), None)
    result = next((l for l in out.splitlines() if l.startswith("RESULT ")), None)
    outcome = result.split()[1] if result else ("TIMEOUT" if code is None else OUTCOMES.get(code, "FAIL"))
    result = result or f"RESULT {outcome} (no result line, exit {code})"
    deny = denials(pid, since) if pid else []
    return outcome, result, deny, out


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=pathlib.Path,
                        default=pathlib.Path(os.environ.get("PARC_PINNED_CHROMIUM", DEFAULT_SOURCE)))
    parser.add_argument("--cache", default=os.environ.get("PARC_FAIRPLAY_CACHE",
                                                          str(pathlib.Path(tempfile.gettempdir()) / "parc-fairplay-cache")))
    parser.add_argument("--scenarios", default=",".join(SCENARIOS))
    parser.add_argument("--play-seconds", type=float, default=5)
    parser.add_argument("--timeout", type=float, default=60, help="playback budget once sandboxed")
    parser.add_argument("--setup-timeout", type=float, default=180, help="download budget before the sandbox")
    parser.add_argument("--ablate", action="store_true")
    parser.add_argument("--ablate-groups", action="store_true")
    parser.add_argument("--ablate-scenario", default="h264")
    parser.add_argument("--rules", type=pathlib.Path,
                        help="file of rules used instead of the patch's FairPlay additions")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    lock = (REPO / "Engine/source-lock.json").read_text()
    rev = re.search(r'"chromium":\s*{[^}]*"commit":\s*"([0-9a-f]{40})"', lock, re.S).group(1)

    common = pinned(args.source, rev, "sandbox/policy/mac/common.sb")
    gpu = pinned(args.source, rev, "sandbox/policy/mac/gpu.sb")
    patched = patched_gpu_sb(args.source, rev)
    if not patched.startswith(gpu):
        raise SystemExit("FairPlay gpu.sb additions are not a pure append")
    added = args.rules.read_text() if args.rules else patched[len(gpu):]
    lines = added.splitlines(keepends=True)
    grants = [i for i, l in enumerate(lines) if GRANT.search(l)]
    all_names = [m.group(2) for l in lines for m in GRANT.finditer(l)]
    scenarios = [s for s in args.scenarios.split(",") if s]

    with tempfile.TemporaryDirectory(prefix="parc-fairplay-sandbox.") as tmp:
        workdir = pathlib.Path(tmp)
        (workdir / "media").mkdir()
        for name in CHROMIUM_MEDIA:
            (workdir / "media" / name).write_bytes(pinned(args.source, rev, f"media/test/data/{name}", True))
        binary = compile_all(workdir)
        failures = []

        def show(ok, label, result, deny, out, keys=None):
            print(f"{'ok  ' if ok else 'FAIL'} {label}: {result}")
            for item in deny:
                if keys is None or any(k in item for k in keys):
                    print(f"       denied: {item}")
            if not ok or args.verbose:
                print("\n".join("       | " + l for l in out.splitlines()[-25:]))
            if not ok:
                failures.append(label)

        for scenario in scenarios:
            outcome, result, deny, out = run(binary, common + gpu + added, f"with-{scenario}", scenario,
                                             args, workdir)
            show(outcome == "PASS", f"{scenario}: GPU profile + FairPlay rules plays", result, deny, out)

        if "h264" in scenarios:
            outcome, result, deny, out = run(binary, common + gpu, "without-h264", "h264", args, workdir)
            named = [d for d in deny if any(names_denial(d, n) for n in NEEDED)]
            ok = outcome in ("FAIL", "TIMEOUT") and bool(named)
            show(ok, "h264: GPU profile without FairPlay rules fails on a needed FairPlay service", result, deny,
                 out)

        def ablate(label, removed):
            variant = list(lines)
            names = []
            for i in removed:
                names += [m.group(2) for m in GRANT.finditer(lines[i])]
                variant[i] = GRANT.sub(lambda m: f'({m.group(1)} "{NEVER[m.group(1)]}")', lines[i])
            assert len(variant) == len(lines) and "".join(variant).count("(") == added.count("(")
            outcome, result, deny, out = run(binary, common + gpu + "".join(variant), label,
                                             args.ablate_scenario, args, workdir)
            hits = [d for d in deny if any(names_denial(d, n) for n in names)]
            if outcome == "PASS":
                verdict = "not seen"
            elif outcome in ("FAIL", "TIMEOUT") and hits:
                verdict = "NEEDED  "
            else:
                verdict = "unclear "
            print(f"  {verdict} {', '.join(names)}" + ("" if outcome == "PASS" else f"   [{result}]"))
            for item in hits:
                print(f"           denied: {item}")
            if verdict == "unclear ":
                print("           (failed without a denial naming it, or before playback; rerun)")

        if args.ablate:
            print(f"ablation of {len(grants)} FairPlay grants, one at a time ({args.ablate_scenario}):")
            for i in grants:
                ablate(f"ablate-{i}", [i])
        if args.ablate_groups:
            groups, current = [], None
            for i, l in enumerate(lines):
                if l.strip().startswith(";"):
                    if current is None or current:
                        current = []
                        groups.append(current)
                elif i in grants and current is not None:
                    current.append(i)
            groups = [g for g in groups if g]
            print(f"ablation of {len(groups)} FairPlay grant groups ({args.ablate_scenario}):")
            for n, group in enumerate(groups):
                ablate(f"ablate-group-{n}", group)

        print("PASS" if not failures else f"FAIL: {', '.join(failures)}")
        return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
