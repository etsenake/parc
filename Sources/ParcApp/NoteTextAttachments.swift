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
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            icon.draw(in: bounds)
            tint.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
