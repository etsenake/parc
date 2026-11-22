import Foundation
import Testing
@testable import ParcCore

struct EaselConnectorRoutingSettlementTests {
    @Test func movingAnAttachedObjectUpdatesTheRelatedConnectorGeometry() throws {
        let sticky = EaselItem(kind: .sticky, frame: EaselRect(x: 100, y: 100, width: 200, height: 200))
        var highlight = EaselItem(kind: .freehand, frame: EaselRect(x: 120, y: 150, width: 100, height: 10))
        highlight.points = [EaselPoint(x: 0, y: 5), EaselPoint(x: 100, y: 5)]
        highlight.brush = .highlighter
        highlight.attachedTo = sticky.id
        let far = EaselConnectorRoutingTestsSupport.box(600, 120)
        let link = EaselConnectorRouter.settled(EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .straight,
                                                          startConnection: EaselConnection(itemID: highlight.id, side: .right),
                                                          endConnection: EaselConnection(itemID: far.id, side: .left)),
                                                lookup: EaselConnectorRoutingTestsSupport.lookup([sticky, highlight, far]))
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [sticky, highlight, far, link])
        var dragged = board
        dragged.items[0].frame.x += 40
        dragged.items[0].frame.y += 30
        let settled = EaselDependents.settle(dragged, previous: board, moved: [sticky.id])
        guard let carried = settled.items.first(where: { $0.id == highlight.id }),
              let rerouted = settled.items.first(where: { $0.id == link.id }) else { Issue.record("Everything survives the drag"); return }
        #expect(EaselConnectorRoutingTestsSupport.near(carried.frame.x, 160) && EaselConnectorRoutingTestsSupport.near(carried.frame.y, 180), "A sticky-on follows its sticky")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorRouter.absolutePoints(rerouted).first ?? .init(x: 0, y: 0), EaselPoint(x: 260, y: 185)), "A connector attached to a sticky-on follows it too")
        #expect(EaselDependents.settle(settled, previous: settled, moved: []) == settled, "The carried board is settled")

        var a = EaselConnectorRoutingTestsSupport.box(0, 0), b = EaselConnectorRoutingTestsSupport.box(300, 0), c = EaselConnectorRoutingTestsSupport.box(600, 0)
        b.attachedTo = a.id
        c.attachedTo = b.id
        let chain = EaselDocument(id: UUID(), title: "Chain", createdAt: Date(), modifiedAt: Date(), items: [a, b, c])
        #expect(EaselDependents.removalClosure([a.id], in: chain) == [a.id, b.id, c.id], "Removing an object takes everything stuck to it, all the way down")
        a.attachedTo = b.id
        let loop = EaselDocument(id: UUID(), title: "Loop", createdAt: Date(), modifiedAt: Date(), items: [a, b, c])
        #expect(EaselDependents.removalClosure([b.id], in: loop) == [a.id, b.id, c.id], "Objects stuck to each other in a loop come off together")
        #expect(EaselDependents.removalClosure([UUID()], in: loop).isEmpty, "Unknown objects remove nothing")

        let section = EaselItem(kind: .section, frame: EaselRect(x: 0, y: 0, width: 500, height: 500))
        let inside = EaselConnectorRoutingTestsSupport.box(50, 50), outside = EaselConnectorRoutingTestsSupport.box(900, 900)
        let edge = EaselConnectorRouter.settled(EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                                          startConnection: EaselConnection(itemID: inside.id, side: .right),
                                                          endConnection: EaselConnection(itemID: outside.id, side: .left)),
                                                lookup: EaselConnectorRoutingTestsSupport.lookup([inside, outside]))
        let grouped = EaselDocument(id: UUID(), title: "Sections", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, edge])
        let cleared = EaselDependents.removing([section.id], from: grouped)
        #expect(!cleared.items.contains { $0.id == inside.id } && cleared.items.contains { $0.id == outside.id }, "Deleting a section takes what's inside it")
        let freed = try #require(cleared.items.first(where: { $0.id == edge.id }), "Connectors leaving a deleted section stay")
        #expect(freed.startConnection == nil && freed.endConnection != nil, "A connector from a deleted section's member is freed, not left dangling")
        let kept = EaselDependents.removing([section.id], from: grouped, keepingSectionContents: true)
        #expect(kept.items.contains { $0.id == inside.id } && !kept.items.contains { $0.id == section.id }, "Keeping contents deletes only the section")
    }

    @Test func settlingStoresTheLiveRoutesEnds() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        let settled = EaselConnectorRouter.settled(item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        let points = EaselConnectorRouter.absolutePoints(settled)
        #expect(EaselConnectorRoutingTestsSupport.near(points.first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 130)) && EaselConnectorRoutingTestsSupport.near(points.last ?? .init(x: 0, y: 0), EaselPoint(x: 400, y: 330)), "Settling stores the live route's ends")
        #expect(points.count == 4 && EaselConnectorRoutingTestsSupport.orthogonal(points), "Settling stores the elbow's corners")
        #expect(settled.frame.x >= 0 && settled.frame.width >= 1 && settled.frame.height >= 1, "Settled frames are valid")
        #expect(EaselConnectorRouter.settled(settled, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])) == settled, "Settling twice changes nothing")
        let curved = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .curved,
                               startConnection: EaselConnection(itemID: a.id, side: .bottom), endConnection: EaselConnection(itemID: b.id, side: .top))
        let settledCurve = EaselConnectorRouter.settled(curved, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        #expect(settledCurve.points.count > 10, "Curves store a smooth trace for hit tests and older readers")
        #expect(EaselConnectorRouter.settled(settledCurve, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])) == settledCurve, "Curves settle once")
        let detached = EaselConnectorRouter.detached(settled, from: [a.id])
        #expect(detached.startConnection == nil && detached.endConnection != nil, "Removing an object frees only its own end")
        let kept = try #require(EaselConnectorRouter.route(for: detached, lookup: EaselConnectorRoutingTestsSupport.lookup([b])), "Detached elbows route")
        #expect(kept.vertices == points, "A freed elbow keeps its last route")
    }

    @Test func aSharedContextSettlesExactlyLikeAFreshOne() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        var elbow = EaselConnectorRouter.settled(EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                                           startConnection: EaselConnection(itemID: a.id, side: .right),
                                                           endConnection: EaselConnection(itemID: b.id, side: .left)), lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        elbow.waypoints = [EaselPoint(x: 340, y: 130), EaselPoint(x: 340, y: 330)]
        elbow = EaselConnectorRouter.settled(elbow, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, elbow])
        var dragged = board
        for index in dragged.items.indices { dragged.items[index].frame.x += 30; dragged.items[index].frame.y += 15 }
        let moved: Set<UUID> = [a.id, b.id, elbow.id]
        let context = EaselSettleContext(previous: board)
        let fast = EaselDependents.settle(dragged, context: context, moved: moved)
        #expect(fast == EaselDependents.settle(dragged, previous: board, moved: moved), "A shared context settles exactly like a fresh one")
        let shifted = try #require(fast.items.first(where: { $0.id == elbow.id }), "Dragged connectors stay")
        let expected = EaselConnectorRouter.absolutePoints(elbow).map { EaselPoint(x: $0.x + 30, y: $0.y + 15) }
        #expect(zip(EaselConnectorRouter.absolutePoints(shifted), expected).allSatisfy { EaselConnectorRoutingTestsSupport.near($0, $1) }, "Dragging a connector with both its objects just slides the route")
        #expect(shifted.waypoints == [EaselPoint(x: 370, y: 145), EaselPoint(x: 370, y: 345)], "Its bends slide along")
        var lookupAfter = Dictionary(fast.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lookupAfter[elbow.id] = nil
        #expect(EaselConnectorRouter.settled(shifted) { lookupAfter[$0] } == shifted, "The slid route is exactly what a full reroute would give")
        var half = board
        half.items[0].frame.x += 30
        half.items[2].frame.x += 30
        let partial = EaselDependents.settle(half, previous: board, moved: [a.id, elbow.id])
        let rerouted = try #require(partial.items.first(where: { $0.id == elbow.id }), "Partly dragged connectors stay")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorRouter.absolutePoints(rerouted).last ?? .init(x: 0, y: 0), EaselPoint(x: 400, y: 330)), "When only one end moves along, the connector reroutes to the one that stayed")
    }
}
