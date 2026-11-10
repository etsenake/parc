import AppKit

/// Original ImportKeychainView's named color roles; sRGB values resolved from
/// ARC_ImportFeature in the installed 1.170 reference. No runtime bundle lookup.
enum OnboardingPasswordPalette {
    static let background = adaptive(
        NSColor(srgbRed: 0.878, green: 0.882, blue: 1, alpha: 1),
        NSColor(srgbRed: 25 / 255, green: 27 / 255, blue: 76 / 255, alpha: 1))
    static let border = adaptive(
        NSColor(srgbRed: 44 / 255, green: 51 / 255, blue: 225 / 255, alpha: 1),
        NSColor(srgbRed: 50 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1))
    static let foreground = adaptive(
        NSColor(srgbRed: 0.173, green: 0.2, blue: 0.886, alpha: 1), .white)
    static let symbol = adaptive(
        NSColor(srgbRed: 0.173, green: 0.2, blue: 0.886, alpha: 1),
        NSColor(srgbRed: 0.518, green: 0.533, blue: 1, alpha: 1))
    static let completedBackground = NSColor(srgbRed: 0.773, green: 0.898, blue: 0.753, alpha: 1)
    static let completedForeground = NSColor(srgbRed: 0.243, green: 0.659, blue: 0.18, alpha: 1)
    static let error = NSColor(srgbRed: 0.788, green: 0.2, blue: 0.2, alpha: 1)

    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}

/// ImportKeychainView's original click/file-drop surface (460 × 200, radius 20,
/// 2.5-point [7, 5] dashed outline). Results come from the existing CSV owner;
/// a selected file alone never produces the reference's success presentation.
@MainActor
final class OnboardingPasswordDropTarget: PointingHandButton {
    enum Presentation { case ready, working, removingExport, saved, needsAttention }
    var onChoose: (() -> Void)?
    var onDrop: ((URL) -> Void)?
    private(set) var presentation: Presentation = .ready
    private var permitsFile = false
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""; isBordered = false; setButtonType(.momentaryChange)
        target = self; action = #selector(choose)
        focusRingType = .exterior
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Choose or drop an exported passwords CSV file")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ presentation: Presentation, canImport: Bool) {
        self.presentation = presentation; permitsFile = canImport; isEnabled = canImport
        setAccessibilityValue(presentation == .saved ? "Passwords saved" :
            presentation == .working ? "Import in progress" :
            presentation == .removingExport ? "Moving the exported file to Trash" :
            presentation == .needsAttention ? "Import needs attention" : "No file selected")
        needsDisplay = true
    }

    @objc private func choose() { if permitsFile { onChoose?() } }

    override func accessibilityPerformPress() -> Bool {
        guard permitsFile && isEnabled else { return false }
        performClick(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let saved = presentation == .saved
        let color = saved ? OnboardingPasswordPalette.completedForeground :
            presentation == .needsAttention ? OnboardingPasswordPalette.error : OnboardingPasswordPalette.foreground
        let symbolColor = saved ? OnboardingPasswordPalette.completedForeground :
            presentation == .needsAttention ? OnboardingPasswordPalette.error : OnboardingPasswordPalette.symbol
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 1.25), xRadius: 20, yRadius: 20)
        (saved ? OnboardingPasswordPalette.completedBackground : OnboardingPasswordPalette.background).setFill()
        path.fill()
        (saved ? OnboardingPasswordPalette.completedForeground : OnboardingPasswordPalette.border).setStroke()
        path.lineWidth = 2.5
        path.lineCapStyle = .round; path.setLineDash([7, 5], count: 2, phase: 0); path.stroke()
        let symbol = presentation == .saved ? "checkmark.circle" :
            presentation == .needsAttention ? "exclamationmark.circle" : "doc"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 28, weight: .semibold))?
            .withSymbolConfiguration(.init(paletteColors: [symbolColor]))
        image?.draw(in: NSRect(x: bounds.midX - 15, y: 47, width: 30, height: 30),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let text: String
        switch presentation {
        case .ready: text = "Drag or click here to upload\npasswords file"
        case .working: text = "Importing passwords…"
        case .removingExport: text = "Removing the exported file…"
        case .saved: text = "Success!"
        case .needsAttention: text = "Review your password import"
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: NSRect(x: 20, y: 98, width: bounds.width - 40, height: 70),
            withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: color, .paragraphStyle: paragraph])
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }

    private func admittedFile(_ sender: NSDraggingInfo) -> URL? {
        guard permitsFile,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count == 1,
              let url = urls.first, url.pathExtension.lowercased() == "csv" else { return nil }
        return url
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        admittedFile(sender) == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = admittedFile(sender) else { return false }
        onDrop?(url); return true
    }
}
