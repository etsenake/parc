import AppKit
import Combine
import QuartzCore
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
enum SidebarResizeRegionTestsSupport {
    final class FakePan: NSPanGestureRecognizer {
        var fakeState: NSGestureRecognizer.State = .possible
        var translationX: CGFloat = 0
        var velocityX: CGFloat = 0
        var measuredIn: [NSView?] = []
        override var state: NSGestureRecognizer.State { get { fakeState } set { fakeState = newValue } }
        override func translation(in view: NSView?) -> NSPoint { measuredIn.append(view); return NSPoint(x: translationX, y: 7) }
        override func velocity(in view: NSView?) -> NSPoint { NSPoint(x: velocityX, y: 9) }
    }

    @MainActor final class ManualClock {
        private var now: TimeInterval = 0
        private var pending: [(at: TimeInterval, work: () -> Void)] = []

        func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) { pending.append((now + delay, work)) }

        func advance(by seconds: TimeInterval) {
            now += seconds
            while let index = pending.indices.filter({ pending[$0].at <= now }).min(by: { pending[$0].at < pending[$1].at }) {
                pending.remove(at: index).work()
            }
        }
    }

    typealias R = SidebarResizeRegionView

    @MainActor final class Strip {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 700))
        let region = R(frame: .zero)
        var haptics = 0
        var pans: [(NSGestureRecognizer.State, CGFloat, CGFloat)] = []
        let pan = FakePan(target: nil, action: nil)
        let clock = ManualClock()

        init() {
            window.isReleasedWhenClosed = false
            region.reducesMotion = { false }
            region.delay = { [clock] seconds in
                let subject = PassthroughSubject<Void, Never>()
                clock.schedule(after: seconds) { subject.send(()); subject.send(completion: .finished) }
                return subject.eraseToAnyPublisher()
            }
            region.runFadeOut = { [clock, indicator = region.indicatorLayer] animations, completion in
                animations()
                clock.schedule(after: indicator.animation(forKey: "opacity")?.duration ?? 0, completion)
            }
            root.wantsLayer = true
            window.contentView = root
            region.performHaptic = { [weak self] in self?.haptics += 1 }
            region.referenceView = sidebar
            root.addSubview(sidebar)
            root.addSubview(region)
            region.frame = R.frame(trailing: sidebar.frame, in: root.bounds)
            root.layoutSubtreeIfNeeded()
            region.onPan = { [weak self] in self?.pans.append(($0, $1, $2)) }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var indicator: CAShapeLayer { region.indicatorLayer }
        var center: NSPoint { region.convert(NSPoint(x: region.bounds.midX, y: region.bounds.midY), to: nil) }

        func send(_ state: NSGestureRecognizer.State, _ x: CGFloat, _ v: CGFloat) {
            pan.fakeState = state
            pan.translationX = x
            pan.velocityX = v
            region.perform(NSSelectorFromString("handlePan:"), with: pan)
        }

        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: center, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func fade() -> CABasicAnimation? { indicator.animation(forKey: "opacity") as? CABasicAnimation }
    }
}
