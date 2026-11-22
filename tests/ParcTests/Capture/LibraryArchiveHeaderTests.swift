import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct LibraryArchiveHeaderTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let archive: LibraryView
        let window: NSWindow
        let search: DownloadSearchField
        let filter: DownloadFilterButton

        init(kind: LibraryView.Kind = .archive, width: CGFloat = 416) throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            profile = store.state.profiles[0].id
            archive = LibraryView(isolatingNotesIn: store, kind: kind, profileID: profile, reduceMotion: { true })
            archive.frame = NSRect(x: 0, y: 0, width: width, height: 600)
            window = NSWindow(contentRect: archive.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = archive
            archive.layoutSubtreeIfNeeded()
            let all = Self.descendants(archive)
            search = try #require(all.compactMap { $0 as? DownloadSearchField }.first { $0.accessibilityLabel() == "Search Library" })
            filter = try #require(all.compactMap { $0 as? DownloadFilterButton }.first { $0.style == .header })
        }

        func teardown() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func button(_ title: String, in library: NSView? = nil) throws -> NSButton {
            try #require(Self.descendants(library ?? archive).compactMap { $0 as? NSButton }.first { $0.title == title })
        }

        func press(_ button: NSButton) {
            _ = NSApplication.shared.sendAction(button.action!, to: button.target, from: button)
            archive.layoutSubtreeIfNeeded()
        }

        func headerFrames(_ library: LibraryView) throws -> [NSRect] {
            let all = Self.descendants(library)
            let field = try #require(all.compactMap { $0 as? DownloadSearchField }.first { !$0.isHiddenOrHasHiddenAncestor })
            let action = try #require(all.compactMap { $0 as? DownloadFilterButton }.first {
                $0.style == .header && !$0.isHiddenOrHasHiddenAncestor
            })
            return [field.superview!, field, action].map { library.convert($0.bounds, from: $0) }
        }

        func startComposition() throws -> NSTextView {
            search.stringValue = "query"
            window.makeFirstResponder(search)
            let editor = try #require(search.currentEditor() as? NSTextView)
            editor.setSelectedRange(NSRange(location: 1, length: 2))
            editor.setMarkedText("input", selectedRange: NSRange(location: 5, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            return editor
        }

        func textWidth(_ title: String) -> CGFloat {
            ceil((title as NSString).size(withAttributes: [.font: filter.font!]).width)
        }
    }

    @MainActor @Test func theFilterUsesItsFittingWidthSoTheTitleIsNotClipped() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.filter.frame.width == fixture.filter.fittingSize.width && fixture.filter.fittingSize.width > 72)
    }

    @MainActor @Test func theArchiveHeaderIsTheSharedSearchFieldItsBackdropAndTheHeaderFilter() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.search.superview is DownloadSearchBackdrop)
        #expect(fixture.filter.style == .header)
    }

    @MainActor @Test func theFilterPadsItsGlyphAndTitleByTenPoints() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.filter.fittingSize.width == 10 + LibraryHeaderGlyph.side + 4 + fixture.textWidth("Filter") + 10)
    }

    @MainActor @Test func theDownloadsPageHasNoFilterBecauseItsOnlyFilterWasByProfile() throws {
        let fixture = try Fixture(kind: .downloads)
        defer { fixture.teardown() }
        #expect(!Fixture.descendants(fixture.archive).contains { ($0 as? DownloadFilterButton)?.style == .header && !$0.isHiddenOrHasHiddenAncestor })
    }

    @MainActor @Test func theDownloadsSearchStartsWhereTheArchivesDoesAndRunsToThePageInset() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let downloads = LibraryView(isolatingNotesIn: fixture.store, kind: .downloads, profileID: fixture.profile, reduceMotion: { true })
        downloads.frame = fixture.archive.frame
        let host = NSWindow(contentRect: downloads.frame, styleMask: .titled, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = downloads
        defer { host.contentView = nil }
        downloads.layoutSubtreeIfNeeded()
        let archiveHeader = try fixture.headerFrames(fixture.archive)
        let field = try #require(Fixture.descendants(downloads).compactMap { $0 as? DownloadSearchField }.first { !$0.isHiddenOrHasHiddenAncestor })
        let backdrop = downloads.convert(field.superview!.bounds, from: field.superview!)
        #expect(backdrop.minX == archiveHeader[0].minX && backdrop.minY == archiveHeader[0].minY && backdrop.height == archiveHeader[0].height)
        #expect(abs(backdrop.maxX - (downloads.bounds.width - LibraryPageHeader.inset)) < 0.5)
    }

    @MainActor @Test func theArchiveHeaderUsesThePageHeadersInsetTopHeightAndFieldActionGap() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let header = try fixture.headerFrames(fixture.archive)
        let pageX = LibraryRailLayout.width + LibraryPageHeader.inset
        #expect(header[0] == NSRect(x: pageX, y: LibraryPageHeader.top, width: header[2].minX - LibraryPageHeader.spacing - pageX,
                                    height: LibraryPageHeader.height))
        #expect(header[2].maxX == fixture.archive.bounds.width - LibraryPageHeader.inset)
        #expect(header[2].minY == LibraryPageHeader.top && header[2].height == LibraryPageHeader.height)
    }

    @MainActor @Test func theArchiveListReachesTheBottomWithoutAFooterBar() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let list = try #require(Fixture.descendants(fixture.archive).compactMap { $0 as? NSTableView }.first?.enclosingScrollView)
        #expect(abs(list.frame.maxY - fixture.archive.bounds.height) < 0.5)
    }

    @MainActor @Test func theArchivePaintsANonInteractiveDepthLayerOverTheRailAndItsEdgeOnly() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let frame = NSRect(x: 0, y: 0, width: 145, height: fixture.archive.bounds.height)
        #expect(fixture.archive.subviews.contains { $0.frame == frame && $0.hitTest(NSPoint(x: 8, y: 8)) == nil && !($0 is WindowStandardButtons) })
    }

    @MainActor @Test func theArchiveShowsItsSearchPlaceholder() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.search.placeholderAttributedString?.string == "Search Archive…")
    }

    @MainActor @Test(arguments: [false, true])
    func aThemeChangeKeepsTheArchivePlaceholderGreyQueryInkAndFourteenPointMediumType(_ dark: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.archive.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: dark)
        let color = fixture.search.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(fixture.search.placeholderAttributedString?.string == "Search Archive…")
        #expect(color == .placeholderTextColor && fixture.search.textColor == .labelColor)
        #expect(fixture.search.font == DownloadSearchField.textFont)
    }

    @MainActor @Test func theFilterRefusesToHideAnActiveComposition() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let editor = try fixture.startComposition()
        fixture.press(fixture.filter)
        #expect(fixture.filter.title == "Filter" && editor.hasMarkedText())
    }

    @MainActor @Test func reselectingTheArchivePreservesTheCompositionAndTheSelectedRailState() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let editor = try fixture.startComposition()
        let rail = try fixture.button("Archived Tabs")
        rail.sendClick()
        #expect(editor.hasMarkedText() && rail.state == .on)
    }

    @MainActor @Test func aRejectedCategorySwitchKeepsTheCompositionAndTheOriginalRailState() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let editor = try fixture.startComposition()
        let rail = try fixture.button("Archived Tabs")
        let downloads = try fixture.button("Downloads")
        downloads.sendClick()
        #expect(fixture.archive.kind == .archive && editor.hasMarkedText() && rail.state == .on && downloads.state == .off)
    }

    @MainActor @Test func theArchiveFilterReplacesSearchWhileRetainingTheQuery() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.search.stringValue = "query"
        fixture.press(fixture.filter)
        #expect(fixture.filter.title == "Done" && fixture.search.isHiddenOrHasHiddenAncestor && fixture.search.stringValue == "query")
    }

    @MainActor @Test func doneKeepsTheHeaderActionSizedToItsTitle() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        #expect(fixture.filter.frame.width == fixture.filter.fittingSize.width)
    }

    @MainActor @Test func doneSitsInTheHeadersTrailingSlotPaddedByTwelvePoints() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        #expect(fixture.filter.fittingSize.width == 12 + fixture.textWidth("Done") + 12)
        #expect(fixture.filter.frame.maxX == fixture.archive.bounds.width - LibraryPageHeader.inset)
        #expect(fixture.filter.frame.minY == LibraryPageHeader.top && fixture.filter.frame.height == LibraryPageHeader.height)
    }

    @MainActor @Test func theArchiveExposesItsFilterHeading() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        #expect(Fixture.descendants(fixture.archive).compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "Filter Archived Tabs" && !$0.isHidden
        })
    }

    @MainActor @Test func doneRestoresAnEndOfQueryCaret() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.search.stringValue = "query"
        fixture.window.makeFirstResponder(fixture.search)
        (fixture.search.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 5, length: 0))
        fixture.press(fixture.filter)
        fixture.press(fixture.filter)
        #expect(fixture.search.currentEditor()?.selectedRange == NSRange(location: 5, length: 0))
    }

    @MainActor @Test func doneRestoresAnEmptyQueryCaret() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.search.stringValue = ""
        fixture.window.makeFirstResponder(fixture.search)
        (fixture.search.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: 0))
        fixture.press(fixture.filter)
        fixture.press(fixture.filter)
        #expect(fixture.search.currentEditor()?.selectedRange == NSRange(location: 0, length: 0))
    }

    @MainActor @Test func resizingAnotherLibraryCategoryCannotRevealTheArchiveSearch() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        fixture.archive.show(.downloads)
        fixture.archive.frame.size.width = 380
        fixture.archive.layoutSubtreeIfNeeded()
        #expect(fixture.search.isHiddenOrHasHiddenAncestor)
    }

    @MainActor @Test func aDetachedArchiveRejectsAStaleFilterAction() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        fixture.window.contentView = nil
        fixture.press(fixture.filter)
        #expect(fixture.filter.title == "Done")
    }

    @MainActor @Test func aChipCapturedInTheOriginalWindowCannotActInAReplacementWindow() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        let prior = try fixture.button("Manually Closed")
        fixture.window.contentView = nil
        let replacement = NSWindow(contentRect: fixture.archive.frame, styleMask: .titled, backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        replacement.contentView = fixture.archive
        defer { replacement.contentView = nil }
        let fresh = try fixture.button("Manually Closed")
        fixture.press(prior)
        #expect(fresh.state == .off)
    }

    @MainActor @Test func aReattachedArchiveGetsLiveControlsForItsNewWindow() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.press(fixture.filter)
        fixture.window.contentView = nil
        let replacement = NSWindow(contentRect: fixture.archive.frame, styleMask: .titled, backing: .buffered, defer: false)
        replacement.isReleasedWhenClosed = false
        replacement.contentView = fixture.archive
        defer { replacement.contentView = nil }
        fixture.press(try fixture.button("Manually Closed"))
        #expect(try fixture.button("Manually Closed").state == .on)
    }
}
