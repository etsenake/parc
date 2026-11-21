import AppKit
import ParcCore

extension FolderUndoManager {
    func appendSidebarCopy(_ record: SidebarCopyUndo, store: BrowserStore,
                           canUse: @escaping (Set<UUID>, Direction) -> Bool,
                           remove: @escaping (SidebarCopyUndo, FolderRemovalTarget,
                                              _ done: @escaping (SidebarCopyUndo?) -> Void) -> Void,
                           didRestore: @escaping (SidebarCopyUndo) -> Void,
                           onError: @escaping (Error) -> Void) {
        var current = record
        let ids = Set(record.tabs.map(\.id))
        appendWhenIdle(.init(name: record.actionName, isValid: { [weak store] direction in
            guard let store else { return false }
            return direction == .undo ? current.matchingTarget(in: store.state) != nil : store.canRestoreSidebarCopy(current)
        }, isAvailable: { [weak store] direction in
            guard let store, ids.isDisjoint(with: store.retiringTabIDs),
                  direction == .undo || current.documentsAreAvailable else { return false }
            return canUse(ids, direction)
        }, perform: { [weak store] direction, completion in
            guard let store, canUse(ids, direction) else { completion(false); return }
            switch direction {
            case .undo:
                guard let target = current.matchingTarget(in: store.state) else { completion(false); return }
                remove(current, target) { next in
                    if let next { current = next }
                    completion(next != nil)
                }
            case .redo:
                do {
                    let restored = try store.restoreSidebarCopy(current, shouldCommit: { canUse(ids, .redo) })
                    if restored { didRestore(current) }
                    completion(restored)
                } catch { completion(false); onError(error) }
            }
        })) {}
    }
}
