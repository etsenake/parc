import AppKit

@main @MainActor struct SplitPaneMenuTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1; precondition(value(), message)
    }
    static func main() throws {
        _ = NSApplication.shared
        var performed: [SplitPaneOperation] = []
        var available = true
        let menu = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: 2) { operation in
            { if available { performed.append(operation) } }
        }
        check(!menu.autoenablesItems && menu.title == "Split View Controls Menu", "Actual native menu owns explicit availability")
        check(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Move Left", "Move Right", "Add Right Split", "Add Left Split", "Separate Tab from Split", "Convert to Vertical Split View", "Copy Links"], "Split menu matches the installed pane control list")
        check(menu.items.first?.isEnabled == false && menu.items[1].isEnabled, "Boundary move is disabled in real NSMenu")
        check(menu.items.filter(\.isSeparatorItem).count == 3, "Menu sections remain native separators")
        let move = menu.items[1]
        check(move.target != nil && move.representedObject != nil && move.action != nil, "Native item retains its exact action owner")
        _ = NSApp.sendAction(move.action!, to: move.target, from: move)
        check(performed == [.moveNext], "Native menu dispatch preserves exact operation")
        available = false
        _ = NSApp.sendAction(move.action!, to: move.target, from: move)
        check(performed == [.moveNext], "Original owner can reject action after menu preparation")
        let full = SplitPaneMenu.make(orientation: .vertical, index: 3, count: 4) { operation in { performed.append(operation) } }
        check(full.items.filter { $0.title.hasPrefix("Add ") }.allSatisfy { !$0.isEnabled }, "Four-pane menu has no fifth-pane action")
        check(full.items[0].title == "Move Up" && full.items[0].isEnabled && !full.items[1].isEnabled, "Vertical last-pane neighbor availability")
        check(full.items[7].title == "Convert to Horizontal Split View" && full.items.last?.title == "Copy Links", "Convert sits above Copy Links")
        let copyLinks = menu.items.last!
        _ = NSApp.sendAction(copyLinks.action!, to: copyLinks.target, from: copyLinks)
        check(copyLinks.isEnabled && performed == [.moveNext], "Copy Links follows the owner's live refusal like every other row")
        available = true
        _ = NSApp.sendAction(copyLinks.action!, to: copyLinks.target, from: copyLinks)
        check(performed == [.moveNext, .copyLinks], "Copy Links dispatches the split's copy operation")
        let linkless = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: 2) { operation in
            operation == .copyLinks ? nil : { performed.append(operation) }
        }
        check(linkless.items.last?.title == "Copy Links" && linkless.items.last?.isEnabled == false && linkless.items[1].isEnabled,
              "With no web page to copy, only Copy Links is disabled")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("parc-split-links-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let links = [FolderLinks.Link(tabID: UUID(), title: "Fish & <Chips>", url: "https://one.invalid/a?b=1&c=2"),
                     FolderLinks.Link(tabID: UUID(), title: "", url: "https://two.invalid/")]
        check(LinkPasteboard.write(links, format: .plain, to: pasteboard), "Copy Links writes the pasteboard")
        check(pasteboard.string(forType: .string) == "https://one.invalid/a?b=1&c=2\nhttps://two.invalid/",
              "Plain-text targets get one bare address per line, in order")
        check(pasteboard.string(forType: .html) == "<meta charset=\"utf-8\"><a href=\"https://one.invalid/a?b=1&amp;c=2\">Fish &amp; &lt;Chips&gt;</a><br>\n"
              + "<a href=\"https://two.invalid/\">https://two.invalid/</a>", "Rich-text targets get each title linked to its address")
        check(LinkPasteboard.write(links, format: .markdown, to: pasteboard) && pasteboard.types?.contains(.html) == false
              && pasteboard.string(forType: .string)?.hasPrefix("[Fish & \\<Chips>](<https://one.invalid/a?b=1&c=2>)") == true,
              "Markdown copies stay Markdown only")
        let unchangedCount = pasteboard.changeCount
        check(!LinkPasteboard.write([], format: .plain, to: pasteboard) && pasteboard.changeCount == unchangedCount,
              "Nothing to copy leaves the pasteboard alone")
        let single = SplitPaneMenu.make(orientation: .vertical, index: 0, count: 1) { operation in
            { performed.append(operation) }
        }
        check(single.items.map(\.title) == ["Add Left Split", "Add Right Split", "", "Add Top Split", "Add Bottom Split"], "A sole pane exposes both original orientation sections")
        check(single.items.filter { !$0.isSeparatorItem }.allSatisfy(\.isEnabled), "All four sole-pane directions use genuine admitted actions")
        for item in single.items where !item.isSeparatorItem { _ = NSApp.sendAction(item.action!, to: item.target, from: item) }
        check(Array(performed.suffix(4)) == [.addBefore, .addAfter, .addAbove, .addBelow], "Single-pane native rows dispatch exact before/after/orientation identities")
        for invalidCount in [0, 5] {
            let invalid = SplitPaneMenu.make(orientation: .horizontal, index: 0, count: invalidCount) { _ in { preconditionFailure("Invalid menu dispatched") } }
            check(invalid.items.isEmpty, "No menu materializes outside original content bounds")
        }
        let refused = SplitPaneMenu.make(orientation: .horizontal, index: 1, count: 3) { _ in nil }
        check(refused.items.allSatisfy { $0.isSeparatorItem || !$0.isEnabled }, "A refused native owner cannot leave any enabled action")
        func pixels(_ image: NSImage, _ appearance: NSAppearance.Name) -> Data {
            let size = image.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance { image.draw(in: NSRect(origin: .zero, size: size)) }
            NSGraphicsContext.restoreGraphicsState()
            return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        func rendition(_ file: String) -> NSImage {
            NSImage(contentsOf: SplitPaneMenuArtwork.directory!.appendingPathComponent(file + "@2x.png"))!
        }
        func shows(_ menu: NSMenu, _ artwork: [String?]) -> Bool {
            menu.items.count == artwork.count && zip(menu.items, artwork).allSatisfy { item, name in
                guard let name else { return item.isSeparatorItem }
                guard let image = item.image else { return false }
                if #available(macOS 27, *), item.preferredImageVisibility != .visible { return false }
                let light = rendition(name), dark = rendition(name + "-dark")
                return image.size == light.size && pixels(image, .aqua) == pixels(light, .aqua)
                    && pixels(image, .darkAqua) == pixels(dark, .darkAqua) && pixels(image, .aqua) != pixels(image, .darkAqua)
            }
        }
        check(shows(menu, ["icon-split-move-left", "icon-split-move-right", nil, "icon-split-add-right", "icon-split-add-left", nil,
                           "icon-separate-from-split", "icon-split-vertical", nil, "icon-split-copy-links-horizontal"]),
              "A horizontal split's items show their artwork, light or dark by appearance")
        check(shows(full, ["icon-split-move-top", "icon-split-move-bottom", nil, "icon-split-add-top", "icon-split-add-bottom", nil,
                           "icon-separate-from-split-menu-bottom", "icon-split-horizontal", nil, "icon-split-copy-links-vertical"]),
              "A vertical split takes the vertical Separate, Convert and Copy Links artwork")
        check(shows(single, ["icon-split-add-left", "icon-split-add-right", nil, "icon-split-add-top", "icon-split-add-bottom"]),
              "A sole pane's Add rows show their artwork")
        check(menu.items.compactMap(\.image).map(\.size) == [NSSize(width: 18, height: 18), NSSize(width: 18, height: 18),
              NSSize(width: 18, height: 18), NSSize(width: 18, height: 18), NSSize(width: 18, height: 18),
              NSSize(width: 22, height: 22), NSSize(width: 18, height: 18)],
              "Artwork draws at its catalog sizes: 18 points, 22 for Convert")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-pane-menu-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try BrowserStore(directory: root)
        let id = store.open("https://original.invalid")
        let request = SplitPaneInsertion(paneID: id, operation: .addAfter, state: store.state)!
        var owner = true
        let before = store.state
        let session = SplitPaneInsertionSession(request: request, candidateIDs: [id]) { owner }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        session.placeholder.frame = host.bounds; host.addSubview(session.placeholder)
        session.placeholder.layoutSubtreeIfNeeded()
        check(session.isValid && session.placeholder.superview === host, "Original valid draft owns one native presentation")
        check(session.placeholder.accessibilityLabel() == "New split pane", "Temporary pane has real accessibility label")
        let pending = session.placeholder
        check(pending.subviews.isEmpty, "Nil-blueprint pane draws no invented label or control")
        for (name, alpha) in [(NSAppearance.Name.aqua, 0.666), (.darkAqua, 0.1)] {
            pending.appearance = NSAppearance(named: name); pending.updateLayer()
            let fill = NSColor(cgColor: pending.layer!.backgroundColor!)!.usingColorSpace(.sRGB)!
            check(fill.redComponent == 1 && fill.greenComponent == 1 && fill.blueComponent == 1 && abs(fill.alphaComponent - alpha) < 0.0001,
                  "emptyWindowContentBackgroundColor resolves white at the recovered \(name.rawValue) alpha")
        }
        check(pending.layer?.sublayers?.contains(pending.splitHighlight.layer) == true, "Pending pane owns the original highlight border layer")
        check(store.state == before && store.state.tabs.count == before.tabs.count, "Presentation never creates a saved page")
        owner = false
        check(!session.isValid, "Original owner invalidation revokes temporary pane")
        session.cancel()
        check(session.cancelled && session.placeholder.superview == nil, "Cancellation removes actual placeholder view")
        owner = true
        check(!session.isValid, "Returning owner cannot revive a cancelled presentation")
        session.cancel()
        check(store.state == before, "Repeated cancellation never changes original content records")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let paneView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200)); window.contentView = paneView
        let highlight = SplitPaneHighlight(); highlight.attach(to: paneView)
        let shape = highlight.layer
        CATransaction.flush()
        func takeTransitions() -> [String: CFTimeInterval] {
            defer { shape.removeAllAnimations() }
            return Dictionary(uniqueKeysWithValues: (shape.animationKeys() ?? []).compactMap { key in
                shape.animation(forKey: key).map { (key, $0.duration) }
            })
        }
        func recovered(_ transitions: [String: CFTimeInterval]) -> Bool {
            transitions["opacity"] != nil && transitions.values.allSatisfy { abs($0 - 0.11) < 1e-9 }
        }
        check(shape.fillColor == nil && shape.lineJoin == .round && shape.lineCap == .round && shape.zPosition == 8 && shape.opacity == 0,
              "Highlight layer has no fill, round join/cap, z-position 8 and starts hidden")
        highlight.layout(bounds: paneView.bounds, cornerRadius: 6)
        check(shape.frame == paneView.bounds && shape.path?.boundingBox == CGRect(x: 0, y: 0, width: 300, height: 200),
              "Highlight strokes the full content bounds")
        highlight.color = NSColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        check(shape.strokeColor != nil && shape.animationKeys()?.isEmpty != false, "Stroke color applies without an implicit transition")
        let focused = SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: false)
        let dropTarget = SplitPaneHighlightState.resolve(isProposedDropTarget: true, isFocused: false, paneCount: 2, dragEditActive: true)
        check(focused == SplitPaneHighlightState(display: true, width: 2), "Focused multi-pane content shows the two-point border")
        check(dropTarget == SplitPaneHighlightState(display: true, width: 3), "Proposed replacement shows the three-point border during a drag")
        check(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 2, dragEditActive: true).display,
              "Drag-and-drop pane edit hides the focus border")
        check(!SplitPaneHighlightState.resolve(isProposedDropTarget: false, isFocused: true, paneCount: 1, dragEditActive: false).display,
              "A single content shows no focus border")
        highlight.update(display: false, width: 2)
        check(shape.opacity == 0 && shape.lineWidth == 4 && takeTransitions().isEmpty, "First published state applies immediately")
        highlight.update(display: true, width: 3)
        check(shape.opacity == 1 && shape.lineWidth == 6, "Visible width is half the doubled stroke; opacity is one")
        check(recovered(takeTransitions()), "Displayed-state change uses the recovered 0.11-second implicit transition")
        highlight.update(display: true, width: 2)
        check(shape.lineWidth == 4 && takeTransitions().isEmpty, "Width-only change applies without a transition")
        highlight.update(display: false, width: 2)
        check(shape.opacity == 0 && recovered(takeTransitions()), "Hiding uses the same transition")
        paneView.isHidden = true; highlight.update(display: true, width: 2); paneView.isHidden = false
        check(shape.opacity == 1 && takeTransitions().isEmpty, "A hidden host updates immediately")
        highlight.followLayout(from: CGRect(x: 0, y: 0, width: 200, height: 200),
                               animation: { let a = CABasicAnimation(keyPath: "bounds"); a.duration = 0.2; a.timingFunction = CAMediaTimingFunction(name: .easeOut); return a }())
        let follow = shape.animation(forKey: "Split pane highlight layout") as? CABasicAnimation
        check(follow?.keyPath == "path" && follow?.duration == 0.2 && (follow?.fromValue as! CGPath).boundingBox.width == 200,
              "Path follows the host's bounds transition from its previous size")
        highlight.cancelFollow()
        check(shape.animation(forKey: "Split pane highlight layout") == nil, "Cancelled host transition removes the path transition")
        print("PASS: \(count) native pane-menu/draft ownership checks (no browser)")
    }
}
