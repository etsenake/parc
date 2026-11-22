import Foundation
import CoreGraphics
import Testing
@testable import ParcCore

enum EaselImageFramingTestsSupport {
    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 0.01) -> Bool {
        close(a.minX, b.minX, tolerance) && close(a.minY, b.minY, tolerance) && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }
    static func close(_ a: EaselRect?, _ b: EaselRect?, _ tolerance: Double = 0.0002) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!

    static func image(_ frame: EaselRect = .init(x: 100, y: 100, width: 200, height: 100)) -> EaselItem {
        EaselItem(kind: .image, frame: frame, assetID: UUID().uuidString.lowercased() + ".png")
    }
}
