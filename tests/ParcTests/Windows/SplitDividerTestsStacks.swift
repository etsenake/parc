import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsStacks {
    private typealias Support = SplitDividerTestsSupport

    private typealias SplitConstraintHost = Support.SplitConstraintHost
    private typealias SplitScaleWindow = Support.SplitScaleWindow

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
        #expect(Support.isDivider(rig.changes.first, 0, slot: 0, share: 400.0 / 700))
        #expect(rig.flatCommits == 0)
        #expect(Support.near(rig.layout.stacks!.stackFactors[0], [4.0 / 7, 3.0 / 7]))
        #expect(Support.near(rig.layout.stacks!.slotFactors, [0.5, 0.5]))
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
        #expect(Support.isDivider(rig.changes.last, 0, slot: nil, share: 0.4))
        #expect(Support.near(rig.layout.stacks!.slotFactors, [0.4, 0.6]))
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
        #expect(Support.isDivider(rig.changes.last, 0, slot: 0, share: 0.5))
        #expect(Support.near(rig.layout.stacks!.stackFactors[0], [0.5, 0.5]))
    }

    @Test func makeAllEqualIsAvailableWhenBothLevelsAreUneven() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(rig.split.canEqualizePanes)
    }

    @Test func makeAllEqualEvensBothLevels() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        #expect(rig.split.equalizePanes())
        #expect(rig.changes.last == .equal)
        #expect(rig.layout.stacks!.isEven)
    }

    @Test func makeAllEqualIsUnavailableAfterBothLevelsEvenOut() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        _ = rig.split.equalizePanes()
        #expect(!rig.split.canEqualizePanes)
    }

    @Test func widenStepsTheFocusedPanesWholeSlotAlongTheMainRowOnly() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        _ = rig.split.equalizePanes()
        #expect(rig.split.canResizePane(rig.panes[1], growing: true))
        #expect(rig.split.resizePane(rig.panes[1], growing: true))
        #expect(Support.near(rig.layout.stacks!.slotFactors, [0.6, 0.4]))
        #expect(rig.layout.stacks!.stackFactors == [[0.5, 0.5], [1]])
    }

    @Test func narrowStepsASlotBackAlongTheMainRow() {
        let rig = Rig()
        rig.dragStack()
        rig.dragMain()
        _ = rig.split.equalizePanes()
        _ = rig.split.resizePane(rig.panes[1], growing: true)
        #expect(rig.split.resizePane(rig.panes[2], growing: false))
        #expect(Support.near(rig.layout.stacks!.slotFactors, [0.7, 0.3]))
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
