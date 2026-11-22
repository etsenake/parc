import Foundation
import Testing
@testable import ParcCore

struct EaselConnectorRoutingPresentationTests {
    @Test
    func theLineArrowMatchesTheOriginalOpenVExactly() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        let v = EaselArrowHeadGeometry.make(.arrow, tip: tip, direction: direction, width: 3)
        let angle = atan2(direction.y, direction.x)
        guard v.strokes.count == 1, v.strokes[0].points.count == 3 else { Issue.record("The line arrow is one open V"); return }
        #expect(EaselConnectorRoutingTestsSupport.near(v.strokes[0].points[0], EaselPoint(x: tip.x - cos(angle - 0.5) * 16, y: tip.y - sin(angle - 0.5) * 16), 1e-9)
               && EaselConnectorRoutingTestsSupport.near(v.strokes[0].points[2], EaselPoint(x: tip.x - cos(angle + 0.5) * 16, y: tip.y - sin(angle + 0.5) * 16), 1e-9)
               && !v.strokes[0].closed && v.inset == 0, "The line arrow matches the original open V exactly")
    }

    @Test
    func arrowheadsStayFiniteAndTrimTheShaft() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        for head in EaselArrowHead.allCases {
            let geometry = EaselArrowHeadGeometry.make(head, tip: tip, direction: direction, width: 3)
            #expect(head == .none ? geometry.isEmpty : !geometry.isEmpty, "\(head.rawValue) draws exactly when it should")
            let all = geometry.strokes.flatMap(\.points) + geometry.dots.map(\.center)
            #expect(all.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(head.rawValue) has finite geometry")
            #expect(geometry.inset >= 0 && geometry.inset < 40, "\(head.rawValue) trims the line sensibly")
        }
    }

    @Test
    func arrowheadsHaveTheirOwnFillStyle() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        #expect(EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 3).strokes.first?.filled == true, "The solid arrow is filled")
        #expect(EaselArrowHeadGeometry.make(.triangle, tip: tip, direction: direction, width: 3).strokes.first?.filled == false, "The triangle is hollow")
        #expect(EaselArrowHeadGeometry.make(.circle, tip: tip, direction: direction, width: 3).dots.first?.filled == true, "The circle is filled")
    }

    @Test
    func entityRelationshipHeadsShowTheirCardinality() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        #expect(EaselArrowHeadGeometry.make(.erdZeroOrMore, tip: tip, direction: direction, width: 3).gaps.count == 1, "The ERD ring leaves a gap in the line")
        #expect(EaselArrowHeadGeometry.make(.erdExactlyOne, tip: tip, direction: direction, width: 3).strokes.count == 2, "Exactly one is two bars")
        #expect(EaselArrowHeadGeometry.make(.erdOneOrMore, tip: tip, direction: direction, width: 3).strokes.count == 2, "One or more is a crow's foot and a bar")
    }

    @Test
    func arrowheadsGrowWithStrokeWidth() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        let thin = EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 2)
        let thick = EaselArrowHeadGeometry.make(.solidArrow, tip: tip, direction: direction, width: 8)
        func spread(_ g: EaselArrowHeadGeometry) -> Double {
            guard let points = g.strokes.first?.points, points.count == 3 else { return 0 }
            return hypot(points[0].x - points[2].x, points[0].y - points[2].y)
        }
        #expect(spread(thick) > spread(thin) * 1.5, "Heads grow with the stroke")
    }

    @Test
    func circleHeadsExportAsArcs() {
        let tip = EaselPoint(x: 100, y: 50), direction = EaselPoint(x: 0.6, y: 0.8)
        let circle = EaselArrowHeadGeometry.make(.circle, tip: tip, direction: direction, width: 3).pathData
        #expect(circle.hasPrefix("M") && circle.contains("A"), "Circle heads export as arcs")
    }

    @Test func labelsSitCentredOnThePath() throws {
        guard let route = EaselConnectorRoute(routing: .straight, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 400, y: 0))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 400, y: 0)]) else { Issue.record("Routes build"); return }
        let size = (width: 60.0, height: 18.0)
        let rect = EaselConnectorLabel.rect(on: route, position: 0.5, size: size)
        #expect(EaselConnectorRoutingTestsSupport.near(rect.x + rect.width / 2, 200) && EaselConnectorRoutingTestsSupport.near(rect.y + rect.height / 2, 0), "Labels sit centred on the path")
        #expect(EaselConnectorRoutingTestsSupport.near(rect.width, 60 + 2 * EaselConnectorLabel.paddingX), "Labels get a little breathing room")
        let early = EaselConnectorLabel.rect(on: route, position: 0.25, size: size)
        #expect(EaselConnectorRoutingTestsSupport.near(early.x + early.width / 2, 100), "Labels follow their position along the path")
        #expect(EaselConnectorLabel.canSlide(on: route, size: size), "Long lines let labels slide")
        let clamped = EaselConnectorLabel.clampedPosition(0, on: route, size: size)
        #expect(clamped > 0 && clamped < 0.5, "Labels never slide off the end")
        guard let short = EaselConnectorRoute(routing: .straight, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 70, y: 0))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 70, y: 0)]) else { Issue.record("Short routes build"); return }
        #expect(!EaselConnectorLabel.canSlide(on: short, size: size) && EaselConnectorLabel.clampedPosition(0.1, on: short, size: size) == 0.5, "Short lines keep their label in the middle")
        #expect(EaselConnectorRoutingTestsSupport.near(EaselConnectorLabel.position(nearest: EaselPoint(x: 300, y: 40), on: route, size: size), 0.75), "Dragging a label follows the pointer along the path")
        let hidden = try #require(EaselConnectorLabel.hiddenRange(on: route, rect: rect), "Labels hide the line behind them")
        #expect(hidden.lowerBound < 200 - 30 && hidden.upperBound > 200 + 30 && hidden.upperBound - hidden.lowerBound < 120, "Only the part of the line under the label is hidden")
        let pieces = route.pieces(hiding: [hidden])
        #expect(pieces.count == 2, "A label splits the line in two")
    }

    @Test func theHitBandIsAtLeastTenPointsEach() throws {
        let item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 100), to: .init(x: 300, y: 100), routing: .straight,
                             startConnection: nil, endConnection: nil)
        let route = try #require(EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([])), "Hit routes build")
        let drawing = EaselConnectorDrawing(route: route, item: item)
        for scale in [0.3333, 0.5, 1, 2, 4] {
            let reach = EaselConnectorHit.reach(for: item, scale: scale)
            #expect(reach * scale >= 10, "The hit band is at least ten points each side at \(scale)x")
            #expect(EaselConnectorHit.contains(EaselPoint(x: 150, y: 100 + 9.9 / scale), drawing: drawing, item: item, scale: scale), "Clicking just beside the line hits it at \(scale)x")
        }
        #expect(!EaselConnectorHit.contains(EaselPoint(x: 150, y: 160), drawing: drawing, item: item, scale: 1), "Clicks well away miss")
        let a = EaselConnectorRoutingTestsSupport.box(0, 0), b = EaselConnectorRoutingTestsSupport.box(300, 300)
        let elbow = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                              startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .top))
        let bent = try #require(EaselConnectorRouter.route(for: elbow, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b])), "Elbow hits build")
        let corner = bent.vertices[1]
        #expect(EaselConnectorHit.contains(corner, drawing: EaselConnectorDrawing(route: bent, item: elbow), item: elbow, scale: 1), "Elbow corners are hittable")
        #expect(EaselConnectorHit.intersects(EaselRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10), route: bent), "Marquees catch elbow corners")
        #expect(!EaselConnectorHit.intersects(EaselRect(x: 1000, y: 1000, width: 10, height: 10), route: bent), "Marquees elsewhere miss")
    }

    @Test func curvesExportAsASingleCubic() {
        guard let route = EaselConnectorRoute(routing: .curved, segments: [.cubic(EaselPoint(x: 0, y: 0), EaselPoint(x: 50, y: 0),
                                                                                    EaselPoint(x: 50, y: 100), EaselPoint(x: 100, y: 100))],
                                              vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 100)]) else { Issue.record("Curves build"); return }
        let data = EaselConnectorRoute.pathData([route.segments])
        #expect(data == "M0 0C50 0 50 100 100 100", "Curves export as a single cubic")
        let trimmed = route.subpath(from: 10, to: route.length - 10)
        #expect(trimmed.count == 1 && !EaselConnectorRoutingTestsSupport.near(trimmed[0].start, EaselPoint(x: 0, y: 0)) && !EaselConnectorRoutingTestsSupport.near(trimmed[0].end, EaselPoint(x: 100, y: 100)), "Trimming a curve shortens both ends")
        let location = route.location(atFraction: 0.5)
        #expect(EaselConnectorRoutingTestsSupport.near(location.point, EaselPoint(x: 50, y: 50), 0.5), "Half-way along a symmetric curve is its middle")
        guard let polyline = EaselConnectorRoute(routing: .elbow, segments: [.line(EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0)),
                                                                              .line(EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 50))],
                                                 vertices: [EaselPoint(x: 0, y: 0), EaselPoint(x: 100, y: 0), EaselPoint(x: 100, y: 50)]) else { Issue.record("Polylines build"); return }
        #expect(EaselConnectorRoute.pathData([polyline.segments]) == "M0 0L100 0L100 50", "Elbows export as straight runs")
        let pieces = polyline.pieces(hiding: [0...10, 140...150])
        #expect(pieces.count == 1 && EaselConnectorRoutingTestsSupport.near(pieces[0].first?.start ?? .init(x: -1, y: -1), EaselPoint(x: 10, y: 0))
               && EaselConnectorRoutingTestsSupport.near(pieces[0].last?.end ?? .init(x: -1, y: -1), EaselPoint(x: 100, y: 40)), "Head insets trim the line ends")
        #expect(EaselConnectorRoutingTestsSupport.near(polyline.length, 150) && EaselConnectorRoutingTestsSupport.near(polyline.endDirection, EaselPoint(x: 0, y: 1)) && EaselConnectorRoutingTestsSupport.near(polyline.startDirection, EaselPoint(x: -1, y: 0)), "Routes know their length and which way each end points")
    }

    @Test func exportSVG() {
        let a = EaselConnectorRoutingTestsSupport.box(100, 100), b = EaselConnectorRoutingTestsSupport.box(400, 300)
        var item = EaselConnectorRoutingTestsSupport.connector(from: .init(x: 0, y: 0), to: .init(x: 1, y: 1), routing: .elbow,
                             startConnection: EaselConnection(itemID: a.id, side: .right), endConnection: EaselConnection(itemID: b.id, side: .left))
        item.startHead = .circle
        item.endHead = .diamond
        item.strokeDash = .dashed
        item.text = "yes"
        item.labelBackground = true
        item = EaselConnectorRouter.settled(item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        var art = EaselVectorArt()
        art.connectorRoutes[item.id] = EaselConnectorRouter.route(for: item, lookup: EaselConnectorRoutingTestsSupport.lookup([a, b]))
        art.connectorLabels[item.id] = EaselConnectorLabelArt(text: EaselVectorText(runs: [EaselVectorTextRun(x: 0, y: 12, text: "yes",
                                                                                                             fontFamily: "sans-serif", fontSize: 15)]),
                                                              width: 24, height: 18)
        let svg = EaselVectorExport.element(item, art: art)
        #expect(svg.hasPrefix("<g class=\"easel-connector\">") && svg.hasSuffix("</g>"), "Connectors export as one group")
        #expect(svg.contains("stroke-dasharray:9 9"), "Dashed connectors keep their dashes")
        #expect(svg.components(separatedBy: "<path").count == 4, "The line and each filled head are separate paths")
        #expect(svg.contains("A") && svg.contains("<rect") && svg.contains(">yes</text>"), "Circle heads, label pills and label text all export")
        #expect(svg.contains("fill:var(--easel-card)"), "Label text on an automatic-ink pill uses the paper-side colour in both themes")
        #expect(EaselVectorExport.labelInk(on: "#FFE299") == EaselPalette.inkLight && EaselVectorExport.labelInk(on: "#2C6C91") == EaselPalette.neutralLight, "Label text picks dark ink on light pills and white on dark ones")
        var legacy = EaselItem(kind: .arrow, frame: .init(x: 10, y: 10, width: 100, height: 1))
        legacy.points = [.init(x: 0, y: 0), .init(x: 100, y: 0)]
        let plain = EaselVectorExport.element(legacy, art: EaselVectorArt())
        #expect(plain.contains("M10 10L110 10") && plain.contains("M95.959 17.671L110 10L95.959 2.329"), "Legacy arrows export the same straight line and open V")
    }
}
