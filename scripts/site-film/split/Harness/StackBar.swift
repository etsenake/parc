import AppKit
import CoreImage
@testable import Parc
@testable import ParcKit
@testable import ParcCommandBar
import ParcCore

struct BarRow {
    let id: String
    let title: String
    var subtitle: String? = nil
    var accessory: String = ""
    var isTab = false
    var icon: NSImage?
    var isAction = false
}

@MainActor final class BarOverlay: NSView {
    var bar = NSRect.zero
    var backdrop: CGImage?
    var shown = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard shown, let context = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil)
        let scale = context.convertToDeviceSpace(CGSize(width: 1, height: 1)).width
        context.saveGState()
        let outside = CGMutablePath(); outside.addRect(bounds.insetBy(dx: -200, dy: -200)); outside.addPath(path)
        context.addPath(outside); context.clip(using: .evenOdd)
        context.setShadow(offset: CGSize(width: 0, height: 24 * abs(scale)), blur: 48 * abs(scale),
                          color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(path); context.setFillColor(NSColor.black.cgColor); context.fillPath()
        context.restoreGState()
        guard let backdrop else { return }
        context.saveGState()
        context.addPath(path); context.clip()
        context.translateBy(x: bar.minX, y: bar.maxY); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(backdrop, in: CGRect(origin: .zero, size: bar.size))
        context.restoreGState()
    }
}

@MainActor final class BarCaret: NSView {
    var opacity: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard opacity > 0 else { return }
        NSColor(srgbRed: 0, green: 0.533, blue: 1, alpha: opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1, yRadius: 1).fill()
    }
}

@MainActor final class StackBar {
    final class FlippedBox: NSView { override var isFlipped: Bool { true } }

    let scene: BrowserScene
    let overlay: BarOverlay
    let container = PopoverBackgroundView(blending: .withinWindow)
    let inputIcon = NSImageView()
    let input = NSTextField()
    let divider = CommandBarHairline(frame: .zero)
    let list = FlippedBox()
    let caret = BarCaret()
    let palette: CommandBarPalette
    var rowViews: [String: CommandResultRowView] = [:]
    var current: [BarRow] = []
    var query: String?

    init(scene: BrowserScene, below: NSView) {
        self.scene = scene
        palette = CommandBarPalette(theme: scene.scenario.work.theme)
        overlay = BarOverlay(frame: NSRect(origin: .zero, size: scene.windowRect.size))
        scene.surface.addSubview(overlay, positioned: .below, relativeTo: below)
        let width = max(260, min(765, scene.windowRect.width - 48))
        let x = scene.windowRect.width / 2 - width / 2
        let top = scene.windowRect.height / 2 - 326 / 2
        overlay.bar = NSRect(x: x, y: top, width: width, height: 326)
        container.frame = overlay.bar
        container.cornerRadius = 12
        container.appearance = NSAppearance(named: .aqua)
        container.translucency.alphaValue = 0
        overlay.addSubview(container)
        inputIcon.imageScaling = .scaleProportionallyDown
        inputIcon.contentTintColor = palette.inputIcon
        inputIcon.frame = NSRect(x: 22, y: 22, width: 18, height: 18)
        container.addSubview(inputIcon)
        input.isBordered = false; input.drawsBackground = false
        input.font = CommandBarTypography.field
        input.placeholderString = "Search or Enter URL…"
        input.usesSingleLineMode = true; input.cell?.wraps = false
        input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
        input.focusRingType = .none
        input.textColor = palette.inputText
        input.frame = NSRect(x: 49, y: 21, width: width - 71, height: 31)
        container.addSubview(input)
        divider.frame = NSRect(x: 12, y: 64, width: width - 24, height: 0.5)
        container.addSubview(divider)
        list.frame = NSRect(x: 8, y: 68, width: width - 16, height: 326 - 76)
        container.addSubview(list)
        container.addSubview(caret)
        overlay.isHidden = true
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
    }

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? SidebarPlusMenuArtwork.image(name)
    }

    static func favicon(_ url: String) -> NSImage? { Favicons.specs[url].map(Favicons.image) }

    static func rows(for query: String) -> [BarRow] {
        let meadow = BarRow(id: "history:meadow", title: Canon.meadow.title, subtitle: CommandBarResultText.urlSubtitle(Canon.meadow.url),
                            icon: favicon(Canon.meadow.url) ?? symbol("clock"))
        func search(_ text: String) -> BarRow { BarRow(id: "search:" + text, title: text, icon: symbol("magnifyingglass")) }
        switch query {
        case "":
            return [
                BarRow(id: "tab:urban-parks", title: Canon.urbanParks.title, accessory: "Switch to Tab", isTab: true,
                       icon: favicon(Canon.urbanParks.url)),
                BarRow(id: "tab:roadmap", title: "Quarterly roadmap draft", accessory: "Switch to Tab", isTab: true,
                       icon: favicon("https://docs.example.com/roadmap")),
                BarRow(id: "history:garden", title: "Community garden volunteer day", subtitle: "— parks.example/garden-day", icon: symbol("clock")),
                BarRow(id: "history:bread", title: "Sourdough starter, step by step", subtitle: "— breadnotes.example/starter", icon: symbol("clock")),
                BarRow(id: "history:weather", title: "Weekend forecast", subtitle: "— weather.example/weekend", icon: symbol("clock")),
            ]
        case "m":
            return [search("maps"), search("museum hours"), meadow, search("movie times"), search("m")]
        case "me":
            return [meadow, search("meadow"), search("meal prep ideas"), search("metro map"), search("meetup")]
        case "mea":
            return [meadow, search("meadow"), search("meal prep ideas"), search("meadowlark"), search("meatball recipe")]
        default:
            return [meadow, search("meadow"), search("meadow flowers"), search("meadowlark"), search("east meadow park")]
        }
    }

    func publish(_ rows: [BarRow]) {
        let ids = Set(rows.map(\.id))
        for (id, view) in rowViews where !ids.contains(id) { view.removeFromSuperview(); rowViews[id] = nil }
        for (index, row) in rows.enumerated() {
            let view: CommandResultRowView
            if let existing = rowViews[row.id] { view = existing } else {
                view = CommandResultRowView(frame: NSRect(x: 0, y: 0, width: list.bounds.width, height: 50))
                view.selectedColor = palette.selected
                view.selectionHighlightStyle = .none
                let cell = CommandResultCell(title: row.title, subtitle: row.subtitle, detail: "", accessory: row.accessory,
                                             isTab: row.isTab, icon: row.icon, enabled: true, isAction: row.isAction)
                cell.selectedColor = palette.selected
                cell.frame = view.bounds
                cell.autoresizingMask = [.width, .height]
                view.addSubview(cell)
                list.addSubview(view)
                rowViews[row.id] = view
            }
            view.frame = NSRect(x: 0, y: CGFloat(index) * 50, width: list.bounds.width, height: 50)
            view.needsLayout = true
        }
        current = rows
        list.layoutSubtreeIfNeeded()
    }

    func select(_ index: Int) {
        let base = palette.selected.usingColorSpace(.sRGB) ?? palette.selected
        for (offset, row) in current.enumerated() {
            guard let view = rowViews[row.id] else { continue }
            view.isSelected = offset == index
            view.selectedColor = offset == index ? base : .clear
        }
        if input.stringValue.isEmpty || !current.indices.contains(index) {
            inputIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        } else {
            inputIcon.image = current[index].icon
        }
    }

    func placeCaret(opacity: CGFloat) {
        let text = NSAttributedString(string: input.stringValue, attributes: [.font: CommandBarTypography.field])
        let width = input.stringValue.isEmpty ? 0 : ceil(text.size().width)
        caret.frame = NSRect(x: input.frame.minX + 2 + width, y: 21.5, width: 2, height: 22)
        caret.opacity = opacity
    }

    func refreshBackdrop() {
        overlay.isHidden = true
        let beneath = scene.render(NSRect(origin: .zero, size: NSSize(width: 1440, height: 900)), pixelsWide: 2880, pixelsHigh: 1800).cgImage!
        let bar = overlay.bar.offsetBy(dx: scene.windowRect.minX, dy: scene.windowRect.minY)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let height = CGFloat(beneath.height)
        let crop = CGRect(x: bar.minX * 2, y: bar.minY * 2, width: bar.width * 2, height: bar.height * 2)
        let ciCrop = CGRect(x: crop.minX, y: height - crop.maxY, width: crop.width, height: crop.height)
        let blurred = CIImage(cgImage: beneath).clampedToExtent().applyingGaussianBlur(sigma: 50)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.02])
        overlay.backdrop = context.createCGImage(blurred, from: ciCrop)
        overlay.isHidden = false
    }

    func show(_ text: String, caretOpacity: CGFloat) {
        overlay.isHidden = false; overlay.shown = true
        if text != query {
            input.stringValue = text
            publish(Self.rows(for: text))
            query = text
        }
        select(0)
        placeCaret(opacity: caretOpacity)
        container.layoutSubtreeIfNeeded()
        container.updateLayer()
        divider.updateLayer()
    }

    func hide() {
        overlay.isHidden = true; overlay.shown = false
    }
}
