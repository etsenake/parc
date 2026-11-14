import AppKit
import SwiftUI

struct ParcToastContent: Equatable {
    enum Button: Equatable { case share([URL]) }
    enum Body: Equatable {
        case standard(icon: String?, label: String, subLabel: String?, buttons: [Button])
        case shortcut(leading: String?, shortcut: String, trailing: String?)
    }
    var body: Body
    var accessibilityText: String

    static func standard(_ label: String, icon: String? = nil, subLabel: String? = nil,
                         buttons: [Button] = []) -> ParcToastContent {
        ParcToastContent(body: .standard(icon: icon, label: label, subLabel: subLabel, buttons: buttons),
                        accessibilityText: [label, subLabel].compactMap { $0 }.joined(separator: ", "))
    }
    private static func share(_ urls: [URL]) -> [Button] { urls.isEmpty ? [] : [.share(urls)] }
    static func copiedCurrentURL(_ url: URL?) -> ParcToastContent {
        standard("Copied Current URL", buttons: share(url.map { [$0] } ?? []))
    }
    static func copiedItemLinks(_ urls: [URL]) -> ParcToastContent {
        standard("Copied item links", buttons: share(urls))
    }
    static func copiedQuoteLink(_ url: URL?) -> ParcToastContent {
        standard("Copied Link", icon: "quote.bubble.fill", subLabel: "With Quote", buttons: share(url.map { [$0] } ?? []))
    }
    static func copiedLink(_ url: URL) -> ParcToastContent { standard("Copied Link", buttons: share([url])) }
    static let copiedBuildInfo = standard("Copied Build Info")
    static let cannotAddNewPane = standard("Cannot Add New Pane")
    static let copiedImage = standard("Copied Image")
    static func copiedFile(_ urls: [URL]) -> ParcToastContent { standard("Copied File", buttons: share(urls)) }
    static func zoom(percent: Int) -> ParcToastContent { standard("\(percent)%") }
    static func fullScreenExit(shortcut: String) -> ParcToastContent {
        standard("To exit full screen, press " + shortcut + ".")
    }
    static let archiveCleared = standard("Archive Cleared")
    static func extensionsNotAdded(_ names: [String]) -> ParcToastContent {
        standard(names.count == 1 ? "Couldn’t add " + names[0] : "Couldn’t add \(names.count) extensions")
    }
    static let importPartial = standard("Only some of your data imported. Please try again!")
    static let importFailed = standard("We weren’t able to import… please try again!")
    static func tabRestored(to location: String, selected: Bool) -> ParcToastContent {
        standard("Tab restored to " + location + (selected ? "" : ". Click to view."))
    }
    static func pinnedToFolder(_ name: String) -> ParcToastContent { standard("Pinned to “" + name + "”") }
    static func backgroundTabCreated(inSpace space: String?, document: Bool) -> ParcToastContent {
        if document { return standard("New Document Created") }
        return standard(space.map { "New Tab Created in " + $0 } ?? "New Tab Created")
    }
    var showsShortcut: Bool { if case .shortcut = body { return true } else { return false } }
    static func pressAgain(shortcut: String, title: String) -> ParcToastContent {
        ParcToastContent(body: .shortcut(leading: nil, shortcut: shortcut, trailing: "again to " + title),
                        accessibilityText: "Press " + shortcut + " again to " + title)
    }
    static func undoable(_ text: String) -> ParcToastContent {
        ParcToastContent(body: .shortcut(leading: text + "! Use", shortcut: "⌘Z", trailing: "to undo."),
                        accessibilityText: text + "! Use ⌘Z to undo.")
    }
    static let clearedTabs = undoable("Cleared Tabs")
}

struct ParcToastAccessory: Equatable {
    let text: String
    let image: String?
    let accessibilityLabel: String
}

@MainActor protocol ParcToastAnchoring: NSView {
    var toastContentRect: NSRect { get }
}

enum ParcToastPlacement {
    static let windowSide: CGFloat = 600
    static func windowFrame(for parent: NSRect) -> NSRect {
        NSRect(x: parent.maxX - windowSide, y: parent.maxY - windowSide, width: windowSide, height: windowSide)
    }
    static func contentFrame(for content: NSRect) -> NSRect {
        NSRect(x: content.minX, y: content.minY + content.height / 2, width: content.width, height: content.height / 2)
    }
}

enum ParcToastTiming {
    static let duration: TimeInterval = 5
    static let retirement: TimeInterval = 1
    static let accessoryDelay: TimeInterval = 0.5
}

enum ParcToastScroll {
    static func dismisses(window: NSWindow?, deltaX: CGFloat, deltaY: CGFloat, owners: [NSWindow?]) -> Bool {
        guard deltaX != 0 || deltaY != 0, let window else { return false }
        return owners.contains { $0 === window }
    }
}

struct ParcToastPalette {
    let background: NSColor
    let foreground: NSColor
    let isDark: Bool

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
final class ParcToastState: ObservableObject {
    let content: ParcToastContent
    let accessory: ParcToastAccessory?
    @Published var theme: SpaceTheme
    @Published var basicBackground: NSColor?
    @Published var showing = false
    @Published var showAccessory = false
    @Published var reduceMotion = false
    @Published var maxWidth: CGFloat = ParcToastPlacement.windowSide
    init(content: ParcToastContent, accessory: ParcToastAccessory? = nil, theme: SpaceTheme, basicBackground: NSColor? = nil) {
        self.content = content; self.accessory = accessory; self.theme = theme; self.basicBackground = basicBackground
    }
    func show() {
        withAnimation(reduceMotion ? nil : Self.spring) { showing = true }
    }
    func hide(animated: Bool) {
        withAnimation(animated ? Self.spring : nil) { showing = false }
    }
    private static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)
}

struct ParcToastFrames: Equatable {
    var body = CGRect.zero
    var accessory = CGRect.zero
}
private struct ParcToastFrameKey: PreferenceKey {
    static let defaultValue = ParcToastFrames()
    static func reduce(value: inout ParcToastFrames, nextValue: () -> ParcToastFrames) {
        let next = nextValue()
        if !next.body.isEmpty { value.body = next.body }
        if !next.accessory.isEmpty { value.accessory = next.accessory }
    }
}

struct ParcToastActions {
    var tap: (() -> Void)?
    var accessory: (() -> Void)?
    var dismiss: () -> Void
    var share: @MainActor ([URL]) -> Void
    var frames: (ParcToastFrames) -> Void
}

struct ParcToastCard: View {
    @ObservedObject var state: ParcToastState
    let actions: ParcToastActions
    @Environment(\.colorScheme) private var colorScheme
    @State private var accessoryHovered = false
    private var palette: ParcToastPalette {
        ParcToastPalette(theme: state.theme, isDark: colorScheme == .dark, basicBackground: state.basicBackground)
    }
    private var ink: Color { Color(nsColor: palette.foreground) }
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
            .coordinateSpace(name: "toast").onPreferenceChange(ParcToastFrameKey.self, perform: actions.frames)
    }

    private var card: some View {
        content.foregroundStyle(ink)
            .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 42)
            .background(backdrop(accessory: false))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ParcToastFrameKey.self,
                    value: ParcToastFrames(body: proxy.frame(in: .named("toast"))))
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
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(Self.iconFont) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subLabel {
                        Text(subLabel).font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    }
                }
                .padding(.vertical, subLabel != nil && !buttons.isEmpty ? 4 : 0)
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    switch button {
                    case .share(let urls):
                        SwiftUI.Button { actions.share(urls) } label: {
                            Image(systemName: "square.and.arrow.up").offset(x: 0, y: -1)
                        }
                        .buttonStyle(ParcToastButtonStyle(ink: ink, isDark: palette.isDark))
                        .accessibilityLabel("Share")
                    }
                }
            }
        case .shortcut(let leading, let shortcut, let trailing):
            HStack {
                Group {
                    if let leading { Text(leading) }
                    Text(shortcut).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8).frame(minHeight: 27)
                        .background(ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, -2)
                    if let trailing { Text(trailing) }
                }
                .font(.system(size: 14, weight: .medium))
            }
        }
    }

    private func accessoryView(_ accessory: ParcToastAccessory) -> some View {
        SwiftUI.Button(action: { actions.accessory?() }) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(accessory.text)
                if let image = accessory.image { Image(systemName: image) }
            }
            .font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(backdrop(accessory: true))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .pointingHandCursor()
        }
        .buttonStyle(.plain).accessibilityLabel(accessory.accessibilityLabel)
        .opacity(accessoryHovered ? 0.6 : 1).onHover { accessoryHovered = $0 }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ParcToastFrameKey.self,
                value: ParcToastFrames(accessory: proxy.frame(in: .named("toast"))))
        })
        .padding(.trailing, 13)
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.horizontal, 8)
    }

    @ViewBuilder private func backdrop(accessory: Bool) -> some View {
        ZStack {
            ParcToastMaterial()
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
        let content: ParcToastContent
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

struct ParcToastButtonStyle: ButtonStyle {
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
                .pointingHandCursor()
        }
    }
}

private struct ParcToastMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = NSVisualEffectView.Material(rawValue: 1) ?? .popover
        view.blendingMode = .withinWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

@MainActor
private final class ParcToastWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ParcToastPresentation: NSView {
    let state: ParcToastState
    private let duration: TimeInterval
    private var onTap: (() -> Void)?
    var onRetire: (() -> Void)?
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private weak var originalWindow: NSWindow?
    private weak var panel: ParcToastWindow?
    private var host: NSHostingView<ParcToastCard>!
    private var timer: Timer?
    private var closeWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private(set) var isRetiring = false
    private(set) var frames = ParcToastFrames()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(content: ParcToastContent, theme: SpaceTheme, basicBackground: NSColor? = nil, duration: TimeInterval = ParcToastTiming.duration,
         onTap: (() -> Void)? = nil, share: @escaping @MainActor ([URL]) -> Void = { _ in }) {
        state = ParcToastState(content: content, theme: theme, basicBackground: basicBackground)
        self.duration = duration; self.onTap = onTap
        super.init(frame: NSRect(x: 0, y: 0, width: ParcToastPlacement.windowSide, height: ParcToastPlacement.windowSide))
        host = NSHostingView(rootView: ParcToastCard(state: state, actions: ParcToastActions(
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

    static func frame(in parent: NSWindow, over anchor: NSView?) -> NSRect {
        if let anchor, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor {
            let content = (anchor as? ParcToastAnchoring)?.toastContentRect ?? anchor.bounds
            if content.width > 0, content.height > 0 {
                return ParcToastPlacement.contentFrame(for: parent.convertToScreen(anchor.convert(content, to: nil)))
            }
        }
        return ParcToastPlacement.windowFrame(for: parent.frame)
    }

    @discardableResult
    func present(in parent: NSWindow, over anchor: NSView?) -> Bool {
        guard !isRetiring, originalWindow == nil, parent.isVisible, !parent.isMiniaturized,
              parent.attachedSheet == nil else { return false }
        let frame = Self.frame(in: parent, over: anchor)
        let panel = ParcToastWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
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
        dismiss(animated: true)
        onTap()
    }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + ParcToastTiming.retirement, execute: work)
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
        guard !isRetiring, ParcToastScroll.dismisses(window: window, deltaX: deltaX, deltaY: deltaY,
                                                     owners: [originalWindow, panel]) else { return }
        dismiss(animated: true)
    }
}

@MainActor
final class ParcToastPresenter {
    private(set) var current: ParcToastPresentation?
    private let share: @MainActor ([URL]) -> Void
    var basicBackground: NSColor?
    init(share: @escaping @MainActor ([URL]) -> Void = { _ in }) { self.share = share }

    @discardableResult
    func show(_ content: ParcToastContent, in parent: NSWindow, over anchor: NSView?, theme: SpaceTheme,
              duration: TimeInterval = ParcToastTiming.duration, onTap: (() -> Void)? = nil,
              onRetire: (() -> Void)? = nil) -> ParcToastPresentation? {
        let next = ParcToastPresentation(content: content, theme: theme, basicBackground: basicBackground,
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
    func dismissShortcutToasts() {
        if current?.state.content.showsShortcut == true { current?.dismiss(animated: true) }
    }
    func update(theme: SpaceTheme) { current?.update(theme: theme, basicBackground: basicBackground) }
}
