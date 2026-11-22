import AppKit
import ParcCore

@MainActor
package final class ClosedTabsUndoOperation {
    var record: ClosedTabsUndo
    private(set) var reopened: Set<UUID> = []
    var redoScope: Set<UUID> = []
    init(_ record: ClosedTabsUndo) { self.record = record }
    package func didReopen(_ step: ClosedItemRecord) { reopened.formUnion(record.reopenedIDs(step)) }
    fileprivate func undid() { redoScope = Set(record.tabs.map(\.id)).subtracting(reopened) }
    fileprivate func redid(_ next: ClosedTabsUndo) { record = next; reopened = [] }
}

@MainActor
package final class ClosedPeekUndoOperation {
    static let actionName = "Close Peek"
    package private(set) var record: ClosedPeekRecord
    private(set) var reopened = false
    package var openedPeek: UUID?
    init(_ record: ClosedPeekRecord) { self.record = record }
    package func didReopen(_ step: ClosedPeekRecord) { if step.id == record.id { reopened = true } }
    fileprivate func redid(_ next: ClosedPeekRecord) { record = next; reopened = false; openedPeek = nil }
}

package struct PeekUndoSlotWaiters {
    private var parents: Set<UUID> = []
    package init(parents: Set<UUID> = []) {
        self.parents = parents
    }
    package mutating func refused(_ parent: UUID) { parents.insert(parent) }
    package mutating func release(selected: [UUID]) -> [UUID] {
        defer { parents.removeAll() }
        return selected.filter(parents.contains)
    }
}

extension FolderUndoManager {
    @discardableResult
    package func appendClosedTabs(_ record: ClosedTabsUndo, store: BrowserStore,
                          canUse: @escaping (Set<UUID>, Direction) -> Bool,
                          close: @escaping (Set<UUID>, _ current: @escaping () -> Bool,
                                            _ done: @escaping (ClosedTabsUndo?) -> Void) -> Void,
                          didUndo: @escaping (ClosedTabsUndo) -> Void,
                          onError: @escaping (Error) -> Void,
                          appended: @escaping (ClosedTabsUndoOperation) -> Void) -> ClosedTabsUndoOperation {
        let operation = ClosedTabsUndoOperation(record)
        func targets(_ direction: Direction, _ store: BrowserStore) -> Set<UUID> {
            direction == .undo ? operation.record.restorableIDs(in: store.state)
                : operation.record.redoIDs(in: store.state).intersection(operation.redoScope)
        }
        appendWhenIdle(.init(names: { direction in
            direction == .undo ? operation.record.actionName
                : operation.record.prompt.name(count: operation.record.itemCount(of: operation.redoScope))
        }, isValid: { [weak store] direction in
            guard let store else { return false }
            return direction == .undo ? store.canUndoClosedTabs(operation.record) : !targets(.redo, store).isEmpty
        }, isAvailable: { [weak store] direction in
            guard let store else { return false }
            let ids = targets(direction, store)
            return !ids.isEmpty && ids.isDisjoint(with: store.retiringTabIDs)
                && store.archivePreviewLeases(intersecting: ids).isEmpty && canUse(ids, direction)
        }, perform: { [weak store] direction, completion in
            guard let store else { completion(false); return }
            let ids = targets(direction, store)
            guard !ids.isEmpty, canUse(ids, direction) else { completion(false); return }
            switch direction {
            case .undo:
                do {
                    let restored = try store.undoClosedTabs(operation.record, regroupable: { canUse([$0], .undo) },
                        shouldCommit: { canUse(operation.record.restorableIDs(in: store.state), .undo) })
                    if restored { operation.undid(); didUndo(operation.record) }
                    completion(restored)
                } catch { completion(false); onError(error) }
            case .redo:
                close(ids, { [weak store] in
                    guard let store else { return false }
                    return ids.isSubset(of: targets(.redo, store))
                }) { next in
                    guard let next else { completion(false); return }
                    operation.redid(next)
                    completion(true)
                }
            }
        })) { appended(operation) }
        return operation
    }

    @discardableResult
    package func appendClosedPeek(_ record: ClosedPeekRecord, state: @escaping () -> BrowserState?,
                          canOpen: @escaping (ClosedPeekUndoOperation) -> Bool,
                          open: @escaping (ClosedPeekUndoOperation, _ done: @escaping (Bool) -> Void) -> Void,
                          isOpen: @escaping (ClosedPeekUndoOperation) -> Bool,
                          canClose: @escaping (ClosedPeekUndoOperation) -> Bool,
                          close: @escaping (ClosedPeekUndoOperation, _ done: @escaping (ClosedPeekRecord?) -> Void) -> Void,
                          appended: @escaping (ClosedPeekUndoOperation) -> Void) -> ClosedPeekUndoOperation {
        let operation = ClosedPeekUndoOperation(record)
        appendWhenIdle(.init(name: ClosedPeekUndoOperation.actionName, isValid: { direction in
            guard let state = state(), operation.record.isValid(in: state) else { return false }
            return direction == .undo ? !operation.reopened : isOpen(operation)
        }, isAvailable: { direction in
            direction == .undo ? canOpen(operation) : canClose(operation)
        }, perform: { direction, completion in
            switch direction {
            case .undo: open(operation, completion)
            case .redo:
                close(operation) { next in
                    guard let next else { completion(false); return }
                    operation.redid(next)
                    completion(true)
                }
            }
        })) { appended(operation) }
        return operation
    }
}
