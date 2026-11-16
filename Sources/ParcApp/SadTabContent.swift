import AppKit

@MainActor enum SadTabContent {
    static let message = "Tab crashed. Maybe [reload] the page?"

    static func errorCode(_ code: Int) -> String { String(format: "Error code: %ld", code) }

    struct Segment: Equatable {
        let text: String
        let isLink: Bool
    }

    static func segments(_ text: String) -> [Segment] {
        guard let expression = try? NSRegularExpression(pattern: "\\[\\w+\\]"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return [Segment(text: text, isLink: true)] }
        var result: [Segment] = []
        if range.lowerBound > text.startIndex { result.append(Segment(text: String(text[..<range.lowerBound]), isLink: false)) }
        let inner = text.index(after: range.lowerBound)..<text.index(before: range.upperBound)
        result.append(Segment(text: String(text[inner]), isLink: true))
        if range.upperBound < text.endIndex { result.append(Segment(text: String(text[range.upperBound...]), isLink: false)) }
        return result
    }

    static var plainMessage: String { segments(message).map(\.text).joined() }

    static let foreground = NSColor(name: "ForegroundTertiary") { appearance in
        let white: CGFloat = isDark(appearance) ? 1 : 0
        return NSColor(srgbRed: white, green: white, blue: white, alpha: 0.3)
    }

    static let backing = NSColor(name: "FullOpacityBackgroundPrimary") { appearance in
        isDark(appearance) ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    static var lineHeight: CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font)) }

    private nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static let artworkDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SadTab", isDirectory: true)
    static let navigationArtworkDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("PageFailure", isDirectory: true)
    private static var cachedArtwork: NSImage?
    private static var cachedNavigationArtwork: NSImage?

    static var artwork: NSImage? {
        if let cachedArtwork { return cachedArtwork }
        cachedArtwork = templateImage(in: artworkDirectory, named: "SadTab")
        return cachedArtwork
    }

    static var navigationArtwork: NSImage? {
        if let cachedNavigationArtwork { return cachedNavigationArtwork }
        cachedNavigationArtwork = templateImage(in: navigationArtworkDirectory, named: "PageFailure")
        return cachedNavigationArtwork
    }

    private static func templateImage(in directory: URL?, named name: String) -> NSImage? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("\(name).png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("\(name)@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = size
            image.addRepresentation(double)
        }
        if let vector = NSImage(contentsOf: directory.appendingPathComponent("\(name).svg")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        return image
    }

    static let artworkSize = NSSize(width: 96 * 96 / 103, height: 96)
    static let navigationArtworkSize = NSSize(width: 96, height: 96)
    static let artworkSpacing: CGFloat = 64
    static let cornerInset: CGFloat = 20
}
