import AppKit
import CoreText

enum SidebarIconCatalog {
    enum Font: String { case ionicons, icomoon }

    static let resourceDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
    private static var descriptors: [Font: CTFontDescriptor] = [:]
    private static var assets: [String: NSImage] = [:]
    private static let cache = NSCache<NSString, NSImage>()

    static func font(_ font: Font, size: CGFloat) -> NSFont {
        if descriptors[font] == nil,
           let url = resourceDirectory?.appendingPathComponent(font.rawValue + ".ttf"),
           let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = found.first {
            descriptors[font] = first
        }
        guard let descriptor = descriptors[font] else { return .systemFont(ofSize: size) }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    static func glyph(_ type: SidebarIconType) -> UInt32? { glyphs[type] }
    private static let glyphs: [SidebarIconType: UInt32] = [
        .star: 0xF53B, .bookmark: 0xF193, .heart: 0xF33D, .flag: 0xF2DA,
        .flash: 0xF2E3, .triangle: 0xF598, .medical: 0xF3F7, .notifications: 0xF42D,
        .bulb: 0xF1A8, .shapes: 0xF517, .grid: 0xF31C, .apps: 0xF121,
        .layers: 0xF370, .server: 0xF511, .albums: 0xF10F, .copy: 0xF26B,
        .folder: 0xF2F2, .fileTrayFull: 0xF2C5, .calendar: 0xF1B7, .mail: 0xF3E5,
        .checkbox: 0xF1FC, .document: 0xF286, .book: 0xF190, .chatBubbleEllipses: 0xF1F3,
        .people: 0xF451, .terminal: 0xF565, .construction: 0xF262, .square: 0xF535,
        .egg: 0xF29B, .ellipse: 0xF29E, .moon: 0xF40F, .sunny: 0xF54D,
        .planet: 0xF472, .leaf: 0xF373, .cloud: 0xF23B, .paw: 0xF448,
        .bag: 0xF166, .gift: 0xF2FE, .bed: 0xF17B, .restaurant: 0xF4E1,
        .barbell: 0xF15D, .airplane: 0xF109, .musicalNote: 0xF418, .colorPallete: 0xF259,
        .video: 0xF5A4, .bandage: 0xF157, .code: 0xF24D, .baseball: 0xF163,
        .cloudOutline: 0xF236, .map: 0xF3F1, .bonfire: 0xF18D, .pizza: 0xF46F,
        .skull: 0xF52C, .receipt: 0xF4BA, .thumbsUp: 0xF571, .train: 0xF586,
        .rss: 0xF3C1, .github: 0xF3AB, .search: 0xF50B
    ]

    static func image(for type: SidebarIconType, size: CGFloat) -> NSImage {
        if let code = glyph(type), let scalar = Unicode.Scalar(code) {
            return glyphImage(String(Character(scalar)), font: .ionicons, size: size)
        }
        let key = "asset|\(type.rawValue)|\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let light = asset(type.rawValue), dark = type == .linear ? asset("linear-dark") : nil
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (isDark ? dark ?? light : light)?.draw(in: rect)
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    static func glyphImage(_ string: String, font: Font, size: CGFloat) -> NSImage {
        let key = "\(font.rawValue)|\(size)|\(string)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let text = NSAttributedString(string: string, attributes: [.font: self.font(font, size: size), .foregroundColor: NSColor.black])
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let measured = text.size()
            text.draw(at: NSPoint(x: (rect.width - measured.width) * 0.5, y: (rect.height - measured.height) * 0.5))
            return true
        }
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }

    static func featherImage(_ code: UInt32, size: CGFloat) -> NSImage {
        glyphImage(Unicode.Scalar(code).map { String(Character($0)) } ?? "", font: .icomoon, size: size)
    }

    static func emojiImage(_ emoji: String, size: CGFloat) -> NSImage {
        let key = "emoji|\(size)|\(emoji)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let text = NSAttributedString(string: emoji, attributes: [.font: font(.icomoon, size: size)])
        let measured = text.size()
        let side = ceil(max(measured.width, measured.height) * 1.1)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            text.draw(at: NSPoint(x: (rect.width - measured.width) / 2, y: (rect.height - measured.height) / 2))
            return true
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func asset(_ name: String) -> NSImage? {
        if let image = assets[name] { return image }
        guard let directory = resourceDirectory,
              let image = NSImage(contentsOf: directory.appendingPathComponent(name + ".png")) else { return nil }
        if let retina = NSImageRep(contentsOf: directory.appendingPathComponent(name + "@2x.png")) {
            retina.size = image.size; image.addRepresentation(retina)
        }
        assets[name] = image
        return image
    }

    static let brandGray = NSColor(displayP3Red: 0.4941, green: 0.4941, blue: 0.4941, alpha: 1)
    static func customizationBackground(dark: Bool) -> NSColor {
        dark ? NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 0.25)
             : NSColor(displayP3Red: 0.525, green: 0.533, blue: 0.553, alpha: 0.25)
    }
    static func foregroundSecondary(dark: Bool) -> NSColor {
        NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: 0.5)
    }
}

extension SidebarGroupIcon {
    func image(size: CGFloat) -> NSImage? {
        switch self {
        case .emoji(let value):
            let source = SidebarIconCatalog.emojiImage(value, size: size)
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                source.draw(in: rect); return true
            }
        case .icon(let type): return SidebarIconCatalog.image(for: type, size: size)
        case .symbol(let name): return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }
    var image: NSImage? {
        if case .emoji = self { return nil }
        return image(size: 16)
    }
    var emoji: String? { if case .emoji(let value) = self { return value }; return nil }
}
