#!/usr/bin/env python3
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
with tempfile.TemporaryDirectory(prefix="parc-toolbar-") as directory:
    scratch = Path(directory)
    slices = {
        "ActionButton.swift": ("SidebarView.swift", "final class MenuAction"),
        "NavigationControlButton.swift": ("NavigationControls.swift", "final class NavigationHistoryController"),
        "ThemePalette.swift": ("ThemeRenderer.swift", "@MainActor\nenum NativeInputDiagnostics"),
    }
    for target, (source, marker) in slices.items():
        text = (root / "Sources/ParcApp" / source).read_text()
        (scratch / target).write_text(text[:text.index(marker)])
    (scratch / "SplitOrientation.swift").write_text(
        "enum SplitOrientation: String, Codable, CaseIterable { case horizontal, vertical }\n"
    )
    text = (root / "Sources/ParcApp/SplitPaneMenu.swift").read_text()
    start = text.index("    static let emptyContentBackground")
    (scratch / "EmptyContentBackground.swift").write_text(
        "import AppKit\n@MainActor final class SplitPanePlaceholder {\n"
        + text[start:text.index("    let splitHighlight", start)] + "}\n")
    (scratch / "NativePageStub.swift").write_text("""import AppKit
final class PCNativePage: NSObject {
    @objc var developerModeTint: NSColor?
    @objc var pageBackgroundColor: NSColor?
    // Overlay 294's top-band sample; `sampler` models an engine that has it.
    @objc var topBandColor: NSColor?
    var hasTopBandColorSample = false, topBandColorCrossfades = false, sampler = false
    var topBandColorHost: String?
    var url: URL?
    var isClosed = false, loading = false, legacy = false
    override func responds(to selector: Selector!) -> Bool {
        if !sampler && selector == #selector(getter: PCNativePage.topBandColor) { return false }
        return !(legacy && selector == #selector(getter: PCNativePage.pageBackgroundColor)) && super.responds(to: selector)
    }
}
""")
    text = (root / "Sources/ParcApp/SiteControlCenter.swift").read_text()
    (scratch / "SiteControlCenterArtwork.swift").write_text(text[:text.index("enum SiteControlCenterMetrics")])
    executable = scratch / "checks"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-target", "arm64-apple-macos13.0",
        str(root / "Sources/ParcCore/SpaceTheme.swift"),
        str(scratch / "SplitOrientation.swift"),
        *[str(scratch / name) for name in slices],
        str(root / "Sources/ParcApp/ExtensionControls.swift"),
        str(scratch / "SiteControlCenterArtwork.swift"),
        str(root / "Sources/ParcApp/NavigationControlPress.swift"),
        str(root / "Sources/ParcApp/ReloadControl.swift"),
        str(root / "Sources/ParcApp/TranslucentButtonFace.swift"),
        str(root / "Sources/ParcApp/BrowserToolbarPreferences.swift"),
        str(root / "Sources/ParcApp/BrowserToolbar.swift"),
        str(root / "Sources/ParcApp/PaneTopBarColor.swift"),
        str(scratch / "EmptyContentBackground.swift"),
        str(scratch / "NativePageStub.swift"),
        str(root / "Sources/ParcApp/TopBarColorClient.swift"),
        str(root / "Sources/ParcApp/PaneTopBarPageColor.swift"),
        str(root / "Sources/ParcApp/PaneTitleControl.swift"),
        str(root / "Sources/ParcApp/MenuItemImage.swift"),
        str(root / "Sources/ParcApp/SplitPaneControl.swift"),
        str(root / "Sources/ParcApp/SidebarMotionController.swift"),
        str(root / "Sources/ParcApp/SidebarChromeLayout.swift"),
        str(root / "Sources/ParcApp/WindowStandardButtons.swift"),
        str(root / "Sources/ParcApp/ParcMenuColors.swift"),
        str(root / "tests/Support/AppKitObservation.swift"),
        *map(str, tooltip_sources(root, scratch, ["SpaceTheme.swift", "ThemeRenderer.swift", "ReloadControl.swift"])),
        str(Path(__file__).with_name("main.swift")), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
