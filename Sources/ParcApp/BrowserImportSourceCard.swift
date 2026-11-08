import AppKit
import SwiftUI

/// The one browser choice both import presentations use: setup's 278 × 92
/// BrowserSelection row and the import window's 48-point radio row. The whole
/// card is the button, so a click anywhere selects it; hover, focus, keyboard
/// activation and accessibility are the same in both.
struct BrowserImportSourceCard: View {
    enum Layout { case setup, window }
    let layout: Layout
    let title: String
    let icon: NSImage?
    var iconBackground: NSColor = .clear
    var uppercased = true
    let selected: Bool
    var busy = false
    var height: CGFloat?
    let selectionColor: NSColor
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            switch layout {
            case .setup: BrowserImportSetupCardFace(title: uppercased ? title.uppercased() : title, icon: icon,
                iconBackground: iconBackground, selected: selected, busy: busy, height: height ?? 92,
                selectionColor: selectionColor)
            case .window: BrowserImportWindowCardFace(title: uppercased ? title.uppercased() : title, icon: icon,
                selected: selected, busy: busy, height: height ?? 48, selectionColor: selectionColor)
            }
        }
        .buttonStyle(BrowserImportSourceCardStyle())
        .scaleEffect(hovered && enabled && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.8), value: hovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BrowserImportSourceCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.browserImportCardPressed, configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct BrowserImportCardPressedKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var browserImportCardPressed: Bool {
        get { self[BrowserImportCardPressedKey.self] }
        set { self[BrowserImportCardPressedKey.self] = newValue }
    }
}

private struct BrowserImportSetupCardFace: View {
    let title: String
    let icon: NSImage?
    let iconBackground: NSColor
    let selected: Bool
    let busy: Bool
    let height: CGFloat
    let selectionColor: NSColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.browserImportCardPressed) private var pressed
    private var ink: Color {
        colorScheme == .dark ? .white : Color(.sRGB, red: 0.094, green: 0.106, blue: 0.122)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(-0.02)
                    .foregroundColor(Color(.sRGB, red: 118 / 255, green: 118 / 255, blue: 118 / 255))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if busy { ProgressView().controlSize(.small).accessibilityLabel("Importing") }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            if let icon {
                ZStack {
                    Rectangle().fill(Color(nsColor: iconBackground))
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: min(50, height - 24), height: min(50, height - 24))
                }
                .frame(width: height, height: height)
                .accessibilityHidden(true)
            }
        }
        .frame(width: 278, height: height)
        .background(Color.white.opacity(colorScheme == .dark ? 0.1 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(selected ? Color(nsColor: selectionColor) : ink.opacity(0.1), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 5)
        .opacity(pressed ? 0.85 : 1)
    }
}

/// The import window's observed row: radio, uppercase name, divider and icon.
private struct BrowserImportWindowCardFace: View {
    let title: String
    let icon: NSImage?
    let selected: Bool
    let busy: Bool
    let height: CGFloat
    let selectionColor: NSColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.browserImportCardPressed) private var pressed
    private var dark: Bool { colorScheme == .dark }
    private var line: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        HStack(spacing: 0) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.mini).accessibilityLabel("Importing")
                } else {
                    Circle().fill(.white)
                    if !dark { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1) }
                    if selected { Circle().fill(Color(nsColor: selectionColor)).padding(3) }
                }
            }
            .frame(width: 14, height: 14).padding(.leading, 16).padding(.trailing, 14)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(dark ? .white.opacity(0.7) : Color(nsColor: NSColor(parcHex: "767676")))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(line).frame(width: 1).padding(.vertical, 1)
            Group {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high) } else { Color.clear }
            }
            .frame(width: min(24, height - 16), height: min(24, height - 16)).padding(.horizontal, 12)
            .accessibilityHidden(true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(shape.fill(dark ? Color.white.opacity(pressed ? 0.22 : 0.12)
                                    : Color.white.opacity(pressed ? 0.85 : 1)))
        .overlay(shape.strokeBorder(selected ? Color(nsColor: selectionColor) : line, lineWidth: selected ? 2 : 1))
    }
}
