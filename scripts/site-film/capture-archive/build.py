import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).resolve().parents[3])).resolve()
here = Path(__file__).resolve().parent
gen = here / "gen"
gen.mkdir(exist_ok=True)
for stale in ["DownloadLibraryView.swift", "DownloadFileActivation.swift"]:
    (gen / stale).unlink(missing_ok=True)
app = root / "Sources/ParcApp"
check = (root / "tests/SpaceManager/check.py").read_text()
names = re.search(r'names = """(.*?)"""', check, re.S).group(1).splitlines()
excerpts = [
    ("SidebarPreviewController.swift", None, "struct SidebarPreviewRow: Equatable {", ""),
    ("NavigationControls.swift", None, "enum NavigationHistoryMenuMetrics", ""),
    ("SiteControlCenter.swift", None, "enum SiteControlCenterMetrics", ""),
    ("OnboardingProgressionButton.swift", "struct ParcButtonSpinner", "extension NSColor", "import SwiftUI\n"),
]
extracted = []
for name, start, end, prefix in excerpts:
    text = (app / name).read_text()
    path = gen / name
    path.write_text(prefix + text[text.index(start) if start else 0:text.index(end)])
    extracted.append(path)

def write(name, text):
    path = gen / name
    path.write_text(text)
    extracted.append(path)

access = here / "Access"
controller = (app / "PageCaptureController.swift").read_text()
overlay = controller.split("@MainActor\nfinal class PageCaptureOverlay:")[1]
write("PageCaptureOverlay.swift", "import AppKit\nimport QuartzCore\nclass PCNativePageCaptureTarget {}\n@MainActor\nfinal class PageCaptureOverlay:"
      + overlay + "\n" + (access / "Overlay.swift").read_text())
write("LibraryView.swift", (app / "LibraryView.swift").read_text() + "\n" + (access / "Library.swift").read_text())
write("PortraitCapture.swift", (app / "PortraitCapture.swift").read_text() + "\n" + (access / "Portrait.swift").read_text())
toast = (app / "ParcToast.swift").read_text()
assert toast.count("            ParcToastMaterial()\n") == 1
write("ParcToast.swift", toast.replace("            ParcToastMaterial()\n", "            Color(white: 0.92)\n"))
easel = (app / "EaselEditorViewController.swift").read_text()
write("PortraitDesktopSnapshot.swift", "import AppKit\n@MainActor\nenum PortraitDesktopSnapshot {\n    static func capture(screen: NSScreen?) async throws -> NSImage { throw CancellationError() }\n}\n")
write("EaselStoreOwner.swift", easel[:easel.index("    let session: EaselSession")] + "}\n")

extra = ["CaptureLibraryView", "DocumentsLibraryView", "DocumentsLibraryCatalog", "DocumentDefaultIcon", "DownloadLibraryTable", "DownloadLibraryView", "DownloadThumbnailProvider",
         "ExternalMediaLibrary", "CaptureLibrarySharing", "MediaLibraryContext", "CaptureMotion", "DownloadArrivalMotion",
         "LibraryRailTile", "LibraryRailIcon", "TopBarColorClient", "CapturePresentation", "ParcBrandMark",
         "CapturedImage", "PeekWindowLayout", "PeekControls", "CapturePaletteView", "CaptureModeBar", "NoteTheme", "NoteAnimation",
         "NoteFloatingPanel", "NoteControls", "NoteCustomEmojiImages"]
sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + [app / f"{n}.swift" for n in extra if f"{n}.swift" not in names] + extracted
sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift", root / "tests/SpaceManager/NativeHostStub.swift",
            root / "tests/Support/TestFailure.swift"]
sources += sorted(here.glob("Harness/*.swift"))
command = ["xcrun", "swiftc", "-parse-as-library", "-Onone",
           *map(str, sources), "-o", str(here / "render")]
(here / "compile-command.txt").write_text(" ".join(command) + "\n")
subprocess.run(command, check=True)
print("built", here / "render")
