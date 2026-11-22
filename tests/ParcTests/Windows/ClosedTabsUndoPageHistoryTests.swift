import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

struct ClosedTabsUndoPageHistoryTests {
    private let pageA = UUID(), pageB = UUID(), pageC = UUID()
    private let entriesA = NSObject(), entriesB = NSObject(), entriesC = NSObject()

    @Test func aClosedTabsEntriesWaitForUndoOrReopen() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        #expect(history.takeRestored(pageA) == nil)
    }

    @Test func aRestoredTabsFirstPageTakesThemOnce() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        history.restore([pageA])
        #expect(history.takeRestored(pageA) === entriesA && history.takeRestored(pageA) == nil)
    }

    @Test func theOldestGoPastTheLimit() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageA, state: entriesA)
        history.closed(pageB, state: entriesB)
        history.closed(pageC, state: entriesC)
        history.restore([pageA, pageB, pageC])
        #expect(history.takeRestored(pageA) == nil && history.takeRestored(pageB) === entriesB)
    }

    @Test func closingAgainWaitsForANewRestoreAndAClosedPeeksAreTakenByItsRecord() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageC, state: entriesA)
        #expect(history.takeRestored(pageC) == nil && history.take(pageC) === entriesA)
    }

    @Test func aReopenThatFailedGivesNoEntries() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageB, state: entriesB)
        history.restore([pageB])
        history.unrestore([pageB])
        #expect(history.takeRestored(pageB) == nil)
    }

    @Test func aPageCreatedForTheTabAnyOtherWayDropsItsRestoredEntries() {
        var history = ClosedPageHistory<NSObject>(limit: 2)
        history.closed(pageC, state: entriesC)
        history.restore([pageC])
        history.pageCreated(pageC)
        #expect(history.takeRestored(pageC) == nil && history.take(pageC) == nil)
    }

    @MainActor @Test func theStoreKeepsClosedPagesEntriesForEveryWindowOutsideItsSavedState() throws {
        let f = try ClosedTabsUndoSupport.ArchiveFixture()
        f.store.closedPageHistory.closed(pageA, state: entriesA)
        #expect(!(try JSONEncoder().encode(f.store.state)).isEmpty && f.store.closedPageHistory.take(pageA) === entriesA)
    }

    @Test func aPeekRefusedWhileAnotherUndosPeekWasAdoptedRetriesWhenThatEndsIfItsParentIsSelectedOnce() {
        var waiters = PeekUndoSlotWaiters()
        let shownParent = UUID(), hiddenParent = UUID()
        waiters.refused(shownParent)
        waiters.refused(hiddenParent)
        #expect(waiters.release(selected: [UUID(), shownParent]) == [shownParent] && waiters.release(selected: [hiddenParent]).isEmpty)
    }
}
