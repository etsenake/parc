import Foundation

package struct EaselVectorSectionTitle: Equatable {
    var text: String
    var width: Double
    var baseline: Double
    var hiddenCount: Int?

    package init(text: String, width: Double, baseline: Double, hiddenCount: Int? = nil) {
        self.text = text
        self.width = width
        self.baseline = baseline
        self.hiddenCount = hiddenCount
    }
}

extension EaselVectorExport {
    static func paintedFrame(_ item: EaselItem) -> EaselRect {
        let f = item.frame
        switch item.kind {
        case .sticky:
            let scale = EaselBoardObjects.textScale(item)
            return EaselRect(x: f.x - 3 * scale, y: f.y - 2 * scale, width: f.width + 6 * scale, height: f.height + 20 * scale)
        case .section:
            let reach = EaselBoardObjects.sectionTitleHeight + EaselBoardObjects.sectionTitleGap
            return EaselRect(x: f.x, y: f.y - reach, width: f.width, height: f.height + reach)
        default:
            let bounds = EaselRotation.bounds(of: item)
            let extra = creditExtent(item)
            return extra > 0 ? EaselRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height + extra) : bounds
        }
    }

    static func rounded(_ r: EaselRect, radius: Double, style: String) -> String {
        "<rect x=\"" + number(r.x) + "\" y=\"" + number(r.y) + "\" width=\"" + number(max(0, r.width)) + "\" height=\""
            + number(max(0, r.height)) + "\" rx=\"" + number(radius) + "\" ry=\"" + number(radius) + "\" style=\"" + style + "\"/>"
    }

    static func sticky(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        let f = item.frame, scale = EaselBoardObjects.textScale(item)
        let radius = max(1.5, 4 * scale), lift = min(f.height * 0.45, 72 * scale)
        guard case .color = EaselPaintRules.fill(item) else { return "<g class=\"easel-sticky\">" + text(item, layout) + "</g>" }
        var result = "<g class=\"easel-sticky\">"
        let clip = "sticky-shadow-" + item.id.uuidString.lowercased()
        let reach = 40 * scale
        result += "<clipPath id=\"" + clip + "\"><path clip-rule=\"evenodd\" d=\"M" + number(f.x - reach) + " " + number(f.y - reach)
            + "H" + number(f.x + f.width + reach) + "V" + number(f.y + f.height + reach) + "H" + number(f.x - reach) + "Z"
            + roundedPath(f, radius: radius) + "\"/></clipPath><g clip-path=\"url(#" + clip + ")\">"
        for step in 0..<3 {
            let spread = Double(3 - step) * 3 * scale
            let shadow = EaselRect(x: f.x + 6 * scale - spread, y: f.y + f.height - lift + 6 * scale - spread / 2,
                                   width: max(1, f.width - 12 * scale) + 2 * spread, height: lift + spread)
            result += rounded(shadow, radius: radius + spread, style: "fill:#000000;fill-opacity:.05")
        }
        let contact = EaselRect(x: f.x - 0.75 * scale, y: f.y + scale, width: f.width + 1.5 * scale, height: f.height + 0.5 * scale)
        result += rounded(contact, radius: radius + 0.75 * scale, style: "fill:#000000;fill-opacity:.1") + "</g>"
        result += rounded(f, radius: radius, style: fillStyle(item))
        let finish = "sticky-finish-" + item.id.uuidString.lowercased()
        result += "<defs><linearGradient id=\"" + finish + "\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
            + "<stop offset=\"0\" stop-color=\"#FFFFFF\" stop-opacity=\".16\"/>"
            + "<stop offset=\".35\" stop-color=\"#FFFFFF\" stop-opacity=\"0\"/>"
            + "<stop offset=\"1\" stop-color=\"#000000\" stop-opacity=\".05\"/></linearGradient></defs>"
        result += rounded(f, radius: radius, style: "fill:url(#" + finish + ")")
        let edge = EaselRect(x: f.x + 0.25, y: f.y + 0.25, width: f.width - 0.5, height: f.height - 0.5)
        result += rounded(edge, radius: radius, style: "fill:none;stroke:#000000;stroke-opacity:.06;stroke-width:.5")
        return result + text(item, layout) + "</g>"
    }

    static func roundedPath(_ r: EaselRect, radius: Double) -> String {
        let k = min(radius, r.width / 2, r.height / 2)
        return "M" + number(r.x + k) + " " + number(r.y) + "H" + number(r.x + r.width - k)
            + "A" + number(k) + " " + number(k) + " 0 0 1 " + number(r.x + r.width) + " " + number(r.y + k)
            + "V" + number(r.y + r.height - k)
            + "A" + number(k) + " " + number(k) + " 0 0 1 " + number(r.x + r.width - k) + " " + number(r.y + r.height)
            + "H" + number(r.x + k)
            + "A" + number(k) + " " + number(k) + " 0 0 1 " + number(r.x) + " " + number(r.y + r.height - k)
            + "V" + number(r.y + k)
            + "A" + number(k) + " " + number(k) + " 0 0 1 " + number(r.x + k) + " " + number(r.y) + "Z"
    }

    static func sectionTabFill(_ item: EaselItem, line: String, border: Double) -> String {
        switch EaselPaintRules.fill(item) {
        case .none: return "fill:" + line + ";fill-opacity:" + number(border)
        case .wash(let opacity): return "fill:" + paint(item.color, role: .ink) + ";fill-opacity:" + number(max(opacity, 0.12))
        case .color(let hex, let role, let opacity):
            return "fill:" + paint(hex, role: role) + (opacity < 1 ? ";fill-opacity:" + number(max(opacity, 0.12)) : "")
        }
    }

    static func section(_ item: EaselItem, title: EaselVectorSectionTitle?) -> String {
        let f = item.frame, ink = paint(item.color, role: .ink)
        let border = isAutomatic(item.color) ? 0.22 : 0.5
        let line = ";stroke:" + ink + ";stroke-opacity:" + number(border)
        var result = "<g class=\"easel-section\" role=\"region\" aria-label=\"" + escape(EaselBoardObjects.displayTitle(item)) + "\">"
        result += rounded(f, radius: 14, style: fillStyle(item) + line + ";stroke-width:1.5")
        if let count = title?.hiddenCount, f.width > 180, f.height > 48 {
            result += "<text x=\"" + number(f.x + f.width / 2) + "\" y=\"" + number(f.y + f.height / 2 + 5)
                + "\" text-anchor=\"middle\" style=\"font-family:var(--font);font-size:15px;font-weight:700;fill:" + ink
                + ";fill-opacity:.72\">" + escape(EaselBoardObjects.hiddenSummary(count)) + "</text>"
        }
        let name = title?.text ?? EaselBoardObjects.displayTitle(item)
        let tab = EaselBoardObjects.titleTab(item, titleWidth: title?.width ?? Double(name.count) * 7.6, zoom: 1)
        result += rounded(tab, radius: 7, style: sectionTabFill(item, line: ink, border: border) + line + ";stroke-width:1")
        result += "<text x=\"" + number(tab.x + EaselBoardObjects.sectionTitlePadding) + "\" y=\""
            + number(tab.y + tab.height / 2 + (title?.baseline ?? 4.5))
            + "\" xml:space=\"preserve\" style=\"font-family:var(--font);font-size:13px;font-weight:800;fill:" + ink + "\">"
            + escape(name) + "</text>"
        return result + "</g>"
    }
}
