import Foundation
import Testing
@testable import ParcCore

enum EaselArrangeTestsSupport {
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 }

    static func box(_ x: Double, _ y: Double, _ width: Double = 100, _ height: Double = 100,
                    kind: EaselItemKind = .sticky, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSince1970: 0),
                      modifiedAt: Date(timeIntervalSince1970: 0), items: items)
    }

    static func frame(_ document: EaselDocument?, _ id: UUID) -> EaselRect? {
        document?.items.first { $0.id == id }?.frame
    }
}
