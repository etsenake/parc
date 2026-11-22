import AppKit
import QuartzCore
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitDividerTestsExpand {
    private typealias SplitScaleWindow = SplitDividerTestsSupport.SplitScaleWindow

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
