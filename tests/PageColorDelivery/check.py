#!/usr/bin/env python3
"""The pane and Peek top bars' colour-only delivery path, by source.

PCBrowserView (Sources/ParcEngine/ParcEngine.m) publishes page-colour changes
through browserViewDidChangePageColor:, and its owners repaint only the bar.
The colour choice itself runs in tests/BrowserToolbar. Pass a CEF include
directory to also syntax-check the facade; no engine build, browser or page.
"""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]


def body(text: str, signature: str) -> str:
    start = text.index(signature)
    end = text.find("\n    func ", start + len(signature))
    following = text.find("\n    /// ", start + len(signature))
    end = min(index for index in (end, following, len(text)) if index != -1)
    return text[start:end]


header = (root / "Sources/ParcEngine/ParcEngine.h").read_text()
assert "- (void)browserViewDidChangePageColor:(PCBrowserView*)view" in header \
    and header.index("@optional") < header.index("browserViewDidChangePageColor:"), \
    "the colour-only delegate method is an optional PCBrowserViewDelegate method"

facade = (root / "Sources/ParcEngine/ParcEngine.m").read_text()
change = facade[facade.index("- (void)nativePageDidChange:(PCNativePage*)page {"):]
change = change[:change.index("\n}\n")]
color = change[change.index("NSColor* tint = page.developerModeTint;"):]
assert "[page respondsToSelector:@selector(pageBackgroundColor)]" in color, \
    "pageBackgroundColor is read only from engines that implement it"
assert "![_publishedTint isEqual:tint]" in color and "![_publishedPageBackground isEqual:background]" in color, \
    "each read returns a fresh NSColor, so published colours compare with isEqual:"
assert color.index("browserViewDidChangePageColor:self]") < color.index("_publishedTint = tint;"), \
    "a colour is recorded as published only after the delegate saw it"
assert "page.observer != self" in color[color.index("browserViewDidChangePageColor:self]"):], \
    "the facade revalidates its page and delegate after the colour callback"
assert "refreshLive" not in color and "didChangeLoading" not in color, \
    "a colour-only change never reaches the loading or title callbacks"
delegate = facade[facade.index("- (void)setDelegate:(id<PCBrowserViewDelegate>)delegate {"):]
delegate = delegate[:delegate.index("\n}\n")]
assert "_hasPublishedPageColor = NO;" in delegate, "a new delegate receives the current colour"

controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
handler = body(controller, "func browserViewDidChangePageColor(_ view: PCBrowserView) {")
assert "pane.browserToolbar.showPageColor(of: view.nativePage, failing: pane.showsFailure)" in handler \
    and "!pane.browserToolbar.isHidden" in handler, "the window repaints a visible pane bar"
for forbidden in ("refreshLivePageChrome", "render(", "needsLayout", "configureBrowserToolbar", "peek"):
    assert forbidden not in handler, f"the colour-only path must not reach {forbidden}"
configure = controller[controller.index("private func configureBrowserToolbar("):]
configure = configure[:configure.index("let revision = browser.readerRevision")]
assert "toolbar.showPageColor(of: page, failing: failing)" in configure, \
    "full configuration shares the colour-only path's choice"
assert "toolbar.isHidden = true; toolbar.setPageColor(nil, for: nil)" in configure, \
    "a hidden page bar forgets its colour and owner"
document = controller[controller.index("private func configureDocumentToolbar("):]
document = document[:document.index("let enabled =")]
assert document.count("toolbar.setPageColor(nil, for: nil)") == 2, \
    "a document bar is clear whether shown or hidden"
assert controller.count("failing: peek.showsFailure, themeBackground: nil)") == 2, \
    "Peek's colourless bar takes the window's ink over its own material"
assert controller.count("failing: pane.showsFailure,") >= 2, "pane bars pass their failure state"
assert "browserToolbar.showPageColor(of: livePage?.nativePage, failing: showsFailure)" in controller, \
    "a pane's failure or crash presentation repaints its bar"

peek = (root / "Sources/ParcApp/PeekController.swift").read_text()
handler = body(peek, "func browserViewDidChangePageColor(_ view: PCBrowserView) {")
assert "self.view.browserToolbar.showPageColor(of: page, failing: showsFailure)" in handler \
    and "!self.view.browserToolbar.isHidden" in handler, "Peek repaints its own visible bar"
assert "publishPresentationIfChanged" not in handler and "onUpdate" not in handler, \
    "Peek's colour-only path must not republish its presentation"

if len(sys.argv) > 1:
    # Read-only use of the CEF headers, as scripts/build.py compiles the facade.
    subprocess.run(["xcrun", "clang", "-fsyntax-only", "-arch", "arm64", "-mmacosx-version-min=13.0",
                    "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-fobjc-arc", "-fblocks",
                    "-I", str(root / "Engine/ParcNative"), "-I", str(root / "Sources/ParcEngine"),
                    "-DOS_MAC=1", "-I", sys.argv[1], str(root / "Sources/ParcEngine/ParcEngine.m")], check=True)
    print("Page colour delivery: source checks passed; facade syntax-checked")
else:
    print("Page colour delivery: source checks passed")
