import Foundation
import Testing
@testable import ParcCore

enum EaselBoardObjectsTestsSupport {
    static func item(_ kind: EaselItemKind, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                     z: Int = 0, text: String = "") -> EaselItem {
        var value = EaselItem(kind: kind, frame: EaselRect(x: x, y: y, width: width, height: height), zIndex: z, text: text)
        if kind == .arrow || kind == .freehand { value.points = [EaselPoint(x: 0, y: 0), EaselPoint(x: width, y: height)] }
        return value
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor static func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }
}
