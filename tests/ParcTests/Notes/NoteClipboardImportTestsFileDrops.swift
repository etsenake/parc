import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteClipboardImportTestsFileDrops {
    private let importer: NoteClipboardImportTestsSupport.Fixture

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    @MainActor private struct Drop {
        let trip: NoteClipboardImportTestsSupport.Fixture.Trip
        let dropped: (blocks: [NoteBlock], failures: [Error])
        let sources: [String]
    }

    private func dropPhoto() throws -> Drop {
        let trip = try importer.trip()
        let gone = importer.root.appendingPathComponent("Outside/Gone.mov")
        let dropped = NoteClipboard.blocks(forFiles: [trip.photo, gone], environment: trip.file.environment)
        return Drop(trip: trip, dropped: dropped, sources: dropped.blocks.compactMap(\.props.source))
    }

    @Test func droppedFilesBecomeBlocksRightAway() throws {
        let drop = try dropPhoto()
        #expect(drop.dropped.failures.isEmpty)
        #expect(drop.sources.count == 2)
    }

    @Test func droppedFilesPointAtTheOriginalsWhileTheCopyRuns() throws {
        let drop = try dropPhoto()
        #expect(drop.sources.allSatisfy { $0.hasPrefix("file://") && importer.imports.isPending($0, in: drop.trip.session) })
    }

    @Test func theDroppedPictureShowsUpStraightAway() throws {
        let drop = try dropPhoto()
        #expect(importer.fileExists(drop.sources[0]))
        #expect(URL(string: drop.sources[0])?.lastPathComponent == "Beach.png")
    }

    private func inserted() throws -> (Drop, [NoteBlockID]) {
        let drop = try dropPhoto()
        let ids = drop.trip.session.insertBlocks(drop.dropped.blocks, .top(drop.trip.session.page.blocks.count))
        importer.jobs.runAll()
        return (drop, ids)
    }

    @Test func theFinishedCopyBecomesTheBlocksSource() throws {
        let (drop, ids) = try inserted()
        #expect(drop.trip.session.page.block(ids[0])?.props.source == "Attachments/Beach.png")
    }

    @Test func theCopyIsByteForByte() throws {
        let (drop, _) = try inserted()
        #expect(importer.attachment("Attachments/Beach.png", in: drop.trip.notes) == (try Data(contentsOf: drop.trip.photo)))
    }

    @Test func aFileThatVanishedKeepsItsLink() throws {
        let (drop, ids) = try inserted()
        #expect(drop.trip.session.page.block(ids[1])?.props.source == drop.sources[1])
    }

    @Test func aVanishedFilesCopyFailureIsRecorded() throws {
        let (drop, _) = try inserted()
        #expect(importer.imports.takeFailure(of: drop.sources[1], in: drop.trip.session) != nil)
    }

    @Test func aVanishedFileReadsAsMissing() throws {
        let (drop, _) = try inserted()
        let source = NoteMediaSource(drop.sources[1], resolve: { drop.trip.file.environment.resolve($0) })
        #expect(source.readiness(for: .video, importing: false) == .missing)
    }

    @Test func undoTakesTheDropBack() throws {
        let (drop, ids) = try inserted()
        drop.trip.session.undo()
        #expect(drop.trip.session.page.block(ids[0]) == nil)
    }

    @Test func redoBringsBackTheFinishedSource() throws {
        let (drop, ids) = try inserted()
        drop.trip.session.undo()
        drop.trip.session.redo()
        #expect(drop.trip.session.page.block(ids[0])?.props.source == "Attachments/Beach.png")
    }

    @Test func aSmallPastedPictureLandsRightAway() throws {
        let trip = try importer.trip()
        let pasted = try NoteClipboard.imageBlock(data: importer.bitmapTIFF(side: 2), fileExtension: "tiff", environment: trip.file.environment)
        let source = try #require(pasted.props.source)
        #expect(!importer.imports.isPending(source, in: trip.session))
        #expect(source.hasSuffix(".png"))
    }

    @Test func aTIFFLandsAsAPNG() throws {
        let trip = try importer.trip()
        let pasted = try NoteClipboard.imageBlock(data: importer.bitmapTIFF(side: 2), fileExtension: "tiff", environment: trip.file.environment)
        #expect(importer.attachment(pasted.props.source, in: trip.notes)?.prefix(4) == Data(importer.pngHeader))
    }
}
