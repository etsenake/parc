import AppKit
import ParcCore
import QuartzCore
import Testing
@testable import Parc

enum SplitDropReservationSupport {
    @MainActor final class ReservedHost: NSView { override var isFlipped: Bool { true } }

    @MainActor final class Scene {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1810, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        let host = ReservedHost(frame: NSRect(x: 0, y: 0, width: 1810, height: 700))
        let split: ParcSplitView
        let first = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let second = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let ink = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let originalFrames: [NSRect]
        var third: SplitDropReservedPane?
        var columnFrames: [NSRect] = []
        var editing: [Bool] = []

        var panes: [SplitDropReservedPane] { [first, second] + (third.map { [$0] } ?? []) }
        var allowAll: (SplitDropTarget, SplitOrientation) -> Bool { { _, _ in true } }

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = host
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            split.addArrangedSubview(first)
            split.addArrangedSubview(second)
            split.configure(orientation: .horizontal, factors: [0.75, 0.25])
            split.constrain(to: host)
            originalFrames = split.arrangedSubviews.map(\.frame)
            split.onInteractivePaneEditing = { [weak self] in self?.editing.append($0) }
        }

        func addColumn() {
            let pane = SplitDropReservedPane(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
            third = pane
            split.addArrangedSubview(pane)
            let column = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.5, 0.5], [1]])
            split.configure(orientation: .horizontal, factors: column.flattenedFactors, stacks: column)
            host.layoutSubtreeIfNeeded()
            columnFrames = split.arrangedSubviews.map(\.frame)
        }

        func lease() -> ParcSplitView.DropReservation {
            let lease = immediate(split.prepareDropReservation(in: host, contents: panes.map(\.body))!)
            lease.setInsertionColor { [ink] in ink }
            lease.clock = { 0 }
            return lease
        }

        func region() -> NSView? { split.subviews.first { view in !panes.contains { $0 === view } } }

        func leftEdge(_ lease: ParcSplitView.DropReservation) -> SplitDropGeometry.Proposal {
            lease.proposal(at: NSPoint(x: 1, y: 200), canPropose: allowAll)!
        }

        func leave(_ lease: ParcSplitView.DropReservation) -> SplitDropGeometry.Proposal? {
            lease.proposal(at: NSPoint(x: -20, y: -20), canPropose: allowAll)
        }
    }
}
