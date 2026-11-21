import AppKit

extension EaselCanvasView {
    static let documentDragType = NSPasteboard.PasteboardType(NoteDocumentDrag.pasteboardType)

    func sidebarDocumentDrag(_ pasteboard: NSPasteboard) -> NoteDocumentDrag? {
        guard fixedCanvasSize == nil, !isDocumentLocked, let raw = pasteboard.string(forType: Self.documentDragType),
              let drag = NoteDocumentDrag(encoded: raw), documentLink(for: drag.address) != nil else { return nil }
        return drag
    }

    func documentLink(for address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = InternalPage(urlString: value) else { return nil }
        if let easel = page.easelID {
            return easel == session.fullDocument.id ? nil : InternalPage.easel(easel).urlString
        }
        return page.noteURL.map { URL(fileURLWithPath: $0.path).absoluteString }
    }

    func documentTitle(for drag: NoteDocumentDrag) -> String {
        let title = drag.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let note = InternalPage(urlString: drag.address)?.noteURL { return note.deletingPathExtension().lastPathComponent }
        return InternalPage(urlString: drag.address)?.easelID == nil ? "Untitled" : "Untitled Easel"
    }

    func dropSidebarDocument(_ sender: NSDraggingInfo) -> Bool? {
        guard let drag = sidebarDocumentDrag(sender.draggingPasteboard), let link = documentLink(for: drag.address),
              let url = URL(string: link) else { return nil }
        let title = documentTitle(for: drag)
        let style = EaselTextStyle(family: session.document.resolvedDefaultFamily)
        let typing = EaselTextAppearance.attributed(title, style: style, color: insertionColor).attributes(at: 0, effectiveRange: nil)
        var attributes = typing
        attributes[.link] = url
        let value: NSAttributedString
        if url.isFileURL, (try? EaselRichText.Inline.note(url, title: title).validate()) != nil {
            value = EaselInlineText.character(.note(url, title: title), attributes: typing)
        } else {
            value = NSAttributedString(string: title, attributes: attributes)
        }
        do {
            let styled = try EaselStyledText.capture(value, style: style, color: insertionColor)
            let point = convert(sender.draggingLocation, from: nil)
            return withObjectMotion(.appear) { insert(kind: .text, text: value.string, styledText: styled, at: point) }
        } catch {
            onError?(error)
            return false
        }
    }
}
