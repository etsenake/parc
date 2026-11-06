import AppKit

///
/// with optional keycaps, presented by `TooltipController` for any view that
///
struct TooltipConfiguration: Equatable {
    ///
    enum Anchor: Int, CaseIterable {
        case top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing, cursor
    }
    enum Behavior: Equatable {
        /// Shown `delay` seconds after the pointer stops over the view.
        case onMouseIdle(delay: TimeInterval)
        case immediate
    }
    enum Shortcut: Equatable {
        case fixed(KeyboardShortcut)
        /// A registry command's live binding, read each time the tooltip is shown.
        case command(String)
    }
    enum Style: Equatable {
        /// The label as plain text (`StandardTooltipContentView`'s content).
        case standard
        ///
        /// most four lines over an optional, dimmer subtitle.
        case label(subtitle: String?)
        ///
        ///
        /// `ProfileIndicatorView` in the keycap colours.
        case dockItem(profileName: String?)
    }

    static let defaultMaxWidth: CGFloat = 296

    var label: String
    var style: Style
    var shortcut: Shortcut?
    var anchor: Anchor
    var behavior: Behavior
    /// Nil is `defaultMaxWidth`.
    var maxWidth: CGFloat?
    /// Modifiers that may be held without blocking presentation.
    var allowedModifierKeys: NSEvent.ModifierFlags
    /// Nil takes the window's Space-theme palette, or the neutral one.
    var palette: TooltipColorPalette?
    ///
    ///
    var requiresShortcut: Bool
    /// The anchor's rect in the view's bounds coordinates; nil is the bounds.
    /// For a view that draws its tooltipped parts instead of hosting them as
    /// subviews.
    var anchorRect: CGRect?

    ///
    init(_ label: String, style: Style = .standard, shortcut: Shortcut? = nil, anchor: Anchor = .bottomTrailing,
         behavior: Behavior = .onMouseIdle(delay: 0.45), maxWidth: CGFloat? = nil,
         allowedModifierKeys: NSEvent.ModifierFlags = [], palette: TooltipColorPalette? = nil,
         requiresShortcut: Bool = false, anchorRect: CGRect? = nil) {
        self.label = label; self.style = style; self.shortcut = shortcut; self.anchor = anchor; self.behavior = behavior
        self.maxWidth = maxWidth; self.allowedModifierKeys = allowedModifierKeys; self.palette = palette
        self.requiresShortcut = requiresShortcut; self.anchorRect = anchorRect
    }
}

///
///
struct TooltipColorPalette: Equatable {
    struct Color: Equatable {
        var light: NSColor
        var dark: NSColor
        init(light: NSColor, dark: NSColor) { self.light = light; self.dark = dark }
        init(_ color: NSColor) { light = color; dark = color }
        func resolved(dark isDark: Bool) -> NSColor { isDark ? dark : light }
    }
    var title: Color
    var background: Color
    /// The raised keycap face.
    var keyForeground: Color
    /// The keycap body and the lip below its face.
    var keyBackground: Color
    var keyTitle: Color

    init(title: Color, background: Color, keyForeground: Color, keyBackground: Color, keyTitle: Color) {
        self.title = title; self.background = background
        self.keyForeground = keyForeground; self.keyBackground = keyBackground; self.keyTitle = keyTitle
    }

    ///
    /// for windows without a theme palette.
    static let neutral: TooltipColorPalette = {
        func gray(_ white: CGFloat) -> NSColor {
            NSColor(colorSpace: .extendedSRGB, components: [white, white, white, 1], count: 4)
        }
        return TooltipColorPalette(title: Color(light: gray(0), dark: gray(1)),
                                   background: Color(light: gray(1), dark: gray(0.17)),
                                   keyForeground: Color(light: gray(0.9), dark: gray(0.28)),
                                   keyBackground: Color(light: gray(0.66), dark: gray(0.45)),
                                   keyTitle: Color(light: gray(0), dark: gray(1)))
    }()

    ///
    /// keep the semantic palette's light/dark split; the key colours take the
    /// light palette's hover, focus and maxContrastColor in both appearances.
    /// A theme without colour has no themed semantic palette in Parc
    /// (ThemeChromePalette falls back to system colours), so it keeps the
    /// neutral palette.
    init(theme: SpaceTheme) {
        guard theme.isValid, theme.primaryColor != nil else { self = .neutral; return }
        let light = ThemeChromePalette(theme: theme, isDark: false)
        let dark = ThemeChromePalette(theme: theme, isDark: true)
        self.init(title: Color(light: light.title, dark: dark.title),
                  background: Color(light: light.background, dark: dark.background),
                  keyForeground: Color(light.hover), keyBackground: Color(light.focus),
                  keyTitle: Color(light.maxContrastColor))
    }
}

///
struct TooltipKeycap: Equatable {
    enum Trigger: Equatable {
        case modifier(NSEvent.ModifierFlags)
        case key(String)
    }
    let glyph: String
    let trigger: Trigger

    ///
    static let modifierOrder: [(flag: NSEvent.ModifierFlags, symbol: String)] =
        [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]

    static func keycaps(for shortcut: KeyboardShortcut) -> [TooltipKeycap] {
        modifierOrder.filter { shortcut.flags.contains($0.flag) }.map { TooltipKeycap(glyph: $0.symbol, trigger: .modifier($0.flag)) }
            + [TooltipKeycap(glyph: glyph(forKey: shortcut.key), trigger: .key(shortcut.key))]
    }

    ///
    /// the Essentials keycaps' key text, which spells Tab out.
    static func glyph(forKey key: String) -> String {
        KeyboardShortcut(key: key, flags: []).keycapSymbols.last!
    }

    ///
    func isPressed(modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        switch trigger {
        case .modifier(let flag): return modifiers.contains(flag)
        case .key(let key): return characters.map { $0.lowercased() == key.lowercased() } ?? false
        }
    }
}

///
/// 3 on the corner that points at a diagonal anchor or the cursor.
struct TooltipCorners: Equatable {
    var topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat

    static let radius: CGFloat = 14, anchorRadius: CGFloat = 3

    init(topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        self.topLeft = topLeft; self.topRight = topRight; self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }

    init(anchor: TooltipConfiguration.Anchor) {
        let r = Self.radius, a = Self.anchorRadius
        switch anchor {
        case .top, .bottom, .leading, .trailing: self.init(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
        case .topLeading: self.init(topLeft: r, topRight: r, bottomRight: a, bottomLeft: r)
        case .topTrailing: self.init(topLeft: r, topRight: r, bottomRight: r, bottomLeft: a)
        case .bottomLeading: self.init(topLeft: r, topRight: a, bottomRight: r, bottomLeft: r)
        case .bottomTrailing, .cursor: self.init(topLeft: a, topRight: r, bottomRight: r, bottomLeft: r)
        }
    }

    /// A path in a top-left-origin (flipped) space, each radius limited to
    /// half the shorter side.
    func path(in rect: CGRect) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let tl = min(topLeft, limit), tr = min(topRight, limit), br = min(bottomRight, limit), bl = min(bottomLeft, limit)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: tr)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: br)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: bl)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: tl)
        path.closeSubpath()
        return path
    }
}

///
/// cast by the fill together with the first.
struct TooltipShadow: Equatable {
    /// SwiftUI's radius; the offset is in SwiftUI's y-down space.
    let radius: CGFloat
    let offset: CGSize
    let opacity: CGFloat

    static let standard = [TooltipShadow(radius: 2.5, offset: .zero, opacity: 0.18),
                           TooltipShadow(radius: 10, offset: CGSize(width: 0, height: 2.5), opacity: 0.15)]

    ///
    /// the largest offset plus three times the largest radius, 32.5 points.
    static var windowMargin: CGFloat {
        (standard.map { max(abs($0.offset.width), abs($0.offset.height)) }.max() ?? 0)
            + 3 * (standard.map(\.radius).max() ?? 0)
    }
}

///
///
enum TooltipTiming {
    static let presentDuration: CFTimeInterval = 0.05
    static let exitDuration: TimeInterval = 0.3
    static let cursorExitDuration: TimeInterval = 0.1
    /// Mouse down, scroll wheel and Escape.
    static let interruptionDuration: TimeInterval = 0.1
    static let shortcutDismissalDelay: TimeInterval = 0.25
    ///
    static let pointerStopDelay: TimeInterval = 0.08
    static let hitTestInterval: TimeInterval = 0.25
    static let cursorWarmInterval: TimeInterval = 0.6
    static let cursorWarmDelay: TimeInterval = 0.01
}

///
/// outside `allowed` is. The raw flags are compared unmasked, so Caps Lock
///
/// `.always` window behaviour (Picture in Picture, the Boosts editor) has no
/// Parc adopter.
enum TooltipEligibility {
    static func permits(pressedMouseButtons: Int, modifierFlags: NSEvent.ModifierFlags, allowed: NSEvent.ModifierFlags,
                        keyInParentChain: () -> Bool) -> Bool {
        guard pressedMouseButtons == 0, modifierFlags.subtracting(allowed).isEmpty else { return false }
        return keyInParentChain()
    }
}

/// TooltipController's presentation rules apart from AppKit: scheduling
///
///
///
/// decisions name; `Target` identifies a tooltipped view.
struct TooltipPresentationState<Target: Hashable> {
    enum Phase: Equatable {
        case tracking
        case scheduled(Target)
        case presented(Target)
    }
    enum Request: Equatable {
        case present
        case presentAfter(TimeInterval)
    }
    struct Fade: Equatable {
        var duration: TimeInterval
        var delay: TimeInterval = 0
    }
    enum Exit: Equatable {
        case keep
        case handOff(Target)
        case hide(Fade)
    }

    private(set) var phase = Phase.tracking
    /// A tooltip window is up or still fading out.
    private(set) var isShowing = false
    private(set) var lastDismissal = Date.distantPast

    var target: Target? {
        switch phase {
        case .tracking: return nil
        case .scheduled(let target), .presented(let target): return target
        }
    }
    var isScheduled: Bool { if case .scheduled = phase { return true }; return false }
    var isPresented: Bool { if case .presented = phase { return true }; return false }

    /// For an eligible view. While a window is up or fading, a view-anchored
    /// tooltip replaces it at once and a cursor-anchored one is not scheduled.
    mutating func schedule(_ target: Target, anchor: TooltipConfiguration.Anchor, behavior: TooltipConfiguration.Behavior,
                           now: Date) -> Request? {
        if isShowing { return anchor == .cursor ? nil : .present }
        switch behavior {
        case .immediate: return .present
        case .onMouseIdle(var delay):
            if anchor == .cursor, now.timeIntervalSince(lastDismissal) < TooltipTiming.cursorWarmInterval {
                delay = TooltipTiming.cursorWarmDelay
            }
            phase = .scheduled(target)
            return .presentAfter(delay)
        }
    }

    mutating func didPresent(_ target: Target) { phase = .presented(target); isShowing = true }
    /// A failed presentation closes any tooltip window.
    mutating func didFailToPresent() { phase = .tracking; isShowing = false }
    mutating func cancelSchedule() { if isScheduled { phase = .tracking } }

    /// MouseListener movement cancels a pending presentation; true when it did.
    mutating func pointerMoved() -> Bool {
        guard isScheduled else { return false }
        phase = .tracking
        return true
    }
    /// MouseListener's stop schedules the view under the pointer only while tracking.
    var schedulesWhenPointerStops: Bool { phase == .tracking }

    /// After a mouse exit: keep the tooltip while its view is still under the
    /// pointer, hand off to an enclosing tooltipped view under it, or hide.
    ///
    ///
    /// while a window is up or fading, so such a view is not handed off to:
    /// the tooltip hides and the next pointer stop schedules it.
    func exit(targetUnderPointer: Bool, enclosing: Target?, enclosingAnchor: TooltipConfiguration.Anchor?,
              anchor: TooltipConfiguration.Anchor) -> Exit {
        guard target != nil, !targetUnderPointer else { return .keep }
        if let enclosing, !(isShowing && enclosingAnchor == .cursor) { return .handOff(enclosing) }
        return .hide(Fade(duration: anchor == .cursor ? TooltipTiming.cursorExitDuration : TooltipTiming.exitDuration))
    }

    /// Cancels a pending presentation and returns the fade for a window that
    /// is up. Nothing happens when nothing is scheduled or shown. A scroll
    /// leaves no warm state for cursor tooltips.
    mutating func hide(_ fade: Fade, scrolled: Bool = false, now: Date) -> Fade? {
        guard isShowing || phase != .tracking else { return nil }
        lastDismissal = scrolled ? .distantPast : now
        phase = .tracking
        return isShowing ? fade : nil
    }

    /// Escape fades quickly and completing the shown shortcut fades after
    /// 0.25 s; other keys never dismiss, so the keycaps can show them.
    mutating func keyDown(escape: Bool, modifiers: NSEvent.ModifierFlags, characters: String?,
                          shortcut: KeyboardShortcut?, now: Date) -> Fade? {
        if escape { return hide(Fade(duration: TooltipTiming.interruptionDuration), now: now) }
        guard isPresented, let shortcut, modifiers.intersection(KeyboardShortcut.modifierMask) == shortcut.flags,
              characters?.lowercased() == shortcut.key.lowercased() else { return nil }
        return hide(Fade(duration: TooltipTiming.exitDuration, delay: TooltipTiming.shortcutDismissalDelay), now: now)
    }

    /// A fade-out finished. True when its window goes: no presentation
    /// replaced the tooltip while it faded.
    mutating func fadeDidFinish() -> Bool {
        guard !isPresented else { return false }
        isShowing = false
        return true
    }
}

///
/// top-left-origin space: y = 0 is the top of the window frame.
enum TooltipPlacement {
    static let edgeGap: CGFloat = 4
    static let cornerOverlap: CGFloat = 6
    static let cursorOffset: CGFloat = 12
    static let clampInset: CGFloat = 8

    static func origin(for anchor: TooltipConfiguration.Anchor, size: CGSize, anchorRect a: CGRect,
                       clamp c: CGRect, mouse: CGPoint) -> CGPoint {
        let w = size.width, h = size.height
        func clampedX(_ x: CGFloat) -> CGFloat { max(c.minX, min(c.maxX - w, x)) }
        switch anchor {
        case .top: return CGPoint(x: clampedX(a.midX - w / 2), y: a.minY - h - edgeGap)
        case .bottom: return CGPoint(x: clampedX(a.midX - w / 2), y: a.maxY + edgeGap)
        case .leading: return CGPoint(x: a.minX - w - edgeGap, y: a.midY - h / 2)
        case .trailing: return CGPoint(x: a.maxX + edgeGap, y: a.midY - h / 2)
        case .topLeading: return CGPoint(x: a.minX - w + cornerOverlap, y: a.minY - h + cornerOverlap)
        case .topTrailing: return CGPoint(x: a.maxX - cornerOverlap, y: a.minY - h + cornerOverlap)
        case .bottomLeading: return CGPoint(x: a.minX - w + cornerOverlap, y: a.maxY - cornerOverlap)
        case .bottomTrailing: return CGPoint(x: a.maxX - cornerOverlap, y: a.maxY - cornerOverlap)
        case .cursor: return CGPoint(x: mouse.x + cursorOffset, y: mouse.y + cursorOffset)
        }
    }

    /// The clamp region: the screen's part of the window, inset by 8.
    static func clampRegion(windowFrame: CGRect, screenFrame: CGRect) -> CGRect {
        let visible = windowFrame.intersection(screenFrame)
        guard !visible.isNull else { return .zero }
        return CGRect(x: visible.minX - windowFrame.minX, y: windowFrame.maxY - visible.maxY,
                      width: visible.width, height: visible.height).insetBy(dx: clampInset, dy: clampInset)
    }

    /// The screen holding most of the anchor's screen rect, which a window
    /// spanning displays may not share with its own `screen`; nil when none.
    static func screenIndex(containing anchor: CGRect, screens: [CGRect]) -> Int? {
        let areas = screens.map { screen -> CGFloat in
            let shared = screen.intersection(anchor)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    static func screenRect(_ rect: CGRect, windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + rect.minX, y: windowFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The preferred anchor's screen frame when it lies on the screen;
    /// otherwise the fitting candidate (the eight edges, then the cursor)
    /// whose centre is nearest the preferred frame's. Nil when none fits.
    static func screenFrame(preferred: TooltipConfiguration.Anchor, size: CGSize, anchorRect: CGRect, mouse: CGPoint,
                            windowFrame: CGRect, screenFrame: CGRect) -> CGRect? {
        let clamp = clampRegion(windowFrame: windowFrame, screenFrame: screenFrame)
        func frame(_ anchor: TooltipConfiguration.Anchor) -> CGRect {
            let origin = origin(for: anchor, size: size, anchorRect: anchorRect, clamp: clamp, mouse: mouse)
            return screenRect(CGRect(origin: origin, size: size), windowFrame: windowFrame)
        }
        let target = frame(preferred)
        var best: (frame: CGRect, distance: CGFloat)?
        for anchor in [preferred] + TooltipConfiguration.Anchor.allCases.filter({ $0 != preferred }) {
            let candidate = frame(anchor)
            guard screenFrame.contains(candidate) else { continue }
            let distance = hypot(candidate.midX - target.midX, candidate.midY - target.midY)
            if best.map({ distance < $0.distance }) ?? true { best = (candidate, distance) }
        }
        return best?.frame
    }
}
