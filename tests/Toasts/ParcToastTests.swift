import AppKit

@MainActor private final class BandedAnchor: NSView, ParcToastAnchoring {
    override var isFlipped: Bool { true }
    var toastContentRect: NSRect { NSRect(x: 80, y: 42, width: bounds.width - 160, height: bounds.height - 54) }
}

@MainActor private final class ToastParent: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct ParcToastTests {
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

        check(ParcToastPlacement.windowFrame(for: NSRect(x: 100, y: 200, width: 1000, height: 800))
              == NSRect(x: 500, y: 400, width: 600, height: 600), "600-point child at the window's top right")
        check(ParcToastPlacement.contentFrame(for: NSRect(x: 300, y: 100, width: 600, height: 700))
              == NSRect(x: 300, y: 450, width: 600, height: 350), "content toast uses the upper half of its pane")
        check(ParcToastTiming.duration == 5 && ParcToastTiming.retirement == 1, "five-second toast, one-second retirement")

        let url = URL(string: "https://chatgpt.com/")!
        check(ParcToastContent.copiedCurrentURL(url).body
              == .standard(icon: nil, label: "Copied Current URL", subLabel: nil, buttons: [.share([url])]),
              "copyTabURL: label and share button for the copied URL")
        check(ParcToastContent.copiedCurrentURL(nil).body
              == .standard(icon: nil, label: "Copied Current URL", subLabel: nil, buttons: []),
              "no URL, no share button")
        check(ParcToastContent.copiedLinks([url, url]).body
              == .standard(icon: nil, label: "Copied Links", subLabel: nil, buttons: [.share([url, url])]),
              "copied links share every copied URL")
        check(ParcToastContent.copiedLinks([url]).body
              == .standard(icon: nil, label: "Copied Link", subLabel: nil, buttons: [.share([url])]),
              "a single copied link reads in the singular")
        check(ParcToastContent.copiedQuoteLink(url).body
              == .standard(icon: "quote.bubble.fill", label: "Copied Link", subLabel: "With Quote", buttons: [.share([url])]),
              "copyTabURLQuote: quote icon, sublabel and share button")
        check(ParcToastContent.cannotAddNewPane.body
              == .standard(icon: nil, label: "Cannot Add New Pane", subLabel: nil, buttons: []), "maxNumberPanes")
        check(ParcToastContent.pressAgain(shortcut: "⌘T", title: "New Tab").accessibilityText == "Press ⌘T again to New Tab",
              "Press Again keeps its spoken text")
        check(ParcToastContent.copiedQuoteLink(url).accessibilityText == "Copied Link, With Quote", "label and sublabel are announced")
        check(ParcToastContent.pressAgain(shortcut: "⌘T", title: "New Tab").showsShortcut
              && !ParcToastContent.copiedCurrentURL(url).showsShortcut, "only shortcut content shows a shortcut")
        func label(_ content: ParcToastContent) -> String? {
            if case .standard(_, let label, _, _) = content.body { return label } else { return nil }
        }
        check(label(.copiedImage) == "Copied Image", "captureCopied")
        check(ParcToastContent.copiedFile([url]).body
              == .standard(icon: nil, label: "Copied File", subLabel: nil, buttons: [.share([url])]), "copyFile shares the file")
        check(label(.zoom(percent: 110)) == "110%", "zoomChanged is the percentage")
        check(label(.fullScreenExit(shortcut: "⎋")) == "To exit full screen, press ⎋.", "didEnterFullScreen names the exit binding")
        check(label(.archiveCleared) == "Archive Cleared", "archiveCleared")
        func failed(_ names: String..., in profile: String? = nil) -> [ParcToastContent.FailedExtension] {
            names.map { .init(name: $0, profile: profile) }
        }
        check(ParcToastContent.extensionsNotApplied(added: failed("iCloud Passwords"), removed: []).body
              == .standard(icon: nil, label: "Couldn’t add iCloud Passwords", subLabel: nil, buttons: []),
              "a failed setup install names the extension")
        check(ParcToastContent.extensionsNotApplied(added: [], removed: failed("AdBlock")).body
              == .standard(icon: nil, label: "Couldn’t remove AdBlock", subLabel: nil, buttons: []),
              "an imported ad blocker that stayed is named")
        check(ParcToastContent.extensionsNotApplied(added: failed("A", "B"), removed: failed("AdBlock", "Ghostery")).body
              == .standard(icon: nil, label: "Couldn’t add 2 extensions", subLabel: "Couldn’t remove 2 ad blockers", buttons: []),
              "both failures share one notice, counted when several")
        check(ParcToastContent.extensionsNotApplied(added: failed("iCloud Passwords"), removed: failed("AdBlock")).accessibilityText
              == "Couldn’t add iCloud Passwords, Couldn’t remove AdBlock", "both lines are announced")
        check(ParcToastContent.extensionsNotApplied(added: failed("uBlock Origin Lite"), removed: [], retry: true).body
              == .standard(icon: nil, label: "Couldn’t add uBlock Origin Lite", subLabel: nil, buttons: [.retry]),
              "a notice whose changes can be retried carries a Retry button")
        func removal(_ profiles: String...) -> String? {
            label(.extensionsNotApplied(added: [], removed: profiles.flatMap { failed("AdBlock", in: $0) }))
        }
        check(removal("Work") == "Couldn’t remove AdBlock from Work"
              && removal("Work", "School") == "Couldn’t remove AdBlock from Work and School"
              && removal("Work", "School", "Home") == "Couldn’t remove AdBlock from Work, School and Home"
              && removal("Work", "School", "Home", "Lab", "Club") == "Couldn’t remove AdBlock from Work, School and 3 more",
              "one blocker that stayed in several Profiles names them, briefly")
        check(label(.extensionsNotApplied(added: [], removed: failed("AdBlock", in: "Work") + failed("Ghostery", in: "School")))
              == "Couldn’t remove 2 ad blockers", "several blockers are counted, not listed with their Profiles")
        check(label(.extensionsNotApplied(added: failed("uBlock Origin Lite", in: "Work"), removed: []))
              == "Couldn’t add uBlock Origin Lite to Work", "an add names its Profile with “to”")
        func kept(_ reason: ParcToastContent.FailedExtension.Reason, _ names: String...,
                  removing: Bool = true) -> ParcToastContent.Body {
            let failures = names.map { ParcToastContent.FailedExtension(name: $0, profile: "Work", reason: reason) }
            return ParcToastContent.extensionsNotApplied(added: removing ? [] : failures, removed: removing ? failures : []).body
        }
        check(kept(.otherApp, "AdBlock") == .standard(icon: nil, label: "Couldn’t remove AdBlock from Work",
                                                      subLabel: "Kept installed by another app", buttons: [])
              && kept(.administrator, "AdBlock", "Ghostery") == .standard(icon: nil, label: "Couldn’t remove 2 ad blockers",
                                                                         subLabel: "Kept installed by your administrator", buttons: [])
              && kept(.administrator, "Grammarly", removing: false) == .standard(icon: nil, label: "Couldn’t add Grammarly to Work",
                                                                                subLabel: "Blocked by your administrator", buttons: [])
              && kept(.parentalApproval, "Grammarly", removing: false) == .standard(icon: nil, label: "Couldn’t add Grammarly to Work",
                                                                                   subLabel: "Needs a parent’s approval", buttons: [])
              && kept(.blocklisted, "Grammarly", removing: false) == .standard(icon: nil, label: "Couldn’t add Grammarly to Work",
                                                                              subLabel: "Flagged as unsafe", buttons: []),
              "a change that can never work says why instead of inviting a retry")
        let mixed = ParcToastContent.extensionsNotApplied(added: [.init(name: "Grammarly")],
                                                          removed: [.init(name: "AdBlock", reason: .otherApp)])
        check(mixed.body == .standard(icon: nil, label: "Couldn’t add Grammarly", subLabel: "Couldn’t remove AdBlock", buttons: []),
              "a reason only replaces the second line when it covers the whole notice")
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
        let toasts = ParcToastPresenter(share: { urls, _ in shared.append(urls) })
        check(toasts.show(.copiedCurrentURL(url), in: parent, over: pane, theme: SpaceTheme()) == nil,
              "a hidden parent presents nothing")
        parent.orderBack(nil)
        let paneScreen = parent.convertToScreen(pane.convert(pane.bounds, to: nil))
        check(ParcToastPresentation.frame(in: parent, over: pane) == ParcToastPlacement.contentFrame(for: paneScreen),
              "a pane anchor uses that pane, not the window")
        check(ParcToastPresentation.frame(in: parent, over: nil) == ParcToastPlacement.windowFrame(for: parent.frame),
              "window location uses the window's top right")
        pane.isHidden = true
        check(ParcToastPresentation.frame(in: parent, over: pane) == ParcToastPlacement.windowFrame(for: parent.frame),
              "a hidden pane falls back to the window, as the delegate's nil frame does")
        let peekHost = BandedAnchor(frame: NSRect(x: 160, y: 10, width: 820, height: 660))
        root.addSubview(peekHost)
        let peekContent = parent.convertToScreen(peekHost.convert(peekHost.toastContentRect, to: nil))
        check(ParcToastPresentation.frame(in: parent, over: peekHost) == ParcToastPlacement.contentFrame(for: peekContent),
              "an anchor with a content region frames that region, inside a Peek's card")
        peekHost.removeFromSuperview()
        pane.isHidden = false

        var retired = 0
        guard let first = toasts.show(.copiedCurrentURL(url), in: parent, over: pane, theme: SpaceTheme(),
                                      onRetire: { retired += 1 }),
              let panel = parent.childWindows?.first else { preconditionFailure("missing toast child") }
        check(toasts.current === first && panel.parent === parent && panel.contentView === first, "exact child ownership")
        check(panel.frame == ParcToastPlacement.contentFrame(for: paneScreen), "the child covers the pane's upper half")
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
        check(second.window?.frame == ParcToastPlacement.windowFrame(for: parent.frame), "window toast at the window's top right")
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

        let timed = ParcToastPresentation(content: .standard("Timed"), theme: SpaceTheme(), duration: 0.3)
        check(timed.present(in: parent, over: pane), "short-lived toast admitted")
        await drain(0.5)
        check(timed.isRetiring, "an unhovered timer tick dismisses")
        timed.dismiss(animated: false)

        let held = ParcToastPresentation(content: .standard("Held"), theme: SpaceTheme(), duration: 1)
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

        check(!ParcToastScroll.dismisses(window: parent, deltaX: 0, deltaY: 0, owners: [parent]), "zero distance keeps")
        check(ParcToastScroll.dismisses(window: parent, deltaX: 0, deltaY: -2, owners: [parent]), "scrolling the parent dismisses")
        check(!ParcToastScroll.dismisses(window: nil, deltaX: 3, deltaY: 0, owners: [parent]), "a scroll elsewhere keeps")
        let scrolled = ParcToastPresentation(content: .standard("Scroll"), theme: SpaceTheme())
        check(scrolled.present(in: parent, over: pane), "scroll owner admitted")
        scrolled.scrolled(in: parent, deltaX: 0, deltaY: 0)
        check(!scrolled.isRetiring, "resting fingers keep the toast")
        scrolled.scrolled(in: parent, deltaX: 0, deltaY: 4)
        check(scrolled.isRetiring, "a real scroll dismisses")
        scrolled.dismiss(animated: false)

        var retiringWhenTapped: Bool?
        var tapped: ParcToastPresentation?
        tapped = ParcToastPresentation(content: .standard("Tab moved! Click to go there."), theme: SpaceTheme(),
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

        let framed = ParcToastPresentation(content: .standard("Framed"), theme: SpaceTheme())
        check(framed.present(in: parent, over: pane), "framing owner admitted")
        let framedRect = framed.window?.frame
        parent.setFrame(NSRect(origin: parent.frame.origin, size: NSSize(width: 1100, height: 760)), display: false)
        check(framed.window?.frame == framedRect, "the child keeps its first frame")
        framed.dismiss(animated: false)

        for name in [NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            let toast = ParcToastPresentation(content: .standard("Closes"), theme: SpaceTheme())
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
            let quote = ParcToastPresentation(content: .copiedQuoteLink(url), theme: .singleColor(ThemeColor(hex: hex)!))
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

        var retries = 0
        var retiringWhenRetried: Bool?
        var retrying: ParcToastPresentation?
        retrying = ParcToastPresentation(content: .extensionsNotApplied(added: failed("AdBlock"), removed: [], retry: true),
                                         theme: SpaceTheme(), onRetry: { retries += 1; retiringWhenRetried = retrying?.isRetiring })
        check(retrying?.present(in: parent, over: nil) == true, "retry owner admitted")
        retrying?.performRetry()
        retrying?.performRetry()
        check(retries == 1 && retiringWhenRetried == true, "Retry dismisses the notice before retrying, once")
        retrying?.dismiss(animated: false)

        var idle = 0
        toasts.onIdle = { idle += 1 }
        guard let natural = toasts.show(.standard("Natural"), in: parent, over: nil, theme: SpaceTheme(), duration: 0.3) else {
            preconditionFailure("idle owner refused")
        }
        await drain(0.5)
        check(natural.isRetiring && toasts.current == nil && idle == 1, "a toast that runs its course leaves the window idle")
        natural.dismiss(animated: false)
        guard let replaced = toasts.show(.standard("Replaced"), in: parent, over: nil, theme: SpaceTheme()),
              let replacement = toasts.show(.standard("Replacement"), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("replacement owners refused")
        }
        check(replaced.isRetiring && idle == 1, "a replaced toast doesn't count as finished")
        NotificationCenter.default.post(name: NSWindow.willMiniaturizeNotification, object: parent)
        check(replacement.isRetiring && toasts.current == nil && idle == 1, "a toast the window sweeps away doesn't either")
        replaced.dismiss(animated: false)
        guard let scrolledAway = toasts.show(.standard("Scrolled"), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("scroll owner refused")
        }
        scrolledAway.scrolled(in: parent, deltaX: 0, deltaY: 3)
        check(idle == 2, "scrolling a toast away finishes it")
        scrolledAway.dismiss(animated: false)
        var presenterRetries = 0
        guard let retriedNotice = toasts.show(.extensionsNotApplied(added: failed("AdBlock"), removed: [], retry: true),
                                              in: parent, over: nil, theme: SpaceTheme(), onRetry: { presenterRetries += 1 }) else {
            preconditionFailure("retry notice refused")
        }
        retriedNotice.performRetry()
        check(presenterRetries == 1 && toasts.current == nil && idle == 3, "Retry finishes the notice and leaves the window idle")
        retriedNotice.dismiss(animated: false)
        guard let swept = toasts.show(.standard("Swept"), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("sweep owner refused")
        }
        toasts.dismiss(animated: false)
        check(swept.isRetiring && idle == 3, "a dismissal from outside doesn't finish it")
        toasts.onIdle = nil

        var waiting = ["First", "Second"], restored: [String] = [], eligible = false, front = true
        let lifetimes: [String: TimeInterval] = ["First": 0.3]
        let queue = ParcToastQueue(presenter: toasts, next: {
            guard !waiting.isEmpty else { return nil }
            let text = waiting.removeFirst()
            return .init(content: .standard(text), restore: { restored.append(text); waiting.insert(text, at: 0) })
        }, present: { item in
            let text = label(item.content) ?? ""
            return toasts.show(item.content, in: parent, over: nil, theme: SpaceTheme(), duration: lifetimes[text] ?? 30,
                               onRetry: item.onRetry)
        })
        queue.canShow = { eligible }
        queue.isFront = { front }
        toasts.onIdle = { queue.showNextWhenIdle() }
        func showing() -> String? { toasts.current.flatMap { label($0.state.content) } }
        queue.showNext()
        check(showing() == nil && waiting == ["First", "Second"], "a window that can't show notices takes none")
        eligible = true
        queue.showNext()
        check(showing() == "First" && waiting == ["Second"], "the first waiting notice shows")
        queue.showNext()
        check(showing() == "First" && waiting == ["Second"], "the next one is held back while the first is showing")
        await drain(0.6)
        check(showing() == "Second" && waiting.isEmpty, "once the first finishes on its own, the held notice follows")
        waiting = ["Third"]
        guard let ordinary = toasts.show(.copiedImage, in: parent, over: nil, theme: SpaceTheme(), duration: 30) else {
            preconditionFailure("ordinary toast refused")
        }
        queue.showNextWhenIdle()
        await drain(0.05)
        check(toasts.current === ordinary && waiting == ["Third"],
              "a notice replaced by an ordinary toast doesn't count as finished, and the next waits while that toast shows")
        ordinary.scrolled(in: parent, deltaX: 0, deltaY: 3)
        await drain(0.05)
        check(showing() == "Third" && waiting.isEmpty, "when the ordinary toast finishes, the waiting notice follows")
        front = false
        waiting = ["Fourth"]
        toasts.current?.scrolled(in: parent, deltaX: 0, deltaY: 3)
        await drain(0.05)
        check(toasts.current == nil && waiting == ["Fourth"], "a window that isn't in front leaves the next notice waiting")
        front = true
        queue.showNext()
        check(showing() == "Fourth", "it shows when the window comes forward")
        toasts.dismiss(animated: false)
        queue.showNext()
        check(waiting.isEmpty && toasts.current == nil, "a notice swept away from outside lets the next show, with none left")
        parent.orderOut(nil)
        waiting = ["Fifth"]
        queue.showNext()
        check(restored == ["Fifth"] && waiting == ["Fifth"] && toasts.current == nil,
              "a notice no window could show goes back in line")
        parent.orderBack(nil)
        toasts.onIdle = nil

        func key(_ code: UInt16, _ characters: String = "", _ flags: NSEvent.ModifierFlags = [],
                 in window: NSWindow? = nil) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
        }
        func action(_ code: UInt16, _ characters: String = "", _ flags: NSEvent.ModifierFlags = []) -> ParcToastKeyboard.Action? {
            ParcToastKeyboard.action(for: key(code, characters, flags))
        }
        check(action(0, "a", [.command, .option, .shift]) == .focus && action(97, "", [.control, .function]) == .focus
              && action(0, "a", [.command]) == nil && action(97, "", [.function]) == nil,
              "Command-Option-Shift-A and Control-F6 move focus into a notice, and nothing else does")
        check(action(48, "\t") == .next && action(48, "\t", [.shift]) == .previous
              && action(124, "", [.numericPad, .function]) == .next && action(123, "", [.numericPad, .function]) == .previous
              && [UInt16(36), 76, 49].allSatisfy { action($0, " ") == .activate } && action(53, "\u{1b}") == .dismiss
              && action(36, "\r", [.command]) == nil,
              "Tab and the arrows move between actions, Space and Return press one, Escape dismisses")
        var keyboardShares: [NSPoint?] = [], keyboardRetries = 0
        let keyed = ParcToastPresentation(content: .standard("Couldn’t add Grammarly", buttons: [.share([url]), .retry]),
                                          theme: SpaceTheme(), duration: 0.3, onRetry: { keyboardRetries += 1 },
                                          share: { _, point in keyboardShares.append(point) })
        check(keyed.present(in: parent, over: nil), "keyboard owner admitted")
        guard let keyedPanel = keyed.window else { preconditionFailure("missing keyboard child") }
        check(!keyedPanel.canBecomeKey && !keyed.acceptsFirstResponder && keyed.state.focused == nil,
              "a notice never takes focus from the page when it appears")
        keyed.keyDown(with: key(53, "\u{1b}"))
        keyed.keyDown(with: key(36, "\r"))
        check(!keyed.isRetiring && keyboardRetries == 0 && keyed.state.focused == nil,
              "keys reaching a notice that wasn't given focus do nothing")
        check(keyed.keyboardTargets == [.button(0), .button(1)], "Share then Retry are the notice's keyboard stops")
        check(keyed.focusFromKeyboard() && keyed.state.focused == .button(0) && keyedPanel.canBecomeKey && keyed.acceptsFirstResponder,
              "focusing the notice lands on its first action")
        await drain(0.6)
        check(!keyed.isRetiring, "a notice with keyboard focus outlasts its timer, as it does under the pointer")
        keyed.keyDown(with: key(48, "\t"))
        check(keyed.state.focused == .button(1), "Tab moves to Retry")
        keyed.keyDown(with: key(48, "\t"))
        check(keyed.state.focused == .button(0), "and wraps back to Share")
        keyed.keyDown(with: key(123, "", [.numericPad, .function]))
        check(keyed.state.focused == .button(1), "the left arrow goes round to Retry")
        keyed.keyDown(with: key(48, "\t", [.shift]))
        check(keyed.state.focused == .button(0), "Shift-Tab comes back to Share")
        _ = keyedPanel.performKeyEquivalent(with: key(13, "w", [.command]))
        check(keyed.state.focused == nil && !keyedPanel.canBecomeKey && !keyed.isRetiring,
              "a Command shortcut ends the notice's keyboard session and leaves the notice up")
        keyed.focusFromKeyboard()
        keyed.keyDown(with: key(97, "", [.control, .function]))
        check(keyed.state.focused == nil && !keyed.isRetiring, "Control-F6 again goes back to the window")
        keyed.focusFromKeyboard()
        keyed.keyDown(with: key(49, " "))
        check(keyboardShares.count == 1 && keyboardShares[0].map { keyedPanel.frame.contains($0) } == true && !keyed.isRetiring,
              "Space on Share opens the share menu at the button and keeps the notice")
        keyed.keyDown(with: key(48, "\t"))
        keyed.keyDown(with: key(36, "\r"))
        check(keyboardRetries == 1 && keyed.isRetiring && keyed.state.focused == nil && !keyedPanel.canBecomeKey,
              "Return on Retry retries once and the notice lets go of focus")
        keyed.dismiss(animated: false)

        var escapedIdle = 0
        toasts.onIdle = { escapedIdle += 1 }
        guard let escaping = toasts.show(.copiedCurrentURL(url), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("escape owner refused")
        }
        check(escaping.focusFromKeyboard(), "a copy notice's Share can take keyboard focus")
        escaping.keyDown(with: key(53, "\u{1b}"))
        check(escaping.isRetiring && escapedIdle == 1 && toasts.current == nil,
              "Escape dismisses the focused notice, which counts as finishing it")
        guard let cancelled = toasts.show(.copiedCurrentURL(url), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("cancel owner refused")
        }
        cancelled.focusFromKeyboard()
        cancelled.cancelOperation(nil)
        check(cancelled.isRetiring && escapedIdle == 2, "Command-period dismisses it the same way")
        toasts.onIdle = nil
        guard let resigning = toasts.show(.copiedCurrentURL(url), in: parent, over: nil, theme: SpaceTheme(), duration: 0.3),
              let resigningPanel = resigning.window else { preconditionFailure("resign owner refused") }
        resigning.focusFromKeyboard()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: resigningPanel)
        check(resigning.state.focused == nil && !resigningPanel.canBecomeKey, "clicking elsewhere ends the notice's keyboard focus")
        await drain(0.5)
        check(resigning.isRetiring, "and its timer carries on")
        resigning.dismiss(animated: false)
        var keyboardTaps = 0
        let tappable = ParcToastPresentation(content: .tabRestored(to: "Work", selected: false), theme: SpaceTheme(),
                                             onTap: { keyboardTaps += 1 })
        check(tappable.present(in: parent, over: nil) && tappable.keyboardTargets == [.card] && tappable.focusFromKeyboard()
              && tappable.state.focused == .card, "a clickable notice takes focus as a whole")
        tappable.keyDown(with: key(36, "\r"))
        check(keyboardTaps == 1 && tappable.isRetiring, "Return clicks it")
        tappable.dismiss(animated: false)
        let quiet = ParcToastPresentation(content: .standard("Retry later", buttons: [.retry]), theme: SpaceTheme())
        check(quiet.present(in: parent, over: nil) && quiet.keyboardTargets.isEmpty && !quiet.focusFromKeyboard()
              && quiet.state.focused == nil, "a notice with nothing to press has nothing to focus")
        quiet.dismiss(animated: false)
        guard let monitored = toasts.show(.copiedCurrentURL(url), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("monitor owner refused")
        }
        check(!monitored.takesFocusShortcut(key(0, "a", [.command, .option, .shift])) && monitored.state.focused == nil
              && !monitored.takesFocusShortcut(key(0, "a", [.command], in: parent)),
              "the shortcut from another window, or another shortcut, leaves the notice alone")
        check(monitored.takesFocusShortcut(key(0, "a", [.command, .option, .shift], in: parent)) && monitored.state.focused == .button(0),
              "the shortcut pressed in the browser window moves focus into its notice")
        guard let viaF6 = toasts.show(.copiedCurrentURL(url), in: parent, over: nil, theme: SpaceTheme()) else {
            preconditionFailure("Control-F6 owner refused")
        }
        check(viaF6.takesFocusShortcut(key(97, "", [.control, .function], in: parent)) && viaF6.state.focused == .button(0),
              "Control-F6 does the same")
        viaF6.dismiss(animated: false)
        monitored.dismiss(animated: false)

        let closing = ParcToastPresentation(content: .standard("Close"), theme: SpaceTheme())
        check(closing.present(in: parent, over: pane), "close owner admitted")
        parent.close()
        check(closing.isRetiring && closing.window == nil, "closing the parent retires the toast")
        check(!closing.present(in: parent, over: pane), "a retired toast cannot be presented again")
        print("Parc toast: \(assertions) assertions passed")
    }
}
