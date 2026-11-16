#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="parc-popup-handoff-") as directory:
    executable = Path(directory) / "check"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library",
                    "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/PopupTabHandoff.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    waits = Path(directory) / "waits"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-parse-as-library",
                    "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcApp/WindowRestoreWaits.swift"),
                    str(Path(__file__).with_name("restore_wait.swift")), "-o", str(waits)], check=True)
    subprocess.run([str(waits)], check=True)

delegate = (root / "Sources/ParcApp/AppDelegate.swift").read_text()
coordinator = (root / "Sources/ParcApp/PopupTabHandoffCoordinator.swift").read_text()
checks = 0


def body(source, signature):
    start = source.index(signature)
    depth, i = 0, source.index("{", start)
    for j in range(i, len(source)):
        depth += {"{": 1, "}": -1}.get(source[j], 0)
        if depth == 0:
            return source[start:j + 1]
    raise AssertionError(f"unterminated {signature}")


def expect(condition, message):
    global checks
    assert condition, message
    checks += 1


handoff = body(delegate, "controller.onRequestBrowserTab = {")
expect("self.popupTabHandoff.request(input, from: controller" in handoff,
       "every popup New Tab or address request goes through the admitted handoff")
expect("makeKeyAndOrderFront" not in handoff and "showWindow" not in handoff,
       "the popup request never brings a window forward before admission")
expect("privateParentProfileID: privateParentID" in handoff,
       "a fresh window keeps the popup's private parent, so a private popup opens a private window")
candidate = body(coordinator, "private static func candidate(")
expect("binding.canAdmitHiddenPageTransferDestination" in candidate,
       "a visible destination must pass the engine's hidden-destination admission before it comes forward")
expect("controller.store === origin.store" in candidate and "isPrivate: controller.isPrivateBrowsing" in candidate,
       "a destination must share the popup's browsing session")
expect("window.attachedSheet == nil" in candidate and "canRestore" in candidate,
       "a minimized destination is restored only when no sheet holds it")
arrive = body(coordinator, "private func arrive(")
expect("target.binding?.canAdmitHiddenPageTransferDestination == true" in arrive
       and "origin.isCurrent(in: current)" in arrive and "target.isCurrent(in: current)" in arrive,
       "after coming forward the original page and destination are checked again before delivery")
request = body(coordinator, "func request(")
expect("WindowOwnerSequence.run(" in request and "origin.isCurrent(in: current) && target.isCurrent(in: current)" in request,
       "each step that brings the destination forward rechecks the original page and destination")
expect("sourceIsPrivate: source.isPrivateBrowsing" in request, "the private rule receives the popup's own privacy")
expect("restoreWaits.wait(for: window)" in arrive and "cancel" not in coordinator,
       "a restoring window gets its own wait, and a newer request never drops an older one")
origin = body(coordinator, "func isCurrent(in windows: [BrowserWindowController]) -> Bool {")
expect("selected === page && !page.isClosed" in origin, "the original page must still be the popup's open page")
print(f"PopupTabHandoff wiring: {checks} checks passed")
