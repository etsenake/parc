import AppKit

final class SidebarFaviconView: NSImageView {
    var fallbackTintColor: NSColor? { didSet { if !hasFavicon { contentTintColor = fallbackTintColor } } }
    private var generation: UInt64 = 0
    private var fallback: NSImage?
    private var hasFavicon = false
    override var allowsVibrancy: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyDown
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var hasSettledFavicon: Bool { hasFavicon }

    func load(_ request: (@escaping (NSImage?) -> Void) -> Void) {
        generation &+= 1
        let original = generation
        if !hasFavicon { fallback = image }
        image = fallback; hasFavicon = false; contentTintColor = fallbackTintColor
        request { [weak self] result in
            guard let self, self.generation == original else { return }
            self.hasFavicon = result != nil
            self.image = result ?? self.fallback
            self.contentTintColor = result == nil ? self.fallbackTintColor : nil
        }
    }

    func adoptSettled(_ image: NSImage) {
        generation &+= 1
        if fallback == nil { fallback = self.image }
        hasFavicon = true
        self.image = image
        contentTintColor = nil
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { generation &+= 1 }
        super.viewWillMove(toSuperview: newSuperview)
    }
}
