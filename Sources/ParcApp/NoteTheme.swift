import AppKit
import CoreText

@MainActor
enum NoteTheme {
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

    static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("Parc.Notes." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static let ink = adaptive("Ink", light: rgb(0x1F1B2E), dark: rgb(0xEDEBFA))
    static let titleInk = adaptive("TitleInk", light: rgb(0x220C7F), dark: rgb(0xE6E6FF))
    static let secondaryInk = adaptive("SecondaryInk", light: rgb(0x1F1B2E, 0.62), dark: rgb(0xEDEBFA, 0.62))
    static let tertiaryInk = adaptive("TertiaryInk", light: rgb(0x1F1B2E, 0.38), dark: rgb(0xEDEBFA, 0.38))
    static let placeholderInk = adaptive("Placeholder", light: rgb(0x220C7F, 0.32), dark: rgb(0xE6E6FF, 0.32))
    static let accent = adaptive("Accent", light: rgb(0x2702C2), dark: rgb(0x9380E0))
    static let caret = accent
    static let selection = adaptive("Selection", light: rgb(0xCDCDFF), dark: rgb(0x5235CE, 0.75))
    static let blockSelection = adaptive("BlockSelection", light: rgb(0x2702C2, 0.10), dark: rgb(0x9380E0, 0.20))
    static let link = adaptive("Link", light: rgb(0x220C7F), dark: rgb(0xE6E6FF))
    static let hoverFill = adaptive("Hover", light: rgb(0x1F1B2E, 0.06), dark: rgb(0xFFFFFF, 0.08))
    static let pressedFill = adaptive("Pressed", light: rgb(0x1F1B2E, 0.11), dark: rgb(0xFFFFFF, 0.14))
    static let separator = adaptive("Separator", light: rgb(0x1F1B2E, 0.12), dark: rgb(0xFFFFFF, 0.14))
    static let codeBackground = adaptive("CodeBackground", light: rgb(0x1F1B2E, 0.045), dark: rgb(0xFFFFFF, 0.06))
    static let inlineCodeBackground = adaptive("InlineCodeBackground", light: rgb(0x2702C2, 0.07), dark: rgb(0x9380E0, 0.18))
    static let inlineCodeInk = adaptive("InlineCodeInk", light: rgb(0xC0306A), dark: rgb(0xFF8FB8))
    static let panelFill = adaptive("PanelFill", light: rgb(0xFFFFFF, 0.92), dark: rgb(0x2A2733, 0.94))
    static let panelStroke = adaptive("PanelStroke", light: rgb(0x1F1B2E, 0.10), dark: rgb(0xFFFFFF, 0.12))
    static let paper = adaptive("Paper", light: rgb(0xFFFFFF, 0.85), dark: rgb(0x000000, 0.5))

    private static let palette: [NoteColor: (text: (UInt32, UInt32), background: (UInt32, UInt32))] = [
        .gray: ((0x787774, 0x9B9B9B), (0xF1F1EF, 0x2F2F2F)),
        .brown: ((0x9F6B53, 0xBA856F), (0xF4EEEE, 0x4A3228)),
        .orange: ((0xD9730D, 0xC77D48), (0xFBECDD, 0x5C3B23)),
        .yellow: ((0xCB912F, 0xCA9849), (0xFBF3DB, 0x564328)),
        .green: ((0x448361, 0x529E72), (0xEDF3EC, 0x243D30)),
        .blue: ((0x337EA9, 0x379AD3), (0xE7F3F8, 0x143A4E)),
        .purple: ((0x9065B0, 0x9D68D3), (0xF6F3F9, 0x3C2D49)),
        .pink: ((0xC14C8A, 0xD15796), (0xFAF1F5, 0x4E2C3C)),
        .red: ((0xD44C47, 0xDF5452), (0xFDEBEC, 0x522E2A)),
    ]

    static func color(_ style: NoteColorStyle) -> NSColor {
        let entry = palette[style.color]!
        let pair = style.isBackground ? entry.background : entry.text
        return adaptive((style.isBackground ? "Background." : "Text.") + style.color.rawValue, light: rgb(pair.0), dark: rgb(pair.1))
    }

    static func displayName(_ color: NoteColor) -> String { color.rawValue.capitalized }

    static func bodyFont(_ font: NotePageFont, small: Bool = false, bold: Bool = false, italic: Bool = false) -> NSFont {
        _ = registerFonts
        let size: CGFloat = small ? 15 : 17
        let base: NSFont
        switch font {
        case .standard:
            let name = bold ? (italic ? "Nunito-BoldItalic" : "Nunito-Bold") : (italic ? "Nunito-Italic" : "Nunito-Regular")
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .serif:
            base = NSFont(name: "EBGaramond-Regular", size: size + 1) ?? .systemFont(ofSize: size)
        case .mono:
            base = NSFont(name: bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size - 2) ?? .monospacedSystemFont(ofSize: size - 2, weight: .regular)
        case .wide:
            base = NSFont(name: bold ? "ParcWide-SemiBold" : "ParcWide-Regular", size: size - 1) ?? .systemFont(ofSize: size)
        }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return traits.isEmpty ? base : NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    static func headingFont(_ level: Int, font: NotePageFont, small: Bool = false) -> NSFont {
        _ = registerFonts
        let sizes: [CGFloat] = [30, 24, 20, 18, 17, 16]
        let size = sizes[min(max(level, 1), 6) - 1] - (small ? 3 : 0)
        switch font {
        case .standard: return NSFont(name: "Nunito-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
        case .serif:
            let base = NSFont(name: "EBGaramond-Regular", size: size + 2) ?? .systemFont(ofSize: size)
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        case .mono: return NSFont(name: "SpaceMono-Bold", size: size - 2) ?? .monospacedSystemFont(ofSize: size - 2, weight: .bold)
        case .wide: return NSFont(name: level == 1 ? "ParcWide-Black" : "ParcWide-SemiBold", size: size - 2) ?? .systemFont(ofSize: size, weight: .bold)
        }
    }

    static func titleFont(_ font: NotePageFont) -> NSFont {
        _ = registerFonts
        switch font {
        case .standard: return NSFont(name: "Nunito-ExtraBold", size: 40) ?? .systemFont(ofSize: 40, weight: .heavy)
        case .serif:
            let base = NSFont(name: "EBGaramond-Regular", size: 44) ?? .systemFont(ofSize: 40)
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        case .mono: return NSFont(name: "SpaceMono-Bold", size: 34) ?? .monospacedSystemFont(ofSize: 34, weight: .bold)
        case .wide: return NSFont(name: "ParcWide-Black", size: 34) ?? .systemFont(ofSize: 34, weight: .black)
        }
    }

    static func codeFont(size: CGFloat = 14) -> NSFont {
        _ = registerFonts
        return NSFont(name: "SpaceMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let pageColumnWidth: CGFloat = 720
    static let pageSideMargin: CGFloat = 96
    static let minimumSideMargin: CGFloat = 28
    static let indentWidth: CGFloat = 26
    static let blockSpacing: CGFloat = 2
    static let gutterWidth: CGFloat = 46
    static let columnGap: CGFloat = 46
    static let menuRadius: CGFloat = 12
    static let controlRadius: CGFloat = 6
    static let blockRadius: CGFloat = 6

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
