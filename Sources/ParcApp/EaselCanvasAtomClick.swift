import AppKit

extension EaselCanvasView {
    private var atomClickEditable: Bool {
        !session.isClosed && !session.isDeleted && !viewOnly && !isCaptureBoard && !isDocumentLocked && editor == nil
    }

    private func atomClickItem(clickCount: Int, plain: Bool) -> EaselItem? {
        guard atomClickEditable, selection.count == 1,
              let item = items.first(where: { selection.contains($0.id) }),
              EaselAtomClick.allowsClick(on: item, selection: selection, editable: true, clickCount: clickCount, plain: plain) else { return nil }
        return item
    }

    func atomHit(at point: NSPoint, clickCount: Int = 1, plain: Bool = true) -> EaselAtomHit? {
        guard let item = atomClickItem(clickCount: clickCount, plain: plain), item.kind == .arrow || object(at: point)?.id == item.id,
              let text = restingText(item, at: point) else { return nil }
        return EaselLinkHitTest.atom(at: point, manager: text.manager, container: text.container, storage: text.storage,
                                     origin: text.origin, itemID: item.id)
    }

    func atomPress(at point: NSPoint, event: NSEvent) -> Bool {
        let plain = event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty
        guard resizeHandle(at: point) == nil, let hit = atomHit(at: point, clickCount: event.clickCount, plain: plain),
              let item = items.first(where: { $0.id == hit.itemID }) else { return false }
        if item.kind == .arrow { beginConnectorLabelEditing(item, at: nil) } else { beginEditing(item) }
        guard let editor, editingID == item.id else { return true }
        editor.setSelectedRange(NSRange(location: min(hit.index + 1, (editor.string as NSString).length), length: 0))
        _ = editor.completion?.perform(.activate(hit.index), in: editor)
        return true
    }

    func addAtomCursorRects() {
        guard !drawing, let item = atomClickItem(clickCount: 1, plain: true), let text = restingText(item, at: nil) else { return }
        let length = text.storage.length
        text.storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { object, range, _ in
            guard let inline = (object as? EaselInlineAttachment)?.inline, EaselAtomClick.opens(inline.kind) else { return }
            let glyphs = text.manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let box = text.manager.boundingRect(forGlyphRange: glyphs, in: text.container)
            guard box.width.isFinite, box.height.isFinite, box.width > 0 else { return }
            addCursorRect(box.offsetBy(dx: text.origin.x, dy: text.origin.y), cursor: .pointingHand)
        }
    }
}
