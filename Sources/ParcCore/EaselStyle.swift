import Foundation

package enum EaselStrokeWeight: String, CaseIterable, Codable {
    case none, thin, medium, thick

    package var title: String {
        switch self {
        case .none: return "None"
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }

    fileprivate var step: Int {
        switch self {
        case .none: return 0
        case .thin: return 1
        case .medium: return 2
        case .thick: return 3
        }
    }
}

package enum EaselFillMode: String, CaseIterable, Codable {
    case none, transparent, solid

    package var title: String {
        switch self {
        case .none: return "No Fill"
        case .transparent: return "Transparent"
        case .solid: return "Solid"
        }
    }
}

package enum EaselStyleFamily: String, CaseIterable, Codable {
    case shapes, stickies, lines, pen, highlighter, tape, text, sections, icons, equations

    package static func of(_ item: EaselItem) -> EaselStyleFamily? {
        switch item.kind {
        case .rectangle, .circle: return .shapes
        case .sticky: return .stickies
        case .section: return .sections
        case .arrow: return .lines
        case .text: return .text
        case .stamp: return EaselStampFace(item: item)?.isIcon == true ? .icons : nil
        case .equation: return .equations
        case .freehand:
            switch item.resolvedBrush {
            case .marker: return .pen
            case .highlighter: return .highlighter
            case .washi: return .tape
            }
        default: return nil
        }
    }

    var colorRole: EaselColorRole {
        switch self {
        case .stickies: return .sticky
        case .sections: return .fill
        case .highlighter: return .highlight
        case .shapes, .lines, .pen, .tape, .text, .icons, .equations: return .ink
        }
    }

    var takesFill: Bool { self == .shapes }
    var takesDash: Bool { self == .shapes || self == .lines }

    var weights: [EaselStrokeWeight] {
        switch self {
        case .shapes: return [.none, .thin, .medium, .thick]
        case .lines, .pen, .highlighter: return [.thin, .medium, .thick]
        case .stickies, .sections, .tape, .text, .icons, .equations: return []
        }
    }

    func width(_ weight: EaselStrokeWeight) -> Double? {
        guard weights.contains(weight) else { return nil }
        let scale: [Double]
        switch self {
        case .shapes: scale = [0, 1.5, 2.5, 5]
        case .highlighter: scale = [0, 10, 16, 24]
        default: scale = [0, 1.5, 3, 6]
        }
        return scale[weight.step]
    }

    func weight(forWidth width: Double) -> EaselStrokeWeight? {
        let options = weights.compactMap { weight in self.width(weight).map { (weight, $0) } }
        return options.min { abs($0.1 - width) < abs($1.1 - width) }?.0
    }
}

package enum EaselColorChoice: Hashable {
    case palette(EaselPaletteColor)
    case custom(String)

    init?(storage: String) {
        if storage.hasPrefix("#") {
            guard let hex = EaselPalette.normalized(storage) else { return nil }
            self = .custom(hex)
        } else {
            guard let color = EaselPaletteColor(id: storage) else { return nil }
            self = .palette(color)
        }
    }

    var storage: String {
        switch self {
        case .palette(let color): return color.id
        case .custom(let hex): return hex
        }
    }

    package static func recognizing(_ hex: String, role: EaselColorRole) -> EaselColorChoice? {
        if let color = EaselPalette.color(for: hex, role: role) { return .palette(color) }
        return EaselPalette.normalized(hex).map { .custom($0) }
    }

    package func hex(role: EaselColorRole) -> String {
        switch self {
        case .palette(let color): return EaselPalette.stored(color, role: role)
        case .custom(let hex): return EaselPalette.normalized(hex) ?? EaselPalette.automaticInk
        }
    }
}

package enum EaselStyleChange: Equatable {
    case color(EaselColorChoice)
    case fill(EaselFillMode)
    case fillOpacity(Double)
    case weight(EaselStrokeWeight)
    case dash(EaselStrokeDash)
    case labelBackground(Bool)

    package var actionName: String {
        switch self {
        case .color: return "Change color"
        case .fill, .fillOpacity: return "Change fill"
        case .weight: return "Change line width"
        case .dash: return "Change line style"
        case .labelBackground: return "Label background"
        }
    }
}

package struct EaselStyleControls: Equatable {
    package var colorRole: EaselColorRole
    package var colors: [EaselPaletteColor]
    package var fill: Bool
    package var weights: [EaselStrokeWeight]
    package var dash: Bool
    package var labelBackground: Bool
    package var lineTitle: String

    init(colorRole: EaselColorRole, colors: [EaselPaletteColor], fill: Bool = false, weights: [EaselStrokeWeight] = [],
         dash: Bool = false, labelBackground: Bool = false, lineTitle: String = "Line") {
        self.colorRole = colorRole; self.colors = colors; self.fill = fill; self.weights = weights
        self.dash = dash; self.labelBackground = labelBackground; self.lineTitle = lineTitle
    }

    package init?(families: Set<EaselStyleFamily>) {
        guard !families.isEmpty else { return nil }
        let roles = Set(families.map(\.colorRole))
        if roles.count == 1, let role = roles.first { colorRole = role }
        else if roles.isSubset(of: [.sticky, .fill]) { colorRole = .sticky }
        else { colorRole = .ink }
        colors = EaselPalette.colors(for: colorRole)
        fill = families.contains(.shapes)
        let weighted = families.filter { !$0.weights.isEmpty }
        var options = EaselStrokeWeight.allCases.filter { weight in weighted.contains { $0.weights.contains(weight) } }
        if weighted.contains(where: { !$0.weights.contains(.none) }) { options.removeAll { $0 == .none } }
        weights = options
        dash = families.contains { $0.takesDash }
        labelBackground = families.contains(.lines)
        lineTitle = families.filter { !$0.weights.isEmpty || $0.takesDash } == [.shapes] ? "Outline" : "Line"
    }

    package init?(items: [EaselItem]) { self.init(families: Set(items.compactMap(EaselStyleFamily.of))) }
}

package struct EaselStyleSummary: Equatable {
    package var color: EaselColorChoice?
    package var fill: EaselFillMode?
    package var fillOpacity: Double?
    package var weight: EaselStrokeWeight?
    package var dash: EaselStrokeDash?
    package var labelBackground: Bool?

    package init(color: EaselColorChoice? = nil, fill: EaselFillMode? = nil, fillOpacity: Double? = nil,
         weight: EaselStrokeWeight? = nil, dash: EaselStrokeDash? = nil, labelBackground: Bool? = nil) {
        self.color = color; self.fill = fill; self.fillOpacity = fillOpacity; self.weight = weight; self.dash = dash
        self.labelBackground = labelBackground
    }

    package init(items: [EaselItem]) {
        func uniform<T: Equatable>(_ values: [T?]) -> T? {
            guard let first = values.first, let value = first, values.allSatisfy({ $0 == value }) else { return nil }
            return value
        }
        let styled = items.compactMap { item in EaselStyleFamily.of(item).map { (item, $0) } }
        color = uniform(styled.map { EaselStyle.colorChoice(of: $0.0) })
        let filled = styled.filter { $0.1.takesFill }.map(\.0)
        fill = uniform(filled.map(EaselStyle.fillMode))
        fillOpacity = uniform(filled.map { Optional(EaselStyle.fillOpacity(of: $0)) })
        weight = uniform(styled.filter { !$0.1.weights.isEmpty }.map { $0.1.weight(forWidth: EaselPaintRules.strokeWidth($0.0)) })
        dash = uniform(styled.filter { $0.1.takesDash }.map { Optional($0.0.strokeDash ?? .solid) })
        labelBackground = uniform(styled.filter { $0.1 == .lines }.map { Optional($0.0.labelBackground == true) })
    }
}

package enum EaselStyle {
    package static func applies(_ change: EaselStyleChange, to item: EaselItem) -> Bool {
        guard let family = EaselStyleFamily.of(item) else { return false }
        switch change {
        case .color: return true
        case .fill, .fillOpacity: return family.takesFill
        case .weight(let weight): return family.weights.contains(weight)
        case .dash: return family.takesDash
        case .labelBackground: return family == .lines
        }
    }

    @discardableResult
    package static func apply(_ change: EaselStyleChange, to item: inout EaselItem) -> Bool {
        guard applies(change, to: item), let family = EaselStyleFamily.of(item) else { return false }
        switch change {
        case .color(let choice): recolor(&item, family: family, choice: choice)
        case .fill(let mode): setFill(&item, mode: mode)
        case .fillOpacity(let value): setFillOpacity(&item, value)
        case .weight(let weight):
            guard let width = family.width(weight) else { return false }
            item.strokeWidth = width == EaselPaintRules.defaultStrokeWidth(item.kind, brush: item.brush) ? nil : width
        case .dash(let dash): item.strokeDash = dash == .solid ? nil : dash
        case .labelBackground(let shown): item.labelBackground = shown ? true : nil
        }
        return true
    }

    static func colorChoice(of item: EaselItem) -> EaselColorChoice? {
        guard let family = EaselStyleFamily.of(item) else { return nil }
        switch family {
        case .text:
            let inks = Set(([item.color] + (item.richText?.runs.map(\.attributes.ink) ?? [])).compactMap(EaselPalette.normalized))
            guard inks.count == 1, let ink = inks.first else { return nil }
            return .recognizing(ink, role: .ink)
        case .shapes, .lines, .pen, .tape, .icons, .equations: return .recognizing(item.color, role: .ink)
        case .highlighter: return .recognizing(EaselPaintRules.ink(item).hex, role: .highlight)
        case .stickies: return .recognizing(item.fill ?? EaselPalette.stored(EaselPalette.defaultSticky, role: .sticky), role: .sticky)
        case .sections: return item.fill.flatMap { .recognizing($0, role: .fill) }
        }
    }

    static func fillMode(of item: EaselItem) -> EaselFillMode? {
        guard EaselStyleFamily.of(item)?.takesFill == true else { return nil }
        if fillOpacity(of: item) <= 0 { return EaselFillMode.none }
        return item.fill == nil ? .transparent : .solid
    }

    static func fillOpacity(of item: EaselItem) -> Double {
        if let opacity = item.fillOpacity, opacity.isFinite { return min(1, max(0, opacity)) }
        return item.fill == nil ? EaselPaintRules.washOpacity : 1
    }

    private static func recolor(_ item: inout EaselItem, family: EaselStyleFamily, choice: EaselColorChoice) {
        switch family {
        case .text:
            let ink = choice.hex(role: .ink)
            item.color = ink
            if var rich = item.richText {
                for index in rich.runs.indices {
                    rich.runs[index].attributes.ink = ink + "FF"
                    rich.runs[index].attributes.semanticInk = nil
                }
                item.richText = rich
            }
        case .shapes:
            item.color = choice.hex(role: .ink)
            if item.fill != nil { item.fill = choice.hex(role: .fill) }
        case .stickies:
            item.fill = choice == .palette(.automatic) ? EaselPalette.stored(EaselPalette.defaultSticky, role: .sticky) : choice.hex(role: .sticky)
        case .sections:
            item.fill = choice == .palette(.automatic) ? nil : choice.hex(role: .fill)
            if case .palette(.note(let note)) = choice { item.color = EaselPalette.stored(.note(note), role: .ink) }
            else { item.color = EaselPalette.automaticInk }
        case .lines, .pen, .tape, .icons, .equations:
            item.color = choice.hex(role: .ink)
        case .highlighter:
            item.color = choice.hex(role: .highlight)
        }
    }

    private static func setFill(_ item: inout EaselItem, mode: EaselFillMode) {
        switch mode {
        case .none: item.fillOpacity = 0
        case .solid: ensureFill(&item); item.fillOpacity = nil
        case .transparent: item.fill = nil; item.fillOpacity = nil
        }
    }

    private static func setFillOpacity(_ item: inout EaselItem, _ value: Double) {
        guard value.isFinite else { return }
        let clamped = min(1, max(0, value))
        let natural = item.fill == nil ? EaselPaintRules.washOpacity : 1
        item.fillOpacity = abs(clamped - natural) < 0.0001 ? nil : clamped
    }

    private static func ensureFill(_ item: inout EaselItem) {
        guard item.fill == nil else { return }
        item.fill = (EaselColorChoice.recognizing(item.color, role: .ink) ?? .palette(.automatic)).hex(role: .fill)
    }
}

package struct EaselStyleMemory: Equatable {
    package struct Style: Codable, Equatable {
        var color: String?
        var fill: EaselFillMode?
        var fillOpacity: Double?
        var weight: EaselStrokeWeight?
        var dash: EaselStrokeDash?
        var labelBackground: Bool?
        init(color: String? = nil, fill: EaselFillMode? = nil, fillOpacity: Double? = nil, weight: EaselStrokeWeight? = nil, dash: EaselStrokeDash? = nil, labelBackground: Bool? = nil) {
            self.color = color
            self.fill = fill
            self.fillOpacity = fillOpacity
            self.weight = weight
            self.dash = dash
            self.labelBackground = labelBackground
        }

        var changes: [EaselStyleChange] {
            var result: [EaselStyleChange] = []
            if let choice = color.flatMap(EaselColorChoice.init(storage:)) { result.append(.color(choice)) }
            if let fill { result.append(.fill(fill)) }
            if let fillOpacity, fillOpacity.isFinite { result.append(.fillOpacity(fillOpacity)) }
            if let weight { result.append(.weight(weight)) }
            if let dash { result.append(.dash(dash)) }
            if let labelBackground { result.append(.labelBackground(labelBackground)) }
            return result
        }

        mutating func record(_ change: EaselStyleChange) {
            switch change {
            case .color(let choice): color = choice.storage
            case .fill(let mode): fill = mode; fillOpacity = nil
            case .fillOpacity(let value): fillOpacity = value
            case .weight(let weight): self.weight = weight
            case .dash(let dash): self.dash = dash
            case .labelBackground(let shown): labelBackground = shown
            }
        }
    }

    package static let defaultsKey = "Parc.Easel.Style.Memory"
    package static let rememberedAcrossLaunches: Set<EaselStyleFamily> = [.shapes, .pen, .highlighter, .tape, .text, .sections]

    private(set) var families: [EaselStyleFamily: Style]
    private(set) var sticky: Style
    private(set) var connectors: [UUID: Style] = [:]

    package init(families: [EaselStyleFamily: Style] = [:], sticky: Style) {
        self.families = families.filter { Self.rememberedAcrossLaunches.contains($0.key) }
        self.sticky = sticky
    }

    package static func randomSticky<G: RandomNumberGenerator>(using generator: inout G) -> Style {
        let note = NoteColor.allCases.randomElement(using: &generator) ?? .yellow
        return Style(color: EaselColorChoice.palette(.note(note)).storage)
    }

    func style(for family: EaselStyleFamily, document: UUID?) -> Style {
        switch family {
        case .stickies: return sticky
        case .lines: return document.flatMap { connectors[$0] } ?? Style()
        default: return families[family] ?? Style()
        }
    }

    package mutating func record(_ change: EaselStyleChange, for family: EaselStyleFamily, document: UUID?) {
        switch family {
        case .stickies: sticky.record(change)
        case .lines:
            guard let document else { return }
            connectors[document, default: Style()].record(change)
        default: families[family, default: Style()].record(change)
        }
    }

    package func stamp(_ item: inout EaselItem, document: UUID?) {
        guard let family = EaselStyleFamily.of(item) else { return }
        for change in style(for: family, document: document).changes { EaselStyle.apply(change, to: &item) }
    }

    package var persistentData: Data? {
        var stored: [String: Style] = [:]
        for (family, style) in families where Self.rememberedAcrossLaunches.contains(family) { stored[family.rawValue] = style }
        return try? JSONEncoder().encode(stored)
    }

    package static func persistentFamilies(from data: Data?) -> [EaselStyleFamily: Style] {
        guard let data, let decoded = try? JSONDecoder().decode([String: Style].self, from: data) else { return [:] }
        var result: [EaselStyleFamily: Style] = [:]
        for (key, style) in decoded {
            guard let family = EaselStyleFamily(rawValue: key), rememberedAcrossLaunches.contains(family) else { continue }
            result[family] = style
        }
        return result
    }
}
