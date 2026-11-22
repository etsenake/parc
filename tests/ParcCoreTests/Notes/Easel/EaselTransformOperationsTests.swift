import Foundation
import Testing
@testable import ParcCore

struct EaselTransformOperationsTests {
    @Test func membersOrbitTheSharedCentre() {
        let left = EaselTransformTestsSupport.item(.image, 0, 300, 100, 100), right = EaselTransformTestsSupport.item(.image, 200, 300, 100, 100, rotation: 10)
        let sticky = EaselTransformTestsSupport.item(.sticky, 400, 400, 100, 100)
        var arrow = EaselTransformTestsSupport.item(.arrow, 100, 350, 100, 1)
        arrow.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)]
        let doc = EaselTransformTestsSupport.document([left, right, arrow])
        guard let edit = EaselGeometryEdit(document: doc, selection: [left.id, right.id, arrow.id]),
              let turned = edit.rotated(by: 90, around: EaselPoint(x: 150, y: 350)) else { Issue.record("Group rotation succeeds"); return }
        #expect(EaselTransformTestsSupport.near(EaselRotation.center(of: turned[0].frame), EaselPoint(x: 150, y: 250)), "Members orbit the shared centre")
        #expect(turned[0].rotation == 90 && turned[1].rotation == 100, "Member angles add up")
        #expect(EaselTransformTestsSupport.near(turned[2].frame.x, 150) && EaselTransformTestsSupport.near(turned[2].frame.height, 100), "Free arrows follow the turn")
        guard let withSticky = EaselGeometryEdit(document: EaselTransformTestsSupport.document([left, sticky]), selection: [left.id, sticky.id])?
            .rotated(by: 45, around: EaselPoint(x: 250, y: 250)) else { Issue.record("Mixed rotation succeeds"); return }
        #expect(withSticky[1] == sticky, "Stickies stay put while the rest turns")
        #expect(EaselGeometryEdit(document: EaselTransformTestsSupport.document([sticky]), selection: [sticky.id])?.rotated(by: 15, around: EaselPoint(x: 0, y: 0)) == nil, "A sticky alone refuses to rotate")
        guard let single = EaselGeometryEdit(document: EaselTransformTestsSupport.document([right]), selection: [right.id])?
            .rotated(by: 350, around: EaselPoint(x: 0, y: 0))?.first else { Issue.record("Single rotation succeeds"); return }
        #expect(single.frame == right.frame && single.rotation == nil, "A single object spins in place and drops the field at upright")
    }

    @Test func flippingOneObjectMirrorsItInPlace() throws {
        let photo = EaselTransformTestsSupport.item(.image, 10, 10, 100, 50)
        let once = try #require(EaselRotation.flipped([photo], horizontally: true)?.first, "Flip succeeds")
        #expect(once.flipHorizontal == true && once.frame == photo.frame, "Flipping one object mirrors it in place")
        let twice = try #require(EaselRotation.flipped([once], horizontally: true)?.first, "Second flip succeeds")
        #expect(twice.flipHorizontal == nil, "Flipping twice drops the field")
        let turned = EaselTransformTestsSupport.item(.rectangle, 0, 0, 100, 50, rotation: 30)
        let mirror = try #require(EaselRotation.flipped([turned], horizontally: false)?.first, "Vertical flip succeeds")
        #expect(mirror.rotation == -30 && mirror.flipVertical == true, "Flipping a turned object mirrors its angle too")
        let corner = EaselRotation.canvasPoint(EaselPoint(x: 100, y: 0), in: turned)
        let mirroredCorner = EaselRotation.canvasPoint(EaselPoint(x: 100, y: 0), in: mirror)
        let middle = EaselRotation.center(of: turned.frame)
        #expect(EaselTransformTestsSupport.near(mirroredCorner, EaselPoint(x: corner.x, y: 2 * middle.y - corner.y)), "A vertical flip mirrors across the horizontal centre line")
        let label = EaselTransformTestsSupport.item(.text, 200, 0, 100, 20, rotation: 20), sticky = EaselTransformTestsSupport.item(.sticky, 0, 200, 50, 50)
        guard let group = EaselRotation.flipped([photo, label, sticky], horizontally: true),
              let box = EaselRotation.bounds(of: [photo, label, sticky]) else { Issue.record("Group flip succeeds"); return }
        let pivot = EaselRotation.center(of: box).x
        #expect(EaselTransformTestsSupport.near(group[0].frame.x, 2 * pivot - 60 - 50) && group[0].flipHorizontal == true, "Group members mirror across the shared centre")
        #expect(EaselTransformTestsSupport.near(group[1].frame.x, 2 * pivot - 250 - 50) && group[1].rotation == -20 && group[1].flipHorizontal == nil, "Text mirrors its place but stays readable")
        #expect(group[2] == sticky, "Stickies stay put in a flip")
        #expect(EaselRotation.flipped([label], horizontally: true) == nil, "Text alone can't flip")
    }

    @Test func singleObjectsLandOnAbsolute15Steps() throws {
        let photo = EaselTransformTestsSupport.item(.image, 0, 0, 100, 100, rotation: 7)
        let drag = try #require(EaselRotationDrag(items: [photo], pointer: EaselPoint(x: 150, y: 50)), "Drag begins")
        let pointer = EaselPoint(x: 50 + 100 * cos(20 * .pi / 180), y: 50 + 100 * sin(20 * .pi / 180))
        guard let snapped = drag.delta(to: pointer, free: false), let free = drag.delta(to: pointer, free: true) else { Issue.record("Deltas exist"); return }
        #expect(EaselTransformTestsSupport.near(7 + snapped, 30), "Single objects land on absolute 15° steps")
        #expect(EaselTransformTestsSupport.near(free, 20), "Command turns freely")
        let pair = [EaselTransformTestsSupport.item(.image, 0, 0, 100, 100, rotation: 90), EaselTransformTestsSupport.item(.image, 200, 0, 100, 100)]
        let group = try #require(EaselRotationDrag(items: pair, pointer: EaselPoint(x: 300, y: 50)), "Group drag begins")
        #expect(EaselTransformTestsSupport.near(group.pivot, EaselPoint(x: 150, y: 50)), "Groups turn around their shared centre")
        let groupPointer = EaselPoint(x: 150 + 100 * cos(22 * .pi / 180), y: 50 + 100 * sin(22 * .pi / 180))
        #expect(group.delta(to: groupPointer, free: false).map { EaselTransformTestsSupport.near($0, 15) } == true, "Group turns step by 15°")
        #expect(EaselRotationDrag(items: [EaselTransformTestsSupport.item(.sticky, 0, 0, 10, 10)], pointer: EaselPoint(x: 50, y: 50)) == nil, "Stickies have no rotate drag")
    }

    @Test func applyingCarriesTheAngle() throws {
        let photo = EaselTransformTestsSupport.item(.image, 0, 0, 100, 100)
        let doc = EaselTransformTestsSupport.document([photo])
        guard let edit = EaselGeometryEdit(document: doc, selection: [photo.id]),
              let turned = edit.rotated(by: 45, around: EaselPoint(x: 50, y: 50)),
              let applied = edit.applying(turned, to: doc) else { Issue.record("Rotation applies"); return }
        #expect(applied.items[0].rotation == 45, "Applying carries the angle")
        #expect(!edit.isCurrent(in: applied), "A changed angle cancels a stale gesture")
        guard let flipped = edit.flipped(horizontally: true), let mirrored = edit.applying(flipped, to: doc) else { Issue.record("Flip applies"); return }
        #expect(mirrored.items[0].flipHorizontal == true, "Applying carries flips")
        let near = EaselTransformTestsSupport.item(.image, 0, 0, 100, 20, rotation: 90)
        let moving = try #require(EaselGeometryEdit(document: EaselTransformTestsSupport.document([near]), selection: [near.id])?.translated(x: -100, y: 0).first, "Move exists")
        #expect(moving.frame.x == 0, "Turned objects can't be dragged past the canvas edge")
        let upright = EaselTransformTestsSupport.item(.text, 30, 40, 10, 10)
        let plain = try #require(EaselGeometryEdit(document: EaselTransformTestsSupport.document([upright]), selection: [upright.id])?.translated(x: -100, y: -100).first, "Upright move exists")
        #expect(plain.frame.x == 0 && plain.frame.y == 0, "Upright clamping is unchanged")
    }

    @Test func wholeAnglesReadPlainly() {
        #expect(EaselRotation.turnLabel(45) == "45°", "Whole angles read plainly")
        #expect(EaselRotation.turnLabel(-30) == "\u{2212}30°", "Counter-clockwise angles use a real minus")
        #expect(EaselRotation.turnLabel(12.34) == "12.3°", "Free angles show a tenth")
        #expect(EaselRotation.turnLabel(0) == "0°", "Upright reads zero")
    }

    @Test func svgTurnsAndMirrorsAroundTheCentre() {
        let shape = EaselTransformTestsSupport.item(.rectangle, 10, 20, 100, 50, rotation: 30, flipH: true)
        let svg = EaselVectorExport.element(shape, art: EaselVectorArt())
        #expect(svg.hasPrefix("<g transform=\"rotate(30 60 45) translate(60 45) scale(-1 1) translate(-60 -45)\">") && svg.hasSuffix("</g>"), "SVG turns and mirrors around the centre")
        let plain = EaselTransformTestsSupport.item(.rectangle, 10, 20, 100, 50)
        #expect(!EaselVectorExport.element(plain, art: EaselVectorArt()).hasPrefix("<g transform"), "Upright objects export unchanged")
        let bounds = EaselVectorExport.contentBounds([EaselTransformTestsSupport.item(.image, 0, 0, 100, 40, rotation: 90)], margin: 0)
        #expect(EaselTransformTestsSupport.near(bounds, EaselRect(x: 26, y: -34, width: 48, height: 108)), "Export bounds include turned corners")
        #expect(EaselVectorExport.matrix(.rotation(degrees: 90, around: EaselPoint(x: 0, y: 0))) == "matrix(0 1 -1 0 0 0)", "Matrices print plainly")
    }
}
