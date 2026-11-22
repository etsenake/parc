import AppKit
import Testing
@testable import ParcCore
@testable import ParcEasels
@testable import ParcNotes

struct EaselCanvasTestsMediaPaste {
    @MainActor private struct Fixture {
        let directory: URL
        let session: EaselSession
        let canvas: EaselCanvasView
        let board: NSPasteboard

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-media-paste-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            session = try EaselStore(directory: directory.appendingPathComponent("Easels")).create()
            canvas = makeTestEaselCanvas(session: session)
            canvas.frame = NSRect(x: 0, y: 0, width: 1200, height: 900)
            board = NSPasteboard.withUniqueName()
            board.clearContents()
        }

        func tearDown() {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }

        func pixelSize(of item: EaselItem) throws -> CGSize {
            let data = try session.assetData(try #require(item.assetID))
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return CGSize(width: image.width, height: image.height)
        }

        func write(_ archive: NoteClipboard.Archive) throws {
            let item = NSPasteboardItem()
            item.setData(try #require(NoteClipboard.encode(archive)), forType: NoteClipboard.blocksType)
            item.setString("Pasted from a note", forType: .string)
            board.writeObjects([item])
        }
    }

    private static func png(width: Int, height: Int) throws -> Data {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @MainActor @Test
    func aCopiedImageFilePastesThePictureRatherThanItsFinderIcon() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let picture = fixture.directory.appendingPathComponent("Holiday.png")
        try Self.png(width: 60, height: 30).write(to: picture)
        let item = NSPasteboardItem()
        item.setString(picture.absoluteString, forType: .fileURL)
        item.setData(try #require(NSBitmapImageRep(data: try Self.png(width: 128, height: 128))?.tiffRepresentation), forType: .tiff)
        item.setString("Holiday.png", forType: .string)
        fixture.board.writeObjects([item])

        #expect(fixture.canvas.readPasteboard(fixture.board))
        let pasted = try #require(fixture.session.document.items.first)
        #expect(fixture.session.document.items.count == 1 && pasted.kind == .image)
        #expect(try fixture.pixelSize(of: pasted) == CGSize(width: 60, height: 30))
    }

    @MainActor @Test
    func aNoteImageBlockPastesAsAPictureWithItsFraming() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let note = fixture.directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: note.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try Self.png(width: 80, height: 40).write(to: note.appendingPathComponent("Attachments/Sun.png"))
        var props = NoteBlockProps()
        props.source = "Attachments/Sun.png"
        props.alt = "Sunrise"
        props.crop = NoteImageCrop(x: 0, y: 0, width: 0.5, height: 1)
        props.mask = .circle
        try fixture.write(NoteClipboard.Archive(blocks: [NoteBlock(.image, props: props)], base: note, inline: false))

        #expect(fixture.canvas.readPasteboard(fixture.board))
        let pasted = try #require(fixture.session.document.items.first)
        #expect(fixture.session.document.items.count == 1 && pasted.kind == .image)
        #expect(try fixture.pixelSize(of: pasted) == CGSize(width: 80, height: 40))
        #expect(pasted.altText == "Sunrise" && pasted.mask == .circle && pasted.crop == EaselRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(pasted.frame.width == pasted.frame.height)
    }

    @MainActor @Test
    func aNoteCaptureBlockPastesAsACapturedWebpage() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let note = fixture.directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: note.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try Self.png(width: 64, height: 32).write(to: note.appendingPathComponent("Attachments/Capture.png"))
        var props = NoteBlockProps()
        props.source = "Attachments/Capture.png"
        props.alt = "Release notes"
        let captured = Date(timeIntervalSinceReferenceDate: 800_000_000)
        props.capture = NoteCapture(sourceURL: "https://example.com/notes", capturedAt: captured)
        try fixture.write(NoteClipboard.Archive(blocks: [NoteBlock(.image, props: props)], base: note, inline: false))

        #expect(fixture.canvas.readPasteboard(fixture.board))
        let pasted = try #require(fixture.session.document.items.first)
        #expect(pasted.kind == .webCard && pasted.url == "https://example.com/notes" && pasted.text == "Release notes")
        #expect(pasted.capturedAt == captured && pasted.liveCapture == nil)
        #expect(try fixture.pixelSize(of: pasted) == CGSize(width: 64, height: 32))
    }

    @MainActor @Test
    func aNoteImageOutsideItsNoteFolderIsNeverRead() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let note = fixture.directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: note, withIntermediateDirectories: true)
        try Self.png(width: 10, height: 10).write(to: fixture.directory.appendingPathComponent("Private.png"))
        var props = NoteBlockProps()
        props.source = "../Private.png"
        try fixture.write(NoteClipboard.Archive(blocks: [NoteBlock(.image, props: props)], base: note, inline: false))

        _ = fixture.canvas.readPasteboard(fixture.board)
        #expect(!fixture.session.document.items.contains { $0.kind == .image })
    }

    @MainActor @Test
    func noteBookmarkAndEmbedBlocksPasteAsTheirEaselObjects() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        var props = NoteBlockProps()
        props.source = "https://example.com/article"
        try fixture.write(NoteClipboard.Archive(blocks: [NoteBlock(.bookmark, props: props)], base: nil, inline: false))
        #expect(fixture.canvas.readPasteboard(fixture.board))
        fixture.board.clearContents()
        try fixture.write(NoteClipboard.Archive(blocks: [NoteBlock(.embed, props: props)], base: nil, inline: false))
        #expect(fixture.canvas.readPasteboard(fixture.board))

        let kinds = fixture.session.document.items.map(\.kind)
        #expect(kinds == [.link, .browser])
        #expect(fixture.session.document.items.allSatisfy { $0.url == "https://example.com/article" })
    }

    @MainActor @Test
    func htmlHoldingOnlyAPicturePastesThePicture() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let encoded = try Self.png(width: 20, height: 40).base64EncodedString()
        fixture.board.setString("<img src=\"data:image/png;base64,\(encoded)\">", forType: .html)

        #expect(fixture.canvas.readPasteboard(fixture.board))
        let pasted = try #require(fixture.session.document.items.first)
        #expect(pasted.kind == .image && fixture.session.document.items.count == 1)
        #expect(try fixture.pixelSize(of: pasted) == CGSize(width: 20, height: 40))
    }

    @MainActor @Test
    func pastingAPictureFillsTheSelectedEmptyImage() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        let id = try #require(fixture.canvas.placeEmptyObject(.image))
        fixture.board.setData(try Self.png(width: 50, height: 25), forType: .png)

        #expect(fixture.canvas.fillSelectedPlaceholder(from: fixture.board, at: nil) == true)
        let filled = try #require(fixture.session.document.items.first { $0.id == id })
        #expect(fixture.session.document.items.count == 1 && filled.assetID != nil)
        #expect(try fixture.pixelSize(of: filled) == CGSize(width: 50, height: 25))
    }

    @MainActor @Test
    func pastedImageDataLandsAtThePastePoint() throws {
        let fixture = try Fixture(); defer { fixture.tearDown() }
        fixture.board.setData(try Self.png(width: 100, height: 50), forType: .png)

        #expect(fixture.canvas.readPasteboard(fixture.board, at: NSPoint(x: 700, y: 500)))
        let frame = try #require(fixture.session.document.items.first).frame
        #expect(abs(frame.x + frame.width / 2 - 700) <= 1 && abs(frame.y + frame.height / 2 - 500) <= 1)
    }

    @Test
    func noteMediaSourcesResolveOnlyToSafeOrigins() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-origins", isDirectory: true)
        func origin(_ source: String, base: URL? = base) -> EaselPastedNoteMedia.Origin? {
            EaselPastedNoteMedia.origin(source, kind: .image, base: base, trusted: base)
        }
        guard case .download(let remote)? = origin("https://example.com/a.png") else { Issue.record("A web picture downloads"); return }
        #expect(remote.absoluteString == "https://example.com/a.png")
        guard case .file(let local)? = origin("Attachments/a.png") else { Issue.record("A note attachment is read"); return }
        #expect(local.lastPathComponent == "a.png")
        #expect(origin("Attachments/a.png", base: nil) == nil)
        #expect(origin("/etc/hosts") == nil)
        #expect(origin("Attachments/.hidden/a.png") == nil)
        #expect(origin("ftp://example.com/a.png") == nil)
        #expect(origin("https://user:secret@example.com/a.png") == nil)
    }
}
