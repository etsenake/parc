import AppKit

// Isolated collaborators keep the production popup view inert: no browser,
// navigation, event injection or window activation occurs in this check.
enum NavigationControlKind { case back, forward, reload }
struct NavigationControlInteraction {}
final class NavigationControlButton: NSButton {
    var prepareInteraction: (() -> NavigationControlInteraction?)?
    init(_ title: String, symbol: String, history: Bool = false, commandID: String? = nil) {
        super.init(frame: .zero); self.title = title
    }
    required init?(coder: NSCoder) { fatalError() }
}
final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    var secondaryActionBlock: (() -> Void)?
    init(_ title: String, symbol: String? = nil) { super.init(frame: .zero); self.title = title }
    required init?(coder: NSCoder) { fatalError() }
}
struct ThemeChromePalette { let contentAppearance: NSAppearance?; let title: NSColor; let isDark: Bool }
enum TooltipConfiguration { enum Anchor { case bottom, bottomTrailing } }
///
enum LiveShortcutToolTip {
    static var tooltips: [String: (String?, TooltipConfiguration.Anchor)] = [:]
    static func set(_ view: NSView, _ title: String, commandID: String? = nil, anchor: TooltipConfiguration.Anchor = .bottomTrailing) {
        tooltips[title] = (commandID, anchor)
    }
}
final class SidebarRowActionButton: NSButton {
    var prepareAction: (() -> (() -> Bool)?)?
    var symbol: NSImage?
    var dark = false
    init(_ title: String) { super.init(frame: .zero); self.title = title }
    required init?(coder: NSCoder) { fatalError() }
    func refreshAvailability() {}
}
enum SidebarIconCatalog {
    static var feathers: [UInt32: CGFloat] = [:]
    static func featherImage(_ code: UInt32, size: CGFloat) -> NSImage {
        feathers[code] = size; return NSImage(size: NSSize(width: size, height: size))
    }
}

@main struct PopupChromeChecks {
    @MainActor static func main() {
        let view = PopupChromeView(frame: NSRect(x: 0, y: 0, width: 400, height: 47))
        let buttons = view.subviews.compactMap { $0 as? NSButton }
        let back = buttons.first { $0.title == "Back" }!
        let address = view.subviews.compactMap { $0 as? ActionButton }.first!
        let label = view.subviews.compactMap { $0 as? PopupAddressLabel }.first!
        let copy = buttons.first { $0.title == "Copy URL" } as! SidebarRowActionButton
        let extensions = buttons.first { $0.title == "Extensions" } as! SidebarRowActionButton
        precondition(!buttons.contains { $0.title == "Forward" || $0.title == "Refresh the Page" })
        //
        precondition(LiveShortcutToolTip.tooltips["Copy URL"]! == ("copyCurrentURL:", .bottom)
                     && LiveShortcutToolTip.tooltips["Extensions"]! == (nil, .bottom))
        let background = view.subviews.compactMap { $0 as? PopupAddressBackground }.first!
        precondition(SidebarIconCatalog.feathers[0xE92F] == 16 && SidebarIconCatalog.feathers[0xE98A] == 16
                     && back.image?.size == NSSize(width: 16, height: 16))
        view.update(url: nil, canGoBack: false, loading: false)
        view.layoutSubtreeIfNeeded()
        precondition(back.isHidden && copy.isHidden && extensions.isHidden && address.frame.minX == 73 && label.font?.pointSize == 13)
        precondition(background.frame == address.frame && background.hitTest(NSPoint(x: 1, y: 1)) == nil
                     && background.layer?.cornerRadius == 5 && background.layer?.cornerCurve == .continuous)
        background.update(dark: false, hovered: false)
        let light = NSColor(cgColor: background.layer!.backgroundColor!)!.usingColorSpace(.displayP3)!
        precondition(abs(light.redComponent - 0.055) < 0.001 && abs(light.alphaComponent - 0.06) < 0.001)
        background.update(dark: true, hovered: true)
        let darkHover = NSColor(cgColor: background.layer!.backgroundColor!)!.usingColorSpace(.displayP3)!
        precondition(abs(darkHover.greenComponent - 0.984) < 0.001 && abs(darkHover.alphaComponent - 0.15) < 0.001)
        view.appearance = NSAppearance(named: .aqua)
        let pointer = NSPoint(x: address.frame.minX + 1, y: address.frame.midY)
        view.reconcileAddressHover(pointer: pointer, active: true, visible: true)
        precondition(abs(NSColor(cgColor: background.layer!.backgroundColor!)!.alphaComponent - 0.10) < 0.001)
        view.update(url: URL(string: "https://example.com"), canGoBack: true, loading: true)
        view.updateExtensions(available: true)
        view.layoutSubtreeIfNeeded()
        precondition(!back.isHidden && back.isEnabled && back.frame == NSRect(x: 70, y: 8, width: 31, height: 31)
                     && address.frame == NSRect(x: 105, y: 8, width: 291, height: 31) && label.font?.pointSize == 11
                     && label.frame.minX == 167 && label.frame.maxX == 334 && label.hitTest(.zero) == nil
                     && !copy.isHidden && copy.frame == NSRect(x: 369, y: 12, width: 23, height: 23)
                     && !extensions.isHidden && extensions.frame == NSRect(x: 338, y: 12, width: 23, height: 23)
                     && view.pageControlsAnchor === extensions)
        var copied = false
        view.prepareCopy = { { copied = true; return true } }
        precondition(copy.prepareAction?()?() == true && copied)
        var openedExtensions = false
        view.prepareExtensions = { { openedExtensions = true; return true } }
        precondition(extensions.prepareAction?()?() == true && openedExtensions)
        view.prepareSiteControls = { { true } }
        precondition(address.accessibilityCustomActions()?.contains { $0.name == "Site Control Center" } == true)
        view.reconcileAddressHover(pointer: pointer, active: true, visible: true)
        precondition(abs(NSColor(cgColor: background.layer!.backgroundColor!)!.alphaComponent - 0.06) < 0.001)
        view.update(url: nil, canGoBack: false, loading: false)
        view.updateExtensions(available: false)
        view.layoutSubtreeIfNeeded()
        precondition(back.isHidden && copy.isHidden && extensions.isHidden && address.frame.minX == 73
                     && label.font?.pointSize == 13 && view.pageControlsAnchor === address)
        print("PopupChrome: back availability and layout transitions passed")
    }
}
