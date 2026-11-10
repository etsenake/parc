import AppKit
import SwiftUI

@MainActor
private final class OnboardingFavoritesState: ObservableObject {
    @Published var selected = Set<String>()
    @Published var enabled = true
    var onToggle: ((OnboardingDraft.FavoriteChoice) -> Void)?
}

/// AuthFeature.TopApps is an interactive sidebar illustration, not a list of
/// text buttons. Its nine fixed slots and local hover owner survive selection.
/// Reference addresses and resource provenance are recorded in onboarding.md.
private struct OnboardingFavoritesView: View {
    @ObservedObject var state: OnboardingFavoritesState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?

    private var subtleFill: Color { .primary.opacity(colorScheme == .dark ? 0.2 : 0.07) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 1))
                .shadow(color: .black.opacity(0.2), radius: 11, x: 3, y: 2)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 15) {
                        ForEach(0..<3) { _ in
                            Circle().fill(subtleFill).frame(width: 24, height: 24)
                        }
                    }
                    .padding(.top, 42)
                    .padding(.leading, 30)
                    .accessibilityHidden(true)
                    Color.clear.frame(height: 28)
                    VStack(spacing: 12) {
                        ForEach(0..<3) { row in
                            HStack(spacing: 12) {
                                ForEach(Array(OnboardingDraft.favoriteChoices[(row * 3)..<(row * 3 + 3)])) { choice in
                                    tile(choice)
                                }
                            }
                        }
                    }
                    .padding(.leading, 30)
                    placeholder.padding(.top, 30).padding(.bottom, 12)
                    placeholder
                }
                HStack {
                    Spacer(minLength: 0)
                    Color.black.opacity(0.05).frame(width: 117)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(width: 493, height: 505)
        .offset(x: 20, y: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Favorite apps")
        .onDisappear { hovered = nil }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 21, style: .continuous)
            .fill(subtleFill).frame(width: 302, height: 57)
            .padding(.leading, 30).accessibilityHidden(true)
    }

    private func tile(_ choice: OnboardingDraft.FavoriteChoice) -> some View {
        let selected = state.selected.contains(choice.url)
        return Button { state.onToggle?(choice) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(subtleFill)
                if selected {
                    if let artwork = OnboardingFavoriteArtwork.image(choice, dark: colorScheme == .dark) {
                        Image(nsImage: artwork).resizable()
                            .blur(radius: 20).saturation(3).opacity(0.6)
                            .scaleEffect(2.5)
                    }
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color(.displayP3, white: 1, opacity: 0.7))
                        .blendMode(.lighten).padding(3)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.02), lineWidth: 1.5)
                }
                if let artwork = OnboardingFavoriteArtwork.image(choice, dark: colorScheme == .dark) {
                    Image(nsImage: artwork).resizable()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(width: 94, height: 94)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(hovered == choice.id && !reduceMotion ? 1.05 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8, blendDuration: 0),
                       value: hovered == choice.id)
        }
        .buttonStyle(OnboardingFavoriteButtonStyle())
        .disabled(!state.enabled)
        .onHover { inside in
            // An exit from the preceding tile cannot clear the new tile owner.
            if inside { hovered = choice.id }
            else if hovered == choice.id { hovered = nil }
        }
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Toggle this Favorite")
    }
}

private struct OnboardingFavoriteButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.4, blendDuration: 0.5),
                       value: configuration.isPressed)
            .pointingHandCursor()
    }
}

private enum OnboardingFavoriteArtwork {
    static let images: [String: NSImage] = {
        var result = [String: NSImage]()
        for choice in OnboardingDraft.favoriteChoices {
            for suffix in ["", "-dark"] {
                let name = choice.artwork + suffix
                if let image = OnboardingArtwork.image(name) { result[name] = image }
            }
        }
        return result
    }()
    static func image(_ choice: OnboardingDraft.FavoriteChoice, dark: Bool) -> NSImage? {
        images[choice.artwork + (dark ? "-dark" : "")] ?? images[choice.artwork]
    }
}

/// Keep the SwiftUI host alive as the draft changes; re-rendering the complete
/// setup card on every toggle discards hover, focus and the native press owner.
final class OnboardingFavoritesControl: NSView {
    private let state = OnboardingFavoritesState()
    private var host: NSHostingView<OnboardingFavoritesView>!
    var onToggle: ((OnboardingDraft.FavoriteChoice) -> Void)?
    /// The setup Tab loop targets the SwiftUI host that owns the tiles.
    var keyboardView: NSView { host }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // The reference illustration deliberately extends past the card. Clip
        // it at this right column's card corners, without clipping card shadow.
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.cornerCurve = .continuous
        layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
        host = NSHostingView(rootView: OnboardingFavoritesView(state: state))
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        state.onToggle = { [weak self] choice in
            guard let self, self.state.enabled, !self.isHiddenOrHasHiddenAncestor,
                  let window = self.window, window.attachedSheet == nil else { return }
            self.onToggle?(choice)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() { super.layout(); host.frame = bounds }
    func configure(draft: OnboardingDraft, enabled: Bool) {
        state.selected = Set(OnboardingDraft.favoriteChoices.filter(draft.isFavoriteSelected).map(\.url))
        state.enabled = enabled
    }
}
