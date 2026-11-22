import AppKit
import SwiftUI
import ParcKit

@MainActor final class BoxOfThingsIconState: ObservableObject {
    @Published private(set) var isHovered = false
    @Published private(set) var twinkle1 = false
    @Published private(set) var twinkle2 = false
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }

    func hover(_ hovering: Bool, reduceMotion: Bool) {
        guard !reduceMotion else { return }
        isHovered = hovering
        twinkle1.toggle()
        after(0.15) { [weak self] in self?.twinkle1.toggle(); self?.twinkle2.toggle() }
        after(0.3) { [weak self] in self?.twinkle2.toggle() }
    }
}

struct BoxOfThingsIcon: View {
    @ObservedObject var state: BoxOfThingsIconState
    @Environment(\.colorScheme) private var colorScheme
    private let animation = Animation.spring(response: 0.5, dampingFraction: 1.0, blendDuration: 0)

    var body: some View {
        let hovered = state.isHovered, dark = colorScheme == .dark
        let t1 = state.twinkle1, t2 = state.twinkle2
        ZStack(alignment: .center) {
            artwork("glow")
                .scaleEffect(x: 0.275, y: 0.4)
                .offset(x: 0, y: -7)
                .animation(animation, value: hovered)
                .foregroundColor(.white.opacity(hovered ? 0.3 : 0))
                .blur(radius: 0.875)
                .opacity(dark ? 1 : 0)
            artwork("star")
                .rotationEffect(.radians(hovered ? 1.8325957145940461 : -0.15707963267948966))
                .offset(x: -2.5, y: hovered ? -4.5 : -3)
                .shadow(color: .white.opacity(dark && hovered ? 1 : 0), radius: 1)
                .animation(animation, value: hovered)
                .mask(Rectangle().frame(width: 28, height: 11).foregroundColor(.green).offset(x: 0, y: -8))
            artwork("triangle")
                .scaleEffect(t1 ? 0.15 : 1)
                .rotationEffect(.radians(hovered ? 1.4835298641951802 : 3.9269908169872414))
                .offset(x: hovered ? 6.5 : 4.5, y: hovered ? -5 : -3.5)
                .opacity(t1 ? 0.2 : 1)
                .shadow(color: .white.opacity(dark && hovered ? 1 : 0), radius: 1)
                .animation(animation, value: hovered)
            artwork("circle")
                .scaleEffect(t2 ? 0.1 : 1)
                .offset(x: hovered ? 3 : 2, y: hovered ? -10 : -7.5)
                .opacity(t2 ? 0.2 : 1)
                .shadow(color: .white.opacity(dark && hovered ? 1 : 0), radius: 2)
                .animation(animation, value: hovered)
            artwork("box")
                .offset(x: 0, y: 3.5)
                .opacity(0.9)
        }
        .shadow(color: .white.opacity(dark && hovered ? 0.2 : 0), radius: 2, x: 0, y: 0)
    }

    private func artwork(_ name: String) -> some View {
        Group {
            if let image = LibraryArtwork.boxOfThings(name) { Image(nsImage: image).renderingMode(.template) }
        }
    }
}

@MainActor package final class TranslucentItemState: ObservableObject {
    @Published var hovered = false
    @Published var pressed = false
    @Published var enabled = true
    @Published var colors: TranslucentButtonColors
    let icon = BoxOfThingsIconState()
    init(colors: TranslucentButtonColors) { self.colors = colors }
    var background: NSColor { colors.background(hovered: hovered, pressed: pressed, enabled: enabled) }
    var foreground: NSColor { colors.foreground(pressed: pressed, enabled: enabled) }
}

package struct TranslucentItemFace: View {
    @ObservedObject package var state: TranslucentItemState
    package init(state: TranslucentItemState) {
        self.state = state
    }
    package var body: some View {
        BoxOfThingsIcon(state: state.icon)
            .font(.system(size: 16, weight: .medium))
            .padding(.all, 8)
            .frame(width: 32, height: 32, alignment: .center)
            .background(Color(nsColor: state.background))
            .foregroundColor(Color(nsColor: state.foreground))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(state.pressed ? 0.95 : 1, anchor: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0).delay(0), value: state.pressed)
            .animation(.easeIn(duration: 0.1), value: state.hovered)
            .contentShape(Rectangle())
    }
}

@MainActor package final class LibraryRenderingHostingView<Content: View>: NSHostingView<Content> {
    package override func hitTest(_ point: NSPoint) -> NSView? { nil }
    package override var acceptsFirstResponder: Bool { false }
    package override func becomeFirstResponder() -> Bool { false }
    package override var canBecomeKeyView: Bool { false }
    package override func isAccessibilityElement() -> Bool { false }
    package override func accessibilityChildren() -> [Any]? { [] }
}

@MainActor open class TranslucentBoxOfThingsItem: NSView, Sendable {
    static let side: CGFloat = 32
    package let state: TranslucentItemState
    package var action: (() -> Void)?
    var colors: TranslucentButtonColors? { didSet { resolveColors() } }
    package private(set) var host: LibraryRenderingHostingView<AnyView>!
    private var tracking: NSTrackingArea?
    private var cursorArea: NSTrackingArea?
    private var tracksPress = false

    public init(colors: TranslucentButtonColors? = nil, action: (() -> Void)? = nil) {
        self.colors = colors
        self.action = action
        state = TranslucentItemState(colors: colors ?? .standard(dark: false))
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        install(AnyView(TranslucentItemFace(state: state)))
        setAccessibilityElement(false)
        resolveColors()
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    package func install(_ content: AnyView) {
        host?.removeFromSuperview()
        let view = LibraryRenderingHostingView(rootView: content)
        view.sizingOptions = []
        view.frame = bounds; view.autoresizingMask = [.width, .height]
        addSubview(view); host = view
    }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { false }
    public override func becomeFirstResponder() -> Bool { false }
    public override var canBecomeKeyView: Bool { false }
    open override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); resolveColors() }
    private func resolveColors() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let resolved = colors ?? .standard(dark: dark)
        if state.colors != resolved { state.colors = resolved }
    }

    open var buttonRect: NSRect { bounds }
    var iconHoverRect: NSRect {
        let button = buttonRect
        return button.intersection(NSRect(x: button.midX - 40.5, y: button.midY - 13.5, width: 81, height: 27))
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
        if let cursorArea { removeTrackingArea(cursorArea) }
        cursorArea = NSTrackingArea(rect: buttonRect, options: [.cursorUpdate, .activeInKeyWindow], owner: self)
        addTrackingArea(cursorArea!)
    }
    var showsPointingHand: Bool { state.enabled }
    public override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if showsPointingHand, buttonRect.contains(point) { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }
    public override func mouseEntered(with event: NSEvent) { pointerMoved(to: convert(event.locationInWindow, from: nil)) }
    public override func mouseMoved(with event: NSEvent) { pointerMoved(to: convert(event.locationInWindow, from: nil)) }
    public override func mouseExited(with event: NSEvent) { pointerMoved(to: nil) }

    package func pointerMoved(to point: NSPoint?) {
        let inButton = point.map { buttonRect.contains($0) } ?? false
        if state.hovered != inButton { state.hovered = inButton }
        let inIcon = point.map { iconHoverRect.contains($0) } ?? false
        if state.icon.isHovered != inIcon { state.icon.hover(inIcon, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        pointerDidMove(to: point)
    }
    open func pointerDidMove(to point: NSPoint?) {}

    open override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        return buttonRect.contains(convert(point, from: superview)) ? self : nil
    }
    open override func mouseDown(with event: NSEvent) {
        guard state.enabled, event.type == .leftMouseDown, buttonRect.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event); return
        }
        tracksPress = true; state.pressed = true
    }
    open override func mouseDragged(with event: NSEvent) {
        guard tracksPress else { super.mouseDragged(with: event); return }
        let inside = buttonRect.contains(convert(event.locationInWindow, from: nil))
        if state.pressed != inside { state.pressed = inside }
    }
    open override func mouseUp(with event: NSEvent) {
        guard tracksPress else { super.mouseUp(with: event); return }
        tracksPress = false
        let inside = buttonRect.contains(convert(event.locationInWindow, from: nil))
        state.pressed = false
        if inside { perform() }
    }
    package func perform() { if state.enabled { action?() } }
}

@MainActor final class DownloadBinBoxOfThingsItem: TranslucentBoxOfThingsItem {
    init(palette: ThemeChromePalette) {
        super.init(colors: .bin(maxContrast: palette.maxContrastColor), action: {})
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var showsPointingHand: Bool { false }
}
