import AppKit
import ParcCore

@MainActor
extension EaselDocumentExport {
    static func tableVectorText(_ item: EaselItem) -> EaselVectorText {
        guard let table = item.table else { return EaselVectorText() }
        let grid = EaselTableLayout(table: table, frame: item.frame)
        var result = EaselVectorText()
        for cell in table.visibleCells {
            guard let value = table.cell(cell), !value.text.isEmpty, let box = grid.rect(of: cell, in: table) else { continue }
            let attributed = EaselRichTextCodec.attributed(value.text, richText: value.richText, style: item.resolvedTextStyle, color: item.color)
            EaselTextAttachments.bind(attributed, width: max(1, box.width - 20))
            let layout = EaselTextLayout.Layout(attributed, width: box.width)
            let offset = CGPoint(x: box.x - item.frame.x, y: box.y - item.frame.y + Double(EaselTableMetrics.cellPadding))
            result.runs += vectorRuns(layout, style: item.resolvedTextStyle, offset: offset)
            result.images += EaselInlineText.exportImages(layout, offset: offset)
        }
        return result
    }

    static func vectorRuns(_ layout: EaselTextLayout.Layout, style: EaselTextStyle, offset: CGPoint) -> [EaselVectorTextRun] {
        let manager = layout.manager, storage = layout.storage, container = layout.container, inset = EaselTextLayout.inset
        let text = storage.string as NSString
        var runs: [EaselVectorTextRun] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            storage.enumerateAttributes(in: characters) { attributes, range, _ in
                var value = EaselInlineText.exportText(attributes, text.substring(with: range), images: true)
                while let last = value.last, last.isNewline { value.removeLast() }
                guard !value.isEmpty else { return }
                let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let location = manager.location(forGlyphAt: glyphRange.location)
                let font = attributes[.font] as? NSFont ?? EaselTextAppearance.font(style)
                var run = EaselVectorTextRun(x: Double(offset.x + inset.width + rect.minX + location.x),
                                             y: Double(offset.y + inset.height + rect.minY + location.y),
                                             text: value, fontFamily: cssFamily(font), fontSize: Double(font.pointSize),
                                             weight: cssWeight(font), italic: font.fontDescriptor.symbolicTraits.contains(.italic))
                run.color = (attributes[.foregroundColor] as? NSColor).flatMap(hex)
                run.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                run.strikethrough = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                if let link = attributes[.link] as? URL { run.link = link.absoluteString } else { run.link = attributes[.link] as? String }
                runs.append(run)
            }
        }
        return runs
    }
}
