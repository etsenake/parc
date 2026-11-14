#!/usr/bin/env python3
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
settings = (root / "Sources/ParcApp/SettingsWindow.swift").read_text()
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()


def between(text, start, end):
    assert text.count(start) == 1, f"Expected exactly one: {start!r}"
    head = text.index(start)
    return text[head:text.index(end, head)]


helpers = (between(settings, "    @discardableResult\n    private func label(", "    private func place(")
           + between(settings, "    private func place(", "\n    }\n") + "\n    }\n")
card = between(settings, "        let downloads = group(", "\n\n") + "\n"
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
"""

for use in (
        "private let downloadLocationPicker = DownloadLocationPicker()",
        "downloadLocationPicker.onChoose = { [weak self] choice in self?.downloadLocationChosen(choice) }",
        "for field in [downloadHelp, searchHelp] {",
        "downloadRetry.bezelStyle = .rounded; downloadRetry.isHidden = true",
        "enabled: current.map { !$0.directoryManaged && !$0.promptManaged } ?? false,",
        "panelOpen: downloadFolderPanel != nil)",
        "guard let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged else {\n            refreshDownloadPreferences(); return",
        "if choice == .other { chooseDownloadDirectory(); return }",
        "try AppWidePreferenceController.shared.update { $0.promptForDownload = choice == .prompt }",
        "let profileID = generalProfileID else { downloadLocationPicker.revert(); return }",
        "panel.prompt = \"Select\"",
        "panel.canChooseFiles = false; panel.canChooseDirectories = true",
        "panel.canCreateDirectories = true; panel.allowsMultipleSelection = false",
        "panel.directoryURL = downloadLocationPicker.value?.directory ?? current.directoryURL",
        "downloadFolderPanel = panel\n        renderDownloadLocation()\n        panel.beginSheetModal(for: window)",
        "let url = panel.url else { self.refreshDownloadPreferences(); return }",
        "try AppWidePreferenceController.shared.update { $0.downloadDirectory = url.path; $0.promptForDownload = false }\n"
        "                self.refreshDownloadPreferences()\n"
        "            } catch { self.reportDownloadPreferenceError(error) }",
        "panel?.cancel(nil)\n        if panel != nil { renderDownloadLocation() }",
        "if selectedPane != pane {\n            cancelDownloadFolderSelection()",
        "guard let self, self.downloadPreferencesGeneration == generation,"):
    assert use in settings, f"SettingsWindow no longer wires the picker as checked: {use}"
for gone in ("downloadPrompt", "downloadChoose", "Ask where to save each file", "Change download folder",
             "downloadLocation.stringValue"):
    assert gone not in settings, f"SettingsWindow still carries the former checkbox/button: {gone}"

with tempfile.TemporaryDirectory(prefix="parc-download-location-") as directory:
    temporary = pathlib.Path(directory)
    controls = temporary / "NativeControls.swift"
    controls.write_text(sidebar[:sidebar.index("final class FlippedStackView:")]
        + "\nenum SplitOrientation: Equatable { case horizontal, vertical }\n")
    (temporary / "DownloadsCard.swift").write_text(harness)
    sources = [controls, temporary / "DownloadsCard.swift", root / "Sources/ParcApp/DownloadLocationPicker.swift",
               root / "Sources/ParcApp/MenuItemImage.swift",
               root / "Sources/ParcApp/TranslucentButtonFace.swift", root / "Sources/ParcApp/PointerCover.swift", root / "Sources/ParcApp/ReloadControl.swift",
               root / "Sources/ParcApp/PointingHand.swift", root / "Sources/ParcApp/SettingsHoverButton.swift",
               root / "Sources/ParcApp/SettingsPresentation.swift",
               root / "tests/DownloadLocation/PickerTests.swift"]
    executable = temporary / "download-location-picker"
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-whole-module-optimization", "-parse-as-library",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable), *sys.argv[1:2]], check=True)
print("Download location wiring: source checks passed")
