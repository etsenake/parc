import AppKit

/// MiniPlayerDeck's keyboard stops and rings, the sidebar's minimal hook in the
/// media owner's view: every stop in the sidebar's chain draws a ring. The row
/// stays a stop (Return reveals its page, Space plays or pauses) and draws one
/// around its rounded card, and focusing it expands the deck; "Show All" and
/// the title take the sidebar's radius-5 ring; the transport buttons keep their
///
@main @MainActor struct SidebarMiniPlayerFocusTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard value() else { fatalError("SidebarMiniPlayerFocus: \(message)") }
    }
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = Flipped(frame: NSRect(x: 0, y: 0, width: 300, height: 400)); window.contentView = host
        let deck = MiniPlayerDeck(frame: NSRect(x: 8, y: 100, width: 212, height: 200)); host.addSubview(deck)
        var revealed: [String] = [], played: [String] = []
        func item(_ id: String) -> MiniPlayerItem {
            let page = PCNativePage(), state = PCNativeMediaState(identifier: id)
            page.mediaState = state; page.onAction = { played.append("\(id) \($0)") }
            return MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: { revealed.append(id) })
        }
        deck.update([item("a"), item("b")]); deck.layoutSubtreeIfNeeded()
        let rows = descendants(of: deck).filter { String(describing: type(of: $0)) == "MiniPlayerRow" }
            .sorted { $0.frame.minY > $1.frame.minY }
        check(rows.count == 2, "two players make two rows (\(rows.count))")
        check(rows[0].acceptsFirstResponder && !rows[1].acceptsFirstResponder && rows.allSatisfy { !$0.isHidden },
              "the visible rear card is not a collapsed keyboard stop")
        for row in rows {
            check(row.focusRingType == .exterior && row.focusRingMaskBounds == row.bounds,
                  "a player row has a ring over its bounds")
            check(filled(row, at: NSPoint(x: row.bounds.midX, y: row.bounds.midY)) && !filled(row, at: NSPoint(x: 1, y: 1)),
                  "the row's ring follows its rounded card")
        }
        let buttons = descendants(of: deck).compactMap { $0 as? ActionButton }
        check(buttons.count == 1 + 2 * 11, "the deck's expand button and each row's eleven buttons (\(buttons.count))")
        let expand = buttons.first { $0.accessibilityLabel()?.hasPrefix("Show All") == true }
        let titles = buttons.filter { $0.parcTooltip?.label == "Back to Tab" }
        check(expand != nil && titles.count == 2, "one Show All and a title per row")
        for button in buttons {
            let ringed = button === expand || titles.contains { $0 === button }
            if ringed {
                check(button.focusRingCornerRadius == 5 && button.focusRingType == .exterior && button.focusRingMaskBounds == button.bounds,
                      "\(button.accessibilityLabel() ?? "?") draws the sidebar's rounded ring over its bounds")
            } else {
                check(button.focusRingCornerRadius == nil && button.focusRingType == .exterior,
                      "\(button.parcTooltip?.label ?? "?") keeps its exterior ring")
            }
        }
        // Focusing the front card expands the deck to show every player.
        let collapsed = deck.desiredHeight
        check(window.makeFirstResponder(rows[0]) && window.firstResponder === rows[0], "a row takes focus")
        check(deck.desiredHeight > collapsed, "focusing a row expands the deck (\(collapsed) → \(deck.desiredHeight))")
        deck.layoutSubtreeIfNeeded()
        check(rows.allSatisfy(\.acceptsFirstResponder), "expanded rows are keyboard stops")
        let stops = SidebarAccessibility.keyViews(in: [deck], space: host)
        func index(_ view: NSView) -> Int? { stops.firstIndex { $0 === view } }
        check(stops.first === expand, "Show All leads the deck")
        check(rows.allSatisfy { row in
            guard let title = titles.first(where: { $0.isDescendant(of: row) }) else { return false }
            return index(row).flatMap { rowIndex in index(title).map { rowIndex < $0 } } == true
        }, "each expanded row is a stop ahead of its title")
        // Return on the focused row reveals its page; Space plays or pauses.
        rows[0].keyDown(with: key("\r", 36, window))
        check(revealed == ["a"], "Return on a focused row reveals its page (\(revealed))")
        rows[0].keyDown(with: key(" ", 49, window))
        check(played == ["a pause"], "Space on a focused row pauses it (\(played))")
        let close = buttons.first { $0.parcTooltip?.label == "Close Mini Player" && $0.isDescendant(of: rows[1]) }!
        _ = window.makeFirstResponder(close); close.keyDown(with: key("\r", 36, window))
        check(revealed == ["a", "b"], "Return on a focused control still reaches its row (\(revealed))")
        routeButton(window, host)
        window.close()
        print("Sidebar mini player focus checks: \(count) passed")
    }
    /// The transport's last button is Cast for a Chrome-identity page's
    /// castable player and AirPlay for a Safari-identity page's, and opens the
    /// matching chooser; it reads the session's state.
    static func routeButton(_ window: NSWindow, _ host: NSView) {
        let deck = MiniPlayerDeck(frame: NSRect(x: 8, y: 100, width: 212, height: 200)); host.addSubview(deck)
        let page = PCNativePage(), state = PCNativeMediaState(identifier: "route")
        page.mediaState = state
        let item = MiniPlayerItem(page: page, state: state, icon: nil, host: MiniPlayerHostLease(window), valid: { true }, reveal: {})
        func transport() -> [ActionButton] {
            deck.update([item]); deck.layoutSubtreeIfNeeded()
            return descendants(of: deck).compactMap { $0 as? ActionButton }
                .filter { button in
                    !button.isHidden && !["Close Mini Player", "Open Picture in Picture", "Back to Tab", "Show All"]
                        .contains { button.accessibilityLabel()?.hasPrefix($0) == true }
                }.sorted { $0.frame.minX < $1.frame.minX }
        }
        check(transport().last?.accessibilityLabel() == "Adjust Tab Volume", "no route button without devices")
        state.castState = .available
        guard let cast = transport().last else { return check(false, "a transport row") }
        check(cast.accessibilityLabel() == "Cast" && cast.image?.isTemplate == true, "Cast follows volume (\(cast.accessibilityLabel() ?? "?"))")
        cast.performClick(nil)
        check(page.chooserRequests == ["cast"] && cast.showsSelectedFill, "Cast opens Chromium's chooser and stays selected")
        state.castState = .connecting; state.castDeviceName = "Living Room TV"
        check(transport().last?.accessibilityLabel() == "Connecting to Living Room TV", "connecting names the receiver")
        state.castState = .connected
        let connected = transport().last
        check(connected?.accessibilityLabel() == "Casting to Living Room TV" && connected?.accessibilityValue() as? String == "Connected",
              "connected reads Casting to the receiver")
        page.dismissChooser?()
        check(!cast.showsSelectedFill, "closing the chooser releases the button")
        let castImage = cast.image
        state.castState = .unavailable; state.castDeviceName = nil; state.airPlayState = .available
        guard let airPlay = transport().last else { return check(false, "a transport row") }
        check(airPlay === cast && airPlay.accessibilityLabel() == "AirPlay" && airPlay.image !== castImage,
              "a Safari-identity page's player keeps AirPlay in the same place")
        airPlay.performClick(nil)
        check(page.chooserRequests == ["cast", "airplay"], "AirPlay opens the route list (\(page.chooserRequests))")
        deck.removeFromSuperview()
    }
    static func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }
    static func key(_ characters: String, _ code: UInt16, _ window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: code)!
    }
    /// Whether `view`'s focus-ring mask covers `point` (view coordinates).
    static func filled(_ view: NSView, at point: NSPoint) -> Bool {
        let size = view.bounds.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.black.setFill(); view.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return (bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? 0) > 0.5
    }
}

private class Flipped: NSView { override var isFlipped: Bool { true } }

// Stand-ins for the engine's media types (native_appkit_bridge.h).
enum PCNativeMediaAction { case play, pause, previousTrack, nextTrack, toggleMuted, toggleMicrophone, toggleCamera, enterPictureInPicture }
enum PCNativeAirPlayState { case unavailable, available, connecting, connected }
enum PCNativeCastState { case unavailable, available, connecting, connected }
@MainActor final class PCNativeMediaState {
    let identifier: String, title = "Song", sourceURL = "https://example.test/"
    let playing = true, canPlayPause = true, hasPreviousTrack = true, hasNextTrack = true, muted = false
    let volume = 1.0, canSetVolume = true, canToggleMicrophone = false, canToggleCamera = false
    let microphoneOn = false, cameraOn = false
    var airPlayState = PCNativeAirPlayState.unavailable, airPlayDeviceName: String? = nil
    var castState = PCNativeCastState.unavailable, castDeviceName: String? = nil
    init(identifier: String) { self.identifier = identifier }
}
@MainActor final class PCNativePage {
    var isClosed = false
    var mediaState: PCNativeMediaState?
    var onAction: ((PCNativeMediaAction) -> Void)?
    func performMediaAction(_ action: PCNativeMediaAction, state: PCNativeMediaState) -> Bool { onAction?(action); return true }
    func setMediaVolume(_ volume: Double, state: PCNativeMediaState) -> Bool { true }
    func dismissMediaState(_ state: PCNativeMediaState) -> Bool { true }
    func performMediaAction(_ action: PCNativeMediaAction, state: PCNativeMediaState, in window: NSWindow) -> Bool { onAction?(action); return true }
    func setMediaVolume(_ volume: Double, state: PCNativeMediaState, in window: NSWindow) -> Bool { true }
    func dismissMediaState(_ state: PCNativeMediaState, in window: NSWindow) -> Bool { true }
    var chooserRequests: [String] = []
    var dismissChooser: (() -> Void)?
    func showAirPlayPicker(for state: PCNativeMediaState, relativeTo rect: NSRect, of view: NSView, in window: NSWindow,
                           dismissed: @escaping () -> Void) -> Bool { chooserRequests.append("airplay"); dismissChooser = dismissed; return true }
    func showCastChooser(for state: PCNativeMediaState, relativeTo rect: NSRect, of view: NSView, in window: NSWindow,
                         dismissed: @escaping () -> Void) -> Bool { chooserRequests.append("cast"); dismissChooser = dismissed; return true }
}
