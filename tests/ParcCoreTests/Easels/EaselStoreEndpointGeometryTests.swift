import Foundation
import Testing
@testable import ParcCore

struct EaselStoreEndpointGeometryTests {

    private func arrow() -> EaselItem {
        EaselItem(kind: .arrow, frame: .init(x: 100, y: 100, width: 100, height: 80),
                  points: [.init(x: 0, y: 0), .init(x: 100, y: 80)])
    }

    private func board(_ items: [EaselItem]) -> EaselDocument {
        let time = Date(timeIntervalSinceReferenceDate: 0)
        return EaselDocument(id: UUID(), title: "Direct controls", createdAt: time, modifiedAt: time, items: items)
    }


    @Test
    func endpointHitTargetsKeepTwentyScreenPointsAndRejectInvalidScale() {
        let arrow = arrow()
        #expect(EaselArrowEndpoint.end.hitRect(in: arrow, scale: 2) == .init(x: 195, y: 175, width: 10, height: 10) &&
               EaselArrowEndpoint.end.hitRect(in: arrow, scale: 0) == nil,
               "Endpoint pointer target retains twenty screen points under magnification and refuses invalid scale")
    }

    @Test
    func crossingAnEndpointKeepsItsIdentityAndRebasesThePoints() {
        let arrow = arrow()
        let document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let moved = edit.movingEndpoint(.start, x: 150, y: 120)![0]
        #expect(moved.id == arrow.id && moved.frame == .init(x: 200, y: 180, width: 50, height: 40), "Endpoint crossing rebases original arrow without replacing identity")
        #expect(EaselArrowEndpoint.start.point(in: moved) == .init(x: 250, y: 220) && EaselArrowEndpoint.end.point(in: moved) == .init(x: 200, y: 180), "Crossing preserves actual stationary endpoint and original start/end direction")
    }

    @Test
    func movingAnEndpointToTheSameHeightKeepsAValidFlatFrame() {
        let arrow = arrow()
        let document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let flat = edit.movingEndpoint(.end, x: 0, y: -80)![0]
        #expect(flat.frame.height == 1 && flat.points.map(\.y) == [0, 0], "Flat arrow retains exact rendered endpoints within durable minimum frame")
    }

    @Test
    func coincidentEndpointsKeepAValidFrame() {
        let arrow = arrow()
        let document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let collapsed = edit.movingEndpoint(.end, x: -100, y: -80)![0]
        #expect(collapsed.frame.width == 1 && collapsed.frame.height == 1 && collapsed.points[0] == collapsed.points[1], "Coincident endpoint proposal remains representable and reversible from originals")
    }

    @Test
    func unsafeEndpointProposalsAreRefused() {
        let arrow = arrow()
        let document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        #expect(edit.movingEndpoint(.end, x: .infinity, y: 0) == nil && edit.movingEndpoint(.start, x: -101, y: 0) == nil, "Unsafe endpoint proposals refuse atomically")
    }

    @Test
    func exactEndpointGuidesUseTheMovingEdgeAndTargetExtent() {
        let arrow = arrow()
        var document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let endpointTarget = EaselItem(kind: .rectangle, frame: .init(x: 250, y: 220, width: 20, height: 60))
        document.items = [arrow, endpointTarget]
        var endpointGuides = EaselAlignmentGuides(edit: edit, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        let exactEndpoint = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: true, enabled: true, preserveAspect: true, endpoint: .end)![0]
        #expect(exactEndpoint == edit.movingEndpoint(.end, x: 70, y: 30)![0], "Endpoint alignment never adopts frame centering or aspect constraints")
        let endpointLine = endpointGuides.lines.first { $0.anchor == .right && $0.coordinate == 270 }!
        #expect(endpointLine.targetSegments == [.init(start: .init(x: 270, y: 88), end: .init(x: 270, y: 292))] &&
               endpointLine.anchorSegments == [.init(start: .init(x: 270, y: 100), end: .init(x: 270, y: 210))],
               "Exact endpoint alignment highlights the target extent and actual moving edge separately")
    }

    @Test
    func movingOffAnExactEndpointRetiresItsGuide() {
        let arrow = arrow()
        var document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let endpointTarget = EaselItem(kind: .rectangle, frame: .init(x: 250, y: 220, width: 20, height: 60))
        document.items = [arrow, endpointTarget]
        var endpointGuides = EaselAlignmentGuides(edit: edit, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        _ = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: true, enabled: true, preserveAspect: true, endpoint: .end)![0]
        let nearbyEndpoint = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 68, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, endpoint: .end)![0]
        #expect(nearbyEndpoint == edit.movingEndpoint(.end, x: 68, y: 30)![0] && endpointGuides.lines.isEmpty,
               "Endpoint refuses nonzero correction and retires the previously exact guide")
    }

    @Test
    func disablingGuidesSuppressesEndpointFeedback() {
        let arrow = arrow()
        var document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let endpointTarget = EaselItem(kind: .rectangle, frame: .init(x: 250, y: 220, width: 20, height: 60))
        document.items = [arrow, endpointTarget]
        var endpointGuides = EaselAlignmentGuides(edit: edit, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        _ = endpointGuides.proposal(edit: edit, document: document, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: false, endpoint: .end)
        #expect(endpointGuides.lines.isEmpty, "Command or disabled guides suppress exact endpoint feedback")
    }

    @Test
    func aChangedTargetCannotSupplyStaleEndpointFeedback() {
        let arrow = arrow()
        var document = board([arrow])
        let edit = EaselGeometryEdit(document: document, selection: [arrow.id])!
        let endpointTarget = EaselItem(kind: .rectangle, frame: .init(x: 250, y: 220, width: 20, height: 60))
        document.items = [arrow, endpointTarget]
        var endpointGuides = EaselAlignmentGuides(edit: edit, items: document.items,
            viewport: .init(x: 0, y: 0, width: 800, height: 600), canvasWidth: 800)
        var changedEndpointTarget = document; changedEndpointTarget.items[1].frame.x += 2
        _ = endpointGuides.proposal(edit: edit, document: changedEndpointTarget, translation: .init(x: 70, y: 30),
            velocity: .init(x: 0, y: 0), handle: nil, centered: false, enabled: true, endpoint: .end)
        #expect(endpointGuides.lines.isEmpty, "Changed original target cannot supply stale endpoint feedback")
    }

    @Test
    func editingOneEndOfAMultipointArrowIsRefused() {
        let arrow = arrow()
        var document = board([arrow])
        var polyline = arrow; polyline.points.append(.init(x: 50, y: 50)); document.items = [polyline]
        #expect(EaselGeometryEdit(document: document, selection: [arrow.id])!.movingEndpoint(.start, x: 1, y: 1) == nil, "Unsupported multipoint arrow is preserved instead of flattened")
    }
}
