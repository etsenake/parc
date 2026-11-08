import AppKit
import SwiftUI

/// ImportFeature.BrowserSelection uses the larger onboarding rows (278 × 92),
/// distinct from the compact application-menu chooser. Only actual discovered
/// source descriptors are admitted by the presentation owner.
struct OnboardingImportSourcePicker: View {
    struct Source: Identifiable {
        let id: String
        let title: String
        let icon: NSImage
        let iconBackground: NSColor
        let selected: Bool
        let choose: () -> Void
        var profiles: [Profile] = []
        var loading = false
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
    let sources: [Source]
    let freshStartSelected: Bool
    let selectionColor: NSColor
    let chooseFreshStart: () -> Void
    let chooseFile: () -> Void
    let fileDescription: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(sources) { source in
                    VStack(spacing: 0) {
                        BrowserImportSourceCard(layout: .setup, title: source.title, icon: source.icon,
                            iconBackground: source.iconBackground, selected: source.selected,
                            selectionColor: selectionColor, action: source.choose)
                        if source.selected {
                            if source.loading {
                                ProgressView("Finding profiles…").controlSize(.small)
                                    .font(.system(size: 12)).padding(.top, 15)
                            } else {
                                if source.profiles.count > 1 {
                                    OnboardingImportProfiles(profiles: source.profiles, selectionColor: selectionColor)
                                        .padding(.top, 15).padding(.bottom, 24)
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
                                    Text(message).font(.system(size: 12)).multilineTextAlignment(.center)
                                        .foregroundColor(Color(nsColor: OnboardingSetupPalette.message))
                                        .padding(.top, 8)
                                }
                                if let choosePasswords = source.choosePasswords {
                                    Button("Import exported passwords instead…", action: choosePasswords)
                                        .buttonStyle(.plain).font(.system(size: 12)).padding(.top, 12)
                                }
                            }
                        }
                    }
                }
                BrowserImportSourceCard(layout: .setup, title: "Start fresh", icon: nil,
                    selected: freshStartSelected, selectionColor: selectionColor, action: chooseFreshStart)
                Button("Import a bookmarks file…", action: chooseFile)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: OnboardingSetupPalette.message))
                if let fileDescription {
                    Text(fileDescription).font(.system(size: 12)).multilineTextAlignment(.center)
                        .foregroundColor(Color(nsColor: OnboardingSetupPalette.message))
                }
            }
            .frame(width: 278)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your previous browser")
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
        default: return .white
        }
    }
}

/// ImportFeature.ProfilePicker is inline only for a source with several
/// profiles. Keep native source identity in the owner; this is presentation.
private struct OnboardingImportProfiles: View {
    let profiles: [OnboardingImportSourcePicker.Profile]
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
                    .padding(.vertical, 14).contentShape(Rectangle())
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
