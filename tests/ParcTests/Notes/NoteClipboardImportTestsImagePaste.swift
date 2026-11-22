import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteClipboardImportTestsImagePaste {
    private let importer: NoteClipboardImportTestsSupport.Fixture

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    @MainActor private struct BigPaste {
        let trip: NoteClipboardImportTestsSupport.Fixture.Trip
        let big: Data
        let block: NoteBlock
        let source: String
    }

    private func bigPaste() throws -> BigPaste {
        let trip = try importer.trip()
        let big = importer.bitmapTIFF(side: 1200)
        let block = try NoteClipboard.imageBlock(data: big, fileExtension: "tiff", environment: trip.file.environment)
        return BigPaste(trip: trip, big: big, block: block, source: try #require(block.props.source))
    }

    @Test func aBigPasteWaitsInATemporaryFileWithTheRealBytes() throws {
        let paste = try bigPaste()
        let staged = try #require(URL(string: paste.source))
        #expect(paste.big.count > NoteMediaImport.stagingThreshold)
        #expect(NoteAttachments.isStaged(staged))
        #expect(try Data(contentsOf: staged) == paste.big)
    }

    @Test func aBigPasteCopiesInTheBackground() throws {
        let paste = try bigPaste()
        #expect(importer.imports.isPending(paste.source, in: paste.trip.session))
    }

    private func landedBigPaste() throws -> (BigPaste, String) {
        let paste = try bigPaste()
        paste.trip.session.insertBlocks([paste.block], .top(paste.trip.session.page.blocks.count))
        paste.trip.session.undo()
        importer.jobs.runAll()
        return (paste, try #require(importer.imports.landedPath(for: paste.source, in: paste.trip.session)))
    }

    @Test func aBigTIFFLandsAsAPNGToo() throws {
        let (paste, path) = try landedBigPaste()
        #expect(path.hasSuffix(".png"))
        #expect(importer.attachment(path, in: paste.trip.notes)?.prefix(4) == Data(importer.pngHeader))
    }

    @Test func redoingAPasteThatFinishedWhileUndoneHealsItsSource() throws {
        let (paste, path) = try landedBigPaste()
        paste.trip.session.redo()
        importer.jobs.runAll()
        importer.clock.advance(0.01)
        #expect(paste.trip.session.page.block(paste.block.id)?.props.source == path)
    }

    @Test func smallDataURLsLandInAttachmentsStraightAway() throws {
        let trip = try importer.trip()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
        let decoded = NoteClipboard.importInlineMedia([importer.image("data:image/png;base64," + bytes.base64EncodedString())], environment: trip.file.environment)
        #expect(decoded.failures.isEmpty)
        #expect(importer.attachment(decoded.blocks[0].props.source, in: trip.notes) == bytes)
    }

    private func fromAnotherNote() throws -> (NoteClipboardImportTestsSupport.Fixture.Trip, [NoteBlock], String) {
        let trip = try importer.trip()
        let other = importer.root.appendingPathComponent("Other", isDirectory: true)
        try importer.write(Data([7, 7]), to: other.appendingPathComponent("Attachments/cat.png"))
        let rebased = NoteClipboard.rebase(NoteClipboard.Archive(blocks: [importer.image("Attachments/cat.png")], base: other, inline: false), into: trip.file.environment)
        return (trip, rebased, rebased[0].props.source ?? "")
    }

    @Test func mediaFromAnotherNotesFolderShowsFromThereWhileItCopies() throws {
        let (trip, _, source) = try fromAnotherNote()
        #expect(source.hasPrefix("file://"))
        #expect(importer.fileExists(source))
        #expect(importer.imports.isPending(source, in: trip.session))
    }

    @Test func copiedMediaFromAnotherNoteArrivesIntact() throws {
        let (trip, rebased, _) = try fromAnotherNote()
        trip.session.insertBlocks(rebased, .top(trip.session.page.blocks.count))
        importer.jobs.runAll()
        #expect(importer.attachment(trip.session.page.block(rebased[0].id)?.props.source, in: trip.notes) == Data([7, 7]))
    }

    @Test func ordinarySourcesAreNotImports() throws {
        let trip = try importer.trip()
        #expect(!importer.imports.isPending("Attachments/cat.png", in: trip.session))
    }
}
