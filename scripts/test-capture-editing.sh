#!/bin/bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
check_root=$(mktemp -d "${TMPDIR:-/tmp}/parc-capture-edit.XXXXXX")
trap 'rm -rf "$check_root"' EXIT
spinner=$(python3 -B "$repo_root/tests/Support/declarations.py" "$check_root/ParcButtonSpinner.swift" ParcButtonSpinner)
cat > "$check_root/EaselShapePickerStub.swift" <<'SWIFT'
import AppKit
@MainActor final class EaselShapePickerView: NSView {
    var onPick: ((EaselShape) -> Void)?
    var checked: Set<EaselShape>
    init(checked: Set<EaselShape> = [], pinned: Bool = false, showsPin: Bool = true) {
        self.checked = checked
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
}
SWIFT
cat > "$check_root/EaselTooltipStub.swift" <<'SWIFT'
import AppKit
extension NSView {
    func setEaselTooltip(_ title: String, shortcut: String? = nil) { toolTip = title }
}
SWIFT
xcrun swiftc "$repo_root/tests/Support/TestFailure.swift" -warnings-as-errors -parse-as-library \
  "$repo_root/Sources/ParcCore/"*.swift \
  "$repo_root/Sources/ParcApp/NoteTheme.swift" \
  "$repo_root/Sources/ParcApp/NoteAnimation.swift" \
  "$repo_root/Sources/ParcApp/NoteControls.swift" \
  "$repo_root/Sources/ParcApp/NoteMathFont.swift" \
  "$repo_root/Sources/ParcApp/NoteMathLayout.swift" \
  "$repo_root/Sources/ParcApp/NoteMathRenderer.swift" \
  "$repo_root/Sources/ParcApp/NoteEquationArtwork.swift" \
  "$repo_root/Sources/ParcApp/NoteCodeFont.swift" \
  "$repo_root/Sources/ParcApp/LocalContentDrop.swift" \
  "$repo_root/Sources/ParcApp/EaselAppearance.swift" \
  "$repo_root/Sources/ParcApp/PointingHand.swift" \
  "$repo_root/Sources/ParcApp/PointerCover.swift" \
  "$repo_root/Sources/ParcApp/EaselTextStyle.swift" \
  "$repo_root/Sources/ParcApp/NoteClipboardReading.swift" \
  "$repo_root/Sources/ParcApp/EaselClipboardText.swift" \
  "$repo_root/Sources/ParcApp/EaselStickyText.swift" \
  "$repo_root/Sources/ParcApp/TextFormatMenu.swift" \
  "$repo_root/Sources/ParcApp/EaselRichTextCodec.swift" \
  "$repo_root/Sources/ParcApp/EaselInlineText.swift" \
  "$repo_root/Sources/ParcApp/NoteTextAttachments.swift" \
  "$repo_root/Sources/ParcApp/NoteFloatingPanel.swift" \
  "$repo_root/Sources/ParcApp/DocumentDefaultIcon.swift" \
  "$repo_root/Sources/ParcApp/LibraryArtwork.swift" \
  "$repo_root/Sources/ParcApp/SidebarIconCatalog.swift" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/ParcBrandMark.swift" \
  "$repo_root/tests/NotesEditor/NoteDesignSystemStubs.swift" \
  "$repo_root/Sources/ParcApp/EaselTextHighlight.swift" \
  "$repo_root/Sources/ParcApp/NoteFormatShortcut.swift" \
  "$repo_root/Sources/ParcApp/EaselTextAttachment.swift" \
  "$repo_root/Sources/ParcApp/EaselParagraphEditing.swift" \
  "$repo_root/Sources/ParcApp/EaselMarkdownEditing.swift" \
  "$repo_root/Sources/ParcApp/WebpageEditCommands.swift" \
  "$repo_root/Sources/ParcApp/EaselCanvas"*.swift \
  "$repo_root/Sources/ParcApp/NoteCustomEmojiImages.swift" \
  "$repo_root/Sources/ParcApp/EaselStampArtwork.swift" "$check_root/EaselShapePickerStub.swift" "$check_root/EaselTooltipStub.swift" \
  "$repo_root/Sources/ParcApp/ParcDialog.swift" "$spinner" \
  "$repo_root/Sources/ParcApp/MenuItemImage.swift" \
  "$repo_root/Sources/ParcApp/EaselMotion.swift" \
  "$repo_root/Sources/ParcApp/CaptureLibrarySharing.swift" \
  "$repo_root/tests/CaptureEditingTests.swift" -o "$check_root/capture-editing"
"$check_root/capture-editing"
