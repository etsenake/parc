import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

enum SplitDividerTestsSupport {
    @MainActor final class SplitConstraintHost: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor final class SeeThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor final class SplitScaleWindow: NSWindow {
        var testScale: CGFloat = 2
        override var backingScaleFactor: CGFloat { testScale }

        static func make(width: CGFloat = 1200, height: CGFloat = 1200) -> SplitScaleWindow {
            _ = NSApplication.shared
            let window = SplitScaleWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                          styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }
    }

    static func near(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 0.000001 }
    }

    static func isDivider(_ change: SplitStackResize?, _ index: Int, slot: Int?, share: Double) -> Bool {
        guard case .divider(let changed, let changedSlot, let leading)? = change else { return false }
        return changed == index && changedSlot == slot && abs(leading - share) < 0.000001
    }

    @MainActor final class SplitRig {
        let window: SplitScaleWindow
        let view: ParcSplitView
        let panes: [NSView]
        var commits: [[Double]] = []

        init(count: Int = 3, factors: [Double]? = nil, orientation: SplitOrientation = .horizontal,
             frame: NSRect = NSRect(x: 0, y: 0, width: 1000, height: 1000), window size: NSSize = NSSize(width: 1200, height: 1200),
             scale: CGFloat = 2, attached: Bool = true, accepts: Bool = true) {
            window = SplitScaleWindow.make(width: size.width, height: size.height)
            window.testScale = scale
            view = ParcSplitView(frame: frame)
            panes = (0..<count).map { _ in NSView() }
            panes.forEach(view.addArrangedSubview)
            if attached { window.contentView!.addSubview(view) }
            view.configure(orientation: orientation, factors: factors ?? Array(repeating: 1, count: count))
            view.prepareDividerResize = { [weak self] in { self?.commits.append($0); return accepts } }
        }

        deinit { MainActor.assumeIsolated { view.finishDividerResize(commit: false); window.close() } }

        var frames: [NSRect] { panes.map(\.frame) }
        var widths: [CGFloat] { panes.map { $0.frame.width } }
        var heights: [CGFloat] { panes.map { $0.frame.height } }

        func dividerOrigin(_ index: Int = 0, gap: CGFloat = 5, y: CGFloat = 200) -> NSPoint {
            NSPoint(x: panes[index].frame.maxX + gap, y: y)
        }

        func doubleClick(at point: NSPoint) {
            view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [],
                                                    timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1,
                                                    clickCount: 2, pressure: 1)!)
        }
    }
}
