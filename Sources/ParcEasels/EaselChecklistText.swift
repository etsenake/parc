import AppKit
import ParcCore
import ParcNotes

@MainActor
enum EaselChecklistText {
    package struct Item {
        var paragraph: NSRange
        var prefix: NSRange
        var marker: EaselChecklist.Marker
        var markerCharacter: NSRange { NSRange(location: prefix.location + 1, length: max(0, prefix.length - 2)) }
        var exclusion: NSRange { marker == .divider ? paragraph : prefix }
    }

    struct Parts {
        var exclusions: [NSRange] = []
        var dimmed: [NSRange] = []
        var rules: [EaselVectorRule] = []
        var boxes: [EaselVectorCheckbox] = []
    }

    static let doneAlpha: CGFloat = 0.45

    static func items(in storage: NSAttributedString, range: NSRange) -> [Item] {
        let text = storage.string as NSString
        guard text.length > 0, range.location != NSNotFound else { return [] }
        var position = min(range.location, text.length - 1)
        let end = min(NSMaxRange(range), text.length)
        var result: [Item] = []
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: position, length: 0))
            if let item = item(in: storage, paragraph: paragraph) { result.append(item) }
            position = NSMaxRange(paragraph)
        } while position < end && position < text.length
        return result
    }

    static func item(in storage: NSAttributedString, paragraph: NSRange) -> Item? {
        guard paragraph.length > 0, paragraph.location < storage.length,
              let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
              let list = style.textLists.last, let marker = EaselParagraphEditing.checklistMarker(list) else { return nil }
        let prefix = EaselParagraphEditing.markerRange(storage, paragraph: paragraph)
        guard prefix.length == 3 else { return nil }
        return Item(paragraph: paragraph, prefix: prefix, marker: marker)
    }

    static func hasChecklist(_ rich: EaselRichText?) -> Bool {
        rich?.runs.contains { run in
            run.attributes.paragraph?.lists.contains { EaselChecklist.marker($0.marker)?.isItem == true } == true
        } == true
    }

    static func item(at point: NSPoint, manager: NSLayoutManager, storage: NSAttributedString) -> Item? {
        guard let manager = manager as? EaselChecklistLayoutManager else { return nil }
        return items(in: storage, range: NSRange(location: 0, length: storage.length)).first { item in
            item.marker.isItem && manager.boxRect(for: item)?.insetBy(dx: -4, dy: -4).contains(point) == true
        }
    }

    static func trimmed(_ range: NSRange, excluding exclusions: [NSRange]) -> NSRange? {
        var result = range
        for exclusion in exclusions {
            let overlap = NSIntersectionRange(result, exclusion)
            guard overlap.length > 0 else { continue }
            if overlap.length == result.length { return nil }
            if overlap.location == result.location {
                result = NSRange(location: NSMaxRange(overlap), length: NSMaxRange(result) - NSMaxRange(overlap))
            } else {
                result.length = overlap.location - result.location
            }
        }
        return result
    }

    static func exportParts(manager: NSLayoutManager, storage: NSAttributedString, offset: CGSize) -> Parts {
        guard let manager = manager as? EaselChecklistLayoutManager, storage.length > 0 else { return Parts() }
        var parts = Parts()
        for item in items(in: storage, range: NSRange(location: 0, length: storage.length)) {
            parts.exclusions.append(item.exclusion)
            if item.marker == .divider {
                if let rule = manager.ruleSegment(for: item) {
                    parts.rules.append(EaselVectorRule(x1: Double(offset.width + rule.minX), x2: Double(offset.width + rule.maxX),
                                                       y: Double(offset.height + rule.midY)))
                }
                continue
            }
            if item.marker == .done {
                parts.dimmed.append(NSRange(location: NSMaxRange(item.prefix), length: NSMaxRange(item.paragraph) - NSMaxRange(item.prefix)))
            }
            if let box = manager.boxRect(for: item) {
                parts.boxes.append(EaselVectorCheckbox(x: Double(offset.width + box.minX), y: Double(offset.height + box.minY),
                                                       size: Double(box.width), checked: item.marker == .done))
            }
        }
        return parts
    }

    static func spoken(_ text: String) -> String {
        guard text.contains("\t") else { return text }
        var value = text
        for (marker, words) in [(EaselChecklist.openMarker, "To-do, "), (EaselChecklist.doneMarker, "Done, "), (EaselChecklist.dividerMarker, "Divider")] {
            value = value.replacingOccurrences(of: "(?m)^\t" + marker + "\t", with: words, options: .regularExpression)
        }
        return value
    }

    static func pop(in view: NSView, rect: NSRect, manager: EaselChecklistLayoutManager?, marker: Int) {
        guard !NoteAnimation.reduceMotion, view.window != nil, rect.width > 0, rect.height > 0 else { return }
        let overlay = EaselChecklistPopView(frame: rect)
        var glyph: NSImage?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { glyph = NoteTheme.todoGlyph(checked: true) }
        overlay.image = glyph
        manager?.hiddenMarker = marker
        view.needsDisplay = true
        view.addSubview(overlay)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak view, weak overlay, weak manager] in
            MainActor.assumeIsolated {
                overlay?.removeFromSuperview()
                manager?.hiddenMarker = nil
                view?.needsDisplay = true
            }
        }
        NoteAnimation.pop(overlay)
        CATransaction.commit()
    }
}

private final class EaselChecklistPopView: NSView {
    var image: NSImage?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class EaselChecklistLayoutManager: NSLayoutManager {
    var hiddenMarker: Int?
    private var dimmed = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else { super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return }
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let items = EaselChecklistText.items(in: storage, range: shown)
        guard !items.isEmpty else { super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return }
        var cursor = shown.location
        func draw(to limit: Int, dimmed value: Bool) {
            let end = min(limit, NSMaxRange(shown))
            guard end > cursor else { return }
            let glyphs = glyphRange(forCharacterRange: NSRange(location: cursor, length: end - cursor), actualCharacterRange: nil)
            cursor = end
            guard glyphs.length > 0 else { return }
            dimmed = value
            drawPiece(glyphs, at: origin)
            dimmed = false
        }
        for item in items {
            let hidden = item.marker == .divider ? item.paragraph : item.markerCharacter
            draw(to: hidden.location, dimmed: false)
            cursor = max(cursor, min(NSMaxRange(hidden), NSMaxRange(shown)))
            if item.marker == .done { draw(to: NSMaxRange(item.paragraph), dimmed: true) }
        }
        draw(to: NSMaxRange(shown), dimmed: false)
        for item in items {
            if item.marker == .divider {
                guard let rule = ruleSegment(for: item) else { continue }
                NoteTheme.separator.setFill()
                NSBezierPath(rect: rule.offsetBy(dx: origin.x, dy: origin.y)).fill()
            } else if hiddenMarker != item.markerCharacter.location, let box = boxRect(for: item) {
                NoteTheme.todoGlyph(checked: item.marker == .done, pointSize: box.height)?
                    .draw(in: box.offsetBy(dx: origin.x, dy: origin.y), from: .zero, operation: .sourceOver, fraction: 1,
                          respectFlipped: true, hints: nil)
            }
        }
    }

    private func drawPiece(_ glyphs: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count glyphCount: Int, font: NSFont,
                               textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any] = [:], in graphicsContext: CGContext) {
        guard dimmed else {
            super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font, textMatrix: textMatrix,
                               attributes: attributes, in: graphicsContext)
            return
        }
        let ink = (attributes[.foregroundColor] as? NSColor) ?? NSColor.labelColor
        let faded = ink.withAlphaComponent(ink.alphaComponent * EaselChecklistText.doneAlpha)
        var muted = attributes
        muted[.foregroundColor] = faded
        graphicsContext.saveGState()
        graphicsContext.setFillColor(faded.cgColor)
        super.showCGGlyphs(glyphs, positions: positions, count: glyphCount, font: font, textMatrix: textMatrix,
                           attributes: muted, in: graphicsContext)
        graphicsContext.restoreGState()
    }

    func boxRect(for item: EaselChecklistText.Item) -> NSRect? {
        guard item.marker.isItem, let storage = textStorage else { return nil }
        let character = item.markerCharacter
        guard character.length > 0, NSMaxRange(character) <= storage.length else { return nil }
        let glyphs = glyphRange(forCharacterRange: character, actualCharacterRange: nil)
        guard glyphs.length > 0, NSMaxRange(glyphs) <= numberOfGlyphs,
              let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let place = location(forGlyphAt: glyphs.location)
        let span = boundingRect(forGlyphRange: glyphs, in: container)
        let font = (storage.attribute(.font, at: character.location, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        let side = CGFloat(EaselChecklist.boxSide(fontSize: Double(font.pointSize)))
        let centre = line.minY + place.y - font.capHeight / 2
        let rect = NSRect(x: span.maxX - side, y: centre - side / 2, width: side, height: side)
        return rect.origin.x.isFinite && rect.origin.y.isFinite ? rect : nil
    }

    func ruleSegment(for item: EaselChecklistText.Item) -> NSRect? {
        guard item.marker == .divider, let storage = textStorage else { return nil }
        let character = item.markerCharacter
        guard character.length > 0, NSMaxRange(character) <= storage.length else { return nil }
        let glyphs = glyphRange(forCharacterRange: character, actualCharacterRange: nil)
        guard glyphs.length > 0, NSMaxRange(glyphs) <= numberOfGlyphs,
              let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return nil }
        let line = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let used = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let padding = container.lineFragmentPadding
        let width = line.width - padding * 2
        guard width > 0 else { return nil }
        return NSRect(x: line.minX + padding, y: (used.midY - 0.5).rounded(), width: width, height: 1)
    }
}

extension EaselParagraphEditing {
    struct ChecklistToggle {
        var edit: Edit
        var checked: Bool
        var markers: [Int]
    }

    static func toggleChecklist(_ original: NSAttributedString, selections: [NSRange],
                                typing: [NSAttributedString.Key: Any]) -> ChecklistToggle? {
        var paragraphs: [NSRange] = []
        for selection in selections {
            for range in ranges(original.string, selection: selection) where !paragraphs.contains(range) { paragraphs.append(range) }
        }
        paragraphs.sort { $0.location < $1.location }
        let items = paragraphs.compactMap { EaselChecklistText.item(in: original, paragraph: $0) }.filter { $0.marker.isItem }
        guard let first = selections.first, !items.isEmpty else { return nil }
        let target: EaselChecklist.Marker = items.contains { $0.marker == .open } ? .done : .open
        var edit = Edit(text: NSMutableAttributedString(attributedString: original), selection: first, typing: typing,
                        additionalSelections: Array(selections.dropFirst()))
        var markers: [Int] = []
        for item in items.reversed() where item.marker != target {
            let paragraph = style(edit.text.attributes(at: item.paragraph.location, effectiveRange: nil))
            guard let list = paragraph.textLists.last else { continue }
            paragraph.textLists = Array(paragraph.textLists.dropLast())
                + [NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: EaselChecklist.value(target)), options: Int(list.listOptions.rawValue))]
            edit.text.addAttribute(.paragraphStyle, value: paragraph, range: item.paragraph)
            var attrs = edit.text.attributes(at: item.markerCharacter.location, effectiveRange: nil)
            attrs[.paragraphStyle] = paragraph
            replace(&edit, range: item.markerCharacter, with: NSAttributedString(string: EaselChecklist.value(target), attributes: attrs))
            markers.append(item.markerCharacter.location)
        }
        guard !markers.isEmpty else { return nil }
        return ChecklistToggle(edit: edit, checked: target == .done, markers: markers.sorted())
    }

    static func divider(_ original: NSAttributedString, selection: NSRange, typing: [NSAttributedString.Key: Any],
                        base: EaselTextStyle, bodyPointSize: CGFloat? = nil) -> Edit? {
        guard let range = ranges(original.string, selection: NSRange(location: selection.location, length: 0)).first else { return nil }
        let text = original.string as NSString
        var edit = Edit(text: NSMutableAttributedString(attributedString: original), selection: selection, typing: typing)
        let attrs = attributes(edit, at: range)
        var plain = formatted(attrs, kind: .text, base: base, bodyPointSize: bodyPointSize)
        for key in [NSAttributedString.Key.link, .backgroundColor, .underlineStyle, .strikethroughStyle, .attachment] { plain.removeValue(forKey: key) }
        var rule = plain
        let paragraph = style(plain)
        paragraph.textLists = [NSTextList(markerFormat: dividerMarker, options: 0)]
        paragraph.firstLineHeadIndent = 0; paragraph.headIndent = 0
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 16), NSTextTab(textAlignment: .left, location: 24)]
        rule[.paragraphStyle] = paragraph
        let prefix = markerRange(original, paragraph: range)
        let hasNewline = range.length > 0 && text.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil
        let contentEnd = hasNewline ? NSMaxRange(range) - 1 : NSMaxRange(range)
        let content = text.substring(with: NSRange(location: NSMaxRange(prefix), length: max(0, contentEnd - NSMaxRange(prefix))))
        let line = NSAttributedString(string: EaselChecklist.prefix(.divider), attributes: rule)
        let ending = NSAttributedString(string: "\n", attributes: rule)
        let caret: Int
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replace(&edit, range: NSRange(location: range.location, length: contentEnd - range.location), with: line)
            if hasNewline {
                let newline = NSRange(location: range.location + line.length, length: 1)
                edit.text.addAttribute(.paragraphStyle, value: paragraph, range: newline)
            } else {
                edit.text.append(ending)
            }
            caret = range.location + line.length + 1
        } else {
            let tail = NSMutableAttributedString()
            if !hasNewline { tail.append(NSAttributedString(string: "\n", attributes: attrs)) }
            tail.append(line)
            tail.append(ending)
            let insertion = hasNewline ? NSMaxRange(range) : text.length
            replace(&edit, range: NSRange(location: insertion, length: 0), with: tail)
            caret = insertion + tail.length
        }
        edit.selection = NSRange(location: min(caret, edit.text.length), length: 0)
        edit.additionalSelections = []
        edit.typing = edit.selection.location < edit.text.length ? edit.text.attributes(at: edit.selection.location, effectiveRange: nil) : plain
        renumber(&edit)
        return edit
    }
}

extension EaselStyledTextView {
    func installChecklistLayout() {
        guard let container = textContainer, !(layoutManager is EaselChecklistLayoutManager) else { return }
        container.replaceLayoutManager(EaselChecklistLayoutManager())
    }

    private var checklistManager: EaselChecklistLayoutManager? { layoutManager as? EaselChecklistLayoutManager }

    private func checklistItem(at point: NSPoint) -> EaselChecklistText.Item? {
        guard let manager = checklistManager, let storage = textStorage else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        return EaselChecklistText.item(at: local, manager: manager, storage: storage)
    }

    func checklistPress(atWindowPoint point: NSPoint) -> Bool {
        guard isEditable, !hasMarkedText(), let item = checklistItem(at: convert(point, from: nil)) else { return false }
        toggleChecklist(ranges: [NSRange(location: item.markerCharacter.location, length: 0)])
        return true
    }

    func addChecklistCursorRects() {
        guard isEditable, let manager = checklistManager, let storage = textStorage else { return }
        for item in EaselChecklistText.items(in: storage, range: NSRange(location: 0, length: storage.length)) where item.marker.isItem {
            guard let box = manager.boxRect(for: item) else { continue }
            let rect = box.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).insetBy(dx: -4, dy: -4)
            addCursorRect(rect.intersection(bounds), cursor: .pointingHand)
        }
    }

    var canToggleChecklist: Bool {
        guard isEditable, !hasMarkedText() else { return false }
        return selectedRanges.map(\.rangeValue).contains { range in
            EaselParagraphEditing.ranges(string, selection: range).contains { paragraph in
                EaselChecklistText.item(in: attributedString(), paragraph: paragraph)?.marker.isItem == true
            }
        }
    }

    func toggleChecklist(ranges suppliedRanges: [NSRange]? = nil) {
        guard isEditable, !hasMarkedText() else { return }
        let ranges = suppliedRanges ?? selectedRanges.map(\.rangeValue)
        guard Self.validFormattingRanges(ranges, length: attributedString().length),
              let toggle = EaselParagraphEditing.toggleChecklist(attributedString(), selections: ranges, typing: typingAttributes) else { return }
        let keep = suppliedRanges == nil ? nil : selectedRanges.map(\.rangeValue)
        var edit = toggle.edit
        if let keep, let first = keep.first {
            edit.selection = first
            edit.additionalSelections = Array(keep.dropFirst())
        }
        commitParagraph(edit, name: toggle.checked ? "Tick item" : "Untick item")
        guard toggle.checked, let manager = checklistManager, let storage = textStorage else { return }
        for location in toggle.markers {
            guard let item = EaselChecklistText.items(in: storage, range: NSRange(location: location, length: 1)).first,
                  let box = manager.boxRect(for: item) else { continue }
            EaselChecklistText.pop(in: self, rect: box.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y),
                                   manager: manager, marker: location)
        }
    }

    func handleChecklistKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              canToggleChecklist else { return false }
        toggleChecklist()
        return true
    }

    func insertDivider() {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, Self.validFormattingRanges([selectedRange()], length: attributedString().length),
              let edit = EaselParagraphEditing.divider(attributedString(), selection: selectedRange(), typing: typingAttributes,
                                                      base: objectStyle, bodyPointSize: paragraphBodyPointSize) else { return }
        commitParagraph(edit, name: "Divider")
    }

    func applySlashDivider(removing range: NSRange) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1,
              Self.validFormattingRanges([range], length: attributedString().length) else { return }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: attributedString()), selection: range,
                                              typing: typingAttributes)
        EaselParagraphEditing.replace(&edit, range: range, with: NSAttributedString())
        guard let next = EaselParagraphEditing.divider(edit.text, selection: edit.selection, typing: edit.typing, base: objectStyle,
                                                       bodyPointSize: paragraphBodyPointSize) else { return }
        commitParagraph(next, name: "Divider")
    }

    private func dividerParagraph(at location: Int) -> NSRange? {
        let value = attributedString()
        guard location >= 0, location < value.length else { return nil }
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        guard EaselParagraphEditing.isDivider(value.attributes(at: paragraph.location, effectiveRange: nil)) else { return nil }
        return paragraph
    }

    private func plainAttributes(from attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var plain = EaselParagraphEditing.formatted(attrs, kind: .text, base: objectStyle, bodyPointSize: paragraphBodyPointSize)
        for key in [NSAttributedString.Key.link, .backgroundColor, .underlineStyle, .strikethroughStyle] { plain.removeValue(forKey: key) }
        return plain
    }

    private func endsWithNewline(_ text: NSString, before end: Int) -> Bool {
        end > 0 && end <= text.length && text.substring(with: NSRange(location: end - 1, length: 1)).rangeOfCharacter(from: .newlines) != nil
    }

    func leaveDivider() -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, selectedRange().length == 0 else { return false }
        let value = attributedString(), text = string as NSString, caret = selectedRange().location
        guard text.length > 0, !(caret >= text.length && endsWithNewline(text, before: text.length)),
              let paragraph = dividerParagraph(at: min(caret, text.length - 1)) else { return false }
        let end = NSMaxRange(paragraph), attrs = value.attributes(at: paragraph.location, effectiveRange: nil)
        if endsWithNewline(text, before: end) {
            setSelectedRange(NSRange(location: end, length: 0))
            typingAttributes = end < value.length ? value.attributes(at: end, effectiveRange: nil) : plainAttributes(from: attrs)
            return true
        }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: value), selection: NSRange(location: end, length: 0),
                                              typing: typingAttributes)
        EaselParagraphEditing.replace(&edit, range: NSRange(location: end, length: 0), with: NSAttributedString(string: "\n", attributes: attrs))
        edit.selection = NSRange(location: edit.text.length, length: 0)
        edit.typing = plainAttributes(from: attrs)
        commitParagraph(edit, name: "New paragraph")
        return true
    }

    func deleteAdjacentDivider(forward: Bool) -> Bool {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1, selectedRange().length == 0 else { return false }
        let value = attributedString(), text = string as NSString, caret = selectedRange().location
        let target: NSRange?
        if forward {
            target = caret < text.length && endsWithNewline(text, before: caret + 1) && caret + 1 < text.length ? dividerParagraph(at: caret + 1) : nil
        } else {
            target = caret > 0 && endsWithNewline(text, before: caret) ? dividerParagraph(at: caret - 1) : nil
        }
        guard let target, target.length > 0 else { return false }
        var edit = EaselParagraphEditing.Edit(text: NSMutableAttributedString(attributedString: value), selection: selectedRange(), typing: typingAttributes)
        EaselParagraphEditing.replace(&edit, range: target, with: NSAttributedString())
        commitParagraph(edit, name: "Delete divider")
        return true
    }
}
