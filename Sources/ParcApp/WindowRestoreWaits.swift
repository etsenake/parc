import AppKit

@MainActor
final class WindowRestoreWaits {
    private final class Wait {
        var observers: [NSObjectProtocol] = []
    }
    private var waits: [Wait] = []
    private let timeout: TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    var count: Int { waits.count }

    init(timeout: TimeInterval, schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        if delay == 0 {
            DispatchQueue.main.async { MainActor.assumeIsolated { work() } }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
        }
    }) {
        self.timeout = timeout
        self.schedule = schedule
    }

    func wait(for window: NSWindow, resume: @escaping () -> Void) {
        let wait = Wait()
        waits.append(wait)
        let schedule = schedule
        let finish = { [weak self, weak wait] in
            guard let self, let wait, self.end(wait) else { return }
            resume()
        }
        for name in [NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            wait.observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                schedule(0) { finish() }
            })
        }
        schedule(timeout) { finish() }
    }

    private func end(_ wait: Wait) -> Bool {
        guard let index = waits.firstIndex(where: { $0 === wait }) else { return false }
        waits.remove(at: index)
        wait.observers.forEach(NotificationCenter.default.removeObserver)
        return true
    }
}
