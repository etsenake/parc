import AppKit
import SwiftUI

///
/// pending-choice behavior. macOS consent belongs to the onboarding owner.
struct OnboardingDefaultBrowserChoice: View {
    let selected: Bool
    let selectionColor: NSColor
    let onSelect: (Bool) -> Void

    var body: some View {
        VStack(spacing: 22) {
            OnboardingChoiceRow(selected: selected, preferred: true,
                label: "YES, make Parc default.", selectionColor: selectionColor,
                action: { onSelect(true) }) {
                    Text("YES").bold() + Text(", make Parc default.")
                }
            OnboardingChoiceRow(selected: !selected, preferred: false,
                label: "NO, still exploring my options.", selectionColor: selectionColor,
                action: { onSelect(false) }) {
                    Text("NO").bold() + Text(", still exploring my options.")
                }
        }
        .frame(width: 339)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Default browser")
    }
}

/// Both original setup choices use this same RadioGroupLabel configuration.
/// The caller owns the label and whether selection may show the preferred heart.
struct OnboardingChoiceRow<Label: View>: View {
    let selected: Bool
    let preferred: Bool
    let label: String
    let selectionColor: NSColor
    let action: () -> Void
    @ViewBuilder var content: () -> Label
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    @State private var showHeart = false

    private var tint: Color { Color(nsColor: selectionColor) }
    //
    private var titleColor: Color {
        colorScheme == .dark ? .white : Color(.sRGB, red: 0.094, green: 0.106, blue: 0.122)
    }
    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 19) {
                indicator
                content()
                    .font(.system(size: 16))
                    .foregroundColor(selected ? tint : titleColor)
                    .frame(width: 250, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, 24)
            .frame(width: 339, height: 67)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(selected ? tint : titleColor.opacity(0.1), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 5)
            .contentShape(Rectangle())
            .pointingHandCursor()
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered && enabled && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8, blendDuration: 0), value: hovered)
        .onHover { hovered = $0 }
        .onChange(of: selected) { value in
            withAnimation(selectionAnimation) { showHeart = preferred && value }
        }
        .task(id: showHeart) {
            guard showHeart else { return }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(selectionAnimation) { showHeart = false }
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var indicator: some View {
        ZStack {
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(selected ? tint : .black.opacity(0.25), lineWidth: 1.5)
                if selected {
                    Circle().fill(tint).frame(width: 14, height: 14).transition(.scale)
                }
            }
            .scaleEffect(showHeart ? 0.001 : 1)
            if showHeart {
                Image(systemName: "heart.fill").font(.system(size: 25))
                    .foregroundColor(tint).transition(.scale)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
