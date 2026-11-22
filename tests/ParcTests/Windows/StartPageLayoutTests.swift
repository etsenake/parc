import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct StartPageLayoutTests {
    typealias Layout = StartPageLayout

    private func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat = 0.5) -> Bool { abs(a - b) <= e }

    private static let sizes = [CGSize(width: 1220, height: 820), CGSize(width: 1001, height: 677), CGSize(width: 640, height: 480)]
    private static let rests: [CGFloat] = [64, 52, 80]
    private static let cases = sizes.flatMap { size in rests.map { (size, $0) } }

    private func layout(_ size: CGSize, rest: CGFloat = 64, origin: CGPoint? = nil, buttons: Bool = true,
                        toolbarWidth: CGFloat? = nil, navigation: Bool = false, mark: CGSize? = nil) -> Layout {
        if let mark {
            return Layout(size: size, barRestHeight: rest, markSize: mark, chromeOrigin: origin, showsWindowButtons: buttons)
        }
        if let toolbarWidth {
            return Layout(size: size, barRestHeight: rest, chromeOrigin: origin, showsWindowButtons: buttons,
                          toolbarWidth: toolbarWidth, showsNavigation: navigation)
        }
        return Layout(size: size, barRestHeight: rest, chromeOrigin: origin, showsWindowButtons: buttons)
    }

    @Test func theMarkIs65PointsAbove765PointBar() {
        #expect(Layout.markSize.width == 65 && Layout.markSpacing == 24 && Layout.maximumBarWidth == 765)
    }

    @Test func theBarRestsAt64PointsUntilTheOwnerSaysOtherwise() {
        #expect(Layout.defaultBarRestHeight == 64)
    }

    @Test(arguments: cases)
    func theSlotIsTheNarrowerOfTheBarWidthAndThePageLessGutters(size: CGSize, rest: CGFloat) {
        #expect(layout(size, rest: rest).commandBarSlot.width == min(765, size.width - 2 * Layout.sideGutter))
    }

    @Test(arguments: cases)
    func markAndBarAreCentred(size: CGSize, rest: CGFloat) {
        let value = layout(size, rest: rest)
        #expect(near(value.commandBarSlot.midX, size.width / 2) && near(value.mark.midX, size.width / 2))
    }

    @Test(arguments: cases)
    func theMarkSits24PointsAboveTheBarsTopEdge(size: CGSize, rest: CGFloat) {
        let value = layout(size, rest: rest)
        #expect(value.commandBarSlot.minY - value.mark.maxY == 24)
    }

    @Test(arguments: cases)
    func theSlotRunsToTheBottomSoTheBarCanGrowDown(size: CGSize, rest: CGFloat) {
        #expect(layout(size, rest: rest).commandBarSlot.maxY == size.height)
    }

    @Test(arguments: cases)
    func theRestingPairCentresAt45PercentOfTheHeight(size: CGSize, rest: CGFloat) {
        let value = layout(size, rest: rest)
        let center = (value.mark.minY + value.commandBarSlot.minY + rest) / 2
        #expect(near(center, size.height * Layout.pairCenter))
        #expect(center < size.height / 2 && center > size.height * 0.4)
    }

    @Test(arguments: cases)
    func framesAreWholePoints(size: CGSize, rest: CGFloat) {
        let value = layout(size, rest: rest)
        #expect([value.commandBarSlot.minX, value.commandBarSlot.minY, value.mark.minX, value.mark.minY].allSatisfy { $0 == $0.rounded() })
    }

    @Test(arguments: cases)
    func thereIsNoChromeWithoutAnOrigin(size: CGSize, rest: CGFloat) {
        let value = layout(size, rest: rest)
        #expect(value.windowButtons == nil && value.sidebarButton == nil)
    }

    @Test func aTallerRestingBarLiftsThePairByHalfTheDifference() {
        let size = CGSize(width: 1000, height: 600)
        #expect(layout(size, rest: 120).commandBarSlot.minY == layout(size).commandBarSlot.minY - 28)
    }

    @Test func theLayoutFollowsTheMarksOwnSize() {
        let measured = layout(CGSize(width: 1000, height: 600), mark: CGSize(width: 64, height: 90))
        #expect(measured.mark.size == CGSize(width: 64, height: 90))
        #expect(measured.commandBarSlot.minY - measured.mark.maxY == 24)
        #expect(near((measured.mark.minY + measured.commandBarSlot.minY + 64) / 2, 270))
    }

    @Test func aMarkWithoutASizeFallsBackTo65By96() {
        let size = CGSize(width: 1000, height: 600)
        #expect(layout(size, mark: CGSize(width: -1, height: -1)) == layout(size))
    }

    @Test func aNarrowPageKeeps40PointGutters() {
        let narrow = layout(CGSize(width: 300, height: 900))
        #expect(narrow.commandBarSlot.width == 220 && narrow.commandBarSlot.minX == 40)
    }

    @Test func aTinyPageClampsInsteadOfGoingNegative() {
        let tiny = layout(CGSize(width: 50, height: 100))
        #expect(tiny.mark.minY == 0 && tiny.commandBarSlot.width == 0 && tiny.commandBarSlot.height >= 0)
    }

    private let origin = CGPoint(x: -5, y: -5)
    private let page = CGSize(width: 1220, height: 820)

    @Test func theWindowButtonsSitWhereTheSidebarHeaderPutsThem() {
        let value = layout(page, origin: origin)
        let sidebar = SidebarChromeLayout.toolbar(width: 1220, windowButtons: WindowStandardButtons.stackSize, showsNavigation: false)
        #expect(value.windowButtons == sidebar.windowButtons?.offsetBy(dx: -5, dy: -5))
    }

    @Test func theSidebarButtonSitsWhereTheSidebarsOwnToggleDoes() {
        let value = layout(page, origin: origin)
        let sidebar = SidebarChromeLayout.toolbar(width: 1220, windowButtons: WindowStandardButtons.stackSize, showsNavigation: false)
        #expect(value.sidebarButton == sidebar.toggle?.offsetBy(dx: -5, dy: -5))
    }

    @Test func standardButtonsAndA32PointToggleShareOneRow() throws {
        let value = layout(page, origin: origin)
        let lights = try #require(value.windowButtons), toggle = try #require(value.sidebarButton)
        #expect(lights.size == WindowStandardButtons.stackSize && toggle.size == CGSize(width: 32, height: 32))
        #expect(lights.midY == toggle.midY && toggle.minX == lights.maxX + SidebarChromeLayout.windowButtonMargin)
    }

    @Test func withoutWindowButtonsTheToggleTakesTheLeadingSlot() {
        let bare = layout(page, origin: origin, buttons: false)
        #expect(bare.windowButtons == nil && bare.sidebarButton?.minX == SidebarChromeLayout.navigationLeading - 5)
    }

    @Test(arguments: [164, 190, 210, 228, 320].flatMap { width in [false, true].map { (CGFloat(width), $0) } })
    func aSidebarOfAnyWidthLandsItsToggleOnThePages(width: CGFloat, navigation: Bool) {
        let narrow = layout(page, origin: origin, toolbarWidth: width, navigation: navigation)
        let own = SidebarChromeLayout.toolbar(width: width, windowButtons: WindowStandardButtons.stackSize, showsNavigation: navigation)
        #expect(narrow.sidebarButton == own.toggle?.offsetBy(dx: -5, dy: -5))
        #expect(narrow.windowButtons == own.windowButtons?.offsetBy(dx: -5, dy: -5))
    }
}
