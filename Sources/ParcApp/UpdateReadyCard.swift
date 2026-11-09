import AppKit
import SwiftUI

///
///
///
/// owns lifetime and motion. Values and open items: docs/software-update.md.
@MainActor
final class UpdateReadyCard: NSView {
    var onRestart: (() -> Void)?
    var onToggleAutomaticUpdates: (() -> Void)?
    private let model = UpdateReadyModel()
    private var hosting: NSHostingController<UpdateReadyBanner>!
    private var measured: (width: CGFloat, height: CGFloat)?
    override var isFlipped: Bool { true }
    var keyViewControls: [NSView] { [hosting.view] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        model.restart = { [weak self] in self?.perform(self?.onRestart) }
        model.toggle = { [weak self] in self?.perform(self?.onToggleAutomaticUpdates) }
        hosting = NSHostingController(rootView: UpdateReadyBanner(model: model))
        // The sidebar sizes the slot; the content must not add constraints.
        hosting.sizingOptions = []
        hosting.view.frame = bounds
        hosting.view.autoresizingMask = [.width, .height]
        addSubview(hosting.view)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyPalette(_ palette: ThemeChromePalette) {
        model.dark = palette.isDark
        let base = UpdateCompleteModel.gradientBase(palette)
        model.base = Color(nsColor: base)
        // Parc's choice: whichever of black and white reads on the fill.
        if let rgb = base.usingColorSpace(.sRGB) {
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            model.label = luminance > 0.5 ? .black : .white
        } else { model.label = .white }
    }
    func setInteractionEnabled(_ enabled: Bool) { model.interactive = enabled }
    func setAutomaticUpdates(_ enabled: Bool) { model.automaticUpdates = enabled }
    /// Asked on every sidebar layout while the banner occupies the slot.
    func preferredHeight(for width: CGFloat) -> CGFloat {
        if let measured, measured.width == width { return measured.height }
        let height = ceil(hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        measured = (width, height)
        return height
    }
    private func perform(_ action: (() -> Void)?) {
        guard model.interactive, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor else { return }
        action?()
    }
}

@MainActor
final class UpdateReadyModel: ObservableObject {
    @Published var dark = false
    @Published var interactive = false
    @Published var automaticUpdates = true
    @Published var base = Color.accentColor
    @Published var label = Color.white
    var restart: () -> Void = {}
    var toggle: () -> Void = {}
}

struct UpdateReadyBanner: View {
    @ObservedObject var model: UpdateReadyModel
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            UpdateBannerHeader(title: "New Parc Version Available", dark: model.dark, sparkles: false,
                               sparkleColor: model.base, close: nil)
            VStack(spacing: 8) {
                //
                UpdateBannerRow(title: "Automatic Updates", icon: model.automaticUpdates ? "checkmark.square" : "square",
                                dark: model.dark, gradient: false, base: model.base, alignment: .center, action: model.toggle)
                    .accessibilityValue(model.automaticUpdates ? "On" : "Off")
                UpdateBannerPrimaryButton(title: "Restart and Update", dark: model.dark, label: model.label,
                                          gradient: hovered && model.interactive && !reduceMotion, base: model.base,
                                          action: model.restart)
            }
            .padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
        .background(UpdateBannerCard(dark: model.dark))
        .onHover { hovered = $0 }
        // Not .disabled: that would dim the controls through the exit fade.
        .allowsHitTesting(model.interactive)
        .environment(\.colorScheme, model.dark ? .dark : .light)
    }
}

///
/// theme colour in a continuous radius-6 shape, `ButtonBackground`'s turning
/// gradient (blur 12, opacity 0.5) while the banner is hovered, a white 0.2
/// edge in dark, and a 0.97 scale with 0.8 label opacity on a 0.2/0.6 spring
/// while pressed. The label's font, colour and padding weren't recovered.
private struct UpdateBannerPrimaryButton: View {
    let title: String
    let dark: Bool
    let label: Color
    let gradient: Bool
    let base: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(Style(dark: dark, label: label, gradient: gradient, base: base))
        .animation(.easeOut(duration: 0.1), value: gradient)
    }

    private struct Style: ButtonStyle {
        let dark: Bool
        let label: Color
        let gradient: Bool
        let base: Color
        func makeBody(configuration: Configuration) -> some View {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            return configuration.label
                .foregroundStyle(label)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .background {
                    ZStack {
                        base
                        if gradient { UpdateBannerGradient(base: base, blurRadius: 12, blurOpacity: 0.5).transition(.opacity) }
                    }
                    .clipShape(shape)
                }
                .overlay { shape.stroke(Color.white.opacity(dark ? 0.2 : 0), lineWidth: 1) }
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}
