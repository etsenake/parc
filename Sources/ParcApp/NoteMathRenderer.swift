import AppKit
import CoreText

final class NoteMathLayoutEntry {
    let box: NoteMathBox
    let frame: CGRect
    let error: NoteMathParseError?
    let isEmpty: Bool

    init(box: NoteMathBox, error: NoteMathParseError?, isEmpty: Bool) {
        self.box = box
        self.error = error
        self.isEmpty = isEmpty
        frame = isEmpty ? .zero : NoteMathLayoutEntry.inkFrame(box)
    }

    private static func inkFrame(_ box: NoteMathBox) -> CGRect {
        var frame = CGRect(x: 0, y: -box.descent, width: box.width, height: box.height)
        for ink in box.inks {
            var bounds: CGRect
            switch ink.content {
            case .glyph(let glyph, let font):
                var value = glyph
                bounds = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(font, .horizontal, &value, &bounds, 1)
            case .rule(let size):
                bounds = CGRect(origin: .zero, size: size)
            case .line(let line):
                bounds = CTLineGetImageBounds(line, nil)
            case .segment(let vector, let width):
                bounds = NoteMathInk.segmentBounds(vector, width: width)
            }
            guard !bounds.isNull, !bounds.isEmpty else { continue }
            frame = frame.union(bounds.offsetBy(dx: ink.origin.x, dy: ink.origin.y))
        }
        return frame.insetBy(dx: -1, dy: -1).integral
    }
}

final class NoteMathRendering {
    let source: String
    let fontSize: CGFloat
    let color: NSColor
    let display: Bool
    let size: CGSize
    let baseline: CGFloat
    let error: String?
    let errorRange: NSRange?
    let isEmpty: Bool
    private let entry: NoteMathLayoutEntry

    init(source: String, fontSize: CGFloat, color: NSColor, display: Bool, entry: NoteMathLayoutEntry) {
        self.source = source
        self.fontSize = fontSize
        self.color = color
        self.display = display
        self.entry = entry
        size = entry.frame.size
        baseline = entry.frame.maxY
        error = entry.error?.message
        errorRange = entry.error.map { NSRange(location: $0.offset, length: $0.length) }
        isEmpty = entry.isEmpty
    }

    var descent: CGFloat { size.height - baseline }

    var accessibilityLabel: String {
        isEmpty ? "Empty equation" : error == nil ? "Equation: \(source)" : "Equation with a typo: \(source)"
    }

    func draw(in context: CGContext, at origin: CGPoint) {
        draw(in: context, at: origin, ink: color.cgColor, muted: Self.mutedInk(for: color))
    }

    func drawFlipped(in context: CGContext, at topLeft: CGPoint) {
        context.saveGState()
        context.translateBy(x: topLeft.x, y: topLeft.y + size.height)
        context.scaleBy(x: 1, y: -1)
        draw(in: context, at: .zero)
        context.restoreGState()
    }

    private func draw(in context: CGContext, at origin: CGPoint, ink: CGColor, muted: CGColor) {
        let base = CGPoint(x: origin.x - entry.frame.minX, y: origin.y - entry.frame.minY)
        context.saveGState()
        context.textMatrix = .identity
        for item in entry.box.inks {
            let fill: CGColor
            switch item.color {
            case .inherited: fill = ink
            case .custom(let custom): fill = custom
            case .muted: fill = muted
            }
            context.setFillColor(fill)
            let point = CGPoint(x: base.x + item.origin.x, y: base.y + item.origin.y)
            switch item.content {
            case .glyph(let glyph, let font):
                var value = glyph
                var position = point
                context.textMatrix = .identity
                CTFontDrawGlyphs(font, &value, &position, 1, context)
            case .rule(let size):
                context.fill(CGRect(origin: point, size: size))
            case .line(let line):
                context.textMatrix = .identity
                context.textPosition = point
                CTLineDraw(line, context)
            case .segment(let vector, let width):
                context.setStrokeColor(fill)
                context.setLineWidth(width)
                context.setLineCap(.round)
                context.move(to: point)
                context.addLine(to: CGPoint(x: point.x + vector.dx, y: point.y + vector.dy))
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    static func mutedInk(for color: NSColor) -> CGColor {
        let base = color.usingColorSpace(.sRGB) ?? .black
        let red = NSColor.systemRed.usingColorSpace(.sRGB) ?? .red
        return (base.blended(withFraction: 0.55, of: red) ?? red).withAlphaComponent(0.85).cgColor
    }

    func image(appearance: NSAppearance? = nil) -> NSImage {
        var fixed: (ink: CGColor, muted: CGColor)?
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                fixed = (self.color.cgColor, Self.mutedInk(for: self.color))
            }
        }
        let image = NSImage(size: size, flipped: false) { [self] _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if let fixed {
                draw(in: context, at: .zero, ink: fixed.ink, muted: fixed.muted)
            } else {
                draw(in: context, at: .zero)
            }
            return true
        }
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    func cgImage(scale: CGFloat = 2, appearance: NSAppearance? = nil) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        if let appearance {
            appearance.performAsCurrentDrawingAppearance { self.draw(in: context, at: .zero) }
        } else {
            draw(in: context, at: .zero)
        }
        return context.makeImage()
    }
}

@MainActor
enum NoteMathRenderer {
    private static var fontURL: URL?
    private static var loadedFont: NoteMathFont?
    private static var attemptedLoad = false
    private static let cache: NSCache<NSString, NoteMathLayoutEntry> = {
        let cache = NSCache<NSString, NoteMathLayoutEntry>()
        cache.countLimit = 400
        return cache
    }()

    static func useFont(at url: URL) {
        fontURL = url
        loadedFont = nil
        attemptedLoad = false
        cache.removeAllObjects()
    }

    static var font: NoteMathFont? {
        if attemptedLoad { return loadedFont }
        attemptedLoad = true
        let bundled = Bundle.main.url(forResource: "STIXTwoMath-Regular", withExtension: "otf", subdirectory: "NoteFonts")
        if let url = fontURL ?? bundled {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            loadedFont = NoteMathFont(url: url)
        }
        if loadedFont == nil { loadedFont = NoteMathFont(name: "STIXTwoMath-Regular") }
        return loadedFont
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    static func render(_ latex: String, fontSize: CGFloat, color: NSColor, display: Bool) -> NoteMathRendering {
        NoteMathRendering(source: latex, fontSize: fontSize, color: color, display: display,
                          entry: layout(latex, fontSize: fontSize, display: display))
    }

    static func layout(_ latex: String, fontSize: CGFloat, display: Bool) -> NoteMathLayoutEntry {
        let key = "\(display ? "D" : "T")\(fontSize)|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let entry = makeEntry(latex, fontSize: fontSize, display: display)
        cache.setObject(entry, forKey: key)
        return entry
    }

    private static func makeEntry(_ latex: String, fontSize: CGFloat, display: Bool) -> NoteMathLayoutEntry {
        if latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NoteMathLayoutEntry(box: NoteMathBox(), error: nil, isEmpty: true)
        }
        guard let font else {
            let failure = NoteMathParseError(message: "The math font is missing", offset: 0, length: (latex as NSString).length)
            return NoteMathLayoutEntry(box: errorBox(latex, fontSize: fontSize), error: failure, isEmpty: false)
        }
        do {
            let nodes = try NoteMathParser.parse(latex)
            let box = NoteMathTypesetter(font: font, baseSize: fontSize).typeset(nodes, display: display)
            return NoteMathLayoutEntry(box: box, error: nil, isEmpty: false)
        } catch {
            return NoteMathLayoutEntry(box: errorBox(latex, fontSize: fontSize), error: error, isEmpty: false)
        }
    }

    private static func errorBox(_ latex: String, fontSize: CGFloat) -> NoteMathBox {
        let flattened = latex.split(whereSeparator: \.isNewline).joined(separator: " ")
        let monospaced = NSFont.monospacedSystemFont(ofSize: fontSize * 0.82, weight: .regular) as CTFont
        let attributes: [CFString: Any] = [kCTFontAttributeName: monospaced,
                                           kCTForegroundColorFromContextAttributeName: kCFBooleanTrue as Any]
        guard let string = CFAttributedStringCreate(kCFAllocatorDefault, flattened as CFString, attributes as CFDictionary) else {
            return NoteMathBox()
        }
        let line = CTLineCreateWithAttributedString(string)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return NoteMathBox(width: width, ascent: ascent, descent: descent,
                           inks: [NoteMathInk(content: .line(line), origin: .zero, color: .muted)])
    }

    static func fontSize(matching textFont: NSFont) -> CGFloat {
        guard let font else { return textFont.pointSize }
        let mathXHeight = CTFontGetXHeight(font.font(size: textFont.pointSize))
        guard mathXHeight > 0, textFont.xHeight > 0 else { return textFont.pointSize }
        let ratio = min(max(textFont.xHeight / mathXHeight, 0.9), 1.35)
        return (textFont.pointSize * ratio * 4).rounded() / 4
    }

    static func attachment(for latex: String, font textFont: NSFont, color: NSColor,
                           appearance: NSAppearance? = nil) -> NSTextAttachment {
        let rendering = render(latex, fontSize: fontSize(matching: textFont), color: color, display: false)
        let attachment = NSTextAttachment()
        attachment.image = rendering.image(appearance: appearance)
        attachment.bounds = CGRect(x: 0, y: -rendering.descent, width: rendering.size.width, height: rendering.size.height)
        return attachment
    }
}
