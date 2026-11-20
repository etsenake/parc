import Foundation

enum BrowserScriptError: Error { case cancelled }
struct NoteFlushFailure: Error {}
final class NSWindow { var attachedSheet: NSWindow?, isVisible = true }
final class ParcApplication: NSObject {
    var approvedTerminations = 0
    func finishApprovedTermination(_ sender: Any?) { approvedTerminations += 1 }
}
let NSApp: NSObject = ParcApplication()
let application = NSApp as! ParcApplication
enum PCNativeBrowserApplication {
    static var restartArmed = false, cancelledQuits = 0
    static func cancelQuit() { restartArmed = false; cancelledQuits += 1 }
}
enum PCBrowserEngine {
    static var reply: ((Bool) -> Void)?
    static func requestTermination(completion: @escaping (Bool) -> Void) { reply = completion }
    static func resolve(_ allowed: Bool) { let callback = reply; reply = nil; callback?(allowed) }
}
final class HistorySpotlightIndexer { var flushes = 0; func flush() { flushes += 1 } }
enum NoteFileSession {
    static var fails = false
    static func flushAll() throws { if fails { throw NoteFlushFailure() } }
}
struct QuitWarningState { var isEnabled = true }
final class QuitWarningPreferences {
    static let shared = QuitWarningPreferences()
    var state = QuitWarningState()
}
final class ApplicationQuitWarning {
    static var shown: ApplicationQuitWarning?
    let window = NSWindow()
    var isCurrent: () -> Bool = { true }
    var onDecision: (Bool) -> Void = { _ in }
    var cancelled = false
    init(preferences: QuitWarningPreferences) {}
    func present(in parent: NSWindow) { Self.shown = self; parent.attachedSheet = window }
    func cancel() { cancelled = true }
}
final class Settings {
    var window: NSWindow? = NSWindow()
    var prepares = true, closes = true
    func prepareForTermination() -> Bool { prepares }
    func attemptClose() -> Bool { closes }
    func restoreAfterCancelledOwnerClose() {}
}
final class BrowserWindowController {
    var window: NSWindow? = NSWindow()
    var hasReadyPresentation = true, notesCanSave = true, settingsSave = true, closing = false
    func prepareNotesToClose() -> Bool { notesCanSave }
    func prepareSettingsForTermination() -> Bool { settingsSave }
    func prepareForApplicationClose() { closing = true }
    func closePreparedSettingsForTermination() -> Bool { true }
    func cancelApplicationClose() { closing = false }
}
final class BrowserImportWindow { func close() {} }
final class OnboardingWindow { func closeBrowserImport() {} }
final class PrivateWindowCreation { func finish(_ result: Result<Int, Error>) {} }
final class ApplicationRestart {}
final class BrowserStore { let directory = URL(fileURLWithPath: NSTemporaryDirectory()) }
final class AppDelegate {
    let store = BrowserStore()
    var started = true, terminationInProgress = false, replayCloseInProgress = false, armedReplayRestart = false
    var quitCommandPending = false, quitWarningApprovalPending = false
    var deferredReplayTermination: (() -> Void)?, restartCompletion: ((String?) -> Void)?
    var quitWarning: ApplicationQuitWarning?, quitWarningOwner: BrowserWindowController?
    var windows: [BrowserWindowController] = [], applicationSettings: Settings? = Settings()
    var applicationRestart: ApplicationRestart?, browserImport: BrowserImportWindow?, onboarding: OnboardingWindow?
    var privateWindowCreations: [UUID: PrivateWindowCreation] = [:]
    var restartCancellations: [String] = [], shutdowns = 0
    var historySpotlight: HistorySpotlightIndexer? = HistorySpotlightIndexer()
    func cancelApplicationRestart(_ message: String) { restartCancellations.append(message) }
    func resumeOnboardingAfterCancelledTermination() {}
    func recordWindowSessions() {}
    func persistTabHistory() {}
    func resumePendingAppKitRestorations() {}
    func finishInitialLaunchIfReady() {}
    func drainInitialActions() {}
    func cancelPendingAppKitRestorations() {}
    func trace(_ event: String) {}
    func saveSession() {}
    func finishShutdown() { shutdowns += 1 }
    static func removeReplayRestartDraft(in directory: URL) {}
}
func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
func check(_ condition: Bool, _ piece: String, line: UInt = #line) { precondition(condition, piece, line: line) }
func fixture() -> (AppDelegate, BrowserWindowController) {
    let app = AppDelegate(), owner = BrowserWindowController()
    app.windows = [owner]; app.quitWarningOwner = owner
    PCNativeBrowserApplication.restartArmed = true; PCNativeBrowserApplication.cancelledQuits = 0
    PCBrowserEngine.reply = nil; NoteFileSession.fails = false; ApplicationQuitWarning.shown = nil
    return (app, owner)
}
func quitsCleanlyAfterwards(_ app: AppDelegate, _ piece: String) {
    let approved = application.approvedTerminations
    app.requestApplicationTermination(nil); PCBrowserEngine.resolve(true)
    check(application.approvedTerminations == approved + 1 && !PCNativeBrowserApplication.restartArmed,
          piece + ": the next ordinary Quit only quits")
}
func abandons(_ piece: String, _ setUp: (AppDelegate, BrowserWindowController) -> Void,
              _ trigger: (AppDelegate) -> Void = { $0.requestApplicationTermination(nil) }) {
    let (app, owner) = fixture(), approved = application.approvedTerminations
    setUp(app, owner); trigger(app); drain()
    check(!PCNativeBrowserApplication.restartArmed && PCNativeBrowserApplication.cancelledQuits == 1,
          piece + ": the abandoned quit drops the pending restart once")
    check(app.restartCancellations.count == 1 && !app.terminationInProgress && !owner.closing
          && application.approvedTerminations == approved && app.shutdowns == 0,
          piece + ": Parc stays open with its own restart cancelled")
    owner.notesCanSave = true; owner.settingsSave = true
    app.applicationSettings?.prepares = true; app.applicationSettings?.closes = true; NoteFileSession.fails = false
    quitsCleanlyAfterwards(app, piece)
}
abandons("Notes that can't close", { $1.notesCanSave = false })
abandons("A note that can't save", { _, _ in NoteFileSession.fails = true })
abandons("Settings that can't save", { app, _ in app.applicationSettings?.prepares = false })
abandons("A window's settings that can't save", { $1.settingsSave = false })
abandons("Settings that can't close", { app, _ in app.applicationSettings?.closes = false })
abandons("A page that refuses to leave", { _, _ in }) { app in
    app.requestApplicationTermination(nil); PCBrowserEngine.resolve(false)
}
abandons("Quit Parc? cancelled", { app, _ in app.quitCommandPending = true }) { app in
    app.requestApplicationTermination(nil); ApplicationQuitWarning.shown?.onDecision(false)
}
do {
    let (app, _) = fixture(), approved = application.approvedTerminations
    app.requestApplicationTermination(nil)
    check(ApplicationQuitWarning.shown == nil, "A restart's quit skips Quit Parc?")
    PCBrowserEngine.resolve(true)
    check(PCNativeBrowserApplication.restartArmed && PCNativeBrowserApplication.cancelledQuits == 0
          && application.approvedTerminations == approved + 1 && app.shutdowns == 1,
          "An uncancelled restart keeps its relaunch and quits")
}
do {
    let (app, _) = fixture(), approved = application.approvedTerminations
    app.quitCommandPending = true; app.requestApplicationTermination(nil)
    let warning = ApplicationQuitWarning.shown
    app.requestApplicationTermination(nil)
    check(warning?.cancelled == true && app.quitWarning == nil, "A restart during Quit Parc? dismisses it")
    warning?.onDecision(false); PCBrowserEngine.resolve(true)
    check(PCNativeBrowserApplication.restartArmed && PCNativeBrowserApplication.cancelledQuits == 0
          && application.approvedTerminations == approved + 1,
          "The dismissed warning's late answer can't drop the restart that replaced it")
}
do {
    let (app, _) = fixture()
    app.quitCommandPending = true; app.requestApplicationTermination(nil)
    ApplicationQuitWarning.shown?.onDecision(true); drain()
    check(app.quitWarningApprovalPending == false && PCBrowserEngine.reply != nil, "Approving Quit Parc? continues")
    PCBrowserEngine.resolve(true)
    check(PCNativeBrowserApplication.restartArmed && PCNativeBrowserApplication.cancelledQuits == 0,
          "An approved quit never drops a pending restart")
}
do {
    let (app, _) = fixture()
    app.terminationInProgress = true; app.requestApplicationTermination(nil)
    check(PCNativeBrowserApplication.restartArmed && PCNativeBrowserApplication.cancelledQuits == 0
          && PCBrowserEngine.reply == nil, "A restart during a running quit rides along without dropping it")
}
print("Termination restart: every abandoned quit drops a pending restart, and an uncancelled one still relaunches")
