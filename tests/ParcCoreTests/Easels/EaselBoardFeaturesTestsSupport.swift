import Foundation
import Testing
@testable import ParcCore

enum EaselBoardFeaturesTestsSupport {
    static func item(_ kind: EaselItemKind, _ text: String, x: Double, y: Double, width: Double = 200, height: Double = 100) -> EaselItem {
        EaselItem(kind: kind, frame: .init(x: x, y: y, width: width, height: height), text: text)
    }

    static func locked(_ value: EaselItem) -> EaselItem {
        var copy = value
        copy.locked = true
        return copy
    }

    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Board", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    static func attributes(_ ink: String, bold: Bool = false) -> EaselRichText.Attributes {
        EaselRichText.Attributes(font: .init(name: "Helvetica", size: 15, traits: bold ? 2 : 0), ink: ink)
    }

    static func session(_ query: String, in board: EaselDocument) -> EaselFindSession {
        var value = EaselFindSession()
        value.query = query
        value.refresh(in: board, keeping: nil)
        return value
    }
}
