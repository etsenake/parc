#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/parc-easel-motion.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$scratch/easel-spinner.swift" ParcButtonSpinner)
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselMotionTests.swift" \
  -o "$scratch/easel-motion"
"$scratch/easel-motion"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselCanvasInteraction.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvasView.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselMotionCanvasTests.swift" \
  -o "$scratch/easel-motion-canvas"
"$scratch/easel-motion-canvas"
