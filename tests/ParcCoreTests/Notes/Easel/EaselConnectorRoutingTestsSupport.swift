import Foundation
import Testing
@testable import ParcCore

enum EaselConnectorRoutingTestsSupport {
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
}
