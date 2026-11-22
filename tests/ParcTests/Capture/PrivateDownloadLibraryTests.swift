import AppKit
import Testing
@testable import Parc
@testable import ParcCore

struct PrivateDownloadLibraryTests {
    @MainActor private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let profilePath: String

        init() throws {
            store = try BrowserStore(directory: root.appendingPathComponent("Regular"))
            profile = store.activeSpace.profileID
            profilePath = store.independentEngineProfilePath(for: profile)
        }

        func cleanup() {
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: root)
        }

        func snapshot(privateContext: Bool, name: String = "Private file.pdf", profilePath: String? = nil) -> [String: Any] {
            ["id": "same-guid", "profilePath": profilePath ?? self.profilePath, "offTheRecord": privateContext,
             "name": name, "path": privateContext ? "/not-opened/private.pdf" : "/not-opened/regular.pdf",
             "sourceURL": privateContext ? "https://example.test/private" : "https://example.test/regular",
             "status": "completed", "available": true, "itemIdentity": "same-incarnation",
             "canOpen": true, "canCopyFile": true, "canRemove": true, "startedAt": 1_000]
        }

        func publish() {
            store.recordDownload(snapshot(privateContext: false, name: "Regular file.pdf"))
            store.recordTransientDownload(snapshot(privateContext: true), contextID: "alpha")
            store.recordTransientDownload(snapshot(privateContext: true), contextID: "beta")
        }

        func privateStore() -> BrowserStore {
            BrowserStore(privateParentProfileID: profile, engineProfilePath: profilePath,
                directory: root.appendingPathComponent("Private"), settings: store.state.settings)
        }
    }

    @MainActor @Test func aManagerGuidSharedAcrossContextsKeepsDistinctSelectionLeases() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.publish()
        let displayed = fixture.store.downloadItems
        #expect(displayed.count == 3 && Set(displayed.map(DownloadLibraryIdentity.init)).count == 3)
        #expect(fixture.store.transientDownloads.allSatisfy { $0.profileID == fixture.profile })
    }

    @MainActor @Test func reloadingTheStoreDoesNotRecreatePrivateRows() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.publish()
        try fixture.store.save()
        let reopened = try BrowserStore(directory: fixture.root.appendingPathComponent("Regular"))
        #expect(reopened.downloadItems.map(\.name) == ["Regular file.pdf"])
        #expect(reopened.transientDownloads.isEmpty)
    }

    @MainActor @Test func directlyEncodingAPrivateDownloadIsRefused() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.publish()
        let item = try #require(fixture.store.transientDownloads.first)
        #expect(throws: (any Error).self) { try JSONEncoder().encode(item) }
    }

    enum InvalidContext: CaseIterable, Sendable { case regularPayload, unknownProfile, emptyContext, privateStore }

    @MainActor @Test(arguments: InvalidContext.allCases)
    func theSharedTransientEndpointRejectsInvalidContexts(_ kind: InvalidContext) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = kind == .privateStore ? fixture.privateStore() : fixture.store
        store.recordTransientDownload(fixture.snapshot(privateContext: kind != .regularPayload,
            profilePath: kind == .unknownProfile ? fixture.profilePath + "-foreign" : nil),
            contextID: kind == .emptyContext ? "" : "alpha")
        #expect(store.transientDownloads.isEmpty)
    }

    @MainActor @Test func retiringOnePrivateContextKeepsOtherPrivateAndRegularDownloads() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.publish()
        fixture.store.retireTransientDownloads(contextID: "alpha")
        #expect(fixture.store.downloadItems.count == 2)
        #expect(fixture.store.transientDownloads.map(\.privateContextID) == ["beta"])
        #expect(fixture.store.state.downloads.map(\.name) == ["Regular file.pdf"])
    }

    @MainActor @Test func aLivePrivateSourceDoesNotDependOnAnUnrelatedRegularSpace() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.publish()
        let privateItem = try #require(fixture.store.transientDownloads.first)
        let regular = try #require(fixture.store.state.downloads.first)
        #expect(DownloadLibrarySelection.eligible(privateItem, .openSource, spaces: []))
        #expect(!DownloadLibrarySelection.eligible(regular, .openSource, spaces: []))
    }
}

extension PrivateDownloadLibraryTests {
    @MainActor @Test func thePrivateRailWithoutAMediaContextNormalizesToDownloads() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.privateStore()
        let library = LibraryView(store: store, kind: .documents, profileID: store.activeSpace.profileID,
                                  spaceManager: SpaceManagerView(frame: .zero), files: IsolatedNoteFiles.make())
        #expect(library.kind == .downloads)
        #expect(library.accessibilityLabel() == "Downloads")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Private").path))
    }

    @MainActor @Test(arguments: [LibraryView.Kind.archive, .documents, .spaces, .captures])
    func thePrivateRailCannotOpenUnownedPages(_ category: LibraryView.Kind) throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = fixture.privateStore()
        let library = LibraryView(store: store, kind: .downloads, profileID: store.activeSpace.profileID,
                                  spaceManager: SpaceManagerView(frame: .zero), files: IsolatedNoteFiles.make())
        library.show(category)
        #expect(library.kind == .downloads)
    }
}
