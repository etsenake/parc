import AppKit

@MainActor private final class BandedAnchor: NSView, PArcToastAnchoring {
    override var isFlipped: Bool { true }
    var toastContentRect: NSRect { NSRect(x: 80, y: 42, width: bounds.width - 160, height: bounds.height - 54) }
}

@MainActor private final class ToastParent: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct PArcToastTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        Task { @MainActor in await run(); exit(0) }
        app.run()
    }

    @MainActor static func run() async {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); assertions += 1
        }
        func drain(_ interval: TimeInterval) async {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.75 }

        check(PArcToastPlacement.windowFrame(for: NSRect(x: 100, y: 200, width: 1000, height: 800))
              == NSRect(x: 500, y: 400, width: 600, height: 600), "600-point child at the window's top right")
        check(PArcToastPlacement.contentFrame(for: NSRect(x: 300, y: 100, width: 600, height: 700))
              == NSRect(x: 300, y: 450, width: 600, height: 350), "content toast uses the upper half of its pane")
        check(PArcToastTiming.duration == 5 && PArcToastTiming.retirement == 1, "five-second toast, one-second retirement")

        let url = URL(string: "https://chatgpt.com/")!
        check(PArcToastContent.copiedCurrentURL(url).body
              == .standard(icon: nil, label: "Copied Current URL", subLabel: nil, buttons: [.share([url])]),
              "copyTabURL: label and share button for the copied URL")
        check(PArcToastContent.copiedCurrentURL(nil).body
              == .standard(icon: nil, label: "Copied Current URL", subLabel: nil, buttons: []),
              "no URL, no share button")
        check(PArcToastContent.copiedItemLinks([url, url]).body
              == .standard(icon: nil, label: "Copied item links", subLabel: nil, buttons: [.share([url, url])]),
              "copyItemURLs shares every copied URL")
        check(PArcToastContent.copiedQuoteLink(url).body
              == .standard(icon: "quote.bubble.fill", label: "Copied Link", subLabel: "With Quote", buttons: [.share([url])]),
              "copyTabURLQuote: quote icon, sublabel and share button")
        check(PArcToastContent.cannotAddNewPane.body
              == .standard(icon: nil, label: "Cannot Add New Pane", subLabel: nil, buttons: []), "maxNumberPanes")
        check(PArcToastContent.pressAgain(shortcut: "⌘T", title: "New Tab").accessibilityText == "Press ⌘T again to New Tab",
              "Press Again keeps its spoken text")
        check(PArcToastContent.copiedQuoteLink(url).accessibilityText == "Copied Link, With Quote", "label and sublabel are announced")
        check(PArcToastContent.pressAgain(shortcut: "⌘T", title: "New Tab").showsShortcut
              && !PArcToastContent.copiedCurrentURL(url).showsShortcut, "only shortcut content shows a shortcut")
        func label(_ content: PArcToastContent) -> String? {
            if case .standard(_, let label, _, _) = content.body { return label } else { return nil }
        }
        check(label(.copiedImage) == "Copied Image", "captureCopied")
        check(PArcToastContent.copiedFile([url]).body
              == .standard(icon: nil, label: "Copied File", subLabel: nil, buttons: [.share([url])]), "copyFile shares the file")
        check(label(.zoom(percent: 110)) == "110%", "zoomChanged is the percentage")
        check(label(.fullScreenExit(shortcut: "⎋")) == "To exit full screen, press ⎋.", "didEnterFullScreen names the exit binding")
        check(label(.archiveCleared) == "Archive Cleared", "archiveCleared")
        check(label(.tabRestored(to: "Work", selected: false)) == "Tab restored to Work. Click to view."
              && label(.tabRestored(to: "Work", selected: true)) == "Tab restored to Work", "tabUnarchived wording")
        check(label(.pinnedToFolder("Reading")) == "Pinned to “Reading”", "tabPinnedToFolder")
        check(label(.backgroundTabCreated(inSpace: nil, document: false)) == "New Tab Created"
              && label(.backgroundTabCreated(inSpace: "Home", document: false)) == "New Tab Created in Home"
              && label(.backgroundTabCreated(inSpace: "Home", document: true)) == "New Document Created",
              "the background-tab affordance's three messages")
        let iconFont = NSFontManager.shared.font(withFamily: NSFont.systemFont(ofSize: 13).familyName ?? "",
                                                 traits: [], weight: 8, size: 13)
        check(iconFont.map { NSFontManager.shared.weight(of: $0) > NSFontManager.shared.weight(of: NSFont.systemFont(ofSize: 13)) } == true,
              "the quote icon is the label font made heavier at NSFontManager weight 8")

        let parent = ToastParent(contentRect: NSRect(x: -12_000, y: -12_000, width: 1000, height: 700),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false; parent.isRestorable = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let pane = NSView(frame: NSRect(x: 520, y: 10, width: 470, height: 660))
        root.addSubview(pane); parent.contentView = root
        var shared: [[URL]] = []
        let toasts = PArcToastPresenter(share: { shared.append($0) })
        check(toasts.show(.copiedCurrentURL(url), in: parent, over: pane, theme: SpaceTheme()) == nil,
              "a hidden parent presents nothing")
        parent.orderBack(nil)
        let paneScreen = parent.convertToScreen(pane.convert(pane.bounds, to: nil))
        check(PArcToastPresentation.frame(in: parent, over: pane) == PArcToastPlacement.contentFrame(for: paneScreen),
              "a pane anchor uses that pane, not the window")
        check(PArcToastPresentation.frame(in: parent, over: nil) == PArcToastPlacement.windowFrame(for: parent.frame),
              "window location uses the window's top right")
        pane.isHidden = true
        check(PArcToastPresentation.frame(in: parent, over: pane) == PArcToastPlacement.windowFrame(for: parent.frame),
              "a hidden pane falls back to the window, as the delegate's nil frame does")
        let peekHost = BandedAnchor(frame: NSRect(x: 160, y: 10, width: 820, height: 660))
        root.addSubview(peekHost)
        let peekContent = parent.convertToScreen(peekHost.convert(peekHost.toastContentRect, to: nil))
        check(PArcToastPresentation.frame(in: parent, over: peekHost) == PArcToastPlacement.contentFrame(for: peekContent),
              "an anchor with a content region frames that region, below a Peek's title band")
        peekHost.removeFromSuperview()
        pane.isHidden = false

        var retired = 0
        guard let first = toasts.show(.copiedCurrentURL(url), in: parent, over: pane, theme: SpaceTheme(),
                                      onRetire: { retired += 1 }),
              let panel = parent.childWindows?.first else { preconditionFailure("missing toast child") }
        check(toasts.current === first && panel.parent === parent && panel.contentView === first, "exact child ownership")
        check(panel.frame == PArcToastPlacement.contentFrame(for: paneScreen), "the child covers the pane's upper half")
        check(!panel.canBecomeKey && !panel.canBecomeMain && !first.acceptsFirstResponder, "no keyboard owner")
        await drain(0.6)
        let body = first.frames.body
        check(near(body.maxX, panel.frame.width - 8) && near(body.minY, 8), "card sits 8 points in from the pane's top right")
        check(near(body.height, 47), "label row with the 27-point share button is 47 points tall")
        check(body.width > 150 && body.width < panel.frame.width - 16, "card hugs its content")
        func inParent(_ point: NSPoint) -> NSPoint { first.superview.map { $0.convert(point, from: first) } ?? point }
        check(first.hitTest(inParent(NSPoint(x: 10, y: 10))) == nil, "the clear window passes input through")
        check(first.hitTest(inParent(NSPoint(x: body.midX, y: body.midY))) != nil, "the card receives input")

        guard let second = toasts.show(.cannotAddNewPane, in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("replacement refused")
        }
        check(first.isRetiring && toasts.current === second && retired == 1, "a new toast replaces the visible one")
        check(first.hitTest(inParent(NSPoint(x: body.midX, y: body.midY))) == nil, "a retiring toast refuses input at once")
        check(second.window?.frame == PArcToastPlacement.windowFrame(for: parent.frame), "window toast at the window's top right")
        await drain(1.1)
        check(panel.parent == nil && !panel.isVisible, "the replaced child closes after its retirement")
        check(second.window?.parent === parent, "an old completion cannot retire the replacement")
        second.dismiss(animated: false)
        check(toasts.current == nil && parent.childWindows?.isEmpty != false, "immediate dismissal removes the child")

        let basic = NSColor(displayP3Red: 0.054, green: 0.06, blue: 0.075, alpha: 1)
        toasts.basicBackground = basic
        guard let privateToast = toasts.show(.cannotAddNewPane, in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("private window toast admitted")
        }
        check(privateToast.state.basicBackground === basic, "the presenter passes the incognito basic colour to the card")
        let other = SpaceTheme.singleColor(ThemeColor(hex: "568AC5")!)
        toasts.update(theme: other)
        check(privateToast.state.basicBackground === basic && privateToast.state.theme == other,
              "a theme refresh keeps the window's basic colour while taking the new Space theme")
        toasts.basicBackground = nil
        toasts.update(theme: other)
        check(privateToast.state.basicBackground == nil, "an ordinary window's refresh carries none")
        privateToast.dismiss(animated: false)

        let timed = PArcToastPresentation(content: .standard("Timed"), theme: SpaceTheme(), duration: 0.3)
        check(timed.present(in: parent, over: pane), "short-lived toast admitted")
        await drain(0.5)
        check(timed.isRetiring, "an unhovered timer tick dismisses")
        timed.dismiss(animated: false)

        let held = PArcToastPresentation(content: .standard("Held"), theme: SpaceTheme(), duration: 1)
        check(held.present(in: parent, over: pane), "hover owner admitted")
        await drain(0.7)
        if let heldPanel = held.window {
            let card = held.frames.body
            check(near(card.maxX, heldPanel.frame.width - 8) && near(card.minY, 8), "the card scales in to its own top-right place")
            let center = heldPanel.convertPoint(toScreen: held.convert(NSPoint(x: card.midX, y: card.midY), to: nil))
            held.pointerLocation = { center }
            check(held.containsPointer, "the pointer over the card is hover")
            await drain(0.5)
            check(!held.isRetiring, "a hovered tick keeps the toast")
            heldPanel.orderOut(nil)
            check(!held.containsPointer, "a hidden toast window is never hovered")
            heldPanel.orderBack(nil)
            held.pointerLocation = { NSPoint(x: center.x + 5_000, y: center.y) }
            await drain(1.1)
            check(held.isRetiring, "the first unhovered tick dismisses")
        } else { preconditionFailure("missing hover child") }
        held.dismiss(animated: false)

        check(!PArcToastScroll.dismisses(window: parent, deltaX: 0, deltaY: 0, owners: [parent]), "zero distance keeps")
        check(PArcToastScroll.dismisses(window: parent, deltaX: 0, deltaY: -2, owners: [parent]), "scrolling the parent dismisses")
        check(!PArcToastScroll.dismisses(window: nil, deltaX: 3, deltaY: 0, owners: [parent]), "a scroll elsewhere keeps")
        let scrolled = PArcToastPresentation(content: .standard("Scroll"), theme: SpaceTheme())
        check(scrolled.present(in: parent, over: pane), "scroll owner admitted")
        scrolled.scrolled(in: parent, deltaX: 0, deltaY: 0)
        check(!scrolled.isRetiring, "resting fingers keep the toast")
        scrolled.scrolled(in: parent, deltaX: 0, deltaY: 4)
        check(scrolled.isRetiring, "a real scroll dismisses")
        scrolled.dismiss(animated: false)

        var retiringWhenTapped: Bool?
        var tapped: PArcToastPresentation?
        tapped = PArcToastPresentation(content: .standard("Tab moved! Click to go there."), theme: SpaceTheme(),
                                      onTap: { retiringWhenTapped = tapped?.isRetiring })
        check(tapped?.present(in: parent, over: nil) == true, "tap owner admitted")
        tapped?.performTap()
        check(retiringWhenTapped == true, "a tap dismisses before acting")
        tapped?.performTap()
        check(retiringWhenTapped == true, "a retired toast ignores further taps")
        tapped?.dismiss(animated: false)

        guard let copyToast = toasts.show(.copiedCurrentURL(url), in: parent, over: pane, theme: SpaceTheme()) else {
            preconditionFailure("copy toast refused")
        }
        toasts.dismissShortcutToasts()
        check(!copyToast.isRetiring, "a copy toast survives a binding change")
        guard let cue = toasts.show(.pressAgain(shortcut: "⌘T", title: "New Tab"), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("shortcut toast refused")
        }
        toasts.dismissShortcutToasts()
        check(cue.isRetiring && toasts.current == nil, "a shortcut toast retires on a binding change")
        check(shared.isEmpty, "presenting never shares")

        let framed = PArcToastPresentation(content: .standard("Framed"), theme: SpaceTheme())
        check(framed.present(in: parent, over: pane), "framing owner admitted")
        let framedRect = framed.window?.frame
        parent.setFrame(NSRect(origin: parent.frame.origin, size: NSSize(width: 1100, height: 760)), display: false)
        check(framed.window?.frame == framedRect, "the child keeps its first frame")
        framed.dismiss(animated: false)

        for name in [NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            let toast = PArcToastPresentation(content: .standard("Closes"), theme: SpaceTheme())
            check(toast.present(in: parent, over: pane), "\(name.rawValue) owner admitted")
            NotificationCenter.default.post(name: name, object: parent)
            check(toast.isRetiring && toast.window == nil, "\(name.rawValue) closes the toast")
        }

        func luminance(_ color: NSColor) -> CGFloat {
            let c = color.usingColorSpace(.sRGB) ?? color
            func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        for (appearance, hex) in [(NSAppearance.Name.darkAqua, "E4E2F7"), (.aqua, "1F1D33")] {
            parent.appearance = NSAppearance(named: appearance)
            let quote = PArcToastPresentation(content: .copiedQuoteLink(url), theme: .singleColor(ThemeColor(hex: hex)!))
            check(quote.present(in: parent, over: pane), "quote toast admitted")
            await drain(0.6)
            guard let rep = quote.bitmapImageRepForCachingDisplay(in: quote.bounds) else { preconditionFailure("no bitmap") }
            quote.cacheDisplay(in: quote.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / quote.bounds.width
            let card = quote.frames.body
            func contrast(xs: ClosedRange<CGFloat>, ys: ClosedRange<CGFloat>) -> CGFloat {
                guard let fill = rep.colorAt(x: Int((card.minX + 4) * scale), y: Int(card.midY * scale)) else { return 0 }
                let background = luminance(fill)
                var best: CGFloat = 1
                for y in stride(from: card.minY + ys.lowerBound, to: card.minY + ys.upperBound, by: 1 / scale) {
                    for x in stride(from: card.minX + xs.lowerBound, to: card.minX + xs.upperBound, by: 1 / scale) {
                        guard let pixel = rep.colorAt(x: Int(x * scale), y: Int(y * scale)) else { continue }
                        let value = luminance(pixel)
                        best = max(best, (max(value, background) + 0.05) / (min(value, background) + 0.05))
                    }
                }
                return best
            }
            let icon = contrast(xs: 12...30, ys: 14...card.height - 14)
            let subLabel = contrast(xs: 40...80, ys: 34...card.height - 12)
            check(icon >= 4.5, "\(appearance.rawValue): the quote icon takes the toast's ink (\(icon):1)")
            check(subLabel >= 4.5, "\(appearance.rawValue): the sub-label is readable (\(subLabel):1)")
            quote.dismiss(animated: false)
        }
        parent.appearance = nil

        let closing = PArcToastPresentation(content: .standard("Close"), theme: SpaceTheme())
        check(closing.present(in: parent, over: pane), "close owner admitted")
        parent.close()
        check(closing.isRetiring && closing.window == nil, "closing the parent retires the toast")
        check(!closing.present(in: parent, over: pane), "a retired toast cannot be presented again")
        print("Parc toast: \(assertions) assertions passed")
    }
}
