import Foundation

package struct WindowRestorationLaunch {
    package enum Action: Equatable { case newWindow, blankWindow, newNote(spaceID: UUID, profileID: UUID) }
    private(set) var launchReady = false
    private(set) var restorationFinished = false
    private(set) var pendingDockReopen = false
    private var actions: [Action] = []

    package var canPresent: Bool { launchReady && restorationFinished }

    package init() {}
    package func mayPresent(terminating: Bool, cancelled: Bool = false) -> Bool { canPresent && !terminating && !cancelled }
    package static func isRegularLaunchOwner(mainStore: Bool, popup: Bool, ready: Bool) -> Bool {
        mainStore && !popup && ready
    }
    package static func preferredOwner(keyOrMain: [Bool], lastActiveIndex: Int?) -> Int? {
        if let index = keyOrMain.firstIndex(of: true) { return index }
        if let index = lastActiveIndex, keyOrMain.indices.contains(index) { return index }
        return keyOrMain.indices.last
    }
    package static func shouldRestoreFallback(hasRestoredOwner: Bool, hasOtherLaunchOwner: Bool) -> Bool {
        !hasRestoredOwner && !hasOtherLaunchOwner
    }
    package static func shouldDeferWindow(engineReady: Bool, terminating: Bool) -> Bool {
        !engineReady || terminating
    }

    package mutating func finishLaunch() { launchReady = true }
    package mutating func finishRestoration() { restorationFinished = true }
    package mutating func deferDockReopen() { pendingDockReopen = true }
    package mutating func deferAction(_ action: Action) { actions.append(action) }
    package func nextAction(initialBrowserOpened: Bool, terminating: Bool) -> Action? {
        guard initialBrowserOpened, mayPresent(terminating: terminating) else { return nil }
        return actions.first
    }
    package mutating func completeAction() { if !actions.isEmpty { actions.removeFirst() } }
    package mutating func takeDockReopen() -> Bool {
        guard canPresent, pendingDockReopen else { return false }
        pendingDockReopen = false
        return true
    }
}

package struct LaunchContinuity: Codable, Equatable {
    package var running: Bool
    var build: String

    package init(running: Bool, build: String) {
        self.running = running
        self.build = build
    }

    package static func restoresEveryWindow(previous: LaunchContinuity?, build: String) -> Bool {
        guard let previous else { return false }
        return previous.running || previous.build != build
    }

    package static func accepts(_ recordID: UUID?, launchWindowID: UUID?, everyWindow: Bool) -> Bool {
        everyWindow || (recordID != nil && recordID == launchWindowID)
    }

    static func file(in directory: URL) -> URL { directory.appendingPathComponent("launch.json") }
    package static func read(in directory: URL) -> LaunchContinuity? {
        (try? Data(contentsOf: file(in: directory))).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
    package func write(in directory: URL) {
        try? JSONEncoder().encode(self).write(to: Self.file(in: directory), options: .atomic)
    }
}
