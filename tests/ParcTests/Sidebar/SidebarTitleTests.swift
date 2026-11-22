import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

private final class TitleTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor
struct SidebarTitleTests {
    @MainActor private final class Anchor {
        let directory: URL
        let store: BrowserStore
        let id: UUID
        let original: BrowserTab

        init() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-title-" + UUID().uuidString)
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: "https://example.test/anchor")!)
            store.updateTab(id, title: "Original saved title")
            store.setKind(id, .pinned)
            self.directory = directory
            self.store = store
            self.id = id
            original = store.state.tabs.first { $0.id == id }!
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        var tab: BrowserTab { store.state.tabs.first { $0.id == id }! }

        func navigateAway() -> BrowserTab {
            store.updateTab(id, title: "Live destination title", url: "https://example.test/away")
            return tab
        }
    }

    @Test func theSavedLabelIsDisplayed() throws {
        #expect(SidebarTabTitle.display(try Anchor().original) == "Original saved title")
    }

    @Test func navigationDoesNotReplaceTheSavedSidebarLabel() throws {
        let anchor = try Anchor()
        #expect(SidebarTabTitle.display(anchor.navigateAway()) == "Original saved title")
    }

    @Test func thePageTitleRemainsIndependent() throws {
        #expect(try Anchor().navigateAway().title == "Live destination title")
    }

    @Test func aManualOverrideIsTrimmed() throws {
        let anchor = try Anchor()
        try anchor.store.saveSidebarTitle(anchor.navigateAway(), title: "  My project\n")
        #expect(anchor.tab.customTitle == "My project")
        #expect(SidebarTabTitle.display(anchor.tab) == "My project")
    }

    @Test func renamingChangesNoDestinationOrPageTitle() throws {
        let anchor = try Anchor()
        let away = anchor.navigateAway()
        try anchor.store.saveSidebarTitle(away, title: "My project")
        let custom = anchor.tab
        #expect(custom.url == away.url)
        #expect(custom.title == away.title)
        #expect(custom.savedURL == away.savedURL)
        #expect(custom.savedTitle == away.savedTitle)
    }

    @Test func renamingRecordsNoSelectionOrHistoryEvent() throws {
        let anchor = try Anchor()
        let away = anchor.navigateAway()
        let before = anchor.store.state
        try anchor.store.saveSidebarTitle(away, title: "My project")
        #expect(anchor.store.state.selectedTabIDs == before.selectedTabIDs)
        #expect(anchor.store.state.history == before.history)
    }

    @Test func aCustomTitlePersistsIndependently() throws {
        let anchor = try Anchor()
        try anchor.store.saveSidebarTitle(anchor.navigateAway(), title: "My project")
        #expect(try BrowserStore(directory: anchor.directory).state.tabs.first { $0.id == anchor.id }?.customTitle == "My project")
    }

    @Test func aConcurrentRenameCannotOverwrite() throws {
        let anchor = try Anchor()
        let away = anchor.navigateAway()
        try anchor.store.saveSidebarTitle(away, title: "My project")
        #expect(throws: SidebarTabTitle.EditError.unavailable) { try anchor.store.saveSidebarTitle(away, title: "Stale") }
        #expect(anchor.tab.customTitle == "My project")
    }

    @Test func anEmptyEditRestoresTheSavedTitle() throws {
        let anchor = try Anchor()
        try anchor.store.saveSidebarTitle(anchor.navigateAway(), title: "My project")
        let custom = anchor.tab
        try anchor.store.saveSidebarTitle(custom, title: "  \n")
        #expect(anchor.tab.customTitle == nil)
        #expect(SidebarTabTitle.display(anchor.tab) == anchor.original.savedTitle)
    }

    @Test func aLiveUpdateSurvivesTheEditTransaction() throws {
        let anchor = try Anchor()
        try anchor.store.saveSidebarTitle(anchor.navigateAway(), title: "My project")
        let custom = anchor.tab
        anchor.store.updateTab(anchor.id, title: "Updated live page", url: "https://example.test/next")
        try anchor.store.saveSidebarTitle(custom, title: "  \n")
        #expect(anchor.tab.title == "Updated live page")
    }

    @Test func aMissingSavedTitleUsesTheSourceURL() throws {
        var tab = try Anchor().original
        tab.savedTitle = " \n"
        tab.savedURL = "https://example.test/fallback"
        #expect(SidebarTabTitle.display(tab) == tab.savedURL)
    }

    @Test func aBlankSourceShowsThePlaceholder() throws {
        var tab = try Anchor().original
        tab.savedTitle = " \n"
        tab.savedURL = "about:blank"
        #expect(SidebarTabTitle.display(tab) == "New tab")
    }

    @Test func anOldSessionDecodesWithoutAnInventedOverride() throws {
        let anchor = try Anchor()
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(anchor.original)) as? [String: Any])
        legacy.removeValue(forKey: "customTitle")
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.customTitle == nil)
        #expect(decoded.title == anchor.original.title)
    }

    @Test func aMovedIdentityInvalidatesTheEdit() throws {
        let original = try Anchor().original
        var moved = original
        moved.spaceID = UUID()
        #expect(!SidebarTabTitle.sameItemForEditing(moved, original))
    }

    @Test func aFolderChangeInvalidatesTheEdit() throws {
        let original = try Anchor().original
        var moved = original
        moved.folderID = UUID()
        #expect(!SidebarTabTitle.sameItemForEditing(moved, original))
    }

    @Test func anArchivedIdentityInvalidatesTheEdit() throws {
        let original = try Anchor().original
        var moved = original
        moved.archivedAt = Date()
        #expect(!SidebarTabTitle.sameItemForEditing(moved, original))
    }

    @Test func aPrivateCustomTitleIsUsableWithoutPersistentStorage() throws {
        let anchor = try Anchor()
        let privateDirectory = anchor.directory.appendingPathComponent("uncreated-private")
        let privateStore = BrowserStore(privateParentProfileID: anchor.original.profileID, engineProfilePath: "/not-opened",
                                        directory: privateDirectory, settings: anchor.store.state.settings)
        let privateID = privateStore.openResolvedURL(URL(string: "https://private.test/")!)
        try privateStore.saveSidebarTitle(privateStore.state.tabs.first { $0.id == privateID }!, title: "Private name")
        #expect(privateStore.state.tabs.first { $0.id == privateID }?.customTitle == "Private name")
        #expect(!FileManager.default.fileExists(atPath: privateDirectory.path))
    }

    @Test func aFailedPersistenceDoesNotPublishATitle() throws {
        let anchor = try Anchor()
        try anchor.store.save()
        let failedState = anchor.store.state
        let tab = anchor.tab
        try FileManager.default.removeItem(at: anchor.directory)
        try Data().write(to: anchor.directory)
        #expect(throws: (any Error).self) { try anchor.store.saveSidebarTitle(tab, title: "Must not publish") }
        #expect(anchor.store.state == failedState)
        try FileManager.default.removeItem(at: anchor.directory)
    }

    @MainActor private final class Editor {
        let field = SidebarTitleField()
        let window = TitleTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: 220, height: 80),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        var values: [String?] = []

        init(attached: Bool = true) {
            window.isReleasedWhenClosed = false
            field.onFinish = { [weak self] in self?.values.append($0) }
            field.frame = NSRect(x: 20, y: 20, width: 180, height: 22)
            if attached { window.contentView!.addSubview(field) }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var textView: NSTextView { field.currentEditor() as! NSTextView }

        func type(_ text: String) {
            textView.string = text
            textView.didChangeText()
        }

        func drainMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @Test func aDetachedEditorRefusesFocus() {
        let editor = Editor(attached: false)
        #expect(!editor.field.begin(title: "Detached"))
    }

    @Test func anAttachedEditorBegins() {
        let editor = Editor()
        #expect(editor.field.begin(title: "Original"))
    }

    @Test func theNativeEditorSelectsTheWholeTitle() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        #expect(editor.field.currentEditor()?.selectedRange == NSRange(location: 0, length: 8))
    }

    @Test func ordinaryCaretEditingRemainsNative() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        #expect(!editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.moveLeft(_:))))
    }

    @Test func returnPreservesAnActiveInputMethodComposition() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        editor.textView.setMarkedText("入力", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    @Test func escapeConsumesOnlyTheLocalEditorCancellation() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        #expect(editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    }

    @Test func cancellingPublishesNoText() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        _ = editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        #expect(editor.values.count == 1)
        #expect(editor.values[0] == nil)
        #expect(!editor.field.editingTitle)
    }

    @Test func completionOccursOnlyOnce() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        _ = editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        editor.field.cancel()
        #expect(editor.values.count == 1)
    }

    @Test func returnCompletesTheEditWithTheActualText() {
        let editor = Editor()
        _ = editor.field.begin(title: "Original")
        editor.type("Changed")
        #expect(editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.values == ["Changed"])
    }

    @Test func detachmentCancelsInsteadOfSavingTheDraft() {
        let editor = Editor()
        _ = editor.field.begin(title: "Again")
        editor.field.removeFromSuperview()
        #expect(editor.values.count == 1)
        #expect(editor.values[0] == nil)
    }

    @Test func aQueuedEndEditCannotPublishAfterDetachmentCancellation() async {
        let editor = Editor()
        _ = editor.field.begin(title: "Again")
        editor.field.removeFromSuperview()
        await editor.drainMainQueue()
        #expect(editor.values.count == 1)
    }

    @Test func aReattachedEditorHasAFreshSession() {
        let editor = Editor()
        _ = editor.field.begin(title: "Again")
        editor.field.removeFromSuperview()
        editor.window.contentView!.addSubview(editor.field)
        #expect(editor.field.begin(title: "Click away"))
    }

    @Test func nativeFocusLossCompletesOnce() async {
        let editor = Editor()
        _ = editor.field.begin(title: "Click away")
        editor.type("Blurred title")
        _ = editor.window.makeFirstResponder(editor.window.contentView)
        await editor.drainMainQueue()
        #expect(editor.values == ["Blurred title"])
    }
}
