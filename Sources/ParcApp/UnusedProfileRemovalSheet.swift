import AppKit

/// The review captures exact IDs/names. Presentation never expands a retry to
/// newly created Profiles or substitutes the current Settings selection.
@MainActor
final class UnusedProfileRemovalSheet: ProfileRemovalDialog {
    let profiles: [BrowserProfile]
    private var submissionFailure: String?

    init(profiles: [BrowserProfile]) {
        self.profiles = profiles
        let names = profiles.map(\.name).joined(separator: ", ")
        let prefix = "Deleting unused Profiles will permanently remove any cookies, history, preferences, and logins that belong to those Profiles. Saved tabs are also removed; downloaded files, captures and Easels stay on this Mac.\n\nThe unused Profiles to be deleted are: "
        let text = prefix + names + "\n\nTo continue, please type CONFIRM"
        let emphasis = [NSRange(location: prefix.utf16.count, length: names.utf16.count),
                        NSRange(location: text.utf16.count - 7, length: 7)]
        super.init(title: "Delete unused Profiles", detail: Self.copy(text, emphasizing: emphasis),
            confirmation: "CONFIRM", accessibilityLabel: "Type CONFIRM to delete the listed unused Profiles")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func willSubmit() { submissionFailure = nil }

    func refresh(store: BrowserStore, controller: ProfileRemovalController) {
        guard submitted else { return }
        let remaining = profiles.filter { expected in store.state.profiles.contains { $0.id == expected.id } }
        let running = remaining.contains { controller.status(for: $0.id)?.running == true }
        if running { submissionFailure = nil }
        let rows = NSMutableAttributedString(string: "")
        for profile in profiles {
            let outcome = remaining.contains { $0.id == profile.id } ?
                (controller.status(for: profile.id)?.message ?? "Not removed") : "Removed"
            if rows.length > 0 { rows.append(NSAttributedString(string: "\n\n")) }
            rows.append(Self.copy(profile.name + " — " + outcome, emphasizing: [NSRange(location: 0, length: profile.name.utf16.count)], size: 13))
        }
        setResults(rows)
        let count = profiles.count - remaining.count
        if remaining.isEmpty {
            showState("Removed all \(profiles.count) Profiles. Downloaded files, captures and Easels remain on this Mac.", complete: true)
        } else if running {
            showState("Removed \(count) of \(profiles.count) Profiles. Closing cancels preparations; committed removals finish in the background.", busy: true, canCancel: false)
        } else {
            showState(submissionFailure ?? "Removed \(count) of \(profiles.count) Profiles. Review the results above, then retry the remaining Profiles or close.", error: true)
        }
    }
    func showFailure(_ error: Error) {
        submissionFailure = error.localizedDescription
        showState(error.localizedDescription, error: true)
    }
}
