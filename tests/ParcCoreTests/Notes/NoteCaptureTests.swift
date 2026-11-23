import Foundation
import Testing
@testable import ParcCore

struct NoteCaptureTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static let layout = EaselCaptureLayout(viewport: EaselPoint(x: 1280, y: 800), scroll: EaselPoint(x: 0, y: 1200.5),
                                           region: EaselRect(x: 10, y: 20, width: 400, height: 300))

    var layout: EaselCaptureLayout { Self.layout }

    var capture: NoteCapture { NoteCapture(sourceURL: "https://example.com/story?id=1", capturedAt: Self.date, geometry: NoteCaptureGeometry(layout)) }

    var panelled: EaselCaptureLayout {
        var panelled = layout
        panelled.scrollContainers = [EaselScrollContainer(anchorID: "feed", path: "div:0>^>section:2", scroll: EaselPoint(x: 0, y: 2400.25),
                                                          frame: EaselRect(x: 0, y: 64, width: 900, height: 736))]
        return panelled
    }

    var panelledValues: [String: String] {
        let attributes = NoteCapture(sourceURL: "https://example.com", geometry: NoteCaptureGeometry(panelled)).attributes
        return Dictionary(attributes.compactMap { key, value in value.map { (key, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    @Test func geometryAttributesParseIntoTheRendererLayoutAndBack() {
        let parsed = NoteCaptureGeometry(viewport: "1280,800", scroll: "0,1200.5", region: "10,20,400,300")
        #expect(parsed == NoteCaptureGeometry(layout))
        #expect(parsed?.easelLayout == layout)
    }

    @Test(arguments: [("1280,800", "0,0", "10,20,2000,300"), ("1280", "0,0", "0,0,1,1"), ("nan,800", "0,0", "0,0,1,1"), ("0,800", "0,0", "0,0,1,1")])
    func impossibleGeometryIsRefused(viewport: String, scroll: String, region: String) {
        #expect(NoteCaptureGeometry(viewport: viewport, scroll: scroll, region: region) == nil)
    }

    @Test func fractionalScrollOffsetsKeepTheirCSSPixels() {
        #expect(NoteCaptureGeometry(layout).scrollAttribute == "0,1200.5")
    }

    @Test func aCaptureWithoutGeometryCannotBeLive() {
        #expect(NoteCapture(sourceURL: "https://a.com", geometry: nil, live: true).live == false)
    }

    @Test func innerScrollPanelsAreSavedAndComeBackExactly() {
        let values = panelledValues
        #expect(values[NoteCapture.scrollersKey] == "#feed div:0>^>section:2 0,2400.25 0,64,900,736")
        #expect(NoteCapture(values: values, flags: [])?.geometry?.easelLayout == panelled)
    }

    @Test func windowOnlyCapturesSaveNoScrollPanels() {
        #expect(NoteCapture(sourceURL: "https://example.com", geometry: NoteCaptureGeometry(layout)).attributes.allSatisfy { $0.0 != NoteCapture.scrollersKey })
    }

    @Test func anUnreadableScrollPanelRecordNeverGoesLive() throws {
        var broken = panelledValues
        broken[NoteCapture.scrollersKey] = "#feed div;0 0,0 0,0,1,1"
        let unreadable = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: try #require(NoteCapture(values: broken, flags: [])))
        #expect(!NoteCaptureLive.canMakeLive(unreadable))
    }

    var block: NoteBlock { NoteCapture.block(source: "Attachments/Story.png", title: "Story", capture: capture) }

    @Test func aCaptureWithGeometryAndAWebSourceCanGoLive() {
        #expect(NoteCaptureLive.canMakeLive(block))
    }

    @Test func aNewCaptureStartsAsItsSnapshot() {
        #expect(!NoteCaptureLive.ownsLivePage(block))
    }

    @Test func liveModeLoadsTheSavedSource() {
        var live = block
        live.props.capture?.live = true
        #expect(NoteCaptureLive.liveAddress(of: live)?.absoluteString == "https://example.com/story?id=1")
    }

    @Test func capturesWithoutGeometryStaySnapshotOnly() {
        var noGeometry = block
        noGeometry.props.capture = NoteCapture(sourceURL: "https://example.com", capturedAt: Self.date)
        #expect(!NoteCaptureLive.canMakeLive(noGeometry))
    }

    @Test func onlyWebPagesCanGoLive() {
        var local = block
        local.props.capture = NoteCapture(sourceURL: "file:///tmp/a.html", capturedAt: Self.date, geometry: NoteCaptureGeometry(layout))
        #expect(!NoteCaptureLive.canMakeLive(local))
    }

    @Test func onlyImageBlocksCarryCaptures() {
        var video = block
        video.kind = .video
        #expect(NoteCaptureLive.capture(of: video) == nil && !NoteCaptureLive.canMakeLive(video))
    }

    @Test func aCaptureWithoutItsImageCannotGoLive() {
        var missing = block
        missing.props.source = nil
        #expect(!NoteCaptureLive.canMakeLive(missing))
    }

    var sizedText: (NoteBlock, String) {
        var block = NoteCapture.block(source: "Attachments/Story.png", title: "A \"quoted\" story", capture: capture)
        block.props.width = 0.5
        return (block, NoteMarkdown.serialize(NotePage(blocks: [block])))
    }

    @Test func theSourceTimeAndGeometryAreWrittenInTheParcComment() {
        let text = sizedText.1
        #expect(text.contains("capture=\"https://example.com/story?id=1\""))
        #expect(text.contains("captured=\""))
        #expect(text.contains("region=\"10,20,400,300\"") && text.contains("viewport=\"1280,800\"") && text.contains("scroll=\"0,1200.5\""))
    }

    @Test func snapshotModeWritesNoLiveFlag() {
        #expect(!sizedText.1.contains(" live"))
    }

    @Test func aCaptureReadsBackAsTheSameSizedImageBlock() {
        let (block, text) = sizedText
        let read = NoteMarkdown.parse(text).blocks.first
        #expect(read?.kind == .image)
        #expect(read?.props.capture == block.props.capture)
        #expect(read?.props.width == 0.5)
    }

    @Test func aCaptureLineIsStableOnResave() {
        let text = sizedText.1
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text)
    }

    @Test func liveModeIsRememberedInTheFile() {
        var live = sizedText.0
        live.props.capture?.live = true
        let liveText = NoteMarkdown.serialize(NotePage(blocks: [live]))
        #expect(liveText.contains(" live"))
        #expect(NoteMarkdown.parse(liveText).blocks.first?.props.capture?.live == true)
    }

    var fullPageBlock: NoteBlock {
        let layout = EaselCaptureGeometry.captured(viewport: EaselPoint(x: 1280, y: 800), scroll: EaselPoint(x: 0, y: 0),
                                                   region: EaselRect(x: 0, y: 0, width: 1280, height: 800), scrollContainers: [], fullPage: true)!
        var block = NoteCapture.block(source: "Attachments/Page.png", title: "Page",
                                      capture: NoteCapture(sourceURL: "https://example.com/long", capturedAt: Self.date, geometry: NoteCaptureGeometry(layout)))
        block.props.capture?.live = true
        return block
    }

    @Test func aFullPageCaptureIsRememberedInTheFileAndGoesLiveAsAPage() throws {
        let text = NoteMarkdown.serialize(NotePage(blocks: [fullPageBlock]))
        #expect(text.contains(" fullpage"))
        let read = try #require(NoteMarkdown.parse(text).blocks.first)
        #expect(read.props.capture == fullPageBlock.props.capture)
        #expect(NoteCaptureLive.ownsLivePage(read))
        #expect(NoteCaptureLive.layout(of: read)?.isFullPage == true)
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text)
    }

    @Test func parcsOwnHTMLKeepsAFullPageCapture() {
        let back = NoteHTMLReader.blocks(from: NotePageHTML.fragment([fullPageBlock]), baseURL: nil)
        #expect(back.first?.props.capture?.geometry?.easelLayout?.isFullPage == true)
    }

    @Test func regionCapturesWriteNoFullPageFlag() {
        #expect(!sizedText.1.contains("fullpage"))
        #expect(NoteCaptureLive.layout(of: block)?.isFullPage == false)
    }

    @Test func brokenGeometryLeavesASnapshotOnlyCapture() {
        let handWritten = "![](Attachments/a.png) <!-- parc capture=\"https://x.com\" region=\"1,1,1\" live -->"
        let partial = NoteMarkdown.parse(handWritten).blocks.first?.props.capture
        #expect(partial?.sourceURL == "https://x.com" && partial?.geometry == nil && partial?.live == false)
    }

    @Test func ordinaryImagesCarryNoCapture() {
        #expect(NoteMarkdown.parse("![](Attachments/a.png) <!-- parc width=\"0.5\" -->").blocks.first?.props.capture == nil)
    }

    @Test func markdownExportsKeepTheImageAndLinkTheSourceWithoutParcMarkup() {
        let markdown = NoteMarkdown.serialize(NotePage(blocks: [block]), purpose: .export)
        #expect(!markdown.contains("<!--") && !markdown.contains("parc"))
        #expect(markdown.contains("![Story](Attachments/Story.png)"))
        #expect(markdown.contains("[example.com](https://example.com/story?id=1)"))
    }

    @Test func htmlExportsShowTheSourceLink() {
        let html = NotePageHTML.fragment([block])
        #expect(html.contains("class=\"capture-source\"") && html.contains("href=\"https://example.com/story?id=1\""))
    }

    @Test func parcsOwnHTMLReadsTheCaptureBackAsOneBlock() {
        let back = NoteHTMLReader.blocks(from: NotePageHTML.fragment([block]), baseURL: nil)
        #expect(back.count == 1)
        #expect(back.first?.props.capture == block.props.capture)
    }

    var utc: (Calendar, Locale) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (calendar, Locale(identifier: "en_US"))
    }

    @Test(arguments: [(0.0, "Snapshot · captured today"), (86_400, "Snapshot · captured yesterday")])
    func theSnapshotBadgeMatchesAnEaselSnapshots(offset: TimeInterval, expected: String) {
        let (calendar, locale) = utc
        let badge = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: capture)
        #expect(NoteCaptureLive.badge(of: badge, now: Self.date.addingTimeInterval(offset), calendar: calendar, locale: locale) == expected)
    }

    @Test func liveModeIsLabelledLiveWithTheEaselHelp() {
        var live = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: capture)
        live.props.capture?.live = true
        #expect(NoteCaptureLive.badge(of: live) == "Live")
        #expect(NoteCaptureLive.badgeHelp(of: live) == EaselWebItemChrome.liveHelp)
    }

    @Test func capturesWithoutGeometrySaySnapshotOnlyAndExplainWhy() {
        var only = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: capture)
        only.props.capture = NoteCapture(sourceURL: "https://example.com")
        #expect(NoteCaptureLive.badge(of: only) == "Snapshot only")
        #expect(NoteCaptureLive.badgeHelp(of: only) == EaselWebItemChrome.snapshotOnlyHelp)
    }

    @Test func untitledCapturesFallBackToTheDomain() {
        #expect(NoteCaptureText.title(for: capture, alt: nil) == "example.com")
    }

    static let profile = UUID()
    static let base = URL(fileURLWithPath: "/tmp/parc-capture-notes", isDirectory: true)

    static func reference(_ name: String, modified: TimeInterval) -> NoteReference {
        NoteReference(url: base.appendingPathComponent(name + ".md"), title: name, icon: nil, modifiedAt: Date(timeIntervalSince1970: modified))
    }

    static let notes = [reference("Alpha", modified: 10), reference("Beta", modified: 30), reference("Gamma", modified: 20), reference("Delta", modified: 5)]

    static let activity = [
        CaptureNoteDestination.Activity(url: notes[3].url, profileID: profile, date: Date(timeIntervalSince1970: 100)),
        CaptureNoteDestination.Activity(url: notes[0].url, profileID: profile, date: Date(timeIntervalSince1970: 50)),
        CaptureNoteDestination.Activity(url: notes[0].url, profileID: profile, date: Date(timeIntervalSince1970: 200)),
        CaptureNoteDestination.Activity(url: notes[2].url, profileID: UUID(), date: Date(timeIntervalSince1970: 900)),
    ]

    var catalog: [CaptureNoteDestination] { CaptureNoteDestination.catalog(notes: Self.notes, activity: Self.activity, profileID: Self.profile) }

    @Test func recentActivityInThisProfileRanksFirstThenNotesByModification() {
        #expect(catalog.map(\.title) == ["Alpha", "Delta", "Beta", "Gamma"])
    }

    @Test func theCatalogIsCappedToRecentNotes() {
        #expect(CaptureNoteDestination.catalog(notes: Self.notes, activity: Self.activity, profileID: Self.profile, limit: 2).map(\.title) == ["Alpha", "Delta"])
    }

    @Test(arguments: [("TA", ["Delta", "Beta"]), ("", ["Alpha", "Delta", "Beta", "Gamma"])])
    func searchIsACaseInsensitiveSubstringThatKeepsTheOrder(query: String, expected: [String]) {
        #expect(CaptureNoteDestination.search(catalog, query: query).map(\.title) == expected)
    }

    @Test func selectionFollowsTheExactFileAcrossRenames() {
        let renamed = CaptureNoteDestination.catalog(notes: [NoteReference(url: Self.notes[0].url, title: "Alpha renamed", icon: nil, modifiedAt: Self.notes[0].modifiedAt)],
                                                     activity: [], profileID: Self.profile)
        #expect(CaptureNoteDestination.reselect(catalog[0].id, in: renamed)?.title == "Alpha renamed")
    }

    @Test func targetsShareDestinationIdentity() {
        #expect(CaptureNoteTarget.note(Self.notes[0].url).id == catalog[0].id && CaptureNoteTarget.newNote.id == "newNote")
    }
}

@MainActor struct NoteCapturePlacementTests {
    let block = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: NoteCapture(sourceURL: "https://example.com"))
    let first = NoteBlock.paragraph(NoteText("one")), empty = NoteBlock.paragraph(), last = NoteBlock.paragraph(NoteText("two"))

    func placed(caret: NoteBlockID?) -> [NoteBlockID] {
        var page = NotePage(blocks: [first, empty, last])
        _ = NoteCaptureDelivery.place(block, in: &page, caret: caret)
        return page.blocks.map(\.id)
    }

    @Test func withoutACaretTheCaptureGoesAtTheEnd() {
        var page = NotePage(blocks: [first, empty, last])
        #expect(NoteCaptureDelivery.place(block, in: &page, caret: nil))
        #expect(page.blocks.map(\.id) == [first.id, empty.id, last.id, block.id])
    }

    @Test func withACaretTheCaptureGoesAfterItsBlock() {
        #expect(placed(caret: first.id) == [first.id, block.id, empty.id, last.id])
    }

    @Test func aCaretInAnEmptyLineIsReplacedByTheCapture() {
        #expect(placed(caret: empty.id) == [first.id, block.id, last.id])
    }

    @Test func aBlankNewNoteHoldsJustTheCapture() {
        var page = NotePage(blocks: [.paragraph()])
        _ = NoteCaptureDelivery.place(block, in: &page, caret: nil)
        #expect(page.blocks.map(\.id) == [block.id])
    }
}

@MainActor final class NoteCaptureDeliveryTests {
    let folder = NoteFileTestSupport.makeFolder("captures")
    let files = NoteFileTestSupport.files(clock: NoteManualClock())
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
    let input = NoteCaptureInput(pngData: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]), sourceURL: "https://example.com/story",
                                 pageTitle: "Story: Part/1", capturedAt: NoteCaptureTests.date, captureLayout: NoteCaptureTests.layout)

    deinit {
        NoteFileTestSupport.remove(folder)
    }

    func deliver(to target: CaptureNoteTarget) throws -> NoteCaptureDelivery.Result {
        try NoteCaptureDelivery.deliver(input, to: target, notesFolder: folder, in: files)
    }

    @Test func aNewNoteLandsInTheNotesFolderHoldingTheCapture() throws {
        let made = try deliver(to: .newNote)
        let text = NoteFileTestSupport.read(made.note)
        #expect(NoteFilePaths.key(for: made.note.deletingLastPathComponent()) == NoteFilePaths.key(for: folder))
        #expect(text.contains("capture=\"https://example.com/story\"") && text.contains("region=\"10,20,400,300\""))
    }

    @Test func theExactPNGIsStoredInTheNotesAttachmentsFolder() throws {
        let made = try deliver(to: .newNote)
        let attachments = try FileManager.default.contentsOfDirectory(atPath: NoteAttachments.folder(for: made.note).path)
        #expect(attachments.count == 1)
        #expect(try Data(contentsOf: NoteAttachments.folder(for: made.note).appendingPathComponent(attachments[0])) == png)
    }

    @Test func anExistingNoteGetsTheCaptureAtItsEndAndKeepsItsText() throws {
        let existing = NoteFileTestSupport.write("# Notes\n\nKeep me\n", to: folder.appendingPathComponent("Existing.md"))
        let added = try deliver(to: .note(existing))
        let page = NoteMarkdown.parse(NoteFileTestSupport.read(existing))
        #expect(page.blocks.last?.props.capture?.sourceURL == "https://example.com/story" && page.blocks.first?.text.string == "Notes")
        #expect(added.note.lastPathComponent == "Existing.md")
    }

    @Test func plainTextNotesRefuseCapturesAndStayUntouched() {
        let plain = NoteFileTestSupport.write("hello\n", to: folder.appendingPathComponent("Plain.txt"))
        #expect(throws: NoteCaptureDeliveryError.plainText("Plain")) { _ = try self.deliver(to: .note(plain)) }
        #expect(NoteFileTestSupport.read(plain) == "hello\n")
    }

    @Test func missingNotesFailWithoutASubstitute() {
        #expect(throws: NoteFileError.missing) { _ = try self.deliver(to: .note(self.folder.appendingPathComponent("Gone.md"))) }
    }
}
