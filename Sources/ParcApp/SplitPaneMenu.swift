import AppKit

@MainActor
enum SplitPaneMenu {
    ///
    /// item its own `ContextMenus` artwork (`SplitPaneMenuArtwork`). The split's
    /// orientation picks the Separate, Convert and Share variants: item types 5,
    /// 7 and 9 for a horizontal split, 6, 8 and 10 for a vertical one.
    static func make(orientation: SplitOrientation, index: Int, count: Int,
                     prepare: (SplitPaneOperation) -> (() -> Void)?) -> NSMenu {
        let vertical = orientation == .vertical
        // The original content-panel producer has a separate single-content
        // list: both orientations are available before a split exists.
        let horizontal: [(String, String, SplitPaneOperation)?] = [
            ("Add Left Split", "icon-split-add-left", .addBefore),
            ("Add Right Split", "icon-split-add-right", .addAfter)
        ]
        let populatedHorizontal: [(String, String, SplitPaneOperation)?] = [
            ("Add Right Split", "icon-split-add-right", .addAfter),
            ("Add Left Split", "icon-split-add-left", .addBefore)
        ]
        let verticalAdds: [(String, String, SplitPaneOperation)?] = [
            ("Add Top Split", "icon-split-add-top", .addAbove),
            ("Add Bottom Split", "icon-split-add-bottom", .addBelow)
        ]
        let rows: [(String, String, SplitPaneOperation)?]
        if count == 1 {
            rows = horizontal + [nil] + verticalAdds
        } else if (2...4).contains(count) {
            rows = [
                (vertical ? "Move Up" : "Move Left", vertical ? "icon-split-move-top" : "icon-split-move-left", .movePrevious),
                (vertical ? "Move Down" : "Move Right", vertical ? "icon-split-move-bottom" : "icon-split-move-right", .moveNext), nil
            ] + (vertical ? verticalAdds : populatedHorizontal) + [
                nil, ("Separate Tab from Split",
                      vertical ? "icon-separate-from-split-menu-bottom" : "icon-separate-from-split", .separate),
                (vertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View",
                 vertical ? "icon-split-horizontal" : "icon-split-vertical", .flip),
                nil, ("Share Split View…", vertical ? "icon-split-share-vertical" : "icon-split-share-horizontal", .share)
            ]
        } else {
            rows = []
        }
        let menu = NSMenu(title: "Split View Controls Menu")
        menu.autoenablesItems = false
        for row in rows {
            guard let (title, artwork, operation) = row else { menu.addItem(.separator()); continue }
            let action = operation.isEnabled(index: index, count: count) ? prepare(operation) : nil
            let target = SplitPaneMenuAction(action)
            let item = NSMenuItem(title: title, action: #selector(SplitPaneMenuAction.invoke), keyEquivalent: "")
            item.target = target; item.representedObject = target
            item.showImage(SplitPaneMenuArtwork.image(artwork))
            item.isEnabled = action != nil; menu.addItem(item)
        }
        return menu
    }
}

///
///
///
/// Convert. The catalog has light and dark renditions and no template: the
/// frame is a lighter tone than the arrow or plus, and Separate's arrow is
/// blue. Each image draws the rendition for the appearance it is drawn in.
@MainActor
enum SplitPaneMenuArtwork {
    static let directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("SplitPaneMenu", isDirectory: true)
    private static var renditions: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        guard let light = rendition(name), let dark = rendition(name + "-dark") else { return nil }
        let image = NSImage(size: light.size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (isDark ? dark : light).draw(in: rect)
            return true
        }
        // A menu draws in its own appearance; never reuse another's raster.
        image.cacheMode = .never
        return image
    }

    private static func rendition(_ name: String) -> NSImage? {
        if let cached = renditions[name] { return cached }
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(name + ".png")),
              let base = NSBitmapImageRep(data: data) else { return nil }
        base.size = NSSize(width: base.pixelsWide, height: base.pixelsHigh)
        let image = NSImage(size: base.size)
        image.addRepresentation(base)
        if let data = try? Data(contentsOf: directory.appendingPathComponent(name + "@2x.png")),
           let double = NSBitmapImageRep(data: data) {
            double.size = NSSize(width: CGFloat(double.pixelsWide) / 2, height: CGFloat(double.pixelsHigh) / 2)
            image.addRepresentation(double)
        }
        renditions[name] = image
        return image
    }
}

@MainActor
private final class SplitPaneMenuAction: NSObject {
    let action: (() -> Void)?
    init(_ action: (() -> Void)?) { self.action = action }
    @objc func invoke() { action?() }
}

/// This original-window draft has no URL, saved item or native page. Canceling
/// it removes only the presentation; a chosen request is owned by its callback.
@MainActor
final class SplitPaneInsertionSession {
    let id = UUID()
    let request: SplitPaneInsertion
    let placeholder = SplitPanePlaceholder(frame: .zero)
    let candidateIDs: Set<UUID>
    let validate: () -> Bool
    var submitting = false
    private(set) var cancelled = false
    init(request: SplitPaneInsertion, candidateIDs: Set<UUID>, validate: @escaping () -> Bool) {
        self.request = request; self.candidateIDs = candidateIDs; self.validate = validate
    }
    var isValid: Bool { !cancelled && validate() }
    func cancel() { cancelled = true; placeholder.removeFromSuperview() }
}

///
///
///
/// the command bar is the only input owner while the pane is pending. A window
/// with no tab open shows the same content.
///
///
///
/// only the scrim loader), so it follows the window's own appearance.
@MainActor
final class SplitPanePlaceholder: NSView {
    /// White at 0.666 alpha (light) or 0.1 alpha (dark), resolved per appearance.
    static let emptyContentBackground = NSColor(name: "emptyWindowContentBackgroundColor") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 1, green: 1, blue: 1, alpha: 0.1)
            : NSColor(red: 1, green: 1, blue: 1, alpha: 0.666)
    }
    let splitHighlight = SplitPaneHighlight()
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        splitHighlight.attach(to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.group); setAccessibilityLabel("New split pane")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Self.emptyContentBackground.cgColor
        }
        splitHighlight.refreshColor()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
    override func layout() {
        super.layout()
        splitHighlight.layout(bounds: bounds, cornerRadius: layer?.cornerRadius ?? 0)
    }
}
