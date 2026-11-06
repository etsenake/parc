#!/usr/bin/env python3
"""the floating sidebar surface: CellDropShadow artwork and provenance, the
radius-8 masks, SidebarBorderColor edge, the clip toggling that lets the shadow
show, the floating → locked group's fades (shadow and blur out, the window's
behind-window material in, prepared before the group), and a blur in the
window's appearance that a light ↔ dark Space swipe leaves unchanged, on the
production ThemeRendererView in an off-screen window that is never ordered in
or made key. No browser, input or preferences."""
from pathlib import Path
import hashlib
import re
import shutil
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
app = root / "Sources/ParcApp"
controller = (app / "BrowserWindowController.swift").read_text()
for use in ("        sidebarContainer.floatingCornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : nil\n"
            "        // A full pass while the dock slides keeps what the dock faded.\n"
            "        sidebarContainer.docksFloatingSurface = fullPass && sidebarFloatingSurface && sidebarPresentation == .locked\n",
            "        sidebar.layer?.cornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : 0\n"
            "        sidebar.clipsToBounds = floatingSurface\n",
            "        if sidebarFloatingSurface && sidebarPresentation == .locked { sidebarContainer.docksFloatingSurface = true }\n",
            #
            #
            "            sidebarChromePass = .preparation\n"
            "            layoutChrome()\n"
            "            sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface\n"
            "            sidebarChromePass = .geometry\n",
            "        if fullPass { sidebarContainer.preparesFloatingDock = false }\n"):
    assert use in controller, f"BrowserWindowController no longer drives the floating surface as checked: {use}"
assert controller.count("preparesFloatingDock") == 2, "only the dock's preparation and the full pass set preparesFloatingDock"
assert "        docksFloatingSurface = previous == .floating && next == .locked\n" in (app / "SidebarMotionController.swift").read_text(), \
    "SidebarTransition no longer prepares the dock only for floating → locked"
assert "sidebarContainer.layer?.cornerRadius" not in controller and "sidebarContainer.layer?.masksToBounds" not in controller, \
    "the surface's corners and clip belong to ThemeRendererView.floatingCornerRadius"
assert "sidebar.layer?.cornerRadius = 0" not in controller, "a docking sidebar keeps the corners until it settles"
# Every Space swipe hands the themes of the pages either side of the strip's
# position to the window's surfaces, whose canvases draw both themes, instead
# of stacking the neighbour's own surface (main.swift renders the commit on
# both; tests/SidebarSpacePaging checks the pages).
sidebar_view = (app / "SidebarView.swift").read_text()
strip = sidebar_view[sidebar_view.index("    private func showPageStrip(at offset: CGFloat) {"):]
strip = strip[:strip.index("\n    }\n")]
# A switch made elsewhere blends from the Space it left (pagingSourceID).
assert "SidebarSpacePagingModel.themePages(selected: index, offset: offset, width: width, count: spaces.count)" in strip \
    and re.search(r"onPagingTheme\?\(ThemePagingTransition\(from: spaces\[pages\.left\]\.theme, theme: spaces\[pages\.left \+ 1\]\.theme,\s+progress: pages\.progress\)\)", strip) \
    and "ThemePagingTransition(from: spaces[source].theme, theme: spaces[index].theme, progress: 1 - fraction)" in strip \
    and "onPagingTheme?(nil)" in strip, "SidebarView no longer gives every swipe's pages to the window's surfaces"
assert "alphaValue" not in strip and "isOnFloatingSurface" not in sidebar_view, "a swipe's neighbouring theme is stacked over the sidebar again"
assert "ThemeRendererView(" not in sidebar_view and "neighborTheme" not in sidebar_view and "updateNeighborPalette(space)" in strip \
    and "        neighborSidebar?.palette = ThemeChromePalette(theme: space.theme, appearance: appearance)\n" in sidebar_view, \
    "the neighbouring page builds a theme renderer for its palette again"
assert ("        sidebar.onPagingTheme = { [weak self] transition in\n"
        "            self?.rootView.pagingTransition = transition; self?.sidebarContainer.pagingTransition = transition\n"
        "        }\n") in controller, "the controller no longer gives the swipe to the window's background and the sidebar surface"
assert "isOnFloatingSurface" not in controller, "the swipe's colour no longer depends on the presentation"
# The packager copies all of Resources, FloatingSidebar included.
assert 'shutil.copytree(repo / "Resources", resources, symlinks=True)' in (root / "scripts/build.py").read_text(), \
    "scripts/build.py no longer packages the whole Resources directory"
artwork = root / "Resources/FloatingSidebar"
readme = (artwork / "README.md").read_text()
for name in ("CellDropShadow.png", "CellDropShadow@2x.png"):
    digest = hashlib.sha256((artwork / name).read_bytes()).hexdigest()
    assert re.search(rf"\| `{re.escape(name)}` \| `{digest}` \|", readme), f"README provenance hash for {name}"
assert "30a0e03a290800bc07b3ed475f2d75548cf8890f60371d3e36aaec785cad7595" in readme, "README names the source catalog"
assert sorted(path.name for path in artwork.iterdir() if not path.name.startswith(".")) == ["CellDropShadow.png", "CellDropShadow@2x.png", "README.md"], \
    "Resources/FloatingSidebar holds only the copied artwork and its README"
with tempfile.TemporaryDirectory(prefix="parc-floating-sidebar-surface-") as directory:
    executable = Path(directory) / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-parse-as-library", "-target", "arm64-apple-macos13.0",
                    str(root / "Sources/ParcCore/SpaceTheme.swift"), str(app / "ThemeRenderer.swift"),
                    str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    # An unbundled executable's Bundle.main.resourceURL is its own directory.
    shutil.copytree(artwork, Path(directory) / "FloatingSidebar")
    shutil.copytree(root / "Resources/ThemeTextures", Path(directory) / "ThemeTextures")
    subprocess.run([str(executable)], check=True, timeout=120)
print("FloatingSidebarSurface check passed")
