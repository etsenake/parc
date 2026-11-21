import Foundation

struct EaselVectorTextRun: Equatable {
    var x: Double
    var y: Double
    var text: String
    var fontFamily: String
    var fontSize: Double
    var weight: Int = 400
    var italic = false
    var color: String?
    var underline = false
    var strikethrough = false
    var link: String?
    var syntax: String?
}

struct EaselVectorText: Equatable {
    var runs: [EaselVectorTextRun] = []
    var fillPath: String?
    var fillColor: String = "#000000"
}

struct EaselVectorImage: Equatable {
    var data: Data
    var mimeType: String
    var dataURI: String { "data:" + mimeType + ";base64," + data.base64EncodedString() }
}

struct EaselVectorPalette: Equatable {
    struct Swatch: Equatable {
        var ink: String
        var card: String
        var cardLine: String
        var muted: String
    }
    var light: Swatch
    var dark: Swatch
    var code: EaselCodePalette = .standard

    static let standard = EaselVectorPalette(
        light: Swatch(ink: "#1F1B2E", card: "#F6F5F9", cardLine: "rgba(31,27,46,.12)", muted: "rgba(31,27,46,.62)"),
        dark: Swatch(ink: "#EDEBFA", card: "#24212F", cardLine: "rgba(255,255,255,.14)", muted: "rgba(237,235,250,.62)"))
}

struct EaselVectorArt {
    var texts: [UUID: EaselVectorText] = [:]
    var images: [UUID: EaselVectorImage] = [:]
}

enum EaselVectorExport {
    static let margin: Double = 40
    static let automaticInk = "#252525"

    static func contentBounds(_ items: [EaselItem], margin: Double = margin) -> EaselRect {
        let frames = items.map(\.frame).filter { [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) }
        guard let first = frames.first else { return EaselRect(x: 0, y: 0, width: 2 * margin + 320, height: 2 * margin + 200) }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width); maxY = max(maxY, frame.y + frame.height)
        }
        let stroke = 4.0
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

    static func number(_ value: Double) -> String {
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

    static func paint(_ hex: String) -> String {
        isAutomatic(hex) ? "var(--easel-ink)" : (color(hex) ?? "var(--easel-ink)")
    }

    static func svg(_ items: [EaselItem], art: EaselVectorArt, title: String) -> String {
        let bounds = contentBounds(items)
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" class=\"easel-svg\""
        svg += " role=\"img\" aria-label=\"" + escape(title) + "\""
        svg += " width=\"" + number(bounds.width) + "\" height=\"" + number(bounds.height) + "\""
        svg += " viewBox=\"" + [bounds.x, bounds.y, bounds.width, bounds.height].map(number).joined(separator: " ") + "\">"
        for item in items.sorted(by: { $0.zIndex < $1.zIndex }) {
            svg += element(item, art: art)
        }
        return svg + "</svg>"
    }

    static func element(_ item: EaselItem, art: EaselVectorArt) -> String {
        switch item.kind {
        case .text: return text(item, art.texts[item.id])
        case .rectangle, .circle: return shape(item)
        case .arrow: return stroke(item)
        case .freehand: return drawing(item)
        case .image: return art.images[item.id].map { framedImage(item, $0) } ?? ""
        case .webCard, .browser:
            if let picture = art.images[item.id] { return linked(image(item, picture, corner: 8), item.url) }
            return card(item)
        case .link: return card(item)
        case .sticky, .section: return board(item, art.texts[item.id])
        case .table: return table(item, art.texts[item.id])
        case .code: return codeBlock(item, art.texts[item.id])
        }
    }

    static func board(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        let f = item.frame, radius = item.kind == .sticky ? 4.0 : 12.0
        let fill = item.fill.map(paint) ?? paint(automaticInk)
        let opacity = item.fill == nil ? 0.09 : (item.fillOpacity ?? 1)
        let paper = "<rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\""
            + number(f.height) + "\" rx=\"" + number(radius) + "\" ry=\"" + number(radius) + "\" style=\"fill:" + fill
            + ";fill-opacity:" + number(opacity) + "\"/>"
        return "<g>" + paper + text(item, layout) + "</g>"
    }

    static func linked(_ body: String, _ raw: String?) -> String {
        guard let link = safeLink(raw) else { return body }
        return "<a href=\"" + escape(link) + "\" target=\"_blank\" rel=\"noopener\">" + body + "</a>"
    }

    static func shape(_ item: EaselItem) -> String {
        let f = item.frame, ink = paint(item.color)
        let style = " style=\"fill:" + ink + ";fill-opacity:.09;stroke:" + ink + ";stroke-width:2.5\""
        if item.kind == .circle {
            return "<ellipse cx=\"" + number(f.x + f.width / 2) + "\" cy=\"" + number(f.y + f.height / 2) + "\" rx=\""
                + number(f.width / 2) + "\" ry=\"" + number(f.height / 2) + "\"" + style + "/>"
        }
        return "<rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\""
            + number(f.height) + "\" rx=\"5\" ry=\"5\"" + style + "/>"
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
        return "M" + number(end.x - cos(angle - 0.5) * 16) + " " + number(end.y - sin(angle - 0.5) * 16)
            + "L" + number(end.x) + " " + number(end.y)
            + "L" + number(end.x - cos(angle + 0.5) * 16) + " " + number(end.y - sin(angle + 0.5) * 16)
    }

    static func stroke(_ item: EaselItem) -> String {
        guard let path = strokePath(item) else { return "" }
        let style = " style=\"fill:none;stroke:" + paint(item.color) + ";stroke-width:3;stroke-linecap:round;stroke-linejoin:round\""
        var result = "<path d=\"" + path + "\"" + style + "/>"
        if let head = arrowHead(item) { result += "<path d=\"" + head + "\"" + style + "/>" }
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

    static func text(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        guard let layout, !layout.runs.isEmpty || layout.fillPath != nil else { return "" }
        var result = "<g transform=\"translate(" + number(item.frame.x) + " " + number(item.frame.y) + ")\">"
        if let fill = layout.fillPath, !fill.isEmpty {
            result += "<path d=\"" + escape(fill) + "\" style=\"fill:" + (color(layout.fillColor) ?? "#000000") + "\"/>"
        }
        for run in layout.runs where !run.text.isEmpty { result += textRun(run) }
        return result + "</g>"
    }

    static func textRun(_ run: EaselVectorTextRun) -> String {
        var style = "font-family:" + run.fontFamily + ";font-size:" + number(run.fontSize) + "px"
        if run.weight != 400 { style += ";font-weight:" + String(run.weight) }
        if run.italic { style += ";font-style:italic" }
        style += ";fill:" + (run.color.map(paint) ?? "var(--easel-ink)")
        let decorations = [run.underline ? "underline" : nil, run.strikethrough ? "line-through" : nil].compactMap { $0 }
        if !decorations.isEmpty { style += ";text-decoration:" + decorations.joined(separator: " ") }
        let body = "<text x=\"" + number(run.x) + "\" y=\"" + number(run.y) + "\" xml:space=\"preserve\" style=\"" + escape(style) + "\">"
            + escape(run.text) + "</text>"
        return linked(body, run.link)
    }

    static func css(_ palette: EaselVectorPalette) -> String {
        func variables(_ swatch: EaselVectorPalette.Swatch) -> String {
            "--easel-ink:" + swatch.ink + ";--easel-card:" + swatch.card + ";--easel-card-line:" + swatch.cardLine + ";--easel-muted:" + swatch.muted + ";"
        }
        return ":root{" + variables(palette.light) + "}\n"
            + "@media screen and (prefers-color-scheme:dark){:root{" + variables(palette.dark) + "}}\n"
            + ".easel-canvas{margin:0;overflow-x:auto;line-height:0}\n"
            + ".easel-svg{display:block;max-width:100%;height:auto;margin:0 auto}\n"
            + ".easel-svg a{cursor:pointer}\n" + codeCSS(palette.code)
            + highlightCSS
    }

    static func htmlDocument(_ document: EaselDocument, art: EaselVectorArt, palette: EaselVectorPalette = .standard) -> String {
        let trimmed = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled Easel" : trimmed
        var html = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        html += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        html += "<meta name=\"generator\" content=\"Parc\">\n"
        html += "<title>" + escape(name) + "</title>\n<style>\n" + NotePageHTMLStyle.css + css(palette) + "</style>\n</head>\n"
        html += "<body class=\"page-font-standard full-width easel-export\">\n<article class=\"page\">\n<header class=\"page-header\">\n"
        html += "<h1 class=\"page-title\">" + escape(name) + "</h1>\n</header>\n<main class=\"page-body\">\n<figure class=\"easel-canvas\">"
        html += svg(document.items, art: art, title: name)
        html += "</figure>\n</main>\n</article>\n</body>\n</html>\n"
        return html
    }

    static func imageMimeType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        return nil
    }

    static func exportFileName(_ title: String, fileExtension: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (trimmed.isEmpty ? "Untitled Easel" : trimmed)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return base + "." + fileExtension
    }
}
