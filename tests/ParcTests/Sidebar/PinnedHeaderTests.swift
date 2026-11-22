import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar
@testable import ParcSettings

@MainActor
struct PinnedHeaderTests {
    typealias L = SidebarPinnedHeaderLayout
    private let digit: (Int, Bool) -> CGFloat = { value, chips in CGFloat(String(value).count + (chips ? 1 : 0)) * 6 }
    private var mid: CGFloat { SidebarChromeLayout.tablistVisibleRowHeight / 2 }
    private var chevron: CGRect { L.chevronFrame(width: 212) }

    private func summary(width: CGFloat = 212, icons: Int = 4, count: Int = 6, showsIcons: Bool = true) -> L.Summary {
        L.summary(width: width, labelWidth: 36, icons: icons, count: count, showsIcons: showsIcons, countWidth: digit)
    }

    @Test func theHeaderIsAStandardSidebarRow() {
        #expect(L.height == SidebarChromeLayout.tablistVisibleRowHeight)
        #expect(SidebarChromeLayout.TablistSlot.pinnedSectionHeader.row == .item)
    }

    @Test func aSpaceWithPinnedItemsLeadsWithTheHeader() {
        #expect(SidebarChromeLayout.tablistSlots(pinnedItems: 1, todayItems: 0, isPrivate: false, sectionHeader: true)
                == [.pinnedSectionHeader, .pinnedItem, .newTab])
    }

    @Test func aFoldedPinnedKeepsTheHeaderAboveTheDivider() {
        #expect(SidebarChromeLayout.tablistSlots(pinnedItems: 0, todayItems: 1, isPrivate: false, sectionHeader: true)
                == [.pinnedSectionHeader, .sectionDivider, .newTab, .todayItem])
    }

    @Test func privateWindowsNeverGetAPinnedHeader() {
        #expect(SidebarChromeLayout.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: true, sectionHeader: true) == [.privateHeading, .newTab])
    }

    @Test func theChevronSitsInTheRowsCloseButtonColumnCentred() {
        #expect(chevron.midX == 212 - SidebarRowAppearance.closeTrailingInset - SidebarRowAppearance.closeSize / 2)
        #expect(chevron.midY == mid)
    }

    @Test func aRoomyHeaderShowsFourIconsAndTheRestAsACount() {
        let wide = summary()
        #expect(wide.chips.count == 4)
        #expect(wide.hidden == 2)
        #expect(wide.pill == nil)
    }

    @Test func theStackStartsAFixedGapAfterTheLabel() {
        #expect(summary().chips.first?.minX == L.labelInset + 36 + L.summarySpacing)
    }

    @Test func iconsOverlapAtAnEvenPitch() {
        let wide = summary()
        #expect(zip(wide.chips, wide.chips.dropFirst()).allSatisfy { $1.minX - $0.minX == L.chipPitch && $1.minX < $0.maxX })
    }

    @Test func iconsAreCentredOnTheLabelLine() {
        #expect(summary().chips.allSatisfy { $0.midY == mid && $0.width == L.chipSide })
    }

    @Test func theCountFollowsTheLastIcon() {
        let wide = summary()
        #expect(wide.countX == wide.chips[3].maxX + L.countSpacing)
    }

    @Test func theSummaryNeverRunsIntoTheChevron() {
        let wide = summary()
        #expect(wide.countX! + digit(2, true) <= chevron.minX - L.chevronClearance)
    }

    @Test func aNarrowSidebarDropsIconsIntoTheCountInsteadOfColliding() {
        let narrow = summary(width: 148, count: 120)
        let end = (narrow.countX ?? narrow.chips.last?.maxX ?? 0) + (narrow.hidden > 0 ? digit(narrow.hidden, true) : 0)
        #expect(!narrow.chips.isEmpty)
        #expect(narrow.chips.count < 4)
        #expect(end <= L.chevronFrame(width: 148).minX - L.chevronClearance)
    }

    @Test func droppedIconsAreCounted() {
        let narrow = summary(width: 148, count: 120)
        #expect(narrow.hidden == 120 - narrow.chips.count)
    }

    @Test func threePinnedTabsShowThreeIconsAndNoCount() {
        let few = summary(icons: 3, count: 3)
        #expect(few.chips.count == 3)
        #expect(few.hidden == 0)
        #expect(few.countX == nil)
    }

    @Test func aVeryWideSidebarShowsNoMoreThanTheIconsItWasGiven() {
        #expect(summary(width: 600, count: 40).chips.count == 4)
    }

    @Test func iconsOffShowsACountPillAndNoIcons() {
        let pill = summary(showsIcons: false)
        #expect(pill.chips.isEmpty)
        #expect(pill.pill != nil)
        #expect(pill.pill!.width >= pill.pill!.height)
    }

    @Test func thePillIsMeasuredForTheBareCountItDraws() {
        #expect(summary(showsIcons: false).pill!.width == max(L.pillHeight, digit(6, false) + L.pillPadding * 2))
    }

    @Test func thePillSitsWhereTheIconsWouldBe() {
        let pill = summary(showsIcons: false)
        #expect(pill.pill?.minX == L.labelInset + 36 + L.summarySpacing)
        #expect(pill.pill?.midY == mid)
    }

    @Test func iconsOnShowsNoPill() {
        #expect(summary().pill == nil)
    }

    @Test func withNoIconToShowThePillKeepsTheCountVisible() {
        #expect(summary(icons: 0, count: 2).pill != nil)
    }

    @Test func nothingPinnedMeansNothingSummarised() {
        #expect(summary(icons: 0, count: 0) == .init(chips: [], hidden: 0, countX: nil, pill: nil))
    }

    @Test func aSliverOfRoomShowsOnlyTheLabel() {
        #expect(summary(width: 70).chips.isEmpty)
    }

    @Test func iconsSayPlusNAndThePillSaysN() {
        #expect(L.countText(3, chips: true) == "+3")
        #expect(L.countText(3, chips: false) == "3")
    }

    @Test(arguments: [(true, 1, "Pinned, 1 tab"), (true, 6, "Pinned, 6 tabs"), (false, 6, "Pinned")])
    func voiceOverHearsTheCountOnlyWhileFolded(collapsed: Bool, count: Int, expected: String) {
        #expect(L.accessibilityLabel(collapsed: collapsed, count: count) == expected)
    }

    @Test(arguments: [(false, "Collapse Pinned"), (true, "Expand Pinned")])
    func theCommandReadsAsTheActionItWillTake(collapsed: Bool, expected: String) {
        #expect(L.actionTitle(collapsed: collapsed) == expected)
    }

    @Test(arguments: [(true, "Hide Collapsed Pinned Icons"), (false, "Show Collapsed Pinned Icons")])
    func theIconCommandReadsAsTheActionItWillTake(shows: Bool, expected: String) {
        #expect(L.iconsActionTitle(shows: shows) == expected)
    }

    @Test func theChevronTurnsAQuarterWhenFolding() {
        #expect(L.chevronAngle(collapsed: false) == 0)
        #expect(L.chevronAngle(collapsed: true) == -.pi / 2)
    }

    @Test func theOpenChevronPointsDownInTheHeadersFlippedCoordinates() {
        let open = L.chevronPoints(in: chevron, angle: L.chevronAngle(collapsed: false))
        #expect(open.count == 3)
        #expect(open[1].y > open[0].y)
        #expect(abs(open[0].y - open[2].y) < 0.001)
        #expect(abs(open[1].x - chevron.midX) < 0.001)
    }

    @Test func theFoldedChevronPointsToTheTrailingEdge() {
        let shut = L.chevronPoints(in: chevron, angle: L.chevronAngle(collapsed: true))
        #expect(shut[1].x > shut[0].x)
        #expect(abs(shut[0].x - shut[2].x) < 0.001)
        #expect(abs(shut[1].y - chevron.midY) < 0.001)
    }

    @Test func theChevronTurnsOverTwoTenthsOfASecond() {
        #expect(L.chevronDuration == 0.2)
    }

    private func header() -> SidebarPinnedHeaderView {
        SidebarPinnedHeaderView(frame: NSRect(x: 0, y: 0, width: 212, height: L.height))
    }

    @Test func theHeaderIsADisclosureControl() {
        let h = header()
        #expect(h.accessibilityRole() == .disclosureTriangle)
        #expect(h.isAccessibilityElement())
    }

    @Test func thereIsNoPressWithoutAnOwner() {
        #expect(!header().isAccessibilitySelectorAllowed(#selector(NSView.accessibilityPerformPress)))
    }

    @Test func voiceOversPressFoldsOrUnfolds() {
        let h = header()
        var toggles = 0
        h.toggle = { toggles += 1 }
        #expect(h.accessibilityPerformPress())
        #expect(toggles == 1)
        #expect(h.isAccessibilitySelectorAllowed(#selector(NSView.accessibilityPerformPress)))
    }

    @Test func anOpenSectionReadsAsExpanded() {
        let h = header()
        #expect((h.accessibilityValue() as? Int) == 1)
        #expect(h.accessibilityLabel() == "Pinned")
    }

    @Test func aFoldedSectionReadsAsCollapsedWithItsCount() {
        let h = header()
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [UUID(), UUID()]), fallbacks: [:], animated: false)
        #expect((h.accessibilityValue() as? Int) == 0)
        #expect(h.accessibilityLabel() == "Pinned, 6 tabs")
    }

    @Test func theHeaderKnowsWhichTabsItShows() {
        let h = header()
        let first = UUID()
        let hidden = UUID()
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [first, UUID()]), fallbacks: [:], animated: false)
        #expect(h.shows(first))
        #expect(!h.shows(hidden))
    }

    @Test func aFaviconForATabItDoesNotShowIsDropped() {
        let h = header()
        let hidden = UUID()
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [UUID(), UUID()]), fallbacks: [:], animated: false)
        h.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: hidden, url: "https://hidden.invalid")
        #expect(h.needsFavicon(for: hidden, url: "https://hidden.invalid"))
    }

    private func withFavicon(_ first: UUID) -> SidebarPinnedHeaderView {
        let h = header()
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [first, UUID()]), fallbacks: [:], animated: false)
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in NSColor.systemRed.setFill(); rect.fill(); return true }
        h.setFavicon(icon, for: first, url: "https://first.invalid")
        return h
    }

    @Test func aLoadedFaviconIsNotFetchedAgain() {
        let first = UUID()
        #expect(!withFavicon(first).needsFavicon(for: first, url: "https://first.invalid"))
    }

    @Test func aNavigatedTabRefetchesItsFavicon() {
        let first = UUID()
        #expect(withFavicon(first).needsFavicon(for: first, url: "https://first.invalid/moved"))
    }

    @Test func aChangedFaviconIsFetchedAgain() {
        let first = UUID()
        let h = withFavicon(first)
        h.forgetFavicon(for: first)
        #expect(h.needsFavicon(for: first, url: "https://first.invalid"))
    }

    @Test func faviconsForTabsThatLeftTheStackAreReleased() {
        let first = UUID()
        let h = withFavicon(first)
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [UUID()]), fallbacks: [:], animated: false)
        #expect(h.needsFavicon(for: first, url: "https://first.invalid"))
    }

    private func painted() -> (SidebarPinnedHeaderView, L.Summary, (CGFloat, CGFloat) -> CGFloat) {
        let first = UUID()
        let h = header()
        h.update(.init(collapsed: true, showsIcons: true, count: 6, icons: [first, UUID()]), fallbacks: [:], animated: false)
        h.applyStyle(dark: false, accent: nil)
        h.layoutSubtreeIfNeeded()
        let bitmap = h.bitmapImageRepForCachingDisplay(in: h.bounds)!
        h.cacheDisplay(in: h.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / h.bounds.width
        return (h, h.summary!, { x, y in bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0 })
    }

    @Test func theFirstIconsTileIsPainted() {
        let (_, summary, alpha) = painted()
        #expect(alpha(summary.chips[0].minX + 1.5, summary.chips[0].midY) > 0.8)
    }

    @Test func theNextIconCutsACleanRingOutOfTheOneBeneath() {
        let (_, summary, alpha) = painted()
        #expect(alpha(summary.chips[1].minX - L.chipRing / 2, summary.chips[0].midY) < 0.05)
    }

    @Test func theOverlappingIconIsWhole() {
        let (_, summary, alpha) = painted()
        #expect(alpha(summary.chips[1].midX, summary.chips[1].midY) > 0.8)
    }

    @Test func theHeaderIsClearOutsideItsContent() {
        let (_, summary, alpha) = painted()
        #expect(alpha(summary.countX! + 20, 2) < 0.05)
    }

    @Test func turningIconsOffSwapsTheStackForThePill() {
        let (h, _, _) = painted()
        h.update(.init(collapsed: true, showsIcons: false, count: 6, icons: []), fallbacks: [:], animated: false)
        #expect(h.summary?.chips.isEmpty == true)
        #expect(h.summary?.pill != nil)
    }

    private func preferences() -> (UserDefaults, PinnedSectionPreferences) {
        let defaults = TestDefaults("parc.pinned.tests.")!
        return (defaults, PinnedSectionPreferences(defaults: defaults))
    }

    @Test func iconsShowByDefault() {
        let (_, preferences) = preferences()
        #expect(preferences.state.showsCollapsedIcons)
        #expect(!preferences.loadError)
    }

    @Test func turningIconsOffIsRemembered() throws {
        let (defaults, preferences) = preferences()
        try preferences.setShowsCollapsedIcons(false)
        #expect(!PinnedSectionPreferences(defaults: defaults).state.showsCollapsedIcons)
    }

    @Test func anUnreadablePreferenceFallsBackToIconsWithoutOverwriting() {
        let (defaults, _) = preferences()
        defaults.set("garbage", forKey: "parc.pinnedSection.v1")
        let broken = PinnedSectionPreferences(defaults: defaults)
        #expect(broken.loadError)
        #expect(broken.state.showsCollapsedIcons)
    }

    @Test func anUnreadablePreferenceIsNeverClobbered() {
        let (defaults, _) = preferences()
        defaults.set("garbage", forKey: "parc.pinnedSection.v1")
        let broken = PinnedSectionPreferences(defaults: defaults)
        #expect(throws: (any Error).self) { try broken.setShowsCollapsedIcons(false) }
        #expect(defaults.string(forKey: "parc.pinnedSection.v1") == "garbage")
    }

    @Test func anEmptyLibraryCardsHeaderIsAPlainPinnedLabel() {
        let card = header()
        card.update(.init(placeholder: true), fallbacks: [:], animated: false)
        #expect(card.accessibilityRole() == .staticText)
        #expect(card.accessibilityLabel() == "Pinned")
        #expect(card.accessibilityValue() == nil)
        #expect((card.accessibilityHelp() ?? "").isEmpty)
        #expect(card.toolTip == nil)
    }

    @Test func theEmptyCardsLabelLeavesClicksToTheCardAndFoldsNothing() {
        let card = header()
        card.update(.init(placeholder: true), fallbacks: [:], animated: false)
        #expect(card.hitTest(NSPoint(x: 20, y: mid)) == nil)
        #expect(!card.accessibilityPerformPress())
        #expect(card.summary == nil)
    }
}
