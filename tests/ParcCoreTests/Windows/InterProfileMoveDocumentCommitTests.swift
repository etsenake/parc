import Foundation
import Testing
@testable import ParcCore

struct InterProfileMoveDocumentCommitTests {
    private typealias Store = InterProfileMoveTestsSupport.Store
    private typealias Fixture = InterProfileMoveTestsSupport.Fixture

    @MainActor private final class Documents {
        let f = Fixture()
        let s: Store
        let noteID = UUID()
        let withNote: BrowserState
        let store: BrowserStore
        let proposal: (BrowserState) -> BrowserState?
        var result: Result<Bool, Error>?
        var relocated: [InternalPage] = []
        var fromProfile: UUID?, toProfile: UUID?
        var reversed = 0
        var retirementCalls = 0
        var editorValid = false
        var pending: (() -> Bool, (Bool) -> Void)?

        init() throws {
            let f = f
            s = try Store("documents")
            var withNote = f.state
            withNote.tabs[0].url = InternalPage.easel(noteID).urlString
            self.withNote = withNote
            store = try s.open(withNote)
            let r = f.request(f.today)
            proposal = { ForeignSplitDrop.proposal(r, state: $0, now: Date(), creation: nil) }
        }

        func installOwner() {
            store.relocateLocalDocuments = { [unowned self] _, pages, a, b in
                relocated = pages; fromProfile = a; toProfile = b
                return { [unowned self] in reversed += 1 }
            }
            store.prepareLocalDocumentRelocation = { [unowned self] ids in
                #expect(ids == [f.today.id])
                return { [unowned self] in editorValid }
            }
        }

        func holdRetirement() {
            store.requestPageRetirement = { [unowned self] _, shouldCommit, completion in retirementCalls += 1; pending = (shouldCommit, completion) }
        }

        func move() { result = nil; store.moveAcrossProfiles([f.today.id], proposal: proposal) { [unowned self] in result = $0 }; }
        var succeeded: Bool? { try? result?.get() }
    }

    @MainActor @Test func aDocumentMoveWithoutItsRelocationOwnerRefuses() throws {
        let d = try Documents()
        d.move()
        #expect(d.succeeded == false)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func anUnfinishedOriginalEditorRefusesBeforeNativePageRetirement() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.move()
        #expect(d.succeeded == false)
        #expect(d.retirementCalls == 0)
        #expect(d.relocated.isEmpty)
    }

    @MainActor @Test func aChangedEditorDuringConsentRefusesBeforeUnload() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        d.editorValid = false
        #expect(d.pending?.0() == false)
    }

    @MainActor @Test func anEditorRefusalLeavesTheOriginalDocumentAndProfileUntouched() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        d.editorValid = false
        _ = d.pending?.0()
        d.pending?.1(false)
        #expect(d.succeeded == false)
        #expect(d.relocated.isEmpty)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func unchangedOriginalEditorsAdmitTheActualUnload() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        #expect(d.pending?.0() == true)
    }

    @MainActor @Test func aLateEditorChangeAfterUnloadStillPreventsRelocation() throws {
        let d = try Documents()
        d.installOwner()
        d.holdRetirement()
        d.editorValid = true
        d.move()
        _ = d.pending?.0()
        d.editorValid = false
        d.pending?.1(true)
        #expect(d.succeeded == false)
        #expect(d.relocated.isEmpty)
        #expect(d.store.state == d.withNote)
    }

    @MainActor @Test func documentsRelocateSourceToDestinationBeforePublication() throws {
        let d = try Documents()
        d.installOwner()
        d.editorValid = true
        d.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        d.move()
        #expect(d.succeeded == true)
        #expect(d.relocated == [.easel(d.noteID)])
        #expect(d.fromProfile == d.f.p.id)
        #expect(d.toProfile == d.f.q.id)
        #expect(d.reversed == 0)
    }

    @MainActor @Test func aFailedSaveReversesTheDocumentMove() throws {
        let d = try Documents()
        d.installOwner()
        d.editorValid = true
        d.store.requestPageRetirement = { _, shouldCommit, completion in completion(shouldCommit()) }
        try d.s.breakWrites()
        d.move()
        #expect(d.reversed == 1)
        #expect(d.store.state == d.withNote)
    }

    @MainActor private final class Mixed {
        let f = Fixture()
        let root: URL
        let easels: EaselStore, targetEasels: EaselStore
        let easel: EaselSession
        let noteFile: URL
        let noteBytes = Data("Original note\n".utf8)
        let store: BrowserStore
        let move: SidebarSpaceMove
        var editorValid = true

        init() throws {
            let f = f
            root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-mixed-profile-" + UUID().uuidString)
            easels = try EaselStore(directory: root.appendingPathComponent("source/Easels"))
            targetEasels = try EaselStore(directory: root.appendingPathComponent("target/Easels"))
            easel = try easels.create()
            noteFile = root.appendingPathComponent("Parc Notes/Original Note.md")
            try FileManager.default.createDirectory(at: noteFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try noteBytes.write(to: noteFile)
            let browser = EaselItem(kind: .browser, frame: .init(x: 0, y: 0, width: 320, height: 200), url: "https://example.com/embedded")
            try easel.perform("Browser") { $0.items = [browser] }
            var initial = f.state
            for (tabID, page) in [(f.g1.id, InternalPage.note(noteFile)), (f.g2.id, InternalPage.easel(easel.document.id))] {
                let index = initial.tabs.firstIndex { $0.id == tabID }!
                initial.tabs[index].url = page.urlString
                initial.tabs[index].savedURL = page.urlString
            }
            try InterProfileMoveTestsSupport.encoder.encode(initial).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root)
            let from = SidebarHierarchySnapshot(state: initial, spaceID: f.s.id, profileID: f.p.id)!
            let to = SidebarHierarchySnapshot(state: initial, spaceID: f.d.id, profileID: f.q.id)!
            move = SidebarSpaceMove(items: [.split(f.group.id)], from: from, to: to, state: initial)!
            let easelID = easel.document.id, easels = easels, targetEasels = targetEasels
            store.prepareLocalDocumentRelocation = { [unowned self] _ in { self.editorValid } }
            store.requestPageRetirement = { _, validate, complete in complete(validate()) }
            store.relocateLocalDocuments = { _, pages, source, destination in
                #expect(source == f.p.id && destination == f.q.id)
                #expect(pages == [.easel(easelID)])
                try easels.retireSessionForRelocation(easelID)
                let copied = try easels.relocate(easelID, to: targetEasels)
                return { _ = try? targetEasels.relocate(easelID, to: easels); targetEasels.removeAssets(copied) }
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func run() -> Bool? {
            var result: Result<Bool, Error>?
            let move = move
            store.moveAcrossProfiles(Set(move.tabIDs), proposal: { move.applying(to: $0) }) { result = $0 }
            return try? result?.get()
        }
    }

    @MainActor @Test func aDraftRefusalPreservesTheOriginalEaselStoreAndNoteFile() throws {
        let m = try Mixed()
        m.editorValid = false
        #expect(m.run() == false)
        #expect(try m.easels.load(m.easel.document.id) === m.easel)
        #expect(try Data(contentsOf: m.noteFile) == m.noteBytes)
    }

    @MainActor @Test func aMixedNoteAndEaselSplitCommitsItsOriginalRecordsToTheDestinationProfile() throws {
        let m = try Mixed()
        #expect(m.run() == true)
        #expect(m.move.tabIDs.allSatisfy { id in m.store.state.tabs.first { $0.id == id }?.profileID == m.f.q.id })
    }

    @MainActor @Test func theEaselMovesToTheDestinationProfileWithItsSavedContents() throws {
        let m = try Mixed()
        _ = m.run()
        #expect((try? m.easels.load(m.easel.document.id)) == nil)
        #expect(try m.targetEasels.load(m.easel.document.id).document == m.easel.document)
    }

    @MainActor @Test func theNoteFileStaysPutAndTheMovedTabStillPointsAtIt() throws {
        let m = try Mixed()
        _ = m.run()
        #expect(try Data(contentsOf: m.noteFile) == m.noteBytes)
        #expect(m.store.state.tabs.first { $0.id == m.f.g1.id }?.url == InternalPage.note(m.noteFile).urlString)
    }
}
