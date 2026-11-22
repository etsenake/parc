import Foundation
import Testing
@testable import ParcCore

struct SplitPaneControlsInsertionTests {
    private typealias Fixture = SplitPaneControlsTestsSupport.Fixture

    @MainActor @Test func aTopInsertionDraftTargetsTheExactPane() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(draft.index == 1)
        #expect(draft.orientation == .vertical)
        #expect(draft.selection == [f.a, f.b, f.c])
    }

    @MainActor @Test func temporaryGeometryStaysNormalized() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(draft.previewFactors.count == 4)
        #expect(abs(draft.previewFactors.reduce(0, +) - 1) < 0.00001)
    }

    @MainActor @Test func thePendingPaneReceivesOneOverTheNewPaneCount() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(abs(draft.previewFactors[1] - 0.25) < 0.00001)
    }

    @MainActor @Test func existingPanesKeepTheirRelativeFactors() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        let previous = try #require(f.store.activeSplitLayout).widthFactors, pending = draft.previewFactors
        #expect(zip(previous, [pending[0], pending[2], pending[3]]).allSatisfy { abs($0 * 0.75 - $1) < 0.00001 })
    }

    @MainActor @Test func draftingNeverPersistsAPlaceholder() throws {
        let f = try Fixture()
        let before = f.store.state
        _ = SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state)
        #expect(f.store.state == before)
    }

    @MainActor @Test func anAcceptedNavigationInsertsOneRecordAtomically() throws {
        let f = try Fixture()
        let draft = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAbove, state: f.store.state))
        #expect(f.store.insertSplitPane(draft, tabID: UUID(), navigationURL: f.url, creation: f.creation(), savedHomeIDs: [:], documents: [:]))
    }

    @MainActor @Test func theNewPaneUsesTheRequestedSlotInTheOriginalContainer() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(f.store.state.selectedTabIDs == [f.a, inserted.id, f.b, f.c])
        #expect(f.store.activeSplitLayout?.id == f.original.id)
    }

    @MainActor @Test func theInsertedTabKeepsItsDestinationAndCreationSource() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        let created = try #require(f.store.state.tabs.first { $0.id == inserted.id })
        #expect(created.url == f.url.absoluteString)
        #expect(created.kind == .today)
        #expect(created.activeTabBeforeCreationID == f.b)
    }

    @MainActor @Test func existingPagesKeepTheirExactIdentity() throws {
        let f = try Fixture()
        _ = try f.insertFour()
        #expect(f.tabs.allSatisfy { f.store.state.tabs.contains($0) })
    }

    @MainActor @Test func aFifthPaneCannotBeDrafted() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(SplitPaneInsertion(paneID: inserted.id, operation: .addAfter, state: f.store.state) == nil)
    }

    @MainActor @Test func anAdmittedDraftCannotReplayAfterMembershipChanged() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        let full = f.store.state
        #expect(!f.store.insertSplitPane(inserted.draft, tabID: UUID(), navigationURL: f.url, creation: nil, savedHomeIDs: [:], documents: [:]))
        #expect(f.store.state == full)
    }

    @MainActor @Test func theAcceptedPaneAndGroupPersistTogether() throws {
        let f = try Fixture()
        let inserted = try f.insertFour()
        #expect(try BrowserStore(directory: f.root).state.selectedTabIDs == [f.a, inserted.id, f.b, f.c])
    }

    @MainActor @Test func mainAddSupportsASingleOriginalContent() throws {
        let f = try Fixture()
        _ = f.store.separateSplitPane(f.b)
        let single = try #require(SplitPaneInsertion(paneID: f.b, operation: .addAfter, state: f.store.state))
        #expect(single.selection.count == 1)
        #expect(single.index == 1)
    }
}
