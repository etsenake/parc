import AppKit
import ParcCore
import SwiftUI

struct ParcToastContent: Equatable {
    enum Button: Equatable { case share([URL]), retry }
    struct FailedExtension: Equatable {
        enum Reason: Equatable {
            case administrator, otherApp, parentalApproval, blocklisted
            func explanation(removing: Bool) -> String {
                switch self {
                case .administrator: return removing ? "Kept installed by your administrator" : "Blocked by your administrator"
                case .otherApp: return removing ? "Kept installed by another app" : "Managed by another app"
                case .parentalApproval: return "Needs a parent’s approval"
                case .blocklisted: return "Flagged as unsafe"
                }
            }
        }
        var name: String
        var profile: String? = nil
        var reason: Reason? = nil
    }
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
    static func copiedLinks(_ urls: [URL]) -> ParcToastContent {
        standard(urls.count == 1 ? "Copied Link" : "Copied Links", buttons: share(urls))
    }
    static func copiedQuoteLink(_ url: URL?) -> ParcToastContent {
        standard("Copied Link", icon: "quote.bubble.fill", subLabel: "With Quote", buttons: share(url.map { [$0] } ?? []))
    }
    static let copiedBuildInfo = standard("Copied Build Info")
    static let cannotAddNewPane = standard("Cannot Add New Pane")
    static let copiedImage = standard("Copied Image")
    static func copiedFile(_ urls: [URL]) -> ParcToastContent { standard("Copied File", buttons: share(urls)) }
    static func zoom(percent: Int) -> ParcToastContent { standard("\(percent)%") }
    static func fullScreenExit(shortcut: String) -> ParcToastContent {
        standard("To exit full screen, press " + shortcut + ".")
    }
    static let archiveCleared = standard("Archive Cleared")
    static func extensionsNotApplied(added: [FailedExtension], removed: [FailedExtension],
                                     retry: Bool = false) -> ParcToastContent {
        func line(_ verb: String, _ place: String, _ failures: [FailedExtension], _ kind: String) -> String? {
            var names: [String] = [], profiles: [String] = []
            for failure in failures {
                if !names.contains(failure.name) { names.append(failure.name) }
                if let profile = failure.profile, !profiles.contains(profile) { profiles.append(profile) }
            }
            guard let name = names.first else { return nil }
            guard names.count == 1 else { return "Couldn’t \(verb) \(names.count) \(kind)" }
            return "Couldn’t \(verb) " + name + (profiles.isEmpty ? "" : " \(place) " + listed(profiles))
        }
        let lines = [line("add", "to", added, "extensions"), line("remove", "from", removed, "ad blockers")].compactMap { $0 }
        let reason = (added + removed).first?.reason
        let explained = lines.count == 1 && (added + removed).allSatisfy { $0.reason == reason }
        let subLabel = explained ? reason?.explanation(removing: !removed.isEmpty) : lines.dropFirst().first
        return standard(lines.first ?? "", subLabel: subLabel, buttons: retry ? [.retry] : [])
    }
    private static func listed(_ names: [String]) -> String {
        switch names.count {
        case 1: return names[0]
        case 2: return names[0] + " and " + names[1]
        case 3: return names[0] + ", " + names[1] + " and " + names[2]
        default: return names[0] + ", " + names[1] + " and \(names.count - 2) more"
        }
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

enum ParcToastFocus: Hashable { case card, button(Int) }

enum ParcToastKeyboard {
    enum Action: Equatable { case focus, next, previous, activate, dismiss }
    static func action(for event: NSEvent) -> Action? {
        action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
    }
    static func action(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> Action? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        if flags == [.command, .option, .shift] && characters?.lowercased() == "a" { return .focus }
        if flags == [.control] && keyCode == 97 { return .focus }
        switch (keyCode, flags) {
        case (48, []), (124, []), (125, []): return .next
        case (48, [.shift]), (123, []), (126, []): return .previous
        case (36, []), (76, []), (49, []): return .activate
        case (53, []): return .dismiss
        default: return nil
        }
    }
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
    @Published var focused: ParcToastFocus?
    var appKitFocusTargets: Set<ParcToastFocus> = []
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
    var buttons: [Int: CGRect] = [:]
}
private struct ParcToastFrameKey: PreferenceKey {
    static let defaultValue = ParcToastFrames()
    static func reduce(value: inout ParcToastFrames, nextValue: () -> ParcToastFrames) {
        let next = nextValue()
        if !next.body.isEmpty { value.body = next.body }
        if !next.accessory.isEmpty { value.accessory = next.accessory }
        value.buttons.merge(next.buttons) { $1 }
    }
}

struct ParcToastActions {
    var tap: (() -> Void)?
    var accessory: (() -> Void)?
    var dismiss: () -> Void
    var share: @MainActor ([URL]) -> Void
    var frames: (ParcToastFrames) -> Void
    var retry: (() -> Void)?
}

struct ParcToastCard: View {
    @ObservedObject var state: ParcToastState
    let actions: ParcToastActions
    var backgroundFill: Color? = nil
    var buttonPointer = true
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
            .overlay(focusRing(cornerRadius: 12, shown: state.focused == .card))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ParcToastFrameKey.self,
                    value: ParcToastFrames(body: proxy.frame(in: .named("toast"))))
            })
            .modifier(TapModifier(tap: actions.tap))
            .modifier(AccessibilityModifier(content: state.content, tap: actions.tap,
                                            inAppKit: state.appKitFocusTargets.contains(.card)))
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
                ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                    Group {
                        switch button {
                        case .share(let urls):
                            SwiftUI.Button { actions.share(urls) } label: {
                                Image(systemName: "square.and.arrow.up").offset(x: 0, y: -1)
                            }
                            .buttonStyle(ParcToastButtonStyle(ink: ink, isDark: palette.isDark, showsPointer: buttonPointer))
                            .accessibilityLabel("Share")
                        case .retry:
                            SwiftUI.Button("Retry") { actions.retry?() }
                                .buttonStyle(ParcToastButtonStyle(ink: ink, isDark: palette.isDark, showsPointer: buttonPointer))
                        }
                    }
                    .overlay(focusRing(cornerRadius: 6, shown: state.focused == .button(index)))
                    .accessibilityHidden(state.appKitFocusTargets.contains(.button(index)))
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ParcToastFrameKey.self,
                            value: ParcToastFrames(buttons: [index: proxy.frame(in: .named("toast"))]))
                    })
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

    private func focusRing(cornerRadius: CGFloat, shown: Bool) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
            .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
            .padding(-3).opacity(shown ? 1 : 0)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    @ViewBuilder private func backdrop(accessory: Bool) -> some View {
        ZStack {
            if let backgroundFill { backgroundFill } else { ParcToastMaterial() }
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
            if let tap { content.contentShape(Rectangle()).pointingHandCursor().onTapGesture(perform: tap) } else { content }
        }
    }
    private struct AccessibilityModifier: ViewModifier {
        let content: ParcToastContent
        let tap: (() -> Void)?
        let inAppKit: Bool
        @ViewBuilder func body(content view: Content) -> some View {
            if inAppKit {
                view.accessibilityHidden(true)
            } else if let tap {
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
    var showsPointer = true
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let button = StyledButton(configuration: configuration, ink: ink, isDark: isDark)
        if showsPointer { button.pointingHandCursor() } else { button }
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
    var acceptsKeyboard = false
    var onCommandKey: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard acceptsKeyboard, event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        onCommandKey?()
        return parent?.performKeyEquivalent(with: event) == true || super.performKeyEquivalent(with: event)
    }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ParcToastFocusElement: NSView {
    let target: ParcToastFocus
    private weak var owner: ParcToastPresentation?
    init(target: ParcToastFocus, owner: ParcToastPresentation) {
        self.target = target; self.owner = owner
        super.init(frame: .zero)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { owner?.state.focused == target }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { owner?.isRetiring == false }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { owner?.focusLabel(for: target) }
    override func accessibilityPerformPress() -> Bool { owner?.press(target) ?? false }
}

struct ParcToastClock {
    var repeating: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    var after: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    static let system = ParcToastClock(
        repeating: { interval, work in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { work() } }
            return { timer.invalidate() }
        },
        after: { delay, work in
            let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        })
}

@MainActor
final class ParcToastPresentation: NSView {
    let state: ParcToastState
    private let duration: TimeInterval
    private var onTap: (() -> Void)?
    private var onRetry: (() -> Void)?
    private let share: @MainActor ([URL], NSPoint?) -> Void
    var onRetire: ((Bool) -> Void)?
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    var yieldsShortcut: (NSEvent) -> Bool = { _ in false }
    private weak var originalWindow: NSWindow?
    private weak var panel: ParcToastWindow?
    private var host: NSHostingView<ParcToastCard>!
    private var focusElements: [ParcToastFocus: ParcToastFocusElement] = [:]
    private let clock: ParcToastClock
    private var cancelTimer: (() -> Void)?
    private var cancelClose: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private(set) var isRetiring = false
    private(set) var frames = ParcToastFrames()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { state.focused != nil }

    init(content: ParcToastContent, theme: SpaceTheme, basicBackground: NSColor? = nil, duration: TimeInterval = ParcToastTiming.duration,
         onTap: (() -> Void)? = nil, onRetry: (() -> Void)? = nil,
         share: @escaping @MainActor ([URL], NSPoint?) -> Void = { _, _ in }, clock: ParcToastClock = .system) {
        state = ParcToastState(content: content, theme: theme, basicBackground: basicBackground)
        self.clock = clock
        self.duration = duration; self.onTap = onTap; self.onRetry = onRetry; self.share = share
        super.init(frame: NSRect(x: 0, y: 0, width: ParcToastPlacement.windowSide, height: ParcToastPlacement.windowSide))
        state.appKitFocusTargets = Set(keyboardTargets)
        host = NSHostingView(rootView: ParcToastCard(state: state, actions: ParcToastActions(
            tap: onTap == nil ? nil : { [weak self] in self?.performTap() },
            accessory: nil,
            dismiss: { [weak self] in self?.retire(animated: true, finished: true) },
            share: { urls in share(urls, nil) },
            frames: { [weak self] frames in
                guard let self, !self.isRetiring else { return }
                self.frames = frames
                self.placeFocusElements()
            },
            retry: onRetry == nil ? nil : { [weak self] in self?.performRetry() })))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
        for target in keyboardTargets {
            let element = ParcToastFocusElement(target: target, owner: self)
            addSubview(element)
            focusElements[target] = element
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        cancelTimer?(); cancelClose?()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
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
        panel.onCommandKey = { [weak self] in self?.returnFocus() }
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
        startDismissalTimer { [weak self] in self?.containsPointer == true }
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: state.content.accessibilityText,
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }

    func startDismissalTimer(isHovered: @escaping () -> Bool) {
        cancelTimer = clock.repeating(duration) { [weak self] in
            guard let self, !self.isRetiring, !isHovered(), self.state.focused == nil else { return }
            self.retire(animated: true, finished: true)
        }
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

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard !isRetiring, let window else { return super.accessibilityHitTest(point) }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return keyboardTargets.reversed().lazy.compactMap { self.focusElements[$0] }.first { $0.frame.contains(local) }
            ?? super.accessibilityHitTest(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isRetiring else { return nil }
        let local = superview.map { convert(point, from: $0) } ?? point
        guard frames.body.contains(local) else { return nil }
        return super.hitTest(point)
    }

    func performTap() {
        guard !isRetiring, let onTap else { return }
        retire(animated: true, finished: true)
        onTap()
    }

    func performRetry() {
        guard !isRetiring, let onRetry else { return }
        retire(animated: true, finished: true)
        onRetry()
    }

    var keyboardTargets: [ParcToastFocus] {
        guard case .standard(_, _, _, let buttons) = state.content.body else { return [] }
        let usable = buttons.indices.filter { if case .retry = buttons[$0] { return onRetry != nil } else { return true } }
        return (onTap == nil ? [] : [.card]) + usable.map { .button($0) }
    }

    func takesFocusShortcut(_ event: NSEvent) -> Bool {
        guard event.window === originalWindow, ParcToastKeyboard.action(for: event) == .focus,
              !yieldsShortcut(event) else { return false }
        return focusFromKeyboard()
    }

    @discardableResult
    func focusFromKeyboard() -> Bool {
        guard !isRetiring, let panel, panel.isVisible, let first = keyboardTargets.first else { return false }
        panel.acceptsKeyboard = true
        focus(first)
        panel.makeKey()
        return true
    }

    private func focus(_ target: ParcToastFocus) {
        state.focused = target
        panel?.makeFirstResponder(focusElements[target] ?? self)
    }

    private func placeFocusElements() {
        for (target, element) in focusElements {
            switch target {
            case .card: element.frame = frames.body
            case .button(let index): element.frame = frames.buttons[index] ?? .zero
            }
        }
    }

    fileprivate func focusLabel(for target: ParcToastFocus) -> String? {
        switch target {
        case .card: return state.content.accessibilityText
        case .button(let index):
            guard case .standard(_, _, _, let buttons) = state.content.body, buttons.indices.contains(index) else { return nil }
            switch buttons[index] {
            case .share: return "Share"
            case .retry: return "Retry"
            }
        }
    }

    fileprivate func press(_ target: ParcToastFocus) -> Bool {
        guard !isRetiring, keyboardTargets.contains(target) else { return false }
        activate(target)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard !isRetiring, let focused = state.focused else { super.keyDown(with: event); return }
        let targets = keyboardTargets
        switch ParcToastKeyboard.action(for: event) {
        case .next?, .previous?:
            guard let index = targets.firstIndex(of: focused) else { return }
            let step = ParcToastKeyboard.action(for: event) == .next ? 1 : targets.count - 1
            focus(targets[(index + step) % targets.count])
        case .activate?: activate(focused)
        case .dismiss?: retire(animated: true, finished: true)
        case .focus?:
            returnFocus()
            if yieldsShortcut(event), originalWindow?.performKeyEquivalent(with: event) != true {
                _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
            }
        case nil: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        guard !isRetiring, state.focused != nil else { super.cancelOperation(sender); return }
        retire(animated: true, finished: true)
    }

    private func activate(_ target: ParcToastFocus) {
        switch target {
        case .card: performTap()
        case .button(let index):
            guard case .standard(_, _, _, let buttons) = state.content.body, buttons.indices.contains(index) else { return }
            switch buttons[index] {
            case .share(let urls): share(urls, shareLocation(for: index))
            case .retry: performRetry()
            }
        }
    }

    private func shareLocation(for index: Int) -> NSPoint? {
        guard let panel, let frame = frames.buttons[index] else { return nil }
        return panel.convertPoint(toScreen: convert(NSPoint(x: frame.minX, y: frame.maxY + 4), to: nil))
    }

    private func endKeyboardFocus() {
        state.focused = nil
        panel?.acceptsKeyboard = false
        if let panel, !panel.isKeyWindow, focusElements.values.contains(where: { $0 === panel.firstResponder }) {
            panel.makeFirstResponder(nil)
        }
    }

    private func returnFocus() {
        let hadFocus = panel?.isKeyWindow == true
        endKeyboardFocus()
        if hadFocus, let parent = originalWindow, parent.isVisible { parent.makeKey() }
    }

    func dismiss(animated: Bool) { retire(animated: animated, finished: false) }

    private func retire(animated: Bool, finished: Bool, returningFocus: Bool = true) {
        guard !isRetiring else { if !animated { closePresentation() }; return }
        let shouldAnimate = animated && panel?.isVisible == true && !state.reduceMotion
        isRetiring = true; onTap = nil; onRetry = nil
        if returningFocus { returnFocus() } else { endKeyboardFocus() }
        cancelTimer?(); cancelTimer = nil
        panel?.ignoresMouseEvents = true
        state.hide(animated: shouldAnimate)
        let retire = onRetire; onRetire = nil
        retire?(finished)
        guard shouldAnimate else { closePresentation(); return }
        cancelClose = clock.after(ParcToastTiming.retirement) { [weak self] in self?.closePresentation() }
    }

    private func closePresentation() {
        isRetiring = true
        cancelTimer?(); cancelTimer = nil; cancelClose?(); cancelClose = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }; scrollMonitor = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
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
                MainActor.assumeIsolated { self?.retire(animated: false, finished: false, returningFocus: false) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.endKeyboardFocus()
                if NSApp.keyWindow == nil, let parent = self.originalWindow, parent.isVisible, !parent.isMiniaturized {
                    parent.makeKey()
                }
            }
        })
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
        guard !keyboardTargets.isEmpty else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.takesFocusShortcut(event) ?? false }
            return consumed ? nil : event
        }
    }
    func scrolled(in window: NSWindow?, deltaX: CGFloat, deltaY: CGFloat) {
        guard !isRetiring, ParcToastScroll.dismisses(window: window, deltaX: deltaX, deltaY: deltaY,
                                                     owners: [originalWindow, panel]) else { return }
        retire(animated: true, finished: true)
    }
}

@MainActor
final class ParcToastQueue {
    struct Item {
        let content: ParcToastContent
        var onRetry: (() -> Void)? = nil
        let restore: () -> Void
    }
    private weak var presenter: ParcToastPresenter?
    private weak var shown: ParcToastPresentation?
    private let next: () -> Item?
    private let present: (Item) -> ParcToastPresentation?
    private let schedule: (@escaping @MainActor () -> Void) -> Void
    var canShow: () -> Bool = { true }
    var isFront: () -> Bool = { true }

    init(presenter: ParcToastPresenter, next: @escaping () -> Item?, present: @escaping (Item) -> ParcToastPresentation?,
         schedule: @escaping (@escaping @MainActor () -> Void) -> Void = { work in DispatchQueue.main.async { work() } }) {
        self.presenter = presenter; self.next = next; self.present = present
        self.schedule = schedule
    }

    func showNext() {
        guard canShow(), shown?.isRetiring != false, let item = next() else { return }
        shown = present(item)
        if shown == nil { item.restore() }
    }

    func showNextWhenIdle() {
        schedule { [weak self] in
            guard let self, self.isFront(), self.presenter?.current == nil else { return }
            self.showNext()
        }
    }
}

@MainActor
final class ParcToastPresenter {
    private(set) var current: ParcToastPresentation?
    private let share: @MainActor ([URL], NSPoint?) -> Void
    var basicBackground: NSColor?
    var onIdle: (() -> Void)?
    var yieldsShortcut: (NSEvent) -> Bool = { _ in false }
    private let clock: ParcToastClock
    private let present: @MainActor (ParcToastPresentation, NSWindow, NSView?) -> Bool
    init(share: @escaping @MainActor ([URL], NSPoint?) -> Void = { _, _ in }, clock: ParcToastClock = .system,
         present: @escaping @MainActor (ParcToastPresentation, NSWindow, NSView?) -> Bool = { $0.present(in: $1, over: $2) }) {
        self.share = share
        self.clock = clock
        self.present = present
    }

    @discardableResult
    func show(_ content: ParcToastContent, in parent: NSWindow, over anchor: NSView?, theme: SpaceTheme,
              duration: TimeInterval = ParcToastTiming.duration, onTap: (() -> Void)? = nil,
              onRetry: (() -> Void)? = nil, onRetire: (() -> Void)? = nil) -> ParcToastPresentation? {
        let next = ParcToastPresentation(content: content, theme: theme, basicBackground: basicBackground,
                                        duration: duration, onTap: onTap, onRetry: onRetry, share: share, clock: clock)
        next.yieldsShortcut = yieldsShortcut
        guard present(next, parent, anchor) else { return nil }
        let previous = current
        current = next
        next.onRetire = { [weak self, weak next] finished in
            let idle = self.map { $0.current === next } ?? false
            if idle { self?.current = nil }
            onRetire?()
            if idle && finished { self?.onIdle?() }
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
