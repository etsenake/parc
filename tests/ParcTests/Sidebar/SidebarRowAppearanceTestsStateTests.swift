import AppKit
import Testing
@testable import Parc
@testable import ParcKit

struct SidebarRowAppearanceTestsStateTests {
    private typealias Support = SidebarRowAppearanceTestsSupport
    @Test(arguments: 0..<16)
    func fillPrecedenceIsCurrentThenContentVisibleThenMultiSelectedThenHovered(bits: Int) {
        let expected: SidebarRowAppearance.Fill? = bits & 1 != 0 ? .current : bits & 2 != 0 ? .contentVisible
            : bits & 4 != 0 ? .multiSelected : bits & 8 != 0 ? .hovered : nil
        #expect(Support.state(bits).fill == expected)
    }

    @Test(arguments: 0..<16)
    func onlyTheCurrentRowCastsTheSelectedShadow(bits: Int) {
        #expect(Support.state(bits).showsShadow == (bits & 1 != 0))
    }

    @Test(arguments: 0..<16)
    func theKeyDraggedItemTakesTheCurrentFillButNotItsShadow(bits: Int) {
        var dragged = Support.state(bits)
        dragged.keyDragged = true
        #expect(dragged.fill == .current)
        #expect(dragged.showsShadow == (bits & 1 != 0))
    }

    @Test(arguments: 0..<16)
    func aSplitChildIgnoresRowSelectionAndHover(bits: Int) {
        var child = Support.state(bits)
        child.splitChild = true
        #expect(child.fill == nil)
        #expect(!child.showsShadow)
    }

    @Test(arguments: 0..<16)
    func aSelectedSplitsChildShowsItsOwnBackground(bits: Int) {
        var child = Support.state(bits)
        child.splitChild = true
        child.splitGroupSelected = true
        #expect(child.fill == .splitChild)
        #expect(!child.showsShadow)
    }

    struct SplitChildBackground: CustomTestStringConvertible {
        let testDescription: String
        let dark: Bool
        let base: CGFloat
    }

    @MainActor @Test(arguments: [
        SplitChildBackground(testDescription: "Light appearance", dark: false, base: 0.0),
        SplitChildBackground(testDescription: "Dark appearance", dark: true, base: 1.0),
    ])
    func theSplitChildBackgroundIsBlackOrWhiteAtSevenPercent(_ sample: SplitChildBackground) {
        let dark = sample.dark
        let base = sample.base
        #expect(Support.rgba(SidebarRowAppearance.color(.splitChild, dark: dark)) == [base, base, base, 0.07])
    }

    @Test func rowCornersStayTwelve() {
        #expect(SidebarRowAppearance().cornerRadius(in: NSRect(x: 0, y: 0, width: 90, height: 28)) == 12)
    }

    struct ChildCornerWidth: CustomTestStringConvertible {
        let testDescription: String
        let width: CGFloat
        let expected: CGFloat
    }

    @Test(arguments: [
        ChildCornerWidth(testDescription: "Wide child", width: 90.0, expected: 8.0),
        ChildCornerWidth(testDescription: "Narrow child", width: 10.0, expected: 5.0),
    ])
    func aSplitChildRoundsByMinOfHalfWidthAndEight(_ sample: ChildCornerWidth) {
        let width = sample.width
        let expected = sample.expected
        #expect(SidebarRowAppearance(splitChild: true).cornerRadius(in: NSRect(x: 0, y: 0, width: width, height: 28)) == expected)
    }

    struct FillColor: CustomTestStringConvertible {
        let testDescription: String
        let fill: SidebarRowAppearance.Fill
        let dark: Bool
        let space: NSColorSpace
        let expected: [Double]
    }

    @MainActor @Test(arguments: [
        FillColor(testDescription: "Current light", fill: SidebarRowAppearance.Fill.current, dark: false, space: NSColorSpace.sRGB, expected: [1.0, 1, 1, 0.85]),
        FillColor(testDescription: "Current dark", fill: .current, dark: true, space: .displayP3, expected: [0.98, 0.984, 1, 0.2]),
        FillColor(testDescription: "Visible content light", fill: .contentVisible, dark: false, space: .sRGB, expected: [1, 1, 1, 0.7]),
        FillColor(testDescription: "Visible content dark", fill: .contentVisible, dark: true, space: .displayP3, expected: [0.98, 0.984, 1, 0.15]),
        FillColor(testDescription: "Multi-selected light", fill: .multiSelected, dark: false, space: .sRGB, expected: [0, 0, 0, 0.1]),
        FillColor(testDescription: "Multi-selected dark", fill: .multiSelected, dark: true, space: .displayP3, expected: [0.98, 0.984, 1, 0.1]),
        FillColor(testDescription: "Hovered light", fill: .hovered, dark: false, space: .displayP3, expected: [0.055, 0.059, 0.063, 0.05]),
        FillColor(testDescription: "Hovered dark", fill: .hovered, dark: true, space: .displayP3, expected: [0.98, 0.984, 1, 0.1]),
    ])
    func eachFillHasItsRecoveredColor(_ sample: FillColor) {
        let fill = sample.fill
        let dark = sample.dark
        let space = sample.space
        let expected = sample.expected
        #expect(Support.rgba(SidebarRowAppearance.color(fill, dark: dark), space) == expected.map { CGFloat($0) })
    }

    @MainActor @Test func theSelectedShadowIsBlackAtTwentyPercentInLight() {
        #expect(Support.rgba(SidebarRowAppearance.shadowColor(dark: false)) == [0, 0, 0, 0.2])
    }

    @MainActor @Test func theSelectedShadowIsClearInDark() {
        #expect(SidebarRowAppearance.shadowColor(dark: true).alphaComponent == 0)
    }

    struct ControlFill: CustomTestStringConvertible {
        let testDescription: String
        let pressed: Bool
        let dark: Bool
        let expected: [Double]
    }

    @MainActor @Test(arguments: [
        ControlFill(testDescription: "Light idle", pressed: false, dark: false, expected: [0.0, 0, 0, 0.071]),
        ControlFill(testDescription: "Light pressed", pressed: true, dark: false, expected: [0, 0, 0, 0.09]),
        ControlFill(testDescription: "Dark idle", pressed: false, dark: true, expected: [1, 1, 1, 0.077]),
        ControlFill(testDescription: "Dark pressed", pressed: true, dark: true, expected: [1, 1, 1, 0.103]),
    ])
    func theControlFillFollowsPressedAndAppearance(_ sample: ControlFill) {
        let pressed = sample.pressed
        let dark = sample.dark
        let expected = sample.expected
        #expect(Support.rgba(SidebarRowAppearance.controlFill(pressed: pressed, dark: dark)) == expected.map { CGFloat($0) })
    }

    private let row = NSRect(x: 0, y: 0, width: 212, height: 36)

    @Test func theIconSlotIsTwentyFourPointsInsetSix() {
        #expect(SidebarRowAppearance.iconSlotFrame(in: row) == NSRect(x: 6, y: 6, width: 24, height: 24))
    }

    @Test func theFaviconIsCentred() {
        #expect(SidebarRowAppearance.iconFrame(in: row) == NSRect(x: 10, y: 10, width: 16, height: 16))
    }

    @Test func theFaviconIsPixelAlignedInAThirtyFivePointRow() {
        #expect(SidebarRowAppearance.iconFrame(in: NSRect(x: 0, y: 0, width: 212, height: 35)).origin == NSPoint(x: 10, y: 9))
    }

    @Test func theTitleFollowsTheSlotSpacing() {
        #expect(SidebarRowAppearance.iconSlotFrame(in: row).maxX + 6 == SidebarRowAppearance.titleInset)
    }

    @MainActor @Test func aStackedLabelsAlignmentRectSitsTwoPointsInsideEachEdge() {
        let label = NSTextField(labelWithString: "Title")
        label.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize)
        #expect(SidebarRowAppearance.titleTextPadding == 2)
        #expect(label.alignmentRectInsets.left == SidebarRowAppearance.titleTextPadding)
        #expect(label.alignmentRectInsets.right == SidebarRowAppearance.titleTextPadding)
    }

    @Test func theSlashHasItsGeometry() {
        #expect(SidebarRowAppearance.slashFrame(in: row) == NSRect(x: 30, y: 10, width: 4, height: 15))
    }

    @Test func theIconRegionEndsAtTheSlash() {
        #expect(SidebarRowAppearance.resetRegionFrame(in: row) == NSRect(x: 0, y: 0, width: 30, height: 36))
    }

    @Test func aResettableTitleStartsAfterTheSlashAndItsSpacing() {
        #expect(SidebarRowAppearance.resetTitleInset == 38)
    }

    @Test func theCloseHasItsGeometry() {
        #expect(SidebarRowAppearance.closeFrame(in: row) == NSRect(x: 182, y: 6, width: 24, height: 24))
    }

    struct CloseVisibility: CustomTestStringConvertible {
        let testDescription: String
        let closeVisible: Bool
        let expected: CGFloat
    }

    @Test(arguments: [
        CloseVisibility(testDescription: "Close visible", closeVisible: true, expected: 180.0),
        CloseVisibility(testDescription: "Close hidden", closeVisible: false, expected: 202.0),
    ])
    func theTitleStopsBeforeAVisibleCloseAndWidensWithoutOne(_ sample: CloseVisibility) {
        let closeVisible = sample.closeVisible
        let expected = sample.expected
        #expect(SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: closeVisible) == expected)
    }

    @Test func aHoveredTitleRunsToTheClose() {
        let span = SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: true))
        #expect(span.minX == 34)
        #expect(span.minX + span.width == SidebarRowAppearance.closeFrame(in: row).minX)
    }

    @Test func anIdleTitleRunsToTenInsideTheRow() {
        let span = SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: row, closeVisible: false))
        #expect(span.minX == 34)
        #expect(span.minX + span.width == 204)
    }

    @Test func aResettableRowsTitleStartsAfterTheSlash() {
        let span = SidebarRowAppearance.titleLabelSpan(resettable: true, trailing: 202)
        #expect(span.minX == SidebarRowAppearance.resetTitleInset - 2)
        #expect(span.minX + span.width == 204)
    }

    @Test func aRowTooNarrowForATitleGivesItNoWidth() {
        #expect(SidebarRowAppearance.titleLabelSpan(resettable: false, trailing: 20).width == 0)
    }

    @Test func theSubtitleRisesSevenPointsInOneTenthOfASecond() {
        #expect(SidebarRowAppearance.subtitleLift == 7)
        #expect(SidebarRowAppearance.subtitleDuration == 0.1)
    }

    @Test func theSubtitleUsesHalfOpacity() {
        #expect(SidebarRowAppearance.subtitleTextAlpha == 0.5)
    }

    @Test func theResetSubtitleSaysBackToPinnedURL() {
        #expect(SidebarRowAppearance.resetSubtitle == "Back to Pinned URL")
    }

    @Test func theSeparateSubtitleNamesItsAction() {
        #expect(SidebarRowAppearance.separateSubtitle == "Separate From Pinned Tab")
    }

    @Test func theSubtitleUsesAnElevenPointSystemFont() {
        #expect(SidebarRowAppearance.subtitleFontSize == 11)
    }
}
