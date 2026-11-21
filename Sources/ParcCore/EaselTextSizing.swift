import Foundation

extension EaselTextStyle.Size {
    var title: String {
        switch self {
        case .body: return "Body"
        case .h2: return "Heading 2"
        case .h1: return "Heading 1"
        case .h0: return "Title"
        case .ultra: return "Display"
        }
    }
}

extension EaselTextStyle.Alignment {
    var title: String {
        switch self {
        case .left: return "Align Left"
        case .center: return "Align Center"
        case .right: return "Align Right"
        }
    }

    var shortcut: String {
        switch self {
        case .left: return "⌥⌘L"
        case .center: return "⌥⌘T"
        case .right: return "⌥⌘R"
        }
    }
}

extension EaselRichText.Attributes {
    mutating func scale(by ratio: Double) {
        guard ratio.isFinite, ratio > 0, ratio != 1 else { return }
        func scaled(_ value: Double, limit: Double) -> Double {
            let result = (value * ratio * 100).rounded() / 100
            return result.isFinite ? min(limit, max(-limit, result)) : value
        }
        let limits = EaselTextStyle.customSizes
        let proposed = (font.size * ratio).rounded()
        let size = proposed.isFinite ? min(limits.upperBound, max(limits.lowerBound, proposed)) : font.size
        if size != font.size { font.size = size; font.style = nil }
        kern = scaled(kern, limit: 10_000)
        baseline = scaled(baseline, limit: 10_000)
        guard var p = paragraph else { return }
        p.firstIndent = scaled(p.firstIndent, limit: 100_000)
        p.headIndent = scaled(p.headIndent, limit: 100_000)
        p.tailIndent = scaled(p.tailIndent, limit: 100_000)
        p.lineSpacing = scaled(p.lineSpacing, limit: 100_000)
        p.before = scaled(p.before, limit: 100_000)
        p.after = scaled(p.after, limit: 100_000)
        p.minimumHeight = scaled(p.minimumHeight, limit: 100_000)
        p.maximumHeight = scaled(p.maximumHeight, limit: 100_000)
        p.defaultTab = scaled(p.defaultTab, limit: 100_000)
        p.tabs = p.tabs.map { .init(alignment: $0.alignment, location: scaled($0.location, limit: 100_000)) }
        paragraph = p
    }
}

enum EaselTextSizing {
    static let minimumWidth = 24.0
    static let autoWidthEms = 36.0
    static let autoWidthFloor = 560.0
    static let autoWidthCeiling = 4000.0

    static func isAutoWidth(_ item: EaselItem) -> Bool { item.kind == .text && item.textStyle?.autoWidth == true }

    static func isTextOnly(_ items: [EaselItem]) -> Bool { !items.isEmpty && items.allSatisfy { $0.kind == .text } }

    static func maximumAutoWidth(pointSize: Double) -> Double {
        let size = pointSize.isFinite && pointSize > 0 ? pointSize : EaselTextStyle().pointSize
        return min(autoWidthCeiling, max(autoWidthFloor, (size * autoWidthEms).rounded(.up)))
    }

    static func autoWidth(natural: Double, pointSize: Double) -> Double {
        let limit = maximumAutoWidth(pointSize: pointSize)
        guard natural.isFinite, natural > 0 else { return minimumWidth }
        return min(limit, max(minimumWidth, natural.rounded(.up)))
    }

    static func defaultAlignment(for kind: EaselItemKind) -> EaselTextStyle.Alignment {
        kind == .rectangle || kind == .circle ? .center : .left
    }

    static func resolvedAlignment(_ item: EaselItem) -> EaselTextStyle.Alignment {
        item.textStyle?.alignment ?? defaultAlignment(for: item.kind)
    }

    static func sharedAlignment(_ items: [EaselItem]) -> EaselTextStyle.Alignment? {
        let alignments = items.filter(\.kind.holdsText).map(resolvedAlignment)
        guard let first = alignments.first, alignments.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    static func canAlign(_ items: [EaselItem]) -> Bool { items.contains { $0.kind.holdsText && !$0.isLocked } }

    static func aligning(_ document: EaselDocument, ids: Set<UUID>, to alignment: EaselTextStyle.Alignment) -> EaselDocument? {
        var next = document, changed = false
        for index in next.items.indices where ids.contains(next.items[index].id) {
            let item = next.items[index]
            guard item.kind.holdsText, !item.isLocked, item.textStyle?.alignment != alignment else { continue }
            var style = item.resolvedTextStyle
            style.alignment = alignment
            next.items[index].textStyle = style
            changed = true
        }
        return changed ? next : nil
    }

    static func anchoredX(_ x: Double, width: Double, to newWidth: Double, alignment: EaselTextStyle.Alignment) -> Double {
        let shift: Double
        switch alignment {
        case .left: shift = 0
        case .center: shift = (width - newWidth) / 2
        case .right: shift = width - newWidth
        }
        let result = x + shift
        return result.isFinite ? max(0, result) : x
    }

    static func fittedFrame(_ item: EaselItem, naturalWidth: Double, height measure: (Double) -> Double) -> EaselRect {
        var frame = item.frame
        if isAutoWidth(item) {
            let width = autoWidth(natural: naturalWidth, pointSize: item.resolvedTextStyle.pointSize)
            frame.x = anchoredX(frame.x, width: frame.width, to: width, alignment: resolvedAlignment(item))
            frame.width = width
            frame.height = sanitized(measure(width), fallback: frame.height)
        } else {
            frame.height = max(frame.height, sanitized(measure(frame.width), fallback: frame.height))
        }
        return frame
    }

    static func autoWidthFrame(_ item: EaselItem, naturalWidth: Double, height measure: (Double) -> Double) -> EaselItem? {
        guard item.kind == .text, !item.isLocked, !isAutoWidth(item) else { return nil }
        var next = item
        var style = item.resolvedTextStyle
        style.autoWidth = true
        next.textStyle = style
        next.frame = fittedFrame(next, naturalWidth: naturalWidth, height: measure)
        return next
    }

    static func widthResized(_ item: EaselItem, height measure: (Double) -> Double) -> EaselItem {
        guard item.kind == .text else { return item }
        var next = item
        next.frame.height = sanitized(measure(item.frame.width), fallback: item.frame.height)
        if next.textStyle?.autoWidth != nil { next.textStyle?.autoWidth = nil }
        return next
    }

    static func handleOrder(for items: [EaselItem]) -> [EaselResizeHandle] {
        isTextOnly(items) ? [.left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight] : EaselResizeHandle.allCases
    }

    static func handleRect(_ handle: EaselResizeHandle, in rect: EaselRect, items: [EaselItem], scale: Double = 1) -> EaselRect? {
        guard isTextOnly(items) else { return handle.hitRect(in: rect, scale: scale) }
        guard scale.isFinite, scale > 0 else { return nil }
        switch handle {
        case .top, .bottom: return nil
        case .left, .right:
            let radius = 10 / scale, thickness = 10 / scale, x = handle == .left ? rect.x : rect.x + rect.width
            let span = rect.height - 2 * radius
            if span >= 8 / scale { return EaselRect(x: x - thickness / 2, y: rect.y + radius, width: thickness, height: span) }
            let band = min(max(8 / scale, rect.height / 3), max(rect.height, 8 / scale))
            return EaselRect(x: x - thickness / 2, y: rect.y + (rect.height - band) / 2, width: thickness, height: band)
        default: return handle.hitRect(in: rect, scale: scale)
        }
    }

    static func sideHandlePoints(in rect: EaselRect, items: [EaselItem]) -> [EaselPoint] {
        guard isTextOnly(items) else { return [] }
        return [EaselResizeHandle.left, .right].map { $0.point(in: rect) }
    }

    static func scalesText(_ items: [EaselItem], handle: EaselResizeHandle?) -> Bool {
        handle?.isCorner == true && isTextOnly(items)
    }

    static func setsTextWidth(_ handle: EaselResizeHandle?) -> Bool { handle == .left || handle == .right }

    static func scaledSize(base: Double, factor: Double) -> Double? {
        guard base.isFinite, base > 0, factor.isFinite, factor > 0 else { return nil }
        let limits = EaselTextStyle.customSizes
        return min(limits.upperBound, max(limits.lowerBound, (base * factor).rounded()))
    }

    static func scaled(_ item: EaselItem, factor: Double) -> EaselItem? {
        guard item.kind == .text else { return nil }
        let style = item.resolvedTextStyle
        guard let size = scaledSize(base: style.pointSize, factor: factor) else { return nil }
        let ratio = size / style.pointSize
        var next = item
        var nextStyle = style
        nextStyle.customSize = size == style.presetPointSize ? nil : size
        next.textStyle = item.textStyle == nil && nextStyle == EaselTextStyle() ? nil : nextStyle
        if ratio != 1, var rich = item.richText {
            for index in rich.runs.indices { rich.runs[index].attributes.scale(by: ratio) }
            next.richText = rich
        }
        next.frame.width = max(1, item.frame.width * ratio)
        next.frame.height = max(1, item.frame.height * ratio)
        return next
    }

    static func scaledFrame(_ item: EaselItem, original: EaselRect, proposed: EaselRect, handle: EaselResizeHandle,
                            centered: Bool, single: Bool, naturalWidth: Double, height measure: (Double) -> Double) -> EaselRect {
        let width = isAutoWidth(item) ? autoWidth(natural: naturalWidth, pointSize: item.resolvedTextStyle.pointSize) : item.frame.width
        let height = sanitized(measure(width), fallback: item.frame.height)
        guard single else { return EaselRect(x: max(0, proposed.x), y: max(0, proposed.y), width: width, height: height) }
        let x = centered ? original.x + (original.width - width) / 2 : handle.movesLeft ? original.x + original.width - width : original.x
        let y = centered ? original.y + (original.height - height) / 2 : handle.movesTop ? original.y + original.height - height : original.y
        return EaselRect(x: max(0, x), y: max(0, y), width: width, height: height)
    }

    static func merging(_ changes: [EaselItem], into document: EaselDocument) -> EaselDocument {
        let byID = Dictionary(changes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var next = document
        for index in next.items.indices {
            guard let change = byID[next.items[index].id], next.items[index].kind == .text, change.kind == .text else { continue }
            next.items[index].frame = change.frame
            next.items[index].textStyle = change.textStyle
            next.items[index].richText = change.richText
        }
        return next
    }

    static func sizeLabel(for style: EaselTextStyle) -> String {
        let points = Int(style.pointSize.rounded())
        return style.customSize == nil ? "\(style.size.title) · \(points)" : "\(points) pt"
    }

    static func customSized(_ style: EaselTextStyle, points: Double) -> EaselTextStyle? {
        guard points.isFinite else { return nil }
        let limits = EaselTextStyle.customSizes
        let size = min(limits.upperBound, max(limits.lowerBound, points.rounded()))
        var next = style
        next.customSize = size == style.presetPointSize ? nil : size
        return next
    }

    static func preset(_ style: EaselTextStyle, size: EaselTextStyle.Size) -> EaselTextStyle {
        var next = style
        next.size = size
        next.customSize = nil
        return next
    }

    static func stepped(_ style: EaselTextStyle, by delta: Int) -> EaselTextStyle? {
        guard delta != 0 else { return nil }
        if let custom = style.customSize {
            let presets = EaselTextStyle.Size.allCases.map { ($0, EaselTextStyle(family: style.family, size: $0).presetPointSize) }
            let candidate = delta > 0 ? presets.filter { $0.1 > custom }.min { $0.1 < $1.1 }
                : presets.filter { $0.1 < custom }.max { $0.1 < $1.1 }
            return candidate.map { preset(style, size: $0.0) }
        }
        let shifted = style.size.shifted(by: delta)
        return shifted == style.size ? nil : preset(style, size: shifted)
    }

    static func fits(_ frame: EaselRect, in bounds: EaselRect) -> Bool {
        frame.width <= bounds.width + 0.5 && frame.height <= bounds.height + 0.5
    }

    static func placed(_ frame: EaselRect, in bounds: EaselRect) -> EaselRect {
        EaselRect(x: min(max(frame.x, bounds.x), max(bounds.x, bounds.x + bounds.width - frame.width)),
                  y: min(max(frame.y, bounds.y), max(bounds.y, bounds.y + bounds.height - frame.height)),
                  width: frame.width, height: frame.height)
    }

    private static func sanitized(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value >= 1 ? min(value, 1_000_000) : max(1, min(fallback, 1_000_000))
    }
}
