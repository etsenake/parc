import AppKit

@MainActor
package enum ParcBrandMark {
    package enum Style: String { case borderless = "Borderless", monochrome = "Monochrome" }

    package static let monochromeOutline = "M6.88 12.15C6.39 11.81 5.69 11.47 5.51 10.86C5.29 10.14 6.02 9.59 6.88 10.12C6.93 9.8 6.9 9.45 6.9 9.13C6.89 8.33 6.84 5.81 6.93 5.19C6.99 4.84 7.11 4.48 7.29 4.17C8.19 2.58 10.24 2.25 11.92 2.24C13.52 2.24 15.26 2.53 16.55 3.54C17.09 3.97 17.53 4.52 17.85 5.14C18.79 7.01 18.81 9.92 17.46 11.6C16.84 12.38 16.06 12.92 15.14 13.31C14.11 13.75 12.95 13.91 11.84 13.93C11.55 13.93 11.25 13.91 10.95 13.91C10.9 14.29 10.94 17.47 10.95 18.12C10.95 18.72 10.98 19.3 11.51 19.67C11.98 19.99 12.73 19.86 12.96 19.31C13.13 18.92 12.9 18.61 13.35 18.27C13.97 17.8 14.69 18.39 14.69 19.08C14.68 20.07 13.82 20.89 12.98 21.28C11.35 22.05 8.91 21.93 7.67 20.48C6.84 19.51 6.89 18.48 6.9 17.29C6.91 16.09 6.9 14.89 6.9 13.69C6.89 13.24 6.94 12.57 6.88 12.15ZM10.95 5.37C10.89 6 10.94 7.49 10.94 8.22C10.94 8.83 10.94 9.44 10.94 10.05C10.94 10.43 10.92 10.83 10.95 11.21C11.32 11.28 12.19 11.14 12.59 11.04C13.31 10.86 14 10.58 14.53 10.03C15.57 8.96 15.58 6.94 14.42 5.94C13.7 5.31 12.73 5.21 11.81 5.25C11.53 5.27 11.21 5.28 10.95 5.37Z"

    package static let monochromePath: CGPath = path(svg: monochromeOutline) ?? CGMutablePath()

    package static var monochromeBounds: CGRect { monochromePath.boundingBoxOfPath }

    package static func path(svg data: String) -> CGPath? {
        var tokens: [String] = []
        var number = ""
        func end() { if !number.isEmpty { tokens.append(number); number = "" } }
        for character in data {
            if "MLCZmlcz".contains(character) { end(); tokens.append(String(character)) }
            else if character == " " || character == "," || character == "\n" { end() }
            else if character == "-" { end(); number = "-" }
            else { number.append(character) }
        }
        end()
        let path = CGMutablePath()
        var index = 0, command = ""
        func take(_ count: Int) -> [CGFloat]? {
            guard index + count <= tokens.count else { return nil }
            let values = tokens[index..<index + count].compactMap(Double.init).map { CGFloat($0) }
            guard values.count == count else { return nil }
            index += count
            return values
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index].uppercased(); index += 1
                if command == "Z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M":
                guard let p = take(2) else { return nil }
                path.move(to: CGPoint(x: p[0], y: p[1])); command = "L"
            case "L":
                guard let p = take(2) else { return nil }
                path.addLine(to: CGPoint(x: p[0], y: p[1]))
            case "C":
                guard let p = take(6) else { return nil }
                path.addCurve(to: CGPoint(x: p[4], y: p[5]), control1: CGPoint(x: p[0], y: p[1]), control2: CGPoint(x: p[2], y: p[3]))
            default:
                return nil
            }
        }
        return path.isEmpty ? nil : path
    }

    package static func image(_ style: Style, resources: URL? = Bundle.main.resourceURL) -> NSImage? {
        guard let url = resources?.appendingPathComponent("AppIcons/Marks/\(style.rawValue).png"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.isTemplate = style == .monochrome
        return image
    }

    package static func drawMonochrome(_ image: NSImage, in rect: CGRect, color: NSColor, context: CGContext) {
        guard rect.width > 0, rect.height > 0,
              let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = min(rect.width / CGFloat(mask.width), rect.height / CGFloat(mask.height))
        let fitted = CGRect(x: rect.midX - CGFloat(mask.width) * scale / 2,
                            y: rect.midY - CGFloat(mask.height) * scale / 2,
                            width: CGFloat(mask.width) * scale, height: CGFloat(mask.height) * scale)
        context.saveGState()
        context.clip(to: fitted, mask: mask)
        context.setFillColor(color.cgColor)
        context.fill(fitted)
        context.restoreGState()
    }
}
