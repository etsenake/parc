import Foundation

@main
struct EaselObjectLinkTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    @MainActor static func main() {
        normalizing()
        linking()
        badges()
        saving()
        print("EaselObjectLinkTests passed")
    }

    static func item(_ kind: EaselItemKind, url: String? = nil, locked: Bool = false) -> EaselItem {
        var item = EaselItem(kind: kind, frame: EaselRect(x: 100, y: 100, width: 200, height: 80), text: "Hello")
        item.url = url
        item.locked = locked ? true : nil
        return item
    }

    static func normalizing() {
        expect(EaselObjectLink.normalized("https://parc.example/notes?a=1") == "https://parc.example/notes?a=1", "Full web links stay as typed")
        expect(EaselObjectLink.normalized("  example.com/path ") == "https://example.com/path", "Bare domains get https")
        expect(EaselObjectLink.normalized("http://localhost:8080") == "http://localhost:8080", "Local addresses with a scheme work")
        expect(EaselObjectLink.normalized("localhost") == "https://localhost", "Bare localhost works")
        for refused in ["", "   ", "notes", "mailto:a@b.c", "ftp://example.com", "javascript:alert(1)", "https://", "two words.com",
                        "https://user:secret@example.com"] {
            expect(EaselObjectLink.normalized(refused) == nil, "Object links refuse \(refused)")
        }
        expect(EaselObjectLink.normalized("https://example.com/" + String(repeating: "a", count: 17_000)) == nil, "Huge links are refused")
    }

    static func linking() {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        for target in [text, shape, sticky] {
            guard let linked = EaselObjectLink.linking(board, id: target.id, to: "example.com") else { failTest("\(target.kind) takes a link") }
            expect(linked.items.first { $0.id == target.id }?.url == "https://example.com", "\(target.kind) stores the normalized link")
            expect(linked.items.filter { $0.id != target.id } == board.items.filter { $0.id != target.id }, "Only the chosen object changes")
        }
        expect(EaselObjectLink.linking(board, id: image.id, to: "example.com") == nil, "Images keep their own source")
        expect(EaselObjectLink.linking(board, id: locked.id, to: "example.com") == nil, "Locked objects refuse a new link")
        expect(EaselObjectLink.linking(board, id: text.id, to: "not a link") == nil, "An invalid link changes nothing")
        expect(EaselObjectLink.linking(board, id: UUID(), to: "example.com") == nil, "A missing object changes nothing")
        guard let linked = EaselObjectLink.linking(board, id: text.id, to: "https://example.com") else { failTest("Linking works") }
        expect(EaselObjectLink.linking(linked, id: text.id, to: "example.com") == nil, "The same link again changes nothing")
        guard let removed = EaselObjectLink.linking(linked, id: text.id, to: nil) else { failTest("Removing a link works") }
        expect(removed.items[0].url == nil, "Remove Link clears the object link")
        expect(EaselObjectLink.linking(removed, id: text.id, to: nil) == nil, "Removing a missing link changes nothing")
        expect(EaselObjectLink.link(of: item(.text, url: "https://example.com"))?.host == "example.com", "Linked text opens its link")
        expect(EaselObjectLink.link(of: item(.link, url: "https://example.com")) == nil, "Link cards are not object links")
        let exported = EaselVectorExport.objectLinked(item(.sticky, url: "https://example.com/a?b=1&c=2"), "<g></g>")
        expect(exported.hasPrefix("<a href=\"https://example.com/a?b=1&amp;c=2\"") && exported.hasSuffix("</a>"),
               "Exported pages make linked objects clickable")
        expect(EaselVectorExport.objectLinked(item(.text), "<g></g>") == "<g></g>", "Unlinked objects export unchanged")
        expect(EaselVectorExport.objectLinked(item(.text, url: "https://example.com"), "") == "", "Empty art gets no stray link")
    }

    static func badges() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 80)
        let badge = EaselObjectLink.badgeRect(for: frame, scale: 1)
        expect(badge == EaselRect(x: 305, y: 77, width: 18, height: 18), "The badge floats just outside the top-right corner")
        let zoomed = EaselObjectLink.badgeRect(for: frame, scale: 2)
        expect(zoomed.width == 9 && zoomed.x == 302.5, "The badge keeps its size on screen at any zoom")
        expect(EaselObjectLink.badgeRect(for: EaselRect(x: 0, y: 0, width: 50, height: 20), scale: 1).y == 0, "The badge never leaves the canvas")
        let corner = EaselResizeHandle.topRight.hitRect(in: frame)!
        expect(!EaselContentHitTest.contains(EaselPoint(x: badge.x + badge.width / 2, y: badge.y + badge.height / 2), rect: corner),
               "The badge's middle stays clear of the corner handle")
        let linked = item(.text, url: "https://example.com"), plain = item(.text)
        expect(EaselObjectLink.item(at: EaselPoint(x: 314, y: 86), in: [plain, linked], scale: 1)?.id == linked.id, "Clicking the badge finds its object")
        expect(EaselObjectLink.item(at: EaselPoint(x: 200, y: 140), in: [linked], scale: 1) == nil, "Clicking the object itself is not a badge click")
        expect(EaselObjectLink.badgeAllowance(linked, scale: 1) == 32 && EaselObjectLink.badgeAllowance(plain, scale: 1) == 0,
               "Only linked objects reserve room for the badge")
    }

    @MainActor static func saving() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("easel-object-link-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            let linked = item(.sticky, url: "https://example.com/board")
            try session.perform("Add") { $0.items.append(linked) }
            let reopened = try EaselStore(directory: directory).load(session.document.id).document
            expect(reopened.items.first?.url == "https://example.com/board", "Object links survive a save and reopen")
            let plain = String(decoding: try JSONEncoder().encode(item(.text)), as: UTF8.self)
            expect(!plain.contains("\"url\""), "Objects without a link save no url")
        } catch { failTest("Object link saving failed: \(error)") }
    }
}
