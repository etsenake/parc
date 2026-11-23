import AppKit
import ParcCore
import ParcNotes

@MainActor
final class EaselInlineAttachment: NSTextAttachment {
    let inline: EaselRichText.Inline
    init(inline: EaselRichText.Inline) {
        self.inline = inline
        super.init(data: nil, ofType: nil)
        attachmentCell = EaselInlineCell(inline: inline)
    }
    required init?(coder: NSCoder) { return nil }
}

@MainActor
final class EaselInlineCell: NSTextAttachmentCell {
    static var epoch = 0
    private struct Key: Equatable {
        var font: String
        var size: CGFloat
        var ink: NSColor
        var epoch: Int
    }
    let inline: EaselRichText.Inline
    private var resolvedCell: NoteAtomCell?
    private var key: Key?
    private lazy var emojiImage: NSImage? = inline.image.flatMap(NSImage.init(data:))

    init(inline: EaselRichText.Inline) {
        self.inline = inline
        super.init(textCell: "")
    }
    required init(coder: NSCoder) { fatalError("Inline cells are restored from validated runs") }
    override func copy(with zone: NSZone? = nil) -> Any { self }

    func atomCell(font: NSFont, ink: NSColor) -> NoteAtomCell {
        let next = Key(font: font.fontName, size: font.pointSize, ink: ink, epoch: Self.epoch)
        if let resolvedCell, key == next { return resolvedCell }
        var face = NoteAtomRendering.face(for: inline.atom, font: font, ink: ink, now: Date())
        if inline.kind == .emoji, let emojiImage { face = NoteAtomFace(label: NSAttributedString(), image: emojiImage) }
        let cell = NoteAtomCell(face: face, font: font, accessibilityText: NoteAtomRendering.accessibilityText(for: inline.atom))
        resolvedCell = cell
        key = next
        return cell
    }

    private func atomCell(in storage: NSTextStorage?, at index: Int) -> NoteAtomCell {
        guard let storage, index >= 0, index < storage.length else {
            return resolvedCell ?? atomCell(font: EaselTextAppearance.font(.init()), ink: .labelColor)
        }
        let attributes = storage.attributes(at: index, effectiveRange: nil)
        let font = attributes[.font] as? NSFont ?? EaselTextAppearance.font(.init())
        return atomCell(font: font, ink: attributes[.foregroundColor] as? NSColor ?? .labelColor)
    }

    override func cellSize() -> NSSize {
        MainActor.assumeIsolated { (resolvedCell ?? atomCell(in: nil, at: 0)).cellSize() }
    }

    override func cellBaselineOffset() -> NSPoint {
        MainActor.assumeIsolated { (resolvedCell ?? atomCell(in: nil, at: 0)).cellBaselineOffset() }
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        MainActor.assumeIsolated {
            let cell = atomCell(in: textContainer.layoutManager?.textStorage, at: charIndex)
            return NSRect(origin: cell.cellBaselineOffset(), size: cell.cellSize())
        }
    }

    override func wantsToTrackMouse() -> Bool { false }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView?) {}

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        MainActor.assumeIsolated { (resolvedCell ?? atomCell(in: nil, at: 0)).draw(withFrame: cellFrame, in: controlView) }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        MainActor.assumeIsolated {
            atomCell(in: layoutManager.textStorage, at: charIndex).draw(withFrame: cellFrame, in: controlView)
        }
    }

    override func accessibilityLabel() -> String? {
        MainActor.assumeIsolated { NoteAtomRendering.accessibilityText(for: inline.atom) }
    }
}

@MainActor
enum EaselInlineText {
    static let datesChanged = Notification.Name("EaselInlineText.datesChanged")
    static func character(_ inline: EaselRichText.Inline, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attrs = attributes
        attrs.removeValue(forKey: .link)
        attrs[.attachment] = EaselInlineAttachment(inline: inline)
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    static func inline(at index: Int, in value: NSAttributedString) -> EaselRichText.Inline? {
        guard index >= 0, index < value.length else { return nil }
        return (value.attribute(.attachment, at: index, effectiveRange: nil) as? EaselInlineAttachment)?.inline
    }

    static func hasInlines(_ value: NSAttributedString) -> Bool {
        var found = false
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { object, _, stop in
            if object is EaselInlineAttachment { found = true; stop.pointee = true }
        }
        return found
    }

    static func readable(_ value: NSAttributedString, now: Date = Date()) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        var places: [(NSRange, EaselRichText.Inline)] = []
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { object, range, _ in
            if let inline = (object as? EaselInlineAttachment)?.inline { places.append((range, inline)) }
        }
        var orphans: [NSRange] = []
        (value.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: value.length), options: .byComposedCharacterSequences) { piece, range, _, _ in
            if piece == "\u{FFFC}", value.attribute(.attachment, at: range.location, effectiveRange: nil) == nil { orphans.append(range) }
        }
        for range in orphans.reversed() { result.deleteCharacters(in: range) }
        for (original, inline) in places.reversed() {
            let range = NSRange(location: original.location - orphans.filter { $0.location < original.location }.count, length: original.length)
            var attrs = value.attributes(at: original.location, effectiveRange: nil)
            attrs.removeValue(forKey: .attachment)
            if inline.kind == .note, let url = inline.noteURL { attrs[.link] = url }
            result.replaceCharacters(in: range, with: NSAttributedString(string: inline.readable(now: now), attributes: attrs))
        }
        return result
    }

    static func spoken(_ text: String, rich: EaselRichText?) -> String {
        EaselChecklistText.spoken(inlineSpoken(text, rich: rich))
    }

    private static func inlineSpoken(_ text: String, rich: EaselRichText?) -> String {
        guard let rich, rich.runs.contains(where: { $0.attributes.isAtomic }) else { return text.replacingOccurrences(of: "\u{FFFC}", with: "") }
        let source = text as NSString
        var result = "", location = 0
        for run in rich.runs where run.attributes.isAtomic && run.location >= location && run.location < source.length {
            result += source.substring(with: NSRange(location: location, length: run.location - location)).replacingOccurrences(of: "\u{FFFC}", with: "")
            if let inline = run.attributes.inline { result += NoteAtomRendering.accessibilityText(for: inline.atom) }
            location = run.location + run.length
        }
        if location < source.length { result += source.substring(from: location).replacingOccurrences(of: "\u{FFFC}", with: "") }
        return result
    }

    static func refreshDates() { EaselInlineCell.epoch &+= 1 }

    static func exportText(_ attributes: [NSAttributedString.Key: Any], _ raw: String, images: Bool) -> String {
        guard let inline = (attributes[.attachment] as? EaselInlineAttachment)?.inline else {
            return raw.replacingOccurrences(of: "\u{FFFC}", with: "")
        }
        if images, exportArtwork(inline) != nil { return "" }
        return inline.readable(now: Date())
    }

    static func hasArtwork(_ inline: EaselRichText.Inline) -> Bool {
        switch inline.kind {
        case .emoji: return inline.image != nil
        case .equation: return !(inline.tex ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .note, .date: return false
        }
    }

    private static var equationArtwork: [String: EaselVectorImage?] = [:]

    static func exportArtwork(_ inline: EaselRichText.Inline) -> EaselVectorImage? {
        if inline.kind == .equation, let tex = inline.tex, let cached = equationArtwork[tex] { return cached }
        let made = makeArtwork(inline)
        if inline.kind == .equation, let tex = inline.tex {
            if equationArtwork.count >= 256 { equationArtwork.removeAll() }
            equationArtwork[tex] = made
        }
        return made
    }

    private static func makeArtwork(_ inline: EaselRichText.Inline) -> EaselVectorImage? {
        guard hasArtwork(inline) else { return nil }
        switch inline.kind {
        case .emoji:
            return inline.image.map { EaselVectorImage(data: $0, mimeType: "image/png") }
        case .equation:
            guard let tex = inline.tex, let svg = NotePageEquationArtwork.svg(tex, display: false) else { return nil }
            return EaselVectorImage(data: Data(svg.markup.utf8), mimeType: "image/svg+xml")
        case .note, .date:
            return nil
        }
    }

    static func exportImages(_ layout: EaselTextLayout.Layout, offset: CGPoint) -> [EaselVectorInlineImage] {
        let storage = layout.storage, manager = layout.manager, container = layout.container
        var result: [EaselVectorInlineImage] = []
        let shown = manager.characterRange(forGlyphRange: manager.glyphRange(for: container), actualGlyphRange: nil)
        storage.enumerateAttribute(.attachment, in: shown) { object, range, _ in
            guard let inline = (object as? EaselInlineAttachment)?.inline,
                  let image = exportArtwork(inline) else { return }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let box = manager.boundingRect(forGlyphRange: glyphs, in: container)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return }
            result.append(EaselVectorInlineImage(x: Double(offset.x + layout.inset.width + box.minX), y: Double(offset.y + layout.inset.height + box.minY),
                                                 width: Double(box.width), height: Double(box.height), image: image))
        }
        return result
    }
}
