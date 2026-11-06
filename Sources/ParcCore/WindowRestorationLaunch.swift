import Foundation

// Launch and AppKit restoration can finish in either order. Do not present a
// fallback browser or handle a Dock reopen until both original owners finish.
struct WindowRestorationLaunch {
    enum Action: Equatable { case newWindow, blankWindow, newNote(spaceID: UUID, profileID: UUID) }
    private(set) var launchReady = false
    private(set) var restorationFinished = false
    private(set) var pendingDockReopen = false
    private var actions: [Action] = []

    var canPresent: Bool { launchReady && restorationFinished }
    func mayPresent(terminating: Bool, cancelled: Bool = false) -> Bool { canPresent && !terminating && !cancelled }
    static func isRegularLaunchOwner(mainStore: Bool, popup: Bool, ready: Bool) -> Bool {
        mainStore && !popup && ready
    }
    static func preferredOwner(keyOrMain: [Bool], lastActiveIndex: Int?) -> Int? {
        if let index = keyOrMain.firstIndex(of: true) { return index }
        if let index = lastActiveIndex, keyOrMain.indices.contains(index) { return index }
        return keyOrMain.indices.last
    }
    static func shouldRestoreFallback(hasRestoredOwner: Bool, hasOtherLaunchOwner: Bool) -> Bool {
        !hasRestoredOwner && !hasOtherLaunchOwner
    }
    static func shouldDeferWindow(engineReady: Bool, terminating: Bool) -> Bool {
        !engineReady || terminating
    }

    mutating func finishLaunch() { launchReady = true }
    mutating func finishRestoration() { restorationFinished = true }
    mutating func deferDockReopen() { pendingDockReopen = true }
    mutating func deferAction(_ action: Action) { actions.append(action) }
    func nextAction(initialBrowserOpened: Bool, terminating: Bool) -> Action? {
        guard initialBrowserOpened, mayPresent(terminating: terminating) else { return nil }
        return actions.first
    }
    mutating func completeAction() { if !actions.isEmpty { actions.removeFirst() } }
    mutating func takeDockReopen() -> Bool {
        guard canPresent, pendingDockReopen else { return false }
        pendingDockReopen = false
        return true
    }
}

///
/// state at Quit (its defaults domain sets NSQuitAlwaysKeepsWindows) and its
///
/// updater relaunched it or after a crash, otherwise as its restore-windows
/// setting (`arc_quitAlwaysKeepsWindows`, off) says, which leaves one window.
/// Parc has no updater; a launch of a different build than the last one on
/// the same data stands in for it. Kept beside the session file.
struct LaunchContinuity: Codable, Equatable {
    /// Set for as long as a run is alive; still set at launch means it crashed.
    var running: Bool
    /// The build that run was.
    var build: String

    static func restoresEveryWindow(previous: LaunchContinuity?, build: String) -> Bool {
        guard let previous else { return false }
        return previous.running || previous.build != build
    }

    /// Whether AppKit may restore a saved window: every one, or only the one
    /// that was first among the saved records at launch.
    static func accepts(_ recordID: UUID?, launchWindowID: UUID?, everyWindow: Bool) -> Bool {
        everyWindow || (recordID != nil && recordID == launchWindowID)
    }

    static func file(in directory: URL) -> URL { directory.appendingPathComponent("launch.json") }
    static func read(in directory: URL) -> LaunchContinuity? {
        (try? Data(contentsOf: file(in: directory))).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    func write(in directory: URL) {
        try? JSONEncoder().encode(self).write(to: Self.file(in: directory), options: .atomic)
    }
}
