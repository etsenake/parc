#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
core=("$repo_root/Sources/ParcCore/EaselStore.swift" "$repo_root/Sources/ParcCore/EaselRichText.swift" "$repo_root/Sources/ParcCore/NoteStore.swift")
xcrun swiftc -parse-as-library "${core[@]}" "$repo_root/tests/Support/FileObservation.swift" "$repo_root/tests/NoteStoreTests.swift" -o "$repo_root/build/tests/note-store"
"$repo_root/build/tests/note-store"
# Native editor components only; no browser or visible window. Paste uses a private board.
xcrun swiftc -parse-as-library "${core[@]}" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/NoteKeyboardEditing.swift" \
  "$repo_root/Sources/ParcApp/NoteDocumentPresentation.swift" \
  "$repo_root/Sources/ParcApp/NoteImageImport.swift" \
  "$repo_root/Sources/ParcApp/NoteAccessibility.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatting.swift" \
  "$repo_root/Sources/ParcApp/NoteSelectionFormatting.swift" \
  "$repo_root/Sources/ParcApp/NoteMotion.swift" \
  "$repo_root/Sources/ParcApp/NoteEditorViewController.swift" \
  "$repo_root/tests/Support/AppKitObservation.swift" "$repo_root/tests/Support/FileObservation.swift" \
  "$repo_root/tests/NoteEditorTests.swift" -o "$repo_root/build/tests/note-editor"
# An unbundled executable's Bundle.main.resourceURL is its own directory.
rm -rf "$repo_root/build/tests/CustomInfoPicker"
cp -R "$repo_root/Resources/CustomInfoPicker" "$repo_root/build/tests/CustomInfoPicker"
"$repo_root/build/tests/note-editor" "$repo_root/Resources/NoteFonts/Nunito-ExtraBold.ttf"

# Final close must recheck a draft changed during another page's consent.
xcrun swiftc -parse-as-library "${core[@]}" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/NoteKeyboardEditing.swift" \
  "$repo_root/Sources/ParcApp/NoteDocumentPresentation.swift" \
  "$repo_root/Sources/ParcApp/NoteImageImport.swift" \
  "$repo_root/Sources/ParcApp/NoteAccessibility.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatting.swift" \
  "$repo_root/Sources/ParcApp/NoteSelectionFormatting.swift" \
  "$repo_root/Sources/ParcApp/NoteMotion.swift" \
  "$repo_root/Sources/ParcApp/NoteEditorViewController.swift" \
  "$repo_root/tests/Notes/RetirementTests.swift" -o "$repo_root/build/tests/note-retirement"
"$repo_root/build/tests/note-retirement" "$repo_root/Resources/NoteFonts/Nunito-ExtraBold.ttf"

xcrun swiftc -parse-as-library "$repo_root"/Sources/ParcCore/*.swift \
  "$repo_root/tests/NoteTabTests.swift" -o "$repo_root/build/tests/note-tabs"
"$repo_root/build/tests/note-tabs"
