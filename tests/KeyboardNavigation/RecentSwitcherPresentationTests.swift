import AppKit

@main struct RecentSwitcherPresentationTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func settle(_ interval: TimeInterval = 0.15) {
            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }
        let parent = NSRect(x: 50, y: 70, width: 1200, height: 800)
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let frame = RecentTabSwitcherView.panelFrame(itemCount: 5, parent: parent, screen: screen)
        let metrics = RecentTabSwitcherView.Metrics.self
        check(abs(metrics.cardWidth - 181.7) < 0.0001, "original 158-height card at 1.15 aspect")
        check(frame.height == 478, "190-point content plus original shadow padding")
        check(abs(frame.width - 1228.5) < 0.0001, "five original cards and padding")
        check(frame.minX + 144 + 940.5 / 2 == parent.midX, "shadow does not recenter actual content")
        check(frame.minY + 168 + 95 == parent.midY, "same original parent content center")
        let narrow = RecentTabSwitcherView.panelFrame(itemCount: 5, parent: NSRect(x: 0, y: 0, width: 600, height: 700), screen: screen)
        check(narrow.width - 288 == 520, "narrow original parent uses horizontal scrolling")
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isRestorable = false
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        let view = RecentTabSwitcherView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = view
        var allowed = true, chosen: [Int] = [], hovered: [Int] = [], changes = 0
        view.canInteract = { allowed }
        view.onChoose = { chosen.append($0) }; view.onHover = { hovered.append($0) }
        view.onVisibleItemsChanged = { changes += 1 }
        let ids = (0..<5).map { _ in UUID() }
        let items = ids.enumerated().map { index, id in
            RecentTabSwitcherView.Item(id: id.uuidString, title: ["Sunset", "A long page title that truncates", "Documents", "Research", "Reference"][index],
                spaceName: "Space 1", vertical: false,
                components: [.init(id: id, title: "Page \(index + 1)", image: nil)])
        }
        view.configure(isDark: false, focus: .systemPurple, hover: .systemGray, maxContrast: .black, cutout: .white)
        view.setItems(items, focused: 1)
        window.orderFront(nil); view.layoutSubtreeIfNeeded(); settle(0.3)
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let material = all(view).compactMap { $0 as? NSVisualEffectView }.first
        check(material != nil, "actual native material renderer exists")
        check(material?.material == .popover, "actual material 6 is popover")
        check(material?.state == .followsWindowActiveState, "original material state")
        check(material?.blendingMode == .withinWindow && material?.isEmphasized == false, "original native configuration")
        check(!view.acceptsFirstResponder, "presentation cannot take parent keyboard focus")
        check(view.contentRect.minX == 144 && view.contentRect.minY == 120 && view.contentRect.height == 190 && view.contentRect.width == window.frame.width - 288 && abs(view.contentRect.width - 940.5) <= 2, "original content and shadow relation after AppKit pixel rounding")
        check(view.focusedID == items[1].id, "same original focus")
        check(view.itemFrames.count == 5, "five original native-rendered cards")
        let card = view.itemFrames[items[0].id]!
        check(abs(card.width - 181.7) < 0.01 && abs(card.height - 158) < 0.01, "actual hosted card dimensions")
        check(abs(card.minX - 16) < 0.01 && abs(card.minY - 16) < 0.01, "actual sixteen-point row padding")
        check(view.visibleItemIndexes == Set(0..<5) && changes > 0, "actual viewport supplies native preview visibility")
        let publishedFrames = view.itemFrames
        let publishedVisible = view.visibleItemIndexes
        let publishedChanges = changes
        view.configure(isDark: false, focus: .systemPurple, hover: .systemGray, maxContrast: .black, cutout: .white)
        view.setItems(items, focused: 1)
        view.focus(1)
        settle(0.05)
        check(view.itemFrames == publishedFrames && view.visibleItemIndexes == publishedVisible && changes == publishedChanges,
              "identical items, colors and focus skip frame and visibility republish")
        view.focus(3)
        settle()
        check(view.focusedID == items[3].id, "focus-only step still moves preview focus")
        check(view.itemFrames == publishedFrames && view.visibleItemIndexes == publishedVisible && changes == publishedChanges,
              "focus-only step keeps the same card frames and visibility")
        view.focus(1)
        settle()
        check(view.focusedID == items[1].id, "restored original focus after the skip path")
        check(all(view).compactMap { $0 as? NSScrollView }.allSatisfy { !$0.hasHorizontalScroller }, "no added horizontal scrollbar")
        view.hover(items[2].id); view.choose(items[2].id)
        check(hovered == [2] && chosen == [2], "exact original ID maps to current item")
        view.choose("retired"); check(chosen == [2], "retired item cannot dispatch")
        allowed = false; view.choose(items[0].id); view.hover(items[0].id)
        check(chosen == [2] && hovered == [2], "original owner refusal retains input boundary")
        allowed = true
        let responder = window.firstResponder
        view.focus(4); settle()
        check(view.focusedID == items[4].id && window.firstResponder === responder, "preview focus does not replace native responder")
        view.setItems([items[3], items[1]], focused: 1); settle()
        view.choose(items[3].id)
        check(chosen == [2, 0], "reordered original ID does not retain old index")
        view.choose(items[4].id); check(chosen == [2, 0], "removed item callback refuses")
        view.isHidden = true; view.choose(items[1].id)
        check(chosen == [2, 0], "hidden view refuses input")
        view.isHidden = false
        view.setItems(items, focused: 1); settle()
        if CommandLine.arguments.contains("--appearance") {
            func picture(_ color: NSColor) -> NSImage {
                NSImage(size: NSSize(width: 480, height: 300), flipped: false) { rect in
                    color.setFill(); rect.fill()
                    NSColor.white.withAlphaComponent(0.8).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 24, y: 230, width: 432, height: 36), xRadius: 6, yRadius: 6).fill()
                    NSColor.white.withAlphaComponent(0.45).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 24, y: 30, width: 220, height: 175), xRadius: 6, yRadius: 6).fill()
                    return true
                }
            }
            let colors: [NSColor] = [.systemOrange, .systemBlue, .systemPurple, .systemGreen, .systemPink]
            var illustrated = items
            for index in illustrated.indices { illustrated[index].components[0].image = picture(colors[index]) }
            illustrated[2].components.append(.init(id: UUID(), title: "Second pane", image: picture(.systemTeal)))
            view.setItems(illustrated, focused: 1)
            view.configure(isDark: false, focus: NSColor(red: 0.6, green: 0.65, blue: 0.8, alpha: 1), hover: .gray, maxContrast: .black, cutout: .white)
            app.activate(ignoringOtherApps: true); window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) { window.close(); app.terminate(nil) }
            print("\(checks) MRU presentation assertions passed; inert appearance window only")
            app.run(); return
        }
        // A sixth original item occupies the reserve slot but owns no input,
        // accessibility action, focus or thumbnail visibility until promotion.
        let reserveID = UUID()
        var reserve = RecentTabSwitcherView.Item(id: reserveID.uuidString, title: "Reserve",
            spaceName: "Space 1", vertical: false,
            components: [.init(id: reserveID, title: "Reserve")], isHidden: true)
        view.setItems(items + [reserve], focused: 1); settle()
        check(view.itemFrames.count == 6, "hidden reserve remains in the real row")
        check(view.visibleItemIndexes == Set(0..<5), "reserve never enters preview visibility")
        let previousChosen = chosen, previousHovered = hovered
        view.choose(reserve.id); view.hover(reserve.id); view.focus(5)
        check(chosen == previousChosen && hovered == previousHovered && view.focusedID == nil,
              "reserve refuses choose, hover and focus")
        reserve.isHidden = false
        let promoted = Array(items.dropFirst()) + [reserve]
        view.setItems(promoted, focused: 4); settle(0.3)
        check(view.itemFrames.count == 5 && view.focusedID == reserve.id,
              "confirmed removal promotes the same reserve identity")
        check(view.visibleItemIndexes == Set(0..<5), "promoted reserve joins preview visibility")
        view.choose(reserve.id)
        check(chosen == previousChosen + [4], "promoted reserve dispatches its current position")

        // Render the actual production variants with inert local content.
        check(RecentSwitcherArtwork.directory == Bundle.main.resourceURL?.appendingPathComponent("RecentSwitcher", isDirectory: true),
              "the artwork loads from the bundle's RecentSwitcher resources")
        check(RecentSwitcherArtwork.note != nil && RecentSwitcherArtwork.easel != nil
            && RecentSwitcherArtwork.incognito != nil, "all copied native PDF templates decode")
        func swatch(_ color: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 240, height: 180), flipped: false) { rect in
                color.setFill(); rect.fill(); return true
            }
        }
        var variants = items
        variants[0].components[0].template = .init(image: RecentSwitcherArtwork.note!, title: "A two-line note title")
        variants[1].components[0].image = swatch(.systemBlue)
        variants[1].components.append(.init(id: UUID(), title: "Second pane", image: swatch(.systemTeal)))
        variants[1].customInfo = .init(icon: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), title: "Named split")
        variants[2].components.append(.init(id: UUID(), title: "Empty second pane"))
        variants[2].customInfo = .init(icon: nil, title: "Counted split")
        variants[3].components[0].image = swatch(.systemOrange)
        variants[3].overlay = .init(id: UUID(), title: "Original Peek", image: swatch(.systemPurple))
        variants[4].components[0].template = .init(image: RecentSwitcherArtwork.incognito!, title: nil)
        variants[4].components[0].isRecordingMedia = true
        view.setItems(variants, focused: 1); settle(0.3)
        check(view.itemFrames.values.allSatisfy { abs($0.width - metrics.cardWidth) < 0.01
            && abs($0.height - metrics.cardHeight) < 0.01 }, "all production variants retain the recovered card geometry")
        if let directory = ProcessInfo.processInfo.environment["PARC_SWITCHER_CAPTURE_DIRECTORY"] {
            func capture(_ name: String) {
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("capture") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
                try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
            }
            capture("variants-light")
            view.configure(isDark: true, focus: .gray, hover: .darkGray, maxContrast: .white, cutout: .black)
            window.appearance = NSAppearance(named: .darkAqua); settle(0.3)
            capture("variants-dark")
        }
        view.setItems(items, focused: 1); settle()
        chosen = [2, 0]
        view.retire(); view.choose(items[0].id); view.focus(0)
        check(chosen == [2, 0] && view.focusedID == items[1].id, "retirement revokes both callbacks and presentation mutation")
        check(view.canInteract == nil && view.onChoose == nil, "retired closures released")
        window.close(); settle()
        let coldWindow = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        coldWindow.isReleasedWhenClosed = false; coldWindow.isRestorable = false
        let cold = RecentTabSwitcherView(frame: .zero)
        coldWindow.contentView = cold
        cold.configure(isDark: true, focus: .gray, hover: .darkGray, maxContrast: .white, cutout: .black)
        cold.setItems(items, focused: 1)
        coldWindow.setFrame(frame, display: true); coldWindow.orderFront(nil); settle(0.3)
        check(cold.bounds.size == coldWindow.contentView!.bounds.size && cold.contentRect.height == 190,
              "actual zero-size controller construction adopts original panel bounds")
        check(cold.itemFrames.count == 5 && cold.visibleItemIndexes == Set(0..<5),
              "deferred initial host publishes actual cards after original show")
        cold.retire(); coldWindow.close(); settle()
        print("\(checks) MRU presentation assertions passed")
    }
}
