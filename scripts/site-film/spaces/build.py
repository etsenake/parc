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
sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + extracted
sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift", root / "tests/SpaceManager/NativeHostStub.swift",
            root / "tests/Support/TestFailure.swift"]
sources += sorted(here.glob("Harness/*.swift"))
command = ["xcrun", "swiftc", "-parse-as-library", "-Onone",
           *map(str, sources), "-o", str(here / "render")]
(here / "compile-command.txt").write_text(" ".join(command) + "\n")
subprocess.run(command, check=True)
print("built", here / "render")
