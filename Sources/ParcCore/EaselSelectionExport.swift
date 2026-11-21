import Foundation

package enum EaselSelectionExport {
    package static func scope(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        let live = ids.intersection(Set(document.items.map(\.id)))
        guard !live.isEmpty else { return [] }
        let expanded = EaselArrange.withFollowers(EaselBoardObjects.withContents(live, in: document), in: document)
        return expanded.subtracting(EaselBoardObjects.hiddenIDs(in: document.items))
    }

    package static func document(_ document: EaselDocument, keeping ids: Set<UUID>) -> EaselDocument {
        let dropped = Set(document.items.map(\.id)).subtracting(ids)
        var next = EaselDependents.removing(dropped, from: document, keepingSectionContents: true)
        next.items.removeAll { !ids.contains($0.id) }
        return next
    }

    package static func stickies(in document: EaselDocument, within ids: Set<UUID>? = nil) -> [EaselItem] {
        let hidden = EaselBoardObjects.hiddenIDs(in: document.items)
        let chosen = ids.map { scope($0, in: document) }
        let stickies = document.items.filter { item in
            item.kind == .sticky && !hidden.contains(item.id) && (chosen?.contains(item.id) ?? true)
        }
        return EaselFinder.readingOrder(stickies)
    }

    package static func stickyCSV(_ stickies: [EaselItem]) -> String {
        let rows = ["Content"] + stickies.map { stickyCSVField($0.text) }
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    package static func stickyCSVField(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "\u{FFFC}", with: "")
        guard let first = text.unicodeScalars.first else { return "\"\"" }
        guard "=+-@\t\r".unicodeScalars.contains(first) else { return EaselTableData.field(text, separator: ",") }
        return "\"'" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
