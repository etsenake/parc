import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[3])).resolve()
here = Path(__file__).resolve().parent
gen = here / "gen"
gen.mkdir(exist_ok=True)
app = root / "Sources/ParcApp"
check = (root / "tests/SpaceManager/check.py").read_text()
names = re.search(r'names = """(.*?)"""', check, re.S).group(1).splitlines()
excerpts = [
    ("SidebarPreviewController.swift", None, "struct SidebarPreviewRow: Equatable {", ""),
    ("NavigationControls.swift", None, "enum NavigationHistoryMenuMetrics", ""),
    ("SiteControlCenter.swift", None, "enum SiteControlCenterMetrics", ""),
    ("DownloadLibraryView.swift", "@MainActor enum DownloadRowSubtitle", "@MainActor enum DownloadRowArtwork {", "import AppKit\nimport UniformTypeIdentifiers\n"),
    ("OnboardingProgressionButton.swift", "struct ParcButtonSpinner", "extension NSColor", "import SwiftUI\n"),
    ("EaselPageSwitcher.swift", None, "@MainActor\nfinal class EaselPageSwitcher {", ""),
    ("EaselTimer.swift", None, "@MainActor\nfinal class EaselTimerView", ""),
]
extracted = []
for name, start, end, prefix in excerpts:
    text = (app / name).read_text()
    path = gen / name
    path.write_text(prefix + text[text.index(start) if start else 0:text.index(end)])
    extracted.append(path)
text = (app / "DownloadLibraryView.swift").read_text()
path = gen / "DownloadFileActivation.swift"
path.write_text("import AppKit\nimport UniformTypeIdentifiers\n" + text[text.index("enum DownloadFileActivation"):])
extracted.append(path)
motion = (app / "EaselCanvasView+ObjectMotion.swift").read_text()
gate = "window != nil && !isHiddenOrHasHiddenAncestor && canPresentMotion"
assert gate in motion
path = gen / "EaselCanvasView+ObjectMotion.swift"
path.write_text(motion.replace(gate, "!isHiddenOrHasHiddenAncestor && canPresentMotion"))
extracted.append(path)
sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + extracted
sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift", root / "tests/SpaceManager/NativeHostStub.swift",
            root / "tests/Support/TestFailure.swift"]
sources += [app / name for name in ["CommandResultRowView.swift", "CommandResultCell.swift", "CommandBarAppearance.swift",
    "PopoverBackgroundView.swift", "LocalContentDrop.swift", "NoteTheme.swift", "EaselAppearance.swift", "EaselTextStyle.swift", "TextFormatMenu.swift",
    "EaselRichTextCodec.swift", "EaselTextHighlight.swift", "NoteFormatShortcut.swift", "EaselTextAttachment.swift", "EaselParagraphEditing.swift", "EaselMarkdownEditing.swift",
    "WebpageEditCommands.swift", "EaselMotion.swift", "EaselDocumentExport.swift", "EaselTableExport.swift", "EaselDocumentExport+Connectors.swift", "EaselStickyText.swift", "EaselTooltip.swift", 
    "EaselShapePicker.swift", "NoteAnimation.swift", "NoteFloatingPanel.swift", "NoteControls.swift", "NoteCustomEmojiImages.swift", "DocumentDefaultIcon.swift", "LibraryArtwork.swift", "EaselStampArtwork.swift", "SidebarIconCatalog.swift", "MenuItemImage.swift", "ParcBrandMark.swift", "EaselImageExport.swift", "NoteCursor.swift", "EaselToolPalette.swift", "NotePageChromeControls.swift"] if name not in names]
sources += [path for path in sorted(app.glob("EaselCanvas*.swift")) if path.name not in names and path.name != "EaselCanvasView+ObjectMotion.swift"]
sources += sorted(here.glob("Harness/*.swift"))
command = ["xcrun", "swiftc", "-parse-as-library", "-Onone",
           *map(str, sources), "-o", str(here / "render")]
(here / "compile-command.txt").write_text(" ".join(command) + "\n")
subprocess.run(command, check=True)
print("built", here / "render")
