#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
pinned = {"PageFailureView.swift": ["SidebarMotionController.pinDrawnContent(self, to: .scaleAxesIndependently)",
                                    "SidebarMotionController.pinDrawnContent(sentence, to: .center)",
                                    "SidebarMotionController.pinDrawnContent(corner, to: .center)"],
          "PaneTitleControl.swift": ["SidebarMotionController.pinDrawnContent(label, to: .center)"],
          "BrowserToolbar.swift": ["SidebarMotionController.pinDrawnContent(self, to: .scaleAxesIndependently)"]}
for source, calls in pinned.items():
    text = (root / "Sources/ParcApp" / source).read_text()
    for call in calls:
        assert call in text, f"{source} no longer pins: {call}"
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
for use in ("sidebarContainer.isHidden = !sidebarAvailable\n",
            "let placement = SidebarPresentationFrame(sidebarPresentation, inMotion: sidebarMotionVisible,\n"
            "                                                 floatingSurface: sidebarFloatingSurface, revealsAnchored: sidebarRevealsAnchored)\n"
            "        return SidebarChromeFrames(bounds: bounds, sidebarWidth: sidebarWidth, presentation: sidebarPresentation, placement: placement,",
            "let transition = SidebarTransition(from: previous, to: presentation)",
            "sidebarRevealsAnchored = transition.revealsAnchored",
            "if self.sidebarPresentation != .hidden { self.sidebar.retestPointer() }"):
    assert use in controller, f"BrowserWindowController no longer presents the hidden sidebar: {use}"
presented = "let presented = sidebarAvailable && sidebarPresentation.presents(inMotion: sidebarMotionVisible)"
assert controller.index("sidebar.frame = sidebarContainer.bounds") < controller.index(presented) \
    < controller.index("sidebar.isPresented = presented\n"), \
    "BrowserWindowController no longer sets the presentation after the sidebar's frames"
motion = (root / "Sources/ParcApp/SidebarMotionController.swift").read_text()
hold = "        for view in hidden { view.layerContentsRedrawPolicy = .beforeViewResize }\n"
assert hold in motion, "SidebarMotionController no longer holds hidden drawing views during the group"
assert ("let libraryWidth: CGFloat = !library || fullscreen ? 0\n"
        "            : max(Self.libraryMinimumWidth, min(bounds.width - 56, libraryContentWidth))") in motion, \
    "Library column is max(min(width − 56, the page's content width), 417)"
assert "case .libraryWidth: context.duration = 0.2" in motion and "if style != .floating {" in motion, \
    "the Library width group is 0.2 s on the anchored cubic"
for use in ("        libraryView = view\n        libraryContentWidth = view.contentWidth\n",
            "        libraryMotion.cancel()\n"
            "        libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0\n"
            "        layoutChrome()\n",
            "        if sidebarMotionLayoutKey != layoutKey {\n"
            "            sidebarPreviews?.dismiss()\n"
            "            if libraryMotion.isAnimating {\n"
            "                libraryMotion.cancel(); pageHost.needsLayout = true; extensionSidePanel.needsLayout = true\n",
            "        settleSidebarMotion()\n        libraryMotion.cancel()\n",
            "libraryMotion.cancel(); libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0; ",
            "        sidebar.frame = sidebarContainer.bounds\n        libraryView?.frame = frames.library\n",
            "            library: libraryView != nil,\n            libraryContentWidth: libraryContentWidth,\n",
            "library: libraryView != nil,\n            libraryContentWidth: libraryContentWidth, popup: isPopupWindow,"):
    assert controller.count(use) == 1, f"BrowserWindowController no longer owns the Library width as checked: {use}"
assert controller.index("libraryContentWidth = view.contentWidth") < controller.index("rootView.addSubview(view)\n        layoutChrome()"), \
    "the Library opens at its page's width without a group"
setter = controller[controller.index("private func setLibraryContentWidth("):controller.index("private func openLibraryURLs(")]
for use in ("guard libraryContentWidth != width else { return }",
            "guard let libraryView, window?.isVisible == true, window?.isMiniaturized != true, !rootView.inLiveResize else {\n"
            "            libraryMotion.cancel(); layoutChrome(); return\n",
            "sidebarChromePass = .geometry\n"
            "        libraryMotion.animate(layoutRoot: rootView,\n"
            "                              views: [libraryView, pageHost, pageShadow, extensionSidePanel, findHost, loadingIndicator],\n"
            "                              style: .libraryWidth) {\n"
            "            layoutChrome()\n",
            "guard let self, !self.isClosing, self.libraryView != nil else { return }",
            "self.pageHost.needsLayout = true\n            self.extensionSidePanel.needsLayout = true\n            self.layoutChrome()",
            "sidebarChromePass = .full\n"):
    assert use in setter, f"setLibraryContentWidth no longer follows the setHomeWidth: {use}"
assert "accessibilityDisplayShouldReduceMotion" not in setter, "the home-width group reads no Reduce Motion"
shutdown = controller[controller.index("    func shutdownBrowsers() {"):controller.index("    func windowWillClose(")]
assert "        settleSidebarMotion()\n        libraryMotion.cancel()\n" in shutdown, \
    "window disposal settles the Library width group with the sidebar's"
geometry = controller[controller.index("    private func layoutChromeGeometry() {"):controller.index("    func newTab() {")]
assert ("        pageHost.frame = frames.pageHost\n"
        "        extensionSidePanel.isHidden = !frames.showsSidePanel\n"
        "        extensionSidePanel.frame = frames.sidePanel\n") in geometry, \
    "the geometry pass moves the extension side panel with the page"
assert "pageHost.layer?.cornerRadius = PageCard.cornerRadius\n        pageHost.layer?.cornerCurve = .continuous" in controller \
    and "nonisolated(unsafe) private(set) static var cornerRadius: CGFloat = 6" in (root / "Sources/ParcApp/PageCardShadow.swift").read_text(), \
    "the page host starts at the 6-point continuous corner and follows the window frame thickness"
assert "let sidebarless = isPopupWindow && nativeFullscreenTabID == nil" in controller, \
    "Library is not sidebarless; only a popup is"
assert "libraryView?.showsWindowButtons = showsOwn && !sidebarless" in controller, \
    "Library lists the dimmed lights, and a popup does not"
split = (root / "Sources/ParcApp/ParcSplitView.swift").read_text()
assert "pane.layer?.cornerRadius = divided ? PageCard.cornerRadius : 0" in split, "split panes keep their own 6-point radius"
assert "NativeStartView" not in controller, "the Parc start page is gone"
assert "wanted = [startPage]" in controller, "a window with no tab shows the start page"
assert controller.index("rootView.addSubview(pageShadow)") < controller.index("rootView.addSubview(pageHost)"), \
    "the page card's shadow sits below the page host"
assert controller.count("pageShadow.place(around: frames.pageHost)") == 2, "both chrome passes place the page card's shadow"
assert "views: [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator]" in controller, \
    "the page card's shadow takes the ⌘S group's motion with the page host"
assert "host.layer?.cornerRadius" not in split, "split backing does not restyle the page host's corner"
with tempfile.TemporaryDirectory(prefix="parc-sidebar-motion-") as directory:
    def build(name, source):
        controller = Path(directory) / f"{name}.swift"
        controller.write_text(source)
        executable = Path(directory) / name
        subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0", str(controller),
            str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
            str(root / "Sources/ParcApp/WindowStandardButtons.swift"),
            str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
        return executable
    subprocess.run([str(build("checks", motion))], check=True)
    result = subprocess.run([str(build("unheld", motion.replace(hold, "")))], capture_output=True, text=True)
    assert result.returncode != 0 and "a hidden drawing view is sized once" in result.stderr, \
        "negative control: the hidden-view check passes without the hold"
    print("SidebarMotion negative control fails as expected: hidden drawing view without the hold")
