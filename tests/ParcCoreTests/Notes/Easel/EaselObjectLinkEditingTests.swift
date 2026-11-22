import Foundation
import Testing
@testable import ParcCore

struct EaselObjectLinkEditingTests {
    func item(_ kind: EaselItemKind, url: String? = nil, locked: Bool = false) -> EaselItem {
        var item = EaselItem(kind: kind, frame: EaselRect(x: 100, y: 100, width: 200, height: 80), text: "Hello")
        item.url = url
        item.locked = locked ? true : nil
        return item
    }

    private struct AddressCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let expected: String?

        init(_ label: String, _ input: String, _ expected: String? = nil) {
            testDescription = label
            self.input = input
            self.expected = expected
        }
    }

    @Test(arguments: [
        AddressCase("full web address", "https://parc.example/notes?a=1", "https://parc.example/notes?a=1"),
        AddressCase("bare domain with surrounding spaces", "  example.com/path ", "https://example.com/path"),
        AddressCase("localhost with port and scheme", "http://localhost:8080", "http://localhost:8080"),
        AddressCase("bare localhost", "localhost", "https://localhost"),
        AddressCase("empty address", ""),
        AddressCase("whitespace only", "   "),
        AddressCase("word without a domain", "notes"),
        AddressCase("email link", "mailto:a@b.c"),
        AddressCase("FTP link", "ftp://example.com"),
        AddressCase("script link", "javascript:alert(1)"),
        AddressCase("missing host", "https://"),
        AddressCase("spaces in the host", "two words.com"),
        AddressCase("credentials in the address", "https://user:secret@example.com"),
        AddressCase("overlong address", "https://example.com/" + String(repeating: "a", count: 17_000)),
    ])
    private func objectLinksNormalizeOnlySupportedAddresses(_ testCase: AddressCase) {
        #expect(EaselObjectLink.normalized(testCase.input) == testCase.expected)
    }

    @Test
    func anImageKeepsItsSourceWhenLinked() {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        #expect(EaselObjectLink.linking(board, id: image.id, to: "example.com") == nil, "Images keep their own source")
    }

    @Test
    func aLockedObjectCannotReceiveALink() {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        #expect(EaselObjectLink.linking(board, id: locked.id, to: "example.com") == nil, "Locked objects refuse a new link")
    }

    @Test
    func invalidLinksLeaveObjectsAlone() {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        #expect(EaselObjectLink.linking(board, id: text.id, to: "not a link") == nil, "An invalid link changes nothing")
    }

    @Test
    func linkingAMissingObjectDoesNothing() {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        #expect(EaselObjectLink.linking(board, id: UUID(), to: "example.com") == nil, "A missing object changes nothing")
    }

    @Test
    func reapplyingTheSameLinkDoesNothing() throws {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        let linked = try #require(EaselObjectLink.linking(board, id: text.id, to: "https://example.com"), "Linking works")
        #expect(EaselObjectLink.linking(linked, id: text.id, to: "example.com") == nil, "The same link again changes nothing")
    }

    @Test
    func removingALinkClearsTheObjectsURL() throws {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        let linked = try #require(EaselObjectLink.linking(board, id: text.id, to: "https://example.com"), "Linking works")
        let removed = try #require(EaselObjectLink.linking(linked, id: text.id, to: nil), "Removing a link works")
        #expect(removed.items[0].url == nil, "Remove Link clears the object link")
    }

    @Test
    func removingAMissingLinkDoesNothing() throws {
        let text = item(.text), shape = item(.rectangle), sticky = item(.sticky), image = item(.image), locked = item(.circle, locked: true)
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [text, shape, sticky, image, locked])
        let linked = try #require(EaselObjectLink.linking(board, id: text.id, to: "https://example.com"), "Linking works")
        let removed = try #require(EaselObjectLink.linking(linked, id: text.id, to: nil), "Removing a link works")
        #expect(EaselObjectLink.linking(removed, id: text.id, to: nil) == nil, "Removing a missing link changes nothing")
    }

    @Test
    func linkedTextOpensItsWebAddress() {
        #expect(EaselObjectLink.link(of: item(.text, url: "https://example.com"))?.host == "example.com", "Linked text opens its link")
    }

    @Test
    func aLinkCardDoesNotHaveAnObjectLink() {
        #expect(EaselObjectLink.link(of: item(.link, url: "https://example.com")) == nil, "Link cards are not object links")
    }

    @Test
    func aStickyReportsWhetherItHasALink() {
        #expect(EaselObjectLink.hasLink(item(.sticky, url: "https://example.com")) && !EaselObjectLink.hasLink(item(.sticky)), "A sticky with a url has a link")
    }

    @Test
    func capturedPagesKeepTheirSourceWithoutALinkBadge() {
        #expect(!EaselObjectLink.hasLink(item(.webCard, url: "https://example.com")), "Captured pages keep their source, not a badge")
    }

    @Test
    func linkedObjectsExportWithAnEscapedClickableAddress() {
        let exported = EaselVectorExport.objectLinked(item(.sticky, url: "https://example.com/a?b=1&c=2"), "<g></g>")
        #expect(exported.hasPrefix("<a href=\"https://example.com/a?b=1&amp;c=2\"") && exported.hasSuffix("</a>"), "Exported pages make linked objects clickable")
    }

    @Test
    func unlinkedObjectsExportTheirArtUnchanged() {
        #expect(EaselVectorExport.objectLinked(item(.text), "<g></g>") == "<g></g>", "Unlinked objects export unchanged")
    }

    @Test
    func linkedObjectsWithoutArtExportNoLink() {
        #expect(EaselVectorExport.objectLinked(item(.text, url: "https://example.com"), "") == "", "Empty art gets no stray link")
    }

    @Test(arguments: [EaselItemKind.text, .rectangle, .sticky])
    func linkingStoresTheNormalizedAddressOnTheChosenObject(_ kind: EaselItemKind) throws {
        let items = [item(.text), item(.rectangle), item(.sticky), item(.image), item(.circle, locked: true)]
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: items)
        let target = try #require(items.first { $0.kind == kind })
        let linked = try #require(EaselObjectLink.linking(board, id: target.id, to: "example.com"), "\(target.kind) takes a link")
        #expect(linked.items.first { $0.id == target.id }?.url == "https://example.com", "\(target.kind) stores the normalized link")
        #expect(linked.items.filter { $0.id != target.id } == board.items.filter { $0.id != target.id }, "Only the chosen object changes")
    }

    @Test(arguments: ["https://user:secret@example.com", "https:///path", "mailto:a@example.com"])
    func unsafeOrIncompleteObjectLinksNeverOpen(_ address: String) {
        #expect(EaselObjectLink.link(of: item(.text, url: address)) == nil)
    }

    @Test
    func theBadgeFloatsJustOutsideTheTopRightCorner() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 80)
        let badge = EaselObjectLink.badgeRect(for: frame, scale: 1)
        #expect(badge == EaselRect(x: 305, y: 77, width: 18, height: 18), "The badge floats just outside the top-right corner")
    }

    @Test
    func theBadgeKeepsItsScreenSizeWhenZoomed() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 80)
        let zoomed = EaselObjectLink.badgeRect(for: frame, scale: 2)
        #expect(zoomed.width == 9 && zoomed.x == 302.5, "The badge keeps its size on screen at any zoom")
    }

    @Test
    func theBadgeStaysOnTheCanvas() {
        #expect(EaselObjectLink.badgeRect(for: EaselRect(x: 0, y: 0, width: 50, height: 20), scale: 1).y == 0, "The badge never leaves the canvas")
    }

    @Test
    func theBadgeLeavesTheResizeHandleClear() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 80)
        let badge = EaselObjectLink.badgeRect(for: frame, scale: 1)
        let corner = EaselResizeHandle.topRight.hitRect(in: frame)!
        #expect(!EaselContentHitTest.contains(EaselPoint(x: badge.x + badge.width / 2, y: badge.y + badge.height / 2), rect: corner), "The badge's middle stays clear of the corner handle")
    }

    @Test
    func clickingTheBadgeFindsItsObject() {
        let linked = item(.text, url: "https://example.com"), plain = item(.text)
        #expect(EaselObjectLink.item(at: EaselPoint(x: 314, y: 86), in: [plain, linked], scale: 1)?.id == linked.id, "Clicking the badge finds its object")
    }

    @Test
    func clickingAnObjectDoesNotCountAsClickingItsBadge() {
        let linked = item(.text, url: "https://example.com")
        #expect(EaselObjectLink.item(at: EaselPoint(x: 200, y: 140), in: [linked], scale: 1) == nil, "Clicking the object itself is not a badge click")
    }

    @Test
    func onlyLinkedObjectsReserveRoomForTheBadge() {
        let linked = item(.text, url: "https://example.com"), plain = item(.text)
        #expect(EaselObjectLink.badgeAllowance(linked, scale: 1) == 32 && EaselObjectLink.badgeAllowance(plain, scale: 1) == 0, "Only linked objects reserve room for the badge")
    }

    @MainActor @Test
    func objectLinksSurviveASaveAndReopen() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("easel-object-link-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = try EaselStore(directory: directory)
            let session = try store.create()
            let linked = item(.sticky, url: "https://example.com/board")
            try session.perform("Add") { $0.items.append(linked) }
            let reopened = try EaselStore(directory: directory).load(session.document.id).document
            #expect(reopened.items.first?.url == "https://example.com/board", "Object links survive a save and reopen")
        } catch { Issue.record("Object link saving failed: \(error)") }
    }

    @Test
    func objectsWithoutALinkOmitTheURL() throws {
        let plain = String(decoding: try JSONEncoder().encode(item(.text)), as: UTF8.self)
        #expect(!plain.contains("\"url\""), "Objects without a link save no url")
    }
}
