#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import tempfile
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tests/Support"))
from app_sources import compile_swift
from window_sources import browser_window_controller_source

app = root / "Sources/ParcApp"
controller = browser_window_controller_source(app)
origin = controller[controller.index("func extensionPopupOrigin(forExtension identifier: String"):]
origin = origin[:origin.index("\n    }\n")]
assert origin.index("extensionPopupAnchor(for: identifier, popup: popup)") \
    < origin.index("trackExtensionPopupActivity(popup, control: anchor?.control)"), \
    "the button a popup anchors to, clicked or not, must light from the popup's first placement"
for use in ("@objc(parcExtensionPopup:forExtension:didChangePhase:)",
            "case .revealed?: showExtensionPopupActivity(extensionPopupActivity.reveal(popup: popup))",
            "case .closing?, .closed?: endExtensionPopupActivity(popup)",
            "forName: NSWindow.willCloseNotification, object: popup",
            "if control is ExtensionActionButton { return true }",
            "sidebar.pageControlsAnchor", "chrome === popupChrome.addressAnchor ? nil : chrome",
            "toolbars.map { $0?.siteControlCenterAnchor }"):
    assert use in controller, f"the window no longer follows its popup's lit button: {use}"

header = (root / "Engine/ParcNative/extension_popup_presenter.h").read_text()
presenter = (root / "Engine/ParcNative/extension_popup_presenter.mm").read_text()
for name, value in (("Revealed", 1), ("Closing", 2), ("Closed", 3)):
    assert f"PCExtensionPopupPhase{name} = {value}," in header, f"the engine's {name.lower()} report changed its number"
activity = (app / "ExtensionPopupActivity.swift").read_text()
assert "case revealed = 1, closing, closed" in activity, "the app must read the engine's popup reports by the same numbers"
assert "@optional\n- (void)parcExtensionPopup:(NSWindow*)popup" in header, \
    "windows that don't follow popup phases must still be able to place popups"


def method(name):
    body = presenter[presenter.index(name):]
    return body[:body.index("\n}\n")]


reveal = method("- (void)reveal {")
assert reveal.index("_revealed = YES;") < reveal.index("[self beginMotion:Motion::kOpening];") \
    < reveal.index("reportPhase:PCExtensionPopupPhaseRevealed"), "a popup reports its reveal as it starts to fade in"
dismiss = method("- (BOOL)dismissWithMotion:")
assert dismiss.index("[self beginMotion:Motion::kClosing];") < dismiss.index("reportPhase:PCExtensionPopupPhaseClosing"), \
    "a popup reports the start of its closing fade"
invalidate = method("- (void)invalidate {")
assert invalidate.index("NSWindow* parent = _parent;") < invalidate.index("_invalidated = YES;") \
    and invalidate.index("[popup close];") < invalidate.index("reportPhase:PCExtensionPopupPhaseClosed popup:popup parent:parent]"), \
    "every close path, including refusals and popups that never appeared, reports the close"

indicator = (app / "ExtensionPopupActivityIndicator.swift").read_text()
for use in ("view.setAccessibilityExpanded(next != nil)", "(view as? NSControl)?.cell?.setAccessibilityExpanded(next != nil)",
            "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"):
    assert use in indicator, f"the lit button no longer tells VoiceOver or follows Reduce Motion: {use}"
for name, owner in (("ExtensionControls.swift", "final class ExtensionActionButton:"),
                    ("SidebarView.swift", "final class ActionButton:"),
                    ("BrowserToolbar.swift", "final class BrowserToolbarActionButton:"),
                    ("SidebarRowActionButton.swift", "final class SidebarRowActionButton:")):
    text = (app / name).read_text()
    body = text[text.index(owner):]
    body = body[:re.search(r"\n(?:@MainActor )?(?:private )?(?:final )?class ", body[1:]).start() + 1]
    assert "var activityFill: CGFloat = 0" in body and "var glyphLift: CGFloat = 0" in body, \
        f"{owner} can no longer light or bounce for a popup"
    assert "isFlipped ? -glyphLift : glyphLift" in body, f"{owner} must hop its icon upward in flipped and unflipped views"
    assert "activityFill" in body[body.index("var glyphLift"):], f"{owner} must draw its lit fill"

with tempfile.TemporaryDirectory(prefix="parc-extension-popup-activity-") as directory:
    executable = Path(directory) / "checks"
    compile_swift(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                   str(app / "ExtensionPopupActivity.swift"), str(Path(__file__).with_name("main.swift")),
                   "-o", str(executable)])
    subprocess.run([str(executable)], check=True)
