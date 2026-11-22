import Foundation
import Testing
@testable import ParcCore

@MainActor
struct WindowPresentationPlaceholderCloseTests {
    private typealias World = WindowPresentationTestsSupport.World

    @MainActor private struct CloseMove {
        var state = BrowserState.initial()
        let held: BrowserTab
        let mine: BrowserTab
        let moves = NativePageOwnership()
        let holderWindow = UUID()
        let viewerWindow = UUID()
        let bystanderWindow = UUID()
        var holder: WindowPresentation
        var viewer: WindowPresentation

        init() {
            let space = state.spaces[0]
            held = World.tab(space)
            mine = World.tab(space)
            state.tabs = [held, mine]
            state.selectedTabIDs = [held.id]
            holder = WindowPresentation(state: state, ready: true)
            viewer = WindowPresentation(state: state, ready: true)
        }

        func usable(by window: UUID) -> (UUID) -> Bool { { moves.canUse($0, owner: window) } }

        func move(from source: UUID, to destination: UUID) -> Bool {
            guard let reservation = moves.reserveTransfer(held.id, page: "close-held", from: source, to: destination) else { return false }
            return moves.finishTransfer(reservation, moved: true)
        }

        mutating func holderTakesThePage() -> Bool {
            let claimed = moves.claim(held.id, owner: viewerWindow, page: "close-held")
            let left = viewer.leavePlaceholder(held.id, state: state)
            let moved = move(from: viewerWindow, to: holderWindow)
            viewer.reconcile(state, available: usable(by: viewerWindow))
            holder.reconcile(state, available: usable(by: holderWindow))
            return claimed && left && moved
        }
    }

    @Test func theWindowAPageLeftShowsItsPlaceholderWithNoRowSelected() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        #expect(m.viewer.selectedTabIDs.isEmpty && m.viewer.displayedPlaceholders == [m.held.id])
    }

    @Test func closingFromThePlaceholderWindowMovesThePageThere() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        let movedBack = m.move(from: m.holderWindow, to: m.viewerWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(movedBack && left)
        m.viewer.adopt(m.held.id, state: m.state, foreground: false)
        m.viewer.reconcile(m.state, available: m.usable(by: m.viewerWindow))
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        #expect(m.viewer.selectedTabIDs == [m.held.id] && m.viewer.displayedPlaceholders.isEmpty)
    }

    @Test func aCloseThatCannotBeginReturnsThePageAndRestoresTheViewersPlaceholder() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        let before = (m.viewer.selectedTabIDs, m.viewer.displayedTabIDs, m.viewer.displayedPlaceholders)
        let movedBack = m.move(from: m.holderWindow, to: m.viewerWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(movedBack && left)
        m.viewer.adopt(m.held.id, state: m.state, foreground: false)
        m.viewer.reconcile(m.state, available: m.usable(by: m.viewerWindow))
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        let handedBack = m.move(from: m.viewerWindow, to: m.holderWindow)
        let viewerLeft = m.viewer.leavePlaceholder(m.held.id, state: m.state)
        #expect(handedBack && viewerLeft)
        m.holder.adopt(m.held.id, state: m.state, foreground: false)
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        m.viewer.reconcile(m.state, available: m.usable(by: m.viewerWindow))
        #expect(m.viewer.selectedTabIDs == before.0 && m.viewer.displayedTabIDs == before.1 && m.viewer.displayedPlaceholders == before.2)
        #expect(m.holder.selectedTabIDs == [m.held.id] && m.holder.displayedPlaceholders.isEmpty)
    }

    @Test func aPageMovedToABystanderOnlyToCloseArrivesInTheBackground() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        m.state.selectedTabIDs = [m.mine.id]
        var bystander = WindowPresentation(state: m.state, ready: true)
        let moved = m.move(from: m.holderWindow, to: m.bystanderWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(moved && left)
        bystander.adopt(m.held.id, state: m.state, foreground: false)
        bystander.reconcile(m.state, available: m.usable(by: m.bystanderWindow))
        #expect(bystander.selectedTabIDs == [m.mine.id] && !bystander.displayedTabIDs.contains(m.held.id))
    }

    @Test func returningThePageFromABystanderLeavesNoPlaceholder() {
        var m = CloseMove()
        let taken = m.holderTakesThePage()
        #expect(taken)
        m.state.selectedTabIDs = [m.mine.id]
        var bystander = WindowPresentation(state: m.state, ready: true)
        let moved = m.move(from: m.holderWindow, to: m.bystanderWindow)
        let left = m.holder.leavePlaceholder(m.held.id, state: m.state)
        #expect(moved && left)
        bystander.adopt(m.held.id, state: m.state, foreground: false)
        bystander.reconcile(m.state, available: m.usable(by: m.bystanderWindow))
        let back = m.move(from: m.bystanderWindow, to: m.holderWindow)
        let bystanderLeft = bystander.leavePlaceholder(m.held.id, state: m.state)
        #expect(back && !bystanderLeft)
        m.holder.adopt(m.held.id, state: m.state, foreground: false)
        m.holder.reconcile(m.state, available: m.usable(by: m.holderWindow))
        bystander.reconcile(m.state, available: m.usable(by: m.bystanderWindow))
        #expect(bystander.selectedTabIDs == [m.mine.id] && !bystander.hasPlaceholders && m.holder.selectedTabIDs == [m.held.id])
    }

    @Test func aCloseWithoutARefusalNeedsNoExplanation() {
        #expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: nil) == nil)
    }

    @Test func aRefusedCloseExplainsWhyItStopped() {
        #expect(PageReparenting.closeRefusal(unsavedNotes: false, reason: "A page is still opening.") == .explain("A page is still opening."))
    }

    @Test func anUnsavedNoteGetsItsOwnCloseExplanation() {
        if case .explain(let message) = PageReparenting.closeRefusal(unsavedNotes: true, reason: "A page is still opening.") {
            #expect(message.contains("Note"))
        } else {
            Issue.record("a Note that couldn't save explains itself")
        }
    }
}
