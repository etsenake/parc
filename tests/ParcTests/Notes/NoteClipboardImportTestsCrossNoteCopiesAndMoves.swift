import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct NoteClipboardImportTestsCrossNoteCopiesAndMoves {
    private let importer: NoteClipboardImportTestsSupport.Fixture

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    @MainActor private struct Cross {
        let first: NoteFileSession
        let second: NoteFileSession
        let dropped: [NoteBlock]
        let source: String
        let archive: NoteClipboard.Archive
        let payload: NoteClipboard.Payload
        let secondFolder: URL
        let bytes: Data
    }

    private func crossNotePaste() throws -> Cross {
        let photo = importer.root.appendingPathComponent("Shared/Beach.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 4, 4, 4])
        try importer.write(bytes, to: photo)
        let first = try importer.note(importer.root.appendingPathComponent("A/Trip.md"))
        let second = try importer.note(importer.root.appendingPathComponent("B/Plan.md"))
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: first.environment).blocks
        let source = try #require(dropped.first?.props.source)
        first.page.insertBlocks(dropped, .top(first.page.page.blocks.count))
        let payload = NoteClipboard.payload(for: dropped, inline: false, base: importer.root.appendingPathComponent("A", isDirectory: true), plainTextFile: false)
        let data = try #require(NoteClipboard.encode(payload.archive))
        let archive = try #require(NoteClipboard.decode(data))
        return Cross(first: first, second: second, dropped: dropped, source: source, archive: archive, payload: payload,
                     secondFolder: importer.root.appendingPathComponent("B", isDirectory: true), bytes: bytes)
    }

    @Test func aBlockCopiedMidCopyCarriesALinkThatWorks() throws {
        let cross = try crossNotePaste()
        #expect(cross.archive.blocks[0].props.source == cross.source)
        #expect(importer.fileExists(cross.source))
    }

    @Test func markdownCopiedMidCopyCarriesTheWorkingLink() throws {
        let cross = try crossNotePaste()
        #expect(cross.payload.markdown?.contains(cross.source) == true)
        #expect(cross.payload.markdown?.contains("parc-attachment") == false)
    }

    private func pasteIntoSecond(_ cross: Cross) -> [NoteBlock] {
        let pasted = NoteClipboard.rebase(cross.archive, into: cross.second.environment).map { $0.withFreshIDs() }
        cross.second.page.insertBlocks(pasted, .top(cross.second.page.page.blocks.count))
        return pasted
    }

    @Test func pastingItIntoAnotherNoteStartsThatNotesOwnCopy() throws {
        let cross = try crossNotePaste()
        let pasted = NoteClipboard.rebase(cross.archive, into: cross.second.environment).map { $0.withFreshIDs() }
        #expect(pasted[0].props.source == cross.source)
        #expect(importer.imports.isPending(cross.source, in: cross.second.page))
    }

    @Test func eachNoteGetsItsOwnCopyInItsOwnAttachments() throws {
        let cross = try crossNotePaste()
        let pasted = pasteIntoSecond(cross)
        importer.jobs.runAll()
        #expect(cross.first.page.page.block(cross.dropped[0].id)?.props.source == "Attachments/Beach.png")
        #expect(cross.second.page.page.block(pasted[0].id)?.props.source == "Attachments/Beach.png")
        #expect((try? Data(contentsOf: cross.secondFolder.appendingPathComponent("Attachments/Beach.png"))) == cross.bytes)
    }

    @Test func pastingTheOldCopyLaterStillLandsInAttachmentsWithoutADuplicate() throws {
        let cross = try crossNotePaste()
        _ = pasteIntoSecond(cross)
        importer.jobs.runAll()
        let late = pasteIntoSecond(cross)
        importer.jobs.runAll()
        #expect(cross.second.page.page.block(late[0].id)?.props.source == "Attachments/Beach.png")
        #expect(!FileManager.default.fileExists(atPath: cross.secondFolder.appendingPathComponent("Attachments/Beach 2.png").path))
    }

    @Test func aPastedFileLinkParcNeverImportedIsNotCopiedAnywhere() throws {
        let cross = try crossNotePaste()
        let secret = importer.root.appendingPathComponent("Secrets/id_rsa")
        try importer.write(Data([1]), to: secret)
        let forged = NoteClipboard.Archive(blocks: [importer.image(secret.absoluteString, kind: .file)], base: nil, inline: false)
        let refused = NoteClipboard.rebase(forged, into: cross.second.environment)
        #expect(refused[0].props.source == secret.absoluteString)
        #expect(!importer.imports.isPending(secret.absoluteString, in: cross.second.page))
    }

    @MainActor private struct Moved {
        let file: NoteFileSession
        let dropped: [NoteBlock]
        let source: String
        let newFolder: URL
        let destination: URL
        let bytes: Data
    }

    private func movedMidImport() throws -> Moved {
        let photo = importer.root.appendingPathComponent("Shared/Sunset.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 5, 5, 5])
        try importer.write(bytes, to: photo)
        let file = try importer.note(importer.root.appendingPathComponent("Old/Trip.md"))
        let dropped = NoteClipboard.blocks(forFiles: [photo], environment: file.environment).blocks
        let source = try #require(dropped.first?.props.source)
        file.page.insertBlocks(dropped, .top(file.page.page.blocks.count))
        let newFolder = importer.root.appendingPathComponent("New", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        let destination = newFolder.appendingPathComponent("Trip.md")
        try FileManager.default.moveItem(at: importer.root.appendingPathComponent("Old/Trip.md"), to: destination)
        file.handle(.moved(destination))
        return Moved(file: file, dropped: dropped, source: source, newFolder: newFolder, destination: destination, bytes: bytes)
    }

    @Test func theSessionFollowsTheNoteToItsNewFolder() throws {
        let moved = try movedMidImport()
        #expect(NoteFilePaths.key(for: moved.file.url) == NoteFilePaths.key(for: moved.destination))
    }

    @Test func theFinishedCopyIsLinkedFromTheNotesNewFolder() throws {
        let moved = try movedMidImport()
        importer.jobs.runAll()
        #expect(moved.file.page.page.block(moved.dropped[0].id)?.props.source == "Attachments/Sunset.png")
    }

    @Test func thePictureLivesInTheNewFoldersAttachmentsAndTheLinkResolves() throws {
        let moved = try movedMidImport()
        importer.jobs.runAll()
        #expect(try Data(contentsOf: moved.newFolder.appendingPathComponent("Attachments/Sunset.png")) == moved.bytes)
        let landed = moved.file.page.page.block(moved.dropped[0].id)?.props.source
        #expect(landed.flatMap { moved.file.environment.resolve($0) }.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func theFirstCopyDoesNotLingerInTheOldFolder() throws {
        _ = try movedMidImport()
        importer.jobs.runAll()
        #expect(!FileManager.default.fileExists(atPath: importer.root.appendingPathComponent("Old/Attachments/Sunset.png").path))
    }

    @Test func whenTheCopyCannotBeMadeTheLinkPointsBackToWhereThePictureLanded() throws {
        let moved = try movedMidImport()
        let stranded = importer.root.appendingPathComponent("Old/Attachments/Kept.png")
        try importer.write(moved.bytes, to: stranded)
        let readOnly = importer.root.appendingPathComponent("Locked/Note.md")
        try FileManager.default.createDirectory(at: readOnly.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.deletingLastPathComponent().path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.deletingLastPathComponent().path) }
        let fallback = try NoteAttachmentImports.rebase(stranded, created: true, into: readOnly, discardingOriginal: true)
        #expect(fallback == NoteAttachments.Placement(path: "../Old/Attachments/Kept.png", created: true))
        #expect(FileManager.default.fileExists(atPath: stranded.path))
    }

    @Test func aPictureThisImportDidNotMakeIsCopiedNeverTakenAway() throws {
        let moved = try movedMidImport()
        let shared = importer.root.appendingPathComponent("Old/Attachments/Shared.png")
        try importer.write(moved.bytes, to: shared)
        let kept = try NoteAttachmentImports.rebase(shared, created: false, into: moved.destination, discardingOriginal: false)
        #expect(kept == NoteAttachments.Placement(path: "Attachments/Shared.png", created: true))
        #expect(FileManager.default.fileExists(atPath: shared.path))
    }
}
