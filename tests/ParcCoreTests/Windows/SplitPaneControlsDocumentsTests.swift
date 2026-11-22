import Foundation
import Testing
@testable import ParcCore

struct SplitPaneControlsDocumentsTests {
    private typealias Fixture = SplitPaneControlsTestsSupport.Fixture

    @MainActor private struct LocalNote {
        let file: URL
        let id: UUID
        let old: BrowserTab

        init(_ f: Fixture) throws {
            file = f.root.appendingPathComponent("Shared Note.md")
            let id = f.store.openNote(url: file, title: "Shared Note")!
            f.store.selectTab(f.b)
            self.id = id
            old = f.store.state.tabs.first { $0.id == id }!
        }

        func join(_ f: Fixture) throws -> Bool {
            let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addBelow, state: f.store.state))
            return f.store.insertSplitPane(draft, tabID: id, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:])
        }
    }

    @MainActor @Test func anExistingLocalNoteCanFillABlankPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        #expect(try note.join(f))
    }

    @MainActor @Test func theLocalNoteRecordIsMovedNeverCloned() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.state.tabs.first { $0.id == note.id }?.url == note.old.url)
        #expect(f.store.state.selectedTabIDs == [f.b, note.id])
    }

    @MainActor @Test func aTodayNoteLeavesNoSavedHome() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(note.file) }.count == 1)
    }

    @MainActor @Test func separatingTheNoteRestoresTheOriginalFirstPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let note = try LocalNote(f)
        _ = try note.join(f)
        #expect(f.store.separateTabFromSplit(note.id, expected: f.store.activeSplitLayout!, focusedID: f.b))
        #expect(f.store.state.selectedTabIDs == [f.b])
    }

    @MainActor private struct LocalEasel {
        let easels: EaselStore
        let easel: EaselSession
        let id: UUID
        let old: BrowserTab

        init(_ f: Fixture) throws {
            easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
            easel = try easels.create()
            let id = f.store.openEasel(id: easel.document.id, title: "Shared Easel")!
            f.store.selectTab(f.b)
            self.id = id
            old = f.store.state.tabs.first { $0.id == id }!
        }

        func join(_ f: Fixture) throws -> Bool {
            let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAfter, state: f.store.state))
            return f.store.insertSplitPane(draft, tabID: id, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:])
        }
    }

    @MainActor @Test func anExistingLocalEaselCanFillABlankPane() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        #expect(try easel.join(f))
    }

    @MainActor @Test func theLocalEaselRecordIsMovedNeverCloned() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(f.store.state.tabs.first { $0.id == easel.id }?.url == easel.old.url)
        #expect(f.store.state.selectedTabIDs == [f.b, easel.id])
    }

    @MainActor @Test func aTodayEaselLeavesNoSavedHome() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url)?.easelID == easel.easel.document.id }.count == 1)
    }

    @MainActor @Test func theSharedEaselSessionRemainsTheOriginal() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let easel = try LocalEasel(f)
        _ = try easel.join(f)
        #expect(try easel.easels.load(easel.easel.document.id) === easel.easel)
    }

    @MainActor private struct Host {
        let id: UUID
        let createdNote: URL
        let draft: SplitPaneInsertion

        init(_ f: Fixture, operation: SplitPaneOperation) throws {
            id = f.store.open("https://later.invalid/host")
            f.store.selectTab(id)
            createdNote = f.root.appendingPathComponent("Untitled.md")
            draft = try #require(SplitPaneInsertion(paneID: id, operation: operation, state: f.store.state))
        }

        func insertNote(_ f: Fixture, tabID: UUID = UUID(), navigation: URL? = nil) -> Bool {
            f.store.insertSplitPane(draft, tabID: tabID, navigationURL: navigation, creation: nil, savedHomeIDs: [:], documents: [:],
                localPage: .note(createdNote), localTitle: "Untitled")
        }
    }

    @MainActor @Test func addLeftDraftsTheFirstSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        #expect(host.draft.index == 0)
        #expect(host.draft.orientation == .horizontal)
        #expect(host.draft.selection == [host.id])
    }

    @MainActor @Test func aLocalPageAndANavigationURLCannotMaterializeTogether() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let before = f.store.state
        #expect(!host.insertNote(f, navigation: f.url))
        #expect(f.store.state == before)
    }

    @MainActor @Test func aNewNoteOccupiesTheDraftedSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        #expect(host.insertNote(f, tabID: tab))
        #expect(f.store.state.selectedTabIDs == [tab, host.id])
        #expect(f.store.activeSplitLayout?.orientation == .horizontal)
    }

    @MainActor @Test func theNewNoteTabAddressesTheCreatedDocumentWithoutASavedHome() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        _ = host.insertNote(f, tabID: tab)
        #expect(f.store.state.tabs.first { $0.id == tab }?.url == InternalPage.note(host.createdNote).urlString)
        #expect(f.store.state.tabs.filter { InternalPage(urlString: $0.url) == .note(host.createdNote) }.count == 1)
    }

    @MainActor @Test func separatingTheNewNoteRestoresTheOriginalHost() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addBefore)
        let tab = UUID()
        _ = host.insertNote(f, tabID: tab)
        #expect(f.store.separateTabFromSplit(tab, expected: f.store.activeSplitLayout!, focusedID: host.id))
        #expect(f.store.state.selectedTabIDs == [host.id])
    }

    @MainActor @Test func theSameNewNoteDocumentCannotOpenASecondTab() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addAbove)
        _ = host.insertNote(f)
        let before = f.store.state
        #expect(!host.insertNote(f))
        #expect(f.store.state == before)
    }

    @MainActor @Test func aNewEaselOccupiesTheDraftedTopSlot() throws {
        let f = try Fixture()
        let host = try Host(f, operation: .addAbove)
        let easels = try EaselStore(directory: f.root.appendingPathComponent("easels"))
        let created = try easels.create()
        let tab = UUID()
        #expect(host.draft.index == 0)
        #expect(host.draft.orientation == .vertical)
        #expect(host.draft.selection == [host.id])
        #expect(f.store.insertSplitPane(host.draft, tabID: tab, navigationURL: nil, creation: nil, savedHomeIDs: [:], documents: [:],
            localPage: .easel(created.document.id), localTitle: created.document.title))
        #expect(f.store.state.selectedTabIDs == [tab, host.id])
        #expect(f.store.activeSplitLayout?.orientation == .vertical)
    }
}
