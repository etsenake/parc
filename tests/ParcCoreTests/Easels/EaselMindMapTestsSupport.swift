import Foundation
import Testing
@testable import ParcCore

enum EaselMindMapTestsSupport {
    static func document(_ items: [EaselItem]) -> EaselDocument {
        EaselDocument(id: UUID(), title: "Map", createdAt: Date(timeIntervalSinceReferenceDate: 0),
                      modifiedAt: Date(timeIntervalSinceReferenceDate: 0), items: items)
    }

    @MainActor static func accepts(_ items: [EaselItem]) -> Bool {
        (try? EaselSession(inMemory: document(items), assets: [:])) != nil
    }

    static func node(_ text: String, width: Double = 120, height: Double = 30, kind: EaselItemKind = .text) -> EaselItem {
        EaselItem(kind: kind, frame: EaselRect(x: 400, y: 300, width: width, height: height), text: text)
    }

    static func item(_ id: UUID, in document: EaselDocument) -> EaselItem? { document.items.first { $0.id == id } }

    static func nodes(_ document: EaselDocument) -> [EaselItem] { document.items.filter(EaselMindMap.isNode) }
    static func branches(_ document: EaselDocument) -> [EaselItem] { document.items.filter(EaselMindMap.isBranch) }

    static func overlaps(_ document: EaselDocument) -> Bool {
        let hidden = EaselMindMap.hiddenIDs(in: document.items)
        let frames = nodes(document).filter { !hidden.contains($0.id) }.map(\.frame)
        for (index, a) in frames.enumerated() {
            for b in frames[(index + 1)...] where a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height {
                return true
            }
        }
        return false
    }

    static func starter() -> (document: EaselDocument, root: UUID, kids: [UUID]) {
        let root = node("Big idea", width: 160, height: 40)
        let kids = [node("One"), node("Two")]
        let made = EaselMindMap.creatingMap(root: root, children: kids, in: document([])) ?? document([])
        return (made, root.id, kids.map(\.id))
    }
}
