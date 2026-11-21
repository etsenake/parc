import Foundation

enum EaselColorRole: String, CaseIterable {
    case ink, fill, sticky
}

enum EaselPaletteColor: Hashable, CaseIterable {
    case automatic
    case neutral
    case note(NoteColor)

    static let allCases: [EaselPaletteColor] = [.automatic, .neutral] + NoteColor.allCases.map { .note($0) }

    init?(id: String) {
        switch id {
        case "automatic": self = .automatic
        case "neutral": self = .neutral
        default:
            guard let color = NoteColor(rawValue: id) else { return nil }
            self = .note(color)
        }
    }

    var id: String {
        switch self {
        case .automatic: return "automatic"
        case .neutral: return "neutral"
        case .note(let color): return color.rawValue
        }
    }

    func title(dark: Bool) -> String {
        switch self {
        case .automatic: return "Default"
        case .neutral: return dark ? "Black" : "White"
        case .note(let color): return color.rawValue.capitalized
        }
    }
}

struct EaselColorVariants: Equatable {
    var canonical: String
    var light: String
    var dark: String
    var adapts: Bool { light != dark }
}

enum EaselPalette {
    static let automaticInk = "#252525"
    static let inkLight = "#1F1B2E"
    static let inkDark = "#EDEBFA"
    static let neutralLight = "#FFFFFF"
    static let neutralDark = "#2A2733"
    static let defaultSticky = EaselPaletteColor.note(.yellow)

    private typealias Pair = (light: String, dark: String)

    private static func values(_ color: NoteColor) -> (ink: Pair, fill: Pair, sticky: Pair) {
        switch color {
        case .gray: return (("#686865", "#9C9C9C"), ("#E8E8E7", "#434246"), ("#CFCECD", "#565558"))
        case .brown: return (("#895C48", "#C1927F"), ("#EEE4DF", "#4C3C39"), ("#DAC5BB", "#644B45"))
        case .orange: return (("#B05D0B", "#CE8E5F"), ("#FAE7D5", "#553D2F"), ("#F5CDA7", "#724E36"))
        case .yellow: return (("#956B23", "#CA9849"), ("#FAF0D8", "#55462E"), ("#F5E0AC", "#725B34"))
        case .green: return (("#3B7255", "#5EAB7F"), ("#DCEBE2", "#2D463B"), ("#B5D5C2", "#355B48"))
        case .blue: return (("#2C6C91", "#4CA5D8"), ("#D8E9F3", "#27425A"), ("#AED0E6", "#2B5675"))
        case .purple: return (("#8154A3", "#B48CDD"), ("#EBE2F3", "#45365A"), ("#D5C3E6", "#594475"))
        case .pink: return (("#AD3C78", "#DC7FAF"), ("#F6DEEB", "#562F48"), ("#EDBAD5", "#73395A"))
        case .red: return (("#C0322D", "#E77F7D"), ("#F9DEDC", "#593033"), ("#F2BAB6", "#773B3B"))
        }
    }

    private static func pair(_ color: NoteColor, role: EaselColorRole) -> Pair {
        let entry = values(color)
        switch role {
        case .ink: return entry.ink
        case .fill: return entry.fill
        case .sticky: return entry.sticky
        }
    }

    static func colors(for role: EaselColorRole) -> [EaselPaletteColor] {
        let notes = NoteColor.allCases.map { EaselPaletteColor.note($0) }
        return role == .ink ? [.automatic] + notes : [.neutral] + notes
    }

    static func hex(_ color: EaselPaletteColor, role: EaselColorRole) -> String? {
        switch color {
        case .automatic: return role == .ink ? automaticInk : nil
        case .neutral: return role == .ink ? nil : neutralLight
        case .note(let value): return pair(value, role: role).light
        }
    }

    static func normalized(_ hex: String) -> String? {
        let value = hex.uppercased()
        let digits = value.dropFirst()
        guard value.first == "#", digits.count == 6 || (digits.count == 8 && digits.hasSuffix("FF")),
              digits.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(value.prefix(7))
    }

    static func color(for hex: String, role: EaselColorRole) -> EaselPaletteColor? {
        guard let value = normalized(hex) else { return nil }
        if role == .ink, value == automaticInk { return .automatic }
        if role != .ink, value == neutralLight { return .neutral }
        return NoteColor.allCases.first { pair($0, role: role).light == value }.map { .note($0) }
    }

    static func resolve(_ hex: String, role: EaselColorRole, dark: Bool) -> String {
        guard let value = normalized(hex) else { return hex }
        switch color(for: value, role: role) {
        case .automatic?: return dark ? inkDark : inkLight
        case .neutral?: return dark ? neutralDark : neutralLight
        case .note(let note)?: return dark ? pair(note, role: role).dark : value
        case nil: return value
        }
    }

    static func variants(_ hex: String, role: EaselColorRole) -> EaselColorVariants? {
        guard let value = normalized(hex) else { return nil }
        return EaselColorVariants(canonical: value, light: resolve(value, role: role, dark: false),
                                  dark: resolve(value, role: role, dark: true))
    }
}

enum EaselPaintRules {
    enum Fill: Equatable {
        case none
        case wash(opacity: Double)
        case color(hex: String, role: EaselColorRole, opacity: Double)
    }

    static let shapeWidth = 2.5
    static let lineWidth = 3.0
    static let washOpacity = 0.09
    static let maximumWidth = 64.0

    static func takesFill(_ kind: EaselItemKind) -> Bool {
        kind == .rectangle || kind == .circle || kind == .sticky || kind == .section
    }

    static func takesStroke(_ kind: EaselItemKind) -> Bool {
        kind == .rectangle || kind == .circle || kind == .arrow || kind == .freehand || kind == .sticky || kind == .section
    }

    static func fillRole(_ kind: EaselItemKind) -> EaselColorRole { kind == .sticky ? .sticky : .fill }

    static func defaultStrokeWidth(_ kind: EaselItemKind) -> Double {
        switch kind {
        case .rectangle, .circle: return shapeWidth
        case .arrow, .freehand: return lineWidth
        default: return 0
        }
    }

    static func strokeWidth(_ item: EaselItem) -> Double {
        guard takesStroke(item.kind) else { return 0 }
        guard let width = item.strokeWidth, width.isFinite else { return defaultStrokeWidth(item.kind) }
        return min(maximumWidth, max(0, width))
    }

    static func dashPattern(_ dash: EaselStrokeDash?, width: Double) -> [Double] {
        let unit = max(1, width.isFinite ? width : 1)
        switch dash ?? .solid {
        case .solid: return []
        case .dashed: return [unit * 3, unit * 3]
        case .dotted: return [0, unit * 2]
        }
    }

    static func arrowHeadLength(width: Double) -> Double { 10 + 2 * max(0, width) }

    static func fill(_ item: EaselItem) -> Fill {
        guard takesFill(item.kind) else { return .none }
        let opacity = item.fillOpacity.map { $0.isFinite ? min(1, max(0, $0)) : 1 }
        if opacity == 0 { return .none }
        let role = fillRole(item.kind)
        if let hex = item.fill.flatMap(EaselPalette.normalized) { return .color(hex: hex, role: role, opacity: opacity ?? 1) }
        if item.kind == .sticky, let hex = EaselPalette.hex(EaselPalette.defaultSticky, role: .sticky) {
            return .color(hex: hex, role: .sticky, opacity: opacity ?? 1)
        }
        return .wash(opacity: opacity ?? washOpacity)
    }
}
