import Foundation

package struct EaselVectorTextRun: Equatable {
    var x: Double
    var y: Double
    var text: String
    var fontFamily: String
    var fontSize: Double
    var weight: Int = 400
    var italic = false
    package var color: String?
    package var underline = false
    package var strikethrough = false
    package var dimmed = false
    package var link: String?
    package var syntax: String?
    package var mark: EaselVectorMark?
    package init(x: Double, y: Double, text: String, fontFamily: String, fontSize: Double, weight: Int = 400, italic: Bool = false, color: String? = nil, underline: Bool = false, strikethrough: Bool = false, dimmed: Bool = false, link: String? = nil, syntax: String? = nil, mark: EaselVectorMark? = nil) {
        self.x = x
        self.y = y
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.weight = weight
        self.italic = italic
        self.color = color
        self.underline = underline
        self.strikethrough = strikethrough
        self.dimmed = dimmed
        self.link = link
        self.syntax = syntax
        self.mark = mark
    }
}

package struct EaselVectorMark: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: String
    package init(x: Double, y: Double, width: Double, height: Double, color: String) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.color = color
    }
}

package struct EaselVectorInlineImage: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var image: EaselVectorImage
    package init(x: Double, y: Double, width: Double, height: Double, image: EaselVectorImage) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.image = image
    }
}

package struct EaselVectorRule: Equatable {
    var x1: Double
    var x2: Double
    var y: Double
    package init(x1: Double, x2: Double, y: Double) {
        self.x1 = x1
        self.x2 = x2
        self.y = y
    }
}

package struct EaselVectorCheckbox: Equatable {
    var x: Double
    var y: Double
    var size: Double
    var checked: Bool
    package init(x: Double, y: Double, size: Double, checked: Bool) {
        self.x = x
        self.y = y
        self.size = size
        self.checked = checked
    }
}

package struct EaselVectorText: Equatable {
    package var runs: [EaselVectorTextRun] = []
    package var images: [EaselVectorInlineImage] = []
    package var rules: [EaselVectorRule] = []
    package var checkboxes: [EaselVectorCheckbox] = []
    package var fillPath: String?
    var fillColor: String = "#000000"
    package init(runs: [EaselVectorTextRun] = [], images: [EaselVectorInlineImage] = [], rules: [EaselVectorRule] = [], checkboxes: [EaselVectorCheckbox] = [], fillPath: String? = nil, fillColor: String = "#000000") {
        self.runs = runs
        self.images = images
        self.rules = rules
        self.checkboxes = checkboxes
        self.fillPath = fillPath
        self.fillColor = fillColor
    }
}

package struct EaselVectorImage: Equatable {
    var data: Data
    var mimeType: String
    package init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
    var dataURI: String { "data:" + mimeType + ";base64," + data.base64EncodedString() }
}

package struct EaselVectorPalette: Equatable {
    package struct Swatch: Equatable {
        var ink: String
        var card: String
        var cardLine: String
        var muted: String
        var rule = "rgba(31,27,46,.13)"
        var todo = "#2702C2"
        package init(ink: String, card: String, cardLine: String, muted: String, rule: String = "rgba(31,27,46,.13)", todo: String = "#2702C2") {
            self.ink = ink
            self.card = card
            self.cardLine = cardLine
            self.muted = muted
            self.rule = rule
            self.todo = todo
        }
    }
    var light: Swatch
    var dark: Swatch
    var code: EaselCodePalette = .standard
    package init(light: Swatch, dark: Swatch, code: EaselCodePalette = .standard) {
        self.light = light
        self.dark = dark
        self.code = code
    }

    static let standard = EaselVectorPalette(
        light: Swatch(ink: "#1F1B2E", card: "#F6F5F9", cardLine: "rgba(31,27,46,.12)", muted: "rgba(31,27,46,.62)"),
        dark: Swatch(ink: "#EDEBFA", card: "#24212F", cardLine: "rgba(255,255,255,.14)", muted: "rgba(237,235,250,.62)",
                    rule: "rgba(255,255,255,.15)", todo: "#9380E0"))
}

package struct EaselVectorArt {
    package var texts: [UUID: EaselVectorText] = [:]
    package var images: [UUID: EaselVectorImage] = [:]
    package var connectorRoutes: [UUID: EaselConnectorRoute] = [:]
    package var connectorLabels: [UUID: EaselConnectorLabelArt] = [:]
    package var sectionTitles: [UUID: EaselVectorSectionTitle] = [:]
    package var mediaDetails: [UUID: String] = [:]
    package var equations: [UUID: EaselVectorEquation] = [:]
    package init(texts: [UUID: EaselVectorText] = [:], images: [UUID: EaselVectorImage] = [:], connectorRoutes: [UUID: EaselConnectorRoute] = [:], connectorLabels: [UUID: EaselConnectorLabelArt] = [:], sectionTitles: [UUID: EaselVectorSectionTitle] = [:], mediaDetails: [UUID: String] = [:], equations: [UUID: EaselVectorEquation] = [:]) {
        self.texts = texts
        self.images = images
        self.connectorRoutes = connectorRoutes
        self.connectorLabels = connectorLabels
        self.sectionTitles = sectionTitles
        self.mediaDetails = mediaDetails
        self.equations = equations
    }
}

package enum EaselVectorExport {
    static let margin: Double = 40
    static let automaticInk = "#252525"

    package static func contentBounds(_ items: [EaselItem], art: EaselVectorArt = .init(), margin: Double = margin) -> EaselRect {
        let frames = items.map { exportFrame($0, art: art) }.filter { [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) }
        guard let first = frames.first else { return EaselRect(x: 0, y: 0, width: 2 * margin + 320, height: 2 * margin + 200) }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width); maxY = max(maxY, frame.y + frame.height)
        }
        let stroke = strokeAllowance
        return EaselRect(x: minX - margin - stroke, y: minY - margin - stroke,
                         width: max(1, maxX - minX) + 2 * (margin + stroke), height: max(1, maxY - minY) + 2 * (margin + stroke))
    }

    static func isAutomatic(_ hex: String) -> Bool {
        let value = hex.uppercased()
        return value == automaticInk || value == automaticInk + "FF"
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default:
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" { continue }
                if (0xFFFE...0xFFFF).contains(scalar.value) { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    package static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int(rounded)) }
        return String(rounded)
    }

    static func safeLink(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url.absoluteString
    }

    static func color(_ hex: String) -> String? {
        let body = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard [6, 8].contains(body.count), body.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + body.prefix(6).uppercased()
    }

    static func paint(_ hex: String) -> String { paint(hex, role: .ink) }

    static func svg(_ items: [EaselItem], art: EaselVectorArt, title: String) -> String {
        let shown = EaselBoardObjects.displayed(items)
        let bounds = contentBounds(shown, art: art)
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" class=\"easel-svg\""
        svg += " role=\"img\" aria-label=\"" + escape(title) + "\""
        svg += " width=\"" + number(bounds.width) + "\" height=\"" + number(bounds.height) + "\""
        svg += " viewBox=\"" + [bounds.x, bounds.y, bounds.width, bounds.height].map(number).joined(separator: " ") + "\">"
        svg += drawingStyles(shown)
        for item in shown {
            svg += objectLinked(item, element(item, art: art))
        }
        return svg + "</svg>"
    }

    static func element(_ item: EaselItem, art: EaselVectorArt) -> String {
        guard !item.isEmptyPlaceholder else { return "" }
        let credit = item.kind == .image && art.images[item.id] != nil ? creditElement(item) : ""
        return transformed(item, kindElement(item, art: art)) + credit
    }

    static func transformed(_ item: EaselItem, _ body: String) -> String {
        guard !body.isEmpty, EaselRotation.isTransformed(item) else { return body }
        let middle = EaselRotation.center(of: item.frame), angle = EaselRotation.degrees(of: item)
        var steps: [String] = []
        if angle != 0 { steps.append("rotate(" + [angle, middle.x, middle.y].map(number).joined(separator: " ") + ")") }
        let mirrorX = EaselRotation.mirrorsHorizontally(item), mirrorY = EaselRotation.mirrorsVertically(item)
        if mirrorX || mirrorY {
            steps.append("translate(" + number(middle.x) + " " + number(middle.y) + ") scale(" + (mirrorX ? "-1" : "1") + " "
                + (mirrorY ? "-1" : "1") + ") translate(" + number(-middle.x) + " " + number(-middle.y) + ")")
        }
        return "<g transform=\"" + steps.joined(separator: " ") + "\">" + body + "</g>"
    }

    static func matrix(_ transform: EaselTransform) -> String {
        "matrix(" + [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].map(number).joined(separator: " ") + ")"
    }

    static func kindElement(_ item: EaselItem, art: EaselVectorArt) -> String {
        switch item.kind {
        case .text: return text(item, art.texts[item.id])
        case .rectangle, .circle: return shape(item) + text(item, art.texts[item.id])
        case .arrow: return connector(item, art: art)
        case .freehand: return drawing(item)
        case .image: return art.images[item.id].map { framedImage(item, $0) } ?? ""
        case .webCard, .browser:
            if let picture = art.images[item.id] { return linked(image(item, picture, corner: 8), item.url) }
            return card(item)
        case .link: return bookmark(item)
        case .sticky, .section: return board(item, art.texts[item.id], title: art.sectionTitles[item.id])
        case .table: return table(item, art.texts[item.id])
        case .code: return codeBlock(item, art.texts[item.id])
        case .stamp: return stamp(item, art.images[item.id])
        case .video: return art.images[item.id].map { poster(item, $0) } ?? linkedVideoElement(item)
        case .audio, .file, .pdf: return mediaElement(item, art: art)
        case .equation: return equation(item, art.equations[item.id])
        }
    }

    static func board(_ item: EaselItem, _ layout: EaselVectorText?, title: EaselVectorSectionTitle? = nil) -> String {
        item.kind == .section ? section(item, title: title) : sticky(item, layout)
    }

    static func objectLinked(_ item: EaselItem, _ body: String) -> String {
        EaselObjectLink.canLink(item) && !body.isEmpty ? linked(body, item.url) : body
    }

    static func linked(_ body: String, _ raw: String?) -> String {
        guard let link = safeLink(raw) else { return body }
        return "<a href=\"" + escape(link) + "\" target=\"_blank\" rel=\"noopener\">" + body + "</a>"
    }

    static func shape(_ item: EaselItem) -> String {
        if let kind = item.resolvedShape, !EaselShapeGeometry.usesOriginalLook(item) { return styledShape(item, kind) }
        let f = item.frame
        let style = " style=\"" + fillStyle(item) + ";" + strokeStyle(item) + "\""
        if item.kind == .circle {
            return "<ellipse cx=\"" + number(f.x + f.width / 2) + "\" cy=\"" + number(f.y + f.height / 2) + "\" rx=\""
                + number(f.width / 2) + "\" ry=\"" + number(f.height / 2) + "\"" + style + "/>"
        }
        return "<rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\""
            + number(f.height) + "\" rx=\"5\" ry=\"5\"" + style + "/>"
    }

    static func styledShape(_ item: EaselItem, _ kind: EaselShape) -> String {
        var result = "<path d=\"" + EaselShapeGeometry.outline(kind, in: item.frame).svgPathData + "\" style=\"" + fillStyle(item) + ";" + strokeStyle(item) + "\"/>"
        let details = EaselShapeGeometry.details(kind, in: item.frame)
        if EaselPaintRules.strokeWidth(item) > 0, !details.isEmpty {
            result += "<path d=\"" + details.svgPathData + "\" style=\"fill:none;" + strokeStyle(item, rounded: true) + "\"/>"
        }
        return result
    }

    static func strokePath(_ item: EaselItem) -> String? {
        guard let first = item.points.first else { return nil }
        let f = item.frame
        var path = "M" + number(f.x + first.x) + " " + number(f.y + first.y)
        for point in item.points.dropFirst() { path += "L" + number(f.x + point.x) + " " + number(f.y + point.y) }
        if item.points.count == 1 { path += "L" + number(f.x + first.x) + " " + number(f.y + first.y) }
        return path
    }

    static func arrowHead(_ item: EaselItem) -> String? {
        guard item.kind == .arrow, item.points.count >= 2, let last = item.points.last else { return nil }
        let previous = item.points[item.points.count - 2], angle = atan2(last.y - previous.y, last.x - previous.x)
        let end = (x: item.frame.x + last.x, y: item.frame.y + last.y)
        let length = EaselPaintRules.arrowHeadLength(width: EaselPaintRules.strokeWidth(item))
        return "M" + number(end.x - cos(angle - 0.5) * length) + " " + number(end.y - sin(angle - 0.5) * length)
            + "L" + number(end.x) + " " + number(end.y)
            + "L" + number(end.x - cos(angle + 0.5) * length) + " " + number(end.y - sin(angle + 0.5) * length)
    }

    static func stroke(_ item: EaselItem) -> String {
        guard let path = strokePath(item) else { return "" }
        var result = "<path d=\"" + path + "\" style=\"fill:none;" + strokeStyle(item, rounded: true) + "\"/>"
        if let head = arrowHead(item) { result += "<path d=\"" + head + "\" style=\"fill:none;" + strokeStyle(item, dashed: false, rounded: true) + "\"/>" }
        return result
    }

    static func image(_ item: EaselItem, _ picture: EaselVectorImage, corner: Double) -> String {
        let f = item.frame
        let geometry = "x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\"" + number(f.height) + "\""
        var result = ""
        var clip = ""
        if corner > 0 {
            let id = "clip-" + item.id.uuidString.lowercased()
            result += "<clipPath id=\"" + id + "\"><rect " + geometry + " rx=\"" + number(corner) + "\"/></clipPath>"
            clip = " clip-path=\"url(#" + id + ")\""
        }
        let label = item.text.isEmpty ? "" : " aria-label=\"" + escape(item.text) + "\""
        result += "<image " + geometry + " preserveAspectRatio=\"none\"" + clip + label + " href=\"" + picture.dataURI + "\"/>"
        return result
    }

    static func framedImage(_ item: EaselItem, _ picture: EaselVectorImage) -> String {
        let f = item.frame
        let frame = CGRect(x: f.x, y: f.y, width: f.width, height: f.height)
        let alt = item.altText.flatMap { $0.isEmpty ? nil : escape($0) }
        let label = alt.map { " role=\"img\" aria-label=\"" + $0 + "\"" } ?? ""
        let title = alt.map { "<title>" + $0 + "</title>" } ?? ""
        func element(_ rect: CGRect, _ extra: String) -> String {
            "<image x=\"" + number(Double(rect.minX)) + "\" y=\"" + number(Double(rect.minY)) + "\" width=\"" + number(Double(rect.width))
                + "\" height=\"" + number(Double(rect.height)) + "\" preserveAspectRatio=\"none\"" + extra + " href=\"" + picture.dataURI + "\""
        }
        guard EaselImageFraming.isFramed(item) else {
            return title.isEmpty ? element(frame, label) + "/>" : element(frame, label) + ">" + title + "</image>"
        }
        let turns = item.resolvedQuarterTurns
        let full = EaselImageFraming.pictureRect(frame: frame, crop: item.crop, turns: turns)
        let source = EaselImageFraming.sourceRect(picture: full, turns: turns)
        let id = "frame-" + item.id.uuidString.lowercased()
        let shape = item.mask.map { "<path d=\"" + NoteImageMask.svgData($0.path(in: frame)) + "\"/>" }
            ?? "<rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\"" + number(f.height) + "\"/>"
        let rotate = turns == 0 ? "" : " transform=\"rotate(" + number(Double(turns) * 90) + " " + number(Double(full.midX)) + " "
            + number(Double(full.midY)) + ")\""
        return "<clipPath id=\"" + id + "\">" + shape + "</clipPath><g clip-path=\"url(#" + id + ")\"" + label + ">" + title
            + element(source, rotate) + "/></g>"
    }

    static func poster(_ item: EaselItem, _ picture: EaselVectorImage) -> String {
        let alt = item.altText.flatMap { $0.isEmpty ? nil : escape($0) }
        var labelled = item
        labelled.text = ""
        let body = image(labelled, picture, corner: min(8, item.frame.width / 4, item.frame.height / 4))
        guard let alt else { return "<g>" + body + "</g>" }
        return "<g role=\"img\" aria-label=\"" + alt + "\"><title>" + alt + "</title>" + body + "</g>"
    }

    static func card(_ item: EaselItem) -> String {
        let f = item.frame
        let title = item.text.isEmpty ? (item.url ?? "Link") : item.text
        var result = "<g class=\"easel-card\"><rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width)
            + "\" height=\"" + number(f.height) + "\" rx=\"10\" ry=\"10\" style=\"fill:var(--easel-card);stroke:var(--easel-card-line);stroke-width:1\"/>"
        let clip = "card-" + item.id.uuidString.lowercased()
        result += "<clipPath id=\"" + clip + "\"><rect x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + 8) + "\" width=\""
            + number(max(0, f.width - 32)) + "\" height=\"" + number(max(0, f.height - 16)) + "\"/></clipPath>"
        result += "<g clip-path=\"url(#" + clip + ")\">"
        result += "<text x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + 16 + 17) + "\" style=\"font-family:var(--font);font-size:17px;font-weight:700;fill:"
            + paint(item.color) + "\">" + escape(title) + "</text>"
        if let url = item.url, !url.isEmpty {
            result += "<text x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + f.height - 36 + 12) + "\" style=\"font-family:var(--font);font-size:12px;fill:var(--easel-muted)\">"
                + escape(url) + "</text>"
        }
        return linked(result + "</g></g>", item.url)
    }

    static func bookmark(_ item: EaselItem) -> String {
        guard let url = item.url, !url.isEmpty else { return "" }
        let f = item.frame
        let clip = "bookmark-" + item.id.uuidString.lowercased()
        var result = "<g class=\"easel-bookmark\"><rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width)
            + "\" height=\"" + number(f.height) + "\" rx=\"10\" ry=\"10\" style=\"fill:var(--easel-card);stroke:var(--easel-card-line);stroke-width:1\"/>"
        result += "<clipPath id=\"" + clip + "\"><rect x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + 8) + "\" width=\""
            + number(max(0, f.width - 32)) + "\" height=\"" + number(max(0, f.height - 16)) + "\"/></clipPath><g clip-path=\"url(#" + clip + ")\">"
        result += "<text x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + 31) + "\" style=\"font-family:var(--font);font-size:14.5px;font-weight:700;fill:"
            + paint(item.color) + "\">" + escape(EaselBookmarkCard.title(of: item)) + "</text>"
        if let summary = EaselBookmarkCard.summary(of: item) {
            let perLine = max(8, Int((f.width - 32) / 6.6))
            for (index, line) in wrap(summary, perLine: perLine, lines: 2).enumerated() {
                result += "<text x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + 52 + Double(index) * 18) + "\" style=\"font-family:var(--font);font-size:13px;fill:var(--easel-muted)\">"
                    + escape(line) + "</text>"
            }
        }
        result += "<text x=\"" + number(f.x + 16) + "\" y=\"" + number(f.y + f.height - 18) + "\" style=\"font-family:var(--font);font-size:12.5px;fill:var(--easel-muted)\">"
            + escape(EaselBookmarkCard.siteLine(of: item)) + "</text>"
        return linked(result + "</g></g>", url)
    }

    static func wrap(_ text: String, perLine: Int, lines: Int) -> [String] {
        guard perLine > 1, lines > 0 else { return [] }
        var result: [String] = [], current = "", truncated = false
        for word in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if candidate.count <= perLine { current = candidate; continue }
            if !current.isEmpty { result.append(current) }
            if result.count == lines { truncated = true; current = ""; break }
            current = String(word.prefix(perLine))
        }
        if !current.isEmpty {
            if result.count < lines { result.append(current) } else { truncated = true }
        }
        if truncated, let last = result.last { result[result.count - 1] = String(last.prefix(perLine - 1)) + "…" }
        return result
    }

    static func text(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        guard let layout, !layout.runs.isEmpty || !layout.images.isEmpty || !layout.rules.isEmpty || !layout.checkboxes.isEmpty
                || layout.fillPath != nil else { return "" }
        var result = "<g transform=\"translate(" + number(item.frame.x) + " " + number(item.frame.y) + ")\">"
        if let fill = layout.fillPath, !fill.isEmpty {
            result += "<path d=\"" + escape(fill) + "\" style=\"fill:" + (color(layout.fillColor) ?? "#000000") + "\"/>"
        }
        for run in layout.runs where !run.text.isEmpty { result += textRun(run) }
        for placed in layout.images { result += inlineImage(placed) }
        for rule in layout.rules { result += ruleLine(rule) }
        for box in layout.checkboxes { result += checkbox(box) }
        return result + "</g>"
    }

    static func ruleLine(_ rule: EaselVectorRule) -> String {
        "<line x1=\"" + number(rule.x1) + "\" y1=\"" + number(rule.y) + "\" x2=\"" + number(rule.x2) + "\" y2=\"" + number(rule.y)
            + "\" style=\"stroke:var(--easel-rule,rgba(128,128,128,.3));stroke-width:1\"/>"
    }

    static func checkbox(_ box: EaselVectorCheckbox) -> String {
        let radius = box.size / 2
        let open = "<circle cx=\"" + number(box.x + radius) + "\" cy=\"" + number(box.y + radius) + "\" r=\""
        guard box.checked else {
            return open + number(radius - 0.75) + "\" style=\"fill:none;stroke:var(--easel-muted);stroke-width:1.5\"/>"
        }
        let points = [(0.27, 0.52), (0.44, 0.68), (0.74, 0.34)].map { number(box.x + box.size * $0.0) + " " + number(box.y + box.size * $0.1) }
        return open + number(radius) + "\" style=\"fill:var(--easel-todo,#2702C2)\"/><path d=\"M" + points[0] + "L" + points[1] + "L" + points[2]
            + "\" style=\"fill:none;stroke:#FFFFFF;stroke-width:" + number(box.size * 0.11) + ";stroke-linecap:round;stroke-linejoin:round\"/>"
    }

    static func inlineImage(_ placed: EaselVectorInlineImage) -> String {
        "<image x=\"" + number(placed.x) + "\" y=\"" + number(placed.y) + "\" width=\"" + number(placed.width) + "\" height=\""
            + number(placed.height) + "\" preserveAspectRatio=\"xMidYMid meet\" href=\"" + escape(placed.image.dataURI) + "\"/>"
    }

    static func textRun(_ run: EaselVectorTextRun) -> String {
        var style = "font-family:" + run.fontFamily + ";font-size:" + number(run.fontSize) + "px"
        if run.weight != 400 { style += ";font-weight:" + String(run.weight) }
        if run.italic { style += ";font-style:italic" }
        style += ";fill:" + (run.color.map(paint) ?? "var(--easel-ink)")
        if run.dimmed { style += ";fill-opacity:.45" }
        let decorations = [run.underline ? "underline" : nil, run.strikethrough ? "line-through" : nil].compactMap { $0 }
        if !decorations.isEmpty { style += ";text-decoration:" + decorations.joined(separator: " ") }
        let body = markRect(run.mark) + "<text x=\"" + number(run.x) + "\" y=\"" + number(run.y) + "\" xml:space=\"preserve\" style=\"" + escape(style) + "\">"
            + escape(run.text) + "</text>"
        return linked(body, run.link)
    }

    static func markRect(_ mark: EaselVectorMark?) -> String {
        guard let mark, mark.width > 0, mark.height > 0, mark.color.range(of: "^#[0-9A-Fa-f]{8}$", options: .regularExpression) != nil else { return "" }
        let value = mark.color.uppercased()
        let fill = EaselPalette.markVariable(for: value).map { "var(" + $0 + "," + value + ")" } ?? value
        return "<rect x=\"" + number(mark.x) + "\" y=\"" + number(mark.y) + "\" width=\"" + number(mark.width) + "\" height=\""
            + number(mark.height) + "\" rx=\"3\" ry=\"3\" style=\"fill:" + fill + "\"/>"
    }

    static func css(_ palette: EaselVectorPalette) -> String {
        func variables(_ swatch: EaselVectorPalette.Swatch) -> String {
            "--easel-ink:" + swatch.ink + ";--easel-card:" + swatch.card + ";--easel-card-line:" + swatch.cardLine + ";--easel-muted:" + swatch.muted
                + ";--easel-rule:" + swatch.rule + ";--easel-todo:" + swatch.todo + ";"
        }
        return ":root{" + variables(palette.light) + EaselPalette.cssDeclarations(dark: false) + "}\n"
            + "@media screen and (prefers-color-scheme:dark){:root{" + variables(palette.dark) + EaselPalette.cssDeclarations(dark: true) + "}}\n"
            + ".easel-canvas{margin:0;overflow-x:auto;line-height:0}\n"
            + ".easel-svg{display:block;max-width:100%;height:auto;margin:0 auto}\n"
            + ".easel-svg a{cursor:pointer}\n" + codeCSS(palette.code)
    }

    package static func htmlDocument(_ document: EaselDocument, art: EaselVectorArt, palette: EaselVectorPalette = .standard) -> String {
        let trimmed = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled Easel" : trimmed
        var html = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        html += "<meta name=\"generator\" content=\"Parc\">\n"
        html += "<title>" + escape(name) + "</title>\n<style>\n" + NotePageHTMLStyle.css + css(palette) + "</style>\n</head>\n"
        html += "<body class=\"page-font-standard full-width easel-export\">\n<article class=\"page\">\n<header class=\"page-header\">\n"
        html += "<h1 class=\"page-title\">" + escape(name) + "</h1>\n</header>\n<main class=\"page-body\">\n"
        let pages = EaselPages.exportedPages(document)
        if pages.isEmpty {
            html += "<figure class=\"easel-canvas\">" + svg(document.items, art: art, title: name) + "</figure>\n"
        } else {
            for page in pages {
                html += "<section class=\"easel-page\">\n<h2>" + escape(page.name) + "</h2>\n<figure class=\"easel-canvas\">"
                html += svg(page.items, art: art, title: page.name) + "</figure>\n</section>\n"
            }
        }
        html += "</main>\n</article>\n</body>\n</html>\n"
        return html
    }

    package static func imageMimeType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        return nil
    }

    package static func exportFileName(_ title: String, fileExtension: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed.isEmpty ? "Untitled Easel" : trimmed)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return base + "." + fileExtension
    }
}
