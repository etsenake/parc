import Foundation
import Testing
@testable import ParcCore

enum EaselPagesTestsSupport {
    static func item(_ kind: EaselItemKind, x: Double, y: Double, width: Double = 100, height: Double = 80, z: Int = 0) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), zIndex: z)
    }

    static func arrow(from start: UUID?, to end: UUID?, x: Double = 100, y: Double = 40) -> EaselItem {
        var value = EaselItem(kind: .arrow, frame: .init(x: x, y: y, width: 200, height: 1),
                              points: [EaselPoint(x: 0, y: 0), EaselPoint(x: 200, y: 0)])
        value.startConnection = start.map { EaselConnection(itemID: $0) }
        value.endConnection = end.map { EaselConnection(itemID: $0) }
        return value
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    static func paged(_ items: [EaselItem]) -> (document: EaselDocument, first: UUID, second: UUID) {
        guard let change = EaselPages.adding(to: document(items)), let first = change.document.pages?.first?.id,
              let second = change.page else {
            Issue.record("adding a page failed")
            return (document(items), UUID(), UUID())
        }
        return (change.document, first, second)
    }
}
