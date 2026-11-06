import AppKit
import SwiftUI

///
/// its own `ToastWindow` child, shared by every toast Parc presents. See
/// docs/toasts.md for the recovered addresses behind each value.
struct PArcToastContent: Equatable {
    /// `ToastContent.Button`. Parc presents only `shareButton(items:)`.
    enum Button: Equatable { case share([URL]) }
    /// `ToastContentOptions`: `.default(icon:label:subLabel:buttons:)` and
    /// `.shortcut(leadingLabel:shortcut:trailingLabel:)`.
    enum Body: Equatable {
        case standard(icon: String?, label: String, subLabel: String?, buttons: [Button])
        case shortcut(leading: String?, shortcut: String, trailing: String?)
    }
    var body: Body
    var accessibilityText: String

    static func standard(_ label: String, icon: String? = nil, subLabel: String? = nil,
                         buttons: [Button] = []) -> PArcToastContent {
        PArcToastContent(body: .standard(icon: icon, label: label, subLabel: subLabel, buttons: buttons),
                        accessibilityText: [label, subLabel].compactMap { $0 }.joined(separator: ", "))
    }
    private static func share(_ urls: [URL]) -> [Button] { urls.isEmpty ? [] : [.share(urls)] }
    ///
    ///
    static func copiedCurrentURL(_ url: URL?) -> PArcToastContent {
        standard("Copied Current URL", buttons: share(url.map { [$0] } ?? []))
    }
    ///
    static func copiedItemLinks(_ urls: [URL]) -> PArcToastContent {
        standard("Copied item links", buttons: share(urls))
    }
    ///
    static func copiedQuoteLink(_ url: URL?) -> PArcToastContent {
        standard("Copied Link", icon: "quote.bubble.fill", subLabel: "With Quote", buttons: share(url.map { [$0] } ?? []))
    }
    ///
    ///
    static let copiedBuildInfo = standard("Copied Build Info")
    ///
    static let cannotAddNewPane = standard("Cannot Add New Pane")
    ///
    static let copiedImage = standard("Copied Image")
    ///
    ///
    static func copiedFile(_ urls: [URL]) -> PArcToastContent { standard("Copied File", buttons: share(urls)) }
    ///
    ///
    static func zoom(percent: Int) -> PArcToastContent { standard("\(percent)%") }
    ///
    static func fullScreenExit(shortcut: String) -> PArcToastContent {
        standard("To exit full screen, press " + shortcut + ".")
    }
    ///
    static let archiveCleared = standard("Archive Cleared")
    ///
    ///
    static func tabRestored(to location: String, selected: Bool) -> PArcToastContent {
        standard("Tab restored to " + location + (selected ? "" : ". Click to view."))
    }
    ///
    static func pinnedToFolder(_ name: String) -> PArcToastContent { standard("Pinned to “" + name + "”") }
    /// ToastType.backgroundTabCreated (case 31) as `BackgroundTabAffordanceView`
    ///
    static func backgroundTabCreated(inSpace space: String?, document: Bool) -> PArcToastContent {
        if document { return standard("New Document Created") }
        return standard(space.map { "New Tab Created in " + $0 } ?? "New Tab Created")
    }
    var showsShortcut: Bool { if case .shortcut = body { return true } else { return false } }
    ///
    static func pressAgain(shortcut: String, title: String) -> PArcToastContent {
        PArcToastContent(body: .shortcut(leading: nil, shortcut: shortcut, trailing: "again to " + title),
                        accessibilityText: "Press " + shortcut + " again to " + title)
    }
    /// ToastType.undo (case 12) becomes `.undoable(text, showShortcutHint: true)`
    ///
    ///
    ///
    ///
    ///
    static func undoable(_ text: String) -> PArcToastContent {
        PArcToastContent(body: .shortcut(leading: text + "! Use", shortcut: "⌘Z", trailing: "to undo."),
                        accessibilityText: text + "! Use ⌘Z to undo.")
    }
    ///
    static let clearedTabs = undoable("Cleared Tabs")
}

/// `ToastAccessoryOptions`: the delayed pill below the card.
struct PArcToastAccessory: Equatable {
    let text: String
    let image: String?
    let accessibilityLabel: String
}

/// An anchor whose window content is only part of its bounds.
@MainActor protocol PArcToastAnchoring: NSView {
    var toastContentRect: NSRect { get }
}

enum PArcToastPlacement {
    ///
    static let windowSide: CGFloat = 600
    ///
    ///
    static func windowFrame(for parent: NSRect) -> NSRect {
        NSRect(x: parent.maxX - windowSide, y: parent.maxY - windowSide, width: windowSide, height: windowSide)
    }
    ///
    /// `.windowContent` toast in the Spaces layout: the content view's upper
    ///
    static func contentFrame(for content: NSRect) -> NSRect {
        NSRect(x: content.minX, y: content.minY + content.height / 2, width: content.width, height: content.height / 2)
    }
}

enum PArcToastTiming {
    ///
    static let duration: TimeInterval = 5
    ///
    static let retirement: TimeInterval = 1
    ///
    static let accessoryDelay: TimeInterval = 0.5
}

/// `ToastAnimator`'s `ScrollWheelObserver`: a scroll that moves in the parent
/// or toast window dismisses; a resting finger's zero-distance event does not.
enum PArcToastScroll {
    static func dismisses(window: NSWindow?, deltaX: CGFloat, deltaY: CGFloat, owners: [NSWindow?]) -> Bool {
        guard deltaX != 0 || deltaY != 0, let window else { return false }
        return owners.contains { $0 === window }
    }
}

///
/// remote experiment is excluded; every toast uses the attributed color
/// material branch, with the original per-color HSL adjustment before averaging.
struct PArcToastPalette {
    let background: NSColor
    let foreground: NSColor
    let isDark: Bool

    ///
    ///
    /// static incognito theme. Its `basicColor` background is the one colour
    ///
    ///
    init(theme: SpaceTheme, isDark: Bool, basicBackground: NSColor? = nil) {
        if let basicBackground { self.init(colors: [basicBackground]); return }
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)!
        var colors: [NSColor] = []
        appearance.performAsCurrentDrawingAppearance {
            colors = theme.colors.map { value in
                let space: NSColorSpace
                switch value.colorSpace {
                case .sRGB: space = .sRGB
                case .displayP3: space = .displayP3
                case .linearSRGB:
                    space = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
                }
                return NSColor(colorSpace: space,
                    components: [value.red, value.green, value.blue, 1], count: 4)
            }
            if colors.isEmpty {
                // Parc's existing uncolored Space follows the native window
                // appearance; no remote palette or service state is introduced.
                colors = [NSColor.windowBackgroundColor.usingColorSpace(.displayP3) ?? .gray]
            }
        }
        self.init(colors: colors)
    }

    init(colors: [NSColor]) {
        let values = colors.map(Self.adjusted)
        let divisor = CGFloat(max(1, values.count))
        let red = values.reduce(0) { $0 + $1.redComponent } / divisor
        let green = values.reduce(0) { $0 + $1.greenComponent } / divisor
        let blue = values.reduce(0) { $0 + $1.blueComponent } / divisor
        background = NSColor(displayP3Red: red, green: green, blue: blue, alpha: 1)
        isDark = (max(red, green, blue) + min(red, green, blue)) / 2 < 0.45
        let contrasted = background.blended(withFraction: 0.3, of: isDark ? .black : .white)?.usingColorSpace(.displayP3) ?? background
        let lightness = (max(contrasted.redComponent, contrasted.greenComponent, contrasted.blueComponent) +
            min(contrasted.redComponent, contrasted.greenComponent, contrasted.blueComponent)) / 2
        foreground = lightness < 0.45 ? .white : .black
    }

    private static func adjusted(_ input: NSColor) -> NSColor {
        let color = input.usingColorSpace(.displayP3) ?? input
        func clamp(_ value: CGFloat) -> Double { Double(min(1, max(0, value))) }
        let value = ThemeColor(red: clamp(color.redComponent), green: clamp(color.greenComponent),
                               blue: clamp(color.blueComponent), colorSpace: .displayP3)!
        let hsl = value.hsl
        let saturation = hsl.saturation < 0.1 ? 0 : (hsl.saturation < 0.3 ? 0.4 : (hsl.saturation < 0.7 ? 0.2 : 0))
        let lightness: Double
        if hsl.lightness < 0.1 { lightness = hsl.saturation < 0.2 ? 0.3 : 0.15 }
        else if hsl.lightness < 0.45 || hsl.lightness > 0.95 { lightness = -0.05 }
        else { lightness = hsl.lightness < 0.8 ? 0.1 : -0.25 }
        let adjusted = ThemeColor.hsl(hue: hsl.hue,
            saturation: min(1, max(0, hsl.saturation + saturation)),
            lightness: min(1, max(0, hsl.lightness + lightness)), colorSpace: .displayP3)!
        return NSColor(displayP3Red: adjusted.red, green: adjusted.green, blue: adjusted.blue, alpha: 1)
    }
}

@MainActor
final class PArcToastState: ObservableObject {
    let content: PArcToastContent
    let accessory: PArcToastAccessory?
    @Published var theme: SpaceTheme
    /// An incognito window's basic background, in place of the theme's colours.
    @Published var basicBackground: NSColor?
    @Published var showing = false
    @Published var showAccessory = false
    @Published var reduceMotion = false
    ///
    @Published var maxWidth: CGFloat = PArcToastPlacement.windowSide
    init(content: PArcToastContent, accessory: PArcToastAccessory? = nil, theme: SpaceTheme, basicBackground: NSColor? = nil) {
        self.content = content; self.accessory = accessory; self.theme = theme; self.basicBackground = basicBackground
    }
    ///
    func show() {
        withAnimation(reduceMotion ? nil : Self.spring) { showing = true }
    }
    func hide(animated: Bool) {
        withAnimation(animated ? Self.spring : nil) { showing = false }
    }
    private static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)
}

struct PArcToastFrames: Equatable {
    var body = CGRect.zero
    var accessory = CGRect.zero
}
private struct PArcToastFrameKey: PreferenceKey {
    static let defaultValue = PArcToastFrames()
    static func reduce(value: inout PArcToastFrames, nextValue: () -> PArcToastFrames) {
        let next = nextValue()
        if !next.body.isEmpty { value.body = next.body }
        if !next.accessory.isEmpty { value.accessory = next.accessory }
    }
}

struct PArcToastActions {
    ///
    var tap: (() -> Void)?
    var accessory: (() -> Void)?
    var dismiss: () -> Void
    var share: @MainActor ([URL]) -> Void
    var frames: (PArcToastFrames) -> Void
}

/// `ShinyToastDropdown` with its `ToastContentView` and `ToastAccessoryView`,
///
struct PArcToastCard: View {
    @ObservedObject var state: PArcToastState
    let actions: PArcToastActions
    @Environment(\.colorScheme) private var colorScheme
    @State private var accessoryHovered = false
    private var palette: PArcToastPalette {
        PArcToastPalette(theme: state.theme, isDark: colorScheme == .dark, basicBackground: state.basicBackground)
    }
    private var ink: Color { Color(nsColor: palette.foreground) }
    ///
    ///
    static let iconFont: Font = {
        let label = NSFont.systemFont(ofSize: 13)
        return Font(label.familyName.flatMap {
            NSFontManager.shared.font(withFamily: $0, traits: [], weight: 8, size: label.pointSize)
        } ?? label)
    }()

    var body: some View {
        WidthLimit(maxWidth: max(0, state.maxWidth - 16)) { card }
            .padding([.top, .trailing], 8)
            .opacity(state.showing ? 1 : 0)
            .scaleEffect(state.reduceMotion ? 1 : (state.showing ? 1 : 0), anchor: UnitPoint(x: 0.5, y: 0.1))
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                if abs(value.translation.height) >= 10 { actions.dismiss() }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .coordinateSpace(name: "toast").onPreferenceChange(PArcToastFrameKey.self, perform: actions.frames)
    }

    private var card: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 42)
            .background(backdrop(accessory: false))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: PArcToastFrameKey.self,
                    value: PArcToastFrames(body: proxy.frame(in: .named("toast"))))
            })
            .modifier(TapModifier(tap: actions.tap))
            .modifier(AccessibilityModifier(content: state.content, tap: actions.tap))
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if let accessory = state.accessory, state.showAccessory { accessoryView(accessory) }
                }.alignmentGuide(.bottom) { $0[.bottom] - $0.height }
            }
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 6)
    }

    /// Caps the card at the window's width without widening it, so the
    /// scale-in stays anchored on the card itself.
    private struct WidthLimit: Layout {
        let maxWidth: CGFloat
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let child = subviews.first else { return .zero }
            return child.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: proposal.height))
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
    }

    @ViewBuilder private var content: some View {
        switch state.content.body {
        case .standard(let icon, let label, let subLabel, let buttons):
            //
            HStack(spacing: 8) {
                if let icon {
                    //
                    // the inherited primary colour, not the toast's ink.
                    Image(systemName: icon).font(Self.iconFont)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    //
                    //
                    if let subLabel {
                        Text(subLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.opacity(0.33))
                    }
                }
                .padding(.vertical, subLabel != nil && !buttons.isEmpty ? 4 : 0)
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    switch button {
                    case .share(let urls):
                        SwiftUI.Button { actions.share(urls) } label: {
                            Image(systemName: "square.and.arrow.up").offset(x: 0, y: -1)
                        }
                        .buttonStyle(PArcToastButtonStyle(ink: ink, isDark: palette.isDark))
                        .accessibilityLabel("Share")
                    }
                }
            }
        case .shortcut(let leading, let shortcut, let trailing):
            //
            HStack {
                Group {
                    if let leading { Text(leading) }
                    Text(shortcut).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8).frame(minHeight: 27)
                        .background(ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, -2)
                    if let trailing { Text(trailing) }
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(ink)
            }
        }
    }

    private func accessoryView(_ accessory: PArcToastAccessory) -> some View {
        SwiftUI.Button(action: { actions.accessory?() }) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(accessory.text)
                if let image = accessory.image { Image(systemName: image) }
            }
            .font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(backdrop(accessory: true))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityLabel(accessory.accessibilityLabel)
        .opacity(accessoryHovered ? 0.6 : 1).onHover { accessoryHovered = $0 }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PArcToastFrameKey.self,
                value: PArcToastFrames(accessory: proxy.frame(in: .named("toast"))))
        })
        .padding(.trailing, 13)
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.horizontal, 8)
    }

    @ViewBuilder private func backdrop(accessory: Bool) -> some View {
        ZStack {
            PArcToastMaterial()
            Color(nsColor: palette.background).opacity(0.8)
            if !accessory {
                LinearGradient(colors: palette.isDark ? [.black.opacity(0.2), .black.opacity(0.4)] :
                    [.white.opacity(0.4), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.black.opacity(0.3), lineWidth: 1 / max(1, NSScreen.screens.map(\.backingScaleFactor).min() ?? 1))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private struct TapModifier: ViewModifier {
        let tap: (() -> Void)?
        @ViewBuilder func body(content: Content) -> some View {
            if let tap { content.contentShape(Rectangle()).onTapGesture(perform: tap) } else { content }
        }
    }
    private struct AccessibilityModifier: ViewModifier {
        let content: PArcToastContent
        let tap: (() -> Void)?
        @ViewBuilder func body(content view: Content) -> some View {
            if let tap {
                view.accessibilityElement(children: .ignore).accessibilityLabel(content.accessibilityText)
                    .accessibilityAddTraits(.isButton).accessibilityAction(.default, tap)
            } else if content.showsShortcut {
                view.accessibilityElement(children: .ignore).accessibilityLabel(content.accessibilityText)
            } else {
                view.accessibilityElement(children: .contain)
            }
        }
    }
}

///
struct PArcToastButtonStyle: ButtonStyle {
    let ink: Color
    let isDark: Bool
    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, ink: ink, isDark: isDark)
    }
    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let ink: Color
        let isDark: Bool
        @State private var hovered = false
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ink)
                .padding(.horizontal, 8)
                .frame(minHeight: 27)
                .background(
                    shape.fill(Color.white.opacity(isDark ? 0.2 : 0.6))
                        .overlay(shape.strokeBorder(LinearGradient(
                            colors: [.white.opacity(isDark ? 0.12 : 0.2), .white.opacity(0)],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25)), lineWidth: 3))
                        .overlay(shape.strokeBorder(ink.opacity(isDark ? 0.2 : 0.36), lineWidth: 0.5))
                        .overlay(shape.fill(configuration.isPressed ? Color.black.opacity(0.05)
                            : hovered ? Color.black.opacity(0.025) : Color.clear))
                )
                .onHover { hovered = $0 }
        }
    }
}

private struct PArcToastMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = NSVisualEffectView.Material(rawValue: 1) ?? .popover
        view.blendingMode = .withinWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@MainActor
private final class PArcToastWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One presented toast: its passive child window, five-second repeating
///
@MainActor
final class PArcToastPresentation: NSView {
    let state: PArcToastState
    private let duration: TimeInterval
    private var onTap: (() -> Void)?
    var onRetire: (() -> Void)?
    /// Where the pointer is, in screen coordinates.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private weak var originalWindow: NSWindow?
    private weak var panel: PArcToastWindow?
    private var host: NSHostingView<PArcToastCard>!
    private var timer: Timer?
    private var closeWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private(set) var isRetiring = false
    private(set) var frames = PArcToastFrames()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(content: PArcToastContent, theme: SpaceTheme, basicBackground: NSColor? = nil, duration: TimeInterval = PArcToastTiming.duration,
         onTap: (() -> Void)? = nil, share: @escaping @MainActor ([URL]) -> Void = { _ in }) {
        state = PArcToastState(content: content, theme: theme, basicBackground: basicBackground)
        self.duration = duration; self.onTap = onTap
        super.init(frame: NSRect(x: 0, y: 0, width: PArcToastPlacement.windowSide, height: PArcToastPlacement.windowSide))
        host = NSHostingView(rootView: PArcToastCard(state: state, actions: PArcToastActions(
            tap: onTap == nil ? nil : { [weak self] in self?.performTap() },
            accessory: nil,
            dismiss: { [weak self] in self?.dismiss(animated: true) },
            share: share,
            frames: { [weak self] frames in
                guard let self, !self.isRetiring else { return }
                self.frames = frames
            })))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        timer?.invalidate(); closeWork?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    /// The child frame for `anchor`'s content, or the window placement when
    /// there is no attached, visible content (the delegate's nil frame).
    static func frame(in parent: NSWindow, over anchor: NSView?) -> NSRect {
        if let anchor, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor {
            let content = (anchor as? PArcToastAnchoring)?.toastContentRect ?? anchor.bounds
            if content.width > 0, content.height > 0 {
                return PArcToastPlacement.contentFrame(for: parent.convertToScreen(anchor.convert(content, to: nil)))
            }
        }
        return PArcToastPlacement.windowFrame(for: parent.frame)
    }

    @discardableResult
    func present(in parent: NSWindow, over anchor: NSView?) -> Bool {
        guard !isRetiring, originalWindow == nil, parent.isVisible, !parent.isMiniaturized,
              parent.attachedSheet == nil else { return false }
        let frame = Self.frame(in: parent, over: anchor)
        let panel = PArcToastWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.backgroundColor = .clear; panel.hasShadow = false
        panel.contentView = self; panel.acceptsMouseMovedEvents = true
        panel.appearance = parent.effectiveAppearance
        originalWindow = parent; self.panel = panel
        state.maxWidth = frame.width
        state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        parent.addChildWindow(panel, ordered: .above)
        panel.setFrame(frame, display: true)
        observe(parent)
        layoutSubtreeIfNeeded()
        guard panel.parent === parent, panel.isVisible else { dismiss(animated: false); return false }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isRetiring else { return }
            self.state.show()
        }
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isRetiring, !self.containsPointer else { return }
                self.dismiss(animated: true)
            }
        }
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: state.content.accessibilityText,
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    func update(theme: SpaceTheme, basicBackground: NSColor?) {
        guard !isRetiring else { return }
        state.theme = theme; state.basicBackground = basicBackground
        if let originalWindow { panel?.appearance = originalWindow.effectiveAppearance }
    }

    var containsPointer: Bool {
        guard !isRetiring, let panel, panel.isVisible else { return false }
        let point = convert(panel.convertPoint(fromScreen: pointerLocation()), from: nil)
        return frames.body.contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isRetiring else { return nil }
        let local = superview.map { convert(point, from: $0) } ?? point
        guard frames.body.contains(local) else { return nil }
        return super.hitTest(point)
    }

    func performTap() {
        guard !isRetiring, let onTap else { return }
        //
        dismiss(animated: true)
        onTap()
    }

    /// Input is revoked at once; only this passive child finishes its exit.
    func dismiss(animated: Bool) {
        guard !isRetiring else { if !animated { closePresentation() }; return }
        let shouldAnimate = animated && panel?.isVisible == true && !state.reduceMotion
        isRetiring = true; onTap = nil
        timer?.invalidate(); timer = nil
        panel?.ignoresMouseEvents = true
        state.hide(animated: shouldAnimate)
        let retire = onRetire; onRetire = nil
        retire?()
        guard shouldAnimate else { closePresentation(); return }
        let work = DispatchWorkItem { [weak self] in self?.closePresentation() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PArcToastTiming.retirement, execute: work)
    }

    private func closePresentation() {
        isRetiring = true
        timer?.invalidate(); timer = nil; closeWork?.cancel(); closeWork = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }; scrollMonitor = nil
        let panel = self.panel
        self.panel = nil; originalWindow = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil); panel.contentView = nil; panel.close()
        }
    }

    private func observe(_ parent: NSWindow) {
        for name in [NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.willEnterFullScreenNotification,
                     NSWindow.willExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(animated: false) }
            })
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.state.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    if self.state.reduceMotion && self.isRetiring { self.closePresentation() }
                }
            }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                self?.scrolled(in: event.window, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            }
            return event
        }
    }
    func scrolled(in window: NSWindow?, deltaX: CGFloat, deltaY: CGFloat) {
        guard !isRetiring, PArcToastScroll.dismisses(window: window, deltaX: deltaX, deltaY: deltaY,
                                                     owners: [originalWindow, panel]) else { return }
        dismiss(animated: true)
    }
}

/// A window's toast slot. Presenting removes every existing window toast first
///
@MainActor
final class PArcToastPresenter {
    private(set) var current: PArcToastPresentation?
    ///
    private let share: @MainActor ([URL]) -> Void
    /// The window's basic background, in place of its theme's colours: an
    /// incognito window's, whose theme context is the static incognito theme.
    var basicBackground: NSColor?
    init(share: @escaping @MainActor ([URL]) -> Void = { _ in }) { self.share = share }

    @discardableResult
    func show(_ content: PArcToastContent, in parent: NSWindow, over anchor: NSView?, theme: SpaceTheme,
              duration: TimeInterval = PArcToastTiming.duration, onTap: (() -> Void)? = nil,
              onRetire: (() -> Void)? = nil) -> PArcToastPresentation? {
        let next = PArcToastPresentation(content: content, theme: theme, basicBackground: basicBackground,
                                        duration: duration, onTap: onTap, share: share)
        guard next.present(in: parent, over: anchor) else { return nil }
        let previous = current
        current = next
        next.onRetire = { [weak self, weak next] in
            if let self, self.current === next { self.current = nil }
            onRetire?()
        }
        previous?.dismiss(animated: true)
        return next
    }
    func dismiss(animated: Bool) { current?.dismiss(animated: animated) }
    /// A changed binding retires only a toast that shows a shortcut.
    func dismissShortcutToasts() {
        if current?.state.content.showsShortcut == true { current?.dismiss(animated: true) }
    }
    func update(theme: SpaceTheme) { current?.update(theme: theme, basicBackground: basicBackground) }
}
