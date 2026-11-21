import AppKit
import Testing
@testable import Parc

private final class FlippedHost: NSView {
    override var isFlipped: Bool { true }
}

struct SidebarRowAppearanceTests {
    private func rgba(_ color: NSColor, _ space: NSColorSpace = .sRGB) -> [CGFloat] {
        let c = color.usingColorSpace(space)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { ($0 * 1000).rounded() / 1000 }
    }

    private func state(_ bits: Int) -> SidebarRowAppearance {
        SidebarRowAppearance(current: bits & 1 != 0, contentVisible: bits & 2 != 0, multiSelected: bits & 4 != 0, hovered: bits & 8 != 0)
    }

    @Test(arguments: 0..<16)
    func fillPrecedenceIsCurrentThenContentVisibleThenMultiSelectedThenHovered(bits: Int) {
        let expected: SidebarRowAppearance.Fill? = bits & 1 != 0 ? .current : bits & 2 != 0 ? .contentVisible
            : bits & 4 != 0 ? .multiSelected : bits & 8 != 0 ? .hovered : nil
        #expect(state(bits).fill == expected)
    }

    @Test(arguments: 0..<16)
    func onlyTheCurrentRowCastsTheSelectedShadow(bits: Int) {
        #expect(state(bits).showsShadow == (bits & 1 != 0))
    }

    @Test(arguments: 0..<16)
    func theKeyDraggedItemTakesTheCurrentFillButNotItsShadow(bits: Int) {
        var dragged = state(bits)
        dragged.keyDragged = true
        #expect(dragged.fill == .current)
        #expect(dragged.showsShadow == (bits & 1 != 0))
    }

    @Test(arguments: 0..<16)
    func aSplitChildIgnoresRowSelectionAndHover(bits: Int) {
        var child = state(bits)
        child.splitChild = true
        #expect(child.fill == nil)
        #expect(!child.showsShadow)
    }

    @Test(arguments: 0..<16)
    func aSelectedSplitsChildShowsItsOwnBackground(bits: Int) {
        var child = state(bits)
        child.splitChild = true
        child.splitGroupSelected = true
        #expect(child.fill == .splitChild)
        #expect(!child.showsShadow)
    }

    @MainActor @Test(arguments: [(false, 0.0), (true, 1.0)])
    func theSplitChildBackgroundIsBlackOrWhiteAtSevenPercent(dark: Bool, base: CGFloat) {
        #expect(rgba(SidebarRowAppearance.color(.splitChild, dark: dark)) == [base, base, base, 0.07])
    }

    @Test func rowCornersStayTwelve() {
        #expect(SidebarRowAppearance().cornerRadius(in: NSRect(x: 0, y: 0, width: 90, height: 28)) == 12)
    }

    @Test(arguments: [(90.0, 8.0), (10.0, 5.0)])
    func aSplitChildRoundsByMinOfHalfWidthAndEight(width: CGFloat, expected: CGFloat) {
        #expect(SidebarRowAppearance(splitChild: true).cornerRadius(in: NSRect(x: 0, y: 0, width: width, height: 28)) == expected)
    }

    @MainActor @Test(arguments: [
        (SidebarRowAppearance.Fill.current, false, NSColorSpace.sRGB, [1.0, 1, 1, 0.85]),
        (.current, true, .displayP3, [0.98, 0.984, 1, 0.2]),
        (.contentVisible, false, .sRGB, [1, 1, 1, 0.7]),
        (.contentVisible, true, .displayP3, [0.98, 0.984, 1, 0.15]),
        (.multiSelected, false, .sRGB, [0, 0, 0, 0.1]),
        (.multiSelected, true, .displayP3, [0.98, 0.984, 1, 0.1]),
        (.hovered, false, .displayP3, [0.055, 0.059, 0.063, 0.05]),
        (.hovered, true, .displayP3, [0.98, 0.984, 1, 0.1]),
    ])
    func eachFillHasItsRecoveredColor(fill: SidebarRowAppearance.Fill, dark: Bool, space: NSColorSpace, expected: [Double]) {
        #expect(rgba(SidebarRowAppearance.color(fill, dark: dark), space) == expected.map { CGFloat($0) })
    }

    @MainActor @Test func theSelectedShadowIsBlackAtTwentyPercentInLight() {
        #expect(rgba(SidebarRowAppearance.shadowColor(dark: false)) == [0, 0, 0, 0.2])
    }

    @MainActor @Test func theSelectedShadowIsClearInDark() {
        #expect(SidebarRowAppearance.shadowColor(dark: true).alphaComponent == 0)
    }

    @MainActor @Test(arguments: [(false, false, [0.0, 0, 0, 0.071]), (true, false, [0, 0, 0, 0.09]),
                                 (false, true, [1, 1, 1, 0.077]), (true, true, [1, 1, 1, 0.103])])
    func theControlFillFollowsPressedAndAppearance(pressed: Bool, dark: Bool, expected: [Double]) {
        #expect(rgba(SidebarRowAppearance.controlFill(pressed: pressed, dark: dark)) == expected.map { CGFloat($0) })
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

    @Test(arguments: [(true, 180.0), (false, 202.0)])
    func theTitleStopsBeforeAVisibleCloseAndWidensWithoutOne(closeVisible: Bool, expected: CGFloat) {
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

    @Test func theHoverSubtitleMotionAndColourAreFixed() {
        #expect(SidebarRowAppearance.subtitleLift == 7)
        #expect(SidebarRowAppearance.subtitleDuration == 0.1)
        #expect(SidebarRowAppearance.subtitleTextAlpha == 0.5)
    }

    @Test func theHoverSubtitleTexts() {
        #expect(SidebarRowAppearance.resetSubtitle == "Back to Pinned URL")
        #expect(SidebarRowAppearance.separateSubtitle == "Separate From Pinned Tab")
    }

    @Test func theSubtitleUsesAnElevenPointSystemFont() {
        #expect(SidebarRowAppearance.subtitleFontSize == 11)
    }

    private func child(_ width: CGFloat, recording: Bool = false, hovered: Bool = false, close: Bool = true) -> SidebarRowAppearance.SplitChildLayout {
        SidebarRowAppearance.splitChildLayout(in: NSRect(x: 0, y: 0, width: width, height: 35), titleHeight: 17,
                                              recording: recording, closeAvailable: close, groupHovered: hovered)
    }

    @Test func aSplitChildIsTwentyEightPointsCentredInTheRow() {
        #expect(child(100).cell == NSRect(x: 0, y: 3, width: 100, height: 28))
    }

    @Test func aSplitChildsIconSlotIsTwoPointsIn() {
        #expect(child(100).iconSlot == NSRect(x: 2, y: 5, width: 24, height: 24))
        #expect(child(100).indicator == nil)
    }

    @Test func aSplitChildsTitleStartsSixAfterTheSlotAndEndsTwoBeforeTheEdge() {
        let idle = child(100)
        #expect(!idle.showsClose)
        #expect(idle.title == NSRect(x: 32, y: 8, width: 66, height: 17))
    }

    @Test func aHoveredSplitGroupShowsCloseTwoInsideTheEdge() {
        let hovered = child(100, hovered: true)
        #expect(hovered.showsClose)
        #expect(hovered.close == NSRect(x: 74, y: 5, width: 24, height: 24))
        #expect(hovered.title?.width == 40)
    }

    @Test func noCloseShowsWithoutACloseCommand() {
        #expect(!child(100, hovered: true, close: false).showsClose)
    }

    @Test func theRecordingIndicatorPrecedesTheIcon() {
        let recording = child(100, recording: true)
        #expect(recording.indicator == NSRect(x: 2, y: 10, width: 14, height: 14))
        #expect(recording.iconSlot.minX == 16)
        #expect(recording.title?.minX == 46)
    }

    @Test(arguments: [(41.0, false), (42.0, true)])
    func theIndicatorNeedsRoomForItselfTheSlotAndBothInsets(width: Double, shown: Bool) {
        #expect((child(width, recording: true).indicator != nil) == shown)
    }

    @Test func aChildNoWiderThanItsSlotCentresOnlyTheIcon() {
        let narrow = child(28, recording: true, hovered: true)
        #expect(narrow.iconSlot == NSRect(x: 0, y: 5, width: 28, height: 24))
        #expect(narrow.title == nil)
        #expect(!narrow.showsClose)
        #expect(narrow.indicator == nil)
    }

    @Test(arguments: [(50.0, true), (49.0, false)])
    func closeMustClearTheIcon(width: Double, shown: Bool) {
        #expect(child(width, hovered: true).showsClose == shown)
    }

    @Test(arguments: [(54.0, nil), (55.0, 21.0)])
    func titlesNeedMoreThanTwentyPoints(width: Double, titleWidth: Double?) {
        #expect(child(width).title?.width == titleWidth.map { CGFloat($0) })
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

    @MainActor @Test(arguments: [(true, false, [0.055, 0.059, 0.063, 0.065]), (true, true, [0.98, 0.984, 1, 0.065]),
                                 (false, false, [0.055, 0.059, 0.063, 0.05])])
    func theRegionFillFollowsPressedAndAppearance(pressed: Bool, dark: Bool, expected: [Double]) {
        #expect(rgba(SidebarRowAppearance.regionFill(pressed: pressed, dark: dark), .displayP3) == expected.map { CGFloat($0) })
    }

    @MainActor @Test(arguments: [(false, 0.0), (true, 1.0)])
    func theSlashIsBlackOrWhiteAtThirtyPercent(dark: Bool, base: CGFloat) {
        #expect(rgba(SidebarRowAppearance.slashColor(dark: dark), .displayP3) == [base, base, base, 0.3])
    }

    @MainActor private final class Background {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = FlippedHost(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        let view = SidebarRowBackgroundView(frame: NSRect(x: 8, y: 10, width: 212, height: 35))
        var layer: CALayer { view.fillLayer }
        var ring: CALayer { view.ringLayer }

        init() {
            window.isReleasedWhenClosed = false
            window.contentView!.addSubview(host)
            host.addSubview(view)
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        func painted() -> Background {
            view.updateLayer()
            return self
        }
    }

    @MainActor @Test func theFillViewKeepsAppKitsUnflippedShadowDirection() {
        #expect(!Background().view.isFlipped)
    }

    @MainActor @Test func theFillNeverTakesRowInput() {
        #expect(Background().view.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @MainActor @Test func theFillAddsNoAccessibilityElement() {
        #expect(!Background().view.isAccessibilityElement())
    }

    @MainActor @Test func theSelectedShadowIsNotClippedToTheFill() {
        let view = Background().view
        #expect(!view.clipsToBounds)
        #expect(view.layer?.masksToBounds == false)
    }

    @MainActor @Test func translucentFillsCompositeOntoTheThemeNotAnOffscreenBacking() {
        #expect(Background().view.layer?.allowsGroupOpacity == false)
    }

    @MainActor @Test func theFillAndRingAreSiblingLayers() {
        let background = Background().painted()
        #expect(background.layer.superlayer === background.view.layer)
        #expect(background.ring.superlayer === background.view.layer)
    }

    @MainActor @Test func anIdleRowIsClear() {
        let background = Background().painted()
        #expect(background.layer.backgroundColor == nil)
        #expect(background.view.layer!.backgroundColor == nil)
    }

    @MainActor @Test func theFillHasContinuousTwelvePointCorners() {
        let layer = Background().painted().layer
        #expect(layer.cornerRadius == 12)
        #expect(layer.cornerCurve == .continuous)
    }

    @MainActor @Test func theFillCoversTheVisibleRow() {
        let background = Background().painted()
        #expect(background.layer.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func atRestThereIsNoRingOrDimming() {
        let background = Background().painted()
        #expect(background.ring.isHidden)
        #expect(background.layer.opacity == 1)
    }

    @MainActor @Test func theShadowHasItsRecoveredGeometry() {
        let layer = Background().painted().layer
        #expect(layer.shadowRadius == 1)
        #expect(layer.shadowOffset == CGSize(width: 0, height: -1))
        #expect(layer.shadowOpacity == 1)
    }

    @MainActor @Test func updateLayerKeepsTheHostAndFillUnclipped() {
        let background = Background().painted()
        #expect(background.layer.masksToBounds == false)
        #expect(background.view.layer?.masksToBounds == false)
    }

    @MainActor @Test func thereIsNoShadowWithoutTheCurrentItem() {
        #expect(NSColor(cgColor: Background().painted().layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor @Test func theCurrentFillWinsOverHover() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.updateLayer()
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [1, 1, 1, 0.85])
    }

    @MainActor @Test func theCurrentRowCastsItsShadow() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.updateLayer()
        #expect(rgba(NSColor(cgColor: background.layer.shadowColor!)!) == [0, 0, 0, 0.2])
    }

    @MainActor @Test func aDarkCurrentRowHasNoShadow() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(current: true, hovered: true)
        background.view.dark = true
        background.view.updateLayer()
        #expect(NSColor(cgColor: background.layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor @Test func multiSelectionWinsOverHover() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(multiSelected: true, hovered: true)
        background.view.updateLayer()
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [0, 0, 0, 0.1])
    }

    @MainActor @Test func aNarrowCompactRowKeepsAValidShadowPath() {
        let background = Background()
        background.view.frame = NSRect(x: 0, y: 0, width: 10, height: 35)
        background.view.updateLayer()
        #expect(background.layer.shadowPath != nil)
    }

    @MainActor @Test func aSelectedSplitChildIsAPill() {
        let background = Background()
        background.view.appearanceState = SidebarRowAppearance(splitChild: true, splitGroupSelected: true)
        background.view.frame = NSRect(x: 0, y: 3, width: 90, height: 28)
        background.view.updateLayer()
        #expect(background.layer.cornerRadius == 8)
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!) == [0, 0, 0, 0.07])
        #expect(NSColor(cgColor: background.layer.shadowColor!)!.alphaComponent == 0)
    }

    @MainActor private func highlighted() -> Background {
        let background = Background()
        background.view.ringColor = .black
        background.view.appearanceState = SidebarRowAppearance(current: true, highlighted: true, dimmed: true)
        background.view.updateLayer()
        return background
    }

    @MainActor @Test func aHighlightedRowDrawsTheTwoPointContinuousRing() {
        let ring = highlighted().ring
        #expect(!ring.isHidden)
        #expect(ring.borderWidth == 2)
        #expect(ring.cornerRadius == 12)
        #expect(ring.cornerCurve == .continuous)
    }

    @MainActor @Test func theRingSharesTheFillFrame() {
        let background = highlighted()
        #expect(background.ring.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func theRingUsesTheSuppliedContrastColour() {
        #expect(rgba(NSColor(cgColor: highlighted().ring.borderColor!)!) == [0, 0, 0, 1])
    }

    @MainActor @Test func dimmingHalvesTheFillAndShadowButNotTheRing() {
        let background = highlighted()
        #expect(background.layer.opacity == 0.5)
        #expect(background.ring.opacity == 1)
    }

    @MainActor @Test func aDimmedCurrentRowKeepsItsFillColour() {
        #expect(rgba(NSColor(cgColor: highlighted().layer.backgroundColor!)!) == [1, 1, 1, 0.85])
    }

    @MainActor @Test func updateLayerRecordsTheBoundsItPainted() {
        let background = highlighted()
        #expect(background.view.paintedBounds == background.view.bounds)
    }

    @MainActor @Test func aNoOpLayoutDoesNotRebuildUnchangedLayers() {
        let background = highlighted()
        let painted = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.layout()
        #expect(background.view.paintedBounds == painted)
        #expect(background.layer.shadowPath === shadow)
        #expect(background.layer.frame == background.view.layer!.bounds)
    }

    @MainActor @Test func unchangedAppearanceInputsDoNotRebuildLayers() {
        let background = highlighted()
        let shadow = background.layer.shadowPath
        let painted = background.view.paintedBounds
        background.view.appearanceState = background.view.appearanceState
        background.view.dark = false
        background.view.ringColor = background.view.ringColor
        #expect(background.layer.shadowPath === shadow)
        #expect(background.view.paintedBounds == painted)
    }

    @MainActor @Test func movingTheUnflippedFillViewDoesNotRedraw() {
        let background = highlighted()
        let painted = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.frame.origin = NSPoint(x: 40, y: 18)
        background.view.layout()
        #expect(background.view.bounds.size == NSSize(width: 212, height: 35))
        #expect(background.view.paintedBounds == painted)
        #expect(background.layer.shadowPath === shadow)
    }

    @MainActor @Test func hoverFillStillPaintsFromAppearanceWithoutALayout() {
        let background = highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.055, 0.059, 0.063, 0.05])
        #expect(background.ring.isHidden)
        #expect(background.layer.opacity == 1)
    }

    @MainActor @Test func aFollowUpLayoutKeepsTheAppearanceThatAlreadyPainted() {
        let background = highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        background.view.layout()
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.055, 0.059, 0.063, 0.05])
    }

    @MainActor @Test func aWidthChangeLeavesPaintedBoundsStaleUntilLayout() {
        let background = highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        #expect(background.view.paintedBounds != background.view.bounds)
    }

    @MainActor @Test func aWidthChangeStillRefreshesFillAndRingFrames() {
        let background = highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        background.view.layout()
        #expect(background.view.paintedBounds == background.view.bounds)
        #expect(background.layer.frame.size == NSSize(width: 180, height: 35))
        #expect(background.ring.frame.size == NSSize(width: 180, height: 35))
    }

    @MainActor @Test func aFollowUpLayoutAtTheNewSizeIsANoOp() {
        let background = highlighted()
        background.view.setFrameSize(NSSize(width: 180, height: 35))
        background.view.layout()
        let sized = background.view.paintedBounds
        let shadow = background.layer.shadowPath
        background.view.layout()
        #expect(background.view.paintedBounds == sized)
        #expect(background.layer.shadowPath === shadow)
    }

    @MainActor @Test func aHeightChangeStillRefreshesTheShadowPathBounds() {
        let background = highlighted()
        let before = background.layer.shadowPath
        background.view.setFrameSize(NSSize(width: 212, height: 36))
        background.view.layout()
        #expect(background.view.paintedBounds == background.view.bounds)
        #expect(background.layer.frame.size.height == 36)
        #expect(background.layer.shadowPath != nil)
        #expect(background.layer.shadowPath !== before)
    }

    @MainActor @Test func darkAppearanceStillPaintsTheHoverFill() {
        let background = highlighted()
        background.view.appearanceState = SidebarRowAppearance(hovered: true)
        background.view.dark = true
        #expect(rgba(NSColor(cgColor: background.layer.backgroundColor!)!, .displayP3) == [0.98, 0.984, 1, 0.1])
    }

    @MainActor @Test func ringColourDimmingAndHighlightStillUpdateTogether() {
        let background = highlighted()
        background.view.ringColor = .white
        #expect(!background.ring.isHidden)
        #expect(background.ring.borderWidth == 2)
        #expect(background.layer.opacity == 0.5)
        #expect(rgba(NSColor(cgColor: background.ring.borderColor!)!) == [1, 1, 1, 1])
        #expect(background.ring.opacity == 1)
    }

    @MainActor @Test func theSkipDoesNotClipTheSelectedShadowOrFlattenTranslucentFills() {
        let background = highlighted()
        background.view.layout()
        #expect(!background.view.clipsToBounds)
        #expect(background.view.layer?.masksToBounds == false)
        #expect(background.view.layer?.allowsGroupOpacity == false)
        #expect(background.layer.masksToBounds == false)
    }
}
