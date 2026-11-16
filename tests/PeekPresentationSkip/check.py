#!/usr/bin/env python3
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/PeekController.swift").read_text()
skip = (root / "Sources/ParcCore/PeekPresentationSkip.swift").read_text()
window = browser_window_controller_source(root / "Sources/ParcApp")

assert "enum PeekPresentationSkip" in skip, "PeekPresentationSkip helper missing"
assert "static func shouldSkip(previous: String?, next: String) -> Bool" in skip, \
    "shouldSkip predicate missing"
assert "previous == next" in skip, "shouldSkip must be a true identical-fingerprint no-op"
assert "static func fingerprint(" in skip, "fingerprint helper missing"
for needle in (
    "title:",
    "url:",
    "loading:",
    "canGoBack:",
    "canGoForward:",
    "closePending:",
    "canExpand:",
    "canSplit:",
    "capture:",
    "crash:",
    "favicon:",
):
    assert needle in skip, f"fingerprint no longer includes {needle}"

assert "private var lastPresentedFingerprint: String?" in controller, \
    "missing last-applied Peek presentation fingerprint"
assert "private func publishPresentationIfChanged()" in controller, \
    "missing publishPresentationIfChanged gate"
assert "private func presentationFingerprint()" in controller, \
    "missing live presentationFingerprint builder"
assert "PeekPresentationSkip.shouldSkip(previous: lastPresentedFingerprint, next: fingerprint)" in controller, \
    "refresh must gate on PeekPresentationSkip.shouldSkip"
assert "if refresh() { onUpdate?() }" in controller, \
    "publish must notify only after a changed refresh"

for selector in (
    "func browserView(_ view: PCBrowserView, didChangeTitle title: String)",
    "func browserView(_ view: PCBrowserView, didChangeURL url: URL)",
    "func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool)",
    "func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?)",
    "func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?)",
    "func browserViewDidChangeFavicon(_ view: PCBrowserView)",
):
    match = re.search(re.escape(selector) + r" \{(?P<body>[^}]*)\}", controller)
    assert match, f"{selector} missing"
    body = match.group("body")
    assert "publishPresentationIfChanged()" in body, \
        f"{selector} must publish through the fingerprint gate"
    assert "refresh(); onUpdate?()" not in body, \
        f"{selector} must not unconditionally refresh+onUpdate"
    assert body.count("onUpdate?()") == 0, \
        f"{selector} must not call onUpdate outside publishPresentationIfChanged"

assert "self?.view.confirmationTitle = nil\n                self?.onUpdate?()" in controller, \
    "dismissal confirmation expiry must still call onUpdate ungated"
assert re.search(
    r'view\.confirmationTitle = mediaConfirmation \? "Hang up" : "Close"\n'
    r'.*?\n\s+onUpdate\?\(\)',
    controller, re.S), \
    "dismissal confirmation request must still call onUpdate ungated"
assert "if closePending { onUpdate?() }" in controller, \
    "dismissal-start owners must still observe closePending via onUpdate"

assert "func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) { refresh(); focus() }" in controller, \
    "renderer-crash focus must still refresh then focus"

peek_wire = re.search(
    r"peek\.onUpdate = \{ \[weak self\] in self\?\.(?P<fn>\w+)\(\) \}",
    window)
assert peek_wire, "peek.onUpdate wiring missing"
assert peek_wire.group("fn") in ("refreshLivePageChromeOrRender", "updateNavigation"), \
    "peek.onUpdate must still reach live chrome / navigation"
assert "PeekPresentationSkip" not in window, \
    "Peek skip must not move onto the BrowserWindowController onUpdate bridge"

print("PeekPresentationSkip check passed")
