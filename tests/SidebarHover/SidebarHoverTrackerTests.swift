import AppKit
import QuartzCore

@MainActor final class FlippedRoot: NSView { override var isFlipped: Bool { true } }

@MainActor final class ManualClock {
    private(set) var now: CFTimeInterval = 0
    private var pending: [(at: CFTimeInterval, order: Int, body: @MainActor () -> Void)] = []
    private var order = 0
    func schedule(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        order += 1; pending.append((now + delay, order, body))
    }
    func advance(_ interval: TimeInterval) {
        let target = now + interval
        var fired = 0
        while let next = pending.filter({ $0.at <= target + 1e-9 }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            fired += 1
            guard fired < 1_000 else { fatalError("SidebarHoverTracker: a timer keeps re-arming without time passing") }
            pending.removeAll { $0.order == next.order }
            now = max(now, next.at); next.body()
        }
        now = max(now, target)
    }
}

@main @MainActor struct SidebarHoverTrackerTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarHoverTracker: \(message)") }
    }
    static func main() { exitOnFailure(runChecks) }
    static func runChecks() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = FlippedRoot(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        window.contentView = root
        var presentation = SidebarHoverZones.Presentation.hidden
        var pointer = NSPoint(x: 500, y: 350)
        var listening = true
        var published: [SidebarHoverInfo] = []
        var regionBuilds = 0
        let tracker = SidebarHoverTracker()
        let clock = ManualClock()
        var delays: [TimeInterval] = []
        tracker.now = { clock.now }
        tracker.after = { delay, body in delays.append(delay); clock.schedule(delay, body) }
        tracker.nextTurn = { body in clock.schedule(0, body) }
        tracker.view = root
        tracker.canListen = { listening }
        tracker.mouseLocation = { window.convertPoint(toScreen: root.convert(pointer, to: nil)) }
        tracker.regions = { info in
            regionBuilds += 1
            return SidebarHoverZones.rects(size: root.bounds.size, presentation: presentation, sidebarWidth: 228, showingToolbar: false,
                                    trafficLightHeight: 0, info: info)
                .mapValues { NSRect(x: $0.minX, y: root.bounds.height - $0.maxY, width: $0.width, height: $0.height) }
        }
        tracker.onChange = { published.append($0) }
        window.acceptsMouseMovedEvents = false
        tracker.attach(to: window)
        check(window.acceptsMouseMovedEvents, "the window receives moves beyond its frame")
        check(published.count == 1 && tracker.info[.window] == .inside && tracker.info[.innerLeftEdge] == .none,
              "listening reports the current pointer once")
        check(tracker.stopScheduleCount == 0, "in-page listen start does not arm the edge stop")
        let idleBuilds = regionBuilds
        for offset in 1...20 {
            pointer = NSPoint(x: 500 + CGFloat(offset), y: 350 + CGFloat(offset % 3))
            tracker.refresh()
            tracker.mouseMoved()
        }
        check(regionBuilds == idleBuilds, "inside-window motion reuses converted regions")
        check(published.count == 1 && tracker.info[.window] == .inside && tracker.info[.innerLeftEdge] == .none,
              "inside-window motion does not publish or change regions")
        check(tracker.stopScheduleCount == 0, "inside-window motion does not arm the edge stop")
        let samePointBuilds = regionBuilds
        tracker.mouseMoved()
        check(regionBuilds == samePointBuilds && published.count == 1,
              "an identical pointer skips containment work")

        let edgeBuilds = regionBuilds
        pointer = NSPoint(x: 3, y: 690); tracker.refresh()
        check(regionBuilds > edgeBuilds, "entering the inner edge rebuilds the widened zones")
        check(tracker.info[.innerLeftEdge] == .inside && tracker.info[.innerTopLeftEdge] == .none, "bottom-left is the inner edge")
        check(tracker.stopScheduleCount == 0, "refresh alone does not arm the edge stop")
        delays.removeAll()
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == 1 && delays == [0.08], "mouseMoved on a stoppable edge arms one 0.08 s stop")
        pointer = NSPoint(x: 3, y: 690); tracker.refresh(); tracker.mouseMoved()
        check(published.count == 2, "an unchanged refresh publishes nothing")
        check(tracker.stopScheduleCount == 1, "identical edge motion keeps one pending stop")
        clock.advance(0.079)
        check(tracker.info[.innerLeftEdge] == .inside && published.count == 2, "no promotion before the stop")
        clock.advance(0.001)
        check(tracker.info[.innerLeftEdge] == .hasStopped && published.last?[.innerLeftEdge] == .hasStopped && published.count == 3,
              "stopped and published at 0.08 s")
        pointer = NSPoint(x: 20, y: 5); tracker.refresh(); tracker.mouseMoved()
        check(tracker.info[.innerTopLeftEdge] == .inside && tracker.info[.innerLeftEdge] == .none, "top-left in flipped coordinates")
        check(tracker.stopScheduleCount == 2, "a new stoppable edge arms the stop again")

        presentation = .floating
        tracker.setNeedsRefresh()
        pointer = NSPoint(x: 300, y: 350); tracker.refresh()
        check(tracker.info[.sidebar] == .inside, "the floating zone reaches 308 pt")
        check(delays.last == 0.15, "entering the sidebar arms a 0.15 s linger")
        let afterSidebar = tracker.stopScheduleCount
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == afterSidebar, "sidebar-only motion does not arm the edge stop")
        clock.advance(0.149)
        check(tracker.info[.sidebar] == .inside, "not lingered before 0.15 s")
        clock.advance(0.001)
        check(tracker.info[.sidebar] == .hasLingered && published.last?[.sidebar] == .hasLingered, "lingered at 0.15 s and published")

        let beforeBurst = tracker.stopScheduleCount
        pointer = NSPoint(x: 3, y: 400); tracker.refresh()
        check(tracker.info[.innerLeftEdge] == .inside, "burst starts on the inner edge")
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == beforeBurst + 1, "burst entry arms one stop")
        clock.advance(0.05)
        tracker.mouseMoved()
        clock.advance(0.05)
        check(tracker.stopScheduleCount == beforeBurst + 1, "burst moves share the pending stop")
        check(tracker.info[.innerLeftEdge] == .inside, "a later move keeps the 0.08 s stop")
        clock.advance(0.029)
        check(tracker.info[.innerLeftEdge] == .inside, "no stop before 0.08 s after the last move")
        clock.advance(0.001)
        check(tracker.info[.innerLeftEdge] == .hasStopped && published.last?[.innerLeftEdge] == .hasStopped,
              "stop is 0.08 s after the last move")

        let before = published.count
        listening = false; NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(!tracker.isListening && tracker.info == SidebarHoverInfo(), "resigning key resets every region")
        check(published.count == before + 1 && published.last == SidebarHoverInfo(), "the reset is reported")
        pointer = NSPoint(x: 800, y: 350); tracker.refresh()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        check(tracker.info == SidebarHoverInfo() && published.count == before + 1, "no report while not listening")
        clock.advance(0.2)
        check(tracker.info == SidebarHoverInfo() && published.count == before + 1, "nothing promotes while not listening")
        pointer = NSPoint(x: 100, y: 350)
        listening = true; NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(tracker.isListening && tracker.info[.sidebar] == .inside && tracker.info[.window] == .inside
              && published.count == before + 2, "becoming key re-tests the pointer")
        listening = false; tracker.refresh()
        check(!tracker.isListening && published.last == SidebarHoverInfo() && published.count == before + 3,
              "a refresh after losing key resets and reports")
        listening = true; tracker.refresh()
        check(tracker.isListening && tracker.info[.sidebar] == .inside && published.count == before + 4,
              "a refresh in the key window starts listening and reports")

        let entered = published.count
        tracker.isEnabled = false
        check(tracker.info == SidebarHoverInfo() && published.count == entered && !tracker.isListening,
              "disabled drops the states silently")
        clock.advance(0.2)
        check(tracker.info == SidebarHoverInfo() && published.count == entered, "pending lingers die with the old tracker")
        tracker.isEnabled = true
        check(!tracker.isListening && published.count == entered, "enabling does not report synchronously")
        clock.advance(0)
        check(tracker.isListening && tracker.info[.sidebar] == .inside && tracker.info[.window] == .inside
              && published.count == entered + 1, "the new tracker reports the pointer on the next turn")
        tracker.isEnabled = false; tracker.isEnabled = true; tracker.refresh()
        check(tracker.isListening && published.count == entered + 2, "an explicit refresh starts the new tracker at once")
        clock.advance(0)
        check(published.count == entered + 2, "the deferred start then finds nothing new")

        let rebuilds = regionBuilds
        tracker.setNeedsRefresh()
        check(regionBuilds == rebuilds, "a geometry refresh waits for the next turn")
        clock.advance(0)
        check(regionBuilds > rebuilds, "a geometry refresh rebuilds hover rects")

        let publishedAtInvalidate = published.count
        tracker.invalidate()
        check(!tracker.isListening && tracker.isInvalidated, "invalidating removes the listener")
        tracker.isEnabled = false; tracker.isEnabled = true
        tracker.refresh(); tracker.setNeedsRefresh()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        clock.advance(0.2)
        check(!tracker.isListening && published.count == publishedAtInvalidate, "an invalidated tracker never listens or reports")
        print("SidebarHoverTracker: \(count) assertions passed")
    }
}
