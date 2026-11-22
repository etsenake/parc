import Foundation

package struct EaselMediaCardLayout: Equatable {
    package var tile: EaselRect
    package var textX: Double
    package var textWidth: Double
    package var titleBaseline: Double
    package var subtitleBaseline: Double?
    package init(tile: EaselRect, textX: Double, textWidth: Double, titleBaseline: Double, subtitleBaseline: Double? = nil) {
        self.tile = tile
        self.textX = textX
        self.textWidth = textWidth
        self.titleBaseline = titleBaseline
        self.subtitleBaseline = subtitleBaseline
    }
}

extension EaselVectorExport {
    package static let creditGap = 4.0
    package static let creditFontSize = 11.0
    package static let creditHeight = 14.0

    package static func mediaCredit(_ item: EaselItem) -> NoteMediaCredit? {
        guard item.kind == .image, let credit = item.credit else { return nil }
        return NoteMediaCredit(name: credit.name, link: credit.profileURL)
    }

    static func creditExtent(_ item: EaselItem) -> Double {
        mediaCredit(item) == nil ? 0 : creditGap + creditHeight
    }

    static func creditElement(_ item: EaselItem) -> String {
        guard let credit = mediaCredit(item) else { return "" }
        let f = item.frame
        var body = ""
        for part in credit.parts {
            switch part {
            case .text(let text):
                body += "<tspan>" + escape(text) + "</tspan>"
            case .link(let text, let url):
                body += linked("<tspan>" + escape(text) + "</tspan>", url.absoluteString)
            }
        }
        let text = "<text x=\"" + number(f.x) + "\" y=\"" + number(f.y + f.height + creditGap + creditFontSize)
            + "\" xml:space=\"preserve\" style=\"font-family:var(--font);font-size:" + number(creditFontSize)
            + "px;fill:var(--easel-muted)\">" + body + "</text>"
        var upright = item
        upright.flipHorizontal = nil
        upright.flipVertical = nil
        return transformed(upright, text)
    }

    package static func mediaCardLayout(_ f: EaselRect) -> EaselMediaCardLayout {
        let inset = 14.0
        let side = min(36, max(16, f.height - 2 * inset))
        let tile = EaselRect(x: f.x + inset, y: f.y + (f.height - side) / 2, width: side, height: side)
        let textX = tile.x + side + 12
        let middle = f.y + f.height / 2
        let two = f.height >= 44
        return EaselMediaCardLayout(tile: tile, textX: textX, textWidth: max(0, f.x + f.width - inset - textX),
                                    titleBaseline: two ? middle - 3 : middle + 5, subtitleBaseline: two ? middle + 15 : nil)
    }

    package static func mediaGlyph(_ kind: EaselItemKind, in tile: EaselRect) -> [[EaselPoint]] {
        func point(_ x: Double, _ y: Double) -> EaselPoint { EaselPoint(x: tile.x + tile.width * x, y: tile.y + tile.height * y) }
        switch kind {
        case .audio:
            let heights = [0.2, 0.44, 0.6, 0.34, 0.5, 0.26]
            let step = 0.6 / Double(heights.count)
            return heights.enumerated().map { index, height in
                let left = 0.2 + step * Double(index) + step * 0.15, right = left + step * 0.7
                return [point(left, 0.5 - height / 2), point(right, 0.5 - height / 2), point(right, 0.5 + height / 2), point(left, 0.5 + height / 2)]
            }
        case .video:
            return [[point(0.38, 0.28), point(0.74, 0.5), point(0.38, 0.72)]]
        default:
            return [[point(0.28, 0.2), point(0.55, 0.2), point(0.72, 0.38), point(0.72, 0.8), point(0.28, 0.8)]]
        }
    }

    package static func mediaTitle(_ item: EaselItem) -> String {
        if let name = item.fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let raw = item.url, let url = URL(string: raw) {
            let last = url.lastPathComponent
            if !last.isEmpty, last != "/" { return last.removingPercentEncoding ?? last }
            if let host = url.host, !host.isEmpty { return host }
        }
        switch item.kind {
        case .audio: return "Audio"
        case .video: return "Video"
        case .pdf: return "PDF"
        default: return "File"
        }
    }

    package static func mediaSubtitle(_ item: EaselItem, detail: String?) -> String {
        switch item.kind {
        case .audio: return "Audio"
        case .video: return URL(string: item.url ?? "")?.host ?? "Video"
        case .pdf: return detail.map { "PDF, " + $0 } ?? "PDF"
        default: return detail ?? "File"
        }
    }

    static func mediaCard(_ item: EaselItem, detail: String?) -> String {
        let f = item.frame
        let layout = mediaCardLayout(f)
        var result = "<g class=\"easel-card\"><rect x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width)
            + "\" height=\"" + number(f.height) + "\" rx=\"8\" ry=\"8\" style=\"fill:var(--easel-card);stroke:var(--easel-card-line);stroke-width:1\"/>"
        result += rounded(layout.tile, radius: 8, style: "fill:var(--easel-card-line)")
        for shape in mediaGlyph(item.kind, in: layout.tile) {
            guard let first = shape.first else { continue }
            let path = "M" + number(first.x) + " " + number(first.y) + shape.dropFirst().map { "L" + number($0.x) + " " + number($0.y) }.joined() + "Z"
            result += "<path d=\"" + path + "\" style=\"fill:var(--easel-ink)\"/>"
        }
        let clip = "media-" + item.id.uuidString.lowercased()
        result += "<clipPath id=\"" + clip + "\"><rect x=\"" + number(layout.textX) + "\" y=\"" + number(f.y) + "\" width=\""
            + number(layout.textWidth) + "\" height=\"" + number(f.height) + "\"/></clipPath><g clip-path=\"url(#" + clip + ")\">"
        result += "<text x=\"" + number(layout.textX) + "\" y=\"" + number(layout.titleBaseline)
            + "\" style=\"font-family:var(--font);font-size:15px;font-weight:700;fill:var(--easel-ink)\">" + escape(mediaTitle(item)) + "</text>"
        if let baseline = layout.subtitleBaseline {
            result += "<text x=\"" + number(layout.textX) + "\" y=\"" + number(baseline)
                + "\" style=\"font-family:var(--font);font-size:12px;fill:var(--easel-muted)\">" + escape(mediaSubtitle(item, detail: detail)) + "</text>"
        }
        return linked(result + "</g></g>", item.url)
    }

    static func mediaElement(_ item: EaselItem, art: EaselVectorArt) -> String {
        switch item.kind {
        case .pdf:
            if let picture = art.images[item.id] { return poster(item, picture) }
            return mediaCard(item, detail: art.mediaDetails[item.id])
        case .audio, .file:
            return mediaCard(item, detail: art.mediaDetails[item.id])
        default:
            return ""
        }
    }

    static func linkedVideoElement(_ item: EaselItem) -> String {
        guard item.poster == nil, item.assetID == nil, item.url != nil else { return "" }
        return mediaCard(item, detail: nil)
    }
}
