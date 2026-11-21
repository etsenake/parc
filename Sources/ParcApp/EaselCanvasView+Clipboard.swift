import AppKit
import ParcCore

extension EaselCanvasView {
    static let objectsPasteboardType = NSPasteboard.PasteboardType(EaselClipboardPayload.typeIdentifier)

    var canCutSelection: Bool { !removableIDs(for: selection).isEmpty }

    var canPasteObjects: Bool {
        NSPasteboard.general.availableType(from: [Self.objectsPasteboardType, EaselStyledText.pasteboardType,
            EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType, .rtfd, .rtf, .png, .tiff,
            Self.gifPasteboardType, .fileURL, .URL, .string]) != nil
    }

    func removableIDs(for ids: Set<UUID>) -> Set<UUID> {
        Set(session.document.items.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
    }

    @discardableResult
    func deleteSelection() -> Bool {
        cancelPointerInteraction()
        guard !session.isClosed, !session.isDeleted, finishEditing() else { return false }
        let doomed = removableIDs(for: selection)
        refuseLocked(selection)
        guard !doomed.isEmpty else { return false }
        let next = EaselArrange.dissolvingSingletonGroups(EaselDependents.removing(doomed, from: session.document))
        prepareReplacement(next) { [weak self] in
            guard let self, self.withObjectMotion(.vanish, { self.commit("Delete objects", { $0 = next }) }) else { return }
            self.selection.subtract(doomed)
        }
        return true
    }

    @discardableResult
    func copySelection() -> Bool {
        guard copyObjects(selection) else { return false }
        flashCopiedSelection(selection)
        return true
    }

    @discardableResult
    func cutSelection() -> Bool {
        let ids = removableIDs(for: selection)
        guard !ids.isEmpty, copyObjects(ids) else { return false }
        selection = ids
        return deleteSelection()
    }

    @discardableResult
    func copyObjects(_ ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty, !session.isClosed else { return false }
        do {
            let document = session.document
            var assets: [String: Data] = [:]
            for id in EaselClipboardPayload.assetIDs(of: ids, in: document) { assets[id] = try session.assetData(id) }
            guard let payload = try EaselClipboardPayload.capturing(ids, in: document, assets: assets) else { return false }
            let item = NSPasteboardItem()
            guard item.setData(try payload.encoded(), forType: Self.objectsPasteboardType) else { throw CocoaError(.fileWriteUnknown) }
            try writeFallbacks(for: payload, into: item)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
            arrangeState.lastPaste = nil
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    private func writeFallbacks(for payload: EaselClipboardPayload, into item: NSPasteboardItem) throws {
        let objects = payload.items
        if objects.count == 1, let only = objects.first, [.image, .webCard].contains(only.kind),
           let asset = only.assetID, let data = payload.assets[asset] {
            item.setData(data, forType: EaselAssetType.of(assetID: asset) == .gif ? Self.gifPasteboardType : .png)
        } else if let image = renderObjectsImage(Set(objects.map(\.id)), backingScale: 2),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        let worded = objects.filter { ($0.kind.holdsText || $0.kind == .section || $0.kind == .arrow) && !EaselTextAttachments.plainString($0.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if objects.count == 1, let only = worded.first {
            let styled = EaselStyledText(text: only.text, style: only.resolvedTextStyle, color: only.color, richText: only.richText)
            try styled.validate()
            item.setData(try JSONEncoder().encode(styled), forType: EaselStyledText.pasteboardType)
        }
        if !worded.isEmpty {
            let joined = NSMutableAttributedString()
            for (index, object) in worded.enumerated() {
                if index > 0 { joined.append(NSAttributedString(string: "\n\n")) }
                joined.append(EaselInlineText.readable(EaselRichTextCodec.attributed(object)))
            }
            let images = EaselTextAttachments.hasImages(joined)
            let native = try joined.data(from: NSRange(location: 0, length: joined.length),
                documentAttributes: [.documentType: images ? NSAttributedString.DocumentType.rtfd : NSAttributedString.DocumentType.rtf])
            if native.count <= 8_388_608 { item.setData(native, forType: images ? .rtfd : .rtf) }
        }
        EaselClipboardText.writeFlavours(for: EaselMarkdown.blocks(for: worded.isEmpty ? [] : objects), into: item)
        let plain = objects.compactMap(clipboardWords).joined(separator: "\n\n")
        if !plain.isEmpty { item.setString(plain, forType: .string) }
    }

    private func clipboardWords(_ item: EaselItem) -> String? {
        if item.kind == .equation { return EaselEquationArtwork.plainText(item) }
        let words = EaselRichText.readable(item.text, rich: item.richText).trimmingCharacters(in: .whitespacesAndNewlines)
        if [.link, .webCard, .browser].contains(item.kind), let url = item.url {
            return words.isEmpty || words == url ? url : words + "\n" + url
        }
        return words.isEmpty ? nil : words
    }

    func renderObjectsImage(_ ids: Set<UUID>, backingScale: CGFloat, pages: [UUID: EaselPageSnapshot] = [:]) -> CGImage? {
        let objects = EaselArrange.paintOrder(session.document).filter { ids.contains($0.id) }
        guard let bounds = EaselArrange.union(objects.map(EaselArrange.visualFrame)) else { return nil }
        let pad = 16.0
        let area = NSRect(x: bounds.x - pad, y: bounds.y - pad, width: bounds.width + 2 * pad, height: bounds.height + 2 * pad)
        var scale = Double(backingScale)
        let pixels = area.width * area.height * scale * scale
        if pixels > 40_000_000 { scale *= (40_000_000 / pixels).squareRoot() }
        scale = min(scale, 16_384 / area.width, 16_384 / area.height)
        let width = Int((area.width * scale).rounded(.up)), height = Int((area.height * scale).rounded(.up))
        guard scale.isFinite, scale > 0, width > 0, height > 0, width <= 16_384, height <= 16_384,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let appearance = effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            (NoteTheme.isDark(appearance) ? NSColor.black : NSColor.white).setFill()
            area.fill()
            for item in objects {
                if let page = pages[item.id] { drawLivePage(page, in: rect(item)) } else { drawObject(item, showsEditor: false) }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    @discardableResult
    func copySelectionAsImage() -> Bool {
        let scale = max(2, window?.backingScaleFactor ?? 2)
        guard !selection.isEmpty, let image = renderObjectsImage(EaselSelectionExport.scope(selection, in: session.document), backingScale: scale),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { onError?(CocoaError(.fileWriteUnknown)); return false }
        flashCopiedSelection(selection)
        onCopiedImage?()
        return true
    }

    func pasteObjects(from pasteboard: NSPasteboard, at point: NSPoint?) -> Bool? {
        guard let data = pasteboard.data(forType: Self.objectsPasteboardType) else { return nil }
        do { return try paste(EaselClipboardPayload.decoded(data), at: point) }
        catch { onError?(error); return false }
    }

    @discardableResult
    func pasteHere(_ point: NSPoint?) -> Bool {
        withObjectMotion(.appear) {
            if let pasted = pasteObjects(from: .general, at: point) { return pasted }
            return readPasteboard(.general)
        }
    }

    @discardableResult
    func pastePlainText(at point: NSPoint?) -> Bool {
        do {
            guard let text = try EaselStyledText.plainText(from: .general) else { return false }
            return insert(kind: .text, text: text, at: point)
        } catch {
            onError?(error)
            return false
        }
    }

    private func paste(_ payload: EaselClipboardPayload, at point: NSPoint?) throws -> Bool {
        cancelPointerInteraction()
        guard !session.isClosed, finishEditing() else { return false }
        drawing = false
        let document = session.document
        var assets: [String: String] = [:]
        let incoming = captureBoardPasteable(payload.items), needed = Set(incoming.compactMap(\.assetID))
        for (original, data) in payload.assets.sorted(by: { $0.key < $1.key }) where !isCaptureBoard || needed.contains(original) {
            if payload.documentID == document.id, let existing = try? session.assetData(original), existing == data {
                assets[original] = original
            } else {
                assets[original] = try session.importAsset(data, type: EaselAssetType.of(assetID: original) ?? .png)
            }
        }
        let items = incoming.map { item -> EaselItem in
            var copy = item
            copy.assetID = item.assetID.flatMap { assets[$0] }
            return copy
        }
        guard let content = EaselArrange.union(items.map(EaselArrange.visualFrame)) else { return false }
        let visible = EaselRect(x: visibleRect.minX, y: visibleRect.minY, width: visibleRect.width, height: visibleRect.height)
        var hasher = Hasher()
        for item in payload.items { hasher.combine(item.id) }
        let fingerprint = hasher.finalize()
        let pointer = (point ?? pointerOnCanvas()).map { EaselPoint(x: $0.x.rounded(), y: $0.y.rounded()) }
        var step = 1
        if let last = arrangeState.lastPaste, last.fingerprint == fingerprint, last.pointer == pointer { step = last.step + 1 }
        let anchor: EaselArrange.PasteAnchor
        if let pointer {
            anchor = .pointer(pointer)
        } else if payload.documentID == document.id, EaselContentHitTest.intersects(content, visible) {
            let present = Set(document.items.map(\.id))
            if payload.items.contains(where: { present.contains($0.id) }) { anchor = .source(step: step) }
            else { anchor = step > 1 ? .source(step: step - 1) : .inPlace }
        } else {
            anchor = .viewport
        }
        var offset = EaselArrange.pasteOffset(content: content, anchor: anchor, viewport: visible)
        if case .pointer = anchor, step > 1 {
            offset.x += EaselArrange.duplicateOffset * Double(step - 1)
            offset.y += EaselArrange.duplicateOffset * Double(step - 1)
        }
        if let size = fixedCanvasSize {
            offset.x = min(max(offset.x, -content.x), max(-content.x, size.width - content.x - content.width))
            offset.y = min(max(offset.y, -content.y), max(-content.y, size.height - content.y - content.height))
        }
        guard let pasted = EaselArrange.appending(items, to: document, offset: offset),
              commit("Paste objects", { $0 = pasted.document }) else { return false }
        arrangeState.lastPaste = (fingerprint, step, pointer)
        arrangeState.enteredGroup = nil
        selection = Set(pasted.copies)
        window?.makeFirstResponder(self)
        return true
    }

    private func pointerOnCanvas() -> NSPoint? {
        guard let window, window.isKeyWindow else { return nil }
        let location = window.mouseLocationOutsideOfEventStream
        let point = convert(location, from: nil)
        guard visibleRect.contains(point), isTopmost(atWindowPoint: location) else { return nil }
        return point
    }

    @objc func cut(_ sender: Any?) {
        cutSelection()
    }
}
