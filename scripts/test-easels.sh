#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$repo_root/build/tests"
#
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$repo_root/build/tests/easel-spinner.swift" PArcButtonSpinner)
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/EaselCanvasInteraction.swift" \
  "$repo_root/Sources/ParcCore/EaselWebNavigation.swift" \
  "$repo_root/tests/Support/FileObservation.swift" \
  "$repo_root/tests/EaselStoreTests.swift" \
  -o "$repo_root/build/tests/easel-store"
"$repo_root/build/tests/easel-store"

# A private app-shaped resource directory exercises bundled font resolution.
# The component check uses its own named pasteboard, never the user's clipboard.
style_bundle="$repo_root/build/tests/EaselTextStyle.app/Contents"
mkdir -p "$style_bundle/MacOS" "$style_bundle/Resources/EaselFonts"
cp "$repo_root/Resources/EaselFonts/"*.ttf "$style_bundle/Resources/EaselFonts/"
xcrun swiftc -parse-as-library \
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
  "$repo_root/tests/EaselTextStyleTests.swift" \
  -o "$style_bundle/MacOS/EaselTextStyle"
"$style_bundle/MacOS/EaselTextStyle"

# Exercise actual native selection/move/menu owners without displaying a window.
xcrun swiftc -parse-as-library \
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
  "$repo_root/tests/EaselCanvasTests.swift" \
  -o "$style_bundle/MacOS/EaselCanvas"
"$style_bundle/MacOS/EaselCanvas"

# Export as Image: the actual canvas export render, Share menu row, panel
# configuration and encoders. Nothing is displayed and no panel runs.
mkdir -p "$style_bundle/Resources/CustomInfoPicker" "$style_bundle/Resources/AppIcons/Marks"
cp "$repo_root/Resources/CustomInfoPicker/icomoon.ttf" "$style_bundle/Resources/CustomInfoPicker/"
cp "$repo_root/Resources/AppIcons/Marks/Borderless.png" "$style_bundle/Resources/AppIcons/Marks/"
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
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
  "$repo_root/Sources/ParcApp/SidebarIconCatalog.swift" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/Sources/ParcApp/EaselImageExport.swift" \
  "$repo_root/tests/EaselImageExportTests.swift" \
  -o "$style_bundle/MacOS/EaselImageExport"
"$style_bundle/MacOS/EaselImageExport"

# Real captured-card/image import, durable provenance and shared-session undo.
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselStore.swift" \
  "$repo_root/Sources/ParcCore/EaselRichText.swift" \
  "$repo_root/Sources/ParcCore/CaptureDestinations.swift" \
  "$repo_root/Sources/ParcApp/EaselImagePlacement.swift" \
  "$repo_root/Sources/ParcApp/CaptureMessageSharing.swift" \
  "$repo_root/tests/CaptureDestinationTests.swift" \
  -o "$repo_root/build/tests/capture-destinations"
"$repo_root/build/tests/capture-destinations"

# The actual address/search native editor: cancellation and IME in a hidden component.
xcrun swiftc -parse-as-library \
  "$repo_root/Sources/ParcCore/EaselWebNavigation.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/EaselWebInput.swift" \
  "$repo_root/Sources/ParcApp/SavedFocus.swift" \
  "$repo_root/tests/EaselWebInputTests.swift" \
  -o "$repo_root/build/tests/easel-web-input"
"$repo_root/build/tests/easel-web-input"
