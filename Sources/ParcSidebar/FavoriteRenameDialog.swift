import AppKit
import ParcKit

@MainActor
package final class FavoriteRenameDialog: NSObject, NSTextFieldDelegate {
    let dialog: ParcDialog
    let field: NSTextField
    package var isCurrent: () -> Bool = { false }
    package var onCommit: ((String) throws -> Void)?
    package var onFinish: (() -> Void)?
    private weak var parent: NSWindow?
    private(set) var finished = false
    private var committing = false
    package var sheetWindow: NSWindow { dialog.panel }

    package init(title: String) {
        dialog = ParcDialog(.init(title: [("Rename Tab…", false)], confirm: "Rename", cancel: "Cancel",
                                 field: .init(value: title, placeholder: "Keep it short and sweet!", required: false)))
        field = dialog.textField!
        super.init()
        field.delegate = self; field.setAccessibilityLabel("Tab name")
        dialog.confirmButton.target = self; dialog.confirmButton.action = #selector(accept(_:))
        dialog.cancelButton?.target = self; dialog.cancelButton?.action = #selector(cancelAction(_:))
        updateValidity()
    }

    package func present(in window: NSWindow) {
        guard !finished, window.isKeyWindow, window.attachedSheet == nil, isCurrent() else { cancel(); return }
        parent = window
        guard dialog.begin(for: window, completion: { [weak self] _ in self?.finish() }) else { cancel(); return }
    }

    package func reconcile() {
        guard !finished, !committing else { return }
        if !isCurrent() { cancel() }
    }

    private func updateValidity() {
        dialog.confirmButton.isEnabled = !finished && !field.stringValue.isEmpty
    }

    package func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === field else { return }
        updateValidity()
    }

    package func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard !finished, !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { accept(nil); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        return false
    }

    @objc private func accept(_ sender: Any?) {
        guard !finished, !committing, !field.stringValue.isEmpty,
              (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        guard isCurrent(), let onCommit else { cancel(); return }
        committing = true
        do {
            try onCommit(field.stringValue)
            committing = false
            closeSheet()
        } catch {
            committing = false
            updateValidity()
            if sheetWindow.isVisible, sheetWindow.attachedSheet == nil {
                ParcDialog.inform(in: sheetWindow, .init(error: error))
            }
        }
    }

    @objc private func cancelAction(_ sender: Any?) { cancel() }
    package func cancel() { guard !committing else { return }; closeSheet() }

    private func closeSheet() {
        guard !finished else { return }
        finished = true; updateValidity(); field.abortEditing()
        if let error = sheetWindow.attachedSheet { sheetWindow.endSheet(error) }
        if let parent, parent.attachedSheet === sheetWindow {
            parent.endSheet(sheetWindow)
        } else { finish() }
    }

    private func finish() {
        finished = true; updateValidity()
        let callback = onFinish; onFinish = nil
        onCommit = nil; callback?()
    }
}
