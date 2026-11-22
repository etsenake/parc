import AppKit
import Combine
import Darwin
import Testing
@testable import Parc
@testable import ParcLibrary

struct ExternalMediaLibraryTests {
    private struct DiskFixture {
        let root: URL
        let folder: URL
        let profile: URL
        let disk: ExternalMediaDisk
        let png: Data
        let time = ContinuousClock.now

        init() throws {
            root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            folder = root.appendingPathComponent("Files", isDirectory: true).standardizedFileURL
            profile = root.appendingPathComponent("Profile", isDirectory: true)
            disk = ExternalMediaDisk(directory: profile)
            let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let image = try #require(context.makeImage())
            png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }

        func save(_ name: String = "Capture.png", contents: Data? = nil) throws -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: false).standardizedFileURL
            try (contents ?? png).write(to: url)
            return url
        }

        func scan() async throws -> ExternalMediaDisk.Snapshot { try await disk.scan(systemFolders: [folder]) }

        func entry(_ url: URL) async throws -> ExternalMediaFile {
            let snapshot = try await scan()
            return try #require(snapshot.catalog.index[url.path])
        }

        func mark(_ attribute: String, at url: URL) throws {
            let bytes = Data("yes".utf8)
            let result = bytes.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0) }
            try #require(result == 0)
        }

        func grow(_ url: URL) throws {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            _ = try file.seekToEnd()
            try file.write(contentsOf: png)
        }
    }

    enum SkippedEntry: CaseIterable, Sendable { case hidden, nested, symbolicLink, unsupported }

    @Test(arguments: SkippedEntry.allCases)
    func scanningOnlyListsDirectRegularMediaFiles(_ input: SkippedEntry) async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let original = try fixture.save()
        switch input {
        case .hidden: _ = try fixture.save(".Hidden.png")
        case .nested:
            let folder = fixture.folder.appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try fixture.png.write(to: folder.appendingPathComponent("Nested.png"))
        case .symbolicLink:
            try FileManager.default.createSymbolicLink(at: fixture.folder.appendingPathComponent("Link.png"), withDestinationURL: original)
        case .unsupported: _ = try fixture.save("Document.txt")
        }
        let snapshot = try await fixture.scan()
        #expect(snapshot.catalog.items.map(\.id) == [original.path])
    }

    @Test func duplicateLocationsAreListedOnceAndMissingLocationsAreUnavailable() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let missing = fixture.root.appendingPathComponent("Missing", isDirectory: true)
        let snapshot = try await fixture.disk.scan(systemFolders: [fixture.folder, fixture.folder, missing])
        #expect(snapshot.folders.filter { $0.url.path == fixture.folder.path }.count == 1)
        let missingFolder = try #require(snapshot.folders.first { $0.url.path == missing.path })
        guard case .unavailable = missingFolder.access else { Issue.record("Expected the missing location to be unavailable"); return }
    }

    @Test func aScreenshotRetainsItsFileModificationDate() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let url = try fixture.save()
        let date = Date(timeIntervalSince1970: 100)
        try fixture.mark("com.apple.metadata:kMDItemIsScreenCapture", at: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        let image = try await fixture.entry(url)
        #expect(image.kind == .image && image.isScreenshot && image.date == date)
    }

    @Test(arguments: [false, true])
    func aMovieWithDownloadProvenanceIsNotAScreenRecording(_ downloaded: Bool) async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let url = try fixture.save("Capture.mov", contents: Data("movie fixture".utf8))
        if downloaded { try fixture.mark("com.apple.metadata:kMDItemWhereFroms", at: url) }
        let movie = try await fixture.entry(url)
        #expect(movie.kind == .movie && movie.isScreenRecording != downloaded)
    }

    @Test func anUnchangedRescanKeepsTheCatalogVersion() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        _ = try fixture.save()
        let original = try await fixture.scan()
        let repeatScan = try await fixture.scan()
        #expect(repeatScan.catalog.version == original.catalog.version)
    }

    @Test func newestFilesLeadWithIdentityAsTheTieBreaker() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let b = try fixture.save("B.png"), a = try fixture.save("A.png"), recent = try fixture.save("Z.png")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: b.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: recent.path)
        let snapshot = try await fixture.scan()
        #expect(snapshot.catalog.items.map(\.id) == [recent.path, a.path, b.path])
    }

    @Test func aTargetedUpdateOnlyRereadsItsOriginalFile() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let target = try fixture.save(), unrelated = try fixture.save("Other.png")
        let before = try await fixture.scan()
        try fixture.grow(target)
        try fixture.grow(unrelated)
        let change = try await fixture.disk.update(paths: [target.path], at: fixture.time)
        let catalog = try #require(change.catalog)
        #expect(catalog.index[target.path]?.revision.size == Int64(fixture.png.count * 2))
        #expect(catalog.index[unrelated.path]?.revision == before.catalog.index[unrelated.path]?.revision)
    }

    @Test(arguments: ["Renamed.png", "CAPTURE.png"])
    func renamingAMediaFileReplacesItsOldIdentity(_ name: String) async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let original = try fixture.save()
        _ = try await fixture.scan()
        let renamed = fixture.folder.appendingPathComponent(name)
        try #require(Darwin.rename(original.path, renamed.path) == 0)
        let result = try await fixture.disk.update(paths: [original.path, renamed.path], at: fixture.time)
        #expect(result.catalog?.items.map(\.id) == [renamed.path])
    }

    @Test func aNewCompleteFileAppearsImmediately() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.scan()
        let file = try fixture.save()
        let result = try await fixture.disk.update(paths: [file.path], at: fixture.time)
        #expect(result.catalog?.index[file.path] != nil && result.settle == nil)
    }

    @Test func aGrowingFileWaitsUntilItsLastWriteSettles() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.scan()
        let file = try fixture.save()
        _ = try await fixture.disk.update(paths: [file.path], at: fixture.time)
        try fixture.grow(file)
        let lastWrite = fixture.time.advanced(by: .milliseconds(250))
        let growing = try await fixture.disk.update(paths: [file.path], at: lastWrite)
        #expect(growing.catalog == nil && growing.settle == .seconds(1))
        let early = try await fixture.disk.settle(at: lastWrite.advanced(by: .milliseconds(750)))
        #expect(early.catalog == nil && early.settle == .milliseconds(250))
        let settled = try await fixture.disk.settle(at: lastWrite.advanced(by: .seconds(1)))
        #expect(settled.catalog?.index[file.path]?.revision.size == Int64(fixture.png.count * 2))
        #expect(settled.settle == nil)
    }

    @Test func removingAGrowingFileDoesNotWaitForItsSettleDeadline() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.scan()
        let file = try fixture.save()
        _ = try await fixture.disk.update(paths: [file.path], at: fixture.time)
        try fixture.grow(file)
        _ = try await fixture.disk.update(paths: [file.path], at: fixture.time.advanced(by: .milliseconds(250)))
        try FileManager.default.removeItem(at: file)
        let removed = try await fixture.disk.update(paths: [file.path], at: fixture.time.advanced(by: .milliseconds(500)))
        #expect(removed.catalog?.items.isEmpty == true && removed.settle == nil)
    }

    @Test func exportingWritesTheOriginalBytes() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let file = try await fixture.entry(fixture.save())
        let export = fixture.root.appendingPathComponent("Export.png")
        try await fixture.disk.export(file, to: export)
        #expect(try Data(contentsOf: export) == fixture.png)
    }

    @Test(arguments: [false, true])
    func exportingCannotOverwriteTheOriginalOrAHardLink(_ hardLink: Bool) async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let original = try fixture.save()
        let target = hardLink ? fixture.root.appendingPathComponent("Alias.png") : original
        if hardLink { try FileManager.default.linkItem(at: original, to: target) }
        let file = try await fixture.entry(original)
        await #expect(throws: ExternalMediaFailure.sameFile) {
            try await fixture.disk.export(file, to: target)
        }
    }

    @Test func hidingAnItemKeepsTheOriginalFile() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let url = try fixture.save()
        let file = try await fixture.entry(url)
        let catalog = try await fixture.disk.hide(file)
        #expect(catalog.index[url.path] == nil && FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aPrivateRestoreKeepsTheParentAndOtherPrivateCatalogsHidden() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let url = try fixture.save()
        _ = try await fixture.disk.hide(fixture.entry(url))
        let manifest = fixture.profile.appendingPathComponent("MediaFolders.json")
        let before = try Data(contentsOf: manifest)
        let privateA = ExternalMediaDisk(directory: fixture.profile, preferencesAreEphemeral: true)
        let privateB = ExternalMediaDisk(directory: fixture.profile, preferencesAreEphemeral: true)
        _ = try await privateA.scan(systemFolders: [fixture.folder])
        try await privateA.restoreHidden()
        let restored = try await privateA.scan(systemFolders: [fixture.folder])
        let isolated = try await privateB.scan(systemFolders: [fixture.folder])
        #expect(restored.catalog.index[url.path] != nil && isolated.catalog.index[url.path] == nil)
        #expect(try Data(contentsOf: manifest) == before)
    }

    @Test func privateChangesNeverCreateAnAbsentParentConfiguration() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let privateDisk = ExternalMediaDisk(directory: fixture.profile, preferencesAreEphemeral: true)
        _ = try await privateDisk.setEnabled(false, folder: fixture.folder)
        #expect(!FileManager.default.fileExists(atPath: fixture.profile.path))
    }

    @Test func disablingTheFolderRevokesExistingFileAccess() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let file = try await fixture.entry(fixture.save())
        _ = try await fixture.disk.setEnabled(false, folder: fixture.folder)
        await #expect(throws: ExternalMediaFailure.changed) { try await fixture.disk.validate(file) }
    }

    @Test func aReplacedFileCannotBeReadWithTheOldRevision() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        let url = try fixture.save()
        let file = try await fixture.entry(url)
        try Data("replacement".utf8).write(to: url, options: .atomic)
        await #expect(throws: ExternalMediaFailure.changed) { try await fixture.disk.data(file) }
    }

    @Test func corruptFolderPreferencesAreNeverOverwritten() async throws {
        let fixture = try DiskFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.profile, withIntermediateDirectories: true)
        let corrupt = Data("invalid JSON".utf8)
        let manifest = fixture.profile.appendingPathComponent("MediaFolders.json")
        try corrupt.write(to: manifest)
        await #expect(throws: ExternalMediaFailure.invalidConfiguration) {
            try await fixture.disk.setEnabled(true, folder: fixture.folder)
        }
        #expect(try Data(contentsOf: manifest) == corrupt)
    }
}

struct MediaLibraryContextTests {
    private static let order = ["file:A", "capture:B", "file:C", "capture:D"]

    @Test(arguments: [0, 1, 2, 3])
    func navigationUsesTheMixedCaptureAndExternalFileOrder(_ index: Int) {
        let order = Self.order
        let navigation = MediaLibraryNavigation(orderedIDs: order, selectedID: order[index])
        #expect(navigation.ordinal == index + 1)
        #expect(navigation.neighbor(-1) == (index > 0 ? order[index - 1] : nil))
        #expect(navigation.neighbor(1) == (index + 1 < order.count ? order[index + 1] : nil))
    }

    @Test func filteringOutTheSelectionWithdrawsItsNeighbors() {
        let navigation = MediaLibraryNavigation(orderedIDs: ["file:C"], selectedID: "capture:D")
        #expect(navigation.index == nil && navigation.neighbor(-1) == nil)
    }

    @Test(arguments: [(UInt64(3), true, true, true), (4, true, true, false), (3, false, true, false), (3, true, false, false)])
    func anActionRequiresTheSameLiveOwnerItemAndGeneration(_ generation: UInt64, _ owner: Bool, _ item: Bool, _ valid: Bool) {
        #expect(MediaLibraryActionTicket(generation: 3).canCommit(generation: generation, ownerValid: owner, itemCurrent: item) == valid)
    }
}

struct MediaLibraryThumbnailOperationTests {
    @Test func aSynchronouslyCompletedThumbnailReturnsItsOriginalBytes() async throws {
        let bytes = Data([4, 5])
        let operation = MediaLibraryThumbnailOperation(start: { $0(.success(bytes)) }, stop: {})
        #expect(try await operation.value() == bytes)
    }

    @Test func cancelingAThumbnailStopsItsWorkAndRejectsLateBytes() async throws {
        let (started, notify) = AsyncStream<MediaLibraryThumbnailOperation.Completion>.makeStream()
        let (stopped, stop) = AsyncStream<Void>.makeStream()
        let operation = MediaLibraryThumbnailOperation(start: { notify.yield($0) }, stop: { stop.yield() })
        let pending = Task { try await operation.value() }
        var starts = started.makeAsyncIterator()
        let start = await starts.next()
        let callback = try #require(start)
        pending.cancel()
        callback(.success(Data([1, 2, 3])))
        await #expect(throws: CancellationError.self) { try await pending.value }
        var stops = stopped.makeAsyncIterator()
        let didStop: Void? = await stops.next()
        #expect(didStop != nil)
    }
}

struct ExternalMediaObservationTests {
    @MainActor private final class Fixture {
        typealias Event = @Sendable (ExternalMediaWatcher.Batch) -> Void
        let directory: URL
        let folder: URL
        let file: URL
        let client = UUID()
        let cloud = Cloud()
        var event: Event?
        var roots: Set<String> = []
        weak var watcher: NSObject?

        lazy var library = ExternalMediaLibrary(directory: directory.appendingPathComponent("Profile"),
            systemFolders: { [folder] in [folder] }, cloud: cloud.source, screenshotPreferences: nil,
            makeWatcher: { [weak self] aliases, _, event in
                let watcher = NSObject()
                self?.roots = Set(aliases.values)
                self?.event = event
                self?.watcher = watcher
                return watcher
            })

        init() throws {
            directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
            folder = directory.appendingPathComponent("Scanned", isDirectory: true)
            file = folder.appendingPathComponent("First.png")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1]).write(to: file)
        }

        func start() async throws {
            let load = try #require(library.activate(client))
            await load.value
        }

        func teardown() {
            library.deactivate(client)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private final class Cloud: @unchecked Sendable {
        private final class Observation: ExternalMediaCloudObservation, @unchecked Sendable {
            let onPresent: @Sendable (Set<String>) -> Void
            init(onPresent: @escaping @Sendable (Set<String>) -> Void) { self.onPresent = onPresent }
            func present(_ folders: Set<String>) { onPresent(folders) }
        }

        private let lock = NSLock()
        private var reports: (@Sendable (Set<String>) -> Void)?
        private var folders: Set<String> = []
        private var evicted: Set<String> = []
        private weak var observation: Observation?
        var enabled = false

        private func locked<T>(_ read: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return read()
        }

        var watched: Set<String> { locked { folders } }
        var isObserving: Bool { locked { observation != nil } }

        var source: ExternalMediaCloud {
            let enabled = enabled
            return ExternalMediaCloud(isSynced: { _ in enabled }, isLocal: { [self] path, _ in locked { !evicted.contains(path) } },
                observe: { [self] handler in
                    let observation = Observation { [weak self] locations in
                        guard let self else { return }
                        locked { self.folders = locations }
                    }
                    locked {
                        reports = handler
                        self.observation = observation
                    }
                    return observation
                })
        }

        func evict(_ path: String) {
            let handler = locked {
                evicted.insert(path)
                return reports
            }
            handler?([path])
        }
    }

    @MainActor @Test func openingMediaStartsWatchingOnlyItsScannedFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try await fixture.start()
        #expect(fixture.roots == [fixture.folder.path])
        #expect(fixture.library.items.map(\.id) == [fixture.file.path])
    }

    @MainActor @Test func anUnchangedRefreshDoesNotRepublishMediaItems() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try await fixture.start()
        let revision = fixture.library.revision
        let refresh = try #require(fixture.library.refresh())
        await refresh.value
        #expect(fixture.library.revision == revision)
        #expect(!fixture.library.isLoading)
    }

    @MainActor @Test func onlyTheLastClientReleasesTheObservedCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try await fixture.start()
        let second = UUID()
        let refresh = try #require(fixture.library.activate(second))
        await refresh.value
        fixture.library.deactivate(second)
        #expect(fixture.library.items.map(\.id) == [fixture.file.path])
        fixture.library.deactivate(fixture.client)
        #expect(fixture.library.items.isEmpty && fixture.watcher == nil)
    }

    @MainActor @Test func aFolderReportPublishesTheExactArrivingFile() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try await fixture.start()
        let report = try #require(fixture.event)
        let second = fixture.folder.appendingPathComponent("Second.png")
        try Data([1, 2]).write(to: second)
        let (changes, send) = AsyncStream<[ExternalMediaFile]>.makeStream()
        let observation = fixture.library.$items.dropFirst().sink { send.yield($0) }
        defer { observation.cancel(); send.finish() }
        report(.paths([second.path]))
        var iterator = changes.makeAsyncIterator()
        let changed = await iterator.next()
        #expect(Set(changed?.map(\.id) ?? []) == [fixture.file.path, second.path])
    }

    @MainActor @Test func localFoldersDoNotStartCloudObservation() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        try await fixture.start()
        #expect(!fixture.cloud.isObserving)
    }

    @MainActor @Test func leavingMediaReleasesTheCloudObserverForItsFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.cloud.enabled = true
        try await fixture.start()
        #expect(fixture.cloud.isObserving && fixture.cloud.watched == [fixture.folder.path])
        fixture.library.deactivate(fixture.client)
        #expect(!fixture.cloud.isObserving)
    }

    @MainActor @Test func aCloudEvictionRefreshesTheTileWithoutWaitingToSettle() async throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.cloud.enabled = true
        try await fixture.start()
        let (changes, send) = AsyncStream<[ExternalMediaFile]>.makeStream()
        let observation = fixture.library.$items.dropFirst().sink { send.yield($0) }
        defer { observation.cancel(); send.finish() }
        fixture.cloud.evict(fixture.file.path)
        var iterator = changes.makeAsyncIterator()
        let changed = await iterator.next()
        #expect(changed?.first?.isLocal == false)
        #expect(changed?.first?.detail == "Download in Finder to preview")
    }
}
