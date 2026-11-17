import Foundation

@main @MainActor
struct SplitStackLayoutTests {
    static var assertions = 0
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String,
                       file: StaticString = #file, line: UInt = #line) throws {
        assertions += 1
        if try !value() { failTest(message, file: file, line: line) }
    }
    static func main() { exitOnFailure(runChecks) }

    static func close(_ left: [Double], _ right: [Double], _ tolerance: Double = 1e-9) -> Bool {
        left.count == right.count && zip(left, right).allSatisfy { abs($0 - $1) < tolerance }
    }

    static func stacks(_ sizes: [Int], _ slots: [Double], _ inner: [[Double]]) -> BrowserSplitStacks {
        BrowserSplitStacks(slotSizes: sizes, slotFactors: slots, stackFactors: inner)
    }

    static func frames(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                       size: CGSize = CGSize(width: 1010, height: 710), scale: CGFloat = 2) -> [CGRect] {
        SplitStackGeometry.paneFrames(size: size, orientation: orientation, stacks: value,
                                      thickness: 10, minimum: 220, scale: scale)
    }

    static func dividers(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                         size: CGSize = CGSize(width: 1010, height: 710)) -> [SplitStackGeometry.Divider] {
        SplitStackGeometry.dividers(paneFrames: frames(value, orientation, size: size), size: size,
                                    orientation: orientation, stacks: value, thickness: 10)
    }

    static func runChecks() throws {
        try frameMaths()
        try dividerRectsAndRegions()
        try containerMinimum()
        try splitterValuesAndLabels()
        try layoutCommands()
        try reservedStackShapes()
        try pendingPanePreview()
        try picturesOfASplit()
        print("SplitStackLayoutTests passed \(assertions) checks")
    }

    static func frameMaths() throws {
        let column = stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
        try expect(frames(column) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 0, y: 360, width: 500, height: 350),
                                      CGRect(x: 510, y: 0, width: 500, height: 710)],
                   "A side-by-side split runs its slots across and stacks the first column top and bottom with a 10-point gap")
        let row = stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
        try expect(frames(row, .vertical) == [CGRect(x: 0, y: 0, width: 500, height: 350), CGRect(x: 510, y: 0, width: 500, height: 350),
                                              CGRect(x: 0, y: 360, width: 1010, height: 350)],
                   "A top-and-bottom split runs its rows down and divides the first row left and right")
        let squeezedStack = frames(stacks([2, 1], [0.5, 0.5], [[0.95, 0.05], [1]]))
        try expect(squeezedStack[1].height == 220 && squeezedStack[0].height == 480 && squeezedStack[1].minY == 490,
                   "A stacked pane keeps the 220-point minimum on the cross axis and its neighbour gives up the deficit")
        let squeezedRow = frames(stacks([2, 1], [0.9, 0.1], [[0.5, 0.5], [1]]))
        try expect(squeezedRow[2].width == 220 && squeezedRow[0].width == 780 && squeezedRow[1].width == 780,
                   "A slot keeps the 220-point minimum on the main axis and both panes in the stack share its width")
        let three = frames(stacks([1, 3], [0.5, 0.5], [[1], [0.9, 0.05, 0.05]]))
        try expect(three[2].height == 220 && three[3].height == 220 && three[1].height == 250,
                   "Several squeezed stack panes each keep the minimum and the rest redistributes")
        let odd = frames(stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]]), size: CGSize(width: 1001, height: 701), scale: 2)
        let integral = odd.allSatisfy { [$0.minX, $0.minY, $0.maxX, $0.maxY].allSatisfy { $0 == $0.rounded() } }
        try expect(integral, "Pane edges stay on whole points after backing-scale rounding")
        try expect(odd[0].minX == odd[1].minX && odd[0].maxX == odd[1].maxX, "Panes in one stack share the slot's edges exactly")
        try expect(odd[2].maxX == 1001 && odd[1].maxY == 701, "The last slot and the last stacked pane reach the split's far edges")
        let lengths = SplitStackGeometry.lengths([0.7, 0.2, 0.1], available: 1000, minimum: 220)
        try expect(lengths.map { Double($0) } == [560, 220, 220], "The deficit loop matches the flat split's redistribution")
    }

    static func dividerRectsAndRegions() throws {
        let column = dividers(stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]]))
        try expect(column.map(\.id) == [SplitStackDivider(slot: 0, index: 0), SplitStackDivider(slot: nil, index: 0)],
                   "Dividers follow reading order: the stack divider, then the main-row divider")
        try expect(column[0].rect == CGRect(x: 0, y: 350, width: 500, height: 10) && !column[0].isVerticalBar,
                   "A stack divider spans only its column")
        try expect(column[0].region == CGRect(x: 8, y: 350, width: 484, height: 10),
                   "The stacked divider's 8-point end inset applies within its column")
        try expect(column[1].rect == CGRect(x: 500, y: 0, width: 10, height: 710) && column[1].isVerticalBar,
                   "A main-row divider spans the whole split")
        try expect(column[1].region == CGRect(x: 500, y: 53, width: 10, height: 657),
                   "The main-row side-by-side divider keeps the 53-point top bar clear")

        let rows = dividers(stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]]), .vertical)
        try expect(rows.map(\.id) == [SplitStackDivider(slot: nil, index: 0), SplitStackDivider(slot: 1, index: 0)],
                   "A top-and-bottom split lists the main-row divider before the lower row's divider")
        try expect(rows[0].rect == CGRect(x: 0, y: 350, width: 1010, height: 10)
                   && rows[0].region == CGRect(x: 8, y: 350, width: 994, height: 10),
                   "The main-row divider in a top-and-bottom split spans the width with the 8-point end inset")
        try expect(rows[1].rect == CGRect(x: 500, y: 360, width: 10, height: 350) && rows[1].isVerticalBar,
                   "A divider inside the lower row spans only that row")
        try expect(rows[1].region == CGRect(x: 500, y: 413, width: 10, height: 297),
                   "A divider between two lower panes stays clear of their own headers")

        let four = stacks([2, 2], [0.5, 0.5], [[0.5, 0.5], [0.5, 0.5]])
        try expect(four.divider(after: 0) == SplitStackDivider(slot: 0, index: 0)
                   && four.divider(after: 1) == SplitStackDivider(slot: nil, index: 0)
                   && four.divider(after: 2) == SplitStackDivider(slot: 1, index: 0) && four.divider(after: 3) == nil,
                   "Four panes in two stacks give a splitter between each pair of reading-order neighbours")
        try expect(stacks([3, 1], [0.5, 0.5], [[1, 1, 1], [1]]).divider(after: 1) == SplitStackDivider(slot: 0, index: 1),
                   "The second divider inside a three-pane stack is that stack's second divider")
        try expect(SplitStackGeometry.dividers(paneFrames: [.zero, .zero], size: .zero, orientation: .horizontal,
                                               stacks: four, thickness: 10).isEmpty,
                   "Frames that don't match the stack give no dividers")
    }

    static func containerMinimum() throws {
        try expect(SplitStackGeometry.minimumSize(orientation: .horizontal, slotSizes: [2, 1], minimum: 220, thickness: 10)
                   == CGSize(width: 450, height: 450), "Two columns and a two-pane stack need 450 points each way")
        try expect(SplitStackGeometry.minimumSize(orientation: .horizontal, slotSizes: [3, 1], minimum: 220, thickness: 10)
                   == CGSize(width: 450, height: 680), "A three-pane stack sums three minimums down the column")
        try expect(SplitStackGeometry.minimumSize(orientation: .vertical, slotSizes: [1, 1, 2], minimum: 220, thickness: 10)
                   == CGSize(width: 450, height: 680), "Three rows sum down the split and the divided row sums across")
        try expect(SplitStackGeometry.minimumSize(orientation: .horizontal, slotSizes: [2, 1, 1], minimum: 220, thickness: 10)
                   == CGSize(width: 680, height: 450), "A reserved main-row slot adds one minimum along the row")
    }

    static func splitterValuesAndLabels() throws {
        try expect(SplitStackGeometry.splitterLabel(index: 0, count: 2, slot: 0, orientation: .horizontal)
                   == "Split View Divider 1, inside column 1", "A stack splitter says which column it sits in")
        try expect(SplitStackGeometry.splitterLabel(index: 1, count: 3, slot: 0, orientation: .horizontal)
                   == "Split View Divider 2, inside column 1", "Splitters keep their reading-order number")
        try expect(SplitStackGeometry.splitterLabel(index: 1, count: 2, slot: 1, orientation: .vertical)
                   == "Split View Divider 2, inside row 2", "A top-and-bottom split names rows")
        try expect(SplitStackGeometry.splitterLabel(index: 1, count: 2, slot: nil, orientation: .horizontal)
                   == "Split View Divider 2", "Main-row splitters keep today's label")
        try expect(SplitStackGeometry.splitterLabel(index: 0, count: 1, slot: nil, orientation: .horizontal)
                   == "Split View Divider", "A lone splitter stays unnumbered")
        let pair = SplitStackGeometry.splitterPosition(shares: [0.25, 0.75], index: 0, minimum: 0.2)!
        try expect(close([pair.value, pair.minimum, pair.maximum], [0.25, 0.2, 0.8]),
                   "A stack splitter reports its share within its slot, bounded by the minimum on each side")
        let middle = SplitStackGeometry.splitterPosition(shares: [0.25, 0.25, 0.5], index: 1, minimum: 0.2)!
        try expect(close([middle.value, middle.minimum, middle.maximum], [0.5, 0.45, 0.8]),
                   "A later splitter counts the panes before it")
        try expect(SplitStackGeometry.splitterPosition(shares: [0.5, 0.5], index: 1, minimum: 0.2) == nil,
                   "A splitter past the last pair has no value")
        let saved = SplitStackGeometry.adjustableShares(saved: [0.5, 0.5], shown: [350, 350], available: 700, minimum: 220)!
        try expect(close(saved.shares, [0.5, 0.5]) && abs(saved.minimum - 220.0 / 700) < 1e-12,
                   "Valid saved stack shares measure against the slot's own length")
        let shown = SplitStackGeometry.adjustableShares(saved: [0.95, 0.05], shown: [480, 220], available: 700, minimum: 220)!
        try expect(close(shown.shares, [480.0 / 700, 220.0 / 700]), "Shares squeezed below the minimum fall back to what's shown")
        try expect(close(SplitStackGeometry.resizableFactors(saved: [0.5, 0.5], shown: [350, 350], divider: 0,
                                                              available: 700, minimum: 220)!, [0.5, 0.5]),
                   "A roomy pair drags from its saved shares")
    }

    static func layoutCommands() throws {
        let ids = [UUID(), UUID(), UUID()]
        let value = stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: ids, orientation: .horizontal,
                                        widthFactors: value.flattenedFactors, stacks: value)

        let expanded = layout.expanded(focusing: ids[1])!.stacks!
        try expect(expanded.slotFactors[0] > 0.999 && expanded.stackFactors[0][1] > 0.999,
                   "Expand gives the focused pane the largest share on both levels")
        let expandedFrames = frames(expanded)
        try expect(expandedFrames[2].width == 220 && expandedFrames[0].height == 220 && expandedFrames[1].height == 480,
                   "An expanded stacked pane leaves its neighbours at the minimum on both axes")

        let equal = layout.resized(by: .equal)!.stacks!
        try expect(equal.slotFactors == [0.5, 0.5] && equal.stackFactors == [[0.5, 0.5], [1]] && equal.isEven,
                   "Make All Equal evens the slots, then each stack")
        try expect(!value.isEven && stacks([2, 2], [1, 1], [[2, 2], [3, 3]]).isEven, "Evenness checks both levels")

        let widened = SplitPaneResize.resizingPane(0, in: value.slotFactors, growing: true, minimum: 0.22)!
        let wide = layout.resized(by: .slots(widened))!.stacks!
        try expect(close(wide.slotFactors, [0.7, 0.3]) && wide.stackFactors == value.stackFactors,
                   "Widen steps the focused pane's slot along the main row only")
        let narrowed = SplitPaneResize.resizingPane(0, in: value.slotFactors, growing: false, minimum: 0.22)!
        let narrow = layout.resized(by: .slots(narrowed))!.stacks!
        try expect(close(narrow.slotFactors, [0.5, 0.5]) && narrow.stackFactors == value.stackFactors,
                   "Narrow steps the slot back toward even and leaves the stack alone")

        let stackDivider = layout.resized(by: .divider(0, slot: 0, leadingShare: 0.5))!.stacks!
        try expect(close(stackDivider.stackFactors[0], [0.5, 0.5]) && close(stackDivider.slotFactors, value.slotFactors),
                   "Evening a stack divider moves only its two panes")
        let mainDivider = layout.resized(by: .divider(0, slot: nil, leadingShare: 0.25))!.stacks!
        try expect(close(mainDivider.slotFactors, [0.25, 0.75]) && mainDivider.stackFactors == value.stackFactors,
                   "A main-row divider moves only its two slots")
        let stepped = SplitPaneResize.movingDivider(0, in: [0.3, 0.7], forward: true, minimum: 0.3)!
        try expect(close(stepped, [0.4, 0.6]), "A keyboard step on a stack divider uses the slot's own shares")
        try expect(layout.resized(by: .divider(1, slot: 0, leadingShare: 0.5)) == nil, "A divider outside the stack is refused")
        let squeezed = SplitStackGeometry.resizableFactors(saved: [0.05, 0.24, 0.71], shown: [220, 318, 942], divider: 0,
                                                           available: 1480, minimum: 220)!
        try expect(close(squeezed, [220.0 / 1480, 318.0 / 1480, 942.0 / 1480]),
                   "A pair squeezed below the minimum drags from what's shown")
        let three = stacks([1, 1, 2], [0.05, 0.24, 0.71], [[1], [1], [0.5, 0.5]])
        let trio = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: [UUID(), UUID(), UUID(), UUID()], orientation: .horizontal,
                                      widthFactors: three.flattenedFactors, stacks: three)
        let whole = trio.resized(by: .level(slot: nil, factors: [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]))!.stacks!
        try expect(close(whole.slotFactors, [269.0 / 1480, 269.0 / 1480, 942.0 / 1480]) && whole.stackFactors == three.stackFactors,
                   "A squeezed drag saves its whole level as previewed, so the other slot keeps its size")
        let inner = layout.resized(by: .level(slot: 0, factors: [0.2, 0.8]))!.stacks!
        try expect(close(inner.stackFactors[0], [0.2, 0.8]) && close(inner.slotFactors, value.slotFactors),
                   "A whole-level save inside a stack changes only that stack")

        try expect(value.replacing([0.2, 0.8], inSlot: 0).stackFactors[0] == [0.2, 0.8]
                   && value.replacing([0.1, 0.9], inSlot: nil).slotFactors == [0.1, 0.9],
                   "A live drag replaces only its own level")
        let reserved = value.reservingSlot(at: 1)
        try expect(reserved.slotSizes == [2, 1, 1] && close(reserved.slotFactors, [0.4, 1.0 / 3, 0.4 * 2 / 3])
                   && reserved.stackFactors == [[0.3, 0.7], [1], [1]],
                   "A main-row drop reservation makes a whole new slot")
    }

    static func reservedStackShapes() throws {
        func committed(_ value: BrowserSplitStacks, _ orientation: SplitOrientation = .horizontal,
                       pane: Int, after: Bool) -> BrowserSplitStacks? {
            let layout = BrowserSplitLayout(id: UUID(), spaceID: UUID(), tabIDs: (0..<value.paneCount).map { _ in UUID() },
                                            orientation: orientation, widthFactors: value.flattenedFactors,
                                            stacks: value.slotSizes.contains { $0 > 1 } ? value : nil)
            return layout.insertingIntoStack(UUID(), besidePaneAt: pane, after: after)?.stacks
        }
        func matches(_ left: BrowserSplitStacks, _ right: BrowserSplitStacks?) -> Bool {
            guard let right else { return false }
            return left.slotSizes == right.slotSizes && close(left.slotFactors, right.slotFactors)
                && left.stackFactors.count == right.stackFactors.count
                && zip(left.stackFactors, right.stackFactors).allSatisfy { close($0, $1) }
        }
        func inside(_ region: CGRect, slotOf pane: CGRect, _ orientation: SplitOrientation = .horizontal) -> Bool {
            orientation == .horizontal ? region.minX == pane.minX && region.maxX == pane.maxX
                                       : region.minY == pane.minY && region.maxY == pane.maxY
        }

        let pair = BrowserSplitStacks.flat([0.6, 0.4])
        try expect(pair.slotSizes == [1, 1] && pair.slotFactors == [0.6, 0.4] && pair.stackFactors == [[1], [1]],
                   "A flat split reads as one pane per slot")
        let below = pair.reservingStack(besidePane: 0, after: true)!
        try expect(below.region == 1 && below.stacks.slotSizes == [2, 1] && below.stacks.slotFactors == [0.6, 0.4]
                   && below.stacks.stackFactors == [[0.5, 0.5], [1]],
                   "Stacking below the first of two panes halves its column and keeps the slot weights")
        try expect(matches(below.stacks, committed(pair, pane: 0, after: true)), "The reserved shape is the one the store commits")
        let belowFrames = frames(below.stacks)
        try expect(inside(belowFrames[1], slotOf: belowFrames[0]) && belowFrames[1].minY == belowFrames[0].maxY + 10
                   && belowFrames[2].height == 710,
                   "The region sits under its pane inside that column while the other column keeps its full height")
        let above = pair.reservingStack(besidePane: 1, after: false)!
        let aboveFrames = frames(above.stacks)
        try expect(above.region == 1 && above.stacks.slotSizes == [1, 2] && above.stacks.stackFactors == [[1], [0.5, 0.5]]
                   && inside(aboveFrames[1], slotOf: aboveFrames[2]) && aboveFrames[1].maxY + 10 == aboveFrames[2].minY,
                   "Stacking above the second pane puts the region first in its column")

        let trio = BrowserSplitStacks.flat([0.5, 0.25, 0.25])
        let middle = trio.reservingStack(besidePane: 1, after: false)!
        let middleFrames = frames(middle.stacks)
        try expect(middle.region == 1 && middle.stacks.slotSizes == [1, 2, 1] && middle.stacks.stackFactors == [[1], [0.5, 0.5], [1]]
                   && matches(middle.stacks, committed(trio, pane: 1, after: false)),
                   "Three flat panes stack the middle one in place")
        try expect(inside(middleFrames[1], slotOf: middleFrames[2]) && middleFrames[1].minY == 0
                   && middleFrames[0].height == 710 && middleFrames[3].height == 710, "Only the middle column divides")

        let column = stacks([2, 1], [0.6, 0.4], [[0.3, 0.7], [1]])
        let grown = column.reservingStack(besidePane: 0, after: true)!
        try expect(grown.region == 1 && grown.stacks.slotSizes == [3, 1] && grown.stacks.slotFactors == [0.6, 0.4]
                   && close(grown.stacks.stackFactors[0], [0.2, 1.0 / 3, 0.7 / 1.5]) && grown.stacks.stackFactors[1] == [1],
                   "A stack of two grows to three, the newcomer taking an average share before renormalising")
        try expect(matches(grown.stacks, committed(column, pane: 0, after: true)), "The grown stack matches the store's insertion")
        let grownFrames = frames(grown.stacks)
        try expect(inside(grownFrames[1], slotOf: grownFrames[0]) && grownFrames[1].minY == grownFrames[0].maxY + 10
                   && grownFrames[2].minY == grownFrames[1].maxY + 10,
                   "The region sits between the stacked panes inside their column")
        let lone = column.reservingStack(besidePane: 2, after: true)!
        try expect(lone.region == 3 && lone.stacks.slotSizes == [2, 2] && lone.stacks.stackFactors == [[0.3, 0.7], [0.5, 0.5]],
                   "Stacking the lone column leaves the other stack alone")

        let rows = BrowserSplitStacks.flat([0.5, 0.5])
        let right = rows.reservingStack(besidePane: 1, after: true)!
        let rowFrames = frames(right.stacks, .vertical)
        try expect(right.region == 2 && right.stacks.slotSizes == [1, 2]
                   && matches(right.stacks, committed(rows, .vertical, pane: 1, after: true)),
                   "A top-and-bottom split stacks its lower row left and right")
        try expect(inside(rowFrames[2], slotOf: rowFrames[1], .vertical) && rowFrames[2].minX == rowFrames[1].maxX + 10
                   && rowFrames[0].width == 1010, "The region sits to the right of its pane inside that row")

        try expect(column.reservingStack(besidePane: 3, after: false) == nil
                   && stacks([2, 1], [0.5, 0.5], [[1], [1]]).reservingStack(besidePane: 0, after: true) == nil,
                   "A pane outside the split or a malformed stack reserves nothing")
    }

    static func pendingPanePreview() throws {
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        let ids = [UUID(), UUID(), UUID()]
        func state(_ layout: BrowserSplitLayout) -> BrowserState {
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.tabs = layout.tabIDs.enumerated().map { index, id in
                BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                           kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                           savedURL: "https://\(index).test/", savedTitle: "T\(index)")
            }
            state.splitLayouts = [layout]; state.selectedTabIDs = layout.tabIDs
            return state
        }
        let value = stacks([2, 1], [0.5, 0.5], [[0.5, 0.5], [1]])
        let stacked = state(BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: ids, orientation: .horizontal,
                                               widthFactors: value.flattenedFactors, stacks: value))
        let below = SplitPaneInsertion(paneID: ids[2], stackingAfter: true, state: stacked)!
        try expect(below.index == 3 && below.previewLayout?.stacks?.slotSizes == [2, 2]
                   && below.previewLayout?.orientation == .horizontal,
                   "A pending pane below the lone column renders inside that column, after its pane")
        try expect(below.previewFactors.count == 4 && abs(below.previewFactors.reduce(0, +) - 1) < 1e-9,
                   "The pending stacked preview keeps a valid flat row")
        let above = SplitPaneInsertion(paneID: ids[0], stackingAfter: false, state: stacked)!
        try expect(above.index == 0 && above.previewLayout?.stacks?.slotSizes == [3, 1],
                   "A pending pane above the top-left pane joins its stack at the top")
        let mainRow = SplitPaneInsertion(paneID: ids[1], operation: .addAfter, state: stacked)!
        try expect(mainRow.index == 2 && mainRow.previewLayout?.stacks?.slotSizes == [2, 1, 1],
                   "A pending main-row pane beside a stack renders as its own full-length slot")
        try expect(SplitPaneInsertion(paneID: ids[0], operation: .addBelow, state: stacked) == nil,
                   "An Add that would change a stacked split's direction never opens a pending pane")

        let flat = state(BrowserSplitLayout(spaceID: space.id, tabIDs: [ids[0], ids[1]], orientation: .horizontal, widthFactors: [0.5, 0.5]))
        let flatAdd = SplitPaneInsertion(paneID: ids[1], operation: .addAfter, state: flat)!
        try expect(flatAdd.previewLayout == nil && close(flatAdd.previewFactors, [1.0 / 3, 1.0 / 3, 1.0 / 3]),
                   "A flat split's pending pane keeps today's flat preview")
        let flatStack = SplitPaneInsertion(paneID: ids[0], stackingAfter: true, state: flat)!
        try expect(flatStack.index == 1 && flatStack.previewLayout?.stacks?.slotSizes == [2, 1],
                   "Stacking a pane in a flat split previews the new stack")
    }

    static func picturesOfASplit() throws {
        var order = RecentTabOrder()
        let profile = BrowserProfile(id: UUID(), name: "Profile")
        let space = BrowserSpace(id: UUID(), name: "Home", symbol: "circle", color: "000000", profileID: profile.id)
        let ids = [UUID(), UUID(), UUID(), UUID()]
        var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
        state.tabs = ids.enumerated().map { index, id in
            BrowserTab(id: id, spaceID: space.id, profileID: profile.id, url: "https://\(index).test/", title: "T\(index)",
                       kind: .today, createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10),
                       savedURL: "https://\(index).test/", savedTitle: "T\(index)")
        }
        let value = stacks([1, 2], [0.5, 0.5], [[1], [0.5, 0.5]])
        state.splitLayouts = [BrowserSplitLayout(id: UUID(), spaceID: space.id, tabIDs: Array(ids.prefix(3)), orientation: .vertical,
                                                 widthFactors: value.flattenedFactors, stacks: value)]
        let items = order.items(state: state, selected: [ids[3]], currentSpace: space.id) { _ in true }
        let split = items.first { $0.tabIDs.count == 3 }
        try expect(split?.slotSizes == [1, 2] && split?.orientation == .vertical,
                   "The tab switcher learns the split's real stacked shape")
        try expect(items.first { $0.tabIDs == [ids[3]] }?.slotSizes == nil, "A single page has no stacked shape")
    }
}
