import AppKit
import Testing
@testable import Parc

@MainActor
struct ApplicationTerminationTests {
    private struct NoteFlushFailure: Error {}

    private final class Window: TerminatingWindow {
        let window: NSWindow? = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var hasReadyPresentation = true, notesCanSave = true, settingsSave = true, closing = false
        func prepareNotesForTermination() -> Bool { notesCanSave }
        func prepareSettingsForTermination() -> Bool { settingsSave }
        func prepareForApplicationClose() { closing = true }
        func closePreparedSettingsForTermination() -> Bool { true }
        func cancelApplicationClose() { closing = false }
    }

    private final class Settings: TerminatingSettings {
        let window: NSWindow? = nil
        var prepares = true, closes = true
        func prepareForTermination() -> Bool { prepares }
        func attemptClose() -> Bool { closes }
        func restoreAfterCancelledOwnerClose() {}
    }

    private final class Warning: QuitWarningPrompt {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var isCurrent: () -> Bool = { true }
        var onDecision: ((Bool) -> Void)?
        var presentedIn: NSWindow?, cancelled = false
        func present(in parent: NSWindow) { presentedIn = parent }
        func cancel() { cancelled = true }
    }

    private final class Host: ApplicationTerminationHost {
        var terminationStarted = true
        let owner = Window()
        let settings = Settings()
        var terminatingWindows: [TerminatingWindow] { [owner] }
        var terminatingSettings: TerminatingSettings? { settings }
        var quitWarningOwner: TerminatingWindow? { owner }
        var quitWarningEnabled = true
        var warnings: [Warning] = []
        var approvals: [@Sendable @MainActor () -> Void] = []
        var replayClosing = false, deferred: (() -> Void)?
        var approvedTerminations = 0, notesFail = false, recorded = 0, closes = 0
        var engineReply: ((Bool) -> Void)?, engineRequests = 0
        var completions = 0, refusalResumes = 0, onboardingResumes = 0
        var abandoned: [String] = []

        func makeQuitWarning() -> QuitWarningPrompt { let warning = Warning(); warnings.append(warning); return warning }
        func afterQuitWarningApproval(_ work: @escaping @Sendable @MainActor () -> Void) { approvals.append(work) }
        func deferTerminationWhileClosing(_ resume: @escaping () -> Void) -> Bool {
            guard replayClosing else { return false }
            deferred = resume
            return true
        }
        func finishApprovedTermination(_ sender: Any?) { approvedTerminations += 1 }
        func flushNotesForTermination() throws { if notesFail { throw NoteFlushFailure() } }
        func recordStateForTermination() { recorded += 1 }
        func closeForTermination() { closes += 1 }
        func requestEngineTermination(_ completion: @escaping (Bool) -> Void) { engineRequests += 1; engineReply = completion }
        func completeTermination(_ sender: Any?) { completions += 1 }
        func resumeAfterRefusedTermination() { refusalResumes += 1 }
        func resumeOnboardingAfterCancelledTermination() { onboardingResumes += 1 }
        func abandonTermination(_ message: String) { abandoned.append(message) }

        func resolve(_ allowed: Bool) { let reply = engineReply; engineReply = nil; reply?(allowed) }
        func approve() { let pending = approvals; approvals = []; pending.forEach { $0() } }
    }

    enum Stop: CaseIterable {
        case notesStayOpen, noteCannotSave, settingsCannotSave, windowSettingsCannotSave, settingsCannotClose
        case pageRefusesToLeave, quitWarningCancelled

        var message: String {
            switch self {
            case .notesStayOpen: "Restart cancelled. Your notes are still open."
            case .noteCannotSave: "Quit cancelled. A note could not be saved on this Mac."
            case .settingsCannotSave, .windowSettingsCannotSave: "Quit cancelled. Air Traffic Control changes could not be saved."
            case .settingsCannotClose: "Quit cancelled. Settings could not be closed."
            case .pageRefusesToLeave: "Restart cancelled. Your browser is still open."
            case .quitWarningCancelled: "Restart cancelled."
            }
        }
    }

    private func stopped(_ stop: Stop) -> (Host, ApplicationTermination) {
        let host = Host(), termination = ApplicationTermination(host: host)
        switch stop {
        case .notesStayOpen: host.owner.notesCanSave = false
        case .noteCannotSave: host.notesFail = true
        case .settingsCannotSave: host.settings.prepares = false
        case .windowSettingsCannotSave: host.owner.settingsSave = false
        case .settingsCannotClose: host.settings.closes = false
        case .pageRefusesToLeave, .quitWarningCancelled: break
        }
        if stop == .quitWarningCancelled { termination.quitCommandPending = true }
        termination.request(nil)
        if stop == .pageRefusesToLeave { host.resolve(false) }
        if stop == .quitWarningCancelled { host.warnings.last?.onDecision?(false) }
        return (host, termination)
    }

    @Test(arguments: Stop.allCases)
    func everyAbandonedQuitDropsThePendingRestartOnceAndKeepsParcOpen(_ stop: Stop) {
        let (host, termination) = stopped(stop)
        #expect(host.abandoned == [stop.message])
        #expect(!termination.inProgress && !host.owner.closing)
        #expect(host.approvedTerminations == 0 && host.completions == 0)
        #expect(host.onboardingResumes == 1)
    }

    @Test(arguments: Stop.allCases)
    func theNextOrdinaryQuitAfterAnAbandonedOneOnlyQuits(_ stop: Stop) {
        let (host, termination) = stopped(stop)
        host.owner.notesCanSave = true; host.owner.settingsSave = true
        host.settings.prepares = true; host.settings.closes = true; host.notesFail = false
        termination.request(nil)
        host.resolve(true)
        #expect(host.completions == 1 && host.abandoned.count == 1)
    }

    @Test(arguments: [Stop.settingsCannotClose, .pageRefusesToLeave])
    func aRefusedCloseResumesDeferredLaunchWork(_ stop: Stop) {
        let (host, _) = stopped(stop)
        #expect(host.refusalResumes == 1)
    }

    @Test func aRestartsQuitSkipsTheQuitWarningAndKeepsItsRelaunch() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.request(nil)
        #expect(host.warnings.isEmpty && host.recorded == 1 && host.closes == 1 && host.engineRequests == 1)
        host.resolve(true)
        #expect(host.completions == 1 && host.abandoned.isEmpty)
    }

    @Test func theQuitCommandAsksFirstInTheOwnersWindow() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        let warning = host.warnings.last
        #expect(warning?.presentedIn === host.owner.window && termination.quitWarning === warning)
        #expect(host.engineRequests == 0 && !termination.quitCommandPending)
    }

    @Test func aDisabledQuitWarningQuitsStraightAway() {
        let host = Host(), termination = ApplicationTermination(host: host)
        host.quitWarningEnabled = false
        termination.quitCommandPending = true
        termination.request(nil)
        #expect(host.warnings.isEmpty && host.engineRequests == 1)
    }

    @Test func aRestartDuringTheQuitWarningDismissesItAndIgnoresItsLateAnswer() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        let warning = host.warnings.last
        termination.request(nil)
        #expect(warning?.cancelled == true && termination.quitWarning == nil)
        warning?.onDecision?(false)
        host.resolve(true)
        #expect(host.abandoned.isEmpty && host.completions == 1)
    }

    @Test func approvingTheQuitWarningContinuesOnTheNextTurnWithoutDroppingTheRestart() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        host.warnings.last?.onDecision?(true)
        #expect(termination.approvalPending && host.engineRequests == 0)
        termination.request(nil)
        #expect(host.engineRequests == 0)
        host.approve()
        #expect(!termination.approvalPending && host.engineReply != nil)
        host.resolve(true)
        #expect(host.abandoned.isEmpty && host.completions == 1)
    }

    @Test func theWarningStaysCurrentOnlyWhileItsOwnerIsReady() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        let warning = host.warnings.last
        #expect(warning?.isCurrent() == true)
        host.owner.hasReadyPresentation = false
        #expect(warning?.isCurrent() == false)
    }

    @Test func aRestartDuringARunningQuitRidesAlong() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.request(nil)
        #expect(termination.inProgress)
        termination.request(nil)
        #expect(host.engineRequests == 1 && host.abandoned.isEmpty)
    }

    @Test func beforeTheEngineStartsAQuitFinishesAtOnce() {
        let host = Host(), termination = ApplicationTermination(host: host)
        host.terminationStarted = false
        termination.request(nil)
        #expect(host.approvedTerminations == 1 && host.engineRequests == 0 && host.recorded == 0)
    }

    @Test func aQuitDuringReplayClosingWaitsAndKeepsItsQuitCommand() {
        let host = Host(), termination = ApplicationTermination(host: host)
        host.replayClosing = true
        termination.quitCommandPending = true
        termination.request(nil)
        #expect(host.warnings.isEmpty && host.engineRequests == 0)
        host.replayClosing = false
        host.deferred?()
        #expect(host.warnings.count == 1)
    }

    @Test func shuttingDownCancelsAnOpenWarning() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        termination.shutDown()
        #expect(host.warnings.last?.cancelled == true)
    }

    @Test func shuttingDownClearsAPendingApproval() {
        let host = Host(), termination = ApplicationTermination(host: host)
        termination.quitCommandPending = true
        termination.request(nil)
        host.warnings.last?.onDecision?(true)
        termination.shutDown()
        #expect(!termination.approvalPending)
    }
}
