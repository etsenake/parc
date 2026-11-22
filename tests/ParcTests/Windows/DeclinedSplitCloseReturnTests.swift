import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct DeclinedSplitCloseReturnTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ownership = NativePageOwnership()
        let store: BrowserStore
        let source: BrowserWindowController
        let receiver: BrowserWindowController
        let moved: UUID
        let split: BrowserSplitLayout
        let behind: UUID
        var pending: [@MainActor () -> Void] = []
        var requested: Set<UUID> = []
        var reply: ((Bool) -> Void)?
        var declines = 0
        var attempts: [UUID] = []
        var blocksReturn = false

        init() throws {
            let store = try BrowserStore(directory: directory)
            self.store = store
            store.scheduleDeferredSave = { _, _ in }
            moved = store.open("https://moved.invalid")
            let local = store.open("https://local.invalid")
            behind = store.open("https://behind.invalid")
            store.setSplit([moved, local])
            split = try #require(store.activeSplitLayout)
            store.setWindowPresentation(spaceID: store.activeSpaceID, selectedTabIDs: [behind], splitLayout: nil)
            source = try BrowserWindowController(store: store, ownership: ownership, windowHost: SplitDividerTestsSupport.SplitScaleWindow.make())
            receiver = try BrowserWindowController(store: store, ownership: ownership, windowHost: SplitDividerTestsSupport.SplitScaleWindow.make())
            source.rendering = true
            receiver.rendering = true
            #expect(ownership.claim(moved, owner: source.presentationID))
            receiver.enqueueUntargetedReturns = { [weak self] in self?.pending.append($0) }
            receiver.tabHolder = { [weak self] _, _ in self.map { .emptyClaim($0.source) } ?? .none }
            receiver.onRequestTabTransfer = { [weak self] id, destination, arrive in
                guard let self, self.source.handOverEmptyClaim(id, to: destination) else { return false }
                return arrive?() ?? true
            }
            receiver.onUntargetedReturn = { [weak self] id, owner, trigger in
                guard let self else { return .blocked }
                if case .deselected = trigger {} else { Issue.record("Expected a deselection return") }
                self.attempts.append(id)
                if self.blocksReturn { return .blocked }
                return owner.handOverEmptyClaim(id, to: self.source) ? .started : .blocked
            }
            store.requestPageRetirement = { [weak self] ids, _, reply in
                self?.requested = ids
                self?.reply = reply
            }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func declineClose() throws {
            let prepared = receiver.prepareSidebarRootsClose([.split(split.id)], archive: false,
                requiresConfirmation: false, isSelectionCommand: false, selectionIsCurrent: { true },
                declined: { [weak self] in self?.declines += 1 })
            let action = try #require(prepared)
            try #require(action())
            #expect(requested == Set(split.tabIDs))
            #expect(ownership.owner(of: moved) == receiver.presentationID)
            let finish = try #require(reply)
            finish(false)
            #expect(declines == 1)
        }

        func runNextReturn() throws {
            try #require(pending.count == 1)
            pending.removeFirst()()
        }
    }

    @Test func decliningTheCloseReturnsTheMovedPaneToItsOwner() throws {
        let fixture = try Fixture()
        try fixture.declineClose()
        try fixture.runNextReturn()

        #expect(fixture.ownership.owner(of: fixture.moved) == fixture.source.presentationID)
        #expect(fixture.receiver.selectedTabIDs == [fixture.behind])
        #expect(fixture.store.state.splitLayouts.contains(fixture.split))
        #expect(Set(fixture.store.state.openTabs.map(\.id)).isSuperset(of: fixture.split.tabIDs))
    }

    @Test func aBlockedReturnTriesAgainWhenReleased() throws {
        let fixture = try Fixture()
        fixture.blocksReturn = true
        try fixture.declineClose()
        try fixture.runNextReturn()
        #expect(fixture.attempts == [fixture.moved])
        #expect(fixture.pending.isEmpty)
        #expect(fixture.ownership.owner(of: fixture.moved) == fixture.receiver.presentationID)

        fixture.blocksReturn = false
        fixture.receiver.retryHeldReturns()
        fixture.receiver.retryHeldReturns()
        try fixture.runNextReturn()
        #expect(fixture.attempts == [fixture.moved, fixture.moved])
        #expect(fixture.pending.isEmpty)
        #expect(fixture.ownership.owner(of: fixture.moved) == fixture.source.presentationID)
    }
}
