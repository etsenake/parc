import AppKit

@MainActor private final class InertWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}
@MainActor private final class MarkedEditor: NSTextView {
    override func hasMarkedText() -> Bool { true }
}

@main struct CaptureMotionChecks {
    @MainActor static func main() { exitOnFailure(runChecks) }
    @MainActor static func runChecks() {
        _ = NSApplication.shared
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); count += 1
        }
        let a = CGRect(x: 10, y: 20, width: 200, height: 100)
        let b = CGRect(x: 300, y: 200, width: 100, height: 80)
        let c = CGRect(x: 100, y: 40, width: 400, height: 200)
        var motion = CaptureLensMotion()
        motion.target(a, at: 0, animated: true)
        motion.target(b, at: 0.01, animated: true)
        check(motion.rect == a && motion.isAnimating, "A later target is throttled, not lost")
        motion.target(c, at: 0.02, animated: true)
        motion.tick(at: 0.08)
        check(motion.rect == a, "90 ms throttle keeps the current presentation")
        motion.tick(at: 0.1)
        check(motion.rect != a && motion.rect != b, "Latest target replaces pending intermediate geometry")
        let moving = motion.rect
        motion.target(b, at: 0.2, animated: true)
        check(motion.rect == moving, "Retargeting preserves the current presentation")
        for i in 21...300 { motion.tick(at: Double(i) / 100) }
        check(motion.rect == b && !motion.isAnimating, "The interrupted spring settles exactly on its last target")
        motion.target(c, at: 3.01, animated: true); motion.clear(); motion.tick(at: 4)
        check(motion.rect == nil && !motion.isAnimating, "Retirement destroys both pending and active movement")
        motion.target(a, at: 5, animated: true); motion.target(c, at: 5.01, animated: true); motion.settle(at: 5.02)
        check(motion.rect == c && !motion.isAnimating, "Reduce Motion settles the latest pending target")

        let window = InertWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
                                 styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 600)); window.contentView = host
        let first = NSButton(title: "First", target: nil, action: nil)
        let second = NSButton(title: "Second", target: nil, action: nil)
        host.addSubview(first); host.addSubview(second); window.makeFirstResponder(first)
        var valid = true
        let bookmark = CaptureFocusReturn(window: window, target: second, valid: { valid })
        window.key = false; bookmark.restore()
        check(window.firstResponder === first, "Background windows never acquire focus")
        window.key = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        check(window.firstResponder === second, "The original key window consumes its deferred return")
        window.makeFirstResponder(first); bookmark.restore()
        check(window.firstResponder === first, "Consumed focus return never runs twice")
        let expired = CaptureFocusReturn(window: window, target: second, valid: { valid })
        valid = false; expired.restore()
        check(window.firstResponder === first, "Retired owners cannot restore focus")
        valid = true
        let interrupted = CaptureFocusReturn(window: window, target: first, valid: { valid })
        window.makeFirstResponder(second); interrupted.restore()
        check(window.firstResponder === second, "User-intervening focus is preserved")

        let fieldOne = NSTextField(string: "first search"), fieldTwo = NSTextField(string: "other field")
        fieldOne.frame = CGRect(x: 0, y: 0, width: 150, height: 24)
        fieldTwo.frame = CGRect(x: 0, y: 30, width: 150, height: 24)
        host.addSubview(fieldOne); host.addSubview(fieldTwo); window.makeFirstResponder(fieldOne)
        let fieldBookmark = CaptureFocusReturn(window: window, target: fieldOne, valid: { valid })
        let sharedEditor = window.firstResponder
        window.makeFirstResponder(fieldTwo)
        check(window.firstResponder === sharedEditor, "The regression uses AppKit's shared native field editor")
        fieldBookmark.restore()
        check(fieldTwo.currentEditor() === window.firstResponder && fieldOne.currentEditor() == nil,
              "Changing the field-editor owner prevents stale search focus restoration")

        let overlay = PageCaptureOverlay(frame: host.bounds); host.addSubview(overlay)
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let pixels = context.makeImage()!
        overlay.showPreview(pixels); overlay.layoutSubtreeIfNeeded(); overlay.focusPreferredControl()
        let palette = overlay.palette, search = palette.view.search
        check(search.textField.currentEditor() === window.firstResponder, "Preview starts in the palette's native search editor")
        check(palette.isPresented && palette.card.superview === overlay && overlay.bounds.contains(palette.card.frame),
              "The palette is a Notes card inside the capture overlay")
        check(palette.card.frame.minX >= overlay.imageRect.maxX || palette.card.frame.maxX <= overlay.imageRect.minX
              || palette.card.frame.minY >= overlay.imageRect.maxY, "The palette sits beside the captured image")
        check(palette.view.list.highlightedItem == nil, "No row is filled before the pointer or keyboard picks one")
        check(overlay.nextKeyView == nil, "Preview keeps focus in the palette instead of a row key loop")
        check(palette.perform(#selector(NSResponder.insertTab(_:)), in: .main, editor: nil), "Tab stays in the palette like Notes menus")
        overlay.setEaselDestinations([CaptureEaselDestination(id: UUID(), title: "Moodboard", lastActive: nil)])
        check(palette.perform(#selector(NSResponder.moveDown(_:)), in: .main, editor: nil)
              && palette.highlightedRow?.id == "library", "The first arrow press highlights the first row")
        var outputs: [CapturePaletteAction] = []; overlay.onAction = { outputs.append($0) }
        let marked = MarkedEditor()
        let handled = palette.perform(#selector(NSResponder.insertNewline(_:)), in: .main, editor: marked)
        check(!handled && outputs.isEmpty, "IME composition never dispatches a capture destination")
        overlay.setLibrarySaved(true)
        check(search.textField.currentEditor() === window.firstResponder && palette.highlightedRow?.id == "library"
              && palette.highlightedRow?.isChecked == true, "Saving keeps the search focused and the same highlighted row")
        while palette.highlightedRow?.id != "easels" { _ = palette.perform(#selector(NSResponder.moveDown(_:)), in: .main, editor: nil) }
        check(palette.perform(#selector(NSResponder.moveRight(_:)), in: .main, editor: nil) && palette.hasSubmenu,
              "Right opens the Easel submenu beside its row")
        _ = palette.perform(#selector(NSResponder.cancelOperation(_:)), in: .submenu(.easels), editor: nil)
        check(!palette.hasSubmenu && search.textField.currentEditor() === window.firstResponder,
              "Escape closes just the submenu and returns to the palette search")
        overlay.setDestinationAvailability(library: false, easels: false)
        let privateTitles = palette.rows.map(\.title)
        check(privateTitles.contains("Copy") && privateTitles.contains("Save…") &&
              !privateTitles.contains("Save to Library") && !privateTitles.contains("Easel"),
              "Private capture only offers permitted output destinations")
        overlay.setOutputBusy(true)
        check(palette.rows.allSatisfy { !$0.isEnabled } && palette.view.statusText == "Finish or cancel in Messages.",
              "An open composer disables every row and says why")
        overlay.showSelection(); overlay.layoutSubtreeIfNeeded()
        check(!palette.isPresented, "Returning to selection dismisses the palette card")
        check(overlay.nextKeyView != nil && overlay.nextKeyView?.isHidden == false,
              "Returning to selection restores the capture controls' key loop")

        FrameSources.install()
        SystemOverrides.install()
        func lensTimers(_ body: () -> Void) -> [FrameSource] {
            FrameSources.scheduled(during: body).filter { $0.timer?.timeInterval == 1.0 / 60 }
        }
        func armed(_ timers: [FrameSource]) -> Bool { timers.contains(where: \.isLive) }
        let probe = PCNativePageCaptureTarget()
        let focusA = NSRect(x: 40, y: 50, width: 180, height: 100)
        let focusB = NSRect(x: 260, y: 140, width: 120, height: 90)
        SystemOverrides.reduceMotion = false
        check(!armed(lensTimers { overlay.setTarget(probe, rect: focusA) }), "First focus settles without arming the lens timer")
        check(lensTimers { for _ in 0..<40 { overlay.setTarget(probe, rect: focusA) } }.isEmpty,
              "Identical settled focus does not re-arm the 60 Hz timer")
        SystemOverrides.reduceMotion = true
        check(!armed(lensTimers { overlay.setTarget(probe, rect: focusB) }), "Reduce Motion settles retargets without a lens timer")
        SystemOverrides.reduceMotion = false
        let retarget = lensTimers { overlay.setTarget(probe, rect: focusA) }
        check(armed(retarget), "Retarget arms the lens timer while the spring runs")
        let deadline = Date(timeIntervalSinceNow: 2)
        while armed(retarget), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        check(!armed(retarget), "Settled spring idle-stops the lens timer")
        check(lensTimers { for _ in 0..<40 { overlay.setTarget(probe, rect: focusA) } }.isEmpty,
              "Identical settled focus stays idle after spring settle")
        let clearing = lensTimers { overlay.setTarget(probe, rect: focusB) }
        let armedBeforeClearing = armed(clearing)
        overlay.setTarget(nil, rect: nil)
        check(armedBeforeClearing && !armed(clearing), "Clearing focus idles a running lens timer")
        SystemOverrides.reduceMotion = nil

        overlay.retirePresentation(); overlay.removeFromSuperview()

        let layer = CALayer()
        CaptureMotion.reveal(layer, reduceMotion: false)
        check((layer.animation(forKey: "captureReveal") as? CABasicAnimation)?.duration == 1, "Real image reveal has the recovered one-second duration")
        CaptureMotion.reveal(layer, reduceMotion: true)
        check(layer.animationKeys()?.isEmpty != false, "Reduce Motion cancels an already-running reveal")
        var closed = 0
        SystemOverrides.reduceMotion = false
        let mediaPreview = DownloadLibraryPreview()
        mediaPreview.onClosed = { closed += 1 }
        let backdrop = mediaPreview.window!.contentView!
        let modal = backdrop.subviews[1]
        let live = modal.subviews[0], snapshot = modal.subviews[1]
        for view in [backdrop.subviews[0], modal, live, snapshot] {
            let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = 0; animation.toValue = 1; animation.duration = 5
            view.layer!.add(animation, forKey: "inertActiveTransition")
        }
        SystemOverrides.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        check([backdrop.subviews[0], modal, live, snapshot].allSatisfy { $0.layer?.animationKeys()?.isEmpty != false },
              "Enabling Reduce Motion cancels every external-preview transition layer")
        check(live.layer?.opacity == 1 && snapshot.layer?.opacity == 0, "External-preview settlement shows actual live content")
        mediaPreview.close()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        check(closed == 1, "Retired previews consume close once and remove the preference observer")
        SystemOverrides.reduceMotion = nil
        window.orderOut(nil)
        print("Capture motion/focus: \(count) assertions passed; no ordered window, browser, input posting or outgoing service.")
    }
}
