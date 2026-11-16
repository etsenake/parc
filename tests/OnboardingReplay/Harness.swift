import Foundation
struct NSRect: Equatable { var x, y, width, height: Int }

enum BrowserScriptError: Error { case busy, missing }
final class Text { var isEditable = true }
final class View { var needsLayout = false }
final class Document { var deleted = false }
final class Session { let document = Document() }
final class NoteEditorViewController {
    let text = Text(), titleText = Text(), view = View(), session = Session()
}
struct Note { let editor: NoteEditorViewController }
struct BrowserWindowRecord { let id: UUID }
struct SavedWindowFrame { let rect: NSRect }
final class BrowserStore { var state = 0; func save() throws {} }
enum NoteStore { static func flushAllSharedDelayedDiskSaves() throws {} }
final class Settings {
    var window: NSWindow?; var allowsClose = true
    func attemptClose() -> Bool { allowsClose }
    func restoreAfterCancelledOwnerClose() {}
}
struct StyleMask: OptionSet { let rawValue: Int; static let fullScreen = Self(rawValue: 1) }
final class NSWindow {
    var attachedSheet: NSWindow?, isVisible = true, isMiniaturized = false
    var frame = NSRect(x: 27, y: 43, width: 811, height: 607)
    var styleMask: StyleMask = []
    var shouldClose: ((NSWindow) -> Bool)?, didClose: (() -> Void)?
    func performClose(_ sender: Any?) { if shouldClose?(self) == true { isVisible = false; didClose?() } }
    func orderOut(_ sender: Any?) { isVisible = false }
    func orderFront(_ sender: Any?) { isVisible = true }
    func makeKeyAndOrderFront(_ sender: Any?) { isVisible = true }
    func miniaturize(_ sender: Any?) { isMiniaturized = true; isVisible = false }
    func toggleFullScreen(_ sender: Any?) { styleMask.insert(.fullScreen) }
    func setFrame(_ value: NSRect, display: Bool) { frame = value }
}
final class Application { var orderedWindows: [NSWindow] = []; func activate(ignoringOtherApps: Bool) {} }
let NSApp = Application()
final class OnboardingWindow { var presented = false; func present() { presented = true }; func suspend() {} }
final class Binding {
    var completion: ((Bool) -> Void)?
    func requestClose(_ reply: @escaping (Bool) -> Void) { completion = reply }
    func resolve(_ value: Bool) { let reply = completion; completion = nil; reply?(value) }
}
final class PCNativePage { var isClosed = false; let binding: Binding; init(_ binding: Binding) { self.binding = binding } }
final class Browser { var nativePage: PCNativePage?; init(_ page: PCNativePage) { nativePage = page } }
struct Peek { let page: PCNativePage }
final class PageObjects { var pages: [PCNativePage] = [] }
final class EaselEditor { var pageObjects: PageObjects? }
struct Easel { let editor: EaselEditor }
enum PCNativeBrowserApplication {
    static var consent: (() -> Bool)?, reply: ((Bool) -> Void)?
    static var requested: [PCNativePage] = []
    static func owner(of page: PCNativePage) -> Binding? { page.binding }
    static func requestClosePages(_ pages: [PCNativePage], shouldCommit: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        requested = pages; consent = shouldCommit; reply = completion
    }
    static func resolve(_ allowed: Bool) {
        if allowed { precondition(consent?() == false, "auxiliary consent must never unload") }
        let callback = reply; consent = nil; reply = nil; callback?(false)
    }
}
final class Transfer { func retry() {} }
final class BrowserWindowController {
    let store: BrowserStore; var sessionID = UUID()
    var sessionRecord: BrowserWindowRecord { BrowserWindowRecord(id: sessionID) }
    var savedFrame: SavedWindowFrame?
    var window: NSWindow? = NSWindow(), nativeBinding: Binding? = Binding()
    var isPopupWindow = false, isPrivateBrowsing = false, hasReadyPresentation = true
    var isClosing = false, wholeWindowClose = false, windowClosePending = false, windowCloseApproved = false
    var closeAfterEjecting = false, pendingApprovedWindowClose = false, onboardingCloseRequested = false
    var onboardingCloseNotes: [(editor: NoteEditorViewController, bodyEditable: Bool, titleEditable: Bool)]?
    var scriptingWindowCloseCompletions: [(Bool) -> Void] = []
    var noteEditors: [UUID: Note] = [:], settings: Settings?
    var collectionTransfer: Transfer?, transferRecoveries: [UUID: () -> Void] = [:]
    var transferringTabIDs: Set<UUID> = [], resolvingTransfers: Set<UUID> = []
    var transferContainers: [String: View] = [:]
    var browsers: [UUID: Browser] = [:], peeks: [UUID: Peek] = [:], easelEditors: [UUID: Easel] = [:]
    var notesCanSave = true, pendingCreation = false, deferEjection = false
    var onClose: (() -> Void)?
    init(store: BrowserStore) {
        self.store = store
        window?.shouldClose = { [weak self] in self?.windowShouldClose($0) ?? false }
        window?.didClose = { [weak self] in
            self?.finishScriptingWindowClose(true); self?.onClose?()
        }
    }
    func prepareNotesToClose() -> Bool { notesCanSave }
    func render(_ state: Int) {}
    func hasPendingNativePage(in ids: Set<UUID>) -> Bool { pendingCreation }
    func ejectPageBeforeClose() -> Bool {
        if deferEjection { closeAfterEjecting = true; return true }; return false
    }
}
final class AppDelegate {
    struct ReplayWindow {
        let record: BrowserWindowRecord; let frame: NSRect
        let wasVisible: Bool; let wasMiniaturized: Bool; let wasFullScreen: Bool
    }
    let store = BrowserStore()
    var windows: [BrowserWindowController] = [], hiddenReplayWindows: [BrowserWindowController] = []
    var replayWindow: ReplayWindow?, replayReturnOwner: BrowserWindowController?
    var onboarding: OnboardingWindow?, lastActiveWindow: BrowserWindowController?
    var replayCloseInProgress = false, replaySessionActive = false, terminationInProgress = false
    var deferredReplayTermination: (() -> Void)?, replayRestoreError: Error?
    var quitCommandPending = false, quitWarningApprovalPending = false
    var globalQuitRequests = 0, recordsWritten = 0, recoveryPrompts = 0, failsRestoration = false
    func add(_ owner: BrowserWindowController) {
        windows.append(owner); NSApp.orderedWindows.append(owner.window!)
        owner.onClose = { [weak self, weak owner] in self?.windows.removeAll { $0 === owner } }
    }
    func recordWindowSessions() { if !replaySessionActive { recordsWritten += 1 } }
    func persistTabHistory() {}
    func cancelApplicationRestart(_ message: String) {}
    func presentReplayRestoreFailure() { recoveryPrompts += 1 }
    func deliverPendingBrowserRequests(to owner: BrowserWindowController) {}
    func refreshVisibleActivity() {}
    func makeBrowserWindow(renderInitialSelection: Bool, showImmediately: Bool, restoredRecord: BrowserWindowRecord? = nil) throws -> BrowserWindowController {
        if failsRestoration { throw BrowserScriptError.busy }
        let owner = BrowserWindowController(store: store); owner.sessionID = restoredRecord?.id ?? UUID()
        owner.window?.isVisible = showImmediately; add(owner); return owner
    }
}
func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
func fixture() -> (AppDelegate, BrowserWindowController, BrowserWindowController, OnboardingWindow) {
    NSApp.orderedWindows = []
    let app = AppDelegate(), flow = OnboardingWindow()
    let origin = BrowserWindowController(store: app.store), other = BrowserWindowController(store: BrowserStore())
    other.isPrivateBrowsing = true; app.add(origin); app.add(other)
    return (app, origin, other, flow)
}
do {
    let (app, origin, other, flow) = fixture(), editor = NoteEditorViewController()
    origin.noteEditors[UUID()] = Note(editor: editor)
    try app.startOnboardingReplay(flow, closing: origin)
    precondition(!editor.text.isEditable && !editor.titleText.isEditable)
    app.requestApplicationTermination(nil)
    precondition(app.globalQuitRequests == 0 && origin.wholeWindowClose)
    origin.nativeBinding?.resolve(false); drain()
    precondition(editor.text.isEditable && editor.titleText.isEditable)
    precondition(app.onboarding == nil && !flow.presented && other.window!.isVisible)
    precondition(app.globalQuitRequests == 0 && app.replayReturnOwner == nil)
}
do {
    let (app, origin, other, flow) = fixture(), editor = NoteEditorViewController()
    origin.noteEditors[UUID()] = Note(editor: editor)
    let frame = origin.window!.frame, id = origin.sessionID
    try app.startOnboardingReplay(flow, closing: origin)
    origin.notesCanSave = false
    origin.nativeBinding?.resolve(true); drain()
    precondition(flow.presented && !other.window!.isVisible && !app.windows.contains { $0 === origin })
    app.failsRestoration = true; let writes = app.recordsWritten
    app.finishOnboardingReplay()
    precondition(app.replayWindow?.record.id == id && app.replayReturnOwner != nil)
    precondition(app.recoveryPrompts == 1 && app.recordsWritten == writes && !other.window!.isVisible)
    app.failsRestoration = false; app.finishOnboardingReplay()
    precondition(app.windows.contains { $0 === other } && other.window!.isVisible)
    precondition(app.lastActiveWindow?.sessionID == id && app.lastActiveWindow?.window?.frame == frame)
    precondition(app.replayReturnOwner == nil && app.onboarding == nil)
}
for direct in [false, true] {
    let (app, origin, _, flow) = fixture()
    try app.startOnboardingReplay(flow, closing: origin)
    if direct { app.continueApplicationTermination(nil) } else { app.requestApplicationTermination(nil) }
    precondition(app.globalQuitRequests == 0)
    origin.nativeBinding?.resolve(true); drain()
    precondition(app.globalQuitRequests == 1 && app.lastActiveWindow?.sessionID == origin.sessionID)
    precondition(app.replayReturnOwner == nil && !flow.presented)
}
do {
    let (app, origin, _, flow) = fixture()
    try app.startOnboardingReplay(flow, closing: origin)
    app.requestApplicationTermination(nil); app.failsRestoration = true
    origin.nativeBinding?.resolve(true); drain()
    precondition(app.globalQuitRequests == 0 && app.deferredReplayTermination != nil)
    precondition(app.replaySessionActive && app.replayWindow != nil)
    app.failsRestoration = false; app.finishOnboardingReplay()
    precondition(app.globalQuitRequests == 1 && !app.replaySessionActive)
}
do {
    let (app, origin, _, flow) = fixture(); origin.deferEjection = true
    try app.startOnboardingReplay(flow, closing: origin)
    origin.closeAfterEjecting = false; origin.deferEjection = false; origin.notesCanSave = false
    origin.window?.performClose(nil); drain()
    precondition(!app.replayCloseInProgress && app.onboarding == nil)
    precondition(origin.scriptingWindowCloseCompletions.isEmpty && !flow.presented)
}
for privateOrigin in [false, true] {
    let (app, origin, _, flow) = fixture()
    origin.isPopupWindow = !privateOrigin
    let auxiliary = privateOrigin ? BrowserWindowController(store: BrowserStore()) : origin
    if privateOrigin { auxiliary.isPrivateBrowsing = true; app.add(auxiliary) }
    let binding = auxiliary.nativeBinding!
    auxiliary.browsers[UUID()] = Browser(PCNativePage(binding))
    auxiliary.peeks[UUID()] = Peek(page: PCNativePage(binding))
    let easel = EaselEditor(); easel.pageObjects = PageObjects(); easel.pageObjects?.pages = [PCNativePage(binding)]
    auxiliary.easelEditors[UUID()] = Easel(editor: easel)
    try app.startOnboardingReplay(flow, closing: auxiliary)
    precondition(PCNativeBrowserApplication.requested.count == 3)
    PCNativeBrowserApplication.resolve(false); drain()
    precondition(!flow.presented && app.windows.contains { $0 === auxiliary })
    try app.startOnboardingReplay(flow, closing: auxiliary)
    PCNativeBrowserApplication.resolve(true); drain()
    precondition(flow.presented && !auxiliary.window!.isVisible)
    app.finishOnboardingReplay()
    precondition(app.lastActiveWindow === auxiliary && auxiliary.window!.isVisible)
}
do {
    let (app, origin, _, flow) = fixture(); origin.isPopupWindow = true
    origin.browsers[UUID()] = Browser(PCNativePage(origin.nativeBinding!))
    try app.startOnboardingReplay(flow, closing: origin)
    origin.browsers[UUID()] = Browser(PCNativePage(origin.nativeBinding!))
    PCNativeBrowserApplication.resolve(true); drain()
    precondition(!flow.presented && app.replayReturnOwner == nil && origin.window!.isVisible)
}
do {
    let (app, origin, _, flow) = fixture()
    let popup = BrowserWindowController(store: app.store); popup.isPopupWindow = true; app.add(popup)
    try app.startOnboardingReplay(flow, closing: popup)
    PCNativeBrowserApplication.resolve(true); drain()
    app.windows.removeAll { $0 === popup }
    app.finishOnboardingReplay()
    precondition(app.lastActiveWindow === origin && origin.window!.isVisible && !app.replaySessionActive)
}
do {
    NSApp.orderedWindows = []
    let app = AppDelegate(), flow = OnboardingWindow()
    try app.startOnboardingReplay(flow, closing: nil); drain()
    precondition(flow.presented && app.replaySessionActive)
    app.failsRestoration = true; app.finishOnboardingReplay()
    precondition(app.replaySessionActive && app.recoveryPrompts == 1)
    app.failsRestoration = false; app.finishOnboardingReplay()
    precondition(app.lastActiveWindow?.store === app.store && !app.replaySessionActive)
}
do {
    let (app, origin, _, flow) = fixture(), editor = NoteEditorViewController()
    origin.noteEditors[UUID()] = Note(editor: editor)
    try app.startOnboardingReplay(flow, closing: origin)
    editor.session.document.deleted = true
    origin.nativeBinding?.resolve(false); drain()
    precondition(!editor.text.isEditable && !editor.titleText.isEditable)
}
print("Onboarding replay: consent, note freeze, late refusal, recovery, Quit and exact auxiliary ownership passed")
