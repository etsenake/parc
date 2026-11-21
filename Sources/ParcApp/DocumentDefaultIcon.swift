import AppKit

@MainActor
enum DocumentDefaultIcon: String {
    case note, easel

    static let artwork: CGFloat = 18
    private static var cards: [String: NSImage] = [:]
    private static var images: [String: NSImage] = [:]

    var symbol: String { "parc." + rawValue }

    init?(symbol: String) {
        guard symbol.hasPrefix("parc.") else { return nil }
        self.init(rawValue: String(symbol.dropFirst(5)))
    }

    func card(dark: Bool) -> NSImage? {
        let key = rawValue + (dark ? "-dark" : "")
        if let image = Self.cards[key] { return image }
        guard let image = LibraryArtwork.card(rawValue, dark: dark, side: Self.artwork) else { return nil }
        Self.cards[key] = image
        return image
    }

    func image(size: CGFloat) -> NSImage {
        let key = "\(rawValue)@\(size)"
        if let image = Self.images[key] { return image }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            self.card(dark: dark)?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                                        hints: [.interpolation: NSImageInterpolation.high.rawValue])
            return true
        }
        image.cacheMode = .never
        image.accessibilityDescription = self == .note ? "Note" : "Easel"
        Self.images[key] = image
        return image
    }

    static func fallback(named name: String, size: CGFloat = 16) -> NSImage? {
        DocumentDefaultIcon(symbol: name)?.image(size: size) ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
