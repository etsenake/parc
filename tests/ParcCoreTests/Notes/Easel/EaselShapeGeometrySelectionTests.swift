import Foundation
import Testing
@testable import ParcCore

struct EaselShapeGeometrySelectionTests {
    @Test func aQuarterTurnSwapsAFrameSWidthAnd() {
        let frame = EaselRect(x: 0, y: 0, width: 200, height: 100)
        #expect(EaselShapeGeometryTestsSupport.close(EaselShapeGeometry.rotatedBounds(frame, degrees: 90), EaselRect(x: 50, y: -50, width: 100, height: 200), 1e-9), "A quarter turn swaps a frame's width and height around its centre")
        #expect(EaselShapeGeometry.rotatedBounds(frame, degrees: 360) == frame, "A full turn is no turn")
        let turned = EaselTransform.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0)).apply(EaselPoint(x: 10, y: 0))
        #expect(EaselShapeGeometryTestsSupport.close(turned.x, 0, 1e-9) && EaselShapeGeometryTestsSupport.close(turned.y, 10, 1e-9), "Positive rotation turns clockwise on the flipped canvas")

        var item = EaselShapeGeometryTestsSupport.shapeItem(.arrowRight, EaselRect(x: 30, y: 40, width: 200, height: 100))
        for degrees in [0.0, 15, 90, 137, -45, 359] {
            for flips in [(false, false), (true, false), (false, true), (true, true)] {
                item.rotation = degrees; item.flipHorizontal = flips.0; item.flipVertical = flips.1
                let transform = EaselShapeGeometry.transform(for: item)
                for point in [EaselPoint(x: 0, y: 0), EaselPoint(x: 31, y: -7), EaselPoint(x: 230, y: 140)] {
                    let back = EaselShapeGeometry.localPoint(transform.apply(point), in: item)
                    #expect(EaselShapeGeometryTestsSupport.close(back.x, point.x, 1e-9) && EaselShapeGeometryTestsSupport.close(back.y, point.y, 1e-9), "Canvas and local points round-trip at \(degrees) degrees with flips \(flips)")
                }
            }
        }
        item.rotation = 90; item.flipHorizontal = nil; item.flipVertical = nil
        #expect(EaselShapeGeometryTestsSupport.close(EaselShapeGeometry.outline(for: item)?.bounds, EaselRect(x: 80, y: -10, width: 100, height: 200), 1e-6), "A rotated shape's outline turns with it")
        let tip = EaselShapeGeometry.edgePoint(of: item, toward: EaselPoint(x: 130, y: 1000))
        #expect(tip.map { EaselShapeGeometryTestsSupport.close($0.x, 130, 1e-6) && EaselShapeGeometryTestsSupport.close($0.y, 190, 1e-6) } == true, "A right arrow turned a quarter clockwise points down")
    }

    @Test func anUprightTriangleLeavesItsTopCornersEmpty() {
        var triangle = EaselShapeGeometryTestsSupport.shapeItem(.triangle, EaselRect(x: 0, y: 0, width: 200, height: 120))
        #expect(EaselShapeGeometry.outline(for: triangle)?.contains(EaselPoint(x: 5, y: 5)) == false, "An upright triangle leaves its top corners empty")
        triangle.flipVertical = true
        #expect(EaselShapeGeometry.outline(for: triangle)?.contains(EaselPoint(x: 5, y: 5)) == true, "A flipped triangle fills its top corners")
        #expect((EaselShapeGeometry.textRect(for: triangle)?.y ?? 100) < 10, "A flipped triangle moves its text to the wide top half")
        var bubble = EaselShapeGeometryTestsSupport.shapeItem(.speechBubble, EaselRect(x: 0, y: 0, width: 200, height: 150))
        #expect(EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 36, y: 140)) == true, "Speech bubble tails start bottom left")
        bubble.flipHorizontal = true
        #expect(EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 164, y: 140)) == true
               && EaselShapeGeometry.outline(for: bubble)?.contains(EaselPoint(x: 36, y: 140)) == false, "A mirrored speech bubble moves its tail to the right")
        #expect(EaselShapeGeometryTestsSupport.close(EaselShapeGeometry.textRect(for: bubble), EaselShapeGeometry.textRect(.speechBubble, in: bubble.frame)), "Mirroring a symmetric text area leaves it in place, so text stays readable")
        let rotated = EaselTransform.rotation(degrees: 30, around: EaselPoint(x: 5, y: 5))
        let mirror = EaselTransform.mirror(horizontally: true, vertically: false, around: EaselPoint(x: 5, y: 5))
        let both = mirror.concatenating(rotated), sample = EaselPoint(x: 17, y: -3)
        let stepwise = rotated.apply(mirror.apply(sample)), combined = both.apply(sample)
        #expect(EaselShapeGeometryTestsSupport.close(stepwise.x, combined.x, 1e-9) && EaselShapeGeometryTestsSupport.close(stepwise.y, combined.y, 1e-9), "Concatenated transforms apply in order")
    }

    @Test
    func unfilledShapesAreHitOnlyNearTheirOutline() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        #expect(!EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: false, scale: 1), "An unfilled shape lets clicks through its middle")
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 101, y: 160), item: plain, selected: false, scale: 1)
               && EaselShapeGeometry.hits(EaselPoint(x: 90, y: 160), item: plain, selected: false, scale: 1), "An unfilled shape is grabbed on and just outside its outline")
        #expect(!EaselShapeGeometry.hits(EaselPoint(x: 80, y: 160), item: plain, selected: false, scale: 1), "Clicks well clear of an unfilled outline miss")
    }

    @Test
    func theOutlineHitBandKeepsItsScreenWidth() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        #expect(!EaselShapeGeometry.hits(EaselPoint(x: 90, y: 160), item: plain, selected: false, scale: 4), "Zooming in tightens the outline band to the same screen distance")
        var ring = EaselShapeGeometryTestsSupport.shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 400, height: 400))
        ring.fillOpacity = 0
        for index in 0..<72 {
            let angle = Double(index) * .pi / 36
            let point = EaselPoint(x: 200 + 201.4 * cos(angle), y: 200 + 201.4 * sin(angle))
            #expect(EaselShapeGeometry.hits(point, item: ring, selected: false, scale: 10), "At 10× zoom the band around a curve keeps its full 1.5 points at \(index * 5) degrees")
        }
    }

    @Test
    func selectedShapesCanBeDraggedFromTheirCentre() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: true, scale: 1), "A selected unfilled shape can be dragged from its middle")
    }

    @Test
    func textMakesAnUnfilledShapeSolidForClicks() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        plain.text = "Label"
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 200, y: 160), item: plain, selected: false, scale: 1), "An unfilled shape with text is solid")
    }

    @Test
    func aThickOutlineHasAWiderHitBand() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var plain = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)
        plain.fillOpacity = 0
        plain.text = ""; plain.strokeWidth = 50
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 78, y: 160), item: plain, selected: false, scale: 1), "Thick outlines widen their hit band")
    }

    @Test
    func aStarIsHitInItsInteriorAndMissesInAnEmptyCorner() {
        let star = EaselShapeGeometryTestsSupport.shapeItem(.star, EaselRect(x: 0, y: 0, width: 200, height: 200))
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 100, y: 110), item: star, selected: false, scale: 1), "A filled star is hit at its heart")
        #expect(!EaselShapeGeometry.hits(EaselPoint(x: 12, y: 12), item: star, selected: false, scale: 1), "A star's empty corners miss")
    }

    @Test
    func tinyShapesKeepAMinimumHitTarget() {
        let tiny = EaselShapeGeometryTestsSupport.shapeItem(.diamond, EaselRect(x: 0, y: 0, width: 12, height: 12))
        #expect(EaselShapeGeometry.hits(EaselPoint(x: -8, y: -8), item: tiny, selected: false, scale: 1), "Tiny shapes keep the 30-point minimum target")
    }

    @Test
    func rotatedShapesAreHitWhereTheyAreDrawn() {
        var thin = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 20))
        thin.rotation = 90
        #expect(EaselShapeGeometry.hits(EaselPoint(x: 100, y: -60), item: thin, selected: false, scale: 1)
               && !EaselShapeGeometry.hits(EaselPoint(x: 180, y: 10), item: thin, selected: false, scale: 1), "Rotated shapes are hit where they are drawn")
    }

    @Test
    func onlyUntouchedSavedShapesUseTheOriginalLook() {
        let frame = EaselRect(x: 100, y: 100, width: 200, height: 120)
        var thin = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 20))
        thin.rotation = 90
        #expect(EaselShapeGeometry.usesOriginalLook(EaselItem(kind: .rectangle, frame: frame))
               && EaselShapeGeometry.usesOriginalLook(EaselItem(kind: .circle, frame: frame))
               && !EaselShapeGeometry.usesOriginalLook(EaselShapeGeometryTestsSupport.shapeItem(.rectangle, frame)) && !EaselShapeGeometry.usesOriginalLook(thin), "Only untouched saved shapes keep the original look and hit rules")
        #expect(EaselShapeGeometry.strokeWidth(of: EaselItem(kind: .rectangle, frame: frame)) == 2.5
               && EaselShapeGeometry.hasVisibleFill(EaselItem(kind: .rectangle, frame: frame)), "Saved shapes keep their 2.5-point outline and wash")
    }

    @Test func aMarqueeInsideAnUnfilledShapePicksWhatsInside() {
        var hollow = EaselShapeGeometryTestsSupport.shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 400, height: 400))
        hollow.fillOpacity = 0
        let inside = EaselRect(x: 150, y: 150, width: 100, height: 100)
        let crossing = EaselRect(x: -20, y: 180, width: 60, height: 40)
        #expect(!EaselShapeGeometry.intersects(inside, item: hollow, selected: false), "A marquee inside an unfilled shape picks what's inside, not the shape")
        #expect(EaselShapeGeometry.intersects(crossing, item: hollow, selected: false), "A marquee crossing an outline picks the shape")
        #expect(EaselShapeGeometry.intersects(inside, item: hollow, selected: true), "Already selected shapes stay in a marquee over them")
        let solid = EaselShapeGeometryTestsSupport.shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 400, height: 400))
        #expect(EaselShapeGeometry.intersects(inside, item: solid, selected: false), "A marquee inside a filled shape picks it")
        #expect(!EaselShapeGeometry.intersects(EaselRect(x: 0, y: 0, width: 20, height: 20), item: solid, selected: false), "A marquee in a circle's empty corner misses it")
        var turned = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 20))
        turned.rotation = 90
        #expect(EaselShapeGeometry.intersects(EaselRect(x: 95, y: -80, width: 10, height: 10), item: turned, selected: false)
               && !EaselShapeGeometry.intersects(EaselRect(x: 160, y: 0, width: 20, height: 20), item: turned, selected: false), "Marquees follow rotated outlines")
    }

    @Test func edgePointsLandOnTheOutline() {
        let box = EaselShapeGeometryTestsSupport.shapeItem(.rectangle, EaselRect(x: 0, y: 0, width: 200, height: 100))
        let right = EaselShapeGeometry.edgePoint(of: box, toward: EaselPoint(x: 1000, y: 50))
        #expect(right.map { EaselShapeGeometryTestsSupport.close($0.x, 200, 1e-6) && EaselShapeGeometryTestsSupport.close($0.y, 50, 1e-6) } == true, "Edge points land on the outline")
        let circle = EaselShapeGeometryTestsSupport.shapeItem(.ellipse, EaselRect(x: 0, y: 0, width: 200, height: 100))
        if let point = EaselShapeGeometry.edgePoint(of: circle, toward: EaselPoint(x: 300, y: 150)) {
            let value = pow((point.x - 100) / 100, 2) + pow((point.y - 50) / 50, 2)
            #expect(abs(value - 1) < 0.01, "Edge points land on curved outlines")
        } else { Issue.record("Ellipses have edge points") }
        var turned = box
        turned.rotation = 90
        let top = EaselShapeGeometry.anchorPoint(of: turned, side: .top)
        #expect(top.map { EaselShapeGeometryTestsSupport.close($0.x, 150, 1e-6) && EaselShapeGeometryTestsSupport.close($0.y, 50, 1e-6) } == true, "A rotated shape's top anchor turns with it: \(String(describing: top))")
        #expect(EaselShapeGeometry.edgePoint(of: box, toward: EaselPoint(x: 100, y: 50)) == nil, "The centre has no direction")
        #expect(EaselShapeGeometry.edgePoint(of: EaselItem(kind: .text, frame: box.frame), toward: EaselPoint(x: 0, y: 0)) == nil, "Only shapes have outlines")
    }

    @Test func textObjectsKeepTodaysPlacement() {
        let frame = EaselRect(x: 40, y: 60, width: 200, height: 120)
        let text = EaselItem(kind: .text, frame: frame, text: "Hello")
        #expect(EaselTextPlacement.box(for: text) == frame && EaselTextPlacement.alignment(for: text) == nil
               && !EaselTextPlacement.centresVertically(text) && !EaselTextPlacement.clipsOverflow(text)
               && EaselTextPlacement.retiresWhenEmpty(text), "Text objects keep today's placement")
        #expect(EaselTextPlacement.fittedFrameHeight(text, textHeight: 300) == 300
               && EaselTextPlacement.fittedFrameHeight(text, textHeight: 20) == 120, "Text objects grow to fit and never shrink")
        let origin = EaselTextPlacement.origin(for: text, textHeight: 30, overflowing: false)
        #expect(origin.x == 40 && origin.y == 60, "Text objects start at their top left")

        var shape = EaselShapeGeometryTestsSupport.shapeItem(.diamond, frame)
        shape.text = "Decide"
        let box = EaselTextPlacement.box(for: shape)
        #expect(box == EaselShapeGeometry.textRect(.diamond, in: frame), "Shapes wrap text inside their own text area")
        #expect(EaselTextPlacement.alignment(for: shape) == .center && EaselTextPlacement.centresVertically(shape)
               && EaselTextPlacement.clipsOverflow(shape) && !EaselTextPlacement.retiresWhenEmpty(shape), "Shape text is centred, clipped and never deletes the shape")
        var measured = false
        #expect(EaselTextPlacement.fittedFrameHeight(shape, textHeight: { measured = true; return 900 }()) == nil && !measured, "Shapes never grow with their text, and never pay for measuring it")
        let centred = EaselTextPlacement.origin(for: shape, textHeight: 20, overflowing: false)
        #expect(centred.x == box.x && centred.y == box.y + ((box.height - 20) / 2).rounded(.down), "Short shape text sits in the middle")
        let top = EaselTextPlacement.origin(for: shape, textHeight: 400, overflowing: true)
        #expect(top.y == box.y, "Overflowing shape text starts at the top so its first lines show")
        shape.textStyle = EaselTextStyle(alignment: .right)
        #expect(EaselTextPlacement.alignment(for: shape) == .right, "A chosen alignment beats the centred default")

        var flipped = EaselShapeGeometryTestsSupport.shapeItem(.triangle, frame)
        flipped.flipVertical = true
        #expect(EaselTextPlacement.box(for: flipped) == EaselShapeGeometry.textRect(.triangle, in: frame)
               && EaselTextPlacement.canvasBox(for: flipped).y < frame.y + 10, "Flipped shapes draw text upright in their own space and edit it at the mirrored spot on the canvas")
        let sticky = EaselItem(kind: .sticky, frame: frame)
        #expect(EaselTextPlacement.box(for: sticky) == EaselBoardObjects.stickyTextBox(sticky) && !EaselTextPlacement.retiresWhenEmpty(sticky), "Stickies type inside their padding and keep their text even when it's empty")
    }
}
