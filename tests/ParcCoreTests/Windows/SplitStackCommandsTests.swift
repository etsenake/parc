import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SplitStackCommandsTests {
    static func close(_ left: [Double], _ right: [Double]) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < 1e-9 }
    }
    static func layout(_ sizes: [Int], orientation: SplitOrientation = .horizontal) -> BrowserSplitLayout {
        let ids = (0..<sizes.reduce(0, +)).map { _ in UUID() }
        let even = sizes.map { Array(repeating: 1 / Double($0), count: $0) }
        let shape = BrowserSplitLayout.shape(orientation: orientation, sizes: sizes,
                                             factors: Array(repeating: 1 / Double(sizes.count), count: sizes.count), stackFactors: even)
        return BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: ids, orientation: shape.orientation,
                                  widthFactors: shape.widthFactors, stacks: shape.stacks)
    }

    @Test static func flatEnablingIsUnchanged() throws {
        for count in 0...5 {
            for index in -1...5 {
                let inside = (0..<count).contains(index)
                let flat = count > 0 ? layout(Array(repeating: 1, count: count)) : nil
                for candidate in [nil, flat] {
                    #expect(SplitPaneOperation.movePrevious.isEnabled(index: index, count: count, layout: candidate)
                               == (inside && count > 1 && index > 0), "Flat Move Left/Up keeps today's rule at \(index) of \(count)")
                    #expect(SplitPaneOperation.moveNext.isEnabled(index: index, count: count, layout: candidate)
                               == (inside && count > 1 && index < count - 1), "Flat Move Right/Down keeps today's rule at \(index) of \(count)")
                    #expect(SplitPaneOperation.addAfter.isEnabled(index: index, count: count, layout: candidate) == (inside && count < 4),
                               "Flat Add keeps today's four-pane limit")
                    #expect(SplitPaneOperation.separate.isEnabled(index: index, count: count, layout: candidate) == (inside && count > 1),
                               "Flat Separate keeps today's rule")
                    #expect(SplitPaneOperation.stackAfter.isEnabled(index: index, count: count, layout: candidate)
                               == (inside && (2...3).contains(count)), "Split This Pane needs a split with room for one more pane")
                    #expect(!SplitPaneOperation.stackPrevious.isEnabled(index: index, count: count, layout: candidate)
                               && !SplitPaneOperation.stackNext.isEnabled(index: index, count: count, layout: candidate),
                               "A flat pane has no stack to move in")
                }
            }
        }
    }

    @Test static func stackedEnablingMatchesTheStore() throws {
        for sizes in [[1, 2], [2, 1], [2, 2], [3, 1], [1, 3], [2, 1, 1], [1, 2, 1], [1, 1, 2], [1, 1], [1, 1, 1, 1]] {
            let split = layout(sizes)
            for (index, id) in split.tabIDs.enumerated() {
                let count = split.tabIDs.count
                #expect(SplitPaneOperation.movePrevious.isEnabled(index: index, count: count, layout: split)
                           == (split.movingSlot(of: id, by: -1) != nil), "Move Left matches the store's slot move in \(sizes)")
                #expect(SplitPaneOperation.moveNext.isEnabled(index: index, count: count, layout: split)
                           == (split.movingSlot(of: id, by: 1) != nil), "Move Right matches the store's slot move in \(sizes)")
                #expect(SplitPaneOperation.stackPrevious.isEnabled(index: index, count: count, layout: split)
                           == (split.movingWithinStack(id, by: -1) != nil), "Move Up matches the store's stack move in \(sizes)")
                #expect(SplitPaneOperation.stackNext.isEnabled(index: index, count: count, layout: split)
                           == (split.movingWithinStack(id, by: 1) != nil), "Move Down matches the store's stack move in \(sizes)")
                #expect(SplitPaneOperation.stackBefore.isEnabled(index: index, count: count, layout: split) == (count < 4),
                           "Split This Pane is offered on every pane until the split holds four")
            }
        }
        let trio = layout([1, 2])
        #expect(SplitPaneOperation.moveNext.isEnabled(index: 0, count: 3, layout: trio)
                   && !SplitPaneOperation.moveNext.isEnabled(index: 1, count: 3, layout: trio)
                   && SplitPaneOperation.movePrevious.isEnabled(index: 2, count: 3, layout: trio),
                   "Main-row Move follows slots: the stack's top pane can't move right past the end")
        #expect(SplitPaneOperation.stackNext.isEnabled(index: 1, count: 3, layout: trio)
                   && !SplitPaneOperation.stackPrevious.isEnabled(index: 1, count: 3, layout: trio)
                   && SplitPaneOperation.stackPrevious.isEnabled(index: 2, count: 3, layout: trio)
                   && !SplitPaneOperation.stackNext.isEnabled(index: 2, count: 3, layout: trio),
                   "A stack move needs a neighbour in that direction")
        #expect(!SplitPaneOperation.stackNext.isEnabled(index: 1, count: 4, layout: trio)
                   && SplitPaneOperation.moveNext.isEnabled(index: 1, count: 4, layout: trio),
                   "A layout that doesn't match the panes falls back to today's flat rules")
    }

    static func store(_ name: String) throws -> (BrowserStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-stack-commands-\(name)-" + UUID().uuidString)
        return (try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1_800_000_000) }), root)
    }

    @Test static func splitThisPaneTargets() throws {
        let (store, root) = try store("targets")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = store.open("https://a.test")
        #expect(SplitPaneInsertion(paneID: a, operation: .stackAfter, state: store.state) == nil
                   && SplitPaneInsertion(paneID: a, operation: .stackBefore, state: store.state) == nil,
                   "A single unsplit page has no stack to add to")
        #expect(SplitPaneInsertion(paneID: a, operation: .addBelow, state: store.state) != nil,
                   "A single page keeps today's Add items to start a split")
        let b = store.open("https://b.test")
        store.setSplit([a, b])
        let flat = store.activeSplitLayout!
        let below = SplitPaneInsertion(paneID: a, operation: .stackAfter, state: store.state)
        #expect(below != nil && below == SplitPaneInsertion(paneID: a, stackingAfter: true, state: store.state),
                   "Add Below This Pane is the store's stacked insertion")
        #expect(below?.target == .stack(0, after: true) && below?.index == 1 && below?.orientation == .horizontal
                   && below?.layout == flat && below?.paneID == a, "Add Below targets the pane's own slot, after it")
        let above = SplitPaneInsertion(paneID: b, operation: .stackBefore, state: store.state)
        #expect(above?.target == .stack(1, after: false) && above?.index == 1, "Add Above targets the pane's own slot, before it")
        #expect(below?.previewLayout?.stacks?.slotSizes == [2, 1] && above?.previewLayout?.stacks?.slotSizes == [1, 2]
                   && below?.previewLayout?.orientation == .horizontal, "The pending pane previews inside the pane's slot")
        let mainRow = SplitPaneInsertion(paneID: a, operation: .addAfter, state: store.state)
        #expect(mainRow?.target == .insert(1) && mainRow?.previewLayout == nil
                   && close(mainRow!.previewFactors, [1.0 / 3, 1.0 / 3, 1.0 / 3]),
                   "Add Right keeps adding a full-length pane with today's flat preview")
        for request in [below!, above!] {
            let preview = request.previewLayout!
            #expect(close(request.previewFactors, preview.widthFactors) && request.previewFactors.count == 3
                       && abs(request.previewFactors.reduce(0, +) - 1) < 1e-9, "Stacked preview factors are the preview's valid flat row")
        }
        let id = UUID()
        #expect(store.insertSplitPane(below!, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil,
                                         savedHomeIDs: [:], documents: [:]), "Add Below This Pane commits")
        let committed = store.activeSplitLayout!
        #expect(committed.id == flat.id && committed.tabIDs == [a, id, b] && committed.stacks?.slotSizes == [2, 1],
                   "The new pane lands below the pane, inside its column")
        #expect(close(below!.previewFactors, committed.widthFactors) && below!.previewLayout?.stacks == committed.stacks,
                   "The pending pane previewed exactly the shape that was committed")
        let again = SplitPaneInsertion(paneID: id, operation: .stackAfter, state: store.state)
        #expect(again?.target == .stack(1, after: true) && again?.previewLayout?.stacks?.slotSizes == [3, 1],
                   "On a pane already in a stack, the same items add to that stack")
        #expect(SplitPaneInsertion(paneID: a, operation: .addBelow, state: store.state) == nil,
                   "A cross-direction Add stays refused on a stacked split")
        #expect(store.insertSplitPane(SplitPaneInsertion(paneID: b, operation: .stackBefore, state: store.state)!, tabID: UUID(),
                                         navigationURL: URL(string: "https://fourth.test/"), creation: nil, savedHomeIDs: [:], documents: [:]),
                   "Add Above This Pane on the lone column commits")
        #expect(store.activeSplitLayout?.stacks?.slotSizes == [2, 2], "Both columns are stacks now")
        for pane in store.state.selectedTabIDs {
            #expect(SplitPaneInsertion(paneID: pane, operation: .stackAfter, state: store.state) == nil
                       && SplitPaneInsertion(paneID: pane, operation: .stackBefore, state: store.state) == nil,
                       "Split This Pane refuses at four panes")
        }
    }

    @Test static func splitThisPaneStartsASplitOnASinglePage() throws {
        for count in 0...5 {
            for isSplit in [false, true] {
                #expect(SplitPaneOperation.stackAfter.startsSplitView(paneCount: count, isSplit: isSplit) == (count == 1 && !isSplit),
                           "Split This Pane starts a Split View only on a single unsplit page, not with \(count) panes, split \(isSplit)")
                for operation in SplitPaneOperation.allCases where operation != .stackAfter {
                    #expect(!operation.startsSplitView(paneCount: count, isSplit: isSplit),
                               "Only Split This Pane is redirected, never \(operation) with \(count) panes")
                }
            }
        }
        let (store, root) = try store("single-page")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = store.open("https://a.test")
        #expect(store.state.selectedTabIDs == [a] && store.activeSplitLayout == nil
                   && SplitPaneOperation.stackAfter.startsSplitView(paneCount: store.state.selectedTabIDs.count,
                                                                    isSplit: store.activeSplitLayout != nil),
                   "On a single page Split This Pane runs as Add Split View")
        let started = SplitPaneInsertion(paneID: a, operation: .addAfter, state: store.state)
        #expect(started?.target == .insert(1) && started?.orientation == .horizontal && started?.layout == nil
                   && started?.previewLayout == nil && close(started!.previewFactors, [0.5, 0.5]),
                   "It opens Add Split View's pending pane to the right of the page")
        let id = UUID()
        #expect(store.insertSplitPane(started!, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil,
                                         savedHomeIDs: [:], documents: [:]), "The new Split View commits like Add Split View's")
        let split = store.activeSplitLayout
        #expect(split?.tabIDs == [a, id] && split?.orientation == .horizontal && split?.stacks == nil,
                   "The page and the new pane sit side by side with no stack")
        for (index, pane) in [a, id].enumerated() {
            #expect(!SplitPaneOperation.stackAfter.startsSplitView(paneCount: store.state.selectedTabIDs.count,
                                                                     isSplit: store.activeSplitLayout != nil),
                       "Once there is a split, Split This Pane stacks again")
            let below = SplitPaneInsertion(paneID: pane, operation: .stackAfter, state: store.state)
            #expect(below?.target == .stack(index, after: true) && below?.previewLayout?.stacks?.slotSizes == (index == 0 ? [2, 1] : [1, 2]),
                       "In the new split Split This Pane adds below the pane in focus")
        }
    }

    @Test static func committedPanesFollowReadingOrder() throws {
        let (store, root) = try store("reading")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = store.open("https://a.test"), b = store.open("https://b.test"), c = store.open("https://c.test")
        store.setSplit([a, b, c])
        let id = UUID()
        #expect(store.insertSplitPane(SplitPaneInsertion(paneID: c, operation: .stackBefore, state: store.state)!, tabID: id,
                                         navigationURL: URL(string: "https://new.test/"), creation: nil, savedHomeIDs: [:], documents: [:]),
                   "Add Above This Pane commits on the last column")
        func readingOrderHolds(_ sizes: [Int]) -> Bool {
            guard let split = store.activeSplitLayout else { return false }
            return store.state.selectedTabIDs == split.tabIDs && split.stacks?.slotSizes == sizes
        }
        #expect(store.state.selectedTabIDs == [a, b, id, c] && readingOrderHolds([1, 1, 2]),
                   "Numbered focus reads slot by slot, top to bottom: pane 3 is the new pane above the last one")
        var split = store.activeSplitLayout!
        #expect(SplitPaneOperation.stackNext.isEnabled(index: 2, count: 4, layout: split)
                   && store.moveSplitPaneWithinStack(id, offset: 1, expected: split), "Move Down within the stack commits")
        #expect(store.state.selectedTabIDs == [a, b, c, id] && readingOrderHolds([1, 1, 2]),
                   "Moving within a stack keeps reading order and the stack")
        split = store.activeSplitLayout!
        #expect(!SplitPaneOperation.moveNext.isEnabled(index: 3, count: 4, layout: split)
                   && !store.moveSplitPane(id, offset: 1, expected: split), "The last column can't move further right")
        #expect(SplitPaneOperation.movePrevious.isEnabled(index: 3, count: 4, layout: split)
                   && store.moveSplitPane(id, offset: -1, expected: split), "Move Left moves the whole column")
        #expect(store.state.selectedTabIDs == [a, c, id, b] && readingOrderHolds([1, 2, 1]),
                   "The whole stack moved together and pane 1 is still the top-left pane")
    }

    @Test static func topAndBottomSplitsStackSideways() throws {
        let (store, root) = try store("vertical")
        defer { try? FileManager.default.removeItem(at: root) }
        let a = store.open("https://a.test"), b = store.open("https://b.test")
        store.setSplit([a, b]); store.setSplitLayout(orientation: .vertical, widthFactors: [0.5, 0.5])
        let right = SplitPaneInsertion(paneID: b, operation: .stackAfter, state: store.state)!
        #expect(right.orientation == .vertical && right.target == .stack(1, after: true)
                   && right.previewLayout?.orientation == .vertical && right.previewLayout?.stacks?.slotSizes == [1, 2],
                   "In a top-and-bottom split, Add Right of This Pane divides the pane's row")
        let id = UUID()
        #expect(store.insertSplitPane(right, tabID: id, navigationURL: URL(string: "https://new.test/"), creation: nil,
                                         savedHomeIDs: [:], documents: [:]), "Add Right of This Pane commits")
        let split = store.activeSplitLayout!
        #expect(split.orientation == .vertical && split.tabIDs == [a, b, id] && split.stacks?.slotSizes == [1, 2],
                   "The new pane sits right of the pane, inside its row")
        #expect(SplitPaneOperation.stackPrevious.isEnabled(index: 2, count: 3, layout: split)
                   && !SplitPaneOperation.stackNext.isEnabled(index: 2, count: 3, layout: split)
                   && SplitPaneOperation.movePrevious.isEnabled(index: 2, count: 3, layout: split)
                   && !SplitPaneOperation.moveNext.isEnabled(index: 2, count: 3, layout: split),
                   "Move Left within the row and Move Up for the whole row are offered; their opposites have no neighbour")
    }
}
