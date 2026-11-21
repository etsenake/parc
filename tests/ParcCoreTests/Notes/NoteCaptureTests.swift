import Foundation
import Testing
@testable import ParcCore

extension NoteProcessWide {
@MainActor final class NoteCaptureTests {
    init() {
        NoteFileSession.clock = clock
        NoteFileSession.worker = .inline
        NoteLibrary.clock = clock
        NoteLibrary.worker = .inline
    }

    deinit {

    }

    let clock = NoteManualClock()

    let date = Date(timeIntervalSince1970: 1_790_000_000)

    let layout = EaselCaptureLayout(viewport: EaselPoint(x: 1280, y: 800), scroll: EaselPoint(x: 0, y: 1200.5),
                                           region: EaselRect(x: 10, y: 20, width: 400, height: 300))

    var capture: NoteCapture { NoteCapture(sourceURL: "https://example.com/story?id=1", capturedAt: date, geometry: NoteCaptureGeometry(layout)) }

    @Test func geometry() {
        let parsed = NoteCaptureGeometry(viewport: "1280,800", scroll: "0,1200.5", region: "10,20,400,300")
        #expect(parsed == NoteCaptureGeometry(layout), "geometry attributes parse into the renderer layout")
        #expect(parsed?.easelLayout == layout, "note geometry converts back to the Easel layout exactly")
        #expect(NoteCaptureGeometry(viewport: "1280,800", scroll: "0,0", region: "10,20,2000,300") == nil, "a region outside the viewport is refused")
        #expect(NoteCaptureGeometry(viewport: "1280", scroll: "0,0", region: "0,0,1,1") == nil, "short lists are refused")
        #expect(NoteCaptureGeometry(viewport: "nan,800", scroll: "0,0", region: "0,0,1,1") == nil, "non-finite numbers are refused")
        #expect(NoteCaptureGeometry(viewport: "0,800", scroll: "0,0", region: "0,0,1,1") == nil, "an empty viewport is refused")
        #expect(NoteCaptureGeometry(layout).scrollAttribute == "0,1200.5", "fractional scroll offsets keep their CSS pixels")
        #expect(NoteCapture(sourceURL: "https://a.com", geometry: nil, live: true).live == false, "a capture without geometry can't be live")
        var panelled = layout
        panelled.scrollContainers = [EaselScrollContainer(anchorID: "feed", path: "div:0>^>section:2", scroll: EaselPoint(x: 0, y: 2400.25),
                                                          frame: EaselRect(x: 0, y: 64, width: 900, height: 736))]
        let attributes = NoteCapture(sourceURL: "https://example.com", geometry: NoteCaptureGeometry(panelled)).attributes
        let values = Dictionary(attributes.compactMap { key, value in value.map { (key, $0) } }, uniquingKeysWith: { a, _ in a })
        #expect(values[NoteCapture.scrollersKey] == "#feed div:0>^>section:2 0,2400.25 0,64,900,736", "inner scroll panels are saved with the capture")
        #expect(NoteCapture(values: values, flags: [])?.geometry?.easelLayout == panelled, "saved scroll panels come back exactly")
        #expect(NoteCapture(sourceURL: "https://example.com", geometry: NoteCaptureGeometry(layout)).attributes.allSatisfy { $0.0 != NoteCapture.scrollersKey }, "window-only captures save no scroll panels")
        var broken = values
        broken[NoteCapture.scrollersKey] = "#feed div;0 0,0 0,0,1,1"
        let unreadable = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: NoteCapture(values: broken, flags: [])!)
        #expect(!NoteCaptureLive.canMakeLive(unreadable), "an unreadable scroll panel record never goes live with the wrong framing")
    }

    @Test func liveDecision() {
        var block = NoteCapture.block(source: "Attachments/Story.png", title: "Story", capture: capture)
        #expect(NoteCaptureLive.canMakeLive(block), "a capture with geometry and a web source can go live")
        #expect(!NoteCaptureLive.ownsLivePage(block), "a new capture starts as its snapshot")
        block.props.capture?.live = true
        #expect(NoteCaptureLive.liveAddress(of: block)?.absoluteString == "https://example.com/story?id=1", "live mode loads the saved source")
        var noGeometry = block
        noGeometry.props.capture = NoteCapture(sourceURL: "https://example.com", capturedAt: date)
        #expect(!NoteCaptureLive.canMakeLive(noGeometry), "captures without geometry stay snapshot only")
        var local = block
        local.props.capture = NoteCapture(sourceURL: "file:///tmp/a.html", capturedAt: date, geometry: NoteCaptureGeometry(layout))
        #expect(!NoteCaptureLive.canMakeLive(local), "only web pages can go live")
        var video = block
        video.kind = .video
        #expect(NoteCaptureLive.capture(of: video) == nil && !NoteCaptureLive.canMakeLive(video), "only image blocks carry captures")
        var missing = block
        missing.props.source = nil
        #expect(!NoteCaptureLive.canMakeLive(missing), "a capture without its image can't go live")
    }

    @Test func markdownRoundTrip() {
        var block = NoteCapture.block(source: "Attachments/Story.png", title: "A \"quoted\" story", capture: capture)
        block.props.width = 0.5
        let page = NotePage(blocks: [block])
        let text = NoteMarkdown.serialize(page)
        #expect(text.contains("capture=\"https://example.com/story?id=1\""), "the source is written in the parc comment: \(text)")
        #expect(text.contains("captured=\"2026-09-21T") || text.contains("captured=\""), "the acquisition time is written")
        #expect(text.contains("region=\"10,20,400,300\"") && text.contains("viewport=\"1280,800\"") && text.contains("scroll=\"0,1200.5\""), "the renderer geometry is written: \(text)")
        #expect(!text.contains(" live"), "snapshot mode writes no live flag")
        let read = NoteMarkdown.parse(text).blocks.first
        #expect(read?.kind == .image, "a capture reads back as an image block")
        #expect(read?.props.capture == block.props.capture, "capture metadata round-trips exactly")
        #expect(read?.props.width == 0.5, "image sizing survives beside capture metadata")
        #expect(NoteMarkdown.serialize(NoteMarkdown.parse(text)) == text, "a capture line is stable on resave")
        var live = block
        live.props.capture?.live = true
        let liveText = NoteMarkdown.serialize(NotePage(blocks: [live]))
        #expect(liveText.contains(" live"), "live mode is remembered in the file")
        #expect(NoteMarkdown.parse(liveText).blocks.first?.props.capture?.live == true, "live mode reads back")
        let handWritten = "![](Attachments/a.png) <!-- parc capture=\"https://x.com\" region=\"1,1,1\" live -->"
        let partial = NoteMarkdown.parse(handWritten).blocks.first?.props.capture
        #expect(partial?.sourceURL == "https://x.com" && partial?.geometry == nil && partial?.live == false, "broken geometry leaves a snapshot-only capture rather than guessing")
        let plainImage = NoteMarkdown.parse("![](Attachments/a.png) <!-- parc width=\"0.5\" -->").blocks.first
        #expect(plainImage?.props.capture == nil, "ordinary images carry no capture")
    }

    @Test func exports() {
        let block = NoteCapture.block(source: "Attachments/Story.png", title: "Story", capture: capture)
        let markdown = NoteMarkdown.serialize(NotePage(blocks: [block]), purpose: .export)
        #expect(!markdown.contains("<!--") && !markdown.contains("parc"), "Markdown exports carry no Parc markup: \(markdown)")
        #expect(markdown.contains("![Story](Attachments/Story.png)"), "Markdown exports keep the image")
        #expect(markdown.contains("[example.com](https://example.com/story?id=1)"), "Markdown exports link the source: \(markdown)")
        let html = NotePageHTML.fragment([block])
        #expect(html.contains("class=\"capture-source\"") && html.contains("href=\"https://example.com/story?id=1\""), "HTML exports show the source link: \(html)")
        let back = NoteHTMLReader.blocks(from: html, baseURL: nil)
        #expect(back.count == 1, "the source line isn't read back as its own paragraph")
        #expect(back.first?.props.capture == block.props.capture, "capture metadata survives Parc's own HTML")
    }

    @Test func badges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        var block = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: capture)
        #expect(NoteCaptureLive.badge(of: block, now: date, calendar: calendar, locale: locale) == "Snapshot · captured today", "the badge matches an Easel snapshot's")
        #expect(NoteCaptureLive.badge(of: block, now: date.addingTimeInterval(86_400), calendar: calendar, locale: locale) == "Snapshot · captured yesterday", "next-day badge")
        block.props.capture?.live = true
        #expect(NoteCaptureLive.badge(of: block) == "Live", "live mode is labelled Live")
        #expect(NoteCaptureLive.badgeHelp(of: block) == EaselWebItemChrome.liveHelp, "live help is the Easel one")
        var only = block
        only.props.capture = NoteCapture(sourceURL: "https://example.com")
        #expect(NoteCaptureLive.badge(of: only) == "Snapshot only", "captures without geometry say Snapshot only")
        #expect(NoteCaptureLive.badgeHelp(of: only) == EaselWebItemChrome.snapshotOnlyHelp, "and explain why")
        #expect(NoteCaptureText.title(for: capture, alt: nil) == "example.com", "untitled captures fall back to the domain")
    }

    @Test func destinations() {
        let profile = UUID(), other = UUID()
        let base = URL(fileURLWithPath: "/tmp/parc-capture-notes", isDirectory: true)
        func note(_ name: String, modified: TimeInterval) -> NoteReference {
            NoteReference(url: base.appendingPathComponent(name + ".md"), title: name, icon: nil, modifiedAt: Date(timeIntervalSince1970: modified))
        }
        let notes = [note("Alpha", modified: 10), note("Beta", modified: 30), note("Gamma", modified: 20), note("Delta", modified: 5)]
        let activity = [
            CaptureNoteDestination.Activity(url: notes[3].url, profileID: profile, date: Date(timeIntervalSince1970: 100)),
            CaptureNoteDestination.Activity(url: notes[0].url, profileID: profile, date: Date(timeIntervalSince1970: 50)),
            CaptureNoteDestination.Activity(url: notes[0].url, profileID: profile, date: Date(timeIntervalSince1970: 200)),
            CaptureNoteDestination.Activity(url: notes[2].url, profileID: other, date: Date(timeIntervalSince1970: 900)),
        ]
        let catalog = CaptureNoteDestination.catalog(notes: notes, activity: activity, profileID: profile)
        #expect(catalog.map(\.title) == ["Alpha", "Delta", "Beta", "Gamma"], "recent sidebar activity ranks first, then notes by modification, ignoring other Profiles")
        #expect(CaptureNoteDestination.catalog(notes: notes, activity: activity, profileID: profile, limit: 2).map(\.title) == ["Alpha", "Delta"], "the catalog is capped to recent notes")
        #expect(CaptureNoteDestination.search(catalog, query: "TA").map(\.title) == ["Delta", "Beta"], "search is a case-insensitive substring that keeps the order")
        #expect(CaptureNoteDestination.search(catalog, query: "").count == 4, "an empty search keeps everything")
        let renamed = CaptureNoteDestination.catalog(notes: [NoteReference(url: notes[0].url, title: "Alpha renamed", icon: nil, modifiedAt: notes[0].modifiedAt)],
                                                     activity: [], profileID: profile)
        #expect(CaptureNoteDestination.reselect(catalog[0].id, in: renamed)?.title == "Alpha renamed", "selection follows the exact file across renames")
        #expect(CaptureNoteTarget.note(notes[0].url).id == catalog[0].id && CaptureNoteTarget.newNote.id == "newNote", "targets share destination identity")
    }

    @Test func insertion() {
        let block = NoteCapture.block(source: "Attachments/a.png", title: "A", capture: capture)
        let first = NoteBlock.paragraph(NoteText("one")), empty = NoteBlock.paragraph(), last = NoteBlock.paragraph(NoteText("two"))
        var page = NotePage(blocks: [first, empty, last])
        #expect(NoteCaptureDelivery.place(block, in: &page, caret: nil), "inserting without a caret works")
        #expect(page.blocks.map(\.id) == [first.id, empty.id, last.id, block.id], "without a caret the capture goes at the end")
        page = NotePage(blocks: [first, empty, last])
        _ = NoteCaptureDelivery.place(block, in: &page, caret: first.id)
        #expect(page.blocks.map(\.id) == [first.id, block.id, empty.id, last.id], "with a caret the capture goes after its block")
        page = NotePage(blocks: [first, empty, last])
        _ = NoteCaptureDelivery.place(block, in: &page, caret: empty.id)
        #expect(page.blocks.map(\.id) == [first.id, block.id, last.id], "a caret in an empty line is replaced by the capture")
        page = NotePage(blocks: [.paragraph()])
        _ = NoteCaptureDelivery.place(block, in: &page, caret: nil)
        #expect(page.blocks.map(\.id) == [block.id], "a blank new note holds just the capture")
    }

    @Test func delivery() throws {
        let folder = NoteFileTestSupport.makeFolder("captures")
        defer { NoteFileTestSupport.remove(folder) }
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let input = NoteCaptureInput(pngData: png, sourceURL: "https://example.com/story", pageTitle: "Story: Part/1",
                                     capturedAt: date, captureLayout: layout)
        let made = try NoteCaptureDelivery.deliver(input, to: .newNote, notesFolder: folder)
        let text = NoteFileTestSupport.read(made.note)
        #expect(NoteFilePaths.key(for: made.note.deletingLastPathComponent()) == NoteFilePaths.key(for: folder), "New Note lands in the Notes folder")
        #expect(text.contains("capture=\"https://example.com/story\"") && text.contains("region=\"10,20,400,300\""), "the new note holds the capture: \(text)")
        let attachments = try FileManager.default.contentsOfDirectory(atPath: NoteAttachments.folder(for: made.note).path)
        #expect(attachments.count == 1, "the PNG is stored in the note's Attachments folder")
        #expect((try Data(contentsOf: NoteAttachments.folder(for: made.note).appendingPathComponent(attachments[0]))) == png, "the exact PNG bytes are kept")
        let existing = NoteFileTestSupport.write("# Notes\n\nKeep me\n", to: folder.appendingPathComponent("Existing.md"))
        let added = try NoteCaptureDelivery.deliver(input, to: .note(existing), notesFolder: folder)
        let page = NoteMarkdown.parse(NoteFileTestSupport.read(existing))
        #expect(page.blocks.last?.props.capture?.sourceURL == "https://example.com/story" && page.blocks.first?.text.string == "Notes", "an existing note gets the capture at its end and keeps its text")
        #expect(added.note.lastPathComponent == "Existing.md", "the existing note is the destination")
        let plain = NoteFileTestSupport.write("hello\n", to: folder.appendingPathComponent("Plain.txt"))
        #expect(throws: NoteCaptureDeliveryError.plainText("Plain"), "plain-text notes refuse captures") {
            _ = try NoteCaptureDelivery.deliver(input, to: .note(plain), notesFolder: folder)
        }
        #expect(NoteFileTestSupport.read(plain) == "hello\n", "a refused note is untouched")
        #expect(throws: NoteFileError.missing, "missing notes fail without a substitute") {
            _ = try NoteCaptureDelivery.deliver(input, to: .note(folder.appendingPathComponent("Gone.md")), notesFolder: folder)
        }
    }
}
}
