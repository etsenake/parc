import Foundation
import Testing
@testable import ParcCore

struct EaselConnectorRoutingMagnetsTests {
    @Test
    func rectangleMagnetsSitAtTheirEdgeMidpoints() {
        let rect = EaselConnectorRoutingTestsSupport.box(100, 100)
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.magnet(.top, on: rect), EaselPoint(x: 150, y: 100)), "The top magnet sits mid-way along the top edge")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.magnet(.right, on: rect), EaselPoint(x: 200, y: 130)), "The right magnet sits mid-way down the right edge")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.magnet(.bottom, on: rect), EaselPoint(x: 150, y: 160)), "The bottom magnet sits on the bottom edge")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.magnet(.left, on: rect), EaselPoint(x: 100, y: 130)), "The left magnet sits on the left edge")
    }

    @Test
    func triangleMagnetsFollowTheDrawnOutline() {
        var triangle = EaselConnectorRoutingTestsSupport.box(0, 0, 100, 100)
        triangle.shape = .triangle
        let apex = EaselConnectorAttachment.magnet(.top, on: triangle)
        #expect(EaselConnectorRoutingTestsSupport.near(apex, EaselPoint(x: 50, y: 0), 0.5), "A triangle's top magnet is its apex")
        let flank = EaselConnectorAttachment.magnet(.left, on: triangle)
        #expect(flank.x > 1 && EaselConnectorRoutingTestsSupport.near(flank.y, 50, 0.5), "A triangle's left magnet sits on its slanted outline, not the empty frame corner")
    }

    @Test
    func aTurnedMagnetKeepsItsPositionAndOutwardDirection() {
        var turned = EaselConnectorRoutingTestsSupport.box(0, 0, 100, 60)
        turned.rotation = 90
        let top = EaselConnectorAttachment.magnet(.top, on: turned)
        #expect(EaselConnectorRoutingTestsSupport.near(top, EaselPoint(x: 80, y: 30), 1e-6), "A quarter-turned object's top magnet turns with it")
        let outward = EaselConnectorAttachment.outward(.top, on: turned)
        #expect(EaselConnectorRoutingTestsSupport.near(outward, EaselPoint(x: 1, y: 0), 1e-9), "The quarter-turned top side faces right")
    }

    @Test
    func anAutomaticSideFacesItsTarget() {
        let rect = EaselConnectorRoutingTestsSupport.box(100, 100)
        #expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 500, y: 140)) == .right, "A target far to the right faces right")
        #expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 150, y: -300)) == .top, "A target far above faces up")
        #expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: -40, y: 130)) == .left, "A target to the left faces left")
        #expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 160, y: 900)) == .bottom, "A target below faces down")
    }

    @Test
    func aLockedObjectKeepsItsExistingConnections() {
        var locked = EaselConnectorRoutingTestsSupport.box(0, 0)
        locked.locked = true
        #expect(!EaselConnectorAttachment.canAttach(to: locked), "Locked objects take no new connector ends")
        #expect(EaselConnectorAttachment.resolves(locked), "Existing connections to a locked object keep working")
    }

    @Test
    func connectorsNeverAttachToOtherConnectors() {
        #expect(!EaselConnectorAttachment.canAttach(to: EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10))), "Connectors never attach to connectors")
    }

    @Test func pinnedPointsAreStoredAsFractionsOfTheFrame() {
        var item = EaselConnectorRoutingTestsSupport.box(100, 100, 200, 100)
        let anchor = EaselConnectorAttachment.anchor(at: EaselPoint(x: 150, y: 175), on: item)
        #expect(EaselConnectorRoutingTestsSupport.near(anchor, EaselPoint(x: 0.25, y: 0.75)), "Pinned points are stored as fractions of the frame")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.anchorPoint(anchor, on: item), EaselPoint(x: 150, y: 175)), "Pinned points map back to the same spot")
        item.rotation = 30
        item.flipHorizontal = true
        let spot = EaselPoint(x: 230, y: 160)
        let turned = EaselConnectorAttachment.anchor(at: spot, on: item)
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorAttachment.anchorPoint(turned, on: item), spot, 1e-6), "Pinned points round-trip through rotation and flips")
        let outside = EaselConnectorAttachment.anchor(at: EaselPoint(x: -500, y: 2000), on: EaselConnectorRoutingTestsSupport.box(0, 0))
        #expect(outside.x >= 0 && outside.x <= 1 && outside.y >= 0 && outside.y <= 1, "Pinned points stay inside the object")
        #expect(EaselConnectorAttachment.nearestSide(of: EaselPoint(x: 0.95, y: 0.5), on: EaselConnectorRoutingTestsSupport.box(0, 0)) == .right, "A pin near the right edge leaves to the right")
        #expect(EaselConnectorAttachment.nearestSide(of: EaselPoint(x: 0.5, y: 0.02), on: EaselConnectorRoutingTestsSupport.box(0, 0)) == .top, "A pin near the top leaves upwards")
    }

    @Test func endsSnapToTheNearestSideMagnet() {
        let target = EaselConnectorRoutingTestsSupport.box(100, 100, 200, 200)
        let edge = EaselConnectorAttachment.snap(EaselPoint(x: 296, y: 190), to: target, pin: false, scale: 1)
        #expect(edge.connection?.side == .right && EaselConnectorRoutingTestsSupport.near(edge.point, EaselPoint(x: 300, y: 200)), "Ends snap to the nearest side magnet")
        let middle = EaselConnectorAttachment.snap(EaselPoint(x: 200, y: 200), to: target, pin: false, scale: 1)
        #expect(middle.connection != nil && middle.connection?.side == nil && middle.connection?.anchor == nil, "Dropping in the middle of a roomy object lets the connector pick the side")
        let pinned = EaselConnectorAttachment.snap(EaselPoint(x: 140, y: 260), to: target, pin: true, scale: 1)
        #expect(pinned.connection?.anchor.map { EaselConnectorRoutingTestsSupport.near($0, EaselPoint(x: 0.2, y: 0.8)) } == true && EaselConnectorRoutingTestsSupport.near(pinned.point, EaselPoint(x: 140, y: 260)), "Command pins the exact point")
        let small = EaselConnectorAttachment.snap(EaselPoint(x: 20, y: 20), to: EaselConnectorRoutingTestsSupport.box(0, 0, 40, 40), pin: false, scale: 1)
        #expect(small.connection?.side != nil, "Small objects always snap to a side magnet")
        var locked = target
        locked.locked = true
        let refused = EaselConnectorAttachment.snap(EaselPoint(x: 296, y: 190), to: locked, pin: false, scale: 1)
        #expect(refused.connection == nil && EaselConnectorRoutingTestsSupport.near(refused.point, EaselPoint(x: 296, y: 190)), "Locked objects leave the end free")
        let free = EaselConnectorAttachment.snap(EaselPoint(x: 5, y: 6), to: nil, pin: false, scale: 1)
        #expect(free.connection == nil, "No object, no attachment")
    }

    @Test func aStraightConnectorJoinsTheFacingMagnets() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 100)
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10),
                             startConnection: EaselConnection(itemID: a.id), endConnection: EaselConnection(itemID: b.id))
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "A connected straight route resolves")
        #expect(EaselConnectorRoutingTestsSupport.near(route.start, EaselPoint(x: 200, y: 130)) && EaselConnectorRoutingTestsSupport.near(route.end, EaselPoint(x: 400, y: 130)), "A straight connector joins the facing magnets")
        #expect(EaselConnectorRoutingTestsSupport.near(route.length, 200), "The straight route's length is the gap")
        var legacy = EaselItem(kind: .arrow, frame: EaselRect(x: 10, y: 20, width: 220, height: 140))
        legacy.points = [EaselPoint(x: 0, y: 140), EaselPoint(x: 120, y: 60), EaselPoint(x: 220, y: 0)]
        let old = try #require(EaselConnectorRouter.route(for: legacy, lookup: EaselConnectorRoutingTestsSupport.lookup([])), "Legacy arrows route")
        #expect(old.vertices.count == 3 && EaselConnectorRoutingTestsSupport.near(old.vertices[1], EaselPoint(x: 130, y: 80)), "Legacy arrows keep every stored point")
        #expect(EaselConnectorRouter.settled(legacy, lookup: EaselConnectorRoutingTestsSupport.lookup([])) == legacy, "Settling never touches a legacy arrow")
        let orphan = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 10, y: 10), to: .init(x: 90, y: 50), startConnection: EaselConnection(itemID: UUID()))
        let settled = EaselConnectorRouter.settled(orphan, lookup: EaselConnectorRoutingTestsSupport.lookup([]))
        #expect(settled.startConnection == nil && EaselConnectorRoutingTestsSupport.near(EaselConnectorRouter.absolutePoints(settled).first ?? .init(x: -1, y: -1), EaselPoint(x: 10, y: 10)), "A connection to a missing object turns into a free end where it last was")
    }

    @Test func aConnectorFollowsTheObjectItIsAttached() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let item = EaselConnectorRouter.settled(EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                                          startConnection: EaselConnection(itemID: a.id, side: .right),
                                                          endConnection: EaselConnection(itemID: b.id, side: .left)), lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, item])
        var next = document
        next.items[0].frame.y += 80
        let settled = EaselDependents.settle(next, previous: document, moved: [a.id])
        let connector = try #require(settled.items.first(where: { $0.id == item.id }), "Connectors survive a move")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorRouter.absolutePoints(connector).first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 210)), "A connector follows the object it is attached to")
        #expect(EaselDependents.settle(settled, previous: settled, moved: []) == settled, "Settling a settled board is a no-op")

        var dragged = document
        dragged.items[2].frame.x += 50
        let stuck = EaselDependents.settle(dragged, previous: document, moved: [item.id])
        #expect(stuck.items[2] == item, "A connector with both ends attached doesn't drag on its own")

        var loose = item
        loose.endConnection = nil
        let looseDocument = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, loose])
        var looseMoved = looseDocument
        looseMoved.items[2].frame.x += 50
        let travelled = EaselDependents.settle(looseMoved, previous: looseDocument, moved: [loose.id])
        let ends = EaselConnectorRouter.absolutePoints(travelled.items[2])
        #expect(EaselConnectorRoutingTestsSupport.near(ends.first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 130)) && EaselConnectorRoutingTestsSupport.near(ends.last ?? .init(x: 0, y: 0), EaselPoint(x: 450, y: 330)), "A connector with a free end drags that end and keeps the attached one")

        let removed = EaselDependents.removing([b.id], from: document)
        #expect(removed.items.count == 2 && removed.items.contains { $0.id == a.id }, "Removing takes only the chosen objects")
        let orphan = try #require(removed.items.first(where: { $0.id == item.id }), "Connectors outlive their objects")
        #expect(orphan.endConnection == nil && orphan.startConnection != nil, "Removing an object detaches its connector end")
        #expect(EaselConnectorRouter.absolutePoints(orphan) == EaselConnectorRouter.absolutePoints(item), "The freed connector keeps its last route")
        let resettled = EaselDependents.settle(removed, previous: removed, moved: [])
        #expect(resettled == removed, "A freed connector stays put afterwards")
    }
}
