#!/bin/bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-motion.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
python3 - "$repo_root" "$check_root/Components.swift" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
shared = (root / 'Sources/ParcApp/SidebarView.swift').read_text().split('final class FlippedStackView')[0]
overlay = (root / 'Sources/ParcApp/PageCaptureController.swift').read_text().split('@MainActor\nfinal class PageCaptureOverlay:')[1]
pathlib.Path(sys.argv[2]).write_text(
    'enum SplitOrientation: String { case horizontal, vertical }\n'
    + shared
    + '\nclass PCNativePageCaptureTarget {}\nstruct EaselSummary { let id: UUID; let title: String }\n@MainActor\nfinal class PageCaptureOverlay:'
    + overlay
)
PY
xcrun swiftc -warnings-as-errors -parse-as-library -target arm64-apple-macos13.0 \
  "$check_root/Components.swift" "$repo_root/Sources/ParcCore/CaptureDestinations.swift" \
  "$repo_root/Sources/ParcApp/CapturePresentation.swift" "$repo_root/Sources/ParcApp/CaptureMotion.swift" \
  "$repo_root/Sources/ParcApp/DownloadArrivalMotion.swift" "$repo_root/Sources/ParcApp/DownloadLibraryPreview.swift" \
  "$repo_root/Sources/ParcApp/TranslucentButtonFace.swift" "$repo_root/Sources/ParcApp/PointerCover.swift" "$repo_root/Sources/ParcApp/ReloadControl.swift" "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/tests/Support/AppKitObservation.swift" "$repo_root/tests/CaptureMotion/main.swift" \
  -o "$check_root/CaptureMotionChecks"
"$check_root/CaptureMotionChecks"
