import Foundation
import Testing
@testable import ParcCore

enum EaselFreehandDrawingTestsSupport {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func near(_ a: EaselPoint, _ b: EaselPoint, _ tolerance: Double = 1e-6) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }

    static func p(_ x: Double, _ y: Double) -> EaselPoint { EaselPoint(x: x, y: y) }

    static func stroke(_ absolute: [EaselPoint], brush: EaselBrush? = nil) -> EaselItem {
        let placed = EaselDrawing.geometry(absolute)!
        var item = EaselItem(kind: .freehand, frame: placed.frame, points: placed.points)
        item.brush = brush
        return item
    }

    static func object(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000EA")!, title: "Board",
                      createdAt: Date(timeIntervalSinceReferenceDate: 0), modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }
}
