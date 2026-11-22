import Foundation
import Testing
@testable import ParcCore

struct EaselStoreAspectGeometryTests {
    private func image() -> EaselItem {
        EaselItem(kind: .image, frame: .init(x: 100, y: 100, width: 200, height: 100), assetID: "original.png")
    }

    private func board(_ items: [EaselItem]) -> EaselDocument {
        let time = Date(timeIntervalSinceReferenceDate: 0)
        return EaselDocument(id: UUID(), title: "Direct controls", createdAt: time, modifiedAt: time, items: items)
    }

    private func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.000001
    }

    @Test
    func anImageUsesAspectUnlessCommandIsHeld() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        #expect(ie.preservesAspect(shift: false, command: false) && !ie.preservesAspect(shift: true, command: true), "Original image policy preserves aspect by default with Command precedence")
    }

    @Test
    func cornerResizeProjectsOntoTheOriginalAspectAndKeepsImageIdentity() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let projected = ie.resizedPreservingAspect(using: .bottomRight, x: 100, y: 0, centering: [])![0]
        #expect(near(projected.frame.width, 280) && near(projected.frame.height, 140) && projected.frame.x == 100 && projected.frame.y == 100, "Corner uses orthogonal original-ratio diagonal projection, not max-axis scaling")
        #expect(projected.id == image.id && projected.assetID == image.assetID, "Aspect geometry preserves original image identity and pixels")
    }

    @Test
    func crossingACornerRetainsTheImageAspectAndAsset() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let crossing = ie.resizedPreservingAspect(using: .bottomRight, x: -300, y: -180, centering: [])![0]
        #expect(near(crossing.frame.width / crossing.frame.height, 2) && crossing.assetID == image.assetID, "Crossing retains original ratio and unmirrored image payload")
    }

    @Test
    func aspectCorrectionRecoversAZeroHeightProposal() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let recovered = ie.resizedPreservingAspect(using: .bottomRight, x: 100, y: -100, centering: [])![0]
        #expect(recovered.frame.width > 1 && near(recovered.frame.width / recovered.frame.height, 2), "Aspect correction precedes final durable validation even at a zero-height plain intermediate")
    }

    @Test
    func horizontalAspectResizeAdjustsHeightAroundTheMidpoint() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let side = ie.resizedPreservingAspect(using: .right, x: 100, y: 0, centering: [])![0]
        #expect(side.frame == .init(x: 100, y: 75, width: 300, height: 150), "Horizontal edge derives height around the proposed midpoint")
    }

    @Test
    func verticalAspectResizeAdjustsWidthAroundTheMidpoint() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let top = ie.resizedPreservingAspect(using: .top, x: 0, y: -50, centering: [])![0]
        #expect(top.frame == .init(x: 50, y: 50, width: 300, height: 150), "Vertical edge derives width around the proposed midpoint")
    }

    @Test
    func centeredAspectResizeKeepsBothCentres() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let centered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .both)![0]
        #expect(centered.frame == .init(x: 80, y: 90, width: 240, height: 120), "Centered corner derives original-ratio height from width and keeps both centers")
    }

    @Test
    func capturedHorizontalAspectResizeKeepsTheOppositeVerticalEdge() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let xCentered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .horizontal)![0]
        #expect(xCentered.frame == .init(x: 80, y: 100, width: 240, height: 120), "One captured horizontal axis preserves opposite vertical edge")
    }

    @Test
    func capturedVerticalAspectResizeKeepsTheOppositeHorizontalEdge() {
        let image = image()
        let document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let yCentered = ie.resizedPreservingAspect(using: .bottomRight, x: 20, y: 50, centering: .vertical)![0]
        #expect(near(yCentered.frame.x, 100) && near(yCentered.frame.y, 95) && near(yCentered.frame.width, 220) && near(yCentered.frame.height, 110), "One captured vertical axis preserves opposite horizontal edge")
    }

    @Test
    func aShapeKeepsItsPlainFrameControlWhenShiftIsHeld() {
        let image = image()
        var document = board([image])
        var rectangle = image; rectangle.kind = .rectangle; document.items = [rectangle]
        #expect(!EaselGeometryEdit(document: document, selection: [rectangle.id])!.preservesAspect(shift: true, command: false), "Single shape retains its actual plain frame control owner")
    }

    @Test
    func aLinkPreservesItsAspectByDefault() {
        let image = image()
        var document = board([image])
        var link = image; link.kind = .link; document.items = [link]
        #expect(EaselGeometryEdit(document: document, selection: [link.id])!.preservesAspect(shift: false, command: false), "Original link content tag participates in aspect policy")
    }

    @Test
    func anAspectGuidePreservesTheOriginalRatio() {
        let image = image()
        var document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        document.items = [image, neighbor]
        var guides = EaselAlignmentGuides(edit: ie, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let aligned = guides.proposal(edit: ie, document: document, translation: .init(x: 48, y: 24),
            velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true, preserveAspect: true)![0]
        #expect(near(aligned.frame.x + aligned.frame.width, 350) && near(aligned.frame.width / aligned.frame.height, 2), "Aspect corner guide couples both deltas and preserves the original frame ratio")
        #expect(guides.lines.contains { $0.anchor == .right && near($0.coordinate, 350) }, "Aspect guide is shown only on the final actual aligned frame")
    }

    @Test
    func theIntrinsicGuideRatioChangesTheCorrectionButNotTheResultingAspect() {
        let image = image()
        var document = board([image])
        let ie = EaselGeometryEdit(document: document, selection: [image.id])!
        let neighbor = EaselItem(kind: .rectangle, frame: .init(x: 300, y: 220, width: 50, height: 60))
        document.items = [image, neighbor]
        var guides = EaselAlignmentGuides(edit: ie, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let intrinsic = guides.proposal(edit: ie, document: document, translation: .init(x: 48, y: 24),
            velocity: .init(x: 0, y: 0), handle: .bottomRight, centered: false, enabled: true,
            preserveAspect: true, aspectGuideRatio: 1)![0]
        #expect(near(intrinsic.frame.width, 250.4) && near(intrinsic.frame.width / intrinsic.frame.height, 2), "Shift intrinsic guide ratio affects correction without replacing original frame ratio")
    }

    @Test
    func shiftPreservesAspectForAnOrdinaryGroup() {
        let image = image()
        var document = board([image])
        var rectangle = image; rectangle.kind = .rectangle; document.items = [rectangle]
        let second = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 300, width: 100, height: 100))
        document.items = [rectangle, second]
        let group = EaselGeometryEdit(document: document, selection: [rectangle.id, second.id])!
        #expect(!group.preservesAspect(shift: false, command: false) && group.preservesAspect(shift: true, command: false), "Generic group Shift forces original group ratio")
    }

    @Test
    func aGroupWithAnImagePreservesAspectByDefault() {
        let image = image()
        var document = board([image])
        let second = EaselItem(kind: .rectangle, frame: .init(x: 400, y: 300, width: 100, height: 100))
        document.items = [image, second]
        #expect(EaselGeometryEdit(document: document, selection: [image.id, second.id])!.preservesAspect(shift: false, command: false), "Generic group with original image retains aspect by default")
    }
}
