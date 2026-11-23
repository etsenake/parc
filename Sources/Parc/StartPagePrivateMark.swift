import AppKit

@MainActor
final class StartPagePrivateMarkView: NSView {
    static let size = CGSize(width: 96, height: 96)
    static let cornerRadius: CGFloat = 22

    static let artwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "PrivateMark", withExtension: "png", subdirectory: "PrivateMark"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        return image
    }()

    private let tile = CALayer()
    private let image: NSImage?

    var hasArtwork: Bool { image != nil }

    convenience init() { self.init(image: Self.artwork) }

    init(image: NSImage?) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        tile.cornerRadius = Self.cornerRadius
        tile.cornerCurve = .continuous
        tile.masksToBounds = true
        tile.contentsGravity = .resizeAspectFill
        tile.contents = image
        layer?.addSublayer(tile)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tile.frame = bounds
        tile.contentsScale = window?.backingScaleFactor ?? 2
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        CATransaction.commit()
    }
}
