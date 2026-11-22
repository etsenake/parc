import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationTransfersTests {
    private typealias World = WindowPresentationTestsSupport.World

    @MainActor private struct Split {
        var w = World()
        let ownership = NativePageOwnership()
        let windowA = UUID()
        var left: WindowPresentation

        init() {
            left = WindowPresentation(state: w.shared, ready: true)
            _ = ownership.claim(w.a.id, owner: windowA, page: "real-opener-page")
            left.reconcile(w.shared, available: availableA)
        }

        func availableA(_ id: UUID) -> Bool { ownership.canUse(id, owner: windowA) }
    }

    @Test func splitCaptureRemovesDuplicateForeignOwnerAndForeignProfilePages() {
        var s = Split()
        s.w.shared.activeSpaceID = s.w.firstSpace.id
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.b.id, s.w.a.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs == [s.w.a.id, s.w.c.id])
    }

    @Test func removingAPaneFromTheCapturedSplitKeepsItsSurvivor() {
        var s = Split()
        s.w.shared.activeSpaceID = s.w.firstSpace.id
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.b.id, s.w.a.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.remove(s.w.a.id)
        #expect(s.left.selectedTabIDs == [s.w.c.id])
    }

    struct FocusCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let removedAt: Int?
        let expected: Int?
    }

    @Test(arguments: [
        FocusCase(testDescription: "Middle pane removed", count: 2, removedAt: 1, expected: 1),
        FocusCase(testDescription: "Last pane removed", count: 2, removedAt: 2, expected: 1),
        FocusCase(testDescription: "No removal index", count: 1, removedAt: nil, expected: 0),
        FocusCase(testDescription: "No surviving panes", count: 0, removedAt: 0, expected: nil),
    ])
    func closingAPaneChoosesTheSurvivorAtTheSameIndexOrTheEnd(_ panes: FocusCase) {
        let remaining = (0..<panes.count).map { _ in UUID() }
        #expect(BrowserSplitLayout.focusSuccessor(remaining, removedAt: panes.removedAt) == panes.expected.map { remaining[$0] })
    }

    @Test func closingTheFocusedMiddlePaneFocusesThePaneThatTakesItsSlot() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.pin.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.recordFocusedTab(s.w.c.id)
        s.left.remove(s.w.c.id)
        #expect(s.left.selectedTabIDs == [s.w.a.id, s.w.pin.id] && s.left.preferredFocusedTabID == s.w.pin.id)
    }

    @Test func closingTheLastPaneFocusesTheNewLastPane() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.a.id, s.w.c.id, s.w.pin.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.recordFocusedTab(s.w.c.id)
        s.left.remove(s.w.c.id)
        s.left.recordFocusedTab(s.w.pin.id)
        s.left.remove(s.w.pin.id)
        #expect(s.left.selectedTabIDs == [s.w.a.id] && s.left.preferredFocusedTabID == s.w.a.id)
    }

    @Test func theLastSavedTabClosesToStartAndNeverRecreatesItself() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.pin.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.left.remove(s.w.pin.id)
        s.left.reconcile(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs.isEmpty)
    }

    @Test func sharedRetirementRemovesTheActualLocalSelection() {
        var s = Split()
        s.w.shared.selectedTabIDs = [s.w.c.id]
        s.left.captureCommand(s.w.shared, available: s.availableA)
        s.w.shared.tabs[2].archivedAt = Date()
        s.left.reconcile(s.w.shared, available: s.availableA)
        #expect(s.left.selectedTabIDs.isEmpty)
    }

    @MainActor private struct TransferFixture {
        let world = World()
        let ownership = NativePageOwnership()
        let origin = UUID()
        let target = UUID()
        let third = UUID()

        var tab: UUID { world.a.id }
        let page = "same-live-page"

        init() throws {
            try #require(ownership.claim(tab, owner: origin, page: page))
        }

        func reserve() throws -> NativePageOwnership.Transfer {
            try #require(ownership.reserveTransfer(tab, page: page, from: origin, to: target))
        }
    }

    enum WrongTransfer: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case page = "Wrong live page"
        case owner = "Wrong source window"
        case sameWindow = "Transfer to the same window"

        var testDescription: String { rawValue }
    }

    @Test(arguments: WrongTransfer.allCases)
    func transferReservationsRequireTheLivePageAndADifferentDestination(_ mistake: WrongTransfer) throws {
        let transfer = try TransferFixture()
        let page = mistake == .page ? "wrong-page" : transfer.page
        let from = mistake == .owner ? transfer.target : transfer.origin
        let to = mistake == .sameWindow || mistake == .owner ? transfer.origin : transfer.target
        #expect(transfer.ownership.reserveTransfer(transfer.tab, page: page, from: from, to: to) == nil)
    }

    @Test func aTransferReservationIsCurrentAndOwnsThePageUntilFinished() throws {
        let transfer = try TransferFixture()
        let reservation = try transfer.reserve()
        #expect(transfer.ownership.isCurrent(reservation))
        #expect(!transfer.ownership.claim(transfer.tab, owner: transfer.origin, page: transfer.page))
        #expect(!transfer.ownership.claim(transfer.tab, owner: transfer.target, page: transfer.page))
        #expect(!transfer.ownership.canUse(transfer.tab, owner: transfer.third) && !transfer.ownership.canAdopt(transfer.page))
        #expect(transfer.ownership.reserveTransfer(transfer.tab, page: transfer.page, from: transfer.origin, to: transfer.third) == nil)
    }

    @Test func aRefusedTransferRetainsTheOriginalOwner() throws {
        let transfer = try TransferFixture()
        let reservation = try transfer.reserve()
        #expect(transfer.ownership.finishTransfer(reservation, moved: false))
        #expect(transfer.ownership.canUse(transfer.tab, owner: transfer.origin)
                && !transfer.ownership.canUse(transfer.tab, owner: transfer.target))
    }

    @Test func aFinishedTransferDoesNotAcceptItsLateResult() throws {
        let transfer = try TransferFixture()
        let reservation = try transfer.reserve()
        try #require(transfer.ownership.finishTransfer(reservation, moved: false))
        #expect(!transfer.ownership.finishTransfer(reservation, moved: true))
    }

    @Test func aStaleTransferCannotConsumeANewReservation() throws {
        let transfer = try TransferFixture()
        let original = try transfer.reserve()
        try #require(transfer.ownership.finishTransfer(original, moved: false))
        let replacement = try transfer.reserve()
        #expect(!transfer.ownership.finishTransfer(original, moved: true) && transfer.ownership.isCurrent(replacement))
    }

    @Test func completingTheRetryMovesTheExistingPageToTheTarget() throws {
        let transfer = try TransferFixture()
        let original = try transfer.reserve()
        try #require(transfer.ownership.finishTransfer(original, moved: false))
        let replacement = try transfer.reserve()
        #expect(transfer.ownership.finishTransfer(replacement, moved: true))
        #expect(transfer.ownership.canUse(transfer.tab, owner: transfer.target)
                && !transfer.ownership.canUse(transfer.tab, owner: transfer.origin))
        #expect(!transfer.ownership.canAdopt(transfer.page))
        #expect(!transfer.ownership.claim(transfer.world.c.id, owner: transfer.target, page: transfer.page))
    }

    private func closedDuringReturn(_ transfer: TransferFixture) throws -> NativePageOwnership.Transfer {
        let ownership = transfer.ownership
        let first = try transfer.reserve()
        try #require(ownership.finishTransfer(first, moved: true))
        let returning = try #require(ownership.reserveTransfer(transfer.tab, page: transfer.page,
                                                               from: transfer.target, to: transfer.origin))
        ownership.release(transfer.tab, owner: transfer.target)
        return returning
    }

    @Test func closingTheLivePageInvalidatesItsPendingReturnAndFreesItsPage() throws {
        let transfer = try TransferFixture()
        let returning = try closedDuringReturn(transfer)
        #expect(!transfer.ownership.isCurrent(returning) && !transfer.ownership.finishTransfer(returning, moved: true))
        #expect(transfer.ownership.canAdopt(transfer.page))
    }

    @Test func closingTheLivePageLetsTheTabClaimAReplacementWithoutAnOldReturn() throws {
        let transfer = try TransferFixture()
        let returning = try closedDuringReturn(transfer)
        #expect(transfer.ownership.claim(transfer.tab, owner: transfer.origin, page: "replacement-page"))
        #expect(!transfer.ownership.finishTransfer(returning, moved: true))
    }

    @Test func tearingDownTheTargetCancelsItsReservationButKeepsTheOriginalPage() throws {
        let transfer = try TransferFixture()
        _ = try closedDuringReturn(transfer)
        try #require(transfer.ownership.claim(transfer.tab, owner: transfer.origin, page: "replacement-page"))
        let teardown = try #require(transfer.ownership.reserveTransfer(transfer.tab, page: "replacement-page",
                                                                       from: transfer.origin, to: transfer.target))
        transfer.ownership.releaseAll(owner: transfer.target)
        #expect(!transfer.ownership.isCurrent(teardown) && transfer.ownership.canUse(transfer.tab, owner: transfer.origin))
    }
}
