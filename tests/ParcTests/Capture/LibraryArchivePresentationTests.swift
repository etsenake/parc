import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct LibraryArchivePresentationTests {
    @MainActor private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let window: NSWindow
        let view: LibraryView

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            let auto = store.open("https://auto.example.test")
            let manual = store.open("https://manual.example.test")
            store.closeTabs([auto], reason: .automatic)
            store.closeTabs([manual], reason: .manual)
            view = LibraryView(store: store, kind: .archive, profileID: store.activeSpace.profileID, files: IsolatedNoteFiles.make(), reduceMotion: { true })
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 540),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.frame = CGRect(x: 0, y: 0, width: 460, height: 540)
            view.layoutSubtreeIfNeeded()
        }

        func cleanup() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        func button(_ label: String) throws -> NSButton {
            try #require(descendants(view).compactMap { $0 as? NSButton }.first {
                $0.title == label && !$0.isHiddenOrHasHiddenAncestor
            })
        }

        func search() throws -> NSTextField {
            try #require(descendants(view).compactMap { $0 as? DownloadSearchField }.first {
                $0.accessibilityLabel() == "Search Library"
            })
        }

        func press(_ button: NSButton) throws {
            let action = try #require(button.action)
            _ = NSApplication.shared.sendAction(action, to: button.target, from: button)
            view.layoutSubtreeIfNeeded()
        }

        func titles() throws -> [String] {
            let table = try #require(descendants(view).compactMap { $0 as? NSTableView }.first)
            return (0..<table.numberOfRows).flatMap { row in
                table.view(atColumn: 0, row: row, makeIfNecessary: true).map(descendants)?.compactMap {
                    ($0 as? NSTextField)?.stringValue
                } ?? []
            }
        }

        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
    }

    @MainActor @Test func theArchiveShowsBothOriginalClosureReasonsWithNoFilter() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let titles = try fixture.titles()
        #expect(titles.contains("auto.example.test") && titles.contains("manual.example.test"))
    }

    @MainActor @Test(arguments: [("Auto-Closed", "auto.example.test", "manual.example.test"),
                                ("Manually Closed", "manual.example.test", "auto.example.test")])
    func theArchiveReasonFilterSelectsOnlyItsOriginalClosureType(_ name: String, _ included: String, _ excluded: String) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.press(fixture.button("Filter"))
        try fixture.press(fixture.button(name))
        let titles = try fixture.titles()
        #expect(titles.contains(included) && !titles.contains(excluded))
    }

    @MainActor @Test func reselectingTheActiveReasonRestoresAllRows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.press(fixture.button("Filter"))
        try fixture.press(fixture.button("Manually Closed"))
        try fixture.press(fixture.button("Manually Closed"))
        let titles = try fixture.titles()
        #expect(titles.contains("auto.example.test") && titles.contains("manual.example.test"))
    }

    @MainActor @Test func theRetiredFilterChipCannotReplayItsAction() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.press(fixture.button("Filter"))
        let original = try fixture.button("Auto-Closed")
        try fixture.press(original)
        try fixture.press(original)
        #expect(try fixture.button("Auto-Closed").state == .on)
    }

    @MainActor @Test func openingTheFilterPreservesTheSearchQueryWhileHidingTheField() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let search = try fixture.search()
        search.stringValue = "query"
        try fixture.press(fixture.button("Filter"))
        #expect(search.isHiddenOrHasHiddenAncestor)
        #expect(search.stringValue == "query")
        #expect(try !fixture.button("Done").isHidden)
    }

    @MainActor @Test func closingTheFilterRestoresTheOriginalQuerySelection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let search = try fixture.search()
        search.stringValue = "query"
        try #require(fixture.window.makeFirstResponder(search))
        let editor = try #require(search.currentEditor())
        let range = NSRange(location: 1, length: 2)
        editor.selectedRange = range
        try fixture.press(fixture.button("Filter"))
        try fixture.press(fixture.button("Done"))
        #expect(!search.isHiddenOrHasHiddenAncestor)
        #expect(search.currentEditor()?.selectedRange == range)
    }

    @MainActor @Test func changingTheArchiveThemeKeepsItsSearchPlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let search = try fixture.search()
        let prior = search.placeholderAttributedString?.string
        fixture.view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: true)
        #expect(prior == "Search Archive…")
        #expect(search.placeholderAttributedString?.string == prior)
    }
}
