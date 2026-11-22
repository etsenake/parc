import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsResizeCommands {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

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

    @Test func afterExpandTheFocusedPaneCannotWiden() throws {
        let rig = try Rig()
        rig.expand()
        #expect(!rig.split.canResizePane(rig.panes[1], growing: true))
    }

    @Test func afterExpandTheFocusedPaneCanNarrow() throws {
        let rig = try Rig()
        rig.expand()
        #expect(rig.split.canResizePane(rig.panes[1], growing: false))
    }

    @Test func afterExpandThePanesCanBeMadeEqual() throws {
        let rig = try Rig()
        rig.expand()
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

    @Test func narrowingCanLeaveAPaneAboveItsMinimum() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(3)
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.widths[1] > 220)
    }

    @Test func narrowingClampsThePaneAtItsMinimum() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(4)
        #expect(rig.split.resizePane(rig.panes[1], growing: false))
        #expect(rig.widths[1] == 220)
    }

    @Test func narrowingRefusesAPaneAlreadyAtItsMinimum() throws {
        let rig = try Rig()
        rig.expand()
        rig.narrow(5)
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
