import AppKit

extension EaselCanvasView {
    private func checklistTarget(at point: NSPoint, item: EaselItem) -> (item: EaselChecklistText.Item, layout: EaselTextLayout.Layout, origin: NSPoint)? {
        let layout = cachedTextLayout(for: item)
        let placed = EaselTextPlacement.origin(for: item, textHeight: Double(layout.height), overflowing: false)
        let origin = NSPoint(x: placed.x + layout.inset.width, y: placed.y + layout.inset.height)
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let found = EaselChecklistText.item(at: local, manager: layout.manager, storage: layout.storage) else { return nil }
        return (found, layout, origin)
    }

    private func restingChecklist(_ item: EaselItem) -> Bool {
        item.kind.holdsText && item.kind != .arrow && !item.isLocked && editingID != item.id && (item.rotation ?? 0) == 0
            && item.flipHorizontal != true && item.flipVertical != true && EaselChecklistText.hasChecklist(item.richText)
    }

    func checklistPress(at point: NSPoint) -> Bool {
        guard !session.isClosed, !viewOnly, let hit = object(at: point), restingChecklist(hit),
              let target = checklistTarget(at: point, item: hit) else { return false }
        let authored = EaselRichTextCodec.attributed(hit)
        let markerLocation = target.item.markerCharacter.location
        guard let toggle = EaselParagraphEditing.toggleChecklist(authored, selections: [NSRange(location: markerLocation, length: 0)], typing: [:]),
              let rich = try? EaselRichTextCodec.snapshot(toggle.edit.text) else { return false }
        let text = toggle.edit.text.string
        let saved = commit(toggle.checked ? "Tick item" : "Untick item") { document in
            guard let index = document.items.firstIndex(where: { $0.id == hit.id }) else { return }
            document.items[index].text = text
            document.items[index].richText = rich
        }
        guard saved else { return true }
        window?.invalidateCursorRects(for: self)
        guard toggle.checked, let updated = session.document.items.first(where: { $0.id == hit.id }) else { return true }
        let layout = cachedTextLayout(for: updated)
        guard let manager = layout.manager as? EaselChecklistLayoutManager,
              let entry = EaselChecklistText.items(in: layout.storage, range: NSRange(location: markerLocation, length: 1)).first,
              let box = manager.boxRect(for: entry) else { return true }
        EaselChecklistText.pop(in: self, rect: box.offsetBy(dx: target.origin.x, dy: target.origin.y), manager: manager, marker: markerLocation)
        return true
    }

    func addChecklistCursorRects() {
        guard !drawing else { return }
        for item in items where restingChecklist(item) {
            let layout = cachedTextLayout(for: item)
            guard let manager = layout.manager as? EaselChecklistLayoutManager else { continue }
            let placed = EaselTextPlacement.origin(for: item, textHeight: Double(layout.height), overflowing: false)
            let origin = NSPoint(x: placed.x + layout.inset.width, y: placed.y + layout.inset.height)
            for entry in EaselChecklistText.items(in: layout.storage, range: NSRange(location: 0, length: layout.storage.length)) where entry.marker.isItem {
                guard let box = manager.boxRect(for: entry) else { continue }
                addCursorRect(box.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -4, dy: -4), cursor: .pointingHand)
            }
        }
    }
}
