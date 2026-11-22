import AppKit
import Combine
import Testing
@testable import ParcCore
@testable import ParcSidebar

private final class CompositionTextView: NSTextView {
    override func hasMarkedText() -> Bool { true }
}

@MainActor
struct FavoriteRenameTests {
    @MainActor private final class Favorite {
        let directory: URL
        let store: BrowserStore
        let id: UUID
        let undo = FolderUndoManager()

        init() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-favorite-rename-" + UUID().uuidString)
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: "https://favorite.test/original")!)
            store.updateTab(id, title: "Saved page")
            store.setKind(id, .favorite)
            self.directory = directory
            self.store = store
            self.id = id
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var tab: BrowserTab { store.state.tabs.first { $0.id == id }! }
    }

    @Test func anEmptyDialogNameNeverWritesOrClears() throws {
        let favorite = try Favorite()
        let original = favorite.tab
        let snapshot = favorite.store.state
        var publications = 0
        let observation = favorite.store.statePublisher.dropFirst().sink { _ in publications += 1 }
        #expect(throws: SidebarTabTitle.EditError.unavailable) { try favorite.store.saveFavoriteTitle(original, title: "") }
        #expect(favorite.store.state == snapshot)
        #expect(publications == 0)
        observation.cancel()
    }

    @Test func theDialogSuppliesLiteralTextForTheOriginalID() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "  Research 🪐  "))
        #expect(change.tabID == favorite.id)
        #expect(change.previousTitle == nil)
        #expect(change.title == "  Research 🪐  ")
    }

    @Test func onlyTheOriginalManualTitlePublishesAtomically() throws {
        let favorite = try Favorite()
        let original = favorite.tab
        favorite.store.updateTab(favorite.id, title: "Live title", url: "https://favorite.test/current")
        let before = favorite.store.state
        var publications = 0
        let observation = favorite.store.statePublisher.dropFirst().sink { _ in publications += 1 }
        let change = try #require(try favorite.store.saveFavoriteTitle(original, title: "Research"))
        var expected = before
        expected.tabs[expected.tabs.firstIndex { $0.id == favorite.id }!].customTitle = change.title
        #expect(favorite.store.state == expected)
        #expect(publications == 1)
        observation.cancel()
    }

    @Test func theOriginalSavedAndLiveDestinationsAreUntouched() throws {
        let favorite = try Favorite()
        let original = favorite.tab
        favorite.store.updateTab(favorite.id, title: "Live title", url: "https://favorite.test/current")
        _ = try favorite.store.saveFavoriteTitle(original, title: "Research")
        #expect(favorite.tab.savedURL == original.savedURL)
        #expect(favorite.tab.url == "https://favorite.test/current")
    }

    @Test func theFavoriteTitlePersists() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "Research"))
        #expect(try BrowserStore(directory: favorite.directory).state.tabs.first { $0.id == favorite.id }?.customTitle == change.title)
    }

    @Test func undoUsesTheSharedRenameName() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "Research"))
        _ = favorite.undo.appendTabTitleChange(change, store: favorite.store, available: { true }, onError: { _ in })
        #expect(favorite.undo.undoMenuItemTitle == "Undo Rename Item")
    }

    @Test func undoRestoresTheFavoriteFallbackWithoutChangingMembership() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "Research"))
        _ = favorite.undo.appendTabTitleChange(change, store: favorite.store, available: { true }, onError: { _ in })
        favorite.undo.undo()
        #expect(favorite.tab.customTitle == nil)
        #expect(favorite.tab.kind == .favorite)
    }

    @Test func redoAppliesTheOriginalName() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "Research"))
        _ = favorite.undo.appendTabTitleChange(change, store: favorite.store, available: { true }, onError: { _ in })
        favorite.undo.undo()
        favorite.undo.redo()
        #expect(favorite.tab.customTitle == change.title)
    }

    @Test func anUnchangedConfirmCreatesNoInverse() throws {
        let favorite = try Favorite()
        let change = try #require(try favorite.store.saveFavoriteTitle(favorite.tab, title: "Research"))
        #expect(try favorite.store.saveFavoriteTitle(favorite.tab, title: change.title!) == nil)
    }

    @Test func aCompetingSharedNameRefusesAStaleDialog() throws {
        let favorite = try Favorite()
        let original = favorite.tab
        let change = try #require(try favorite.store.saveFavoriteTitle(original, title: "Research"))
        #expect(throws: SidebarTabTitle.EditError.unavailable) { try favorite.store.saveFavoriteTitle(original, title: "Stale") }
        #expect(favorite.tab.customTitle == change.title)
    }

    @Test func unfavoritingInvalidatesTheOriginalEditor() throws {
        let favorite = try Favorite()
        let beforeMembership = favorite.tab
        favorite.store.setKind(favorite.id, .pinned)
        #expect(throws: SidebarTabTitle.EditError.unavailable) { try favorite.store.saveFavoriteTitle(beforeMembership, title: "Stale") }
        #expect(favorite.tab.kind == .pinned)
        #expect(favorite.tab.customTitle == nil)
    }

    @Test func aRealStorageFailureRetainsTheOriginalSharedState() throws {
        let favorite = try Favorite()
        let valid = favorite.tab
        let beforeFailure = favorite.store.state
        try FileManager.default.removeItem(at: favorite.directory)
        try Data().write(to: favorite.directory)
        #expect(throws: (any Error).self) { try favorite.store.saveFavoriteTitle(valid, title: "Failure") }
        #expect(favorite.store.state == beforeFailure)
        try FileManager.default.removeItem(at: favorite.directory)
    }

    @Test func aPendingNativeRetirementRefusesTheDialog() throws {
        let favorite = try Favorite()
        let pending = favorite.tab
        favorite.store.requestPageRetirement = { _, _, _ in }
        favorite.store.closeTab(favorite.id)
        #expect(throws: SidebarTabTitle.EditError.unavailable) { try favorite.store.saveFavoriteTitle(pending, title: "Retiring") }
    }

    @Test func aRefusedNativeRetirementPreservesTheActualOriginal() throws {
        let favorite = try Favorite()
        var completion: ((Bool) -> Void)?
        favorite.store.requestPageRetirement = { _, _, done in completion = done }
        favorite.store.closeTab(favorite.id)
        completion?(false)
        #expect(try favorite.store.saveFavoriteTitle(favorite.tab, title: "After cancellation") != nil)
    }

    private final class Commits {
        var values: [String] = []
        var finishes = 0
    }

    private func dialog(_ commits: Commits = Commits(), title: String = "Original") -> FavoriteRenameDialog {
        let dialog = FavoriteRenameDialog(title: title)
        dialog.isCurrent = { true }
        dialog.onCommit = { commits.values.append($0) }
        dialog.onFinish = { commits.finishes += 1 }
        return dialog
    }

    private func type(_ text: String, into dialog: FavoriteRenameDialog) {
        dialog.field.stringValue = text
        dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.field))
    }

    @Test func theDialogCarriesItsRecoveredStrings() {
        let dialog = dialog()
        #expect(dialog.sheetWindow.accessibilityLabel() == "Rename Tab…")
        #expect(dialog.field.placeholderString == "Keep it short and sweet!")
        #expect(dialog.dialog.confirmButton.title == "Rename")
        #expect(dialog.dialog.cancelButton?.title == "Cancel")
    }

    @Test func theFieldIsABorderless14PointFieldOnItsCardInsideTheSheet() {
        let dialog = dialog()
        #expect(!dialog.field.isBordered)
        #expect(!dialog.field.isBezeled)
        #expect(!dialog.field.drawsBackground)
        #expect(dialog.field.focusRingType == .none)
        #expect(dialog.field.font?.pointSize == 14)
        #expect(dialog.field.superview?.superview === dialog.sheetWindow.contentView)
    }

    @Test func theFieldIsANativeSingleLineSelectionAndTextOwner() {
        let dialog = dialog()
        #expect(dialog.field.usesSingleLineMode)
        #expect(dialog.field.isEditable)
        #expect(dialog.field.isSelectable)
    }

    @Test func requiredInputDisablesRename() {
        let dialog = dialog()
        type("", into: dialog)
        #expect(!dialog.dialog.confirmButton.isEnabled)
    }

    @Test func nonEmptyTextEnablesExplicitConfirm() {
        let dialog = dialog()
        type("Literal 🪐", into: dialog)
        #expect(dialog.dialog.confirmButton.isEnabled)
    }

    @Test(arguments: [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))])
    func theInputMethodOwnsMarkedTextReturnAndEscape(command: Selector) {
        let dialog = dialog()
        #expect(!dialog.control(dialog.field, textView: CompositionTextView(), doCommandBy: command))
    }

    @Test func nativeCaretKeysPassThrough() {
        let dialog = dialog()
        #expect(!dialog.control(dialog.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }

    @Test func anUnmarkedReturnInvokesExplicitConfirm() {
        let dialog = dialog()
        #expect(dialog.control(dialog.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    @Test func commitAndCompletionAreOnceOnly() {
        let commits = Commits()
        let dialog = dialog(commits)
        type("Literal 🪐", into: dialog)
        dialog.dialog.confirmButton.sendClick()
        dialog.cancel()
        #expect(commits.values == ["Literal 🪐"])
        #expect(commits.finishes == 1)
    }

    @Test func escapeCancelsWithoutAModelWrite() {
        let commits = Commits()
        let dialog = dialog(commits)
        _ = dialog.control(dialog.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(dialog.finished)
        #expect(commits.values.isEmpty)
    }

    @Test func invalidatingTheOriginalOwnerCancels() {
        let commits = Commits()
        let dialog = dialog(commits)
        dialog.isCurrent = { false }
        dialog.reconcile()
        #expect(dialog.finished)
        #expect(commits.values.isEmpty)
    }

    @Test func aFailedCommitKeepsTheNativeDraft() {
        let dialog = FavoriteRenameDialog(title: "Draft")
        dialog.isCurrent = { true }
        dialog.onCommit = { _ in throw NSError(domain: "Storage unavailable", code: 1) }
        dialog.dialog.confirmButton.sendClick()
        #expect(!dialog.finished)
        #expect(dialog.field.stringValue == "Draft")
    }

    @Test func anExplicitRetryCommitsThePreservedDraft() {
        let commits = Commits()
        var fails = true
        let dialog = FavoriteRenameDialog(title: "Draft")
        dialog.isCurrent = { true }
        dialog.onCommit = { value in
            if fails { throw NSError(domain: "Storage unavailable", code: 1) }
            commits.values.append(value)
        }
        dialog.dialog.confirmButton.sendClick()
        fails = false
        dialog.dialog.confirmButton.sendClick()
        #expect(dialog.finished)
        #expect(commits.values == ["Draft"])
    }
}
