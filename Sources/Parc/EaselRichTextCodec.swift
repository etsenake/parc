import AppKit
import ParcCore

@MainActor
enum EaselRichTextCodec {
    static let noteBodyColor = NSColor(name: NSColor.Name("Parc.Note.BodyText")) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }
    private static func semanticInk(_ color: NSColor) -> EaselRichText.SemanticInk? {
        guard color.type == .catalog,
              color.catalogNameComponent == noteBodyColor.catalogNameComponent,
              color.colorNameComponent == noteBodyColor.colorNameComponent else { return nil }
        return .noteBody
    }
    static func hex(_ color: NSColor) throws -> String {
        guard let c = color.usingColorSpace(.sRGB) else { throw EaselTextClipboardError.unsupportedFormatting }
        return String(format: "#%02X%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
    }
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x252525FF
        return NSColor(srgbRed: Double(value >> 24 & 255) / 255, green: Double(value >> 16 & 255) / 255,
                       blue: Double(value >> 8 & 255) / 255, alpha: Double(value & 255) / 255)
    }
    static func font(_ value: EaselRichText.Font) -> NSFont {
        let traits = NSFontDescriptor.SymbolicTraits(rawValue: value.traits)
        let monospaced = value.name.hasPrefix(".AppleSystemUIFontMonospaced") || value.name.hasPrefix(".SFMono")
        let system = monospaced
            ? NSFont.monospacedSystemFont(ofSize: value.size, weight: NSFont.Weight(rawValue: value.weight))
            : NSFont.systemFont(ofSize: value.size, weight: NSFont.Weight(rawValue: value.weight))
        let isSystem = value.name.hasPrefix(".SF") || value.name.hasPrefix(".AppleSystemUIFont")
        let original = value.style.map(EaselTextAppearance.font) ?? (isSystem ? system : NSFont(name: value.name, size: value.size)) ?? system
        var attributes: [NSFontDescriptor.AttributeName: Any] = [.traits: [NSFontDescriptor.TraitKey.symbolic: traits.rawValue,
            .weight: value.weight, .width: value.width, .slant: value.slant]]
        if !value.variations.isEmpty {
            attributes[.variation] = Dictionary(value.variations.compactMap { key, amount in
                UInt32(key).map { (NSNumber(value: $0), NSNumber(value: amount)) }
            }, uniquingKeysWith: { first, _ in first })
        }
        return NSFont(descriptor: original.fontDescriptor.addingAttributes(attributes), size: value.size) ?? original
    }
    static func snapshotFont(_ font: NSFont) -> EaselRichText.Font {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let axes = font.fontDescriptor.object(forKey: .variation) as? [NSNumber: NSNumber] ?? [:]
        return .init(name: font.fontName, size: font.pointSize, traits: font.fontDescriptor.symbolicTraits.rawValue,
                     weight: (traits?[.weight] as? NSNumber)?.doubleValue ?? 0,
                     width: (traits?[.width] as? NSNumber)?.doubleValue ?? 0, slant: (traits?[.slant] as? NSNumber)?.doubleValue ?? 0,
                     variations: Dictionary(axes.map { ($0.key.stringValue, $0.value.doubleValue) }, uniquingKeysWith: { first, _ in first }), style: EaselTextAppearance.matchingStyle(font))
    }
    static func snapshot(_ value: NSAttributedString) throws -> EaselRichText {
        var runs: [EaselRichText.Run] = [], error: Error?
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attrs, range, stop in
            do {
                let originalFont = NSAttributedString.Key("NSOriginalFont")
                guard attrs[originalFont] == nil || attrs[originalFont] is NSFont else {
                    throw EaselTextClipboardError.unsupportedFormatting
                }
                let allowed: Set<NSAttributedString.Key> = [originalFont, .font, .foregroundColor, .backgroundColor, .underlineStyle,
                    .strikethroughStyle, .underlineColor, .strikethroughColor, .link, .kern, .baselineOffset, .paragraphStyle, .ligature, .attachment]
                guard Set(attrs.keys).isSubset(of: allowed), (attrs[.ligature] as? NSNumber)?.intValue ?? 1 == 1 else {
                    throw EaselTextClipboardError.unsupportedFormatting
                }
                let face = (attrs[originalFont] as? NSFont) ?? (attrs[.font] as? NSFont) ?? EaselTextAppearance.font(.init())
                let foreground = (attrs[.foregroundColor] as? NSColor) ?? .textColor
                let semantic = semanticInk(foreground)
                var a = EaselRichText.Attributes(font: snapshotFont(face),
                    ink: semantic == .noteBody ? "#000000FF" : try EaselInk.storedInk(foreground) ?? hex(foreground),
                    semanticInk: semantic)
                if let object = attrs[.attachment] {
                    guard let attachment = object as? NSTextAttachment, range.length == 1,
                          (value.string as NSString).substring(with: range) == "\u{FFFC}" else {
                        throw EaselTextClipboardError.unsupportedFormatting
                    }
                    if let inline = (attachment as? EaselInlineAttachment)?.inline {
                        try inline.validate()
                        a.inline = inline
                    } else { a.image = try EaselTextAttachments.source(attachment) }
                }
                a.background = try (attrs[.backgroundColor] as? NSColor).map { try EaselTextHighlight.stored($0) ?? hex($0) }
                a.underlineColor = try (attrs[.underlineColor] as? NSColor).map(hex)
                a.strikeColor = try (attrs[.strikethroughColor] as? NSColor).map(hex)
                a.underline = (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0
                a.strike = (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0
                a.kern = (attrs[.kern] as? NSNumber)?.doubleValue ?? 0
                a.baseline = (attrs[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
                if let link = attrs[.link] {
                    if let url = link as? URL { a.link = url.absoluteString }
                    else if let string = link as? String { a.link = string }
                    else { throw EaselTextClipboardError.unsupportedFormatting }
                }
                if let p = attrs[.paragraphStyle] as? NSParagraphStyle {
                    guard p.textBlocks.isEmpty, p.tabStops.allSatisfy({ $0.options.isEmpty }) else { throw EaselTextClipboardError.unsupportedFormatting }
                    a.paragraph = .init(alignment: p.alignment.rawValue, direction: p.baseWritingDirection.rawValue,
                        lineBreak: Int(p.lineBreakMode.rawValue), firstIndent: p.firstLineHeadIndent, headIndent: p.headIndent,
                        tailIndent: p.tailIndent, lineSpacing: p.lineSpacing, before: p.paragraphSpacingBefore,
                        after: p.paragraphSpacing, minimumHeight: p.minimumLineHeight, maximumHeight: p.maximumLineHeight,
                        heightMultiple: p.lineHeightMultiple, hyphenation: p.hyphenationFactor,
                        tightening: p.tighteningFactorForTruncation, allowsTightening: p.allowsDefaultTighteningForTruncation,
                        defaultHyphenation: p.usesDefaultHyphenation, defaultTab: p.defaultTabInterval,
                        tabs: p.tabStops.map { .init(alignment: $0.alignment.rawValue, location: $0.location) },
                        lists: p.textLists.map { .init(marker: $0.markerFormat.rawValue, options: $0.listOptions.rawValue, start: $0.startingItemNumber) },
                        heading: p.headerLevel == 0 ? nil : p.headerLevel)
                    if p == NSParagraphStyle.default { a.paragraph = nil }
                }
                if !a.isAtomic, let last = runs.last, last.attributes == a, last.location + last.length == range.location {
                    runs[runs.count - 1].length += range.length
                } else { runs.append(.init(location: range.location, length: range.length, attributes: a)) }
            } catch let failure { error = failure; stop.pointee = true }
        }
        if let error { throw error }
        let result = EaselRichText(runs: runs); try result.validate(text: value.string); return result
    }
    static func attributes(_ a: EaselRichText.Attributes) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [.font: font(a.font), .foregroundColor: a.semanticInk == .noteBody ? noteBodyColor : color(a.ink)]
        if let image = a.image { result[.attachment] = EaselImageAttachment(source: image) }
        else if let inline = a.inline { result[.attachment] = EaselInlineAttachment(inline: inline) }
        if let c = a.background { result[.backgroundColor] = color(c) }
        if a.underline != 0 { result[.underlineStyle] = a.underline }
        if a.strike != 0 { result[.strikethroughStyle] = a.strike }
        if let c = a.underlineColor { result[.underlineColor] = color(c) }
        if let c = a.strikeColor { result[.strikethroughColor] = color(c) }
        if let link = a.link { result[.link] = link }
        if a.kern != 0 { result[.kern] = a.kern }
        if a.baseline != 0 { result[.baselineOffset] = a.baseline }
        if let p = a.paragraph {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = NSTextAlignment(rawValue: p.alignment) ?? .natural
            paragraph.baseWritingDirection = NSWritingDirection(rawValue: p.direction) ?? .natural
            paragraph.lineBreakMode = NSLineBreakMode(rawValue: UInt(p.lineBreak)) ?? .byWordWrapping
            paragraph.firstLineHeadIndent = p.firstIndent; paragraph.headIndent = p.headIndent; paragraph.tailIndent = p.tailIndent
            paragraph.lineSpacing = p.lineSpacing; paragraph.paragraphSpacingBefore = p.before; paragraph.paragraphSpacing = p.after
            paragraph.minimumLineHeight = p.minimumHeight; paragraph.maximumLineHeight = p.maximumHeight
            paragraph.lineHeightMultiple = p.heightMultiple; paragraph.hyphenationFactor = p.hyphenation
            paragraph.tighteningFactorForTruncation = p.tightening
            paragraph.allowsDefaultTighteningForTruncation = p.allowsTightening
            paragraph.usesDefaultHyphenation = p.defaultHyphenation
            paragraph.defaultTabInterval = p.defaultTab
            paragraph.headerLevel = p.heading ?? 0
            paragraph.tabStops = p.tabs.map { NSTextTab(textAlignment: NSTextAlignment(rawValue: $0.alignment) ?? .left, location: $0.location) }
            paragraph.textLists = p.lists.map {
                let list = NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: $0.marker), options: Int($0.options))
                list.startingItemNumber = $0.start; return list
            }
            result[.paragraphStyle] = paragraph
        }
        return result
    }
    static func attributed(_ text: String, richText: EaselRichText?, style: EaselTextStyle, color: String) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: EaselTextAppearance.attributed(text, style: style, color: color))
        guard let richText else { return result }
        for run in richText.runs {
            result.setAttributes(attributes(run.attributes), range: NSRange(location: run.location, length: run.length))
        }
        return result
    }
    static func attributed(_ item: EaselItem) -> NSAttributedString {
        let result = attributed(item.text, richText: item.richText, style: item.resolvedTextStyle, color: item.color)
        EaselTextAttachments.bind(result, width: max(1, item.frame.width - 20))
        return result
    }
    static func align(_ value: NSMutableAttributedString, to alignment: NSTextAlignment) {
        var parts: [(NSRange, NSParagraphStyle?)] = []
        value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, range, _ in
            parts.append((range, style as? NSParagraphStyle))
        }
        for (range, style) in parts where style?.alignment != alignment {
            let next = (style?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            next.alignment = alignment
            value.addAttribute(.paragraphStyle, value: next, range: range)
        }
    }
}

@MainActor
protocol EaselPanelHandle: AnyObject {
    var isOpen: Bool { get }
    func close()
}

struct EaselLinkRequest {
    var link: String?
    var webOnly: Bool
    var host: NSView
    var anchor: NSRect
    var commit: (String?) -> Void
}

struct EaselTextSizeRequest {
    var points: Double?
    var host: NSView
    var anchor: NSRect
    var commit: (Double) -> Void
}

struct EaselLinkHoverRequest {
    var key: String
    var link: String
    var host: NSView
    var anchor: NSRect
    var canEdit: Bool
    var edit: () -> Void
    var remove: () -> Void
}

@MainActor
protocol EaselPanelPresenting: AnyObject {
    func presentLinkEditor(_ request: EaselLinkRequest) -> EaselPanelHandle?
    func presentTextSizeEditor(_ request: EaselTextSizeRequest) -> EaselPanelHandle?
    func hoverLink(_ request: EaselLinkHoverRequest?)
}

enum EaselLinkTarget {
    case web(URL)
    case note(URL)
    case other(URL)

    static func classify(_ raw: String) -> EaselLinkTarget? {
        guard EaselRichText.validLink(raw), let url = URL(string: raw) else { return nil }
        switch url.scheme?.lowercased() {
        case "http", "https": return .web(url)
        case "file": return NoteFileKind(url: url) == nil ? nil : .note(url)
        case "parc": return .web(url)
        default: return .other(url)
        }
    }
}
