import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary
@testable import ParcSidebar

struct LibrarySpacesHostTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let view: LibraryView
        let window: NSWindow
        let manager: SpaceManagerView

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            let suppliedManager = SpaceManagerView(frame: .zero)
            view = LibraryView(isolatingNotesIn: store, kind: .spaces, profileID: store.activeSpace.profileID,
                               spaceManager: suppliedManager, reduceMotion: { true })
            view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            manager = try #require(Self.descendants(view).compactMap { $0 as? SpaceManagerView }.first { $0 === suppliedManager })
        }

        func teardown() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func drain() async {
            await withCheckedContinuation { continuation in RunLoop.main.perform(inModes: [.default]) { continuation.resume() } }
        }
    }

    @MainActor @Test func theSpacesPaneHostsTheSpaceManager() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(!fixture.manager.isHidden)
    }

    @MainActor @Test func settingsPublishesKeepSpacesHostedAndReloadTheCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.store.updateSettings { $0.showSpaceHeaderOnSingleUnnamedSpaces = true }
        await fixture.drain()
        #expect(Fixture.descendants(fixture.view).contains { $0 === fixture.manager && !$0.isHidden })
    }

    @MainActor @Test func liveTabTitlePublishesStillReachSpacesReload() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let tab = fixture.store.open("https://spaces-live-title.example.invalid")
        fixture.store.updateTab(tab, title: "Spaces live title")
        await fixture.drain()
        #expect(Fixture.descendants(fixture.view).contains { $0 === fixture.manager && !$0.isHidden })
    }
}
