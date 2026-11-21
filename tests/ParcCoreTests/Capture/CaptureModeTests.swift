import CoreGraphics
import Testing
@testable import ParcCore

struct CaptureModeItemTests {
    @Test func theBarReadsElementRegionVisibleAreaFullPageCancel() {
        #expect(CaptureModeItem.allCases == [.element, .region, .visibleArea, .fullPage, .cancel])
    }

    @Test func onlyElementAndRegionAreSelectionModes() {
        #expect(CaptureModeItem.allCases.map(\.mode) == [.element, .region, nil, nil, nil])
    }

    @Test func modesOneClickCapturesAndCancelFormThreeGroups() {
        #expect(CaptureModeItem.allCases.map(\.group) == [0, 0, 1, 1, 2])
    }

    @Test func everyItemHasItsOwnKey() {
        #expect(Set(CaptureModeItem.allCases.map(\.key)).count == 5)
    }

    @Test func visibleAreaIsLabelledWithItsKey() {
        #expect(CaptureModeItem.visibleArea.title == "Visible Area")
        #expect(CaptureModeItem.visibleArea.key == "V")
    }

    @Test func cancelShowsEscape() {
        #expect(CaptureModeItem.cancel.key == "esc")
    }

    @Test func everyItemHasAnIconATitleAndATooltip() {
        #expect(CaptureModeItem.allCases.allSatisfy { !$0.symbol.isEmpty && !$0.toolTip.isEmpty && !$0.title.isEmpty })
    }
}

struct CaptureModeKeysTests {
    @Test func lettersChooseTheirItems() {
        #expect(CaptureModeKeys.item(typed: "e", keyCode: 14) == .element)
        #expect(CaptureModeKeys.item(typed: "r", keyCode: 15) == .region)
        #expect(CaptureModeKeys.item(typed: "v", keyCode: 9) == .visibleArea)
        #expect(CaptureModeKeys.item(typed: "f", keyCode: 3) == .fullPage)
    }

    @Test func capsLockStillReachesTheItem() {
        #expect(CaptureModeKeys.item(typed: "V", keyCode: 9) == .visibleArea)
    }

    @Test func latinLayoutsFollowTheTypedLetterWhereverTheKeySits() {
        #expect(CaptureModeKeys.item(typed: "e", keyCode: 2) == .element)
    }

    @Test func aTypedPunctuationKeyNeverFallsBackToThePhysicalE() {
        #expect(CaptureModeKeys.item(typed: ".", keyCode: 14) == nil)
    }

    @Test func unassignedLettersDoNothing() {
        #expect(CaptureModeKeys.item(typed: "x", keyCode: 7) == nil)
    }

    @Test func nonLatinLayoutsUseThePhysicalPosition() {
        #expect(CaptureModeKeys.item(typed: "у", keyCode: 14) == .element)
        #expect(CaptureModeKeys.item(typed: "м", keyCode: 9) == .visibleArea)
    }

    @Test func deadKeysFallBackToThePhysicalPosition() {
        #expect(CaptureModeKeys.item(typed: "", keyCode: 3) == .fullPage)
    }

    @Test func spaceIsNotACaptureItem() {
        #expect(CaptureModeKeys.item(typed: nil, keyCode: 49) == nil)
    }

    @Test func multiCharacterInputIsIgnored() {
        #expect(CaptureModeKeys.item(typed: "ef", keyCode: 14) == nil)
    }
}

struct CaptureModeHintTests {
    let element = CaptureModeHint.text(mode: .element, targeted: false, dragging: false)
    let targeted = CaptureModeHint.text(mode: .element, targeted: true, dragging: false)
    let region = CaptureModeHint.text(mode: .region, targeted: false, dragging: false)
    let dragging = CaptureModeHint.text(mode: .element, targeted: true, dragging: true)

    @Test func eachStateExplainsItselfDifferently() {
        #expect(Set([element, targeted, region, dragging]).count == 4)
    }

    @Test func aHighlightedTargetSaysWhatAClickDoes() {
        #expect(targeted.hasPrefix("Click"))
    }

    @Test func elementModeStillMentionsDraggingOutARegion() {
        #expect(element.contains("drag") && targeted.contains("drag"))
    }

    @Test func regionModeOnlyDrags() {
        #expect(region.hasPrefix("Drag") && !region.contains("Click"))
    }

    @Test func draggingReadsTheSameInBothModes() {
        #expect(CaptureModeHint.text(mode: .region, targeted: true, dragging: true) == dragging)
    }

    @Test func hintsStayShortSingleLines() {
        #expect([element, targeted, region, dragging].allSatisfy { $0.count <= 48 && !$0.hasSuffix(".") })
    }

    @Test func voiceOverHearsHowToCaptureTheTarget() {
        #expect(CaptureModeHint.accessibilityValue(mode: .element, targeted: true).contains("Return"))
    }

    @Test func voiceOverHearsTheCurrentMode() {
        #expect(CaptureModeHint.accessibilityValue(mode: .region, targeted: false).contains("Region"))
    }
}

struct CaptureSizeReadoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    let size = CGSize(width: 80, height: 22)

    @Test func sizesReadWidthByHeight() {
        #expect(CaptureSizeReadout.text(CGSize(width: 320, height: 180)) == "320 × 180")
    }

    @Test func readoutsRoundAndNeverGoNegative() {
        #expect(CaptureSizeReadout.text(CGSize(width: 319.6, height: -4)) == "320 × 0")
    }

    @Test func overlayDragsConvertToPagePoints() {
        let scaled = CaptureSizeReadout.viewportRect(CGRect(x: 50, y: 40, width: 250, height: 200),
                                                     overlay: CGSize(width: 500, height: 400), viewport: CGSize(width: 1000, height: 800))
        #expect(scaled == CGRect(x: 100, y: 80, width: 500, height: 400))
    }

    @Test func aCollapsedOverlayHasNoReadout() {
        #expect(CaptureSizeReadout.viewportRect(.zero, overlay: .zero, viewport: CGSize(width: 1000, height: 800)) == nil)
    }

    @Test func readoutsRoundOutwardLikeTheCaptureBounds() {
        #expect(CaptureSizeReadout.pointSize(CGRect(x: 10.4, y: 0.5, width: 99.2, height: 20)) == CGSize(width: 100, height: 21))
    }

    @Test func wholePointRectanglesKeepTheirExactSize() {
        #expect(CaptureSizeReadout.pointSize(CGRect(x: 10, y: 10, width: 100, height: 50)) == CGSize(width: 100, height: 50))
    }

    @Test func emptySelectionsReadZero() {
        #expect(CaptureSizeReadout.pointSize(.null) == .zero)
        #expect(CaptureSizeReadout.pointSize(.zero) == .zero)
    }

    @Test func theReadoutSitsUnderTheFramesTrailingCorner() {
        let placed = CaptureSizeReadout.placement(for: CGRect(x: 100, y: 100, width: 200, height: 100), size: size, in: bounds)
        #expect(placed == CGRect(x: 220, y: 206, width: 80, height: 22))
    }

    @Test func framesNearTheBottomPutTheReadoutAboveThem() {
        let placed = CaptureSizeReadout.placement(for: CGRect(x: 100, y: 450, width: 200, height: 140), size: size, in: bounds)
        #expect(placed.maxY <= 450 - 6 && placed.minY >= 8)
    }

    @Test func aFullPageFrameKeepsTheReadoutInsideThePage() {
        let placed = CaptureSizeReadout.placement(for: bounds, size: size, in: bounds)
        #expect(bounds.insetBy(dx: 8, dy: 8).contains(placed))
    }

    @Test func theReadoutNeverHidesUnderTheModeBar() {
        let bar = CGRect(x: 200, y: 540, width: 400, height: 44)
        let placed = CaptureSizeReadout.placement(for: CGRect(x: 300, y: 400, width: 200, height: 120), size: size, in: bounds, avoiding: bar)
        #expect(!placed.intersects(bar))
    }

    @Test func narrowFramesAtTheEdgeKeepTheReadoutOnThePage() {
        let placed = CaptureSizeReadout.placement(for: CGRect(x: 0, y: 100, width: 40, height: 40), size: size, in: bounds)
        #expect(placed.minX >= 8)
    }

    @Test func tinyPanesStillGetAWholeReadout() {
        let placed = CaptureSizeReadout.placement(for: CGRect(x: 0, y: 0, width: 30, height: 20), size: size,
                                                  in: CGRect(x: 0, y: 0, width: 60, height: 30))
        #expect(placed.width == size.width && placed.height == size.height)
    }
}

struct CaptureModeBarLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)

    @Test func widePagesShowLabelsAndKeys() {
        #expect(CaptureModeBarLayout.density(available: 600, full: 560, labels: 420) == .full)
    }

    @Test func mediumPanesDropTheKeycapsFirst() {
        #expect(CaptureModeBarLayout.density(available: 500, full: 560, labels: 420) == .labels)
    }

    @Test func narrowPanesFallBackToIcons() {
        #expect(CaptureModeBarLayout.density(available: 300, full: 560, labels: 420) == .icons)
    }

    @Test func theBarFloatsCentredSixteenPointsAboveTheBottom() {
        let frame = CaptureModeBarLayout.frame(size: CGSize(width: 540, height: 44), in: bounds)
        #expect(frame == CGRect(x: 230, y: 640, width: 540, height: 44))
    }

    @Test func theBarNeverLeavesANarrowPane() {
        let narrow = CaptureModeBarLayout.frame(size: CGSize(width: 540, height: 44), in: CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(narrow.minX >= 0 && narrow.maxX <= 300 && narrow.maxY <= 200)
    }

    @Test func theHintFloatsEightPointsAboveTheBar() {
        let frame = CaptureModeBarLayout.frame(size: CGSize(width: 540, height: 44), in: bounds)
        let hint = CaptureModeBarLayout.hintFrame(size: CGSize(width: 300, height: 30), above: frame, in: bounds)
        #expect(hint == CGRect(x: 350, y: 602, width: 300, height: 30))
    }

    @Test func shortPanesKeepTheHintOnThePage() {
        let squeezed = CaptureModeBarLayout.hintFrame(size: CGSize(width: 300, height: 30), above: CGRect(x: 0, y: 10, width: 100, height: 20),
                                                      in: CGRect(x: 0, y: 0, width: 200, height: 40))
        #expect(squeezed.minY >= 0 && squeezed.width <= 200)
    }
}
