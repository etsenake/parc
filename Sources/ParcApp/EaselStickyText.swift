import AppKit

@MainActor
enum EaselStickyText {
    static func scaled(_ value: NSAttributedString, by scale: Double) -> NSAttributedString {
        resized(value, by: scale, rounding: false)
    }

    static func unscaled(_ value: NSAttributedString, by scale: Double) -> NSAttributedString {
        guard scale.isFinite, scale > 0 else { return value }
        return resized(value, by: 1 / scale, rounding: true)
    }

    private nonisolated static func resized(_ value: NSAttributedString, by factor: Double, rounding: Bool,
                                            canonical: NSFont? = nil) -> NSAttributedString {
        guard factor.isFinite, factor > 0, abs(factor - 1) > 0.0005, value.length > 0 else { return value }
        let size: (Double) -> Double = { points in rounding ? (points * factor * 1000).rounded() / 1000 : points * factor }
        let result = NSMutableAttributedString(attributedString: value)
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
            if let font = attributes[.font] as? NSFont {
                let points = CGFloat(size(Double(font.pointSize)))
                let face = CTFontCreateCopyWithAttributes(font, points, nil, nil) as NSFont
                result.addAttribute(.font, value: canonical.flatMap { matches(face, $0) ? $0 : nil } ?? face, range: range)
            }
            if let kern = attributes[.kern] as? NSNumber { result.addAttribute(.kern, value: size(kern.doubleValue), range: range) }
            if let offset = attributes[.baselineOffset] as? NSNumber {
                result.addAttribute(.baselineOffset, value: size(offset.doubleValue), range: range)
            }
            if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
               let copy = paragraph.mutableCopy() as? NSMutableParagraphStyle {
                func scaled(_ value: CGFloat) -> CGFloat { CGFloat(size(Double(value))) }
                copy.headIndent = scaled(paragraph.headIndent)
                copy.firstLineHeadIndent = scaled(paragraph.firstLineHeadIndent)
                copy.tailIndent = scaled(paragraph.tailIndent)
                copy.lineSpacing = scaled(paragraph.lineSpacing)
                copy.paragraphSpacing = scaled(paragraph.paragraphSpacing)
                copy.paragraphSpacingBefore = scaled(paragraph.paragraphSpacingBefore)
                copy.minimumLineHeight = scaled(paragraph.minimumLineHeight)
                copy.maximumLineHeight = scaled(paragraph.maximumLineHeight)
                copy.defaultTabInterval = scaled(paragraph.defaultTabInterval)
                if paragraph.tabStops != NSParagraphStyle.default.tabStops {
                    copy.tabStops = paragraph.tabStops.map {
                        NSTextTab(textAlignment: $0.alignment, location: scaled($0.location), options: $0.options)
                    }
                }
                result.addAttribute(.paragraphStyle, value: copy, range: range)
            }
        }
        return result
    }

    static func scaledAttributes(_ attributes: [NSAttributedString.Key: Any], by factor: Double) -> [NSAttributedString.Key: Any] {
        guard factor.isFinite, factor > 0, abs(factor - 1) > 0.0005, !attributes.isEmpty else { return attributes }
        return resized(NSAttributedString(string: " ", attributes: attributes), by: factor, rounding: false)
            .attributes(at: 0, effectiveRange: nil)
    }

    static func presented(_ item: EaselItem, adaptive: Bool) -> NSAttributedString {
        let scaled = scaled(EaselRichTextCodec.attributed(item), by: EaselBoardObjects.textScale(item))
        let value = EaselTextPresentation.displayed(scaled, for: item)
        return adaptive ? EaselInk.adapting(value) : value
    }

    static func stored(_ value: NSAttributedString, for item: EaselItem) -> NSAttributedString {
        let scale = EaselBoardObjects.textScale(item)
        guard scale.isFinite, scale > 0 else { return EaselTextPresentation.stored(value, for: item) }
        return resized(EaselTextPresentation.stored(value, for: item), by: 1 / scale, rounding: true,
                       canonical: EaselTextAppearance.font(item.resolvedTextStyle))
    }

    private nonisolated static func matches(_ face: NSFont, _ font: NSFont) -> Bool {
        abs(face.pointSize - font.pointSize) < 0.001 && face.fontDescriptor.symbolicTraits == font.fontDescriptor.symbolicTraits
            && (face.familyName == font.familyName || (face.fontName.hasPrefix(".") && font.fontName.hasPrefix(".")))
    }

    static func typingAttributes(_ item: EaselItem, color: NSColor) -> [NSAttributedString.Key: Any] {
        let base: [NSAttributedString.Key: Any] = [.font: EaselTextAppearance.font(item.resolvedTextStyle), .foregroundColor: color]
        return EaselTextPresentation.typingAttributes(scaledAttributes(base, by: EaselBoardObjects.textScale(item)), for: item)
    }

    static func height(_ item: EaselItem) -> Double {
        let box = EaselBoardObjects.stickyTextBox(item)
        let value = item.text.isEmpty ? NSAttributedString() : presented(item, adaptive: false)
        return value.length == 0 ? 0 : Double(EaselTextLayout.Layout(value, width: box.width).height)
    }
}
