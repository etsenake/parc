import AppKit
import Combine

@MainActor private final class TitleWindow: NSWindow {
    var key = true
    var pointer = NSPoint(x: -100, y: -100)
    override var isKeyWindow: Bool { key }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}
private final class TitleTrackingEvent: NSEvent {
    var area: NSTrackingArea?
    override var trackingArea: NSTrackingArea? { area }
}

try MainActor.assumeIsolated {
    _ = NSApplication.shared
    let suite = "Parc.ToolbarChecks." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "parc.browserToolbar.v1"
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    for dark in [false, true, false] {
        let ink = SidebarNewTabAppearance.titleColor(dark: dark).usingColorSpace(.sRGB)!
        let icon = SidebarNewTabAppearance.plusColor(dark: dark).usingColorSpace(.sRGB)!
        check(abs(ink.redComponent - (dark ? 1 : 0)) < 0.001 && abs(ink.alphaComponent - (dark ? 0.45 : 0.30)) < 0.001,
              "New Tab label is SidebarForeground, with its alpha in the text colour")
        check(abs(icon.redComponent - (dark ? 1 : 0)) < 0.001 && abs(icon.alphaComponent - 0.5) < 0.001,
              "New Tab icon uses the original secondary foreground")
    }
    let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 16, weight: .medium))!
    check(SidebarNewTabAppearance.title == "New Tab" && SidebarNewTabAppearance.plus?.size == plus.size,
          "New Tab's plus is the 16-point medium plus")
    let clear = ActionButton(SidebarClearAppearance.title)
    for dark in [false, true] {
        SidebarClearAppearance.apply(to: clear, dark: dark)
        let label = clear.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        let ink = label.usingColorSpace(.sRGB)!, tint = clear.contentTintColor!.usingColorSpace(.sRGB)!
        check(clear.title == "Clear" && abs(ink.redComponent - (dark ? 1 : 0)) < 0.001 && abs(ink.alphaComponent - 0.3) < 0.001
              && abs(tint.redComponent - (dark ? 1 : 0)) < 0.001 && abs(tint.alphaComponent - 0.3) < 0.001,
              "resting Clear's label and arrow are ForegroundTertiary, not the theme subtitle wash")
        check(clear.font == NSFont.systemFont(ofSize: 10, weight: .semibold), "Clear's label is 10-point semibold")
        let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)!.withSymbolConfiguration(.init(pointSize: 10, weight: .bold))!
        check(clear.image?.size == arrow.size && clear.imagePosition == .imageLeading && clear.imageHugsTitle,
              "Clear leads with the bold 10-point arrow.down")
        SidebarClearAppearance.apply(to: clear, dark: dark, hovered: true)
        let hovered = (clear.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor).usingColorSpace(.sRGB)!
        let hoveredTint = clear.contentTintColor!.usingColorSpace(.sRGB)!
        check(abs(hovered.alphaComponent - (dark ? 0.8 : 0.9)) < 0.001 && abs(hoveredTint.alphaComponent - (dark ? 0.8 : 0.9)) < 0.001
              && (dark ? hovered.redComponent > 0.99 : hovered.redComponent < 0.07), "hovered Clear is ForegroundPrimary")
    }
    let preferences = BrowserToolbarPreferences(defaults: defaults)
    check(!preferences.loadError, "new preference owner is available")
    check(defaults.object(forKey: key) == nil, "reading defaults writes no data")
    var published: [BrowserToolbarPreferences.State] = []
    let subscription = preferences.$state.sink { published.append($0) }
    try preferences.setShowsFullURL(true)
    check(!preferences.state.isVisible, "full URL preference does not toggle visibility")
    try preferences.setVisible(true)
    check(preferences.state.showsFullURL, "visibility does not reset full URLs")
    let restored = BrowserToolbarPreferences(defaults: defaults)
    check(restored.state == preferences.state, "both independent values persist")
    let count = published.count
    try preferences.setVisible(true)
    check(published.count == count, "idempotent writes do not publish another layout")
    try preferences.setVisible(false)
    check(published.last?.isVisible == false, "shared consumers receive the new appearance state")
    check(!PaneTopBarAdmission.displayed(toolbarVisible: false, inSplit: false),
          "a single pane with Toolbar hidden has no top bar")
    check(PaneTopBarAdmission.displayed(toolbarVisible: true, inSplit: false),
          "Show Toolbar puts a top bar on a single pane")
    check(PaneTopBarAdmission.displayed(toolbarVisible: false, inSplit: true),
          "a split always shows the per-pane top bar, including with Toolbar hidden")
    check(!PaneTopBarAdmission.displayed(toolbarVisible: false, inSplit: true, isPopup: true),
          "popup windows never take the ordinary pane top bar")
    check(!PaneTopBarAdmission.displayed(toolbarVisible: true, inSplit: true, hasLibrary: true),
          "Library has no pane top bar")
    check(!PaneTopBarAdmission.displayed(toolbarVisible: true, inSplit: true, tabFullscreen: true),
          "tab fullscreen has no pane top bar")
    check(!PaneTopBarAdmission.peekDisplayed(toolbarVisible: false, isActivePeek: true, developerToolbarHidden: true),
          "Peek's own bar still follows Show Toolbar")
    check(PaneTopBarAdmission.peekDisplayed(toolbarVisible: true, isActivePeek: true, developerToolbarHidden: true),
          "an active Peek with Toolbar shown has its own bar")
    check(!PaneTopBarAdmission.peekDisplayed(toolbarVisible: true, isActivePeek: false, developerToolbarHidden: true),
          "an inactive Peek has no bar")
    check(!PaneTopBarAdmission.peekDisplayed(toolbarVisible: true, isActivePeek: true, developerToolbarHidden: false),
          "Developer Mode Peek has no ordinary bar")
    check(PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: true, toolbarVisible: false),
          "a split pane's top bar keeps the sidebar URL bar (installed Parc, November 1 reference)")
    check(!PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: true, toolbarVisible: true),
          "the Toolbar replaces the sidebar URL bar")
    check(PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: false, toolbarVisible: true),
          "a content without a top bar keeps the sidebar URL bar")
    let paneA = UUID(), paneB = UUID(), paneC = UUID()
    check(SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA, paneB]),
          "a split pane's Close retires that original page")
    check(SplitPaneCloseAdmission.accepts(tabID: paneB, selected: [paneA, paneB]),
          "an unfocused split pane's Close still retires that page")
    check(!SplitPaneCloseAdmission.accepts(tabID: paneC, selected: [paneA, paneB]),
          "Close cannot retire a page that is not in the split")
    check(!SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA]),
          "a single page has no split Close")
    check(!SplitPaneCloseAdmission.accepts(tabID: paneA, selected: [paneA, paneB], isPeek: true),
          "Peek has no split Close")
    withExtendedLifetime(subscription) {}
    for invalid: Any in [Data("not json".utf8), Data("{\"version\":99,\"isVisible\":true,\"showsFullURL\":true}".utf8), "unexpected legacy type"] {
        defaults.set(invalid, forKey: key)
        let preserved = defaults.object(forKey: key) as! NSObject
        let unavailable = BrowserToolbarPreferences(defaults: defaults)
        check(unavailable.loadError, "malformed or future data refuses mutation")
        do { try unavailable.setVisible(true); preconditionFailure("invalid preference overwritten") } catch { checks += 1 }
        check((defaults.object(forKey: key) as! NSObject).isEqual(preserved), "unreadable values remain untouched")
    }
    let url = URL(string: "https://sub.example.test:8443/a%20b?q=%2F#part")!
    check(BrowserToolbarAddress(url: url, full: false).title == "sub.example.test", "short title is native URL host")
    check(BrowserToolbarAddress(url: url, full: true).title == "sub.example.test:8443/a%20b?q=%2f#part", "long display follows original prefix trimming and lowercase formatter")
    let internalURL = URL(string: "parc://settings/content")!
    check(BrowserToolbarAddress(url: internalURL, full: true).title == internalURL.absoluteString, "virtual scheme is never text-rewritten")
    check(BrowserToolbarAddress(url: nil, full: true).fullURL.isEmpty, "missing page never invents a destination")
    let addressValue = BrowserToolbarAddress(url: url, full: true)
    check(addressValue.fullURL == url.absoluteString, "display formatting never changes actual copy/AX URL")
    check(addressValue.primary == "sub.example.test" && addressValue.suffix == ":8443/a%20b?q=%2f#part", "actual prefix split preserves separate emphasis runs")
    check(BrowserToolbarAddress(url: URL(string: "https://www.example.test/?"), full: true).title == "example.test", "one trailing query marker/slash and leading web/www prefixes are display-only")
    check(BrowserToolbarAddress(url: URL(string: "https://http://www.example.test/?"), full: true).title == "http://www.example.test", "scheme stripping is one alternative, not a repeated prefix loop")
    check(BrowserToolbarAddress(url: URL(string: "file:///tmp/MixedCase"), full: true).title == "file:///tmp/MixedCase", "nonmatching long prefix preserves original short display")
    let labelControl = PaneTitleControl(frame: NSRect(x: 0, y: 0, width: 420, height: 28))
    labelControl.update(addressValue); labelControl.place(in: NSRect(x: 0, y: 0, width: 420, height: 28)); labelControl.layoutSubtreeIfNeeded()
    let textLabel = labelControl.subviews.compactMap { $0 as? NSTextField }.first!
    check(textLabel.layerContentsRedrawPolicy == .beforeViewResize && textLabel.layerContentsPlacement == .center,
          "Sidebar round 3: the title label is drawn once and held centred inside the ⌘S group")
    let text = textLabel.attributedStringValue
    check(text.string == addressValue.title, "actual native label renders both source-owned runs")
    check((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 13, "native primary is thirteen points")
    let primaryLength = (addressValue.primary as NSString).length
    let primaryFont = text.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
    let suffixFont = text.attribute(.font, at: primaryLength, effectiveRange: nil) as! NSFont
    check(primaryFont != suffixFont && suffixFont.pointSize == 13, "native suffix retains separate regular font")
    let cellInset = (textLabel.cell!.cellSize.width - text.size().width) / 2
    check(textLabel.frame.minX + cellInset == 6 && textLabel.frame.maxX - cellInset == labelControl.bounds.maxX - 6 && textLabel.frame.minY == 4 && textLabel.frame.maxY == labelControl.bounds.maxY - 4, "actual glyph area has recovered padding without doubling AppKit cell inset")
    check(textLabel.cell!.cellSize.width <= textLabel.frame.width, "actual native cell fits complete long display before truncation is needed")
    check(textLabel.lineBreakMode == .byTruncatingTail, "a fitting domain with suffix truncates the tail")
    check(labelControl.accessibilityChildren()?.isEmpty == true && !textLabel.isAccessibilityElement(), "only the original button owns accessibility")
    check(textLabel.hitTest(.zero) == nil, "passive text cannot steal native button tracking")
    check(labelControl.accessibilityLabel() == "Address: " + url.absoluteString, "AX retains the complete genuine URL")
    for (appearance, alpha) in [(NSAppearance.Name.aqua, CGFloat(0.6)), (.darkAqua, 0.75)] {
        labelControl.appearance = NSAppearance(named: appearance)
        labelControl.viewDidChangeEffectiveAppearance(); labelControl.layoutSubtreeIfNeeded()
        let value = textLabel.attributedStringValue
        let primaryInk = value.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        let suffixInk = value.attribute(.foregroundColor, at: primaryLength, effectiveRange: nil) as! NSColor
        check(abs(primaryInk.alphaComponent - alpha) < 0.00001, "original primary appearance alpha")
        check(abs(suffixInk.alphaComponent - alpha * 5 / 6) < 0.00001, "original secondary appearance alpha")
        check(primaryInk.usingColorSpace(.sRGB)!.redComponent == (appearance == .darkAqua ? 1 : 0), "named foreground resolves black/white rather than Space accent")
    }
    labelControl.place(in: NSRect(x: 0, y: 0, width: 80, height: 28)); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.primary && textLabel.lineBreakMode == .byTruncatingHead, "insufficient original domain room drops suffix and preserves host tail")
    labelControl.place(in: NSRect(x: 0, y: 0, width: 420, height: 28)); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.title, "expansion restores exact retained suffix without navigation")
    let completeWidth = text.size().width
    let fittingWidth = completeWidth + 26
    let titleSlot = NSRect(x: 17, y: 3, width: fittingWidth, height: 28)
    labelControl.place(in: titleSlot); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.title, "exact original full-run threshold admits the complete suffix")
    check(abs(labelControl.frame.midX - titleSlot.midX) < 0.00001,
          "native title remains centered in its original offset allocation")
    check(labelControl.frame.width < titleSlot.width,
          "measurement allowance is not added to the native button hit surface")
    labelControl.viewDidChangeEffectiveAppearance(); labelControl.needsLayout = true
    labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.title,
          "appearance and native layout retain parent fit after shrink-to-content")
    labelControl.place(in: NSRect(x: 17, y: 3, width: fittingWidth - 0.01, height: 28))
    labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.primary && textLabel.lineBreakMode == .byTruncatingHead,
          "just below full-run threshold omits suffix rather than clipping the long address")
    labelControl.needsLayout = true; labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.primary, "native relayout cannot oscillate suffix admission")
    let replacement = BrowserToolbarAddress(url: URL(string: "https://short.test/p"), full: true)
    labelControl.update(replacement); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == replacement.title, "new content measures its own complete runs in the retained allocation")
    labelControl.update(addressValue); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.primary, "longer replacement cannot inherit a previous title's fit")
    check(labelControl.toolTip == url.absoluteString && labelControl.accessibilityLabel() == "Address: " + url.absoluteString,
          "fit changes preserve the exact original URL for native help and accessibility")
    labelControl.place(in: NSRect(x: 0, y: 0, width: fittingWidth, height: 28))
    labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == addressValue.title, "expanding across the measured boundary restores the retained complete pair")
    labelControl.updateTitle("Original Note title"); labelControl.layoutSubtreeIfNeeded()
    check(textLabel.stringValue == "Original Note title" && textLabel.lineBreakMode == .byTruncatingTail, "local documents preserve actual authored title")
    var titleActions = 0
    labelControl.actionBlock = { titleActions += 1 }; labelControl.performClick(nil)
    check(titleActions == 1, "native title button dispatches actual owner once")
    labelControl.isEnabled = false; labelControl.performClick(nil)
    check(titleActions == 1, "disabled native title cannot dispatch")
    labelControl.isEnabled = true
    labelControl.updateTitle("Short title"); labelControl.place(in: NSRect(x: 0, y: 0, width: 420, height: 28))
    labelControl.layoutSubtreeIfNeeded()
    check(labelControl.frame.width < 200 && labelControl.frame.midX == 210 && labelControl.frame.midY == 14,
          "actual native padded surface hugs short content inside its original allocation")
    check(textLabel.cell!.cellSize.width <= textLabel.frame.width, "actual native short-title cell has room without a false truncation")
    let window = TitleWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSView(frame: window.contentView!.bounds); window.contentView = host
    host.addSubview(labelControl); labelControl.updateTrackingAreas()
    let surface = labelControl.layer!.sublayers!.first!
    // The passive surface follows its button at once outside an implicit
    // group and takes the group's geometry timing inside one (round 3).
    labelControl.place(in: NSRect(x: 0, y: 0, width: 300, height: 28)); labelControl.layoutSubtreeIfNeeded()
    check(surface.frame == labelControl.bounds && surface.animation(forKey: "bounds") == nil
          && surface.animation(forKey: "position") == nil, "surface frame follows outside a group without an implicit animation")
    labelControl.updateTitle("A longer original title for the group")
    // Core Animation adds implicit actions only to a rendered layer tree.
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000)); window.orderFrontRegardless()
    labelControl.layoutSubtreeIfNeeded(); window.displayIfNeeded(); CATransaction.flush()
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.08; context.allowsImplicitAnimation = true
        labelControl.place(in: NSRect(x: 0, y: 0, width: 420, height: 28)); labelControl.layoutSubtreeIfNeeded()
        check(surface.frame == labelControl.bounds
              && abs((surface.animation(forKey: "bounds")?.duration ?? 0) - 0.08) < 0.00001,
              "surface frame is assigned inside the group with the group's timing")
    }
    surface.removeAllAnimations()
    labelControl.updateTitle("Short title"); labelControl.place(in: NSRect(x: 0, y: 0, width: 420, height: 28))
    labelControl.layoutSubtreeIfNeeded()
    // URLTextView.onRightClickURL: the owner builds the menu; the passive
    // control never builds or performs one itself.
    let ownerMenu = NSMenu()
    var menuRequests = 0
    labelControl.menuProvider = { menuRequests += 1; return ownerMenu }
    check(labelControl.titleMenu() === ownerMenu && menuRequests == 1, "right-click asks the original owner for a fresh menu")
    labelControl.isEnabled = false
    check(labelControl.titleMenu() == nil && menuRequests == 1, "disabled title offers no menu")
    labelControl.isEnabled = true
    window.key = false
    check(labelControl.titleMenu() == nil && menuRequests == 1, "a background window's title offers no menu")
    window.key = true
    labelControl.menuProvider = nil
    //
    let noURL = PaneShareMenu.item(for: nil)
    check(noURL.title == "Share" && !noURL.isEnabled && noURL.submenu == nil, "a page without a URL offers no services")
    let shared = URL(string: "https://example.test/page")!
    var sharedRequests: [URL] = [], performed = 0
    let service = NSSharingService(title: "Test Service", image: NSImage(size: NSSize(width: 16, height: 16)),
                                   alternateImage: nil) { performed += 1 }
    let shareItem = PaneShareMenu.item(for: shared) { sharedRequests.append(contentsOf: $0); return [service] }
    check(sharedRequests == [shared] && shareItem.title == "Share" && shareItem.image == nil,
          "Share asks for services for the original URL only and keeps the plain title")
    let serviceEntry = shareItem.submenu?.items.first
    check(shareItem.submenu?.items.count == 1 && serviceEntry?.title == "Test Service" && serviceEntry?.image != nil,
          "each service appears with its menu title and image")
    if #available(macOS 27, *), let serviceEntry, let submenu = shareItem.submenu {
        // AppKit makes room for an item's image only when the item asks to show it.
        let hidden = NSMenu(); hidden.addItem(withTitle: serviceEntry.title, action: nil, keyEquivalent: "")
        hidden.items[0].image = serviceEntry.image
        check(serviceEntry.preferredImageVisibility == .visible && submenu.size.width > hidden.size.width,
              "macOS 27 shows each service's image ShareMenu does")
    }
    if let serviceEntry, let target = serviceEntry.target, let action = serviceEntry.action {
        _ = (target as AnyObject).perform(action)
    }
    check(performed == 1, "choosing a service performs it once with the URL")
    check(PaneShareMenu.item(for: shared) { _ in [] }.submenu == nil, "no services leave Share without a submenu")
    _ = PaneShareMenu.sharingServices(for: [shared])
    checks += 1
    // A toast's share button offers the same menu for every copied URL.
    let second = URL(string: "https://example.test/other")!
    var toastRequests: [URL] = []
    let toastMenu = PaneShareMenu.menu(for: [shared, second]) { toastRequests = $0; return [service] }
    check(toastRequests == [shared, second] && toastMenu?.items.first?.title == "Test Service"
          && (toastMenu?.items.first?.representedObject as? PaneShareMenu.ShareAction)?.urls == [shared, second],
          "a toast's share menu asks for and performs with every copied URL")
    check(PaneShareMenu.menu(for: []) { _ in [service] } == nil, "no URLs, no share menu")
    //
    check(PaneMenuContent(livePage: true, tabURL: "parc://note/x", localDocument: true) == .web,
          "a live page, including an error or crash, is web content")
    check(PaneMenuContent(livePage: false, tabURL: "https://example.test/", localDocument: false) == .web,
          "an ordinary tab without its page yet is still web content")
    check(PaneMenuContent(livePage: false, tabURL: "parc://note/x", localDocument: true) == .document,
          "a Note or Easel is a document without the tab or extension items")
    check(PaneMenuContent(livePage: false, tabURL: "about:blank", localDocument: false) == .none
          && PaneMenuContent(livePage: false, tabURL: "", localDocument: false) == .none
          && PaneMenuContent(livePage: false, tabURL: nil, localDocument: false) == .none,
          "a content without a URL has no actions")
    func titleAreas() -> [NSTrackingArea] { labelControl.trackingAreas.filter { $0.owner === labelControl && !$0.options.contains(.cursorUpdate) } }
    let old = TitleTrackingEvent(); old.area = titleAreas().first
    labelControl.updateTrackingAreas(); labelControl.mouseEntered(with: old)
    check(!labelControl.isHovered, "retired title tracking cannot start decoration")
    let current = TitleTrackingEvent(); current.area = titleAreas().first
    labelControl.appearance = NSAppearance(named: .aqua); labelControl.viewDidChangeEffectiveAppearance()
    labelControl.mouseEntered(with: current)
    check(labelControl.isHovered && abs(surface.opacity - 0.07) < 0.00001, "original light hover")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(abs((surface.animation(forKey: "pane-title-opacity")?.duration ?? 0) - 0.18) < 0.00001, "original title hover duration")
    }
    labelControl.cell!.highlight(true, withFrame: labelControl.bounds, in: labelControl)
    check(labelControl.isPressed && abs(surface.opacity - 0.11) < 0.00001, "native press has original precedence")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(abs((surface.animation(forKey: "pane-title-opacity")?.duration ?? 0) - 0.16) < 0.00001, "original title press duration")
    }
    labelControl.appearance = NSAppearance(named: .darkAqua); labelControl.viewDidChangeEffectiveAppearance()
    check(abs(surface.opacity - 0.15) < 0.00001, "original dark pressed surface")
    labelControl.cell!.highlight(false, withFrame: labelControl.bounds, in: labelControl)
    check(abs(surface.opacity - 0.11) < 0.00001, "release restores original dark hover")
    labelControl.mouseExited(with: old)
    check(labelControl.isHovered, "retired title exit cannot clear current decoration")
    window.key = false; NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    labelControl.mouseEntered(with: current)
    check(!labelControl.isHovered && !labelControl.isPressed && surface.animationKeys()?.isEmpty != false,
          "original key loss retires title state and motion")
    window.pointer = labelControl.convert(NSPoint(x: 12, y: 12), to: nil)
    window.key = true; NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    check(labelControl.isHovered, "key return samples exact original title surface")
    labelControl.isHidden = true; labelControl.viewDidHide(); labelControl.mouseEntered(with: current)
    check(!labelControl.isHovered && surface.animationKeys()?.isEmpty != false, "hiding retires title decoration")
    labelControl.isHidden = false; labelControl.mouseEntered(with: current)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    check(surface.animationKeys()?.isEmpty != false, "appearance option change removes old title animation")
    labelControl.removeFromSuperview(); labelControl.mouseEntered(with: current)
    check(!labelControl.isHovered && titleAreas().isEmpty, "detached title revokes exact tracking owner")
    weak var retiredTitle: PaneTitleControl?
    autoreleasepool {
        let temporary = PaneTitleControl(frame: .zero); retiredTitle = temporary
        host.addSubview(temporary); temporary.removeFromSuperview()
    }
    check(retiredTitle == nil, "passive title observers do not retain retired native owner")
    window.close()
    check(BrowserToolbarView.height == 32, "original native top-bar height")
    let toolbar = BrowserToolbarView(frame: .zero)
    var invocations = 0
    let item = ExtensionControlItem(identifier: "test", name: "Test", tooltip: "Test", accessibilityLabel: "Test",
        image: nil, pinnedIndex: 0, canChangePin: true, execute: { invocations += 1 }, showContextMenu: { _ in }, setPinned: { _ in })
    @MainActor func update(enabled: Bool) {
        toolbar.update(url: url, fullURL: true, enabled: enabled, canBack: true, canForward: false,
            loading: false, canReload: true, canCopy: true, canShowSiteInfo: true, canSplit: true,
            close: true, showSidebar: true, extensionItems: [item])
    }
    update(enabled: true)
    let reload = toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "Reload this page" }!
    check(reload.imagePosition == .imageOnly, "loading publication preserves the icon-only Reload control")
    check(reload.title.isEmpty && reload.accessibilityLabel() == "Reload this page",
          "custom-drawn Reload has no visible title while retaining its accessible label")
    if let button = reload as? NavigationControlButton {
        button.setLoading(true, enabled: true)
        check(button.title.isEmpty && button.accessibilityLabel() == "Stop Loading" && button.parcTooltip?.label == "Stop Loading",
              "loading keeps the custom glyph title-free and exposes Stop Loading")
        button.setLoading(false, enabled: true)
        check(button.title.isEmpty && button.accessibilityLabel() == "Reload this page" && button.parcTooltip?.label == "Reload this page",
              "returning to idle restores Reload accessibility and tooltip")
    } else { check(false, "toolbar Reload is the native navigation control") }
    check(toolbar.accessibilityRole() == .toolbar, "native Toolbar accessibility role")
    check(toolbar.layerContentsRedrawPolicy == .beforeViewResize && toolbar.layerContentsPlacement == .scaleAxesIndependently,
          "Sidebar round 3: the drawn rule is not redrawn every frame of the ⌘S group")
    func named(_ tip: String) -> NSView? { toolbar.subviews.first { $0.parcTooltip?.label == tip } }
    let lock = toolbar.subviews.compactMap { $0 as? SplitPaneControl }.first { $0.kind == .insecure }!
    for width: CGFloat in [160, 240, 300, 340, 720, 1200] {
        toolbar.frame = NSRect(x: 0, y: 0, width: width, height: BrowserToolbarView.height)
        toolbar.layoutSubtreeIfNeeded()
        let visible = toolbar.subviews.filter { !$0.isHidden && !$0.frame.isEmpty }
        check(visible.allSatisfy { toolbar.bounds.contains($0.frame) }, "narrow layout remains inside pane")
        check(visible.allSatisfy { $0.frame.midY == 16 }, "actual controls stay centered in original top-bar row")
        check(visible.enumerated().allSatisfy { index, view in
            visible.dropFirst(index + 1).allSatisfy { !view.frame.intersects($0.frame) }
        }, "visible controls do not overlap")
        check(["Go back", "Go forward", "Split View Options", "Remove Tab from Split View", "Show sidebar"].allSatisfy {
            named($0).map { !$0.isHidden } == true
        }, "original essential groups never yield room at \(width) points")
        check(lock.isHidden, "a secure or neutral page shows no insecure lock")
        let reloadControl = named("Reload this page")!, copyButton = named("Copy Current URL")!
        let titleControl = toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first!
        check(reloadControl.isHidden == (reloadControl.frame.maxX >= copyButton.frame.minX),
              "refreshHasRoom compares Reload with Copy while copying is available")
        check(copyButton.isHidden == !(named("Go forward")!.frame.maxX < copyButton.frame.minX),
              "copyHasRoom compares Copy with Forward")
        check(named("Site Control Center")!.isHidden == (titleControl.frame.maxX >= named("Site Control Center")!.frame.minX),
              "settingsHasRoom compares the title with Site Control Center")
    }
    let toolbarTitle = toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first!
    let copyControl = toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "Copy Current URL" }!
    check(toolbarTitle.frame.midX == toolbar.bounds.midX,
          "asymmetric edge controls do not shift the original centered title")
    check(copyControl.frame.maxX == toolbarTitle.frame.minX,
          "Copy Link occupies the leading balanced slot rather than the right accessory bank")
    check(copyControl.frame.width == 19,
          "native Copy uses the original twenty-four minus five footprint")
    let originalTitleCenter = toolbarTitle.frame.midX
    @MainActor func update(insecure: Bool) {
        toolbar.update(url: URL(string: "http://example.test/a"), fullURL: false, enabled: true, canBack: true, canForward: false,
            loading: false, canReload: true, canCopy: true, canShowSiteInfo: true, canSplit: true,
            close: true, showSidebar: true, insecure: insecure, extensionItems: [item])
        toolbar.layoutSubtreeIfNeeded()
    }
    update(insecure: true)
    check(!lock.isHidden && lock.frame.size == NSSize(width: 24, height: 24) && lock.frame.minY == 4,
          "URLIsInsecure shows the original 24-point lock in the center stack")
    check(lock.frame.minX == toolbarTitle.frame.minX - 19 && copyControl.frame.maxX == lock.frame.minX,
          "Copy, then the lock's 19-point footprint, then the title")
    check(toolbarTitle.frame.midX == toolbar.bounds.midX, "the balancing slug keeps the title centered on its pane")
    check(toolbar.hitTest(NSPoint(x: lock.frame.maxX - 2, y: 16)) === toolbarTitle
          && toolbar.hitTest(NSPoint(x: lock.frame.minX + 4, y: 16)) === lock,
          "the title stays above the lock's five-point overhang")
    var lockActions: [BrowserToolbarView.Action] = []
    var lockAnchors: [NSView] = []
    toolbar.onAction = { action, anchor in lockActions.append(action); lockAnchors.append(anchor) }
    lock.performClick(nil)
    check(lockActions.isEmpty, "the lock refuses dispatch outside a key window")
    let toolbarWindow = TitleWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 60),
        styleMask: .borderless, backing: .buffered, defer: false)
    toolbarWindow.isReleasedWhenClosed = false
    toolbarWindow.contentView!.addSubview(toolbar)
    lock.performClick(nil)
    check(lockActions.count == 1, "the lock dispatches didClickSiteInsecureButton to its owner once")
    if case .siteInsecure = lockActions[0] { checks += 1 } else { preconditionFailure("lock sends the insecure action") }
    check(lockAnchors.first === named("Site Control Center"),
          "the lock's Site Control Center is anchored at the Site Control Center button popover is")
    toolbar.removeFromSuperview(); toolbarWindow.close(); toolbar.onAction = nil
    update(insecure: false)
    check(lock.isHidden && copyControl.frame.maxX == toolbarTitle.frame.minX, "a secure page drops the lock and its slug")
    toolbar.setObstructedByModal(true, animated: false)
    check(named("Go back")!.alphaValue == 0 && named("Go forward")!.alphaValue == 0
          && named("Remove Tab from Split View")!.alphaValue == 1,
          "a presented modal hides Back and Forward while Close stays")
    check(!named("Go back")!.isHidden && named("Go back")!.frame.width == 28, "obstruction keeps the navigation frames")
    toolbar.setObstructedByModal(false, animated: false)
    check(named("Go back")!.alphaValue == 1 && named("Go forward")!.alphaValue == 1, "modal retirement restores navigation")
    update(enabled: true); toolbar.layoutSubtreeIfNeeded()
    toolbar.updateExtensionItems([]); toolbar.layoutSubtreeIfNeeded()
    check(toolbarTitle.frame.midX == originalTitleCenter,
          "extension removal cannot displace original pane center")
    toolbar.updateExtensionItems([item]); toolbar.layoutSubtreeIfNeeded()
    check(toolbarTitle.frame.midX == originalTitleCenter,
          "extension replacement preserves center without title or page replacement")
    for width: CGFloat in [160, 220, 250, 300, 480, 800] {
        let rect = NSRect(x: 11, y: 4, width: width, height: 24)
        let slot = PaneTitleLayout.slot(in: rect, leftEssential: 11, rightEssential: rect.maxX - 64,
            requiredLeft: rect.minX + 13, requiredRight: rect.maxX - 68, balancesCopy: false)
        check(slot.midX == rect.midX && slot.maxX <= rect.maxX - 68,
              "compact pane title centers within the original pane and respects actual essential controls")
    }
    let centered = PaneTitleLayout.slot(in: NSRect(x: 10, y: 2, width: 600, height: 28),
        leftEssential: 100, rightEssential: 550, requiredLeft: 68, requiredRight: 550, balancesCopy: true)
    check(centered.midX == 310 && centered.width == 378,
          "actual offset stack uses the larger symmetric edge reservation and two balancing footprints")
    let constrained = PaneTitleLayout.slot(in: NSRect(x: 0, y: 0, width: 250, height: 28),
        leftEssential: 120, rightEssential: 230, requiredLeft: 50, requiredRight: 230, balancesCopy: true)
    check(constrained.width == 112,
          "reference hundred-fifty floor applies to complete stack, not title")
    check(PaneTitleLayout.slot(in: NSRect(x: 0, y: 0, width: CGFloat.nan, height: 28),
        leftEssential: 0, rightEssential: 20, requiredLeft: 0, requiredRight: 20,
        balancesCopy: true) == .zero, "invalid geometry cannot create an actionable title region")
    let splitControls = toolbar.subviews.compactMap { $0 as? SplitPaneControl }.filter { $0.kind != .insecure }
    check(splitControls.allSatisfy { $0.frame.minY == 4 && $0.frame.maxY == 28 }, "symbol surface has original vertical inset")
    let closeControl = splitControls.first { $0.accessibilityLabel() == "Close Split View Pane" }!
    check(closeControl.frame.maxX == toolbar.bounds.maxX - 5, "trailing surface uses original five-point padding")
    check(splitControls.count == 2, "actual toolbar uses the shared attributed menu and close controls")
    check(splitControls.allSatisfy { $0.frame.size == SplitPaneControl.surfaceSize }, "both surfaces retain the recovered size")
    check(splitControls.contains { $0.accessibilityLabel() == "Split View Menu" }, "shared menu preserves its native AX identity")
    let menuControl = splitControls.first { $0.accessibilityLabel() == "Split View Menu" }!
    let menuFrame = menuControl.frame
    toolbar.setControlsRevealed(false)
    check(menuControl.alphaValue == 0 && closeControl.alphaValue == 1, "essential-only presentation hides menu without hiding Close")
    check(!menuControl.isHidden && menuControl.frame == menuFrame, "opacity preserves original control frame and action owner")
    check(named("Reload this page")!.alphaValue == 0 && named("Site Control Center")!.alphaValue == 0
          && toolbar.extensionToolbar.alphaValue == 0,
          "the reveal predicate also drives Reload, Site Control Center and the extensions control")
    check(named("Go back")!.alphaValue == 1 && named("Copy Current URL")!.alphaValue == 1,
          "navigation and the center stack are not driven by the reveal predicate")
    toolbar.setControlsRevealed(true)
    check(named("Reload this page")!.alphaValue == 1 && toolbar.extensionToolbar.alphaValue == 1,
          "revealing restores the predicate-driven controls")
    check(menuControl.alphaValue == 1 && closeControl.alphaValue == 1, "focused or hovered presentation restores only menu opacity")
    //
    let actionWindow = TitleWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false)
    actionWindow.isReleasedWhenClosed = false
    actionWindow.contentView = NSView(frame: actionWindow.contentView!.bounds)
    toolbar.frame = NSRect(x: 0, y: 0, width: 720, height: BrowserToolbarView.height)
    actionWindow.contentView!.addSubview(toolbar); toolbar.layoutSubtreeIfNeeded()
    let actionButtons = toolbar.subviews.compactMap { $0 as? BrowserToolbarActionButton }
    //
    check(Set(actionButtons.map { $0.parcTooltip?.label ?? "" }) == ["Copy Current URL", "Site Control Center", "Show sidebar"]
          && actionButtons.allSatisfy { $0.toolTip == nil },
          "the three Toolbar action buttons use the TopBarButtonStyle owner")
    let siteButton = actionButtons.first { $0.parcTooltip?.label == "Site Control Center" }!
    let siteSurface = siteButton.layer!.sublayers!.first!
    check(siteSurface.frame.height == 24 && siteSurface.frame.width == siteButton.bounds.width && siteSurface.cornerRadius == 6,
          "background surface keeps the slot width at the original height and corner")
    // N6: identical-frame action-surface layout skips CATransaction; a real
    // bounds change still rewrites; hover/press opacity refresh stays ungated.
    typealias SurfaceSkip = BrowserToolbarActionSurfaceLayoutSkip
    let matchedSurface = CGRect(x: 0, y: 4, width: 28, height: 24)
    check(SurfaceSkip.shouldSkip(current: matchedSurface, next: matchedSurface),
          "Matching action-surface frames skip")
    check(!SurfaceSkip.shouldSkip(current: .zero, next: matchedSurface),
          "Mismatched action-surface frame does not skip")
    GeometryWrites.install()
    @MainActor func surfaceWrites(_ body: () -> Void) -> Int { GeometryWrites.layerWrites(by: siteButton, during: body).count }
    // A stale surface frame, so the next layout pass has geometry to write.
    siteSurface.frame = .zero
    check(surfaceWrites { siteButton.needsLayout = true; siteButton.layoutSubtreeIfNeeded() } > 0
          && siteSurface.frame.height == 24,
          "first action-surface layout wrote the frame")
    check(surfaceWrites { siteButton.needsLayout = true; siteButton.layoutSubtreeIfNeeded() } == 0,
          "no-op action-surface layout skips CATransaction rewrite")
    let priorSurfaceFrame = siteSurface.frame
    siteButton.setFrameSize(NSSize(width: siteButton.bounds.width + 4, height: siteButton.bounds.height))
    check(surfaceWrites { siteButton.layoutSubtreeIfNeeded() } > 0
          && siteSurface.frame.width == priorSurfaceFrame.width + 4
          && siteSurface.frame.height == 24,
          "an action-surface bounds change still rewrites the frame")
    check(surfaceWrites { siteButton.needsLayout = true; siteButton.layoutSubtreeIfNeeded() } == 0,
          "follow-up action-surface layout at the new size remains a no-op")
    siteButton.setFrameSize(NSSize(width: priorSurfaceFrame.width, height: siteButton.bounds.height))
    siteButton.layoutSubtreeIfNeeded()
    siteButton.appearance = NSAppearance(named: .aqua); siteButton.viewDidChangeEffectiveAppearance()
    check(siteSurface.opacity == 0 && abs((siteButton.contentTintColor?.alphaComponent ?? 0) - 0.55) < 0.00001,
          "original light rest surface and enabled glyph")
    siteButton.updateTrackingAreas()
    let siteHover = TitleTrackingEvent(); siteHover.area = siteButton.trackingAreas.first { $0.owner === siteButton && !$0.options.contains(.cursorUpdate) }
    siteButton.mouseEntered(with: siteHover)
    check(siteButton.isHovered && abs(siteSurface.opacity - 0.05) < 0.00001, "original light hover surface")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(abs((siteSurface.animation(forKey: "toolbar-action-opacity")?.duration ?? 0) - 0.18) < 0.00001, "original hover duration")
    }
    siteButton.cell!.highlight(true, withFrame: siteButton.bounds, in: siteButton)
    check(siteButton.isPressed && abs(siteSurface.opacity - 0.09) < 0.00001, "native press has original precedence")
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(abs((siteSurface.animation(forKey: "toolbar-action-opacity")?.duration ?? 0) - 0.16) < 0.00001, "original press duration")
    }
    siteButton.appearance = NSAppearance(named: .darkAqua); siteButton.viewDidChangeEffectiveAppearance()
    check(abs(siteSurface.opacity - 0.13) < 0.00001 && abs((siteButton.contentTintColor?.alphaComponent ?? 0) - 0.675) < 0.00001,
          "original dark pressed surface and enabled glyph")
    siteButton.cell!.highlight(false, withFrame: siteButton.bounds, in: siteButton)
    check(!siteButton.isPressed && abs(siteSurface.opacity - 0.09) < 0.00001, "release restores original dark hover")
    siteButton.isEnabled = false
    check(!siteButton.isHovered && siteSurface.opacity == 0 && abs((siteButton.contentTintColor?.alphaComponent ?? 0) - 0.25) < 0.00001,
          "disabled glyph and no surface")
    siteButton.isEnabled = true; siteButton.mouseEntered(with: siteHover)
    let motionChecked = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    siteButton.isEnabled = true
    actionWindow.pointer = siteButton.convert(NSPoint(x: 5, y: 5), to: nil); siteButton.updateTrackingAreas()
    let republishedHover = TitleTrackingEvent(); republishedHover.area = siteButton.trackingAreas.first { $0.owner === siteButton && !$0.options.contains(.cursorUpdate) }
    check(siteButton.isHovered && abs(siteSurface.opacity - 0.09) < 0.00001
          && (!motionChecked || siteSurface.animation(forKey: "toolbar-action-opacity") != nil),
          "unchanged enable and layout re-sampling keep the running hover fade")
    siteButton.isEnabled = false; siteButton.isEnabled = true
    check(siteButton.isHovered && siteSurface.opacity > 0, "re-enabling under a resting pointer restores hover")
    siteButton.mouseExited(with: republishedHover); actionWindow.pointer = NSPoint(x: -100, y: -100)
    siteButton.mouseEntered(with: republishedHover)
    let copyButton = actionButtons.first { $0.parcTooltip?.label == "Copy Current URL" }!
    check(copyButton.layer!.sublayers!.first!.frame.size == NSSize(width: 19, height: 24), "Copy surface keeps its 19-point slot")
    siteButton.appearance = nil
    //
    // the scheme; without one the bar inherits the window's own appearance.
    func ink(_ view: NSButton) -> CGFloat? { view.contentTintColor?.usingColorSpace(.sRGB)?.redComponent }
    func fill() -> NSColor? { toolbar.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) } }
    let page = NSObject()
    for (red, green, blue, dark, label) in [(0.0, 0.0, 0.0, true, "ChatGPT black"), (1.0, 1.0, 1.0, false, "white"),
                                            (0.059, 0.059, 0.059, true, "YouTube #0F0F0F"),
                                            (0.02, 0.447, 0.925, true, "1Password blue"), (1.0, 0.8, 0.0, false, "yellow")] {
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        check(PaneTopBarColor.usesDarkScheme(on: color) == dark, "\(label) page colour picks the original contrast scheme")
        toolbar.setPageColor(color, for: NSObject()); siteButton.viewDidChangeEffectiveAppearance()
        check(siteButton.appearance?.name == (dark ? .darkAqua : .aqua) && ink(siteButton) == (dark ? 1 : 0),
              "the bar's controls take the \(label) page colour's scheme")
        check(fill().map { abs($0.redComponent - red) < 0.01 && abs($0.blueComponent - blue) < 0.01 } == true,
              "the bar fills with the \(label) page colour")
        check(toolbar.layer?.animation(forKey: "page-color") == nil, "a newly shown content's colour applies at once")
    }
    toolbar.setPageColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), for: page)
    toolbar.setPageColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), for: page)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        check(abs((toolbar.layer?.animation(forKey: "page-color")?.duration ?? 0) - 0.18) < 0.00001,
              "a later colour for the same content crossfades over 0.18 s")
    }
    // Chromium resets both colours for each committed document; the same
    // page keeps its colour while it loads without one.
    toolbar.setPageColor(nil, for: page, holdingWhileUnknown: true)
    check(toolbar.pageColor != nil, "a loading page without a colour yet keeps its last colour")
    toolbar.setPageColor(nil, for: NSObject(), holdingWhileUnknown: true)
    check(toolbar.pageColor == nil, "another content's bar never keeps the previous content's colour")
    toolbar.setPageColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), for: page)
    toolbar.setPageColor(nil, for: page)
    check(toolbar.pageColor == nil, "a page that finished loading without a colour leaves the bar clear")
    toolbar.setPageColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5), for: page)
    check(toolbar.pageColor == nil && siteButton.appearance == nil, "a translucent page colour leaves the bar clear")
    // The one route panes, Peek and colour-only notifies share.
    let native = PCNativePage()
    let theme = NSColor(srgbRed: 0.02, green: 0.447, blue: 0.925, alpha: 1)
    let background = NSColor(srgbRed: 0.059, green: 0.059, blue: 0.059, alpha: 1)
    @MainActor func shown() -> NSColor? { toolbar.pageColor?.usingColorSpace(.sRGB) }
    native.developerModeTint = theme; native.pageBackgroundColor = background
    toolbar.showPageColor(of: native, failing: false)
    check(shown() == theme.usingColorSpace(.sRGB), "the declared theme colour outranks the page background")
    native.developerModeTint = nil; toolbar.showPageColor(of: native, failing: false)
    check(shown() == background.usingColorSpace(.sRGB), "without a theme colour the bar takes the page background")
    native.legacy = true; toolbar.showPageColor(of: native, failing: false)
    check(shown() == nil, "an engine without pageBackgroundColor leaves a page without a theme colour clear")
    native.legacy = false; toolbar.showPageColor(of: native, failing: false)
    native.pageBackgroundColor = nil; native.loading = true; toolbar.showPageColor(of: native, failing: false)
    check(shown() == background.usingColorSpace(.sRGB), "a committed document still loading keeps the last colour")
    native.loading = false; toolbar.showPageColor(of: native, failing: false)
    check(shown() == nil, "a document that finished loading without a colour clears the bar")
    native.pageBackgroundColor = background; native.loading = true; toolbar.showPageColor(of: native, failing: false)
    toolbar.showPageColor(of: native, failing: true)
    check(shown() == nil, "a failure or crash presentation clears the bar, loading or not")
    toolbar.showPageColor(of: native, failing: false); native.isClosed = true
    toolbar.showPageColor(of: native, failing: false)
    check(shown() == nil, "a closed page leaves the bar clear")
    // Overlay 294's engine: the client's colour, never the theme stand-ins.
    // A bar outside a browser window counts as private, so the test's colours
    // stay out of real preferences.
    let sampled = PCNativePage(); sampled.sampler = true
    sampled.url = URL(string: "https://my.1password.com/vault")
    sampled.developerModeTint = theme; sampled.pageBackgroundColor = background
    toolbar.showPageColor(of: sampled, failing: false)
    check(shown() == NSColor.white.usingColorSpace(.sRGB), "a sampled page with no colour or cache starts white")
    let blue = NSColor(srgbRed: 0.1, green: 0.45, blue: 0.91, alpha: 1)
    sampled.hasTopBandColorSample = true; sampled.topBandColor = blue; sampled.topBandColorHost = "my.1password.com"
    toolbar.showPageColor(of: sampled, failing: false)
    check(shown().map { TopBarColorClient.distance($0, blue) < 0.0001 } == true, "the sample replaces the initial colour")
    check(toolbar.layer?.animation(forKey: "page-color") == nil, "a sample without shouldCrossfade cuts")
    sampled.topBandColor = nil; toolbar.showPageColor(of: sampled, failing: false)
    check(shown().map { TopBarColorClient.distance($0, blue) < 0.0001 } == true, "a sample without a colour keeps the bar's colour")
    let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    sampled.topBandColor = black; sampled.topBandColorCrossfades = true
    toolbar.showPageColor(of: sampled, failing: false)
    check(toolbar.layer?.animation(forKey: "page-color") != nil, "a later sample with shouldCrossfade crossfades")
    let sibling = PCNativePage(); sibling.sampler = true; sibling.url = URL(string: "https://my.1password.com/other")
    toolbar.showPageColor(of: sibling, failing: false)
    check(shown().map { TopBarColorClient.distance($0, blue) < 0.0001 } == true,
          "another page on the host starts with the host's settled colour")
    toolbar.showPageColor(of: sampled, failing: true)
    check(shown() == nil, "a failure covers a sampled page's colour too")
    toolbar.setPageColor(nil, for: nil)
    for name in [NSAppearance.Name.aqua, .darkAqua] {
        actionWindow.appearance = NSAppearance(named: name); siteButton.viewDidChangeEffectiveAppearance()
        let dark = name == .darkAqua
        check(toolbar.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name && ink(siteButton) == (dark ? 1 : 0),
              "without a page colour the bar follows the window's \(dark ? "dark" : "light") appearance")
        check(fill().map { $0.redComponent == 1 && abs($0.alphaComponent - (dark ? 0.1 : 0.666)) < 0.001 } == true,
              "without a page colour the bar shows the content backing")
    }
    // Over a Space theme the backing's contrast picks the scheme; the window
    // still resolves the backing.
    let lightTheme = ThemeChromePalette(theme: SpaceTheme(primaryColor: ThemeColor(red: 0.6, green: 0.85, blue: 0.7), colorCount: 2),
                                        isDark: false)
    let darkTheme = ThemeChromePalette(theme: SpaceTheme(primaryColor: ThemeColor(red: 0.6, green: 0.85, blue: 0.7), colorCount: 2),
                                       isDark: true)
    for (palette, window, dark) in [(lightTheme, NSAppearance.Name.darkAqua, false), (lightTheme, .aqua, false),
                                    (darkTheme, .darkAqua, true), (darkTheme, .aqua, false)] {
        actionWindow.appearance = NSAppearance(named: window); toolbar.themeBackground = palette.background
        siteButton.viewDidChangeEffectiveAppearance()
        check(siteButton.appearance?.name == (dark ? .darkAqua : .aqua) && ink(siteButton) == (dark ? 1 : 0),
              "a \(palette.isDark ? "dark" : "light") theme in a \(window == .darkAqua ? "dark" : "light") window keeps readable ink")
        check(fill().map { abs($0.alphaComponent - (window == .darkAqua ? 0.1 : 0.666)) < 0.001 } == true,
              "the window's appearance, not the bar's scheme, resolves the backing")
    }
    toolbar.setPageColor(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), for: NSObject())
    check(siteButton.appearance?.name == .darkAqua, "a page colour outranks the theme backing")
    toolbar.setPageColor(nil, for: nil); toolbar.themeBackground = nil
    actionWindow.appearance = nil
    actionWindow.key = false; NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: actionWindow)
    check(!siteButton.isHovered && siteSurface.opacity == 0 && siteSurface.animationKeys()?.isEmpty != false,
          "key loss retires action hover and motion")
    actionWindow.key = true
    toolbar.removeFromSuperview(); actionWindow.close()
    // The extensions control dims to one half while controls are disabled.
    update(enabled: false)
    check(toolbar.extensionToolbar.alphaValue == 0.5,
          "disabled controls dim the extensions control to 0.5")
    update(enabled: true)
    check(toolbar.extensionToolbar.alphaValue == 1, "enabled controls restore the extensions control")
    // Copy exists only while copying is available; Reload stops at the
    // leftmost shown center element.
    let longURL = URL(string: "https://www.example-domain-with-a-long-name.test/some/really/long/path?query=1")!
    for width in stride(from: CGFloat(220), through: CGFloat(420), by: CGFloat(20)) {
        for (canCopy, insecure) in [(false, false), (false, true), (true, true), (true, false)] {
            toolbar.frame = NSRect(x: 0, y: 0, width: width, height: BrowserToolbarView.height)
            toolbar.update(url: longURL, fullURL: true, enabled: true, canBack: true, canForward: true,
                loading: false, canReload: true, canCopy: canCopy, canShowSiteInfo: true, canSplit: true,
                close: true, showSidebar: false, insecure: insecure, extensionItems: [])
            toolbar.layoutSubtreeIfNeeded()
            let copyButton = named("Copy Current URL")!
            check(!canCopy ? copyButton.isHidden : true, "Copy is absent while copying is unavailable at \(width)")
            let shown = toolbar.subviews.filter { !$0.isHidden && $0.frame.width > 0 }
            let title = toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first!
            check(shown.enumerated().allSatisfy { index, view in
                shown.dropFirst(index + 1).allSatisfy { other in
                    let overhang = (view === lock && other === title) || (view === title && other === lock)
                    return overhang || !view.frame.intersects(other.frame)
                }
            }, "no control overlaps another at \(width) (canCopy \(canCopy), insecure \(insecure))")
        }
    }
    // Bar choice follows the content kind, not the page view's visibility.
    check(PaneSurface.page.usesPageBar(pageLive: true) && PaneSurface.failure.usesPageBar(pageLive: true),
          "a navigation failure or renderer crash over a live page keeps the web bar")
    check(!PaneSurface.local.usesPageBar(pageLive: true) && !PaneSurface.page.usesPageBar(pageLive: false)
          && !PaneSurface.failure.usesPageBar(pageLive: false),
          "a local content or a closed page takes the content bar")
    // A content without a page keeps the same bar without site controls.
    toolbar.frame = NSRect(x: 0, y: 0, width: 720, height: BrowserToolbarView.height)
    toolbar.update(url: nil, documentTitle: "Original Note", fullURL: false, enabled: true, canBack: false,
        canForward: false, loading: false, canReload: false, canCopy: false, canShowSiteInfo: false,
        canSplit: true, close: true, showSidebar: true, siteControls: false, extensionItems: [item])
    toolbar.layoutSubtreeIfNeeded()
    let documentTitle = toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first!
    check(documentTitle.accessibilityLabel() == "Original Note" && documentTitle.frame.midX == toolbar.bounds.midX,
          "a document's authored title sits centered in the shared bar")
    check(named("Site Control Center")!.isHidden
          && toolbar.extensionToolbar.subviews.isEmpty && named("Copy Current URL")!.isHidden,
          "a document has no Site Control Center, extension or Copy control")
    toolbar.updateExtensionItems([item])
    check(toolbar.extensionToolbar.subviews.isEmpty, "a later extension refresh cannot give a document bar pins")
    check(!named("Go back")!.isHidden && !(named("Go back") as! NSButton).isEnabled
          && !(named("Go forward") as! NSButton).isEnabled && !named("Show sidebar")!.isHidden
          && !menuControl.isHidden && !closeControl.isHidden,
          "a document keeps the disabled navigation group, sidebar button, menu and Close")
    update(enabled: true); toolbar.layoutSubtreeIfNeeded()
    toolbar.onAction = { _, _ in invocations += 1 }
    let copy = toolbar.subviews.compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "Copy Current URL" }!
    copy.performClick(nil)
    check(invocations == 1, "actual Cocoa button dispatch reaches the owned callback")
    let pin = toolbar.extensionToolbar.subviews.compactMap { $0 as? NSButton }.first!
    update(enabled: false)
    toolbar.updateExtensionItems([item])
    check(toolbar.extensionToolbar.subviews.isEmpty, "background/blocked owner does not republish actionable pins")
    pin.performClick(nil)
    check(invocations == 1, "retired pinned button cannot invoke its old lease")
    toolbar.invalidate()
    copy.performClick(nil)
    check(invocations == 1, "detached Toolbar cannot dispatch")
    print("Browser Toolbar component checks: \(checks) passed")
}
