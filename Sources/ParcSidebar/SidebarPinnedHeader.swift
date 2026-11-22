import AppKit
import ParcCore
import ParcKit

struct SidebarPinnedPresentation: Equatable {
    var header = false
    var placeholder = false
    var folded = false
    var peek: [SidebarItemReference] = []
    var icons = false
}

struct SidebarPinnedHeaderContent: Equatable {
    var placeholder = false
    var collapsed = false
    var showsIcons = true
    var count = 0
    var icons: [UUID] = []
}

package enum SidebarPinnedHeaderLayout {
    static let height = SidebarChromeLayout.tablistVisibleRowHeight
    static let labelInset: CGFloat = 10
    static let labelFontSize: CGFloat = 11
    static let summarySpacing: CGFloat = 6
    static let chipSide: CGFloat = 16
    static let chipRadius: CGFloat = 4.5
    static let chipPitch: CGFloat = 11
    static let chipRing: CGFloat = 1.5
    static let faviconSide: CGFloat = 12
    static let countSpacing: CGFloat = 4
    static let pillHeight: CGFloat = 16
    static let pillPadding: CGFloat = 5
    static let chevronSide: CGFloat = 10
    static let chevronClearance: CGFloat = 6
    static let title = "Pinned"

    static func chevronFrame(width: CGFloat, height: CGFloat = height) -> CGRect {
        let midX = width - SidebarRowAppearance.closeTrailingInset - SidebarRowAppearance.closeSize / 2
        return CGRect(x: midX - chevronSide / 2, y: (height - chevronSide) / 2, width: chevronSide, height: chevronSide)
    }

    static let chevronDuration: CFTimeInterval = 0.2

    static func chevronAngle(collapsed: Bool) -> CGFloat { collapsed ? -.pi / 2 : 0 }

    static func chevronPoints(in frame: CGRect, angle: CGFloat) -> [CGPoint] {
        let side = min(frame.width, frame.height)
        let reach = side * 0.32, drop = side * 0.16
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return [CGPoint(x: -reach, y: -drop), CGPoint(x: 0, y: drop), CGPoint(x: reach, y: -drop)].map { point in
            CGPoint(x: center.x + cos(angle) * point.x - sin(angle) * point.y,
                    y: center.y + sin(angle) * point.x + cos(angle) * point.y)
        }
    }

    struct Summary: Equatable {
        var chips: [CGRect]
        var hidden: Int
        var countX: CGFloat?
        var pill: CGRect?
    }

    static func summary(width: CGFloat, height: CGFloat = height, labelWidth: CGFloat, icons: Int, count: Int,
                        showsIcons: Bool, countWidth: (Int, Bool) -> CGFloat) -> Summary {
        let start = labelInset + labelWidth + summarySpacing
        let limit = chevronFrame(width: width, height: height).minX - chevronClearance
        let midY = height / 2
        guard count > 0, limit > start else { return Summary(chips: [], hidden: count, countX: nil, pill: nil) }
        if showsIcons, icons > 0 {
            var shown = min(icons, count)
            while shown > 0 {
                let hidden = count - shown
                let chipsEnd = start + chipSide + CGFloat(shown - 1) * chipPitch
                let end = hidden > 0 ? chipsEnd + countSpacing + countWidth(hidden, true) : chipsEnd
                if end <= limit { break }
                shown -= 1
            }
            if shown > 0 {
                let chips = (0..<shown).map {
                    CGRect(x: start + CGFloat($0) * chipPitch, y: midY - chipSide / 2, width: chipSide, height: chipSide)
                }
                let hidden = count - shown
                return Summary(chips: chips, hidden: hidden,
                               countX: hidden > 0 ? chips[chips.count - 1].maxX + countSpacing : nil, pill: nil)
            }
        }
        let pillWidth = max(pillHeight, countWidth(count, false) + pillPadding * 2)
        guard start + pillWidth <= limit else { return Summary(chips: [], hidden: count, countX: nil, pill: nil) }
        return Summary(chips: [], hidden: count, countX: nil,
                       pill: CGRect(x: start, y: midY - pillHeight / 2, width: pillWidth, height: pillHeight))
    }

    static func countText(_ hidden: Int, chips: Bool) -> String { chips ? "+\(hidden)" : "\(hidden)" }

    static func accessibilityLabel(collapsed: Bool, count: Int) -> String {
        guard collapsed, count > 0 else { return title }
        return "\(title), \(count) \(count == 1 ? "tab" : "tabs")"
    }

    package static func actionTitle(collapsed: Bool) -> String { collapsed ? "Expand Pinned" : "Collapse Pinned" }
    package static func iconsActionTitle(shows: Bool) -> String { shows ? "Hide Collapsed Pinned Icons" : "Show Collapsed Pinned Icons" }
}

@MainActor
final class SidebarPinnedHeaderView: NSView {
    static let commandID = "togglePinnedSection:"
    private typealias L = SidebarPinnedHeaderLayout
    private(set) var content = SidebarPinnedHeaderContent()
    var toggle: (() -> Void)?
    var makeMenu: (() -> NSMenu?)?
    var setCursor: (NSCursor) -> Void = { $0.set() }
    private var favicons: [UUID: (url: String, image: NSImage)] = [:]
    private var fallbacks: [UUID: String] = [:]
    private var symbolImages: [String: NSImage] = [:]
    private var dark = false
    private var accent: NSColor?
    private var hover = false
    private var pressed = false
    private var tracking: NSTrackingArea?
    private var keyObservers: [NSObjectProtocol] = []
    private var chevronAngle = L.chevronAngle(collapsed: false)
    private var chevronTurn: (from: CGFloat, to: CGFloat, start: CFTimeInterval, timer: Timer)?
    override var isFlipped: Bool { true }
    deinit { keyObservers.forEach(NotificationCenter.default.removeObserver); chevronTurn?.timer.invalidate() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.cornerRadius = SidebarRowAppearance.cornerRadius
        layer?.cornerCurve = .continuous
        addCursorUpdateArea()
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
        setAccessibilityIdentifier("sidebarPinnedHeader")
        setAccessibilityChildren([])
        refreshAccessibility()
        refreshTooltip()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ next: SidebarPinnedHeaderContent, fallbacks symbols: [UUID: String], animated: Bool) {
        if symbols != fallbacks { fallbacks = symbols; needsDisplay = true }
        favicons = favicons.filter { next.icons.contains($0.key) }
        guard next != content else { return }
        let toggled = next.collapsed != content.collapsed
        let roleChanged = next.placeholder != content.placeholder
        content = next
        if toggled { turnChevron(to: L.chevronAngle(collapsed: next.collapsed), animated: animated) }
        refreshAccessibility()
        if toggled || roleChanged { refreshTooltip() }
        if toggled { NSAccessibility.post(element: self, notification: .valueChanged) }
        refreshColors()
    }

    func needsFavicon(for tabID: UUID, url: String) -> Bool { favicons[tabID]?.url != url }
    func shows(_ tabID: UUID) -> Bool { content.icons.contains(tabID) }

    func setFavicon(_ image: NSImage?, for tabID: UUID, url: String) {
        guard content.icons.contains(tabID) else { return }
        if let image { favicons[tabID] = (url, image) } else { favicons.removeValue(forKey: tabID) }
        needsDisplay = true
    }

    func forgetFavicon(for tabID: UUID) {
        guard favicons.removeValue(forKey: tabID) != nil else { return }
        needsDisplay = true
    }

    func applyStyle(dark: Bool, accent: NSColor?) {
        guard dark != self.dark || accent != self.accent else { return }
        self.dark = dark; self.accent = accent
        refreshColors()
    }

    private var ink: NSColor { dark ? .white : .black }
    private var emphasis: Bool { !content.placeholder && ((hover && window?.isKeyWindow == true) || pressed) }

    private var plateFill: NSColor? {
        guard emphasis else { return nil }
        return pressed ? SidebarRowAppearance.controlFill(pressed: true, dark: dark) : SidebarRowAppearance.color(.hovered, dark: dark)
    }

    private func refreshColors() {
        layer?.backgroundColor = plateFill?.cgColor
        needsDisplay = true
    }

    private func turnChevron(to angle: CGFloat, animated: Bool) {
        chevronTurn?.timer.invalidate(); chevronTurn = nil
        guard animated, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            chevronAngle = angle; needsDisplay = true; return
        }
        let from = chevronAngle, start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.stepChevron()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        chevronTurn = (from, angle, start, timer)
    }

    private func stepChevron() {
        guard let turn = chevronTurn else { return }
        let progress = min(1, (CACurrentMediaTime() - turn.start) / L.chevronDuration)
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        chevronAngle = turn.from + (turn.to - turn.from) * eased
        if progress >= 1 { turn.timer.invalidate(); chevronTurn = nil }
        setNeedsDisplay(L.chevronFrame(width: bounds.width, height: bounds.height).insetBy(dx: -2, dy: -2))
    }

    private func refreshAccessibility() {
        setAccessibilityRole(content.placeholder ? .staticText : .disclosureTriangle)
        setAccessibilityLabel(L.accessibilityLabel(collapsed: content.collapsed, count: content.count))
        setAccessibilityValue(content.placeholder ? nil : content.collapsed ? 0 : 1)
    }

    private func refreshTooltip() {
        if content.placeholder {
            parcTooltip = nil; toolTip = nil
            LiveShortcutToolTip.help(self, "", commandID: nil, requiresBinding: true)
            return
        }
        LiveShortcutToolTip.set(self, L.actionTitle(collapsed: content.collapsed), commandID: Self.commandID)
    }

    private var labelText: NSAttributedString {
        NSAttributedString(string: L.title, attributes: [
            .font: NSFont.systemFont(ofSize: L.labelFontSize, weight: .semibold),
            .foregroundColor: ink.withAlphaComponent(emphasis ? 0.65 : 0.4)
        ])
    }

    private func countText(_ value: Int, chips: Bool) -> NSAttributedString {
        let color = chips ? ink.withAlphaComponent(emphasis ? 0.6 : 0.4) : pillInk.withAlphaComponent(dark ? 0.85 : 0.75)
        return NSAttributedString(string: L.countText(value, chips: chips), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold), .foregroundColor: color
        ])
    }

    private var pillInk: NSColor { accent ?? ink }

    var summary: SidebarPinnedHeaderLayout.Summary? {
        guard content.collapsed, content.count > 0 else { return nil }
        return L.summary(width: bounds.width, height: bounds.height, labelWidth: ceil(labelText.size().width),
                         icons: content.icons.count, count: content.count, showsIcons: content.showsIcons,
                         countWidth: { [self] value, chips in ceil(countText(value, chips: chips).size().width) })
    }

    override func draw(_ dirtyRect: NSRect) {
        if !content.placeholder { drawChevron() }
        let label = labelText
        let labelSize = label.size()
        label.draw(at: NSPoint(x: L.labelInset, y: snap((bounds.height - labelSize.height) / 2)))
        guard let summary else { return }
        if let pill = summary.pill {
            pillInk.withAlphaComponent(dark ? 0.18 : 0.1).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            let text = countText(content.count, chips: false)
            let size = text.size()
            text.draw(at: NSPoint(x: snap(pill.midX - size.width / 2), y: snap(pill.midY - size.height / 2)))
            return
        }
        guard let context = NSGraphicsContext.current else { return }
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.cgContext.endTransparencyLayer() }
        for (index, chip) in summary.chips.enumerated() {
            if index > 0 {
                context.saveGraphicsState()
                context.compositingOperation = .destinationOut
                NSColor.black.setFill()
                let ring = chip.insetBy(dx: -L.chipRing, dy: -L.chipRing)
                NSBezierPath(roundedRect: ring, xRadius: L.chipRadius + L.chipRing, yRadius: L.chipRadius + L.chipRing).fill()
                context.restoreGraphicsState()
            }
            drawChip(chip, tabID: content.icons[index])
        }
        if let x = summary.countX {
            let text = countText(summary.hidden, chips: true)
            let size = text.size()
            text.draw(at: NSPoint(x: x, y: snap((bounds.height - size.height) / 2)))
        }
    }

    private func drawChevron() {
        let points = L.chevronPoints(in: L.chevronFrame(width: bounds.width, height: bounds.height), angle: chevronAngle)
        let path = NSBezierPath()
        path.move(to: points[0]); path.line(to: points[1]); path.line(to: points[2])
        path.lineWidth = 1.6; path.lineCapStyle = .round; path.lineJoinStyle = .round
        ink.withAlphaComponent(emphasis ? 0.65 : content.collapsed ? 0.4 : 0.3).setStroke()
        path.stroke()
    }

    private func drawChip(_ chip: CGRect, tabID: UUID) {
        let shape = NSBezierPath(roundedRect: chip, xRadius: L.chipRadius, yRadius: L.chipRadius)
        (dark ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16) : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)).setFill()
        shape.fill()
        let inset = (L.chipSide - L.faviconSide) / 2
        let target = chip.insetBy(dx: inset, dy: inset)
        if let image = favicons[tabID]?.image ?? documentFallback(tabID) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: target, xRadius: 2.5, yRadius: 2.5).addClip()
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high.rawValue])
            NSGraphicsContext.restoreGraphicsState()
        } else if let symbol = fallbacks[tabID].flatMap(symbolImage) {
            let configured = symbol.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)
                .applying(.init(paletteColors: [ink.withAlphaComponent(0.55)]))) ?? symbol
            let size = configured.size
            configured.draw(in: NSRect(x: snap(chip.midX - size.width / 2), y: snap(chip.midY - size.height / 2),
                                       width: size.width, height: size.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    private func documentFallback(_ tabID: UUID) -> NSImage? {
        fallbacks[tabID].flatMap(DocumentDefaultIcon.init(symbol:))?.image(size: L.faviconSide)
    }

    private func symbolImage(_ name: String) -> NSImage? {
        if let image = symbolImages[name] { return image }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        symbolImages[name] = image
        return image
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        refreshHover()
    }
    private func refreshHover() {
        let point = window.flatMap { $0.isKeyWindow ? $0.mouseLocationOutsideOfEventStream : nil }
        setHover(point.map { bounds.contains(convert($0, from: nil)) && isTopmost(atWindowPoint: $0) } ?? false)
    }
    override func setFrameSize(_ newSize: NSSize) {
        let resized = newSize != frame.size
        super.setFrameSize(newSize)
        if resized { needsDisplay = true }
    }
    override func mouseEntered(with event: NSEvent) { setHover(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHover(isTopmost(atWindowPoint: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func viewDidHide() { super.viewDidHide(); resetPointer() }
    func resetPointer() { pressed = false; hover = false; refreshColors() }
    private func setHover(_ next: Bool) {
        guard next != hover else { return }
        hover = next
        refreshColors()
    }
    override func cursorUpdate(with event: NSEvent) {
        if content.placeholder { super.cursorUpdate(with: event) } else { setCursor(.pointingHand) }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, let turn = chevronTurn {
            turn.timer.invalidate(); chevronTurn = nil; chevronAngle = turn.to; needsDisplay = true
        }
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let newWindow else { return }
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshHover(); self?.refreshColors() }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        guard !content.placeholder else { super.mouseDown(with: event); return }
        pressed = true
        refreshColors()
    }
    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressed else { return }
        pressed = inside
        refreshColors()
    }
    override func mouseUp(with event: NSEvent) {
        let activate = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refreshColors()
        if activate { toggle?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { content.placeholder ? super.menu(for: event) : makeMenu?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !content.placeholder, frame.contains(point) else { return nil }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    override func accessibilityPerformPress() -> Bool {
        guard let toggle else { return false }
        toggle()
        return true
    }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        if selector == #selector(accessibilityPerformPress) { return toggle != nil }
        return super.isAccessibilitySelectorAllowed(selector)
    }
}
