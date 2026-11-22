import AppKit
import Testing
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary
@testable import ParcSidebar

@MainActor
struct SpaceManagerCardTestsDropTests {
    private typealias Layout = SpaceManagerCardTestsSupport.Layout
    private typealias Cards = SpaceManagerCardTestsSupport.Cards

    private func withExtras(_ cards: Cards) -> (BrowserTab, BrowserTab, BrowserState) {
        var archived = cards.tab("archived", .today)
        archived.archivedAt = Date()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        let elsewhere = Cards.tab("elsewhere", .today, in: second)
        var otherProfile = cards.tab("other-profile", .today)
        otherProfile.profileID = UUID()
        var targets = cards.state
        targets.tabs += [archived, elsewhere, otherProfile]
        return (elsewhere, archived, targets)
    }

    @Test func clearArchivesOnlyTheCardSpacesLiveTodayTabs() {
        let cards = Cards()
        let (_, _, targets) = withExtras(cards)
        #expect(SpaceClearToday.ids(in: targets, spaceID: cards.first.id, profileID: cards.first.profileID) == [cards.today.id, cards.later.id])
    }

    @Test func anotherCardsClearTargetsItsOwnSpace() {
        let cards = Cards()
        let (elsewhere, _, targets) = withExtras(cards)
        #expect(SpaceClearToday.ids(in: targets, spaceID: elsewhere.spaceID, profileID: elsewhere.profileID) == [elsewhere.id])
    }

    @Test func aDropBelowTheTodayRowsLandsAtTheEndOfToday() {
        let cards = Cards()
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }
        let lastToday = rows.first { $0.tabID == cards.later.id }!
        cards.drop(cards.later.id, at: cards.sidebar.convert(NSPoint(x: lastToday.bounds.midX, y: lastToday.bounds.maxY + 30), from: lastToday))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
        #expect(cards.commits[0].1 == nil)
    }

    @Test func aDropOnThePinnedRowStaysInPinned() {
        let cards = Cards()
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }
        let pinnedRow = rows.first { $0.tabID == cards.pinned.id }!
        cards.drop(cards.later.id, at: cards.sidebar.convert(NSPoint(x: pinnedRow.bounds.midX, y: pinnedRow.bounds.minY + 4), from: pinnedRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .pinned)
    }

    private func todayless(_ cards: Cards) -> BrowserTab {
        let extra = cards.tab("extra", .pinned)
        var state = cards.state
        state.tabs = [cards.pinned, extra]
        cards.reload(state)
        return extra
    }

    @Test func aCardWithAnEmptyTodayHasNoDividerAndNoClear() {
        let cards = Cards()
        _ = todayless(cards)
        #expect(!sidebarDescendants(cards.sidebar).contains { ($0 as? ActionButton)?.identifier?.rawValue == "sidebarClear" })
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarHairline })
    }

    @Test func withoutADividerADropBelowTheCardsLastRowLandsInToday() {
        let cards = Cards()
        let extra = todayless(cards)
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.filter { [cards.pinned.id, extra.id].contains($0.tabID) }
        let lastRow = rows.max { $0.convert($0.bounds, to: cards.sidebar).maxY < $1.convert($1.bounds, to: cards.sidebar).maxY }!
        cards.drop(extra.id, at: cards.sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY + 30), from: lastRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
        #expect(cards.commits[0].1 == nil)
    }

    @Test func withoutADividerADropOnTheLastPinnedRowStaysInPinned() {
        let cards = Cards()
        let extra = todayless(cards)
        let rows = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarTabRow }.filter { [cards.pinned.id, extra.id].contains($0.tabID) }
        let lastRow = rows.max { $0.convert($0.bounds, to: cards.sidebar).maxY < $1.convert($1.bounds, to: cards.sidebar).maxY }!
        cards.drop(extra.id, at: cards.sidebar.convert(NSPoint(x: lastRow.bounds.midX, y: lastRow.bounds.maxY - 4), from: lastRow))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .pinned)
    }

    private func emptyCard(_ cards: Cards) -> (NSRect, BrowserTab) {
        let favorite = cards.tab("favorite", .favorite)
        var empty = cards.state
        empty.tabs = [favorite]
        cards.reload(empty)
        let outline = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        return (outline.convert(outline.rows[0].frame, to: cards.sidebar), favorite)
    }

    @Test func anEmptyCardListsOnlyItsPinnedHeaderWithNoDivider() {
        let cards = Cards()
        let (headerRow, _) = emptyCard(cards)
        let outline = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarOutlineView }.first!
        #expect(cards.header.isHidden)
        #expect(outline.rows.count == 1)
        #expect(headerRow.height == SidebarChromeLayout.tablistCellHeight + SidebarChromeLayout.tablistIntercellSpacing)
        #expect(!sidebarDescendants(cards.sidebar).contains { $0 is SidebarHairline })
    }

    @Test func theEmptyCardsPinnedHeaderIsAPlainLabelThatLeavesClicksToTheCard() {
        let cards = Cards()
        _ = emptyCard(cards)
        let pinnedHeader = sidebarDescendants(cards.sidebar).compactMap { $0 as? SidebarPinnedHeaderView }.first
        #expect(pinnedHeader?.content.placeholder == true)
        #expect(pinnedHeader?.accessibilityRole() == .staticText)
        #expect(pinnedHeader?.hitTest(NSPoint(x: 5, y: 5)) == nil)
    }

    struct PinnedDropPosition: CustomTestStringConvertible {
        let testDescription: String
        let fraction: Double
        let pinned: Bool
    }

    @Test(arguments: [
        PinnedDropPosition(testDescription: "Two points into the header", fraction: 2.0, pinned: true),
        PinnedDropPosition(testDescription: "Middle of the header", fraction: 0.5, pinned: true),
    ])
    func anEmptyCardsWholePinnedHeaderTakesPinnedDrops(_ sample: PinnedDropPosition) {
        let fraction = sample.fraction
        let pinned = sample.pinned
        let cards = Cards()
        let (headerRow, favorite) = emptyCard(cards)
        cards.drop(favorite.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: fraction == 2 ? headerRow.minY + 2 : headerRow.midY))
        #expect(cards.commits.count == 1)
        #expect((cards.commits[0].0.section == .pinned) == pinned)
    }

    @Test func belowAnEmptyCardsPinnedHeaderIsToday() {
        let cards = Cards()
        let (headerRow, favorite) = emptyCard(cards)
        cards.drop(favorite.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: headerRow.maxY + 10))
        #expect(cards.commits.count == 1)
        #expect(cards.commits[0].0.section == .today)
        #expect(cards.commits[0].0.spaceID == cards.first.id)
    }

    @Test func aCardTakesNoFavoriteDropAboveItsShownHeader() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var trayless = cards.state
        trayless.spaces.append(second)
        trayless.tabs = [cards.pinned]
        cards.reload(trayless)
        let header = cards.header
        cards.drop(cards.pinned.id, at: NSPoint(x: cards.sidebar.bounds.midX, y: header.frame.minY / 2))
        #expect(cards.manager.sidebar(for: cards.first.id) === cards.sidebar)
        #expect(!header.isHidden)
        #expect(header.frame.minY > 0)
        #expect(!cards.commits.contains { $0.0.section == .favorite })
    }

    @Test func withTwoSpacesEveryCardShowsItsHeaderItsPaddingBelowTheTop() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var pair = cards.state
        pair.spaces.append(second)
        pair.tabs.append(Cards.tab("elsewhere", .today, in: second))
        cards.reload(pair)
        let headers = pair.spaces.map { space in sidebarDescendants(cards.manager.sidebar(for: space.id)!).compactMap { $0 as? SidebarSpaceHeaderView }.first! }
        #expect(headers.allSatisfy { !$0.isHidden && $0.frame.minY == SidebarChromeLayout.SpaceHeader.topPadding })
        #expect(zip(pair.spaces, headers).allSatisfy { cards.manager.anchor(for: $0.id) === $1 })
    }

    @Test func theSecondCardFollowsOneGapLaterAndTheAddCircleMovesAfterIt() {
        let cards = Cards()
        let second = BrowserSpace(id: UUID(), name: "Second", symbol: "star.fill", color: "AABBCC", profileID: cards.first.profileID)
        var pair = cards.state
        pair.spaces.append(second)
        pair.tabs.append(Cards.tab("elsewhere", .today, in: second))
        cards.reload(pair)
        let secondCard = cards.manager.sidebar(for: second.id)!.superview!.superview!
        let add = sidebarDescendants(cards.manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }!
        #expect(secondCard.frame == Layout.cardFrame(index: 1, height: cards.manager.bounds.height))
        #expect(add.frame.minX == secondCard.frame.maxX + 24 + 9)
    }
}
