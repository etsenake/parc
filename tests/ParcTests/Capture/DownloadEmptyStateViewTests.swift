import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct DownloadEmptyStateViewTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let view: DownloadLibraryView
        let window: NSWindow
        let empty: DownloadEmptyContentView
        let search: NSTextField

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            view = DownloadLibraryView(store: store, ownerValid: { true }, reduceMotion: { false })
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let all = Self.descendants(view)
            empty = try #require(all.compactMap { $0 as? DownloadEmptyContentView }.first)
            search = try #require(all.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Search Downloads" })
        }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        var entrance: CAAnimation? { empty.layer?.animation(forKey: "empty.translation") }
    }

    @MainActor @Test func theRealLibraryKeepsItsIconAndLabelInOneEmptyStateAnimationOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.empty.mode == .empty && fixture.empty.subviews.count == 2)
    }

    @MainActor @Test func managerLoadingNeverAnimatesAsASuccessfulEmptyState() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 1, message: nil)
        #expect(fixture.empty.mode == .status && fixture.entrance == nil)
    }

    @MainActor @Test func aLoadFailureRemainsANonAnimatedStatusOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 0, message: "Could not load downloads")
        #expect(fixture.empty.mode == .status)
    }

    @MainActor @Test func aLoadedEmptyPublicationRunsTheRecoveredWholeContentEntrance() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 1, message: nil)
        fixture.view.setLoading(count: 0, message: nil)
        #expect(fixture.empty.mode == .empty && fixture.entrance != nil)
    }

    @MainActor @Test func emptyStateChangesNeverTakeSearchOrPageInputFocus() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.window.makeFirstResponder(fixture.search)
        let responder = fixture.window.firstResponder
        fixture.view.setLoading(count: 1, message: nil)
        fixture.view.setLoading(count: 0, message: nil)
        #expect(fixture.window.firstResponder === responder)
    }

    @MainActor @Test func invalidatingTheLibrarySettlesItsActualEmptySubtree() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.setLoading(count: 1, message: nil)
        fixture.view.setLoading(count: 0, message: nil)
        fixture.view.invalidate()
        #expect(fixture.entrance == nil)
    }
}
