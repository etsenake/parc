import Foundation
import Testing
@testable import ParcCore

struct EaselTransformGeometryTests {
    @Test func quarterTurnsUseExactCosines() throws {
        let quarter = EaselTransform.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0))
        #expect(quarter.a == 0 && quarter.b == 1 && quarter.c == -1 && quarter.d == 0, "Quarter turns use exact cosines")
        #expect(EaselTransformTestsSupport.near(quarter.apply(EaselPoint(x: 1, y: 0)), EaselPoint(x: 0, y: 1)), "Positive degrees turn clockwise on a top-down canvas")
        #expect(EaselTransform.rotation(degrees: 360, around: EaselPoint(x: 5, y: 5)).isIdentity, "A full turn is the identity")
        let turn = EaselTransform.rotation(degrees: 33, around: EaselPoint(x: 10, y: 20))
        let inverse = try #require(turn.inverted, "Rotations invert")
        let point = EaselPoint(x: 42, y: -7)
        #expect(EaselTransformTestsSupport.near(inverse.apply(turn.apply(point)), point), "The inverse undoes the rotation")
        let mirror = EaselTransform.mirror(horizontally: true, vertically: false, around: EaselPoint(x: 50, y: 0))
        #expect(EaselTransformTestsSupport.near(mirror.apply(EaselPoint(x: 40, y: 3)), EaselPoint(x: 60, y: 3)), "Mirroring reflects across the centre line")
        let both = mirror.concatenating(.translation(x: 1, y: 2))
        #expect(EaselTransformTestsSupport.near(both.apply(EaselPoint(x: 40, y: 3)), EaselPoint(x: 61, y: 5)), "Concatenation applies the receiver first")
        #expect(EaselTransformTestsSupport.near(turn.applyVector(EaselPoint(x: 1, y: 0)), EaselPoint(x: cos(33 * .pi / 180), y: sin(33 * .pi / 180))), "Vectors ignore translation")
    }

    @Test func rotates() {
        for kind in [EaselItemKind.text, .image, .rectangle, .circle, .freehand, .stamp] {
            #expect(EaselRotation.isRotatable(kind), "\(kind) rotates")
        }
        for kind in [EaselItemKind.arrow, .webCard, .browser, .link, .sticky, .section, .table, .code] {
            #expect(!EaselRotation.isRotatable(kind), "\(kind) stays upright")
        }
        for kind in [EaselItemKind.image, .rectangle, .circle, .freehand, .stamp] { #expect(EaselRotation.isFlippable(kind), "\(kind) flips") }
        for kind in [EaselItemKind.text, .arrow, .webCard, .browser, .link, .sticky, .section, .table, .code] {
            #expect(!EaselRotation.isFlippable(kind), "\(kind) never mirrors")
        }
        var locked = EaselTransformTestsSupport.item(.image, 0, 0, 10, 10); locked.locked = true
        #expect(!EaselRotation.canRotate(locked) && !EaselRotation.canFlip(locked), "Locked objects refuse rotation and flips")
        let sticky = EaselTransformTestsSupport.item(.sticky, 0, 0, 100, 100, rotation: 30, flipH: true)
        #expect(!EaselRotation.isTransformed(sticky) && EaselRotation.transform(for: sticky).isIdentity, "Stickies ignore stray angles")
        let text = EaselTransformTestsSupport.item(.text, 0, 0, 100, 20, rotation: 0, flipH: true)
        #expect(!EaselRotation.isTransformed(text), "Text never mirrors")
    }

    @Test func anglesWrapPastAFullTurn() {
        #expect(EaselRotation.normalized(370) == 10, "Angles wrap past a full turn")
        #expect(EaselRotation.normalized(-190) == 170, "Negative angles wrap into range")
        #expect(EaselRotation.normalized(180) == 180 && EaselRotation.normalized(-180) == 180, "Half a turn reads as 180")
        #expect(EaselRotation.normalized(.nan) == 0, "Broken angles read as upright")
        #expect(EaselRotation.stored(0) == nil && EaselRotation.stored(360) == nil, "Upright objects omit the field")
        #expect(EaselRotation.stored(12.3456) == 12.35, "Stored angles keep two decimals")
        #expect(EaselRotation.stored(-725) == -5, "Stored angles stay within validation range")
        #expect(EaselRotation.snapped(22) == 15 && EaselRotation.snapped(23) == 30 && EaselRotation.snapped(-8) == -15, "Drags land on 15° steps")
    }

    @Test func rotatedBoundsSwapAQuarterTurn() throws {
        let bar = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)
        #expect(EaselTransformTestsSupport.near(EaselRotation.bounds(of: bar), EaselRect(x: 30, y: -30, width: 40, height: 100)), "Rotated bounds swap a quarter turn")
        let flipped = EaselTransformTestsSupport.item(.image, 3, 4, 10, 20, flipH: true)
        #expect(EaselRotation.bounds(of: flipped) == flipped.frame, "Flips keep the exact frame as bounds")
        let polygon = EaselRotation.polygon(of: bar)
        #expect(EaselTransformTestsSupport.near(polygon[0], EaselPoint(x: 70, y: -30)), "The top-left corner turns clockwise to the top right")
        let local = EaselPoint(x: 10, y: 5)
        #expect(EaselTransformTestsSupport.near(EaselRotation.localPoint(EaselRotation.canvasPoint(local, in: bar), in: bar), local), "Canvas and item space round-trip")
        let mirrored = EaselTransformTestsSupport.item(.rectangle, 0, 0, 100, 50, rotation: 30, flipH: true)
        let round = EaselRotation.localPoint(EaselRotation.canvasPoint(local, in: mirrored), in: mirrored)
        #expect(EaselTransformTestsSupport.near(round, local), "Flipped and rotated points round-trip")
        let readable = EaselRotation.readableTransform(for: mirrored, in: EaselRect(x: 10, y: 10, width: 20, height: 10))
        #expect(EaselTransformTestsSupport.near(readable.apply(EaselPoint(x: 20, y: 15)), EaselPoint(x: 20, y: 15)) &&
               EaselTransformTestsSupport.near(readable.apply(EaselPoint(x: 10, y: 15)), EaselPoint(x: 30, y: 15)), "Readable text mirrors about its own box")
        let box = try #require(EaselRotation.bounds(of: [bar, EaselTransformTestsSupport.item(.text, 200, 200, 10, 10)]), "Bounds exist")
        #expect(EaselTransformTestsSupport.near(box, EaselRect(x: 30, y: -30, width: 180, height: 240)), "Selection bounds use rotated boxes")
        #expect(EaselGeometryEdit.bounds(of: [EaselTransformTestsSupport.item(.text, 1, 2, 3, 4), EaselTransformTestsSupport.item(.text, 10, 20, 5, 5)]) == EaselRect(x: 1, y: 2, width: 14, height: 23), "Upright selection bounds stay exactly as before")
    }

    @Test func theTurnedTipIsHit() {
        let bar = EaselTransformTestsSupport.item(.image, 0, 100, 200, 20, rotation: 90)
        #expect(EaselContentHitTest.contains(EaselPoint(x: 100, y: 15), item: bar, selected: false), "The turned tip is hit")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 110), item: bar, selected: false), "The old upright corner is empty")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 110), item: bar, selected: true), "Selected objects hit their turned box only")
        let ellipse = EaselTransformTestsSupport.item(.circle, 0, 0, 200, 50, rotation: 90)
        #expect(EaselContentHitTest.contains(EaselPoint(x: 100, y: -60), item: ellipse, selected: false), "A turned ellipse is hit along its new long axis")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 25), item: ellipse, selected: false), "A turned ellipse misses its old ends")
        var stroke = EaselTransformTestsSupport.item(.freehand, 0, 0, 100, 100, rotation: 90)
        stroke.points = [EaselPoint(x: 0, y: 50), EaselPoint(x: 100, y: 50)]
        #expect(EaselContentHitTest.contains(EaselPoint(x: 50, y: 5), item: stroke, selected: false), "A turned stroke is hit where it is drawn")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 5, y: 50), item: stroke, selected: false), "A turned stroke misses where it used to be")
        var flippedStroke = EaselTransformTestsSupport.item(.freehand, 0, 0, 100, 100, flipH: true)
        flippedStroke.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 20, y: 0)]
        #expect(EaselContentHitTest.contains(EaselPoint(x: 95, y: 2), item: flippedStroke, selected: false), "A mirrored stroke is hit on its mirrored side")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 5, y: 2), item: flippedStroke, selected: false), "A mirrored stroke misses its old side")
    }

    @Test func aBoxInTheEmptyCornerOfATurned() {
        let diamond = EaselTransformTestsSupport.item(.image, 0, 0, 100, 100, rotation: 45)
        #expect(!EaselContentHitTest.intersects(EaselRect(x: 0, y: 0, width: 12, height: 12), item: diamond, selected: false), "A box in the empty corner of a turned square misses it")
        #expect(EaselContentHitTest.intersects(EaselRect(x: 45, y: -25, width: 10, height: 10), item: diamond, selected: false), "A box over the turned tip catches it")
        let ellipse = EaselTransformTestsSupport.item(.circle, 0, 0, 200, 50, rotation: 90)
        #expect(EaselContentHitTest.intersects(EaselRect(x: 95, y: -70, width: 10, height: 10), item: ellipse, selected: false), "A box over a turned ellipse's end catches it")
        #expect(!EaselContentHitTest.intersects(EaselRect(x: 0, y: 20, width: 10, height: 10), item: ellipse, selected: false), "A box over a turned ellipse's old end misses it")
        let items = [diamond, EaselTransformTestsSupport.item(.text, 300, 300, 50, 20)]
        let picked = EaselCanvasSelection.selecting(in: EaselRect(x: 40, y: -30, width: 20, height: 20), items: items, original: [], operation: .replace)
        #expect(picked == [diamond.id], "Marquee selection follows turned outlines")
    }

    @Test
    func aTurnedEdgeResizesAlongItsOwnAxisAndKeepsTheOppositeEdge() throws {
        let bar = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)
        let doc = EaselTransformTestsSupport.document([bar])
        let edit = try #require(EaselGeometryEdit(document: doc, selection: [bar.id]), "Edit exists")
        #expect(edit.resizesRotated, "A single turned object resizes along its own axes")
        let fixedBefore = EaselRotation.canvasPoint(EaselPoint(x: 0, y: 20), in: bar)
        let grown = try #require(edit.resized(using: .right, x: 0, y: 20, centering: [])?.first, "Turned resize succeeds")
        #expect(EaselTransformTestsSupport.near(grown.frame.width, 120) && EaselTransformTestsSupport.near(grown.frame.height, 40), "Dragging along the turned axis grows the width")
        #expect(EaselTransformTestsSupport.near(EaselRotation.canvasPoint(EaselPoint(x: grown.frame.x, y: grown.frame.y + 20), in: grown), fixedBefore), "The opposite edge stays put on screen")
    }

    @Test
    func aTurnedCornerResizesInLocalAxesAndKeepsItsOppositeCorner() throws {
        let bar = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)
        let doc = EaselTransformTestsSupport.document([bar])
        let edit = try #require(EaselGeometryEdit(document: doc, selection: [bar.id]), "Edit exists")
        let corner = try #require(edit.resized(using: .bottomRight, x: -10, y: 30, centering: [])?.first, "Corner resize succeeds")
        let anchor = EaselRotation.canvasPoint(EaselPoint(x: 0, y: 0), in: bar)
        #expect(EaselTransformTestsSupport.near(EaselRotation.canvasPoint(EaselPoint(x: corner.frame.x, y: corner.frame.y), in: corner), anchor), "The opposite corner stays put on screen")
        #expect(EaselTransformTestsSupport.near(corner.frame.width, 130) && EaselTransformTestsSupport.near(corner.frame.height, 50), "Corner drags map into the object's axes")
    }

    @Test
    func placedAndLocalFramesRoundTrip() {
        let bar = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)
        let local = EaselRect(x: 0, y: 0, width: 140, height: 60)
        #expect(EaselTransformTestsSupport.near(EaselRotation.localFrame(bar, from: EaselRotation.recentred(bar, frame: local)), local), "Placed and local frames round-trip")
    }

    @Test
    func optionResizingATurnedObjectKeepsItsCentre() throws {
        let bar = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)
        let doc = EaselTransformTestsSupport.document([bar])
        let edit = try #require(EaselGeometryEdit(document: doc, selection: [bar.id]), "Edit exists")
        let centered = try #require(edit.resized(using: .right, x: 0, y: 10, centering: .both)?.first, "Centred resize succeeds")
        #expect(EaselTransformTestsSupport.near(EaselRotation.center(of: centered.frame), EaselRotation.center(of: bar.frame)), "Option keeps the centre")
    }

    @Test
    func draggingPastTheFarEdgeMirrorsATurnedShape() {
        let arrowShape = EaselTransformTestsSupport.item(.rectangle, 300, 300, 100, 40, rotation: 90)
        guard let crossing = EaselGeometryEdit(document: EaselTransformTestsSupport.document([arrowShape]), selection: [arrowShape.id])?
            .resized(using: .right, x: 0, y: -150, centering: [])?.first else { Issue.record("Crossing resize succeeds"); return }
        #expect(crossing.flipHorizontal == true && EaselTransformTestsSupport.near(crossing.frame.width, 50), "Dragging past the far edge mirrors a turned shape")
    }

    @Test
    func resizingATurnedImageKeepsItsAspect() {
        let photo = EaselTransformTestsSupport.item(.image, 300, 300, 100, 50, rotation: 90)
        guard let aspect = EaselGeometryEdit(document: EaselTransformTestsSupport.document([photo]), selection: [photo.id])?
            .resizedPreservingAspect(using: .bottomRight, x: -20, y: 40, centering: [])?.first else { Issue.record("Aspect resize succeeds"); return }
        #expect(EaselTransformTestsSupport.near(aspect.frame.width / aspect.frame.height, 2), "Turned images keep their aspect")
    }

    @Test func scalingAQuarterTurnedMemberSwapsTheAxes() {
        let turned = EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90), other = EaselTransformTestsSupport.item(.text, 200, 0, 100, 40)
        let size = EaselRotation.scaledSize(turned, scaleX: 2, scaleY: 1)
        #expect(EaselTransformTestsSupport.near(size.width, 100) && EaselTransformTestsSupport.near(size.height, 80), "Scaling a quarter-turned member swaps the axes")
        let doc = EaselTransformTestsSupport.document([turned, other])
        guard let edit = EaselGeometryEdit(document: doc, selection: [turned.id, other.id]),
              let resized = edit.resized(using: .right, x: 270, y: 0, centering: []) else { Issue.record("Group resize succeeds"); return }
        #expect(resized[0].rotation == 90 && EaselTransformTestsSupport.near(resized[0].frame.height, 80), "Turned members stretch along the screen axis")
        let shape = EaselTransformTestsSupport.item(.rectangle, 300, 0, 100, 50)
        guard let crossed = EaselGeometryEdit(document: EaselTransformTestsSupport.document([shape]), selection: [shape.id])?
            .resized(using: .right, x: -150, y: 0, centering: [])?.first else { Issue.record("Crossing succeeds"); return }
        #expect(crossed.flipHorizontal == true && crossed.frame.x == 250 && crossed.frame.width == 50, "Crossing an edge mirrors a shape")
        let words = EaselTransformTestsSupport.item(.text, 300, 0, 100, 50)
        guard let crossedText = EaselGeometryEdit(document: EaselTransformTestsSupport.document([words]), selection: [words.id])?
            .resized(using: .right, x: -150, y: 0, centering: [])?.first else { Issue.record("Text crossing succeeds"); return }
        #expect(crossedText.flipHorizontal == nil, "Crossing an edge keeps text readable")
    }

    @Test func aSingleTurnedObjectKeepsItsOwnFrame() throws {
        let turned = EaselTransformTestsSupport.item(.image, 100, 100, 100, 40, rotation: 90)
        let box = EaselRotation.bounds(of: turned)
        let single = EaselSelectionChrome(frame: box, items: [turned])
        #expect(single.isTurned && single.frame == turned.frame, "A single turned object keeps its own frame for handles")
        #expect(EaselTransformTestsSupport.near(single.point(.topLeft), EaselPoint(x: 170, y: 70)), "Handles sit on the turned corners")
        let tip = single.point(.bottomRight)
        #expect(single.handle(at: EaselPoint(x: tip.x + 3, y: tip.y - 3), scale: 1, where: { _ in true }) == .bottomRight, "Turned handles are hit where drawn")
        let outward = single.outward(.topLeft)
        #expect(EaselTransformTestsSupport.near(outward, EaselPoint(x: sqrt(0.5), y: -sqrt(0.5))), "The rotate zone points away from the turned corner")
        let zone = try #require(single.rotateZones(scale: 1).first(where: { $0.corner == .topLeft })?.rect, "Zones exist")
        let middle = EaselPoint(x: zone.x + zone.width / 2, y: zone.y + zone.height / 2)
        #expect(single.rotateZone(at: middle, scale: 1) == .topLeft, "Rotate zones find their corner")
        #expect(!EaselContentHitTest.contains(middle, item: turned, selected: true), "Rotate zones sit outside the object")
        let group = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 300, height: 100), items: [turned, EaselTransformTestsSupport.item(.text, 0, 0, 10, 10)])
        #expect(!group.isTurned && EaselTransformTestsSupport.near(group.point(.bottomRight), EaselPoint(x: 300, y: 100)), "Groups keep an upright box")
        let flippedOnly = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 10, height: 10), items: [EaselTransformTestsSupport.item(.image, 0, 0, 10, 10, flipH: true)])
        #expect(!flippedOnly.isTurned, "Mirrored but upright objects keep upright handles")
        let zoomed = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 100, height: 100), items: [])
        let small = try #require(zoomed.rotateZones(scale: 2).first?.rect, "Zoomed zones exist")
        #expect(EaselTransformTestsSupport.near(small.width, 9), "Rotate zones keep their on-screen size when zoomed")
    }
}
