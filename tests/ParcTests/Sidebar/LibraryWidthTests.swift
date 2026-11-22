import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct LibraryWidthTests {
    typealias Layout = SpaceManagementLayout
    nonisolated private static let windowBounds = NSRect(x: 0, y: 0, width: 1470, height: 831)

    nonisolated private static func frames(_ content: CGFloat, in bounds: NSRect = windowBounds) -> SidebarChromeFrames {
        SidebarChromeFrames(bounds: bounds, sidebarWidth: 228, presentation: .locked, placement: .locked, library: true, libraryContentWidth: content)
    }

    @MainActor private final class Reloads {
        private var pending: [@MainActor () -> Void] = []

        func schedule(_ reload: @escaping @MainActor () -> Void) {
            pending.append(reload)
        }

        func deliver() {
            let reloads = pending
            pending.removeAll()
            reloads.forEach { $0() }
        }
    }

    @MainActor private final class Library {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let library: LibraryView
        let reloads = Reloads()
        var reports: [CGFloat] = []

        init() throws {
            store = try BrowserStore(directory: directory)
            profile = store.state.profiles[0].id
            library = LibraryView(store: store, kind: .archive, profileID: profile, scheduleReload: reloads.schedule)
            reloads.deliver()
            library.onContentWidthChange = { [weak self] in
                guard let self else { return }
                reports.append(library.contentWidth)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        var strip: NSScrollView { library.spaceManager.subviews.compactMap { $0 as? NSScrollView }.first! }

        func showSpaces() -> Library {
            library.show(.spaces)
            library.frame = LibraryWidthTests.frames(library.contentWidth).library
            library.layoutSubtreeIfNeeded()
            return self
        }

        func page(_ kind: LibraryView.Kind) -> LibraryView {
            let page = LibraryView(store: store, kind: kind, profileID: profile, scheduleReload: reloads.schedule)
            reloads.deliver()
            return page
        }

        func fits(_ count: Int) -> Bool {
            library.frame = LibraryWidthTests.frames(library.contentWidth).library
            library.layoutSubtreeIfNeeded()
            let add = Layout.addItemFrame(count: count, height: library.spaceManager.bounds.height).offsetBy(dx: library.spaceManager.frame.minX, dy: 0)
            return store.state.spaces.count == count && library.contentWidth == Layout.libraryWidth(count: count)
                && add.maxX + Layout.horizontalInset + Layout.pageInset == library.frame.maxX && strip.documentView!.frame.width == strip.contentSize.width
        }

        func created(_ name: String = "Work") -> UUID {
            let id = store.createSpace(name: name)
            reloads.deliver()
            return id
        }

        func delete(_ target: SpaceDeletionTarget) -> SpaceDeletionUndo? {
            store.requestPageRetirement = { _, valid, done in done(valid()) }
            var deletion: SpaceDeletionUndo?
            store.deleteSpace(target, documents: [:], shouldCommit: { true }, didCommit: { deletion = $0 }) { _ in }
            reloads.deliver()
            return deletion
        }
    }

    @Test(arguments: 1...6)
    func theSpacesPageIsTwoHundredSixteenPlusTwoHundredSixtyFourPerSpace(spaces: Int) {
        #expect(Layout.libraryWidth(count: spaces) == 216 + 264 * CGFloat(spaces))
    }

    @Test(arguments: 1...6)
    func theStripFillsThePageColumnInsideTheFourPointInsets(spaces: Int) {
        #expect(LibraryRailLayout.width + 2 * Layout.pageInset + Layout.contentWidth(count: spaces) == Layout.libraryWidth(count: spaces))
    }

    @Test func oneSpacesLibraryIsFourHundredEightyAndItsPageStartsThere() {
        let f = Self.frames(Layout.libraryWidth(count: 1))
        #expect(f.library.width == 480)
        #expect(f.pageHost.minX == 480)
    }

    @Test func fiveSpacesStopAtTheWindowWidthMinusFiftySix() {
        #expect(Self.frames(Layout.libraryWidth(count: 5)).library.width == 1414)
    }

    @Test func twoSpacesInTheNarrowestWindowStopAtItsWidthMinusFiftySix() {
        #expect(Self.frames(Layout.libraryWidth(count: 2), in: NSRect(x: 0, y: 0, width: 760, height: 540)).library.width == 704)
    }

    @Test(arguments: [LibraryView.Kind.archive, .downloads, .captures, .documents])
    func everyOtherPageKeepsTheFourHundredSeventeenLibrary(kind: LibraryView.Kind) throws {
        let l = try Library()
        let page = l.page(kind)
        #expect(page.contentWidth == SidebarChromeFrames.libraryMinimumWidth)
        #expect(Self.frames(page.contentWidth).library.width == 417)
    }

    @Test func showingSpacesReportsOneSpacesWidth() throws {
        let l = try Library()
        l.library.show(.spaces)
        #expect(l.reports.last == 480)
        #expect(l.library.contentWidth == 480)
    }

    @Test func theStripSitsFourPointsInsideThePageColumn() throws {
        let l = try Library().showSpaces()
        #expect(l.library.spaceManager.frame == NSRect(x: 116, y: 0, width: 360, height: 831))
    }

    @Test func theAddItemEndsTwentyEightPointsBeforeThePage() throws {
        let l = try Library().showSpaces()
        let add = Layout.addItemFrame(count: 1, height: l.library.spaceManager.bounds.height).offsetBy(dx: l.library.spaceManager.frame.minX, dy: 0)
        #expect(add.maxX + Layout.horizontalInset + Layout.pageInset == l.library.frame.maxX)
    }

    @Test func aSpaceCreatedElsewhereWhileSpacesIsShownReMeasures() throws {
        let l = try Library().showSpaces()
        _ = l.store.createSpace(name: "Work")
        #expect(l.reports == [480])
        l.reloads.deliver()
        #expect(l.reports.suffix(2) == [480, 744])
        #expect(l.fits(2))
    }

    @Test func aThemeChangeOnTheShownPageReportsNothing() throws {
        let l = try Library().showSpaces()
        _ = l.created()
        let reported = l.reports.count
        _ = l.store.setSpaceTheme(l.store.state.spaces[0].id, theme: SpaceTheme(primaryColor: ThemeColor(red: 0.5, green: 0.4, blue: 0.9), colorCount: 1, appearance: .dark))
        l.reloads.deliver()
        #expect(l.reports.count == reported)
    }

    @Test func reorderingSpacesReportsNothing() throws {
        let l = try Library().showSpaces()
        let work = l.created()
        let reported = l.reports.count
        let order = l.store.state.spaces.map(\.id)
        #expect(try l.store.reorderSpace(work, before: order[0], expectedOrder: order))
        l.reloads.deliver()
        #expect(l.reports.count == reported)
        #expect(l.library.contentWidth == 744)
    }

    @Test func deletingASpaceReMeasures() throws {
        let l = try Library().showSpaces()
        let work = l.created()
        let reported = l.reports.count
        let deletion = l.delete(SpaceDeletionTarget(spaceID: work, state: l.store.state)!)
        #expect(deletion != nil)
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 480)
        #expect(l.fits(1))
    }

    @Test func undoOfADeletionReMeasures() throws {
        let l = try Library().showSpaces()
        let work = l.created()
        let deletion = try #require(l.delete(SpaceDeletionTarget(spaceID: work, state: l.store.state)!))
        let reported = l.reports.count
        let restored = try l.store.undoSpaceDeletion(deletion, shouldCommit: { true })
        l.reloads.deliver()
        #expect(restored)
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 744)
        #expect(l.fits(2))
    }

    @Test func theRestoredCardStaysInsideTheVisibleStrip() throws {
        let l = try Library().showSpaces()
        let work = l.created()
        let deletion = try #require(l.delete(SpaceDeletionTarget(spaceID: work, state: l.store.state)!))
        _ = try l.store.undoSpaceDeletion(deletion, shouldCommit: { true })
        l.reloads.deliver()
        _ = l.fits(2)
        let card = l.strip.documentView!.subviews.first { $0.accessibilityLabel() == "Work" }
        #expect(card.map { l.strip.documentVisibleRect.contains($0.frame) } == true)
    }

    @Test func redoOfADeletionReMeasures() throws {
        let l = try Library().showSpaces()
        let work = l.created()
        let deletion = try #require(l.delete(SpaceDeletionTarget(spaceID: work, state: l.store.state)!))
        _ = try l.store.undoSpaceDeletion(deletion, shouldCommit: { true })
        l.reloads.deliver()
        let reported = l.reports.count
        _ = l.delete(deletion.redoTarget(in: l.store.state)!)
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 480)
        #expect(l.fits(1))
    }

    private func converted(_ l: Library) throws -> SpaceFolderUndo {
        let later = l.created("Later")
        let conversion = SpaceFolderConversion(source: later, destination: l.store.state.spaces[0].id, state: l.store.state, documents: [:])!
        let folding = try #require(try l.store.convertSpaceToFolder(conversion))
        l.reloads.deliver()
        return folding
    }

    @Test func turnIntoFolderReMeasures() throws {
        let l = try Library().showSpaces()
        _ = l.created("Later")
        _ = l.fits(2)
        let reported = l.reports.count
        _ = try {
            let conversion = SpaceFolderConversion(source: l.store.state.spaces[1].id, destination: l.store.state.spaces[0].id, state: l.store.state, documents: [:])!
            _ = try l.store.convertSpaceToFolder(conversion)
            l.reloads.deliver()
        }()
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 480)
        #expect(l.fits(1))
    }

    @Test func undoOfTurnIntoFolderReMeasures() throws {
        let l = try Library().showSpaces()
        let folding = try converted(l)
        let reported = l.reports.count
        let unfolded = try l.store.undoSpaceFolderConversion(folding)
        l.reloads.deliver()
        #expect(unfolded)
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 744)
        #expect(l.fits(2))
    }

    @Test func redoOfTurnIntoFolderReMeasures() throws {
        let l = try Library().showSpaces()
        let folding = try converted(l)
        _ = try l.store.undoSpaceFolderConversion(folding)
        l.reloads.deliver()
        let reported = l.reports.count
        _ = try l.store.convertSpaceToFolder(folding.redo(in: l.store.state)!)
        l.reloads.deliver()
        #expect(l.reports.count == reported + 1)
        #expect(l.reports.last == 480)
        #expect(l.fits(1))
    }

    @Test func anotherWindowsSpacesPageOpensAtOneSpacesWidth() throws {
        let l = try Library()
        #expect(l.page(.spaces).contentWidth == 480)
    }

    @Test func bothWindowsSpacesPagesFollowASpaceCreatedInOne() throws {
        let l = try Library().showSpaces()
        let other = l.page(.spaces)
        var otherReports: [CGFloat] = []
        other.onContentWidthChange = { [unowned other] in otherReports.append(other.contentWidth) }
        _ = l.created("Shared")
        #expect(l.reports.last == 744)
        #expect(otherReports == [744])
        #expect(l.fits(2))
        other.onContentWidthChange = nil
    }

    @Test func bothWindowsSpacesPagesFollowASpaceDeletedInOne() throws {
        let l = try Library().showSpaces()
        let other = l.page(.spaces)
        var otherReports: [CGFloat] = []
        other.onContentWidthChange = { [unowned other] in otherReports.append(other.contentWidth) }
        let shared = l.created("Shared")
        _ = l.delete(SpaceDeletionTarget(spaceID: shared, state: l.store.state)!)
        #expect(l.reports.last == 480)
        #expect(otherReports == [744, 480])
        #expect(l.fits(1))
        other.onContentWidthChange = nil
    }

    @Test func leavingSpacesReturnsTheLibraryToFourHundredSeventeen() throws {
        let l = try Library().showSpaces()
        l.library.show(.archive)
        #expect(l.reports.last == 417)
        #expect(l.library.contentWidth == 417)
    }

    @Test func movingBetweenFourHundredSeventeenPagesReportsNothing() throws {
        let l = try Library().showSpaces()
        l.library.show(.archive)
        let reported = l.reports.count
        l.library.show(.downloads)
        #expect(l.reports.count == reported)
        #expect(l.library.contentWidth == 417)
    }

    @Test func aSpaceCreatedWhileAnotherPageShowsReportsNothing() throws {
        let l = try Library().showSpaces()
        l.library.show(.archive)
        let reported = l.reports.count
        _ = l.created("Elsewhere")
        #expect(l.reports.count == reported)
        #expect(l.library.contentWidth == 417)
    }

    @Test func returningToSpacesReadsTheCurrentCount() throws {
        let l = try Library().showSpaces()
        l.library.show(.archive)
        _ = l.created("Elsewhere")
        l.library.show(.spaces)
        #expect(l.reports.last == 744)
        #expect(l.library.contentWidth == 744)
    }

    @Test func choosingTheShownPageAgainReportsNothing() throws {
        let l = try Library().showSpaces()
        let reported = l.reports.count
        l.library.show(.spaces)
        #expect(l.reports.count == reported)
    }

    @MainActor private final class Host {
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1470, height: 831), styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: LibraryWidthTests.windowBounds)

        init() {
            window.isReleasedWhenClosed = false
            window.contentView = root
        }

        deinit {
            MainActor.assumeIsolated { window.close() }
        }

        func animates(onScreen: Bool? = nil, reduceMotion: Bool) -> Bool {
            guard let onScreen else {
                return SidebarMotionController.animatesLibraryWidth(in: window, layoutRoot: root, reducesMotion: { reduceMotion })
            }
            return SidebarMotionController.animatesLibraryWidth(in: window, layoutRoot: root, isOnScreen: { _ in onScreen },
                                                                reducesMotion: { reduceMotion })
        }
    }

    @Test func aWindowThatIsNotOnScreenAppliesANewLibraryWidthAtOnce() {
        #expect(!Host().animates(reduceMotion: false))
    }

    @Test func withReduceMotionOffAnOnScreenWindowSlidesToANewLibraryWidth() {
        #expect(Host().animates(onScreen: true, reduceMotion: false))
    }

    @Test func withReduceMotionOnEveryLibraryWidthChangeAppliesAtOnce() {
        #expect(!Host().animates(onScreen: true, reduceMotion: true))
    }

    @Test func withoutAWindowNoLibraryWidthChangeAnimates() {
        #expect(!SidebarMotionController.animatesLibraryWidth(in: nil, layoutRoot: NSView(), isOnScreen: { _ in true }, reducesMotion: { false }))
    }
}
