import AppKit

@MainActor
final class NoteSelectionCanvasLayout: NoteSelectionLayout {
    unowned let editor: NotePageEditor
    var upstream: NotePosition?
    private var cachedItems: [NoteSelectionItem]?

    init(editor: NotePageEditor) {
        self.editor = editor
    }

    private var canvas: NotePageCanvasView { editor.canvas }

    func invalidate() { cachedItems = nil }

    var items: [NoteSelectionItem] {
        if let cachedItems { return cachedItems }
        let page = editor.session.page
        var blocks: [NoteBlockID: NoteBlock] = [:]
        for block in page.allBlocks() { blocks[block.id] = block }
        let built = page.flattened().compactMap { flat -> NoteSelectionItem? in
            guard let block = blocks[flat.id] else { return nil }
            return NoteSelectionItem(id: flat.id, parent: flat.parent, depth: flat.depth,
                                     role: Self.role(for: block, view: canvas.existingBlockView(for: flat.id)),
                                     frame: canvas.frame(of: flat.id) ?? .zero)
        }
        cachedItems = built
        return built
    }

    static func role(for block: NoteBlock, view: NoteBlockView?) -> NoteSelectionRole {
        switch block.kind {
        case .columns: return .layout
        case .column: return .column
        case .divider, .tableOfContents: return .decoration
        default:
            if let view { return view.textHost(for: .body) != nil ? .text : .object }
            switch block.kind {
            case .paragraph, .heading, .bulletedItem, .numberedItem, .todo, .toggle, .quote, .callout, .code, .html, .raw:
                return .text
            default:
                return .object
            }
        }
    }

    func host(for position: NotePosition, materialize: Bool = false) -> NoteTextHost? {
        if let host = canvas.existingBlockView(for: position.block)?.textHost(for: position.field) { return host }
        guard materialize, editor.session.page.block(position.block) != nil else { return nil }
        return canvas.textHost(for: position)
    }

    func textView(for position: NotePosition, materialize: Bool = false) -> NoteTextView? {
        host(for: position, materialize: materialize)?.textView
    }

    private func string(of position: NotePosition) -> NSString {
        (editor.session.page.text(of: position)?.string ?? "") as NSString
    }

    func length(of position: NotePosition) -> Int {
        editor.session.page.text(of: position)?.length ?? 0
    }

    static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029 || character == 0x85
    }

    func caretRect(in view: NoteTextView, offset: Int, upstream: Bool) -> NSRect {
        guard let layoutManager = view.layoutManager, let container = view.textContainer else { return .zero }
        layoutManager.ensureLayout(for: container)
        let text = view.string as NSString
        let length = text.length
        let clamped = min(max(0, offset), length)
        let origin = view.textContainerOrigin
        let lineHeight = view.font.map { layoutManager.defaultLineHeight(for: $0) } ?? 20
        if length == 0 || (clamped == length && Self.isNewline(text.character(at: length - 1))) {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 {
                return NSRect(x: extra.minX + origin.x, y: extra.minY + origin.y, width: 1, height: extra.height)
            }
            if length == 0 { return NSRect(x: origin.x, y: origin.y, width: 1, height: lineHeight) }
        }
        let trailing = clamped == length || (upstream && clamped > 0 && !Self.isNewline(text.character(at: clamped - 1)))
        let character = trailing ? clamped - 1 : clamped
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return NSRect(x: (trailing ? box.maxX : box.minX) + origin.x, y: line.minY + origin.y, width: 1, height: line.height)
    }

    func caretRect(at position: NotePosition) -> NSRect? {
        guard let view = textView(for: position) else { return nil }
        return view.convert(caretRect(in: view, offset: position.offset, upstream: upstream == position), to: canvas)
    }

    func offset(in view: NoteTextView, at local: NSPoint) -> (offset: Int, upstream: Bool) {
        guard let layoutManager = view.layoutManager, let container = view.textContainer else { return (0, false) }
        layoutManager.ensureLayout(for: container)
        let text = view.string as NSString
        let length = text.length
        guard length > 0 else { return (0, false) }
        let point = NSPoint(x: local.x - view.textContainerOrigin.x, y: local.y - view.textContainerOrigin.y)
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0, point.y >= extra.minY { return (length, false) }
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        var offset = min(length, index + (fraction > 0.5 ? 1 : 0))
        let glyph = min(layoutManager.glyphIndex(for: point, in: container), max(0, layoutManager.numberOfGlyphs - 1))
        var glyphs = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphs)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let end = NSMaxRange(characters)
        guard end > characters.location, offset >= end, end < length || Self.isNewline(text.character(at: end - 1)) else {
            return (offset, false)
        }
        if Self.isNewline(text.character(at: end - 1)) {
            offset = end - 1
            return (offset, false)
        }
        return (end, true)
    }

    func offset(in id: NoteBlockID, at canvasPoint: NSPoint, field: NoteTextField = .body) -> Int? {
        guard let view = textView(for: NotePosition(id, 0, field: field)) else { return nil }
        let result = offset(in: view, at: view.convert(canvasPoint, from: canvas))
        upstream = result.upstream ? NotePosition(id, result.offset, field: field) : nil
        return result.offset
    }

    private func localX(_ x: CGFloat, in view: NSView) -> CGFloat {
        view.convert(NSPoint(x: x, y: 0), from: canvas).x
    }

    func caretX(at position: NotePosition) -> CGFloat? {
        guard let view = textView(for: position, materialize: true) else { return nil }
        let rect = caretRect(in: view, offset: position.offset, upstream: upstream == position)
        return view.convert(rect, to: canvas).minX
    }

    func lineOffset(from position: NotePosition, up: Bool, x: CGFloat) -> Int? {
        guard let view = textView(for: position, materialize: true) else { return nil }
        let length = (view.string as NSString).length
        let current = caretRect(in: view, offset: position.offset, upstream: upstream == position)
        let first = caretRect(in: view, offset: 0, upstream: false)
        let last = caretRect(in: view, offset: length, upstream: false)
        if up && current.minY <= first.minY + 0.5 { return nil }
        if !up && current.minY >= last.minY - 0.5 { return nil }
        let y = up ? current.minY - 1 : current.maxY + 1
        let result = offset(in: view, at: NSPoint(x: localX(x, in: view), y: y))
        upstream = result.upstream ? NotePosition(position.block, result.offset, field: position.field) : nil
        return result.offset
    }

    func entryOffset(in block: NoteBlockID, x: CGFloat, fromAbove: Bool) -> Int {
        let start = NotePosition(block, 0)
        guard let view = textView(for: start, materialize: true) else { return fromAbove ? 0 : length(of: start) }
        let length = (view.string as NSString).length
        let line = caretRect(in: view, offset: fromAbove ? 0 : length, upstream: false)
        let result = offset(in: view, at: NSPoint(x: localX(x, in: view), y: line.midY))
        upstream = result.upstream ? NotePosition(block, result.offset) : nil
        return result.offset
    }

    func characterOffset(from position: NotePosition, forward: Bool) -> Int? {
        let text = string(of: position)
        let offset = min(max(0, position.offset), text.length)
        if forward {
            guard offset < text.length else { return nil }
            return NSMaxRange(text.rangeOfComposedCharacterSequence(at: offset))
        }
        guard offset > 0 else { return nil }
        return text.rangeOfComposedCharacterSequence(at: offset - 1).location
    }

    func wordOffset(from position: NotePosition, forward: Bool) -> Int? {
        let text = string(of: position)
        let offset = min(max(0, position.offset), text.length)
        if forward ? offset >= text.length : offset <= 0 { return nil }
        let next = NSAttributedString(string: text as String).nextWord(from: offset, forward: forward)
        return next == offset ? nil : next
    }

    func paragraphOffset(from position: NotePosition, forward: Bool) -> Int? {
        let text = string(of: position)
        var offset = min(max(0, position.offset), text.length)
        if forward {
            guard offset < text.length else { return nil }
            if Self.isNewline(text.character(at: offset)) { offset += 1 }
            while offset < text.length, !Self.isNewline(text.character(at: offset)) { offset += 1 }
        } else {
            guard offset > 0 else { return nil }
            if Self.isNewline(text.character(at: offset - 1)) { offset -= 1 }
            while offset > 0, !Self.isNewline(text.character(at: offset - 1)) { offset -= 1 }
        }
        return offset
    }

    func paragraphBounds(at position: NotePosition) -> Range<Int> {
        let text = string(of: position)
        let offset = min(max(0, position.offset), text.length)
        let range = text.paragraphRange(for: NSRange(location: offset, length: 0))
        var end = NSMaxRange(range)
        if end > range.location && Self.isNewline(text.character(at: end - 1)) { end -= 1 }
        return range.location..<max(range.location, end)
    }

    func lineEdgeOffset(from position: NotePosition, forward: Bool) -> Int {
        let total = length(of: position)
        guard let view = textView(for: position, materialize: true), let layoutManager = view.layoutManager,
              let container = view.textContainer else { return forward ? total : 0 }
        layoutManager.ensureLayout(for: container)
        let text = view.string as NSString
        let length = text.length
        let offset = min(max(0, position.offset), length)
        guard length > 0 else { return 0 }
        if offset == length && Self.isNewline(text.character(at: length - 1)) { return length }
        let trailing = offset == length || (upstream == position && offset > 0 && !Self.isNewline(text.character(at: offset - 1)))
        let glyph = layoutManager.glyphIndexForCharacter(at: trailing ? offset - 1 : offset)
        var glyphs = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &glyphs)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard forward else { return characters.location }
        var end = NSMaxRange(characters)
        if end > characters.location && Self.isNewline(text.character(at: end - 1)) {
            end -= 1
        } else if end < length {
            upstream = NotePosition(position.block, end, field: position.field)
        }
        return end
    }

    func wordRange(at position: NotePosition) -> Range<Int> {
        let text = string(of: position)
        guard text.length > 0 else { return 0..<0 }
        let offset = min(max(0, position.offset), text.length)
        let probe = offset == text.length ? offset - 1 : offset
        let range = NSAttributedString(string: text as String).doubleClick(at: probe)
        guard range.location != NSNotFound else { return offset..<offset }
        return range.location..<NSMaxRange(range)
    }

    func selectionRects(for position: NotePosition, range: Range<Int>) -> [NSRect] {
        guard let view = textView(for: position) else { return [] }
        if range.isEmpty {
            return [view.convert(caretRect(in: view, offset: range.lowerBound, upstream: upstream == position), to: canvas)]
        }
        return view.selectionRects(for: range).map { view.convert($0, to: canvas) }
    }
}
