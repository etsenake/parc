import AppKit

final class NoteAtomAttachment: NSTextAttachment {
    let atom: NoteAtom?

    init(atom: NoteAtom?, cell: NoteAtomCell) {
        self.atom = atom
        super.init(data: nil, ofType: nil)
        attachmentCell = cell
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var atomCell: NoteAtomCell? { attachmentCell as? NoteAtomCell }
}

struct NoteAtomFace {
    var label: NSAttributedString
    var icon: NSImage?
    var iconTint: NSColor?
    var math: NoteMathRendering?
    var fill: NSColor?
    var stroke: NSColor?
    var horizontalPadding: CGFloat = 4
    var gap: CGFloat = 3
}

final class NoteAtomCell: NSTextAttachmentCell {
    let face: NoteAtomFace
    let textFont: NSFont
    let accessibilityText: String

    init(face: NoteAtomFace, font: NSFont, accessibilityText: String) {
        self.face = face
        self.textFont = font
        self.accessibilityText = accessibilityText
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var pillHeight: CGFloat { ceil(textFont.ascender - textFont.descender) + 2 }

    private var iconSide: CGFloat { (textFont.pointSize * 0.86).rounded() }

    private var contentWidth: CGFloat {
        var width = ceil(face.label.size().width)
        if face.icon != nil { width += iconSide + (face.label.length > 0 ? face.gap : 0) }
        return width
    }

    private static let mathPadding: CGFloat = 2

    override func cellSize() -> NSSize {
        if let math = face.math {
            return NSSize(width: ceil(math.size.width) + Self.mathPadding * 2, height: ceil(math.baseline) + ceil(math.descent))
        }
        return NSSize(width: contentWidth + face.horizontalPadding * 2, height: pillHeight)
    }

    override func cellBaselineOffset() -> NSPoint {
        if let math = face.math { return NSPoint(x: 0, y: -ceil(math.descent)) }
        return NSPoint(x: 0, y: textFont.descender - 1)
    }

    override func wantsToTrackMouse() -> Bool { false }

    override func accessibilityLabel() -> String? { accessibilityText }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView?) {}

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let flipped = controlView?.isFlipped ?? true
        let frame = cellFrame.insetBy(dx: 0.5, dy: 0)
        if let fill = face.fill {
            let pill = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height).insetBy(dx: 0, dy: 0.5)
            let path = NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4)
            fill.setFill()
            path.fill()
            if let stroke = face.stroke {
                stroke.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        if let math = face.math, let context = NSGraphicsContext.current?.cgContext {
            let x = cellFrame.minX + Self.mathPadding
            if flipped {
                let baseline = cellFrame.maxY - ceil(math.descent)
                math.drawFlipped(in: context, at: CGPoint(x: x, y: baseline - math.baseline))
            } else {
                math.draw(in: context, at: CGPoint(x: x, y: cellFrame.minY + ceil(math.descent) - math.descent))
            }
            return
        }
        var x = frame.minX + face.horizontalPadding
        let baseline = flipped ? frame.maxY + cellBaselineOffset().y : frame.minY - cellBaselineOffset().y
        if let icon = face.icon {
            let side = iconSide
            let iconRect = NSRect(x: x, y: flipped ? baseline - textFont.capHeight / 2 - side / 2 - 0.5 : baseline + textFont.capHeight / 2 - side / 2 + 0.5,
                                  width: side, height: side)
            drawIcon(icon, in: iconRect, tint: face.iconTint ?? .labelColor)
            x += side + (face.label.length > 0 ? face.gap : 0)
        }
        guard face.label.length > 0 else { return }
        let ascent = textFont.ascender
        let labelOrigin = NSPoint(x: x, y: flipped ? baseline - ascent : baseline + textFont.descender)
        face.label.draw(with: NSRect(x: labelOrigin.x, y: labelOrigin.y, width: frame.maxX - x, height: ascent - textFont.descender),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView)
    }

    private func drawIcon(_ icon: NSImage, in rect: NSRect, tint: NSColor) {
        let tinted = Self.tinted(icon, size: rect.size, tint: tint)
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    static func tinted(_ icon: NSImage, size: NSSize, tint: NSColor) -> NSImage {
        let drawing: (NSRect) -> Bool = { bounds in
            icon.draw(in: bounds)
            tint.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        guard NSGraphicsContext.current?.isDrawingToScreen == false, size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * 3).rounded(.up)),
                                         pixelsHigh: Int((size.height * 3).rounded(.up)), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: size, flipped: false, drawingHandler: drawing)
        }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage(size: size, flipped: false, drawingHandler: drawing) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        _ = drawing(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

@MainActor
enum NoteAtomRendering {
    static func attachment(for atom: NoteAtom?, font: NSFont, ink: NSColor, now: Date = Date()) -> NoteAtomAttachment {
        let face = self.face(for: atom, font: font, ink: ink, now: now)
        return NoteAtomAttachment(atom: atom, cell: NoteAtomCell(face: face, font: font, accessibilityText: accessibilityText(for: atom)))
    }

    static func face(for atom: NoteAtom?, font: NSFont, ink: NSColor, now: Date) -> NoteAtomFace {
        let labelFont = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 0.94) ?? font
        func label(_ text: String, _ color: NSColor, _ face: NSFont = labelFont) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: face, .foregroundColor: color])
        }
        guard let atom else {
            return NoteAtomFace(label: label("◇", NoteTheme.tertiaryInk), fill: NoteTheme.hoverFill)
        }
        switch atom {
        case .equation(let source):
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let math = NoteMathRenderer.render(source, fontSize: font.pointSize, color: ink, display: false)
                if !math.isEmpty, math.size.width > 0 { return NoteAtomFace(label: NSAttributedString(), math: math) }
            }
            let mono = NoteTheme.codeFont(size: (font.pointSize * 0.82).rounded())
            let text = trimmed.isEmpty ? "New equation" : source
            return NoteAtomFace(label: label(text, trimmed.isEmpty ? NoteTheme.placeholderInk : NoteTheme.codeInk, mono),
                                fill: NoteTheme.codeBackground)
        case .page(_, let title):
            return NoteAtomFace(label: label(title.isEmpty ? "Untitled" : title, NoteTheme.mentionInk),
                                icon: symbol("doc.text"), iconTint: NoteTheme.secondaryInk, fill: NoteTheme.hoverFill)
        case .link(let url, let title):
            let text = title.isEmpty ? (URL(string: url)?.host ?? url) : title
            return NoteAtomFace(label: label(text, NoteTheme.mentionInk), icon: symbol("link"),
                                iconTint: NoteTheme.secondaryInk, fill: NoteTheme.hoverFill)
        case .raw(let source):
            return NoteAtomFace(label: label(source.isEmpty ? "◇" : source, NoteTheme.tertiaryInk,
                                             NoteTheme.codeFont(size: (font.pointSize * 0.78).rounded())),
                                fill: NoteTheme.hoverFill)
        case .date(let date):
            let overdue = date.remind && isOverdue(date, now: now)
            let tint = date.remind ? (overdue ? NoteTheme.color(.text(.red)) : NoteTheme.accent) : NoteTheme.secondaryInk
            return NoteAtomFace(label: label("@" + dateLabel(date, now: now), date.remind ? tint : NoteTheme.mentionInk),
                                icon: date.remind ? symbol("bell.fill") : nil, iconTint: tint,
                                fill: date.remind ? (overdue ? NoteTheme.color(.background(.red)) : NoteTheme.inlineCodeBackground) : NoteTheme.hoverFill)
        }
    }

    static func accessibilityText(for atom: NoteAtom?) -> String {
        guard let atom else { return "Object" }
        switch atom {
        case .equation(let source): return "Equation, " + source
        case .page(_, let title): return "Page, " + (title.isEmpty ? "Untitled" : title)
        case .link(let url, let title): return "Link, " + (title.isEmpty ? url : title)
        case .date(let date): return (date.remind ? "Reminder, " : "Date, ") + dateLabel(date, now: Date())
        case .raw(let source): return source
        }
    }

    static func date(of mention: NoteDateMention, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: mention.year, month: mention.month, day: mention.day,
                                           hour: mention.hour ?? 0, minute: mention.hour == nil ? 0 : (mention.minute ?? 0)))
    }

    static func isOverdue(_ mention: NoteDateMention, now: Date, calendar: Calendar = .current) -> Bool {
        guard let start = date(of: mention, calendar: calendar) else { return false }
        if mention.includesTime { return start <= now }
        return calendar.startOfDay(for: now) >= start
    }

    static func dateLabel(_ mention: NoteDateMention, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let value = date(of: mention, calendar: calendar) else { return NoteAtom.date(mention).fallbackText }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: value)
        let distance = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let dayText: String
        switch distance {
        case 0: dayText = "Today"
        case 1: dayText = "Tomorrow"
        case -1: dayText = "Yesterday"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: value) == calendar.component(.year, from: now)
                                                         ? "MMMMd" : "yMMMMd")
            dayText = formatter.string(from: value)
        }
        guard mention.includesTime else { return dayText }
        let time = DateFormatter()
        time.calendar = calendar
        time.locale = locale
        time.timeZone = calendar.timeZone
        time.setLocalizedDateFormatFromTemplate("jmm")
        return dayText + " " + time.string(from: value)
    }

    private static var symbols: [String: NSImage] = [:]

    private static func symbol(_ name: String) -> NSImage? {
        if let cached = symbols[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        symbols[name] = image
        return image
    }
}

@MainActor
enum NotePageEquationArtwork {
    static let lightInk = NSColor(srgbRed: 0x1F / 255, green: 0x1B / 255, blue: 0x2E / 255, alpha: 1)
    static let darkInk = NSColor(srgbRed: 0xED / 255, green: 0xEB / 255, blue: 0xFA / 255, alpha: 1)
    static let scale: CGFloat = 3
    static let displayScale: CGFloat = 1.2

    static func fontSize(display: Bool) -> CGFloat {
        let body = NoteTheme.bodyFont(.standard)
        let size = NoteMathRenderer.fontSize(matching: body) * (display ? displayScale : 1)
        return (size * 4).rounded() / 4
    }

    static func svg(_ tex: String, display: Bool) -> (markup: String, size: CGSize)? {
        guard !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let fontSize = fontSize(display: display)
        let light = NoteMathRenderer.render(tex, fontSize: fontSize, color: lightInk, display: display)
        guard !light.isEmpty, light.error == nil, light.size.width > 0, light.size.height > 0 else { return nil }
        let dark = NoteMathRenderer.render(tex, fontSize: fontSize, color: darkInk, display: display)
        let aqua = NSAppearance(named: .aqua)
        guard let lightPNG = png(light.cgImage(scale: scale, appearance: aqua)),
              let darkPNG = png(dark.cgImage(scale: scale, appearance: NSAppearance(named: .darkAqua))) else { return nil }
        let width = ceil(light.size.width)
        let ascent = light.baseline, descent = light.descent
        var height = ceil(light.size.height)
        var top: CGFloat = 0
        if !display {
            let axis = fontSize * 0.25
            let half = max(ascent - axis, descent + axis)
            height = ceil(half * 2)
            top = (half - (ascent - axis)).rounded(.down)
        }
        func number(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
        let w = number(width), h = number(height)
        let imageHeight = number(light.size.height), imageWidth = number(light.size.width), y = number(top)
        let markup = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"" + w + "\" height=\"" + h
            + "\" viewBox=\"0 0 " + w + " " + h + "\"><style>.d{display:none}@media screen and (prefers-color-scheme:dark){.l{display:none}.d{display:inline}}</style>"
            + "<image class=\"l\" x=\"0\" y=\"" + y + "\" width=\"" + imageWidth + "\" height=\"" + imageHeight + "\" xlink:href=\"data:image/png;base64,"
            + lightPNG + "\"/><image class=\"d\" x=\"0\" y=\"" + y + "\" width=\"" + imageWidth + "\" height=\"" + imageHeight
            + "\" xlink:href=\"data:image/png;base64," + darkPNG + "\"/></svg>"
        return (markup, CGSize(width: width, height: height))
    }

    static func url(_ tex: String, display: Bool) -> URL? {
        guard let svg = svg(tex, display: display) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$'()*+,;=:@/")
        guard let encoded = svg.markup.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "data:image/svg+xml;charset=utf-8," + encoded)
    }

    private static func png(_ image: CGImage?) -> String? {
        guard let image else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.base64EncodedString()
    }
}
