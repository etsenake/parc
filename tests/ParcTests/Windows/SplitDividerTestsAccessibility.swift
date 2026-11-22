import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsAccessibility {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

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
        #expect(SplitDividerTestsSupport.near([rig.commits[0][0] - rig.commits[0][1]], [2 * SplitPaneResize.step]))
        #expect(SplitDividerTestsSupport.near([rig.commits[0][2]], [1.0 / 3]))
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
