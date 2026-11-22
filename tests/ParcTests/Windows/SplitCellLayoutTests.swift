import AppKit
import Testing
@testable import Parc
@testable import ParcKit
@testable import ParcSidebar

struct SplitCellLayoutTests {
    private typealias L = SidebarSplitCellLayout

    private static let row = NSRect(x: 0, y: 0, width: 212, height: 36)

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    private static func rgba(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }

    @Test func theCellMetricsAreFixed() {
        #expect(L.containerInset == 4 && L.childPadding == 4 && L.collapseWidth == 60)
        #expect(L.childHeight == 28 && L.separatorHeight == 16)
        #expect(L.closeSize == 24 && L.closeTrailingInset == 6 && L.extendedTrailingInset == 34)
        #expect(L.infoLeadingInset == 6 && L.infoTitleInset == 36 && L.infoTrailingInset == 18)
        #expect(L.countIconSize == 16 && L.countIconCornerRadius == 4)
    }

    @Test func atRestTwoChildrenShareTheRowAroundTheirPadding() {
        let rest = L.layout(in: Self.row, childCount: 2, showsClose: false, pixel: 0.5)
        #expect(rest.children == [NSRect(x: 4, y: 4, width: 100, height: 28), NSRect(x: 108, y: 4, width: 100, height: 28)])
    }

    @Test func atRestOneDevicePixelSeparatorSitsCentredInTheGap() {
        let rest = L.layout(in: Self.row, childCount: 2, showsClose: false, pixel: 0.5)
        #expect(rest.separators.count == 1)
        #expect(Self.near(rest.separators[0].minX, 105.75))
        #expect(rest.separators[0].width == 0.5 && rest.separators[0].minY == 10 && rest.separators[0].height == 16)
    }

    @Test func atRestThereIsNoCloseAndACustomTitleEndsTenInside() {
        let rest = L.layout(in: Self.row, childCount: 2, showsClose: false, pixel: 0.5)
        #expect(rest.close == nil)
        #expect(rest.infoTitleTrailing == 202)
    }

    @Test func aHoveredSplitPlacesCloseSixPointsInsideTheTrailingEdge() {
        #expect(L.layout(in: Self.row, childCount: 2, showsClose: true).close == NSRect(x: 182, y: 6, width: 24, height: 24))
    }

    @Test func onlyTheLastChildYieldsToClose() {
        let hovered = L.layout(in: Self.row, childCount: 2, showsClose: true)
        #expect(hovered.children[0].width == 100)
        #expect(hovered.children[1].minX == 108 && hovered.children[1].maxX == 178)
    }

    @Test func theSeparatorFollowsTheFirstChildWhenCloseIsShown() {
        #expect(Self.near(L.layout(in: Self.row, childCount: 2, showsClose: true).separators[0].minX, 105.5))
    }

    @Test func aCustomTitleEndsEighteenBeforeClose() {
        #expect(L.layout(in: Self.row, childCount: 2, showsClose: true).infoTitleTrailing == 164)
    }

    @Test func narrowChildrenWithCloseShareTheExtendedWidth() {
        let collapsed = L.layout(in: NSRect(x: 0, y: 0, width: 140, height: 36), childCount: 3, showsClose: true)
        let extended = (140.0 - 4 - 34 - 8) / 3
        #expect(collapsed.children.allSatisfy { Self.near($0.width, extended) })
        #expect(Self.near(collapsed.children[2].maxX, 106))
    }

    @Test func narrowChildrenAtRestShareTheDefaultWidth() {
        let narrowRest = L.layout(in: NSRect(x: 0, y: 0, width: 140, height: 36), childCount: 3, showsClose: false)
        #expect(narrowRest.children.allSatisfy { Self.near($0.width, (140.0 - 8 - 8) / 3) })
        #expect(narrowRest.separators.count == 2)
    }

    @Test func aDefaultWidthOfExactlySixtyTakesTheExtendedWidth() {
        let boundary = L.layout(in: NSRect(x: 0, y: 0, width: 132, height: 36), childCount: 2, showsClose: true)
        #expect(boundary.children[0].width == (132.0 - 4 - 34 - 4) / 2)
    }

    @Test func aboveSixtyTheFirstChildKeepsItsDefaultWidth() {
        let wider = L.layout(in: NSRect(x: 0, y: 0, width: 134, height: 36), childCount: 2, showsClose: true)
        #expect(wider.children[0].width == 61)
        #expect(wider.children[1].maxX == 100)
    }

    @Test func noChildrenMeansNoFrames() {
        #expect(L.layout(in: Self.row, childCount: 0, showsClose: true).children.isEmpty)
    }

    @Test func oneChildMeansNoSeparator() {
        #expect(L.layout(in: Self.row, childCount: 1, showsClose: false).separators.isEmpty)
    }

    struct CloseCase: Sendable, CustomTestStringConvertible {
        let today: Bool
        let current: Bool
        let customInfo: Bool
        let splitHasClose: Bool
        let childClose: Bool
        let name: String
        var testDescription: String { name }
    }

    @Test(arguments: [
        CloseCase(today: true, current: true, customInfo: false, splitHasClose: false, childClose: true, name: "current Today split"),
        CloseCase(today: true, current: false, customInfo: false, splitHasClose: true, childClose: false, name: "other Today split"),
        CloseCase(today: false, current: true, customInfo: false, splitHasClose: true, childClose: false, name: "pinned split"),
        CloseCase(today: true, current: true, customInfo: true, splitHasClose: true, childClose: false, name: "custom info")
    ])
    func closeBelongsToTheChildOrToTheSplit(_ c: CloseCase) {
        #expect(L.splitHasClose(today: c.today, current: c.current, customInfo: c.customInfo) == c.splitHasClose)
        #expect(L.childCloseAvailable(today: c.today, current: c.current, customInfo: c.customInfo) == c.childClose)
    }

    @Test(arguments: [true, false])
    func aTodaySplitCloses(_ presented: Bool) {
        #expect(L.closeAction(today: true, anyChildPresented: presented) == .close)
    }

    @Test func aPinnedSplitWithAPresentedChildDeselects() {
        #expect(L.closeAction(today: false, anyChildPresented: true) == .deselect)
    }

    @Test func aPinnedSplitWithNothingPresentedCloses() {
        #expect(L.closeAction(today: false, anyChildPresented: false) == .close)
    }

    @Test func closeTooltipsNeverArchiveInAPrivateWindow() {
        #expect(L.closeTitle(.close, privateWindow: false) == "Archive this item")
        #expect(L.closeTitle(.deselect, privateWindow: false) == "Close this item")
        #expect(L.closeTitle(.close, privateWindow: true) == "Close this item")
    }

    @Test(arguments: [(nil as String?, false, false), ("", false, false)])
    func noTitleOrIconKeepsChildItems(_ title: String?, _ hasIcon: Bool, _ editing: Bool) {
        #expect(!L.usesCustomInfo(title: title, hasIcon: hasIcon, editing: editing))
    }

    @Test(arguments: [("Work" as String?, false, false), (nil as String?, true, false), (nil as String?, false, true)])
    func aTitleAnIconOrEditingUsesCustomInfo(_ title: String?, _ hasIcon: Bool, _ editing: Bool) {
        #expect(L.usesCustomInfo(title: title, hasIcon: hasIcon, editing: editing))
    }

    @Test func theDefaultTitleCountsTheTabs() {
        #expect(L.defaultTitle(count: 3) == "3 Tabs")
    }

    @Test func theSeparatorIsFifteenPercentInkInLightAndDark() {
        #expect(Self.rgba(L.separatorColor(dark: false)) == [0, 0, 0, 0.15])
        #expect(Self.rgba(L.separatorColor(dark: true)) == [1, 1, 1, 0.15])
    }

    @Test func theCustomIconTintIsHalfInkInLightAndDark() {
        #expect(Self.rgba(L.customIconTint(dark: false)) == [0, 0, 0, 0.5])
        #expect(Self.rgba(L.customIconTint(dark: true)) == [1, 1, 1, 0.5])
    }

    @Test func theCountBackgroundIsEightyPercent() {
        #expect(L.countBackgroundAlpha == 0.8)
    }

    @Test func aCurrentSplitTakesTheCurrentFillAndShadow() {
        let appearance = SidebarRowAppearance(current: true, hovered: true)
        #expect(appearance.fill == .current)
        #expect(appearance.showsShadow)
    }

    @Test func aHoveredSplitTakesTheHoveredFill() {
        #expect(SidebarRowAppearance(hovered: true).fill == .hovered)
    }

    @Test func aMultiSelectedSplitTakesTheMultiSelectedFill() {
        #expect(SidebarRowAppearance(multiSelected: true, hovered: true).fill == .multiSelected)
    }

    @Test func aDraggedSplitTakesTheCurrentFillWithoutTheShadow() {
        let appearance = SidebarRowAppearance(keyDragged: true)
        #expect(appearance.fill == .current)
        #expect(!appearance.showsShadow)
    }
}
