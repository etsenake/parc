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
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
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
  "$repo_root/Sources/ParcApp/EaselCanvas"*.swift \
  "$repo_root/Sources/ParcApp/EaselDocumentExport.swift" \
  "$repo_root/Sources/ParcApp/EaselTableExport.swift" \
  "$repo_root/Sources/ParcApp/EaselShapePicker.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/NoteFloatingPanel.swift" \
  "$repo_root/Sources/ParcApp/NoteControls.swift" \
  "$repo_root/Sources/ParcApp/NoteCustomEmojiImages.swift" \
  "$repo_root/Sources/ParcApp/DocumentDefaultIcon.swift" \
  "$repo_root/Sources/ParcApp/LibraryArtwork.swift" \
  "$repo_root/tests/NotesEditor/NoteDesignSystemStubs.swift" \
  "$repo_root/Sources/ParcApp/EaselStampArtwork.swift" \
  "$repo_root/Sources/ParcApp/SidebarIconCatalog.swift" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/EaselImageExport.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselMotionCanvasTests.swift" \
  -o "$scratch/easel-motion-canvas"
"$scratch/easel-motion-canvas"
