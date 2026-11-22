import Foundation
import Testing
@testable import ParcCore

struct EaselBoardTests {
    fileprivate static func run(link: String?, location: Int, length: Int) -> EaselRichText.Run {
        let font = EaselRichText.Font(name: "Helvetica", size: 15)
        return EaselRichText.Run(location: location, length: length,
                                 attributes: EaselRichText.Attributes(font: font, ink: "#000000FF", link: link))
    }

    fileprivate static func item(_ text: String, runs: [EaselRichText.Run], url: String? = nil) -> EaselItem {
        var item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 200, height: 40))
        item.text = text
        item.richText = EaselRichText(runs: runs)
        item.url = url
        return item
    }

    fileprivate static func linked(_ text: String, to link: String, url: String? = nil) -> EaselItem {
        item(text, runs: [run(link: link, location: 0, length: (text as NSString).length)], url: url)
    }

    private static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Plans", createdAt: Date(), modifiedAt: Date(), items: items)
    }

    private static let roadmap = URL(fileURLWithPath: "/Users/me/Notes/Roadmap.md")
    private static let planB = URL(fileURLWithPath: "/Users/me/Notes/Plan B.md")
    private static var move: NoteBacklinkMove { NoteBacklinkMove(fromKey: NoteFilePaths.key(for: roadmap), from: roadmap, to: planB) }

    @Test(arguments: ["file:///Users/me/Notes/Roadmap.md", "parc://easel/" + UUID().uuidString.lowercased()])
    func noteFileAndEaselLinksAreValid(link: String) {
        #expect(EaselRichText.validLink(link))
    }

    @Test(arguments: ["file://evil.example/Users/me/a.md", "parc://settings"])
    func remoteFileHostsAndOtherParcAddressesAreRefused(link: String) {
        #expect(!EaselRichText.validLink(link))
    }

    @Test func objectsCanLinkToNotes() {
        #expect(EaselObjectLink.normalized("file:///Users/me/Notes/Roadmap.md") == "file:///Users/me/Notes/Roadmap.md")
    }

    @MainActor @Test func aShapeLinkedToANoteSaves() {
        var linked = EaselItem(kind: .rectangle, frame: EaselRect(x: 0, y: 0, width: 40, height: 40))
        linked.url = Self.roadmap.absoluteString
        #expect((try? EaselSession(inMemory: Self.document([linked]), assets: [:])) != nil)
    }

    @MainActor @Test func cardsStillNeedWebAddresses() {
        var card = EaselItem(kind: .link, frame: EaselRect(x: 0, y: 0, width: 40, height: 40))
        card.url = Self.roadmap.absoluteString
        #expect((try? EaselSession(inMemory: Self.document([card]), assets: [:])) == nil)
    }

    @Test func adjacentRunsWithOneLinkCountOnceAndShowTheLinkedWords() {
        let link = Self.roadmap.absoluteString
        let text = "See the Roadmap now"
        let found = EaselBacklinkScanner.outgoing(of: Self.item(text, runs: [
            Self.run(link: nil, location: 0, length: 8), Self.run(link: link, location: 8, length: 4),
            Self.run(link: link, location: 12, length: 3), Self.run(link: nil, location: 15, length: 4)]))
        #expect(found.count == 1)
        #expect(found.first?.target == NoteBacklinkScanner.targetKey(link, from: URL(fileURLWithPath: "/")))
        #expect(found.first?.snippet.text.contains("Roadmap") == true)
    }

    @Test func objectLinksAreFound() {
        let object = Self.item("Plan", runs: [Self.run(link: nil, location: 0, length: 4)], url: Self.roadmap.absoluteString)
        #expect(EaselBacklinkScanner.outgoing(of: object).count == 1)
    }

    @Test func webLinksAreNotBacklinks() {
        #expect(EaselBacklinkScanner.outgoing(of: Self.linked("Web", to: "https://example.com")).isEmpty)
    }

    @Test func noteMentionsCountAsBacklinkMentionsSpelledOut() throws {
        let text = "See \u{FFFC} today"
        var mention = Self.run(link: nil, location: 4, length: 1)
        mention.attributes.inline = .note(Self.roadmap, title: "Roadmap")
        let mentions = EaselBacklinkScanner.outgoing(of: Self.item(text, runs: [
            Self.run(link: nil, location: 0, length: 4), mention, Self.run(link: nil, location: 5, length: 6)]))
        try #require(mentions.count == 1)
        #expect(mentions[0].kind == .mention)
        #expect(mentions[0].target == NoteBacklinkScanner.targetKey(Self.roadmap.absoluteString, from: URL(fileURLWithPath: "/")))
        #expect(mentions[0].snippet.text == "See Roadmap today")
    }

    @Test func linksToAMovedNoteFollowItAndKeepTheirHeading() throws {
        let doc = Self.document([Self.linked("Roadmap", to: Self.roadmap.absoluteString + "#goals", url: Self.roadmap.absoluteString)])
        let next = try #require(EaselBacklinkRewriter.rewrite(doc, move: Self.move))
        #expect(next.items[0].url == Self.planB.absoluteString)
        #expect(next.items[0].richText?.runs[0].attributes.link == Self.planB.absoluteString + "#goals")
        #expect(next.items[0].text == "Roadmap")
    }

    @Test func linksToOtherNotesAreLeftAlone() {
        let other = Self.document([Self.linked("Roadmap", to: "file:///Users/me/Notes/Other.md")])
        #expect(EaselBacklinkRewriter.rewrite(other, move: Self.move) == nil)
    }

    @Test func mentionsFollowAMovedNoteAndTakeItsNewName() throws {
        var mention = Self.run(link: nil, location: 0, length: 1)
        mention.attributes.inline = .note(Self.roadmap, title: "Roadmap")
        let moved = try #require(EaselBacklinkRewriter.rewrite(Self.document([Self.item("\u{FFFC}", runs: [mention])]), move: Self.move))
        let inline = try #require(moved.items[0].richText?.runs[0].attributes.inline)
        #expect(inline.noteURL?.path == Self.planB.path)
        #expect(inline.title == "Plan B")
    }

    @MainActor private static func session(_ items: [EaselItem] = []) throws -> EaselSession {
        try EaselSession(inMemory: document(items), assets: [:])
    }

    private static func isLockError(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return false
        } catch EaselStoreError.lockedDocument {
            return true
        } catch {
            return false
        }
    }

    @MainActor @Test func aLockedEaselRefusesEdits() throws {
        let session = try Self.session([Self.item("Hello", runs: [Self.run(link: nil, location: 0, length: 5)])])
        try session.perform("Lock Easel") { $0.locked = true }
        #expect(session.document.isLocked)
        #expect(Self.isLockError { try session.perform("Edit") { $0.title = "Changed" } })
    }

    @MainActor @Test func undoUnlocksTheEaselForEditsAgain() throws {
        let session = try Self.session()
        try session.perform("Lock Easel") { $0.locked = true }
        try session.undo()
        #expect(!session.document.isLocked)
        try session.perform("Edit") { $0.title = "Changed" }
        #expect(session.document.title == "Changed")
    }

    @MainActor @Test func unlockingIsAllowedOnALockedEasel() throws {
        let session = try Self.session()
        try session.perform("Lock Easel") { $0.locked = true }
        try session.perform("Unlock Easel") { $0.locked = nil }
        #expect(!session.document.isLocked)
    }

    @MainActor @Test func anUnlockedEaselLeavesTheFieldOutOfTheFile() throws {
        let session = try Self.session()
        try session.perform("Lock Easel") { $0.locked = true }
        try session.perform("Unlock Easel") { $0.locked = nil }
        #expect(!String(decoding: try JSONEncoder().encode(session.document), as: UTF8.self).contains("locked"))
    }

    @MainActor @Test func undoRightAfterLockingUnlocksAndKeepsEarlierEdits() throws {
        let session = try Self.session()
        try session.perform("Edit") { $0.title = "A" }
        try session.perform("Lock Easel") { $0.locked = true }
        #expect(session.canUndo)
        try session.undo()
        #expect(!session.document.isLocked)
        #expect(session.document.title == "A")
        #expect(session.canRedo)
        try session.redo()
        #expect(session.document.isLocked)
    }

    @MainActor @Test func undoingAnUnlockLocksAgainAndRedoReappliesIt() throws {
        let session = try Self.session()
        try session.perform("Lock Easel") { $0.locked = true }
        try session.perform("Unlock Easel") { $0.locked = nil }
        try session.perform("Lock Easel") { $0.locked = true }
        try session.undo()
        try session.undo()
        #expect(session.document.isLocked)
        try session.redo()
        #expect(!session.document.isLocked)
    }

    @MainActor @Test func undoIsRefusedWhenTheLockingStepDidMoreThanLock() throws {
        let mixed = try Self.session()
        try mixed.perform("Lock and rename") { $0.locked = true; $0.title = "X" }
        #expect(!mixed.canUndo)
        #expect(Self.isLockError { try mixed.undo() })
        #expect(mixed.document.title == "X")
    }

    @MainActor @Test func aMixedLockStepStaysUndoneWhileItsUnlockIsUndoneAndRedone() throws {
        let mixed = try Self.session()
        try mixed.perform("Lock and rename") { $0.locked = true; $0.title = "X" }
        try mixed.perform("Unlock Easel") { $0.locked = nil }
        try mixed.undo()
        #expect(mixed.document.isLocked)
        #expect(!mixed.canUndo)
        #expect(mixed.canRedo)
        try mixed.redo()
        #expect(!mixed.document.isLocked)
    }

    @MainActor @Test func aRetractedStepLeavesTheEaselAsItWasAndItsAssetsDiscardable() throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        let session = try Self.session()
        let id = try session.importPNG(png)
        var picture = EaselItem(kind: .image, frame: EaselRect(x: 0, y: 0, width: 20, height: 20))
        picture.assetID = id
        try session.perform("Send Here") { $0.items = [picture] }
        try session.retractLastStep()
        #expect(session.document.items.isEmpty)
        #expect(!session.canRedo)
        session.discardUnusedAssets([id])
        #expect(session.inMemoryAssets[id] == nil)
    }

    @MainActor @Test func aLockedEaselsLinksFollowAMovedNoteThroughHistoryAndSaves() throws {
        let folder = NoteFileTestSupport.makeFolder("easel-locked-links")
        defer { NoteFileTestSupport.remove(folder) }
        let old = Self.roadmap.absoluteString, new = Self.planB.absoluteString
        let session = try EaselStore(directory: folder).create(title: "Plans")
        try session.perform("Add") { $0.items = [Self.linked("Roadmap", to: old, url: old)] }
        try session.perform("Lock Easel") { $0.locked = true }
        try session.updateLinks { EaselBacklinkRewriter.rewrite($0, move: Self.move) }
        #expect(session.document.isLocked)
        #expect(session.document.items[0].url == new)
        #expect(session.document.items[0].richText?.runs[0].attributes.link == new)
        #expect(session.document.title == "Plans")
        try session.undo()
        #expect(session.document.items[0].url == new)
        #expect(try EaselStore(directory: folder).load(session.document.id).document.items[0].url == new)
    }

    @MainActor @Test func aLockedEaselRefusesLinkEdits() throws {
        let old = Self.roadmap.absoluteString
        let session = try Self.session([Self.linked("Roadmap", to: old, url: old)])
        try session.perform("Lock Easel") { $0.locked = true }
        #expect(Self.isLockError { try session.perform("Edit") { $0.items[0].url = Self.planB.absoluteString } })
    }

    private static func styled(_ location: Int, _ length: Int, bold: Bool = false, link: String? = nil, heading: Int? = nil,
                               list: String? = nil) -> EaselRichText.Run {
        var font = EaselRichText.Font(name: "Helvetica", size: 15)
        if bold { font.traits = EaselMarkdown.boldTrait }
        var attributes = EaselRichText.Attributes(font: font, ink: "#000000FF", link: link)
        if heading != nil || list != nil {
            attributes.paragraph = EaselRichText.Paragraph(alignment: 0, direction: 0, lineBreak: 0, firstIndent: 0, headIndent: 0,
                tailIndent: 0, lineSpacing: 0, before: 0, after: 0, minimumHeight: 0, maximumHeight: 0, heightMultiple: 0,
                hyphenation: 0, tightening: 0, allowsTightening: false, defaultHyphenation: false, defaultTab: 0, tabs: [],
                lists: list.map { [EaselRichText.Paragraph.List(marker: $0, options: 0, start: 1)] } ?? [], heading: heading)
        }
        return EaselRichText.Run(location: location, length: length, attributes: attributes)
    }

    private static var board: EaselDocument {
        var title = item("Plans\nBold move see Roadmap\nfirst\nsecond", runs: [
            styled(0, 6, heading: 1), styled(6, 4, bold: true), styled(10, 10), styled(20, 7, link: roadmap.absoluteString),
            styled(27, 1), styled(28, 6, list: "{disc}"), styled(34, 6, list: "{disc}")])
        title.frame = EaselRect(x: 0, y: 0, width: 300, height: 100)
        var sticky = EaselItem(kind: .sticky, frame: EaselRect(x: 0, y: 200, width: 100, height: 100))
        sticky.text = "Buy milk"
        var code = EaselItem(kind: .code, frame: EaselRect(x: 0, y: 400, width: 100, height: 100))
        code.text = "print(1)"
        code.language = "python"
        var table = EaselItem(kind: .table, frame: EaselRect(x: 0, y: 600, width: 100, height: 100))
        table.table = EaselTable(columnWidths: [100, 100], rowHeights: [30, 30], cells: [
            [EaselTableCell(text: "Name"), EaselTableCell(text: "Age")], [EaselTableCell(text: "Ada"), EaselTableCell(text: "36")]])
        return document([title, sticky, code, table])
    }

    @Test func theTitleLeadsTheMarkdown() {
        #expect(EaselMarkdown.markdown(Self.board).hasPrefix("# Plans\n"))
    }

    @Test(arguments: [
        ["## Plans"],
        ["**Bold**"],
        ["[Roadmap](", "Roadmap.md"],
        ["- first", "- second"],
        ["- Buy milk"],
        ["```python"],
        ["| Name | Age |", "| Ada  | 36  |"],
    ])
    func boardObjectsBecomeMarkdown(fragments: [String]) {
        let text = EaselMarkdown.markdown(Self.board)
        for fragment in fragments { #expect(text.contains(fragment), "\(text)") }
    }

    @Test func objectsReadTopToBottomInTheMarkdown() {
        let text = EaselMarkdown.markdown(Self.board)
        let order = ["## Plans", "Buy milk", "```python", "| Name"].compactMap { text.range(of: $0)?.lowerBound }
        #expect(order.count == 4)
        #expect(order == order.sorted())
    }

    private static var checklistMarkdown: String {
        let listText = "\t\u{2610}\tmilk\n\t\u{2611}\teggs\n\t\u{2015}\t\nSee \u{FFFC}"
        var mention = styled(24, 1)
        mention.attributes.inline = .note(roadmap, title: "Roadmap")
        let checklist = item(listText, runs: [styled(0, 8, list: EaselChecklist.openMarker), styled(8, 8, list: EaselChecklist.doneMarker),
                                              styled(16, 4, list: EaselChecklist.dividerMarker), styled(20, 4), mention])
        return EaselMarkdown.markdown(document([checklist]))
    }

    @Test func toDosBecomeTaskItems() {
        let listed = Self.checklistMarkdown
        #expect(listed.contains("- [ ] milk") && listed.contains("- [x] eggs"))
    }

    @Test func dividersBecomeRules() {
        #expect(Self.checklistMarkdown.contains("---"))
    }

    @Test func mentionsKeepTheNotesNameInTheMarkdown() {
        let listed = Self.checklistMarkdown
        #expect(listed.contains("Roadmap") && !listed.contains("\u{FFFC}"))
    }

    @Test func wordsCountTextStickiesAndTables() {
        #expect(EaselBoardText.stats(of: Self.board).words >= 10)
    }
}

@MainActor final class EaselBoardBacklinkIndexTests {
    let clock = NoteManualClock()
    let files: NoteFiles
    let folder: URL

    init() {
        files = NoteFileTestSupport.files(clock: clock)
        folder = NoteFileTestSupport.makeFolder("easel-backlinks")
    }

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    @Test func anEaselThatLinksToANoteIsABacklinkThatOpensAtTheObject() throws {
        let notes = folder.appendingPathComponent("Notes", isDirectory: true)
        let note = NoteFileTestSupport.write("# Roadmap\n", to: notes.appendingPathComponent("Roadmap.md"))
        let store = try EaselStore(directory: folder.appendingPathComponent("Easels", isDirectory: true))
        let session = try store.create(title: "Plans")
        let linked = EaselBoardTests.linked("Roadmap", to: note.absoluteString)
        try session.perform("Add") { $0.items = [linked] }
        let index = NoteBacklinkIndex(files: files)
        index.include(store)
        clock.advance(2)
        let found = index.backlinks(to: note)
        try #require(found.count == 1)
        #expect(found[0].isEasel)
        #expect(found[0].title == "Plans")
        #expect(found[0].destination.fragment == linked.id.uuidString.lowercased())
    }
}
