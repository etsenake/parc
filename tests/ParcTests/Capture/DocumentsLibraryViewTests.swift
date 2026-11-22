import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary
@testable import ParcSidebar

struct DocumentsLibraryViewTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let clock = NoteEditorManualClock()
        let store: BrowserStore
        let profile: UUID
        let files: NoteFiles
        let easelIcons: EaselTabIcons
        let easelStore: EaselStore
        let library: NoteLibrary
        let view: DocumentsLibraryView
        let window: NSWindow
        let grid: NSTableView

        init(easels: Int = 0, notes: [String] = [], width: CGFloat = 304) throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            profile = store.activeSpace.profileID
            let defaults = try #require(TestDefaults("parc.tests.documents-library."))
            let defaultFolder = directory.appendingPathComponent("Default Notes", isDirectory: true)
            var settings = NoteFileSettings(clock: clock, worker: .inline, hopToMain: { _ in },
                trashMover: { _ in throw NoteEditorRealTrashRefused() }, defaults: defaults, notesFolders: { [] })
            settings.defaultFolder = { defaultFolder }
            files = NoteFiles(settings: settings)
            easelIcons = EaselTabIcons(files: files)
            easelIcons.worker = .inline
            easelStore = try EaselStore(directory: store.easelsDirectory(for: profile))
            files.folders.setFolder(directory.appendingPathComponent("Library Notes", isDirectory: true), for: profile)
            library = files.library(forProfile: profile)
            if easels > 0 {
                for index in 0..<easels { _ = try easelStore.create(title: "Disposable Easel \(index + 1)") }
            }
            for title in notes { _ = try library.createNote(title: title) }
            view = DocumentsLibraryView(store: store, profileID: profile, files: files, easelIcons: easelIcons,
                                        easelStore: { [easelStore] _ in easelStore })
            view.ownerValid = { true }
            view.appearance = NSAppearance(named: .aqua)
            view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: false)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
            view.layoutSubtreeIfNeeded()
            grid = try #require(Self.descendants(view).compactMap { $0 as? NSTableView }.first)
        }

        func teardown() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func cards(row: Int) throws -> [NSView] {
            let container = try #require(grid.view(atColumn: 0, row: row, makeIfNecessary: true))
            container.layoutSubtreeIfNeeded()
            container.displayIfNeeded()
            return container.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }.sorted { $0.frame.minX < $1.frame.minX }
        }

        func titles() -> [String] {
            (0..<grid.numberOfRows).flatMap { row -> [String] in
                guard let container = grid.view(atColumn: 0, row: row, makeIfNecessary: true) else { return [] }
                return container.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }
                    .sorted { $0.frame.minX < $1.frame.minX }
                    .compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
            }
        }

        var search: NSTextField {
            Self.descendants(view).compactMap { $0 as? NSTextField }.first { $0.placeholderString == "Search Easels & Notes…" }!
        }

        func query(_ text: String) {
            search.stringValue = text
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        }

        func srgb(_ color: NSColor?) -> [CGFloat] {
            guard let value = color?.usingColorSpace(.sRGB) else { return [] }
            return [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
        }
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func bothOriginalDocumentsAppearInOneGridRow(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        #expect(try fixture.cards(row: 0).count == 2)
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func bothDocumentCardsFitTheActualLibraryPane(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let row = try #require(fixture.grid.view(atColumn: 0, row: 0, makeIfNecessary: true))
        #expect(try fixture.cards(row: 0).allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= row.bounds.width })
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func documentCardsRemainDistinctPointerTargets(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let cards = try fixture.cards(row: 0)
        #expect(cards[0].frame.maxX <= cards[1].frame.minX)
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func theGridRowHeightFitsTheCardPlusTwelvePointsTopAndBottom(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let cards = try fixture.cards(row: 0)
        #expect(abs(fixture.grid.rowHeight - (cards[0].frame.height + 24)) < 0.01)
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func documentCardsUseOpaqueWhiteTiles(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        for card in try fixture.cards(row: 0) {
            card.needsDisplay = true
            card.displayIfNeeded()
            let color = try #require(card.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) })
            let value = fixture.srgb(color)
            #expect(value.count == 4 && value[0] > 0.99 && value[1] > 0.99 && value[2] > 0.99 && value[3] > 0.99)
        }
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func documentTitlesWrapAtFifteenPoints(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let titles = try fixture.cards(row: 0).compactMap { $0.subviews.compactMap { $0 as? NSTextField }.first }
        #expect(titles.count == 2 && titles.allSatisfy { $0.font?.pointSize == 15 && $0.maximumNumberOfLines > 1 })
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func cardTitlesUseChromeInkNotTheSpacesForegroundPrimary(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let titles = try fixture.cards(row: 0).compactMap { $0.subviews.compactMap { $0 as? NSTextField }.first }
        let chrome = fixture.srgb(DocumentCardChrome.title(dark: false))
        #expect(titles.allSatisfy { fixture.srgb($0.textColor) == chrome && fixture.srgb($0.textColor) != fixture.srgb(fixture.view.palette?.foregroundPrimary) })
    }

    @MainActor @Test(arguments: [CGFloat(304), 248])
    func theGridAllowsDocumentCardKeyboardFocus(_ width: CGFloat) throws {
        let fixture = try Fixture(easels: 2, width: width)
        defer { fixture.teardown() }
        let card = try #require(try fixture.cards(row: 0).first)
        #expect(fixture.window.makeFirstResponder(card) && fixture.window.firstResponder === card)
    }

    @MainActor @Test func newNoteIsAThirtySixPointIconOnlyControl() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        let create = try #require(Fixture.descendants(fixture.view).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "New Note" })
        #expect(create.title.isEmpty && abs(create.frame.width - 36) < 0.01 && abs(create.frame.height - 36) < 0.01)
    }

    @MainActor @Test func aNewlyCreatedNoteFileAppearsInTheDocumentsGrid() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        _ = try fixture.library.createNote()
        #expect(fixture.grid.numberOfRows == 2)
        #expect(fixture.titles().contains("Untitled"))
    }

    @MainActor @Test func aBodyOnlySaveKeepsTheVisibleCardsAndTheirTitles() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        let note = try fixture.library.createNote()
        let before = fixture.titles()
        try Data("keystroke body that is not a card title\n".utf8).write(to: note)
        fixture.library.refresh()
        #expect(fixture.grid.numberOfRows == 2 && fixture.titles() == before)
    }

    @MainActor @Test func aBodyOnlySaveDoesNotClearDocumentCardSelection() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        let note = try fixture.library.createNote()
        let card = try #require(try fixture.cards(row: 0).first)
        fixture.window.makeFirstResponder(card)
        try Data("keystroke body that is not a card title\n".utf8).write(to: note)
        fixture.library.refresh()
        #expect(fixture.window.firstResponder is NSView)
    }

    @MainActor @Test func renamingANotesFileRefreshesTheDocumentsCatalog() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        let note = try fixture.library.createNote()
        let renamed = try fixture.files.rename(note, to: "Named Library Note")
        #expect(fixture.titles().contains("Named Library Note"))
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @MainActor @Test func anIdenticalCatalogRepublishRemainsAFingerprintNoOpThatKeepsCardSelection() throws {
        let fixture = try Fixture(easels: 2)
        defer { fixture.teardown() }
        _ = try fixture.files.rename(try fixture.library.createNote(), to: "Named Library Note")
        let card = try #require(try fixture.cards(row: 0).first)
        fixture.window.makeFirstResponder(card)
        let rows = fixture.grid.numberOfRows, titles = fixture.titles(), focus = fixture.window.firstResponder
        fixture.library.changes.send()
        #expect(fixture.grid.numberOfRows == rows && fixture.titles() == titles && fixture.window.firstResponder === focus)
    }

    @MainActor @Test func anExplicitReloadWithAnUnchangedCatalogStaysAFingerprintNoOp() throws {
        let fixture = try Fixture(easels: 2, notes: ["Stable note"])
        defer { fixture.teardown() }
        let titles = fixture.titles()
        fixture.view.reload()
        #expect(fixture.titles() == titles)
    }

    @MainActor @Test func aSearchFilterForcesAReloadPastTheDocumentsFingerprint() throws {
        let fixture = try Fixture(easels: 2, notes: ["Stable note"])
        defer { fixture.teardown() }
        fixture.query("no-match-filter")
        #expect(fixture.titles().isEmpty)
    }

    @MainActor @Test func clearingTheDocumentsSearchForcesMembershipToReload() throws {
        let fixture = try Fixture(easels: 2, notes: ["Stable note"])
        defer { fixture.teardown() }
        let before = fixture.titles()
        fixture.query("no-match-filter")
        fixture.query("")
        #expect(fixture.titles() == before)
    }

    @MainActor @Test func theIsolatedDocumentsViewStartsWithTheTitledNote() throws {
        let fixture = try Fixture(notes: ["Documents fingerprint note"])
        defer { fixture.teardown() }
        #expect(fixture.titles() == ["Documents fingerprint note"])
    }

    @MainActor @Test func anIdenticalIsolatedRepublishRemainsAFingerprintNoOp() throws {
        let fixture = try Fixture(notes: ["Documents fingerprint note"])
        defer { fixture.teardown() }
        fixture.library.changes.send()
        #expect(fixture.titles() == ["Documents fingerprint note"])
    }

    @MainActor @Test func aBodySaveReachesTheDocumentsSearch() throws {
        let fixture = try Fixture(notes: ["Documents fingerprint note"])
        defer { fixture.teardown() }
        let note = try #require(fixture.library.listedEntries()?.first?.url)
        try Data("documents-fingerprint-body-match\n".utf8).write(to: note)
        fixture.library.refresh()
        fixture.query("fingerprint-body-match")
        #expect(fixture.titles() == ["Documents fingerprint note"])
    }

    @MainActor @Test func aNonMatchingDocumentsSearchClearsTheRows() throws {
        let fixture = try Fixture(notes: ["Documents fingerprint note"])
        defer { fixture.teardown() }
        fixture.query("no-match-filter")
        #expect(fixture.titles().isEmpty)
    }

    @MainActor @Test func renamingANotesFileRefreshesTheIsolatedDocumentsCatalog() throws {
        let fixture = try Fixture(notes: ["Documents fingerprint note"])
        defer { fixture.teardown() }
        let note = try #require(fixture.library.listedEntries()?.first?.url)
        fixture.query("no-match-filter")
        _ = try fixture.files.rename(note, to: "Documents fingerprint renamed")
        fixture.query("")
        #expect(fixture.titles() == ["Documents fingerprint renamed"])
    }

    @MainActor private func hosted(_ fixture: Fixture) throws -> (LibraryView, NSWindow, NSTableView) {
        let library = LibraryView(store: fixture.store, kind: .documents, profileID: fixture.profile,
                                  spaceManager: SpaceManagerView(frame: .zero), files: fixture.files, easelIcons: fixture.easelIcons,
                                  easelStore: { _ in fixture.easelStore },
                                  reduceMotion: { true })
        library.frame = NSRect(x: 0, y: 0, width: 416, height: 600)
        let window = NSWindow(contentRect: library.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = library
        library.layoutSubtreeIfNeeded()
        let documents = try #require(Fixture.descendants(library).compactMap { $0 as? DocumentsLibraryView }.first)
        let table = try #require(Fixture.descendants(documents).compactMap { $0 as? NSTableView }.first)
        return (library, window, table)
    }

    @MainActor private func titles(_ table: NSTableView) -> [String] {
        (0..<table.numberOfRows).flatMap { row -> [String] in
            guard let container = table.view(atColumn: 0, row: row, makeIfNecessary: true) else { return [] }
            return container.subviews.filter { $0.identifier?.rawValue.hasPrefix("document-") == true }
                .compactMap { card in card.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
        }
    }

    @MainActor @Test func theLibraryDocumentsPaneShowsTheNoteCatalog() throws {
        let fixture = try Fixture(easels: 2, notes: ["Named Library Note"])
        defer { fixture.teardown() }
        let (library, window, table) = try hosted(fixture)
        defer { window.contentView = nil; _ = library }
        #expect(titles(table).contains("Named Library Note"))
    }

    @MainActor @Test func unrelatedLiveTabTitlesDoNotRebuildTheLibraryDocuments() async throws {
        let fixture = try Fixture(easels: 2, notes: ["Named Library Note"])
        defer { fixture.teardown() }
        let (library, window, table) = try hosted(fixture)
        defer { window.contentView = nil; _ = library }
        let before = titles(table)
        let first = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true))
        let tab = fixture.store.open("https://unrelated-documents-title.example.invalid")
        fixture.store.updateTab(tab, title: "Unrelated documents live title")
        await withCheckedContinuation { continuation in RunLoop.main.perform(inModes: [.default]) { continuation.resume() } }
        #expect(titles(table) == before)
        #expect(table.view(atColumn: 0, row: 0, makeIfNecessary: true) === first)
    }
}
