import AppKit
import QuartzCore

@MainActor final class FlippedRoot: NSView { override var isFlipped: Bool { true } }

@main @MainActor struct SidebarHoverTrackerTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarHoverTracker: \(message)") }
    }
    static func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds)) }
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
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == 1, "mouseMoved on a stoppable edge arms one stop")
        pointer = NSPoint(x: 3, y: 690); tracker.refresh(); tracker.mouseMoved()
        check(published.count == 2, "an unchanged refresh publishes nothing")
        check(tracker.stopScheduleCount == 1, "identical edge motion keeps one pending stop")
        wait(0.05)
        check(tracker.info[.innerLeftEdge] == .inside, "no promotion before the stop")
        wait(0.06)
        check(tracker.info[.innerLeftEdge] == .hasStopped && published.last?[.innerLeftEdge] == .hasStopped, "stopped and published")
        pointer = NSPoint(x: 20, y: 5); tracker.refresh(); tracker.mouseMoved()
        check(tracker.info[.innerTopLeftEdge] == .inside && tracker.info[.innerLeftEdge] == .none, "top-left in flipped coordinates")
        check(tracker.stopScheduleCount == 2, "a new stoppable edge arms the stop again")

        presentation = .floating
        tracker.setNeedsRefresh()
        pointer = NSPoint(x: 300, y: 350); tracker.refresh()
        check(tracker.info[.sidebar] == .inside, "the floating zone reaches 308 pt")
        let afterSidebar = tracker.stopScheduleCount
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == afterSidebar, "sidebar-only motion does not arm the edge stop")
        wait(0.1)
        check(tracker.info[.sidebar] == .inside, "not lingered at 0.1 s")
        wait(0.12)
        check(tracker.info[.sidebar] == .hasLingered && published.last?[.sidebar] == .hasLingered, "lingered after 0.15 s and published")

        let beforeBurst = tracker.stopScheduleCount
        pointer = NSPoint(x: 3, y: 400); tracker.refresh()
        check(tracker.info[.innerLeftEdge] == .inside, "burst starts on the inner edge")
        tracker.mouseMoved()
        check(tracker.stopScheduleCount == beforeBurst + 1, "burst entry arms one stop")
        wait(0.05)
        tracker.mouseMoved()
        wait(0.05)
        check(tracker.stopScheduleCount == beforeBurst + 1, "burst moves share the pending stop")
        check(tracker.info[.innerLeftEdge] == .inside, "a later move keeps the 0.08 s stop")
        wait(0.06)
        check(tracker.info[.innerLeftEdge] == .hasStopped && published.last?[.innerLeftEdge] == .hasStopped,
              "stop is still 0.08 s after the last move")

        let before = published.count
        listening = false; NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        check(!tracker.isListening && tracker.info == SidebarHoverInfo(), "resigning key resets every region")
        check(published.count == before + 1 && published.last == SidebarHoverInfo(), "the reset is reported")
        pointer = NSPoint(x: 800, y: 350); tracker.refresh()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        check(tracker.info == SidebarHoverInfo() && published.count == before + 1, "no report while not listening")
        wait(0.2)
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
        wait(0.2)
        check(tracker.info == SidebarHoverInfo(), "pending lingers die with the old tracker")
        tracker.isEnabled = true
        check(!tracker.isListening && published.count == entered, "enabling does not report synchronously")
        wait(0.02)
        check(tracker.isListening && tracker.info[.sidebar] == .inside && tracker.info[.window] == .inside
              && published.count == entered + 1, "the new tracker reports the pointer on the next turn")
        tracker.isEnabled = false; tracker.isEnabled = true; tracker.refresh()
        check(tracker.isListening && published.count == entered + 2, "an explicit refresh starts the new tracker at once")
        wait(0.02)
        check(published.count == entered + 2, "the deferred start then finds nothing new")

        let rebuilds = regionBuilds
        tracker.setNeedsRefresh(); wait(0.02)
        check(regionBuilds > rebuilds, "a geometry refresh rebuilds hover rects")

        let publishedAtInvalidate = published.count
        tracker.invalidate()
        check(!tracker.isListening && tracker.isInvalidated, "invalidating removes the listener")
        tracker.isEnabled = false; tracker.isEnabled = true
        tracker.refresh(); tracker.setNeedsRefresh()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        wait(0.2)
        check(!tracker.isListening && published.count == publishedAtInvalidate, "an invalidated tracker never listens or reports")
        print("SidebarHoverTracker: \(count) assertions passed")
    }
}
