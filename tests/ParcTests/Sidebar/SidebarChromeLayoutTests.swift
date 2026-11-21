import CoreGraphics
import Testing
@testable import Parc

struct SidebarChromeLayoutTests {
    typealias L = SidebarChromeLayout
    typealias H = SidebarChromeLayout.SpaceHeader
    typealias E = SidebarChromeLayout.AppTrayEmptyState
    typealias S = SidebarChromeLayout.TablistSpan
    typealias T = SidebarChromeLayout.TablistSlot
    typealias P = SidebarChromeLayout.DockItemPresentation

    private func lights(_ width: CGFloat, _ height: CGFloat = 14) -> CGSize { CGSize(width: width, height: height) }

    private func toolbar(_ width: CGFloat, lights extent: CGFloat?, navigation: Bool = true) -> L.Toolbar {
        L.toolbar(width: width, windowButtons: extent.map { lights($0) }, showsNavigation: navigation)
    }

    @Test func theToolbarCollapsesTheHiddenURLRowBeforeTheSpaceHeaderAndFavorites() {
        #expect(L.headerBottom - L.hiddenAddressHeight(toolbar: true, hasPrompt: false, keyboardSearch: false) == L.headerTop + L.navigationRowHeight)
    }

    @Test func theOrdinarySidebarKeepsItsURLRow() {
        #expect(L.hiddenAddressHeight(toolbar: false, hasPrompt: false, keyboardSearch: false) == 0)
    }

    @Test func aRealPagePromptRetainsItsInteractiveRow() {
        #expect(L.hiddenAddressHeight(toolbar: true, hasPrompt: true, keyboardSearch: false) == 0)
    }

    @Test func keyboardSearchRetainsItsInteractiveRow() {
        #expect(L.hiddenAddressHeight(toolbar: true, hasPrompt: false, keyboardSearch: true) == 0)
    }

    @Test func narrowIsBelowTwoHundredTwelve() {
        #expect(L.narrowWidth == 212)
    }

    @Test func theFieldSitsBelowTheRowAndItsPadding() {
        #expect(L.fieldTop == 46)
        #expect(L.fieldHeight == 36)
    }

    @Test func lightsLeadTheRowAtEightPlusFive() {
        #expect(toolbar(228, lights: 60).windowButtons == CGRect(x: 13, y: 17, width: 60, height: 14))
    }

    @Test func reloadForwardAndBackSitAtTheTrailingOffsets() {
        let regular = toolbar(228, lights: 60)
        #expect(regular.reload == CGRect(x: 190, y: 8, width: 32, height: 32))
        #expect(regular.forward == CGRect(x: 156, y: 8, width: 32, height: 32))
        #expect(regular.back == CGRect(x: 122, y: 8, width: 32, height: 32))
    }

    @Test func theToggleSitsFourPointsAfterTheTrafficLightsAndLevelWithThem() {
        let regular = toolbar(228, lights: 60)
        #expect(regular.toggle == CGRect(x: 77, y: 8, width: 32, height: 32))
        #expect(regular.windowButtons?.midY == regular.toggle?.midY)
        #expect(regular.toggle?.midY == 24)
    }

    @Test func sixPointSpacingBeforeMacOSTwentySixPutsTheToggleAtSeventyOne() {
        let before = toolbar(228, lights: 54)
        #expect(before.windowButtons == CGRect(x: 13, y: 17, width: 54, height: 14))
        #expect(before.toggle?.minX == 71)
        #expect(before.back == toolbar(228, lights: 60).back)
    }

    @Test func theToggleFollowsWiderLights() {
        #expect(toolbar(228, lights: 56).toggle?.minX == 73)
    }

    @Test func withoutTrafficLightsTheToggleLeadsTheStack() {
        let full = toolbar(228, lights: nil)
        #expect(full.toggle?.minX == 13)
        #expect(full.windowButtons == nil)
    }

    @Test func wideSidebarsKeepTheToggleLeadingAndTheRestTrailing() {
        let wide = toolbar(500, lights: 60)
        #expect(wide.reload?.minX == 462)
        #expect(wide.back?.minX == 394)
        #expect(wide.toggle?.minX == 77)
    }

    @Test func aCompactRowKeepsRegularButtons() {
        #expect(toolbar(220, lights: 60).reload?.width == 32)
    }

    @Test func aCrowdedTwoHundredTwelveKeepsEveryControlAtTwentyEightPoints() {
        let crowded = toolbar(212, lights: 56)
        #expect(crowded.toggle == CGRect(x: 73, y: 10, width: 28, height: 28))
        #expect(crowded.back?.minX == 122)
        #expect(crowded.forward?.minX == 150)
        #expect(crowded.reload?.minX == 178)
    }

    @Test func sixtyPointLightsAtTwoHundredTwelveKeepTheToggleAndReloadAtTwentyEight() {
        let crowded = toolbar(212, lights: 60)
        #expect(crowded.toggle == CGRect(x: 77, y: 10, width: 28, height: 28))
        #expect(crowded.reload != nil)
        #expect(crowded.back?.minX == 122)
    }

    @Test func regularReturnsAtTwoHundredSeventeenWithSixtyPointLights() {
        #expect(toolbar(216, lights: 60).back?.width == 28)
        #expect(toolbar(217, lights: 60).back?.width == 32)
    }

    @Test func regularReturnsOnceItFits() {
        #expect(toolbar(214, lights: 56).back?.width == 32)
    }

    @Test func narrowHidesReload() {
        #expect(toolbar(164, lights: 54).reload == nil)
    }

    @Test func narrowPutsBackForwardAndTheToggleInTheMoreSlot() {
        let narrow = toolbar(164, lights: 54)
        #expect(narrow.toggle == CGRect(x: 130, y: 10, width: 28, height: 28))
        #expect(narrow.forward == CGRect(x: 102, y: 10, width: 28, height: 28))
        #expect(narrow.back == CGRect(x: 74, y: 10, width: 28, height: 28))
    }

    @Test func narrowKeepsTheLights() {
        #expect(toolbar(164, lights: 54).windowButtons == toolbar(228, lights: 54).windowButtons)
    }

    @Test func slightlyWiderLightsFitTheNarrowRow() {
        var expected = toolbar(164, lights: 54)
        expected.windowButtons = CGRect(x: 13, y: 17, width: 56, height: 14)
        #expect(toolbar(164, lights: 56) == expected)
    }

    @Test func withSixtyPointLightsForwardYieldsBeforeTheToggle() {
        let narrow = toolbar(164, lights: 60)
        #expect(narrow.forward == nil)
        #expect(narrow.toggle?.minX == 130)
        #expect(narrow.back?.minX == 102)
    }

    @Test func forwardReturnsOnceItFits() {
        #expect(toolbar(211, lights: 60).forward?.minX == 149)
    }

    @Test func aContentToolbarKeepsTheToggleLeadingAndOwnsNavigation() {
        let narrow = toolbar(164, lights: 54, navigation: false)
        #expect(narrow.toggle == CGRect(x: 71, y: 10, width: 28, height: 28))
        #expect(narrow.back == nil)
        #expect(toolbar(228, lights: 54, navigation: false).reload == nil)
    }

    @Test(arguments: stride(from: 164.0, through: 500, by: 1).map { CGFloat($0) })
    func everyToolbarWidthKeepsItsControlsSeparateClearOfTheLightsAndInsideTheTrailingInset(width: CGFloat) {
        for extent in [nil, 48, 51, 54, 56, 60] as [CGFloat?] {
            for height in [14.0, 16] as [CGFloat] {
                let leading = extent.map { 13 + $0 + 4 } ?? 13
                for navigation in [true, false] {
                    let bar = L.toolbar(width: width, windowButtons: extent.map { lights($0, height) }, showsNavigation: navigation)
                    #expect(bar.toggle != nil)
                    let frames = [bar.windowButtons, bar.toggle, bar.back, bar.forward, bar.reload].compactMap { $0 }.sorted { $0.minX < $1.minX }
                    #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.0001 })
                    let shown = [bar.toggle, bar.back, bar.forward, bar.reload].compactMap { $0 }
                    #expect(shown.allSatisfy { $0.minX >= leading })
                    #expect(shown.allSatisfy { $0.maxX <= width - 6 })
                    #expect(navigation == (bar.back != nil))
                    #expect(bar.windowButtons.map { $0.midY == 24 && $0.minX == 13 } ?? (extent == nil))
                }
            }
        }
    }

    @Test func anEmptyTrayPutsTheListAtEightyTwoPlusFive() {
        #expect(L.headerBottom == 82)
        #expect(L.tablistTop(trayHeight: 0) == 87)
    }

    @Test func theListSitsDirectlyBelowAOneOrTwoRowTray() {
        #expect(L.tablistTop(trayHeight: 63) == 145)
        #expect(L.tablistTop(trayHeight: 118) == 200)
    }

    @Test func anUndismissedEmptyTrayShowsTheEmptyState() {
        #expect(L.showsAppTrayEmptyState(favorites: 0, dismissed: false, privateWindow: false))
    }

    @Test(arguments: [(0, true, false), (1, false, false), (0, false, true)])
    func dismissedFavoritesOrPrivateShowNone(favorites: Int, dismissed: Bool, privateWindow: Bool) {
        #expect(!L.showsAppTrayEmptyState(favorites: favorites, dismissed: dismissed, privateWindow: privateWindow))
    }

    @Test func theTraysEmptyStateConstraintIsEightPlusFortySevenPlusEight() {
        #expect(E.minimumHeight == 63)
    }

    @Test func favoritesTakeTheGridsHeight() {
        #expect(L.appTrayHeight(gridHeight: 0, emptyState: nil) == 0)
        #expect(L.appTrayHeight(gridHeight: 63, emptyState: nil) == 63)
        #expect(L.appTrayHeight(gridHeight: 118, emptyState: 102) == 118)
    }

    @Test func theEmptyStateTakesItsFittingHeightAtLeastSixtyThree() {
        #expect(L.appTrayHeight(gridHeight: 0, emptyState: 40) == 63)
        #expect(L.appTrayHeight(gridHeight: 0, emptyState: 102) == 102)
    }

    @Test func theListSitsAtEightyTwoPlusTheEmptyStateWithNoInsetAndAtEightySevenOnceDismissed() {
        #expect(L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: 102)) == 184)
        #expect(L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: 40)) == 145)
        #expect(L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: nil)) == 87)
    }

    @Test func oneUntitledSpaceWithoutAnIconShowsNoHeader() {
        #expect(!H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: false))
    }

    @Test(arguments: [(2, false, false), (1, true, false), (1, false, true)])
    func twoSpacesATitleOrAnIconShowTheHeader(count: Int, titled: Bool, icon: Bool) {
        #expect(H.isShown(spaceCount: count, titled: titled, customIcon: icon, privateWindow: false, showOnSingleUnnamedSpace: false))
    }

    @Test func theSettingShowsItForOneUntitledSpace() {
        #expect(H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: true))
    }

    @Test func neverInAnIncognitoWindowWhateverTheSetting() {
        #expect(!H.isShown(spaceCount: 3, titled: true, customIcon: true, privateWindow: true, showOnSingleUnnamedSpace: true))
    }

    @Test(arguments: [(false, "Show Space Header"), (true, "Hide Space Header")])
    func theToggleReadsAsTheActionItWillTake(setting: Bool, title: String) {
        #expect(H.toggleTitle(spaceCount: 1, titled: false, customIcon: false, showOnSingleUnnamedSpace: setting) == title)
    }

    @Test func noToggleOnceTwoSpacesATitleOrAnIconDecideTheHeader() {
        let titles = [H.toggleTitle(spaceCount: 2, titled: false, customIcon: false, showOnSingleUnnamedSpace: true),
                      H.toggleTitle(spaceCount: 1, titled: true, customIcon: false, showOnSingleUnnamedSpace: false),
                      H.toggleTitle(spaceCount: 1, titled: false, customIcon: true, showOnSingleUnnamedSpace: false),
                      H.toggleTitle(spaceCount: 0, titled: false, customIcon: false, showOnSingleUnnamedSpace: false)]
        #expect(titles.allSatisfy { $0 == nil })
    }

    @Test func thePlaceholderIsSpaceNOrSpace() {
        #expect(H.placeholderTitle(position: 0) == "Space 1")
        #expect(H.placeholderTitle(position: 2) == "Space 3")
        #expect(H.placeholderTitle(position: nil) == "Space")
    }

    @Test func theHeaderConstants() {
        #expect(H.height == 36)
        #expect(H.topPadding == 8)
        #expect(H.inset == 14)
        #expect(H.iconSide == 24)
        #expect(H.spacing == 4)
        #expect(H.fontSize == 13)
    }

    @Test func aShownHeaderTakesTheHeaderInsetToZero() {
        #expect(L.pageTop(trayHeight: 0, spaceHeader: true) == 82)
        #expect(L.pageTop(trayHeight: 0, spaceHeader: false) == 87)
    }

    @Test func twoSpacesWithADismissedEmptyTrayPutTheHeaderAtNinetyAndTheListAtOneTwentySix() {
        #expect(H.top(trayHeight: 0, hasFavorites: false) == 90)
        #expect(L.tablistTop(trayHeight: 0, spaceHeader: true) == 126)
    }

    @Test func oneFavoritesRowPutsTheHeaderAtTheTraysEndAndTheListAtOneEightyOne() {
        #expect(H.top(trayHeight: 63, hasFavorites: true) == 145)
        #expect(L.tablistTop(trayHeight: 63, spaceHeader: true, hasFavorites: true) == 181)
    }

    @Test func theEmptyStatePutsTheHeaderEightBelowItAndTheListAtTwoThirtyTwo() {
        #expect(H.top(trayHeight: 106, hasFavorites: false) == 196)
        #expect(L.tablistTop(trayHeight: 106, spaceHeader: true) == 232)
    }

    @Test func aHiddenHeaderLeavesTheListBelowTheTray() {
        #expect(L.tablistTop(trayHeight: 63, spaceHeader: false, hasFavorites: true) == 145)
    }

    @Test func theIconLeadsAtTheFourteenPointInsetAndTheNameFollowsFourAfterIt() {
        let frames = H.frames(width: 228, icon: true, titleHeight: 16)
        #expect(frames.icon == CGRect(x: 14, y: 6, width: 24, height: 24))
        #expect(frames.title == CGRect(x: 42, y: 10, width: 168, height: 16))
    }

    @Test func withoutAnIconTheNameLeadsTheStack() {
        let plain = H.frames(width: 164, icon: false, titleHeight: 16)
        #expect(plain.icon == nil)
        #expect(plain.title == CGRect(x: 14, y: 10, width: 132, height: 16))
    }

    @Test func aTooNarrowHeaderNeverGivesTheNameANegativeWidth() {
        #expect(H.frames(width: 20, icon: true, titleHeight: 16).title.width == 0)
    }

    @Test func editButtonWidths() {
        #expect(H.editButtonHeight == 24)
        #expect(H.editButtonWidth(shown: false, editing: false) == 0)
        #expect(H.editButtonWidth(shown: false, editing: true) == 0)
        #expect(H.editButtonWidth(shown: true, editing: false) == 24)
        #expect(H.editButtonWidth(shown: true, editing: true) == 30)
        #expect(H.editButtonWidth(shown: true, editing: true, titleWidth: 33.4) == 38)
        #expect(H.editButtonWidth(shown: false, editing: true, titleWidth: 33.4) == 0)
    }

    @Test func atRestTheButtonIsAZeroWidthSlotAtTheTrailingInset() {
        #expect(H.frames(width: 228, icon: true, titleHeight: 16).editButton == CGRect(x: 214, y: 6, width: 0, height: 24))
        #expect(H.frames(width: 164, icon: false, titleHeight: 16).editButton == CGRect(x: 150, y: 6, width: 0, height: 24))
    }

    @Test func shownTheButtonIsTwentyFourWideAndTheNameEndsFourBeforeIt() {
        let shown = H.frames(width: 228, icon: true, titleHeight: 16, editButtonWidth: 24)
        #expect(shown.icon == H.frames(width: 228, icon: true, titleHeight: 16).icon)
        #expect(shown.editButton == CGRect(x: 190, y: 6, width: 24, height: 24))
        #expect(shown.title == CGRect(x: 42, y: 10, width: 144, height: 16))
    }

    @Test func editingTheButtonIsThirtyWideAndTheNameEndsBeforeIt() {
        let editing = H.frames(width: 228, icon: false, titleHeight: 16, editButtonWidth: 30)
        #expect(editing.editButton == CGRect(x: 184, y: 6, width: 30, height: 24))
        #expect(editing.title == CGRect(x: 14, y: 10, width: 166, height: 16))
    }

    @Test(arguments: [(false, false, true, false), (false, true, true, true), (true, false, true, true), (true, true, false, false), (false, true, false, false)])
    func theEditButtonShowsOnHoverOrEditingAndNeverWithoutTheHeaderButtonsGate(editing: Bool, hovered: Bool, gate: Bool, shows: Bool) {
        #expect(H.showsEditButton(editing: editing, hovered: hovered, canShowHeaderButtons: gate) == shows)
    }

    @Test func hoverInWaitsATenthOfASecondAndHoverOutDoesNot() {
        #expect(H.editButtonHoverDelay(hovered: true) == 0.1)
        #expect(H.editButtonHoverDelay(hovered: false) == 0)
        #expect(H.editButtonFadeDuration == 0.1)
    }

    @Test(arguments: [(228.0, 150.0), (164.0, 128.0), (20.0, 0.0)])
    func emptyStateTextWrapsAtOneHundredFiftyOrTheCardsPaddedWidth(width: CGFloat, expected: CGFloat) {
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

    @Test func theOutlineConstants() {
        #expect(L.tablistCellHeight == 40)
        #expect(L.tablistVisibleRowHeight == 36)
        #expect(L.tablistIntercellSpacing == 1)
        #expect(L.tablistIndentation == 16)
        #expect(L.tablistBottomInset == 120)
        #expect(L.pinnedHeaderHeight == 2)
        #expect(L.sectionDividerHeight == 24)
    }

    @Test func itemsFollowTheTwoPointPinnedHeader() {
        let pair = L.tablist([.gap(height: L.pinnedHeaderHeight), .item, .item])
        #expect(pair.views == [nil, S(minY: 5, height: 36), S(minY: 46, height: 36)])
        let expected: CGFloat = 205
        #expect(pair.height == expected)
    }

    @Test func aLoneItemAnAnEmptyOutlineAndAnAccessoryFirst() {
        #expect(L.tablist([.item]).views == [S(minY: 2, height: 36)])
        #expect(L.tablist([]).height == 120)
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

    @Test func privateWindowsListHeadingNewTabToday() {
        #expect(L.tablistSlots(pinnedItems: 0, todayItems: 2, isPrivate: true) == [.privateHeading, .newTab, .todayItem, .todayItem])
        #expect(L.tablistSlots(pinnedItems: 0, todayItems: 0, isPrivate: true) == [.privateHeading, .newTab])
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

    @Test(arguments: [(2.0, 0.5), (1.0, 1.0), (3.0, 2.0 / 3), (0.0, 1.0)])
    func theBorderIsRoundHalfTimesScaleOverScalePoints(scale: CGFloat, expected: CGFloat) {
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

    @Test func theDockButtonsAndStrip() {
        #expect(L.dockTrailingButton(width: 228, height: 800) == CGRect(x: 188, y: 759, width: 32, height: 32))
        #expect(L.dockLeadingButton(height: 800) == CGRect(x: 8, y: 759, width: 32, height: 32))
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

    @Test(arguments: [(136.0, false), (135.0, true)])
    func belowTwentyTwoTheItemsBecomeDots(width: CGFloat, compact: Bool) {
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

    @Test(arguments: stride(from: 30.0, through: 400, by: 7).map { CGFloat($0) })
    func theDockLayoutKeepsItsInvariantsAtEveryWidth(width: CGFloat) {
        for itemCount in 1...40 {
            for focus in [nil, 0, itemCount / 2, itemCount - 1] as [Int?] {
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
        }
    }

    @Test(arguments: [(false, "circle.fill", true), (false, "circle", true), (true, "circle", false), (false, "star", false)])
    func theIconlessSentinelsAndCustomIcons(custom: Bool, symbol: String, iconless: Bool) {
        #expect(L.dockIconless(hasCustomIcon: custom, symbol: symbol) == iconless)
    }

    @Test(arguments: [(1, false, false, false), (0, false, false, false), (1, true, false, true), (2, false, false, true), (1, false, true, true)])
    func theDockShowsSpacesOnlyWhenItHasMoreThanOneIconlessSpace(count: Int, custom: Bool, creating: Bool, shows: Bool) {
        #expect(L.dockShowsSpaces(count: count, anyCustomIcon: custom, creating: creating) == shows)
    }

    @Test func iconlessSpacesAreEightPointDots() {
        #expect(L.dockItemPresentation(compact: false, selection: 1, highlighted: false, dark: false, iconless: true) == P.dot(side: 8, alpha: 1))
        #expect(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: true, iconless: true) == P.dot(side: 8, alpha: 0.35))
        #expect(L.dockItemPresentation(compact: false, selection: 0, highlighted: true, dark: false, iconless: true) == P.dot(side: 8, alpha: 0.7))
    }

    @Test func compactDotsAreFourPointsLightOrDark() {
        #expect(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: false) == P.dot(side: 4, alpha: 0.5))
        #expect(L.dockItemPresentation(compact: true, selection: 0, highlighted: false, dark: true) == P.dot(side: 4, alpha: 0.35))
    }

    @Test func aSelectedOrHighlightedDotShowsItsIcon() {
        #expect(L.dockItemPresentation(compact: true, selection: 1, highlighted: false, dark: false) == P.icon(active: 1, inactive: 0))
        #expect(L.dockItemPresentation(compact: true, selection: 0, highlighted: true, dark: true) == P.icon(active: 0.7, inactive: 0))
    }

    @Test func restingHighlightedAndSelectedIcons() {
        #expect(L.dockItemPresentation(compact: false, selection: 0, highlighted: false, dark: false) == P.icon(active: 0, inactive: 0.5))
        #expect(L.dockItemPresentation(compact: false, selection: 0, highlighted: false, dark: true) == P.icon(active: 0, inactive: 0.35))
        #expect(L.dockItemPresentation(compact: false, selection: 0, highlighted: true, dark: false) == P.icon(active: 0.7, inactive: 0))
        #expect(L.dockItemPresentation(compact: false, selection: 1, highlighted: true, dark: false) == P.icon(active: 1, inactive: 0))
    }

    @Test func selectionCrossFadesTheIcons() {
        #expect(L.dockItemPresentation(compact: false, selection: 0.5, highlighted: false, dark: false) == P.icon(active: 0.5, inactive: 0.25))
    }
}
