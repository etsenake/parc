import AppKit

final class FocusStop: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
}

@main
struct EmptyStateViewTests {
    static var failures = 0, count = 0
    static func check(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
    static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.6)) }
    static func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 228, height: 300), styleMask: [.borderless],
                 backing: .buffered, defer: false)
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parc-empty-state-view-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let profile = store.activeSpace.profileID
        let other = store.createProfile(name: "Work")
        typealias E = SidebarChromeLayout.AppTrayEmptyState
        typealias L = SidebarChromeLayout

        let windows = [window(), window()]
        let views = windows.map { _ in FavoritesEmptyStateView() }
        for (window, view) in zip(windows, views) { window.contentView?.addSubview(view) }
        func render(favorites: Int = 0, profileID: UUID? = profile, privateWindow: Bool = false) {
            for view in views {
                view.update(favorites: favorites, profileID: profileID, settings: store.state.settings,
                            privateWindow: privateWindow) { store.dismissFavoritesEmptyState(profileID: $0) }
            }
        }
        render()
        let view = views[0], window = windows[0]
        let height = view.fittingHeight(width: 228)
        view.frame = NSRect(x: 0, y: 0, width: 228, height: height)
        view.layoutSubtreeIfNeeded()

        let labels = view.subviews.compactMap { $0 as? NSTextField }
        let title = labels.first { $0.stringValue == FavoritesEmptyStateView.title }
        let subtitle = labels.first { $0.stringValue == FavoritesEmptyStateView.subtitle }
        check(FavoritesEmptyStateView.title == "Drag to add Favorites"
              && FavoritesEmptyStateView.subtitle == "Favorites keep your most used sites and apps close", "the empty state strings")
        guard let title, let subtitle, let button = view.subviews.compactMap({ $0 as? NSButton }).first,
              let icon = view.subviews.compactMap({ $0 as? NSImageView }).first else {
            check(false, "the view holds the icon, both labels and the Dismiss button"); exit(1)
        }
        func attribute(_ field: NSTextField, _ key: NSAttributedString.Key) -> Any? {
            field.attributedStringValue.attribute(key, at: 0, effectiveRange: nil)
        }
        let titleFont = attribute(title, .font) as? NSFont, subtitleFont = attribute(subtitle, .font) as? NSFont
        check(titleFont?.pointSize == 13 && titleFont == NSFont.systemFont(ofSize: 13, weight: .medium), "title: 13-point medium")
        check(subtitleFont?.pointSize == 12 && subtitleFont == NSFont.systemFont(ofSize: 12, weight: .regular), "subtitle: 12-point regular")
        check((attribute(subtitle, .kern) as? Double) == -0.2 && attribute(title, .kern) == nil, "the subtitle alone is kerned −0.2")
        check([title, subtitle].allSatisfy { (attribute($0, .paragraphStyle) as? NSParagraphStyle)?.alignment == .center }, "both centred")

        let sizes = (icon.image?.size ?? .zero, title.frame.size, subtitle.frame.size)
        check(height == E.height(icon: sizes.0, title: sizes.1, subtitle: sizes.2) && height > E.minimumHeight,
              "fitting height is the model's, taller than the tray's 63-point minimum (\(height))")
        let frames = E.frames(width: 228, height: height, icon: sizes.0, title: sizes.1, subtitle: sizes.2)
        check(icon.frame == frames.icon && title.frame == frames.title && subtitle.frame == frames.subtitle && button.frame == frames.close,
              "subviews at the model's frames")
        check(subtitle.frame.width <= 150 && subtitle.frame.height > title.frame.height * 1.5, "the subtitle wraps within 150 points")
        check(icon.image?.isTemplate == false && (icon.image?.size.height ?? 0) > 12, "a 16-point palette star")
        func holdsText(_ label: NSTextField) -> Bool {
            guard let cell = label.cell else { return false }
            return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.frame.width, height: .greatestFiniteMagnitude)).height
                <= label.frame.height
        }
        check(holdsText(title) && holdsText(subtitle) && title.frame.height < 20, "at 228 the title takes one line, all text shown")

        let elements = (view.accessibilityChildren() ?? []).compactMap { $0 as AnyObject as? NSAccessibilityProtocol }
        let roles = elements.compactMap { $0.accessibilityRole() }
        let owners = elements.compactMap { ($0 as? NSView) ?? ($0 as? NSCell)?.controlView }
        check(roles == [.image, .staticText, .staticText, .button] && owners == [icon, title, subtitle, button],
              "AX children: star, title, subtitle and Dismiss in that order (\(roles))")
        check(button.accessibilityLabel() == "Dismiss" && button.accessibilityIdentifier() == "sidebarFavoritesEmptyStateDismissButton",
              "Dismiss label and identifier")
        check(button.focusRingType != .none && !button.focusRingMaskBounds.isEmpty && !button.refusesFirstResponder,
              "Dismiss can take focus and draws AppKit's ring")

        var hides: [UUID] = []
        let menuView = FavoritesEmptyStateView()
        menuView.update(favorites: 0, profileID: other, settings: store.state.settings, privateWindow: false) { hides.append($0) }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let menu = menuView.menu(for: event)
        check(menu?.items.map(\.title) == ["Hide"], "the tray menu has Hide")
        if let hide = menu?.items.first, let action = hide.action { NSApp.sendAction(action, to: hide.target, from: hide) }
        check(hides == [other], "Hide calls back with the profile")

        let narrowView = views[1]
        let narrow = narrowView.fittingHeight(width: 164)
        narrowView.frame = NSRect(x: 0, y: 0, width: 164, height: narrow)
        narrowView.layoutSubtreeIfNeeded()
        let narrowLabels = narrowView.subviews.compactMap { $0 as? NSTextField }
        check(narrowLabels.count == 2 && narrowLabels.allSatisfy(holdsText) && narrowLabels.allSatisfy { $0.frame.width <= 128 },
              "at 164 both labels wrap within 128 points and show all their text")
        check(narrowLabels.first { $0.stringValue == FavoritesEmptyStateView.title }.map { $0.frame.height > 16 * 1.5 } == true
              && narrow > height, "at 164 the title takes two lines and the tray grows (\(narrow))")

        let border = view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first
        check(title.alphaValue == 1 && abs(subtitle.alphaValue - 0.7) < 0.001 && border?.lineDashPattern == [5], "idle: 1 / 0.7, dashed [5]")
        check(view.showsDrop(true), "a drop over the shown view takes the dragging style in place of a cue")
        settle()
        check(abs(title.alphaValue - 0.5) < 0.001 && abs(subtitle.alphaValue - 0.3) < 0.001 && border?.lineDashPattern == nil,
              "dragging: 0.5 / 0.3, solid")
        view.showsDrop(false)
        settle()
        check(title.alphaValue == 1 && border?.lineDashPattern == [5], "idle again")

        let star = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))?.size
        check(sizes.0 == star, "the star is the system's star.circle.fill at 16-point medium (\(sizes.0))")
        check(views.allSatisfy { !$0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == height }
              && height == 86 + sizes.0.height && L.tablistTop(trayHeight: height) == 82 + height,
              "an undismissed empty profile: tray \(height), list at \(L.tablistTop(trayHeight: height))")
        render(favorites: 1)
        check(views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 63, width: 228) == 63 }, "Favorites: the grid's tray")
        render(privateWindow: true)
        check(views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == 0 }, "a private window shows none")
        render(profileID: nil)
        check(views.allSatisfy(\.isHidden), "no Space, no empty state")
        check(!view.showsDrop(true), "a hidden view draws no dragging style")
        view.showsDrop(false)
        render()

        let stop = FocusStop(frame: NSRect(x: 0, y: 200, width: 20, height: 20))
        window.contentView?.addSubview(stop)
        SidebarAccessibility.link([button, stop], within: window.contentView!, exit: nil, bypassed: false)
        check(window.makeFirstResponder(button) && window.firstResponder === button, "Dismiss takes focus")
        button.performClick(nil)
        check(store.state.settings.topAppsEmptyStateDismissedForProfiles == [profile], "Dismiss records its profile in the store")
        render()
        check(views.allSatisfy { $0.isHidden && $0.trayHeight(gridHeight: 0, width: 228) == 0 }
              && L.tablistTop(trayHeight: view.trayHeight(gridHeight: 0, width: 228)) == 87,
              "after Dismiss every window of the profile collapses its tray: list at 87")
        check(window.firstResponder === stop, "the next stop takes Dismiss's focus, not the window")
        render(profileID: other)
        check(views.allSatisfy { !$0.isHidden }, "another profile keeps its empty state")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("SidebarFavoritesEmptyState view: \(count) assertions passed")
    }
}
