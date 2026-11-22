import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct ArchivePreviewBackdropFocusTests {
    @MainActor private final class PreviewResponder: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultsName = "Parc.ArchiveBackdrop." + UUID().uuidString
        let host = SplitResizeCommandAvailabilityTests.Host.make()
        let store: BrowserStore
        let owner: BrowserWindowController
        let defaults: UserDefaults

        init() throws {
            defaults = try #require(UserDefaults(suiteName: defaultsName))
            store = try BrowserStore(directory: directory)
            store.scheduleDeferredSave = { _, _ in }
            owner = try BrowserWindowController(store: store, ownership: NativePageOwnership(), windowHost: host)
            host.contentView?.addSubview(owner.splitView)
            owner.splitView.frame = host.contentView?.bounds ?? .zero
        }

        deinit {
            MainActor.assumeIsolated {
                owner.residentCommandBar?.dismiss(restoreFocus: false)
                owner.noteEditors.removeAll()
                host.close()
            }
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: directory)
        }

        func pane(for page: InternalPage) throws -> (BrowserPane, BrowserTab) {
            let url = try #require(URL(string: page.urlString))
            let id = store.openResolvedURL(url)
            let tab = try #require(store.state.tab(id))
            owner.presentation.captureCommand(store.state, available: { _ in true })
            let pane = BrowserPane(frame: owner.splitView.bounds)
            owner.panes[id] = pane
            owner.renderedPaneIDs = [id]
            owner.splitView.addArrangedSubview(pane)
            return (pane, tab)
        }

        func closePreviewAndReturnFocus() throws {
            let card = PeekCard(parent: nil, parentTabID: owner.currentTabID ?? owner.activeSpaceID,
                                sourceSpaceID: owner.activeSpaceID, returnsPage: false)
            let preview = PreviewResponder(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
            card.view.content.addSubview(preview)
            host.contentView?.addSubview(card.view)
            try #require(host.makeFirstResponder(preview))
            let focus = try #require(card.takeFocusReturn())

            card.finish()
            owner.restoreFocusBehindPeek(focus, host, { true })
        }
    }

    @Test func droppingPreviewFocusReturnsTheKeyboardToTheNote() throws {
        let fixture = try Fixture()
        let url = fixture.directory.appendingPathComponent("Journal.md")
        try Data("# Journal\n\nFirst entry.\n".utf8).write(to: url)
        let files = IsolatedNoteFiles.make()
        let editor = NotePageViewController(file: try files.open(url))
        let (pane, tab) = try fixture.pane(for: .note(url))
        fixture.owner.noteEditors[tab.id] = .init(profileID: tab.profileID, editor: editor, originalTab: tab)
        pane.showNote(editor)
        pane.layoutSubtreeIfNeeded()

        try fixture.closePreviewAndReturnFocus()

        #expect(editor.editor.ownsFocus)
    }

    @Test func droppingPreviewFocusReturnsTheKeyboardToTheEasel() throws {
        let fixture = try Fixture()
        let directory = fixture.directory.appendingPathComponent("Easels")
        let store = try EaselEditorViewController.sharedStore(directory: directory)
        let session = try store.create(title: "Board")
        let id = session.document.id
        let easelIcons = EaselTabIcons(files: IsolatedNoteFiles.make())
        let editor = try EaselEditorViewController(directory: directory, documentID: id, easelIcons: easelIcons)
        let (pane, tab) = try fixture.pane(for: .easel(id))
        fixture.owner.easelEditors[tab.id] = .init(documentID: id, profileID: tab.profileID, editor: editor, originalTab: tab)
        pane.showNativeContent(editor.view)
        pane.layoutSubtreeIfNeeded()

        try fixture.closePreviewAndReturnFocus()

        #expect(fixture.host.firstResponder === editor.canvas)
    }

    @Test func droppingPreviewFocusReturnsTheKeyboardToTheStartPageSearchField() throws {
        let fixture = try Fixture()
        let start = fixture.owner.loadStartPage()
        fixture.owner.splitView.addArrangedSubview(start)
        start.frame = fixture.owner.splitView.bounds
        let bar = CommandBar(parent: fixture.host, tabs: [], history: [], currentURL: nil, profilePath: "", page: nil,
                             resident: true, shortcuts: KeyboardShortcuts(mainMenu: { nil }, observesKeyboardLayout: false),
                             privacyDefaults: fixture.defaults, makeOmnibox: { _, _, _ in nil },
                             loadFavicon: { _, _, _ in }, reduceMotion: { true })
        fixture.owner.residentCommandBar = bar
        bar.presentResident(in: start.commandBarSlot)

        try fixture.closePreviewAndReturnFocus()

        let fields = sidebarDescendants(start.commandBarSlot).compactMap { $0 as? NSTextField }
        #expect(fields.contains { field in
            fixture.host.firstResponder === field
                || (field.currentEditor().map { $0 === fixture.host.firstResponder } ?? false)
        })
    }
}
