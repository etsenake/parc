import CoreGraphics
import Testing
@testable import Parc
@testable import ParcSidebar

struct SidebarChromeLayoutTestsHeaderTests {
    private typealias L = SidebarChromeLayoutTestsSupport.L
    private typealias E = SidebarChromeLayoutTestsSupport.E

    private typealias H = SidebarChromeLayout.SpaceHeader

    @Test func anEmptyTrayPutsTheListAtEightyTwoPlusFive() {
        #expect(L.headerBottom == 82)
        #expect(L.tablistTop(trayHeight: 0) == 87)
    }

    struct TrayHeight: CustomTestStringConvertible {
        let testDescription: String
        let height: CGFloat
        let listTop: CGFloat
    }

    @Test(arguments: [
        TrayHeight(testDescription: "One row", height: 63, listTop: 145),
        TrayHeight(testDescription: "Two rows", height: 118, listTop: 200),
    ])
    func theListSitsDirectlyBelowAOneOrTwoRowTray(_ sample: TrayHeight) {
        #expect(L.tablistTop(trayHeight: sample.height) == sample.listTop)
    }

    @Test func anUndismissedEmptyTrayShowsTheEmptyState() {
        #expect(L.showsAppTrayEmptyState(favorites: 0, dismissed: false, privateWindow: false))
    }

    struct EmptyStateSuppression: CustomTestStringConvertible {
        let testDescription: String
        let favorites: Int
        let dismissed: Bool
        let privateWindow: Bool
    }

    @Test(arguments: [
        EmptyStateSuppression(testDescription: "Dismissed", favorites: 0, dismissed: true, privateWindow: false),
        EmptyStateSuppression(testDescription: "Has a Favorite", favorites: 1, dismissed: false, privateWindow: false),
        EmptyStateSuppression(testDescription: "Private window", favorites: 0, dismissed: false, privateWindow: true),
    ])
    func dismissedFavoritesOrPrivateShowNone(_ sample: EmptyStateSuppression) {
        let favorites = sample.favorites
        let dismissed = sample.dismissed
        let privateWindow = sample.privateWindow
        #expect(!L.showsAppTrayEmptyState(favorites: favorites, dismissed: dismissed, privateWindow: privateWindow))
    }

    @Test func theTraysEmptyStateConstraintIsEightPlusFortySevenPlusEight() {
        #expect(E.minimumHeight == 63)
    }

    struct FavoriteGridHeight: CustomTestStringConvertible {
        let testDescription: String
        let height: CGFloat
        let emptyState: CGFloat?
        let expected: CGFloat
    }

    @Test(arguments: [
        FavoriteGridHeight(testDescription: "Empty grid", height: 0, emptyState: nil, expected: 0),
        FavoriteGridHeight(testDescription: "One row", height: 63, emptyState: nil, expected: 63),
        FavoriteGridHeight(testDescription: "Two rows with an empty-state height", height: 118, emptyState: 102, expected: 118),
    ])
    func favoritesTakeTheGridsHeight(_ sample: FavoriteGridHeight) {
        #expect(L.appTrayHeight(gridHeight: sample.height, emptyState: sample.emptyState) == sample.expected)
    }

    struct EmptyStateHeight: CustomTestStringConvertible {
        let testDescription: String
        let height: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        EmptyStateHeight(testDescription: "Below minimum", height: 40, expected: 63),
        EmptyStateHeight(testDescription: "Above minimum", height: 102, expected: 102),
    ])
    func theEmptyStateTakesItsFittingHeightAtLeastSixtyThree(_ sample: EmptyStateHeight) {
        #expect(L.appTrayHeight(gridHeight: 0, emptyState: sample.height) == sample.expected)
    }

    struct TrayEmptyState: CustomTestStringConvertible {
        let testDescription: String
        let height: CGFloat?
        let listTop: CGFloat
    }

    @Test(arguments: [
        TrayEmptyState(testDescription: "102-point empty state", height: 102, listTop: 184),
        TrayEmptyState(testDescription: "40-point empty state", height: 40, listTop: 145),
        TrayEmptyState(testDescription: "Dismissed", height: nil, listTop: 87),
    ])
    func theListSitsAtEightyTwoPlusTheEmptyStateWithNoInsetAndAtEightySevenOnceDismissed(_ sample: TrayEmptyState) {
        #expect(L.tablistTop(trayHeight: L.appTrayHeight(gridHeight: 0, emptyState: sample.height)) == sample.listTop)
    }

    @Test func oneUntitledSpaceWithoutAnIconShowsNoHeader() {
        #expect(!H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: false))
    }

    struct HeaderVisibility: CustomTestStringConvertible {
        let testDescription: String
        let count: Int
        let titled: Bool
        let icon: Bool
    }

    @Test(arguments: [
        HeaderVisibility(testDescription: "Two Spaces", count: 2, titled: false, icon: false),
        HeaderVisibility(testDescription: "Named Space", count: 1, titled: true, icon: false),
        HeaderVisibility(testDescription: "Custom icon", count: 1, titled: false, icon: true),
    ])
    func twoSpacesATitleOrAnIconShowTheHeader(_ sample: HeaderVisibility) {
        let count = sample.count
        let titled = sample.titled
        let icon = sample.icon
        #expect(H.isShown(spaceCount: count, titled: titled, customIcon: icon, privateWindow: false, showOnSingleUnnamedSpace: false))
    }

    @Test func theSettingShowsItForOneUntitledSpace() {
        #expect(H.isShown(spaceCount: 1, titled: false, customIcon: false, privateWindow: false, showOnSingleUnnamedSpace: true))
    }

    @Test func neverInAnIncognitoWindowWhateverTheSetting() {
        #expect(!H.isShown(spaceCount: 3, titled: true, customIcon: true, privateWindow: true, showOnSingleUnnamedSpace: true))
    }

    struct ToggleSetting: CustomTestStringConvertible {
        let testDescription: String
        let setting: Bool
        let title: String
    }

    @Test(arguments: [
        ToggleSetting(testDescription: "Header hidden", setting: false, title: "Show Space Header"),
        ToggleSetting(testDescription: "Header shown", setting: true, title: "Hide Space Header"),
    ])
    func theToggleReadsAsTheActionItWillTake(_ sample: ToggleSetting) {
        let setting = sample.setting
        let title = sample.title
        #expect(H.toggleTitle(spaceCount: 1, titled: false, customIcon: false, showOnSingleUnnamedSpace: setting) == title)
    }

    struct HeaderWithoutToggle: CustomTestStringConvertible {
        let testDescription: String
        let spaceCount: Int
        let titled: Bool
        let customIcon: Bool
        let setting: Bool
    }

    @Test(arguments: [
        HeaderWithoutToggle(testDescription: "Two Spaces", spaceCount: 2, titled: false, customIcon: false, setting: true),
        HeaderWithoutToggle(testDescription: "Titled Space", spaceCount: 1, titled: true, customIcon: false, setting: false),
        HeaderWithoutToggle(testDescription: "Custom icon", spaceCount: 1, titled: false, customIcon: true, setting: false),
        HeaderWithoutToggle(testDescription: "No Spaces", spaceCount: 0, titled: false, customIcon: false, setting: false),
    ])
    func noToggleOnceTwoSpacesATitleOrAnIconDecideTheHeader(_ sample: HeaderWithoutToggle) {
        #expect(H.toggleTitle(spaceCount: sample.spaceCount, titled: sample.titled, customIcon: sample.customIcon, showOnSingleUnnamedSpace: sample.setting) == nil)
    }

    struct PlaceholderPosition: CustomTestStringConvertible {
        let testDescription: String
        let position: Int?
        let title: String
    }

    @Test(arguments: [
        PlaceholderPosition(testDescription: "First Space", position: 0, title: "Space 1"),
        PlaceholderPosition(testDescription: "Third Space", position: 2, title: "Space 3"),
        PlaceholderPosition(testDescription: "Unknown position", position: nil, title: "Space"),
    ])
    func thePlaceholderIsSpaceNOrSpace(_ sample: PlaceholderPosition) {
        #expect(H.placeholderTitle(position: sample.position) == sample.title)
    }

    @Test func theHeaderHasItsHeightAndVerticalPadding() {
        #expect(H.height == 36)
        #expect(H.topPadding == 8)
    }

    @Test func theHeaderHasItsHorizontalInset() {
        #expect(H.inset == 14)
    }

    @Test func theHeaderIconHasItsSideAndSpacing() {
        #expect(H.iconSide == 24)
        #expect(H.spacing == 4)
    }

    @Test func theHeaderTitleUsesThirteenPoints() {
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

    @Test func theEditButtonIsTwentyFourPointsHigh() {
        #expect(H.editButtonHeight == 24)
    }

    struct EditButtonWidth: CustomTestStringConvertible {
        let testDescription: String
        let shown: Bool
        let editing: Bool
        let titleWidth: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        EditButtonWidth(testDescription: "Hidden at rest", shown: false, editing: false, titleWidth: 0, expected: 0),
        EditButtonWidth(testDescription: "Hidden while editing", shown: false, editing: true, titleWidth: 0, expected: 0),
        EditButtonWidth(testDescription: "Visible at rest", shown: true, editing: false, titleWidth: 0, expected: 24),
        EditButtonWidth(testDescription: "Visible while editing", shown: true, editing: true, titleWidth: 0, expected: 30),
        EditButtonWidth(testDescription: "Visible with a wide edit title", shown: true, editing: true, titleWidth: 33.4, expected: 38),
        EditButtonWidth(testDescription: "Hidden with a wide edit title", shown: false, editing: true, titleWidth: 33.4, expected: 0),
    ])
    func editButtonWidths(_ sample: EditButtonWidth) {
        #expect(H.editButtonWidth(shown: sample.shown, editing: sample.editing, titleWidth: sample.titleWidth) == sample.expected)
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

    struct EditButtonVisibility: CustomTestStringConvertible {
        let testDescription: String
        let editing: Bool
        let hovered: Bool
        let gate: Bool
        let shows: Bool
    }

    @Test(arguments: [
        EditButtonVisibility(testDescription: "Idle", editing: false, hovered: false, gate: true, shows: false),
        EditButtonVisibility(testDescription: "Hovered", editing: false, hovered: true, gate: true, shows: true),
        EditButtonVisibility(testDescription: "Editing", editing: true, hovered: false, gate: true, shows: true),
        EditButtonVisibility(testDescription: "Gate closed while editing", editing: true, hovered: true, gate: false, shows: false),
        EditButtonVisibility(testDescription: "Gate closed while hovered", editing: false, hovered: true, gate: false, shows: false),
    ])
    func theEditButtonShowsOnHoverOrEditingAndNeverWithoutTheHeaderButtonsGate(_ sample: EditButtonVisibility) {
        let editing = sample.editing
        let hovered = sample.hovered
        let gate = sample.gate
        let shows = sample.shows
        #expect(H.showsEditButton(editing: editing, hovered: hovered, canShowHeaderButtons: gate) == shows)
    }

    @Test func hoverInWaitsATenthOfASecond() {
        #expect(H.editButtonHoverDelay(hovered: true) == 0.1)
    }

    @Test func hoverOutDoesNotWait() {
        #expect(H.editButtonHoverDelay(hovered: false) == 0)
    }

    @Test func theEditButtonFadesForATenthOfASecond() {
        #expect(H.editButtonFadeDuration == 0.1)
    }
}
