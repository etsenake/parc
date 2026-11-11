#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()

assert "extensionControlsDirty" not in controller, \
    "dirty-bit early out can miss Changed→DeliverChanged; skip must compare live Snapshot"
assert "lastExtensionControlsSurfaceSignature" not in controller, \
    "surface-only skip without Snapshot is not a true visible-model no-op"

assert "private var lastExtensionControlsSignature: String?" in controller, \
    "missing last-applied extension-control signature"

sig = re.search(
    r"private func extensionControlsSignature\((?P<body>.*?)\n    \}\n\n    private func extensionControlsPopupAvailable",
    controller, re.S)
assert sig, "extensionControlsSignature not found"
sig_body = sig.group("body")
for needle in (
    "action.identifier",
    "action.name",
    "action.tooltip",
    "action.accessibilityLabel",
    "action.pinnedIndex",
    "action.isEnabled",
    "action.canChangePin",
    "actions.first?.generation",
    "sidebarOwns",
    "popupAvailable",
):
    assert needle in sig_body, f"signature no longer includes {needle}"

refresh = re.search(
    r"private func refreshExtensionControls\(\) \{(?P<body>.*?)\n    \}\n\n    private func preparePopupSiteControls",
    controller, re.S)
assert refresh, "refreshExtensionControls not found"
body = refresh.group("body")
assert "binding.extensionActions(for: page)" in body, \
    "refreshExtensionControls must always read a live Snapshot before skip"
assert "if signature == lastExtensionControlsSignature" in body, \
    "refreshExtensionControls no longer skips on identical visible signature"
assert "extensionControlItems(actions: actions, binding: binding, page: page)" in body, \
    "changed model must still rebuild action-item closures from the Snapshot"
assert "sidebar.extensionToolbar.update(sidebarOwns ? items : [])" in body, \
    "changed model must still republish sidebar extension toolbar"
assert "selectedBrowserToolbar?.updateExtensionItems(items)" in body, \
    "changed model must still republish toolbar extension items"
assert "updateSiteControlCenter(siteControlCenter, page: sccPage, items: nil)" in body, \
    "identical model must still refresh open SCC non-extension fields"
assert body.index("binding.extensionActions(for: page)") < body.index(
    "if signature == lastExtensionControlsSignature"), \
    "Snapshot must precede the identical-signature skip"
assert "nativeBrowserExtensionActionsDidChange" in controller and \
    "refreshExtensionControls()" in controller.split(
        "func nativeBrowserExtensionActionsDidChange")[1].split("func nativeBrowserExtensionPopupAnchor")[0], \
    "extension-actions-changed notification must still refresh controls"

assert "lastPushedWebsiteTheme" in controller, "website-theme skip gate missing"
assert "last.stylesheet == stylesheet" in controller, "website-theme identical-stylesheet skip missing"

print("ExtensionControlsSkip: live Snapshot compare only; real changes still update; website-theme gate kept")
