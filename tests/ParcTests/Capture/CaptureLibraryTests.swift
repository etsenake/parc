import Foundation
import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ParcCore
@testable import ParcLibrary

@MainActor
private final class LibraryFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcCaptureLibrary-" + UUID().uuidString)
    let profile = UUID()
    let space = UUID()
    let id = UUID()
    let capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
    let png: Data
    let store: CaptureLibraryStore

    init() async {
        let rgba = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255])
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: rgba as CFData)!, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        let output = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, image, nil)
        CGImageDestinationFinalize(encoder)
        png = output as Data
        store = CaptureLibraryStore.shared(directory: root, profileID: profile)
        await store.reload()
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func input(_ expected: UUID? = nil, profileID: UUID? = nil, bytes: Data? = nil) -> CaptureLibraryInput {
        CaptureLibraryInput(id: id, expectedRevision: expected, capturedAt: capturedAt,
                            profileID: profileID ?? profile, spaceID: space, spaceName: "Original Space", title: "A captured page",
                            sourceURL: "https://example.test/original", kind: .region, pngData: bytes ?? png)
    }

    func savedTwice() async throws -> (first: SavedCapture, second: SavedCapture) {
        let first = try await store.save(input())
        return (first, try await store.save(input(first.revision)))
    }
}

struct CaptureLibraryStoreTests {
    @MainActor @Test func aNewLibraryIsEmptyAndHealthy() async {
        let fixture = await LibraryFixture()
        #expect(fixture.store.items.isEmpty && fixture.store.loadError == nil)
    }

    @MainActor @Test func aSavedCaptureKeepsItsProfileSpaceAndCaptureTime() async throws {
        let fixture = await LibraryFixture()
        let saved = try await fixture.store.save(fixture.input())
        #expect(saved.profileID == fixture.profile && saved.spaceID == fixture.space && saved.createdAt == fixture.capturedAt)
    }

    @MainActor @Test func aSavedCaptureReadsBackItsExactBytes() async throws {
        let fixture = await LibraryFixture()
        let saved = try await fixture.store.save(fixture.input())
        #expect(try await fixture.store.data(for: saved) == fixture.png)
    }

    @MainActor @Test func theSameDirectoryAndProfileShareOneStore() async {
        let fixture = await LibraryFixture()
        #expect(CaptureLibraryStore.shared(directory: fixture.root, profileID: fixture.profile) === fixture.store)
    }

    @MainActor @Test func aDirectoryHintSpelledAsAFolderSharesTheSameStore() async {
        let fixture = await LibraryFixture()
        let hint = URL(fileURLWithPath: fixture.root.path, isDirectory: true)
        #expect(CaptureLibraryStore.shared(directory: hint, profileID: fixture.profile) === fixture.store)
    }

    @MainActor @Test func savingWithTheCurrentRevisionReplacesTheCapture() async throws {
        let fixture = await LibraryFixture()
        let (first, second) = try await fixture.savedTwice()
        #expect(second.id == first.id && second.revision != first.revision && fixture.store.items.count == 1)
    }

    @MainActor @Test func aStaleRevisionCannotReplaceANewerCapture() async throws {
        let fixture = await LibraryFixture()
        let (first, _) = try await fixture.savedTwice()
        await #expect(throws: (any Error).self) { _ = try await fixture.store.save(fixture.input(first.revision)) }
    }

    @MainActor @Test func aCrossProfileSaveIsRefused() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        await #expect(throws: (any Error).self) { _ = try await fixture.store.save(fixture.input(second.revision, profileID: UUID())) }
    }

    @MainActor @Test func anInvalidImageIsRefused() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        await #expect(throws: (any Error).self) { _ = try await fixture.store.save(fixture.input(second.revision, bytes: Data("not a PNG".utf8))) }
    }

    @MainActor @Test func anInvalidImageLeavesTheSavedCaptureUntouched() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        _ = try? await fixture.store.save(fixture.input(second.revision, bytes: Data("not a PNG".utf8)))
        #expect(try await fixture.store.data(for: second) == fixture.png)
    }

    @MainActor @Test func exportingWritesTheExactBytes() async throws {
        let fixture = await LibraryFixture()
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let exported = fixture.root.appendingPathComponent("Exported.png")
        try await CaptureLibraryStore.export(fixture.png, to: exported)
        #expect(try Data(contentsOf: exported) == fixture.png)
    }

    @MainActor @Test func aReopenedLibraryReadsTheSavedCatalog() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        let reopenedRoot = fixture.root.appendingPathComponent("Reopened")
        try FileManager.default.createDirectory(at: reopenedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.root.appendingPathComponent("Captures.json"), to: reopenedRoot.appendingPathComponent("Captures.json"))
        try FileManager.default.copyItem(at: fixture.root.appendingPathComponent("Images"), to: reopenedRoot.appendingPathComponent("Images"))
        let reopened = CaptureLibraryStore.shared(directory: reopenedRoot, profileID: fixture.profile)
        await reopened.reload()
        #expect(reopened.items == [second])
    }

    @MainActor @Test func aReopenedLibraryReadsTheSavedBytes() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        let reopenedRoot = fixture.root.appendingPathComponent("Reopened")
        try FileManager.default.createDirectory(at: reopenedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.root.appendingPathComponent("Captures.json"), to: reopenedRoot.appendingPathComponent("Captures.json"))
        try FileManager.default.copyItem(at: fixture.root.appendingPathComponent("Images"), to: reopenedRoot.appendingPathComponent("Images"))
        let reopened = CaptureLibraryStore.shared(directory: reopenedRoot, profileID: fixture.profile)
        await reopened.reload()
        #expect(try await reopened.data(for: second) == fixture.png)
    }

    @MainActor @Test func aStaleDeletionCannotRemoveTheReplacement() async throws {
        let fixture = await LibraryFixture()
        let (first, second) = try await fixture.savedTwice()
        await #expect(throws: (any Error).self) { try await fixture.store.delete(first) }
        #expect(fixture.store.items == [second])
    }

    @MainActor @Test func deletingACaptureEmptiesTheLibrary() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        try await fixture.store.delete(second)
        #expect(fixture.store.items.isEmpty)
    }

    @MainActor @Test func deletingACaptureRemovesItsImageFile() async throws {
        let fixture = await LibraryFixture()
        let (_, second) = try await fixture.savedTwice()
        try await fixture.store.delete(second)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Images").appendingPathComponent(second.assetName).path))
    }
}

struct CaptureLibraryCorruptCatalogTests {
    private static let corrupt = Data("{truncated".utf8)

    @MainActor private func brokenStore(_ fixture: LibraryFixture) async throws -> (CaptureLibraryStore, URL) {
        let directory = fixture.root.appendingPathComponent("Corrupt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.corrupt.write(to: directory.appendingPathComponent("Captures.json"))
        let store = CaptureLibraryStore.shared(directory: directory, profileID: fixture.profile)
        await store.reload()
        return (store, directory)
    }

    @MainActor @Test func aCorruptCatalogReportsALoadError() async throws {
        let fixture = await LibraryFixture()
        let (store, _) = try await brokenStore(fixture)
        #expect(store.loadError != nil)
    }

    @MainActor @Test func aCorruptCatalogIsNeverOverwritten() async throws {
        let fixture = await LibraryFixture()
        let (store, directory) = try await brokenStore(fixture)
        _ = try? await store.save(fixture.input())
        #expect(try Data(contentsOf: directory.appendingPathComponent("Captures.json")) == Self.corrupt)
    }

    @MainActor @Test func savingIntoACorruptCatalogFails() async throws {
        let fixture = await LibraryFixture()
        let (store, _) = try await brokenStore(fixture)
        await #expect(throws: (any Error).self) { _ = try await store.save(fixture.input()) }
    }
}

@MainActor
private final class PrivateLibraryFixture {
    let library: LibraryFixture
    let parent: BrowserStore
    let privateStore: BrowserStore
    let privateDirectory: URL

    init() async throws {
        library = await LibraryFixture()
        parent = try BrowserStore(directory: library.root.appendingPathComponent("Parent"))
        privateDirectory = library.root.appendingPathComponent("Private")
        privateStore = BrowserStore(privateParentProfileID: parent.state.profiles[0].id, engineProfilePath: "/fixture",
                                    directory: privateDirectory, settings: parent.state.settings)
    }

    var parentID: UUID { parent.state.profiles[0].id }

    func destination() -> CaptureLibraryDestination? {
        CaptureLibraryDestination.make(store: privateStore, parent: parent,
                                       profileID: privateStore.activeSpace.profileID, spaceID: privateStore.activeSpaceID)
    }

    func saved() async throws -> SavedCapture {
        let destination = try #require(destination())
        let input = destination.input(id: UUID(), expectedRevision: nil, capturedAt: library.capturedAt,
                                      title: "Private page", sourceURL: "https://example.test/private", kind: .viewport, pngData: library.png)
        let reservation = try #require(destination.reserve())
        return try await reservation.perform { try await destination.library.save(input) }
    }
}

struct CaptureLibraryPrivateDestinationTests {
    @MainActor @Test func privateWindowsNeverAskForEasels() async throws {
        let fixture = try await PrivateLibraryFixture()
        var called = false
        let easels = try #require(fixture.destination()).easels { called = true; return [] }
        #expect(easels.isEmpty && !called)
    }

    @MainActor @Test func aPrivateCaptureIsSavedUnderTheParentProfile() async throws {
        let fixture = try await PrivateLibraryFixture()
        let saved = try await fixture.saved()
        #expect(saved.profileID == fixture.parentID && saved.profileID != fixture.privateStore.activeSpace.profileID)
    }

    @MainActor @Test func aPrivateCaptureIsSavedUnderTheIncognitoSpace() async throws {
        let fixture = try await PrivateLibraryFixture()
        let saved = try await fixture.saved()
        #expect(saved.spaceID != fixture.privateStore.activeSpaceID && saved.spaceName == "Incognito")
    }

    @MainActor @Test func aPrivateCaptureKeepsItsTitleAndAddress() async throws {
        let fixture = try await PrivateLibraryFixture()
        let saved = try await fixture.saved()
        #expect(saved.title == "Private page" && saved.sourceURL == "https://example.test/private")
    }

    @MainActor @Test func aPrivateCaptureReadsBackItsBytes() async throws {
        let fixture = try await PrivateLibraryFixture()
        let saved = try await fixture.saved()
        let destination = try #require(fixture.destination())
        #expect(try await destination.library.data(for: saved) == fixture.library.png)
    }

    @MainActor @Test func aPrivateCaptureNeverWritesToThePrivateDirectory() async throws {
        let fixture = try await PrivateLibraryFixture()
        _ = try await fixture.saved()
        #expect(!FileManager.default.fileExists(atPath: fixture.privateDirectory.path))
    }

    @MainActor @Test func aParentThatIsNotThePrivateWindowsOwnerIsRefused() async throws {
        let fixture = try await PrivateLibraryFixture()
        let other = try BrowserStore(directory: fixture.library.root.appendingPathComponent("OtherParent"))
        let destination = CaptureLibraryDestination.make(store: fixture.privateStore, parent: other,
                                                         profileID: fixture.privateStore.activeSpace.profileID,
                                                         spaceID: fixture.privateStore.activeSpaceID)
        #expect(destination == nil)
    }
}

@MainActor
private final class DeletionFixture {
    let privateFixture: PrivateLibraryFixture
    let removable: UUID
    let owned: CaptureLibraryStore
    var parent: BrowserStore { privateFixture.parent }
    var library: LibraryFixture { privateFixture.library }

    init() async throws {
        privateFixture = try await PrivateLibraryFixture()
        removable = privateFixture.parent.createProfile(name: "Removal test")
        owned = CaptureLibraryStore.shared(directory: privateFixture.parent.capturesDirectory(for: removable), profileID: removable)
        await owned.reload()
    }

    func input(_ revision: UUID? = nil) -> CaptureLibraryInput {
        CaptureLibraryInput(id: library.id, expectedRevision: revision, capturedAt: library.capturedAt,
                            profileID: removable, spaceID: library.space, spaceName: "Test", title: "Test",
                            sourceURL: "https://example.test", kind: .viewport, pngData: library.png)
    }
}

struct CaptureLibraryDeletionTests {
    @MainActor @Test func anUnrelatedOwnerCannotReserveADeletion() async throws {
        let fixture = try await DeletionFixture()
        let candidate = try await fixture.owned.save(fixture.input())
        let other = try BrowserStore(directory: fixture.library.root.appendingPathComponent("OtherParent"))
        #expect(fixture.owned.reserveDeletion(owner: other, item: candidate) == nil)
    }

    @MainActor @Test func aPrivateWindowCannotReserveADeletion() async throws {
        let fixture = try await DeletionFixture()
        let candidate = try await fixture.owned.save(fixture.input())
        #expect(fixture.owned.reserveDeletion(owner: fixture.privateFixture.privateStore, item: candidate) == nil)
    }

    @MainActor @Test func removingAProfileCannotCrossAnInFlightDeletion() async throws {
        let fixture = try await DeletionFixture()
        let candidate = try await fixture.owned.save(fixture.input())
        let reservation = try #require(fixture.owned.reserveDeletion(owner: fixture.parent, item: candidate))
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let (gate, gateSignal) = AsyncStream<Void>.makeStream()
        let owned = fixture.owned
        let deletion = Task {
            try await reservation.perform {
                startedSignal.yield()
                for await _ in gate { break }
                try await owned.delete(candidate)
            }
        }
        for await _ in started { break }
        #expect(throws: (any Error).self) { try fixture.parent.stageProfileRemoval(fixture.removable, expectedName: "Removal test") }
        gateSignal.yield()
        try await deletion.value
    }

    @MainActor @Test func aDeletedCaptureCannotBeReservedAgain() async throws {
        let fixture = try await DeletionFixture()
        let candidate = try await fixture.owned.save(fixture.input())
        let reservation = try #require(fixture.owned.reserveDeletion(owner: fixture.parent, item: candidate))
        try await reservation.perform { try await fixture.owned.delete(candidate) }
        #expect(!fixture.owned.contains(candidate) && fixture.owned.reserveDeletion(owner: fixture.parent, item: candidate) == nil)
    }

    @MainActor @Test func aStaleReservedDeletionFailsAndKeepsTheReplacement() async throws {
        let fixture = try await DeletionFixture()
        let current = try await fixture.owned.save(fixture.input())
        let stale = try #require(fixture.owned.reserveDeletion(owner: fixture.parent, item: current))
        let replacement = try await fixture.owned.save(fixture.input(current.revision))
        await #expect(throws: (any Error).self) { try await stale.perform { try await fixture.owned.delete(current) } }
        #expect(fixture.owned.contains(replacement))
    }

    @MainActor @Test func aPendingProfileRemovalBlocksDeletionUntilCancelled() async throws {
        let fixture = try await DeletionFixture()
        let candidate = try await fixture.owned.save(fixture.input())
        let staged = try fixture.parent.stageProfileRemoval(fixture.removable, expectedName: "Removal test")
        #expect(fixture.owned.reserveDeletion(owner: fixture.parent, item: candidate) == nil)
        try fixture.parent.cancelProfileRemoval(staged)
        #expect(fixture.owned.reserveDeletion(owner: fixture.parent, item: candidate) != nil)
    }
}
