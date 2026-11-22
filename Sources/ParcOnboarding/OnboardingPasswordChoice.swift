import AppKit
import SwiftUI

struct OnboardingPasswordChoice: View {
    let installExtension: Bool
    let enabled: Bool
    let selectionColor: NSColor
    let onSelect: (Bool) -> Void

    var body: some View {
        VStack(spacing: 22) {
            choice("Add iCloud Passwords Extension", detail: "Recommended", selected: installExtension) {
                onSelect(true)
            }
            choice("Import Passwords from Safari", detail: "Manual", selected: !installExtension) {
                onSelect(false)
            }
        }
        .frame(width: 339)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safari passwords")
    }

    private func choice(_ title: String, detail: String, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        OnboardingChoiceRow(selected: selected, preferred: false, label: title + ", " + detail,
                            selectionColor: selectionColor, action: action) {
            VStack(alignment: .leading) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail).font(.system(size: 13)).opacity(0.5)
            }
        }
    }
}
