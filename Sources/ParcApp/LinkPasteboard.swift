import AppKit

enum LinkPasteboard {
    @discardableResult
    static func write(_ links: [FolderLinks.Link], format: FolderLinkFormat, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let text = FolderLinks.text(for: links, format: format) else { return false }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if format == .plain, let html = FolderLinks.html(for: links) { item.setString(html, forType: .html) }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
