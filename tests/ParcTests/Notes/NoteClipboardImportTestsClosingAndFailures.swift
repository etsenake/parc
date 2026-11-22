import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteClipboardImportTestsClosingAndFailures {
    private let importer: NoteClipboardImportTestsSupport.Fixture

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    @MainActor private struct Quit {
        let page: URL
        let file: NoteFileSession
        let session: NotePageSession
        let sources: [String]
        let huge: Data
        let text: String
    }

    private func quitMidCopy() throws -> Quit {
        let movie = importer.root.appendingPathComponent("Outside/Big Trip.mov")
        try importer.write(Data(repeating: 3, count: 2048), to: movie)
        let page = importer.root.appendingPathComponent("Notes/Trip.md")
        let file = try importer.note(page)
        file.retain()
        let session = file.page
        let dropped = NoteClipboard.blocks(forFiles: [movie], environment: file.environment).blocks
        let huge = Data(repeating: 0xAB, count: NoteMediaImport.stagingThreshold + 1)
        let pasted = try NoteClipboard.imageBlock(data: huge, fileExtension: "png", environment: file.environment)
        session.insertBlocks(dropped + [pasted], .top(session.page.blocks.count))
        let sources = (dropped + [pasted]).compactMap(\.props.source)
        file.release()
        let text = try String(contentsOf: page, encoding: .utf8)
        return Quit(page: page, file: file, session: session, sources: sources, huge: huge, text: text)
    }

    @Test func bothCopiesAreStillRunningWhenTheNoteCloses() throws {
        let quit = try quitMidCopy()
        #expect(quit.sources.count == 2)
        #expect(quit.sources.allSatisfy { importer.imports.isPending($0, in: quit.session) })
    }

    @Test func noPlaceholderTokenIsEverWritten() throws {
        #expect(!(try quitMidCopy()).text.contains("parc-attachment"))
    }

    @Test func theSavedNoteLinksToFilesThatReallyExist() throws {
        let quit = try quitMidCopy()
        let environment = NoteFileEnvironment(documentURL: quit.page, isPlainText: false, files: importer.files)
        let saved = NoteMarkdown.parse(quit.text).blocks.filter(\.kind.isMedia)
        #expect(saved.count == 2)
        #expect(saved.allSatisfy { block in
            guard let url = block.props.source.flatMap(environment.resolve) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        })
    }

    @Test func theSavedNoteKeepsWhatKindOfMediaEachOneIs() throws {
        #expect(NoteMarkdown.parse(try quitMidCopy().text).blocks.filter(\.kind.isMedia).map(\.kind) == [.video, .image])
    }

    @Test func aCopyFinishingAfterTheNoteClosedLeavesTheFileAlone() throws {
        let quit = try quitMidCopy()
        importer.jobs.runAll()
        #expect(try String(contentsOf: quit.page, encoding: .utf8) == quit.text)
    }

    private func reopened(_ quit: Quit) throws -> NoteFileSession {
        importer.jobs.runAll()
        let file = try importer.note(quit.page, quit.text)
        file.retain()
        return file
    }

    @Test func reopeningCreatesAFreshSession() throws {
        let quit = try quitMidCopy()
        let file = try reopened(quit)
        defer { file.release() }
        #expect(file.page !== quit.session)
    }

    @Test func reopeningStartsFromTheWorkingLinks() throws {
        let quit = try quitMidCopy()
        let file = try reopened(quit)
        defer { file.release() }
        #expect(file.page.page.blocks.compactMap(\.props.source) == quit.sources)
    }

    @Test func reopeningInTheSameRunPicksUpTheCopiesThatFinishedMeanwhile() throws {
        let quit = try quitMidCopy()
        let file = try reopened(quit)
        defer { file.release() }
        NoteMediaImport.resume(quit.sources[0], environment: file.environment)
        #expect(file.page.page.blocks.compactMap(\.props.source) == ["Attachments/Big%20Trip.mov", "Attachments/Pasted%20Image.png"])
    }

    @Test func theHugePasteArrivedWhole() throws {
        let quit = try quitMidCopy()
        importer.jobs.runAll()
        let landed = quit.page.deletingLastPathComponent().appendingPathComponent("Attachments/Pasted Image.png")
        #expect(try Data(contentsOf: landed) == quit.huge)
    }

    @MainActor private struct Failed {
        let session: NotePageSession
        let file: NoteFileSession
        let source: String
        let photo: URL
        let block: NoteBlock
    }

    private func failedImport() throws -> Failed {
        let photo = importer.root.appendingPathComponent("Sunset.jpg")
        try importer.write(Data([0xFF, 0xD8, 0xFF, 1]), to: photo)
        let page = importer.root.appendingPathComponent("Notes/Trip.md")
        let file = try importer.note(page)
        try Data("not a folder".utf8).write(to: page.deletingLastPathComponent().appendingPathComponent("Attachments"))
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment)
        let source = try #require(dropped.blocks.first?.props.source)
        file.page.insertBlocks(dropped.blocks, .top(file.page.page.blocks.count))
        importer.jobs.runAll()
        return Failed(session: file.page, file: file, source: source, photo: photo, block: dropped.blocks[0])
    }

    @Test func aCopyThatFailsKeepsTheOriginalLink() throws {
        let failed = try failedImport()
        #expect(failed.session.page.block(failed.block.id)?.props.source == failed.source)
    }

    @Test func nothingClaimsToHaveLanded() throws {
        let failed = try failedImport()
        #expect(importer.imports.landedPath(for: failed.source, in: failed.session) == nil)
    }

    @Test func theFailureIsRememberedAndReportedOnce() throws {
        let failed = try failedImport()
        #expect(importer.imports.takeFailure(of: failed.source, in: failed.session) != nil)
        #expect(importer.imports.takeFailure(of: failed.source, in: failed.session) == nil)
    }

    private func failedMedia(_ failed: Failed) -> NoteMediaSource {
        NoteMediaSource(failed.source) { failed.file.environment.resolve($0) }
    }

    @Test func theBlockStillShowsTheOriginalNotABrokenCard() throws {
        let failed = try failedImport()
        #expect(failedMedia(failed).readiness(for: .image, importing: false) == .ready)
        #expect(failedMedia(failed).readiness(for: .file, importing: false) == .ready)
    }

    @Test func filesShimmerOnlyWhileTheCopyRuns() throws {
        let failed = try failedImport()
        #expect(failedMedia(failed).readiness(for: .file, importing: true) == .importing)
    }

    @Test func pdfsReadFromTheOriginalWhileTheCopyRuns() throws {
        let failed = try failedImport()
        #expect(failedMedia(failed).readiness(for: .pdf, importing: true) == .ready)
    }

    @Test func theMediaReadsAsBrokenOnceTheOriginalIsGone() throws {
        let failed = try failedImport()
        try FileManager.default.removeItem(at: failed.photo)
        #expect(failedMedia(failed).readiness(for: .image, importing: false) == .missing)
    }

    @Test func theHeadsUpNamesTheFile() {
        #expect(NoteAttachmentError.leftInPlace("Sunset.jpg").errorDescription?.contains("Sunset.jpg") == true)
    }
}
