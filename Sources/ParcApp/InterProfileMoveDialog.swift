import AppKit

///
///
///
///
/// "Don’t ask again" suppression checkbox, Cancel and the "Move it" confirm.
///
@MainActor
final class InterProfileMoveDialog: NSObject {
    let dialog: PArcDialog

    init(prompt: InterProfileMovePrompt) {
        dialog = PArcDialog(.init(title: prompt.titleSegments, message: prompt.messageSegments,
                                 confirm: InterProfileMovePrompt.confirmTitle, cancel: InterProfileMovePrompt.cancelTitle,
                                 suppression: InterProfileMovePrompt.suppressionTitle,
                                 width: CGFloat(InterProfileMovePrompt.dialogWidth)))
        super.init()
        dialog.panel.setAccessibilityLabel(prompt.title)
    }

    /// Begins the sheet; the decision arrives after the sheet has ended.
    func begin(for window: NSWindow, completion: @escaping (InterProfileMoveDecision) -> Void) -> Bool {
        dialog.begin(for: window) { response in
            completion(InterProfileMovePrompt.decision(confirmed: response != .cancel, suppressed: response == .alwaysConfirm))
        }
    }
}
