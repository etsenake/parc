import AppKit

/// A decorative original-page image. A delayed history lookup may only fill
/// the same visible row generation; it never changes tab selection or state.
final class SidebarFaviconView: NSImageView {
    var fallbackTintColor: NSColor? { didSet { if !hasFavicon { contentTintColor = fallbackTintColor } } }
    private var generation: UInt64 = 0
    private var fallback: NSImage?
    private var hasFavicon = false
    /// Template fallbacks must paint `SemanticColorPalette.title` instead of
    /// sampling the window's light/dark appearance through vibrancy.
    override var allowsVibrancy: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyDown
        setAccessibilityElement(false)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    /// Pointer input over the image belongs to the row or its reset region.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// True once a non-nil page image filled this generation (not the themed
    /// fallback glyph). Used to skip true no-op re-arms across row rebuilds.
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

    /// Install already-settled page art without starting a new lookup. Cancels
    /// any in-flight `load` for this view. Seeds `fallback` from the current
    /// themed glyph when still unset so a later `load` / `reloadFavicon` keeps
    /// a non-nil interim image instead of clearing to nil.
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
