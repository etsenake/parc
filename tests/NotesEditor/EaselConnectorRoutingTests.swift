import Foundation

@main
struct EaselConnectorRoutingTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
    static func near(_ a: EaselPoint, _ b: EaselPoint, _ tolerance: Double = 1e-6) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }

    static func box(_ x: Double, _ y: Double, _ width: Double = 100, _ height: Double = 60, kind: EaselItemKind = .rectangle) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height))
    }

    static func connector(from start: EaselPoint, to end: EaselPoint, routing: EaselConnectorRouting? = nil,
                          startConnection: EaselConnection? = nil, endConnection: EaselConnection? = nil) -> EaselItem {
        let geometry = EaselToolGeometry.lineItemGeometry(from: start, to: end)
        var item = EaselItem(kind: .arrow, frame: geometry.frame)
        item.points = geometry.points
        item.routing = routing
        item.startConnection = startConnection
        item.endConnection = endConnection
        return item
    }

    static func lookup(_ items: [EaselItem]) -> (UUID) -> EaselItem? {
        let table = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return { table[$0] }
    }

    static func orthogonal(_ points: [EaselPoint]) -> Bool {
        zip(points, points.dropFirst()).allSatisfy { near($0.x, $1.x) || near($0.y, $1.y) }
    }

    static func crossesInterior(_ points: [EaselPoint], _ r: EaselRect) -> Bool {
        zip(points, points.dropFirst()).contains { a, b in
            let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
            return maxX > r.x + 0.5 && minX < r.x + r.width - 0.5 && maxY > r.y + 0.5 && minY < r.y + r.height - 0.5
        }
    }

    static func main() {
        magnetsAndSides()
        anchors()
        snapping()
        straightRoutes()
        elbowRoutes()
        manualElbows()
        elbowSegmentDragging()
        curvedRoutes()
        arrowHeads()
        labels()
        hitTesting()
        pathData()
        settling()
        dependents()
        exportSVG()
        print("EaselConnectorRoutingTests passed")
    }

    static func magnetsAndSides() {
        let rect = box(100, 100)
        expect(near(EaselConnectorAttachment.magnet(.top, on: rect), EaselPoint(x: 150, y: 100)), "The top magnet sits mid-way along the top edge")
        expect(near(EaselConnectorAttachment.magnet(.right, on: rect), EaselPoint(x: 200, y: 130)), "The right magnet sits mid-way down the right edge")
        expect(near(EaselConnectorAttachment.magnet(.bottom, on: rect), EaselPoint(x: 150, y: 160)), "The bottom magnet sits on the bottom edge")
        expect(near(EaselConnectorAttachment.magnet(.left, on: rect), EaselPoint(x: 100, y: 130)), "The left magnet sits on the left edge")
        var triangle = box(0, 0, 100, 100)
        triangle.shape = .triangle
        let apex = EaselConnectorAttachment.magnet(.top, on: triangle)
        expect(near(apex, EaselPoint(x: 50, y: 0), 0.5), "A triangle's top magnet is its apex")
        let flank = EaselConnectorAttachment.magnet(.left, on: triangle)
        expect(flank.x > 1 && near(flank.y, 50, 0.5), "A triangle's left magnet sits on its slanted outline, not the empty frame corner")
        var turned = box(0, 0, 100, 60)
        turned.rotation = 90
        let top = EaselConnectorAttachment.magnet(.top, on: turned)
        expect(near(top, EaselPoint(x: 80, y: 30), 1e-6), "A quarter-turned object's top magnet turns with it")
        let outward = EaselConnectorAttachment.outward(.top, on: turned)
        expect(near(outward, EaselPoint(x: 1, y: 0), 1e-9), "The quarter-turned top side faces right")
        expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 500, y: 140)) == .right, "A target far to the right faces right")
        expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 150, y: -300)) == .top, "A target far above faces up")
        expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: -40, y: 130)) == .left, "A target to the left faces left")
        expect(EaselConnectorAttachment.automaticSide(of: rect, toward: EaselPoint(x: 160, y: 900)) == .bottom, "A target below faces down")
        var locked = box(0, 0)
        locked.locked = true
        expect(!EaselConnectorAttachment.canAttach(to: locked), "Locked objects take no new connector ends")
        expect(EaselConnectorAttachment.resolves(locked), "Existing connections to a locked object keep working")
        expect(!EaselConnectorAttachment.canAttach(to: connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10))), "Connectors never attach to connectors")
    }

    static func anchors() {
        var item = box(100, 100, 200, 100)
        let anchor = EaselConnectorAttachment.anchor(at: EaselPoint(x: 150, y: 175), on: item)
        expect(near(anchor, EaselPoint(x: 0.25, y: 0.75)), "Pinned points are stored as fractions of the frame")
        expect(near(EaselConnectorAttachment.anchorPoint(anchor, on: item), EaselPoint(x: 150, y: 175)), "Pinned points map back to the same spot")
        item.rotation = 30
        item.flipHorizontal = true
        let spot = EaselPoint(x: 230, y: 160)
        let turned = EaselConnectorAttachment.anchor(at: spot, on: item)
        expect(near(EaselConnectorAttachment.anchorPoint(turned, on: item), spot, 1e-6), "Pinned points round-trip through rotation and flips")
        let outside = EaselConnectorAttachment.anchor(at: EaselPoint(x: -500, y: 2000), on: box(0, 0))
        expect(outside.x >= 0 && outside.x <= 1 && outside.y >= 0 && outside.y <= 1, "Pinned points stay inside the object")
        expect(EaselConnectorAttachment.nearestSide(of: EaselPoint(x: 0.95, y: 0.5), on: box(0, 0)) == .right, "A pin near the right edge leaves to the right")
        expect(EaselConnectorAttachment.nearestSide(of: EaselPoint(x: 0.5, y: 0.02), on: box(0, 0)) == .top, "A pin near the top leaves upwards")
    }

    static func snapping() {
        let target = box(100, 100, 200, 200)
        let edge = EaselConnectorAttachment.snap(EaselPoint(x: 296, y: 190), to: target, pin: false, scale: 1)
        expect(edge.connection?.side == .right && near(edge.point, EaselPoint(x: 300, y: 200)), "Ends snap to the nearest side magnet")
        let middle = EaselConnectorAttachment.snap(EaselPoint(x: 200, y: 200), to: target, pin: false, scale: 1)
        expect(middle.connection != nil && middle.connection?.side == nil && middle.connection?.anchor == nil,
               "Dropping in the middle of a roomy object lets the connector pick the side")
        let pinned = EaselConnectorAttachment.snap(EaselPoint(x: 140, y: 260), to: target, pin: true, scale: 1)
        expect(pinned.connection?.anchor.map { near($0, EaselPoint(x: 0.2, y: 0.8)) } == true && near(pinned.point, EaselPoint(x: 140, y: 260)),
               "Command pins the exact point")
        let small = EaselConnectorAttachment.snap(EaselPoint(x: 20, y: 20), to: box(0, 0, 40, 40), pin: false, scale: 1)
        expect(small.connection?.side != nil, "Small objects always snap to a side magnet")
        var locked = target
        locked.locked = true
        let refused = EaselConnectorAttachment.snap(EaselPoint(x: 296, y: 190), to: locked, pin: false, scale: 1)
        expect(refused.connection == nil && near(refused.point, EaselPoint(x: 296, y: 190)), "Locked objects leave the end free")
        let free = EaselConnectorAttachment.snap(EaselPoint(x: 5, y: 6), to: nil, pin: false, scale: 1)
        expect(free.connection == nil, "No object, no attachment")
    }

    static func straightRoutes() {
        let a = box(100, 100), b = box(400, 100)
        let item = connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10),
                             startConnection: EaselConnection(itemID: a.id), endConnection: EaselConnection(itemID: b.id))
        guard let route = EaselConnectorRouter.route(for: item, lookup: lookup([a, b])) else { failTest("A connected straight route resolves") }
        expect(near(route.start, EaselPoint(x: 200, y: 130)) && near(route.end, EaselPoint(x: 400, y: 130)),
               "A straight connector joins the facing magnets")
        expect(near(route.length, 200), "The straight route's length is the gap")
        var legacy = EaselItem(kind: .arrow, frame: EaselRect(x: 10, y: 20, width: 220, height: 140))
        legacy.points = [EaselPoint(x: 0, y: 140), EaselPoint(x: 120, y: 60), EaselPoint(x: 220, y: 0)]
        guard let old = EaselConnectorRouter.route(for: legacy, lookup: lookup([])) else { failTest("Legacy arrows route") }
        expect(old.vertices.count == 3 && near(old.vertices[1], EaselPoint(x: 130, y: 80)), "Legacy arrows keep every stored point")
        expect(EaselConnectorRouter.settled(legacy, lookup: lookup([])) == legacy, "Settling never touches a legacy arrow")
        let orphan = connector(from: .init(x: 10, y: 10), to: .init(x: 90, y: 50), startConnection: EaselConnection(itemID: UUID()))
        let settled = EaselConnectorRouter.settled(orphan, lookup: lookup([]))
        expect(settled.startConnection == nil && near(EaselConnectorRouter.absolutePoints(settled).first ?? .init(x: -1, y: -1), EaselPoint(x: 10, y: 10)),
               "A connection to a missing object turns into a free end where it last was")
    }

    static func elbowRoutes() {
        let a = box(100, 100), b = box(400, 300)
        let item = connector(from: .init(x: 0, y: 0), to: .init(x: 10, y: 10), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        guard let route = EaselConnectorRouter.route(for: item, lookup: lookup([a, b])) else { failTest("Elbow routes resolve") }
        let points = route.vertices
        expect(orthogonal(points), "Elbow routes only run across and down")
        expect(near(points[0], EaselPoint(x: 200, y: 130)) && near(points[points.count - 1], EaselPoint(x: 400, y: 330)), "Elbow ends sit on the chosen magnets")
        expect(near(points[1].y, 130) && points[1].x > 200, "The route leaves the right side heading right")
        expect(near(points[points.count - 2].y, 330) && points[points.count - 2].x < 400, "The route arrives at the left side heading right")
        expect(!crossesInterior(points, a.frame) && !crossesInterior(points, b.frame), "The route steers clear of both objects")
        expect(points.count == 4 && near(points[1].x, 300), "A Z-shaped route bends half-way across the gap")

        let c = box(100, 100), d = box(100, 300)
        let sameSide = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                 startConnection: EaselConnection(itemID: c.id, side: .right), endConnection: EaselConnection(itemID: d.id, side: .right))
        guard let loop = EaselConnectorRouter.route(for: sameSide, lookup: lookup([c, d])) else { failTest("Same-side elbows resolve") }
        expect(orthogonal(loop.vertices) && !crossesInterior(loop.vertices, c.frame) && !crossesInterior(loop.vertices, d.frame),
               "Leaving and arriving on the same side loops around both objects")
        expect(loop.vertices.allSatisfy { $0.x >= 200 - 1e-6 }, "The loop stays on the open side")

        let e = box(100, 100), f = box(400, 100)
        let backwards = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                  startConnection: EaselConnection(itemID: e.id, side: .left), endConnection: EaselConnection(itemID: f.id, side: .right))
        guard let around = EaselConnectorRouter.route(for: backwards, lookup: lookup([e, f])) else { failTest("Backwards elbows resolve") }
        expect(orthogonal(around.vertices) && !crossesInterior(around.vertices, e.frame) && !crossesInterior(around.vertices, f.frame),
               "Facing away from each other still routes around both objects")
        expect(around.vertices[1].x < 100 && around.vertices[around.vertices.count - 2].x > 500, "Both ends leave outward first")

        let free = connector(from: .init(x: 10, y: 10), to: .init(x: 210, y: 110), routing: .elbow)
        guard let zed = EaselConnectorRouter.route(for: free, lookup: lookup([])) else { failTest("Free elbows resolve") }
        expect(zed.vertices.count == 4 && orthogonal(zed.vertices) && near(zed.vertices[1].x, 110), "A free elbow makes a tidy Z through the middle")

        let auto = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id), endConnection: EaselConnection(itemID: b.id))
        guard let automatic = EaselConnectorRouter.route(for: auto, lookup: lookup([a, b])) else { failTest("Automatic elbows resolve") }
        expect(orthogonal(automatic.vertices) && !crossesInterior(automatic.vertices, a.frame) && !crossesInterior(automatic.vertices, b.frame),
               "Automatic sides still route cleanly")

        let edge = box(4, 100), other = box(300, 100)
        let hugging = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                startConnection: EaselConnection(itemID: edge.id, side: .left), endConnection: EaselConnection(itemID: other.id, side: .left))
        guard let clamped = EaselConnectorRouter.route(for: hugging, lookup: lookup([edge, other])) else { failTest("Edge-hugging elbows resolve") }
        expect(clamped.vertices.allSatisfy { $0.x >= 0 && $0.y >= 0 }, "Routes never wander off the top or left of the canvas")

        let overlapA = box(100, 100, 200, 200), overlapB = box(150, 150, 200, 200)
        let tangled = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                startConnection: EaselConnection(itemID: overlapA.id, side: .right), endConnection: EaselConnection(itemID: overlapB.id, side: .left))
        guard let crowded = EaselConnectorRouter.route(for: tangled, lookup: lookup([overlapA, overlapB])) else { failTest("Overlapping objects still route") }
        expect(orthogonal(crowded.vertices) && crowded.vertices.count >= 2, "Overlapping objects still get an orthogonal route")
    }

    static func manualElbows() {
        let a = box(100, 100), b = box(400, 300)
        var item = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        item.waypoints = [EaselPoint(x: 340, y: 130), EaselPoint(x: 340, y: 330)]
        guard let route = EaselConnectorRouter.route(for: item, lookup: lookup([a, b])) else { failTest("Manual elbows resolve") }
        expect(route.vertices.count == 4 && near(route.vertices[1].x, 340) && near(route.vertices[2].x, 340), "A dragged middle segment stays where it was put")
        var moved = a
        moved.frame.y = 160
        guard let followed = EaselConnectorRouter.route(for: item, lookup: lookup([moved, b])) else { failTest("Manual elbows follow their objects") }
        expect(orthogonal(followed.vertices) && near(followed.vertices[1].x, 340) && near(followed.vertices[1].y, 190),
               "Moving an object keeps the manual segment and re-squares the ends")
        var far = a
        far.frame.x = 700
        guard let fallback = EaselConnectorRouter.route(for: item, lookup: lookup([far, b])) else { failTest("Broken manual elbows still route") }
        expect(orthogonal(fallback.vertices) && fallback.vertices[1].x > 800 - 1e-6, "A manual route that no longer fits leaves its side correctly")
        let single = EaselConnectorRouter.manualElbow(from: EaselConnectorTerminal(point: .init(x: 0, y: 0), normal: EaselPoint(x: 1, y: 0), box: nil),
                                                      to: EaselConnectorTerminal(point: .init(x: 200, y: 100), normal: EaselPoint(x: -1, y: 0), box: nil),
                                                      corners: [EaselPoint(x: 120, y: 40)])
        expect(single.map(orthogonal) == true && single?.contains { near($0.x, 120) } == true, "One bend between parallel sides becomes a Z through it")
    }

    static func elbowSegmentDragging() {
        let vertices = [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 200), EaselPoint(x: 300, y: 200)]
        guard let middle = EaselConnectorPath.movingElbowSegment(vertices, index: 1, by: 40) else { failTest("Middle segments move") }
        expect(middle == [EaselPoint(x: 140, y: 0), EaselPoint(x: 140, y: 200)], "Dragging a middle segment slides it sideways")
        guard let first = EaselConnectorPath.movingElbowSegment(vertices, index: 0, by: 30) else { failTest("First segments move") }
        let firstPath = [vertices[0]] + first + [vertices[3]]
        expect(orthogonal(firstPath) && firstPath.count > vertices.count, "Dragging the first segment adds a bend instead of tearing the end off")
        expect(near(firstPath[1].y, 0) && firstPath.contains { near($0.y, 30) }, "The first segment's new run sits where it was dragged")
        guard let last = EaselConnectorPath.movingElbowSegment(vertices, index: 2, by: -50) else { failTest("Last segments move") }
        let lastPath = [vertices[0]] + last + [vertices[3]]
        expect(orthogonal(lastPath) && lastPath.contains { near($0.y, 150) }, "Dragging the last segment adds a bend near the end")
        guard let straight = EaselConnectorPath.movingElbowSegment([EaselPoint(x: 0, y: 0), EaselPoint(x: 300, y: 0)], index: 0, by: 60) else {
            failTest("Straight elbows bend")
        }
        let straightPath = [EaselPoint(x: 0, y: 0)] + straight + [EaselPoint(x: 300, y: 0)]
        expect(orthogonal(straightPath) && straightPath.contains { near($0.y, 60) }, "Dragging a single straight run makes a detour")
        expect(EaselConnectorPath.movingElbowSegment(vertices, index: 7, by: 10) == nil, "Out-of-range segments are refused")
        let handles = EaselConnectorPath.elbowHandles(EaselConnectorRoute(routing: .elbow, segments: zip(vertices, vertices.dropFirst()).map { .line($0, $1) },
                                                                          vertices: vertices)!, scale: 1, attachedStart: false, attachedEnd: false)
        expect(handles.count == 3 && handles[1].point == EaselPoint(x: 100, y: 100) && !handles[1].horizontal, "Each long segment gets a handle at its middle")
        let mapped = EaselConnectorPath.mapped([EaselPoint(x: 10, y: 10)], from: EaselRect(x: 0, y: 0, width: 20, height: 20),
                                               to: EaselRect(x: 100, y: 50, width: 40, height: 20))
        expect(mapped == [EaselPoint(x: 120, y: 60)], "Bends travel and stretch with their connector")
    }

    static func curvedRoutes() {
        let a = box(100, 100), b = box(400, 300)
        let item = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .curved,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        guard let route = EaselConnectorRouter.route(for: item, lookup: lookup([a, b])) else { failTest("Curved routes resolve") }
        guard case .cubic(let s, let c1, let c2, let e)? = route.segments.first, route.segments.count == 1 else { failTest("A plain curve is one smooth span") }
        expect(near(s, EaselPoint(x: 200, y: 130)) && near(e, EaselPoint(x: 400, y: 330)), "Curves join the chosen magnets")
        expect(near(c1.y, 130) && c1.x > 200 && near(c2.y, 330) && c2.x < 400, "Curves leave and arrive perpendicular to each side")
        expect(near(route.endDirection, EaselPoint(x: 1, y: 0), 1e-3), "The end head points straight into the left side")
        var bent = item
        bent.waypoints = [EaselPoint(x: 260, y: 400)]
        guard let through = EaselConnectorRouter.route(for: bent, lookup: lookup([a, b])) else { failTest("Bent curves resolve") }
        expect(through.segments.count == 2 && near(through.segments[0].end, EaselPoint(x: 260, y: 400)), "Curves pass through their bend points")
        expect(through.distance(to: EaselPoint(x: 260, y: 400)) < 1e-6, "The pass-through point sits on the curve")
        let handles = EaselConnectorPath.curveHandles(through, waypoints: bent.waypoints ?? [])
        expect(handles.filter { $0.waypoint != nil }.count == 1 && handles.filter { $0.waypoint == nil }.count == 2,
               "Curves offer their bend points plus a new-bend handle on each span")
        let straightFree = connector(from: .init(x: 10, y: 10), to: .init(x: 210, y: 10), routing: .curved)
        guard let flat = EaselConnectorRouter.route(for: straightFree, lookup: lookup([])) else { failTest("Flat curves resolve") }
        expect(flat.distance(to: EaselPoint(x: 110, y: 10)) < 1e-6, "A level free curve stays a clean line")
    }

    static func arrowHeads() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        let v = EaselArrowHeadGeometry.make(.arrow, tip: tip, direction: direction, width: 3)
        let angle = atan2(direction.y, direction.x)
        guard v.strokes.count == 1, v.strokes[0].points.count == 3 else { failTest("The line arrow is one open V") }
        expect(near(v.strokes[0].points[0], EaselPoint(x: tip.x - cos(angle - 0.5) * 16, y: tip.y - sin(angle - 0.5) * 16), 1e-9)
               && near(v.strokes[0].points[2], EaselPoint(x: tip.x - cos(angle + 0.5) * 16, y: tip.y - sin(angle + 0.5) * 16), 1e-9)
               && !v.strokes[0].closed && v.inset == 0, "The line arrow matches the original open V exactly")
        for head in EaselArrowHead.allCases {
            let geometry = EaselArrowHeadGeometry.make(head, tip: tip, direction: direction, width: 3)
            expect(head == .none ? geometry.isEmpty : !geometry.isEmpty, "\(head.rawValue) draws exactly when it should")
            let all = geometry.strokes.flatMap(\.points) + geometry.dots.map(\.center)
            expect(all.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(head.rawValue) has finite geometry")
            expect(geometry.inset >= 0 && geometry.inset < 40, "\(head.rawValue) trims the line sensibly")
        }
        expect(EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 3).strokes.first?.filled == true, "The solid arrow is filled")
        expect(EaselArrowHeadGeometry.make(.triangle, tip: tip, direction: direction, width: 3).strokes.first?.filled == false, "The triangle is hollow")
        expect(EaselArrowHeadGeometry.make(.circle, tip: tip, direction: direction, width: 3).dots.first?.filled == true, "The circle is filled")
        expect(EaselArrowHeadGeometry.make(.erdZeroOrMore, tip: tip, direction: direction, width: 3).gaps.count == 1, "The ERD ring leaves a gap in the line")
        expect(EaselArrowHeadGeometry.make(.erdExactlyOne, tip: tip, direction: direction, width: 3).strokes.count == 2, "Exactly one is two bars")
        expect(EaselArrowHeadGeometry.make(.erdOneOrMore, tip: tip, direction: direction, width: 3).strokes.count == 2, "One or more is a crow's foot and a bar")
        let thin = EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 2)
        let thick = EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 8)
        func spread(_ g: EaselArrowHeadGeometry) -> Double {
            guard let points = g.strokes.first?.points, points.count == 3 else { return 0 }
            return hypot(points[0].x - points[2].x, points[0].y - points[2].y)
        }
        expect(spread(thick) > spread(thin) * 1.5, "Heads grow with the stroke")
        let circle = EaselArrowHeadGeometry.make(.circle, tip: tip, direction: direction, width: 3).pathData
        expect(circle.hasPrefix("M") && circle.contains("A"), "Circle heads export as arcs")
    }

    static func labels() {
        guard let route = EaselConnectorRoute(routing: .straight, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 400, y: 0))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 400, y: 0)]) else { failTest("Routes build") }
        let size = (width: 60.0, height: 18.0)
        let rect = EaselConnectorLabel.rect(on: route, position: 0.5, size: size)
        expect(near(rect.x + rect.width / 2, 200) && near(rect.y + rect.height / 2, 0), "Labels sit centred on the path")
        expect(near(rect.width, 60 + 2 * EaselConnectorLabel.paddingX), "Labels get a little breathing room")
        let early = EaselConnectorLabel.rect(on: route, position: 0.25, size: size)
        expect(near(early.x + early.width / 2, 100), "Labels follow their position along the path")
        expect(EaselConnectorLabel.canSlide(on: route, size: size), "Long lines let labels slide")
        let clamped = EaselConnectorLabel.clampedPosition(0, on: route, size: size)
        expect(clamped > 0 && clamped < 0.5, "Labels never slide off the end")
        guard let short = EaselConnectorRoute(routing: .straight, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 70, y: 0))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 70, y: 0)]) else { failTest("Short routes build") }
        expect(!EaselConnectorLabel.canSlide(on: short, size: size) && EaselConnectorLabel.clampedPosition(0.1, on: short, size: size) == 0.5,
               "Short lines keep their label in the middle")
        expect(near(EaselConnectorLabel.position(nearest: EaselPoint(x: 300, y: 40), on: route, size: size), 0.75), "Dragging a label follows the pointer along the path")
        guard let hidden = EaselConnectorLabel.hiddenRange(on: route, rect: rect) else { failTest("Labels hide the line behind them") }
        expect(hidden.lowerBound < 200 - 30 && hidden.upperBound > 200 + 30 && hidden.upperBound - hidden.lowerBound < 120,
               "Only the part of the line under the label is hidden")
        let pieces = route.pieces(hiding: [hidden])
        expect(pieces.count == 2, "A label splits the line in two")
    }

    static func hitTesting() {
        let item = connector(from: .init(x: 0, y: 100), to: .init(x: 300, y: 100), routing: .straight,
                             startConnection: nil, endConnection: nil)
        guard let route = EaselConnectorRouter.route(for: item, lookup: lookup([])) else { failTest("Hit routes build") }
        let drawing = EaselConnectorDrawing(route: route, item: item)
        for scale in [0.3333, 0.5, 1, 2, 4] {
            let reach = EaselConnectorHit.reach(for: item, scale: scale)
            expect(reach * scale >= 10, "The hit band is at least ten points each side at \(scale)x")
            expect(EaselConnectorHit.contains(EaselPoint(x: 150, y: 100 + 9.9 / scale), drawing: drawing, item: item, scale: scale),
                   "Clicking just beside the line hits it at \(scale)x")
        }
        expect(!EaselConnectorHit.contains(EaselPoint(x: 150, y: 160), drawing: drawing, item: item, scale: 1), "Clicks well away miss")
        let a = box(0, 0), b = box(300, 300)
        let elbow = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                              startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .top))
        guard let bent = EaselConnectorRouter.route(for: elbow, lookup: lookup([a, b])) else { failTest("Elbow hits build") }
        let corner = bent.vertices[1]
        expect(EaselConnectorHit.contains(corner, drawing: EaselConnectorDrawing(route: bent, item: elbow), item: elbow, scale: 1), "Elbow corners are hittable")
        expect(EaselConnectorHit.intersects(EaselRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10), route: bent), "Marquees catch elbow corners")
        expect(!EaselConnectorHit.intersects(EaselRect(x: 1000, y: 1000, width: 10, height: 10), route: bent), "Marquees elsewhere miss")
    }

    static func pathData() {
        guard let route = EaselConnectorRoute(routing: .curved, segments: [.cubic(EaselPoint(x: 0, y: 0), EaselPoint(x: 50, y: 0),
                                                                                    EaselPoint(x: 50, y: 100), EaselPoint(x: 100, y: 100))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 100)]) else { failTest("Curves build") }
        let data = EaselConnectorRoute.pathData([route.segments])
        expect(data == "M0 0C50 0 50 100 100 100", "Curves export as a single cubic")
        let trimmed = route.subpath(from: 10, to: route.length - 10)
        expect(trimmed.count == 1 && !near(trimmed[0].start, EaselPoint(x: 0, y: 0)) && !near(trimmed[0].end, EaselPoint(x: 100, y: 100)),
               "Trimming a curve shortens both ends")
        let location = route.location(atFraction: 0.5)
        expect(near(location.point, EaselPoint(x: 50, y: 50), 0.5), "Half-way along a symmetric curve is its middle")
        guard let polyline = EaselConnectorRoute(routing: .elbow, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)),
                                                                              .line(EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 50))],
                                                 vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 50)]) else { failTest("Polylines build") }
        expect(EaselConnectorRoute.pathData([polyline.segments]) == "M0 0L100 0L100 50", "Elbows export as straight runs")
        let pieces = polyline.pieces(hiding: [0...10, 140...150])
        expect(pieces.count == 1 && near(pieces[0].first?.start ?? .init(x: -1, y: -1), EaselPoint(x: 10, y: 0))
               && near(pieces[0].last?.end ?? .init(x: -1, y: -1), EaselPoint(x: 100, y: 40)), "Head insets trim the line ends")
        expect(near(polyline.length, 150) && near(polyline.endDirection, EaselPoint(x: 0, y: 1)) && near(polyline.startDirection, EaselPoint(x: -1, y: 0)),
               "Routes know their length and which way each end points")
    }

    static func settling() {
        let a = box(100, 100), b = box(400, 300)
        let item = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        let settled = EaselConnectorRouter.settled(item, lookup: lookup([a, b]))
        let points = EaselConnectorRouter.absolutePoints(settled)
        expect(near(points.first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 130)) && near(points.last ?? .init(x: 0, y: 0), EaselPoint(x: 400, y: 330)),
               "Settling stores the live route's ends")
        expect(points.count == 4 && orthogonal(points), "Settling stores the elbow's corners")
        expect(settled.frame.x >= 0 && settled.frame.width >= 1 && settled.frame.height >= 1, "Settled frames are valid")
        expect(EaselConnectorRouter.settled(settled, lookup: lookup([a, b])) == settled, "Settling twice changes nothing")
        let curved = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .curved,
                               startConnection: EaselConnection(itemID: a.id, side: .bottom), endConnection: EaselConnection(itemID: b.id, side: .top))
        let settledCurve = EaselConnectorRouter.settled(curved, lookup: lookup([a, b]))
        expect(settledCurve.points.count > 10, "Curves store a smooth trace for hit tests and older readers")
        expect(EaselConnectorRouter.settled(settledCurve, lookup: lookup([a, b])) == settledCurve, "Curves settle once")
        let detached = EaselConnectorRouter.detached(settled, from: [a.id])
        expect(detached.startConnection == nil && detached.endConnection != nil, "Removing an object frees only its own end")
        guard let kept = EaselConnectorRouter.route(for: detached, lookup: lookup([b])) else { failTest("Detached elbows route") }
        expect(kept.vertices == points, "A freed elbow keeps its last route")
    }

    static func dependents() {
        let a = box(100, 100), b = box(400, 300)
        let item = EaselConnectorRouter.settled(connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                                          startConnection: EaselConnection(itemID: a.id, side: .right),
                                                          endConnection: EaselConnection(itemID: b.id, side: .left)), lookup: lookup([a, b]))
        let document = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, item])
        var next = document
        next.items[0].frame.y += 80
        let settled = EaselDependents.settle(next, previous: document, moved: [a.id])
        guard let connector = settled.items.first(where: { $0.id == item.id }) else { failTest("Connectors survive a move") }
        expect(near(EaselConnectorRouter.absolutePoints(connector).first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 210)),
               "A connector follows the object it is attached to")
        expect(EaselDependents.settle(settled, previous: settled, moved: []) == settled, "Settling a settled board is a no-op")

        var dragged = document
        dragged.items[2].frame.x += 50
        let stuck = EaselDependents.settle(dragged, previous: document, moved: [item.id])
        expect(stuck.items[2] == item, "A connector with both ends attached doesn't drag on its own")

        var loose = item
        loose.endConnection = nil
        let looseDocument = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [a, b, loose])
        var looseMoved = looseDocument
        looseMoved.items[2].frame.x += 50
        let travelled = EaselDependents.settle(looseMoved, previous: looseDocument, moved: [loose.id])
        let ends = EaselConnectorRouter.absolutePoints(travelled.items[2])
        expect(near(ends.first ?? .init(x: 0, y: 0), EaselPoint(x: 200, y: 130)) && near(ends.last ?? .init(x: 0, y: 0), EaselPoint(x: 450, y: 330)),
               "A connector with a free end drags that end and keeps the attached one")

        let removed = EaselDependents.removing([b.id], from: document)
        expect(removed.items.count == 2 && removed.items.contains { $0.id == a.id }, "Removing takes only the chosen objects")
        guard let orphan = removed.items.first(where: { $0.id == item.id }) else { failTest("Connectors outlive their objects") }
        expect(orphan.endConnection == nil && orphan.startConnection != nil, "Removing an object detaches its connector end")
        expect(EaselConnectorRouter.absolutePoints(orphan) == EaselConnectorRouter.absolutePoints(item), "The freed connector keeps its last route")
        let resettled = EaselDependents.settle(removed, previous: removed, moved: [])
        expect(resettled == removed, "A freed connector stays put afterwards")
        pipeline()
    }

    static func exportSVG() {
        let a = box(100, 100), b = box(400, 300)
        var item = connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        item.startHead = .circle
        item.endHead = .diamond
        item.strokeDash = .dashed
        item.text = "yes"
        item.labelBackground = true
        item = EaselConnectorRouter.settled(item, lookup: lookup([a, b]))
        var art = EaselVectorArt()
        art.connectorRoutes[item.id] = EaselConnectorRouter.route(for: item, lookup: lookup([a, b]))
        art.connectorLabels[item.id] = EaselConnectorLabelArt(text: EaselVectorText(runs: [EaselVectorTextRun(x: 0, y: 12, text: "yes",
                                                                                                             fontFamily: "sans-serif", fontSize: 15)]),
                                                              width: 24, height: 18)
        let svg = EaselVectorExport.element(item, art: art)
        expect(svg.hasPrefix("<g class=\"easel-connector\">") && svg.hasSuffix("</g>"), "Connectors export as one group")
        expect(svg.contains("stroke-dasharray:9 9"), "Dashed connectors keep their dashes")
        expect(svg.components(separatedBy: "<path").count == 4, "The line and each filled head are separate paths")
        expect(svg.contains("A") && svg.contains("<rect") && svg.contains(">yes</text>"), "Circle heads, label pills and label text all export")
        expect(svg.contains("fill:var(--easel-card)"), "Label text on an automatic-ink pill uses the paper-side colour in both themes")
        expect(EaselVectorExport.labelInk(on: "#FFE299") == EaselPalette.inkLight && EaselVectorExport.labelInk(on: "#2C6C91") == EaselPalette.neutralLight,
               "Label text picks dark ink on light pills and white on dark ones")
        var legacy = EaselItem(kind: .arrow, frame: .init(x: 10, y: 10, width: 100, height: 1))
        legacy.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        let plain = EaselVectorExport.element(legacy, art: EaselVectorArt())
        expect(plain.contains("M10 10L110 10") && plain.contains("M95.959 17.671L110 10L95.959 2.329"),
               "Legacy arrows export the same straight line and open V")
    }

    static func pipeline() {
        let sticky = EaselItem(kind: .sticky, frame: EaselRect(x: 100, y: 100, width: 200, height: 200))
        var highlight = EaselItem(kind: .freehand, frame: EaselRect(x: 120, y: 150, width: 100, height: 10))
        highlight.points = [EaselPoint(x: 0, y: 5), EaselPoint(x: 100, y: 5)]
        highlight.brush = .highlighter
        highlight.attachedTo = sticky.id
        let far = box(600, 120)
        let link = EaselConnectorRouter.settled(connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .straight,
                                                          startConnection: EaselConnection(itemID: highlight.id, side: .right),
                                                          endConnection: EaselConnection(itemID: far.id, side: .left)),
                                                lookup: lookup([sticky, highlight, far]))
        let board = EaselDocument(id: UUID(), title: "Board", createdAt: Date(), modifiedAt: Date(), items: [sticky, highlight, far, link])
        var dragged = board
        dragged.items[0].frame.x += 40
        dragged.items[0].frame.y += 30
        let settled = EaselDependents.settle(dragged, previous: board, moved: [sticky.id])
        guard let carried = settled.items.first(where: { $0.id == highlight.id }),
              let rerouted = settled.items.first(where: { $0.id == link.id }) else { failTest("Everything survives the drag") }
        expect(near(carried.frame.x, 160) && near(carried.frame.y, 180), "A sticky-on follows its sticky")
        expect(near(EaselConnectorRouter.absolutePoints(rerouted).first ?? .init(x: 0, y: 0), EaselPoint(x: 260, y: 185)),
               "A connector attached to a sticky-on follows it too")
        expect(EaselDependents.settle(settled, previous: settled, moved: []) == settled, "The carried board is settled")

        var a = box(0, 0), b = box(300, 0), c = box(600, 0)
        b.attachedTo = a.id
        c.attachedTo = b.id
        let chain = EaselDocument(id: UUID(), title: "Chain", createdAt: Date(), modifiedAt: Date(), items: [a, b, c])
        expect(EaselDependents.removalClosure([a.id], in: chain) == [a.id, b.id, c.id], "Removing an object takes everything stuck to it, all the way down")
        a.attachedTo = b.id
        let loop = EaselDocument(id: UUID(), title: "Loop", createdAt: Date(), modifiedAt: Date(), items: [a, b, c])
        expect(EaselDependents.removalClosure([b.id], in: loop) == [a.id, b.id, c.id], "Objects stuck to each other in a loop come off together")
        expect(EaselDependents.removalClosure([UUID()], in: loop).isEmpty, "Unknown objects remove nothing")

        let section = EaselItem(kind: .section, frame: EaselRect(x: 0, y: 0, width: 500, height: 500))
        let inside = box(50, 50), outside = box(900, 900)
        let edge = EaselConnectorRouter.settled(connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                                                          startConnection: EaselConnection(itemID: inside.id, side: .right),
                                                          endConnection: EaselConnection(itemID: outside.id, side: .left)),
                                                lookup: lookup([inside, outside]))
        let grouped = EaselDocument(id: UUID(), title: "Sections", createdAt: Date(), modifiedAt: Date(), items: [section, inside, outside, edge])
        let cleared = EaselDependents.removing([section.id], from: grouped)
        expect(!cleared.items.contains { $0.id == inside.id } && cleared.items.contains { $0.id == outside.id },
               "Deleting a section takes what's inside it")
        guard let freed = cleared.items.first(where: { $0.id == edge.id }) else { failTest("Connectors leaving a deleted section stay") }
        expect(freed.startConnection == nil && freed.endConnection != nil, "A connector from a deleted section's member is freed, not left dangling")
        let kept = EaselDependents.removing([section.id], from: grouped, keepingSectionContents: true)
        expect(kept.items.contains { $0.id == inside.id } && !kept.items.contains { $0.id == section.id },
               "Keeping contents deletes only the section")
    }
}
