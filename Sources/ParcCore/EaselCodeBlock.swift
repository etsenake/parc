import Foundation

package enum EaselCodeBlock {
    static let defaultLanguage = "typescript"
    package static let starterLineCount = 4
    static let starterText = String(repeating: "\n", count: starterLineCount - 1)
    package static let defaultWidth = 440.0
    package static let minimumWidth = 160.0
    package static let lineHeight = 22.0
    package static let headerHeight = 34.0
    package static let bottomPadding = 14.0
    package static let sidePadding = 16.0
    package static let labelBaseline = 22.0
    package static let cornerRadius = 10.0
    static let stackGap = 24.0
    static let cascadeStep = 24.0

    package static func language(_ stored: String?) -> NoteCodeLanguage {
        stored.flatMap(NoteCodeLanguage.named) ?? .plainText
    }

    package static func stored(_ language: NoteCodeLanguage) -> String? {
        language.id == NoteCodeLanguage.plainText.id ? nil : language.id
    }

    package static func displayName(_ stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return NoteCodeLanguage.plainText.name }
        return NoteCodeLanguage.named(stored)?.name ?? stored
    }

    package static func newLanguage(remembered: String?) -> String? {
        guard let remembered, let language = NoteCodeLanguage.named(remembered) else { return defaultLanguage }
        return stored(language)
    }

    package static func rememberedValue(_ stored: String?) -> String {
        stored.flatMap(NoteCodeLanguage.named)?.id ?? NoteCodeLanguage.plainText.id
    }

    package static func lineCount(_ code: String) -> Int {
        code.utf16.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
    }

    package static func height(lines: Int) -> Double {
        headerHeight + Double(max(1, lines)) * lineHeight + bottomPadding
    }

    package static func textWidth(forWidth width: Double) -> Double {
        max(1, width - 2 * sidePadding)
    }

    package static func item(at origin: EaselPoint, language: String?, zIndex: Int, width: Double = defaultWidth, text: String = starterText) -> EaselItem {
        let size = max(minimumWidth, width)
        var item = EaselItem(kind: .code, frame: EaselRect(x: max(0, origin.x), y: max(0, origin.y), width: size, height: height(lines: lineCount(text))),
                             zIndex: zIndex, text: text)
        item.language = language
        return item
    }

    package static func placedOrigin(in visible: EaselRect, width: Double, height: Double, occupied: [EaselRect]) -> EaselPoint {
        var origin = EaselPoint(x: max(0, (visible.x + visible.width / 2 - width / 2).rounded()),
                                y: max(0, (visible.y + min(120, max(24, visible.height / 4))).rounded()))
        for _ in 0..<12 where occupied.contains(where: { abs($0.x - origin.x) < 1 && abs($0.y - origin.y) < 1 }) {
            origin.x += cascadeStep
            origin.y += cascadeStep
        }
        return origin
    }

    package static func originBelow(_ frame: EaselRect, height: Double, occupied: [EaselRect]) -> EaselPoint {
        var y = frame.y + frame.height + stackGap
        for _ in 0..<64 {
            let candidate = EaselRect(x: frame.x, y: y, width: frame.width, height: height)
            guard let blocker = occupied.filter({ EaselContentHitTest.intersects(candidate, $0) })
                .max(by: { $0.y + $0.height < $1.y + $1.height }) else { break }
            y = blocker.y + blocker.height + stackGap
        }
        return EaselPoint(x: frame.x, y: y)
    }

    package static func settledFrame(_ proposed: EaselRect, original: EaselRect, lines: Int, keepsTop: Bool) -> EaselRect {
        let width = max(minimumWidth, proposed.width)
        let leftMoved = abs(proposed.x - original.x) > 1e-9
            && abs(proposed.x + proposed.width - original.x - original.width) < 1e-9
        let x = leftMoved ? proposed.x + proposed.width - width : proposed.x
        return EaselRect(x: max(0, x), y: keepsTop ? original.y : proposed.y, width: width, height: height(lines: lines))
    }
}

package struct EaselCodePalette: Equatable {
    package struct Swatch: Equatable {
        package var fill: String
        package var line: String
        package var ink: String
        package var syntax: [String: String]

        package init(fill: String, line: String, ink: String, syntax: [String: String]) {
            self.fill = fill
            self.line = line
            self.ink = ink
            self.syntax = syntax
        }
    }
    package var light: Swatch
    package var dark: Swatch

    package init(light: Swatch, dark: Swatch) {
        self.light = light
        self.dark = dark
    }

    package static let standard = EaselCodePalette(
        light: Swatch(fill: "rgba(31,27,46,.045)", line: "rgba(31,27,46,.12)", ink: "#29243D", syntax: [
            "comment": "rgba(41,36,61,.5)", "keyword": "#6A1FC9", "string": "#2A7A4B", "number": "#A8520C",
            "type": "#0B7285", "function": "#2350C2", "tag": "#B8322B", "attribute": "#9A3F86", "escape": "#B3366E",
            "operator": "rgba(41,36,61,.68)", "heading": "#220C7F", "strong": "#29243D", "emphasis": "#29243D",
            "link": "#2350C2", "meta": "#7A5C9E", "variable": "#29243D"]),
        dark: Swatch(fill: "rgba(255,255,255,.06)", line: "rgba(255,255,255,.14)", ink: "#E4E1F5", syntax: [
            "comment": "rgba(228,225,245,.48)", "keyword": "#C0A6FF", "string": "#8FD8A9", "number": "#F5AC72",
            "type": "#72D4E3", "function": "#93B6FF", "tag": "#FF8F86", "attribute": "#EE9BDB", "escape": "#FF92BF",
            "operator": "rgba(228,225,245,.7)", "heading": "#C9C4FF", "strong": "#E4E1F5", "emphasis": "#E4E1F5",
            "link": "#93B6FF", "meta": "#B9A5D6", "variable": "#E4E1F5"]))
}

extension EaselVectorExport {
    package static let codeFontFamily = "\"Space Mono\",ui-monospace,\"SF Mono\",Menlo,monospace"

    package static func codeBlock(_ item: EaselItem, _ layout: EaselVectorText?) -> String {
        let f = item.frame, radius = number(EaselCodeBlock.cornerRadius)
        let box = "x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\""
            + number(f.height) + "\" rx=\"" + radius + "\" ry=\"" + radius + "\""
        let clip = "code-" + item.id.uuidString.lowercased()
        var result = "<g class=\"easel-code\"><rect " + box
            + " style=\"fill:var(--easel-code);stroke:var(--easel-code-line);stroke-width:1\"/>"
        result += "<clipPath id=\"" + clip + "\"><rect " + box + "/></clipPath><g clip-path=\"url(#" + clip + ")\">"
        result += "<text x=\"" + number(f.x + EaselCodeBlock.sidePadding) + "\" y=\"" + number(f.y + EaselCodeBlock.labelBaseline)
            + "\" style=\"font-family:var(--font);font-size:12px;font-weight:700;fill:var(--easel-muted)\">"
            + escape(EaselCodeBlock.displayName(item.language)) + "</text>"
        result += "<g transform=\"translate(" + number(f.x) + " " + number(f.y) + ")\">"
        for run in layout?.runs ?? plainCodeRuns(item) where !run.text.isEmpty { result += codeRun(run) }
        return result + "</g></g></g>"
    }

    static func plainCodeRuns(_ item: EaselItem) -> [EaselVectorTextRun] {
        item.text.components(separatedBy: "\n").enumerated().map { index, line in
            EaselVectorTextRun(x: EaselCodeBlock.sidePadding, y: EaselCodeBlock.headerHeight + Double(index) * EaselCodeBlock.lineHeight + 16,
                               text: line.replacingOccurrences(of: "\t", with: "    "), fontFamily: codeFontFamily, fontSize: 14)
        }
    }

    static func codeRun(_ run: EaselVectorTextRun) -> String {
        var style = "font-family:" + run.fontFamily + ";font-size:" + number(run.fontSize) + "px"
        if run.weight != 400 { style += ";font-weight:" + String(run.weight) }
        if run.italic { style += ";font-style:italic" }
        let family = run.syntax.map { String($0.lowercased().unicodeScalars.filter { $0.isASCII && CharacterSet.lowercaseLetters.contains($0) }) }
        let fallback = run.color.flatMap(color) ?? "var(--easel-code-ink)"
        if let family, !family.isEmpty { style += ";fill:var(--easel-syntax-" + family + "," + fallback + ")" }
        else { style += ";fill:var(--easel-code-ink," + fallback + ")" }
        if run.underline { style += ";text-decoration:underline" }
        return "<text x=\"" + number(run.x) + "\" y=\"" + number(run.y) + "\" xml:space=\"preserve\" style=\"" + escape(style) + "\">"
            + escape(run.text) + "</text>"
    }

    static func codeCSS(_ palette: EaselCodePalette) -> String {
        func variables(_ swatch: EaselCodePalette.Swatch) -> String {
            var result = "--easel-code:" + swatch.fill + ";--easel-code-line:" + swatch.line + ";--easel-code-ink:" + swatch.ink + ";"
            for family in swatch.syntax.keys.sorted() {
                guard let value = swatch.syntax[family], family.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.lowercaseLetters.contains($0) }) else { continue }
                result += "--easel-syntax-" + family + ":" + value + ";"
            }
            return result
        }
        return ":root{" + variables(palette.light) + "}\n"
            + "@media screen and (prefers-color-scheme:dark){:root{" + variables(palette.dark) + "}}\n"
    }
}
