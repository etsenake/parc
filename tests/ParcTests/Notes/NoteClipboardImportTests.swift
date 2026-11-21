import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

extension NoteEditorProcessWide {
    @MainActor
    final class NoteClipboardImportTests {
        let clock = NoteEditorManualClock()
        let jobs = NoteFileDeferredJobs()
        let folder: NoteEditorTemporaryFolder
        let imports = NoteAttachmentImports.shared
        var root: URL { folder.url }

        init() throws {
            NoteFileSession.clock = clock
            NoteFileSession.worker = .inline
            imports.worker = NoteFileWorker(deferred: jobs)
            imports.clock = clock
            folder = try NoteEditorTemporaryFolder("clipboard")
        }

        let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

        func note(_ path: URL, _ text: String = "Hello\n") throws -> NoteFileSession {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
            return try NoteFileSession.open(path)
        }

        func fileExists(_ source: String?) -> Bool {
            guard let source, let url = URL(string: source), url.isFileURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }

        func image(_ source: String?, kind: NoteBlockKind = .image) -> NoteBlock {
            var block = NoteBlock(kind)
            block.props.source = source
            return block
        }

        func bitmapTIFF(side: Int) -> Data {
            NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?.tiffRepresentation ?? Data()
        }

        func write(_ bytes: Data, to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }

        @MainActor struct Trip {
            let notes: URL
            let photo: URL
            let file: NoteFileSession
            let session: NotePageSession
        }

        func trip() throws -> Trip {
            let outside = root.appendingPathComponent("Outside", isDirectory: true)
            let notes = root.appendingPathComponent("Notes", isDirectory: true)
            let photo = outside.appendingPathComponent("Beach.png")
            try write(Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), to: photo)
            let file = try note(notes.appendingPathComponent("Trip.md"))
            return Trip(notes: notes, photo: photo, file: file, session: file.page)
        }

        func attachment(_ source: String?, in notes: URL) -> Data? {
            guard let source, let path = source.removingPercentEncoding else { return nil }
            return try? Data(contentsOf: notes.appendingPathComponent(path))
        }

        @MainActor struct Drop {
            let trip: Trip
            let dropped: (blocks: [NoteBlock], failures: [Error])
            let sources: [String]
        }

        func dropPhoto() throws -> Drop {
            let trip = try trip()
            let gone = root.appendingPathComponent("Outside/Gone.mov")
            let dropped = NoteClipboard.blocks(forFiles: [trip.photo, gone], environment: trip.file.environment)
            return Drop(trip: trip, dropped: dropped, sources: dropped.blocks.compactMap(\.props.source))
        }

        @Test func droppedFilesBecomeBlocksRightAway() throws {
            let drop = try dropPhoto()
            #expect(drop.dropped.failures.isEmpty)
            #expect(drop.sources.count == 2)
        }

        @Test func theyPointAtTheOriginalsWhileTheCopyRuns() throws {
            let drop = try dropPhoto()
            #expect(drop.sources.allSatisfy { $0.hasPrefix("file://") && imports.isPending($0, in: drop.trip.session) })
        }

        @Test func theDroppedPictureShowsUpStraightAway() throws {
            let drop = try dropPhoto()
            #expect(fileExists(drop.sources[0]))
            #expect(URL(string: drop.sources[0])?.lastPathComponent == "Beach.png")
        }

        func inserted() throws -> (Drop, [NoteBlockID]) {
            let drop = try dropPhoto()
            let ids = drop.trip.session.insertBlocks(drop.dropped.blocks, .top(drop.trip.session.page.blocks.count))
            jobs.runAll()
            return (drop, ids)
        }

        @Test func theFinishedCopyBecomesTheBlocksSource() throws {
            let (drop, ids) = try inserted()
            #expect(drop.trip.session.page.block(ids[0])?.props.source == "Attachments/Beach.png")
        }

        @Test func theCopyIsByteForByte() throws {
            let (drop, _) = try inserted()
            #expect(attachment("Attachments/Beach.png", in: drop.trip.notes) == (try Data(contentsOf: drop.trip.photo)))
        }

        @Test func aFileThatVanishedKeepsItsLinkAndRemembersWhyItDidNotCopy() throws {
            let (drop, ids) = try inserted()
            #expect(drop.trip.session.page.block(ids[1])?.props.source == drop.sources[1])
            #expect(imports.takeFailure(of: drop.sources[1], in: drop.trip.session) != nil)
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
            let trip = try trip()
            let pasted = try NoteClipboard.imageBlock(data: bitmapTIFF(side: 2), fileExtension: "tiff", environment: trip.file.environment)
            let source = try #require(pasted.props.source)
            #expect(!imports.isPending(source, in: trip.session))
            #expect(source.hasSuffix(".png"))
        }

        @Test func aTIFFLandsAsAPNG() throws {
            let trip = try trip()
            let pasted = try NoteClipboard.imageBlock(data: bitmapTIFF(side: 2), fileExtension: "tiff", environment: trip.file.environment)
            #expect(attachment(pasted.props.source, in: trip.notes)?.prefix(4) == Data(pngHeader))
        }

        @MainActor struct BigPaste {
            let trip: Trip
            let big: Data
            let block: NoteBlock
            let source: String
        }

        func bigPaste() throws -> BigPaste {
            let trip = try trip()
            let big = bitmapTIFF(side: 1200)
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

        @Test func itsCopyRunsInTheBackground() throws {
            let paste = try bigPaste()
            #expect(imports.isPending(paste.source, in: paste.trip.session))
        }

        func landedBigPaste() throws -> (BigPaste, String) {
            let paste = try bigPaste()
            paste.trip.session.insertBlocks([paste.block], .top(paste.trip.session.page.blocks.count))
            paste.trip.session.undo()
            jobs.runAll()
            return (paste, try #require(imports.landedPath(for: paste.source, in: paste.trip.session)))
        }

        @Test func aBigTIFFLandsAsAPNGToo() throws {
            let (paste, path) = try landedBigPaste()
            #expect(path.hasSuffix(".png"))
            #expect(attachment(path, in: paste.trip.notes)?.prefix(4) == Data(pngHeader))
        }

        @Test func redoingAPasteThatFinishedWhileUndoneHealsItsSource() throws {
            let (paste, path) = try landedBigPaste()
            paste.trip.session.redo()
            jobs.runAll()
            clock.advance(0.01)
            #expect(paste.trip.session.page.block(paste.block.id)?.props.source == path)
        }

        @Test func smallDataURLsLandInAttachmentsStraightAway() throws {
            let trip = try trip()
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 9, 9])
            let decoded = NoteClipboard.importInlineMedia([image("data:image/png;base64," + bytes.base64EncodedString())], environment: trip.file.environment)
            #expect(decoded.failures.isEmpty)
            #expect(attachment(decoded.blocks[0].props.source, in: trip.notes) == bytes)
        }

        func fromAnotherNote() throws -> (Trip, [NoteBlock], String) {
            let trip = try trip()
            let other = root.appendingPathComponent("Other", isDirectory: true)
            try write(Data([7, 7]), to: other.appendingPathComponent("Attachments/cat.png"))
            let rebased = NoteClipboard.rebase(NoteClipboard.Archive(blocks: [image("Attachments/cat.png")], base: other, inline: false), into: trip.file.environment)
            return (trip, rebased, rebased[0].props.source ?? "")
        }

        @Test func mediaFromAnotherNotesFolderShowsFromThereWhileItCopies() throws {
            let (trip, _, source) = try fromAnotherNote()
            #expect(source.hasPrefix("file://"))
            #expect(fileExists(source))
            #expect(imports.isPending(source, in: trip.session))
        }

        @Test func itArrivesIntact() throws {
            let (trip, rebased, _) = try fromAnotherNote()
            trip.session.insertBlocks(rebased, .top(trip.session.page.blocks.count))
            jobs.runAll()
            #expect(attachment(trip.session.page.block(rebased[0].id)?.props.source, in: trip.notes) == Data([7, 7]))
        }

        @Test func ordinarySourcesAreNotImports() throws {
            let trip = try trip()
            #expect(!imports.isPending("Attachments/cat.png", in: trip.session))
        }

        @MainActor struct Quit {
            let page: URL
            let file: NoteFileSession
            let session: NotePageSession
            let sources: [String]
            let huge: Data
            let text: String
        }

        func quitMidCopy() throws -> Quit {
            let movie = root.appendingPathComponent("Outside/Big Trip.mov")
            try write(Data(repeating: 3, count: 2048), to: movie)
            let page = root.appendingPathComponent("Notes/Trip.md")
            let file = try note(page)
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
            #expect(quit.sources.allSatisfy { imports.isPending($0, in: quit.session) })
        }

        @Test func noPlaceholderTokenIsEverWritten() throws {
            #expect(!(try quitMidCopy()).text.contains("parc-attachment"))
        }

        @Test func theSavedNoteLinksToFilesThatReallyExist() throws {
            let quit = try quitMidCopy()
            let environment = NoteFileEnvironment(documentURL: quit.page, isPlainText: false)
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
            jobs.runAll()
            #expect(try String(contentsOf: quit.page, encoding: .utf8) == quit.text)
        }

        func reopened(_ quit: Quit) throws -> NoteFileSession {
            jobs.runAll()
            let file = try note(quit.page, quit.text)
            file.retain()
            return file
        }

        @Test func reopeningGivesAFreshSessionStartingFromTheWorkingLinks() throws {
            let quit = try quitMidCopy()
            let file = try reopened(quit)
            defer { file.release() }
            #expect(file.page !== quit.session)
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
            jobs.runAll()
            let landed = quit.page.deletingLastPathComponent().appendingPathComponent("Attachments/Pasted Image.png")
            #expect(try Data(contentsOf: landed) == quit.huge)
        }

        @MainActor struct Failed {
            let session: NotePageSession
            let file: NoteFileSession
            let source: String
            let photo: URL
            let block: NoteBlock
        }

        func failedImport() throws -> Failed {
            let photo = root.appendingPathComponent("Sunset.jpg")
            try write(Data([0xFF, 0xD8, 0xFF, 1]), to: photo)
            let page = root.appendingPathComponent("Notes/Trip.md")
            let file = try note(page)
            try Data("not a folder".utf8).write(to: page.deletingLastPathComponent().appendingPathComponent("Attachments"))
            let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment)
            let source = try #require(dropped.blocks.first?.props.source)
            file.page.insertBlocks(dropped.blocks, .top(file.page.page.blocks.count))
            jobs.runAll()
            return Failed(session: file.page, file: file, source: source, photo: photo, block: dropped.blocks[0])
        }

        @Test func aCopyThatFailsKeepsTheOriginalLink() throws {
            let failed = try failedImport()
            #expect(failed.session.page.block(failed.block.id)?.props.source == failed.source)
        }

        @Test func nothingClaimsToHaveLanded() throws {
            let failed = try failedImport()
            #expect(imports.landedPath(for: failed.source, in: failed.session) == nil)
        }

        @Test func theFailureIsRememberedAndReportedOnce() throws {
            let failed = try failedImport()
            #expect(imports.takeFailure(of: failed.source, in: failed.session) != nil)
            #expect(imports.takeFailure(of: failed.source, in: failed.session) == nil)
        }

        func failedMedia(_ failed: Failed) -> NoteMediaSource {
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

        @Test func itReadsAsBrokenOnlyOnceTheOriginalIsGone() throws {
            let failed = try failedImport()
            try FileManager.default.removeItem(at: failed.photo)
            #expect(failedMedia(failed).readiness(for: .image, importing: false) == .missing)
        }

        @Test func theHeadsUpNamesTheFile() {
            #expect(NoteAttachmentError.leftInPlace("Sunset.jpg").errorDescription?.contains("Sunset.jpg") == true)
        }

        @MainActor struct Cross {
            let first: NoteFileSession
            let second: NoteFileSession
            let dropped: [NoteBlock]
            let source: String
            let archive: NoteClipboard.Archive
            let payload: NoteClipboard.Payload
            let secondFolder: URL
            let bytes: Data
        }

        func crossNotePaste() throws -> Cross {
            let photo = root.appendingPathComponent("Shared/Beach.png")
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 4, 4, 4])
            try write(bytes, to: photo)
            let first = try note(root.appendingPathComponent("A/Trip.md"))
            let second = try note(root.appendingPathComponent("B/Plan.md"))
            let dropped = NoteClipboard.blocks(forFiles: [photo], environment: first.environment).blocks
            let source = try #require(dropped.first?.props.source)
            first.page.insertBlocks(dropped, .top(first.page.page.blocks.count))
            let payload = NoteClipboard.payload(for: dropped, inline: false, base: root.appendingPathComponent("A", isDirectory: true), plainTextFile: false)
            let data = try #require(NoteClipboard.encode(payload.archive))
            let archive = try #require(NoteClipboard.decode(data))
            return Cross(first: first, second: second, dropped: dropped, source: source, archive: archive, payload: payload,
                         secondFolder: root.appendingPathComponent("B", isDirectory: true), bytes: bytes)
        }

        @Test func aBlockCopiedMidCopyCarriesALinkThatWorks() throws {
            let cross = try crossNotePaste()
            #expect(cross.archive.blocks[0].props.source == cross.source)
            #expect(fileExists(cross.source))
        }

        @Test func andSoDoesItsMarkdown() throws {
            let cross = try crossNotePaste()
            #expect(cross.payload.markdown?.contains(cross.source) == true)
            #expect(cross.payload.markdown?.contains("parc-attachment") == false)
        }

        func pasteIntoSecond(_ cross: Cross) -> [NoteBlock] {
            let pasted = NoteClipboard.rebase(cross.archive, into: cross.second.environment).map { $0.withFreshIDs() }
            cross.second.page.insertBlocks(pasted, .top(cross.second.page.page.blocks.count))
            return pasted
        }

        @Test func pastingItIntoAnotherNoteStartsThatNotesOwnCopy() throws {
            let cross = try crossNotePaste()
            let pasted = NoteClipboard.rebase(cross.archive, into: cross.second.environment).map { $0.withFreshIDs() }
            #expect(pasted[0].props.source == cross.source)
            #expect(imports.isPending(cross.source, in: cross.second.page))
        }

        @Test func eachNoteGetsItsOwnCopyInItsOwnAttachments() throws {
            let cross = try crossNotePaste()
            let pasted = pasteIntoSecond(cross)
            jobs.runAll()
            #expect(cross.first.page.page.block(cross.dropped[0].id)?.props.source == "Attachments/Beach.png")
            #expect(cross.second.page.page.block(pasted[0].id)?.props.source == "Attachments/Beach.png")
            #expect((try? Data(contentsOf: cross.secondFolder.appendingPathComponent("Attachments/Beach.png"))) == cross.bytes)
        }

        @Test func pastingTheOldCopyLaterStillLandsInAttachmentsWithoutADuplicate() throws {
            let cross = try crossNotePaste()
            _ = pasteIntoSecond(cross)
            jobs.runAll()
            let late = pasteIntoSecond(cross)
            jobs.runAll()
            #expect(cross.second.page.page.block(late[0].id)?.props.source == "Attachments/Beach.png")
            #expect(!FileManager.default.fileExists(atPath: cross.secondFolder.appendingPathComponent("Attachments/Beach 2.png").path))
        }

        @Test func aPastedFileLinkParcNeverImportedIsNotCopiedAnywhere() throws {
            let cross = try crossNotePaste()
            let secret = root.appendingPathComponent("Secrets/id_rsa")
            try write(Data([1]), to: secret)
            let forged = NoteClipboard.Archive(blocks: [image(secret.absoluteString, kind: .file)], base: nil, inline: false)
            let refused = NoteClipboard.rebase(forged, into: cross.second.environment)
            #expect(refused[0].props.source == secret.absoluteString)
            #expect(!imports.isPending(secret.absoluteString, in: cross.second.page))
        }

        @MainActor struct Moved {
            let file: NoteFileSession
            let dropped: [NoteBlock]
            let source: String
            let newFolder: URL
            let destination: URL
            let bytes: Data
        }

        func movedMidImport() throws -> Moved {
            let photo = root.appendingPathComponent("Shared/Sunset.png")
            let bytes = Data([0x89, 0x50, 0x4E, 0x47, 5, 5, 5])
            try write(bytes, to: photo)
            let file = try note(root.appendingPathComponent("Old/Trip.md"))
            let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment).blocks
            let source = try #require(dropped.first?.props.source)
            file.page.insertBlocks(dropped, .top(file.page.page.blocks.count))
            let newFolder = root.appendingPathComponent("New", isDirectory: true)
            try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
            let destination = newFolder.appendingPathComponent("Trip.md")
            try FileManager.default.moveItem(at: root.appendingPathComponent("Old/Trip.md"), to: destination)
            file.handle(.moved(destination))
            return Moved(file: file, dropped: dropped, source: source, newFolder: newFolder, destination: destination, bytes: bytes)
        }

        @Test func theSessionFollowsTheNoteToItsNewFolder() throws {
            let moved = try movedMidImport()
            #expect(NoteFilePaths.key(for: moved.file.url) == NoteFilePaths.key(for: moved.destination))
        }

        @Test func theFinishedCopyIsLinkedFromTheNotesNewFolder() throws {
            let moved = try movedMidImport()
            jobs.runAll()
            #expect(moved.file.page.page.block(moved.dropped[0].id)?.props.source == "Attachments/Sunset.png")
        }

        @Test func thePictureLivesInTheNewFoldersAttachmentsAndTheLinkResolves() throws {
            let moved = try movedMidImport()
            jobs.runAll()
            #expect(try Data(contentsOf: moved.newFolder.appendingPathComponent("Attachments/Sunset.png")) == moved.bytes)
            let landed = moved.file.page.page.block(moved.dropped[0].id)?.props.source
            #expect(landed.flatMap { moved.file.environment.resolve($0) }.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        }

        @Test func theFirstCopyDoesNotLingerInTheOldFolder() throws {
            _ = try movedMidImport()
            jobs.runAll()
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Old/Attachments/Sunset.png").path))
        }

        @Test func whenTheCopyCannotBeMadeTheLinkPointsBackToWhereThePictureLanded() throws {
            let moved = try movedMidImport()
            let stranded = root.appendingPathComponent("Old/Attachments/Kept.png")
            try write(moved.bytes, to: stranded)
            let readOnly = root.appendingPathComponent("Locked/Note.md")
            try FileManager.default.createDirectory(at: readOnly.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.deletingLastPathComponent().path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.deletingLastPathComponent().path) }
            let fallback = try NoteAttachmentImports.rebase(stranded, created: true, into: readOnly, discardingOriginal: true)
            #expect(fallback == NoteAttachments.Placement(path: "../Old/Attachments/Kept.png", created: true))
            #expect(FileManager.default.fileExists(atPath: stranded.path))
        }

        @Test func aPictureThisImportDidNotMakeIsCopiedNeverTakenAway() throws {
            let moved = try movedMidImport()
            let shared = root.appendingPathComponent("Old/Attachments/Shared.png")
            try write(moved.bytes, to: shared)
            let kept = try NoteAttachmentImports.rebase(shared, created: false, into: moved.destination, discardingOriginal: false)
            #expect(kept == NoteAttachments.Placement(path: "Attachments/Shared.png", created: true))
            #expect(FileManager.default.fileExists(atPath: shared.path))
        }

        @MainActor struct Staged {
            let file: NoteFileSession
            let session: NotePageSession
            let source: String
        }

        func stagedNote() throws -> Staged {
            let staged = try NoteAttachments.stage(Data(repeating: 0x42, count: 64), fileExtension: "gif", suggestedName: "Pasted Image")
            let page = root.appendingPathComponent("Notes/Left Open.md")
            let file = try note(page, "![](" + staged.absoluteString + ")\n")
            return Staged(file: file, session: file.page, source: try #require(file.page.page.blocks.first?.props.source))
        }

        @Test func aNoteSavedMidCopyOpensWithTheTemporaryLink() throws {
            let staged = try stagedNote()
            #expect(staged.source.hasPrefix("file://"))
            #expect(NoteAttachments.isStaged(try #require(URL(string: staged.source))))
        }

        @Test func showingItPicksTheCopyBackUp() throws {
            let staged = try stagedNote()
            NoteMediaImport.resume(staged.source, environment: staged.file.environment)
            #expect(imports.isPending(staged.source, in: staged.session))
        }

        @Test func andFinishesItIntoAttachments() throws {
            let staged = try stagedNote()
            NoteMediaImport.resume(staged.source, environment: staged.file.environment)
            jobs.runAll()
            #expect(staged.session.page.blocks.first?.props.source == "Attachments/Pasted%20Image.gif")
        }

        @Test func settledSourcesAreLeftAlone() throws {
            let staged = try stagedNote()
            NoteMediaImport.resume("Attachments/Pasted%20Image.gif", environment: staged.file.environment)
            #expect(!imports.isPending("Attachments/Pasted%20Image.gif", in: staged.session))
        }

        @MainActor struct Replace {
            let file: NoteFileSession
            let session: NotePageSession
            let id: NoteBlockID
            let photo: URL
            let sky: URL
            let attachments: URL
        }

        func replaceFixture() throws -> Replace {
            let photo = root.appendingPathComponent("Pick/Beach.png")
            let sky = root.appendingPathComponent("Pick/Sky.jpg")
            try write(Data([0x89, 0x50, 0x4E, 0x47, 5]), to: photo)
            try write(Data([0xFF, 0xD8, 0xFF, 6]), to: sky)
            let page = root.appendingPathComponent("Notes/Trip.md")
            let attachments = page.deletingLastPathComponent().appendingPathComponent("Attachments")
            try write(Data([1]), to: attachments.appendingPathComponent("Old.png"))
            let file = try note(page, "![](Attachments/Old.png)\n")
            return Replace(file: file, session: file.page, id: try #require(file.page.page.blocks.first?.id), photo: photo, sky: sky, attachments: attachments)
        }

        func replace(_ fixture: Replace, with url: URL) throws -> String {
            try NoteMediaImport.replace(fixture.id, with: url, name: "Replace Image", in: fixture.session, environment: fixture.file.environment)
            return try #require(fixture.session.page.block(fixture.id)?.props.source)
        }

        @Test func replaceSwapsInThePickedFileRightAwayAndCopiesInTheBackground() throws {
            let fixture = try replaceFixture()
            let source = try replace(fixture, with: fixture.photo)
            #expect(source.hasPrefix("file://"))
            #expect(fileExists(source))
            #expect(imports.isPending(source, in: fixture.session))
        }

        @Test func nothingIsCopiedOnTheMainThread() throws {
            let fixture = try replaceFixture()
            _ = try replace(fixture, with: fixture.photo)
            #expect(!FileManager.default.fileExists(atPath: fixture.attachments.appendingPathComponent("Beach.png").path))
        }

        @Test func replaceIsOneUndoStep() throws {
            let fixture = try replaceFixture()
            _ = try replace(fixture, with: fixture.photo)
            #expect(fixture.session.undoActionName == "Replace Image")
        }

        func replacedAndLanded() throws -> Replace {
            let fixture = try replaceFixture()
            _ = try replace(fixture, with: fixture.photo)
            jobs.runAll()
            return fixture
        }

        @Test func theCopyLandsAsTheSource() throws {
            let fixture = try replacedAndLanded()
            #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Beach.png")
        }

        @Test func undoPutsTheOldPictureBackInOneGo() throws {
            let fixture = try replacedAndLanded()
            fixture.session.undo()
            #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Old.png")
        }

        @Test func redoBringsTheCopiedOneBack() throws {
            let fixture = try replacedAndLanded()
            fixture.session.undo()
            fixture.session.redo()
            #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Beach.png")
        }

        func undoneMidCopy() throws -> (Replace, String) {
            let fixture = try replacedAndLanded()
            let skySource = try replace(fixture, with: fixture.sky)
            fixture.session.undo()
            jobs.runAll()
            return (fixture, skySource)
        }

        @Test func undoingMidCopyKeepsThePreviousPicture() throws {
            let (fixture, _) = try undoneMidCopy()
            #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Beach.png")
        }

        @Test func redoAfterTheCopyLandsHealsToTheCopiedFile() throws {
            let (fixture, _) = try undoneMidCopy()
            fixture.session.redo()
            jobs.runAll()
            clock.advance(0.01)
            #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Sky.jpg")
        }

        func coverUpload() throws -> (Replace, String) {
            let fixture = try replaceFixture()
            let coverSource = try NoteMediaImport.source(importing: fixture.sky, environment: fixture.file.environment, scoped: true)
            fixture.session.updateSettings(name: "Change Cover") { $0.cover = NoteCover(source: coverSource, position: 0.5) }
            return (fixture, coverSource)
        }

        @Test func aCoverUploadShowsThePickedFileWhileItCopies() throws {
            let (fixture, source) = try coverUpload()
            #expect(source.hasPrefix("file://"))
            #expect(imports.isPending(source, in: fixture.session))
        }

        @Test func theCoverSettlesOnTheCopy() throws {
            let (fixture, _) = try coverUpload()
            jobs.runAll()
            #expect(fixture.session.page.settings.cover?.source == "Attachments/Sky.jpg")
        }

        @Test func undoRemovesTheCoverInOneStep() throws {
            let (fixture, _) = try coverUpload()
            jobs.runAll()
            fixture.session.undo()
            #expect(fixture.session.page.settings.cover == nil)
        }

        @Test func redoBringsBackTheCopiedCover() throws {
            let (fixture, _) = try coverUpload()
            jobs.runAll()
            fixture.session.undo()
            fixture.session.redo()
            #expect(fixture.session.page.settings.cover?.source == "Attachments/Sky.jpg")
        }
    }
}
