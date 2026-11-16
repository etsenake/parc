#!/usr/bin/env python3
"""Load Parc's error pages and warning skin in a windowless WebKit view and check them."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import fixtures
import pages

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def js_click(selector):
    return f"document.querySelector({json.dumps(selector)}).click()"


def note(name, expression):
    return f"window.__extra = Object.assign(window.__extra || {{}}, {{{json.dumps(name)}: {expression}}})"


ENTER = "document.body.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', bubbles: true}))"
SPACE = "document.body.dispatchEvent(new KeyboardEvent('keydown', {key: ' ', code: 'Space', bubbles: true}))"
FOCUS = "window.dispatchEvent(new Event('focus'))"
FRAMES = ("window.__t = performance.now() + 1000; window.__frames = [];"
          " window.requestAnimationFrame = (f) => window.__frames.push(f); window.cancelAnimationFrame = () => {};")
ADVANCE = ("for (let i = 0; i < 40; i++) { const f = window.__frames.shift(); if (!f) break;"
           " window.__t += 50; f(window.__t); }")
BYPASS = ("for (const c of atob('dGhpc2lzdW5zYWZl')) { const e = new KeyboardEvent('keypress', {key: c, bubbles: true});"
          " Object.defineProperty(e, 'keyCode', {get: () => c.charCodeAt(0)}); document.dispatchEvent(e); }")


def text(selector):
    return f"(document.querySelector({json.dumps(selector)}) || {{}}).textContent || ''"


def shown(selector):
    return (f"(() => {{ const e = document.querySelector({json.dumps(selector)});"
            " return !!e && getComputedStyle(e).display !== 'none' && !e.hidden; })()")


def step(js, wait=None):
    return {"js": js, "wait": wait}


def calls(report, owner, name):
    return sum(1 for call in report.get("calls", []) if call[0] == owner and call[1] == name)


NET_JOBS = [
    ("refused", {}, [step(note("heading", text("#heading"))), step(js_click("#details-button")),
                     step(note("detailsOpen", shown("#details"))), step(js_click("#details a")),
                     step(note("stillOpen", shown("#details"))), step(js_click("#primary")), step(ENTER)],
     lambda r: [r["extra"]["heading"] == "This page didn’t make it", r["extra"]["detailsOpen"], r["extra"]["stillOpen"],
                calls(r, "net", "detailsButtonClick") == 1, calls(r, "net", "reloadButtonClick") == 2,
                "refused to connect" in r["text"], "ERR_CONNECTION_REFUSED" in r["text"]]),
    ("reset", {}, [], lambda r: ["dropped halfway" in r["text"]]),
    ("empty", {}, [], lambda r: ["studio.example.com sent nothing back" in r["text"]]),
    ("offline", {}, [step(note("hint", shown("#hint"))), step(js_click("#primary")), step(FRAMES), step(SPACE),
                     step("initializeEasterEggHighScore(7)"), step(note("status", text("#status"))),
                     step(SPACE), step(ADVANCE), step(note("after", text("#status"))),
                     step("window.dispatchEvent(new Event('online'))"), step(note("summary", text("#summary")))],
     lambda r: [r["extra"]["hint"], calls(r, "net", "reloadButtonClick") == 1, calls(r, "net", "trackEasterEgg") == 1,
                "best 7" in r["extra"]["status"], r["extra"]["after"] != r["extra"]["status"],
                r["extra"]["summary"] == "Back online. Reloading…", "You’re offline" in r["text"]]),
    ("offline-quiet", {}, [step(SPACE), step(note("status", shown("#status"))), step(note("hint", shown("#hint")))],
     lambda r: [calls(r, "net", "trackEasterEgg") == 0, not r["extra"]["status"], not r["extra"]["hint"]]),
    ("dino", {}, [step(note("buttons", shown("#primary"))), step(SPACE), step(note("status", shown("#status")))],
     lambda r: [r["title"] == "parc://dino/", "Two plugs, one game" in r["text"], not r["extra"]["buttons"],
                calls(r, "net", "trackEasterEgg") == 1, r["extra"]["status"]]),
    ("dns-started", {}, [step(note("before", text("#code"))),
                         step(f"updateForDnsProbe({json.dumps(fixtures.NET['dns'])})"), step(note("after", text("#code")))],
     lambda r: [r["extra"]["before"] == "DNS_PROBE_STARTED", r["extra"]["after"] == "DNS_PROBE_FINISHED_NXDOMAIN",
                "We can’t find exmaple.com" in r["text"]]),
    ("timed-out", {}, [], lambda r: ["That took too long" in r["text"], "slow.example.org didn’t answer" in r["text"]]),
    ("redirects", {}, [], lambda r: ["going in circles" in r["text"]]),
    ("not-found-404", {"history": True}, [step(note("primary", text("#primary"))), step(js_click("#primary")),
                                          step(js_click("#secondary"))],
     lambda r: [r["extra"]["primary"] == "Go back", r["backs"] == 1, calls(r, "net", "reloadButtonClick") == 1,
                "Nothing lives here" in r["text"], "HTTP ERROR 404" in r["text"]]),
    ("server-500", {}, [], lambda r: ["api.example.com is having a moment" in r["text"]]),
    ("file-missing", {}, [], lambda r: ["Parc can’t open this file" in r["text"]]),
    ("extension", {"history": True}, [step(note("primary", text("#primary"))), step(note("secondary", text("#secondary"))),
                                      step(js_click("#primary")), step(js_click("#secondary"))],
     lambda r: [r["extra"]["primary"] == "Go back", r["extra"]["secondary"] == "Try again", r["backs"] == 1,
                calls(r, "net", "reloadButtonClick") == 1, "An extension blocked this page" in r["text"]]),
    ("extension", {"name": "extension-new-tab"}, [step(note("primary", text("#primary"))), step(note("secondary", shown("#secondary")))],
     lambda r: [r["extra"]["primary"] == "Try again", not r["extra"]["secondary"]]),
    ("admin", {"history": True}, [step(js_click("#details-button")), step(note("details", text("#details")))],
     lambda r: ["parc://policy" in r["extra"]["details"], "Your organization blocked this site" in r["text"]]),
    ("framed", {"subframe": True}, [step(note("frame", shown("#frame-error")))],
     lambda r: [r["extra"]["frame"], "maps.example.com won’t show up here" in r["text"]]),
    ("resubmit", {}, [step(note("primary", shown("#primary")))],
     lambda r: [not r["extra"]["primary"], "Send that again?" in r["text"]]),
    ("cache-read", {}, [step(note("heading", text("#heading")))],
     lambda r: [r["extra"]["heading"] == "This site can’t be loaded from the cache"]),
    ("bad-address", {}, [], lambda r: [r["title"] == "parc://nope/", "parc://nope/" in r["text"]]),
    ("secure-failed", {}, [], lambda r: ["couldn’t connect securely" in r["text"]]),
    ("unknown-code", {}, [step(note("heading", text("#heading")))],
     lambda r: [r["extra"]["heading"] == "This page isn’t working", "cdn.example.com sent an invalid response." in r["text"]]),
]

INTERSTITIAL_JOBS = [
    ("ssl", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))), step(ENTER),
                 step(note("label", text("#details-button"))), step(js_click("#details-button")),
                 step(note("details", shown("#details"))), step(note("openLabel", text("#details-button"))),
                 step(note("expanded", "document.querySelector('#details-button').getAttribute('aria-expanded')")),
                 step(js_click("#learn-more-link")), step(js_click("#proceed-link")),
                 step(js_click("#error-code")), step(note("debug", shown("#error-debugging-info"))), step(BYPASS),
                 step(note("theme", "document.querySelector('meta[name=theme-color]').content"))],
     lambda r: [r["extra"]["heading"] == "This connection isn’t private", r["extra"]["primary"] == "Go back",
                "Parc can’t confirm this is really bank.example.com" in r["text"], calls(r, "cert", "dontProceed") == 1,
                r["extra"]["details"], calls(r, "cert", "showMoreSection") == 1, calls(r, "cert", "openHelpCenter") == 1,
                calls(r, "cert", "proceed") == 2, r["extra"]["debug"], r["title"] == "Privacy error",
                r["extra"]["theme"] == "#FFFCEC", r["extra"]["label"] == "Details",
                r["extra"]["openLabel"] == "Hide details", r["extra"]["expanded"] == "true"]),
    ("ssl", {"name": "warning-ssl-toggle"}, [step(js_click("#details-button")), step(js_click("#details-button")),
                                              step(note("label", text("#details-button"))),
                                              step(note("expanded", "document.querySelector('#details-button').getAttribute('aria-expanded')")),
                                              step(note("details", shown("#details")))],
     lambda r: [r["extra"]["label"] == "Details", r["extra"]["expanded"] == "false", not r["extra"]["details"],
                calls(r, "cert", "showMoreSection") == 1]),
    ("ssl-hsts", {}, [step(note("primary", text("#primary-button"))), step(js_click("#primary-button")),
                      step(note("proceed", "!!document.querySelector('#proceed-link')"))],
     lambda r: [r["extra"]["primary"] == "Try again", calls(r, "cert", "reload") == 1, not r["extra"]["proceed"]]),
    ("bad-clock", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))),
                       step(js_click("#primary-button")), step(js_click("#details-button")), step(note("details", text("#details")))],
     lambda r: [r["extra"]["heading"] == "Your Mac’s clock is off", r["extra"]["primary"] == "Open Date & Time",
                calls(r, "cert", "openDateSettings") == 1, "Monday, November 16, 2026" in r["extra"]["details"],
                "safely connect to bank.example.com" in r["text"]]),
    ("mitm", {}, [step(note("primary", shown("#primary-button"))), step(ENTER), step(BYPASS), step(note("heading", text("h1"))),
                  step(js_click("#details-button")), step(note("details", text("#details")))],
     lambda r: [not r["extra"]["primary"], [c for c in r["calls"] if c[1] != "showMoreSection"] == [],
                r["extra"]["heading"] == "Software on your Mac is blocking secure connections",
                "Example Shield" in r["extra"]["details"]]),
    ("blocked-interception", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))),
                                  step(js_click("#details-button")), step(js_click("#proceed-link"))],
     lambda r: [r["extra"]["heading"] == "This connection is being monitored", r["extra"]["primary"] == "Back to safety",
                calls(r, "cert", "dontProceed") == 0, calls(r, "cert", "proceed") == 1]),
    ("safe-browsing", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))),
                           step(note("theme", "document.querySelector('meta[name=theme-color]').content")),
                           step(js_click("#primary-button")), step(js_click("#details-button")),
                           step(js_click("#diagnostic-link")), step(js_click("#report-error-link")),
                           step(js_click("#proceed-link")), step(js_click("#opt-in-checkbox")),
                           step(js_click("#whitepaper-link"))],
     lambda r: [r["extra"]["heading"] == "This site is dangerous", r["extra"]["primary"] == "Go back to safety",
                r["extra"]["theme"] == "#B71E2C", calls(r, "cert", "dontProceed") == 1,
                calls(r, "cert", "showMoreSection") == 1, calls(r, "cert", "openDiagnostic") == 1,
                calls(r, "cert", "reportPhishingError") == 1, calls(r, "cert", "proceed") == 1,
                calls(r, "cert", "doReport") == 1, calls(r, "cert", "openWhitepaper") == 1,
                "pretending to be another site" in r["text"]]),
    ("malware", {}, [step(note("final", shown("#final-paragraph")))],
     lambda r: [not r["extra"]["final"], "harmful software" in r["text"]]),
    ("billing", {}, [step(note("heading", text("h1"))), step(note("proceed", text("#proceed-button"))), step(FOCUS),
                     step(js_click("#proceed-button")), step(note("early", "0"), 0.7),
                     step(js_click("#proceed-button")), step(js_click("#primary-button"))],
     lambda r: [r["extra"]["heading"] == "This page may try to charge you", r["extra"]["proceed"] == "Continue anyway",
                calls(r, "cert", "proceed") == 1, calls(r, "cert", "dontProceed") == 1]),
    ("lookalike", {}, [step(note("heading", text("h1"))), step(note("proceed", text("#proceed-button"))),
                       step(js_click("#dont-proceed-link")), step(FOCUS, 0.7), step(js_click("#proceed-button"))],
     lambda r: [r["extra"]["heading"] == "Did you mean example.com?", r["extra"]["proceed"] == "Visit this site anyway",
                "looks a lot like example.com" in r["text"], calls(r, "cert", "dontProceed") == 1,
                calls(r, "cert", "proceed") == 1]),
    ("lookalike-fake", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))),
                            step(js_click("#primary-button"))],
     lambda r: [r["extra"]["heading"] == "This site may be fake", r["extra"]["primary"] == "Go back to safety",
                calls(r, "cert", "dontProceed") == 1]),
    ("https-only", {}, [step(note("heading", text("h1"))), step(js_click("#primary-button")), step(js_click("#learn-more-link")),
                        step(FOCUS, 0.7), step(js_click("#proceed-button"))],
     lambda r: [r["extra"]["heading"] == "The connection to legacy.example.com is not secure",
                "Anyone on your network could see or change" in r["text"], "does not support HTTPS" in r["text"], calls(r, "cert", "openHelpCenter") == 1,
                calls(r, "cert", "dontProceed") == 1, calls(r, "cert", "proceed") == 1]),
    ("https-engagement", {}, [], lambda r: ["You usually connect to this site securely" in r["text"]]),
    ("insecure-form", {}, [step(note("heading", text("h1"))), step(FOCUS, 0.7), step(js_click("#proceed-button"))],
     lambda r: [r["extra"]["heading"] == "This form isn’t secure", calls(r, "cert", "proceed") == 1]),
    ("captive-portal", {}, [step(note("heading", text("h1"))), step(note("primary", text("#primary-button"))),
                            step(js_click("#primary-button"))],
     lambda r: [r["extra"]["heading"] == "This network wants you to sign in", r["extra"]["primary"] == "Open sign-in page",
                "Cafe Guest" in r["text"], calls(r, "cert", "openLogin") == 1]),
    ("enterprise-block", {}, [step(note("heading", text("h1"))), step(js_click("#primary-button"))],
     lambda r: [r["extra"]["heading"] == "Your organization blocked this site", calls(r, "cert", "dontProceed") == 1,
                "parc://management" in r["text"]]),
    ("enterprise-block-domain", {}, [step(js_click("#learn-more-link"))],
     lambda r: ["doesn’t allow games.example.com on this browser" in r["text"], calls(r, "cert", "openHelpCenter") == 1,
                "violates a policy" not in r["text"]]),
    ("enterprise-warn", {}, [step(note("heading", text("h1"))), step(FOCUS, 0.7), step(js_click("#proceed-button"))],
     lambda r: [r["extra"]["heading"] == "Your organization flagged this site", calls(r, "cert", "proceed") == 1,
                "thinks games.example.com might go against a policy" in r["text"]]),
]

SHEET = [("net", "refused"), ("net", "offline"), ("net", "dns"), ("net", "timed-out"), ("net", "extension"),
         ("net", "not-found-404"), ("net", "bad-address"), ("net", "unknown-code"),
         ("warning", "ssl"), ("warning", "safe-browsing"), ("warning", "https-only"), ("warning", "captive-portal"),
         ("warning", "bad-clock"), ("warning", "lookalike"), ("warning", "lookalike-fake"), ("warning", "https-engagement"),
         ("warning", "enterprise-block-domain"), ("warning", "enterprise-warn"), ("warning", "mitm"),
         ("warning", "blocked-interception"), ("warning", "billing")]


def build_jobs(out, pieces, sheet_dir):
    jobs, checks = [], {}
    for kind, specs in (("net", NET_JOBS), ("warning", INTERSTITIAL_JOBS)):
        for key, options, steps, check in specs:
            name = options.get("name", f"{kind}-{key}")
            data = fixtures.NET[key] if kind == "net" else fixtures.INTERSTITIALS[key]
            html = pages.net_error_page(pieces, data) if kind == "net" else pages.interstitial_page(pieces, data)
            path = out / f"{name}.html"
            path.write_text(html, encoding="utf-8")
            for dark in (False, True):
                job_name = f"{name}{'-dark' if dark else ''}"
                jobs.append({"name": job_name, "page": str(path), "dark": dark, "width": 900, "height": 600,
                             "history": options.get("history", False), "subframe": options.get("subframe", False),
                             "steps": steps if not dark else [], "snapshot": None})
                checks[job_name] = check if not dark else (lambda r: [])
    if sheet_dir:
        sheet_dir.mkdir(parents=True, exist_ok=True)
        for kind, key in SHEET:
            data = fixtures.NET[key] if kind == "net" else fixtures.INTERSTITIALS[key]
            html = pages.net_error_page(pieces, data) if kind == "net" else pages.interstitial_page(pieces, data)
            path = out / f"sheet-{kind}-{key}.html"
            path.write_text(html, encoding="utf-8")
            for dark in (False, True):
                job_name = f"sheet-{kind}-{key}{'-dark' if dark else ''}"
                jobs.append({"name": job_name, "page": str(path), "dark": dark, "width": 900, "height": 600,
                             "history": kind == "net", "subframe": False, "steps": [],
                             "snapshot": str(sheet_dir / f"{job_name}.png")})
                checks[job_name] = lambda r: []
    return jobs, checks


def compile_generated(out):
    include = out / "include/parc"
    include.mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / "Engine/ParcChromium/error_pages.h", include / "error_pages.h")
    subprocess.run(["xcrun", "clang++", "-std=c++20", "-Wall", "-Wextra", "-Werror", "-fsyntax-only",
                    "-I", str(out / "include"), str(out / "error_pages.cc")], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "build/tests/error-pages")
    parser.add_argument("--sheet-dir", type=Path)
    arguments = parser.parse_args()
    out = arguments.out
    out.mkdir(parents=True, exist_ok=True)
    pieces = pages.generate(out)
    compile_generated(out)
    raw = pages.interstitial_page(pieces, fixtures.INTERSTITIALS["ssl"], parc=False)
    if "This connection isn’t private" in raw:
        raise SystemExit("control page unexpectedly carries Parc's skin")
    jobs, checks = build_jobs(out, pieces, arguments.sheet_dir)
    (out / "jobs.json").write_text(json.dumps(jobs), encoding="utf-8")
    runner = out / "runner"
    subprocess.run(["xcrun", "swiftc", "-O", "-warnings-as-errors", str(HERE / "Runner.swift"), "-framework", "WebKit",
                    "-o", str(runner)], check=True)
    subprocess.run([str(runner), str(out / "jobs.json"), str(out / "results.json")], check=True)
    results = {item["name"]: item for item in json.loads((out / "results.json").read_text(encoding="utf-8"))}
    failures = []
    for job in jobs:
        report = results.get(job["name"])
        if not report or "error" in report:
            failures.append(f"{job['name']}: {report.get('error') if report else 'no result'}")
            continue
        problems = []
        if report["errors"]:
            problems.append(f"script errors {report['errors']}")
        if report["violations"]:
            problems.append(f"policy violations {report['violations']}")
        if "chrome://" in report["title"] or "chrome://" in report["text"]:
            problems.append("chrome:// is visible")
        if not report["text"].strip():
            problems.append("blank page")
        for index, ok in enumerate(checks[job["name"]](report)):
            if not ok:
                problems.append(f"check {index} failed")
        if problems:
            failures.append(f"{job['name']}: {'; '.join(problems)} | extra={report.get('extra')} calls={report.get('calls')}")
    print(f"{len(jobs) - len(failures)}/{len(jobs)} error page checks passed")
    for failure in failures:
        print("FAIL", failure)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
