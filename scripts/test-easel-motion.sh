#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$repo_root/build/tests/easel-spinner.swift" PArcButtonSpinner)
xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselMotionTests.swift" \
  -o "$repo_root/build/tests/easel-motion"
"$repo_root/build/tests/easel-motion"

xcrun swiftc -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselCanvasInteraction.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvasView.swift" \
  "$repo_root/Sources/ParcApp/PArcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselMotionCanvasTests.swift" \
  -o "$repo_root/build/tests/easel-motion-canvas"
"$repo_root/build/tests/easel-motion-canvas"
