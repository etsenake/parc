import AppKit

///
///
///
/// every crash kind: its state, `ADKClient.WebContentSadTabState`, holds only
/// `processTerminationStatus` and `crashedErrorCode`, and the view reads only
/// the code. 1.170 keeps the strings and layout constants.
@MainActor enum SadTabContent {
    ///
    /// English only). Square brackets mark the link that reloads the page.
    static let message = "Tab crashed. Maybe [reload] the page?"

    ///
    ///
    static func errorCode(_ code: Int) -> String { String(format: "Error code: %ld", code) }

    /// `SadTabView.TextDefinition`: one `Text` of the sentence's HStack.
    struct Segment: Equatable {
        let text: String
        let isLink: Bool
    }

    ///
    /// the text before it, the bracketed word as a link and the text after
    ///
    /// sentence one link.
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

    /// The sentence as it reads on screen, for surfaces without the link.
    static var plainMessage: String { segments(message).map(\.text).joined() }

    ///
    /// 1.170's catalog: sRGB black at 0.3, white at 0.3 in Dark Aqua) tints
    /// the artwork, the sentence, its link and the error code.
    static let foreground = NSColor(name: "ForegroundTertiary") { appearance in
        let white: CGFloat = isDark(appearance) ? 1 : 0
        return NSColor(srgbRed: white, green: white, blue: white, alpha: 0.3)
    }

    /// `SadTabView` itself is clear (`.background(Color.clear)`); behind it is
    /// the web content's backing, `FullOpacityBackgroundPrimary` for a web
    ///
    /// 1.170's catalog: opaque sRGB white, black in Dark Aqua).
    static let backing = NSColor(name: "FullOpacityBackgroundPrimary") { appearance in
        isDark(appearance) ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    }

    /// The text has no font modifier, so it takes SwiftUI's default body font.
    static var font: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
    /// One line of that font (16 points for the 13-point system font).
    static var lineHeight: CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font)) }

    private nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The copied artwork (Resources/SadTab).
    static let artworkDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SadTab", isDirectory: true)
    private static var cachedArtwork: NSImage?

    ///
    /// bitmaps and the vector at the 96 × 103 point size.
    static var artwork: NSImage? {
        if let cachedArtwork { return cachedArtwork }
        guard let directory = artworkDirectory,
              let data = try? Data(contentsOf: directory.appendingPathComponent("SadTab.png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        let size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        base.size = size
        let image = NSImage(size: size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("SadTab@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = size
            image.addRepresentation(double)
        }
        // The vector, when this system decodes SVG; the bitmaps cover 1× and 2×.
        if let vector = NSImage(contentsOf: directory.appendingPathComponent("SadTab.svg")) {
            for representation in vector.representations { image.addRepresentation(representation) }
        }
        image.isTemplate = true
        cachedArtwork = image
        return image
    }

    /// `Image(…).resizable().aspectRatio(contentMode: .fit).frame(height: 96)`
    ///
    static let artworkSize = NSSize(width: 96 * 96 / 103, height: 96)
    ///
    static let artworkSpacing: CGFloat = 64
    ///
    static let cornerInset: CGFloat = 20
}
