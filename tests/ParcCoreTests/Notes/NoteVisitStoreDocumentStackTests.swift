import Foundation
import Testing
@testable import ParcCore

@MainActor struct NoteVisitStoreDocumentStackTests {
    @MainActor private struct Stack {
        let store: BrowserStore
        let page: UUID
        let board: UUID
        let readme: URL
        let guide: URL

        var a: String { readme.absoluteString }
        var b: String { InternalPage.easel(board).urlString }
        var c: String { guide.absoluteString }

        func openDocuments() {
            store.openDocumentOverPage(page, page: .note(readme), title: "Readme")
            store.openDocumentOverPage(page, page: .easel(board), title: "Board")
            store.openDocumentOverPage(page, page: .note(guide), title: "Stacked")
        }

        func renameBoard() {
            store.updateEaselTitle(id: board, profileID: store.activeSpace.profileID, title: "Plans")
        }

        func moveGuide(to renamed: URL) throws {
            try FileManager.default.moveItem(at: guide, to: renamed)
            store.updateNoteFile(from: guide, to: renamed, title: "Moved")
        }

        func deleteBoard() {
            store.deleteLocalDocument(.easel(board), profileID: store.activeSpace.profileID, ownerValid: { true },
                                      deleteDocument: {}, completion: { _ in })
        }
    }

    private func makeStack(_ fixture: NoteVisitTestsSupport.Fixture) throws -> Stack {
        let location = fixture.directory.appendingPathComponent("stacks")
        let guide = fixture.notes.appendingPathComponent("Stacked.md")
        try Data("# Stacked\n".utf8).write(to: guide)
        let store = try BrowserStore(directory: location)
        let page = store.open("https://example.test/stack")
        store.updateTab(page, title: "Stack", url: "https://example.test/stack")
        return Stack(store: store, page: page, board: UUID(), readme: fixture.readme, guide: guide)
    }

    private func restart(_ fixture: NoteVisitTestsSupport.Fixture) throws -> Stack {
        let stack = try makeStack(fixture)
        stack.openDocuments()
        stack.store.stepNoteVisit(stack.page, forward: false)
        stack.renameBoard()
        try stack.store.save()
        let store = try BrowserStore(directory: fixture.directory.appendingPathComponent("stacks"))
        return Stack(store: store, page: stack.page, board: stack.board, readme: stack.readme, guide: stack.guide)
    }

    @Test func theStoreCanStackANoteAnEaselAndAnotherNote() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        let store = stack.store, page = stack.page
        let readme = stack.readme, board = stack.board, guide = stack.guide
        #expect(store.openDocumentOverPage(page, page: .note(readme), title: "Readme")
                   && store.openDocumentOverPage(page, page: .easel(board), title: "Board")
                   && store.openDocumentOverPage(page, page: .note(guide), title: "Stacked"), "The store stacks three documents")
    }

    @Test func storeBackFromTheTopOfTheStackShowsTheEasel() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        stack.openDocuments()
        let store = stack.store, page = stack.page
        let b = stack.b
        #expect(store.stepNoteVisit(page, forward: false) && store.state.tab(page)?.url == b, "Back shows the Easel")
    }

    @Test func movingBetweenDocumentsUpdatesChromeLayout() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        stack.openDocuments()
        let store = stack.store, page = stack.page
        let before = store.state
        store.stepNoteVisit(page, forward: false)
        #expect(!store.state.preservesChromeLayout(relativeTo: before), "Moving between documents redraws the arrows")
    }

    @Test func theStoreCanJumpFromTheEaselToThePage() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        stack.openDocuments()
        let store = stack.store, page = stack.page
        store.stepNoteVisit(page, forward: false)
        #expect(store.stepNoteVisit(page, by: -2) && store.state.tab(page)?.url == "https://example.test/stack", "A jump lands on the page")
    }

    @Test func theStoreCanJumpForwardToTheEasel() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        stack.openDocuments()
        let store = stack.store, page = stack.page
        store.stepNoteVisit(page, by: -3)
        #expect(store.stepNoteVisit(page, by: 2), "and back to the Easel")
    }

    @Test func renamingTheEaselUpdatesItsStepInTheStack() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try makeStack(fixture)
        stack.openDocuments()
        let store = stack.store, page = stack.page
        store.stepNoteVisit(page, forward: false)
        stack.renameBoard()
        #expect(store.state.tab(page)?.title == "Plans" && store.state.tab(page)?.noteVisit?.documents.map(\.title) == ["Readme", "Plans", "Stacked"], "Renaming an Easel in the stack renames its step")
    }

    @Test func theStoreRestoresEveryDocumentAndTheCurrentStep() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try restart(fixture)
        let store = stack.store, page = stack.page
        let a = stack.a, b = stack.b, c = stack.c
        let restored = try #require(store.state.tab(page)?.noteVisit, "restored stack")
        #expect(restored.documents.map(\.url) == [a, b, c] && restored.position == 2 && store.state.tab(page)?.url == b, "A restart restores every step and where the tab stood")
    }

    @Test func renamingANoteAheadInTheStackKeepsItsPlace() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try restart(fixture)
        let store = stack.store, page = stack.page
        let renamed = fixture.notes.appendingPathComponent("Moved.md")
        try stack.moveGuide(to: renamed)
        let b = stack.b
        #expect(store.state.tab(page)?.noteVisit?.ahead.compactMap(\.document) == [.init(url: renamed.absoluteString, title: "Moved")]
                   && store.state.tab(page)?.url == b, "A renamed note ahead keeps its place")
    }

    @Test func theStoreReportsSuccessfulEaselDeletion() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try restart(fixture)
        let store = stack.store, board = stack.board
        var finished: Error??
        store.deleteLocalDocument(.easel(board), profileID: store.activeSpace.profileID, ownerValid: { true },
                                  deleteDocument: {}, completion: { finished = .some($0) })
        #expect(finished != nil && finished! == nil, "The Easel is deleted")
    }

    @Test func deletingTheShownEaselKeepsTheNotesOnEitherSide() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try restart(fixture)
        let store = stack.store, page = stack.page
        let renamed = fixture.notes.appendingPathComponent("Moved.md")
        try stack.moveGuide(to: renamed)
        stack.deleteBoard()
        let a = stack.a
        let after = try #require(store.state.tab(page), "after delete")
        #expect(after.url == a && after.noteVisit?.documents.map(\.url) == [a, renamed.absoluteString], "Deleting the shown Easel shows the note behind it and keeps the note ahead")
    }

    @Test func storeForwardReachesTheNoteAfterADeletedEasel() throws {
        let fixture = try NoteVisitTestsSupport.Fixture()
        let stack = try restart(fixture)
        let store = stack.store, page = stack.page
        let renamed = fixture.notes.appendingPathComponent("Moved.md")
        try stack.moveGuide(to: renamed)
        stack.deleteBoard()
        #expect(store.stepNoteVisit(page, forward: true) && store.state.tab(page)?.url == renamed.absoluteString, "Forward still reaches the note after it")
    }
}
