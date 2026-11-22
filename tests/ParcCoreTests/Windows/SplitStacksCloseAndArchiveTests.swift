import Foundation
import Testing
@testable import ParcCore

struct SplitStacksCloseAndArchiveTests {
    private typealias Fixture = SplitStacksTestsSupport.Fixture

    @MainActor private struct Closed {
        let before: BrowserState
        let undo: ClosedTabsUndo
        var windows: WindowClosedItems

        init(_ f: Fixture, closing ids: [UUID], focused: UUID?, recordWindow: Bool = false) {
            var windows = WindowClosedItems()
            before = f.store.state
            if recordWindow, let id = ids.first, let intent = ClosedItemIntent(ids: [id], state: f.store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: id) {
                f.store.closeTabs(Set(ids))
                windows.record(intent, in: f.store.state)
            } else {
                f.store.closeTabs(Set(ids))
            }
            undo = ClosedTabsUndo(prompt: .clear, ids: Set(ids), spaceID: f.space.id, profileID: f.profile.id, focusedTabID: focused,
                                  before: before, after: f.store.state)!
            self.windows = windows
        }
    }

    @MainActor @Test func closingAStackedPaneCollapsesItsStackAndKeepsTheColumnsShare() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.c], focused: f.c)
        #expect(f.store.state.selectedTabIDs == [f.a, f.b])
        #expect(f.store.state.splitLayouts.count == 1)
        #expect(f.store.state.splitLayouts[0].stacks == nil)
        #expect(f.store.state.splitLayouts[0].widthFactors == [0.5, 0.5])
    }

    @MainActor @Test func undoRestoresThePaneToItsOldStackWithItsOldShare() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.c], focused: f.c)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func reopenClosedTabRejoinsTheOldStack() throws {
        let f = try Fixture("close")
        var closed = Closed(f, closing: [f.c], focused: f.c, recordWindow: true)
        let reopened = closed.windows.next(in: f.store.state)!
        #expect(reopened.membership != nil)
        #expect(try f.store.restoreClosedItem(reopened))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func theSurvivorsCanBeConvertedAfterAClose() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.b], focused: f.b)
        #expect(f.store.flipSplitOrientation(expected: f.store.activeSplitLayout!))
    }

    @MainActor @Test func afterAConvertTheUndoneCloseRejoinsItsOldMatesSlotInTheNewDirection() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.b], focused: f.b)
        _ = f.store.flipSplitOrientation(expected: f.store.activeSplitLayout!)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        let layout = f.store.state.splitLayouts.first
        #expect(layout?.tabIDs == [f.a, f.b, f.c])
        #expect(layout?.orientation == .vertical)
        #expect(layout?.stacks?.slotSizes == [1, 2])
        #expect(layout?.stacks?.slotFactors == [0.5, 0.5])
    }

    @MainActor @Test func closingTheWholeStackDissolvesTheSplit() throws {
        let f = try Fixture("close")
        _ = Closed(f, closing: [f.b, f.c], focused: nil)
        #expect(f.store.state.splitLayouts.isEmpty)
        #expect(f.store.state.selectedTabIDs == [f.a])
    }

    @MainActor @Test func undoRebuildsTheStackedShapeFromTheDissolvedSplit() throws {
        let f = try Fixture("close")
        let closed = Closed(f, closing: [f.b, f.c], focused: nil)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.a, f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor private func closeWhole(_ f: Fixture) -> WindowClosedItems {
        var windows = WindowClosedItems()
        let intent = ClosedItemIntent(ids: Set(f.ids), state: f.store.state, spaceID: f.space.id, profileID: f.profile.id, focusedTabID: f.ids[1])!
        f.store.closeTabs(Set(f.ids))
        windows.record(intent, in: f.store.state)
        return windows
    }

    @MainActor @Test func archivedPanesCarryTheStackedShape() throws {
        let f = try Fixture("whole")
        _ = closeWhole(f)
        let archived = f.store.state.tabs.filter { f.ids.contains($0.id) }
        #expect(archived.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.split?.stacks == f.layout.stacks })
    }

    @MainActor @Test func reopeningAClosedStackedSplitRestoresItAsOneGroup() throws {
        let f = try Fixture("whole")
        var windows = closeWhole(f)
        let record = windows.next(in: f.store.state)!
        #expect(record.split?.stacks == f.layout.stacks)
        #expect(try f.store.restoreClosedItem(record))
        #expect(f.store.state.splitLayouts.first?.tabIDs == f.ids)
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func restoringFromTheArchiveBringsBackTheStackedShape() throws {
        let f = try Fixture("whole")
        f.store.closeTabs(Set(f.ids))
        let restored = f.store.restoreArchivedTab(f.ids[0], destination: .previousSpace(fallbackSpaceID: f.space.id))
        #expect(restored == f.ids)
        #expect(f.store.state.splitLayouts.first?.stacks == f.layout.stacks)
    }

    @MainActor @Test func closingTheLoneColumnLeavesTheStackAsAFlatSplit() throws {
        let f = try Fixture("own-slot")
        _ = Closed(f, closing: [f.a], focused: f.a)
        #expect(f.store.state.splitLayouts.first?.tabIDs == [f.b, f.c])
        #expect(f.store.state.splitLayouts.first?.orientation == .vertical)
        #expect(f.store.state.splitLayouts.first?.stacks == nil)
    }

    @MainActor @Test func aPaneWithoutAnOldStackRejoinsAsItsOwnSlotBesideTheColumnItLeft() throws {
        let f = try Fixture("own-slot")
        let closed = Closed(f, closing: [f.a], focused: f.a)
        #expect(try f.store.undoClosedTabs(closed.undo, shouldCommit: { true }))
        let layout = f.store.state.splitLayouts.first
        #expect(layout?.tabIDs == [f.a, f.b, f.c])
        #expect(layout?.stacks == f.layout.stacks)
        #expect(layout?.orientation == .horizontal)
    }

    @MainActor private func archivedThird(_ f: Fixture) -> BrowserState {
        var state = f.store.state
        let index = state.tabs.firstIndex { $0.id == f.c }!
        state.tabs[index].archivedAt = Date(timeIntervalSince1970: 20)
        return state
    }

    @MainActor @Test func reconcilingAwayAStackedPaneCollapsesItsStack() throws {
        let f = try Fixture("reconcile")
        let layouts = BrowserStore.reconciledSplitLayouts(in: archivedThird(f), activeSpaceID: f.space.id)
        #expect(layouts.first?.tabIDs == [f.a, f.b])
        #expect(layouts.first?.stacks == nil)
        #expect(layouts.first?.widthFactors == [0.5, 0.5])
    }

    @MainActor @Test func reconcilingAnIntactStackedSplitChangesNothing() throws {
        let f = try Fixture("reconcile")
        #expect(BrowserStore.reconciledSplitLayouts(in: f.store.state, activeSpaceID: f.space.id) == f.store.state.splitLayouts)
    }
}
