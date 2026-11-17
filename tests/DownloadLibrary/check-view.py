#!/usr/bin/env python3
import pathlib
import subprocess
import tempfile
import os
import plistlib
import shutil
import re

root = pathlib.Path(__file__).resolve().parents[2]
import sys
sys.path.insert(0, str(root / "tests/Tooltip"))
from support import tooltip_sources
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tests/Support"))
from window_sources import browser_window_controller_source
with tempfile.TemporaryDirectory(prefix="parc-download-library-view-") as directory:
    temporary = pathlib.Path(directory)
    sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()
    controls = temporary / "NativeControls.swift"
    controls.write_text(sidebar[:sidebar.index("final class FlippedStackView:")])
    easel = (root / "Sources/ParcApp/EaselEditorViewController.swift").read_text()
    store_owner = temporary / "EaselStoreOwner.swift"
    store_owner.write_text(easel[:easel.index("    private let session:")] + "}\n")
    sidebar_stub = temporary / "SpaceCardSidebar.swift"
    sidebar_stub.write_text("""import AppKit
@MainActor final class SidebarView: NSView {
    var keyViewExit: NSView?
    var isSpaceManagement = false
    var palette: ThemeChromePalette?
    func cancelSpaceNameEditing() {}
    func spaceAppearanceAnchor(_ id: UUID) -> NSView? { nil }
    func render(state: BrowserState, focusedTabID: UUID?, loading: Set<UUID>, canBack: Bool, canForward: Bool) {}
}
""")
    app = ["LibraryView", "CaptureLibraryStore", "CaptureLibraryView", "DocumentsLibraryView", "DownloadLibrarySelection", "DownloadLibraryTable", "DownloadLibraryView",
           "DownloadLibraryPreview", "DownloadActivityBadge", "DownloadThumbnailProvider", "DownloadFileDrag", "ThemeRenderer", "LibraryArtwork",
           "ExternalMediaLibrary", "CaptureLibrarySharing", "MediaLibraryContext", "SpaceManagerView", "SidebarIconCatalog", "SidebarRowAppearance",
           "CaptureMotion", "DownloadArrivalMotion", "LibraryRailTile", "LibraryRailIcon", "WindowStandardButtons", "TranslucentButtonFace", "ReloadControl",
           "SidebarMotionController", "ParcToast", "TopBarColorClient", "ParcDialog"]
    sources = sorted((root / "Sources/ParcCore").glob("*.swift"))
    sources += [root / "Sources/ParcApp" / f"{name}.swift" for name in app]
    spinner = temporary / "ParcButtonSpinner.swift"
    subprocess.run([sys.executable, "-B", str(root / "tests/Support/declarations.py"), str(spinner), "ParcButtonSpinner"],
                   check=True, stdout=subprocess.DEVNULL)
    sources += [controls, store_owner, sidebar_stub, spinner, root / "tests/Support/AppKitObservation.swift",
                root / "tests/DownloadLibrary/ViewTests.swift"]
    sources += tooltip_sources(root, temporary, sources)
    shutil.copytree(root / "Resources/Library", temporary / "Library")
    executable = temporary / "download-library-view"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library", *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=120)
    selection_sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [
        root / "Sources/ParcApp/DownloadLibrarySelection.swift",
        root / "Sources/ParcApp/DownloadLibraryTable.swift",
        root / "tests/DownloadLibrary/SelectionTests.swift",
    ]
    selection = temporary / "download-library-selection"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, selection_sources), "-o", str(selection)], check=True)
    subprocess.run([str(selection)], check=True, timeout=120)
    entry_sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [
        root / "Sources/ParcApp/DownloadLibrarySelection.swift",
        root / "Sources/ParcApp/DownloadActivityBadge.swift",
        root / "Sources/ParcApp/DownloadFileDrag.swift",
        root / "tests/DownloadLibrary/EntryTests.swift",
    ]
    entry = temporary / "download-entry"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, entry_sources), "-o", str(entry)], check=True)
    subprocess.run([str(entry)], check=True, timeout=120)
    library_entry_sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [
        root / "Sources/ParcApp" / f"{name}.swift" for name in
        sorted(set(app) | {"BoxOfThingsIcon", "SidebarLibraryEntry", "SidebarChromeLayout", "LibraryFlyout", "ParcDialog"})] + [
        controls, store_owner, sidebar_stub, spinner, root / "tests/Support/AppKitObservation.swift",
        root / "tests/DownloadLibrary/LibraryEntryTests.swift"]
    library_entry_sources += tooltip_sources(root, temporary, library_entry_sources)
    library_entry = temporary / "library-entry"
    subprocess.run(["xcrun", "swiftc", str(root / "tests/Support/TestFailure.swift"), "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, library_entry_sources), "-o", str(library_entry)], check=True)
    subprocess.run([str(library_entry)], check=True, timeout=120)
    for use in ("private let libraryEntry = SidebarLibraryEntry()",
                "libraryEntry.place(button: Chrome.dockLeadingButton(height: bounds.height))",
                "spacesHost.frame = Chrome.dockStrip(width: width, height: bounds.height)",
                "for button in [pageActions, paymentAction] { button.focusRingCornerRadius = 5 }",
                "libraryEntry.onOpen = { [weak self] page in self?.onLibrary?(page) }",
                "libraryEntry.updateFlyoutDownloads(items, profiles: profiles, privateWindow: isPrivateBrowsing,",
                "badging: enabled && !libraryEntry.isHidden)",
                "var libraryEntryExpansionAllowed = true { didSet { updateLibraryEntryExpansion() } }",
                "libraryEntry.canExpand = libraryDownloadsEnabled && !libraryEntry.isHidden && libraryEntryExpansionAllowed",
                "func updateLibraryCaptures(_ store: CaptureLibraryStore?) { libraryEntry.captureStore = store }",
                "func updateLibraryFlyoutFiles(_ files: [LibraryFlyoutFile]) { libraryEntry.updateFlyoutFiles(files) }",
                "func libraryDidOpen() { libraryEntry.libraryDidOpen() }",
                "libraryEntry.containerWidth = width",
                "libraryEntry.onFlyoutExpansion = { [weak self] expanded, count in self?.updateLibraryFlyoutMask(expanded, count: count) }",
                "libraryFlyoutMask.expand(on: contentSurface, totalHeight: total, dockHeight: SidebarChromeLayout.dockHeight)",
                "DispatchQueue.main.asyncAfter(deadline: .now() + LibraryFlyoutContentMask.collapseDelay(count: count))",
                "libraryEntry.badge.colors = DownloadBadgeColors(foreground: palette?.foregroundPrimary ?? .labelColor,\n"
                "            maxContrast: palette?.maxContrastColor ?? .labelColor, cutout: palette?.cutoutColor ?? .windowBackgroundColor)",
                "libraryEntry.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)"):
        assert use in sidebar, f"SidebarView no longer hosts the Library entry as checked: {use}"
    chain = re.search(r"SidebarAccessibility\.keyViewChain\((?P<args>[^()]*\btrailing: \[footerMore\][^()]*)\)", sidebar)
    assert chain and "beforeList: [spaceHeader]" in chain.group("args"), \
        "SidebarView's key-view chain no longer ends with footer More after the Space header and list"
    for gone in ("ActionButton(\"Downloads\"", "arrow.down.circle", "width - 73", "onDownloads"):
        assert gone not in sidebar, f"SidebarView still carries the former Downloads button: {gone}"
    controller = browser_window_controller_source(root / "Sources/ParcApp")
    for use in ("sidebar.onLibrary = { [weak self] page in self?.showLibraryFromEntry(page) }",
                "switch LibraryEntryRoute.decide(target: target, showing: showing,",
                "case .open(let page): showLibrary(isPrivateBrowsing && page != .captures ? .downloads : Self.libraryKind(page))",
                "view.onShowKind = { [weak self] kind in self?.recordLibraryPage(kind) }",
                "LibraryEntryPreferences.shared.lastSelectedPage = Self.libraryPage(kind)",
                "sidebar.onLibraryItem = { [weak self] action in self?.performLibraryFlyout(action) ?? false }",
                "sidebar.libraryDownloadFileURL = { [weak self] item in self?.libraryDownloadFileURL(item) }",
                "case let .download(item, command): return performLibraryDownload(item, action: command)",
                "case let .file(file, command): return performLibraryFlyoutFile(file, action: command)",
                "self.startLibraryFlyoutFileQuery()",
                "if libraryView != nil { sidebar.libraryDidClose() }",
                "recordLibraryPage(view.kind)\n        sidebar.libraryDidOpen()",
                "var libraryView: LibraryView? { didSet { updateLibraryEntryExpansion() } }",
                "var tabSwitcher: RecentTabSwitcher? { didSet { updateLibraryEntryExpansion() } }",
                "sidebar.libraryEntryExpansionAllowed = libraryView == nil && tabSwitcher == nil && commandBar == nil",
                "case let .share(item, share): return shareLibraryFlyoutItem(item, share)",
                "case .deleteCapture(let capture): return deleteLibraryFlyoutCapture(capture)",
                "return LibraryFlyoutCaptureDeletion.confirm(in: parent)",
                "do { try await reservation.perform { try await library.delete(capture) } }",
                "sidebar.updateLibraryCaptures(isPrivateBrowsing || isClosing || wholeWindowClose ? nil",
                "sidebar.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles, enabled: downloadActivityEnabled)\n"
                "        refreshLibraryDownloadActivity()",
                "libraryView?.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles,\n"
                "                                            privateWindow: isPrivateBrowsing, enabled: downloadActivityEnabled)",
                "rootView.addSubview(view)\n        layoutChrome()\n        refreshLibraryDownloadActivity()"):
        assert controller.count(use) == 1, f"The window no longer routes the entry as checked: {use}"
    library_view = (root / "Sources/ParcApp/LibraryView.swift").read_text()
    assert ("downloadsButton.progress?.colors = DownloadBadgeColors(foreground: palette?.foregroundPrimary ?? .labelColor,\n"
            "            maxContrast: palette?.maxContrastColor ?? .labelColor, cutout: palette?.cutoutColor ?? .windowBackgroundColor)") in library_view, \
        "The Library rail's Downloads badge no longer takes the sidebar's palette roles"
    command_bar_observer = re.search(r"(?:private )?var commandBar: CommandBar\? \{\s*didSet \{(.*?)\n        \}", controller, re.S)
    assert command_bar_observer and "updateLibraryEntryExpansion()" in command_bar_observer.group(1), \
        "Every command panel replacement must still update the Library entry expansion gate"
    assert controller.count("LibraryFlyoutSharing.perform(share, items: items)") == 3, "Download, folder file and capture shares perform through the macOS service"
    entry_source = (root / "Sources/ParcApp/SidebarLibraryEntry.swift").read_text()
    assert "sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {\n        .copy\n    }" in entry_source, \
        "Flyout drags are copy only"
    assert "onShowKind?(kind)" in (root / "Sources/ParcApp/LibraryView.swift").read_text(), "The Library no longer reports its page"
    download_library = (root / "Sources/ParcApp/DownloadLibraryView.swift").read_text()
    assert "filterScroll" not in download_library and "selectProfile" not in download_library \
        and 'NSTextField(labelWithString: "Profiles")' not in download_library, \
        "Downloads regained a profile filter"
    assert "if !force && shouldSkipCatalogReload() { return }" in download_library, \
        "DownloadLibraryView no longer skips identical catalog fingerprints"
    capture_library = (root / "Sources/ParcApp/CaptureLibraryView.swift").read_text()
    assert "if !force && !itemsChanged && !catalogStatusChanged() { return }" in capture_library, \
        "CaptureLibraryView no longer skips identical Captures-visible fingerprints"
    assert "store.items != observedCaptures" in capture_library, \
        "CaptureLibraryView fingerprint must compare the capture list"
    assert "media.folders != observedMediaFolders" in capture_library, \
        "CaptureLibraryView fingerprint must compare media folder membership/access"
    arrival = (root / "Sources/ParcApp/DownloadArrival.swift").read_text()
    assert "static func make(palette: ThemeChromePalette) -> NSView? { DownloadBinBoxOfThingsItem(palette: palette) }" in arrival, \
        "The arrival bin no longer shows the Library entry's item"
    if destination := os.environ.get("PARC_COMPONENT_APP"):
        app = pathlib.Path(destination)
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(executable, contents / "MacOS" / "DownloadLibraryComponent")
        shutil.copytree(root / "Resources/Library", contents / "Resources" / "Library", dirs_exist_ok=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.parc.DownloadLibraryComponent",
            "CFBundleExecutable": "DownloadLibraryComponent", "CFBundleName": "DownloadLibraryComponent",
            "CFBundlePackageType": "APPL", "ParcComponentPreview": True,
        }))

    if destination := os.environ.get("PARC_ENTRY_COMPONENT_APP"):
        app = pathlib.Path(destination)
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry, contents / "MacOS" / "DownloadEntryComponent")
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.parc.DownloadEntryComponent",
            "CFBundleExecutable": "DownloadEntryComponent", "CFBundleName": "DownloadEntryComponent",
            "CFBundlePackageType": "APPL", "ParcEntryComponent": True,
        }))
