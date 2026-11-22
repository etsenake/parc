import Foundation

final class EaselExportKeys: @unchecked Sendable {
    static let shared = EaselExportKeys()
    private let lock = NSLock()
    private var last = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        last += 1
        return last
    }
}

extension EaselVectorExport {
    static let highlightBlend = "mix-blend-mode:var(--easel-highlight-blend,multiply)"
    static let highlightCSS = "@media screen and (prefers-color-scheme:dark){.easel-highlight{--easel-highlight-blend:normal}}"

    static func drawingStyles(_ items: [EaselItem]) -> String {
        items.contains(where: EaselPaintRules.isHighlighter) ? "<style>" + highlightCSS + "</style>" : ""
    }

    package static func drawing(_ item: EaselItem) -> String {
        switch item.resolvedBrush {
        case .marker, .highlighter: return brushStroke(item)
        case .washi: return tape(item)
        }
    }

    static func drawingPath(_ item: EaselItem) -> String? {
        let f = item.frame
        func point(_ p: EaselPoint) -> String { number(f.x + p.x) + " " + number(f.y + p.y) }
        let path = EaselDrawing.pathElements(item).map { element -> String in
            switch element {
            case .move(let p): return "M" + point(p)
            case .line(let p): return "L" + point(p)
            case .quad(let p, let control): return "Q" + point(control) + " " + point(p)
            }
        }.joined()
        return path.isEmpty ? nil : path
    }

    static func brushStroke(_ item: EaselItem) -> String {
        guard let path = drawingPath(item) else { return "" }
        let highlight = item.resolvedBrush == .highlighter
        return "<path" + (highlight ? " class=\"easel-highlight\"" : "") + " d=\"" + path + "\" style=\"fill:none;"
            + strokeStyle(item, dashed: !highlight, rounded: true) + (highlight ? ";" + highlightBlend : "") + "\"/>"
    }

    static func tape(_ item: EaselItem) -> String {
        guard let placement = EaselWashi.placement(item) else { return "" }
        let tile = EaselWashi.tile(EaselWashi.pattern(item), color: item.color)
        let key = String(EaselExportKeys.shared.next()) + "-" + item.id.uuidString.lowercased(), half = EaselWashi.width / 2
        let outline = EaselWashi.outline(length: placement.length, seed: EaselWashi.seed(item.id))
            .map { number($0.x) + "," + number($0.y) }.joined(separator: " ")
        let edge = EaselWashi.tooth * 2, span = number(placement.length + 2 * edge)
        var result = "<g transform=\"translate(" + number(placement.origin.x) + " " + number(placement.origin.y) + ") rotate("
            + number(placement.angle * 180 / Double.pi) + ")\" opacity=\"" + number(EaselWashi.opacity)
            + "\" style=\"filter:drop-shadow(0 0 1px rgba(0,0,0,.16))\">"
        result += "<pattern id=\"washi-" + key + "\" patternUnits=\"userSpaceOnUse\" x=\"0\" y=\"" + number(-half)
            + "\" width=\"" + number(tile.width) + "\" height=\"" + number(tile.height) + "\">"
        result += "<rect width=\"" + number(tile.width) + "\" height=\"" + number(tile.height) + "\" style=\"fill:" + (color(tile.base) ?? "#FFFFFF") + "\"/>"
        result += tile.marks.map(washiMark).joined() + "</pattern>"
        result += "<clipPath id=\"washi-edge-" + key + "\"><polygon points=\"" + outline + "\"/></clipPath>"
        result += "<polygon points=\"" + outline + "\" style=\"fill:url(#washi-" + key + ")\"/>"
        result += "<g clip-path=\"url(#washi-edge-" + key + ")\">"
        result += "<rect x=\"" + number(-edge) + "\" y=\"" + number(-half) + "\" width=\"" + span + "\" height=\"1\" style=\"fill:#FFFFFF;fill-opacity:.3\"/>"
        result += "<rect x=\"" + number(-edge) + "\" y=\"" + number(half - 1) + "\" width=\"" + span + "\" height=\"1\" style=\"fill:"
            + automaticInk + ";fill-opacity:.08\"/>"
        return result + "</g></g>"
    }

    static func washiMark(_ mark: EaselWashiMark) -> String {
        let style = " style=\"fill:" + (color(mark.color) ?? "#FFFFFF") + ";fill-opacity:" + number(mark.opacity) + "\"/>"
        switch mark.shape {
        case .rect(let r):
            return "<rect x=\"" + number(r.x) + "\" y=\"" + number(r.y) + "\" width=\"" + number(r.width) + "\" height=\"" + number(r.height) + "\"" + style
        case .circle(let center, let radius):
            return "<circle cx=\"" + number(center.x) + "\" cy=\"" + number(center.y) + "\" r=\"" + number(radius) + "\"" + style
        case .polygon(let points):
            return "<polygon points=\"" + points.map { number($0.x) + "," + number($0.y) }.joined(separator: " ") + "\"" + style
        }
    }
}
