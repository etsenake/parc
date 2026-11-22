import Foundation
import Testing
@testable import ParcCore

struct EaselConnectorRoutingPathsTests {
    @Test
    func anElbowBetweenFacingMagnetsBendsMidwayWithoutCrossingObjects() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Elbow routes resolve")
        let points = route.vertices
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(points), "Elbow routes only run across and down")
        #expect(EaselConnectorRoutingTestsSupport.near(points[0], EaselPoint(x: 200, y: 130)) && EaselConnectorRoutingTestsSupport.near(points[points.count - 1], EaselPoint(x: 400, y: 330)), "Elbow ends sit on the chosen magnets")
        #expect(EaselConnectorRoutingTestsSupport.near(points[1].y, 130) && points[1].x > 200, "The route leaves the right side heading right")
        #expect(EaselConnectorRoutingTestsSupport.near(points[points.count - 2].y, 330) && points[points.count - 2].x < 400, "The route arrives at the left side heading right")
        #expect(!EaselConnectorRoutingTestsSupport.crossesInterior(points, a.frame) && !EaselConnectorRoutingTestsSupport.crossesInterior(points, b.frame), "The route steers clear of both objects")
        #expect(points.count == 4 && EaselConnectorRoutingTestsSupport.near(points[1].x, 300), "A Z-shaped route bends half-way across the gap")
    }

    @Test
    func anElbowJoiningTheSameSideStaysOutsideBothObjects() throws {
        let c = EaselConnectorRoutingTestsSupport.box(100, 100), d = EaselConnectorRoutingTestsSupport.box(100, 300)
        let sameSide = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                 startConnection: EaselConnection(itemID: c.id, side: .right), endConnection: EaselConnection(itemID: d.id, side: .right))
        let loop = try #require(EaselConnectorRouter.route(for: sameSide, lookup: EaselConnectorRoutingTestsSupport.lookup([c, d])), "Same-side elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(loop.vertices) && !EaselConnectorRoutingTestsSupport.crossesInterior(loop.vertices, c.frame) && !EaselConnectorRoutingTestsSupport.crossesInterior(loop.vertices, d.frame), "Leaving and arriving on the same side loops around both objects")
        #expect(loop.vertices.allSatisfy { $0.x >= 200 - 1e-6 }, "The loop stays on the open side")
    }

    @Test
    func anElbowFacingAwayStillLeavesAndArrivesOutward() throws {
        let e = EaselConnectorRoutingTestsSupport.box(100, 100), f = EaselConnectorRoutingTestsSupport.box(400, 100)
        let backwards = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                  startConnection: EaselConnection(itemID: e.id, side: .left), endConnection: EaselConnection(itemID: f.id, side: .right))
        let around = try #require(EaselConnectorRouter.route(for: backwards, lookup: EaselConnectorRoutingTestsSupport.lookup([e, f])), "Backwards elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(around.vertices) && !EaselConnectorRoutingTestsSupport.crossesInterior(around.vertices, e.frame) && !EaselConnectorRoutingTestsSupport.crossesInterior(around.vertices, f.frame), "Facing away from each other still routes around both objects")
        #expect(around.vertices[1].x < 100 && around.vertices[around.vertices.count - 2].x > 500, "Both ends leave outward first")
    }

    @Test
    func anUnattachedElbowBendsMidwayBetweenItsEnds() throws {
        let free = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 10, y: 10), to: .init(x: 210, y: 110), routing: .elbow)
        let zed = try #require(EaselConnectorRouter.route(for: free, lookup: EaselConnectorRoutingTestsSupport.lookup([])), "Free elbows resolve")
        #expect(zed.vertices.count == 4 && EaselConnectorRoutingTestsSupport.orthogonal(zed.vertices) && EaselConnectorRoutingTestsSupport.near(zed.vertices[1].x, 110), "A free elbow makes a tidy Z through the middle")
    }

    @Test
    func automaticSidesRouteAroundBothObjects() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let auto = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id), endConnection: EaselConnection(itemID: b.id))
        let automatic = try #require(EaselConnectorRouter.route(for: auto, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Automatic elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(automatic.vertices) && !EaselConnectorRoutingTestsSupport.crossesInterior(automatic.vertices, a.frame) && !EaselConnectorRoutingTestsSupport.crossesInterior(automatic.vertices, b.frame), "Automatic sides still route cleanly")
    }

    @Test
    func elbowsStayInsideTheCanvasAtAnEdge() throws {
        let edge = EaselConnectorRoutingTestsSupport.box(4, 100), other = EaselConnectorRoutingTestsSupport.box(300, 100)
        let hugging = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                startConnection: EaselConnection(itemID: edge.id, side: .left), endConnection: EaselConnection(itemID: other.id, side: .left))
        let clamped = try #require(EaselConnectorRouter.route(for: hugging, lookup: EaselConnectorRoutingTestsSupport.lookup([edge, other])), "Edge-hugging elbows resolve")
        #expect(clamped.vertices.allSatisfy { $0.x >= 0 && $0.y >= 0 }, "Routes never wander off the top or left of the canvas")
    }

    @Test
    func overlappingObjectsStillGetAnOrthogonalRoute() throws {
        let overlapA = EaselConnectorRoutingTestsSupport.box(100, 100, 200, 200), overlapB = EaselConnectorRoutingTestsSupport.box(150, 150, 200, 200)
        let tangled = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                startConnection: EaselConnection(itemID: overlapA.id, side: .right), endConnection: EaselConnection(itemID: overlapB.id, side: .left))
        let crowded = try #require(EaselConnectorRouter.route(for: tangled, lookup: EaselConnectorRoutingTestsSupport.lookup([overlapA, overlapB])), "Overlapping objects still route")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(crowded.vertices) && crowded.vertices.count >= 2, "Overlapping objects still get an orthogonal route")
    }

    @Test func aDraggedMiddleSegmentStaysWhereItWasPut() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        var item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        item.waypoints = [EaselPoint(x: 340, y: 130), EaselPoint(x: 340, y: 330)]
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Manual elbows resolve")
        #expect(route.vertices.count == 4 && EaselConnectorRoutingTestsSupport.near(route.vertices[1].x, 340) && EaselConnectorRoutingTestsSupport.near(route.vertices[2].x, 340), "A dragged middle segment stays where it was put")
        var moved = a
        moved.frame.y = 160
        let followed = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([moved, b])), "Manual elbows follow their objects")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(followed.vertices) && EaselConnectorRoutingTestsSupport.near(followed.vertices[1].x, 340) && EaselConnectorRoutingTestsSupport.near(followed.vertices[1].y, 190), "Moving an object keeps the manual segment and re-squares the ends")
        var far = a
        far.frame.x = 700
        let fallback = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([far, b])), "Broken manual elbows still route")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(fallback.vertices) && fallback.vertices[1].x > 800 - 1e-6, "A manual route that no longer fits leaves its side correctly")
        let single = EaselConnectorRouter.manualElbow(from: EaselConnectorTerminal(point: .init(x: 0, y: 0), normal: EaselPoint(x: 1, y: 0), box: nil),
                                                      to: EaselConnectorTerminal(point: .init(x: 200, y: 100), normal: EaselPoint(x: -1, y: 0), box: nil),
                                                      corners: [EaselPoint(x: 120, y: 40)])
        #expect(single.map(EaselConnectorRoutingTestsSupport.orthogonal) == true && single?.contains { EaselConnectorRoutingTestsSupport.near($0.x, 120) } == true, "One bend between parallel sides becomes a Z through it")
    }

    @Test func elbowSegmentDragging() throws {
        let vertices = [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 200), EaselPoint(x: 300, y: 200)]
        let middle = try #require(EaselConnectorPath.movingElbowSegment(vertices, index: 1, by: 40), "Middle segments move")
        #expect(middle == [EaselPoint(x: 140, y: 0), EaselPoint(x: 140, y: 200)], "Dragging a middle segment slides it sideways")
        let first = try #require(EaselConnectorPath.movingElbowSegment(vertices, index: 0, by: 30), "First segments move")
        let firstPath = [vertices[0]] + first + [vertices[3]]
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(firstPath) && firstPath.count > vertices.count, "Dragging the first segment adds a bend instead of tearing the end off")
        #expect(EaselConnectorRoutingTestsSupport.near(firstPath[1].y, 0) && firstPath.contains { EaselConnectorRoutingTestsSupport.near($0.y, 30) }, "The first segment's new run sits where it was dragged")
        let last = try #require(EaselConnectorPath.movingElbowSegment(vertices, index: 2, by: -50), "Last segments move")
        let lastPath = [vertices[0]] + last + [vertices[3]]
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(lastPath) && lastPath.contains { EaselConnectorRoutingTestsSupport.near($0.y, 150) }, "Dragging the last segment adds a bend near the end")
        guard let straight = EaselConnectorPath.movingElbowSegment([EaselPoint(x: 0, y: 0), EaselPoint(x: 300, y: 0)], index: 0, by: 60) else {
            Issue.record("Straight elbows bend")
            return
        }
        let straightPath = [EaselPoint(x: 0, y: 0)] + straight + [EaselPoint(x: 300, y: 0)]
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(straightPath) && straightPath.contains { EaselConnectorRoutingTestsSupport.near($0.y, 60) }, "Dragging a single straight run makes a detour")
        #expect(EaselConnectorPath.movingElbowSegment(vertices, index: 7, by: 10) == nil, "Out-of-range segments are refused")
        let handles = EaselConnectorPath.elbowHandles(EaselConnectorRoute(routing: .elbow, segments: zip(vertices, vertices.dropFirst()).map { .line($0, $1) },
                                                                          vertices: vertices)!, scale: 1, attachedStart: false, attachedEnd: false)
        #expect(handles.count == 3 && handles[1].point == EaselPoint(x: 100, y: 100) && !handles[1].horizontal, "Each long segment gets a handle at its middle")
        let mapped = EaselConnectorPath.mapped([EaselPoint(x: 10, y: 10)], from: EaselRect(x: 0, y: 0, width: 20, height: 20),
                                               to: EaselRect(x: 100, y: 50, width: 40, height: 20))
        #expect(mapped == [EaselPoint(x: 120, y: 60)], "Bends travel and stretch with their connector")
    }

    @Test func curvesJoinTheChosenMagnets() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .curved,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Curved routes resolve")
        guard case .cubic(let s, let c1, let c2, let e)? = route.segments.first, route.segments.count == 1 else { Issue.record("A plain curve is one smooth span"); return }
        #expect(EaselConnectorRoutingTestsSupport.near(s, EaselPoint(x: 200, y: 130)) && EaselConnectorRoutingTestsSupport.near(e, EaselPoint(x: 400, y: 330)), "Curves join the chosen magnets")
        #expect(EaselConnectorRoutingTestsSupport.near(c1.y, 130) && c1.x > 200 && EaselConnectorRoutingTestsSupport.near(c2.y, 330) && c2.x < 400, "Curves leave and arrive perpendicular to each side")
        #expect(EaselConnectorRoutingTestsSupport.near(route.endDirection, EaselPoint(x: 1, y: 0), 1e-3), "The end head points straight into the left side")
        var bent = item
        bent.waypoints = [EaselPoint(x: 260, y: 400)]
        let through = try #require(EaselConnectorRouter.route(for: bent, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Bent curves resolve")
        #expect(through.segments.count == 2 && EaselConnectorRoutingTestsSupport.near(through.segments[0].end, EaselPoint(x: 260, y: 400)), "Curves pass through their bend points")
        #expect(through.distance(to: EaselPoint(x: 260, y: 400)) < 1e-6, "The pass-through point sits on the curve")
        let handles = EaselConnectorPath.curveHandles(through, waypoints: bent.waypoints ?? [])
        #expect(handles.filter { $0.waypoint != nil }.count == 1 && handles.filter { $0.waypoint == nil }.count == 2, "Curves offer their bend points plus a new-bend handle on each span")
        let straightFree = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 10, y: 10), to: .init(x: 210, y: 10), routing: .curved)
        let flat = try #require(EaselConnectorRouter.route(for: straightFree, lookup: EaselConnectorRoutingTestsSupport.lookup([])), "Flat curves resolve")
        #expect(flat.distance(to: EaselPoint(x: 110, y: 10)) < 1e-6, "A level free curve stays a clean line")
    }

    @Test func rotatedAndPinnedElbows() throws {
        var turned = EaselConnectorRoutingTestsSupport.box(100, 100, 100, 100)
        turned.rotation = 45
        let target = EaselConnectorRoutingTestsSupport.box(420, 320)
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: turned.id, side: .right),
                             endConnection: EaselConnection(itemID: target.id, side: .left))
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([turned, target])), "Rotated elbows resolve")
        let own = EaselShapeGeometry.visualBounds(of: turned)
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(route.vertices), "Elbows from rotated objects stay orthogonal")
        #expect(route.vertices.count > 2 && route.vertices[1].x >= own.x + own.width + EaselConnectorRouter.stub - 1e-6, "The first leg clears the rotated object's own box before it turns")
        #expect(!EaselConnectorRoutingTestsSupport.crossesInterior(Array(route.vertices.dropFirst()), own) && !EaselConnectorRoutingTestsSupport.crossesInterior(route.vertices, target.frame), "After leaving, the route never cuts back through either object")
        var spun = EaselConnectorRoutingTestsSupport.box(400, 300, 100, 100)
        spun.rotation = 30
        let mover = EaselConnectorRoutingTestsSupport.box(100, 100)
        let far = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                            startConnection: EaselConnection(itemID: mover.id, side: .right),
                            endConnection: EaselConnection(itemID: spun.id, side: .top))
        let arriving = try #require(EaselConnectorRouter.route(for: far, lookup: EaselConnectorRoutingTestsSupport.lookup([mover, spun])), "Elbows into rotated objects resolve")
        let spunBox = EaselShapeGeometry.visualBounds(of: spun)
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(arriving.vertices) && !EaselConnectorRoutingTestsSupport.crossesInterior(Array(arriving.vertices.dropLast()), spunBox), "Arriving at a rotated object only enters its box on the last leg")
        let wide = EaselConnectorRoutingTestsSupport.box(100, 100, 200, 100)
        let pinned = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                               startConnection: EaselConnection(itemID: wide.id, side: nil, anchor: EaselPoint(x: 0.5, y: 0.4)),
                               endConnection: EaselConnection(itemID: target.id, side: .left))
        let pinnedRoute = try #require(EaselConnectorRouter.route(for: pinned, lookup: EaselConnectorRoutingTestsSupport.lookup([wide, target])), "Pinned elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.near(pinnedRoute.vertices[0], EaselPoint(x: 200, y: 100)), "A pinned elbow leaves from the outline straight out from the pin")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(pinnedRoute.vertices) && !EaselConnectorRoutingTestsSupport.crossesInterior(Array(pinnedRoute.vertices.dropFirst()), wide.frame), "A pinned elbow never runs back across its own object")
        let straightPin = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .straight,
                                    startConnection: EaselConnection(itemID: wide.id, side: nil, anchor: EaselPoint(x: 0.5, y: 0.4)),
                                    endConnection: EaselConnection(itemID: target.id, side: .left))
        #expect(EaselConnectorRouter.route(for: straightPin, lookup: EaselConnectorRoutingTestsSupport.lookup([wide, target])).map { EaselConnectorRoutingTestsSupport.near($0.start, EaselPoint(x: 200, y: 140)) } == true, "Straight connectors still start right at the pin")
    }

    @Test func sameObjectEnds() throws {
        let solo = EaselConnectorRoutingTestsSupport.box(100, 100, 200, 100)
        let loop = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: nil,
                             startConnection: EaselConnection(itemID: solo.id), endConnection: EaselConnection(itemID: solo.id))
        let straight = try #require(EaselConnectorRouter.route(for: loop, lookup: EaselConnectorRoutingTestsSupport.lookup([solo])), "Same-object connectors resolve")
        #expect(EaselConnectorRoutingTestsSupport.near(straight.start, EaselPoint(x: 300, y: 150)) && EaselConnectorRoutingTestsSupport.near(straight.end, EaselPoint(x: 200, y: 200)) && straight.length > 1, "Both ends on one object take different sides instead of collapsing to a point")
        var elbowLoop = loop
        elbowLoop.routing = .elbow
        let elbow = try #require(EaselConnectorRouter.route(for: elbowLoop, lookup: EaselConnectorRoutingTestsSupport.lookup([solo])), "Same-object elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.orthogonal(elbow.vertices) && elbow.vertices.allSatisfy { $0.x >= 200 - 1e-6 && $0.y >= 150 - 1e-6 }, "A same-object elbow hops around one corner rather than circling the object")
        let sided = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                              startConnection: EaselConnection(itemID: solo.id, side: .top), endConnection: EaselConnection(itemID: solo.id))
        let corner = try #require(EaselConnectorRouter.route(for: sided, lookup: EaselConnectorRoutingTestsSupport.lookup([solo])), "Mixed same-object elbows resolve")
        #expect(EaselConnectorRoutingTestsSupport.near(corner.start, EaselPoint(x: 200, y: 100)) && EaselConnectorRoutingTestsSupport.near(corner.end, EaselPoint(x: 300, y: 150)), "An automatic end beside a fixed one moves on to the next side")
    }

    @Test func aFreedCurveRemembersWhereItsMiddleWas() throws {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        let curve = EaselConnectorRouter.settled(EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .curved,
                                                           startConnection: EaselConnection(itemID: a.id, side: .bottom),
                                                           endConnection: EaselConnection(itemID: b.id, side: .left)), lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        let before = try #require(EaselConnectorRouter.route(for: curve, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Curves resolve")
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, curve])
        let removed = EaselDependents.removing([b.id], from: board)
        let freed = try #require(removed.items.first(where: { $0.id == curve.id }), "Freed curves stay")
        #expect(freed.endConnection == nil && freed.waypoints?.count == 1, "A freed curve remembers where its middle was")
        #expect(freed.waypoints.map { EaselConnectorRoutingTestsSupport.near($0[0], before.location(atFraction: 0.5).point, 1e-6) } == true, "The remembered middle is the old middle")
        let after = try #require(EaselConnectorRouter.route(for: freed, lookup: EaselConnectorRoutingTestsSupport.lookup([a])), "Freed curves route")
        #expect(after.distance(to: before.location(atFraction: 0.5).point) < 1e-6, "The freed curve still passes through its old middle")
        var unrelated = removed
        unrelated.items.append(EaselConnectorRoutingTestsSupport.box(900, 900))
        let settled = EaselDependents.settle(unrelated, previous: removed, moved: [])
        #expect(settled.items.first(where: { $0.id == curve.id }) == freed, "An unrelated edit leaves the freed curve exactly where it was")
    }
}
