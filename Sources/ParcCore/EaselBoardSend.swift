import Foundation

package enum EaselBoardSend {
    static let gap = 80.0

    package static func landing(_ items: [EaselItem], in document: EaselDocument) -> EaselDocument? {
        guard let content = EaselArrange.union(items.map(EaselArrange.visualFrame)) else { return nil }
        var offset = EaselPoint(x: 0, y: 0)
        if let existing = EaselArrange.union(document.items.map(EaselArrange.visualFrame)) {
            offset = EaselPoint(x: existing.x + existing.width + gap - content.x, y: existing.y - content.y)
        }
        let first = EaselPages.firstPageID(document)
        var placed = items
        for index in placed.indices { placed[index].page = first }
        guard let result = EaselArrange.appending(placed, to: document, offset: offset, keepingGroups: Set(placed.compactMap(\.groupID))) else { return nil }
        return result.document
    }
}
