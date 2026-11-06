import AppKit

extension FolderUndoManager {
    /// Called only after a committed rename. No-op, cancelled and failed edits
    /// do not register or discard the user's existing Redo branch.
    @discardableResult
    func appendTabTitleChange(_ change: SidebarTabTitleChange, store: BrowserStore,
                                available: @escaping () -> Bool,
                                onError: @escaping (Error) -> Void) -> Bool {
        append(.init(name: change.actionName, isValid: { [weak store] direction in
            guard let store else { return false }
            return change.target(in: store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak store] direction in
            guard let store, available() else { return false }
            return store.canApplyTabTitleChange(change, undo: direction == .undo)
        }, perform: { [weak store] direction, completion in
            guard let store, available() else { completion(false); return }
            do { completion(try store.applyTabTitleChange(change, undo: direction == .undo)) }
            catch { completion(false); onError(error) }
        }))
    }
}
