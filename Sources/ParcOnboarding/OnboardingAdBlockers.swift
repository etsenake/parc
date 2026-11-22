import AppKit
import ParcCore
import SwiftUI

struct OnboardingAdBlockersChoice: View {
    let blockers: [OnboardingDraft.ImportedAdBlocker]
    let choice: OnboardingDraft.AdBlockerChoice?
    let enabled: Bool
    let selectionColor: NSColor
    let onSelect: (OnboardingDraft.AdBlockerChoice) -> Void

    static func height(blockerCount: Int) -> CGFloat {
        guard blockerCount > 0 else { return 2 * rowHeight + spacing }
        let rows = CGFloat(blockerCount + 1)
        return rows * rowHeight + rows * spacing + 1
    }
    private static let rowHeight: CGFloat = 67
    private static let spacing: CGFloat = 22

    var body: some View {
        VStack(spacing: Self.spacing) {
            if blockers.isEmpty {
                OnboardingChoiceRow(selected: choice == .uBlock, preferred: false,
                    label: "YES, block away!", selectionColor: selectionColor,
                    action: { onSelect(.uBlock) }) {
                        Text("YES").bold() + Text(", block away!")
                    }
                OnboardingChoiceRow(selected: choice == OnboardingDraft.AdBlockerChoice.none, preferred: false,
                    label: "NO, I was looking for new socks.", selectionColor: selectionColor,
                    action: { onSelect(.none) }) {
                        Text("NO").bold() + Text(", I was looking for new socks.")
                    }
            } else {
                ForEach(blockers) { blocker in
                    OnboardingChoiceRow(selected: choice?.isSelected(blocker.identifier) == true,
                        preferred: false, label: blocker.displayName, selectionColor: selectionColor,
                        action: { onSelect(.keep(blocker.identifier)) }) {
                            Text(blocker.displayName).font(.system(size: 16, weight: .medium))
                        }
                }
                Divider()
                OnboardingChoiceRow(selected: choice == OnboardingDraft.AdBlockerChoice.none, preferred: false,
                    label: "Don't block ads, All ad blockers will be removed",
                    selectionColor: selectionColor, action: { onSelect(.none) }) {
                        VStack(alignment: .leading) {
                            Text("Don't block ads").bold()
                            Text("All ad blockers will be removed")
                                .font(.system(size: 13)).opacity(0.5)
                        }
                    }
            }
        }
        .frame(width: 339)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ad blockers")
    }
}
