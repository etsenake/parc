import Foundation
import Testing
@testable import ParcCore

enum EaselShapeGeometryTestsSupport {
    static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func close(_ a: EaselRect?, _ b: EaselRect, _ tolerance: Double = 1e-6) -> Bool {
        guard let a else { return false }
        return close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
            && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }

    static func shapeItem(_ shape: EaselShape, _ frame: EaselRect) -> EaselItem {
        var item = EaselItem(kind: shape == .ellipse ? .circle : .rectangle, frame: frame)
        if shape != .ellipse { item.shape = shape }
        return item
    }
}
