#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Support"))
from app_sources import compile_swift
from window_sources import browser_window_controller_source

controller = browser_window_controller_source(root / "Sources/ParcApp")
for use in ("ExtensionPopupPlacement.anchor(clicked: extensionPopupSource?.control(for: identifier, popup: popup),",
            "panes.values.map { $0.browserToolbar }",
            "@objc(parcExtensionPopupOriginForExtension:popup:size:)"):
    assert use in controller, f"extension popups no longer place from the button that opened them: {use}"
click = controller[controller.index("self.performExtensionActionAfterDismissingControls { [weak self] in"):]
click = click[:click.index("\n                    }")]
for use in ("self?.extensionPopupSource = control.map { ExtensionPopupSource(identifier: action.identifier, control: $0) }",
            "_ = binding.executeExtensionAction(action, for: page)",
            "if self?.extensionPopupSource?.claimed == false { self?.extensionPopupSource = nil }"):
    assert use in click, f"a click must hand its button only to the popup its own action opens: {use}"
assert click.index("ExtensionPopupSource(identifier:") < click.index("executeExtensionAction") < click.index("claimed == false"), \
    "the click's button is recorded just before its action runs and dropped if no popup claimed it"
assert "self.siteControlCenterItems[id]?.execute(controller?.anchorView)" in controller \
    and "items[id]?.execute(anchor)" in controller, \
    "extensions launched from the Site Control Center no longer open below the button that showed it"
assert "window.convertToScreen(view.convert(view.bounds, to: nil))" in controller, \
    "anchor frames must reach the screen through AppKit's own window conversion, flipped views included"

with tempfile.TemporaryDirectory(prefix="parc-extension-popup-placement-") as directory:
    executable = Path(directory) / "checks"
    compile_swift(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors",
                   "-target", "arm64-apple-macos13.0",
                   str(root / "Sources/ParcApp/ExtensionPopupPlacement.swift"),
                   str(Path(__file__).with_name("main.swift")), "-o", str(executable)])
    subprocess.run([str(executable)], check=True)
