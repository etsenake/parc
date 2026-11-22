import CoreGraphics
import Testing
@testable import Parc
@testable import ParcSidebar

struct SidebarChromeLayoutTestsDockTests {
    private typealias L = SidebarChromeLayoutTestsSupport.L

    @Test func theTrailingDockButtonHasItsFrame() {
        #expect(L.dockTrailingButton(width: 228, height: 800) == CGRect(x: 188, y: 759, width: 32, height: 32))
    }

    @Test func theLeadingDockButtonHasItsFrame() {
        #expect(L.dockLeadingButton(height: 800) == CGRect(x: 8, y: 759, width: 32, height: 32))
    }

    @Test func theDockStripHasItsFrame() {
        #expect(L.dockStrip(width: 228, height: 800) == CGRect(x: 40, y: 750, width: 148, height: 50))
    }

    @Test(arguments: [164.0, 228.0, 500.0] as [CGFloat])
    func theStripAbutsBothDockButtons(width: CGFloat) {
        let strip = L.dockStrip(width: width, height: 800)
        #expect(strip.minX == L.dockLeadingButton(height: 800).maxX)
        #expect(strip.maxX == L.dockTrailingButton(width: width, height: 800).minX)
    }

    @Test func aStripNarrowerThanTheTwoButtonsCollapsesToNothing() {
        #expect(L.dockStrip(width: 60, height: 800).width == 0)
    }

    @Test func thirtyFourPointItemsAreCentredAsAGroup() {
        let three = L.dockLayout(width: 148, height: 50, count: 3, focused: nil)
        #expect(three.items == [21, 55, 89].map { CGRect(x: $0, y: 9, width: 34, height: 32) })
        #expect(three.contentWidth == 123)
        #expect(!three.compact)
        #expect(L.dockLayout(width: 148, height: 50, count: 3, focused: 1) == three)
    }

    struct CompactWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: CGFloat
        let compact: Bool
    }

    @Test(arguments: [
        CompactWidth(testDescription: "22-point pitch", width: 136.0, compact: false),
        CompactWidth(testDescription: "Below 22 points", width: 135.0, compact: true),
    ])
    func belowTwentyTwoTheItemsBecomeDots(_ sample: CompactWidth) {
        let width = sample.width
        let compact = sample.compact
        #expect(L.dockLayout(width: width, height: 50, count: 6, focused: nil).compact == compact)
    }

    @Test func aCompactPitchFillsTheStrip() {
        let dots = L.dockLayout(width: 148, height: 50, count: 8, focused: nil)
        #expect(dots.compact)
        #expect(dots.items.allSatisfy { $0.width == 18 })
        #expect(dots.items.first?.minX == 0)
        #expect(dots.contentWidth == 144)
    }

    @Test func theFocusedItemWidensToTwentyTwoAndTheOthersShareTheRest() {
        let focused = L.dockLayout(width: 148, height: 50, count: 8, focused: 2)
        #expect(focused.compact)
        #expect(focused.items[2].width == 22)
        #expect(focused.items.enumerated().allSatisfy { $0.offset == 2 || abs($0.element.width - 122.0 / 7) < 0.0001 })
        #expect(abs(focused.contentWidth - 144) < 0.0001)
    }

    @Test func anOutOfRangeFocusIsIgnored() {
        #expect(L.dockLayout(width: 148, height: 50, count: 8, focused: 8) == L.dockLayout(width: 148, height: 50, count: 8, focused: nil))
    }

    @Test func moreSpacesThanEightPointPitchesScroll() {
        let overflow = L.dockLayout(width: 148, height: 50, count: 20, focused: nil)
        #expect(overflow.items.allSatisfy { $0.width == 8 })
        #expect(overflow.items.first?.minX == 0)
        #expect(overflow.contentWidth == 160)
    }

    @Test func focusWidensOverflowingDots() {
        let overflow = L.dockLayout(width: 148, height: 50, count: 20, focused: 19)
        #expect(overflow.items[19].width == 22)
        #expect(overflow.items[0].width == 8)
        #expect(overflow.contentWidth == 174)
    }

    @Test func itemsNeverExceedTheStripHeight() {
        #expect(L.dockLayout(width: 148, height: 20, count: 2, focused: nil).items.allSatisfy { $0.height == 20 && $0.minY == 0 })
    }

    @Test func noSpaces() {
        #expect(L.dockLayout(width: 148, height: 50, count: 0, focused: 0) == .init(items: [], contentWidth: 0, compact: false))
    }

    struct DockFocus: CustomTestStringConvertible {
        let count: Int
        let index: Int?

        var testDescription: String {
            "\(count) items, " + (index.map { "focus at index \($0)" } ?? "no focus")
        }
    }

    private static let focusCases = (1...40).flatMap { count in
        ([nil, 0, count / 2, count - 1] as [Int?]).map { DockFocus(count: count, index: $0) }
    }

    @Test(arguments: stride(from: 30.0, through: 400, by: 7).map { CGFloat($0) }, focusCases)
    func theDockLayoutKeepsItsInvariantsAtEveryWidth(width: CGFloat, sample: DockFocus) {
        let (itemCount, focus) = (sample.count, sample.index)
        let dock = L.dockLayout(width: width, height: 50, count: itemCount, focused: focus)
        let available = width - 4
        #expect(dock.items.count == itemCount)
        #expect(dock.items.allSatisfy { $0.minY == 9 && $0.height == 32 })
        #expect(zip(dock.items, dock.items.dropFirst()).allSatisfy { abs($0.maxX - $1.minX) < 0.0001 })
        #expect(abs(dock.contentWidth - dock.items[itemCount - 1].maxX) < 0.0001)
        let unfocused = dock.items.enumerated().filter { $0.offset != focus || !dock.compact }.map { $0.element.width }
        #expect(unfocused.allSatisfy { $0 >= 8 && $0 <= 34 && abs($0 - unfocused[0]) < 0.0001 })
        #expect(dock.compact == (unfocused[0] < 22))
        if let focus, dock.compact { #expect(dock.items[focus].width == 22) }
        if dock.contentWidth <= available + 0.0001 {
            let lead = dock.items[0].minX
            let trail = available - dock.items[itemCount - 1].maxX
            #expect(lead >= -0.0001)
            #expect(abs(lead - trail) < 0.0001)
        } else {
            #expect(dock.items[0].minX == 0)
        }
    }

    struct DockIcon: CustomTestStringConvertible {
        let testDescription: String
        let custom: Bool
        let symbol: String
        let iconless: Bool
    }

    @Test(arguments: [
        DockIcon(testDescription: "Filled circle sentinel", custom: false, symbol: "circle.fill", iconless: true),
        DockIcon(testDescription: "Circle sentinel", custom: false, symbol: "circle", iconless: true),
        DockIcon(testDescription: "Custom circle", custom: true, symbol: "circle", iconless: false),
        DockIcon(testDescription: "Star", custom: false, symbol: "star", iconless: false),
    ])
    func theIconlessSentinelsAndCustomIcons(_ sample: DockIcon) {
        let custom = sample.custom
        let symbol = sample.symbol
        let iconless = sample.iconless
        #expect(L.dockIconless(hasCustomIcon: custom, symbol: symbol) == iconless)
    }

    struct DockVisibility: CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let custom: Bool
        let creating: Bool
        let shows: Bool
    }

    @Test(arguments: [
        DockVisibility(testDescription: "One iconless Space", count: 1, custom: false, creating: false, shows: false),
        DockVisibility(testDescription: "No Spaces", count: 0, custom: false, creating: false, shows: false),
        DockVisibility(testDescription: "Custom icon", count: 1, custom: true, creating: false, shows: true),
        DockVisibility(testDescription: "Two Spaces", count: 2, custom: false, creating: false, shows: true),
        DockVisibility(testDescription: "Creating a Space", count: 1, custom: false, creating: true, shows: true),
    ])
    func theDockShowsSpacesOnlyWhenItHasMoreThanOneIconlessSpace(_ sample: DockVisibility) {
        let count = sample.count
        let custom = sample.custom
        let creating = sample.creating
        let shows = sample.shows
        #expect(L.dockShowsSpaces(count: count, anyCustomIcon: custom, creating: creating) == shows)
    }

    struct DockItem: CustomTestStringConvertible {
        let testDescription: String
        let compact: Bool
        let selection: CGFloat
        let highlighted: Bool
        let dark: Bool
        var iconless = false
        let expected: SidebarChromeLayout.DockItemPresentation
    }

    @Test(arguments: [
        DockItem(testDescription: "Selected iconless Space", compact: false, selection: 1, highlighted: false, dark: false, iconless: true, expected: .dot(side: 8, alpha: 1)),
        DockItem(testDescription: "Compact iconless Space in dark appearance", compact: true, selection: 0, highlighted: false, dark: true, iconless: true, expected: .dot(side: 8, alpha: 0.35)),
        DockItem(testDescription: "Highlighted iconless Space", compact: false, selection: 0, highlighted: true, dark: false, iconless: true, expected: .dot(side: 8, alpha: 0.7)),
        DockItem(testDescription: "Idle compact Space in light appearance", compact: true, selection: 0, highlighted: false, dark: false, expected: .dot(side: 4, alpha: 0.5)),
        DockItem(testDescription: "Idle compact Space in dark appearance", compact: true, selection: 0, highlighted: false, dark: true, expected: .dot(side: 4, alpha: 0.35)),
        DockItem(testDescription: "Selected compact Space", compact: true, selection: 1, highlighted: false, dark: false, expected: .icon(active: 1, inactive: 0)),
        DockItem(testDescription: "Highlighted compact Space", compact: true, selection: 0, highlighted: true, dark: true, expected: .icon(active: 0.7, inactive: 0)),
        DockItem(testDescription: "Idle regular Space in light appearance", compact: false, selection: 0, highlighted: false, dark: false, expected: .icon(active: 0, inactive: 0.5)),
        DockItem(testDescription: "Idle regular Space in dark appearance", compact: false, selection: 0, highlighted: false, dark: true, expected: .icon(active: 0, inactive: 0.35)),
        DockItem(testDescription: "Highlighted regular Space", compact: false, selection: 0, highlighted: true, dark: false, expected: .icon(active: 0.7, inactive: 0)),
        DockItem(testDescription: "Selected regular Space", compact: false, selection: 1, highlighted: true, dark: false, expected: .icon(active: 1, inactive: 0)),
        DockItem(testDescription: "Space halfway through selection", compact: false, selection: 0.5, highlighted: false, dark: false, expected: .icon(active: 0.5, inactive: 0.25)),
    ])
    func eachDockStateShowsItsDotOrIcon(_ sample: DockItem) {
        #expect(L.dockItemPresentation(compact: sample.compact, selection: sample.selection,
            highlighted: sample.highlighted, dark: sample.dark, iconless: sample.iconless) == sample.expected)
    }
}
