import AppKit
import Testing
@testable import ParcKit

struct SidebarRowAppearanceTestsRegionsTests {
    private typealias Support = SidebarRowAppearanceTestsSupport

    @Test func aSplitChildIsTwentyEightPointsCentredInTheRow() {
        #expect(Support.child(100).cell == NSRect(x: 0, y: 3, width: 100, height: 28))
    }

    @Test func aSplitChildsIconSlotIsTwoPointsIn() {
        #expect(Support.child(100).iconSlot == NSRect(x: 2, y: 5, width: 24, height: 24))
        #expect(Support.child(100).indicator == nil)
    }

    @Test func aSplitChildsTitleStartsSixAfterTheSlotAndEndsTwoBeforeTheEdge() {
        let idle = Support.child(100)
        #expect(!idle.showsClose)
        #expect(idle.title == NSRect(x: 32, y: 8, width: 66, height: 17))
    }

    @Test func aHoveredSplitGroupShowsCloseTwoInsideTheEdge() {
        let hovered = Support.child(100, hovered: true)
        #expect(hovered.showsClose)
        #expect(hovered.close == NSRect(x: 74, y: 5, width: 24, height: 24))
        #expect(hovered.title?.width == 40)
    }

    @Test func noCloseShowsWithoutACloseCommand() {
        #expect(!Support.child(100, hovered: true, close: false).showsClose)
    }

    @Test func theRecordingIndicatorPrecedesTheIcon() {
        let recording = Support.child(100, recording: true)
        #expect(recording.indicator == NSRect(x: 2, y: 10, width: 14, height: 14))
        #expect(recording.iconSlot.minX == 16)
        #expect(recording.title?.minX == 46)
    }

    struct IndicatorWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: Double
        let shown: Bool
    }

    @Test(arguments: [
        IndicatorWidth(testDescription: "Below minimum width", width: 41.0, shown: false),
        IndicatorWidth(testDescription: "At minimum width", width: 42.0, shown: true),
    ])
    func theIndicatorNeedsRoomForItselfTheSlotAndBothInsets(_ sample: IndicatorWidth) {
        let width = sample.width
        let shown = sample.shown
        #expect((Support.child(width, recording: true).indicator != nil) == shown)
    }

    @Test func aChildNoWiderThanItsSlotCentresOnlyTheIcon() {
        let narrow = Support.child(28, recording: true, hovered: true)
        #expect(narrow.iconSlot == NSRect(x: 0, y: 5, width: 28, height: 24))
        #expect(narrow.title == nil)
        #expect(!narrow.showsClose)
        #expect(narrow.indicator == nil)
    }

    struct CloseWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: Double
        let shown: Bool
    }

    @Test(arguments: [
        CloseWidth(testDescription: "Clears the icon", width: 50.0, shown: true),
        CloseWidth(testDescription: "Overlaps the icon", width: 49.0, shown: false),
    ])
    func closeMustClearTheIcon(_ sample: CloseWidth) {
        let width = sample.width
        let shown = sample.shown
        #expect(Support.child(width, hovered: true).showsClose == shown)
    }

    struct TitleWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: Double
        let titleWidth: Double?
    }

    @Test(arguments: [
        TitleWidth(testDescription: "Twenty points", width: 54.0, titleWidth: nil),
        TitleWidth(testDescription: "Twenty-one points", width: 55.0, titleWidth: 21.0),
    ])
    func titlesNeedMoreThanTwentyPoints(_ sample: TitleWidth) {
        let width = sample.width
        let titleWidth = sample.titleWidth
        #expect(Support.child(width).title?.width == titleWidth.map { CGFloat($0) })
    }

    private let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]

    private let leadingCorners: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

    @Test func anIdleRowSplitsItsRegions() {
        #expect(SidebarRowAppearance().splitsResetRegions)
        #expect(SidebarRowAppearance().resetRegionCorners == allCorners)
    }

    @Test(arguments: [SidebarRowAppearance(current: true), SidebarRowAppearance(contentVisible: true),
                      SidebarRowAppearance(multiSelected: true), SidebarRowAppearance(hovered: true),
                      SidebarRowAppearance(highlighted: true)])
    func aFilledOrRingedRowKeepsOnlyTheIconRegion(state: SidebarRowAppearance) {
        #expect(!state.splitsResetRegions)
        #expect(state.resetRegionCorners == leadingCorners)
    }

    @Test func aHighlightIsARingNotAFill() {
        #expect(SidebarRowAppearance(highlighted: true).fill == nil)
    }

    @Test func dimmingAddsNoFill() {
        #expect(SidebarRowAppearance(dimmed: true).fill == nil)
    }

    struct RegionFill: CustomTestStringConvertible {
        let testDescription: String
        let pressed: Bool
        let dark: Bool
        let expected: [Double]
    }

    @MainActor @Test(arguments: [
        RegionFill(testDescription: "Light pressed", pressed: true, dark: false, expected: [0.055, 0.059, 0.063, 0.065]),
        RegionFill(testDescription: "Dark pressed", pressed: true, dark: true, expected: [0.98, 0.984, 1, 0.065]),
        RegionFill(testDescription: "Light idle", pressed: false, dark: false, expected: [0.055, 0.059, 0.063, 0.05]),
    ])
    func theRegionFillFollowsPressedAndAppearance(_ sample: RegionFill) {
        let pressed = sample.pressed
        let dark = sample.dark
        let expected = sample.expected
        #expect(Support.rgba(SidebarRowAppearance.regionFill(pressed: pressed, dark: dark), .displayP3) == expected.map { CGFloat($0) })
    }

    struct SlashAppearance: CustomTestStringConvertible {
        let testDescription: String
        let dark: Bool
        let base: CGFloat
    }

    @MainActor @Test(arguments: [
        SlashAppearance(testDescription: "Light appearance", dark: false, base: 0.0),
        SlashAppearance(testDescription: "Dark appearance", dark: true, base: 1.0),
    ])
    func theSlashIsBlackOrWhiteAtThirtyPercent(_ sample: SlashAppearance) {
        let dark = sample.dark
        let base = sample.base
        #expect(Support.rgba(SidebarRowAppearance.slashColor(dark: dark), .displayP3) == [base, base, base, 0.3])
    }
}
