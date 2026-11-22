import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsReconcile {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

    @MainActor private final class HostedPage: NSView {
        let inner = NSView()
        override func layout() {
            super.layout()
            if inner.superview !== self { addSubview(inner) }
            inner.frame = bounds
        }
    }

    private static func live() -> (window: SplitScaleWindow, view: ParcSplitView, first: NSView, second: NSView) {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let view = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        window.contentView!.addSubview(view)
        let first = NSView(), second = NSView()
        view.addArrangedSubview(first)
        view.configure(orientation: .horizontal, factors: [1])
        return (window, view, first, second)
    }

    @Test func addingAPaneKeepsTheOriginalChildInTheSameHierarchy() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        let inserted = view.reconcileArrangedSubviews([first, second])
        #expect(inserted.isEmpty)
        #expect(view.arrangedSubviews.count == 2)
        #expect(view.arrangedSubviews[0] === first && view.arrangedSubviews[1] === second)
        #expect(first.superview === view)
    }

    @Test func theOriginalPaneResizesInPlace() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        let width = first.frame.width
        _ = view.reconcileArrangedSubviews([first, second])
        view.configure(orientation: .horizontal, factors: [1, 1])
        #expect(first.superview === view)
        #expect(first.frame.width < width && first.frame.width > 0)
    }

    @Test func aHostedChildThatSizesInLayoutFollowsThePaneInTheSamePass() {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        defer { window.close() }
        let hosted = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        window.contentView!.addSubview(hosted)
        let pane = HostedPage()
        hosted.addArrangedSubview(pane)
        hosted.configure(orientation: .horizontal, factors: [1])
        #expect(pane.inner.frame.size == pane.frame.size)
        #expect(pane.frame.width == 800)
    }

    @Test func splittingPushesTheNewSizeIntoTheHostedChildImmediately() {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        defer { window.close() }
        let hosted = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        window.contentView!.addSubview(hosted)
        let pane = HostedPage()
        hosted.addArrangedSubview(pane)
        hosted.configure(orientation: .horizontal, factors: [1])
        hosted.addArrangedSubview(NSView())
        hosted.configure(orientation: .horizontal, factors: [1, 1])
        #expect(pane.inner.frame.size == pane.frame.size)
        #expect(pane.frame.width < 800)
    }

    @Test func reorderDoesNotParkSurvivingPanes() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        _ = view.reconcileArrangedSubviews([first, second])
        let reordered = view.reconcileArrangedSubviews([second, first])
        #expect(reordered.isEmpty)
        #expect(view.arrangedSubviews[0] === second)
        #expect(first.superview === view)
    }

    @Test func onlyTheDepartingPaneLeavesTheArrangedList() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        _ = view.reconcileArrangedSubviews([first, second])
        view.configure(orientation: .horizontal, factors: [1, 1])
        let departed = view.reconcileArrangedSubviews([first])
        #expect(departed.count == 1 && departed[0] === second)
        #expect(first.superview === view)
    }

    @Test func aDepartingPaneStaysOnScreenWhereItWasUntilItsOwnerParksIt() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        _ = view.reconcileArrangedSubviews([first, second])
        view.configure(orientation: .horizontal, factors: [1, 1])
        _ = view.reconcileArrangedSubviews([first])
        #expect(second.superview === view)
        #expect(second.frame.width > 0)
    }

    @Test func aPaneHeldOutsideTheArrangementFollowsThePageAreasSizeByItsShare() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        _ = view.reconcileArrangedSubviews([first, second])
        view.configure(orientation: .horizontal, factors: [1, 1])
        _ = view.reconcileArrangedSubviews([first])
        let heldWidth = second.frame.width, heldHeight = second.frame.height, areaWidth = view.bounds.width
        second.autoresizingMask = [.width, .height, .minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        view.setFrameSize(NSSize(width: view.frame.width + 200, height: view.frame.height + 100))
        #expect(abs(second.frame.width - (heldWidth + 200 * heldWidth / areaWidth)) < 1)
        #expect(second.frame.height > heldHeight)
    }

    @Test func aReleasedPaneKeepsItsFrameUntilItIsParked() {
        let (window, view, first, second) = Self.live()
        defer { window.close() }
        _ = view.reconcileArrangedSubviews([first, second])
        view.configure(orientation: .horizontal, factors: [1, 1])
        _ = view.reconcileArrangedSubviews([first])
        second.autoresizingMask = []
        let released = second.frame
        view.setFrameSize(NSSize(width: view.frame.width - 200, height: view.frame.height - 100))
        #expect(second.frame == released)
    }
}
