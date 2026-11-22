import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteClipboardImportTestsStagingAndReplacement {
    private let importer: NoteClipboardImportTestsSupport.Fixture

    init() throws { importer = try NoteClipboardImportTestsSupport.Fixture() }

    @MainActor private struct Staged {
        let file: NoteFileSession
        let session: NotePageSession
        let source: String
    }

    private func stagedNote() throws -> Staged {
        let staged = try NoteAttachments.stage(Data(repeating: 0x42, count: 64), fileExtension: "gif", suggestedName: "Pasted Image")
        let page = importer.root.appendingPathComponent("Notes/Left Open.md")
        let file = try importer.note(page, "![](" + staged.absoluteString + ")\n")
        return Staged(file: file, session: file.page, source: try #require(file.page.page.blocks.first?.props.source))
    }

    @Test func aNoteSavedMidCopyOpensWithTheTemporaryLink() throws {
        let staged = try stagedNote()
        #expect(staged.source.hasPrefix("file://"))
        #expect(NoteAttachments.isStaged(try #require(URL(string: staged.source))))
    }

    @Test func showingAStagedImageResumesItsCopy() throws {
        let staged = try stagedNote()
        NoteMediaImport.resume(staged.source, environment: staged.file.environment)
        #expect(importer.imports.isPending(staged.source, in: staged.session))
    }

    @Test func theResumedCopyFinishesIntoAttachments() throws {
        let staged = try stagedNote()
        NoteMediaImport.resume(staged.source, environment: staged.file.environment)
        importer.jobs.runAll()
        #expect(staged.session.page.blocks.first?.props.source == "Attachments/Pasted%20Image.gif")
    }

    @Test func settledSourcesAreLeftAlone() throws {
        let staged = try stagedNote()
        NoteMediaImport.resume("Attachments/Pasted%20Image.gif", environment: staged.file.environment)
        #expect(!importer.imports.isPending("Attachments/Pasted%20Image.gif", in: staged.session))
    }

    @MainActor private struct Replace {
        let file: NoteFileSession
        let session: NotePageSession
        let id: NoteBlockID
        let photo: URL
        let sky: URL
        let attachments: URL
    }

    private func replaceFixture() throws -> Replace {
        let photo = importer.root.appendingPathComponent("Pick/Beach.png")
        let sky = importer.root.appendingPathComponent("Pick/Sky.jpg")
        try importer.write(Data([0x89, 0x50, 0x4E, 0x47, 5]), to: photo)
        try importer.write(Data([0xFF, 0xD8, 0xFF, 6]), to: sky)
        let page = importer.root.appendingPathComponent("Notes/Trip.md")
        let attachments = page.deletingLastPathComponent().appendingPathComponent("Attachments")
        try importer.write(Data([1]), to: attachments.appendingPathComponent("Old.png"))
        let file = try importer.note(page, "![](Attachments/Old.png)\n")
        return Replace(file: file, session: file.page, id: try #require(file.page.page.blocks.first?.id), photo: photo, sky: sky, attachments: attachments)
    }

    private func replace(_ fixture: Replace, with url: URL) throws -> String {
        try NoteMediaImport.replace(fixture.id, with: url, name: "Replace Image", in: fixture.session, environment: fixture.file.environment)
        return try #require(fixture.session.page.block(fixture.id)?.props.source)
    }

    @Test func replaceShowsThePickedFileRightAway() throws {
        let fixture = try replaceFixture()
        let source = try replace(fixture, with: fixture.photo)
        #expect(source.hasPrefix("file://"))
        #expect(importer.fileExists(source))
    }

    @Test func replaceStartsABackgroundCopy() throws {
        let fixture = try replaceFixture()
        let source = try replace(fixture, with: fixture.photo)
        #expect(importer.imports.isPending(source, in: fixture.session))
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

    private func replacedAndLanded() throws -> Replace {
        let fixture = try replaceFixture()
        _ = try replace(fixture, with: fixture.photo)
        importer.jobs.runAll()
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

    private func undoneMidCopy() throws -> (Replace, String) {
        let fixture = try replacedAndLanded()
        let skySource = try replace(fixture, with: fixture.sky)
        fixture.session.undo()
        importer.jobs.runAll()
        return (fixture, skySource)
    }

    @Test func undoingMidCopyKeepsThePreviousPicture() throws {
        let (fixture, _) = try undoneMidCopy()
        #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Beach.png")
    }

    @Test func redoAfterTheCopyLandsHealsToTheCopiedFile() throws {
        let (fixture, _) = try undoneMidCopy()
        fixture.session.redo()
        importer.jobs.runAll()
        importer.clock.advance(0.01)
        #expect(fixture.session.page.block(fixture.id)?.props.source == "Attachments/Sky.jpg")
    }

    private func coverUpload() throws -> (Replace, String) {
        let fixture = try replaceFixture()
        let coverSource = try NoteMediaImport.source(importing: fixture.sky, environment: fixture.file.environment, scoped: true)
        fixture.session.updateSettings(name: "Change Cover") { $0.cover = NoteCover(source: coverSource, position: 0.5) }
        return (fixture, coverSource)
    }

    @Test func aCoverUploadShowsThePickedFile() throws {
        let (_, source) = try coverUpload()
        #expect(source.hasPrefix("file://"))
    }

    @Test func aCoverUploadStartsABackgroundCopy() throws {
        let (fixture, source) = try coverUpload()
        #expect(importer.imports.isPending(source, in: fixture.session))
    }

    @Test func theCoverSettlesOnTheCopy() throws {
        let (fixture, _) = try coverUpload()
        importer.jobs.runAll()
        #expect(fixture.session.page.settings.cover?.source == "Attachments/Sky.jpg")
    }

    @Test func undoRemovesTheCoverInOneStep() throws {
        let (fixture, _) = try coverUpload()
        importer.jobs.runAll()
        fixture.session.undo()
        #expect(fixture.session.page.settings.cover == nil)
    }

    @Test func redoBringsBackTheCopiedCover() throws {
        let (fixture, _) = try coverUpload()
        importer.jobs.runAll()
        fixture.session.undo()
        fixture.session.redo()
        #expect(fixture.session.page.settings.cover?.source == "Attachments/Sky.jpg")
    }
}
