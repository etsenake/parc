import Foundation

enum EaselTextColor {
    static func recoloured(_ item: EaselItem, hex raw: String) -> EaselItem? {
        guard let hex = EaselPalette.normalized(raw), item.kind.holdsText, !item.isLocked else { return nil }
        var next = item
        if item.kind == .text { next.color = hex }
        if var rich = item.richText {
            for index in rich.runs.indices {
                rich.runs[index].attributes.ink = hex + "FF"
                rich.runs[index].attributes.semanticInk = nil
            }
            next.richText = rich
        }
        return next == item ? nil : next
    }

    static func needsRuns(_ item: EaselItem) -> Bool {
        item.kind.holdsText && item.kind != .text && item.richText == nil && !item.text.isEmpty
    }

    static func recolouring(_ document: EaselDocument, ids: Set<UUID>, hex: String,
                            runs make: (EaselItem, String) -> EaselRichText?) -> EaselDocument? {
        guard let hex = EaselPalette.normalized(hex) else { return nil }
        var next = document, changed = false
        for index in next.items.indices where ids.contains(next.items[index].id) {
            var item = next.items[index]
            guard item.kind.holdsText, !item.isLocked else { continue }
            if needsRuns(item) {
                guard let rich = make(item, hex) else { continue }
                item.richText = rich
            }
            guard let recoloured = recoloured(item, hex: hex) ?? (item == next.items[index] ? nil : item) else { continue }
            next.items[index] = recoloured
            changed = true
        }
        return changed ? next : nil
    }
}
