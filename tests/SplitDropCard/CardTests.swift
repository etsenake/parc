import AppKit

@MainActor var passed = 0
@MainActor var failed = 0
@MainActor func check(_ condition: Bool, _ message: String) {
    if condition { passed += 1 } else { failed += 1; print("FAIL:", message) }
}

@MainActor final class Drag: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var source: AnyObject?
    var draggingSource: Any? { source }
    var draggingSequenceNumber = 3
    var draggingFormation = NSDraggingFormation.default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    var items: [NSDraggingItem] = []
    var calls: [(options: NSDraggingItemEnumerationOptions, view: NSView?, classes: [AnyClass], visited: [Int])] = []
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var visited: [Int] = []
        var stop = ObjCBool(false)
        if !classArray.isEmpty {
            for (index, item) in items.enumerated() {
                visited.append(index)
                block(item, index, &stop)
                if stop.boolValue { break }
            }
        }
        calls.append((enumOpts, view, classArray, visited))
    }
    func resetSpringLoading() {}
    func dispose() { draggingPasteboard.releaseGlobally() }
}

@MainActor final class Row: SplitDropCardSource {
    var splitDrag: SidebarSplitDrag?
    var splitDropCardContent: (icon: NSImage?, title: String) = (nil, "1Password")
    var splitDragImage: NSImage?
}

@MainActor final class Pane: NSView {
    let body = NSView()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; addSubview(body)
        body.autoresizingMask = [.width, .height]
        body.frame = NSRect(x: 0, y: 32, width: frame.width, height: max(0, frame.height - 32))
    }
    required init?(coder: NSCoder) { fatalError() }
}
@MainActor final class Host: NSView { override var isFlipped: Bool { true } }

@MainActor func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var values = [Int](repeating: 0, count: 4)
    rep.getPixel(&values, atX: x, y: y)
    return (values[0], values[1], values[2], rep.samplesPerPixel > 3 ? values[3] : 255)
}
@MainActor func item(_ type: NSPasteboard.PasteboardType, _ value: String, frame: NSRect) -> NSDraggingItem {
    let pasteboardItem = NSPasteboardItem(); pasteboardItem.setString(value, forType: type)
    let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
    item.setDraggingFrame(frame, contents: NSImage(size: frame.size))
    return item
}
@MainActor func contents(_ item: NSDraggingItem) -> NSImage? { item.imageComponentsProvider?().first?.contents as? NSImage }

@main @MainActor struct CardTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let portraitPane = NSSize(width: 412, height: 808)
        let portrait = SplitDropPlaceholderCard.size(forIncomingPane: portraitPane)!
        check(portrait.height == 250 && abs(portrait.width - 250 * 412 / 808) < 1e-9,
              "a tall incoming pane gives a 250-point-high card at its aspect ratio")
        let landscape = SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: 808, height: 412))!
        check(landscape.width == 250 && abs(landscape.height - 250 * 412 / 808) < 1e-9,
              "a wide incoming pane gives a 250-point-wide card at its aspect ratio")
        check(SplitDropPlaceholderCard.size(forIncomingPane: NSSize(width: 300, height: 300)) == NSSize(width: 250, height: 250),
              "a square pane takes the height branch")
        check([NSSize(width: 0, height: 808), NSSize(width: 412, height: 0), NSSize(width: -4, height: 10),
               NSSize(width: CGFloat.infinity, height: 10)].allSatisfy { SplitDropPlaceholderCard.size(forIncomingPane: $0) == nil },
              "an empty or unbounded pane makes no card")

        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            guard let image = SplitDropPlaceholderCard.image(icon: NSImage(size: NSSize(width: 16, height: 16)), title: "1Password",
                                                             incomingPane: portraitPane),
                  let rep = image.representations.first as? NSBitmapImageRep else { check(false, "card image renders"); continue }
            check(image.size == portrait, "card image is the computed card size")
            let scale = rep.pixelsHigh / 250
            check(scale >= 1 && rep.pixelsHigh == 250 * scale && rep.pixelsWide == Int((portrait.width * CGFloat(scale)).rounded(.up)),
                  "the windowless card caches at a whole-pixel scale of its size, as AppKit picks for a view with no window")
            let fill = pixel(rep, 6, rep.pixelsHigh / 2)
            check(dark ? fill.r < 8 && fill.g < 8 && fill.b < 8 && fill.a > 247 : fill.r > 247 && fill.g > 247 && fill.b > 247 && fill.a > 247,
                  "the card is FullOpacityBackgroundPrimary in the application's \(dark ? "dark" : "light") appearance")
            check(pixel(rep, 0, 0).a < 8 && pixel(rep, rep.pixelsWide - 1, rep.pixelsHigh - 1).a < 8,
                  "its 20-point corners are transparent outside the rounding")
        }
        NSApp.appearance = nil

        let title = "A long page title that wraps across more lines than the card shows"
        let card = SplitDropPlaceholderCard(icon: NSImage(size: NSSize(width: 64, height: 64)), title: title)
        card.frame = NSRect(origin: .zero, size: portrait)
        card.layoutSubtreeIfNeeded(); card.layoutSubtreeIfNeeded()
        card.updateLayer()
        check(card.layer?.cornerRadius == 20 && card.layer?.cornerCurve == .continuous && card.layer?.backgroundColor != nil,
              "updateLayer paints the continuous 20-point card")
        check(card.iconView.frame.size == NSSize(width: 16, height: 16), "the favicon is 16 × 16 whatever its image size")
        let font = card.titleView.font
        check(font?.pointSize == 13 && font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true,
              "the title is FontSet.label (13 points) made bold")
        check(card.titleView.alignment == .center && card.titleView.maximumNumberOfLines == 3
              && card.titleView.lineBreakMode == .byWordWrapping && card.titleView.cell?.truncatesLastVisibleLine == true,
              "the title is centred, word-wrapped to three lines and truncates its last line")
        if let font {
            let lines = (card.titleView.frame.height / NSLayoutManager().defaultLineHeight(for: font)).rounded()
            check(lines == 3, "a long title fills exactly three lines (\(card.titleView.frame.height) points)")
        }
        check(abs(card.titleView.preferredMaxLayoutWidth - (portrait.width - 16)) < 1e-9, "the title wraps at the card width less both insets")
        let stack = card.subviews.first as? NSStackView
        check(stack?.orientation == .vertical && stack?.alignment == .centerX && stack?.spacing == 24,
              "a vertical centre-X stack spaces the icon and title 24 points apart")
        if let stack {
            let icon = card.convert(card.iconView.frame, from: stack), text = card.convert(card.titleView.frame, from: stack)
            check(abs(icon.midX - card.bounds.midX) < 0.5 && abs(stack.frame.midY - card.bounds.midY) < 0.5,
                  "the stack is centred in the card")
            check(abs(min(abs(text.minY - icon.maxY), abs(icon.minY - text.maxY)) - 24) < 0.5, "the icon sits 24 points from the title")
            check(stack.frame.minX >= 7 && stack.frame.maxX <= card.bounds.maxX - 7,
                  "the stack keeps its 8-point side insets to within AppKit's point rounding")
        }

        let link = SidebarIconCatalog.emojiImage(String(Character(Unicode.Scalar(0xE98A)!)), size: 22)
        check(link.size == NSSize(width: 25, height: 25) && !link.isTemplate,
              "the link icon is Feather's 22-point chain link in a 25-point square, not a template")
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = link.size
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            link.draw(in: NSRect(origin: .zero, size: link.size))
            NSGraphicsContext.restoreGraphicsState()
            var ink = 0, light = 0
            for y in 0..<50 { for x in 0..<50 { let p = pixel(rep, x, y); if p.a > 200 { ink += 1; if p.r > 40 { light += 1 } } } }
            check(ink > 100 && light == 0, "the glyph draws in black from the shipped Feather font")
        }

        let type = SidebarSplitDrag.pasteboardType
        let probe = Drag()
        let own = item(type, "current", frame: NSRect(x: 30, y: 40, width: 206, height: 36))
        let foreign = item(type, "other", frame: NSRect(x: 5, y: 6, width: 206, height: 36))
        let ownOriginal = contents(own)
        probe.items = [own, foreign]
        let image = SplitDropPlaceholderCard.image(icon: nil, title: "1Password", incomingPane: portraitPane)!
        let replaced = SplitDropPlaceholderCard.present(image, on: probe) { $0.string(forType: type) == "current" }
        check(probe.calls.count == 1 && probe.calls[0].options.isEmpty && probe.calls[0].view == nil
              && probe.calls[0].classes.count == 1 && probe.calls[0].classes[0] == NSPasteboardItem.self && probe.calls[0].visited == [0, 1],
              "both items are offered as pasteboard items in screen coordinates")
        check(own.draggingFrame == NSRect(origin: NSPoint(x: 30, y: 40), size: image.size) && contents(own) === image,
              "the session's item becomes the card, keeping its unflipped origin")
        check(foreign.draggingFrame == NSRect(x: 5, y: 6, width: 206, height: 36) && replaced.keys.sorted() == [0],
              "item 1, another session's, is visited but keeps its own image")
        check(replaced[0]?.size == NSSize(width: 206, height: 36) && (replaced[0]?.contents as? NSImage) === ownOriginal,
              "the replaced item's own image and size are recorded")
        own.setDraggingFrame(NSRect(origin: NSPoint(x: 31, y: 41), size: image.size), contents: image)
        SplitDropPlaceholderCard.restore(replaced, on: probe)
        check(own.draggingFrame == NSRect(x: 31, y: 41, width: 206, height: 36) && contents(own) === ownOriginal,
              "restore puts the own image back at the item's current bottom-left")
        probe.dispose()

        let primary = ThemeColor.hsl(hue: 0.42, saturation: 0.5, lightness: 0.75, colorSpace: .displayP3)
        for forced in SpaceTheme.Appearance.allCases {
            var theme = SpaceTheme(primaryColor: primary, colorCount: 2); theme.appearance = forced
            let ink = ThemeChromePalette.appearanceBasedMaxContrast(theme: theme)
            for dark in [false, true] {
                var resolved = NSColor.clear
                NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                    resolved = NSColor(cgColor: ink.cgColor)!.usingColorSpace(.extendedSRGB)!
                }
                let expected = ThemeChromePalette(theme: theme, isDark: dark).maxContrastColor.usingColorSpace(.extendedSRGB)!
                check(abs(resolved.redComponent - expected.redComponent) < 1e-4 && abs(resolved.greenComponent - expected.greenComponent) < 1e-4
                      && abs(resolved.blueComponent - expected.blueComponent) < 1e-4,
                      "a \(forced) theme's ink under \(dark ? "darkAqua" : "aqua") is that palette's maxContrastColor")
            }
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1236, height: 808), styleMask: .borderless, backing: .buffered, defer: false)
        let host = Host(frame: NSRect(x: 0, y: 0, width: 1236, height: 808)); window.contentView = host
        let split = ParcSplitView(frame: host.bounds); host.addSubview(split)
        let panes = [Pane(frame: host.bounds), Pane(frame: host.bounds)]
        panes.forEach { split.addArrangedSubview($0) }
        split.configure(orientation: .horizontal, factors: [0.5, 0.5]); split.constrain(to: host)
        host.layoutSubtreeIfNeeded()
        let drag = SidebarSplitDrag(tabID: UUID(), window: window, validate: { true }, commit: { _, _ in true }, finish: {})
        guard let reservation = split.prepareDropReservation(in: host, contents: panes.map(\.body)) else { fatalError("no reservation") }
        let overlay = SplitDropView(frame: host.bounds, drag: drag, reservation: reservation, insertionColor: { .black })
        overlay.canPropose = { _, _ in true }
        host.addSubview(overlay)
        let row = Row(); row.splitDrag = drag
        let rowImage = NSImage(size: NSSize(width: 206, height: 36)); row.splitDragImage = rowImage

        let session = Drag(); session.source = row; session.draggingDestinationWindow = window
        session.draggingPasteboard.setString(drag.identifier.uuidString, forType: type)
        let sessionItem = item(type, drag.identifier.uuidString, frame: NSRect(x: 30, y: 40, width: 206, height: 36))
        let otherItem = item(type, "other", frame: NSRect(x: 5, y: 6, width: 206, height: 36))
        session.items = [sessionItem, otherItem]
        session.draggingLocation = host.convert(NSPoint(x: 4, y: 300), to: nil)
        let entered = overlay.draggingEntered(session)
        check(entered == .move && overlay.showsCard, "an accepted drag shows the card")
        let expected = SplitDropPlaceholderCard.size(forIncomingPane: reservation.incomingPaneSize)!
        check(sessionItem.draggingFrame.size == expected && sessionItem.draggingFrame.origin == NSPoint(x: 30, y: 40)
              && contents(sessionItem) !== rowImage, "the session's own item becomes the card for the incoming pane")
        check(otherItem.draggingFrame.size == NSSize(width: 206, height: 36), "another item keeps its image")
        overlay.draggingExited(session)
        check(!overlay.showsCard && sessionItem.draggingFrame == NSRect(x: 30, y: 40, width: 206, height: 36) && contents(sessionItem) === rowImage,
              "exit puts back the row's own image and size at the same bottom-left")
        let enumerations = session.calls.count
        overlay.draggingExited(session)
        check(session.calls.count == enumerations, "a second exit without a card changes nothing")
        _ = overlay.draggingEntered(session)
        overlay.draggingEnded(session)
        check(!overlay.showsCard, "the drag's end forgets the card")
        session.dispose()
        let refused = Drag(); refused.source = row; refused.draggingDestinationWindow = window
        refused.draggingPasteboard.setString(UUID().uuidString, forType: type)
        let refusedItem = item(type, "stale", frame: NSRect(x: 10, y: 10, width: 206, height: 36)); refused.items = [refusedItem]
        refused.draggingLocation = host.convert(NSPoint(x: 4, y: 300), to: nil)
        check(overlay.draggingEntered(refused).isEmpty && !overlay.showsCard && refused.calls.isEmpty,
              "a drag the overlay does not accept gets no card")
        overlay.draggingExited(refused)
        check(refused.calls.isEmpty && refusedItem.draggingFrame.size == NSSize(width: 206, height: 36),
              "its exit enumerates nothing, so its image is left alone")
        refused.dispose()

        overlay.removeFromSuperview(); reservation.end()

        print(failed == 0 ? "PASS: \(passed) split drop card checks (no drag, no browser)" : "FAILED: \(failed) of \(passed + failed)")
        exit(failed == 0 ? 0 : 1)
    }
}
