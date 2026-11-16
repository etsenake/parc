import AppKit
import Combine
import Foundation
import Darwin
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct ExternalMediaLibraryTests {
    @MainActor static func main() async { await exitOnFailure(runChecks) }
    @MainActor static func runChecks() async throws {
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
        let latest = MediaLibraryLatestWork<Int>(), finished = FinishedWork()
        func request(_ work: @escaping @Sendable () throws -> Int) -> MediaLibraryLatestWork<Int>.Request {
            { finished.requests += 1; return (work: work, finish: { finished.values.append($0) }) }
        }
        func spin(_ probe: WorkProbe, _ value: Int) -> @Sendable () throws -> Int {
            {
                probe.begin()
                for _ in 0..<5_000 {
                    if Task.isCancelled { probe.cancel(); throw CancellationError() }
                    if probe.released { return value }
                    usleep(1_000)
                }
                return value
            }
        }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<2_000 where !condition() { try await Task.sleep(nanoseconds: 1_000_000) }
        }
        let stale = WorkProbe()
        latest.start(request(spin(stale, 1)))
        try await waitFor { stale.started }
        precondition(stale.started && latest.isRunning)
        latest.start(request { 2 })
        try await waitFor { !latest.isRunning && stale.cancelled }
        precondition(finished.values == [2] && stale.cancelled && !latest.isRunning, "A newer grid calculation cancels the one it replaces")
        let abandoned = WorkProbe()
        latest.start(request(spin(abandoned, 3)))
        try await waitFor { abandoned.started }
        latest.cancel()
        try await waitFor { abandoned.cancelled }
        try await Task.sleep(nanoseconds: 20_000_000)
        precondition(abandoned.cancelled && !latest.isRunning && finished.values == [2], "A forced rebuild cancels the calculation in flight")
        let firstRun = WorkProbe(), secondRun = WorkProbe(), thirdRun = WorkProbe()
        for (probe, value) in [(firstRun, 4), (secondRun, 5), (thirdRun, 6)] {
            latest.start(request(spin(probe, value)))
            try await waitFor { probe.started }
        }
        let requestsBeforeQueue = finished.requests
        latest.start(request { 7 }); latest.start(request { 8 })
        try await waitFor { firstRun.cancelled && secondRun.cancelled }
        precondition(firstRun.cancelled && secondRun.cancelled && !thirdRun.cancelled && latest.isRunning && finished.requests == requestsBeforeQueue,
                     "A steady stream of updates lets one grid calculation finish and waits to read the newest catalog")
        thirdRun.release()
        try await waitFor { !latest.isRunning && finished.values.count == 3 }
        precondition(finished.values == [2, 6, 8] && finished.requests == requestsBeforeQueue + 1 && !latest.isRunning,
                     "Only the newest waiting update is planned, from the catalog current when it starts")
        let longRun = WorkProbe()
        latest.start(request(spin(longRun, 9)))
        try await waitFor { longRun.started }
        latest.start(request { 10 })
        try await waitFor { !latest.isRunning && longRun.cancelled }
        precondition(longRun.cancelled && finished.values == [2, 6, 8, 10], "Once a calculation finishes, newer updates cancel stale ones again")
        let stubborn = WorkProbe()
        latest.start(request {
            stubborn.begin()
            for _ in 0..<5_000 where !stubborn.released { usleep(1_000) }
            return 11
        })
        try await waitFor { stubborn.started }
        latest.start(request { 12 })
        try await waitFor { !latest.isRunning && finished.values.last == 12 }
        stubborn.release()
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(finished.values == [2, 6, 8, 10, 12] && !latest.isRunning, "A stale calculation that finishes late anyway is thrown away")
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
        let touched = try await disk.update(paths: [addition.path]).catalog
        precondition(revision(touched, addition)?.size == Int64(png.count * 2) && revision(touched, other) == quietOther,
                     "A targeted update rereads only the file that changed")
        precondition(touched!.version > grown.catalog.version && touched!.index[addition.path]?.revision.size == Int64(png.count * 2))
        let unchanged = try await disk.update(paths: [addition.path, nested.appendingPathComponent("NotScanned.png").path, root.appendingPathComponent("Outside.png").path])
        precondition(unchanged.catalog == nil && unchanged.settle == nil, "An unchanged file, a nested file and a file outside every folder publish nothing")
        let renamedAddition = folder.appendingPathComponent("Renamed.png"); try fm.moveItem(at: addition, to: renamedAddition)
        let renamed = try await disk.update(paths: [addition.path, renamedAddition.path]).catalog
        precondition(revision(renamed, addition) == nil && revision(renamed, renamedAddition)?.size == Int64(png.count * 2), "A rename moves the file in one update")
        let recased = folder.appendingPathComponent("RENAMED.png")
        precondition(Darwin.rename(renamedAddition.path, recased.path) == 0)
        let caseOnly = try await disk.update(paths: [renamedAddition.path, recased.path]).catalog
        precondition(revision(caseOnly, renamedAddition) == nil && revision(caseOnly, recased) != nil && caseOnly?.items.count == renamed?.items.count,
                     "A case-only rename leaves one tile under the new name")
        try fm.removeItem(at: recased)
        let removed = try await disk.update(paths: [recased.path]).catalog
        precondition(removed?.items.count == snapshot.catalog.items.count && removed?.index[recased.path] == nil, "A removal drops the file")
        precondition(zip(removed!.items, removed!.items.dropFirst()).allSatisfy { ExternalMediaDisk.precedes($0, $1) })
        let copying = folder.appendingPathComponent("Copying.png"); try png.write(to: copying)
        let arrived = try await disk.update(paths: [copying.path])
        precondition(arrived.catalog?.index[copying.path] != nil && arrived.settle == nil, "A file that arrives whole appears at once")
        try grow(copying)
        let growing = try await disk.update(paths: [copying.path])
        precondition(growing.catalog == nil && growing.settle != nil, "A file still being written waits to settle")
        try grow(copying)
        let stillGrowing = try await disk.update(paths: [copying.path])
        let early = try await disk.settle()
        precondition(stillGrowing.catalog == nil && early.catalog == nil && early.settle != nil, "A file written moments ago has not settled")
        try await Task.sleep(for: early.settle! + .milliseconds(50))
        let landed = try await disk.settle()
        precondition(landed.catalog?.index[copying.path]?.revision.size == Int64(png.count * 3) && landed.settle == nil
                     && landed.catalog?.version == arrived.catalog.map { $0.version + 1 }, "A grown file lands in one update once it goes quiet")
        try await Task.sleep(for: ExternalMediaDisk.settleDelay)
        try grow(copying)
        let later = try await disk.update(paths: [copying.path])
        precondition(later.catalog?.index[copying.path]?.revision.size == Int64(png.count * 4) && later.settle == nil, "A change after a quiet spell shows at once")
        try fm.removeItem(at: copying)
        let copyGone = try await disk.update(paths: [copying.path])
        precondition(copyGone.catalog?.index[copying.path] == nil && copyGone.catalog?.items.count == snapshot.catalog.items.count, "A removal never waits to settle")
        let flipCloud = CloudProbe(syncedName: folder.lastPathComponent)
        let flipDisk = ExternalMediaDisk(directory: root.appendingPathComponent("FlipProfile"), cloud: flipCloud.source)
        let flipScan = try await flipDisk.scan(systemFolders: [folder, missing])
        precondition(!flipScan.catalog.items.isEmpty && flipScan.catalog.cloudFolders == [folder.path], "An iCloud folder is watched as one folder, not file by file")
        let flipped = flipScan.catalog.items[0]
        let quiet = try await flipDisk.update(paths: [flipped.id])
        flipCloud.evict(flipped.id)
        let evicted = try await flipDisk.update(paths: [flipped.id])
        flipCloud.restore(flipped.id)
        let downloaded = try await flipDisk.update(paths: [flipped.id])
        precondition(quiet.catalog == nil && evicted.catalog?.index[flipped.id]?.isLocal == false && evicted.settle == nil
                     && downloaded.catalog?.index[flipped.id]?.isLocal == true && downloaded.settle == nil,
                     "An eviction or download shows at once even right after another event for that file")
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
        var copyChanges = 0
        let copyObserver = live.$items.dropFirst().sink { _ in copyChanges += 1 }
        let slow = folder.appendingPathComponent("Slow.png"); try png.write(to: slow)
        try await eventually({ live.items.contains { $0.url == slow } }, "A new file appears without waiting to settle")
        for _ in 0..<5 { try grow(slow); try await Task.sleep(nanoseconds: 200_000_000) }
        try await eventually({ live.items.first { $0.url == slow }?.revision.size == Int64(png.count * 6) }, "A slowly copied file settles at its final size")
        try await Task.sleep(nanoseconds: 300_000_000)
        copyObserver.cancel()
        precondition(copyChanges <= 2, "A slowly copied file took \(copyChanges) updates to settle")
        try fm.removeItem(at: slow)
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
        let cloudFolder = root.appendingPathComponent("Cloud", isDirectory: true), plainFolder = root.appendingPathComponent("Plain", isDirectory: true)
        try fm.createDirectory(at: cloudFolder, withIntermediateDirectories: true); try fm.createDirectory(at: plainFolder, withIntermediateDirectories: true)
        let cloudA = cloudFolder.appendingPathComponent("A.png"), cloudB = cloudFolder.appendingPathComponent("B.png"), plainC = plainFolder.appendingPathComponent("C.png")
        for file in [cloudA, cloudB, plainC] { try png.write(to: file) }
        let cloud = CloudProbe(syncedName: "Cloud")
        let plainOnly = ExternalMediaLibrary(directory: root.appendingPathComponent("PlainObserved"), systemFolders: { [plainFolder] },
                                             cloud: cloud.source, screenshotPreferences: nil)
        let plainClient = UUID(); plainOnly.activate(plainClient)
        try await until { plainOnly.items.count == 1 && !plainOnly.isLoading }
        plainOnly.deactivate(plainClient)
        precondition(cloud.observations == 0, "Media without an iCloud folder never watches download status")
        let synced = ExternalMediaLibrary(directory: root.appendingPathComponent("CloudObserved"), systemFolders: { [cloudFolder, plainFolder] },
                                          cloud: cloud.source, screenshotPreferences: nil)
        precondition(cloud.observations == 0, "Download status is not watched before Media is shown")
        let cloudClient = UUID(); synced.activate(cloudClient)
        try await until { synced.items.count == 3 && !synced.isLoading }
        precondition(cloud.observations == 1 && cloud.presented == [cloudFolder.path] && cloud.peak == 1, "Shown Media watches download status with one presenter for its iCloud folder")
        var cloudChanges = 0
        let cloudObserver = synced.$items.dropFirst().sink { _ in cloudChanges += 1 }
        let beforeEviction = synced.items.filter { $0.url != cloudA }
        cloud.evict(cloudA.path); cloud.report([cloudA.path])
        try await eventually({ synced.items.first { $0.url == cloudA }?.isLocal == false }, "An eviction reported by iCloud reaches its tile")
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(cloudChanges == 1 && synced.items.filter { $0.url != cloudA } == beforeEviction, "An eviction rereads only that file and publishes once")
        precondition(synced.items.first { $0.url == cloudA }?.detail == "Download in Finder to preview")
        cloud.restore(cloudA.path); cloud.report([cloudA.path])
        try await eventually({ synced.items.first { $0.url == cloudA }?.isLocal == true }, "A finished download reaches its tile without waiting to settle")
        precondition(cloudChanges == 2, "A finished download publishes once")
        cloud.report([cloudFolder.appendingPathComponent("Ghost.png").path])
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(cloudChanges == 2, "A status report for a file Media doesn't show changes nothing")
        cloudObserver.cancel()
        let cloudD = cloudFolder.appendingPathComponent("D.png"); try png.write(to: cloudD)
        try fm.removeItem(at: cloudB)
        try await eventually({ synced.items.contains { $0.url == cloudD } && !synced.items.contains { $0.url == cloudB } }, "Arrivals and removals in an iCloud folder reach Media")
        precondition(cloud.presented == [cloudFolder.path] && cloud.peak == 1, "Arrivals and removals never add presenters")
        cloud.evict(cloudD.path); cloud.report([cloudD.path])
        try await eventually({ synced.items.first { $0.url == cloudD }?.isLocal == false }, "A file that arrived after Media opened is covered by its folder's presenter")
        let presentsBeforeRescan = cloud.presentations, revisionBeforeRescan = synced.revision
        synced.refresh()
        try await until { !synced.isLoading }
        precondition(synced.revision == revisionBeforeRescan && cloud.presentations > presentsBeforeRescan && cloud.presented == [cloudFolder.path] && cloud.peak == 1,
                     "A rescan that finds nothing new still puts back a folder presenter that stepped aside")
        weak var watching = cloud.current
        let lateReport = cloud.handler
        synced.deactivate(cloudClient)
        precondition(watching == nil && synced.items.isEmpty, "Leaving Media stops watching download status")
        lateReport?([cloudA.path])
        try await Task.sleep(nanoseconds: 300_000_000)
        precondition(synced.items.isEmpty, "A status report after Media closes is ignored")
        synced.activate(cloudClient)
        try await until { synced.items.count == 3 && !synced.isLoading }
        precondition(cloud.observations == 2 && cloud.presented == [cloudFolder.path])
        watching = cloud.current
        try await synced.setEnabled(false, folder: cloudFolder)
        precondition(watching == nil && synced.items.count == 1, "Hiding the only iCloud folder stops watching download status")
        synced.deactivate(cloudClient)
        let bigFolder = root.appendingPathComponent("Big", isDirectory: true)
        try fm.createDirectory(at: bigFolder, withIntermediateDirectories: true)
        let bigNames = (0..<3_000).map { String(format: "Big-%04d.png", $0) }
        for name in bigNames { try png.write(to: bigFolder.appendingPathComponent(name)) }
        let bigCloud = CloudProbe(syncedName: "Big")
        let big = ExternalMediaLibrary(directory: root.appendingPathComponent("BigObserved"), systemFolders: { [bigFolder] },
                                       cloud: bigCloud.source, screenshotPreferences: nil)
        let bigClient = UUID(); big.activate(bigClient)
        try await until { big.items.count == bigNames.count && !big.isLoading }
        precondition(bigCloud.observations == 1 && bigCloud.presented == [bigFolder.path] && bigCloud.peak == 1,
                     "A synced folder with thousands of files still registers a single presenter")
        let bigTarget = bigFolder.appendingPathComponent(bigNames[1_234]).path, bigOthers = big.items.filter { $0.id != bigTarget }
        var bigChanges = 0
        let bigObserver = big.$items.dropFirst().sink { _ in bigChanges += 1 }
        bigCloud.evict(bigTarget); bigCloud.report([bigTarget])
        try await eventually({ big.items.first { $0.id == bigTarget }?.isLocal == false }, "An eviction deep in a large folder reaches its tile")
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(bigChanges == 1 && big.items.filter { $0.id != bigTarget } == bigOthers, "An eviction in a large folder rereads only that file")
        bigObserver.cancel()
        weak let bigWatching = bigCloud.current
        big.deactivate(bigClient)
        precondition(bigWatching == nil && big.items.isEmpty, "Closing Media releases the folder presenter")
        let presentersBefore = NSFileCoordinator.filePresenters.count
        let spelled = realpath(bigFolder.path, nil).map { real in defer { free(real) }; return String(cString: real) } ?? bigFolder.path
        let spellings: Set<String> = [bigFolder.path, spelled]
        let realReports = CloudReports()
        var realStatus: ExternalMediaCloudStatus? = ExternalMediaCloudStatus { realReports.add($0) }
        realStatus?.present(spellings)
        try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore + spellings.count },
                             "The real iCloud source registers one presenter per folder for a folder of thousands of files")
        let nestedFolder = bigFolder.appendingPathComponent("Nested", isDirectory: true)
        try fm.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        let coordinated = [bigFolder.appendingPathComponent(bigNames[42]), nestedFolder.appendingPathComponent("Deep.png"),
                           bigFolder.appendingPathComponent("Notes.txt"), bigFolder.appendingPathComponent(bigNames[43])]
        for target in coordinated {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    var failure: NSError?
                    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: target, options: [], error: &failure) { try? png.write(to: $0) }
                    done.resume()
                }
            }
        }
        let expectedReports = Set(spellings.flatMap { folder in [bigNames[42], bigNames[43]].map { (folder as NSString).appendingPathComponent($0) } })
        try await eventually({ realReports.all.isSuperset(of: expectedReports) }, "A change to a direct media child is reported under each spelling its folder was registered with")
        precondition(realReports.all == expectedReports && NSFileCoordinator.filePresenters.count == presentersBefore + spellings.count,
                     "Nested files, subfolders and non-media files are not reported, and the files written add no presenters")
        if #available(macOS 14.4, *) {
            let folderPresenter = NSFileCoordinator.filePresenters.first { $0.presentedItemURL?.path == spelled }
            let evictionAllowed = CloudReports()
            folderPresenter?.accommodatePresentedItemEviction?(completionHandler: { evictionAllowed.add($0 == nil ? ["allowed"] : ["refused"]) })
            precondition(evictionAllowed.all == ["allowed"], "Evicting the presented folder is allowed instead of blocked")
            try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore + spellings.count - 1 }, "Evicting the presented folder steps its presenter aside")
            realStatus?.present(spellings)
            try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore + spellings.count }, "The next present puts an evicted folder's presenter back")
        }
        realStatus?.present([])
        try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore }, "A folder no longer shown releases its presenter")
        realStatus?.present(spellings)
        try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore + spellings.count }, "A folder shown again registers again")
        realStatus = nil
        try await eventually({ NSFileCoordinator.filePresenters.count == presentersBefore }, "Dropping the iCloud source when Media closes releases every presenter")
        let shotsSuite = "parc.media-screenshot-tests." + UUID().uuidString
        let shotsDefaults = UserDefaults(suiteName: shotsSuite)!
        defer { shotsDefaults.removePersistentDomain(forName: shotsSuite) }
        let shotsHome = root.appendingPathComponent("Home", isDirectory: true), shotsFolder = root.appendingPathComponent("Screenshots", isDirectory: true)
        try fm.createDirectory(at: shotsHome, withIntermediateDirectories: true); try fm.createDirectory(at: shotsFolder, withIntermediateDirectories: true)
        try png.write(to: shotsHome.appendingPathComponent("Home.png")); try png.write(to: shotsFolder.appendingPathComponent("Shot.png"))
        let located = ExternalMediaLibrary(directory: root.appendingPathComponent("LocatedObserved"), preferencesAreEphemeral: true,
            systemFolders: { [shotsHome] + (shotsDefaults.string(forKey: "location").map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? []) },
            screenshotPreferences: shotsDefaults)
        let locatedClient = UUID(); located.activate(locatedClient)
        try await until { located.items.count == 1 && !located.isLoading }
        shotsDefaults.set(shotsFolder.path, forKey: "location")
        try await eventually({ located.items.count == 2 }, "A new screenshot location is picked up without waiting for the minute check")
        located.deactivate(locatedClient)
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
        print("External media discovery, change publication, settling, iCloud status, screenshot location, cancellation, original-byte export, revision, hiding, source access and corruption checks passed")
    }
}

@MainActor private final class FinishedWork { var values: [Int] = []; var requests = 0 }

private final class CloudReports: @unchecked Sendable {
    private let lock = NSLock()
    private var reported = Set<String>()
    var all: Set<String> { lock.lock(); defer { lock.unlock() }; return reported }
    func add(_ paths: Set<String>) { lock.lock(); reported.formUnion(paths); lock.unlock() }
}

private final class WorkProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false, didCancel = false
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return didCancel }
    private var didRelease = false
    var released: Bool { lock.lock(); defer { lock.unlock() }; return didRelease }
    func begin() { lock.lock(); didStart = true; lock.unlock() }
    func cancel() { lock.lock(); didCancel = true; lock.unlock() }
    func release() { lock.lock(); didRelease = true; lock.unlock() }
}

private final class CloudProbe: @unchecked Sendable {
    private final class Observation: ExternalMediaCloudObservation, @unchecked Sendable {
        private let probe: CloudProbe
        init(_ probe: CloudProbe) { self.probe = probe }
        func present(_ folders: Set<String>) { probe.record(folders) }
    }
    private let lock = NSLock()
    private let syncedName: String
    private var evicted = Set<String>(), watched = Set<String>(), count = 0, largest = 0, calls = 0
    private var reporter: (@Sendable (Set<String>) -> Void)?
    private weak var live: Observation?
    init(syncedName: String) { self.syncedName = syncedName }
    var source: ExternalMediaCloud {
        ExternalMediaCloud(isSynced: { [self] in $0.lastPathComponent == syncedName },
                           isLocal: { [self] path, flags in flags & UInt32(SF_DATALESS) == 0 && !locked { evicted.contains(path) } },
                           observe: { [self] handler in
                               let observation = Observation(self)
                               locked { count += 1; reporter = handler; live = observation }
                               return observation
                           })
    }
    var observations: Int { locked { count } }
    var presented: Set<String> { locked { watched } }
    var peak: Int { locked { largest } }
    var presentations: Int { locked { calls } }
    var current: AnyObject? { locked { live } }
    var handler: (@Sendable (Set<String>) -> Void)? { locked { reporter } }
    func evict(_ path: String) { locked { _ = evicted.insert(path) } }
    func restore(_ path: String) { locked { _ = evicted.remove(path) } }
    func report(_ paths: Set<String>) { handler?(paths) }
    fileprivate func record(_ folders: Set<String>) { locked { watched = folders; largest = max(largest, folders.count); calls += 1 } }
    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
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
