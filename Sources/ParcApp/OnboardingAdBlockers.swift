import AppKit
import SwiftUI

///
/// native option is omitted because Parc has no native ad blocker.
struct OnboardingAdBlockersChoice: View {
    let blockers: [OnboardingDraft.ImportedAdBlocker]
    let choice: OnboardingDraft.AdBlockerChoice?
    let enabled: Bool
    let selectionColor: NSColor
    let onSelect: (OnboardingDraft.AdBlockerChoice) -> Void

    var body: some View {
        VStack(spacing: 22) {
            ForEach(blockers) { blocker in
                OnboardingChoiceRow(selected: choice?.isSelected(blocker.identifier) == true,
                    preferred: false, label: blocker.displayName, selectionColor: selectionColor,
                    action: { onSelect(.keep(blocker.identifier)) }) {
                        Text(blocker.displayName).font(.system(size: 16, weight: .medium))
                    }
            }
            OnboardingChoiceRow(selected: choice == OnboardingDraft.AdBlockerChoice.none, preferred: false,
                label: "Don't block ads, All ad blockers will be removed",
                selectionColor: selectionColor, action: { onSelect(.none) }) {
                    VStack(alignment: .leading) {
                        Text("Don't block ads").font(.system(size: 16, weight: .medium))
                        Text("All ad blockers will be removed, I was looking for new socks.")
                            .font(.system(size: 13)).opacity(0.5)
                    }
                }
        }
        .frame(width: 339)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ad blockers")
    }
}
