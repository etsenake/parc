import AppKit

@MainActor
package enum NoteEquationArtwork {
    static let placeholderText = "Add a TeX equation"
    static let horizontalInset: CGFloat = 12
    static let placeholderSymbol = "x.squareroot"

    static var errorFont: NSFont { NoteCodeFont.code(size: 13) }

    package static func drawPlaceholder(in bounds: NSRect, font: NSFont, fill: NSColor) {
        let radius = NoteTheme.blockRadius
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let ink = NoteTheme.secondaryInk
        let iconSide: CGFloat = 18
        var x = bounds.minX + 14
        if let image = NoteIconRenderer.symbol(placeholderSymbol, pointSize: 15, weight: .medium) {
            NoteIconRenderer.drawTemplate(image, centeredIn: NSRect(x: x, y: bounds.minY, width: iconSide, height: bounds.height), tint: ink)
        }
        x += iconSide + 10
        let text = NSAttributedString(string: placeholderText, attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        text.draw(at: NSPoint(x: x, y: bounds.minY + ((bounds.height - size.height) / 2).rounded()))
    }

    package static func drawError(source: String, in bounds: NSRect) {
        let font = errorFont
        let flattened = source.split(whereSeparator: \.isNewline).joined(separator: " ")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: flattened, attributes: [.font: font, .foregroundColor: NoteTheme.tertiaryInk,
                                                                       .paragraphStyle: paragraph])
        let glyph: CGFloat = 13, gap: CGFloat = 8
        let available = bounds.width - horizontalInset * 2 - glyph - gap
        let width = max(0, min(available, ceil(text.size().width)))
        let total = glyph + gap + width
        var x = bounds.minX + ((bounds.width - total) / 2).rounded()
        let height = ceil(font.ascender - font.descender + font.leading)
        if let image = NoteIconRenderer.symbol("exclamationmark.triangle.fill", pointSize: 11, weight: .semibold) {
            NoteIconRenderer.drawTemplate(image, centeredIn: NSRect(x: x, y: bounds.minY, width: glyph, height: bounds.height),
                                          tint: NoteTheme.destructiveInk.withAlphaComponent(0.8))
        }
        x += glyph + gap
        text.draw(with: NSRect(x: x, y: bounds.minY + ((bounds.height - height) / 2).rounded(), width: width, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
