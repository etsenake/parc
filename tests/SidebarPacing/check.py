#!/usr/bin/env python3
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
motion = (app / "SidebarMotionController.swift").read_text()
controller = browser_window_controller_source(app)
for use in ("let transition = SidebarTransition(from: previous, to: presentation)",
            "sidebarFloatingSurface = transition.keepsFloatingSurface",
            "sidebarRevealsAnchored = transition.revealsAnchored\n"
            "            sidebarChromePass = .preparation\n"
            "            layoutChrome()\n"
            "            sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface\n"
            "            sidebarChromePass = .geometry\n"
            "            sidebarMotion.animate(layoutRoot: rootView, views: [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator],\n"
            "                                  style: transition.style, flushesPreviousLayout: transition.flushesPreparation) {\n"
            "                sidebarPresentation = presentation\n"
            "                layoutChrome()",
            "SidebarMotionController.pinSurface(of: sidebarContainer, except: sidebar)",
            "rootView.onLayout = { [weak self] in self?.layoutChrome() }",
            "        let frames = chromeFrames(sidebarWidth: sidebarLayoutWidth, in: bounds)\n"
            "        sidebarContainer.frame = frames.sidebar\n"
            "        sidebar.frame = sidebarContainer.bounds\n",
            "        pageHost.frame = frames.pageHost\n"
            "        extensionSidePanel.isHidden = !frames.showsSidePanel\n"
            "        extensionSidePanel.frame = frames.sidePanel\n"
            "        pageShadow.place(around: frames.pageHost)\n"
            "        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)\n"
            "        splitMarginHandle.frame = splitMarginFrame(frames)\n"
            "        pageHost.needsLayout = true\n"
            "        pageHost.layoutSubtreeIfNeeded()\n",
            "        if sidebarFloatingSurface && sidebarPresentation == .locked { sidebarContainer.docksFloatingSurface = true }\n",
            "        sidebarContainer.floatingCornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : nil\n"
            "        sidebarContainer.docksFloatingSurface = fullPass && sidebarFloatingSurface && sidebarPresentation == .locked\n"
            "        if fullPass { sidebarContainer.preparesFloatingDock = false }\n",
            "        pageHost.frame = frames.pageHost\n"
            "        if pageHostMoved, loadedStartPage?.superview != nil { loadedStartPage?.invalidateCoordinates() }\n"
            "        splitView.dividerThickness = frameThickness\n"
            "        pageShadow.place(around: frames.pageHost)\n"
            "        refreshPageShadow()\n",
            "rootView.addSubview(pageShadow)\n        rootView.addSubview(pageHost)\n"):
    assert use in controller, f"BrowserWindowController no longer runs the passes tests/SidebarPacing measures: {use}"
assert controller.count("sidebarContainer.frame = frames.sidebar") == 2, "both chrome passes place the sidebar by SidebarChromeFrames"
for source, view in (("DeveloperMode.swift", "DeveloperToolbarView"), ("BrowserToolbar.swift", "BrowserToolbarView"),
                     ("PageFailureView.swift", "PageFailureView")):
    body = re.search(rf"^(?:@MainActor )?final class {view}\b.*?(?=^(?:@MainActor |private |fileprivate )?(?:final )?(?:class|struct|enum|extension) )",
                     (app / source).read_text() + "\nclass End", re.S | re.M)
    assert body and "override func draw(_ dirtyRect: NSRect)" in body.group(0), f"{view} no longer draws; the harness's hidden strips stand for it"
for use in ("        let toolbar = DeveloperToolbarView()\n        toolbar.isHidden = true\n"
            "        addSubview(toolbar, positioned: .below, relativeTo: browserToolbar)\n",
            "browserToolbar.isHidden = true; addSubview(browserToolbar)",
            "browserToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)",
            "loadedDeveloperToolbar?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: developerHeight)",
            "            self.error.frame = self.content.bounds\n"):
    assert use in controller, f"BrowserPane no longer lays its hidden views out as the harness does: {use}"
hold = "        for view in hidden { view.layerContentsRedrawPolicy = .beforeViewResize }\n"
pin = "            pinDrawnContent(surface, to: .scaleAxesIndependently)\n"
assert hold in motion and pin in motion, "SidebarMotionController no longer holds hidden drawing views or pins the floating surface"
split_menu = (app / "SplitPaneMenu.swift").read_text()
placeholder = re.search(r"^final class SplitPanePlaceholder\b.*?^}", split_menu, re.S | re.M)
assert placeholder and "override var wantsUpdateLayer: Bool { true }" in placeholder.group(0) \
    and "override func draw(" not in placeholder.group(0) and "addSubview(" not in placeholder.group(0), \
    "SplitPanePlaceholder no longer draws only through its layer; the harness's EmptyContent stands for it"
assert "    let placeholder = SplitPanePlaceholder(frame: .zero)\n" in split_menu \
    and "            wanted.insert(draft.placeholder, at: index)\n" in controller \
    and "requested == .hidden && pendingPane ? .floating : requested" in motion, \
    "Add Split's pending pane no longer shows the empty content while it holds the sidebar floating"

def build(directory, name, motion_source):
    source = Path(directory) / f"{name}-SidebarMotionController.swift"
    source.write_text(motion_source)
    executable = Path(directory) / name
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(root / "Sources/ParcCore/WindowFrame.swift"),
                    str(app / "ThemeRenderer.swift"), str(source),
                    str(app / "SidebarChromeLayout.swift"), str(app / "WindowStandardButtons.swift"),
                    str(app / "ReloadControl.swift"), str(app / "PageLoadingIndicator.swift"), str(app / "PageCardShadow.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    return executable

with tempfile.TemporaryDirectory(prefix="parc-sidebar-pacing-") as directory:
    shutil.copytree(root / "Resources/FloatingSidebar", Path(directory) / "FloatingSidebar")
    subprocess.run([str(build(directory, "pacing", motion))], check=True)
    controls = {"hidden views resized every frame": (motion.replace(hold, ""), "⌘S hide, web page: per-frame"),
                "theme canvas rendered every frame": (motion.replace(pin, "            _ = surface\n"),
                                                         "⌘S locks a floating sidebar: per-frame")}
    for name, (source, failure) in controls.items():
        result = subprocess.run([str(build(directory, name.replace(" ", "-"), source))], capture_output=True, text=True)
        assert result.returncode != 0 and failure in result.stdout, f"negative control did not fail: {name}\n{result.stdout[-2000:]}"
        print(f"SidebarPacing negative control fails as expected: {name}")
