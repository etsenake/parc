import Foundation

enum EaselSelectionExport {
    static func scope(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        let live = ids.intersection(Set(document.items.map(\.id)))
        guard !live.isEmpty else { return [] }
        let expanded = EaselArrange.withFollowers(EaselBoardObjects.withContents(live, in: document), in: document)
        return expanded.subtracting(EaselBoardObjects.hiddenIDs(in: document.items))
    }

    static func document(_ document: EaselDocument, keeping ids: Set<UUID>) -> EaselDocument {
        let dropped = Set(document.items.map(\.id)).subtracting(ids)
        var next = EaselDependents.removing(dropped, from: document, keepingSectionContents: true)
        next.items.removeAll { !ids.contains($0.id) }
        return next
    }

    static func stickies(in document: EaselDocument, within ids: Set<UUID>? = nil) -> [EaselItem] {
        let hidden = EaselBoardObjects.hiddenIDs(in: document.items)
        let chosen = ids.map { scope($0, in: document) }
        let stickies = document.items.filter { item in
            item.kind == .sticky && !hidden.contains(item.id) && (chosen?.contains(item.id) ?? true)
        }
        return EaselFinder.readingOrder(stickies)
    }

    static func stickyCSV(_ stickies: [EaselItem]) -> String {
        let rows = ["Content"] + stickies.map { EaselTableData.field($0.text, separator: ",") }
        return rows.joined(separator: "\r\n") + "\r\n"
    }
}
