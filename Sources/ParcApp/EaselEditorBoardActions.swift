import AppKit

extension EaselEditorViewController {
    func toggleLock() {
        guard canvas.finishEditing(removingEmpty: false) else { return }
        let lock = !session.document.isLocked
        do {
            try session.perform(lock ? "Lock Easel" : "Unlock Easel") { $0.locked = lock ? true : nil }
        } catch {
            show(error)
        }
    }

    func setDefaultFamily(_ family: EaselTextStyle.Family) {
        guard !session.document.isLocked, session.document.resolvedDefaultFamily != family else { return }
        do {
            try session.perform("Default Text") { $0.defaultFamily = family == .clean ? nil : family }
        } catch {
            show(error)
        }
    }

    func applyLock(_ locked: Bool) {
        palette?.isViewOnly = locked
        titleField.isEditable = !locked
        canvas.documentLockDidChange()
    }
}
