import AppKit

extension FolderUndoManager {
    @discardableResult
    func appendSpaceThemeChange(_ change: SpaceThemeChange, store: BrowserStore,
                                available: @escaping () -> Bool,
                                onApplied: @escaping () -> Void,
                                onError: @escaping (Error) -> Void) -> Bool {
        append(.init(name: change.actionName, isValid: { [weak store] direction in
            guard let store else { return false }
            return change.target(in: store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak store] direction in
            guard let store, available() else { return false }
            return store.canApplySpaceThemeChange(change, undo: direction == .undo)
        }, perform: { [weak store] direction, completion in
            guard let store, available() else { completion(false); return }
            do {
                let committed = try store.applySpaceThemeChange(change, undo: direction == .undo)
                if committed { onApplied() }
                completion(committed)
            } catch { completion(false); onError(error) }
        }))
    }
}
