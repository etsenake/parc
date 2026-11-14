import AppKit

@MainActor
final class InterProfileMoveDialog: NSObject {
    let dialog: ParcDialog

    init(prompt: InterProfileMovePrompt) {
        dialog = ParcDialog(.init(title: prompt.titleSegments, message: prompt.messageSegments,
                                 confirm: InterProfileMovePrompt.confirmTitle, cancel: InterProfileMovePrompt.cancelTitle,
                                 suppression: InterProfileMovePrompt.suppressionTitle,
                                 width: CGFloat(InterProfileMovePrompt.dialogWidth)))
        super.init()
        dialog.panel.setAccessibilityLabel(prompt.title)
    }

    func begin(for window: NSWindow, completion: @escaping (InterProfileMoveDecision) -> Void) -> Bool {
        dialog.begin(for: window) { response in
            completion(InterProfileMovePrompt.decision(confirmed: response != .cancel, suppressed: response == .alwaysConfirm))
        }
    }
}
