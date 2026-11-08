import AppKit
import SwiftUI

/// ImportFeature.BrowserSelection: a plain stack of browser cards with the
/// selected browser's profiles beneath it, in setup's 278 × 92 rows or the
///
/// choices outgrow the space the rows tighten instead. Only actual discovered
/// source descriptors are admitted by the presentation owner.
struct BrowserImportSourcePicker: View {
    struct Source: Identifiable {
        let id: String
        let title: String
        let icon: NSImage
        var iconBackground: NSColor = .clear
        let selected: Bool
        let choose: () -> Void
        var profiles: [Profile] = []
        /// Profiles are loading, or this browser's data is importing.
        var busy = false
        var options: [ImportOption] = []
        var messages: [String] = []
        var choosePasswords: (() -> Void)?
    }
    struct Profile: Identifiable {
        let id: String
        let title: String
        let selected: Bool
        let enabled: Bool
        let choose: () -> Void
    }
    struct ImportOption: Identifiable {
        let id: String
        let title: String
        let selected: Bool
        let toggle: () -> Void
    }
    /// BrowserSelectionOption's last case: import nothing.
    struct Skip {
        let selected: Bool
        let choose: () -> Void
    }
    let layout: BrowserImportSourceCard.Layout
    let sources: [Source]
    var skip: Skip?
    var enabled = true
    let selectionColor: NSColor
    @Environment(\.colorScheme) private var colorScheme

    private struct Metrics { let rowHeight: CGFloat; let spacing: CGFloat; let profilePadding: CGFloat }
    private var metrics: [Metrics] {
        switch layout {
        case .setup: return [.init(rowHeight: 92, spacing: 20, profilePadding: 14), .init(rowHeight: 72, spacing: 14, profilePadding: 10),
                             .init(rowHeight: 56, spacing: 8, profilePadding: 7)]
        case .window: return [.init(rowHeight: 48, spacing: 12, profilePadding: 12), .init(rowHeight: 40, spacing: 8, profilePadding: 8),
                              .init(rowHeight: 34, spacing: 6, profilePadding: 6)]
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(metrics.indices.dropLast(), id: \.self) { stack(metrics[$0]) }
            // Past the tightest rows the stack scales down whole rather than scroll.
            BrowserImportScaledToFit { stack(metrics[metrics.count - 1]) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout == .setup ? .center : .top)
        //
        //
        .environment(\.colorScheme, layout == .setup ? .light : colorScheme)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your previous browser")
    }

    private func stack(_ metrics: Metrics) -> some View {
        VStack(spacing: metrics.spacing) {
            ForEach(sources) { source in
                VStack(spacing: 0) {
                    BrowserImportSourceCard(layout: layout, title: source.title, icon: source.icon,
                        iconBackground: source.iconBackground, selected: source.selected, busy: source.busy,
                        height: metrics.rowHeight, selectionColor: selectionColor, action: source.choose)
                        .opacity(enabled || source.selected ? 1 : 0.5)
                    if source.selected { details(source, metrics) }
                }
            }
            if let skip {
                BrowserImportSourceCard(layout: layout, title: "No, I want to type in all my passwords again.", icon: nil,
                    uppercased: false, selected: skip.selected, height: metrics.rowHeight,
                    selectionColor: selectionColor, action: skip.choose)
                    .opacity(enabled || skip.selected ? 1 : 0.5)
            }
        }
        .frame(width: layout == .setup ? 278 : nil)
        .padding(.horizontal, layout == .setup ? 24 : 6)
        .padding(.vertical, layout == .setup ? 16 : 4)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func details(_ source: Source, _ metrics: Metrics) -> some View {
        if source.profiles.count > 1 {
            BrowserImportProfiles(profiles: source.profiles, rowPadding: metrics.profilePadding, selectionColor: selectionColor)
                .padding(.top, metrics.profilePadding + 1).padding(.bottom, metrics.profilePadding * 1.7)
        }
        if !source.options.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Extensions to bring with you").fontWeight(.medium)
                ForEach(source.options) { option in
                    Toggle(option.title, isOn: Binding(get: { option.selected }, set: { _ in option.toggle() }))
                        .toggleStyle(.checkbox)
                }
            }
            .font(.system(size: 12)).padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(Array(source.messages.enumerated()), id: \.offset) { _, message in
            Text(message).font(.system(size: layout == .setup ? 12 : 11)).multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        if let choosePasswords = source.choosePasswords {
            Button("Import exported passwords instead…", action: choosePasswords)
                .buttonStyle(.plain).font(.system(size: 12)).padding(.top, 12)
        }
    }

    /// Original BrowserSource colors; discovery's app identity supplies the key.
    /// Unknown Chromium-family sources keep a neutral background.
    static func iconBackground(bundleIdentifier: String?) -> NSColor {
        switch bundleIdentifier {
        case "com.google.Chrome": return NSColor(parcHex: "FFCBB0")
        case "com.brave.Browser": return NSColor(red: 0.95, green: 0.76, blue: 0.09, alpha: 0.3)
        case "com.microsoft.edgemac": return NSColor(parcHex: "D7FFF2")
        case "org.mozilla.firefox": return NSColor(red: 0.99, green: 0.71, blue: 0.9, alpha: 1)
        case "com.operasoftware.Opera": return NSColor(parcHex: "FFE4E7")
        case "com.operasoftware.OperaGX": return NSColor(parcHex: "FECDD8")
        case "com.apple.Safari": return NSColor(red: 0.82, green: 0.87, blue: 1, alpha: 0.3)
        case "com.vivaldi.Vivaldi": return NSColor(parcHex: "FCD7D7")
        case BrowserImportCoordinator.arcBundleIdentifier: return NSColor(parcHex: "E3E6FC")
        default: return .white
        }
    }
}

/// ImportFeature.ProfilePicker is inline only for a source with several
/// profiles. Keep native source identity in the owner; this is presentation.
private struct BrowserImportProfiles: View {
    let profiles: [BrowserImportSourcePicker.Profile]
    let rowPadding: CGFloat
    let selectionColor: NSColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                Button(action: profile.choose) {
                    HStack(spacing: 12) {
                        ZStack {
                            if profile.selected {
                                Circle().fill(Color(nsColor: selectionColor))
                                    .overlay(Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                                    .transition(.scale)
                            } else {
                                Circle().fill(.white)
                                Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1.5)
                            }
                        }
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(profile.title).lineLimit(1).truncationMode(.tail)
                            .help(profile.title).padding(.trailing, 18)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(nsColor: NSColor(parcHex: "767676")))
                    .padding(.vertical, rowPadding).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!profile.enabled)
                .accessibilityLabel("Import \(profile.title)")
                .accessibilityValue(profile.selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(profile.selected ? .isSelected : [])
                if index < profiles.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(colorScheme == .dark ? Color.clear : .white))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import profile")
    }
}

/// Scales its content down uniformly to the offered height; never up.
private struct BrowserImportScaledToFit<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var height: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            content()
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { Color.clear.preference(key: BrowserImportFitHeight.self, value: $0.size.height) })
                .scaleEffect(height > geometry.size.height && height > 0 ? geometry.size.height / height : 1)
                .opacity(height > 0 ? 1 : 0)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onPreferenceChange(BrowserImportFitHeight.self) { height = $0 }
    }
}
private struct BrowserImportFitHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
