import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Production-store persistence checks. Run in a temporary directory only; no
/// browser, renderer, profile fixture, UI or substitute capture service is used.
@main
struct CaptureLibraryTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ParcCaptureLibrary-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = UUID(), space = UUID(), id = UUID(), capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
        // Encode real 2×2 pixels independently of the production store.
        let rgba = Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,255,255])
        let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: rgba as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(encoder, image, nil); precondition(CGImageDestinationFinalize(encoder))
        let png = output as Data
        let store = CaptureLibraryStore.shared(directory: root, profileID: profile)
        await store.reload()
        precondition(store.items.isEmpty && store.loadError == nil)
        func input(_ expected: UUID? = nil, profileID: UUID? = nil, bytes: Data? = nil) -> CaptureLibraryInput {
            CaptureLibraryInput(id: id, expectedRevision: expected, capturedAt: capturedAt,
                profileID: profileID ?? profile, spaceID: space, spaceName: "Original Space", title: "A captured page",
                sourceURL: "https://example.test/original", kind: .region, pngData: bytes ?? png)
        }
        let first = try await store.save(input())
        precondition(first.profileID == profile && first.spaceID == space && first.createdAt == capturedAt)
        let firstData = try await store.data(for: first); precondition(firstData == png)
        let shared = CaptureLibraryStore.shared(directory: root, profileID: profile)
        precondition(shared === store)
        let directoryHint = URL(fileURLWithPath: root.path, isDirectory: true)
        precondition(CaptureLibraryStore.shared(directory: directoryHint, profileID: profile) === store)
        let second = try await store.save(input(first.revision))
        precondition(second.id == first.id && second.revision != first.revision && store.items.count == 1)
        do { _ = try await store.save(input(first.revision)); fatalError("Stale revision replaced a newer capture") } catch {}
        do { _ = try await store.save(input(second.revision, profileID: UUID())); fatalError("Cross-profile save was accepted") } catch {}
        do { _ = try await store.save(input(second.revision, bytes: Data("not a PNG".utf8))); fatalError("Invalid image replaced capture") } catch {}
        let secondData = try await store.data(for: second); precondition(secondData == png)
        let exported = root.appendingPathComponent("Exported.png")
        try await CaptureLibraryStore.export(secondData, to: exported)
        let exportedData = try Data(contentsOf: exported); precondition(exportedData == png)
        // A fresh owner reconstructs from the actual persisted catalog/assets.
        let reopenedRoot = root.appendingPathComponent("Reopened")
        try FileManager.default.createDirectory(at: reopenedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("Captures.json"), to: reopenedRoot.appendingPathComponent("Captures.json"))
        try FileManager.default.copyItem(at: root.appendingPathComponent("Images"), to: reopenedRoot.appendingPathComponent("Images"))
        let reopened = CaptureLibraryStore.shared(directory: reopenedRoot, profileID: profile)
        await reopened.reload(); precondition(reopened.items == [second])
        let reopenedData = try await reopened.data(for: second); precondition(reopenedData == png)
        do { try await store.delete(first); fatalError("Stale deletion removed replacement") } catch {}
        try await store.delete(second)
        precondition(store.items.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Images").appendingPathComponent(second.assetName).path))
        let corruptRoot = root.appendingPathComponent("Corrupt")
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corrupt = Data("{truncated".utf8)
        try corrupt.write(to: corruptRoot.appendingPathComponent("Captures.json"))
        let broken = CaptureLibraryStore.shared(directory: corruptRoot, profileID: profile)
        await broken.reload(); precondition(broken.loadError != nil)
        do { _ = try await broken.save(input()); fatalError("Corrupt catalog was overwritten") } catch {}
        let preserved = try Data(contentsOf: corruptRoot.appendingPathComponent("Captures.json")); precondition(preserved == corrupt)
        // The production destination selects the real normal parent and never
        // writes the private window's synthetic profile/Space or another owner.
        let parentDirectory = root.appendingPathComponent("Parent")
        let parentStore = try BrowserStore(directory: parentDirectory)
        let parentID = parentStore.state.profiles[0].id
        let privateDirectory = root.appendingPathComponent("Private")
        let privateStore = BrowserStore(privateParentProfileID: parentID, engineProfilePath: "/fixture",
                                        directory: privateDirectory, settings: parentStore.state.settings)
        let privateID = privateStore.activeSpace.profileID, privateSpace = privateStore.activeSpaceID
        let destination = CaptureLibraryDestination.make(store: privateStore, parent: parentStore,
                                                         profileID: privateID, spaceID: privateSpace)!
        var easelProviderCalled = false
        let easels = destination.easels { easelProviderCalled = true; return [] }
        precondition(easels.isEmpty && !easelProviderCalled)
        let privateInput = destination.input(id: UUID(), expectedRevision: nil, capturedAt: capturedAt,
            title: "Private page", sourceURL: "https://example.test/private", kind: .viewport, pngData: png)
        let reservation = destination.reserve()!
        let saved = try await reservation.perform { try await destination.library.save(privateInput) }
        let privateBytes = try await destination.library.data(for: saved)
        precondition(privateBytes == png && saved.profileID == parentID && saved.profileID != privateID)
        precondition(saved.spaceID != privateSpace && saved.spaceName == "Incognito")
        precondition(saved.title == "Private page" && saved.sourceURL == "https://example.test/private")
        precondition(!FileManager.default.fileExists(atPath: privateDirectory.path))
        let other = try BrowserStore(directory: root.appendingPathComponent("OtherParent"))
        precondition(CaptureLibraryDestination.make(store: privateStore, parent: other,
                                                    profileID: privateID, spaceID: privateSpace) == nil)
        let wrong = CaptureLibraryStore.shared(directory: other.capturesDirectory(for: other.state.profiles[0].id),
                                               profileID: other.state.profiles[0].id)
        await wrong.reload(); precondition(wrong.items.isEmpty)
        // A deletion reserves the exact durable owner before asynchronous work.
        // This disposable profile is removable; the parent default profile is not.
        let removable = parentStore.createProfile(name: "Removal test")
        let owned = CaptureLibraryStore.shared(directory: parentStore.capturesDirectory(for: removable), profileID: removable)
        await owned.reload()
        func deletionInput(_ revision: UUID? = nil) -> CaptureLibraryInput {
            CaptureLibraryInput(id: id, expectedRevision: revision, capturedAt: capturedAt,
                profileID: removable, spaceID: space, spaceName: "Test", title: "Test",
                sourceURL: "https://example.test", kind: .viewport, pngData: png)
        }
        let candidate = try await owned.save(deletionInput())
        precondition(owned.reserveDeletion(owner: other, item: candidate) == nil)
        precondition(owned.reserveDeletion(owner: privateStore, item: candidate) == nil)
        var ownerReservation: ProfileWriteReservation? = owned.reserveDeletion(owner: parentStore, item: candidate)!
        var resumeDelete: CheckedContinuation<Void, Never>?
        let deletion = Task { [reservation = ownerReservation!] in
            try await reservation.perform {
                await withCheckedContinuation { resumeDelete = $0 }
                try await owned.delete(candidate)
            }
        }
        ownerReservation = nil
        while resumeDelete == nil { await Task.yield() }
        do { _ = try parentStore.stageProfileRemoval(removable, expectedName: "Removal test"); fatalError("Removal crossed an in-flight deletion") } catch {}
        resumeDelete?.resume(); try await deletion.value
        precondition(!owned.contains(candidate))
        precondition(owned.reserveDeletion(owner: parentStore, item: candidate) == nil)
        let current = try await owned.save(deletionInput())
        let failingReservation = owned.reserveDeletion(owner: parentStore, item: current)!
        let replacement = try await owned.save(deletionInput(current.revision))
        do { try await failingReservation.perform { try await owned.delete(current) }; fatalError("Stale delete succeeded") } catch {}
        precondition(owned.contains(replacement))
        let staged = try parentStore.stageProfileRemoval(removable, expectedName: "Removal test")
        precondition(owned.reserveDeletion(owner: parentStore, item: replacement) == nil)
        try parentStore.cancelProfileRemoval(staged)
        let finalReservation = owned.reserveDeletion(owner: parentStore, item: replacement)!
        try await finalReservation.perform { try await owned.delete(replacement) }
        print("Capture Library persistence checks passed")
    }
}
