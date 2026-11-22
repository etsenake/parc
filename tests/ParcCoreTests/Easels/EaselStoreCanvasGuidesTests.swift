import Foundation
import Testing
@testable import ParcCore

struct EaselStoreCanvasGuidesTests {
    private func makeGuides(_ document: EaselDocument, _ edit: EaselGeometryEdit) -> EaselAlignmentGuides {
        let viewport = EaselRect(x: 0, y: 0, width: 1000, height: 1000)
        return EaselAlignmentGuides(edit: edit, items: document.items, viewport: viewport, canvasWidth: 1000)
    }

    private func groupFixture() -> (document: EaselDocument, edit: EaselGeometryEdit) {
        let first = EaselItem(kind: .rectangle, frame: .init(x: 100, y: 100, width: 60, height: 40))
        let second = EaselItem(kind: .rectangle, frame: .init(x: 180, y: 100, width: 60, height: 40))
        let target = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 100, width: 140, height: 40))
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let document = EaselDocument(id: UUID(), title: "Guides", createdAt: date, modifiedAt: date, items: [first, second, target])
        return (document, EaselGeometryEdit(document: document, selection: [first.id, second.id])!)
    }

    private func centerFixture() -> (document: EaselDocument, edit: EaselGeometryEdit) {
        let item = EaselItem(kind: .rectangle, frame: .init(x: 450, y: 100, width: 100, height: 100))
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let document = EaselDocument(id: UUID(), title: "Original anchors", createdAt: date, modifiedAt: date, items: [item])
        return (document, EaselGeometryEdit(document: document, selection: [item.id])!)
    }

    @Test
    func snappingAMovedGroupKeepsSpacingAndIdentity() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        let aligned = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        #expect(aligned[0].frame.x == 300 && aligned[1].frame.x == 380, "Guide correction translates original group without changing spacing")
        #expect(!guides.lines.isEmpty && aligned.map(\.id) == doc.items.prefix(2).map(\.id), "Active guides preserve original identities")
    }

    @Test
    func fastMotionDoesNotAcquireAnAlignmentGuide() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        let fast = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 1000, y: 0), handle: nil, centered: false, enabled: true)!
        #expect(fast[0].frame.x == 295, "Fast motion does not acquire a new horizontal snap")
    }

    @Test
    func disablingGuidesUsesThePointerAndClearsTheSnap() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        _ = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        let suppressed = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false)!
        #expect(suppressed[0].frame.x == 295 && guides.lines.isEmpty, "Command/toggle suppression clears snap state and preserves actual pointer proposal")
    }

    @Test
    func changingTheTargetInvalidatesItsGuide() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        var changed = doc
        changed.items[2].frame.x += 1
        let stale = guides.proposal(edit: edit, document: changed, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        #expect(stale[0].frame.x == 295 && guides.lines.isEmpty, "A changed target frame cannot retain an old guide")
    }

    @Test
    func aGuideCannotApplyToAnotherDocument() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        var wrong = doc; wrong.id = UUID()
        #expect(guides.proposal(edit: edit, document: wrong, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true) == nil, "Solver rejects replaced original document")
    }

    @Test
    func nearbyObjectsSnapToTheStandardGap() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        let gap = guides.proposal(edit: edit, document: doc, translation: .init(x: 40, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        #expect(abs(gap[1].frame.x + gap[1].frame.width - 276) < 0.001, "Adjacent objects acquire recovered 24-point separation")
    }

    @Test
    func offscreenObjectsDoNotProvideGuides() {
        let (doc, edit) = groupFixture()
        var guides = makeGuides(doc, edit)
        let offscreen = EaselRect(x: 0, y: 0, width: 250, height: 1000)
        let hidden = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, viewport: offscreen)!
        #expect(hidden[0].frame.x == 295 && guides.lines.isEmpty, "Offscreen target does not provide visible guides")
    }

    @Test
    func anAcquiredGuideHoldsUntilThePointerMovesTooFar() {
        let fixture = groupFixture()
        var doc = fixture.document
        let edit = fixture.edit
        doc.items[2].frame.height = 600
        var guides = makeGuides(doc, edit)
        _ = guides.proposal(edit: edit, document: doc, translation: .init(x: 195, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)
        let sticky = guides.proposal(edit: edit, document: doc, translation: .init(x: 191, y: 200), velocity: .init(x: 1000, y: 1000), handle: nil, centered: false, enabled: true)!
        #expect(sticky[0].frame.x == 300, "Acquired guide uses perpendicular-travel hysteresis without new-snap velocity gate")
        let released = guides.proposal(edit: edit, document: doc, translation: .init(x: 170, y: 200), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)!
        #expect(released[0].frame.x == 270, "Pointer beyond bounded hysteresis releases acquired guide")
    }

    @Test
    func resizeGuidesKeepTheGroupIdentityAndInactiveAxis() {
        let fixture = groupFixture()
        var doc = fixture.document
        let edit = fixture.edit
        doc.items[2].frame = .init(x: 100, y: 170, width: 300, height: 40)
        var guides = makeGuides(doc, edit)
        let resized = guides.proposal(edit: edit, document: doc, translation: .init(x: 155, y: 0), velocity: .init(x: 0, y: 0), handle: .right, centered: false, enabled: true)!
        #expect(abs(EaselGeometryEdit.bounds(of: resized)!.width - 300) < 0.001, "Resize correction goes through original group control point")
        #expect(resized[0].id == doc.items[0].id && resized[1].id == doc.items[1].id && resized[0].frame.y == 100, "Resize guides preserve exact members and inactive axis")
    }

    @Test
    func canvasAnchorsCaptureOnlyTheExactAxis() {
        let (doc, edit) = centerFixture()
        let guides = makeGuides(doc, edit)
        #expect(guides.activeAtDragBegin == [.centerX], "Canvas producer captures only exact horizontal center, with no invented vertical canvas anchor")
    }

    @Test
    func aCapturedCanvasCentreResizesOnlyTheHorizontalAxis() {
        let (doc, edit) = centerFixture()
        var guides = makeGuides(doc, edit)
        let centered = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true)![0].frame
        #expect(centered == .init(x: 430, y: 100, width: 140, height: 130), "Captured canvas center expands horizontal axis only")
        #expect(guides.lines.contains { $0.anchor == .centerX && $0.coordinate == 500 }, "Exact fixed center retains real active guide during resize")
    }

    @Test
    func anActiveCentreGuideDrawsOutsideTheMovingObject() {
        let (doc, edit) = centerFixture()
        var guides = makeGuides(doc, edit)
        let centered = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true)![0].frame
        let centerLine = guides.lines.first { $0.anchor == .centerX }!
        #expect(centerLine.targetSegments.count == 2 && centerLine.anchorSegments.count == 4 &&
               centerLine.targetSegments[0].end.y < centered.y && centerLine.targetSegments[1].start.y > centered.y + centered.height,
               "Center feedback splits the pale path outside the moving object and supplies four cross-mark segments")
    }

    @Test
    func suppressingGuidesKeepsTheCapturedCentre() {
        let (doc, edit) = centerFixture()
        var guides = makeGuides(doc, edit)
        let centered = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true)![0].frame
        let command = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        #expect(command == centered && guides.lines.isEmpty, "Command suppresses correction and lines, not original captured axis centering")
    }

    @Test
    func optionAddsVerticalCenteringUntilReleased() {
        let (doc, edit) = centerFixture()
        var guides = makeGuides(doc, edit)
        let centered = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true)![0].frame
        _ = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        let option = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: true, enabled: false)![0].frame
        #expect(option == .init(x: 430, y: 70, width: 140, height: 160), "Option adds vertical centering to captured horizontal center")
        let released = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        #expect(released == centered, "Releasing Option resumes exact captured axes from originals")
    }

    @Test
    func capturedAnchorsBelongToTheOriginalCanvasWidth() {
        let (doc, edit) = centerFixture()
        let guides = makeGuides(doc, edit)
        #expect(guides.matchesCanvas(width: 1000) && !guides.matchesCanvas(width: 1001), "Canvas coordinate owner is exact and cannot silently retarget original anchors")
    }

    @Test
    func capturedCentresDoNotResizeAnObjectDuringAMove() {
        let (doc, edit) = centerFixture()
        var guides = makeGuides(doc, edit)
        let moved = guides.proposal(edit: edit, document: doc, translation: .init(x: 40, y: 20), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false)![0].frame
        #expect(moved == .init(x: 490, y: 120, width: 100, height: 100), "Captured centers do not turn body move into a resize")
    }

    @Test
    func aNewGestureOnlyCapturesTheExactCanvasCentre() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame.x += 0.01; edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        #expect(!guides.activeAtDragBegin.contains(.centerX), "Nearby center within snap radius is not an exact drag-begin anchor")
        let fresh = guides.proposal(edit: edit, document: doc, translation: .init(x: 20, y: 30), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        #expect(fresh.x == 450.01 && fresh.width == 120, "New gesture recomputes anchors rather than retaining prior canvas session")
    }

    @Test
    func canvasMarginsSnapSymmetrically() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        let left = guides.proposal(edit: edit, document: doc, translation: .init(x: -55, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        #expect(abs(left.x - 42) < 0.000001, "Canvas left margin is recovered 42/1000 logical width")
        guides = makeGuides(doc, edit)
        let right = guides.proposal(edit: edit, document: doc, translation: .init(x: 755, y: 0), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        #expect(abs(right.x + right.width - 958) < 0.000001, "Canvas right margin is symmetric 42/1000 logical width")
    }

    @Test
    func fastMotionDoesNotSnapToACanvasMargin() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        guides = makeGuides(doc, edit)
        let fast = guides.proposal(edit: edit, document: doc, translation: .init(x: -55, y: 0), velocity: .init(x: 1000, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        #expect(fast.x == 45 && guides.lines.isEmpty, "Canvas guides share real new-snap velocity policy")
    }

    @Test
    func theCanvasOffersNoVerticalMarginGuide() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        let vertical = guides.proposal(edit: edit, document: doc, translation: .init(x: 0, y: -55), velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true)![0].frame
        #expect(vertical.y == 45 && guides.lines.isEmpty, "No speculative top or bottom canvas margin is introduced")
    }

    @Test
    func aNeighbourCanCaptureOnlyTheVerticalCentre() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 220, y: 125, width: 100, height: 50))
        doc.items.append(neighbor); guides = makeGuides(doc, edit)
        #expect(guides.activeAtDragBegin.contains(.centerY) && !guides.activeAtDragBegin.contains(.centerX), "Exact original neighbor center captures vertical axis independently")
        let neighborCentered = guides.proposal(edit: edit, document: doc, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        #expect(abs(neighborCentered.x - 100) < 0.000001 && abs(neighborCentered.y - 80) < 0.000001 &&
               abs(neighborCentered.width - 110) < 0.000001 && abs(neighborCentered.height - 140) < 0.000001, "Original neighbor center keeps vertical symmetry without horizontal centering")
    }

    @Test
    func theCapturedCentreUsesTheOriginalGeometryUntilTheNextGesture() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 220, y: 125, width: 100, height: 50))
        doc.items.append(neighbor); guides = makeGuides(doc, edit)
        let neighborCentered = guides.proposal(edit: edit, document: doc, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        doc.items[1].frame.y += 10
        let snapshot = guides.proposal(edit: edit, document: doc, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false)![0].frame
        #expect(snapshot == neighborCentered, "Drag-begin center remains original geometry policy even when a later target changes")
        guides = makeGuides(doc, edit)
        #expect(!guides.activeAtDragBegin.contains(.centerY), "Next gesture does not inherit changed neighbor alignment")
    }

    @Test
    func capturedAxesDoNotCrossDocumentIdentity() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items[0].frame = .init(x: 100, y: 100, width: 100, height: 100)
        edit = EaselGeometryEdit(document: doc, selection: [item.id])!; guides = makeGuides(doc, edit)
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 220, y: 125, width: 100, height: 50))
        doc.items.append(neighbor); guides = makeGuides(doc, edit)
        doc.items[1].frame.y += 10
        guides = makeGuides(doc, edit)
        var wrong = doc; wrong.id = UUID()
        #expect(guides.proposal(edit: edit, document: wrong, translation: .init(x: 10, y: 20), velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: false) == nil, "Captured axis cannot cross original document identity")
    }

    @Test
    func capturedCanvasCentresTransformTheWholeGroup() {
        let fixture = centerFixture()
        var doc = fixture.document
        var edit = fixture.edit
        let item = doc.items[0]
        var guides = makeGuides(doc, edit)
        doc.items = [item, EaselItem(kind: .rectangle, frame: .init(x: 450, y: 240, width: 100, height: 100))]
        edit = EaselGeometryEdit(document: doc, selection: Set(doc.items.map(\.id)))!; guides = makeGuides(doc, edit)
        let group = guides.proposal(edit: edit, document: doc, translation: .init(x: 25, y: 0), velocity: .init(x: 0, y: 0), handle: .right, centered: false, enabled: false)!
        #expect(group.allSatisfy { $0.frame.x == 425 && $0.frame.width == 150 } && group.map(\.id) == doc.items.map(\.id), "Captured canvas center transforms exact original group members together")
    }
}
