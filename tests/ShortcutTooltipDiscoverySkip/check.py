#!/usr/bin/env python3
"""P2-Y behavior lock: BrowserWindowController's LiveShortcutToolTip.didChange
sink skips dismiss/copy-tooltip/site-control shortcut reapply when the
discovered fingerprint already matches what that window last applied. A first
apply or any string change still updates; multi-window correctness when content
changes is preserved by per-window last-applied comparison."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
skip = (root / "Sources/ParcCore/ShortcutTooltipDiscoverySkip.swift").read_text()

assert "enum ShortcutTooltipDiscoverySkip" in skip, "ShortcutTooltipDiscoverySkip helper missing"
assert "static func shouldSkip(previous: String?, next: String) -> Bool" in skip, \
    "shouldSkip predicate missing"
assert "previous == next" in skip, "shouldSkip must be a true identical-fingerprint no-op"
assert "static func fingerprint(" in skip, "fingerprint helper missing"
for needle in (
    "copyURLTooltip",
    "copyURLShortcut",
    "captureShortcut",
    "captureVisiblePageShortcut",
    "captureFullPageShortcut",
):
    assert needle in skip, f"fingerprint no longer includes {needle}"

assert "private var lastAppliedShortcutTooltipDiscovery: String?" in controller, \
    "missing per-window last-applied discovery fingerprint"

sink = re.search(
    r"shortcutDiscoverySubscription = NotificationCenter\.default\.publisher\(for: LiveShortcutToolTip\.didChange\)\.sink \{ \[weak self\] _ in(?P<body>.*?)\n        \}",
    controller, re.S)
assert sink, "LiveShortcutToolTip.didChange sink not found"
body = sink.group("body")
assert "shortcutTooltipDiscoveryFingerprint()" in body, \
    "sink must compute discovered content before skip"
assert "ShortcutTooltipDiscoverySkip.shouldSkip(" in body, \
    "sink must gate on ShortcutTooltipDiscoverySkip.shouldSkip"
assert "lastAppliedShortcutTooltipDiscovery" in body, \
    "sink must compare/store lastAppliedShortcutTooltipDiscovery"
assert "toasts.dismissShortcutToasts()" in body, \
    "real discovery changes must still retire a toast that shows a shortcut"
assert "popupChrome.updateCopyTooltip()" in body, \
    "real discovery changes must still update the copy tooltip"
assert "updateSiteControlCenterShortcuts()" in body, \
    "real discovery changes must still refresh site-control shortcuts"
assert body.index("shortcutTooltipDiscoveryFingerprint()") < body.index(
    "ShortcutTooltipDiscoverySkip.shouldSkip("), \
    "discovery fingerprint must be computed before the skip gate"
assert body.index("ShortcutTooltipDiscoverySkip.shouldSkip(") < body.index(
    "toasts.dismissShortcutToasts()"), \
    "identical fingerprint must skip before dismiss/reapply"
assert body.index("updateSiteControlCenterShortcuts()") < body.index(
    "lastAppliedShortcutTooltipDiscovery = discovery"), \
    "last-applied must be recorded only after a real apply"

fp = re.search(
    r"private func shortcutTooltipDiscoveryFingerprint\(\) -> String \{(?P<body>.*?)\n    \}\n",
    controller, re.S)
assert fp, "shortcutTooltipDiscoveryFingerprint helper missing"
fp_body = fp.group("body")
assert "LiveShortcutToolTip.text(\"Copy URL\", commandID: \"copyCurrentURL:\")" in fp_body, \
    "fingerprint must include the discovered Copy URL tooltip text"
for command in (
    "copyCurrentURL:",
    "capturePage:",
    "captureVisiblePage:",
    "captureFullPage:",
):
    assert f'activeShortcut(for: "{command}")' in fp_body, \
        f"fingerprint must still read activeShortcut for {command}"

# Unconditional sink apply must stay gone.
assert (
    "shortcutDiscoverySubscription = NotificationCenter.default.publisher(for: LiveShortcutToolTip.didChange).sink { [weak self] _ in\n"
    "            guard let self else { return }\n"
    "            self.toasts.dismissShortcutToasts()\n"
    "            self.popupChrome.updateCopyTooltip()\n"
    "            self.updateSiteControlCenterShortcuts()\n"
    "        }"
) not in controller, "ungated didChange sink apply must stay gone"

print("ShortcutTooltipDiscoverySkip: identical discovery skips; string changes still update")
