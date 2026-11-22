import Foundation
import Combine
import ImageIO
import ParcCore
import UniformTypeIdentifiers

package struct SavedCapture: Codable, Equatable, Identifiable, Sendable {
    package enum Kind: String, Codable, Sendable { case region, viewport, fullPage, portrait }
    package let id: UUID
    package let revision: UUID
    package let profileID: UUID
    let spaceID: UUID
    let spaceName: String
    let title: String
    package let sourceURL: String
    let createdAt: Date
    let kind: Kind
    let pixelWidth: Int
    let pixelHeight: Int
    var assetName: String { revision.uuidString + ".png" }
}

package struct CaptureLibraryInput: Sendable {
    let id: UUID
    let expectedRevision: UUID?
    let capturedAt: Date
    let profileID: UUID
    let spaceID: UUID
    let spaceName: String
    let title: String
    let sourceURL: String
    let kind: SavedCapture.Kind
    let pngData: Data
}

@MainActor
package final class CaptureLibraryStore: ObservableObject {
    private final class Weak { weak var value: CaptureLibraryStore?; init(_ value: CaptureLibraryStore) { self.value = value } }
    private struct OwnerKey: Hashable { let directory: String; let profileID: UUID }
    private static var owners: [OwnerKey: Weak] = [:]
    package static func shared(directory: URL, profileID: UUID) -> CaptureLibraryStore {
        let key = OwnerKey(directory: directory.standardizedFileURL.path, profileID: profileID)
        if let existing = owners[key]?.value { return existing }
        owners = owners.filter { $0.value.value != nil }
        let store = CaptureLibraryStore(directory: URL(fileURLWithPath: key.directory, isDirectory: true), profileID: profileID)
        owners[key] = Weak(store); return store
    }
    @Published package private(set) var items: [SavedCapture] = []
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = true
    let profileID: UUID
    private let directoryPath: String
    private let disk: CaptureLibraryDisk
    private var generation: UInt64 = 0
    private init(directory: URL, profileID: UUID) {
        self.profileID = profileID; directoryPath = directory.standardizedFileURL.path
        disk = CaptureLibraryDisk(directory: directory, profileID: profileID)
        Task { await reload() }
    }
    func reload() async {
        do { apply(try await disk.snapshot()); loadError = nil }
        catch { loadError = error.localizedDescription }
        isLoading = false
    }
    package func save(_ input: CaptureLibraryInput) async throws -> SavedCapture {
        let result = try await disk.save(input); apply(result)
        guard let item = result.items.first(where: { $0.id == input.id }) else { throw CaptureLibraryFailure.changed }
        return item
    }
    package func delete(_ item: SavedCapture) async throws {
        do { apply(try await disk.delete(item)) }
        catch {
            if let snapshot = try? await disk.snapshot() { apply(snapshot) }
            throw error
        }
    }
    package func data(for item: SavedCapture) async throws -> Data { try await disk.data(for: item) }
    package func thumbnail(for item: SavedCapture) async throws -> Data { try await disk.thumbnail(for: item) }
    func preview(for item: SavedCapture) async throws -> CaptureLibraryPreviewData { try await disk.preview(for: item) }
    nonisolated static func export(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) { try data.write(to: url, options: .atomic) }.value
    }
    package func contains(_ item: SavedCapture) -> Bool { items.contains(item) }
    package func reserveDeletion(owner: BrowserStore, item: SavedCapture) -> ProfileWriteReservation? {
        guard item.profileID == profileID, contains(item),
              directoryPath == owner.capturesDirectory(for: profileID).standardizedFileURL.path else { return nil }
        return owner.reserveProfileWrite(profileID)
    }
    private func apply(_ result: CaptureLibraryDisk.Snapshot) {
        guard result.generation >= generation else { return }
        generation = result.generation; items = result.items; loadError = nil
    }
}

struct CaptureLibraryPreviewData: Sendable { let original: Data; let display: Data }

private enum CaptureLibraryFailure: LocalizedError {
    case changed, invalidImage, invalidCatalog
    var errorDescription: String? {
        switch self {
        case .changed: return "This capture changed or was removed. Reopen the Library and try again."
        case .invalidImage: return "The image could not be read as a PNG."
        case .invalidCatalog: return "The capture Library could not be read. Its existing files have been preserved."
        }
    }
}

private actor CaptureLibraryDisk {
    struct Snapshot: Sendable { let generation: UInt64; let items: [SavedCapture] }
    private struct Catalog: Codable { let version: Int; var items: [SavedCapture] }
    private let directory: URL
    private let profileID: UUID
    private var generation: UInt64 = 0
    private var catalog: Catalog?
    init(directory: URL, profileID: UUID) { self.directory = directory; self.profileID = profileID }
    private var manifest: URL { directory.appendingPathComponent("Captures.json") }
    private var images: URL { directory.appendingPathComponent("Images", isDirectory: true) }
    private func read() throws -> Catalog {
        if let catalog { return catalog }
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            let empty = Catalog(version: 1, items: []); catalog = empty; return empty
        }
        let data = try Data(contentsOf: manifest)
        guard let loaded = try? JSONDecoder().decode(Catalog.self, from: data), loaded.version == 1,
              Set(loaded.items.map(\.id)).count == loaded.items.count,
              Set(loaded.items.map(\.revision)).count == loaded.items.count,
              loaded.items.allSatisfy({ $0.profileID == profileID && $0.pixelWidth > 0 && $0.pixelHeight > 0 }) else {
            throw CaptureLibraryFailure.invalidCatalog
        }
        catalog = loaded; cleanUnreferencedImages(in: loaded); return loaded
    }
    func snapshot() throws -> Snapshot { Snapshot(generation: generation, items: try read().items) }
    private func commit(_ next: Catalog) throws -> Snapshot {
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: manifest, options: .atomic)
        catalog = next; generation &+= 1
        return Snapshot(generation: generation, items: next.items)
    }
    func save(_ input: CaptureLibraryInput) throws -> Snapshot {
        guard input.profileID == profileID else { throw CaptureLibraryFailure.changed }
        guard let source = CGImageSourceCreateWithData(input.pngData as CFData, nil),
              let type = CGImageSourceGetType(source), type as String == UTType.png.identifier,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CaptureLibraryFailure.invalidImage }
        var next = try read()
        let old = next.items.first { $0.id == input.id }
        guard old?.revision == input.expectedRevision else { throw CaptureLibraryFailure.changed }
        let item = SavedCapture(id: input.id, revision: UUID(), profileID: profileID,
            spaceID: input.spaceID, spaceName: input.spaceName, title: input.title, sourceURL: input.sourceURL,
            createdAt: old?.createdAt ?? input.capturedAt, kind: input.kind, pixelWidth: image.width, pixelHeight: image.height)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let imageURL = images.appendingPathComponent(item.assetName)
        try input.pngData.write(to: imageURL, options: .atomic)
        next.items.removeAll { $0.id == item.id }; next.items.append(item)
        next.items.sort { $0.createdAt > $1.createdAt }
        do {
            let result = try commit(next)
            cleanUnreferencedImages(in: next)
            return result
        } catch { try? FileManager.default.removeItem(at: imageURL); throw error }
    }
    func delete(_ item: SavedCapture) throws -> Snapshot {
        let previous = try read()
        guard previous.items.contains(item) else { throw CaptureLibraryFailure.changed }
        var next = previous; next.items.removeAll { $0.id == item.id }
        let result = try commit(next)
        let url = images.appendingPathComponent(item.assetName)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            _ = try commit(previous); throw error
        }
        cleanUnreferencedImages(in: next)
        return result
    }
    func data(for item: SavedCapture) throws -> Data {
        guard try read().items.contains(item) else { throw CaptureLibraryFailure.changed }
        return try Data(contentsOf: images.appendingPathComponent(item.assetName), options: .mappedIfSafe)
    }
    func preview(for item: SavedCapture) throws -> CaptureLibraryPreviewData {
        let original = try data(for: item)
        return CaptureLibraryPreviewData(original: original, display: try reducedImage(original, maximum: 2200))
    }
    func thumbnail(for item: SavedCapture) throws -> Data { try reducedImage(data(for: item), maximum: 360) }
    private func reducedImage(_ data: Data, maximum: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum] as CFDictionary) else { throw CaptureLibraryFailure.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { throw CaptureLibraryFailure.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureLibraryFailure.invalidImage }
        return result as Data
    }
    private func cleanUnreferencedImages(in catalog: Catalog) {
        let names = Set(catalog.items.map(\.assetName))
        for file in (try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)) ?? [] {
            guard file.pathExtension == "png", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                  !names.contains(file.lastPathComponent) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
