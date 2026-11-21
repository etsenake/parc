#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/parc-easels.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$scratch/easel-spinner.swift" ParcButtonSpinner)
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselCanvasInteraction.swift" \
  "$repo_root/Sources/ParcCore/EaselShapeGeometry.swift" \
  "$repo_root/Sources/ParcCore/EaselTransform.swift" \
  "$repo_root/Sources/ParcCore/EaselWebNavigation.swift" \
  "$repo_root/Sources/ParcCore/EaselMediaPlacement.swift" \
  "$repo_root/tests/Support/FileObservation.swift" \
  "$repo_root/tests/EaselStoreTests.swift" \
  -o "$scratch/easel-store"
"$scratch/easel-store"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselWebItemChrome.swift" \
  "$repo_root/tests/EaselWebItemChromeTests.swift" \
  -o "$scratch/easel-web-item-chrome"
"$scratch/easel-web-item-chrome"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselLiveCaptureFraming.swift" \
  "$repo_root/tests/EaselLiveCaptureFramingTests.swift" \
  -o "$scratch/easel-live-capture-framing"
"$scratch/easel-live-capture-framing"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselVectorExportTests.swift" \
  -o "$scratch/easel-vector-export"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselDrawingTests.swift" \
  -o "$scratch/easel-drawing"
"$scratch/easel-drawing"
"$scratch/easel-vector-export"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselMediaImportTests.swift" \
  -o "$scratch/easel-media-import"
"$scratch/easel-media-import"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselRoundTripTests.swift" \
  -o "$scratch/easel-round-trip"
"$scratch/easel-round-trip"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselPagesTests.swift" \
  -o "$scratch/easel-pages"
"$scratch/easel-pages"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselImageFramingTests.swift" \
  -o "$scratch/easel-image-framing"
"$scratch/easel-image-framing"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselCodeBlockTests.swift" \
  -o "$scratch/easel-code-blocks"
"$scratch/easel-code-blocks"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselMindMapTests.swift" \
  -o "$scratch/easel-mind-maps"
"$scratch/easel-mind-maps"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/tests/EaselCrashHardeningTests.swift" \
  -o "$scratch/easel-crash-hardening"
"$scratch/easel-crash-hardening"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvasControlMotion.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvasCodeBlockViews.swift" \
  "$repo_root/tests/EaselCodeBlockStyleTests.swift" \
  -o "$scratch/easel-code-block-style"
"$scratch/easel-code-block-style"

style_bundle="$scratch/EaselTextStyle.app/Contents"
mkdir -p "$style_bundle/MacOS" "$style_bundle/Resources/EaselFonts" "$style_bundle/Resources/AppIcons/Marks"
cp "$repo_root/Resources/EaselFonts/"*.ttf "$style_bundle/Resources/EaselFonts/"
cp "$repo_root/Resources/AppIcons/Marks/"*.png "$style_bundle/Resources/AppIcons/Marks/"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextHighlight.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatShortcut.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/tests/EaselTextStyleTests.swift" \
  -o "$style_bundle/MacOS/EaselTextStyle"
"$style_bundle/MacOS/EaselTextStyle"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextHighlight.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatShortcut.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvas"*.swift \
  "$repo_root/Sources/ParcApp/EaselDocumentExport.swift" \
  "$repo_root/Sources/ParcApp/EaselTableExport.swift" \
  "$repo_root/Sources/ParcApp/EaselDocumentExport+Connectors.swift" \
  "$repo_root/Sources/ParcApp/EaselStickyText.swift" \
  "$repo_root/Sources/ParcApp/EaselTooltip.swift" \
  "$repo_root/Sources/ParcApp/EaselShapePicker.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/NoteFloatingPanel.swift" \
  "$repo_root/Sources/ParcApp/NoteControls.swift" \
  "$repo_root/Sources/ParcApp/NoteCustomEmojiImages.swift" \
  "$repo_root/Sources/ParcApp/DocumentDefaultIcon.swift" \
  "$repo_root/Sources/ParcApp/LibraryArtwork.swift" \
  "$repo_root/tests/NotesEditor/NoteDesignSystemStubs.swift" \
  "$repo_root/Sources/ParcApp/SidebarIconCatalog.swift" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/EaselImageExport.swift" \
  "$repo_root/Sources/ParcApp/EaselStampArtwork.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/tests/EaselCanvasTests.swift" \
  -o "$style_bundle/MacOS/EaselCanvas"
"$style_bundle/MacOS/EaselCanvas"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextHighlight.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatShortcut.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvas"*.swift \
  "$repo_root/Sources/ParcApp/EaselDocumentExport.swift" \
  "$repo_root/Sources/ParcApp/EaselTableExport.swift" \
  "$repo_root/Sources/ParcApp/EaselDocumentExport+Connectors.swift" \
  "$repo_root/Sources/ParcApp/EaselStickyText.swift" \
  "$repo_root/Sources/ParcApp/EaselTooltip.swift" \
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
  "$repo_root/tests/EaselSelectionToolbarCanvasTests.swift" \
  -o "$style_bundle/MacOS/EaselSelectionToolbarCanvas"
"$style_bundle/MacOS/EaselSelectionToolbarCanvas"

mkdir -p "$style_bundle/Resources/CustomInfoPicker" "$style_bundle/Resources/AppIcons/Marks"
cp "$repo_root/Resources/CustomInfoPicker/feather.ttf" "$style_bundle/Resources/CustomInfoPicker/"
cp "$repo_root/Resources/AppIcons/Marks/Borderless.png" "$style_bundle/Resources/AppIcons/Marks/"
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselTextHighlight.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatShortcut.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvas"*.swift \
  "$repo_root/Sources/ParcApp/EaselDocumentExport.swift" \
  "$repo_root/Sources/ParcApp/EaselTableExport.swift" \
  "$repo_root/Sources/ParcApp/EaselDocumentExport+Connectors.swift" \
  "$repo_root/Sources/ParcApp/EaselStickyText.swift" \
  "$repo_root/Sources/ParcApp/EaselTooltip.swift" \
  "$repo_root/Sources/ParcApp/EaselShapePicker.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/NoteFloatingPanel.swift" \
  "$repo_root/Sources/ParcApp/NoteControls.swift" \
  "$repo_root/Sources/ParcApp/NoteCustomEmojiImages.swift" \
  "$repo_root/Sources/ParcApp/DocumentDefaultIcon.swift" \
  "$repo_root/Sources/ParcApp/LibraryArtwork.swift" \
  "$repo_root/tests/NotesEditor/NoteDesignSystemStubs.swift" \
  "$repo_root/Sources/ParcApp/EaselStampArtwork.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/Sources/ParcApp/SidebarIconCatalog.swift" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/EaselImageExport.swift" \
  "$repo_root/tests/EaselImageExportTests.swift" \
  -o "$style_bundle/MacOS/EaselImageExport"
"$style_bundle/MacOS/EaselImageExport"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselPageModel.swift" \
  "$repo_root/Sources/ParcCore/EaselTable.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/CaptureDestinations.swift" \
  "$repo_root/Sources/ParcApp/EaselImagePlacement.swift" \
  "$repo_root/Sources/ParcApp/CaptureMessageSharing.swift" \
  "$repo_root/tests/CaptureDestinationTests.swift" \
  -o "$scratch/capture-destinations"
"$scratch/capture-destinations"

xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvasControlMotion.swift" \
  "$repo_root/Sources/ParcApp/EaselWebInput.swift" \
  "$repo_root/Sources/ParcApp/SavedFocus.swift" \
  "$repo_root/tests/EaselWebInputTests.swift" \
  -o "$scratch/easel-web-input"
"$scratch/easel-web-input"
