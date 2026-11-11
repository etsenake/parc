import AppKit
import ObjectiveC

private enum ParentResignOnHUDKey {
    private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        exchange()
    }
    static func remove() {
        guard installed else { return }
        installed = false
        exchange()
    }
    private static func exchange() {
        let window = NSWindow.self
        let original = class_getInstanceMethod(window, #selector(NSWindow.makeKeyAndOrderFront(_:)))!
        let replacement = class_getInstanceMethod(window, #selector(NSWindow.parcResignParentOnHUDKey(_:)))!
        method_exchangeImplementations(original, replacement)
    }
}

private enum DisplayRequests {
    static var marked: Set<ObjectIdentifier> = []
    private static var installed = false
    static func install() {
        guard !installed else { return }
        installed = true
        marked = []
        exchange()
    }
    static func remove() {
        guard installed else { return }
        installed = false
        exchange()
    }
    private static func exchange() {
        let original = class_getInstanceMethod(NSView.self, #selector(setter: NSView.needsDisplay))!
        let replacement = class_getInstanceMethod(NSView.self, #selector(NSView.parcRecordNeedsDisplay(_:)))!
        method_exchangeImplementations(original, replacement)
    }
}

extension NSView {
    @objc func parcRecordNeedsDisplay(_ flag: Bool) {
        if flag { DisplayRequests.marked.insert(ObjectIdentifier(self)) }
        parcRecordNeedsDisplay(flag)
    }
}

extension NSWindow {
    @objc func parcResignParentOnHUDKey(_ sender: Any?) {
        if self is SidebarPlusMenuWindow, let parent, parent.styleMask.contains(.titled) {
            parent.resignKey()
        }
        parcResignParentOnHUDKey(sender)
    }
}

@main @MainActor struct PlusMenuTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fatalError("SidebarPlusMenu: \(message)") }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    static func waitForClose(_ parent: NSWindow) {
        let until = Date(timeIntervalSinceNow: 0.3)
        while parent.childWindows?.isEmpty == false, Date() < until {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    static func resolved(_ color: NSColor, dark: Bool) -> [CGFloat] {
        var components: [CGFloat] = []
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let value = color.usingColorSpace(.extendedSRGB)!
            components = [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
        return components
    }

    static func same(_ a: NSColor, _ b: NSColor, dark: Bool) -> Bool {
        zip(resolved(a, dark: dark), resolved(b, dark: dark)).allSatisfy { abs($0 - $1) < 1e-5 }
    }

    static func over(_ foreground: NSColor, _ background: [CGFloat], dark: Bool) -> [CGFloat] {
        let f = resolved(foreground, dark: dark)
        return (0..<3).map { (f[$0] * f[3] + background[$0] * (1 - f[3])) * 255 }
    }

    static func render(_ view: NSView, dark: Bool) -> NSBitmapImageRep {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -14_000, y: -14_000), size: view.frame.size),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = view
        let rep = capture(view)
        window.contentView = nil
        return rep
    }

    static func capture(_ view: NSView) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!.retagging(with: .sRGB)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func pixel(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> [CGFloat] {
        var raw = [Int](repeating: 0, count: 4)
        rep.getPixel(&raw, atX: Int(x * 2), y: Int(y * 2))
        return raw.prefix(3).map(CGFloat.init)
    }

    static func near(_ a: [CGFloat], _ b: [CGFloat], _ tolerance: CGFloat = 2) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    static func ink(_ rep: NSBitmapImageRep, _ box: NSRect, background: [CGFloat]) -> (color: [CGFloat], minX: CGFloat, maxX: CGFloat) {
        var best: (CGFloat, [CGFloat]) = (0, background)
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        for py in Int(box.minY * 2)..<Int(box.maxY * 2) {
            for px in Int(box.minX * 2)..<Int(box.maxX * 2) {
                let value = pixel(rep, CGFloat(px) / 2, CGFloat(py) / 2)
                let distance = zip(value, background).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
                if distance > best.0 { best = (distance, value) }
                if distance > 40 * 40 { minX = min(minX, CGFloat(px) / 2); maxX = max(maxX, CGFloat(px + 1) / 2) }
            }
        }
        return (best.1, minX, maxX)
    }

    static func inkWidth(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        NSAttributedString(string: text, attributes: attributes)
            .boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics]).width
    }

    static func parentAndAnchor() -> (NSWindow, NSView) {
        let parent = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 400, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 300, y: 10, width: 32, height: 32))
        parent.contentView?.addSubview(anchor)
        parent.orderFront(nil)
        return (parent, anchor)
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let titles = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: true, canSplit: true) { id in
            id == "newTab:" ? "⌘T" : id == "createEasel:" ? "⌃⇧E" : id == "createNote:" ? "⌃⇧N" : id == "split:" ? "⌃⇧=" : ""
        }
        check(titles.map(\.title) == ["New Space", "New Folder", "New Easel", "New Note", "New Split", "New Tab"],
              "plus menu order matches Parc 1.170, with New Note in the Boost row")
        check(titles.map(\.action) == [.space, .folder, .easel, .note, .split, .tab], "plus menu actions")
        check(titles.allSatisfy(\.enabled), "creation rows are enabled")
        check(!titles.contains { $0.title.contains("Boost") }, "Boost is excluded")
        check(titles.first { $0.action == .note }?.symbol == "doc.text", "New Note uses the doc.text image")
        check(titles.map(\.symbol) == ["add-space", "folder", "scribble", "doc.text", "split-add-right", "add-tab"],
              "plus menu images are Parc's")
        check(SidebarPlusMenuArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("SidebarPlusMenu", isDirectory: true)
              && SidebarPlusMenuArtwork.image("add-space") != nil, "the artwork loads from the bundle's SidebarPlusMenu resources")
        for name in ["add-space", "split-add-right", "add-tab"] {
            let image = SidebarPlusMenuArtwork.image(name)
            check(image?.isTemplate == true && image?.size == NSSize(width: 28, height: 28)
                  && image?.representations.contains { $0.pixelsWide == 56 } == true,
                  "the \(name) template loads at 28 points with its 2x rendition")
        }
        check(SidebarPlusMenuArtwork.image("folder") == nil, "SF Symbol rows do not resolve as copied artwork")
        check(titles.first { $0.action == .note }?.shortcut == "⌃⇧N", "New Note shows Control-Shift-N")
        check(titles.first { $0.action == .tab }?.shortcut == "⌘T", "New Tab shows its live shortcut")
        check(titles.first { $0.action == .easel }?.shortcut == "⌃⇧E", "New Easel shows Control-Shift-E")
        check(titles.first { $0.action == .split }?.shortcut == "⌃⇧=", "New Split shows Control-Shift-Equals")
        check(!titles.contains(where: { $0.title.contains("Settings") || $0.title.contains("Theme") || $0.title.contains("Rename") || $0.title.contains("preview") }),
              "plus menu is not the Space context menu")

        let noteOnly = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: false, canCreateNote: true, canSplit: true)
        check(noteOnly.first { $0.action == .easel }?.enabled == false && noteOnly.first { $0.action == .note }?.enabled == true,
              "Easel and Note availability are independent")
        let easelOnly = SidebarPlusMenuModel.rows(privateBrowsing: false, canCreateEasel: true, canCreateNote: false, canSplit: true)
        check(easelOnly.first { $0.action == .easel }?.enabled == true && easelOnly.first { $0.action == .note }?.enabled == false,
              "New Note follows its own availability")

        let privateRows = SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false, canSplit: false)
        check(privateRows.first { $0.action == .tab }?.enabled == true, "private windows still create a tab")
        check(privateRows.filter { $0.action != .tab }.allSatisfy { !$0.enabled },
              "private windows disable Space, Folder, Easel, Note and Split")

        var chosen: SidebarPlusAction?
        let neutral = PArcMenuColors(theme: SpaceTheme())
        let view = SidebarPlusMenuView(rows: titles, colors: neutral) { chosen = $0 }
        check(view.menuSize.width == 210 && view.menuSize.height == 290, "Parc HUD size 210 × 290")
        check(view.appearance == nil, "the HUD takes the app appearance, not a forced dark one")
        check(view.accessibilityRole() == .menu, "HUD is a menu")
        check(view.accessibilityLabel() == "New Tab, Folder, or Space", "HUD keeps the plus button name")
        let buttons = descendants(view).compactMap { $0 as? SidebarPlusRowButton }
        check(buttons.map(\.row.title) == titles.map(\.title), "HUD rows match the model")
        check(buttons.map(\.frame) == [
            NSRect(x: 8, y: 8, width: 194, height: 40),
            NSRect(x: 8, y: 48, width: 194, height: 40),
            NSRect(x: 8, y: 105, width: 194, height: 40),
            NSRect(x: 8, y: 145, width: 194, height: 40),
            NSRect(x: 8, y: 202, width: 194, height: 40),
            NSRect(x: 8, y: 242, width: 194, height: 40)
        ], "Parc HUD rows keep balanced 8-point insets and PArcMenu's 8 + 1 + 8 separator bands")
        check(buttons.last?.emphasized == true && buttons.last?.row.action == .tab, "New Tab starts highlighted")
        check(buttons.filter(\.emphasized).count == 1, "only one highlighted row")

        let purple = SpaceTheme(primaryColor: ThemeColor(hex: "3D2468"), colorCount: 1, appearance: .dark, noise: 0.3)
        let blue = SpaceTheme(primaryColor: ThemeColor(hex: "3F9BD6"), colorCount: 2, noise: 0.3)
        let srgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        for theme in [purple, blue, SpaceTheme()] {
            let colors = PArcMenuColors(theme: theme)
            for dark in [false, true] {
                let palette = ThemeChromePalette(theme: theme, isDark: dark)
                let name = "\(theme.primaryColor?.hex ?? "colourless") \(dark ? "dark" : "light")"
                check(same(colors.base, dark ? .black : .white, dark: dark), "\(name): the card base is \(dark ? "black" : "white")")
                check(same(colors.background, palette.backgroundExtra, dark: dark), "\(name): the card is backgroundExtra")
                check(same(colors.hover, palette.hover, dark: dark), "\(name): rows and separators are hover")
                check(same(colors.subtitle, palette.subtitle, dark: dark), "\(name): shortcuts are subtitle")
                check(same(colors.title, dark ? .white : .black, dark: dark), "\(name): titles and icons are BasePrimary")
                let disabled = dark ? srgb(121 / 255, 120 / 255, 129 / 255) : srgb(171 / 255, 171 / 255, 171 / 255)
                check(same(colors.disabledTitle, disabled, dark: dark), "\(name): disabled titles are MenuDisabledText")
                check(same(colors.disabledSubtitle, disabled, dark: dark), "\(name): disabled shortcuts are MenuSubtitle, the same grey")
            }
        }
        check(!same(PArcMenuColors(theme: purple).background, ThemeChromePalette(theme: purple, isDark: true).backgroundExtra, dark: false),
              "a forced-dark theme still shows its light half in a light app")

        for dark in [false, true] {
            let colors = PArcMenuColors(theme: purple)
            let card = SidebarPlusMenuView(rows: titles, colors: colors) { _ in }
            let rep = render(card, dark: dark)
            let background = over(colors.background, resolved(colors.base, dark: dark).map { $0 }, dark: dark)
            let backdrop = background.map { $0 / 255 }
            let mode = dark ? "dark" : "light"
            check(near(pixel(rep, 100, 4), background), "\(mode): card background is backgroundExtra over the base")
            check(near(pixel(rep, 100, 96.5), over(colors.hover, backdrop, dark: dark)), "\(mode): first separator is hover")
            check(near(pixel(rep, 100, 193.5), over(colors.hover, backdrop, dark: dark)), "\(mode): second separator is hover")
            check(near(pixel(rep, 100, 95), background) && near(pixel(rep, 100, 98), background), "\(mode): separators are one point")
            let highlight = over(colors.hover, backdrop, dark: dark)
            check(near(pixel(rep, 120, 245), highlight), "\(mode): the highlighted New Tab row is hover")
            check(near(pixel(rep, 120, 205), background), "\(mode): other rows are not filled")
            let title = ink(rep, NSRect(x: 48, y: 8, width: 110, height: 40), background: background)
            check(near(title.color, resolved(colors.title, dark: dark).prefix(3).map { $0 * 255 }, 3), "\(mode): titles are BasePrimary")
            let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
            check(abs((title.maxX - title.minX) - inkWidth("New Space", [.font: titleFont])) <= 1, "\(mode): titles are 13-point medium")
            let shortcutBox = NSRect(x: 140, y: 105, width: 62, height: 40)
            let shortcut = ink(rep, shortcutBox, background: background)
            check(near(shortcut.color, over(colors.subtitle, backdrop, dark: dark), 3), "\(mode): shortcuts are subtitle")
            check(abs((shortcut.maxX - shortcut.minX) - inkWidth("⌃⇧E", [.font: NSFont.systemFont(ofSize: 13), .kern: 2])) <= 1,
                  "\(mode): shortcuts are 13-point regular, kerned 2 with no spaces")
            let tabShortcut = ink(rep, NSRect(x: 150, y: 242, width: 52, height: 40), background: highlight)
            check(near(tabShortcut.color, over(colors.subtitle, highlight.map { $0 / 255 }, dark: dark), 3),
                  "\(mode): the highlighted row keeps the subtitle shortcut colour")
            let disabledRows = SidebarPlusMenuModel.rows(privateBrowsing: true, canCreateEasel: false, canCreateNote: false,
                                                         canSplit: false) { $0 == "createEasel:" ? "⌃⇧E" : "" }
            let disabled = SidebarPlusMenuView(rows: disabledRows, colors: colors) { _ in }
            let disabledRep = render(disabled, dark: dark)
            check(near(ink(disabledRep, NSRect(x: 48, y: 8, width: 110, height: 40), background: background).color,
                       resolved(colors.disabledTitle, dark: dark).prefix(3).map { $0 * 255 }, 3), "\(mode): disabled titles are MenuDisabledText")
            check(near(ink(disabledRep, shortcutBox, background: background).color,
                       over(colors.disabledSubtitle, backdrop, dark: dark), 3), "\(mode): disabled shortcuts are MenuSubtitle")
            let chrome = SidebarPlusMenuChrome(card: SidebarPlusMenuView(rows: titles, colors: colors) { _ in }, tailX: 190)
            let chromeRep = render(chrome, dark: dark)
            check(near(pixel(chromeRep, 190, 296 - 4.5), background), "\(mode): the tail matches the card")
        }
        NSApp.appearance = nil
        let disabledNote = SidebarPlusMenuView(rows: privateRows, colors: neutral) { chosen = $0 }
        descendants(disabledNote).compactMap { $0 as? SidebarPlusRowButton }.first { $0.row.action == .note }!.performClick(nil)
        check(chosen == nil, "an unavailable New Note click does nothing")
        buttons.first { $0.row.action == .note }!.performClick(nil)
        check(chosen == .note, "New Note performs")
        buttons.last?.performClick(nil)
        check(chosen == .tab, "New Tab performs")
        let anchor = CGRect(x: 400, y: 80, width: 32, height: 32)
        let placed = SidebarPlusMenuPlacement.windowFrame(anchor: anchor, menu: view.menuSize, parentMinX: 0)
        check(placed.frame.maxX == anchor.maxX, "the card's trailing edge is flush with the + button")
        check(abs(placed.frame.minY - (anchor.maxY + 16 - 6)) < 0.01, "16 points between the card and the + button")
        check(abs(placed.tailX - (view.menuSize.width - 19.25)) < 0.01, "the tail center is 19.25 points from the card's trailing edge")
        let clamped = SidebarPlusMenuPlacement.windowFrame(anchor: CGRect(x: 0, y: 80, width: 1, height: 32),
                                                           menu: view.menuSize, parentMinX: 0)
        check(clamped.frame.minX == 0, "a clamped card begins at the parent edge")
        check(abs(clamped.tailX - (SidebarPlusMenuPlacement.cornerRadius + SidebarPlusMenuPlacement.tailBase / 2)) < 0.01,
              "the left tail clamp clears the 12-point card corner")
        let rightClamped = SidebarPlusMenuPlacement.windowFrame(anchor: CGRect(x: 400, y: 80, width: 1, height: 32),
                                                                menu: view.menuSize, parentMinX: 0)
        check(abs(rightClamped.tailX - (view.menuSize.width - SidebarPlusMenuPlacement.cornerRadius
                - SidebarPlusMenuPlacement.tailBase / 2)) < 0.01,
              "the right tail clamp clears the 12-point card corner")
        let menuWindow = SidebarPlusMenuWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        check(menuWindow.canBecomeKey && !menuWindow.canBecomeMain, "HUD window is key but not main")

        do {
            let (parent, anchor) = parentAndAnchor()
            let controller = SidebarPlusMenuController()
            controller.theme = purple
            controller.toggle(from: anchor, rows: titles) { _ in }
            guard let panel = parent.childWindows?.first as? SidebarPlusMenuWindow,
                  let chrome = panel.contentView as? SidebarPlusMenuChrome else {
                fatalError("SidebarPlusMenu: the themed HUD installs its child window")
            }
            check(panel.appearance == nil && chrome.card.appearance == nil && panel.appearanceSource === NSApp,
                  "the HUD window keeps AppKit's default appearance source, the app")
            for (app, expected) in [(NSAppearance.Name.aqua, NSAppearance.Name.aqua), (.darkAqua, .darkAqua)] {
                NSApp.appearance = NSAppearance(named: app)
                check(chrome.card.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected,
                      "over an ordinary window the HUD follows the app's \(app.rawValue)")
            }
            NSApp.appearance = nil
            for dark in [false, true] {
                check(same(chrome.colors.background, ThemeChromePalette(theme: purple, isDark: dark).backgroundExtra, dark: dark),
                      "the HUD opens in the window theme")
            }
            let rowButtons = descendants(chrome.card).compactMap { $0 as? SidebarPlusRowButton }
            panel.displayIfNeeded()
            DisplayRequests.install()
            controller.theme = purple
            check(DisplayRequests.marked.isEmpty, "an unchanged theme does not redraw the HUD")
            controller.theme = blue
            let marked = DisplayRequests.marked
            DisplayRequests.remove()
            for dark in [false, true] {
                let palette = ThemeChromePalette(theme: blue, isDark: dark)
                check(same(chrome.colors.background, palette.backgroundExtra, dark: dark)
                      && same(chrome.card.colors.hover, palette.hover, dark: dark)
                      && rowButtons.allSatisfy { same($0.colors.subtitle, palette.subtitle, dark: dark) },
                      "an open HUD recolours with the window theme")
            }
            check(([chrome, chrome.card] + rowButtons).allSatisfy { marked.contains(ObjectIdentifier($0)) },
                  "the recoloured HUD redraws its tail, card and every row")
            controller.dismiss()
            waitForClose(parent)
            parent.close()
        }

        do {
            NSApp.appearance = NSAppearance(named: .aqua)
            let (parent, anchor) = parentAndAnchor()
            parent.appearance = NSAppearance(named: .darkAqua)
            check(parent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua, "the private parent is Dark Aqua")
            let controller = SidebarPlusMenuController()
            controller.theme = purple
            controller.toggle(from: anchor, rows: titles) { _ in }
            guard let panel = parent.childWindows?.first as? SidebarPlusMenuWindow,
                  let chrome = panel.contentView as? SidebarPlusMenuChrome else {
                fatalError("SidebarPlusMenu: the private-window HUD installs its child window")
            }
            check(panel.appearanceSource === NSApp, "a private window's HUD keeps the app as its appearance source")
            check(chrome.card.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                  "a dark private window's HUD is light in a light app")
            let rep = capture(chrome.card)
            let colors = PArcMenuColors(theme: purple)
            check(near(pixel(rep, 100, 4), over(colors.background, resolved(colors.base, dark: false), dark: false)),
                  "a dark private window's HUD draws the theme's light half in a light app")
            controller.dismiss()
            waitForClose(parent)
            parent.close()
            NSApp.appearance = nil
        }

        var blockedAction: SidebarPlusAction?
        let closingView = SidebarPlusMenuView(rows: titles, colors: neutral) { blockedAction = $0 }
        closingView.acceptsActions = false
        let closingButtons = descendants(closingView).compactMap { $0 as? SidebarPlusRowButton }
        closingButtons.last?.performClick(nil)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: 53)!
        closingView.keyDown(with: escape)
        check(blockedAction == nil, "rows and Escape do nothing while closing")

        for closePath in ["dismiss", "toggle", "escape", "row", "outside-click", "parent-close"] {
            let (parent, anchor) = parentAndAnchor()
            let controller = SidebarPlusMenuController()
            var transitions: [Bool] = []
            controller.onVisibilityChange = { transitions.append($0) }
            controller.toggle(from: anchor, rows: titles) { _ in }
            check(SidebarPlusMenuController.isShown(in: parent), "\(closePath) opens the HUD")
            guard let panel = parent.childWindows?.first as? SidebarPlusMenuWindow,
                  let chrome = panel.contentView as? SidebarPlusMenuChrome else {
                fatalError("SidebarPlusMenu: \(closePath) installs the HUD child window")
            }
            check(panel.accessibilityLabel() == "New Tab, Folder, or Space", "\(closePath) HUD accessibility label")
            switch closePath {
            case "dismiss":
                controller.dismiss()
            case "toggle":
                controller.toggle(from: anchor, rows: titles) { _ in }
            case "escape":
                chrome.card.keyDown(with: escape)
            case "row":
                descendants(chrome.card).compactMap { $0 as? SidebarPlusRowButton }.last?.performClick(nil)
            case "outside-click":
                panel.resignKey()
            default:
                parent.close()
            }
            check(chrome.card.acceptsActions == false, "\(closePath) disables menu actions at close start")
            check(panel.ignoresMouseEvents == true, "\(closePath) blocks HUD input at close start")
            waitForClose(parent)
            check(!SidebarPlusMenuController.isShown(in: parent), "\(closePath) clears HUD ownership")
            check(transitions == [true, false], "\(closePath) fires visibility exactly once per transition")
            if closePath != "parent-close" { parent.close() }
        }

        let keyParent = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 400, height: 500),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        keyParent.isReleasedWhenClosed = false
        let keyAnchor = NSView(frame: NSRect(x: 300, y: 10, width: 32, height: 32))
        keyParent.contentView?.addSubview(keyAnchor)
        keyParent.orderFront(nil)
        check(keyParent.canBecomeKey, "the titled parent can become key")
        let keyController = SidebarPlusMenuController()
        var shownDuringResign: Bool?
        let resign = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: keyParent, queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                shownDuringResign = SidebarPlusMenuController.isShown(in: keyParent)
            }
        }
        ParentResignOnHUDKey.install()
        keyController.toggle(from: keyAnchor, rows: titles) { _ in }
        ParentResignOnHUDKey.remove()
        NotificationCenter.default.removeObserver(resign)
        check(shownDuringResign == true, "the HUD is registered before the parent resigns key")
        keyController.dismiss()
        waitForClose(keyParent)
        keyParent.close()
        let summary = "Sidebar plus menu checks passed (\(count))"
        print(summary)
    }
}
