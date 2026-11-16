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
mini = (app / "MiniPlayerView.swift").read_text()
lease = "init(_ window: NSWindow) { self.window = window }"
assert lease in mini
(gen / "MiniPlayerView.swift").write_text(mini.replace(lease, "init(_ window: NSWindow?) { self.window = window }"))
stub = (root / "tests/SpaceManager/NativeHostStub.swift").read_text()
start = stub.index("@MainActor final class PCNativeMediaState {")
end = stub.index("@MainActor final class PCNativePage {")
media = """@MainActor final class PCNativeMediaState {
    let identifier: String
    var title = "Song", sourceURL = "https://example.test/"
    var playing = true, canPlayPause = true, hasPreviousTrack = true, hasNextTrack = true, muted = false
    var volume = 1.0, canSetVolume = true, canToggleMicrophone = false, canToggleCamera = false
    var microphoneOn = false, cameraOn = false, canEnterPictureInPicture = true
    var airPlayState = PCNativeAirPlayState.unavailable, airPlayDeviceName: String? = nil
    var castState = PCNativeCastState.unavailable, castDeviceName: String? = nil
    init(identifier: String) { self.identifier = identifier }
}
"""
(gen / "NativeHostStub.swift").write_text(stub[:start] + media + stub[end:])
names = [name for name in names if name != "MiniPlayerView.swift"]
sources = sorted((root / "Sources/ParcCore").glob("*.swift")) + [app / name for name in names] + extracted
sources += [gen / "MiniPlayerView.swift", app / "MembershipCardView.swift"]
sources += [root / "tests/KeyboardNavigation/NativeShortcutStub.swift", gen / "NativeHostStub.swift",
            root / "tests/Support/TestFailure.swift"]
sources += sorted(here.glob("Harness/*.swift"))
command = ["xcrun", "swiftc", "-parse-as-library", "-Onone",
           *map(str, sources), "-o", str(here / "render")]
(here / "compile-command.txt").write_text(" ".join(command) + "\n")
subprocess.run(command, check=True)
print("built", here / "render")
