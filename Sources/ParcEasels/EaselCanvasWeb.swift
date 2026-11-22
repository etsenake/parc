import AppKit
import PDFKit
import ParcCore
import ParcNotes

@MainActor
protocol EaselCanvasPasteChoices: AnyObject {
    func offerPasteChoices(for id: UUID, url: URL)
}

extension EaselCanvasView {
    @discardableResult
    func pasteWebLink(_ url: URL, at point: NSPoint? = nil, as kind: EaselItemKind = .link, offersChoices: Bool = true) -> Bool {
        guard fixedCanvasSize == nil, !session.isClosed, kind == .link || kind == .browser,
              EaselLinkPreviewData.isAddress(url.absoluteString) else { return false }
        cancelPointerInteraction()
        guard finishEditing() else { return false }
        drawing = false
        let size = EaselMediaPlacement.filledSize(for: kind)
        let shown = uncoveredVisibleRect
        let centre = point.map { EaselPoint(x: $0.x, y: $0.y) } ?? EaselPoint(x: shown.midX, y: shown.midY)
        let frame = EaselMediaPlacement.resized(EaselRect(x: centre.x, y: centre.y, width: 0, height: 0), width: size.width, height: size.height)
        let top = session.document.items.map(\.zIndex).max() ?? 0
        guard top < Int.max else { return false }
        let item = EaselItem(kind: kind, frame: frame, zIndex: top + 1, text: url.host ?? url.absoluteString,
                             url: url.absoluteString, color: insertionColor)
        guard commit(kind == .link ? "Add bookmark" : "Add embed", { $0.items.append(item) }) else { return false }
        selection = [item.id]
        window?.makeFirstResponder(self)
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard offersChoices, kind == .link else { return true }
        hostedObjects.lazy.compactMap { $0 as? EaselCanvasPasteChoices }.first?.offerPasteChoices(for: item.id, url: url)
        return true
    }

    @discardableResult
    func fillWebObject(_ id: UUID, url: URL) -> Bool {
        guard !viewOnly, !session.isClosed, EaselLinkPreviewData.isAddress(url.absoluteString),
              let item = session.document.items.first(where: { $0.id == id }), item.isEmptyPlaceholder,
              item.kind == .link || item.kind == .browser, !item.isLocked else { return false }
        let size = EaselMediaPlacement.filledSize(for: item.kind)
        let frame = EaselMediaPlacement.resized(item.frame, width: size.width, height: size.height)
        let filled = commit(item.kind == .link ? "Add bookmark" : "Add embed") { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
            document.items[index].url = url.absoluteString
            document.items[index].text = url.host ?? url.absoluteString
            document.items[index].frame = frame
        }
        guard filled else { return false }
        selection = [id]
        if window?.firstResponder is NSText { window?.makeFirstResponder(self) }
        needsLayout = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
        return true
    }

    @discardableResult
    func turnBookmark(_ id: UUID, into kind: EaselItemKind) -> Bool {
        guard !session.isClosed, let item = session.document.items.first(where: { $0.id == id && $0.kind == .link }),
              !item.isLocked, let raw = item.url, let url = URL(string: raw) else { return false }
        switch kind {
        case .browser:
            let size = EaselMediaPlacement.filledSize(for: .browser)
            let frame = EaselMediaPlacement.resized(item.frame, width: size.width, height: size.height)
            return commit("Embed link") { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                document.items[index].kind = .browser
                document.items[index].preview = nil
                document.items[index].frame = frame
            }
        case .text:
            var text = EaselItem(kind: .text, frame: item.frame, zIndex: item.zIndex, text: raw, color: item.color)
            stampRememberedStyle(on: &text)
            let styled = NSMutableAttributedString(attributedString: EaselRichTextCodec.attributed(text))
            styled.addAttribute(.link, value: url, range: NSRange(location: 0, length: styled.length))
            text.richText = try? EaselRichTextCodec.snapshot(styled)
            text.frame = EaselRect(x: item.frame.x, y: item.frame.y, width: min(max(160, item.frame.width), 480), height: 28)
            let changed = commit("Paste as link") { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
                text.id = id
                text.groupID = document.items[index].groupID
                text.page = document.items[index].page
                document.items[index] = text
            }
            if changed { selection = [id] }
            return changed
        default:
            return false
        }
    }

    @discardableResult
    func replaceBookmark(_ id: UUID, withMedia kind: EaselItemKind, url: URL, data: Data?) -> Bool {
        guard !viewOnly, !session.isClosed, let link = session.document.items.first(where: { $0.id == id && $0.kind == .link }),
              !link.isLocked, link.url == url.absoluteString else { return false }
        var item = EaselItem(kind: kind, frame: link.frame, zIndex: link.zIndex, color: link.color)
        item.id = id
        item.groupID = link.groupID
        item.page = link.page
        item.fileName = EaselMediaImportPlan.linkFileName(url)
        var natural: (width: Double, height: Double)?
        do {
            switch kind {
            case .video, .audio:
                guard EaselMediaImportPlan.isLinkable(url, kind: kind) else { return false }
                item.url = url.absoluteString
            case .image:
                guard let data else { return false }
                let asset = try preparedImageAsset(data)
                item.assetID = try session.importAsset(asset.data, type: asset.type)
                item.fileName = nil
                natural = (Double(asset.pixelSize.width), Double(asset.pixelSize.height))
            case .pdf:
                guard let data, let page = PDFDocument(data: data)?.page(at: 0) else { throw EaselStoreError.invalidFile }
                item.assetID = try session.importAsset(data, type: .pdf)
                let bounds = page.bounds(for: .mediaBox)
                natural = (Double(bounds.width), Double(bounds.height))
            default:
                return false
            }
        } catch {
            onError?(error)
            return false
        }
        let size = EaselMediaPlacement.filledSize(for: kind, natural: natural)
        item.frame = EaselMediaPlacement.resized(link.frame, width: size.width, height: size.height)
        let replaced = commit(EaselMediaPlacement.addName(for: kind)) { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }), document.items[index] == link else {
                throw EaselStoreError.staleObject
            }
            document.items[index] = item
        }
        if replaced { selection = [id]; needsLayout = true }
        return replaced
    }

    func recordLinkPreview(_ preview: EaselLinkPreviewData, for id: UUID, url: String) {
        guard !viewOnly, !session.isClosed else { return }
        do {
            guard try session.base.recordLinkPreview(preview, itemID: id, url: url) else { return }
            invalidateIncrementalDisplay(layout: true)
        } catch EaselStoreError.browserInUse {
        } catch { onError?(error) }
    }

    func drawBookmarkCard(_ item: EaselItem, in r: NSRect) {
        let shape = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        EaselAppearance.cardFill.setFill(); shape.fill()
        EaselAppearance.cardStroke.setStroke(); shape.stroke()
        let text = r.insetBy(dx: 16, dy: 14)
        guard text.width > 0, text.height > 0 else { return }
        let wrapping = NSMutableParagraphStyle(); wrapping.lineBreakMode = .byWordWrapping
        let clipping = NSMutableParagraphStyle(); clipping.lineBreakMode = .byTruncatingTail
        (EaselBookmarkCard.title(of: item) as NSString).draw(
            with: NSRect(x: text.minX, y: text.minY, width: text.width, height: 21), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NoteTheme.nunitoBold(14.5), .foregroundColor: color(item.color), .paragraphStyle: clipping])
        if let summary = EaselBookmarkCard.summary(of: item), text.height > 60 {
            (summary as NSString).draw(
                with: NSRect(x: text.minX, y: text.minY + 24, width: text.width, height: 36), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: NoteTheme.nunitoRegular(13), .foregroundColor: EaselAppearance.secondaryText, .paragraphStyle: wrapping])
        }
        (EaselBookmarkCard.siteLine(of: item) as NSString).draw(
            with: NSRect(x: text.minX, y: max(text.minY + 24, text.maxY - 18), width: text.width, height: 18),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: NoteTheme.nunitoRegular(12.5), .foregroundColor: EaselAppearance.secondaryText, .paragraphStyle: clipping])
    }
}
