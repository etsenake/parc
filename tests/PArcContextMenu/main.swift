import AppKit
import SwiftUI

/// Records what the menu does, in order, as the engine's target and delegate see it.
final class Recorder: NSObject, NSMenuDelegate {
    var log: [String] = []
    @objc func record(_ sender: NSMenuItem) { log.append("perform " + sender.title) }
    func menuWillOpen(_ menu: NSMenu) { log.append("open " + menu.title) }
    func menuDidClose(_ menu: NSMenu) { log.append("close " + menu.title) }
}

@main
struct PArcContextMenuChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            precondition(condition(), message)
        }
        let recorder = Recorder()
        func item(_ title: String, state: NSControl.StateValue = .off, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(Recorder.record(_:)), keyEquivalent: "")
            item.target = recorder; item.state = state; item.isEnabled = enabled
            return item
        }
        /// The engine's extension menu, in Chromium's title-case strings.
        func extensionMenu() -> NSMenu {
            let access = NSMenu(title: "access")
            access.autoenablesItems = false
            for (title, state) in [("Ask on Every Visit", NSControl.StateValue.off), ("Always on example.com", .on),
                                   ("Always on All Sites", .off)] { access.addItem(item(title, state: state)) }
            let menu = NSMenu(title: "root")
            menu.autoenablesItems = false
            menu.delegate = recorder
            menu.addItem(item("uBlock Origin Lite"))
            menu.addItem(.separator())
            let site = NSMenuItem(title: "This Can Read and Change Site Data", action: nil, keyEquivalent: "")
            site.submenu = access
            menu.addItem(site)
            menu.addItem(.separator())
            for title in ["Options", "Remove from Parc…", "Unpin"] { menu.addItem(item(title)) }
            menu.addItem(item("Open Side Panel", enabled: false))
            menu.items.last?.toolTip = "Extension side panels are currently unavailable."
            menu.addItem(.separator())
            for title in ["Manage Extension", "View Web Permissions"] { menu.addItem(item(title)) }
            return menu
        }

        // Placement: the first row level with the anchor, to its right, or
        // to its left where the screen ends, and moved onto the screen.
        let m = PArcContextMenuMetrics.self
        let tile = NSRect(x: 100, y: 500, width: 48, height: 32)
        let size = NSSize(width: 200, height: 300)
        let right = m.frame(card: size, beside: tile, right: true, screen: NSRect(x: 0, y: 0, width: 1000, height: 800))
        expect(right.right && right.frame.minX == tile.maxX + m.gap && right.frame.maxY == tile.maxY + m.inset,
               "the card hangs to the right of the tile, its first row level with it")
        let edge = m.frame(card: size, beside: NSRect(x: 850, y: 500, width: 48, height: 32), right: true,
                           screen: NSRect(x: 0, y: 0, width: 1000, height: 800))
        expect(!edge.right && edge.frame.maxX == 850 - m.gap, "without room on the right it hangs to the left")
        let low = m.frame(card: size, beside: NSRect(x: 100, y: 40, width: 48, height: 32), right: true,
                          screen: NSRect(x: 0, y: 20, width: 1000, height: 800))
        expect(low.frame.minY == 20, "near the bottom of the screen it moves up onto it")
        expect(m.frame(card: size, beside: tile, right: false, screen: nil).frame.maxX == tile.minX - m.gap,
               "a submenu keeps its parent's side")

        // Rows: hidden items and stray separators drop; 32-point rows, 17-point dividers.
        let menu = extensionMenu()
        menu.items[0].isHidden = true
        let shown = m.shownItems(menu)
        expect(shown.first?.title == "This Can Read and Change Site Data" && !shown.contains { $0.isHidden },
               "a hidden first item takes its separator with it")
        menu.items[0].isHidden = false
        let view = PArcContextMenuView(menu: menu, colors: PArcMenuColors(theme: SpaceTheme()))
        let rows = view.items.indices.filter { !view.items[$0].isSeparatorItem }
        expect(rows.allSatisfy { view.rows[$0].height == m.rowHeight } &&
               view.items.indices.filter { view.items[$0].isSeparatorItem }.allSatisfy { view.rows[$0].height == SidebarPlusMenuView.divider },
               "rows are 32 points and separators the dock + menu's 17")
        expect(view.rows[0].maxY == view.card.maxY - m.inset && view.rows[0].minX == view.card.minX + m.inset,
               "rows sit inside the card's 8-point inset, from the top")
        expect(view.card.width >= m.minimumWidth && view.card.width <= m.maximumWidth, "the card fits its titles within bounds")
        expect(view.row(at: NSPoint(x: view.rows[1].midX, y: view.rows[1].midY)) == nil, "a separator is not a row")
        expect(view.accessibilityChildren()?.count == rows.count, "VoiceOver sees each row as a menu item")

        // The loop, driven by posted events over an off-screen parent.
        let parent = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: 600, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderFront(nil)
        let anchor = parent.convertToScreen(NSRect(x: 40, y: 600, width: 48, height: 32))
        let colors = PArcMenuColors(theme: SpaceTheme())
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func mouse(_ type: NSEvent.EventType, _ screen: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: parent.convertPoint(fromScreen: screen), modifierFlags: [], timestamp: 0,
                               windowNumber: parent.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        /// Presents `menu` with `events` queued, then returns the log.
        func run(_ menu: NSMenu, _ events: [NSEvent], during: ((PArcContextMenu) -> Void)? = nil) -> [String] {
            recorder.log.removeAll()
            let presenter = PArcContextMenu(anchor: anchor, parent: parent, colors: colors)
            events.forEach { NSApp.postEvent($0, atStart: false) }
            during?(presenter)
            expect(presenter.present(menu), "the menu shows")
            settle()
            expect(parent.childWindows?.isEmpty ?? true, "its cards are gone once it returns")
            return recorder.log
        }
        func screenRow(_ view: PArcContextMenuView, _ row: Int, beside: NSRect) -> NSPoint {
            let frame = m.frame(card: view.card.size, beside: beside, right: true, screen: nil).frame
            return NSPoint(x: frame.minX - m.shadowMargin + view.rows[row].midX, y: frame.minY - m.shadowMargin + view.rows[row].midY)
        }

        var keyed = extensionMenu()
        keyed.items[2].submenu?.delegate = recorder
        expect(run(keyed, [key(125), key(125), key(124), key(125), key(36)]) ==
               ["open root", "open access", "close access", "close root", "perform Always on example.com"],
               "arrows walk the rows into the submenu, Return chooses, and the item runs after the menu has closed")
        expect(run(extensionMenu(), [key(126), key(126), key(126), key(36)]) == ["open root", "close root", "perform Unpin"],
               "Up from nothing starts at the last row and skips the separator and the disabled row")
        expect(run(extensionMenu(), [key(53)]) == ["open root", "close root"], "Escape closes without choosing")
        expect(run(extensionMenu(), [mouse(.leftMouseDown, NSPoint(x: anchor.minX - 200, y: anchor.minY))]) ==
               ["open root", "close root"], "a press outside the card closes it without choosing")
        expect(run(extensionMenu(), [], during: { presenter in
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in MainActor.assumeIsolated { presenter.cancel() } }
            RunLoop.main.add(timer, forMode: .common)
        }) == ["open root", "close root"], "the engine's cancel ends the menu from between events")

        keyed = extensionMenu()
        let sample = PArcContextMenuView(menu: keyed, colors: colors)
        let options = screenRow(sample, 4, beside: anchor)
        expect(run(keyed, [mouse(.mouseMoved, options), mouse(.leftMouseUp, options)]) == ["open root", "close root", "perform Options"],
               "releasing over a row chooses it")
        let disabled = screenRow(sample, 7, beside: anchor)
        expect(run(extensionMenu(), [mouse(.leftMouseUp, disabled), key(53)]) == ["open root", "close root"],
               "a disabled row does nothing")
        let siteRow = screenRow(sample, 2, beside: anchor)
        let rootFrame = m.frame(card: sample.card.size, beside: anchor, right: true, screen: nil).frame
        let siteRect = sample.submenuAnchor(2).offsetBy(dx: rootFrame.minX - m.shadowMargin, dy: rootFrame.minY - m.shadowMargin)
        let access = PArcContextMenuView(menu: keyed.items[2].submenu!, colors: colors)
        let allSites = screenRow(access, 2, beside: siteRect)
        expect(run(extensionMenu(), [mouse(.rightMouseDragged, siteRow), mouse(.rightMouseDragged, allSites),
                                      mouse(.rightMouseUp, allSites)]) == ["open root", "close root", "perform Always on All Sites"],
               "dragging from the tile into the submenu and releasing chooses there")

        // NSMenu's submenu aim: a diagonal path through the next row keeps the
        // submenu; a straight move or a pause on that row switches.
        let aim = NSPoint(x: rootFrame.maxX - m.inset - 2, y: options.y)
        expect(run(extensionMenu(), [mouse(.mouseMoved, siteRow), mouse(.mouseMoved, aim), mouse(.mouseMoved, allSites),
                                      mouse(.leftMouseUp, allSites)]) == ["open root", "close root", "perform Always on All Sites"],
               "heading into the submenu across the next row keeps it open")
        expect(run(extensionMenu(), [mouse(.mouseMoved, siteRow), mouse(.mouseMoved, options), mouse(.leftMouseUp, options)]) ==
               ["open root", "close root", "perform Options"], "moving straight to another row closes the submenu at once")
        expect(run(extensionMenu(), [mouse(.mouseMoved, siteRow), mouse(.mouseMoved, aim)], during: { _ in
            let timer = Timer(timeInterval: m.submenuAimDelay * 2, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.postEvent(mouse(.leftMouseUp, aim), atStart: false) }
            }
            RunLoop.main.add(timer, forMode: .common)
        }) == ["open root", "close root", "perform Options"], "pausing on the next row switches to it")

        // Keys stay with the lit row under a submenu the pointer opened.
        expect(run(extensionMenu(), [mouse(.mouseMoved, siteRow), key(125), key(36)]) == ["open root", "close root", "perform Options"],
               "Down moves in the parent and closes the hovered submenu")
        expect(run(extensionMenu(), [mouse(.mouseMoved, siteRow), key(124), key(36)]) ==
               ["open root", "close root", "perform Ask on Every Visit"], "Right goes into the hovered submenu")

        // VoiceOver's press chooses between events.
        expect(run(extensionMenu(), [], during: { _ in
            let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let card = parent.childWindows?.first?.contentView as? PArcContextMenuView
                    let element = card?.accessibilityChildren()?.lazy.compactMap { $0 as? NSAccessibilityElement }
                        .first { $0.accessibilityLabel() == "Options" }
                    _ = element?.accessibilityPerformPress()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }) == ["open root", "close root", "perform Options"], "a VoiceOver press on a row chooses it at once")

        parent.orderOut(nil)
        expect(!PArcContextMenu(anchor: anchor, parent: parent, colors: colors).present(extensionMenu()),
               "a hidden parent shows nothing")

        if CommandLine.arguments.count > 1 {
            render(to: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true), menu: extensionMenu)
        }
        print("PASS: \(assertions) extension context menu assertions")
    }

    /// The Site Control Center hanging from its button with the second
    /// tile's menu open beside it and that menu's site-access submenu open.
    @MainActor static func render(to output: URL, menu: () -> NSMenu) {
        let purple = SpaceTheme(primaryColor: ThemeColor(hex: "3D2468"), colorCount: 1, appearance: .dark, noise: 0.3)
        let blue = SpaceTheme(primaryColor: ThemeColor(hex: "3F9BD6"), colorCount: 2, noise: 0.3)
        for (name, theme, appearanceName, page) in [("light", blue, NSAppearance.Name.aqua, NSColor(white: 0.95, alpha: 1)),
                                                     ("dark", purple, .darkAqua, NSColor(white: 0.12, alpha: 1))] {
            let appearance = NSAppearance(named: appearanceName)
            let colors = SiteControlCenterColors(theme: theme)
            let sample = SiteControlCenterModel()
            sample.colors = colors
            sample.canCopy = true; sample.canShare = true; sample.captureAvailable = true; sample.canCapture = true
            sample.extensions = ["a", "b", "c"].map {
                .init(id: $0, name: "Extension " + $0, tooltip: "", accessibilityLabel: "", icon: nil,
                      isPinned: $0 == "a", canChangePin: true)
            }
            sample.settings = [
                .init(id: "preview", symbol: "filemenu.and.cursorarrow", symbolSize: 14, symbolWeight: .bold, title: "Preview",
                      subtitle: "Enabled", isOn: true, isEnabled: true),
                .init(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium, title: "Developer Mode",
                      subtitle: "Off", isOn: false, isEnabled: true)]
            sample.isSecure = true
            sample.menuExtension = "b"
            let host = NSHostingView(rootView: SiteControlCenterView(model: sample))
            let size = NSSize(width: SiteControlCenterMetrics.width,
                              height: ceil(host.fittingSize.height))
            host.frame.size = size
            let card = SiteControlCenterCard(content: host, colors: colors.menu)
            let chrome = PArcMenuChrome(content: card, size: size, colors: colors.menu, tailX: size.width - 28, tailOnTop: true)
            let window = NSWindow(contentRect: NSRect(x: -12_000, y: -12_000, width: chrome.frame.width, height: chrome.frame.height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = chrome
            chrome.layoutSubtreeIfNeeded()
            host.layoutSubtreeIfNeeded()
            guard let tile = find(SiteControlCenterAlternateClick.identifier("b"), in: host) else { fatalError("no tile b") }
            let margin: CGFloat = 24
            let origin = NSPoint(x: margin, y: margin + 140)
            let tileRect = tile.convert(tile.bounds, to: chrome).offsetBy(dx: origin.x, dy: origin.y)
            // As SiteControlCenterController.presentExtensionMenu anchors it: the card's width, the tile's height.
            let cardRect = card.convert(card.bounds, to: chrome).offsetBy(dx: origin.x, dy: origin.y)
            let anchorRow = NSRect(x: cardRect.minX, y: tileRect.minY, width: cardRect.width, height: tileRect.height)
            let root = PArcContextMenuView(menu: menu(), colors: colors.menu)
            let rootFrame = PArcContextMenuMetrics.frame(card: root.card.size, beside: anchorRow, right: true, screen: nil).frame
            root.frame.origin = NSPoint(x: rootFrame.minX - PArcContextMenuMetrics.shadowMargin, y: rootFrame.minY - PArcContextMenuMetrics.shadowMargin)
            root.highlighted = 2
            let siteRow = root.submenuAnchor(2).offsetBy(dx: root.frame.minX, dy: root.frame.minY)
            let sub = PArcContextMenuView(menu: root.items[2].submenu!, colors: colors.menu)
            let subFrame = PArcContextMenuMetrics.frame(card: sub.card.size, beside: siteRow, right: true, screen: nil).frame
            sub.frame.origin = NSPoint(x: subFrame.minX - PArcContextMenuMetrics.shadowMargin, y: subFrame.minY - PArcContextMenuMetrics.shadowMargin)
            sub.highlighted = 2
            let chromeFrame = NSRect(origin: origin, size: chrome.frame.size)
            let bounds = chromeFrame.union(root.frame).union(sub.frame).insetBy(dx: -margin, dy: -margin)
            let canvas = NSSize(width: ceil(bounds.maxX), height: ceil(max(bounds.maxY, chromeFrame.maxY + margin)))
            let rep = bitmap(canvas)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            page.setFill(); NSRect(origin: .zero, size: canvas).fill()
            // AppKit masks the card's layer to its corners; this draw path does not, so clip as it does.
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: NSRect(origin: origin, size: size), xRadius: 12, yRadius: 12)
            clip.append(NSBezierPath(rect: NSRect(x: origin.x, y: origin.y + size.height, width: size.width,
                                                  height: SidebarPlusMenuPlacement.tailHeight)))
            clip.addClip()
            snapshot(chrome).draw(in: chromeFrame)
            NSGraphicsContext.restoreGraphicsState()
            for view in [root, sub] {
                view.appearance = appearance
                snapshot(view).draw(in: view.frame)
            }
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("extension-menu-\(name).png"))
        }
    }

    static func bitmap(_ size: NSSize) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        return rep
    }

    @MainActor static func snapshot(_ view: NSView) -> NSImage {
        let rep = bitmap(view.bounds.size)
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    @MainActor static func find(_ identifier: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
        if view.identifier == identifier { return view }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }
}
