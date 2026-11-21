import Foundation
import Testing
@testable import ParcCore

struct EaselTransformTests {
    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    func near(_ a: EaselPoint, _ b: EaselPoint, _ tolerance: Double = 1e-6) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }

    func near(_ a: EaselRect, _ b: EaselRect, _ tolerance: Double = 1e-6) -> Bool {
        near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) && near(a.width, b.width, tolerance) && near(a.height, b.height, tolerance)
    }

    func item(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                     rotation: Double? = nil, flipH: Bool? = nil, flipV: Bool? = nil) -> EaselItem {
        var value = EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height))
        value.rotation = rotation; value.flipHorizontal = flipH; value.flipVertical = flipV
        if kind == .image { value.assetID = UUID().uuidString.lowercased() + ".png" }
        if kind == .arrow || kind == .freehand { value.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: width, y: height)] }
        return value
    }

    func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Rotation", createdAt: Date(), modifiedAt: Date(), items: items)
    }

    @Test func transforms() throws {
        let quarter = EaselTransform.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0))
        #expect(quarter.a == 0 && quarter.b == 1 && quarter.c == -1 && quarter.d == 0, "Quarter turns use exact cosines")
        #expect(near(quarter.apply(EaselPoint(x: 1, y: 0)), EaselPoint(x: 0, y: 1)), "Positive degrees turn clockwise on a top-down canvas")
        #expect(EaselTransform.rotation(degrees: 360, around: EaselPoint(x: 5, y: 5)).isIdentity, "A full turn is the identity")
        let turn = EaselTransform.rotation(degrees: 33, around: EaselPoint(x: 10, y: 20))
        let inverse = try #require(turn.inverted, "Rotations invert")
        let point = EaselPoint(x: 42, y: -7)
        #expect(near(inverse.apply(turn.apply(point)), point), "The inverse undoes the rotation")
        let mirror = EaselTransform.mirror(horizontally: true, vertically: false, around: EaselPoint(x: 50, y: 0))
        #expect(near(mirror.apply(EaselPoint(x: 40, y: 3)), EaselPoint(x: 60, y: 3)), "Mirroring reflects across the centre line")
        let both = mirror.concatenating(.translation(x: 1, y: 2))
        #expect(near(both.apply(EaselPoint(x: 40, y: 3)), EaselPoint(x: 61, y: 5)), "Concatenation applies the receiver first")
        #expect(near(turn.applyVector(EaselPoint(x: 1, y: 0)), EaselPoint(x: cos(33 * .pi / 180), y: sin(33 * .pi / 180))), "Vectors ignore translation")
    }

    @Test func kindRules() {
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
        var locked = item(.image, 0, 0, 10, 10); locked.locked = true
        #expect(!EaselRotation.canRotate(locked) && !EaselRotation.canFlip(locked), "Locked objects refuse rotation and flips")
        let sticky = item(.sticky, 0, 0, 100, 100, rotation: 30, flipH: true)
        #expect(!EaselRotation.isTransformed(sticky) && EaselRotation.transform(for: sticky).isIdentity, "Stickies ignore stray angles")
        let text = item(.text, 0, 0, 100, 20, rotation: 0, flipH: true)
        #expect(!EaselRotation.isTransformed(text), "Text never mirrors")
    }

    @Test func angles() {
        #expect(EaselRotation.normalized(370) == 10, "Angles wrap past a full turn")
        #expect(EaselRotation.normalized(-190) == 170, "Negative angles wrap into range")
        #expect(EaselRotation.normalized(180) == 180 && EaselRotation.normalized(-180) == 180, "Half a turn reads as 180")
        #expect(EaselRotation.normalized(.nan) == 0, "Broken angles read as upright")
        #expect(EaselRotation.stored(0) == nil && EaselRotation.stored(360) == nil, "Upright objects omit the field")
        #expect(EaselRotation.stored(12.3456) == 12.35, "Stored angles keep two decimals")
        #expect(EaselRotation.stored(-725) == -5, "Stored angles stay within validation range")
        #expect(EaselRotation.snapped(22) == 15 && EaselRotation.snapped(23) == 30 && EaselRotation.snapped(-8) == -15, "Drags land on 15° steps")
    }

    @Test func itemGeometry() throws {
        let bar = item(.image, 0, 0, 100, 40, rotation: 90)
        #expect(near(EaselRotation.bounds(of: bar), EaselRect(x: 30, y: -30, width: 40, height: 100)), "Rotated bounds swap a quarter turn")
        let flipped = item(.image, 3, 4, 10, 20, flipH: true)
        #expect(EaselRotation.bounds(of: flipped) == flipped.frame, "Flips keep the exact frame as bounds")
        let polygon = EaselRotation.polygon(of: bar)
        #expect(near(polygon[0], EaselPoint(x: 70, y: -30)), "The top-left corner turns clockwise to the top right")
        let local = EaselPoint(x: 10, y: 5)
        #expect(near(EaselRotation.localPoint(EaselRotation.canvasPoint(local, in: bar), in: bar), local), "Canvas and item space round-trip")
        let mirrored = item(.rectangle, 0, 0, 100, 50, rotation: 30, flipH: true)
        let round = EaselRotation.localPoint(EaselRotation.canvasPoint(local, in: mirrored), in: mirrored)
        #expect(near(round, local), "Flipped and rotated points round-trip")
        let readable = EaselRotation.readableTransform(for: mirrored, in: EaselRect(x: 10, y: 10, width: 20, height: 10))
        #expect(near(readable.apply(EaselPoint(x: 20, y: 15)), EaselPoint(x: 20, y: 15)) &&
               near(readable.apply(EaselPoint(x: 10, y: 15)), EaselPoint(x: 30, y: 15)), "Readable text mirrors about its own box")
        let box = try #require(EaselRotation.bounds(of: [bar, item(.text, 200, 200, 10, 10)]), "Bounds exist")
        #expect(near(box, EaselRect(x: 30, y: -30, width: 180, height: 240)), "Selection bounds use rotated boxes")
        #expect(EaselGeometryEdit.bounds(of: [item(.text, 1, 2, 3, 4), item(.text, 10, 20, 5, 5)]) == EaselRect(x: 1, y: 2, width: 14, height: 23), "Upright selection bounds stay exactly as before")
    }

    @Test func hitTests() {
        let bar = item(.image, 0, 100, 200, 20, rotation: 90)
        #expect(EaselContentHitTest.contains(EaselPoint(x: 100, y: 15), item: bar, selected: false), "The turned tip is hit")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 110), item: bar, selected: false), "The old upright corner is empty")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 110), item: bar, selected: true), "Selected objects hit their turned box only")
        let ellipse = item(.circle, 0, 0, 200, 50, rotation: 90)
        #expect(EaselContentHitTest.contains(EaselPoint(x: 100, y: -60), item: ellipse, selected: false), "A turned ellipse is hit along its new long axis")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 10, y: 25), item: ellipse, selected: false), "A turned ellipse misses its old ends")
        var stroke = item(.freehand, 0, 0, 100, 100, rotation: 90)
        stroke.points = [EaselPoint(x: 0, y: 50), EaselPoint(x: 100, y: 50)]
        #expect(EaselContentHitTest.contains(EaselPoint(x: 50, y: 5), item: stroke, selected: false), "A turned stroke is hit where it is drawn")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 5, y: 50), item: stroke, selected: false), "A turned stroke misses where it used to be")
        var flippedStroke = item(.freehand, 0, 0, 100, 100, flipH: true)
        flippedStroke.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 20, y: 0)]
        #expect(EaselContentHitTest.contains(EaselPoint(x: 95, y: 2), item: flippedStroke, selected: false), "A mirrored stroke is hit on its mirrored side")
        #expect(!EaselContentHitTest.contains(EaselPoint(x: 5, y: 2), item: flippedStroke, selected: false), "A mirrored stroke misses its old side")
    }

    @Test func marquee() {
        let diamond = item(.image, 0, 0, 100, 100, rotation: 45)
        #expect(!EaselContentHitTest.intersects(EaselRect(x: 0, y: 0, width: 12, height: 12), item: diamond, selected: false), "A box in the empty corner of a turned square misses it")
        #expect(EaselContentHitTest.intersects(EaselRect(x: 45, y: -25, width: 10, height: 10), item: diamond, selected: false), "A box over the turned tip catches it")
        let ellipse = item(.circle, 0, 0, 200, 50, rotation: 90)
        #expect(EaselContentHitTest.intersects(EaselRect(x: 95, y: -70, width: 10, height: 10), item: ellipse, selected: false), "A box over a turned ellipse's end catches it")
        #expect(!EaselContentHitTest.intersects(EaselRect(x: 0, y: 20, width: 10, height: 10), item: ellipse, selected: false), "A box over a turned ellipse's old end misses it")
        let items = [diamond, item(.text, 300, 300, 50, 20)]
        let picked = EaselCanvasSelection.selecting(in: EaselRect(x: 40, y: -30, width: 20, height: 20), items: items, original: [], operation: .replace)
        #expect(picked == [diamond.id], "Marquee selection follows turned outlines")
    }

    @Test func rotatedResize() throws {
        let bar = item(.image, 0, 0, 100, 40, rotation: 90)
        let doc = document([bar])
        let edit = try #require(EaselGeometryEdit(document: doc, selection: [bar.id]), "Edit exists")
        #expect(edit.resizesRotated, "A single turned object resizes along its own axes")
        let fixedBefore = EaselRotation.canvasPoint(EaselPoint(x: 0, y: 20), in: bar)
        let grown = try #require(edit.resized(using: .right, x: 0, y: 20, centering: [])?.first, "Turned resize succeeds")
        #expect(near(grown.frame.width, 120) && near(grown.frame.height, 40), "Dragging along the turned axis grows the width")
        #expect(near(EaselRotation.canvasPoint(EaselPoint(x: grown.frame.x, y: grown.frame.y + 20), in: grown), fixedBefore), "The opposite edge stays put on screen")
        let corner = try #require(edit.resized(using: .bottomRight, x: -10, y: 30, centering: [])?.first, "Corner resize succeeds")
        let anchor = EaselRotation.canvasPoint(EaselPoint(x: 0, y: 0), in: bar)
        #expect(near(EaselRotation.canvasPoint(EaselPoint(x: corner.frame.x, y: corner.frame.y), in: corner), anchor), "The opposite corner stays put on screen")
        #expect(near(corner.frame.width, 130) && near(corner.frame.height, 50), "Corner drags map into the object's axes")
        let local = EaselRect(x: 0, y: 0, width: 140, height: 60)
        #expect(near(EaselRotation.localFrame(bar, from: EaselRotation.recentred(bar, frame: local)), local), "Placed and local frames round-trip")
        let centered = try #require(edit.resized(using: .right, x: 0, y: 10, centering: .both)?.first, "Centred resize succeeds")
        #expect(near(EaselRotation.center(of: centered.frame), EaselRotation.center(of: bar.frame)), "Option keeps the centre")
        let arrowShape = item(.rectangle, 300, 300, 100, 40, rotation: 90)
        guard let crossing = EaselGeometryEdit(document: document([arrowShape]), selection: [arrowShape.id])?
            .resized(using: .right, x: 0, y: -150, centering: [])?.first else { Issue.record("Crossing resize succeeds"); return }
        #expect(crossing.flipHorizontal == true && near(crossing.frame.width, 50), "Dragging past the far edge mirrors a turned shape")
        let photo = item(.image, 300, 300, 100, 50, rotation: 90)
        guard let aspect = EaselGeometryEdit(document: document([photo]), selection: [photo.id])?
            .resizedPreservingAspect(using: .bottomRight, x: -20, y: 40, centering: [])?.first else { Issue.record("Aspect resize succeeds"); return }
        #expect(near(aspect.frame.width / aspect.frame.height, 2), "Turned images keep their aspect")
    }

    @Test func groupRotation() {
        let left = item(.image, 0, 300, 100, 100), right = item(.image, 200, 300, 100, 100, rotation: 10)
        let sticky = item(.sticky, 400, 400, 100, 100)
        var arrow = item(.arrow, 100, 350, 100, 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)]
        let doc = document([left, right, arrow])
        guard let edit = EaselGeometryEdit(document: doc, selection: [left.id, right.id, arrow.id]),
              let turned = edit.rotated(by: 90, around: EaselPoint(x: 150, y: 350)) else { Issue.record("Group rotation succeeds"); return }
        #expect(near(EaselRotation.center(of: turned[0].frame), EaselPoint(x: 150, y: 250)), "Members orbit the shared centre")
        #expect(turned[0].rotation == 90 && turned[1].rotation == 100, "Member angles add up")
        #expect(near(turned[2].frame.x, 150) && near(turned[2].frame.height, 100), "Free arrows follow the turn")
        guard let withSticky = EaselGeometryEdit(document: document([left, sticky]), selection: [left.id, sticky.id])?
            .rotated(by: 45, around: EaselPoint(x: 250, y: 250)) else { Issue.record("Mixed rotation succeeds"); return }
        #expect(withSticky[1] == sticky, "Stickies stay put while the rest turns")
        #expect(EaselGeometryEdit(document: document([sticky]), selection: [sticky.id])?.rotated(by: 15, around: EaselPoint(x: 0, y: 0)) == nil, "A sticky alone refuses to rotate")
        guard let single = EaselGeometryEdit(document: document([right]), selection: [right.id])?
            .rotated(by: 350, around: EaselPoint(x: 0, y: 0))?.first else { Issue.record("Single rotation succeeds"); return }
        #expect(single.frame == right.frame && single.rotation == nil, "A single object spins in place and drops the field at upright")
    }

    @Test func flips() throws {
        let photo = item(.image, 10, 10, 100, 50)
        let once = try #require(EaselRotation.flipped([photo], horizontally: true)?.first, "Flip succeeds")
        #expect(once.flipHorizontal == true && once.frame == photo.frame, "Flipping one object mirrors it in place")
        let twice = try #require(EaselRotation.flipped([once], horizontally: true)?.first, "Second flip succeeds")
        #expect(twice.flipHorizontal == nil, "Flipping twice drops the field")
        let turned = item(.rectangle, 0, 0, 100, 50, rotation: 30)
        let mirror = try #require(EaselRotation.flipped([turned], horizontally: false)?.first, "Vertical flip succeeds")
        #expect(mirror.rotation == -30 && mirror.flipVertical == true, "Flipping a turned object mirrors its angle too")
        let corner = EaselRotation.canvasPoint(EaselPoint(x: 100, y: 0), in: turned)
        let mirroredCorner = EaselRotation.canvasPoint(EaselPoint(x: 100, y: 0), in: mirror)
        let middle = EaselRotation.center(of: turned.frame)
        #expect(near(mirroredCorner, EaselPoint(x: corner.x, y: 2 * middle.y - corner.y)), "A vertical flip mirrors across the horizontal centre line")
        let label = item(.text, 200, 0, 100, 20, rotation: 20), sticky = item(.sticky, 0, 200, 50, 50)
        guard let group = EaselRotation.flipped([photo, label, sticky], horizontally: true),
              let box = EaselRotation.bounds(of: [photo, label, sticky]) else { Issue.record("Group flip succeeds"); return }
        let pivot = EaselRotation.center(of: box).x
        #expect(near(group[0].frame.x, 2 * pivot - 60 - 50) && group[0].flipHorizontal == true, "Group members mirror across the shared centre")
        #expect(near(group[1].frame.x, 2 * pivot - 250 - 50) && group[1].rotation == -20 && group[1].flipHorizontal == nil, "Text mirrors its place but stays readable")
        #expect(group[2] == sticky, "Stickies stay put in a flip")
        #expect(EaselRotation.flipped([label], horizontally: true) == nil, "Text alone can't flip")
    }

    @Test func dragSnapping() throws {
        let photo = item(.image, 0, 0, 100, 100, rotation: 7)
        let drag = try #require(EaselRotationDrag(items: [photo], pointer: EaselPoint(x: 150, y: 50)), "Drag begins")
        let pointer = EaselPoint(x: 50 + 100 * cos(20 * .pi / 180), y: 50 + 100 * sin(20 * .pi / 180))
        guard let snapped = drag.delta(to: pointer, free: false), let free = drag.delta(to: pointer, free: true) else { Issue.record("Deltas exist"); return }
        #expect(near(7 + snapped, 30), "Single objects land on absolute 15° steps")
        #expect(near(free, 20), "Command turns freely")
        let pair = [item(.image, 0, 0, 100, 100, rotation: 90), item(.image, 200, 0, 100, 100)]
        let group = try #require(EaselRotationDrag(items: pair, pointer: EaselPoint(x: 300, y: 50)), "Group drag begins")
        #expect(near(group.pivot, EaselPoint(x: 150, y: 50)), "Groups turn around their shared centre")
        let groupPointer = EaselPoint(x: 150 + 100 * cos(22 * .pi / 180), y: 50 + 100 * sin(22 * .pi / 180))
        #expect(group.delta(to: groupPointer, free: false).map { near($0, 15) } == true, "Group turns step by 15°")
        #expect(EaselRotationDrag(items: [item(.sticky, 0, 0, 10, 10)], pointer: EaselPoint(x: 50, y: 50)) == nil, "Stickies have no rotate drag")
    }

    @Test func editIntegration() throws {
        let photo = item(.image, 0, 0, 100, 100)
        let doc = document([photo])
        guard let edit = EaselGeometryEdit(document: doc, selection: [photo.id]),
              let turned = edit.rotated(by: 45, around: EaselPoint(x: 50, y: 50)),
              let applied = edit.applying(turned, to: doc) else { Issue.record("Rotation applies"); return }
        #expect(applied.items[0].rotation == 45, "Applying carries the angle")
        #expect(!edit.isCurrent(in: applied), "A changed angle cancels a stale gesture")
        guard let flipped = edit.flipped(horizontally: true), let mirrored = edit.applying(flipped, to: doc) else { Issue.record("Flip applies"); return }
        #expect(mirrored.items[0].flipHorizontal == true, "Applying carries flips")
        let near = item(.image, 0, 0, 100, 20, rotation: 90)
        let moving = try #require(EaselGeometryEdit(document: document([near]), selection: [near.id])?.translated(x: -100, y: 0).first, "Move exists")
        #expect(moving.frame.x == 0, "Turned objects can't be dragged past the canvas edge")
        let upright = item(.text, 30, 40, 10, 10)
        let plain = try #require(EaselGeometryEdit(document: document([upright]), selection: [upright.id])?.translated(x: -100, y: -100).first, "Upright move exists")
        #expect(plain.frame.x == 0 && plain.frame.y == 0, "Upright clamping is unchanged")
    }

    @Test func groupResize() {
        let turned = item(.image, 0, 0, 100, 40, rotation: 90), other = item(.text, 200, 0, 100, 40)
        let size = EaselRotation.scaledSize(turned, scaleX: 2, scaleY: 1)
        #expect(near(size.width, 100) && near(size.height, 80), "Scaling a quarter-turned member swaps the axes")
        let doc = document([turned, other])
        guard let edit = EaselGeometryEdit(document: doc, selection: [turned.id, other.id]),
              let resized = edit.resized(using: .right, x: 270, y: 0, centering: []) else { Issue.record("Group resize succeeds"); return }
        #expect(resized[0].rotation == 90 && near(resized[0].frame.height, 80), "Turned members stretch along the screen axis")
        let shape = item(.rectangle, 300, 0, 100, 50)
        guard let crossed = EaselGeometryEdit(document: document([shape]), selection: [shape.id])?
            .resized(using: .right, x: -150, y: 0, centering: [])?.first else { Issue.record("Crossing succeeds"); return }
        #expect(crossed.flipHorizontal == true && crossed.frame.x == 250 && crossed.frame.width == 50, "Crossing an edge mirrors a shape")
        let words = item(.text, 300, 0, 100, 50)
        guard let crossedText = EaselGeometryEdit(document: document([words]), selection: [words.id])?
            .resized(using: .right, x: -150, y: 0, centering: [])?.first else { Issue.record("Text crossing succeeds"); return }
        #expect(crossedText.flipHorizontal == nil, "Crossing an edge keeps text readable")
    }

    @Test func labels() {
        #expect(EaselRotation.turnLabel(45) == "45°", "Whole angles read plainly")
        #expect(EaselRotation.turnLabel(-30) == "\u{2212}30°", "Counter-clockwise angles use a real minus")
        #expect(EaselRotation.turnLabel(12.34) == "12.3°", "Free angles show a tenth")
        #expect(EaselRotation.turnLabel(0) == "0°", "Upright reads zero")
    }

    @Test func vectorExport() {
        let shape = item(.rectangle, 10, 20, 100, 50, rotation: 30, flipH: true)
        let svg = EaselVectorExport.element(shape, art: EaselVectorArt())
        #expect(svg.hasPrefix("<g transform=\"rotate(30 60 45) translate(60 45) scale(-1 1) translate(-60 -45)\">") && svg.hasSuffix("</g>"), "SVG turns and mirrors around the centre")
        let plain = item(.rectangle, 10, 20, 100, 50)
        #expect(!EaselVectorExport.element(plain, art: EaselVectorArt()).hasPrefix("<g transform"), "Upright objects export unchanged")
        let bounds = EaselVectorExport.contentBounds([item(.image, 0, 0, 100, 40, rotation: 90)], margin: 0)
        #expect(near(bounds, EaselRect(x: 26, y: -34, width: 48, height: 108)), "Export bounds include turned corners")
        #expect(EaselVectorExport.matrix(.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0))) == "matrix(0 1 -1 0 0 0)", "Matrices print plainly")
    }

    @Test func chrome() throws {
        let turned = item(.image, 100, 100, 100, 40, rotation: 90)
        let box = EaselRotation.bounds(of: turned)
        let single = EaselSelectionChrome(frame: box, items: [turned])
        #expect(single.isTurned && single.frame == turned.frame, "A single turned object keeps its own frame for handles")
        #expect(near(single.point(.topLeft), EaselPoint(x: 170, y: 70)), "Handles sit on the turned corners")
        let tip = single.point(.bottomRight)
        #expect(single.handle(at: EaselPoint(x: tip.x + 3, y: tip.y - 3), scale: 1, where: { _ in true }) == .bottomRight, "Turned handles are hit where drawn")
        let outward = single.outward(.topLeft)
        #expect(near(outward, EaselPoint(x: sqrt(0.5), y: -sqrt(0.5))), "The rotate zone points away from the turned corner")
        let zone = try #require(single.rotateZones(scale: 1).first(where: { $0.corner == .topLeft })?.rect, "Zones exist")
        let middle = EaselPoint(x: zone.x + zone.width / 2, y: zone.y + zone.height / 2)
        #expect(single.rotateZone(at: middle, scale: 1) == .topLeft, "Rotate zones find their corner")
        #expect(!EaselContentHitTest.contains(middle, item: turned, selected: true), "Rotate zones sit outside the object")
        let group = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 300, height: 100), items: [turned, item(.text, 0, 0, 10, 10)])
        #expect(!group.isTurned && near(group.point(.bottomRight), EaselPoint(x: 300, y: 100)), "Groups keep an upright box")
        let flippedOnly = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 10, height: 10), items: [item(.image, 0, 0, 10, 10, flipH: true)])
        #expect(!flippedOnly.isTurned, "Mirrored but upright objects keep upright handles")
        let zoomed = EaselSelectionChrome(frame: EaselRect(x: 0, y: 0, width: 100, height: 100), items: [])
        let small = try #require(zoomed.rotateZones(scale: 2).first?.rect, "Zoomed zones exist")
        #expect(near(small.width, 9), "Rotate zones keep their on-screen size when zoomed")
    }
}
