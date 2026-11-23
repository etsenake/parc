import AppKit
import CoreText
import ParcCore

package enum NoteTextRole: Hashable {
    case title
    case heading(Int)
    case body
    case quote
    case callout
    case listMarker
    case code
    case inlineCode
    case caption
    case tableCell
    case tableHeader
    case placeholder
    case mention
}

package struct NoteTextStyle {
    package var font: NSFont
    var lineHeight: CGFloat
    package var ink: NSColor
    var kern: CGFloat = 0
    var baselineShift: CGFloat?

    package var baselineOffset: CGFloat {
        if let baselineShift { return baselineShift }
        let natural = font.ascender - font.descender + font.leading
        return max(0, (lineHeight - natural) / 2)
    }

    var runAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .baselineOffset: baselineOffset]
        if kern != 0 { attributes[.kern] = kern }
        return attributes
    }

    package func paragraphStyle(spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0,
                        alignment: NSTextAlignment = .natural) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        return style
    }

    var attributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: paragraphStyle(),
            .baselineOffset: baselineOffset,
        ]
        if kern != 0 { attributes[.kern] = kern }
        return attributes
    }
}

@MainActor
package enum NoteTheme {
    private static let registerFonts: Void = {
        let notes = ["Nunito-ExtraBold", "Nunito-Regular", "Nunito-Bold", "Nunito-Italic", "Nunito-BoldItalic"]
        for name in notes {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "NoteFonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        let easel = ["SpaceMono-Regular", "SpaceMono-Bold", "EBGaramond-VariableFont_wght",
                     "ParcWide-Regular", "ParcWide-SemiBold", "ParcWide-Black"]
        for name in easel {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "EaselFonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    static func ensureFontsRegistered() { _ = registerFonts }

    static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("Parc.Notes." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    package static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    package static func resolved(_ color: NSColor, in view: NSView) -> CGColor {
        var result = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    static func resolved(_ color: NSColor, in appearance: NSAppearance) -> CGColor {
        var result = color.cgColor
        appearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    package static let ink = adaptive("Ink", light: rgb(0x1F1B2E), dark: rgb(0xEDEBFA))
    package static let titleInk = adaptive("TitleInk", light: rgb(0x220C7F), dark: rgb(0xE6E6FF))
    package static let secondaryInk = adaptive("SecondaryInk", light: rgb(0x1F1B2E, 0.62), dark: rgb(0xEDEBFA, 0.62))
    package static let tertiaryInk = adaptive("TertiaryInk", light: rgb(0x1F1B2E, 0.38), dark: rgb(0xEDEBFA, 0.38))
    package static let placeholderInk = adaptive("Placeholder", light: rgb(0x220C7F, 0.32), dark: rgb(0xE6E6FF, 0.32))
    package static let titlePlaceholderInk = adaptive("TitlePlaceholder", light: rgb(0x220C7F, 0.4), dark: rgb(0xE6E6FF, 0.4))
    package static let accent = adaptive("Accent", light: rgb(0x2702C2), dark: rgb(0x9380E0))
    package static let caret = accent
    package static let selection = adaptive("Selection", light: rgb(0xCDCDFF), dark: rgb(0x5235CE, 0.75))
    static let inactiveSelection = adaptive("InactiveSelection", light: rgb(0xCDCDFF, 0.55), dark: rgb(0x5235CE, 0.4))
    package static let blockSelection = adaptive("BlockSelection", light: rgb(0x2702C2, 0.10), dark: rgb(0x9380E0, 0.20))
    static let link = adaptive("Link", light: rgb(0x220C7F), dark: rgb(0xE6E6FF))
    static let linkUnderline = adaptive("LinkUnderline", light: rgb(0x220C7F, 0.4), dark: rgb(0xE6E6FF, 0.45))
    package static let hoverFill = adaptive("Hover", light: rgb(0x1F1B2E, 0.06), dark: rgb(0xFFFFFF, 0.08))
    package static let pressedFill = adaptive("Pressed", light: rgb(0x1F1B2E, 0.11), dark: rgb(0xFFFFFF, 0.14))
    package static let checkedFill = adaptive("Checked", light: rgb(0x2702C2, 0.1), dark: NSColor(srgbRed: 0.024, green: 0.180, blue: 0.475, alpha: 1))
    package static let checkedInk = adaptive("CheckedInk", light: NSColor(srgbRed: 0.153, green: 0.008, blue: 0.761, alpha: 1),
                                     dark: NSColor(srgbRed: 0.714, green: 0.788, blue: 0.980, alpha: 1))
    package static let separator = adaptive("Separator", light: rgb(0x1F1B2E, 0.12), dark: rgb(0xFFFFFF, 0.14))
    package static let codeBackground = adaptive("CodeBackground", light: rgb(0x1F1B2E, 0.045), dark: rgb(0xFFFFFF, 0.06))
    package static let codeInk = adaptive("CodeInk", light: rgb(0x29243D), dark: rgb(0xE4E1F5))
    static let inlineCodeBackground = adaptive("InlineCodeBackground", light: rgb(0x2702C2, 0.07), dark: rgb(0x9380E0, 0.18))
    static let inlineCodeInk = adaptive("InlineCodeInk", light: rgb(0xC0306A), dark: rgb(0xFF8FB8))
    package static let panelFill = adaptive("PanelFill", light: rgb(0xFFFFFF, 0.92), dark: rgb(0x2A2733, 0.94))
    package static let panelStroke = adaptive("PanelStroke", light: rgb(0x1F1B2E, 0.10), dark: rgb(0xFFFFFF, 0.12))
    package static let paper = adaptive("Paper", light: rgb(0xFFFFFF, 0.85), dark: rgb(0x000000, 0.5))

    package static let menuFill = adaptive("MenuFill", light: .white, dark: NSColor(srgbRed: 0.071, green: 0.059, blue: 0.180, alpha: 1))
    package static let menuHairline = adaptive("MenuHairline", light: rgb(0x2B2659, 0.13), dark: rgb(0x34334D))
    package static let menuShadow = NSColor.black.withAlphaComponent(0.12)
    package static let menuSeparator = adaptive("MenuSeparator", light: rgb(0x2B2659, 0.09), dark: rgb(0xFFFFFF, 0.09))
    package static let menuInk = adaptive("MenuInk", light: rgb(0x2E2847), dark: rgb(0xE6E6FF))
    package static let menuSecondaryInk = adaptive("MenuSecondaryInk", light: NSColor(srgbRed: 0.431, green: 0.404, blue: 0.553, alpha: 1),
                                           dark: NSColor(srgbRed: 0.529, green: 0.584, blue: 0.757, alpha: 1))
    package static let menuTertiaryInk = adaptive("MenuTertiaryInk", light: NSColor(srgbRed: 0.431, green: 0.404, blue: 0.553, alpha: 0.72),
                                          dark: NSColor(srgbRed: 0.529, green: 0.584, blue: 0.757, alpha: 0.72))
    package static let menuHighlight = adaptive("MenuHighlight", light: rgb(0x2B2659, 0.065), dark: rgb(0xFFFFFF, 0.085))
    package static let menuPressed = adaptive("MenuPressed", light: rgb(0x2B2659, 0.11), dark: rgb(0xFFFFFF, 0.13))
    package static let destructiveInk = adaptive("Destructive", light: rgb(0xD0300F), dark: rgb(0xFF7B5E))
    package static let destructiveHighlight = adaptive("DestructiveHighlight", light: rgb(0xF53714, 0.09), dark: rgb(0xF53714, 0.2))
    package static let fieldFill = adaptive("FieldFill", light: rgb(0x060E2B, 0.055), dark: rgb(0xEEEEF6, 0.09))
    package static let keycapFace = adaptive("KeycapFace", light: rgb(0xF1F0F7), dark: rgb(0x2C2A47))
    package static let keycapBase = adaptive("KeycapBase", light: rgb(0xBDBACF), dark: rgb(0x4E4B6E))
    package static let keycapInk = adaptive("KeycapInk", light: rgb(0x48426A), dark: rgb(0xD5D4F0))
    static let chipFill = adaptive("ChipFill", light: rgb(0x1F1B2E, 0.1), dark: rgb(0xFFFFFF, 0.12))
    static let tooltipShortcutInk = menuSecondaryInk

    package static let dropIndicatorFallback = adaptive("DropIndicator", light: rgb(0x2702C2, 0.55), dark: rgb(0x9380E0, 0.75))
    static let quoteBar = adaptive("QuoteBar", light: rgb(0x1F1B2E, 0.85), dark: rgb(0xEDEBFA, 0.85))
    static let dividerLine = adaptive("Divider", light: rgb(0x1F1B2E, 0.13), dark: rgb(0xFFFFFF, 0.15))
    static let calloutFill = adaptive("CalloutFill", light: rgb(0x8C8B87, 0.12), dark: rgb(0x9B9B9B, 0.16))
    static let tableBorder = adaptive("TableBorder", light: rgb(0x1F1B2E, 0.12), dark: rgb(0xFFFFFF, 0.14))
    static let tableHeaderFill = adaptive("TableHeaderFill", light: rgb(0x1F1B2E, 0.03), dark: rgb(0xFFFFFF, 0.04))
    package static let handleInk = adaptive("HandleInk", light: rgb(0x1F1B2E, 0.35), dark: rgb(0xEDEBFA, 0.4))
    static let todoDoneInk = adaptive("TodoDone", light: rgb(0x1F1B2E, 0.45), dark: rgb(0xEDEBFA, 0.45))
    package static let todoBox = adaptive("TodoBox", light: rgb(0x1F1B2E, 0.55), dark: rgb(0xEDEBFA, 0.6))
    package static let todoCheckFill = adaptive("TodoCheckFill", light: rgb(0x2702C2), dark: rgb(0x9380E0))
    package static func todoGlyph(checked: Bool, pointSize: CGFloat = todoBoxSize) -> NSImage? {
        let name = checked ? "checkmark.circle.fill" : "circle"
        let colors: [NSColor] = checked ? [.white, todoCheckFill] : [todoBox]
        let resolved = colors.map { NSColor(cgColor: $0.cgColor) ?? $0 }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: resolved))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
    static let mentionInk = adaptive("MentionInk", light: rgb(0x1F1B2E, 0.82), dark: rgb(0xEDEBFA, 0.85))
    static let mentionUnderline = adaptive("MentionUnderline", light: rgb(0x1F1B2E, 0.22), dark: rgb(0xEDEBFA, 0.28))
    package static let mediaPlaceholderFill = adaptive("MediaPlaceholder", light: rgb(0x1F1B2E, 0.045), dark: rgb(0xFFFFFF, 0.06))
    package static let findMatch = adaptive("FindMatch", light: rgb(0xFFD84D, 0.45), dark: rgb(0xFFD84D, 0.3))
    package static let findCurrentMatch = adaptive("FindCurrent", light: rgb(0xFFB020, 0.75), dark: rgb(0xFFB020, 0.6))

    package nonisolated static let disabledOpacity: CGFloat = 0.25
    package nonisolated static let disabledRowOpacity: CGFloat = 0.38
    nonisolated static let idleHandleOpacity: CGFloat = 0.33

    static func dropIndicator(spaceFocus: NSColor?) -> NSColor {
        guard let spaceFocus else { return dropIndicatorFallback }
        return adaptive("DropIndicator.Space", light: spaceFocus.withAlphaComponent(0.7), dark: spaceFocus.withAlphaComponent(0.85))
    }

    static func blockSelectionWash(spaceFocus: NSColor?) -> NSColor {
        guard let spaceFocus else { return blockSelection }
        return adaptive("BlockSelection.Space", light: spaceFocus.withAlphaComponent(0.13), dark: spaceFocus.withAlphaComponent(0.24))
    }

    static func menuHighlight(spaceFocus: NSColor?) -> NSColor {
        guard let spaceFocus else { return menuHighlight }
        return adaptive("MenuHighlight.Space", light: spaceFocus.withAlphaComponent(0.1), dark: spaceFocus.withAlphaComponent(0.22))
    }

    private static let palette: [NoteColor: (text: (UInt32, UInt32), background: (UInt32, UInt32))] = [
        .gray: ((0x686865, 0x9C9C9C), (0x8C8B87, 0x9B9B9B)),
        .brown: ((0x895C48, 0xC1927F), (0xA8765E, 0xBA856F)),
        .orange: ((0xB05D0B, 0xCE8E5F), (0xE8892E, 0xD98A4E)),
        .yellow: ((0x956B23, 0xCA9849), (0xE8B53A, 0xD9A94A)),
        .green: ((0x3B7255, 0x5EAB7F), (0x4F9A6E, 0x52A877)),
        .blue: ((0x2C6C91, 0x4CA5D8), (0x3D8FC4, 0x3D9CDB)),
        .purple: ((0x8154A3, 0xB48CDD), (0x9A6FC4, 0xA374DB)),
        .pink: ((0xAD3C78, 0xDC7FAF), (0xD45A9A, 0xDB5C9F)),
        .red: ((0xC0322D, 0xE77F7D), (0xE05A52, 0xE5605A)),
    ]

    static let backgroundTintAlpha: (light: CGFloat, dark: CGFloat) = (0.16, 0.26)

    private static var colorCache: [NoteColorStyle: NSColor] = [:]

    static func color(_ style: NoteColorStyle) -> NSColor {
        if let cached = colorCache[style] { return cached }
        let entry = palette[style.color]!
        let made: NSColor
        if style.isBackground {
            made = adaptive("Background." + style.color.rawValue, light: rgb(entry.background.0, backgroundTintAlpha.light),
                            dark: rgb(entry.background.1, backgroundTintAlpha.dark))
        } else {
            made = adaptive("Text." + style.color.rawValue, light: rgb(entry.text.0), dark: rgb(entry.text.1))
        }
        colorCache[style] = made
        return made
    }

    package static func swatch(_ color: NoteColor) -> NSColor {
        let entry = palette[color]!
        return adaptive("Swatch." + color.rawValue, light: rgb(entry.background.0), dark: rgb(entry.background.1))
    }

    package static func displayName(_ color: NoteColor) -> String { color.rawValue.capitalized }

    static func syntaxColor(_ kind: NoteSyntaxKind) -> NSColor { syntaxColor(kind.rawValue) }
    static func syntaxIsItalic(_ kind: NoteSyntaxKind) -> Bool { syntaxIsItalic(kind.rawValue) }
    static func syntaxIsBold(_ kind: NoteSyntaxKind) -> Bool { syntaxIsBold(kind.rawValue) }
    static func syntaxIsUnderlined(_ kind: NoteSyntaxKind) -> Bool { syntaxFamily(kind.rawValue) == "link" }

    package static func syntaxAttributes(_ kind: NoteSyntaxKind, size: CGFloat = codeSize) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: syntaxColor(kind)]
        if syntaxIsBold(kind) { attributes[.font] = boldCodeFont(size: size) }
        if syntaxIsItalic(kind) { attributes[.obliqueness] = 0.12 }
        if syntaxIsUnderlined(kind) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    package static func syntaxColor(_ rawValue: String) -> NSColor {
        syntaxPalette[syntaxFamily(rawValue)] ?? codeInk
    }

    static func syntaxIsItalic(_ rawValue: String) -> Bool {
        let family = syntaxFamily(rawValue)
        return family == "comment" || family == "emphasis"
    }

    static func syntaxIsBold(_ rawValue: String) -> Bool {
        let family = syntaxFamily(rawValue)
        return family == "heading" || family == "strong"
    }

    package static func syntaxFamily(_ rawValue: String) -> String {
        let name = rawValue.lowercased()
        let families: [(String, [String])] = [
            ("comment", ["comment", "doc", "prolog", "cdata"]),
            ("keyword", ["keyword", "control", "storage", "modifier", "directive", "important", "atrule"]),
            ("string", ["string", "char", "template", "inserted"]),
            ("number", ["number", "constant", "boolean", "null", "nil", "unit", "literal"]),
            ("type", ["type", "class", "interface", "struct", "enum", "namespace", "module", "builtin"]),
            ("function", ["function", "method", "macro", "call", "selector"]),
            ("tag", ["tag", "deleted", "invalid", "error"]),
            ("attribute", ["attribute", "attr", "property", "key", "field", "label", "decorator", "annotation"]),
            ("escape", ["escape", "regex", "entity", "interpolation", "placeholder"]),
            ("operator", ["operator", "punctuation", "delimiter", "bracket"]),
            ("heading", ["heading", "title", "section"]),
            ("strong", ["strong", "bold"]),
            ("emphasis", ["emphasis", "italic"]),
            ("link", ["link", "href"]),
            ("meta", ["meta", "shebang", "pragma", "preprocessor"]),
            ("variable", ["variable", "parameter", "identifier", "plain", "text"]),
        ]
        for (family, names) in families where names.contains(where: { name.hasPrefix($0) || name.hasSuffix($0) }) {
            return family
        }
        return "plain"
    }

    private static let syntaxPalette: [String: NSColor] = [
        "comment": adaptive("Syntax.Comment", light: rgb(0x29243D, 0.5), dark: rgb(0xE4E1F5, 0.48)),
        "keyword": adaptive("Syntax.Keyword", light: rgb(0x6A1FC9), dark: rgb(0xC0A6FF)),
        "string": adaptive("Syntax.String", light: rgb(0x2A7A4B), dark: rgb(0x8FD8A9)),
        "number": adaptive("Syntax.Number", light: rgb(0xA8520C), dark: rgb(0xF5AC72)),
        "type": adaptive("Syntax.Type", light: rgb(0x0B7285), dark: rgb(0x72D4E3)),
        "function": adaptive("Syntax.Function", light: rgb(0x2350C2), dark: rgb(0x93B6FF)),
        "tag": adaptive("Syntax.Tag", light: rgb(0xB8322B), dark: rgb(0xFF8F86)),
        "attribute": adaptive("Syntax.Attribute", light: rgb(0x9A3F86), dark: rgb(0xEE9BDB)),
        "escape": adaptive("Syntax.Escape", light: rgb(0xB3366E), dark: rgb(0xFF92BF)),
        "operator": adaptive("Syntax.Operator", light: rgb(0x29243D, 0.68), dark: rgb(0xE4E1F5, 0.7)),
        "heading": adaptive("Syntax.Heading", light: rgb(0x220C7F), dark: rgb(0xC9C4FF)),
        "strong": adaptive("Syntax.Strong", light: rgb(0x29243D), dark: rgb(0xE4E1F5)),
        "emphasis": adaptive("Syntax.Emphasis", light: rgb(0x29243D), dark: rgb(0xE4E1F5)),
        "link": adaptive("Syntax.Link", light: rgb(0x2350C2), dark: rgb(0x93B6FF)),
        "meta": adaptive("Syntax.Meta", light: rgb(0x7A5C9E), dark: rgb(0xB9A5D6)),
        "variable": adaptive("Syntax.Variable", light: rgb(0x29243D), dark: rgb(0xE4E1F5)),
    ]

    nonisolated static let bodySize: CGFloat = 17
    nonisolated static let smallBodySize: CGFloat = 15
    nonisolated static let headingSizes: [CGFloat] = [30, 24, 20, 18, 17, 16]
    nonisolated static let titleSize: CGFloat = 40
    nonisolated static let smallTitleSize: CGFloat = 34
    nonisolated static let codeSize: CGFloat = 14
    nonisolated static let captionSize: CGFloat = 13.5
    nonisolated static let menuTitleSize: CGFloat = 13.5
    nonisolated static let menuSubtitleSize: CGFloat = 12
    nonisolated static let menuHeaderSize: CGFloat = 11.5
    nonisolated static let lineHeightRatio: CGFloat = 1.52
    nonisolated static let headingLineHeightRatio: CGFloat = 1.3
    nonisolated static let titleLineHeightRatio: CGFloat = 1.25

    private static func nunito(_ name: String, _ size: CGFloat, fallback: NSFont.Weight) -> NSFont {
        _ = registerFonts
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallback)
    }

    package static func nunitoRegular(_ size: CGFloat) -> NSFont { nunito("Nunito-Regular", size, fallback: .regular) }
    package static func nunitoBold(_ size: CGFloat) -> NSFont { nunito("Nunito-Bold", size, fallback: .bold) }
    package static func nunitoExtraBold(_ size: CGFloat) -> NSFont { nunito("Nunito-ExtraBold", size, fallback: .heavy) }
    static func nunitoItalic(_ size: CGFloat) -> NSFont { nunito("Nunito-Italic", size, fallback: .regular) }

    private static func garamond(_ size: CGFloat, weight: CGFloat) -> NSFont {
        _ = registerFonts
        guard let base = NSFont(name: "EBGaramond-Regular", size: size) else { return .systemFont(ofSize: size) }
        let tag = 0x77676874
        let descriptor = base.fontDescriptor.addingAttributes([.variation: [tag: weight]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    package static func bodyFont(_ font: NotePageFont, small: Bool = false, bold: Bool = false, italic: Bool = false) -> NSFont {
        _ = registerFonts
        let size: CGFloat = small ? smallBodySize : bodySize
        let base: NSFont
        switch font {
        case .standard:
            let name = bold ? (italic ? "Nunito-BoldItalic" : "Nunito-Bold") : (italic ? "Nunito-Italic" : "Nunito-Regular")
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .serif:
            base = garamond(size + 1.5, weight: bold ? 650 : 420)
        case .mono:
            base = NSFont(name: bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size - 2.5)
                ?? .monospacedSystemFont(ofSize: size - 2.5, weight: bold ? .bold : .regular)
        case .wide:
            base = NSFont(name: bold ? "ParcWide-SemiBold" : "ParcWide-Regular", size: size - 2)
                ?? .systemFont(ofSize: size - 2, weight: bold ? .semibold : .regular)
        }
        return italic ? slanted(base) : base
    }

    static func slanted(_ font: NSFont) -> NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        if converted.fontDescriptor.symbolicTraits.contains(.italic), converted.pointSize == font.pointSize { return converted }
        var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        return CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, &skew, nil) as NSFont
    }

    static func headingFont(_ level: Int, font: NotePageFont, small: Bool = false) -> NSFont {
        _ = registerFonts
        let size = headingSize(level, small: small)
        switch font {
        case .standard: return NSFont(name: "Nunito-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        case .serif: return garamond(size + 2, weight: 640)
        case .mono: return NSFont(name: "SpaceMono-Bold", size: size - 2) ?? .monospacedSystemFont(ofSize: size - 2, weight: .bold)
        case .wide: return NSFont(name: level == 1 ? "ParcWide-Black" : "ParcWide-SemiBold", size: size - 2) ?? .systemFont(ofSize: size, weight: .bold)
        }
    }

    static func headingSize(_ level: Int, small: Bool = false) -> CGFloat {
        let size = headingSizes[min(max(level, 1), 6) - 1]
        return small ? (size * smallBodySize / bodySize).rounded() : size
    }

    static func titleFont(_ font: NotePageFont) -> NSFont { titleFont(font, small: false) }

    static func titleFont(_ font: NotePageFont, small: Bool) -> NSFont {
        _ = registerFonts
        let size = small ? smallTitleSize : titleSize
        switch font {
        case .standard: return NSFont(name: "Nunito-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        case .serif: return garamond(size + 4, weight: 640)
        case .mono: return NSFont(name: "SpaceMono-Bold", size: size - 6) ?? .monospacedSystemFont(ofSize: size - 6, weight: .bold)
        case .wide: return NSFont(name: "ParcWide-Black", size: size - 6) ?? .systemFont(ofSize: size - 6, weight: .black)
        }
    }

    package static func codeFont(size: CGFloat = 14) -> NSFont {
        _ = registerFonts
        return NSFont(name: "SpaceMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func boldCodeFont(size: CGFloat = 14) -> NSFont {
        _ = registerFonts
        return NSFont(name: "SpaceMono-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static func inlineCodeFont(relativeTo font: NSFont) -> NSFont { codeFont(size: (font.pointSize * 0.85).rounded()) }

    package static func captionFont(_ font: NotePageFont = .standard) -> NSFont {
        switch font {
        case .serif: return garamond(captionSize + 1, weight: 420)
        case .mono: return codeFont(size: captionSize - 2)
        default: return nunitoRegular(captionSize)
        }
    }

    package static func menuTitleFont() -> NSFont { nunitoBold(menuTitleSize) }
    package static func menuSubtitleFont() -> NSFont { nunitoRegular(menuSubtitleSize) }
    package static func menuHeaderFont() -> NSFont { nunitoExtraBold(menuHeaderSize) }
    package static func chromeFont(_ size: CGFloat = 13) -> NSFont { nunitoBold(size) }

    package static func textStyle(_ role: NoteTextRole, font: NotePageFont = .standard, small: Bool = false) -> NoteTextStyle {
        let body = small ? smallBodySize : bodySize
        let bodyLine = (body * lineHeightRatio).rounded()
        switch role {
        case .title:
            let face = titleFont(font, small: small)
            return NoteTextStyle(font: face, lineHeight: (face.pointSize * titleLineHeightRatio).rounded(), ink: titleInk,
                                 kern: font == .standard ? -0.4 : 0)
        case .heading(let level):
            let face = headingFont(level, font: font, small: small)
            return NoteTextStyle(font: face, lineHeight: max(bodyLine, (face.pointSize * headingLineHeightRatio).rounded()),
                                 ink: level >= 6 ? secondaryInk : ink, kern: level <= 2 && font == .standard ? -0.2 : 0)
        case .body, .tableCell, .callout:
            return NoteTextStyle(font: bodyFont(font, small: small), lineHeight: bodyLine, ink: ink)
        case .tableHeader:
            return NoteTextStyle(font: bodyFont(font, small: small, bold: true), lineHeight: bodyLine, ink: ink)
        case .quote:
            return NoteTextStyle(font: bodyFont(font, small: small), lineHeight: bodyLine, ink: ink)
        case .listMarker:
            return NoteTextStyle(font: bodyFont(font, small: small), lineHeight: bodyLine, ink: ink)
        case .code:
            let size = small ? codeSize - 1.5 : codeSize
            return NoteTextStyle(font: codeFont(size: size), lineHeight: (size * 1.6).rounded(), ink: codeInk)
        case .inlineCode:
            let host = textStyle(.body, font: font, small: small)
            return NoteTextStyle(font: inlineCodeFont(relativeTo: host.font), lineHeight: bodyLine, ink: inlineCodeInk,
                                 baselineShift: host.baselineOffset)
        case .caption:
            let face = captionFont(font)
            return NoteTextStyle(font: face, lineHeight: (face.pointSize * 1.45).rounded(), ink: secondaryInk)
        case .placeholder:
            return NoteTextStyle(font: bodyFont(font, small: small), lineHeight: bodyLine, ink: placeholderInk)
        case .mention:
            return NoteTextStyle(font: bodyFont(font, small: small), lineHeight: bodyLine, ink: mentionInk)
        }
    }

    static func placeholder(for kind: NoteBlockKind, level: Int = 1) -> String {
        switch kind {
        case .heading: return "Heading \(min(max(level, 1), 6))"
        case .bulletedItem, .numberedItem: return "List"
        case .todo: return "To-do"
        case .toggle: return "Toggle"
        case .quote: return "Quote someone wise"
        case .callout: return "Say something worth a callout"
        case .code: return "Write some code"
        case .equation: return "E = mc²"
        default: return "Type / for blocks, or just start writing"
        }
    }

    nonisolated static let titlePlaceholder = "Untitled"
    nonisolated static let captionPlaceholder = "Add a caption"

    nonisolated static let pageColumnWidth: CGFloat = 720
    nonisolated static let fullWidthMaximum: CGFloat = 1600
    nonisolated static let pageSideMargin: CGFloat = 96
    nonisolated static let minimumSideMargin: CGFloat = 28
    nonisolated static let pageTopMargin: CGFloat = 64
    nonisolated static let pageBottomMargin: CGFloat = 160
    nonisolated static let titleSpacingAfter: CGFloat = 12
    nonisolated static let indentWidth: CGFloat = 26
    nonisolated static let blockSpacing: CGFloat = 2
    nonisolated static let blockVerticalPadding: CGFloat = 3
    nonisolated static let gutterWidth: CGFloat = 46
    static let handleSize = NSSize(width: 18, height: 24)
    nonisolated static let handleGap: CGFloat = 4
    nonisolated static let columnGap: CGFloat = 46
    nonisolated static let columnMinimumWidth: CGFloat = 120
    nonisolated static let listMarkerWidth: CGFloat = 26
    nonisolated static let todoBoxSize: CGFloat = 16
    nonisolated static let toggleTriangleSize: CGFloat = 22
    nonisolated static let quoteBarWidth: CGFloat = 3
    nonisolated static let quoteInset: CGFloat = 14
    static let calloutPadding = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 18)
    nonisolated static let calloutIconSize: CGFloat = 22
    static let codePadding = NSEdgeInsets(top: 30, left: 18, bottom: 18, right: 18)
    nonisolated static let dividerHeight: CGFloat = 13
    nonisolated static let dropIndicatorThickness: CGFloat = 3
    nonisolated static let mediaRadius: CGFloat = 6
    nonisolated static let inlineCodeRadius: CGFloat = 4
    package nonisolated static let menuRadius: CGFloat = 12
    package nonisolated static let menuInset: CGFloat = 6
    package nonisolated static let menuRowHeight: CGFloat = 34
    nonisolated static let menuDetailedRowHeight: CGFloat = 46
    nonisolated static let menuHeaderHeight: CGFloat = 28
    package nonisolated static let menuSeparatorSlot: CGFloat = 9
    package nonisolated static let menuHighlightRadius: CGFloat = 6
    package nonisolated static let menuGap: CGFloat = 6
    package nonisolated static let menuScreenMargin: CGFloat = 8
    package nonisolated static let controlRadius: CGFloat = 6
    package nonisolated static let blockRadius: CGFloat = 6
    package nonisolated static let toolbarHeight: CGFloat = 36
    package static let toolbarButtonSize = NSSize(width: 28, height: 28)
    package nonisolated static let keycapSide: CGFloat = 19
    package nonisolated static let chipHeight: CGFloat = 26
    package nonisolated static let fieldHeight: CGFloat = 32

    static func spacingBefore(_ kind: NoteBlockKind, level: Int = 1, isFirst: Bool = false) -> CGFloat {
        guard !isFirst else { return 0 }
        switch kind {
        case .heading:
            switch level {
            case 1: return 26
            case 2: return 18
            case 3: return 12
            default: return 8
            }
        case .divider: return 2
        case .code, .callout, .table, .image, .video, .embed, .bookmark, .equation: return 6
        case .columns: return 4
        default: return blockSpacing
        }
    }

    static func spacingAfter(_ kind: NoteBlockKind, level: Int = 1) -> CGFloat {
        switch kind {
        case .heading: return level <= 2 ? 2 : 1
        case .code, .callout, .table, .image, .video, .embed, .bookmark, .equation: return 6
        default: return blockSpacing
        }
    }

    static func contentWidth(forViewport width: CGFloat, fullWidth: Bool = false) -> CGFloat {
        let margin = sideMargin(forViewport: width, fullWidth: fullWidth)
        let available = max(0, width - margin * 2)
        return fullWidth ? min(available, fullWidthMaximum) : min(pageColumnWidth, available)
    }

    static func sideMargin(forViewport width: CGFloat, fullWidth: Bool = false) -> CGFloat {
        let spare = width - pageColumnWidth
        if fullWidth { return max(minimumSideMargin, min(pageSideMargin, width * 0.08)) }
        return max(minimumSideMargin, min(pageSideMargin, spare / 2))
    }

    package static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
