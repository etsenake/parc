import AppKit
import ParcSettings

@MainActor
protocol TerminatingWindow: AnyObject {
    var window: NSWindow? { get }
    var hasReadyPresentation: Bool { get }
    func prepareNotesForTermination() -> Bool
    func prepareSettingsForTermination() -> Bool
    func prepareForApplicationClose()
    func closePreparedSettingsForTermination() -> Bool
    func cancelApplicationClose()
}

@MainActor
protocol TerminatingSettings: AnyObject {
    var window: NSWindow? { get }
    func prepareForTermination() -> Bool
    func attemptClose() -> Bool
    func restoreAfterCancelledOwnerClose()
}

@MainActor
protocol QuitWarningPrompt: AnyObject {
    var window: NSWindow { get }
    var isCurrent: () -> Bool { get set }
    var onDecision: ((Bool) -> Void)? { get set }
    func present(in parent: NSWindow)
    func cancel()
}

@MainActor
protocol ApplicationTerminationHost: AnyObject {
    var terminationStarted: Bool { get }
    var terminatingWindows: [TerminatingWindow] { get }
    var terminatingSettings: TerminatingSettings? { get }
    var quitWarningOwner: TerminatingWindow? { get }
    var quitWarningEnabled: Bool { get }
    func makeQuitWarning() -> QuitWarningPrompt
    func afterQuitWarningApproval(_ work: @escaping @Sendable @MainActor () -> Void)
    func deferTerminationWhileClosing(_ resume: @escaping () -> Void) -> Bool
    func finishApprovedTermination(_ sender: Any?)
    func flushNotesForTermination() throws
    func recordStateForTermination()
    func closeForTermination()
    func requestEngineTermination(_ completion: @escaping (Bool) -> Void)
    func completeTermination(_ sender: Any?)
    func resumeAfterRefusedTermination()
    func resumeOnboardingAfterCancelledTermination()
    func abandonTermination(_ message: String)
}

extension BrowserWindowController: TerminatingWindow {
    func prepareNotesForTermination() -> Bool { prepareNotesToClose() }
}

extension SettingsWindow: TerminatingSettings {}

extension ApplicationQuitWarning: QuitWarningPrompt {}

@MainActor
final class ApplicationTermination {
    private weak var host: ApplicationTerminationHost?
    private(set) var inProgress = false
    private(set) var quitWarning: QuitWarningPrompt?
    private(set) var approvalPending = false
    var quitCommandPending = false

    init(host: ApplicationTerminationHost) { self.host = host }

    func request(_ sender: Any?) {
        guard let host else { return }
        let fromQuitCommand = quitCommandPending
        quitCommandPending = false
        guard !inProgress, !approvalPending else { return }
        if host.deferTerminationWhileClosing({ [weak self] in
            self?.quitCommandPending = fromQuitCommand
            self?.request(sender)
        }) { return }
        guard host.terminationStarted else {
            host.finishApprovedTermination(sender)
            return
        }
        if let quitWarning {
            self.quitWarning = nil
            quitWarning.cancel()
            proceed(sender)
            return
        }
        if fromQuitCommand, host.quitWarningEnabled, let owner = host.quitWarningOwner, let parent = owner.window {
            let warning = host.makeQuitWarning()
            warning.isCurrent = { [weak self, weak owner, weak parent, weak warning] in
                guard let self, let host = self.host, let owner, let parent, let warning,
                      self.quitWarning === warning, host.terminationStarted, !self.inProgress,
                      host.terminatingWindows.contains(where: { $0 === owner }), owner.window === parent,
                      owner.hasReadyPresentation,
                      parent.attachedSheet == nil || parent.attachedSheet === warning.window else { return false }
                return true
            }
            warning.onDecision = { [weak self, weak warning] approved in
                guard let self, let host = self.host, self.quitWarning === warning else { return }
                self.quitWarning = nil
                guard approved else {
                    host.abandonTermination("Restart cancelled.")
                    host.resumeOnboardingAfterCancelledTermination()
                    return
                }
                self.approvalPending = true
                host.afterQuitWarningApproval { [weak self] in self?.proceed(sender) }
            }
            quitWarning = warning
            warning.present(in: parent)
            return
        }
        proceed(sender)
    }

    func shutDown() {
        approvalPending = false
        quitWarning?.cancel()
    }

    private func proceed(_ sender: Any?) {
        approvalPending = false
        guard let host, !inProgress else { return }
        if host.deferTerminationWhileClosing({ [weak self] in
            self?.proceed(sender)
        }) { return }
        guard host.terminationStarted else {
            host.finishApprovedTermination(sender)
            return
        }
        guard host.terminatingWindows.allSatisfy({ $0.prepareNotesForTermination() }) else {
            host.abandonTermination("Restart cancelled. Your notes are still open.")
            host.resumeOnboardingAfterCancelledTermination()
            return
        }
        do { try host.flushNotesForTermination() }
        catch {
            host.abandonTermination("Quit cancelled. A note could not be saved on this Mac.")
            host.resumeOnboardingAfterCancelledTermination()
            return
        }
        guard host.terminatingSettings?.prepareForTermination() ?? true,
              host.terminatingWindows.allSatisfy({ $0.prepareSettingsForTermination() }) else {
            host.abandonTermination("Quit cancelled. Air Traffic Control changes could not be saved.")
            host.resumeOnboardingAfterCancelledTermination()
            return
        }
        host.recordStateForTermination()
        let settingsWasVisible = host.terminatingSettings?.window?.isVisible == true
        inProgress = true
        host.terminatingWindows.forEach { $0.prepareForApplicationClose() }
        guard host.terminatingSettings?.attemptClose() ?? true,
              host.terminatingWindows.allSatisfy({ $0.closePreparedSettingsForTermination() }) else {
            inProgress = false
            if settingsWasVisible { host.terminatingSettings?.restoreAfterCancelledOwnerClose() }
            host.terminatingWindows.forEach { $0.cancelApplicationClose() }
            host.resumeAfterRefusedTermination()
            host.abandonTermination("Quit cancelled. Settings could not be closed.")
            host.resumeOnboardingAfterCancelledTermination()
            return
        }
        host.closeForTermination()
        host.requestEngineTermination { [weak self] allowed in
            guard let self, let host = self.host else { return }
            if allowed {
                host.completeTermination(sender)
            } else {
                self.inProgress = false
                host.resumeOnboardingAfterCancelledTermination()
                if settingsWasVisible { host.terminatingSettings?.restoreAfterCancelledOwnerClose() }
                host.terminatingWindows.forEach { $0.cancelApplicationClose() }
                host.resumeAfterRefusedTermination()
                host.abandonTermination("Restart cancelled. Your browser is still open.")
            }
        }
    }
}
