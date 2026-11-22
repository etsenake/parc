import AppKit
import ParcCore

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
        return withObjectMotion(.appear) { insertDocumentLink(url, title: documentTitle(for: drag), at: convert(sender.draggingLocation, from: nil)) }
    }

    @discardableResult
    func insertDocumentLink(_ url: URL, title: String, at point: NSPoint?) -> Bool {
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
            return insert(kind: .text, text: value.string, styledText: styled, at: point)
        } catch {
            onError?(error)
            return false
        }
    }

    func importPastedFiles(_ urls: [URL], at point: NSPoint?) throws {
        let notes = fixedCanvasSize == nil ? urls.filter { NoteFileKind(url: $0) == .markdown } : []
        let media = urls.filter { !notes.contains($0) }
        let shown = uncoveredVisibleRect
        let anchor = point ?? NSPoint(x: shown.midX - 140, y: shown.midY)
        for (index, note) in notes.enumerated() {
            let title = note.deletingPathExtension().lastPathComponent
            insertDocumentLink(note, title: title, at: NSPoint(x: anchor.x, y: anchor.y + CGFloat(index) * 40))
        }
        guard !media.isEmpty else { return }
        let below = notes.isEmpty ? point : NSPoint(x: anchor.x + 140, y: anchor.y + CGFloat(notes.count) * 40 + 200)
        try importMediaFiles(media, at: below)
    }
}
