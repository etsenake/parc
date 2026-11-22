import AppKit
import CoreText
import ParcCore

package final class NoteMathLayoutEntry {
    let box: NoteMathBox
    package let frame: CGRect
    let equationFrame: CGRect
    let tagFrames: [CGRect]
    let tagGap: CGFloat
    package let error: NoteMathParseError?
    package let isEmpty: Bool

    init(box: NoteMathBox, error: NoteMathParseError?, isEmpty: Bool, tagGap: CGFloat = 0) {
        self.box = box
        self.error = error
        self.isEmpty = isEmpty
        self.tagGap = tagGap
        let equation = isEmpty ? .zero : NoteMathLayoutEntry.inkFrame(box)
        let tags = isEmpty ? [] : box.tags.map { NoteMathLayoutEntry.inkFrame($0.box).offsetBy(dx: 0, dy: $0.baseline) }
        equationFrame = equation
        tagFrames = tags
        if let widest = tags.map(\.width).max() {
            let minY = tags.reduce(equation.minY) { min($0, $1.minY) }
            let maxY = tags.reduce(equation.maxY) { max($0, $1.maxY) }
            frame = CGRect(x: equation.minX, y: minY, width: equation.width + tagGap + widest, height: maxY - minY)
        } else {
            frame = equation
        }
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

package final class NoteMathRendering {
    let source: String
    let fontSize: CGFloat
    let color: NSColor
    let display: Bool
    package let size: CGSize
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

    var hasTags: Bool { !entry.tagFrames.isEmpty }

    var accessibilityLabel: String {
        isEmpty ? "Empty equation" : error == nil ? "Equation: \(source)" : "Equation with a typo: \(source)"
    }

    func draw(in context: CGContext, at origin: CGPoint) {
        draw(in: context, at: origin, width: size.width)
    }

    func links(width: CGFloat) -> [NoteMathLinkMark] {
        let available = max(width, size.width)
        let baselineY = -entry.frame.minY
        let equationX = equationOffset(width: width) - entry.equationFrame.minX
        var result: [NoteMathLinkMark] = entry.box.links.map { link in
            var flipped = link
            flipped.rect = CGRect(x: equationX + link.rect.minX, y: size.height - (baselineY + link.rect.maxY),
                                  width: link.rect.width, height: link.rect.height)
            return flipped
        }
        for (mark, frame) in zip(entry.box.tags, entry.tagFrames) {
            let x = (available - frame.maxX).rounded()
            for link in mark.box.links {
                var placed = link
                placed.rect = CGRect(x: x + link.rect.minX, y: size.height - (baselineY + mark.baseline + link.rect.maxY),
                                     width: link.rect.width, height: link.rect.height)
                result.append(placed)
            }
        }
        return result
    }

    func draw(in context: CGContext, at origin: CGPoint, width: CGFloat) {
        draw(in: context, at: origin, width: width, ink: color.cgColor, muted: Self.mutedInk(for: color), link: Self.linkInk(for: color))
    }

    package func drawFlipped(in context: CGContext, at topLeft: CGPoint) {
        drawFlipped(in: context, at: topLeft, width: size.width)
    }

    func drawFlipped(in context: CGContext, at topLeft: CGPoint, width: CGFloat) {
        context.saveGState()
        context.translateBy(x: topLeft.x, y: topLeft.y + size.height)
        context.scaleBy(x: 1, y: -1)
        draw(in: context, at: .zero, width: width)
        context.restoreGState()
    }

    func equationOffset(width: CGFloat) -> CGFloat {
        let available = max(width, size.width)
        let equation = entry.equationFrame
        var offset = (available - equation.width) / 2
        if let widest = entry.tagFrames.map(\.width).max() {
            offset = min(offset, available - widest - entry.tagGap - equation.width)
        }
        return max(0, offset).rounded()
    }

    private func draw(in context: CGContext, at origin: CGPoint, width: CGFloat, ink: CGColor, muted: CGColor, link: CGColor) {
        let available = max(width, size.width)
        let baselineY = origin.y - entry.frame.minY
        draw(entry.box.inks, in: context, at: CGPoint(x: origin.x + equationOffset(width: width) - entry.equationFrame.minX, y: baselineY),
             ink: ink, muted: muted, link: link)
        for (mark, frame) in zip(entry.box.tags, entry.tagFrames) {
            draw(mark.box.inks, in: context, at: CGPoint(x: (origin.x + available - frame.maxX).rounded(), y: baselineY + mark.baseline),
                 ink: ink, muted: muted, link: link)
        }
    }

    private func draw(_ inks: [NoteMathInk], in context: CGContext, at base: CGPoint, ink: CGColor, muted: CGColor, link: CGColor) {
        context.saveGState()
        context.textMatrix = .identity
        for item in inks {
            let fill: CGColor
            switch item.color {
            case .inherited: fill = ink
            case .custom(let custom): fill = custom
            case .muted: fill = muted
            case .link: fill = link
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

    static func linkInk(for color: NSColor) -> CGColor {
        color.withAlphaComponent(color.alphaComponent * 0.42).cgColor
    }

    package static func mutedInk(for color: NSColor) -> CGColor {
        let base = color.usingColorSpace(.sRGB) ?? .black
        let red = NSColor.systemRed.usingColorSpace(.sRGB) ?? .red
        return (base.blended(withFraction: 0.55, of: red) ?? red).withAlphaComponent(0.85).cgColor
    }

    func image(appearance: NSAppearance? = nil) -> NSImage {
        var fixed: (ink: CGColor, muted: CGColor, link: CGColor)?
        if let appearance {
            appearance.performAsCurrentDrawingAppearance {
                fixed = (self.color.cgColor, Self.mutedInk(for: self.color), Self.linkInk(for: self.color))
            }
        }
        let image = NSImage(size: size, flipped: false) { [self] _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if let fixed {
                draw(in: context, at: .zero, width: size.width, ink: fixed.ink, muted: fixed.muted, link: fixed.link)
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
package enum NoteMathRenderer {
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

    package static func render(_ latex: String, fontSize: CGFloat, color: NSColor, display: Bool,
                       numbering: NoteMathNumberingContext = NoteMathNumberingContext()) -> NoteMathRendering {
        NoteMathRendering(source: latex, fontSize: fontSize, color: color, display: display,
                          entry: layout(latex, fontSize: fontSize, display: display, numbering: numbering))
    }

    package static func layout(_ latex: String, fontSize: CGFloat, display: Bool,
                       numbering: NoteMathNumberingContext = NoteMathNumberingContext()) -> NoteMathLayoutEntry {
        let key = "\(display ? "D" : "T")\(fontSize)|\(numbering.fingerprint(for: latex, display: display))|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let entry = makeEntry(latex, fontSize: fontSize, display: display, numbering: numbering)
        cache.setObject(entry, forKey: key)
        return entry
    }

    private static func makeEntry(_ latex: String, fontSize: CGFloat, display: Bool, numbering: NoteMathNumberingContext) -> NoteMathLayoutEntry {
        if latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NoteMathLayoutEntry(box: NoteMathBox(), error: nil, isEmpty: true)
        }
        guard let font else {
            let failure = NoteMathParseError(message: "The math font is missing", offset: 0, length: (latex as NSString).length)
            return NoteMathLayoutEntry(box: errorBox(latex, fontSize: fontSize), error: failure, isEmpty: false)
        }
        do {
            let equation = try NoteMathParser.parseEquation(latex, display: display, numbering: numbering)
            let box = NoteMathTypesetter(font: font, baseSize: fontSize).typeset(equation, display: display)
            return NoteMathLayoutEntry(box: box, error: nil, isEmpty: false, tagGap: fontSize)
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

package struct NoteMathOutline {
    package var path: CGPath
    package var color: NoteMathInkColor
}

extension NoteMathRendering {
    package func outlines(width: CGFloat? = nil) -> [NoteMathOutline] {
        let available = max(width ?? size.width, size.width)
        let baselineY = -entry.frame.minY
        var collected = NoteMathOutlineCollector()
        collected.add(entry.box.inks, at: CGPoint(x: equationOffset(width: available) - entry.equationFrame.minX, y: baselineY))
        for (mark, frame) in zip(entry.box.tags, entry.tagFrames) {
            collected.add(mark.box.inks, at: CGPoint(x: (available - frame.maxX).rounded(), y: baselineY + mark.baseline))
        }
        return collected.outlines
    }
}

private struct NoteMathOutlineCollector {
    private(set) var outlines: [NoteMathOutline] = []
    private var current: CGMutablePath?

    mutating func add(_ inks: [NoteMathInk], at base: CGPoint) {
        for ink in inks {
            let point = CGPoint(x: base.x + ink.origin.x, y: base.y + ink.origin.y)
            guard let shape = Self.shape(of: ink.content, at: point) else { continue }
            if let last = outlines.last, Self.matches(last.color, ink.color), let mutable = current {
                mutable.addPath(shape)
            } else {
                let mutable = CGMutablePath()
                mutable.addPath(shape)
                current = mutable
                outlines.append(NoteMathOutline(path: mutable, color: ink.color))
            }
        }
    }

    private static func matches(_ first: NoteMathInkColor, _ second: NoteMathInkColor) -> Bool {
        switch (first, second) {
        case (.inherited, .inherited), (.muted, .muted), (.link, .link): return true
        case (.custom(let one), .custom(let two)): return CFEqual(one, two)
        default: return false
        }
    }

    private static func shape(of content: NoteMathInk.Content, at point: CGPoint) -> CGPath? {
        switch content {
        case .glyph(let glyph, let font):
            var move = CGAffineTransform(translationX: point.x, y: point.y)
            return CTFontCreatePathForGlyph(font, glyph, &move)
        case .rule(let size):
            return CGPath(rect: CGRect(origin: point, size: size), transform: nil)
        case .line(let line):
            let path = CGMutablePath()
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let value = attributes[kCTFontAttributeName], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
                let font = unsafeBitCast(value as CFTypeRef, to: CTFont.self)
                for index in 0..<count {
                    var move = CGAffineTransform(translationX: point.x + positions[index].x, y: point.y + positions[index].y)
                    if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], &move) { path.addPath(glyphPath) }
                }
            }
            return path.isEmpty ? nil : path
        case .segment(let vector, let width):
            let line = CGMutablePath()
            line.move(to: point)
            line.addLine(to: CGPoint(x: point.x + vector.dx, y: point.y + vector.dy))
            return line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
    }
}
