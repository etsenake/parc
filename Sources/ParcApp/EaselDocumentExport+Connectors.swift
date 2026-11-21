import AppKit

extension EaselDocumentExport {
    static func connectorArt(_ item: EaselItem, lookup: [UUID: EaselItem], into art: inout EaselVectorArt) {
        guard item.kind == .arrow else { return }
        if let route = EaselConnectorRouter.route(for: item, lookup: { lookup[$0] }) { art.connectorRoutes[item.id] = route }
        guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = NSMutableAttributedString(attributedString: EaselRichTextCodec.attributed(item))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        value.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: value.length))
        let layout = EaselConnectorLabelLayout(value)
        let used = layout.used, manager = layout.manager, storage = layout.storage
        let text = storage.string as NSString
        var runs: [EaselVectorTextRun] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: layout.container)) { rect, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                var value = EaselInlineText.exportText(attributes, text.substring(with: range), images: false)
                while let last = value.last, last.isNewline { value.removeLast() }
                guard !value.isEmpty else { return }
                let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let location = manager.location(forGlyphAt: glyphRange.location)
                let font = attributes[.font] as? NSFont ?? EaselTextAppearance.font(item.resolvedTextStyle)
                var run = EaselVectorTextRun(x: Double(rect.minX + location.x - used.minX), y: Double(rect.minY + location.y - used.minY),
                                             text: value, fontFamily: cssFamily(font), fontSize: Double(font.pointSize),
                                             weight: cssWeight(font), italic: font.fontDescriptor.symbolicTraits.contains(.italic))
                run.color = (attributes[.foregroundColor] as? NSColor).flatMap(hex)
                run.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                runs.append(run)
            }
        }
        art.connectorLabels[item.id] = EaselConnectorLabelArt(text: EaselVectorText(runs: runs),
                                                              width: Double(ceil(used.width)), height: Double(ceil(used.height)))
    }
}
