import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class SplitConstraintHost: NSView {
    override var isFlipped: Bool { true }
}

@MainActor private final class SeeThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class SplitScaleWindow: NSWindow {
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

private func near(_ values: [Double], _ expected: [Double]) -> Bool {
    values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 0.000001 }
}

private func isDivider(_ change: SplitStackResize?, _ index: Int, slot: Int?, share: Double) -> Bool {
    guard case .divider(let changed, let changedSlot, let leading)? = change else { return false }
    return changed == index && changedSlot == slot && abs(leading - share) < 0.000001
}

@MainActor private final class SplitRig {
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

@MainActor
struct SplitDividerScaleTests {
    @Test func aDetachedViewRoundsEveryPaneIndependentlyWithoutLastPaneFill() {
        let rig = SplitRig(attached: false)
        #expect(rig.widths == [327, 327, 327])
        #expect(rig.panes.last?.frame.maxX == 1001)
    }

    @Test func theWindowBackingScaleRoundsLengthsBeforeFinalIntegerEdges() {
        let rig = SplitRig()
        #expect(rig.widths == [327, 326, 327])
        #expect(rig.panes.map { $0.frame.minX } == [0, 337, 673])
    }

    @Test func verticalPanesFollowTheSameLengthAndPrefixPositionCalculation() {
        let rig = SplitRig(orientation: .vertical)
        #expect(rig.heights == [327, 326, 327])
        #expect(rig.panes.map { $0.frame.minY } == [0, 337, 673])
    }

    @Test func aScaleChangeRecalculatesExistingPanesWithoutAModelWrite() {
        let rig = SplitRig()
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.widths == [327, 327, 327])
        #expect(rig.panes.last?.frame.maxX == 1001)
        #expect(rig.commits.isEmpty)
    }

    @Test func nativePreviewRecalculatesEveryFrameFromIndependentlyRoundedLengths() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        #expect(rig.commits.isEmpty)
        #expect(rig.widths == [325, 263, 392])
        #expect(rig.panes.map { $0.frame.minX } == [0, 335, 608])
    }

    @Test func theDurableRatioUsesTheGlobalAvailableAxisNotThePairWidth() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.count == 1)
        #expect(near(rig.commits[0], [324.3 / 980, 0.6 - 324.3 / 980, 0.4]))
    }

    @Test func theAcceptedPreviewAndTheSavedLayoutHaveIdenticalGeometryOnTheSamePanes() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        let preview = rig.frames
        rig.view.finishDividerResize(commit: true)
        #expect(rig.frames == preview)
        #expect(zip(rig.panes, rig.view.arrangedSubviews).allSatisfy { $0 === $1 })
    }

    @Test func aSameScaleBackingNotificationRetainsTheCurrentPreview() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        let preview = rig.frames
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.frames == preview)
    }

    @Test func anActualScaleChangeCancelsTheCapturedPreviewAndRestoresSourceRatios() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let before = rig.frames
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.isEmpty)
        rig.window.testScale = 2
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.frames == before)
    }

    @Test func completionRejectsAChangedScaleEvenBeforeItsNotificationArrives() {
        let rig = SplitRig(factors: [0.3, 0.3, 0.4])
        let before = rig.frames
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 30.3, y: 200), velocity: 200)
        rig.window.testScale = 1
        rig.view.finishDividerResize(commit: true)
        rig.window.testScale = 2
        rig.view.viewDidChangeBackingProperties()
        #expect(rig.commits.isEmpty)
        #expect(rig.frames == before)
    }

    @Test func minimumRedistributionCanMoveTheLivePanesOriginWhileKeepingEarlierShare() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: 200), velocity: 200)
        #expect(rig.panes[0].frame.width == 392)
        #expect(rig.panes[1].frame.minX == 402)
        #expect(rig.panes[1].frame.width == 240)
    }

    @Test func theNextUpdateRetainsTheCapturedHandleOffsetRelativeToTheLivePane() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        let held = NSPoint(x: origin.x + 20, y: 200)
        rig.view.updateDividerResize(at: held, velocity: 200)
        rig.view.updateDividerResize(at: held, velocity: 200)
        #expect(rig.panes[1].frame.width == 220)
        #expect(rig.commits.isEmpty)
    }

    @Test func cancelRestoresSourceRatiosAfterTheLiveOriginMoved() {
        let rig = SplitRig(factors: [0.4, 0.01, 0.59])
        let before = rig.frames
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 20, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: false)
        #expect(rig.frames == before)
        #expect(rig.commits.isEmpty)
    }

    @Test func anInvalidWindowScaleCannotProduceNonfiniteGeometry() {
        let rig = SplitRig()
        rig.window.testScale = .nan
        rig.view.viewDidChangeBackingProperties()
        rig.view.configure(orientation: .horizontal, factors: [1, 1, 1])
        #expect(rig.widths == [327, 327, 327])
    }

    @Test func anUnpersistableNonPositiveFactorRefusesInsteadOfCorruptingItsGroup() {
        let rig = SplitRig(factors: [0.01, 0.01, 0.98], orientation: .vertical)
        let before = rig.frames
        let origin = NSPoint(x: 20, y: rig.panes[0].frame.maxY + 5)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: 20, y: origin.y + 20), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.isEmpty)
        #expect(rig.frames == before)
    }

    @Test func sideBySidePanesKeepOrdinaryHitTestingOutsideAPan() {
        let rig = SplitRig()
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.panes[0])
    }

    @Test func aSideBySidePanSetsItsReasonAndLocksPaneInput() {
        let rig = SplitRig()
        var activity: [Bool] = []
        rig.view.onDividerPanActivity = { activity.append($0) }
        let origin = rig.dividerOrigin()
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.beginDividerPan(at: origin)
        #expect(activity == [true])
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.view)
    }

    @Test func aBackingScaleChangeMidPanClearsTheReasonAndThePaneLock() {
        let rig = SplitRig()
        var activity: [Bool] = []
        rig.view.onDividerPanActivity = { activity.append($0) }
        let origin = rig.dividerOrigin()
        rig.view.beginDividerResize(at: origin)
        rig.view.beginDividerPan(at: origin)
        rig.window.testScale = 1
        rig.view.viewDidChangeBackingProperties()
        #expect(activity == [true, false])
        #expect(!rig.view.isDividerPanActive)
        #expect(rig.view.hitTest(NSPoint(x: 100, y: 500)) === rig.panes[0])
    }
}

@MainActor
struct SplitDividerConstraintTests {
    @MainActor private final class Rig {
        let window = SplitScaleWindow.make(width: 1000, height: 800)
        let windowFrame: NSRect
        let host = SplitConstraintHost(frame: NSRect(x: 20, y: 30, width: 500, height: 300))
        let split: ParcSplitView
        let panes: [NSView]
        var commits = 0

        init(factors: [Double] = [1, 2, 3]) {
            windowFrame = window.frame
            window.contentView!.addSubview(host)
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            split.constrain(to: host)
            panes = (0..<3).map { _ in NSView() }
            panes.forEach(split.addArrangedSubview)
            split.configure(orientation: .horizontal, factors: factors)
            split.prepareDividerResize = { [weak self] in { _ in self?.commits += 1; return true } }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var frames: [NSRect] { panes.map(\.frame) }
    }

    @Test func aSplitNeverGrowsPastAPageAreaTooSmallForItsMinimums() {
        let rig = Rig()
        #expect(rig.split.frame == rig.host.bounds)
    }

    @Test func theSplitMinimumDoesNotEnlargeOrRepositionTheHostOrWindow() {
        let rig = Rig()
        #expect(rig.host.frame == NSRect(x: 20, y: 30, width: 500, height: 300))
        #expect(rig.window.frame == rig.windowFrame)
    }

    @Test func panesShortOfRoomForTheMinimumShareThePageAreaEvenly() {
        let rig = Rig()
        #expect(rig.frames == [NSRect(x: 0, y: 0, width: 160, height: 300), NSRect(x: 170, y: 0, width: 160, height: 300),
                               NSRect(x: 340, y: 0, width: 160, height: 300)])
    }

    @Test func draggingBetweenSqueezedPanesMovesNothingAndSavesNothing() {
        let rig = Rig()
        let frames = rig.frames
        let first = NSPoint(x: rig.panes[0].frame.maxX + 5, y: 200)
        #expect(rig.split.beginDividerResize(at: first))
        rig.split.updateDividerResize(at: NSPoint(x: first.x + 30, y: 200), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        let second = NSPoint(x: rig.panes[1].frame.maxX + 5, y: 200)
        #expect(rig.split.beginDividerResize(at: second))
        rig.split.updateDividerResize(at: NSPoint(x: second.x + 60, y: 200), velocity: 200)
        rig.split.updateDividerResize(at: NSPoint(x: second.x + 45, y: 200), velocity: -30)
        rig.split.finishDividerResize(commit: true)
        #expect(rig.commits == 0)
        #expect(rig.frames == frames)
    }

    @Test func squeezedPanesOfferNoStepsAndVoiceOversLimitsMeetAtTheDivider() {
        let rig = Rig()
        let splitter = (rig.split.accessibilitySplitters() ?? []).first as? ParcSplitView.DividerAccessibilityElement
        let values = [splitter?.accessibilityValue(), splitter?.accessibilityMinValue(), splitter?.accessibilityMaxValue()]
            .map { ($0 as? NSNumber)?.doubleValue }
        #expect(values == [33, 33, 33])
        #expect(!rig.split.canResizePane(rig.panes[0], growing: true))
        #expect(!rig.split.canResizePane(rig.panes[0], growing: false))
        #expect(splitter?.accessibilityPerformIncrement() == false)
        #expect(rig.commits == 0)
    }

    @Test func theSplitIsPinnedToItsPageAreasFourEdgesWithNoSizeMinimum() {
        let rig = Rig()
        let constraints = (rig.host.constraints + rig.split.constraints).filter {
            ($0.firstItem as? NSView) === rig.split || ($0.secondItem as? NSView) === rig.split
        }.filter(\.isActive)
        #expect(constraints.count == 4)
        #expect(constraints.allSatisfy { $0.priority == .required && [.leading, .top, .trailing, .bottom].contains($0.firstAttribute) })
    }

    @Test func theSameConstrainedContainerFillsALargerHost() {
        let rig = Rig()
        rig.host.frame.size = NSSize(width: 1200, height: 900)
        rig.host.layoutSubtreeIfNeeded()
        #expect(rig.split.frame == rig.host.bounds)
        #expect(rig.panes.last?.frame.maxX == 1200)
    }

    @Test func aShortTopAndBottomSplitSharesItsHeightAndTakesNoWidthMinimum() {
        let rig = Rig()
        rig.host.frame.size = NSSize(width: 1200, height: 900)
        rig.host.layoutSubtreeIfNeeded()
        rig.split.configure(orientation: .vertical, factors: [1, 2, 3])
        rig.host.frame.size = NSSize(width: 500, height: 300)
        rig.host.layoutSubtreeIfNeeded()
        #expect(rig.split.frame == rig.host.bounds)
        #expect(rig.frames == [NSRect(x: 0, y: 0, width: 500, height: 93), NSRect(x: 0, y: 103, width: 500, height: 93),
                               NSRect(x: 0, y: 206, width: 500, height: 93)])
    }

    @Test func growingTheHostRestoresRatioGeometryOnTheSameNativePanes() {
        let rig = Rig()
        rig.host.frame.size = NSSize(width: 1200, height: 900)
        rig.host.layoutSubtreeIfNeeded()
        let roomy = rig.frames
        rig.split.configure(orientation: .vertical, factors: [1, 2, 3])
        rig.host.frame.size = NSSize(width: 500, height: 300)
        rig.host.layoutSubtreeIfNeeded()
        rig.host.frame.size = NSSize(width: 1200, height: 900)
        rig.host.layoutSubtreeIfNeeded()
        rig.split.configure(orientation: .horizontal, factors: [1, 2, 3])
        #expect(rig.frames == roomy)
        #expect(zip(rig.split.arrangedSubviews, rig.panes).allSatisfy { $0 === $1 })
    }

    @Test func aHostResizeCancelsTheCapturedDividerWithoutPublishingPreviewRatios() {
        let rig = Rig()
        rig.host.frame.size = NSSize(width: 1200, height: 900)
        rig.host.layoutSubtreeIfNeeded()
        let origin = NSPoint(x: rig.panes[0].frame.maxX + 5, y: 200)
        #expect(rig.split.beginDividerResize(at: origin))
        rig.split.updateDividerResize(at: NSPoint(x: origin.x + 40, y: 200), velocity: 200)
        rig.host.frame.size.width = 900
        rig.host.layoutSubtreeIfNeeded()
        rig.split.finishDividerResize(commit: true)
        #expect(rig.commits == 0)
        #expect(rig.split.frame.width == 900)
    }

    @Test func oneRemainingPaneRestoresSinglePageSizingWithoutSplitMinima() {
        let rig = Rig()
        rig.panes.dropFirst().forEach { $0.removeFromSuperview() }
        rig.host.frame.size = NSSize(width: 180, height: 140)
        rig.split.configure(orientation: .horizontal, factors: [1])
        rig.host.layoutSubtreeIfNeeded()
        #expect(rig.split.frame == rig.host.bounds)
        #expect(rig.panes[0].frame == rig.split.bounds)
    }

    @Test func detachmentRetiresTheExactParentConstraintLease() {
        let rig = Rig()
        let constraints = (rig.host.constraints + rig.split.constraints).filter {
            ($0.firstItem as? NSView) === rig.split || ($0.secondItem as? NSView) === rig.split
        }
        rig.split.removeFromSuperview()
        #expect(constraints.allSatisfy { !$0.isActive })
    }
}

@MainActor
struct SplitDividerAccessibilityTests {
    @MainActor private final class Rig {
        let window = SplitScaleWindow.make(width: 1000, height: 800)
        let split = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        let panes = [NSView(), NSView(), NSView()]
        var prepared = 0
        var commits: [[Double]] = []

        init() {
            window.contentView!.addSubview(split)
            for pane in panes {
                pane.setAccessibilityElement(true)
                pane.setAccessibilityRole(.group)
                split.addArrangedSubview(pane)
            }
            split.configure(orientation: .horizontal, factors: [1, 1, 1])
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var splitters: [ParcSplitView.DividerAccessibilityElement] {
            (split.accessibilitySplitters() ?? []).compactMap { $0 as? ParcSplitView.DividerAccessibilityElement }
        }

        var shares: [Double] {
            let lengths = panes.map { Double($0.frame.width) }
            return lengths.map { $0 / lengths.reduce(0, +) }
        }

        func commitOwner(accepting: Bool = true) {
            split.prepareDividerResize = { [weak self] in
                self?.prepared += 1
                return { self?.commits.append($0); return accepting }
            }
        }

        func percent(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? -1 }
    }

    @Test func theContainerStaysIgnoredAndVoiceOverWalksEachPaneWithASplitterBetweenNeighbours() {
        let rig = Rig()
        let children = NSAccessibility.unignoredChildren(from: [rig.split]).map { $0 as AnyObject }
        let splitters = rig.splitters
        #expect(!rig.split.isAccessibilityElement())
        #expect(rig.split.accessibilityRole() != .splitGroup)
        #expect(splitters.count == 2 && children.count == 5)
        #expect(children[0] === rig.panes[0] && children[1] === splitters[0] && children[2] === rig.panes[1])
        #expect(children[3] === splitters[1] && children[4] === rig.panes[2])
    }

    @Test func eachDividerIsALabelledVerticalSplitter() {
        let splitters = Rig().splitters
        #expect(splitters.allSatisfy { $0.isAccessibilityElement() && $0.accessibilityRole() == .splitter && $0.accessibilityOrientation() == .vertical })
        #expect(splitters[0].accessibilityLabel() == "Split View Divider 1")
        #expect(splitters[1].accessibilityLabel() == "Split View Divider 2")
    }

    @Test func aSplitterReportsItsPositionAsItsShareOfTheSplit() {
        let rig = Rig()
        let shares = rig.shares, splitters = rig.splitters
        #expect(rig.percent(splitters[0].accessibilityValue()) == (shares[0] * 100).rounded())
        #expect(rig.percent(splitters[1].accessibilityValue()) == ((shares[0] + shares[1]) * 100).rounded())
        #expect(rig.percent(splitters[0].accessibilityValue()) == 33 && rig.percent(splitters[1].accessibilityValue()) == 67)
        #expect(splitters[0].accessibilityValueDescription() == (1.0 / 3).formatted(.percent.precision(.fractionLength(0))))
    }

    @Test func splitterLimitsKeepBothNeighboursAtTheMinimum() {
        let rig = Rig()
        let shares = rig.shares, splitters = rig.splitters
        let minimum = 220 / rig.panes.map { Double($0.frame.width) }.reduce(0, +)
        #expect(rig.percent(splitters[0].accessibilityMinValue()) == (minimum * 100).rounded())
        #expect(rig.percent(splitters[0].accessibilityMaxValue()) == ((shares[0] + shares[1] - minimum) * 100).rounded())
        #expect(rig.percent(splitters[1].accessibilityMinValue()) == ((shares[0] + minimum) * 100).rounded())
        #expect(rig.percent(splitters[1].accessibilityMaxValue()) == ((1 - minimum) * 100).rounded())
    }

    @Test func aSplitterCoversItsRealDividerBelongsToTheSplitsParentAndIsFoundByHitTesting() {
        let rig = Rig()
        let splitter = rig.splitters[0]
        let screen = rig.window.convertToScreen(rig.split.convert(NSRect(x: rig.panes[0].frame.maxX, y: 0, width: 10, height: 500), to: nil))
        #expect(splitter.accessibilityFrame() == screen)
        #expect((splitter.accessibilityParent() as AnyObject?) === (NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?))
        #expect((rig.split.accessibilityHitTest(NSPoint(x: screen.midX, y: screen.midY)) as AnyObject?) === splitter)
    }

    @Test func voiceOverAdjustsBySteppingNotByTypingAValue() {
        let splitter = Rig().splitters[0]
        #expect(!splitter.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.setAccessibilityValue(_:))))
        #expect(splitter.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformIncrement)))
        #expect(splitter.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityPerformDecrement)))
    }

    @Test func withoutAWindowOwnerToCommitAnIncrementChangesNothing() {
        let rig = Rig()
        let frames = rig.panes.map(\.frame)
        #expect(!rig.splitters[0].accessibilityPerformIncrement())
        #expect(rig.panes.map(\.frame) == frames)
    }

    @Test func anIncrementFromEvenNeighboursMovesExactlyOneStepThroughTheDragsCommit() {
        let rig = Rig()
        rig.commitOwner()
        #expect(rig.splitters[0].accessibilityPerformIncrement())
        #expect(rig.prepared == 1 && rig.commits.count == 1)
        #expect(near([rig.commits[0][0] - rig.commits[0][1]], [2 * SplitPaneResize.step]))
        #expect(near([rig.commits[0][2]], [1.0 / 3]))
    }

    @Test func theAcceptedStepLaysTheLeadingPaneWiderAndRaisesTheValue() {
        let rig = Rig()
        let frames = rig.panes.map(\.frame)
        rig.commitOwner()
        _ = rig.splitters[0].accessibilityPerformIncrement()
        #expect(rig.panes[0].frame.width > frames[0].width)
        #expect(rig.panes[2].frame.width == frames[2].width)
        #expect(rig.percent(rig.splitters[0].accessibilityValue()) > 33)
    }

    @Test func aDecrementThatCrossesTheEvenPointStopsThere() {
        let rig = Rig()
        let frames = rig.panes.map(\.frame)
        rig.commitOwner()
        _ = rig.splitters[0].accessibilityPerformIncrement()
        #expect(rig.splitters[0].accessibilityPerformDecrement())
        #expect(rig.commits.count == 2)
        #expect(abs(rig.panes[0].frame.width - rig.panes[1].frame.width) <= 1)
        #expect(rig.panes[2].frame.width == frames[2].width)
    }

    @Test func incrementsStopAtTheMinimumAndThenRefuse() {
        let rig = Rig()
        rig.commitOwner()
        for _ in 0..<5 { _ = rig.splitters[1].accessibilityPerformIncrement() }
        #expect(rig.panes[2].frame.width == 220)
        #expect(!rig.splitters[1].accessibilityPerformIncrement())
    }

    @Test func aRefusedCommitRestoresTheAuthoritativeLayout() {
        let rig = Rig()
        rig.commitOwner()
        for _ in 0..<5 { _ = rig.splitters[1].accessibilityPerformIncrement() }
        let frames = rig.panes.map(\.frame), commits = rig.commits.count
        rig.commitOwner(accepting: false)
        #expect(!rig.splitters[1].accessibilityPerformDecrement())
        #expect(rig.panes.map(\.frame) == frames)
        #expect(rig.commits.count == commits + 1)
    }

    @Test func availabilityAsksTheSameStepMath() {
        let rig = Rig()
        rig.commitOwner()
        for _ in 0..<5 { _ = rig.splitters[1].accessibilityPerformIncrement() }
        #expect(rig.split.canResizePane(rig.panes[0], growing: true))
        #expect(rig.split.canEqualizePanes)
        #expect(!rig.split.canResizePane(rig.panes[2], growing: false))
        #expect(!rig.split.canResizePane(NSView(), growing: true))
    }

    @Test func aLiveMouseDragRefusesVoiceOverAndCommandAdjustments() {
        let rig = Rig()
        rig.commitOwner()
        #expect(rig.split.beginDividerResize(at: NSPoint(x: rig.panes[0].frame.maxX + 5, y: 300)))
        #expect(!rig.splitters[0].accessibilityPerformIncrement())
        #expect(!rig.split.resizePane(rig.panes[0], growing: true))
        #expect(!rig.split.equalizePanes())
        #expect(!rig.split.canResizePane(rig.panes[0], growing: true))
        #expect(!rig.split.canEqualizePanes)
        rig.split.finishDividerResize(commit: false)
    }

    @Test func stackedPanesReportHorizontalSplitters() {
        let rig = Rig()
        rig.split.configure(orientation: .vertical, factors: [1, 1, 1])
        #expect(rig.splitters.allSatisfy { $0.accessibilityOrientation() == .horizontal })
    }

    @Test func aDepartedPanesSplitterStopsReportingBeforeVoiceOverAsksAgain() {
        let rig = Rig()
        rig.commitOwner()
        let splitters = rig.splitters
        rig.panes[2].removeFromSuperview()
        #expect(!splitters[1].isAccessibilityElement())
        #expect(splitters[1].accessibilityValue() == nil)
        #expect(!splitters[1].accessibilityPerformIncrement())
    }

    @Test func removingAPaneRetiresItsSplitterAndKeepsTheSurvivor() {
        let rig = Rig()
        let splitters = rig.splitters
        rig.panes[2].removeFromSuperview()
        let survivor = rig.splitters
        #expect(survivor.count == 1)
        #expect(survivor[0] === splitters[0])
        #expect(survivor[0].accessibilityLabel() == "Split View Divider")
    }

    @Test func aSinglePageHasNoSplitterAndTheResizeCommandsAreUnavailable() {
        let rig = Rig()
        rig.panes[2].removeFromSuperview()
        rig.panes[1].removeFromSuperview()
        rig.commitOwner()
        #expect((rig.split.accessibilitySplitters() ?? []).isEmpty)
        #expect(NSAccessibility.unignoredChildren(from: [rig.split]).count == 1)
        #expect(!rig.split.resizePane(rig.panes[0], growing: true))
        #expect(!rig.split.resizePane(rig.panes[0], growing: false))
        #expect(!rig.split.equalizePanes())
        #expect(rig.prepared == 0)
    }
}

@MainActor
struct SplitDividerBackingTests {
    @MainActor private final class Rig {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let split: ParcSplitView
        let opaque = NSView(), translucent = NSView()

        init() {
            _ = NSApplication.shared
            host.wantsLayer = true
            host.layer?.cornerRadius = 7
            split = ParcSplitView(frame: host.bounds)
            host.addSubview(split)
            opaque.wantsLayer = true
            opaque.layer?.backgroundColor = NSColor.white.cgColor
            translucent.wantsLayer = true
            translucent.layer?.backgroundColor = NSColor.clear.cgColor
            split.addArrangedSubview(opaque)
            split.addArrangedSubview(translucent)
            split.configure(orientation: .horizontal, factors: [1, 1])
            split.configureBacking(in: host, hasTranslucentPane: true)
        }
    }

    @Test func theContainerExposesTheParentBackingInsteadOfAFixedSeparatorSurface() {
        let rig = Rig()
        #expect(!rig.split.isOpaque)
        #expect(rig.split.dividerColor.alphaComponent == 0)
        #expect(rig.split.layer?.backgroundColor == nil)
        #expect(rig.split.layer?.masksToBounds == false)
    }

    @Test func theHostRevealsItsOriginalSurroundingWindowSurface() {
        let rig = Rig()
        #expect(rig.host.layer?.backgroundColor?.alpha == 0)
        #expect(rig.host.layer?.masksToBounds == false)
    }

    @Test func eachPaneOwnsContinuousRoundedClipping() {
        let rig = Rig()
        #expect(rig.split.arrangedSubviews.allSatisfy {
            $0.layer?.cornerRadius == 6 && $0.layer?.cornerCurve == .continuous && $0.layer?.masksToBounds == true
        })
    }

    @Test func perPaneBackingsRemainUnchanged() {
        let rig = Rig()
        #expect(rig.opaque.layer?.backgroundColor?.alpha == 1)
        #expect(rig.translucent.layer?.backgroundColor?.alpha == 0)
    }

    @Test func backingUpdatesPreservePaneIdentityParentAndGeometry() {
        let rig = Rig()
        let frames = rig.split.arrangedSubviews.map(\.frame)
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: true)
        #expect(rig.split.arrangedSubviews[0] === rig.opaque && rig.split.arrangedSubviews[1] === rig.translucent)
        #expect(rig.split.arrangedSubviews.map(\.frame) == frames)
    }

    @Test func drawingTheDividerLeavesTheExistingParentPixelsIntact() throws {
        let rig = Rig()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 12, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.magenta.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 12).fill()
        rig.split.drawDivider(in: NSRect(x: 0, y: 0, width: 12, height: 12))
        NSGraphicsContext.restoreGraphicsState()
        let pixel = try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent > 0.99 && pixel.greenComponent < 0.01 && pixel.blueComponent > 0.99 && pixel.alphaComponent > 0.99)
    }

    @Test func returningToASingleNoteRestoresItsTransparentHostPolicy() {
        let rig = Rig()
        rig.opaque.removeFromSuperview()
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: true)
        #expect(rig.host.layer?.backgroundColor?.alpha == 0)
        #expect(rig.host.layer?.masksToBounds == true)
        #expect(rig.translucent.layer?.cornerRadius == 0)
        #expect(rig.translucent.layer?.masksToBounds == false)
    }

    @Test func returningToOneOrdinaryPageRestoresItsOpaqueRoundedHost() {
        let rig = Rig()
        rig.opaque.removeFromSuperview()
        rig.split.configureBacking(in: rig.host, hasTranslucentPane: false)
        #expect(rig.host.layer?.backgroundColor == NSColor.white.cgColor)
        #expect(rig.host.layer?.cornerRadius == 7)
    }
}

@MainActor
struct SplitDividerGeometryTests {
    private static func integralEdges(_ rect: NSRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy { $0 == $0.rounded() }
    }

    private static func detached() -> SplitRig {
        SplitRig(factors: [0.01, 0.49, 0.5], frame: NSRect(x: 0, y: 0, width: 1201, height: 901), attached: false)
    }

    @Test func theBrowsersContentInsetSuppliesTenPointDividers() {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        #expect(rig.view.dividerThickness == 10)
    }

    @Test func expandedHorizontalPanesEnforceTheRecoveredMinimum() {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        #expect(rig.panes.allSatisfy { $0.frame.width >= 220 })
    }

    @Test func fractionalSharesClampAndAlignThePaneEdges() {
        let rig = Self.detached()
        #expect(rig.panes[0].frame.width == 220)
        #expect(rig.frames.allSatisfy(Self.integralEdges))
    }

    @Test func roundedEdgesPreserveExactGapsAndFillTheViewport() {
        let rig = Self.detached()
        #expect(zip(rig.panes, rig.panes.dropFirst()).allSatisfy { $1.frame.minX - $0.frame.maxX == 10 })
        #expect(rig.panes.last?.frame.maxX == rig.view.bounds.maxX)
    }

    @Test func aMinimumClampedLiveMutationRerendersAllPanesKeepingTheThirdSourceFactor() {
        let rig = Self.detached()
        let origin = NSPoint(x: rig.panes[0].frame.maxX + 5, y: 200)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: -900, y: 200), velocity: -200)
        #expect(rig.panes[0].frame.width == 220)
        #expect(rig.panes[2].frame.width == 591)
        #expect(rig.commits.isEmpty)
    }

    @Test func verticalExpandedPanesUseTheSameMinimumAndAlignedEdges() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        #expect(rig.panes[0].frame.height == 220)
        #expect(rig.frames.allSatisfy(Self.integralEdges))
    }

    @Test func verticalLayoutPreservesExactGapsAndTheViewportExtent() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        #expect(zip(rig.panes, rig.panes.dropFirst()).allSatisfy { $1.frame.minY - $0.frame.maxY == 10 })
        #expect(rig.panes.last?.frame.maxY == rig.view.bounds.maxY)
    }

    @Test func panesShortOfRoomInAnUndersizedViewportShareItsHeightEvenly() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        rig.view.frame.size.height = 400
        rig.view.adjustSubviews()
        #expect(rig.heights == [126, 126, 126])
        #expect(rig.frames.allSatisfy(Self.integralEdges))
        #expect(rig.panes.map { $0.frame.minY } == [0, 136, 272])
        #expect(rig.panes.last!.frame.maxY <= rig.view.bounds.maxY)
    }

    @Test func aRestoredViewportRecoversSourceRatiosWithoutRewritingTheDurableLayout() {
        let rig = Self.detached()
        rig.view.configure(orientation: .vertical, factors: [0.01, 0.49, 0.5])
        rig.view.frame.size.height = 400
        rig.view.adjustSubviews()
        rig.view.frame.size.height = 901
        rig.view.adjustSubviews()
        #expect(rig.panes[0].frame.height == 220)
        #expect(rig.commits.isEmpty)
    }
}

@MainActor
struct SplitDividerHoverTests {
    @MainActor private final class Rig {
        let rig = SplitRig(count: 4, factors: [1, 2, 3, 4], frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
        var view: ParcSplitView { rig.view }

        init() {
            view.appearance = NSAppearance(named: .aqua)
            view.viewDidChangeEffectiveAppearance()
        }

        func grips() -> [CALayer] { (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" } }
        func ink(_ layer: CALayer) -> NSColor? { layer.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.sRGB) }
        func alpha(_ layer: CALayer) -> CGFloat { ink(layer)?.alphaComponent ?? -1 }
        var first: CALayer { grips()[0] }
        var hoverPoint: NSPoint { NSPoint(x: first.frame.midX, y: first.frame.midY) }
        var topGap: NSPoint { NSPoint(x: hoverPoint.x, y: 52) }
        var regionTop: NSPoint { NSPoint(x: hoverPoint.x, y: 53) }
        var windowPoint: NSPoint { view.convert(hoverPoint, to: nil) }
        var window: NSWindow { rig.window }
    }

    @Test func gripLayersDoNotBecomePanesOrChangeTheChildList() {
        let rig = Rig()
        #expect(rig.grips().count == 3)
        #expect(rig.view.arrangedSubviews.count == 4)
    }

    @Test func aHorizontalGripHasTheRecoveredSizeAndRadius() {
        let rig = Rig()
        #expect(rig.first.frame.size == NSSize(width: 2, height: 24))
        #expect(rig.first.cornerRadius == 1)
    }

    @Test func theGripCentersOnTheDividersActualFrame() {
        let rig = Rig()
        #expect(rig.first.frame.midX == rig.view.arrangedSubviews[0].frame.maxX + rig.view.dividerThickness / 2)
        #expect(rig.first.frame.midY == rig.view.bounds.midY)
    }

    @Test func lightAppearanceResolvesIdleDragHintBlackAtTwentyPercent() {
        let rig = Rig()
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
        #expect(rig.ink(rig.first)?.redComponent == 0)
    }

    @Test func aPointedDividerHighlightsItsVisibleGrip() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint, animated: false)
        #expect(rig.grips().allSatisfy { !$0.isHidden })
        #expect(rig.alpha(rig.first) == 0.5)
    }

    @Test func hoverChangesOnlyGripInkNeverItsGeometryOrVisibility() {
        let rig = Rig()
        let frames = rig.grips().map(\.frame)
        rig.view.updateDividerHover(at: rig.hoverPoint, animated: false)
        rig.view.updateDividerHover(at: nil, animated: false)
        #expect(rig.grips().allSatisfy { !$0.isHidden })
        #expect(rig.grips().map(\.frame) == frames)
    }

    @Test func theTopFiftyThreePointsOfADividerAreOutsideItsHoverRegion() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.topGap, animated: false)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func theHoverRegionStartsFiftyThreePointsBelowTheDividerTop() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.regionTop, animated: false)
        #expect(rig.alpha(rig.first) == 0.5)
    }

    @Test func panAdmissionUsesTheSameDraggableRegion() {
        let rig = Rig()
        rig.view.prepareDividerResize = { { _ in false } }
        #expect(!rig.view.beginDividerResize(at: rig.topGap))
        #expect(rig.view.beginDividerResize(at: rig.regionTop))
        rig.view.finishDividerResize(commit: false)
    }

    @Test func trackingAreasCoverEachDraggableRegionWithTheOriginalOptions() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.count == 3)
        #expect(rig.view.trackingAreas.allSatisfy {
            $0.rect.minY == 53 && $0.rect.maxY == rig.view.bounds.maxY && $0.rect.width == rig.view.dividerThickness
                && $0.options.contains(.enabledDuringMouseDrag) && $0.options.contains(.activeInKeyWindow)
        })
    }

    @Test func anUncoveredDividerSetsItsResizePointerThroughCursorUpdates() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.allSatisfy { $0.options.contains(.cursorUpdate) })
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) != nil)
    }

    @Test func aCommandSurfaceOverTheDividerKeepsTheResizePointerOffIt() {
        let rig = Rig()
        let cover = NSView(frame: rig.window.contentView!.convert(
            NSRect(x: rig.hoverPoint.x - 20, y: rig.hoverPoint.y - 20, width: 40, height: 40), from: rig.view))
        rig.window.contentView!.addSubview(cover)
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) == nil)
    }

    @Test func aSeeThroughOverlayLeavesTheDividersResizePointerAlone() {
        let rig = Rig()
        let glass = SeeThroughView(frame: rig.window.contentView!.convert(
            NSRect(x: rig.hoverPoint.x - 20, y: rig.hoverPoint.y - 20, width: 40, height: 40), from: rig.view))
        rig.window.contentView!.addSubview(glass)
        #expect(rig.view.dividerCursor(atWindowPoint: rig.windowPoint) != nil)
    }

    @Test func onlyTheExactPointedDividerReceivesHighlightedInk() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        #expect(rig.alpha(rig.first) == 0.5)
        #expect(abs(rig.alpha(rig.grips()[1]) - 0.2) < 0.000001)
    }

    @Test func hoverUsesTheRecoveredAnimationDurationWithNoReduceMotionGate() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        #expect(rig.first.animation(forKey: "Split grip hover")?.duration == 0.16)
    }

    @Test func immediateOwnerInvalidationClearsTheTransitionAndHover() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.updateDividerHover(at: nil, animated: false)
        #expect(rig.first.animation(forKey: "Split grip hover") == nil)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func anAppearanceChangePreservesHoverButResolvesHighlightedWhite() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.appearance = NSAppearance(named: .darkAqua)
        rig.view.viewDidChangeEffectiveAppearance()
        #expect(rig.ink(rig.first)?.redComponent == 1)
        #expect(rig.alpha(rig.first) == 0.5)
        #expect(rig.first.animationKeys()?.isEmpty != false)
    }

    @Test func aNonfinitePointerCannotRetainTheHighlightedDivider() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.updateDividerHover(at: NSPoint(x: CGFloat.nan, y: 10))
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func gripPresentationLeavesPaneInputOnItsExistingView() {
        let rig = Rig()
        rig.view.updateDividerHover(at: NSPoint(x: 10, y: 10), animated: false)
        #expect(rig.view.hitTest(NSPoint(x: 10, y: 10)) === rig.view.arrangedSubviews[0])
    }

    @Test func windowKeyLossImmediatelyRetiresHighlightedPresentation() {
        let rig = Rig()
        rig.view.updateDividerHover(at: rig.hoverPoint)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.window)
        #expect(rig.first.animationKeys()?.isEmpty != false)
        #expect(abs(rig.alpha(rig.first) - 0.2) < 0.000001)
    }

    @Test func trackingAreasContainOnlyRealVisibleDividerGeometry() {
        let rig = Rig()
        rig.view.updateTrackingAreas()
        #expect(rig.view.trackingAreas.allSatisfy { !$0.rect.isNull && !$0.rect.isEmpty && $0.rect.minX.isFinite && $0.rect.minY.isFinite })
    }

    @Test func detachingTheViewRevokesItsHoverPresentation() {
        let rig = Rig()
        let grip = rig.first
        rig.view.updateDividerHover(at: rig.hoverPoint)
        rig.view.removeFromSuperview()
        #expect(grip.animationKeys()?.isEmpty != false)
        #expect(abs(rig.alpha(grip) - 0.2) < 0.000001)
    }

    @Test func retiredPanesRemoveTheirGripAndTrackingOwners() {
        let rig = Rig()
        for pane in rig.view.arrangedSubviews {
            rig.view.removeArrangedSubview(pane)
            pane.removeFromSuperview()
        }
        rig.view.adjustSubviews()
        #expect(rig.grips().isEmpty)
        #expect(rig.view.trackingAreas.isEmpty)
    }
}

@MainActor
struct SplitStackedPanTests {
    private final class Activity { var values: [Bool] = [] }

    private static func rig() -> (rig: SplitRig, activity: Activity, point: NSPoint) {
        let rig = SplitRig(count: 2, orientation: .vertical, frame: NSRect(x: 0, y: 0, width: 900, height: 900))
        let activity = Activity()
        rig.view.onDividerPanActivity = { activity.values.append($0) }
        return (rig, activity, NSPoint(x: 450, y: rig.panes[0].frame.maxY + 5))
    }

    private static func paneHit(_ rig: SplitRig, _ y: CGFloat) -> Bool {
        rig.panes.contains { $0 === rig.view.hitTest(NSPoint(x: 450, y: y)) }
    }

    @Test func aStackedPaneDividerExcludesEightPointsAtEachEnd() {
        let (rig, _, _) = Self.rig()
        let y = rig.panes[0].frame.maxY + 5
        #expect(!rig.view.beginDividerResize(at: NSPoint(x: 7, y: y)))
        #expect(!rig.view.beginDividerResize(at: NSPoint(x: 893, y: y)))
        #expect(rig.view.beginDividerResize(at: NSPoint(x: 8, y: y)))
    }

    @Test func mouseDownAdmissionAloneSetsNoResizeReasonAndKeepsPaneInput() {
        let (rig, activity, point) = Self.rig()
        #expect(rig.view.beginDividerResize(at: point))
        #expect(activity.values.isEmpty)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }

    @Test func panBeganSetsTheReasonAndEveryPaneRefusesHitTesting() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        #expect(activity.values == [true])
        #expect(rig.view.isDividerPanActive)
        #expect(rig.view.hitTest(NSPoint(x: 450, y: 100)) === rig.view)
        #expect(rig.view.hitTest(NSPoint(x: 450, y: 800)) === rig.view)
    }

    @Test func anEndedPanClearsTheReasonAndRestoresPaneInput() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.updateDividerResize(at: NSPoint(x: 450, y: point.y + 30), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(activity.values == [true, false])
        #expect(!rig.view.isDividerPanActive)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }

    @Test func anOwnerChangeThatCancelsTheCapturedPanAlsoClearsItsReason() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.configure(orientation: .vertical, factors: [2, 1])
        #expect(activity.values == [true, false])
        #expect(Self.paneHit(rig, 100))
    }

    @Test func laterRecognizerEventsAfterCancellationReportNothingFurther() {
        let (rig, activity, point) = Self.rig()
        rig.view.beginDividerResize(at: point)
        rig.view.beginDividerPan(at: point)
        rig.view.configure(orientation: .vertical, factors: [2, 1])
        rig.view.updateDividerResize(at: NSPoint(x: 450, y: point.y + 30), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(activity.values.count == 2)
    }

    @Test func doubleClickEqualizesOnlyInsideTheDraggableRegionAndNeverSetsTheDragReason() {
        let (rig, activity, point) = Self.rig()
        rig.doubleClick(at: NSPoint(x: 4, y: point.y))
        rig.doubleClick(at: NSPoint(x: 450, y: point.y))
        #expect(rig.commits.count == 1)
        #expect(activity.values.isEmpty)
    }

    @Test func detachmentMidPanClearsTheReasonAndThePaneLock() {
        let (rig, activity, point) = Self.rig()
        #expect(rig.view.beginDividerResize(at: point))
        rig.view.beginDividerPan(at: point)
        #expect(activity.values.last == true && rig.view.isDividerPanActive && !Self.paneHit(rig, 100))
        rig.view.removeFromSuperview()
        #expect(activity.values.last == false)
        #expect(!rig.view.isDividerPanActive)
        #expect(Self.paneHit(rig, 100) && Self.paneHit(rig, 800))
    }
}

@MainActor
struct SplitDividerEqualizeTests {
    @MainActor private final class Rig {
        let directory: URL
        let store: BrowserStore
        let ids: [UUID]
        let original: BrowserSplitLayout
        let originalState: BrowserState
        let window = SplitScaleWindow.make()
        let view: ParcSplitView
        var calls = 0

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-dividers-" + UUID().uuidString)
            let opened = try BrowserStore(directory: directory)
            store = opened
            ids = (0..<4).map { opened.open("https://\($0).invalid") }
            store.setSplit(ids)
            _ = store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 2, 3, 4])
            original = store.activeSplitLayout!
            originalState = store.state
            view = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1200))
            window.contentView!.addSubview(view)
            for _ in ids { view.addArrangedSubview(NSView()) }
            view.configure(orientation: .horizontal, factors: original.widthFactors)
            storeOwner()
        }

        deinit {
            let directory = directory
            MainActor.assumeIsolated { window.close() }
            try? FileManager.default.removeItem(at: directory)
        }

        func storeOwner() {
            view.prepareDividerResize = { [weak self] in
                guard let self else { return nil }
                let captured = store.activeSplitLayout!
                return { [weak self] factors in
                    guard let self else { return false }
                    calls += 1
                    return store.resizeSplit(expected: captured, widthFactors: factors)
                }
            }
        }

        func doubleClick(_ divider: Int) {
            let pane = view.arrangedSubviews[divider]
            let local = view.isVertical ? NSPoint(x: pane.frame.maxX + 3, y: 200) : NSPoint(x: 200, y: pane.frame.maxY + 3)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
            view.mouseDown(with: event)
        }

        func grips() -> [CALayer] { (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" } }

        func layoutAnimations() -> [CAAnimationGroup] {
            (view.arrangedSubviews.compactMap(\.layer) + grips()).compactMap { $0.animation(forKey: "Split divider equalization") as? CAAnimationGroup }
        }

        func goVertical() {
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2, 3, 4])
            view.configure(orientation: .vertical, factors: store.activeSplitLayout!.widthFactors)
        }
    }

    @Test func anAcceptedDoubleClickUsesTheRecoveredDurationAndEaseOutCurve() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let animation = rig.layoutAnimations().first
        #expect(animation?.duration == 0.2)
        #expect(animation?.timingFunction == CAMediaTimingFunction(name: .easeOut))
    }

    @Test func theMotionTransformsOnlyLiveGeometry() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.layoutAnimations().first?.animations?.compactMap { ($0 as? CABasicAnimation)?.keyPath } == ["position", "bounds"])
    }

    @Test func keyLossRetiresOwnedMotionWithoutReversingAcceptedDurableState() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let durable = rig.store.activeSplitLayout
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.window)
        #expect(rig.layoutAnimations().isEmpty)
        #expect(rig.store.activeSplitLayout == durable)
    }

    @Test func aNativeDoubleClickEqualizesOnlyTheAdjacentPair() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.calls == 1)
        #expect(near(rig.store.activeSplitLayout!.widthFactors, [0.1, 0.25, 0.25, 0.4]))
    }

    @Test func nativeEqualizationDiffersByAtMostOneRoundedPoint() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(abs(rig.view.arrangedSubviews[1].frame.width - rig.view.arrangedSubviews[2].frame.width) <= 1)
    }

    @Test func aGeometryOperationLeavesPageRecordsAndSelectionUntouched() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
        #expect(rig.store.state.tabs == rig.originalState.tabs)
    }

    @Test func theOriginalGroupAndAnchorIdentityAreRetained() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let changed = rig.store.activeSplitLayout!
        #expect(changed.id == rig.original.id)
        #expect(changed.sidebarAnchorID == rig.original.sidebarAnchorID)
        #expect(changed.tabIDs == rig.ids)
    }

    @Test func theExactLayoutIsDurableBeforePublication() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        let loaded = try BrowserStore(directory: rig.directory)
        #expect(loaded.activeSplitLayout == rig.store.activeSplitLayout)
    }

    @Test func aStaleOriginalRatioReceiptCannotRetarget() throws {
        let rig = try Rig()
        rig.doubleClick(1)
        #expect(!rig.store.resizeSplit(expected: rig.original, widthFactors: [1, 1, 1, 1]))
    }

    @Test func anUnavailableNativeOwnerLeavesTheDividerUnchanged() throws {
        let rig = try Rig()
        let frames = rig.view.arrangedSubviews.map(\.frame)
        let layout = rig.store.activeSplitLayout
        rig.view.prepareDividerResize = { nil }
        rig.doubleClick(2)
        #expect(rig.view.arrangedSubviews.map(\.frame) == frames)
        #expect(rig.store.activeSplitLayout == layout)
    }

    @Test func aRefusedCompletionRestoresTheOriginalGeometryAndNeverStartsMotion() throws {
        let rig = try Rig()
        let frames = rig.view.arrangedSubviews.map(\.frame)
        rig.view.prepareDividerResize = { { _ in false } }
        rig.doubleClick(2)
        #expect(rig.view.arrangedSubviews.map(\.frame) == frames)
        #expect(rig.layoutAnimations().isEmpty)
    }

    @Test func aSynchronousOrientationChangeCannotAnimateOrOverwriteTheNewLayout() throws {
        let rig = try Rig()
        rig.view.prepareDividerResize = { [weak rig] in { _ in
            rig?.view.configure(orientation: .vertical, factors: [1, 1, 1, 1]); return true
        } }
        rig.doubleClick(2)
        #expect(!rig.view.isVertical)
        #expect(rig.layoutAnimations().isEmpty)
    }

    @Test func aVerticalLayoutKeepsAHorizontalGripOnEachActualDivider() throws {
        let rig = try Rig()
        rig.goVertical()
        #expect(rig.grips().allSatisfy { $0.frame.size == NSSize(width: 24, height: 2) })
    }

    @Test func theVerticalGripUsesCurrentDividerAndViewportCoordinates() throws {
        let rig = try Rig()
        rig.goVertical()
        #expect(rig.grips()[0].frame.midY == rig.view.arrangedSubviews[0].frame.maxY + rig.view.dividerThickness / 2)
        #expect(rig.grips()[0].frame.midX == rig.view.bounds.midX)
    }

    @Test func aVerticalPairOperationPreservesTheOtherPanesShares() throws {
        let rig = try Rig()
        rig.goVertical()
        rig.doubleClick(0)
        #expect(near(rig.store.activeSplitLayout!.widthFactors, [0.15, 0.15, 0.3, 0.4]))
    }

    @Test func nativeVerticalFramesEqualizeAdjacentHeights() throws {
        let rig = try Rig()
        rig.goVertical()
        rig.doubleClick(0)
        #expect(abs(rig.view.arrangedSubviews[0].frame.height - rig.view.arrangedSubviews[1].frame.height) <= 1)
    }

    private func failDisk(_ rig: Rig) throws {
        try rig.store.save()
        try FileManager.default.removeItem(at: rig.directory)
        try Data().write(to: rig.directory)
    }

    private func recoverDisk(_ rig: Rig) throws {
        try FileManager.default.removeItem(at: rig.directory)
        try FileManager.default.createDirectory(at: rig.directory, withIntermediateDirectories: true)
    }

    @Test func aRealDiskFailureRefusesGeometryPublication() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!
        try failDisk(rig)
        #expect(!rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1]))
        try recoverDisk(rig)
    }

    @Test func aFailedSaveRetainsTheCompleteGroupAndSelection() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!, state = rig.store.state
        try failDisk(rig)
        _ = rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1])
        #expect(rig.store.state == state)
        #expect(rig.store.persistenceError != nil)
        try recoverDisk(rig)
    }

    @Test func theOriginalReceiptRetriesAfterStorageRecovers() throws {
        let rig = try Rig()
        let layout = rig.store.activeSplitLayout!
        try failDisk(rig)
        _ = rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1])
        try recoverDisk(rig)
        #expect(rig.store.resizeSplit(expected: layout, widthFactors: [1, 1, 1, 1]))
        #expect(rig.store.state.tabs == rig.originalState.tabs)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
    }

    @Test func invalidFactorsCannotCorruptTheOriginalGeometry() throws {
        let rig = try Rig()
        let current = rig.store.activeSplitLayout!, state = rig.store.state
        #expect(!rig.store.resizeSplit(expected: current, widthFactors: [0, 1, 1, 1]))
        #expect(rig.store.state == state)
    }

    @Test func aSelectionChangeDuringADividerOperationRefusesStaleCompletion() throws {
        let rig = try Rig()
        let current = rig.store.activeSplitLayout!
        _ = rig.store.open("https://different-selection.invalid")
        let selected = rig.store.state
        #expect(!rig.store.resizeSplit(expected: current, widthFactors: [1, 1, 1, 1]))
        #expect(rig.store.state == selected)
    }
}

@MainActor
struct SplitDividerExpandTests {
    @MainActor private final class Rig {
        let directory: URL
        let store: BrowserStore
        let ids: [UUID]
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let view = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        let panes: [NSView]

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-commands-" + UUID().uuidString)
            let opened = try BrowserStore(directory: directory)
            store = opened
            ids = (0..<3).map { opened.open("https://command-\($0).invalid") }
            store.setSplit(ids)
            _ = store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 1, 1])
            window.contentView!.addSubview(view)
            panes = ids.map { _ in NSView() }
            panes.forEach(view.addArrangedSubview)
            view.configure(orientation: .horizontal, factors: store.activeSplitLayout!.widthFactors)
        }

        deinit {
            let directory = directory
            MainActor.assumeIsolated { window.close() }
            try? FileManager.default.removeItem(at: directory)
        }

        var hasMotion: Bool {
            let layers = view.arrangedSubviews.compactMap(\.layer) + (view.layer?.sublayers ?? []).filter { $0.name == "Split divider grip" }
            return layers.contains { !($0.animationKeys() ?? []).isEmpty }
        }

        func expand() -> Bool {
            let grouped = store.activeSplitLayout!
            return store.resizeSplit(expected: grouped, widthFactors: grouped.expandedFactors(focusing: ids[1])!)
        }

        func expanded() throws -> Bool {
            let committed = expand()
            view.configure(orientation: .horizontal, factors: store.activeSplitLayout!.widthFactors)
            return committed
        }
    }

    @Test func expandRefusesAPaneOutsideTheOriginalGroup() throws {
        let rig = try Rig()
        #expect(rig.store.activeSplitLayout!.expandedFactors(focusing: UUID()) == nil)
    }

    @Test func expandCommitsThroughTheOriginalResizeEndTransaction() throws {
        let rig = try Rig()
        #expect(rig.expand())
    }

    @Test func expandKeepsEveryOriginalPaneDisplayedAndInOrder() throws {
        let rig = try Rig()
        _ = rig.expand()
        #expect(rig.store.activeSplitLayout!.tabIDs == rig.ids)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
    }

    @Test func expandedWeightsPersist() throws {
        let rig = try Rig()
        _ = rig.expand()
        #expect(try BrowserStore(directory: rig.directory).activeSplitLayout == rig.store.activeSplitLayout)
    }

    @Test func expandingTheAlreadyExpandedPaneComputesIdenticalWeights() throws {
        let rig = try Rig()
        _ = rig.expand()
        let layout = rig.store.activeSplitLayout!
        #expect(layout.expandedFactors(focusing: rig.ids[1]) == layout.widthFactors)
    }

    @Test func expandGivesTheFocusedPaneTheRestAndOthersTheExpandedMinimumImmediately() throws {
        let rig = try Rig()
        _ = try rig.expanded()
        #expect(rig.panes.map { $0.frame.width } == [220, 750, 220])
        #expect(!rig.hasMotion)
    }

    @Test func aZeroWeightStaysAtTheExpandedMinimumAtAnyWindowWidth() throws {
        let rig = try Rig()
        _ = try rig.expanded()
        rig.view.setFrameSize(NSSize(width: 1610, height: 800))
        #expect(rig.panes.map { $0.frame.width } == [220, 1150, 220])
    }

    @Test func convertingOrientationLaysOutImmediatelyWithTheSameWeights() throws {
        let rig = try Rig()
        _ = try rig.expanded()
        rig.view.configure(orientation: .vertical, factors: rig.store.activeSplitLayout!.widthFactors)
        #expect(rig.panes.map { $0.frame.height } == [220, 340, 220])
        #expect(!rig.hasMotion)
    }

    @Test func aSavedWeightChangeFromAnotherOwnerLaysOutImmediately() throws {
        let rig = try Rig()
        rig.view.configure(orientation: .vertical, factors: [1, 1, 1])
        let heights = rig.panes.map { $0.frame.height }
        #expect(heights.max()! - heights.min()! <= 1)
        #expect(!rig.hasMotion)
    }

    @Test func closingOrSeparatingAPaneLaysOutTheSurvivorsImmediately() throws {
        let rig = try Rig()
        rig.view.configure(orientation: .vertical, factors: [1, 1, 1])
        rig.view.removeArrangedSubview(rig.panes[0])
        rig.panes[0].removeFromSuperview()
        rig.view.configure(orientation: .vertical, factors: [1, 1])
        #expect(rig.panes[1].frame.minY == 0)
        #expect(rig.panes[2].frame.maxY == 800)
        #expect(!rig.hasMotion)
    }

    @Test func aOneChildSplitDissolvesIntoAFullSinglePaneImmediately() throws {
        let rig = try Rig()
        rig.view.removeArrangedSubview(rig.panes[0])
        rig.panes[0].removeFromSuperview()
        rig.view.removeArrangedSubview(rig.panes[2])
        rig.panes[2].removeFromSuperview()
        rig.view.configure(orientation: .vertical, factors: [1])
        #expect(rig.panes[1].frame == rig.view.bounds)
        #expect(!rig.hasMotion)
    }

    @Test func anAddSplitPendingPaneIsInsertedImmediately() throws {
        let rig = try Rig()
        for index in [0, 2] {
            rig.view.removeArrangedSubview(rig.panes[index])
            rig.panes[index].removeFromSuperview()
        }
        rig.view.configure(orientation: .vertical, factors: [1])
        let pending = NSView()
        rig.view.insertArrangedSubview(pending, at: 1)
        rig.view.configure(orientation: .horizontal, factors: [1, 1])
        #expect(pending.frame.minX == rig.panes[1].frame.maxX + 10)
        #expect(!rig.hasMotion)
    }

    @Test func cancellingThePendingPaneRestoresTheOriginalLayoutImmediately() throws {
        let rig = try Rig()
        for index in [0, 2] {
            rig.view.removeArrangedSubview(rig.panes[index])
            rig.panes[index].removeFromSuperview()
        }
        rig.view.configure(orientation: .vertical, factors: [1])
        let pending = NSView()
        rig.view.insertArrangedSubview(pending, at: 1)
        rig.view.configure(orientation: .horizontal, factors: [1, 1])
        rig.view.removeArrangedSubview(pending)
        pending.removeFromSuperview()
        rig.view.configure(orientation: .horizontal, factors: [1])
        #expect(rig.panes[1].frame == rig.view.bounds)
        #expect(!rig.hasMotion)
    }
}

@MainActor
struct SplitDegenerateDividerTests {
    private static func rig(scale: CGFloat, factors: [Double] = [0.75, 0.25, 1e-9]) -> SplitRig {
        SplitRig(factors: factors, frame: NSRect(x: 0, y: 0, width: 1210, height: 800), window: NSSize(width: 1610, height: 800), scale: scale)
    }

    @Test func minimumRedistributionDisplaysMoreThanThePairsSavedShare() {
        let rig = Self.rig(scale: 2)
        #expect(rig.widths[2] == 220)
        #expect(rig.widths[1] > 220 && rig.widths[1] < 0.25 * 1190)
    }

    @Test func itsDividerMovesOnlyTheTwoPanesDisplayedSpace() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == widths[1] - 10)
        #expect(rig.widths[2] == 230)
    }

    @Test func theDragCommitsValidWeightsAndKeepsTheOtherPanesSize() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.commits.count == 1)
        #expect(BrowserSplitLayout.normalized(rig.commits[0], count: 3) != nil)
        #expect(rig.widths[0] == widths[0])
    }

    @Test func doubleClickSplitsThePairsDisplayedSpaceAndLeavesTheOtherPaneAlone() {
        let rig = Self.rig(scale: 2)
        let widths = rig.widths
        rig.doubleClick(at: NSPoint(x: rig.panes[1].frame.maxX + 3, y: 200))
        #expect(rig.commits.count == 1)
        #expect(rig.widths[0] == widths[0])
        #expect(abs(rig.widths[1] - rig.widths[2]) <= 1)
    }

    @Test func atOneXIndependentlyRoundedLengthsOverrunTheAvailableLength() {
        let rig = Self.rig(scale: 1)
        #expect(rig.widths.reduce(0, +) > 1190)
    }

    @Test func atOneXThePairTakesTheRoundingRemainderAndTheOtherPaneKeepsItsSize() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == widths[1] - 10)
        #expect(rig.widths[2] == 229)
        #expect(rig.panes[2].frame.maxX == 1210)
    }

    @Test func theOneXCommitKeepsTheOtherPanesSize() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        let origin = rig.dividerOrigin(1)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x - 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.widths[0] == widths[0])
    }

    @Test func aOneXDoubleClickSplitsThePairEvenlyAndLeavesTheOtherPaneAlone() {
        let rig = Self.rig(scale: 1)
        let widths = rig.widths
        rig.doubleClick(at: NSPoint(x: rig.panes[1].frame.maxX + 3, y: 200))
        #expect(rig.widths[0] == widths[0])
        #expect(rig.widths[1] == rig.widths[2])
    }

    @Test func atOneXTheLeadingDegeneratePairOverrunsToo() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        #expect(rig.widths[0] == 220)
        #expect(rig.widths.reduce(0, +) > 1190)
    }

    @Test func atOneXTheFirstDividerMovesItsPairAndTheLastPaneKeepsItsSize() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        let widths = rig.widths
        let origin = rig.dividerOrigin(0)
        #expect(rig.view.beginDividerResize(at: origin))
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 10, y: 200), velocity: 200)
        #expect(rig.widths[0] == 230)
        #expect(rig.widths[2] == widths[2])
        #expect(rig.panes[2].frame.maxX == 1210)
    }

    @Test func theOneXLeadingCommitKeepsTheLastPanesSize() {
        let rig = Self.rig(scale: 1, factors: [1e-9, 0.25, 0.75])
        let widths = rig.widths
        let origin = rig.dividerOrigin(0)
        rig.view.beginDividerResize(at: origin)
        rig.view.updateDividerResize(at: NSPoint(x: origin.x + 10, y: 200), velocity: 200)
        rig.view.finishDividerResize(commit: true)
        #expect(rig.widths[2] == widths[2])
    }
}

@MainActor
struct SplitDividerReconcileTests {
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

@MainActor
struct SplitStackedSplitTests {
    @MainActor private final class Rig {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let split = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1010, height: 710))
        let panes: [NSView]
        var layout: BrowserSplitLayout
        var flatCommits = 0
        var changes: [SplitStackResize] = []

        init() {
            window.contentView!.addSubview(split)
            panes = (0..<3).map { _ in NSView() }
            for pane in panes {
                pane.setAccessibilityElement(true)
                pane.setAccessibilityRole(.group)
                split.addArrangedSubview(pane)
            }
            let start = BrowserSplitStacks(slotSizes: [2, 1], slotFactors: [0.5, 0.5], stackFactors: [[0.5, 0.5], [1]])
            layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: panes.map { _ in UUID() }, orientation: .horizontal,
                                        widthFactors: start.flattenedFactors, stacks: start)
            split.prepareDividerResize = { [weak self] in { _ in self?.flatCommits += 1; return true } }
            split.prepareStackedResize = { [weak self] in { change in
                guard let rig = self else { return nil }
                rig.changes.append(change)
                guard let next = rig.layout.resized(by: change) else { return nil }
                rig.layout = next
                return next.stacks
            } }
            apply()
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        let stackPoint = NSPoint(x: 250, y: 355)
        let mainPoint = NSPoint(x: 505, y: 300)

        func apply() { split.configure(orientation: layout.orientation, factors: layout.widthFactors, stacks: layout.stacks) }

        func dragStack(pan: Bool = false) {
            split.beginDividerResize(at: stackPoint)
            if pan { split.beginDividerPan(at: stackPoint) }
            split.updateDividerResize(at: NSPoint(x: 250, y: 405), velocity: 300)
            split.finishDividerResize(commit: true)
        }

        func dragMain() {
            split.beginDividerResize(at: mainPoint)
            split.updateDividerResize(at: NSPoint(x: 405, y: 300), velocity: -300)
            split.finishDividerResize(commit: true)
        }

        var splitters: [ParcSplitView.DividerAccessibilityElement] {
            (split.accessibilitySplitters() ?? []).compactMap { $0 as? ParcSplitView.DividerAccessibilityElement }
        }

        func percent(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? -1 }

        func rows() {
            let rows = BrowserSplitStacks(slotSizes: [1, 2], slotFactors: [0.5, 0.5], stackFactors: [[1], [0.5, 0.5]])
            layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: layout.tabIDs, orientation: .vertical,
                                        widthFactors: rows.flattenedFactors, stacks: rows)
            apply()
        }
    }

    @Test func aStackedSplitLaysItsColumnOutTopAndBottomBesideAFullHeightPane() {
        let rig = Rig()
        #expect(rig.panes.map(\.frame) == [NSRect(x: 0, y: 0, width: 500, height: 350), NSRect(x: 0, y: 360, width: 500, height: 350),
                                           NSRect(x: 510, y: 0, width: 500, height: 710)])
    }

    @Test func eachDividerShowsTheCursorForItsOwnDirection() {
        let rig = Rig()
        #expect(rig.split.dividerCursor(atWindowPoint: rig.split.convert(rig.stackPoint, to: nil)) == .resizeUpDown)
        #expect(rig.split.dividerCursor(atWindowPoint: rig.split.convert(rig.mainPoint, to: nil)) == .resizeLeftRight)
    }

    @Test func theStackDividerKeepsItsEndInsetAndTheMainDividerKeepsTheTopBarClear() {
        let rig = Rig()
        #expect(!rig.split.beginDividerResize(at: NSPoint(x: 4, y: 355)))
        #expect(!rig.split.beginDividerResize(at: NSPoint(x: 505, y: 20)))
    }

    @Test func aStackDividerAdmitsADragAndAPanLetsThePanesFallThrough() {
        let rig = Rig()
        #expect(rig.split.beginDividerResize(at: rig.stackPoint))
        rig.split.beginDividerPan(at: rig.stackPoint)
        #expect(rig.split.hitTest(NSPoint(x: 700, y: 300)) === rig.split)
    }

    @Test func draggingAStackDividerResizesOnlyTheTwoPanesInItsColumn() {
        let rig = Rig()
        rig.split.beginDividerResize(at: rig.stackPoint)
        rig.split.updateDividerResize(at: NSPoint(x: 250, y: 405), velocity: 300)
        #expect(rig.panes[0].frame.height == 400)
        #expect(rig.panes[1].frame == NSRect(x: 0, y: 410, width: 500, height: 300))
        #expect(rig.panes[2].frame == NSRect(x: 510, y: 0, width: 500, height: 710))
    }

    @Test func theStackDragCommitsOneStackedDividerEditAndNeverAFlatRow() {
        let rig = Rig()
        rig.dragStack()
        #expect(rig.changes.count == 1)
        #expect(isDivider(rig.changes.first, 0, slot: 0, share: 400.0 / 700))
        #expect(rig.flatCommits == 0)
        #expect(near(rig.layout.stacks!.stackFactors[0], [4.0 / 7, 3.0 / 7]))
        #expect(near(rig.layout.stacks!.slotFactors, [0.5, 0.5]))
    }

    @Test func draggingTheMainRowDividerMovesTheWholeColumn() {
        let rig = Rig()
        #expect(rig.split.beginDividerResize(at: rig.mainPoint))
        rig.split.updateDividerResize(at: NSPoint(x: 405, y: 300), velocity: -300)
        #expect(rig.panes[0].frame.width == 400 && rig.panes[1].frame.width == 400)
        #expect(rig.panes[2].frame.minX == 410)
    }

    @Test func theMainRowDragCommitsOnlyTheTwoSlots() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(isDivider(rig.changes.last, 0, slot: nil, share: 0.4))
        #expect(near(rig.layout.stacks!.slotFactors, [0.4, 0.6]))
    }

    @Test func voiceOverWalksThePanesInReadingOrderWithASplitterBetweenNeighbours() {
        let rig = Rig()
        let splitters = rig.splitters
        let children = NSAccessibility.unignoredChildren(from: [rig.split]).map { $0 as AnyObject }
        #expect(splitters.count == 2 && children.count == 5)
        #expect(children[0] === rig.panes[0] && children[1] === splitters[0] && children[2] === rig.panes[1])
        #expect(children[3] === splitters[1] && children[4] === rig.panes[2])
    }

    @Test func theStackSplitterSaysItSitsInsideTheFirstColumnAndRunsAcrossIt() {
        let splitters = Rig().splitters
        #expect(splitters[0].accessibilityLabel() == "Split View Divider 1, inside column 1")
        #expect(splitters[1].accessibilityLabel() == "Split View Divider 2")
        #expect(splitters[0].accessibilityOrientation() == .horizontal)
        #expect(splitters[1].accessibilityOrientation() == .vertical)
    }

    @Test func theStackSplitterReportsItsShareWithinItsColumnBoundedByTheMinimumOnEitherSide() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        let splitters = rig.splitters
        #expect(rig.percent(splitters[0].accessibilityValue()) == 57)
        #expect(rig.percent(splitters[0].accessibilityMinValue()) == 31)
        #expect(rig.percent(splitters[0].accessibilityMaxValue()) == 69)
        #expect(rig.percent(splitters[1].accessibilityValue()) == 40)
    }

    @Test func theStackSplitterCoversOnlyItsColumnsDividerOnScreen() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(rig.splitters[0].accessibilityFrame()
                == rig.window.convertToScreen(rig.split.convert(NSRect(x: 0, y: 400, width: 400, height: 10), to: nil)))
    }

    @Test func aDecrementStepsTheStackDividerWithinItsColumnAndStopsAtTheEvenPoint() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(rig.splitters[0].accessibilityPerformDecrement())
        #expect(isDivider(rig.changes.last, 0, slot: 0, share: 0.5))
        #expect(near(rig.layout.stacks!.stackFactors[0], [0.5, 0.5]))
    }

    @Test func makeAllEqualEvensBothLevelsAndThenHasNothingLeftToDo() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(rig.split.canEqualizePanes)
        #expect(rig.split.equalizePanes())
        #expect(rig.changes.last == .equal)
        #expect(rig.layout.stacks!.isEven)
        #expect(!rig.split.canEqualizePanes)
    }

    @Test func widenStepsTheFocusedPanesWholeSlotAlongTheMainRowOnly() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        _ = rig.split.equalizePanes()
        #expect(rig.split.canResizePane(rig.panes[1], growing: true))
        #expect(rig.split.resizePane(rig.panes[1], growing: true))
        #expect(near(rig.layout.stacks!.slotFactors, [0.6, 0.4]))
        #expect(rig.layout.stacks!.stackFactors == [[0.5, 0.5], [1]])
    }

    @Test func narrowStepsASlotBackAlongTheMainRow() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        _ = rig.split.equalizePanes()
        _ = rig.split.resizePane(rig.panes[1], growing: true)
        #expect(rig.split.resizePane(rig.panes[2], growing: false))
        #expect(near(rig.layout.stacks!.slotFactors, [0.7, 0.3]))
    }

    @Test func expandLeavesTheOtherPanesAtTheMinimumOnBothAxes() {
        let rig = Rig()
        rig.layout = rig.layout.expanded(focusing: rig.layout.tabIDs[1])!
        rig.apply()
        #expect(rig.panes[2].frame.width == 220)
        #expect(rig.panes[0].frame.height == 220)
        #expect(rig.panes[1].frame.height == 480)
    }

    @Test func aTopAndBottomSplitDividesItsLowerRowLeftAndRight() {
        let rig = Rig()
        rig.rows()
        #expect(rig.panes[1].frame == NSRect(x: 0, y: 360, width: 500, height: 350))
        #expect(rig.panes[2].frame.minX == 510)
    }

    @Test func aDividerBetweenTwoLowerPanesStaysClearOfTheirOwnHeaders() {
        let rig = Rig()
        rig.rows()
        #expect(!rig.split.beginDividerResize(at: NSPoint(x: 505, y: 380)))
        #expect(rig.split.beginDividerResize(at: NSPoint(x: 505, y: 500)))
        rig.split.finishDividerResize(commit: false)
    }

    @Test func aTopAndBottomSplitNamesTheRowItsSplitterSitsIn() {
        let rig = Rig()
        rig.rows()
        #expect(rig.splitters.count == 2)
        #expect(rig.splitters.last?.accessibilityLabel() == "Split View Divider 2, inside row 2")
    }

    @Test func aStackedSplitInATinyPageAreaSharesEachAxisInsteadOfSpilling() {
        let rig = Rig()
        rig.rows()
        let host = SplitConstraintHost(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        rig.window.contentView!.addSubview(host)
        rig.split.removeFromSuperview()
        host.addSubview(rig.split)
        rig.split.constrain(to: host)
        rig.apply()
        #expect(rig.split.frame == host.bounds)
        #expect(rig.panes.allSatisfy { host.bounds.contains($0.frame) })
        #expect(rig.panes[0].frame == NSRect(x: 0, y: 0, width: 300, height: 95))
        #expect(rig.panes[1].frame == NSRect(x: 0, y: 105, width: 145, height: 95))
        #expect(rig.panes[2].frame == NSRect(x: 155, y: 105, width: 145, height: 95))
    }
}

struct SplitPaneResizeStepsTests {
    private typealias Steps = SplitPaneResize

    @Test func aDividerStepMovesOneTenthOfTheSplit() {
        #expect(near(Steps.movingDivider(0, in: [0.5, 0.5], forward: true, minimum: 0.2)!, [0.6, 0.4]))
        #expect(near(Steps.movingDivider(0, in: [0.5, 0.5], forward: false, minimum: 0.2)!, [0.4, 0.6]))
    }

    @Test func aStepThatCrossesTheEvenPointStopsOnIt() {
        #expect(near(Steps.movingDivider(0, in: [0.45, 0.55], forward: true, minimum: 0.2)!, [0.5, 0.5]))
    }

    @Test func aStepThatStartsOnTheEvenPointMovesAWholeStep() {
        #expect(near(Steps.movingDivider(0, in: [0.505, 0.495], forward: true, minimum: 0.2)!, [0.6, 0.4]))
    }

    @Test func dividerStepsClampAtTheMinimum() {
        #expect(near(Steps.movingDivider(0, in: [0.75, 0.25], forward: true, minimum: 0.2)!, [0.8, 0.2]))
    }

    @Test func dividerStepsRefuseAtTheMinimumAndForImpossibleRequests() {
        #expect(Steps.movingDivider(0, in: [0.8, 0.2], forward: true, minimum: 0.2) == nil)
        #expect(Steps.movingDivider(2, in: [0.5, 0.5], forward: true, minimum: 0.2) == nil)
        #expect(Steps.movingDivider(0, in: [0.5, 0.5], forward: true, minimum: 0.6) == nil)
    }

    @Test func narrowingGivesTheFreedRoomToTheOtherPanesInProportion() {
        #expect(near(Steps.resizingPane(1, in: [0.2, 0.6, 0.2], growing: false, minimum: 0.2)!, [0.25, 0.5, 0.25]))
    }

    @Test func narrowingThatCrossesTheEqualShareStopsOnIt() {
        #expect(near(Steps.resizingPane(1, in: [0.3, 0.4, 0.3], growing: false, minimum: 0.2)!, [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @Test func wideningTakesRoomFromEachOtherPaneInProportionToItsRoomAboveTheMinimum() {
        #expect(near(Steps.resizingPane(0, in: [0.2, 0.3, 0.5], growing: true, minimum: 0.2)!, [0.3, 0.3 - 0.1 / 4, 0.5 - 0.3 / 4]))
    }

    @Test func paneStepsRefuseAtTheMinimumPastTheLastPaneAndOutsideASplit() {
        let expanded = [0.2, 0.6, 0.2]
        #expect(Steps.resizingPane(1, in: expanded, growing: true, minimum: 0.2) == nil)
        #expect(Steps.resizingPane(0, in: expanded, growing: false, minimum: 0.2) == nil)
        #expect(Steps.resizingPane(3, in: expanded, growing: true, minimum: 0.2) == nil)
        #expect(Steps.resizingPane(0, in: [1], growing: true, minimum: 0) == nil)
    }

    @Test func equalSharesExistOnlyForARealSplit() {
        #expect(near(Steps.equal(count: 4)!, [0.25, 0.25, 0.25, 0.25]))
        #expect(Steps.equal(count: 1) == nil)
        #expect(Steps.isEqual([2, 2, 2]))
        #expect(!Steps.isEqual([1, 2]))
        #expect(!Steps.isEqual([1]))
    }
}

@MainActor
struct SplitResizeCommandTests {
    @MainActor private final class Rig {
        let directory: URL
        let store: BrowserStore
        let ids: [UUID]
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let split = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        let panes: [NSView]
        var prepared = 0
        let expandedFactors: [Double]

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-steps-" + UUID().uuidString)
            let opened = try BrowserStore(directory: directory)
            store = opened
            ids = (0..<3).map { opened.open("https://step-\($0).invalid") }
            store.setSplit(ids)
            _ = store.setSplitLayout(orientation: .horizontal, widthFactors: [1, 1, 1])
            window.contentView!.addSubview(split)
            panes = ids.map { _ in NSView() }
            panes.forEach(split.addArrangedSubview)
            expandedFactors = store.activeSplitLayout!.expandedFactors(focusing: ids[1])!
            split.prepareDividerResize = { [weak self] in
                guard let self else { return nil }
                prepared += 1
                let captured = store.activeSplitLayout!
                return { [weak self] factors in
                    guard let self else { return false }
                    guard store.resizeSplit(expected: captured, widthFactors: factors) else { return false }
                    split.configure(orientation: .horizontal, factors: store.activeSplitLayout!.widthFactors)
                    return true
                }
            }
            split.configure(orientation: .horizontal, factors: store.activeSplitLayout!.widthFactors)
        }

        deinit {
            let directory = directory
            MainActor.assumeIsolated { window.close() }
            try? FileManager.default.removeItem(at: directory)
        }

        var widths: [CGFloat] { panes.map(\.frame.width) }

        func expand() {
            _ = store.resizeSplit(expected: store.activeSplitLayout!, widthFactors: expandedFactors)
            split.configure(orientation: .horizontal, factors: store.activeSplitLayout!.widthFactors)
        }

        func narrow(_ times: Int) {
            for _ in 0..<times { _ = split.resizePane(panes[1], growing: false) }
        }

        var spread: CGFloat { widths.max()! - widths.min()! }
    }

    @Test func expandLeavesTheOtherPanesAtTheirMinimum() throws {
        let rig = try Rig()
        rig.expand()
        #expect(rig.widths == [220, 750, 220])
    }

    @Test func afterExpandTheFocusedPaneCanOnlyNarrowAndMakeEqualIsOffered() throws {
        let rig = try Rig()
        rig.expand()
        #expect(!rig.split.canResizePane(rig.panes[1], growing: true))
        #expect(rig.split.canResizePane(rig.panes[1], growing: false))
        #expect(rig.split.canEqualizePanes)
    }

    @Test func wideningAnExpandedPaneHasNoRoomAndAsksTheWindowForNothing() throws {
        let rig = try Rig()
        rig.expand()
        #expect(!rig.split.resizePane(rig.panes[1], growing: true))
        #expect(rig.prepared == 0)
        #expect(rig.store.activeSplitLayout!.widthFactors == rig.expandedFactors)
    }

    @Test func narrowingTheFocusedPaneTakesOneStepAndSharesItEvenlyWithTheOthers() throws {
        let rig = try Rig()
        rig.expand()
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.prepared == 1)
        #expect(abs(rig.widths[0] - rig.widths[2]) <= 1)
        #expect(rig.widths[0] > 220 && rig.widths[1] < 750)
        #expect(abs(rig.widths[1] - (750 - 119)) <= 1)
    }

    @Test func theNarrowedLayoutIsSavedLikeAFinishedDragAndKeepsEveryPane() throws {
        let rig = try Rig()
        rig.expand()
        _ = rig.split.resizePane(rig.panes[1], growing: false)
        #expect(try BrowserStore(directory: rig.directory).activeSplitLayout == rig.store.activeSplitLayout)
        #expect(rig.store.state.selectedTabIDs == rig.ids)
    }

    @Test func narrowingInStepsLandsExactlyOnEqualPanes() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(2)
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.spread <= 1)
    }

    @Test func narrowingStopsAtTheMinimumThenRefuses() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(3)
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.widths[1] > 220)
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.widths[1] == 220)
        #expect(!rig.split.resizePane(rig.panes[1], growing: false))
    }

    @Test func wideningAnotherPaneLeavesAMinimumWidthPaneAlone() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(5)
        #expect(rig.split.resizePane(rig.panes[0], growing: true))
        #expect(rig.widths[0] > rig.widths[2])
        #expect(rig.widths[1] == 220)
    }

    @Test func makeEqualResetsEveryPaneThroughTheSameCommit() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(5)
        #expect(rig.split.equalizePanes())
        #expect(rig.spread <= 1)
        #expect(SplitPaneResize.isEqual(rig.store.activeSplitLayout!.widthFactors))
    }

    @Test func makeEqualOnAnAlreadyEvenSplitIsUnavailableAndDoesNothing() throws {
        let rig = try Rig()
        rig.expand()
        _ = rig.split.equalizePanes()
        let prepared = rig.prepared
        #expect(!rig.split.canEqualizePanes)
        #expect(!rig.split.equalizePanes())
        #expect(rig.prepared == prepared)
    }

    @Test func makeEqualUndoesExpandInOneStep() throws {
        let rig = try Rig()
        rig.expand()
        #expect(rig.split.equalizePanes())
        #expect(rig.spread <= 1)
    }

    @Test func theEqualLayoutAfterExpandIsSaved() throws {
        let rig = try Rig()
        rig.expand()
        _ = rig.split.equalizePanes()
        let saved = try BrowserStore(directory: rig.directory).activeSplitLayout
        #expect(saved.map { SplitPaneResize.isEqual($0.widthFactors) } == true)
    }

    @Test func aStaleWindowReceiptRefusesTheCommandAndKeepsTheAuthoritativeLayout() throws {
        let rig = try Rig()
        rig.split.configure(orientation: .vertical, factors: [3, 1, 1])
        let stale = rig.store.activeSplitLayout!
        let frames = rig.panes.map(\.frame)
        var commits = 0
        rig.split.prepareDividerResize = { { commits += 1; return rig.store.resizeSplit(expected: stale, widthFactors: $0) } }
        _ = rig.store.resizeSplit(expected: stale, widthFactors: [1, 2, 1])
        #expect(!rig.split.resizePane(rig.panes[0], growing: false))
        #expect(commits == 1)
        #expect(rig.panes.map(\.frame) == frames)
    }

    @Test func whenTheWindowCannotTakeAResizeTheCommandsChangeNothing() throws {
        let rig = try Rig()
        rig.split.configure(orientation: .vertical, factors: [3, 1, 1])
        let frames = rig.panes.map(\.frame)
        var receipts = 0
        rig.split.prepareDividerResize = { receipts += 1; return nil }
        #expect(!rig.split.resizePane(rig.panes[0], growing: false))
        #expect(!rig.split.equalizePanes())
        #expect(receipts == 2)
        #expect(rig.panes.map(\.frame) == frames)
    }
}

@MainActor
struct SplitDividerAnnouncementTests {
    private struct Post {
        let element: AnyObject
        let notification: NSAccessibility.Notification
        let elements: [AnyObject]
    }

    @MainActor private final class Rig {
        let window = SplitScaleWindow.make(width: 1610, height: 800)
        let split = ParcSplitView(frame: NSRect(x: 0, y: 0, width: 1210, height: 800))
        let panes = (0..<3).map { _ in NSView() }
        var posts: [Post] = []
        var settling: (@MainActor () -> Void)?

        init() {
            split.postAccessibilityNotification = { [weak self] element, notification, info in
                self?.posts.append(Post(element: element as AnyObject, notification: notification,
                                  elements: (info?[.uiElements] as? [Any] ?? []).map { $0 as AnyObject }))
            }
            split.scheduleDividerSettle = { [weak self] settle in
                self?.settling = settle
                return Timer(timeInterval: 3600, repeats: false) { _ in }
            }
            window.contentView!.addSubview(split)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func taken() -> [Post] { defer { posts = [] }; return posts }
        var splitters: [ParcSplitView.DividerAccessibilityElement] {
            (split.accessibilitySplitters() ?? []).compactMap { $0 as? ParcSplitView.DividerAccessibilityElement }
        }
        func value(_ index: Int) -> Double { (splitters[index].accessibilityValue() as? NSNumber)?.doubleValue ?? -1 }
        func changed(_ list: [Post]) -> [AnyObject] { list.filter { $0.notification == .valueChanged }.map(\.element) }
        func settle() { let pending = settling; settling = nil; pending?() }
        func dividerPoint(_ x: CGFloat = 0) -> NSPoint { NSPoint(x: panes[0].frame.maxX + 5 + x, y: 300) }
        func doubleClick() {
            split.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown,
                location: split.convert(NSPoint(x: panes[0].frame.maxX + 3, y: 300), to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!)
        }
        var windowCommit: () -> (([Double]) -> Bool)? {
            { [weak split] in
                { factors in
                    guard let split, let saved = BrowserSplitLayout.normalized(factors, count: factors.count) else { return false }
                    split.configure(orientation: .horizontal, factors: saved.map { $0 * 2 })
                    return true
                }
            }
        }

        func twoPanes() {
            _ = split.reconcileArrangedSubviews(Array(panes[..<2]))
            split.configure(orientation: .horizontal, factors: [1, 1])
        }

        func settled() {
            twoPanes()
            _ = taken()
            split.prepareDividerResize = windowCommit
        }

        func shrinkAfterExpand() {
            split.configure(orientation: .horizontal, factors: [980, 220])
            _ = taken()
            for width in [1160.0, 1110, 1060, 1010] { split.setFrameSize(NSSize(width: width, height: 800)) }
        }
    }

    @Test func aNewSplitsSplitterAnnouncesItselfAndTheLayoutChangeWithNoValueChange() {
        let rig = Rig()
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        rig.twoPanes()
        let list = rig.taken()
        let first = rig.splitters[0]
        #expect(parent != nil && list.count == 2)
        #expect(list[0].notification == .created && list[0].element === first)
        #expect(list[1].notification == .layoutChanged && list[1].element === parent)
        #expect(list[1].elements.count == 1 && list[1].elements[0] === first)
        #expect(rig.value(0) == 50)
    }

    @Test func layingOutTheSameSplitAgainAnnouncesNothing() {
        let rig = Rig()
        rig.twoPanes()
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        #expect(rig.taken().isEmpty)
    }

    @Test func aVoiceOverStepMovesTheDividerAndPostsItsValueChangeExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        #expect(first.accessibilityPerformIncrement())
        #expect(rig.value(0) == 60)
        let list = rig.taken()
        #expect(list.count == 1)
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func aRefusedStepChangesNothingAndPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.prepareDividerResize = { { _ in false } }
        #expect(!rig.splitters[0].accessibilityPerformIncrement())
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func steppingBackPostsOnce() {
        let rig = Rig()
        rig.settled()
        _ = rig.splitters[0].accessibilityPerformIncrement()
        _ = rig.taken()
        #expect(rig.splitters[0].accessibilityPerformDecrement())
        #expect(rig.value(0) == 50)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func aLiveMouseDragNeverPostsWhileItMoves() {
        let rig = Rig()
        rig.settled()
        let start = rig.dividerPoint()
        #expect(rig.split.beginDividerResize(at: start))
        for offset in [40.0, 80.0, 120.0] {
            rig.split.updateDividerResize(at: NSPoint(x: start.x + offset, y: start.y), velocity: 200)
        }
        #expect(rig.taken().isEmpty)
        rig.split.finishDividerResize(commit: false)
    }

    @Test func aFinishedMouseDragPostsItsNewValueExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        let start = rig.dividerPoint()
        rig.split.beginDividerResize(at: start)
        for offset in [40.0, 80.0, 120.0] {
            rig.split.updateDividerResize(at: NSPoint(x: start.x + offset, y: start.y), velocity: 200)
        }
        rig.split.finishDividerResize(commit: true)
        let list = rig.taken()
        #expect(rig.value(0) == 60)
        #expect(list.count == 1 && rig.changed(list)[0] === first)
    }

    @Test func aCancelledDragReturnsToTheSameValueAndPostsNothing() {
        let rig = Rig()
        rig.settled()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(-80), velocity: 200)
        rig.split.finishDividerResize(commit: false)
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDoubleClickEqualizePostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [3, 1])
        _ = rig.taken()
        rig.doubleClick()
        #expect(rig.value(0) == 50)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func equalizingAnAlreadyEvenPairPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.doubleClick()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDragTooSmallToChangeTheReportedPercentagePostsNothing() {
        let rig = Rig()
        rig.settled()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(2), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func anExpandFromTheWindowPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.value(0) == 82)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func repeatingTheSameLayoutPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.taken().isEmpty)
    }

    @Test func aWindowResizeThatMovesTheSharesWaitsForTheSizeToSettle() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        #expect(rig.value(0) == 78)
        #expect(rig.taken().isEmpty)
    }

    @Test func onceTheSizeSettlesARunOfResizesPostsExactlyOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        rig.shrinkAfterExpand()
        rig.settle()
        let list = rig.taken()
        #expect(list.count == 1 && rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func theHeldPairReportsItsDisplayedSizesAsTheDragMovesAndNeverPostsWhilePaused() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        #expect(rig.split.beginDividerResize(at: rig.dividerPoint()))
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        #expect(rig.value(0) == 68)
        rig.settle()
        #expect(rig.taken().isEmpty)
    }

    @Test func releasingTheHeldDragPostsTheNewValueExactlyOnceThroughTheWindowsCommit() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        rig.split.beginDividerResize(at: rig.dividerPoint())
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        let list = rig.taken()
        #expect(rig.value(0) == 68)
        #expect(list.count == 1 && rig.changed(list).count == 1)
    }

    @Test func expandingAgainPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        rig.split.beginDividerResize(at: rig.dividerPoint())
        rig.split.updateDividerResize(at: rig.dividerPoint(-100), velocity: 200)
        rig.split.finishDividerResize(commit: true)
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        #expect(rig.value(0) == 78)
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func growingBackAlsoWaitsAndTheEndOfALiveResizePostsAtOnce() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        _ = rig.taken()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        #expect(rig.value(0) == 82)
        #expect(rig.taken().isEmpty)
        rig.split.viewDidEndLiveResize()
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func theSettledValueIsNotPostedAgain() {
        let rig = Rig()
        rig.settled()
        rig.shrinkAfterExpand()
        rig.settle()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        rig.split.viewDidEndLiveResize()
        _ = rig.taken()
        rig.settle()
        #expect(rig.taken().isEmpty)
    }

    @Test func returningToEvenPanesPostsOnce() {
        let rig = Rig()
        rig.settled()
        rig.split.configure(orientation: .horizontal, factors: [980, 220])
        _ = rig.taken()
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        #expect(rig.changed(rig.taken()).count == 1)
    }

    @Test func aWindowResizeThatKeepsTheSharesPostsNothing() {
        let rig = Rig()
        rig.settled()
        rig.split.setFrameSize(NSSize(width: 1010, height: 800))
        rig.settle()
        rig.split.setFrameSize(NSSize(width: 1210, height: 800))
        rig.settle()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func aDropPreviewHidesTheSplitterAndPostsNothingAndEndingItRestoresTheSameValue() {
        let rig = Rig()
        rig.settled()
        let reservation = rig.split.prepareDropReservation(in: rig.window.contentView!, contents: Array(rig.panes[..<2]))
        reservation?.hoverIntent = SplitDropIntent(dwell: 0)
        let preview = reservation?.proposal(at: rig.split.convert(NSPoint(x: 10, y: 300), to: rig.window.contentView!)) { _, _ in true }
        #expect(preview != nil)
        #expect(rig.splitters.isEmpty)
        #expect(rig.taken().isEmpty)
        reservation?.end()
        #expect(rig.value(0) == 50)
        #expect(rig.taken().isEmpty)
    }

    @Test func voiceOverAskingMidUpdatePostsNothing() {
        let rig = Rig()
        rig.settled()
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        #expect(rig.splitters.count == 2)
        #expect(rig.taken().isEmpty)
    }

    @Test func addingAPaneAnnouncesItsNewSplitterAndTheLayoutAndPostsTheMovedDividerOnce() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        rig.split.configure(orientation: .horizontal, factors: [1, 1, 1])
        let list = rig.taken()
        let added = rig.splitters
        #expect(added.count == 2 && added[0] === first)
        #expect(rig.value(0) == 33 && rig.value(1) == 67)
        #expect(list.count == 3)
        let created = list.filter { $0.notification == .created }.map(\.element)
        #expect(created.count == 1 && created[0] === added[1])
        #expect(list.contains { $0.notification == .layoutChanged && $0.element === parent && $0.elements.count == 1 && $0.elements[0] === added[1] })
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func removingAPaneRetiresItsSplitterAnnouncesTheLayoutAndPostsTheSurvivingDividerOnce() {
        let rig = Rig()
        rig.settled()
        _ = rig.split.reconcileArrangedSubviews(rig.panes)
        rig.split.configure(orientation: .horizontal, factors: [1, 1, 1])
        let first = rig.splitters[0], second = rig.splitters[1]
        let parent = NSAccessibility.unignoredAncestor(of: rig.split) as AnyObject?
        _ = rig.taken()
        _ = rig.split.reconcileArrangedSubviews(Array(rig.panes[..<2]))
        rig.split.configure(orientation: .horizontal, factors: [1, 1])
        let list = rig.taken()
        #expect(rig.splitters.count == 1 && rig.value(0) == 50 && list.count == 3)
        let destroyed = list.filter { $0.notification == .uiElementDestroyed }.map(\.element)
        #expect(destroyed.count == 1 && destroyed[0] === second)
        #expect(list.contains { $0.notification == .layoutChanged && $0.element === parent && $0.elements.isEmpty })
        #expect(rig.changed(list).count == 1 && rig.changed(list)[0] === first)
    }

    @Test func endingTheSplitRetiresTheLastSplitterWithoutAValueChange() {
        let rig = Rig()
        rig.settled()
        let first = rig.splitters[0]
        _ = rig.split.reconcileArrangedSubviews([rig.panes[0]])
        rig.split.configure(orientation: .horizontal, factors: [1])
        let list = rig.taken()
        #expect(rig.splitters.isEmpty && list.count == 2)
        #expect(list[0].notification == .uiElementDestroyed && list[0].element === first)
        #expect(list[1].notification == .layoutChanged)
        #expect(rig.changed(list).isEmpty)
    }
}
