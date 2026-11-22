import CoreGraphics
import Testing
@testable import Parc

struct SidebarChromeLayoutTestsToolbarTests {
    private typealias L = SidebarChromeLayoutTestsSupport.L

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

    struct ToolbarControls: CustomTestStringConvertible {
        let extent: CGFloat?
        let height: CGFloat
        let navigation: Bool

        var testDescription: String {
            let lights = extent.map { "\($0) × \(height) lights" } ?? "No lights at height \(height)"
            return lights + (navigation ? ", navigation shown" : ", navigation hidden")
        }
    }

    private static let controlCases = ([nil, 48, 51, 54, 56, 60] as [CGFloat?]).flatMap { extent in
        ([14, 16] as [CGFloat]).flatMap { height in
            [true, false].map { ToolbarControls(extent: extent, height: height, navigation: $0) }
        }
    }

    @Test(arguments: stride(from: 164.0, through: 500, by: 1).map { CGFloat($0) }, controlCases)
    func everyToolbarWidthKeepsItsControlsSeparateClearOfTheLightsAndInsideTheTrailingInset(width: CGFloat, controls: ToolbarControls) {
        let leading = controls.extent.map { 13 + $0 + 4 } ?? 13
        let bar = L.toolbar(width: width, windowButtons: controls.extent.map { lights($0, controls.height) }, showsNavigation: controls.navigation)
        #expect(bar.toggle != nil)
        let frames = [bar.windowButtons, bar.toggle, bar.back, bar.forward, bar.reload].compactMap { $0 }.sorted { $0.minX < $1.minX }
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.0001 })
        let shown = [bar.toggle, bar.back, bar.forward, bar.reload].compactMap { $0 }
        #expect(shown.allSatisfy { $0.minX >= leading })
        #expect(shown.allSatisfy { $0.maxX <= width - 6 })
        #expect(controls.navigation == (bar.back != nil))
        #expect(bar.windowButtons.map { $0.midY == 24 && $0.minX == 13 } ?? (controls.extent == nil))
    }
}
