import AppKit

struct EaselLinkHit: Equatable {
    var itemID: UUID
    var range: NSRange
    var link: String
    var rect: NSRect

    var key: String { "\(itemID.uuidString)-\(range.location)-\(range.length)-\(link)" }
}

enum EaselLinkHitTest {
    @MainActor
    static func hit(at point: NSPoint, manager: NSLayoutManager, container: NSTextContainer, storage: NSTextStorage,
                    origin: NSPoint, itemID: UUID) -> EaselLinkHit? {
        guard manager.numberOfGlyphs > 0, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var fraction: CGFloat = 0
        let glyph = manager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let box = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard box.insetBy(dx: -1, dy: 0).contains(local) else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        var effective = NSRange()
        guard index < storage.length, let value = storage.attribute(.link, at: index, effectiveRange: &effective) else { return nil }
        guard let link = (value as? URL)?.absoluteString ?? value as? String, !link.isEmpty else { return nil }
        let spanGlyphs = manager.glyphRange(forCharacterRange: effective, actualCharacterRange: nil)
        var lineGlyphs = NSRange()
        _ = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
        let shown = NSIntersectionRange(spanGlyphs, lineGlyphs)
        let line = manager.boundingRect(forGlyphRange: shown.length > 0 ? shown : spanGlyphs, in: container)
        let rect = line.offsetBy(dx: origin.x, dy: origin.y)
        return EaselLinkHit(itemID: itemID, range: effective, link: link, rect: rect)
    }
}

extension EaselCanvasView {
    func linkHit(at point: NSPoint) -> EaselLinkHit? {
        if let editor, let id = editingID, editor.superview === self { return editingLinkHit(editor, itemID: id, at: point) }
        for item in items.reversed() where Self.carriesTextLink(item) {
            if let hit = restingLinkHit(item, at: point) { return hit }
        }
        return nil
    }

    static func carriesTextLink(_ item: EaselItem) -> Bool {
        guard item.kind.holdsText || item.kind == .arrow, !item.text.isEmpty else { return false }
        return item.richText?.runs.contains { $0.attributes.link != nil } == true
    }

    private func editingLinkHit(_ editor: EaselStyledTextView, itemID: UUID, at point: NSPoint) -> EaselLinkHit? {
        guard editor.frame.contains(point), let manager = editor.layoutManager, let container = editor.textContainer,
              let storage = editor.textStorage else { return nil }
        let local = editor.convert(point, from: self)
        guard var hit = EaselLinkHitTest.hit(at: local, manager: manager, container: container, storage: storage,
                                             origin: editor.textContainerOrigin, itemID: itemID) else { return nil }
        hit.rect = convert(hit.rect, from: editor)
        return hit
    }

    private func restingLinkHit(_ item: EaselItem, at point: NSPoint) -> EaselLinkHit? {
        guard (item.rotation ?? 0) == 0, item.flipHorizontal != true, item.flipVertical != true else { return nil }
        if item.kind == .arrow {
            guard let rect = connectorLabelRect(item), rect.contains(point) else { return nil }
            let layout = connectorLabelLayout(item)
            let used = layout.used
            let origin = NSPoint(x: rect.minX + CGFloat(EaselConnectorLabel.paddingX) - used.minX,
                                 y: rect.minY + CGFloat(EaselConnectorLabel.paddingY) - used.minY)
            return EaselLinkHitTest.hit(at: point, manager: layout.manager, container: layout.container, storage: layout.storage,
                                        origin: origin, itemID: item.id)
        }
        let frame = NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)
        guard frame.contains(point), editingID != item.id else { return nil }
        let layout = cachedTextLayout(for: item)
        let placed = EaselTextPlacement.origin(for: item, textHeight: Double(layout.height), overflowing: false)
        let origin = NSPoint(x: placed.x + layout.inset.width, y: placed.y + layout.inset.height)
        return EaselLinkHitTest.hit(at: point, manager: layout.manager, container: layout.container, storage: layout.storage,
                                    origin: origin, itemID: item.id)
    }

    func updateLinkHover(at point: NSPoint?, allowed: Bool) {
        guard let panels else { return }
        guard allowed, let point, !session.isClosed, !session.isDeleted, let hit = linkHit(at: point),
              let item = session.document.items.first(where: { $0.id == hit.itemID }) else {
            panels.hoverLink(nil)
            return
        }
        let editable = !item.isLocked && !isCaptureBoard && !viewOnly
        panels.hoverLink(EaselLinkHoverRequest(key: hit.key, link: hit.link, host: self, anchor: hit.rect, canEdit: editable,
                                               edit: { [weak self] in self?.editLink(of: hit) },
                                               remove: { [weak self] in self?.removeLink(of: hit) }))
    }

    func clearLinkHover() { panels?.hoverLink(nil) }

    func followLink(_ raw: String) {
        guard let target = EaselLinkTarget.classify(raw) else { return }
        switch target {
        case .web(let url): onOpenURL?(url)
        case .note(let url): onOpenNote?(url)
        case .other(let url): NSWorkspace.shared.open(url)
        }
    }

    func copyLink(_ raw: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = URL(string: raw), !url.isFileURL { pasteboard.writeObjects([url as NSURL]) }
        pasteboard.setString(raw, forType: .string)
    }

    func editLink(of hit: EaselLinkHit) {
        guard !session.isClosed, let item = session.document.items.first(where: { $0.id == hit.itemID }), !item.isLocked else { return }
        if editingID != hit.itemID {
            selection = [item.id]
            beginEditing(item)
        }
        guard let editor, editingID == hit.itemID else { return }
        let length = (editor.string as NSString).length
        guard NSMaxRange(hit.range) <= length else { return }
        editor.setSelectedRange(hit.range)
        editor.editLink(relativeTo: editor, rect: editor.revealedSelectionRect(), presenter: panels)
    }

    func removeLink(of hit: EaselLinkHit) {
        guard !session.isClosed else { return }
        if let editor, editingID == hit.itemID {
            guard NSMaxRange(hit.range) <= (editor.string as NSString).length else { return }
            editor.removeLink(in: hit.range)
            return
        }
        guard let item = session.document.items.first(where: { $0.id == hit.itemID }), !item.isLocked,
              var rich = item.richText else { return }
        let end = NSMaxRange(hit.range)
        var changed = false
        for index in rich.runs.indices {
            let run = rich.runs[index]
            guard run.attributes.link != nil, run.location >= hit.range.location, run.location + run.length <= end else { continue }
            rich.runs[index].attributes.link = nil
            changed = true
        }
        guard changed else { return }
        _ = commit("Remove link") { document in
            guard let at = document.items.firstIndex(where: { $0.id == item.id }), document.items[at].richText == item.richText else { return }
            document.items[at].richText = rich
        }
    }
}
