import Foundation

extension EaselSlashObject {
    var catalogID: String? {
        switch self {
        case .sticky, .shape: return nil
        default: return rawValue
        }
    }
}

enum EaselSlashAction: Hashable {
    case text(id: String)
    case divider
    case mention
    case date
    case emoji
    case inlineEquation
    case object(EaselSlashObject)
}

struct EaselSlashRow: Hashable, Identifiable {
    var item: NoteCatalogItem
    var action: EaselSlashAction
    var id: String { item.id }
}

enum EaselSlashCatalog {
    static let textIDs = ["text", "heading1", "heading2", "heading3", "bulleted", "numbered", "todo", "quote", "divider"]
    static let inlineIDs = ["mention", "date", "emoji", "inlineEquation"]

    private static let summaries: [EaselSlashObject: String] = [
        .sticky: "A square note to jot on.",
        .shape: "A rectangle, circle and friends.",
        .file: "Attach any file to the Easel.",
        .pdf: "Read a PDF right on the Easel.",
        .embed: "Bring a live page onto the Easel.",
    ]

    static func rows(in context: EaselSlashContext) -> [EaselSlashRow] {
        var result: [EaselSlashRow] = []
        for id in textIDs + inlineIDs {
            guard let item = NoteBlockCatalog.item(id), let action = action(for: id, in: context) else { continue }
            result.append(EaselSlashRow(item: item, action: action))
        }
        guard context.objects else { return result }
        for object in EaselSlashObject.allCases {
            result.append(EaselSlashRow(item: objectItem(object), action: .object(object)))
        }
        return result
    }

    static func results(for query: String, in context: EaselSlashContext) -> [EaselSlashRow] {
        let rows = rows(in: context)
        let normalized = NoteBlockCatalog.normalize(query)
        guard !normalized.isEmpty else { return rows }
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return NoteBlockCatalog.rank(rows.map(\.item), normalized, keepEmpty: false).compactMap { byID[$0.id] }
    }

    private static func action(for id: String, in context: EaselSlashContext) -> EaselSlashAction? {
        switch id {
        case "todo": return context.checklist ? .text(id: id) : nil
        case "divider": return context.divider ? .divider : nil
        case "mention": return context.mention ? .mention : nil
        case "date": return context.date ? .date : nil
        case "emoji": return .emoji
        case "inlineEquation": return context.inlineEquation ? .inlineEquation : nil
        default: return .text(id: id)
        }
    }

    private static func objectItem(_ object: EaselSlashObject) -> NoteCatalogItem {
        let summary = summaries[object]
        if let id = object.catalogID, let base = NoteBlockCatalog.item(id) {
            return NoteCatalogItem(id: "easel." + object.rawValue, title: base.title, summary: summary ?? base.summary, section: .easel,
                                   icon: base.icon, hint: nil, aliases: base.aliases, keywords: base.keywords, effect: base.effect)
        }
        switch object {
        case .sticky:
            return NoteCatalogItem(id: "easel.sticky", title: "Sticky", summary: summary ?? "", section: .easel, icon: .symbol("note.text"), hint: nil,
                                   aliases: ["note", "post-it", "postit", "card"], keywords: ["idea", "paper", "jot", "memo"], effect: .host("sticky"))
        default:
            return NoteCatalogItem(id: "easel.shape", title: "Shape", summary: summary ?? "", section: .easel, icon: .symbol("square.on.circle"), hint: nil,
                                   aliases: ["rectangle", "circle", "box", "ellipse"], keywords: ["diagram", "flow", "draw"], effect: .host("shape"))
        }
    }
}
