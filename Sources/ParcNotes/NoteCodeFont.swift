import AppKit

@MainActor
enum NoteCodeFont {
    private static var cache: [String: NSFont] = [:]

    static func literal(_ font: NSFont) -> NSFont {
        let key = "\(font.fontName)@\(font.pointSize)"
        if let cached = cache[key] { return cached }
        let settings: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kRareLigaturesOffSelector],
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
        ]
        let descriptor = font.fontDescriptor.addingAttributes([.featureSettings: settings])
        let literal = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        cache[key] = literal
        return literal
    }

    static func code(size: CGFloat) -> NSFont { literal(NoteTheme.codeFont(size: size)) }
}
