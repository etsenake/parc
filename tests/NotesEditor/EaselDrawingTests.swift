import Foundation

@main
struct EaselDrawingTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: EaselPoint, _ b: EaselPoint, _ tolerance: Double = 1e-6) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }
    static func p(_ x: Double, _ y: Double) -> EaselPoint { EaselPoint(x: x, y: y) }

    static func stroke(_ absolute: [EaselPoint], brush: EaselBrush? = nil) -> EaselItem {
        let placed = EaselDrawing.geometry(absolute)!
        var item = EaselItem(kind: .freehand, frame: placed.frame, points: placed.points)
        item.brush = brush
        return item
    }

    static func object(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000EA")!, title: "Board",
                      createdAt: Date(timeIntervalSinceReferenceDate: 0), modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor
    static func main() {
        capture()
        strokes()
        smoothingAndSimplifying()
        straightLines()
        paths()
        rotationRoundTrip()
        erasing()
        choosingTargets()
        carrying()
        rebinding()
        removingDependents()
        pipeline()
        washi()
        exporting()
        print("EaselDrawingTests passed")
    }

    static func capture() {
        var points: [EaselPoint] = []
        expect(EaselDrawing.append(p(10, 10), to: &points, scale: 1), "The first sample always lands")
        expect(!EaselDrawing.append(p(10.4, 10), to: &points, scale: 1), "Jitter under a point is skipped at 100%")
        expect(EaselDrawing.append(p(10.4, 10), to: &points, scale: 4), "Zoomed in, a quarter point is enough travel")
        expect(!EaselDrawing.append(p(.nan, 3), to: &points, scale: 1), "Broken samples never enter a stroke")
        points = Array(repeating: p(0, 0), count: EaselDrawing.maximumPoints)
        expect(!EaselDrawing.append(p(50, 50), to: &points, scale: 1), "Strokes stop growing at the point budget")
    }

    static func smoothingAndSimplifying() {
        let spiky = [p(0, 0), p(10, 0), p(20, 10), p(30, 0), p(40, 0)]
        let smooth = EaselDrawing.smoothed(spiky)
        expect(smooth.first == spiky.first && smooth.last == spiky.last, "Smoothing keeps both ends where the pen was")
        expect(smooth[2].y < 10 && smooth[2].y > 0, "Smoothing softens a spike without erasing it")
        let line = (0...100).map { p(Double($0), 0.0) }
        expect(EaselDrawing.simplified(line, tolerance: 0.35) == [p(0, 0), p(100, 0)], "A straight run collapses to its two ends")
        let corner = (0...50).map { p(Double($0), 0.0) } + (1...50).map { p(50.0, Double($0)) }
        let kept = EaselDrawing.simplified(corner, tolerance: 0.35)
        expect(kept == [p(0, 0), p(50, 0), p(50, 50)], "A real corner survives simplification")
        let wave = (0...400).map { index -> EaselPoint in
            let x = Double(index) * 0.5
            return p(x, sin(x / 6) * 20)
        }
        let simple = EaselDrawing.simplified(wave, tolerance: 0.35)
        expect(simple.count < wave.count / 3, "A dense curve keeps far fewer points")
        for point in wave {
            let distance = zip(simple, simple.dropFirst()).map { EaselDrawing.segmentDistance(point, $0, $1) }.min() ?? .infinity
            expect(distance <= 0.35 + 1e-9, "Simplified curves stay within the tolerance")
        }
        expect(EaselDrawing.finished([p(5, 5)], scale: 1) == [p(5, 5), p(5, 5)], "A click becomes a dot with two equal points")
        expect(EaselDrawing.finished([p(1, 1), p(9, 9)], scale: 1) == [p(1, 1), p(9, 9)], "Two points pass through untouched")
        let spiral = (0..<20_000).map { index -> EaselPoint in
            let turn = Double(index) * 0.01
            return p(500 + cos(turn) * (10 + turn * 3), 500 + sin(turn) * (10 + turn * 3))
        }
        let tight = EaselDrawing.simplified(spiral, tolerance: 0.35)
        expect(tight.first == spiral.first && tight.last == spiral.last && tight.count < spiral.count, "A long spiral simplifies and keeps its ends")
        for point in stride(from: 0, to: spiral.count, by: 97).map({ spiral[$0] }) {
            let distance = zip(tight, tight.dropFirst()).map { EaselDrawing.segmentDistance(point, $0, $1) }.min() ?? .infinity
            expect(distance <= 0.35 * 1.5 + 1e-9, "A simplified spiral stays close to what was drawn")
        }
        let jitter = (0..<1_000).map { p(Double($0) * 0.01, 0) }
        expect(EaselDrawing.simplified(jitter, tolerance: 0.35).count == 2, "Samples bunched on one spot collapse quickly")
        let finished = EaselDrawing.finished(wave, scale: 2)
        expect(finished.first == wave.first && finished.last == wave.last, "Finishing keeps the stroke's ends")
        expect(EaselDrawing.finished([], scale: 1).isEmpty, "Nothing drawn finishes as nothing")
    }

    static func straightLines() {
        let flat = EaselDrawing.straightEnd(from: p(0, 0), to: p(100, 4), strict: false)
        expect(near(flat.y, 0) && near(flat.x, hypot(100, 4)), "A nearly level line settles exactly level")
        let steep = EaselDrawing.straightEnd(from: p(0, 0), to: p(3, -100), strict: false)
        expect(near(steep.x, 0), "A nearly upright line settles exactly upright")
        let free = EaselDrawing.straightEnd(from: p(0, 0), to: p(100, 58), strict: false)
        expect(free == p(100, 58), "A deliberate angle stays where it was drawn")
        let strict = EaselDrawing.straightEnd(from: p(0, 0), to: p(100, 58), strict: true)
        expect(near(strict.x, strict.y), "Strict lines snap to 45 degree steps")
        let placed = EaselDrawing.geometry([p(10, 20), p(110, 20)])!
        expect(placed.frame == EaselRect(x: 10, y: 20, width: 100, height: 1), "A level line keeps a one point tall frame")
        expect(placed.points == [p(0, 0), p(100, 0)], "Points become relative to the frame")
        expect(EaselDrawing.isStraight(stroke([p(0, 0), p(40, 40)])) && !EaselDrawing.isStraight(stroke([p(0, 0), p(4, 9), p(40, 40)])),
               "Only two point drawings count as straight lines")
    }

    static func paths() {
        expect(EaselDrawing.smoothPath([p(0, 0), p(10, 0)]) == [.move(p(0, 0)), .line(p(10, 0))], "Two points draw a straight segment")
        expect(EaselDrawing.smoothPath([p(3, 3)]) == [.move(p(3, 3)), .line(p(3, 3))], "One point draws a dot")
        let curve = EaselDrawing.smoothPath([p(0, 0), p(10, 0), p(10, 10)])
        expect(curve == [.move(p(0, 0)), .line(p(5, 0)), .quad(p(10, 5), control: p(10, 0)), .line(p(10, 10))],
               "Corners round through midpoints and the ends stay exact")
        expect(EaselDrawing.smoothPath([]).isEmpty, "No points, no path")
    }

    static func rotationRoundTrip() {
        var item = stroke([p(100, 100), p(160, 120), p(200, 180)])
        for rotation in [0.0, 30, -75, 180] {
            for flips in [(false, false), (true, false), (false, true), (true, true)] {
                item.rotation = rotation
                item.flipHorizontal = flips.0 ? true : nil
                item.flipVertical = flips.1 ? true : nil
                let visual = EaselDrawing.visualPoints(item)
                let moved = visual.map { p($0.x + 37, $0.y - 12) }
                guard let placed = EaselDrawing.placing(moved, like: item) else { failTest("Placing failed") }
                var copy = item
                copy.frame = placed.frame; copy.points = placed.points
                let again = EaselDrawing.visualPoints(copy)
                expect(zip(again, moved).allSatisfy { near($0, $1, 1e-6) }, "Placing keeps every visible point for rotation \(rotation) and flips \(flips)")
            }
        }
        var turned = stroke([p(0, 0), p(100, 0)])
        turned.rotation = 90
        let ends = EaselDrawing.visualPoints(turned)
        expect(near(ends[0], p(50.5, -49.5), 1e-6) && near(ends[1], p(50.5, 50.5), 1e-6), "Rotation turns clockwise around the frame centre")
    }

    static func erasing() {
        let marker = stroke([p(0, 0), p(100, 0), p(100, 100)])
        expect(EaselDrawing.touches(marker, from: p(50, 8), to: p(50, 8), scale: 1), "A click near a stroke catches it")
        expect(!EaselDrawing.touches(marker, from: p(50, 20), to: p(50, 20), scale: 1), "A click well away misses")
        expect(EaselDrawing.touches(marker, from: p(50, -50), to: p(60, 60), scale: 1), "A swipe that crosses a stroke catches it")
        expect(!EaselDrawing.touches(marker, from: p(-50, -50), to: p(-40, 60), scale: 1), "A swipe beside a stroke leaves it")
        expect(!EaselDrawing.touches(marker, from: p(50, 8), to: p(50, 8), scale: 2), "Zoomed in, the eraser shrinks on the board to stay the same on screen")
        expect(EaselDrawing.touches(marker, from: p(50, 15), to: p(50, 15), scale: 0.5), "Zoomed out, the eraser covers more of the board")
        expect(near(EaselDrawing.eraserRadius(scale: 2), EaselDrawing.eraserRadius / 2), "The eraser radius scales with zoom")
        var locked = marker
        locked.locked = true
        expect(!EaselDrawing.touches(locked, from: p(50, 0), to: p(50, 0), scale: 1), "Locked drawings never erase")
        let tape = stroke([p(0, 0), p(200, 0)], brush: .washi)
        expect(EaselDrawing.touches(tape, from: p(100, 20), to: p(100, 20), scale: 1), "Tape is caught across its whole width")
        expect(!EaselDrawing.touches(tape, from: p(100, 30), to: p(100, 30), scale: 1), "Tape has an edge")
        expect(!EaselDrawing.touches(tape, from: p(220, 0), to: p(220, 0), scale: 1), "Tape ends are flat, not rounded")
        expect(EaselDrawing.touches(tape, from: p(208, 0), to: p(208, 0), scale: 1), "The eraser still catches a tape end it overlaps")
        var turnedTape = tape
        turnedTape.rotation = 90
        expect(EaselDrawing.touches(turnedTape, from: p(100, -80), to: p(100, -80), scale: 1), "Rotated tape is caught where it shows")
        expect(!EaselDrawing.touches(turnedTape, from: p(20, 0), to: p(20, 0), scale: 1), "Rotated tape no longer covers its old spot")
        let note = object(.sticky, 0, 0, 100, 100)
        expect(!EaselDrawing.touches(note, from: p(50, 50), to: p(50, 50), scale: 1), "The eraser leaves everything but drawings alone")
        let ids = EaselDrawing.erased([marker, tape, note], from: p(10, -5), to: p(10, 5), scale: 1)
        expect(ids == [marker.id, tape.id], "One swipe collects every drawing it crosses")
        let far = stroke((0..<5_000).map { p(Double($0) + 1_000, 1_000) })
        expect(!EaselDrawing.touches(far, from: p(0, 0), to: p(10, 10), scale: 1), "Distant long strokes are skipped by their bounds")
    }

    static func choosingTargets() {
        let note = object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = object(.image, 100, 0, 200, 200, z: 2)
        let section = object(.section, -50, -50, 600, 600, z: 0)
        let over = [p(10, 100), p(90, 100)]
        expect(EaselDrawing.attachmentTarget(for: over, in: [section, note, picture]) == note.id, "A highlight over a sticky sticks to it")
        let overlap = [p(120, 100), p(190, 100)]
        expect(EaselDrawing.attachmentTarget(for: overlap, in: [section, note, picture]) == picture.id, "The topmost object wins")
        expect(EaselDrawing.attachmentTarget(for: [p(-40, 400), p(40, 400)], in: [section, note, picture]) == nil, "Sections never hold highlights")
        expect(EaselDrawing.attachmentTarget(for: [p(150, 300), p(350, 300)], in: [note]) == nil, "A highlight off every object sticks to nothing")
        expect(EaselDrawing.attachmentTarget(for: [p(-100, 100), p(100, 100)], in: [note]) == nil, "Half a stroke is not most of it")
        expect(EaselDrawing.attachmentTarget(for: [p(-30, 100), p(170, 100)], in: [note]) == note.id, "Most of a stroke is enough")
        let doodle = stroke([p(0, 100), p(200, 100)])
        let arrow = object(.arrow, 0, 90, 200, 20, z: 5)
        expect(EaselDrawing.attachmentTarget(for: over, in: [doodle, arrow]) == nil, "Drawings and connectors don't hold highlights")
        var tilted = object(.rectangle, 0, 0, 200, 20, z: 3)
        tilted.rotation = 90
        expect(EaselDrawing.attachmentTarget(for: [p(100, -80), p(100, 80)], in: [tilted]) == tilted.id, "Rotated objects hold strokes along their turned shape")
        expect(EaselDrawing.attachmentTarget(for: [p(20, 10), p(180, 10)], in: [tilted]) == nil, "A turned object no longer covers its old footprint")
        var pinned = object(.image, 0, 0, 200, 200, z: 4)
        pinned.locked = true
        expect(EaselDrawing.attachmentTarget(for: over, in: [note, pinned]) == note.id, "Locked objects act as background, so highlights stick to what's beneath")
        expect(EaselDrawing.attachmentTarget(for: over, in: [pinned]) == nil, "A highlight over only a locked object sticks to nothing")
        let ring = object(.circle, 0, 0, 100, 100, z: 1)
        expect(EaselDrawing.attachmentTarget(for: [p(2, 2), p(12, 12)], in: [ring]) == nil, "Circles don't claim their empty corners")
    }

    static func carrying() {
        let note = object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = stroke([p(20, 50), p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = stroke([p(500, 500), p(600, 600)])
        let before = document([note, highlight, loose])
        var moved = before
        moved.items[0].frame.x += 40; moved.items[0].frame.y += 10
        let carried = EaselAttachments.carry(moved, previous: before, moved: [note.id])
        let after = carried.items[1]
        expect(near(after.frame.x, highlight.frame.x + 40) && near(after.frame.y, highlight.frame.y + 10) && after.points == highlight.points,
               "A highlight follows its sticky across the board")
        expect(carried.items[2] == loose, "Unattached drawings stay put")
        var both = moved
        both.items[1].frame.x += 40; both.items[1].frame.y += 10
        let once = EaselAttachments.carry(both, previous: before, moved: [note.id, highlight.id])
        expect(once.items[1].frame.x == highlight.frame.x + 40, "A highlight moved with its sticky isn't moved twice")
        var grown = before
        grown.items[0].frame.width = 400; grown.items[0].frame.height = 400
        let scaled = EaselAttachments.carry(grown, previous: before, moved: [note.id])
        let ends = EaselDrawing.visualPoints(scaled.items[1])
        expect(near(ends[0], p(40, 100), 1e-6) && near(ends[1], p(360, 100), 1e-6), "Resizing the sticky stretches the highlight with it")
        var typed = before
        typed.items[0].frame.height = 320
        let taller = EaselAttachments.carry(typed, previous: before, moved: [])
        expect(taller.items[1] == highlight, "A sticky growing as you type leaves its highlight where it is")
        var reflowed = before
        reflowed.items[0].frame.x += 30; reflowed.items[0].frame.width = 260
        let pinned = EaselAttachments.carry(reflowed, previous: before, moved: []).items[1]
        expect(pinned.frame.x == highlight.frame.x + 30 && pinned.frame.width == highlight.frame.width,
               "Content changes pin stuck things to the object's corner instead of stretching them")
        var spun = before
        spun.items[0].rotation = 90
        let quietly = EaselDrawing.visualPoints(EaselAttachments.carry(spun, previous: before, moved: []).items[1])
        expect(near(quietly[0], p(150, 20), 1e-6), "A turn always swings stuck things, even when the edit doesn't say what moved")
        let turned = EaselDrawing.visualPoints(EaselAttachments.carry(spun, previous: before, moved: [note.id]).items[1])
        expect(near(turned[0], p(150, 20), 1e-6) && near(turned[1], p(150, 180), 1e-6), "Rotating the sticky swings the highlight around its centre")
        var stamp = object(.image, 90, 90, 20, 20)
        stamp.attachedTo = note.id
        let stamped = document([note, stamp])
        var spunStamp = stamped
        spunStamp.items[0].rotation = 90
        let placed = EaselAttachments.carry(spunStamp, previous: stamped, moved: [note.id]).items[1]
        expect(placed.frame.width == 20 && placed.frame.height == 20 && placed.rotation == 90, "Other stuck objects keep their size and turn with their target")
        var chained = stroke([p(30, 60), p(60, 60)], brush: .washi)
        chained.attachedTo = stamp.id
        let chain = document([note, stamp, chained])
        var shifted = chain
        shifted.items[0].frame.x += 10
        let followed = EaselAttachments.carry(shifted, previous: chain, moved: [note.id])
        expect(followed.items[1].frame.x == stamp.frame.x + 10 && followed.items[2].frame.x == chained.frame.x + 10, "Stuck objects carry what's stuck to them")
        expect(EaselAttachments.carry(before, previous: before, moved: [note.id]) == before, "Nothing moves when nothing changed")
        expect(EaselAttachments.carrying(moved, previous: before, moved: [note.id]).moved == [note.id, highlight.id],
               "Carried followers join the moved set so connectors can reroute to them")
        var recoloured = before
        recoloured.items[0].fill = "#F5E0AC"
        expect(EaselAttachments.carry(recoloured, previous: before, moved: []).items[1] == highlight, "Restyling a target leaves its highlights alone")
        var cycleA = object(.image, 0, 0, 50, 50), cycleB = object(.image, 10, 10, 50, 50)
        cycleA.attachedTo = cycleB.id; cycleB.attachedTo = cycleA.id
        let cycle = document([cycleA, cycleB])
        var nudged = cycle
        nudged.items[0].frame.x += 5
        let settled = EaselAttachments.carry(nudged, previous: cycle, moved: [cycleA.id])
        expect(settled.items[0].frame.x == 5 && settled.items[1].frame.x == 15, "Objects stuck to each other settle in one pass")
    }

    static func rebinding() {
        let note = object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = object(.image, 400, 0, 200, 200, z: 2)
        var highlight = stroke([p(20, 50), p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let before = document([note, picture, highlight])
        var dragged = before
        dragged.items[2].frame.x += 400
        expect(EaselAttachments.carry(dragged, previous: before, moved: [highlight.id]).items[2].attachedTo == picture.id,
               "A highlight dragged onto a picture sticks to the picture")
        var dropped = before
        dropped.items[2].frame.y += 600
        expect(EaselAttachments.carry(dropped, previous: before, moved: [highlight.id]).items[2].attachedTo == nil,
               "A highlight dragged onto empty paper comes unstuck")
        var together = before
        together.items[0].frame.x += 400; together.items[2].frame.x += 400
        expect(EaselAttachments.carry(together, previous: before, moved: [note.id, highlight.id]).items[2].attachedTo == note.id,
               "Moving a highlight with its sticky keeps them together")
        var stamp = object(.image, 80, 80, 40, 40, z: 3)
        stamp.attachedTo = note.id
        var strip = stroke([p(85, 100), p(115, 100)], brush: .washi)
        strip.attachedTo = stamp.id
        let layered = document([note, stamp, strip])
        var both = layered
        both.items[0].frame.x += 300; both.items[2].frame.x += 300
        let settled = EaselAttachments.carry(both, previous: layered, moved: [note.id, strip.id])
        expect(settled.items[1].frame.x == 380 && settled.items[2].attachedTo == stamp.id,
               "Tape dragged with a sticky stays on the stamp that rode along")
        var marker = stroke([p(20, 50), p(180, 50)])
        marker.attachedTo = nil
        let doodled = document([note, marker])
        var drawn = doodled
        drawn.items[1].frame.x += 5
        expect(EaselAttachments.carry(drawn, previous: doodled, moved: [marker.id]).items[1].attachedTo == nil, "Marker doodles never stick")
    }

    static func removingDependents() {
        let note = object(.sticky, 0, 0, 200, 200)
        var first = stroke([p(10, 10), p(40, 40)], brush: .highlighter)
        first.attachedTo = note.id
        var second = object(.image, 20, 20, 10, 10)
        second.attachedTo = first.id
        let other = stroke([p(300, 300), p(310, 310)], brush: .highlighter)
        let board = document([note, first, second, other])
        expect(EaselAttachments.dependents(of: [note.id], in: board) == [first.id, second.id], "Deleting a sticky takes everything stuck to it")
        expect(EaselAttachments.dependents(of: [other.id], in: board).isEmpty, "Nothing is stuck to a lone highlight")
        expect(EaselAttachments.dependents(of: [first.id], in: board) == [second.id], "Dependents follow the chain from where it starts")
        var loopA = object(.image, 0, 0, 40, 40), loopB = object(.image, 50, 0, 40, 40)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        var lost = stroke([p(0, 300), p(50, 300)], brush: .highlighter)
        lost.attachedTo = UUID()
        let tangled = document([loopA, loopB, lost, note])
        expect(EaselAttachments.dependents(of: [loopA.id], in: tangled) == [loopB.id], "Objects stuck to each other don't loop forever")
        expect(EaselDependents.removing([loopA.id], from: tangled).items.map(\.id) == [lost.id, note.id], "Deleting one of a stuck pair takes both")
        expect(EaselDependents.removing([note.id], from: tangled).items.map(\.id) == [loopA.id, loopB.id, lost.id],
               "A highlight stuck to something long gone is left alone")
        var moved = tangled
        moved.items[3].frame.x += 10
        expect(EaselAttachments.carry(moved, previous: tangled, moved: [note.id]).items[2] == lost, "Dangling stickers don't move")
        let chain = EaselDependents.removing([note.id], from: board)
        expect(chain.items.map(\.id) == [other.id], "Deleting the bottom of a chain removes every link")
    }

    static func pipeline() {
        let note = object(.sticky, 0, 0, 200, 200, z: 1)
        var tape = stroke([p(20, 50), p(180, 50)], brush: .washi)
        tape.attachedTo = note.id
        let board = document([note, tape])
        var moved = board
        moved.items[0].frame.x += 25
        let settled = EaselDependents.settle(moved, previous: board, moved: [note.id])
        expect(settled.items[1].frame.x == tape.frame.x + 25, "Settling after a move brings stuck tape along")
        expect(EaselDependents.settle(board, previous: board, moved: []) == board, "Settling an unchanged board changes nothing")
        let removed = EaselDependents.removing([note.id], from: board)
        expect(removed.items.isEmpty, "Deleting a sticky deletes the tape stuck to it")
        expect(EaselDependents.removing([tape.id], from: board).items.map(\.id) == [note.id], "Deleting tape leaves its sticky")
        let section = object(.section, 0, 0, 600, 600, z: 0)
        let inside = object(.sticky, 50, 50, 200, 200, z: 1)
        var held = stroke([p(70, 100), p(230, 100)], brush: .highlighter)
        held.attachedTo = inside.id
        var outside = stroke([p(150, 580), p(150, 640)], brush: .washi)
        outside.attachedTo = inside.id
        let framed = document([section, inside, held, outside])
        var shifted = framed
        shifted.items[0].frame.x += 100
        let result = EaselDependents.settle(shifted, previous: framed, moved: [section.id])
        expect(result.items[1].frame.x == 150 && result.items[2].frame.x == held.frame.x + 100,
               "A highlight carried by its section isn't carried again by its sticky")
        expect(result.items[3].frame.x == outside.frame.x + 100, "Tape hanging off the section still follows its sticky")
    }

    static func exporting() {
        let doodle = stroke([p(0, 0), p(10, 0), p(10, 10)], brush: .marker)
        let marker = EaselVectorExport.drawing(doodle)
        expect(marker.contains("Q") && marker.contains("stroke-linecap:round") && !marker.contains("easel-highlight"),
               "New doodles export as smooth curves with round ends")
        let legacy = EaselVectorExport.element(stroke([p(0, 0), p(10, 0), p(10, 10)]), art: EaselVectorArt())
        expect(!legacy.contains("Q") && legacy.contains("M0 0L10 0L10 10"), "Doodles saved before smoothing export their exact straight segments")
        let highlight = EaselVectorExport.drawing(stroke([p(0, 0), p(80, 0)], brush: .highlighter))
        expect(highlight.contains("class=\"easel-highlight\"") && highlight.contains("stroke-opacity:0.35") && highlight.contains("stroke-width:16"),
               "Highlights export translucent and wide with the multiply blend class")
        expect(!highlight.contains("var(--easel-ink)"), "An automatic highlighter exports in the default highlight colour, not ink")
        let lit = EaselVectorExport.svg([stroke([p(0, 0), p(80, 0)], brush: .highlighter)], art: EaselVectorArt(), title: "Board")
        expect(lit.contains("<style>.easel-highlight{mix-blend-mode:multiply}") && lit.contains("{.easel-highlight{mix-blend-mode:normal}}"),
               "A standalone SVG carries its own highlight blend for light and dark viewers")
        expect(!EaselVectorExport.svg([doodle], art: EaselVectorArt(), title: "Board").contains("<style>"), "Boards without highlights add no styles")
        expect(!EaselVectorExport.css(.standard).contains(".easel-highlight{"), "Page CSS leaves highlight blending to the SVG")
        var strip = stroke([p(10, 10), p(110, 10)], brush: .washi)
        strip.pattern = "dots"
        let tape = EaselVectorExport.element(strip, art: EaselVectorArt())
        expect(tape.contains("<pattern id=\"washi-") && tape.contains("fill:url(#washi-") && tape.contains("<circle"),
               "Tape exports as a pattern fill drawn from its design")
        expect(tape.contains("opacity=\"0.9\"") && tape.contains("translate(10 10) rotate(0)"), "Tape keeps its translucency and placement")
        let svg = EaselVectorExport.svg([strip, doodle], art: EaselVectorArt(), title: "Board")
        expect(svg.components(separatedBy: "<pattern").count == 2, "Each strip carries one pattern")
        func ids(_ text: String) -> [String] {
            text.components(separatedBy: "id=\"").dropFirst().compactMap { $0.components(separatedBy: "\"").first }
        }
        let twice = EaselVectorExport.svg([strip], art: EaselVectorArt(), title: "One") + EaselVectorExport.svg([strip], art: EaselVectorArt(), title: "Two")
        let tapeIDs = ids(twice).filter { $0.hasPrefix("washi") }
        expect(tapeIDs.count == 4 && Set(tapeIDs).count == 4, "The same strip exported twice on one page never reuses a pattern or clip id")
        var twin = strip
        twin.frame.y += 60
        let pair = ids(EaselVectorExport.svg([strip, twin], art: EaselVectorArt(), title: "Pair")).filter { $0.hasPrefix("washi") }
        expect(Set(pair).count == pair.count && pair.count == 4, "Strips that share an id still get their own pattern and clip")
    }

    @MainActor
    static func strokes() {
        var template = EaselItem(kind: .freehand, frame: EaselRect(x: 0, y: 0, width: 1, height: 1), zIndex: 7, color: "#2C6C91")
        template.brush = .marker
        guard let tap = EaselDrawing.strokeItem([p(40, 50)], like: template, straight: false, strict: false, scale: 1) else { failTest("A tap draws") }
        expect(tap.points.count == 2 && tap.points[0] == tap.points[1] && tap.frame.x == 40 && tap.frame.y == 50, "A tap leaves a dot of two equal points")
        expect(tap.brush == .marker && tap.zIndex == 7 && tap.color == "#2C6C91", "New strokes keep the brush, layer and colour they started with")
        let wobble = [p(0, 0), p(30, 1.5), p(60, -1), p(100, 3)]
        guard let line = EaselDrawing.strokeItem(wobble, like: template, straight: true, strict: false, scale: 1) else { failTest("Shift draws") }
        expect(line.points.count == 2 && line.frame.height == 1 && near(line.points[1].x, hypot(100, 3)),
               "Shift turns a wobbly stroke into one level line from where it started")
        guard let curve = EaselDrawing.strokeItem((0...120).map { p(Double($0), sin(Double($0) / 9) * 30) }, like: template,
                                                  straight: false, strict: false, scale: 1) else { failTest("Freehand draws") }
        expect(curve.points.count > 2 && curve.points.count < 121, "Freehand strokes are smoothed and simplified when they finish")
        expect(EaselDrawing.pathElements(curve).contains { if case .quad = $0 { return true } else { return false } },
               "New strokes draw through smooth curves")
        let legacy = stroke([p(0, 0), p(5, 15), p(10, 0)])
        expect(EaselDrawing.pathElements(legacy) == [.move(p(0, 0)), .line(p(5, 15)), .line(p(10, 0))],
               "Doodles saved before smoothing keep their sharp corners")
        var tapeTemplate = template
        tapeTemplate.brush = .washi
        expect(EaselDrawing.strokeItem([p(0, 0), p(2, 1)], like: tapeTemplate, straight: false, strict: false, scale: 1) == nil,
               "A nudge too short for tape lays nothing")
        guard let tape = EaselDrawing.strokeItem([p(0, 0), p(40, 3), p(90, 52)], like: tapeTemplate, straight: false, strict: true, scale: 1) else {
            failTest("Tape draws")
        }
        expect(tape.points.count == 2 && near(tape.points[1].x - tape.points[0].x, tape.points[1].y - tape.points[0].y),
               "Tape is always straight and Shift snaps it to 45 degrees")
        guard let session = try? EaselSession(inMemory: document([]), assets: [:]) else { failTest("Session opens") }
        try? session.perform("Draw") { $0.items.append(curve) }
        expect(session.document.items.count == 1 && session.canUndo, "A finished stroke lands in one change")
        try? session.undo()
        expect(session.document.items.isEmpty && !session.canUndo, "One Undo takes the whole stroke back")
    }

    static func washi() {
        expect(EaselWashi.pattern(named: nil) == .stripes && EaselWashi.pattern(named: "nope") == .stripes, "Unknown patterns fall back to stripes")
        expect(EaselWashi.pattern(named: "kraft") == .kraft, "Saved pattern names come back")
        expect(EaselWashi.storedName(.stripes) == nil && EaselWashi.storedName(.dots) == "dots", "The default pattern isn't written to the file")
        for pattern in EaselWashiPattern.allCases {
            expect(pattern.rawValue.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil, "\(pattern) saves as a valid pattern name")
            for color in [EaselPalette.automaticInk, "#2C6C91", "#123456"] {
                let tile = EaselWashi.tile(pattern, color: color)
                expect(tile.height == EaselWashi.width && tile.width > 0, "\(pattern) tiles span the tape")
                expect(EaselPalette.normalized(tile.base) != nil, "\(pattern) has a real base colour")
                for mark in tile.marks {
                    expect(EaselPalette.normalized(mark.color) != nil && mark.opacity > 0 && mark.opacity <= 1, "\(pattern) marks have real colours")
                    let inside: Bool
                    switch mark.shape {
                    case .rect(let r): inside = r.x >= -1e-9 && r.y >= -1e-9 && r.x + r.width <= tile.width + 1e-9 && r.y + r.height <= tile.height + 1e-9
                    case .circle(let c, let radius): inside = c.x - radius >= 0 && c.y - radius >= 0 && c.x + radius <= tile.width && c.y + radius <= tile.height
                    case .polygon(let points): inside = points.count >= 3 && points.allSatisfy { $0.x >= -1e-9 && $0.y >= -1e-9 && $0.x <= tile.width + 1e-9 && $0.y <= tile.height + 1e-9 }
                    }
                    expect(inside, "\(pattern) marks stay inside their tile so repeats never double up")
                }
            }
        }
        expect(EaselWashi.tile(.dots, color: EaselPalette.automaticInk).base == EaselPalette.hex(.note(.blue), role: .sticky), "Default dots come in blue")
        expect(EaselWashi.tile(.dots, color: "#C0322D").base == EaselPalette.hex(.note(.red), role: .sticky), "Choosing a palette colour retints the tape")
        expect(EaselWashi.tile(.stripes, color: "#123456").base == "#123456", "A custom colour becomes the tape itself")
        let outline = EaselWashi.outline(length: 120, seed: 42)
        expect(outline.count == 16, "Torn tape has seven teeth at each end")
        expect(outline == EaselWashi.outline(length: 120, seed: 42), "The same strip always tears the same way")
        expect(outline != EaselWashi.outline(length: 120, seed: 43), "Different strips tear differently")
        expect(outline.allSatisfy { abs($0.y) <= EaselWashi.width / 2 + 1e-9 }, "Tears stay within the tape's width")
        expect(outline.allSatisfy { $0.x >= -EaselWashi.tooth - 1e-9 && $0.x <= 120 + EaselWashi.tooth + 1e-9 }, "Tears only nibble the ends")
        let tape = stroke([p(10, 10), p(110, 110)], brush: .washi)
        let placement = EaselWashi.placement(tape)!
        expect(near(placement.origin, p(10, 10)) && near(placement.length, hypot(100, 100)) && near(placement.angle, Double.pi / 4), "Tape runs from its first point to its last")
        let first = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        expect(EaselWashi.seed(first) == EaselWashi.seed(first), "Tear seeds come from the strip's ID")
        let clipped = EaselWashi.clipped([p(-5, -5), p(5, -5), p(5, 5), p(-5, 5)], to: EaselRect(x: 0, y: 0, width: 10, height: 10))
        expect(clipped.allSatisfy { $0.x >= 0 && $0.y >= 0 }, "Clipping trims polygons to the tile")
        expect(EaselBrush.marker.title == "Drawing" && EaselBrush.highlighter.title == "Highlight" && EaselBrush.washi.title == "Washi tape",
               "Each brush has a name people hear")
        expect(!EaselBrush.marker.sticksToObjects && EaselBrush.highlighter.sticksToObjects && EaselBrush.washi.sticksToObjects,
               "Highlights and tape stick; doodles don't")
    }
}
