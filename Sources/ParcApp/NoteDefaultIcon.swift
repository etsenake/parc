import AppKit

@MainActor
enum NoteDefaultIcon {
    static let artwork: CGFloat = 18
    private static var cards: [Bool: NSImage] = [:]
    private static var images: [CGFloat: NSImage] = [:]

    static func card(dark: Bool) -> NSImage? {
        if let image = cards[dark] { return image }
        guard let image = LibraryArtwork.card("note", dark: dark, side: artwork) else { return nil }
        cards[dark] = image
        return image
    }

    static func image(size: CGFloat) -> NSImage {
        if let image = images[size] { return image }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            card(dark: dark)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
            return true
        }
        image.cacheMode = .never
        image.accessibilityDescription = "Note"
        images[size] = image
        return image
    }

    static func fallback(named name: String, size: CGFloat = 16) -> NSImage? {
        name == InternalPage.noteFallbackSymbol ? image(size: size) : NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
