import AppKit
import SwiftUI

/// AuthFeature.ProgressionButtonStyle, shared by the welcome arrow and setup.
///
struct OnboardingProgressionButtonStyle: ButtonStyle {
    let reduceMotion: Bool
    /// A loading button takes no action but keeps its full face.
    var loading = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let scale = !isEnabled ? 1.0 : configuration.isPressed ? 0.98 : isHovered ? 1.02 : 1.0
        configuration.label
            .opacity(isEnabled || loading ? 1 : 0.5)
            .scaleEffect(scale)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45, blendDuration: 0),
                       value: scale)
            .onHover { isHovered = $0 }
    }
}

@MainActor
private final class OnboardingProgressionState: ObservableObject {
    @Published var title = "Next"
    @Published var enabled = true
    @Published var loading = false
    @Published var reduceMotion = false
    @Published var background = OnboardingSetupPalette.action
    @Published var foreground = NSColor.white
    var action: (() -> Void)?
}

private struct OnboardingSetupProgressionButton: View {
    @ObservedObject var state: OnboardingProgressionState

    var body: some View {
        Button { state.action?() } label: {
            // NewSetupView uses ProgressionButton with a Text label and no arrow.
            // Its label inherits the native SwiftUI font; no recovered font
            // override justifies the old semibold AppKit bezel treatment.
            ZStack {
                Text(state.title).opacity(state.loading ? 0 : 1)
                if state.loading { PArcButtonSpinner() }
            }
                .foregroundColor(Color(nsColor: state.foreground))
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: state.background)))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(OnboardingProgressionButtonStyle(reduceMotion: state.reduceMotion, loading: state.loading))
        .disabled(!state.enabled || state.loading)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(state.title)
        .accessibilityValue(state.loading ? "Loading" : "")
        .animation(state.reduceMotion ? nil : .easeInOut(duration: 0.12), value: state.enabled)
    }
}

///
///
struct PArcButtonSpinner: View {
    var body: some View {
        ProgressView().progressViewStyle(.circular).scaleEffect(0.5).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

extension NSColor {
    /// Whether this ink is light enough that a spinner beside it needs the dark appearance.
    var isLightInk: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent > 0.5
    }
}

/// Persistent native host: updating the draft/palette does not replace the
/// SwiftUI button, its hover state or its keyboard/accessibility owner.
final class OnboardingProgressionControl: NSView {
    private let state = OnboardingProgressionState()
    private var host: NSHostingView<OnboardingSetupProgressionButton>!
    /// Tab loop must target the SwiftUI host; first responder is never the wrapper.
    var keyboardView: NSView { host }
    var actionBlock: (() -> Void)?
    var title: String {
        get { state.title }
        set { state.title = newValue }
    }
    var isEnabled = true { didSet { updateAvailability() } }
    /// The spinner replaces the title and the button takes no action.
    var isLoading: Bool {
        get { state.loading }
        set { if state.loading != newValue { state.loading = newValue } }
    }
    override var isHidden: Bool { didSet { updateAvailability() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        host = NSHostingView(rootView: OnboardingSetupProgressionButton(state: state))
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        state.action = { [weak self] in self?.activate() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override func becomeFirstResponder() -> Bool {
        guard let window else { return false }
        if window.firstResponder === host { return true }
        return window.makeFirstResponder(host)
    }

    override func layout() { super.layout(); host.frame = bounds }

    func configure(background: NSColor, foreground: NSColor, reduceMotion: Bool) {
        state.background = background
        state.foreground = foreground
        state.reduceMotion = reduceMotion
        // The system spinner takes its shade from the host's appearance.
        host.appearance = NSAppearance(named: foreground.isLightInk ? .darkAqua : .aqua)
    }

    private func updateAvailability() { state.enabled = isEnabled && !isHidden }

    private func activate() {
        // A retiring/hidden setup control must never compete with the welcome's
        // default action or consume Return during marked-text composition.
        guard isEnabled, !isLoading, !isHiddenOrHasHiddenAncestor,
              let window, window.isKeyWindow, window.attachedSheet == nil else { return }
        if let text = window.firstResponder as? NSTextView, text.hasMarkedText() { return }
        actionBlock?()
    }
}
