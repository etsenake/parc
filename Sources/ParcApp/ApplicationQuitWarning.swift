import AppKit

@MainActor
final class ApplicationQuitWarning: NSObject {
    let dialog: PArcDialog
    var window: NSWindow { dialog.panel }
    let quit: PArcDialogButton
    let suppress: PArcDialogButton
    let cancelButton: PArcDialogButton
    private let preferences: QuitWarningPreferences
    private weak var parent: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var sheetEndObserver: NSObjectProtocol?
    private(set) var finished = false
    var isCurrent: () -> Bool = { false }
    var onDecision: ((Bool) -> Void)?

    init(preferences: QuitWarningPreferences) {
        self.preferences = preferences
        var content = PArcDialog.Content(title: [("Quit Parc?", false)], icon: NSApp.applicationIconImage,
                                        confirm: "Quit", cancel: "Cancel")
        content.auxiliary = "Quit, and don’t ask again"
        dialog = PArcDialog(content)
        quit = dialog.confirmButton; cancelButton = dialog.cancelButton!; suppress = dialog.auxiliaryButton!
        super.init()
        quit.target = self; quit.action = #selector(approve(_:))
        suppress.target = self; suppress.action = #selector(approveAndDisable(_:))
        cancelButton.target = self; cancelButton.action = #selector(cancelAction(_:))
        suppress.isEnabled = !preferences.loadError
        suppress.toolTip = preferences.loadError ? QuitWarningPreferences.Failure.unavailable.localizedDescription : nil
    }

    var isWaiting: Bool { sheetEndObserver != nil }

    func present(in parent: NSWindow) {
        guard !finished, self.parent == nil, NSApp.modalWindow == nil else { cancel(); return }
        self.parent = parent
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        guard parent.attachedSheet != nil else { beginSheet(); return }
        sheetEndObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification,
            object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.beginAfterSheetEnded(attempts: 10, delay: 0) }
            }
    }

    private func beginAfterSheetEnded(attempts: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.finished, self.isWaiting, let parent = self.parent else { return }
                if parent.attachedSheet == nil { self.beginSheet() }
                else if attempts > 1 { self.beginAfterSheetEnded(attempts: attempts - 1, delay: 0.05) }
            }
        }
    }

    private func beginSheet() {
        guard !finished, let parent, parent.attachedSheet == nil else { return }
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver); self.sheetEndObserver = nil }
        guard isCurrent(), NSApp.modalWindow == nil,
              dialog.begin(for: parent, completion: { [weak self] _ in self?.parent = nil; self?.cancel() }) else {
            cancel(); return
        }
    }

    @objc private func approve(_ sender: Any?) { decide(disableWarning: false) }
    @objc private func approveAndDisable(_ sender: Any?) { decide(disableWarning: true) }
    private func decide(disableWarning: Bool) {
        guard !finished else { return }
        guard isCurrent() else { cancel(); return }
        do {
            if disableWarning { try preferences.setEnabled(false) }
            finish(approved: true)
        } catch { PArcDialog.inform(in: window, .init(error: error), queued: true) }
    }
    @objc private func cancelAction(_ sender: Any?) { cancel() }
    func cancel() { finish(approved: false) }

    private func finish(approved: Bool) {
        guard !finished else { return }
        finished = true
        quit.isEnabled = false; suppress.isEnabled = false; cancelButton.isEnabled = false
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver); self.closeObserver = nil }
        if let sheetEndObserver { NotificationCenter.default.removeObserver(sheetEndObserver); self.sheetEndObserver = nil }
        let callback = onDecision; onDecision = nil
        if let error = window.attachedSheet { window.endSheet(error) }
        if let parent, parent.attachedSheet === window { parent.endSheet(window) }
        window.orderOut(nil); parent = nil
        callback?(approved)
    }
}
