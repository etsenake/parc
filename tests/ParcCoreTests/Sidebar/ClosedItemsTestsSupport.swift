import Combine
import Foundation
import Testing
@testable import ParcCore

@MainActor
enum ClosedItemsTestsSupport {
    final class ClosedWindow {
        var items: WindowClosedItems

        init(_ items: WindowClosedItems = WindowClosedItems()) { self.items = items }
        convenience init(itemLastActiveDates: [UUID: Date]) { self.init(WindowClosedItems(itemLastActiveDates: itemLastActiveDates)) }

        var itemLastActiveDates: [UUID: Date] { items.itemLastActiveDates }
        func copy() -> ClosedWindow { ClosedWindow(items) }
        func record(_ intent: ClosedItemIntent, in state: BrowserState) { items.record(intent, in: state) }
        func recordSelection(_ ids: [UUID], focusedTabID: UUID?, state: BrowserState, at date: Date) {
            items.recordSelection(ids, focusedTabID: focusedTabID, state: state, at: date)
        }
        func recordPeek(_ peek: ClosedPeekRecord, in state: BrowserState) { items.recordPeek(peek, in: state) }
        func recordFolderDeletion(_ undo: FolderDeletionUndo) { items.recordFolderDeletion(undo) }
        func selected(_ ids: [UUID]) { items.selected(ids) }
        func next(in state: BrowserState) -> ClosedItemRecord? { items.next(in: state) }
        func nextStep(in state: BrowserState, restorable: (FolderDeletionUndo) -> Bool) -> ClosedItemStep? {
            items.nextStep(in: state, restorable: restorable)
        }
        func consume(_ record: ClosedItemRecord) -> Bool { items.consume(record) }
        func consume(stepID: UUID) -> Bool { items.consume(stepID: stepID) }
    }

    @MainActor final class Fixture {
        let directory: URL
        let store: BrowserStore
        let space: UUID
        let profile: UUID
        let first = ClosedWindow()
        let second = ClosedWindow()
        let cache = ClosedWindow()

        init(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-reopen-component-" + UUID().uuidString)
            store = try BrowserStore(directory: directory, now: now)
            space = store.activeSpaceID
            profile = store.activeSpace.profileID
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func intent(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            ClosedItemIntent(ids: ids, state: store.state, spaceID: space, profileID: profile, focusedTabID: focus)!
        }

        func close(_ ids: Set<UUID>, focus: UUID? = nil) -> ClosedItemIntent {
            let intent = intent(ids, focus: focus)
            store.closeTabs(ids)
            return intent
        }

        func closeIntoCache(_ ids: Set<UUID>, focus: UUID? = nil) {
            let intent = intent(ids, focus: focus)
            store.closeTabs(ids)
            cache.record(intent, in: store.state)
        }
    }
}
