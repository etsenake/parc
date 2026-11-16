#!/usr/bin/env python3
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
controller = browser_window_controller_source(root / "Sources/ParcApp")

assert "captureIndicatorsDirty" not in controller, \
    "dirty-bit early out can miss capture start/stop; skip must compare live fingerprint"
assert "var lastCapturePresentationFingerprint: String?" in controller, \
    "missing last-applied capture presentation fingerprint"

fp = re.search(
    r"(?:private )?func capturePresentationFingerprint\(\s*_ presentations: \[UUID: CaptureIndicatorPresentation\]\s*\) -> String \{(?P<body>.*?)\n    \}\n\n    (?:private )?func refreshCaptureIndicators",
    controller, re.S)
assert fp, "capturePresentationFingerprint not found"
fp_body = fp.group("body")
for needle in (
    "p.camera",
    "p.microphone",
    "p.tab",
    "p.window",
    "p.display",
    "p.mirrored",
    "p.shared",
    "id.uuidString",
):
    assert needle in fp_body, f"fingerprint no longer includes {needle}"

refresh = re.search(
    r"(?:private )?func refreshCaptureIndicators\(\) \{(?P<body>.*?)\n    \}\n\n    (?:private )?func favoriteOverlayStates\(",
    controller, re.S)
assert refresh, "refreshCaptureIndicators not found"
body = refresh.group("body")
assert "browser.captureState" in body, \
    "refreshCaptureIndicators must still walk live browser captureState"
assert "peek.browser.captureState" in body, \
    "refreshCaptureIndicators must still walk peek captureState"
assert "view.captureState" in body, \
    "refreshCaptureIndicators must still walk easel page captureState"
assert "capturePresentationFingerprint(next)" in body, \
    "refresh must fingerprint the live next map before skip"
assert "if fingerprint == lastCapturePresentationFingerprint" in body, \
    "refreshCaptureIndicators no longer skips on identical presentation fingerprint"
assert "capturePresentations = next" in body, \
    "changed fingerprint must still replace the sidebar's capture map"
assert "captureIndicator" not in controller, "the window capture strip stays removed"
assert body.index("browser.captureState") < body.index(
    "if fingerprint == lastCapturePresentationFingerprint"), \
    "live walk must precede the identical-fingerprint skip"
assert body.index("capturePresentationFingerprint(next)") < body.index(
    "if fingerprint == lastCapturePresentationFingerprint"), \
    "fingerprint of next must precede the skip"
skip_idx = body.index("if fingerprint == lastCapturePresentationFingerprint")
assert "return" in body[skip_idx:body.index("capturePresentations = next")], \
    "identical fingerprint must return before the map is replaced"

live = re.search(
    r"(?:private )?func refreshLivePageChrome\(\) -> Bool \{(?P<body>.*?)\n    \}\n\n",
    controller, re.S)
assert live and "refreshCaptureIndicators()" in live.group("body"), \
    "refreshLivePageChrome must still invoke refreshCaptureIndicators"

assert "lastExtensionControlsSignature" in controller, \
    "extension-controls skip gate missing after rebase"
assert "lastPushedWebsiteTheme" in controller, \
    "website-theme skip gate missing after rebase"

print("CaptureIndicatorsSkip: live walk + fingerprint compare only; "
      "real start/stop/bit flips still update; sibling skip gates kept")
