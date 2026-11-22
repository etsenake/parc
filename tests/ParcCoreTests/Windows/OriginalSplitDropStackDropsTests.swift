import Foundation
import Testing
@testable import ParcCore

struct OriginalSplitDropStackDropsTests {
    @MainActor private final class StackFixture {
        let directory: URL
        let store: BrowserStore
        let t: [UUID]

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-original-stacks-" + UUID().uuidString)
            let store = try BrowserStore(directory: directory)
            self.store = store
            t = (0..<13).map { store.open("https://stack\($0).invalid") }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func drop(_ source: UUID, _ target: SplitDropTarget, _ orientation: SplitOrientation = .horizontal) -> Bool {
            store.dropTabIntoSplit(source, expectedSelection: store.state.selectedTabIDs, expectedLayout: store.activeSplitLayout,
                target: target, orientation: orientation)
        }

        func close(_ left: [Double]?, _ right: [Double]?) -> Bool {
            guard let left, let right else { return false }
            return left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
        }

        func flatPair(_ first: Int, _ second: Int, _ orientation: SplitOrientation, _ factors: [Double]) {
            store.setSplit([t[first], t[second]])
            _ = store.setSplitLayout(orientation: orientation, widthFactors: factors)
        }

        func stackedBelow() -> BrowserSplitLayout {
            flatPair(0, 1, .horizontal, [0.4, 0.6])
            _ = drop(t[2], .stack(1, after: true))
            return store.activeSplitLayout!
        }

        func stackedFour() -> BrowserSplitLayout {
            _ = stackedBelow()
            _ = drop(t[3], .stack(1, after: false))
            return store.activeSplitLayout!
        }
    }

    @MainActor @Test func aBottomBandDropCommitsOntoAFlatSplit() throws {
        let s = try StackFixture()
        s.flatPair(0, 1, .horizontal, [0.4, 0.6])
        #expect(s.drop(s.t[2], .stack(1, after: true)))
    }

    @MainActor @Test func theStackedTabSitsBelowItsPaneWhoseColumnKeepsItsWidth() throws {
        let s = try StackFixture()
        s.flatPair(0, 1, .horizontal, [0.4, 0.6])
        let flat = s.store.activeSplitLayout!
        _ = s.drop(s.t[2], .stack(1, after: true))
        let layout = try #require(s.store.activeSplitLayout)
        #expect(layout.id == flat.id)
        #expect(layout.tabIDs == [s.t[0], s.t[1], s.t[2]])
        #expect(layout.orientation == .horizontal)
        #expect(layout.stacks?.slotSizes == [1, 2])
        #expect(s.close(layout.stacks?.slotFactors, [0.4, 0.6]))
    }

    @MainActor @Test func theNewStackSavesWithTheDrop() throws {
        let s = try StackFixture()
        let layout = s.stackedBelow()
        #expect(try BrowserStore(directory: s.directory).activeSplitLayout == layout)
    }

    @MainActor @Test func aDropAboveAStackedPaneCommits() throws {
        let s = try StackFixture()
        _ = s.stackedBelow()
        #expect(s.drop(s.t[3], .stack(1, after: false)))
    }

    @MainActor @Test func aDropAboveJoinsTheExistingStackAboveThatPane() throws {
        let s = try StackFixture()
        let layout = s.stackedFour()
        #expect(layout.tabIDs == [s.t[0], s.t[3], s.t[1], s.t[2]])
        #expect(layout.stacks?.slotSizes == [1, 3])
        #expect(s.close(layout.stacks?.stackFactors[1], [1.0 / 3, 1.0 / 3, 1.0 / 3]))
    }

    @MainActor @Test func aStackDropRefusesAtFourPanes() throws {
        let s = try StackFixture()
        _ = s.stackedFour()
        let full = s.store.state
        #expect(!s.drop(s.t[4], .stack(0, after: true)))
        #expect(s.store.state == full)
    }

    @MainActor @Test func replacementStaysAvailableAtFourPanesAndKeepsTheStack() throws {
        let s = try StackFixture()
        let layout = s.stackedFour()
        #expect(s.drop(s.t[4], .replace(2)))
        #expect(s.store.state.selectedTabIDs == [s.t[0], s.t[3], s.t[4], s.t[2]])
        #expect(s.store.activeSplitLayout?.stacks == layout.stacks)
    }

    @MainActor @Test func aRightBandDropCommitsOntoATopAndBottomSplit() throws {
        let s = try StackFixture()
        s.flatPair(5, 6, .vertical, [0.5, 0.5])
        #expect(s.drop(s.t[7], .stack(0, after: true), .vertical))
    }

    @MainActor @Test func theTabSitsRightOfItsPaneInThatRow() throws {
        let s = try StackFixture()
        s.flatPair(5, 6, .vertical, [0.5, 0.5])
        _ = s.drop(s.t[7], .stack(0, after: true), .vertical)
        #expect(s.store.state.selectedTabIDs == [s.t[5], s.t[7], s.t[6]])
        #expect(s.store.activeSplitLayout?.orientation == .vertical)
        #expect(s.store.activeSplitLayout?.stacks?.slotSizes == [2, 1])
    }

    @MainActor @Test func aMainRowInsertStillAddsAFlatPane() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        #expect(s.drop(s.t[10], .insert(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[10], s.t[9]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
        #expect(s.close(s.store.activeSplitLayout?.widthFactors, BrowserSplitLayout.normalized([0.4, 0.5, 0.6], count: 3)))
    }

    @MainActor @Test func aFlatReplacementKeepsItsFlatWeights() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        let inserted = s.store.activeSplitLayout!
        #expect(s.drop(s.t[11], .replace(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[11], s.t[9]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
        #expect(s.store.activeSplitLayout?.widthFactors == inserted.widthFactors)
    }

    @MainActor private func fullFlat(_ s: StackFixture) {
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        _ = s.drop(s.t[11], .replace(1))
        _ = s.drop(s.t[10], .insert(3))
    }

    @MainActor @Test func aFourthFlatPaneJoinsTheMainRow() throws {
        let s = try StackFixture()
        s.flatPair(8, 9, .horizontal, [0.4, 0.6])
        _ = s.drop(s.t[10], .insert(1))
        _ = s.drop(s.t[11], .replace(1))
        #expect(s.drop(s.t[10], .insert(3)))
        #expect(s.store.activeSplitLayout?.stacks == nil)
    }

    @MainActor @Test func aFullFlatSplitRefusesAStackDrop() throws {
        let s = try StackFixture()
        fullFlat(s)
        let four = s.store.state
        #expect(!s.drop(s.t[12], .stack(1, after: true)))
        #expect(s.store.state == four)
    }

    @MainActor @Test func aFullFlatSplitStillTakesAReplacement() throws {
        let s = try StackFixture()
        fullFlat(s)
        #expect(s.drop(s.t[12], .replace(1)))
        #expect(s.store.state.selectedTabIDs == [s.t[8], s.t[12], s.t[9], s.t[10]])
        #expect(s.store.activeSplitLayout?.stacks == nil)
    }
}
