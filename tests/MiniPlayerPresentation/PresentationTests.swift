import AppKit

@main @MainActor struct PresentationTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let deck = MiniPlayerDeck(frame: NSRect(x: 0, y: 0, width: 212, height: 150))
        window.contentView = deck
        func item(_ id: String) -> MiniPlayerItem {
            let page = PCNativePage(), state = PCNativeMediaState(identifier: id)
            page.mediaState = state
            return MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: {})
        }
        var needsRelink = false
        deck.onKeyViewsChanged = { needsRelink = true }
        let items = [item("a"), item("b"), item("c")]
        deck.update(items)
        deck.layoutSubtreeIfNeeded()
        var rows = descendants(deck).filter { String(describing: type(of: $0)) == "MiniPlayerRow" }
        check(rows.count == 3, "all three collapsed cards remain present")
        let layers = rows.map { $0.layer }
        check(layers.allSatisfy { $0 != nil }, "cards have backing layers")
        deck.needsLayout = true
        deck.layoutSubtreeIfNeeded()
        check(zip(rows, layers).allSatisfy { $0.layer === $1 }, "row reordering retains its backing layer")
        rows.sort { $0.frame.minY > $1.frame.minY }
        check(deck.desiredHeight == 69, "collapsed deck reserves 33 + two 7-point offsets and its accessibility header")
        check(rows.map { $0.frame.height } == [33, 33, 33], "collapsed card heights")
        check(rows[0].frame.minY - rows[1].frame.minY == 7 && rows[1].frame.minY - rows[2].frame.minY == 7, "stack offsets")
        check(rows[0].frame.width - rows[1].frame.width == 10 && rows[1].frame.width - rows[2].frame.width == 10, "stack widths")
        check(rows[0].acceptsFirstResponder && !rows[1].acceptsFirstResponder && !rows[2].acceptsFirstResponder, "only the front collapsed card accepts focus")
        let title = descendants(rows[0]).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Back to Tab" }!
        let previous = descendants(rows[0]).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Previous Track" }!
        let volumeCollapsed = descendants(rows[0]).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Adjust Tab Volume" }!
        check(title.isHidden, "collapsed chrome hides the title")
        check(!previous.isHidden && !volumeCollapsed.isHidden, "collapsed transport keeps previous, next and volume")
        let palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false)
        deck.palette = palette; deck.layoutSubtreeIfNeeded()
        let expand = descendants(deck).compactMap { $0 as? ActionButton }.first { $0.accessibilityLabel()?.hasPrefix("Show All") == true }!
        func installChain() -> [NSView] {
            deck.layoutSubtreeIfNeeded()
            let chain = SidebarAccessibility.keyViews(in: [deck], space: deck)
            SidebarAccessibility.link(chain, within: deck, exit: nil)
            needsRelink = false
            return chain
        }
        let collapsedChain = installChain()
        check(!collapsedChain.contains { $0 === rows[1] }, "rear card excluded from collapsed key chain")
        expand.actionBlock?()
        check(needsRelink, "expansion requests key-chain relink")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(rows.contains { $0.layer?.animation(forKey: "parc.media.position") != nil || $0.layer?.animation(forKey: "parc.media.bounds") != nil }, "expansion animates stacked card geometry")
            check(rows.contains { $0.layer?.animation(forKey: "parc.media.opacity") != nil }, "expansion animates stacked card opacity")
        }
        let otherWindow = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 400),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        otherWindow.contentView = deck
        check(rows.allSatisfy { $0.layer?.animation(forKey: "parc.media.position") == nil && $0.layer?.animation(forKey: "parc.media.bounds") == nil && $0.layer?.animation(forKey: "parc.media.opacity") == nil }, "window transfer settles deck animations")
        window.contentView = deck
        otherWindow.close()
        deck.frame.size.height = deck.desiredHeight
        let expandedChain = installChain()
        guard let rearIndex = expandedChain.firstIndex(where: { $0 === rows[1] }), rearIndex > 0 else {
            fatalError("expanded rear card missing from key chain")
        }
        check(expandedChain[rearIndex - 1].nextKeyView === rows[1], "expanded rear card is linked into the installed chain")
        rows = descendants(deck).filter { String(describing: type(of: $0)) == "MiniPlayerRow" }
        check(deck.desiredHeight == 230, "expanded deck uses three 66-point cards with 5-point gaps")
        check(rows.allSatisfy { $0.frame.height == 66 && $0.acceptsFirstResponder }, "expanded cards and focus")
        check(!title.isHidden, "hover/expanded chrome shows the title")
        let marquee = descendants(rows[0]).first { String(describing: type(of: $0)) == "MiniPlayerMarquee" }!
        let strip = marquee.subviews[0]
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(strip.layer?.animation(forKey: "marquee") == nil, "reduced motion keeps the title static")
        } else {
            guard let start = strip.layer?.animation(forKey: "marquee")?.beginTime else { fatalError("overflowing title must animate") }
            deck.palette = palette; deck.layoutSubtreeIfNeeded()
            check(strip.layer?.animation(forKey: "marquee")?.beginTime == start, "identical palette keeps marquee progress")
        }
        let slider = descendants(rows[0]).compactMap { $0 as? NSSlider }.first!
        let volumeButton = descendants(rows[0]).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Adjust Tab Volume" }!
        check(slider.alphaValue == 0 && slider.refusesFirstResponder && slider.isAccessibilityHidden(), "closed volume is not a key or accessibility target")
        check(slider.hitTest(NSPoint(x: slider.frame.midX, y: slider.frame.midY)) == nil, "closed volume refuses pointer targeting")
        volumeButton.actionBlock?()
        deck.layoutSubtreeIfNeeded()
        check(slider.alphaValue == 1 && !slider.refusesFirstResponder && !slider.isAccessibilityHidden(), "open volume is accessible")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(slider.layer?.animation(forKey: "parc.media.opacity") != nil, "volume opening fades")
        }
        volumeButton.actionBlock?()
        deck.layoutSubtreeIfNeeded()
        check(slider.alphaValue == 0 && slider.refusesFirstResponder && slider.isAccessibilityHidden(), "closed volume immediately stops accepting focus and AX")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(slider.layer?.animation(forKey: "parc.media.opacity") != nil, "volume closing fades")
        }
        volumeButton.actionBlock?()
        deck.layoutSubtreeIfNeeded()
        check(slider.alphaValue == 1, "volume reopened before capability loss")
        items[0].state.canSetVolume = false
        deck.update(items)
        deck.layoutSubtreeIfNeeded()
        check(slider.alphaValue == 0 && slider.refusesFirstResponder && slider.isAccessibilityHidden() && volumeButton.isHidden,
              "capability loss withdraws slider and its button together")
        items[0].state.canSetVolume = true
        deck.update(items); deck.layoutSubtreeIfNeeded()
        check(!volumeButton.isAccessibilityExpanded() && slider.alphaValue == 0, "restored volume reports collapsed")
        volumeButton.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(window.makeFirstResponder(slider), "off-screen slider accepts focus while open")
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 69 && window.firstResponder === rows[0], "focused slider collapse keeps the deck collapsed")
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        volumeButton.actionBlock?(); deck.layoutSubtreeIfNeeded()
        check(window.makeFirstResponder(slider), "off-screen slider can regain focus")
        deck.updateHover(false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: MiniPlayerMotion.hoverOffDelay + 0.1))
        check(deck.desiredHeight > 69, "hover-off waits while focus stays in the deck")
        _ = window.makeFirstResponder(nil)
        window.update(); deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 69, "focus departure completes the pending hover-off")
        expand.actionBlock?(); deck.layoutSubtreeIfNeeded()
        func closeFirst() {
            let row = descendants(deck).first { String(describing: type(of: $0)) == "MiniPlayerRow" }!
            let close = descendants(row).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Close Mini Player" }!
            close.actionBlock?(); deck.layoutSubtreeIfNeeded()
        }
        closeFirst(); closeFirst()
        deck.update([items[2], item("new")]); deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 62, "new episode after dismissal starts collapsed")
        deck.update([item("hover-a"), item("hover-b")])
        deck.updateHover(true); deck.layoutSubtreeIfNeeded()
        closeFirst()
        deck.updateHover(false)
        deck.update([item("fresh-a"), item("fresh-b")]); deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 62, "a later player after hover-off does not inherit expansion")
        var pipActions = 0, reveals = 0
        let pipPage = PCNativePage(), pipState = PCNativeMediaState(identifier: "pip")
        pipPage.mediaState = pipState
        pipPage.onAction = { if $0 == .enterPictureInPicture { pipActions += 1 } }
        deck.update([MiniPlayerItem(page: pipPage, state: pipState, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: { reveals += 1 })])
        deck.updateHover(true); deck.layoutSubtreeIfNeeded()
        let pipButton = descendants(deck).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Open Picture in Picture" }!
        pipButton.actionBlock?()
        check(pipActions == 1 && reveals == 0, "PiP control enters Picture in Picture instead of revealing the tab")
        deck.updateHover(false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: MiniPlayerMotion.hoverOffDelay + 0.1))
        _ = window.makeFirstResponder(nil)
        deck.layoutSubtreeIfNeeded()
        deck.update([item("only")])
        deck.frame.size.height = deck.desiredHeight
        deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 33, "single player starts compact")
        deck.updateHover(true)
        deck.frame.size.height = deck.desiredHeight
        deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 66, "hover expands title chrome")
        let onlyRow = descendants(deck).first { String(describing: type(of: $0)) == "MiniPlayerRow" }!
        let onlyVolume = descendants(onlyRow).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Adjust Tab Volume" }!
        let onlySlider = descendants(onlyRow).compactMap { $0 as? NSSlider }.first!
        onlyVolume.actionBlock?(); deck.frame.size.height = deck.desiredHeight; deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 99 && onlySlider.alphaValue == 1, "volume slider stays inside the hovered card")
        check(onlyVolume.onHover == nil, "hovering the volume button does not open it")
        func deliver(_ event: NSEvent) {
            NSApp.postEvent(event, atStart: false)
            while let next = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(next) }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            deck.frame.size.height = deck.desiredHeight; deck.layoutSubtreeIfNeeded()
        }
        func click(_ view: NSView) {
            let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                deliver(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
        }
        func escape() {
            deliver(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                     context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        }
        click(onlySlider)
        check(deck.desiredHeight == 99, "a click on the slider keeps the volume open")
        click(onlyVolume)
        check(deck.desiredHeight == 99, "a click on the volume button is left to its own toggle")
        let onlyTitle = descendants(onlyRow).compactMap { $0 as? ActionButton }.first { $0.parcTooltip?.label == "Back to Tab" }!
        let titlePoint = onlyTitle.convert(NSPoint(x: onlyTitle.bounds.midX, y: onlyTitle.bounds.midY), to: nil)
        NSApp.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: titlePoint, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        check(deck.desiredHeight == 99, "the deck keeps its frames while the click that closes the volume is dispatched")
        click(onlyTitle)
        check(deck.desiredHeight == 66 && onlySlider.alphaValue == 0, "a click elsewhere closes the volume")
        onlyVolume.actionBlock?(); deck.frame.size.height = deck.desiredHeight; deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 99, "volume reopens by click")
        escape()
        check(deck.desiredHeight == 66 && onlySlider.alphaValue == 0, "Escape closes the volume")
        onlyVolume.actionBlock?(); deck.frame.size.height = deck.desiredHeight; deck.layoutSubtreeIfNeeded()
        _ = window.makeFirstResponder(nil)
        deck.updateHover(false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: MiniPlayerMotion.hoverOffDelay + 0.1))
        deck.layoutSubtreeIfNeeded()
        check(deck.desiredHeight == 33 && onlySlider.alphaValue == 0, "hover-off returns to compact transport")
        window.close()
        checkAppearanceSwitch()
        print("Mini Player presentation checks passed")
    }
    /// The window's root rebuilds a theme-free palette inside its appearance
    /// callback, where AppKit still draws in the old appearance.
    final class Root: NSView {
        var onSwitch: (() -> Void)?
        override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onSwitch?() }
    }
    static func checkAppearanceSwitch() {
        NSApp.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 240, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = Root(frame: NSRect(x: 0, y: 0, width: 240, height: 100)), deck = MiniPlayerDeck(frame: NSRect(x: 0, y: 0, width: 212, height: 33))
        root.addSubview(deck); window.contentView = root
        func palette() -> ThemeChromePalette { ThemeChromePalette(theme: SpaceTheme(), appearance: root.effectiveAppearance) }
        root.onSwitch = { deck.palette = palette() }
        deck.palette = palette()
        let page = PCNativePage(), state = PCNativeMediaState(identifier: "switch")
        page.mediaState = state
        deck.update([MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: {})])
        deck.layoutSubtreeIfNeeded()
        let surface = descendants(deck).first { String(describing: type(of: $0)) == "MiniPlayerSurface" }!
        func luminance() -> CGFloat {
            surface.layer?.backgroundColor?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components?.first ?? -1
        }
        check(luminance() > 0.9, "a theme-free card starts light in light mode")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        check(luminance() < 0.3, "a theme-free card turns dark when the app switches to dark mode")
        NSApp.appearance = nil
        window.close()
    }
}
