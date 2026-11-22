import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct DownloadCatalogFingerprintTests {
    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let path: String
        let window: NSWindow
        let view: DownloadLibraryView
        let table: DownloadLibraryTable

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            path = store.independentEngineProfilePath(for: store.activeSpace.profileID)
            view = DownloadLibraryView(store: store, ownerValid: { true })
            Self.record(store, path, "dl-fp", received: 100)
            view.setLoading(count: 0, message: nil)
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            table = try #require(Self.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
        }

        static func record(_ store: BrowserStore, _ path: String, _ id: String, received: Int, status: String = "downloading",
                           started: Double = 2000) {
            store.recordDownload(["id": id, "profilePath": path, "name": id, "status": status, "available": true,
                "itemIdentity": id + "-1", "canOpen": status == "completed", "canCopyFile": status == "completed",
                "receivedBytes": received, "totalBytes": 1000, "sourceURL": "https://example.invalid/" + id, "startedAt": started])
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func labels() -> [String] {
            (0..<table.numberOfRows).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true)?.accessibilityLabel() }
        }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        func drain() async {
            await withCheckedContinuation { continuation in RunLoop.main.perform(inModes: [.default]) { continuation.resume() } }
        }
    }

    @MainActor @Test func unrelatedLiveTabTitlesDoNotRebuildDownloadsRowsOrSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let rows = fixture.table.numberOfRows, labels = fixture.labels(), selection = fixture.table.selectedRowIndexes
        let tab = fixture.store.open("https://downloads-fingerprint-live.example.invalid")
        fixture.store.updateTab(tab, title: "Unrelated downloads live title")
        await fixture.drain()
        #expect(fixture.table.numberOfRows == rows && fixture.labels() == labels && fixture.table.selectedRowIndexes == selection)
    }

    @MainActor @Test func unrelatedLiveTabAddressPublishesDoNotRebuildDownloadsRows() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let labels = fixture.labels()
        let tab = fixture.store.open("https://downloads-fingerprint-live.example.invalid")
        fixture.store.updateTab(tab, url: "https://downloads-fingerprint-live-url.example.invalid")
        await fixture.drain()
        #expect(fixture.labels() == labels)
    }

    @MainActor @Test func anIdenticalDownloadRepublishRemainsAFingerprintNoOp() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let labels = fixture.labels()
        Fixture.record(fixture.store, fixture.path, "dl-fp", received: 100)
        await fixture.drain()
        #expect(fixture.labels() == labels && fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func progressBytesFlipsStillReloadThroughTheStoreSinkKeepingTheSelectedRow() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let labels = fixture.labels()
        Fixture.record(fixture.store, fixture.path, "dl-fp", received: 700)
        await fixture.drain()
        #expect(fixture.labels() != labels && fixture.table.selectedRowIndexes == IndexSet(integer: 1))
    }

    @MainActor @Test func unrelatedTitlePublishesAfterProgressKeepTheAppliedProgressRows() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        Fixture.record(fixture.store, fixture.path, "dl-fp", received: 700)
        await fixture.drain()
        let labels = fixture.labels()
        let tab = fixture.store.open("https://downloads-fingerprint-live.example.invalid")
        fixture.store.updateTab(tab, title: "Still unrelated after progress")
        await fixture.drain()
        #expect(fixture.labels() == labels)
    }

    @MainActor @Test func aNewDownloadMembershipStillReloadsTheCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        Fixture.record(fixture.store, fixture.path, "dl-fp", received: 700)
        await fixture.drain()
        let afterProgress = fixture.labels()
        Fixture.record(fixture.store, fixture.path, "dl-fp-new", received: 1000, status: "completed", started: 2001)
        await fixture.drain()
        #expect(fixture.labels().contains { $0.contains("dl-fp-new") } && fixture.labels() != afterProgress)
    }
}
