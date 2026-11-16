#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/NoteStore.swift" \
  "$repo_root/Sources/ParcCore/NoteExportArchive.swift" \
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
  "$repo_root/Sources/ParcApp/NoteHTMLExport.swift" \
  "$repo_root/tests/Notes/ExportTests.swift" -o "$temporary/note-export"
"$temporary/note-export"
