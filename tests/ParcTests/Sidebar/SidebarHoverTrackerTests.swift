import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

private final class FlippedRoot: NSView { override var isFlipped: Bool { true } }

@MainActor
private final class ManualClock {
    private(set) var now: CFTimeInterval = 0
    private var pending: [(at: CFTimeInterval, order: Int, body: @MainActor () -> Void)] = []
    private var order = 0

    func schedule(_ delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        order += 1
        pending.append((now + delay, order, body))
    }

    func advance(_ interval: TimeInterval) {
        let target = now + interval
        var fired = 0
        while let next = pending.filter({ $0.at <= target + 1e-9 }).min(by: { ($0.at, $0.order) < ($1.at, $1.order) }) {
            fired += 1
            guard fired < 1_000 else { Issue.record("a timer keeps re-arming without time passing"); return }
            pending.removeAll { $0.order == next.order }
            now = max(now, next.at)
            next.body()
        }
        now = max(now, target)
    }
}

@MainActor
struct SidebarHoverTrackerTests {
    @MainActor private final class Hovering {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = FlippedRoot(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        var presentation = SidebarHoverZones.Presentation.hidden
        var pointer = NSPoint(x: 500, y: 350)
        var listening = true
        var published: [SidebarHoverInfo] = []
        var regionBuilds = 0
        let tracker = SidebarHoverTracker()
        let clock = ManualClock()
        var delays: [TimeInterval] = []

        init(attach: Bool = true) {
            window.isReleasedWhenClosed = false
            window.contentView = root
            tracker.now = { [unowned clock] in clock.now }
            tracker.after = { [weak self] delay, body in self?.delays.append(delay); self?.clock.schedule(delay, body) }
            tracker.nextTurn = { [weak self] body in self?.clock.schedule(0, body) }
            tracker.view = root
            tracker.canListen = { [weak self] in self?.listening ?? false }
            let window = self.window
            tracker.mouseLocation = { [weak self] in
                guard let self else { return .zero }
                return window.convertPoint(toScreen: root.convert(pointer, to: nil))
            }
            let root = self.root
            tracker.regions = { [weak self] info in
                guard let self else { return [:] }
                regionBuilds += 1
                return SidebarHoverZones.rects(size: root.bounds.size, presentation: presentation, sidebarWidth: 228, showingToolbar: false,
                                               trafficLightHeight: 0, info: info)
                    .mapValues { NSRect(x: $0.minX, y: root.bounds.height - $0.maxY, width: $0.width, height: $0.height) }
            }
            tracker.onChange = { [weak self] in self?.published.append($0) }
            window.acceptsMouseMovedEvents = false
            if attach { tracker.attach(to: window) }
        }

        deinit { MainActor.assumeIsolated { tracker.invalidate(); window.close() } }

        func moveInsideTheWindow() {
            for offset in 1...20 {
                pointer = NSPoint(x: 500 + CGFloat(offset), y: 350 + CGFloat(offset % 3))
                tracker.refresh()
                tracker.mouseMoved()
            }
        }

        func onTheInnerEdge() {
            pointer = NSPoint(x: 3, y: 690)
            tracker.refresh()
        }

        func armedEdge() {
            onTheInnerEdge()
            delays.removeAll()
            tracker.mouseMoved()
        }

        func overFloatingSidebar() {
            presentation = .floating
            tracker.setNeedsRefresh()
            pointer = NSPoint(x: 300, y: 350)
            tracker.refresh()
        }

        func resignKey() {
            listening = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    @Test func theWindowReceivesMovesBeyondItsFrame() {
        let h = Hovering()
        #expect(h.window.acceptsMouseMovedEvents)
    }

    @Test func listeningReportsTheCurrentPointerOnce() {
        let h = Hovering()
        #expect(h.published.count == 1)
        #expect(h.tracker.info[.window] == .inside)
        #expect(h.tracker.info[.innerLeftEdge] == SidebarHoverState.none)
    }

    @Test func anInPageListenStartDoesNotArmTheEdgeStop() {
        #expect(Hovering().tracker.stopScheduleCount == 0)
    }

    @Test func insideWindowMotionReusesConvertedRegions() {
        let h = Hovering()
        let idle = h.regionBuilds
        h.moveInsideTheWindow()
        #expect(h.regionBuilds == idle)
    }

    @Test func insideWindowMotionDoesNotPublishOrChangeRegions() {
        let h = Hovering()
        h.moveInsideTheWindow()
        #expect(h.published.count == 1)
        #expect(h.tracker.info[.window] == .inside)
        #expect(h.tracker.info[.innerLeftEdge] == SidebarHoverState.none)
        #expect(h.tracker.stopScheduleCount == 0)
    }

    @Test func anIdenticalPointerSkipsContainmentWork() {
        let h = Hovering()
        h.moveInsideTheWindow()
        let builds = h.regionBuilds
        h.tracker.mouseMoved()
        #expect(h.regionBuilds == builds)
        #expect(h.published.count == 1)
    }

    @Test func enteringTheInnerEdgeRebuildsTheWidenedZones() {
        let h = Hovering()
        let builds = h.regionBuilds
        h.onTheInnerEdge()
        #expect(h.regionBuilds > builds)
    }

    @Test func bottomLeftIsTheInnerEdge() {
        let h = Hovering()
        h.onTheInnerEdge()
        #expect(h.tracker.info[.innerLeftEdge] == .inside)
        #expect(h.tracker.info[.innerTopLeftEdge] == SidebarHoverState.none)
    }

    @Test func refreshAloneDoesNotArmTheEdgeStop() {
        let h = Hovering()
        h.onTheInnerEdge()
        #expect(h.tracker.stopScheduleCount == 0)
    }

    @Test func mouseMovedOnAStoppableEdgeArmsOneStopAtEightyMilliseconds() {
        let h = Hovering()
        h.armedEdge()
        #expect(h.tracker.stopScheduleCount == 1)
        #expect(h.delays == [0.08])
    }

    @Test func anUnchangedRefreshPublishesNothing() {
        let h = Hovering()
        h.armedEdge()
        h.pointer = NSPoint(x: 3, y: 690)
        h.tracker.refresh()
        h.tracker.mouseMoved()
        #expect(h.published.count == 2)
        #expect(h.tracker.stopScheduleCount == 1)
    }

    @Test func thereIsNoPromotionBeforeTheStop() {
        let h = Hovering()
        h.armedEdge()
        h.clock.advance(0.079)
        #expect(h.tracker.info[.innerLeftEdge] == .inside)
        #expect(h.published.count == 2)
    }

    @Test func theEdgeIsStoppedAndPublishedAtEightyMilliseconds() {
        let h = Hovering()
        h.armedEdge()
        h.clock.advance(0.08)
        #expect(h.tracker.info[.innerLeftEdge] == .hasStopped)
        #expect(h.published.last?[.innerLeftEdge] == .hasStopped)
        #expect(h.published.count == 3)
    }

    @Test func aNewStoppableEdgeArmsTheStopAgain() {
        let h = Hovering()
        h.armedEdge()
        h.clock.advance(0.08)
        h.pointer = NSPoint(x: 20, y: 5)
        h.tracker.refresh()
        h.tracker.mouseMoved()
        #expect(h.tracker.info[.innerTopLeftEdge] == .inside)
        #expect(h.tracker.info[.innerLeftEdge] == SidebarHoverState.none)
        #expect(h.tracker.stopScheduleCount == 2)
    }

    @Test func theFloatingZoneReachesThreeHundredEightPoints() {
        let h = Hovering()
        h.overFloatingSidebar()
        #expect(h.tracker.info[.sidebar] == .inside)
    }

    @Test func enteringTheSidebarArmsAFifteenHundredthsLinger() {
        let h = Hovering()
        h.overFloatingSidebar()
        #expect(h.delays.last == 0.15)
    }

    @Test func sidebarOnlyMotionDoesNotArmTheEdgeStop() {
        let h = Hovering()
        h.overFloatingSidebar()
        let armed = h.tracker.stopScheduleCount
        h.tracker.mouseMoved()
        #expect(h.tracker.stopScheduleCount == armed)
    }

    @Test func theSidebarHasNotLingeredBeforeItsDelay() {
        let h = Hovering()
        h.overFloatingSidebar()
        h.clock.advance(0.149)
        #expect(h.tracker.info[.sidebar] == .inside)
    }

    @Test func theSidebarLingersAndPublishesAtItsDelay() {
        let h = Hovering()
        h.overFloatingSidebar()
        h.clock.advance(0.15)
        #expect(h.tracker.info[.sidebar] == .hasLingered)
        #expect(h.published.last?[.sidebar] == .hasLingered)
    }

    private func burst(_ h: Hovering) -> Int {
        h.overFloatingSidebar()
        h.clock.advance(0.15)
        let before = h.tracker.stopScheduleCount
        h.pointer = NSPoint(x: 3, y: 400)
        h.tracker.refresh()
        h.tracker.mouseMoved()
        return before
    }

    @Test func burstEntryArmsOneStop() {
        let h = Hovering()
        let before = burst(h)
        #expect(h.tracker.info[.innerLeftEdge] == .inside)
        #expect(h.tracker.stopScheduleCount == before + 1)
    }

    @Test func burstMovesShareThePendingStop() {
        let h = Hovering()
        let before = burst(h)
        h.clock.advance(0.05)
        h.tracker.mouseMoved()
        h.clock.advance(0.05)
        #expect(h.tracker.stopScheduleCount == before + 1)
        #expect(h.tracker.info[.innerLeftEdge] == .inside)
    }

    @Test func noStopBeforeEightyMillisecondsAfterTheLastMove() {
        let h = Hovering()
        _ = burst(h)
        h.clock.advance(0.05)
        h.tracker.mouseMoved()
        h.clock.advance(0.05)
        h.clock.advance(0.029)
        #expect(h.tracker.info[.innerLeftEdge] == .inside)
    }

    @Test func stopIsEightyMillisecondsAfterTheLastMove() {
        let h = Hovering()
        _ = burst(h)
        h.clock.advance(0.05)
        h.tracker.mouseMoved()
        h.clock.advance(0.05)
        h.clock.advance(0.03)
        #expect(h.tracker.info[.innerLeftEdge] == .hasStopped)
        #expect(h.published.last?[.innerLeftEdge] == .hasStopped)
    }

    @Test func resigningKeyResetsEveryRegionAndReportsIt() {
        let h = Hovering()
        h.overFloatingSidebar()
        let before = h.published.count
        h.resignKey()
        #expect(!h.tracker.isListening)
        #expect(h.tracker.info == SidebarHoverInfo())
        #expect(h.published.count == before + 1)
        #expect(h.published.last == SidebarHoverInfo())
    }

    @Test func noReportWhileNotListening() {
        let h = Hovering()
        h.resignKey()
        let before = h.published.count
        h.pointer = NSPoint(x: 800, y: 350)
        h.tracker.refresh()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(h.tracker.info == SidebarHoverInfo())
        #expect(h.published.count == before)
    }

    @Test func nothingPromotesWhileNotListening() {
        let h = Hovering()
        h.armedEdge()
        h.resignKey()
        let before = h.published.count
        h.clock.advance(0.2)
        #expect(h.tracker.info == SidebarHoverInfo())
        #expect(h.published.count == before)
    }

    @Test func becomingKeyRetestsThePointer() {
        let h = Hovering()
        h.presentation = .floating
        h.resignKey()
        let before = h.published.count
        h.pointer = NSPoint(x: 100, y: 350)
        h.listening = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: h.window)
        #expect(h.tracker.isListening)
        #expect(h.tracker.info[.sidebar] == .inside)
        #expect(h.tracker.info[.window] == .inside)
        #expect(h.published.count == before + 1)
    }

    @Test func aRefreshAfterLosingKeyResetsAndReports() {
        let h = Hovering()
        h.presentation = .floating
        h.pointer = NSPoint(x: 100, y: 350)
        h.tracker.refresh()
        let before = h.published.count
        h.listening = false
        h.tracker.refresh()
        #expect(!h.tracker.isListening)
        #expect(h.published.last == SidebarHoverInfo())
        #expect(h.published.count == before + 1)
    }

    @Test func aRefreshInTheKeyWindowStartsListeningAndReports() {
        let h = Hovering()
        h.presentation = .floating
        h.resignKey()
        h.pointer = NSPoint(x: 100, y: 350)
        let before = h.published.count
        h.listening = true
        h.tracker.refresh()
        #expect(h.tracker.isListening)
        #expect(h.tracker.info[.sidebar] == .inside)
        #expect(h.published.count == before + 1)
    }

    @Test func disabledDropsTheStatesSilently() {
        let h = Hovering()
        let before = h.published.count
        h.tracker.isEnabled = false
        #expect(h.tracker.info == SidebarHoverInfo())
        #expect(h.published.count == before)
        #expect(!h.tracker.isListening)
    }

    @Test func pendingLingersDieWithTheOldTracker() {
        let h = Hovering()
        h.overFloatingSidebar()
        let before = h.published.count
        h.tracker.isEnabled = false
        h.clock.advance(0.2)
        #expect(h.tracker.info == SidebarHoverInfo())
        #expect(h.published.count == before)
    }

    @Test func enablingDoesNotReportSynchronously() {
        let h = Hovering()
        h.tracker.isEnabled = false
        let before = h.published.count
        h.tracker.isEnabled = true
        #expect(!h.tracker.isListening)
        #expect(h.published.count == before)
    }

    @Test func theNewTrackerReportsThePointerOnTheNextTurn() {
        let h = Hovering()
        h.presentation = .floating
        h.pointer = NSPoint(x: 100, y: 350)
        h.tracker.isEnabled = false
        let before = h.published.count
        h.tracker.isEnabled = true
        h.clock.advance(0)
        #expect(h.tracker.isListening)
        #expect(h.tracker.info[.sidebar] == .inside)
        #expect(h.tracker.info[.window] == .inside)
        #expect(h.published.count == before + 1)
    }

    @Test func anExplicitRefreshStartsTheNewTrackerAtOnce() {
        let h = Hovering()
        h.tracker.isEnabled = false
        let before = h.published.count
        h.tracker.isEnabled = true
        h.tracker.refresh()
        #expect(h.tracker.isListening)
        #expect(h.published.count == before + 1)
    }

    @Test func theDeferredStartThenFindsNothingNew() {
        let h = Hovering()
        h.tracker.isEnabled = false
        let before = h.published.count
        h.tracker.isEnabled = true
        h.tracker.refresh()
        h.clock.advance(0)
        #expect(h.published.count == before + 1)
    }

    @Test func aGeometryRefreshWaitsForTheNextTurn() {
        let h = Hovering()
        let builds = h.regionBuilds
        h.tracker.setNeedsRefresh()
        #expect(h.regionBuilds == builds)
    }

    @Test func aGeometryRefreshRebuildsHoverRects() {
        let h = Hovering()
        let builds = h.regionBuilds
        h.tracker.setNeedsRefresh()
        h.clock.advance(0)
        #expect(h.regionBuilds > builds)
    }

    @Test func invalidatingRemovesTheListener() {
        let h = Hovering()
        h.tracker.invalidate()
        #expect(!h.tracker.isListening)
        #expect(h.tracker.isInvalidated)
    }

    @Test func anInvalidatedTrackerNeverListensOrReports() {
        let h = Hovering()
        h.tracker.invalidate()
        let before = h.published.count
        h.tracker.isEnabled = false
        h.tracker.isEnabled = true
        h.tracker.refresh()
        h.tracker.setNeedsRefresh()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: h.window)
        h.clock.advance(0.2)
        #expect(!h.tracker.isListening)
        #expect(h.published.count == before)
    }
}
