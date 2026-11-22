import AppKit
import Combine
import ParcTestSupport
import Testing
@testable import ParcCore
@testable import Parc
@testable import ParcKit
@testable import ParcSettings

@MainActor
private final class DetachedSheetHost: NSWindow {
    private var queuedSheets: [(NSWindow, ((NSApplication.ModalResponse) -> Void)?)] = []

    init() {
        _ = NSApplication.shared
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                   styleMask: .borderless, backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }

    override var attachedSheet: NSWindow? { queuedSheets.first?.0 }

    override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        queuedSheets.append((sheetWindow, handler))
    }

    override func endSheet(_ sheetWindow: NSWindow) {
        endSheet(sheetWindow, returnCode: .stop)
    }

    override func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {
        guard let offset = queuedSheets.firstIndex(where: { $0.0 === sheetWindow }) else { return }
        let (_, completion) = queuedSheets.remove(at: offset)
        completion?(returnCode)
        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: self)
    }
}

@MainActor
private func sendButtonAction(_ button: NSButton) throws {
    let action = try #require(button.action)
    #expect(NSApplication.shared.sendAction(action, to: button.target, from: button))
}

struct ParcDialogTests {
    @MainActor private final class ComposingText: NSTextView {
        override func hasMarkedText() -> Bool { true }
    }

    @Test(arguments: [("", false), (" \n ", false), ("Name", true)])
    @MainActor func theRequiredFieldEnablesConfirmationOnlyForNonblankText(example: (String, Bool)) throws {
        _ = NSApplication.shared
        var content = ParcDialog.Content(title: "Rename", confirm: "Save", cancel: "Cancel")
        content.field = .init(value: "", placeholder: "Name")
        let dialog = ParcDialog(content)
        let field = try #require(dialog.textField)
        field.stringValue = example.0
        dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(dialog.confirmButton.isEnabled == example.1)
    }

    @Test(arguments: [true, false])
    @MainActor func destructiveStylingBelongsToTheConfirmation(destructive: Bool) {
        _ = NSApplication.shared
        var content = ParcDialog.Content(title: "Delete the Space?", confirm: "Delete", cancel: "Cancel")
        content.destructive = destructive
        let dialog = ParcDialog(content)
        #expect(dialog.confirmButton.destructive == destructive)
        #expect(dialog.cancelButton?.destructive == false)
    }

    @Test @MainActor func voiceOverIdentifiesTheConfirmationAsTheDefault() {
        _ = NSApplication.shared
        let dialog = ParcDialog(.init(title: "Export complete"))
        #expect((dialog.panel.accessibilityDefaultButton() as? NSButton) === dialog.confirmButton)
        #expect(dialog.confirmButton.keyEquivalent == "\r")
    }

    @Test(arguments: [false, true])
    @MainActor func aSuppressedMoveReturnsItsDistinctDecision(suppression: Bool) throws {
        let host = DetachedSheetHost()
        let move = InterProfileMoveDialog(prompt: InterProfileMovePrompt(tabCount: 1, spaceName: "Work"))
        var decisions: [InterProfileMoveDecision] = []
        #expect(move.begin(for: host) { decisions.append($0) })
        let checkbox = try #require(move.dialog.suppression)
        checkbox.state = suppression ? .on : .off
        try sendButtonAction(move.dialog.confirmButton)
        #expect(decisions == [suppression ? .alwaysProceed : .proceed])
    }

    @Test @MainActor func escapeAbortsAMove() {
        let host = DetachedSheetHost()
        let move = InterProfileMoveDialog(prompt: InterProfileMovePrompt(tabCount: 1, spaceName: "Work"))
        var decisions: [InterProfileMoveDecision] = []
        #expect(move.begin(for: host) { decisions.append($0) })
        move.dialog.panel.cancelOperation(nil)
        #expect(decisions == [.abort])
    }

    @Test @MainActor func escapeKeepsAMultipleActionDialogOpenWithoutACancelButton() {
        let host = DetachedSheetHost()
        var content = ParcDialog.Content(title: "Page stopped responding", confirm: "Retry")
        content.secondary = "Close Page"
        content.auxiliary = "Keep Open"
        let dialog = ParcDialog(content)
        var decisions: [ParcDialog.Response] = []
        #expect(dialog.begin(for: host) { decisions.append($0) })
        dialog.panel.cancelOperation(nil)
        #expect(host.attachedSheet === dialog.panel)
        #expect(decisions.isEmpty)
        host.endSheet(dialog.panel)
    }

    @Test(arguments: [false, true])
    @MainActor func anOccupiedHostAdmitsOnlyQueuedDialogs(queued: Bool) throws {
        let host = DetachedSheetHost()
        let old = ParcDialog(.init(title: "First"))
        let next = ParcDialog(.init(title: "Second"))
        #expect(old.begin(for: host) { _ in })
        #expect(next.begin(for: host, queued: queued) { _ in } == queued)
        try sendButtonAction(old.confirmButton)
        #expect(host.attachedSheet === (queued ? next.panel : nil))
        if queued { try sendButtonAction(next.confirmButton) }
    }

    @Test @MainActor func theSameDialogCannotBeAttachedTwice() throws {
        let host = DetachedSheetHost()
        let dialog = ParcDialog(.init(title: "Confirm"))
        #expect(dialog.begin(for: host) { _ in })
        #expect(!dialog.begin(for: host, queued: true) { _ in })
        try sendButtonAction(dialog.confirmButton)
    }

    @Test(arguments: [true, false])
    @MainActor func auxiliaryAndSecondaryButtonsReportDifferentResponses(auxiliary: Bool) throws {
        let host = DetachedSheetHost()
        var content = ParcDialog.Content(title: "Page stopped responding", confirm: "Retry")
        content.secondary = "Close Page"
        content.auxiliary = "Keep Open"
        let dialog = ParcDialog(content)
        var responses: [ParcDialog.Response] = []
        #expect(dialog.begin(for: host) { responses.append($0) })
        let button = try #require(auxiliary ? dialog.auxiliaryButton : dialog.secondaryButton)
        try sendButtonAction(button)
        #expect(responses == [auxiliary ? .auxiliary : .secondary])
    }

    @Test(arguments: [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))])
    @MainActor func markedTextKeepsTheFieldEditorsKeyCommand(command: Selector) throws {
        _ = NSApplication.shared
        var content = ParcDialog.Content(title: "Rename", confirm: "Save", cancel: "Cancel")
        content.field = .init(value: "Name", placeholder: "")
        let dialog = ParcDialog(content)
        let field = try #require(dialog.textField)
        let handled = dialog.control(field, textView: ComposingText(), doCommandBy: command)
        #expect(!handled)
    }

    @Test @MainActor func errorDetailsAreSelectableAndReadOnly() {
        _ = NSApplication.shared
        let content = ParcDialogStyle.detailsView("First line\nSecond line", size: CGSize(width: 360, height: 120))
        let details = content.documentView as? NSTextView
        #expect(details?.string == "First line\nSecond line")
        #expect(details?.isSelectable == true)
        #expect(details?.isEditable == false)
        #expect(content.hasVerticalScroller)
    }
}

struct QuitWarningTests {
    private let key = "parc.quitWarning.v1"

    @MainActor private func withPreferences(_ body: (QuitWarningPreferences, UserDefaults) throws -> Void) throws {
        let defaults = try #require(TestDefaults("parc.quit-warning."))
        _ = NSApplication.shared
        try body(QuitWarningPreferences(defaults: defaults), defaults)
    }

    @Test @MainActor func theWarningStartsEnabledWithoutWritingTheDefault() throws {
        try withPreferences { preferences, defaults in
            #expect(preferences.state.isEnabled)
            #expect(defaults.object(forKey: key) == nil)
        }
    }

    @Test @MainActor func keepingTheSamePreferenceDoesNotPublishAgain() throws {
        try withPreferences { preferences, _ in
            var changes = 0
            let observer = preferences.$state.dropFirst().sink { _ in changes += 1 }
            try preferences.setEnabled(true)
            #expect(changes == 0)
            withExtendedLifetime(observer) {}
        }
    }

    @Test(arguments: [false, true])
    @MainActor func aQueuedQuitWarningRespectsCancellation(cancelled: Bool) throws {
        try withPreferences { preferences, _ in
            let host = DetachedSheetHost()
            let blocker = ParcDialog(.init(title: "Sign in"))
            #expect(blocker.begin(for: host) { _ in })
            var pending: [@MainActor () -> Void] = []
            let warning = ApplicationQuitWarning(preferences: preferences) { _, work in pending.append(work) }
            warning.isCurrent = { true }
            var decisions: [Bool] = []
            warning.onDecision = { decisions.append($0) }
            warning.present(in: host)
            #expect(warning.isWaiting)
            #expect(host.attachedSheet === blocker.panel)
            if cancelled { warning.cancel() }
            host.endSheet(blocker.panel)
            pending.forEach { $0() }
            #expect(host.attachedSheet === (cancelled ? nil : warning.window))
            #expect(decisions == (cancelled ? [false] : []))
            warning.cancel()
        }
    }

    @Test @MainActor func cancellingTheWarningDecidesOnlyOnce() throws {
        try withPreferences { preferences, _ in
            let warning = ApplicationQuitWarning(preferences: preferences)
            warning.isCurrent = { true }
            var decisions: [Bool] = []
            warning.onDecision = { decisions.append($0) }
            try sendButtonAction(warning.cancelButton)
            try sendButtonAction(warning.quit)
            #expect(decisions == [false])
            #expect(warning.onDecision == nil)
            #expect(!warning.quit.isEnabled)
        }
    }

    @Test @MainActor func ordinaryQuitDoesNotTurnOffLaterWarnings() throws {
        try withPreferences { preferences, defaults in
            let warning = ApplicationQuitWarning(preferences: preferences)
            warning.isCurrent = { true }
            var decisions: [Bool] = []
            warning.onDecision = { decisions.append($0) }
            try sendButtonAction(warning.quit)
            #expect(decisions == [true])
            #expect(QuitWarningPreferences(defaults: defaults).state.isEnabled)
        }
    }

    @Test @MainActor func permanentlySuppressingTheWarningSavesBeforeApprovingQuit() throws {
        try withPreferences { preferences, defaults in
            let warning = ApplicationQuitWarning(preferences: preferences)
            warning.isCurrent = { true }
            var policy: Bool?
            warning.onDecision = { approved in
                #expect(approved)
                policy = QuitWarningPreferences(defaults: defaults).state.isEnabled
            }
            try sendButtonAction(warning.suppress)
            #expect(policy == false)
        }
    }

    @Test @MainActor func aStaleQuitWarningCannotDisableThePreference() throws {
        try withPreferences { preferences, _ in
            let warning = ApplicationQuitWarning(preferences: preferences)
            var decisions: [Bool] = []
            warning.onDecision = { decisions.append($0) }
            try sendButtonAction(warning.suppress)
            #expect(decisions == [false])
            #expect(preferences.state.isEnabled)
        }
    }

    @Test @MainActor func aFuturePreferenceLeavesOrdinaryQuitAvailableAndPreservesTheRecord() throws {
        try withPreferences { _, defaults in
            let future = Data(#"{"version":99,"isEnabled":false,"future":"preserve"}"#.utf8)
            defaults.set(future, forKey: key)
            let preferences = QuitWarningPreferences(defaults: defaults)
            let warning = ApplicationQuitWarning(preferences: preferences)
            #expect(preferences.loadError && preferences.state.isEnabled)
            #expect(!warning.suppress.isEnabled && warning.quit.isEnabled)
            #expect(throws: QuitWarningPreferences.Failure.unavailable) { try preferences.setEnabled(false) }
            #expect(defaults.data(forKey: key) == future)
        }
    }
}
