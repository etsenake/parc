import AppKit
import Combine
import SwiftUI

@MainActor
final class UpdateReadyCard: NSView {
    var onRestart: (() -> Void)?
    var onToggleAutomaticUpdates: (() -> Void)?
    var onHeightChange: (() -> Void)?
    private let model = UpdateReadyModel()
    private var hosting: NSHostingController<UpdateReadyBanner>!
    private var measured: (width: CGFloat, height: CGFloat)?
    private var expansion: AnyCancellable?
    private let title = UpdateBannerKeyStop(label: "New Parc Version Available", cornerRadius: 12)
    private let automatic = UpdateBannerKeyStop(label: "Automatic Updates", cornerRadius: 4)
    private let restart = UpdateBannerKeyStop(label: "Restart and Update", cornerRadius: 6)
    override var isFlipped: Bool { true }
    var keyViewControls: [NSView] { model.expanded ? [automatic, restart] : [title] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.onPress = { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(title)
            model.expand()
        }
        title.setAccessibilityHelp("Shows Restart and Update")
        automatic.onPress = { [weak self] in self?.perform(self?.onToggleAutomaticUpdates) }
        restart.onPress = { [weak self] in self?.perform(self?.onRestart) }
        setAutomaticUpdates(model.automaticUpdates)
        hosting = NSHostingController(rootView: UpdateReadyBanner(model: model, title: title, automatic: automatic, restart: restart))
        hosting.sizingOptions = []
        hosting.view.frame = bounds
        hosting.view.autoresizingMask = [.width, .height]
        addSubview(hosting.view)
        setAccessibilityElement(false)
        expansion = model.$expanded.dropFirst().removeDuplicates().sink { [weak self] expanded in
            guard let self else { return }
            measured = nil
            automatic.takesFocusOnArrival = expanded && window?.firstResponder === title
            updateStops(expanded: expanded)
            onHeightChange?()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func applyPalette(_ palette: ThemeChromePalette) {
        model.dark = palette.isDark
        let base = UpdateCompleteModel.gradientBase(palette)
        model.base = Color(nsColor: base)
        if let rgb = base.usingColorSpace(.sRGB) {
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            model.label = luminance > 0.5 ? .black : .white
        } else { model.label = .white }
    }
    func setInteractionEnabled(_ enabled: Bool) {
        model.interactive = enabled
        updateStops(expanded: model.expanded)
    }
    func collapse() { model.expanded = false }
    func setAutomaticUpdates(_ enabled: Bool) {
        automatic.setAccessibilityValue(enabled ? "On" : "Off")
        if model.automaticUpdates != enabled { model.automaticUpdates = enabled }
    }
    func preferredHeight(for width: CGFloat) -> CGFloat {
        if let measured, measured.width == width { return measured.height }
        let height = ceil(hosting.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        measured = (width, height)
        return height
    }
    private func updateStops(expanded: Bool) {
        title.isEnabled = model.interactive && !expanded
        automatic.isEnabled = model.interactive && expanded
        restart.isEnabled = automatic.isEnabled
        title.setAccessibilityElement(!expanded)
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
    @Published var expanded = false
    @Published var base = Color.accentColor
    @Published var label = Color.white

    func expand() {
        guard interactive, !expanded else { return }
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
                      : .spring(response: 0.35, dampingFraction: 0.7)) { expanded = true }
    }
}

struct UpdateReadyBanner: View {
    @ObservedObject var model: UpdateReadyModel
    let title: UpdateBannerKeyStop
    let automatic: UpdateBannerKeyStop
    let restart: UpdateBannerKeyStop
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .onHover { hovered = $0 }
            .task(id: hovered) {
                guard hovered, !model.expanded else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if !Task.isCancelled { model.expand() }
            }
            .onReceive(model.$interactive) { if !$0 { hovered = false } }
            .allowsHitTesting(model.interactive)
            .environment(\.colorScheme, model.dark ? .dark : .light)
    }

    private var content: some View {
        VStack(spacing: 8) {
            Button(action: model.expand) {
                UpdateBannerHeader(title: "New Parc Version Available", dark: model.dark, sparkles: false,
                                   sparkleColor: model.base, close: nil, expanded: model.expanded, hovered: hovered)
            }
            .buttonStyle(Bare())
            .disabled(model.expanded)
            .accessibilityHidden(!model.expanded)
            .updateBannerPointingHand(!model.expanded)
            .overlay { UpdateBannerKeyStop.Slot(stop: title).allowsHitTesting(false) }
            if model.expanded { controls.transition(.opacity) }
        }
        .padding(.bottom, model.expanded ? 8 : 0)
        .background { if model.expanded { UpdateBannerCard(dark: model.dark) } }
        .overlay {
            if !model.expanded {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(model.dark ? 0.2 : 0), lineWidth: 1)
            }
        }
    }

    private struct Bare: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label.contentShape(Rectangle()) }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            UpdateBannerRow(title: "Automatic Updates", icon: model.automaticUpdates ? "checkmark.square" : "square",
                            dark: model.dark, alignment: .center, interactive: model.interactive, stop: automatic)
            UpdateBannerPrimaryButton(title: "Restart and Update", dark: model.dark, label: model.label,
                                      gradient: hovered && model.interactive && !reduceMotion, base: model.base,
                                      stop: restart)
        }
        .padding(.horizontal, 8)
    }
}

private struct UpdateBannerPrimaryButton: View {
    let title: String
    let dark: Bool
    let label: Color
    let gradient: Bool
    let base: Color
    let stop: UpdateBannerKeyStop

    var body: some View {
        Button(action: stop.press) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(Style(dark: dark, label: label, gradient: gradient, base: base))
        .animation(.easeOut(duration: 0.1), value: gradient)
        .updateBannerKeyStop(stop)
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
