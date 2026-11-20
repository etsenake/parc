import AppKit

@MainActor
class NoteTextView: NSTextView {
    weak var host: NoteTextHost?
    weak var editor: NotePageEditor?
    var placeholder: String? { didSet { needsDisplay = true } }
    var crossBlockHighlight: Range<Int>? { didSet { if oldValue != crossBlockHighlight { needsDisplay = true } } }
    private(set) var noteText = NoteText()

    convenience init() {
        self.init(usingTextLayoutManager: false)
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false
    }

    func apply(_ text: NoteText, selection: Range<Int>?) {
        noteText = text
        textStorage?.setAttributedString(NSAttributedString(string: text.string))
        if let selection { selectedOffsets = selection }
    }

    var selectedOffsets: Range<Int> {
        get {
            let range = selectedRange()
            return range.location..<(range.location + range.length)
        }
        set {
            let length = (string as NSString).length
            let lower = min(max(0, newValue.lowerBound), length), upper = min(max(lower, newValue.upperBound), length)
            setSelectedRange(NSRange(location: lower, length: upper - lower))
        }
    }

    func caretRect(at offset: Int) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let length = (string as NSString).length
        let clamped = min(max(0, offset), length)
        if length == 0 {
            let height = font.map { layoutManager.defaultLineHeight(for: $0) } ?? 20
            return NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y, width: 1, height: height)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(clamped, length - 1))
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        if clamped == length { rect.origin.x = rect.maxX }
        rect.size.width = 1
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    func offset(at point: NSPoint) -> Int {
        guard let layoutManager, let textContainer else { return 0 }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return min((string as NSString).length, index + (fraction > 0.5 ? 1 : 0))
    }

    func selectionRects(for range: Range<Int>) -> [NSRect] {
        guard let layoutManager, let textContainer, !range.isEmpty else { return [] }
        var rects: [NSRect] = []
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.lowerBound, length: range.count), actualCharacterRange: nil)
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
        }
        return rects
    }

    func isOnFirstLine(_ offset: Int) -> Bool {
        abs(caretRect(at: offset).minY - caretRect(at: 0).minY) < 1
    }

    func isOnLastLine(_ offset: Int) -> Bool {
        abs(caretRect(at: offset).minY - caretRect(at: (string as NSString).length).minY) < 1
    }

    func offset(nearestX x: CGFloat, onFirstLine: Bool) -> Int {
        let line = caretRect(at: onFirstLine ? 0 : (string as NSString).length)
        return offset(at: NSPoint(x: x, y: line.midY))
    }
}
