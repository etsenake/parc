import Foundation
import Testing
@testable import ParcCore

struct EaselFreehandDrawingAttachmentTests {
    @Test
    func highlightsAttachToTheTopmostEligibleObject() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = EaselFreehandDrawingTestsSupport.object(.image, 100, 0, 200, 200, z: 2)
        let section = EaselFreehandDrawingTestsSupport.object(.section, -50, -50, 600, 600, z: 0)
        let over = [EaselFreehandDrawingTestsSupport.p(10, 100), EaselFreehandDrawingTestsSupport.p(90, 100)]
        #expect(EaselDrawing.attachmentTarget(for: over, in: [section, note, picture]) == note.id, "A highlight over a sticky sticks to it")
        let overlap = [EaselFreehandDrawingTestsSupport.p(120, 100), EaselFreehandDrawingTestsSupport.p(190, 100)]
        #expect(EaselDrawing.attachmentTarget(for: overlap, in: [section, note, picture]) == picture.id, "The topmost object wins")
    }

    @Test
    func sectionsAndEmptySpaceDoNotHoldHighlights() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = EaselFreehandDrawingTestsSupport.object(.image, 100, 0, 200, 200, z: 2)
        let section = EaselFreehandDrawingTestsSupport.object(.section, -50, -50, 600, 600, z: 0)
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(-40, 400), EaselFreehandDrawingTestsSupport.p(40, 400)], in: [section, note, picture]) == nil, "Sections never hold highlights")
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(150, 300), EaselFreehandDrawingTestsSupport.p(350, 300)], in: [note]) == nil, "A highlight off every object sticks to nothing")
    }

    @Test
    func aHighlightMustMostlyCoverItsTarget() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(-100, 100), EaselFreehandDrawingTestsSupport.p(100, 100)], in: [note]) == nil, "Half a stroke is not most of it")
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(-30, 100), EaselFreehandDrawingTestsSupport.p(170, 100)], in: [note]) == note.id, "Most of a stroke is enough")
    }

    @Test
    func drawingsAndConnectorsDoNotHoldHighlights() {
        let over = [EaselFreehandDrawingTestsSupport.p(10, 100), EaselFreehandDrawingTestsSupport.p(90, 100)]
        let doodle = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 100), EaselFreehandDrawingTestsSupport.p(200, 100)])
        let arrow = EaselFreehandDrawingTestsSupport.object(.arrow, 0, 90, 200, 20, z: 5)
        #expect(EaselDrawing.attachmentTarget(for: over, in: [doodle, arrow]) == nil, "Drawings and connectors don't hold highlights")
    }

    @Test
    func highlightsAttachToTheTurnedShape() {
        var tilted = EaselFreehandDrawingTestsSupport.object(.rectangle, 0, 0, 200, 20, z: 3)
        tilted.rotation = 90
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(100, -80), EaselFreehandDrawingTestsSupport.p(100, 80)], in: [tilted]) == tilted.id, "Rotated objects hold strokes along their turned shape")
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(20, 10), EaselFreehandDrawingTestsSupport.p(180, 10)], in: [tilted]) == nil, "A turned object no longer covers its old footprint")
    }

    @Test
    func lockedItemsDoNotHoldHighlights() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let over = [EaselFreehandDrawingTestsSupport.p(10, 100), EaselFreehandDrawingTestsSupport.p(90, 100)]
        var pinned = EaselFreehandDrawingTestsSupport.object(.image, 0, 0, 200, 200, z: 4)
        pinned.locked = true
        #expect(EaselDrawing.attachmentTarget(for: over, in: [note, pinned]) == note.id, "Locked objects act as background, so highlights stick to what's beneath")
        #expect(EaselDrawing.attachmentTarget(for: over, in: [pinned]) == nil, "A highlight over only a locked object sticks to nothing")
    }

    @Test
    func aCircleDoesNotHoldAHighlightInAnEmptyCorner() {
        let ring = EaselFreehandDrawingTestsSupport.object(.circle, 0, 0, 100, 100, z: 1)
        #expect(EaselDrawing.attachmentTarget(for: [EaselFreehandDrawingTestsSupport.p(2, 2), EaselFreehandDrawingTestsSupport.p(12, 12)], in: [ring]) == nil, "Circles don't claim their empty corners")
    }

    @Test
    func aHighlightFollowsItsStickyAcrossTheBoard() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var moved = before
        moved.items[0].frame.x += 40; moved.items[0].frame.y += 10
        let carried = EaselAttachments.carry(moved, previous: before, moved: [note.id])
        let after = carried.items[1]
        #expect(EaselFreehandDrawingTestsSupport.near(after.frame.x, highlight.frame.x + 40) && EaselFreehandDrawingTestsSupport.near(after.frame.y, highlight.frame.y + 10) && after.points == highlight.points, "A highlight follows its sticky across the board")
        #expect(carried.items[2] == loose, "Unattached drawings stay put")
    }

    @Test
    func aSelectedHighlightDoesNotMoveTwice() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var moved = before
        moved.items[0].frame.x += 40; moved.items[0].frame.y += 10
        var both = moved
        both.items[1].frame.x += 40; both.items[1].frame.y += 10
        let once = EaselAttachments.carry(both, previous: before, moved: [note.id, highlight.id])
        #expect(once.items[1].frame.x == highlight.frame.x + 40, "A highlight moved with its sticky isn't moved twice")
    }

    @Test
    func resizingAStickyStretchesTheHighlight() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var grown = before
        grown.items[0].frame.width = 400; grown.items[0].frame.height = 400
        let scaled = EaselAttachments.carry(grown, previous: before, moved: [note.id])
        let ends = EaselDrawing.visualPoints(scaled.items[1])
        #expect(EaselFreehandDrawingTestsSupport.near(ends[0], EaselFreehandDrawingTestsSupport.p(40, 100), 1e-6) && EaselFreehandDrawingTestsSupport.near(ends[1], EaselFreehandDrawingTestsSupport.p(360, 100), 1e-6), "Resizing the sticky stretches the highlight with it")
    }

    @Test
    func growingWithTextLeavesAHighlightInPlace() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var typed = before
        typed.items[0].frame.height = 320
        let taller = EaselAttachments.carry(typed, previous: before, moved: [])
        #expect(taller.items[1] == highlight, "A sticky growing as you type leaves its highlight where it is")
    }

    @Test
    func reflowKeepsTheHighlightAtTheCornerWithoutStretching() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var reflowed = before
        reflowed.items[0].frame.x += 30; reflowed.items[0].frame.width = 260
        let pinned = EaselAttachments.carry(reflowed, previous: before, moved: []).items[1]
        #expect(pinned.frame.x == highlight.frame.x + 30 && pinned.frame.width == highlight.frame.width, "Content changes pin stuck things to the object's corner instead of stretching them")
    }

    @Test
    func rotatingAStickySwingsItsHighlightAroundTheCentre() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var spun = before
        spun.items[0].rotation = 90
        let quietly = EaselDrawing.visualPoints(EaselAttachments.carry(spun, previous: before, moved: []).items[1])
        #expect(EaselFreehandDrawingTestsSupport.near(quietly[0], EaselFreehandDrawingTestsSupport.p(150, 20), 1e-6), "A turn always swings stuck things, even when the edit doesn't say what moved")
        let turned = EaselDrawing.visualPoints(EaselAttachments.carry(spun, previous: before, moved: [note.id]).items[1])
        #expect(EaselFreehandDrawingTestsSupport.near(turned[0], EaselFreehandDrawingTestsSupport.p(150, 20), 1e-6) && EaselFreehandDrawingTestsSupport.near(turned[1], EaselFreehandDrawingTestsSupport.p(150, 180), 1e-6), "Rotating the sticky swings the highlight around its centre")
    }

    @Test
    func attachedObjectsKeepTheirSizeWhenTurned() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var stamp = EaselFreehandDrawingTestsSupport.object(.image, 90, 90, 20, 20)
        stamp.attachedTo = note.id
        let stamped = EaselFreehandDrawingTestsSupport.document([note, stamp])
        var spunStamp = stamped
        spunStamp.items[0].rotation = 90
        let placed = EaselAttachments.carry(spunStamp, previous: stamped, moved: [note.id]).items[1]
        #expect(placed.frame.width == 20 && placed.frame.height == 20 && placed.rotation == 90, "Other stuck objects keep their size and turn with their target")
    }

    @Test
    func attachedObjectsCarryTheirOwnFollowers() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var stamp = EaselFreehandDrawingTestsSupport.object(.image, 90, 90, 20, 20)
        stamp.attachedTo = note.id
        var chained = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(30, 60), EaselFreehandDrawingTestsSupport.p(60, 60)], brush: .washi)
        chained.attachedTo = stamp.id
        let chain = EaselFreehandDrawingTestsSupport.document([note, stamp, chained])
        var shifted = chain
        shifted.items[0].frame.x += 10
        let followed = EaselAttachments.carry(shifted, previous: chain, moved: [note.id])
        #expect(followed.items[1].frame.x == stamp.frame.x + 10 && followed.items[2].frame.x == chained.frame.x + 10, "Stuck objects carry what's stuck to them")
    }

    @Test
    func unchangedGeometryKeepsAttachmentsStill() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        #expect(EaselAttachments.carry(before, previous: before, moved: [note.id]) == before, "Nothing moves when nothing changed")
    }

    @Test
    func carriedFollowersJoinTheMovedSet() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var moved = before
        moved.items[0].frame.x += 40; moved.items[0].frame.y += 10
        #expect(EaselAttachments.carrying(moved, previous: before, moved: [note.id]).moved == [note.id, highlight.id], "Carried followers join the moved set so connectors can reroute to them")
    }

    @Test
    func restylingAnObjectLeavesItsHighlightAlone() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let loose = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(500, 500), EaselFreehandDrawingTestsSupport.p(600, 600)])
        let before = EaselFreehandDrawingTestsSupport.document([note, highlight, loose])
        var recoloured = before
        recoloured.items[0].fill = "#F5E0AC"
        #expect(EaselAttachments.carry(recoloured, previous: before, moved: []).items[1] == highlight, "Restyling a target leaves its highlights alone")
    }

    @Test
    func cyclicAttachmentsSettleInOnePass() {
        var cycleA = EaselFreehandDrawingTestsSupport.object(.image, 0, 0, 50, 50), cycleB = EaselFreehandDrawingTestsSupport.object(.image, 10, 10, 50, 50)
        cycleA.attachedTo = cycleB.id; cycleB.attachedTo = cycleA.id
        let cycle = EaselFreehandDrawingTestsSupport.document([cycleA, cycleB])
        var nudged = cycle
        nudged.items[0].frame.x += 5
        let settled = EaselAttachments.carry(nudged, previous: cycle, moved: [cycleA.id])
        #expect(settled.items[0].frame.x == 5 && settled.items[1].frame.x == 15, "Objects stuck to each other settle in one pass")
    }

    @Test
    func aDraggedHighlightAttachesToItsNewTarget() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = EaselFreehandDrawingTestsSupport.object(.image, 400, 0, 200, 200, z: 2)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let before = EaselFreehandDrawingTestsSupport.document([note, picture, highlight])
        var dragged = before
        dragged.items[2].frame.x += 400
        #expect(EaselAttachments.carry(dragged, previous: before, moved: [highlight.id]).items[2].attachedTo == picture.id, "A highlight dragged onto a picture sticks to the picture")
    }

    @Test
    func aHighlightDraggedOntoEmptyCanvasDetaches() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = EaselFreehandDrawingTestsSupport.object(.image, 400, 0, 200, 200, z: 2)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let before = EaselFreehandDrawingTestsSupport.document([note, picture, highlight])
        var dropped = before
        dropped.items[2].frame.y += 600
        #expect(EaselAttachments.carry(dropped, previous: before, moved: [highlight.id]).items[2].attachedTo == nil, "A highlight dragged onto empty paper comes unstuck")
    }

    @Test
    func movingAHighlightWithItsStickyKeepsThemTogether() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        let picture = EaselFreehandDrawingTestsSupport.object(.image, 400, 0, 200, 200, z: 2)
        var highlight = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .highlighter)
        highlight.attachedTo = note.id
        let before = EaselFreehandDrawingTestsSupport.document([note, picture, highlight])
        var together = before
        together.items[0].frame.x += 400; together.items[2].frame.x += 400
        #expect(EaselAttachments.carry(together, previous: before, moved: [note.id, highlight.id]).items[2].attachedTo == note.id, "Moving a highlight with its sticky keeps them together")
    }

    @Test
    func movingTapeWithAStickyKeepsItsAttachmentToARidingStamp() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var stamp = EaselFreehandDrawingTestsSupport.object(.image, 80, 80, 40, 40, z: 3)
        stamp.attachedTo = note.id
        var strip = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(85, 100), EaselFreehandDrawingTestsSupport.p(115, 100)], brush: .washi)
        strip.attachedTo = stamp.id
        let layered = EaselFreehandDrawingTestsSupport.document([note, stamp, strip])
        var both = layered
        both.items[0].frame.x += 300; both.items[2].frame.x += 300
        let settled = EaselAttachments.carry(both, previous: layered, moved: [note.id, strip.id])
        #expect(settled.items[1].frame.x == 380 && settled.items[2].attachedTo == stamp.id, "Tape dragged with a sticky stays on the stamp that rode along")
    }

    @Test
    func markerStrokesStayUnattached() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var marker = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)])
        marker.attachedTo = nil
        let doodled = EaselFreehandDrawingTestsSupport.document([note, marker])
        var drawn = doodled
        drawn.items[1].frame.x += 5
        #expect(EaselAttachments.carry(drawn, previous: doodled, moved: [marker.id]).items[1].attachedTo == nil, "Marker doodles never stick")
    }

    @Test
    func attachmentsFormATransitiveDeletionChain() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200)
        var first = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(10, 10), EaselFreehandDrawingTestsSupport.p(40, 40)], brush: .highlighter)
        first.attachedTo = note.id
        var second = EaselFreehandDrawingTestsSupport.object(.image, 20, 20, 10, 10)
        second.attachedTo = first.id
        let other = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(300, 300), EaselFreehandDrawingTestsSupport.p(310, 310)], brush: .highlighter)
        let board = EaselFreehandDrawingTestsSupport.document([note, first, second, other])
        #expect(EaselAttachments.dependents(of: [note.id], in: board) == [first.id, second.id], "Deleting a sticky takes everything stuck to it")
        #expect(EaselAttachments.dependents(of: [other.id], in: board).isEmpty, "Nothing is stuck to a lone highlight")
        #expect(EaselAttachments.dependents(of: [first.id], in: board) == [second.id], "Dependents follow the chain from where it starts")
        let chain = EaselDependents.removing([note.id], from: board)
        #expect(chain.items.map(\.id) == [other.id], "Deleting the bottom of a chain removes every link")
    }

    @Test
    func deletingOneObjectInAnAttachmentLoopRemovesBoth() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200)
        var loopA = EaselFreehandDrawingTestsSupport.object(.image, 0, 0, 40, 40), loopB = EaselFreehandDrawingTestsSupport.object(.image, 50, 0, 40, 40)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        var lost = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 300), EaselFreehandDrawingTestsSupport.p(50, 300)], brush: .highlighter)
        lost.attachedTo = UUID()
        let tangled = EaselFreehandDrawingTestsSupport.document([loopA, loopB, lost, note])
        #expect(EaselAttachments.dependents(of: [loopA.id], in: tangled) == [loopB.id], "Objects stuck to each other don't loop forever")
        #expect(EaselDependents.removing([loopA.id], from: tangled).items.map(\.id) == [lost.id, note.id], "Deleting one of a stuck pair takes both")
    }

    @Test
    func deletingAnUnrelatedObjectKeepsDanglingAttachments() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200)
        var loopA = EaselFreehandDrawingTestsSupport.object(.image, 0, 0, 40, 40), loopB = EaselFreehandDrawingTestsSupport.object(.image, 50, 0, 40, 40)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        var lost = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 300), EaselFreehandDrawingTestsSupport.p(50, 300)], brush: .highlighter)
        lost.attachedTo = UUID()
        let tangled = EaselFreehandDrawingTestsSupport.document([loopA, loopB, lost, note])
        #expect(EaselDependents.removing([note.id], from: tangled).items.map(\.id) == [loopA.id, loopB.id, lost.id], "A highlight stuck to something long gone is left alone")
    }

    @Test
    func movingAnUnrelatedObjectKeepsDanglingAttachmentsStill() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200)
        var loopA = EaselFreehandDrawingTestsSupport.object(.image, 0, 0, 40, 40), loopB = EaselFreehandDrawingTestsSupport.object(.image, 50, 0, 40, 40)
        loopA.attachedTo = loopB.id; loopB.attachedTo = loopA.id
        var lost = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(0, 300), EaselFreehandDrawingTestsSupport.p(50, 300)], brush: .highlighter)
        lost.attachedTo = UUID()
        let tangled = EaselFreehandDrawingTestsSupport.document([loopA, loopB, lost, note])
        var moved = tangled
        moved.items[3].frame.x += 10
        #expect(EaselAttachments.carry(moved, previous: tangled, moved: [note.id]).items[2] == lost, "Dangling stickers don't move")
    }

    @Test
    func settlingCarriesTapeWithItsTarget() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .washi)
        tape.attachedTo = note.id
        let board = EaselFreehandDrawingTestsSupport.document([note, tape])
        var moved = board
        moved.items[0].frame.x += 25
        let settled = EaselDependents.settle(moved, previous: board, moved: [note.id])
        #expect(settled.items[1].frame.x == tape.frame.x + 25, "Settling after a move brings stuck tape along")
    }

    @Test
    func settlingAnUnchangedBoardChangesNothing() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .washi)
        tape.attachedTo = note.id
        let board = EaselFreehandDrawingTestsSupport.document([note, tape])
        #expect(EaselDependents.settle(board, previous: board, moved: []) == board, "Settling an unchanged board changes nothing")
    }

    @Test
    func deletingAStickyTakesItsTape() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .washi)
        tape.attachedTo = note.id
        let board = EaselFreehandDrawingTestsSupport.document([note, tape])
        let removed = EaselDependents.removing([note.id], from: board)
        #expect(removed.items.isEmpty, "Deleting a sticky deletes the tape stuck to it")
    }

    @Test
    func deletingTapeLeavesItsSticky() {
        let note = EaselFreehandDrawingTestsSupport.object(.sticky, 0, 0, 200, 200, z: 1)
        var tape = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(20, 50), EaselFreehandDrawingTestsSupport.p(180, 50)], brush: .washi)
        tape.attachedTo = note.id
        let board = EaselFreehandDrawingTestsSupport.document([note, tape])
        #expect(EaselDependents.removing([tape.id], from: board).items.map(\.id) == [note.id], "Deleting tape leaves its sticky")
    }

    @Test
    func movingASectionCarriesTapeAndHighlightsOnlyOnce() {
        let section = EaselFreehandDrawingTestsSupport.object(.section, 0, 0, 600, 600, z: 0)
        let inside = EaselFreehandDrawingTestsSupport.object(.sticky, 50, 50, 200, 200, z: 1)
        var held = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(70, 100), EaselFreehandDrawingTestsSupport.p(230, 100)], brush: .highlighter)
        held.attachedTo = inside.id
        var outside = EaselFreehandDrawingTestsSupport.stroke([EaselFreehandDrawingTestsSupport.p(150, 580), EaselFreehandDrawingTestsSupport.p(150, 640)], brush: .washi)
        outside.attachedTo = inside.id
        let framed = EaselFreehandDrawingTestsSupport.document([section, inside, held, outside])
        var shifted = framed
        shifted.items[0].frame.x += 100
        let result = EaselDependents.settle(shifted, previous: framed, moved: [section.id])
        #expect(result.items[1].frame.x == 150 && result.items[2].frame.x == held.frame.x + 100, "A highlight carried by its section isn't carried again by its sticky")
        #expect(result.items[3].frame.x == outside.frame.x + 100, "Tape hanging off the section still follows its sticky")
    }

}
