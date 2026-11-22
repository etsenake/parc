import AppKit
import QuartzCore

@MainActor package final class SidebarAddressSearchIcon: NSImageView {
    package static let placeholder = SidebarAddressText.placeholder
    package static func host(of url: URL) -> String? { SidebarAddressText.host(of: url) }
    package static let centerX: CGFloat = 16
    package static let textIndent: CGFloat = 32
    package static let side: CGFloat = 14
    package static let glyph = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))

    package override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = Self.glyph
        imageScaling = .scaleNone
        setAccessibilityElement(false)
    }
    package required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
