import AppKit

private final class TestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@main
struct RendererCrashPresentationTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func pump() {
        let deadline = Date().addingTimeInterval(0.08)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            NSApp.updateWindows()
        }
    }

    private static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.51) -> Bool { abs(a - b) <= tolerance }

    @MainActor private static func components(_ color: NSColor, _ name: NSAppearance.Name) -> [CGFloat] {
        var result: [CGFloat] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let rgb = color.usingColorSpace(.sRGB)!
            result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        }
        return result
    }

    /// Offscreen rendering of a window-less view: real drawing for the
    /// appearance check, which cannot acknowledge a crash (no window).
    @MainActor private static func pixel(_ view: NSView, at point: NSPoint) -> [CGFloat] {
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        let color = rep.colorAt(x: Int(point.x * CGFloat(rep.pixelsWide) / view.bounds.width),
                                y: Int(point.y * CGFloat(rep.pixelsHigh) / view.bounds.height))!.usingColorSpace(.sRGB)!
        return [color.redComponent, color.greenComponent, color.blueComponent]
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        //
        typealias Segment = SadTabContent.Segment
        expect(SadTabContent.segments(SadTabContent.message) == [Segment(text: "Tab crashed. Maybe ", isLink: false),
               Segment(text: "reload", isLink: true), Segment(text: " the page?", isLink: false)],
               "the bracketed word splits the sentence into text, link and text")
        expect(SadTabContent.segments("[reload]") == [Segment(text: "reload", isLink: true)],
               "empty outer parts are left out")
        expect(SadTabContent.segments("No brackets") == [Segment(text: "No brackets", isLink: true)],
               "without a match the whole sentence is the link")
        expect(SadTabContent.plainMessage == "Tab crashed. Maybe reload the page?", "plain sentence drops the brackets")
        expect(SadTabContent.errorCode(42) == "Error code: 42", "error code text")
        let light = components(SadTabContent.foreground, .aqua), dark = components(SadTabContent.foreground, .darkAqua)
        expect(light.prefix(3) == [0, 0, 0] && near(light[3], 0.3, 0.001), "ForegroundTertiary is black at 0.3")
        expect(dark.prefix(3) == [1, 1, 1] && near(dark[3], 0.3, 0.001), "dark ForegroundTertiary is white at 0.3")
        expect(components(SadTabContent.backing, .aqua) == [1, 1, 1, 1], "FullOpacityBackgroundPrimary is white")
        expect(components(SadTabContent.backing, .darkAqua) == [0, 0, 0, 1], "dark FullOpacityBackgroundPrimary is black")
        let art = SadTabContent.artwork
        expect(SadTabContent.artworkDirectory == Bundle.main.resourceURL?.appendingPathComponent("SadTab", isDirectory: true) && art != nil,
               "the artwork loads from the bundle's SadTab resources")
        expect(art != nil && art!.isTemplate && art!.size == NSSize(width: 96, height: 103) &&
               art!.representations.compactMap { $0 as? NSBitmapImageRep }.map(\.pixelsWide).sorted() == [96, 192],
               "the copied SadTab template loads with its 1x and 2x bitmaps")

        let window = TestWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 420),
                                styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Parc renderer crash component checks"
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        window.contentView = root
        let address = NSTextField(frame: NSRect(x: 10, y: 385, width: 620, height: 24))
        address.stringValue = "Address focus must stay here"
        root.addSubview(address)
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 375))
        page.setAccessibilityElement(true)
        page.setAccessibilityRole(.group)
        let pageButton = NSButton(title: "Original page", target: nil, action: nil)
        pageButton.frame = NSRect(x: 20, y: 20, width: 150, height: 30)
        page.addSubview(pageButton)
        root.addSubview(page)
        let failure = PageFailureView(frame: page.frame)
        failure.pageView = page
        root.addSubview(failure)
        let link = failure.sentence
        let tokenA = NSObject(), tokenB = NSObject()
        let first = RendererCrashPresentation(pageIdentifier: "same-actual-page", identity: tokenA,
                                              terminationStatus: 1, errorCode: 42)
        let replacement = RendererCrashPresentation(pageIdentifier: "same-actual-page", identity: tokenB,
                                                    terminationStatus: 1, errorCode: 7)
        var presented: [RendererCrashPresentation] = []
        var retried: [RendererCrashPresentation] = []
        var navigationRetries = 0
        failure.onRendererPresented = { presented.append($0); return true }
        failure.onRetryRenderer = { retried.append($0) }
        failure.onReload = { navigationRetries += 1 }

        expect(page.isHidden == false && failure.isHidden, "starts with actual retained page visible")
        failure.showNavigationFailure("Previous navigation error")
        expect(failure.presentation == .navigation("Previous navigation error"), "ordinary error has independent presentation")
        failure.layoutSubtreeIfNeeded()
        expect(failure.artwork.isHidden && link.text == "This page couldn’t open. Try again" &&
               failure.corner.text == "Previous navigation error", "navigation failure uses the composition without artwork")
        failure.showRendererFailure(first)
        expect(failure.presentation == .renderer(first), "real snapshot replaces ordinary error presentation")
        expect(page.isHidden && page.window === window && page.superview === root,
               "crash hides but retains exact page/window/container")
        expect(page.hitTest(NSPoint(x: 30, y: 30)) == nil, "hidden native page cannot receive pointer hits")
        expect(page.isAccessibilityHidden(), "hidden native page is hidden from AppKit accessibility")
        expect(!failure.artwork.isHidden && link.text == SadTabContent.plainMessage && failure.corner.text == "Error code: 42",
               "crash shows the artwork, sentence and the snapshot's error code")

        // SadTabView geometry in a 640 × 375 page (flipped, top-left origin).
        failure.layoutSubtreeIfNeeded()
        let bounds = failure.bounds, artFrame = failure.artwork.frame, line = link.frame, code = failure.corner.frame
        let column = 96 + 64 + line.height
        expect(near(artFrame.height, 96) && near(artFrame.width, 96 * 96 / 103), "artwork is 96 points high at its aspect")
        expect(near(artFrame.midX, bounds.midX) && near(line.midX, bounds.midX), "column is centred horizontally")
        expect(near(artFrame.minY, (bounds.height - column) / 2), "column is centred vertically")
        expect(near(line.minY - artFrame.maxY, 64), "sentence sits 64 points below the artwork")
        expect(near(line.height, 16) && line.width > 200 && line.width < 240, "sentence is one 13-point line")
        expect(near(code.maxX, bounds.maxX - 20) && near(code.maxY, bounds.maxY - 20) && near(code.height, 16),
               "error code is 20 points in from the bottom-trailing corner")
        let linkRect = link.linkRect
        expect(linkRect.minX > 100 && linkRect.width > 30 && linkRect.width < 45, "only the bracketed word is the link")
        expect(link.hitTest(link.convert(NSPoint(x: linkRect.midX, y: linkRect.midY), to: failure)) === link,
               "the link takes the pointer")
        expect(link.hitTest(link.convert(NSPoint(x: 10, y: linkRect.midY), to: failure)) == nil &&
               failure.corner.hitTest(NSPoint(x: code.midX, y: code.midY)) == nil, "plain text passes the pointer on")
        expect(link.accessibilityRole() == .link && link.accessibilityLabel() == SadTabContent.plainMessage &&
               failure.corner.accessibilityRole() == .staticText, "AX exposes the link and the static error code")
        expect(!link.canBecomeKeyView, "the link stays out of the key-view loop text")
        let narrow = link.fittingSize(width: 120)
        expect(narrow.width <= 120 && narrow.height > 16, "a narrow pane wraps the HStack's texts")

        link.performClick(nil)
        expect(retried.isEmpty && presented.isEmpty, "undisplayed preparation neither acknowledges nor acts")
        expect(!failure.focusRendererAction(first), "hidden window cannot claim crash focus")

        // Let AppKit draw its real visible window. Never invoke draw directly.
        window.makeKeyAndOrderFront(nil)
        pump()
        expect(presented == [first], "actual native drawing acknowledges current snapshot once")
        failure.needsDisplay = true
        pump()
        expect(presented == [first], "repaint does not repeat presentation acknowledgment")
        // The link's own mouse handlers (hit testing is checked above). The
        // window would focus a clicked view only if it accepted first responder.
        func click(_ point: NSPoint) {
            let location = link.convert(point, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                               clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                if type == .leftMouseDown { link.mouseDown(with: event) } else { link.mouseUp(with: event) }
            }
        }
        click(NSPoint(x: linkRect.maxX + 20, y: linkRect.midY))
        expect(retried.isEmpty, "a click beside the link does nothing")
        click(NSPoint(x: linkRect.midX, y: linkRect.midY))
        expect(retried == [first], "a click on the visible painted link carries exact snapshot")
        expect(!link.acceptsFirstResponder && window.firstResponder !== link,
               "a click does not move keyboard focus to the link tap does not")
        expect(failure.presentation == .renderer(first) && page.isHidden,
               "Retry never predicts recovery or replaces the page")
        expect(navigationRetries == 0, "renderer action does not invoke generic navigation Retry")
        expect(failure.focusRendererAction(first) && failure.ownsFirstResponder && window.firstResponder === link,
               "explicit native crash focus reaches the actual link")
        link.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: " ",
                                            charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!)
        expect(retried == [first, first], "Space on the focused link sends its action")
        expect(link.accessibilityPerformPress() && retried.count == 3, "AX press sends the link's action")
        window.makeFirstResponder(address)
        let addressResponder = window.firstResponder
        failure.showRendererFailure(first)
        pump()
        expect(window.firstResponder === addressResponder, "repeated metadata does not steal address focus")

        failure.isHidden = true
        link.performClick(nil)
        expect(retried.count == 3, "hidden old crash control cannot invoke action")
        failure.showRendererFailure(first)
        failure.clear()
        link.performClick(nil)
        expect(retried.count == 3 && failure.presentation == nil,
               "authoritative clear invalidates old action")
        expect(!link.acceptsFirstResponder && !link.accessibilityPerformPress(), "a cleared link takes no focus or press")
        expect(!page.isHidden && page.window === window && page.superview === root,
               "recovery restores the same retained page without old navigation error")
        expect(!page.isAccessibilityHidden(), "restored page returns to AppKit accessibility")
        failure.showNavigationFailure("Later navigation failure")
        expect(failure.presentation == .navigation("Later navigation failure"),
               "a genuinely later navigation error is still presented")
        link.performClick(nil)
        expect(navigationRetries == 1, "ordinary error retains its own Retry")

        failure.onRendererPresented = { snapshot in
            presented.append(snapshot)
            if snapshot == first { failure.showRendererFailure(replacement) }
            return true
        }
        failure.showRendererFailure(first)
        pump()
        expect(failure.presentation == .renderer(replacement), "acknowledgment reentry may replace the crash")
        expect(failure.corner.text == "Error code: 7", "replacement shows its own error code")
        expect(!failure.focusRendererAction(first), "stale snapshot cannot focus replacement")
        pump()
        expect(presented.contains(replacement), "replacement requires its own actual drawing")
        link.performClick(nil)
        expect(retried.last == replacement, "replacement link dispatches its own snapshot")
        failure.onRendererPresented = { _ in failure.clear(); return true }
        failure.showRendererFailure(first)
        pump()
        expect(failure.presentation == nil && !page.isHidden,
               "teardown during drawing leaves page restored and old action invalid")
        let prior = retried.count
        link.performClick(nil)
        expect(retried.count == prior, "reentrant teardown cannot authorize old action")
        window.orderOut(nil)
        failure.onRendererPresented = { presented.append($0); return true }
        failure.showRendererFailure(first)
        let priorPresentations = presented.count
        pump()
        link.performClick(nil)
        expect(presented.count == priorPresentations && retried.count == prior,
               "ordered-out owner neither acknowledges nor invokes Retry")
        failure.clear()
        page.setAccessibilityHidden(true)
        failure.showRendererFailure(first)
        failure.clear()
        expect(page.isAccessibilityHidden(), "recovery preserves an independently hidden AX subtree")
        page.setAccessibilityHidden(false)
        failure.showRendererFailure(first)
        let nextPage = NSView(frame: page.frame)
        root.addSubview(nextPage)
        failure.pageView = nextPage
        expect(!page.isHidden && !page.isAccessibilityHidden(), "page replacement restores the prior retained host")
        expect(nextPage.isHidden && nextPage.isAccessibilityHidden(), "replacement hierarchy remains hidden until native clear")
        failure.clear()
        expect(!nextPage.isHidden && !nextPage.isAccessibilityHidden(), "clear restores replacement's own visibility and AX value")
        failure.onRendererPresented = nil
        failure.onRetryRenderer = nil
        failure.onReload = nil
        window.close()

        // Light and dark backing, drawn by a window-less copy (no acknowledgment).
        for (name, expected) in [(NSAppearance.Name.aqua, [CGFloat(255), 255, 255]), (.darkAqua, [0, 0, 0])] {
            let offscreen = PageFailureView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            offscreen.appearance = NSAppearance(named: name)
            offscreen.showRendererFailure(first)
            expect(pixel(offscreen, at: NSPoint(x: 10, y: 10)).map { ($0 * 255).rounded() } == expected,
                   "the backing is FullOpacityBackgroundPrimary in \(name.rawValue)")
        }
        print("PASS \(checks) renderer crash AppKit presentation checks")
    }
}
