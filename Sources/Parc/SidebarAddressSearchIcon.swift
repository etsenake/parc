import AppKit
import QuartzCore

@MainActor final class SidebarAddressSearchIcon: NSImageView {
    static let placeholder = SidebarAddressText.placeholder
    static func host(of url: URL) -> String? { SidebarAddressText.host(of: url) }
    static let centerX: CGFloat = 16
    static let textIndent: CGFloat = 32
    static let side: CGFloat = 14
    static let glyph = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = Self.glyph
        imageScaling = .scaleNone
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
