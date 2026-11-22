import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsConstraints {
    private typealias SplitConstraintHost = SplitDividerTestsSupport.SplitConstraintHost
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

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
