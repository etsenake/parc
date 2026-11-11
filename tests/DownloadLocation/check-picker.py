#!/usr/bin/env python3
"""Exercise the Download Location picker and the Settings Downloads card.

Compiles the real DownloadLocationPicker with the exact Downloads card layout
lines and layout helpers sliced from SettingsWindow.swift, plus its shared
SettingsGroupView from SettingsPresentation.swift
(not copies), runs its assertions, and checks the SettingsWindow wiring that
needs the native engine on source. No Chromium, profile, panel or user file.
Usage: check-picker.py [acceptance-image-directory]
"""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
settings = (root / "Sources/ParcApp/SettingsWindow.swift").read_text()
presentation = (root / "Sources/ParcApp/SettingsPresentation.swift").read_text()
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()


def between(text, start, end):
    assert text.count(start) == 1, f"Expected exactly one: {start!r}"
    head = text.index(start)
    return text[head:text.index(end, head)]


helpers = (between(settings, "    @discardableResult\n    private func label(", "    private func place(")
           + between(settings, "    private func place(", "\n    }\n") + "\n    }\n")
card = between(settings, "        let downloads = group(", "\n\n") + "\n"
group_view = between(presentation, "final class SettingsGroupView: LayoutView {", "@MainActor\nfinal class SettingsSymbolBadge")
for use in ("label(\"Download location\", in: downloads,", "place(downloadLocationPicker, in: downloads,",
            "width: DownloadLocationPicker.width", "place(downloadHelp, in: downloads,", "place(downloadRetry, in: downloads,"):
    assert use in card, f"The Downloads card no longer lays out: {use}"

harness = f"""import AppKit
@MainActor final class DownloadsCardHarness {{
    let downloadLocationPicker: DownloadLocationPicker
    let downloadHelp = NSTextField(wrappingLabelWithString: "")
    let downloadRetry = NSButton(title: "Retry", target: nil, action: nil)
    init(picker: DownloadLocationPicker) {{ downloadLocationPicker = picker }}
{helpers}
    func build(in content: NSView) -> SettingsGroupView {{
{card}        return downloads
    }}
}}
{group_view}"""

# SettingsWindow wiring that needs PCNativeBrowserApplication is asserted on
# the source; the full app typecheck compiles it.
for use in (
        "private let downloadLocationPicker = DownloadLocationPicker()",
        "downloadLocationPicker.onChoose = { [weak self] choice in self?.downloadLocationChosen(choice) }",
        "for field in [downloadHelp] {",
        "downloadRetry.bezelStyle = .rounded; downloadRetry.isHidden = true",
        "enabled: current.map { !$0.directoryManaged && !$0.promptManaged } ?? false,",
        "panelOpen: downloadFolderPanel != nil)",
        "guard let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged else {\n            refreshDownloadPreferences(); return",
        "if choice == .other { chooseDownloadDirectory(); return }",
        "_ = try PCNativeBrowserApplication.setPromptForDownload(choice == .prompt, for: current)",
        "let profileID = displayedProfileID else { downloadLocationPicker.revert(); return }",
        "panel.prompt = \"Select\"",
        "panel.canChooseFiles = false; panel.canChooseDirectories = true",
        "panel.canCreateDirectories = true; panel.allowsMultipleSelection = false",
        "panel.directoryURL = current.directoryURL",
        "downloadFolderPanel = panel\n        renderDownloadLocation()\n        panel.beginSheetModal(for: window)",
        "let url = panel.url else { self.refreshDownloadPreferences(); return }",
        "let chosen = try PCNativeBrowserApplication.setDownloadDirectory(url, for: current)\n"
        "                _ = try PCNativeBrowserApplication.setPromptForDownload(false, for: chosen)\n"
        "                self.refreshDownloadPreferences()\n"
        "            } catch { self.reportDownloadPreferenceError(error) }",
        "panel?.cancel(nil)\n        if panel != nil { renderDownloadLocation() }",
        "if selectedPane != pane {\n            cancelDownloadFolderSelection()",
        "if displayedProfileID != selectedProfileID { cancelDownloadFolderSelection() }",
        "if removing { cancelDownloadFolderSelection() }",
        "guard let self, self.downloadPreferencesGeneration == generation,"):
    assert use in settings, f"SettingsWindow no longer wires the picker as checked: {use}"
for gone in ("downloadPrompt", "downloadChoose", "Ask where to save each file", "Change download folder",
             "downloadLocation.stringValue"):
    assert gone not in settings, f"SettingsWindow still carries the former checkbox/button: {gone}"

with tempfile.TemporaryDirectory(prefix="parc-download-location-") as directory:
    temporary = pathlib.Path(directory)
    controls = temporary / "NativeControls.swift"
    controls.write_text(sidebar[:sidebar.index("final class FlippedStackView:")]
        # The Favorite favicon identity above ActionButton needs SplitOrientation.
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    (temporary / "DownloadsCard.swift").write_text(harness)
    sources = [controls, temporary / "DownloadsCard.swift", root / "Sources/ParcApp/DownloadLocationPicker.swift",
               root / "Sources/ParcApp/MenuItemImage.swift",
               root / "Sources/ParcApp/TranslucentButtonFace.swift", root / "Sources/ParcApp/PointerCover.swift", root / "Sources/ParcApp/ReloadControl.swift",
               root / "Sources/ParcApp/PointingHand.swift",
               root / "tests/DownloadLocation/PickerTests.swift"]
    executable = temporary / "download-location-picker"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable), *sys.argv[1:2]], check=True)
print("Download location wiring: source checks passed")
