import AppKit

/// Settings owns only this sheet. Committed removal outlives its presentation.
@MainActor
final class ProfileRemovalSheet: ProfileRemovalDialog {
    let profileID: UUID
    let expectedName: String

    init(profile: BrowserProfile, tabCount: Int, historyCount: Int) {
        profileID = profile.id
        expectedName = profile.name
        let text = "Deleting \(profile.name) will permanently remove any cookies, history, preferences, and logins that belong to this Profile.\n\nThis also removes \(tabCount) saved tabs and \(historyCount) local history entries. Saved captures, downloaded files and Easels stay on this Mac.\n\nTo continue, please type the name of this Profile:"
        super.init(title: "Delete this Profile", detail: Self.copy(text, emphasizing: [NSRange(location: "Deleting ".utf16.count, length: profile.name.utf16.count)]),
            confirmation: profile.name, accessibilityLabel: "Type the name of the profile to delete")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func focusName() { focusConfirmation() }
    func setProgress(_ text: String, canCancel: Bool) {
        showState(text, busy: true, canCancel: canCancel)
    }
    func showFailure(_ text: String, isRecovery: Bool, canCancel: Bool) {
        showState(text, canCancel: canCancel, recovery: isRecovery, error: true)
    }
    func showComplete() {
        showState("“\(expectedName)” was removed. Downloaded files, saved captures and Easels remain on this Mac.", complete: true)
    }
}
