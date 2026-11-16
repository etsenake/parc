import AppKit
import Combine
import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct ExternalMediaLibraryTests {
    @MainActor static func main() async throws {
        let order = ["file:A", "capture:B", "file:C", "capture:D"]
        for index in order.indices {
            let navigation = MediaLibraryNavigation(orderedIDs: order, selectedID: order[index])
            precondition(navigation.ordinal == index + 1)
            precondition(navigation.neighbor(-1) == (index > 0 ? order[index - 1] : nil))
            precondition(navigation.neighbor(1) == (index + 1 < order.count ? order[index + 1] : nil))
        }
        let arrivalOrder = MediaLibraryNavigation(orderedIDs: order + ["file:E"], selectedID: "capture:D")
        precondition(arrivalOrder.neighbor(1) == "file:E")
        let filtered = MediaLibraryNavigation(orderedIDs: ["file:C"], selectedID: "capture:D")
        precondition(filtered.index == nil && filtered.neighbor(-1) == nil)
        let ticket = MediaLibraryActionTicket(generation: 3)
        precondition(ticket.canCommit(generation: 3, ownerValid: true, itemCurrent: true))
        precondition(!ticket.canCommit(generation: 4, ownerValid: true, itemCurrent: true))
        precondition(!ticket.canCommit(generation: 3, ownerValid: false, itemCurrent: true))
        precondition(!ticket.canCommit(generation: 3, ownerValid: true, itemCurrent: false))
        let probe = ThumbnailProbe()
        let operation = MediaLibraryThumbnailOperation(start: { probe.start($0) }, stop: { probe.stop() })
        let pending = Task { try await operation.value() }
        for _ in 0..<100 { if probe.started { break }; try await Task.sleep(nanoseconds: 1_000_000) }
        precondition(probe.started)
        pending.cancel()
        do { _ = try await pending.value; fatalError("Canceled thumbnail completed") } catch is CancellationError {}
        precondition(probe.stopped)
        probe.complete(.success(Data([1, 2, 3])))
        let immediate = MediaLibraryThumbnailOperation(start: { $0(.success(Data([4, 5]))) }, stop: {})
        let immediateBytes = try await immediate.value(); precondition(immediateBytes == Data([4, 5]))
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ParcMedia-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Files", isDirectory: true)
        let config = root.appendingPathComponent("Profile", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let pixels = Data([255, 0, 0, 255])
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
        let png = bytes as Data
        func grow(_ url: URL) throws { let handle = try FileHandle(forWritingTo: url); _ = try handle.seekToEnd(); try handle.write(contentsOf: png); try handle.close() }
        let shot = folder.appendingPathComponent("Shot.png"), other = folder.appendingPathComponent("Other.png")
        try png.write(to: shot); try png.write(to: other)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: shot.path)
        let xattr = Data("yes".utf8)
        precondition(xattr.withUnsafeBytes { setxattr(shot.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0) } == 0)
        let movie = folder.appendingPathComponent("Recording.mov")
        try Data("disposable metadata fixture; not a playable movie".utf8).write(to: movie)
        let nested = folder.appendingPathComponent("Nested", isDirectory: true)
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try png.write(to: nested.appendingPathComponent("NotScanned.png"))
        try png.write(to: folder.appendingPathComponent(".Hidden.png"))
        try fm.createSymbolicLink(at: folder.appendingPathComponent("Link.png"), withDestinationURL: shot)
        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let disk = ExternalMediaDisk(directory: config)
        var snapshot = try await disk.scan(systemFolders: [folder, folder, missing])
        precondition(snapshot.catalog.items.count == 3 && snapshot.folders.count == 2)
        let capture = snapshot.catalog.items.first { $0.url == shot }!
        precondition(capture.isScreenshot && capture.kind == .image && capture.date == Date(timeIntervalSince1970: 100))
        precondition(snapshot.catalog.items.last == capture)
        precondition(snapshot.folders.contains { if case .unavailable = $0.access { return true }; return false })
        let recording = snapshot.catalog.items.first { $0.url == movie }!
        precondition(recording.kind == .movie && recording.isScreenRecording)
        precondition(xattr.withUnsafeBytes { setxattr(movie.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, $0.count, 0, 0) } == 0)
        snapshot = try await disk.scan(systemFolders: [folder])
        precondition(snapshot.catalog.items.first { $0.url == movie }?.isScreenRecording == false)
        let repeated = try await disk.scan(systemFolders: [folder])
        precondition(repeated.catalog.version == snapshot.catalog.version && repeated.catalog.items == snapshot.catalog.items, "An unchanged rescan reports no change")
        let addition = folder.appendingPathComponent("Addition.png"); try png.write(to: addition)
        let grown = try await disk.scan(systemFolders: [folder])
        precondition(grown.catalog.version > snapshot.catalog.version && grown.catalog.items.count == snapshot.catalog.items.count + 1, "A new file is reported as a change")
        precondition(zip(grown.catalog.items, grown.catalog.items.dropFirst()).allSatisfy { $0.date > $1.date || ($0.date == $1.date && $0.id < $1.id) })
        func revision(_ catalog: ExternalMediaDisk.Catalog?, _ url: URL) -> ExternalMediaFile.Revision? { catalog?.items.first { $0.url == url }?.revision }
        let quietOther = revision(grown.catalog, other)!
        try grow(addition); try grow(other)
        let touched = try await disk.update(paths: [addition.path])
        precondition(revision(touched, addition)?.size == Int64(png.count * 2) && revision(touched, other) == quietOther,
                     "A targeted update rereads only the file that changed")
        precondition(touched!.version > grown.catalog.version && touched!.index[addition.path]?.revision.size == Int64(png.count * 2))
        let unchanged = try await disk.update(paths: [addition.path, nested.appendingPathComponent("NotScanned.png").path, root.appendingPathComponent("Outside.png").path])
        precondition(unchanged == nil, "An unchanged file, a nested file and a file outside every folder publish nothing")
        let renamedAddition = folder.appendingPathComponent("Renamed.png"); try fm.moveItem(at: addition, to: renamedAddition)
        let renamed = try await disk.update(paths: [addition.path, renamedAddition.path])
        precondition(revision(renamed, addition) == nil && revision(renamed, renamedAddition)?.size == Int64(png.count * 2), "A rename moves the file in one update")
        let recased = folder.appendingPathComponent("RENAMED.png")
        precondition(Darwin.rename(renamedAddition.path, recased.path) == 0)
        let caseOnly = try await disk.update(paths: [renamedAddition.path, recased.path])
        precondition(revision(caseOnly, renamedAddition) == nil && revision(caseOnly, recased) != nil && caseOnly?.items.count == renamed?.items.count,
                     "A case-only rename leaves one tile under the new name")
        try fm.removeItem(at: recased)
        let removed = try await disk.update(paths: [recased.path])
        precondition(removed?.items.count == snapshot.catalog.items.count && removed?.index[recased.path] == nil, "A removal drops the file")
        precondition(zip(removed!.items, removed!.items.dropFirst()).allSatisfy { ExternalMediaDisk.precedes($0, $1) })
        try png.write(to: other, options: .atomic)
        let data = try await disk.data(capture); precondition(data == png)
        let export = root.appendingPathComponent("Export.png")
        try await disk.export(capture, to: export); let exported = try Data(contentsOf: export); precondition(exported == png)
        do { try await disk.export(capture, to: shot); fatalError("Original overwritten") } catch ExternalMediaFailure.sameFile {}
        let hardLink = root.appendingPathComponent("HardLink.png")
        try fm.linkItem(at: shot, to: hardLink)
        snapshot = try await disk.scan(systemFolders: [folder]); let linked = snapshot.catalog.items.first { $0.url == shot }!
        do { try await disk.export(linked, to: hardLink); fatalError("Alias overwritten") } catch ExternalMediaFailure.sameFile {}
        try await disk.hide(linked); snapshot = try await disk.scan(systemFolders: [folder])
        precondition(!snapshot.catalog.items.contains { $0.url == shot } && fm.fileExists(atPath: shot.path))
        let manifest = config.appendingPathComponent("MediaFolders.json")
        let parentBytes = try Data(contentsOf: manifest)
        let privateA = ExternalMediaDisk(directory: config, preferencesAreEphemeral: true)
        let privateB = ExternalMediaDisk(directory: config, preferencesAreEphemeral: true)
        var aSnapshot = try await privateA.scan(systemFolders: [folder])
        var bSnapshot = try await privateB.scan(systemFolders: [folder])
        precondition(!aSnapshot.catalog.items.contains { $0.url == shot } && aSnapshot.catalog.items == bSnapshot.catalog.items)
        try await privateA.restoreHidden()
        aSnapshot = try await privateA.scan(systemFolders: [folder])
        let privateShot = aSnapshot.catalog.items.first { $0.url == shot }!
        precondition(!bSnapshot.catalog.items.contains { $0.url == shot })
        try await privateA.hide(privateShot)
        try await privateA.setEnabled(false, folder: folder)
        aSnapshot = try await privateA.scan(systemFolders: [folder])
        precondition(aSnapshot.catalog.items.isEmpty && aSnapshot.folders.first?.access == .disabled)
        try await privateA.grant(folder)
        aSnapshot = try await privateA.scan(systemFolders: [folder])
        precondition(aSnapshot.folders.first?.access == .available && !aSnapshot.catalog.items.contains { $0.url == shot })
        bSnapshot = try await privateB.scan(systemFolders: [folder])
        precondition(bSnapshot.folders.first?.access == .available && !bSnapshot.catalog.items.contains { $0.url == shot })
        let afterPrivateChanges = try Data(contentsOf: manifest)
        precondition(afterPrivateChanges == parentBytes)
        let newPrivate = ExternalMediaDisk(directory: config, preferencesAreEphemeral: true)
        let newSnapshot = try await newPrivate.scan(systemFolders: [folder])
        precondition(newSnapshot.catalog.items == bSnapshot.catalog.items)
        let untouchedDirectory = root.appendingPathComponent("UnwrittenPrivate")
        let noParentManifest = ExternalMediaDisk(directory: untouchedDirectory, preferencesAreEphemeral: true)
        try await noParentManifest.setEnabled(false, folder: folder)
        precondition(!fm.fileExists(atPath: untouchedDirectory.path))
        let reopened = ExternalMediaDisk(directory: config)
        snapshot = try await reopened.scan(systemFolders: [folder]); precondition(!snapshot.catalog.items.contains { $0.url == shot })
        try await reopened.restoreHidden(); snapshot = try await reopened.scan(systemFolders: [folder]); precondition(snapshot.catalog.items.count == 3)
        let original = snapshot.catalog.items.first { $0.url == other }!
        try Data("replacement".utf8).write(to: other, options: .atomic)
        do { _ = try await reopened.data(original); fatalError("Stale bytes read") } catch ExternalMediaFailure.changed {}
        do { try await reopened.export(original, to: export); fatalError("Stale bytes exported") } catch ExternalMediaFailure.changed {}
        let preservedExport = try Data(contentsOf: export); precondition(preservedExport == png)
        try await reopened.setEnabled(false, folder: folder)
        snapshot = try await reopened.scan(systemFolders: [folder]); precondition(snapshot.catalog.items.isEmpty && snapshot.folders.first?.access == .disabled)
        do { try await reopened.validate(original); fatalError("Revoked source survived") } catch ExternalMediaFailure.changed {}
        try await reopened.setEnabled(true, folder: folder); snapshot = try await reopened.scan(systemFolders: [folder]); precondition(snapshot.catalog.items.count == 3)
        let fresh = snapshot.catalog.items.first { $0.url == shot }!
        try fm.removeItem(at: shot)
        do { try await reopened.validate(fresh); fatalError("Deleted file survived") } catch {}
        let granted = ExternalMediaDisk(directory: root.appendingPathComponent("Granted"))
        try await granted.grant(folder)
        let grantSnapshot = try await granted.scan(systemFolders: [])
        precondition(grantSnapshot.catalog.items.count == 2)
        let grantReopened = ExternalMediaDisk(directory: root.appendingPathComponent("Granted"))
        let reopenedGrant = try await grantReopened.scan(systemFolders: [])
        precondition(reopenedGrant.catalog.items == grantSnapshot.catalog.items)
        do { try await granted.grant(other); fatalError("File accepted as folder") } catch {}
        let live = ExternalMediaLibrary(directory: root.appendingPathComponent("Observed"), systemFolders: { [folder] })
        let a = UUID(), b = UUID(); live.activate(a); live.activate(b)
        func until(_ condition: () -> Bool) async throws {
            for _ in 0..<80 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            preconditionFailure("Disposable file observation did not settle")
        }
        try await until { live.items.count == 2 && !live.isLoading }
        var published = 0, itemChanges = 0, loadingChanges = 0
        let observers = [live.objectWillChange.sink { published += 1 },
                         live.$items.dropFirst().sink { _ in itemChanges += 1 },
                         live.$isLoading.dropFirst().sink { _ in loadingChanges += 1 }]
        precondition(live.revision > 0 && live.contains(live.items[0]))
        let note = root.appendingPathComponent("Notes.txt"); try Data("not media".utf8).write(to: note)
        let watchedNote = folder.appendingPathComponent("Notes.txt"); try fm.moveItem(at: note, to: watchedNote)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(nanoseconds: 800_000_000)
        precondition(published == 0, "A background refresh that found nothing new published to the main thread")
        live.refresh()
        precondition(live.isLoading)
        try await until { !live.isLoading }
        precondition(itemChanges == 0 && loadingChanges == 2, "An explicit refresh with nothing new republished the list")
        published = 0; loadingChanges = 0
        let staged = root.appendingPathComponent("Settled.png"); try png.write(to: staged)
        let settled = folder.appendingPathComponent("Settled.png"); try fm.moveItem(at: staged, to: settled)
        try await until { live.items.contains { $0.url == settled } }
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(published == 1 && itemChanges == 1 && loadingChanges == 0, "A background change published more than once")
        observers.forEach { $0.cancel() }
        func eventually(_ condition: () -> Bool, _ message: String) async throws {
            for _ in 0..<60 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            preconditionFailure(message)
        }
        let before = live.items.first { $0.url == settled }!
        try grow(settled)
        try await eventually({ live.items.first { $0.url == settled }.map { $0.revision.size == before.revision.size * 2 } == true },
                             "An in-place write is seen from its folder event without a rescan")
        precondition(xattr.withUnsafeBytes { setxattr(settled.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0) } == 0)
        try await eventually({ live.items.first { $0.url == settled }?.isScreenshot == true }, "A screenshot marker added later is seen from its folder event")
        let moved = folder.appendingPathComponent("Moved.png"); try fm.moveItem(at: settled, to: moved)
        try await eventually({ live.items.contains { $0.url == moved } && !live.items.contains { $0.url == settled } }, "A rename is seen from its folder events")
        try fm.removeItem(at: moved)
        try await eventually({ !live.items.contains { $0.url == moved } }, "A removal is seen from its folder event")
        try fm.removeItem(at: watchedNote)
        try await until { live.items.count == 2 }
        live.deactivate(a)
        let arrival = folder.appendingPathComponent("Arrival.png"); try png.write(to: arrival)
        try await until { live.items.contains { $0.url == arrival } }
        try fm.removeItem(at: arrival)
        try await until { !live.items.contains { $0.url == arrival } }
        live.deactivate(b); precondition(live.items.isEmpty && live.folders.isEmpty)
        try png.write(to: arrival)
        try await Task.sleep(nanoseconds: 400_000_000)
        precondition(live.items.isEmpty)
        let denied = root.appendingPathComponent("Denied", isDirectory: true)
        try fm.createDirectory(at: denied, withIntermediateDirectories: true)
        try png.write(to: denied.appendingPathComponent("Private.png"))
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        let deniedSource = ExternalMediaDisk(directory: root.appendingPathComponent("DeniedProfile"))
        let deniedSnapshot = try await deniedSource.scan(systemFolders: [denied])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        precondition(deniedSnapshot.catalog.items.isEmpty)
        precondition(deniedSnapshot.folders.contains { if case .unavailable = $0.access { return true }; return false })
        let corrupt = Data("broken".utf8); try corrupt.write(to: config.appendingPathComponent("MediaFolders.json"))
        let broken = ExternalMediaDisk(directory: config)
        do { _ = try await broken.scan(systemFolders: [folder]); fatalError("Invalid preferences accepted") } catch ExternalMediaFailure.invalidConfiguration {}
        do { try await broken.setEnabled(true, folder: folder); fatalError("Invalid preferences replaced") } catch ExternalMediaFailure.invalidConfiguration {}
        let preservedConfig = try Data(contentsOf: config.appendingPathComponent("MediaFolders.json")); precondition(preservedConfig == corrupt)
        print("External media discovery, change publication, original-byte export, revision, hiding, source access and corruption checks passed")
    }
}

private final class ThumbnailProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: MediaLibraryThumbnailOperation.Completion?
    private var didStart = false, didStop = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    var stopped: Bool { lock.lock(); defer { lock.unlock() }; return didStop }
    func start(_ callback: @escaping MediaLibraryThumbnailOperation.Completion) {
        lock.lock(); self.callback = callback; didStart = true; lock.unlock()
    }
    func stop() { lock.lock(); didStop = true; lock.unlock() }
    func complete(_ result: Result<Data, Error>) {
        lock.lock(); let callback = self.callback; self.callback = nil; lock.unlock(); callback?(result)
    }
}
