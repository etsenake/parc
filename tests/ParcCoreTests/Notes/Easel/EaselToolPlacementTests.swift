import Foundation
import Testing
@testable import ParcCore

struct EaselToolPlacementTests {
    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    @Test
    func selectHandAndEraserNeverCreateObjects() {
        #expect(!EaselTool.select.createsObjects && !EaselTool.hand.createsObjects && !EaselTool.eraser.createsObjects, "Select, hand and eraser never create objects")
    }

    @Test
    func placementToolsCreateTheirMatchingKinds() {
        #expect(EaselTool.sticky.kind == .sticky && EaselTool.section.kind == .section && EaselTool.ellipse.kind == .circle
               && EaselTool.rectangle.kind == .rectangle && EaselTool.text.kind == .text, "Tools create the matching kinds")
    }

    @Test
    func brushToolsCreateFreehandWithTheirBrush() {
        #expect([EaselTool.marker, .highlighter, .washi].allSatisfy { $0.kind == .freehand && $0.draws }, "Brushes draw doodles")
        #expect(EaselTool.marker.brush == .marker && EaselTool.highlighter.brush == .highlighter && EaselTool.washi.brush == .washi
               && EaselTool.eraser.brush == nil && EaselTool.sticky.brush == nil, "Each brush tool carries its brush")
    }

    @Test
    func connectorToolsCreateAnArrowWithTheirRouting() {
        #expect([EaselTool.straightConnector, .elbowConnector, .curvedConnector].allSatisfy { $0.kind == .arrow && $0.drawsConnector }, "Connector tools draw arrows")
        #expect(EaselTool.straightConnector.routing == .straight && EaselTool.elbowConnector.routing == .elbow
               && EaselTool.curvedConnector.routing == .curved, "Connector tools carry their routing")
        #expect(EaselConnectorRouting.allCases.allSatisfy { EaselTool.connector($0).routing == $0 }, "Routing maps back to its tool")
    }

    @Test
    func placementToolsReturnToSelectAfterOnePlacement() {
        #expect([EaselTool.sticky, .rectangle, .ellipse, .text, .section, .table, .codeBlock].allSatisfy { $0.placesObjects && $0.returnsToSelect }, "Stickies, shapes, text, sections, tables and code go back to Select after one placement")
    }

    @Test
    func stampingStaysArmedForAnotherStamp() {
        #expect(EaselTool.stamp.placesObjects && EaselTool.stamp.staysArmed, "Stamps keep stamping until V or Escape")
    }

    @Test
    func continuousToolsStayArmed() {
        #expect([EaselTool.marker, .highlighter, .washi, .eraser, .straightConnector, .elbowConnector, .curvedConnector, .hand, .select]
               .allSatisfy { $0.staysArmed && !$0.returnsToSelect }, "Drawing tools, connectors and the hand stay armed until V or Escape")
    }

    @Test
    func coreToolsAreAvailable() {
        #expect([EaselTool.select, .hand, .marker, .sticky, .rectangle, .ellipse, .text, .section, .straightConnector,
                .elbowConnector, .curvedConnector].allSatisfy{ $0.isAvailable }, "The core tools are ready")
    }

    @Test
    func aClickPlacedSectionHasANonzeroDefaultSize() {
        let section = EaselTool.section.defaultSize
        #expect(section.width > 0 && section.height > 0, "A clicked section has a size")
    }

    @Test
    func aClickedStickyIsCentredOnTheClick() {
        let sticky = EaselToolGeometry.placedFrame(.sticky, at: EaselPoint(x: 300, y: 200))
        #expect(near(sticky.x + sticky.width / 2, 300) && near(sticky.y + sticky.height / 2, 200), "A clicked sticky is centred on the click")
    }

    @Test
    func clickedTextUsesTheSameFrameAsDoubleClickText() {
        let text = EaselToolGeometry.placedFrame(.text, at: EaselPoint(x: 300, y: 200))
        #expect(text.x == 300 && text.y == 186 && text.width == 280 && text.height == 28, "Clicked text matches the double-click text box")
    }

    @Test
    func anUnmodifiedDragSizesTheSameBoxInEitherDirection() {
        let plain = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 10, y: 20), to: EaselPoint(x: 110, y: 70), square: false, centered: false)
        #expect(plain == EaselRect(x: 10, y: 20, width: 100, height: 50), "A drag sizes the object between start and end")
        let reversed = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 110, y: 70), to: EaselPoint(x: 10, y: 20), square: false, centered: false)
        #expect(reversed == plain, "Dragging up and left sizes the same box")
    }

    @Test
    func shiftKeepsADragSquareInItsDirection() {
        let square = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 40, y: 130), square: true, centered: false)
        #expect(square == EaselRect(x: 40, y: 100, width: 60, height: 60), "Shift keeps the drag square in the drag's direction")
    }

    @Test
    func optionSizesADragFromItsCentre() {
        let centred = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 130, y: 110), square: false, centered: true)
        #expect(centred == EaselRect(x: 70, y: 90, width: 60, height: 20), "Option draws from the centre")
    }

    @Test
    func shiftOptionDrawsACentredSquare() {
        let both = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 100, y: 100), to: EaselPoint(x: 130, y: 110), square: true, centered: true)
        #expect(both == EaselRect(x: 70, y: 70, width: 60, height: 60), "Shift-Option draws a square from the centre")
    }

    @Test
    func aPointDragStillMakesAOnePointFrame() {
        let tiny = EaselToolGeometry.draggedFrame(from: EaselPoint(x: 5, y: 5), to: EaselPoint(x: 5, y: 5), square: false, centered: false)
        #expect(tiny.width >= 1 && tiny.height >= 1, "Sizes never collapse below one point")
    }

    @Test
    func fixedCanvasesMoveOrShrinkFramesToFit() {
        let bounds = EaselRect(x: 0, y: 0, width: 300, height: 200)
        let kept = EaselToolGeometry.constrained(EaselRect(x: 250, y: -20, width: 100, height: 100), to: bounds)
        #expect(kept == EaselRect(x: 200, y: 0, width: 100, height: 100), "Fixed canvases keep new objects inside")
        let shrunk = EaselToolGeometry.constrained(EaselRect(x: 0, y: 0, width: 500, height: 500), to: bounds)
        #expect(shrunk == EaselRect(x: 0, y: 0, width: 300, height: 200), "Objects larger than a fixed canvas shrink to fit")
    }

    @Test
    func aFixedCanvasClampsPointsToItsBounds() {
        let bounds = EaselRect(x: 0, y: 0, width: 300, height: 200)
        #expect(EaselToolGeometry.clamped(EaselPoint(x: -5, y: 400), to: bounds) == EaselPoint(x: 0, y: 200), "Points clamp to a fixed canvas")
    }

    @Test
    func shiftSnapsAnAlmostHorizontalDrag() {
        let start = EaselPoint(x: 100, y: 100)
        let flat = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 200, y: 108))
        #expect(near(flat.y, 100) && flat.x > 199, "Shift turns a nearly flat drag into a flat line")
    }

    @Test
    func shiftSnapsADiagonalWithoutChangingLength() {
        let start = EaselPoint(x: 100, y: 100)
        let diagonal = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 170, y: 166))
        #expect(near(diagonal.x - 100, diagonal.y - 100), "Shift snaps to 45°")
        #expect(near(hypot(diagonal.x - 100, diagonal.y - 100), hypot(70, 66)), "Snapping keeps the drag's length")
    }

    @Test
    func shiftSnapsAnAlmostVerticalDrag() {
        let start = EaselPoint(x: 100, y: 100)
        let up = EaselToolGeometry.snappedLineEnd(from: start, to: EaselPoint(x: 103, y: 20))
        #expect(near(up.x, 100) && up.y < 100, "Shift snaps a steep drag straight up")
    }

    @Test
    func aZeroLengthDragStaysPut() {
        let start = EaselPoint(x: 100, y: 100)
        #expect(EaselToolGeometry.snappedLineEnd(from: start, to: start) == start, "A zero-length drag stays put")
    }

    @Test
    func aConnectorFrameStoresRelativeEndpointsInOrder() {
        let line = EaselToolGeometry.lineItemGeometry(from: EaselPoint(x: 200, y: 50), to: EaselPoint(x: 120, y: 90))
        #expect(line.frame == EaselRect(x: 120, y: 50, width: 80, height: 40), "Connector frames wrap both ends")
        #expect(line.points == [EaselPoint(x: 80, y: 0), EaselPoint(x: 0, y: 40)], "Connector points are relative to the frame and keep their order")
    }

    @Test
    func aFlatConnectorKeepsAOnePointFrame() {
        let flatLine = EaselToolGeometry.lineItemGeometry(from: EaselPoint(x: 0, y: 10), to: EaselPoint(x: 50, y: 10))
        #expect(flatLine.frame.height == 1, "A flat connector keeps a valid one-point frame")
    }
}
