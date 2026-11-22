import Foundation
import Testing
@testable import ParcCore

enum EaselTransformTestsSupport {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func near(_ a: EaselPoint, _ b: EaselPoint, _ tolerance: Double = 1e-6) -> Bool { near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) }

    static func near(_ a: EaselRect, _ b: EaselRect, _ tolerance: Double = 1e-6) -> Bool {
        near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance) && near(a.width, b.width, tolerance) && near(a.height, b.height, tolerance)
    }

    static func item(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                     rotation: Double? = nil, flipH: Bool? = nil, flipV: Bool? = nil) -> EaselItem {
        var value = EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height))
        value.rotation = rotation; value.flipHorizontal = flipH; value.flipVertical = flipV
        if kind == .image { value.assetID = UUID().uuidString.lowercased() + ".png" }
        if kind == .arrow || kind == .freehand { value.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: width, y: height)] }
        return value
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Rotation", createdAt: Date(), modifiedAt: Date(), items: items)
    }
}
