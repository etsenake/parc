import AppKit

extension FolderUndoManager {
    @discardableResult
    func appendSplitTitleChange(_ change: SidebarSplitTitleChange, store: BrowserStore,
                                available: @escaping () -> Bool,
                                onError: @escaping (Error) -> Void) -> Bool {
        append(.init(name: change.actionName, isValid: { [weak store] direction in
            guard let store else { return false }
            return change.target(in: store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak store] direction in
            guard let store, available() else { return false }
            return store.canApplySplitTitleChange(change, undo: direction == .undo)
        }, perform: { [weak store] direction, completion in
            guard let store, available() else { completion(false); return }
            do { completion(try store.applySplitTitleChange(change, undo: direction == .undo)) }
            catch { completion(false); onError(error) }
        }))
    }
}

extension FolderUndoManager {
    @discardableResult
    func appendSplitAppearance(_ change: SidebarSplitAppearanceChange, store: BrowserStore,
                               available: @escaping () -> Bool, onError: @escaping (Error) -> Void) -> Bool {
        append(.init(name: change.actionName, isValid: { [weak store] direction in
            guard let store else { return false }; return change.target(in: store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak store] direction in
            guard let store, available() else { return false }; return store.canApplySplitAppearance(change, undo: direction == .undo)
        }, perform: { [weak store] direction, completion in
            guard let store, available() else { completion(false); return }
            do { completion(try store.applySplitAppearance(change, undo: direction == .undo)) }
            catch { completion(false); onError(error) }
        }))
    }
}
