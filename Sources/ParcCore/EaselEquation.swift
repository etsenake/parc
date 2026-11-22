import Foundation

package struct EaselEquationSize: Equatable {
    package var width: Double
    package var height: Double
    package init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var isUsable: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 }
}

package enum EaselEquation {
    package static let fontSize = 30.0
    package static let padding = 14.0
    package static let emptySize = EaselEquationSize(width: 360, height: 72)
    static let minimumScale = 0.2
    static let maximumScale = 16.0
    package static let maximumLength = 20_000

    package static func isBlank(_ tex: String) -> Bool {
        tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package static func clamped(_ tex: String) -> String {
        tex.count <= maximumLength ? tex : String(tex.prefix(maximumLength))
    }

    package static func natural(typeset: EaselEquationSize?) -> EaselEquationSize {
        guard let typeset, typeset.isUsable else { return emptySize }
        return EaselEquationSize(width: typeset.width + 2 * padding, height: typeset.height + 2 * padding)
    }

    package static func scale(of frame: EaselRect, natural: EaselEquationSize) -> Double {
        guard natural.isUsable, frame.width.isFinite, frame.width > 0 else { return 1 }
        return min(max(frame.width / natural.width, minimumScale), maximumScale)
    }

    package static func frame(natural: EaselEquationSize, scale: Double, centeredOn centre: EaselPoint) -> EaselRect {
        let factor = min(max(scale.isFinite ? scale : 1, minimumScale), maximumScale)
        let width = natural.width * factor, height = natural.height * factor
        return EaselRect(x: max(0, centre.x - width / 2), y: max(0, centre.y - height / 2), width: width, height: height)
    }

    package static func refitted(_ frame: EaselRect, from old: EaselEquationSize, to new: EaselEquationSize) -> EaselRect {
        let centre = EaselPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        return Self.frame(natural: new, scale: scale(of: frame, natural: old), centeredOn: centre)
    }

    package static func inner(_ frame: EaselRect, natural: EaselEquationSize) -> EaselRect {
        let factor = scale(of: frame, natural: natural)
        let inset = padding * factor
        return EaselRect(x: frame.x + inset, y: frame.y + inset,
                         width: max(0, frame.width - 2 * inset), height: max(0, frame.height - 2 * inset))
    }

    package static func placed(natural: EaselEquationSize, visible: EaselRect, occupied: [EaselRect]) -> EaselRect {
        let centre = EaselPoint(x: visible.x + visible.width / 2, y: visible.y + visible.height / 2)
        var frame = Self.frame(natural: natural, scale: 1, centeredOn: centre)
        let step = 24.0
        var attempts = 0
        while attempts < 12, occupied.contains(where: { $0.x == frame.x && $0.y == frame.y }) {
            frame.x += step
            frame.y += step
            attempts += 1
        }
        return frame
    }
}

package struct EaselVectorEquationPart: Equatable {
    package var path: String
    package var color: String? = nil
    package var opacity: Double? = nil
    package init(path: String, color: String? = nil, opacity: Double? = nil) {
        self.path = path
        self.color = color
        self.opacity = opacity
    }
}

package struct EaselVectorEquation: Equatable {
    package var width: Double
    package var height: Double
    package var parts: [EaselVectorEquationPart]
    package var error: String? = nil
    package init(width: Double, height: Double, parts: [EaselVectorEquationPart], error: String? = nil) {
        self.width = width
        self.height = height
        self.parts = parts
        self.error = error
    }
}

extension EaselVectorExport {
    package static func equation(_ item: EaselItem, _ art: EaselVectorEquation?) -> String {
        guard !EaselEquation.isBlank(item.text) else { return "" }
        let f = item.frame
        let label = " role=\"img\" aria-label=\"" + escape(NoteEquationSpeech.label(source: item.text, error: art?.error)) + "\""
        guard let art, art.error == nil, art.width > 0, art.height > 0, !art.parts.isEmpty else {
            let size = max(8, min(f.height * 0.4, 18))
            return "<g" + label + "><text x=\"" + number(f.x + f.width / 2) + "\" y=\"" + number(f.y + f.height / 2 + size * 0.35)
                + "\" text-anchor=\"middle\" xml:space=\"preserve\" style=\"font-family:ui-monospace,Menlo,monospace;font-size:" + number(size)
                + "px;fill:var(--easel-muted)\">" + escape(item.text.split(whereSeparator: \.isNewline).joined(separator: " ")) + "</text></g>"
        }
        let natural = EaselEquation.natural(typeset: EaselEquationSize(width: art.width, height: art.height))
        let inner = EaselEquation.inner(f, natural: natural)
        let factor = art.width > 0 ? inner.width / art.width : 1
        var result = "<g" + label + " transform=\"translate(" + number(inner.x) + " " + number(inner.y) + ") scale(" + number6(factor) + ")\">"
        let ink = paint(item.color)
        for part in art.parts where !part.path.isEmpty {
            var style = "fill:" + (part.color.flatMap(color) ?? ink)
            if let opacity = part.opacity, opacity < 1 { style += ";fill-opacity:" + number6(opacity) }
            result += "<path d=\"" + escape(part.path) + "\" style=\"" + style + "\"/>"
        }
        return result + "</g>"
    }

    private static func number6(_ value: Double) -> String {
        guard value.isFinite else { return "1" }
        let rounded = (value * 10_000).rounded() / 10_000
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
        return String(rounded)
    }
}
