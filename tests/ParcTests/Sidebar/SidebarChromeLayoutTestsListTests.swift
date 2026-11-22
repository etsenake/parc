import CoreGraphics
import Testing
@testable import Parc
@testable import ParcSidebar

struct SidebarChromeLayoutTestsListTests {
    private typealias L = SidebarChromeLayoutTestsSupport.L
    private typealias E = SidebarChromeLayoutTestsSupport.E

    private typealias S = SidebarChromeLayout.TablistSpan

    private typealias T = SidebarChromeLayout.TablistSlot

    struct EmptyStateWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        EmptyStateWidth(testDescription: "Wide tray", width: 228.0, expected: 150.0),
        EmptyStateWidth(testDescription: "Narrow tray", width: 164.0, expected: 128.0),
        EmptyStateWidth(testDescription: "Tray narrower than padding", width: 20.0, expected: 0.0),
    ])
    func emptyStateTextWrapsAtOneHundredFiftyOrTheCardsPaddedWidth(_ sample: EmptyStateWidth) {
        let width = sample.width
        let expected = sample.expected
        #expect(E.textWidth(trayWidth: width) == expected)
    }

    private let icon = CGSize(width: 17, height: 16)

    private let title = CGSize(width: 140, height: 16)

    private let subtitle = CGSize(width: 150, height: 30)

    @Test func theEmptyStatesHeightIsEightAboveFourBelowAndTenAroundTheContent() {
        let expected: CGFloat = 102
        #expect(E.height(icon: icon, title: title, subtitle: subtitle) == expected)
    }

    @Test func theCardSitsInsideTheEightEightEightFourInsets() {
        #expect(E.frames(width: 228, height: 102, icon: icon, title: title, subtitle: subtitle).card == CGRect(x: 8, y: 8, width: 212, height: 90))
    }

    @Test func iconTitleAndSubtitleAreCentredAndStackedFourApart() {
        let empty = E.frames(width: 228, height: 102, icon: icon, title: title, subtitle: subtitle)
        #expect(empty.icon == CGRect(x: 105.5, y: 18, width: 17, height: 16))
        #expect(empty.title == CGRect(x: 44, y: 38, width: 140, height: 16))
        #expect(empty.subtitle == CGRect(x: 39, y: 58, width: 150, height: 30))
    }

    @Test func dismissIsFourteenByFourteenEightInFromTheCardsTopTrailingCorner() {
        #expect(E.frames(width: 228, height: 102, icon: icon, title: title, subtitle: subtitle).close == CGRect(x: 198, y: 16, width: 14, height: 14))
    }

    @Test func aTallerTrayCentresTheContentAndDismissStaysAtTheTop() {
        let tall = E.frames(width: 228, height: 160, icon: icon, title: title, subtitle: subtitle)
        #expect(tall.icon.minY - tall.card.minY == tall.card.maxY - tall.subtitle.maxY)
        #expect(tall.close.minY == 16)
    }

    @Test func theOutlineRowsHaveTheirCellHeightAndSpacing() {
        #expect(L.tablistCellHeight == 40)
        #expect(L.tablistVisibleRowHeight == 36)
        #expect(L.tablistIntercellSpacing == 1)
    }

    @Test func theOutlineIndentsEachLevelSixteenPoints() {
        #expect(L.tablistIndentation == 16)
    }

    @Test func theOutlineEndsWithItsBottomInset() {
        #expect(L.tablistBottomInset == 120)
    }

    @Test func thePinnedHeaderIsTwoPointsHigh() {
        #expect(L.pinnedHeaderHeight == 2)
    }

    @Test func theSectionDividerIsTwentyFourPointsHigh() {
        #expect(L.sectionDividerHeight == 24)
    }

    @Test func itemsFollowTheTwoPointPinnedHeader() {
        let pair = L.tablist([.gap(height: L.pinnedHeaderHeight), .item, .item])
        #expect(pair.views == [nil, S(minY: 5, height: 36), S(minY: 46, height: 36)])
        let expected: CGFloat = 205
        #expect(pair.height == expected)
    }

    @Test func aLoneItemStartsTwoPointsDown() {
        #expect(L.tablist([.item]).views == [S(minY: 2, height: 36)])
    }

    @Test func anEmptyOutlineTakesOnlyTheBottomInset() {
        #expect(L.tablist([]).height == 120)
    }

    @Test func aLeadingAccessoryPlacesTheNextItemBelowIt() {
        #expect(L.tablist([.accessory(height: 28), .item]).views == [S(minY: 0, height: 28), S(minY: 31, height: 36)])
    }

    @Test func boundariesAreTwoAndAHalfOutsideAVisibleRow() {
        #expect(L.tablistRowBoundaryOutset == 2.5)
    }

    @Test func afterAAndBeforeBCoincide() {
        let cue = L.tablist([.gap(height: 2), .item, .item, .accessory(height: 24), .item])
        #expect(cue.views[1]!.maxY + L.tablistRowBoundaryOutset == cue.views[2]!.minY - L.tablistRowBoundaryOutset)
        #expect(cue.views[1]!.minY - L.tablistRowBoundaryOutset == 2.5)
        #expect(cue.views[2]!.maxY + L.tablistRowBoundaryOutset == cue.views[3]!.minY - L.tablistIntercellSpacing / 2)
    }

    @Test func slotsPinnedHeaderItemsDividerNewTabToday() {
        #expect(L.tablistSlots(pinnedItems: 2, todayItems: 1, isPrivate: false) == [.pinnedHeader, .pinnedItem, .pinnedItem, .sectionDivider, .newTab, .todayItem])
    }

    @Test func todayItemsKeepTheDividerWithoutPinnedItems() {
        #expect(L.tablistSlots(pinnedItems: 0, todayItems: 1, isPrivate: false) == [.pinnedHeader, .sectionDivider, .newTab, .todayItem])
    }

    @Test func anEmptyTodayListsNoDividerAndNoHint() {
        #expect(L.tablistSlots(pinnedItems: 2, todayItems: 0, isPrivate: false) == [.pinnedHeader, .pinnedItem, .pinnedItem, .newTab])
    }

    @Test func anEmptySpaceIsHeaderAndNewTab() {
        #expect(L.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: false) == [.pinnedHeader, .newTab])
    }

    struct PrivateList: CustomTestStringConvertible {
        let testDescription: String
        let todayItems: Int
        let slots: [SidebarChromeLayout.TablistSlot]
    }

    @Test(arguments: [
        PrivateList(testDescription: "Two Today items", todayItems: 2, slots: [.privateHeading, .newTab, .todayItem, .todayItem]),
        PrivateList(testDescription: "No Today items", todayItems: 0, slots: [.privateHeading, .newTab]),
    ])
    func privateWindowsListHeadingNewTabToday(_ sample: PrivateList) {
        #expect(L.tablistSlots(pinnedItems: 0, todayItems: sample.todayItems, isPrivate: true) == sample.slots)
    }

    @Test func eachSlotsCell() {
        #expect(T.pinnedHeader.row == .gap(height: 2))
        #expect(T.sectionDivider.row == .accessory(height: 24))
        #expect([T.pinnedItem, .newTab, .todayItem].allSatisfy { $0.row == .item })
        #expect(T.privateHeading.row == .accessory(height: 36))
    }

    @Test func withoutTodayNewTabsVisibleRowIsTheNextItemsFortyOnePointsOn() {
        let lone = L.tablist(L.tablistSlots(pinnedItems: 1, todayItems: 0, isPrivate: false).map(\.row))
        #expect(lone.views[2]!.minY - lone.views[1]!.minY == 41)
    }

    @Test func dividerInsetsAndSpacing() {
        #expect(L.sectionDividerInset == 10)
        #expect(L.sectionDividerSpacing == 8)
    }

    struct DividerScale: CustomTestStringConvertible {
        let testDescription: String
        let scale: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        DividerScale(testDescription: "Retina", scale: 2.0, expected: 0.5),
        DividerScale(testDescription: "One times scale", scale: 1.0, expected: 1.0),
        DividerScale(testDescription: "Three times scale", scale: 3.0, expected: 2.0 / 3),
        DividerScale(testDescription: "Zero scale", scale: 0.0, expected: 1.0),
    ])
    func theBorderIsRoundHalfTimesScaleOverScalePoints(_ sample: DividerScale) {
        let scale = sample.scale
        let expected = sample.expected
        #expect(L.sectionDividerThickness(scale: scale) == expected)
    }

    @Test func theOneOneSeventySequence() {
        let top = L.tablistTop(trayHeight: 0)
        let captured = L.tablistSlots(pinnedItems: 1, todayItems: 4, isPrivate: false).map(\.row)
        let still = L.tablist(captured)
        #expect(still.views.compactMap { $0.map { top + $0.minY } } == [92, 131, 158, 199, 240, 281, 322])
    }

    @Test func rowHeightsAsCaptured() {
        let captured = L.tablistSlots(pinnedItems: 1, todayItems: 4, isPrivate: false).map(\.row)
        let still = L.tablist(captured)
        let starts = zip(captured, still.views).map { row, span -> CGFloat in
            guard let span else { return 0 }
            return row == .item ? span.minY - (L.tablistCellHeight - L.tablistVisibleRowHeight) / 2 : span.minY
        } + [still.height - L.tablistBottomInset]
        #expect(zip(starts, starts.dropFirst()).map { $1 - $0 } == [3, 41, 25, 41, 41, 41, 41, 41])
    }
}
