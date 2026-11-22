import AppKit
import Combine
import os
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary

enum CaptureLibraryViewTestsSupport {
    @MainActor final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: -1000, y: -1000)
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    final class Delivery: Scheduler {
        typealias SchedulerTimeType = ImmediateScheduler.SchedulerTimeType
        typealias SchedulerOptions = Never
        var now: SchedulerTimeType { ImmediateScheduler.shared.now }
        var minimumTolerance: SchedulerTimeType.Stride { .zero }
        var pending: [() -> Void] = []

        func schedule(options: Never?, _ action: @escaping () -> Void) { pending.append(action) }
        func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: Never?,
                      _ action: @escaping () -> Void) { preconditionFailure("Unexpected delayed delivery") }
        func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                      options: Never?, _ action: @escaping () -> Void) -> Cancellable { preconditionFailure("Unexpected timer") }
    }

    final class Cloud: ExternalMediaCloudObservation, Sendable {
        let remote = OSAllocatedUnfairLock(initialState: Set<String>())
        let report = OSAllocatedUnfairLock(initialState: Optional<@Sendable (Set<String>) -> Void>.none)
        func present(_ folders: Set<String>) {}

        var source: ExternalMediaCloud {
            ExternalMediaCloud(isSynced: { _ in true }, isLocal: { [remote] path, _ in remote.withLock { !$0.contains(path) } },
                observe: { [self] callback in report.withLock { $0 = callback }; return self })
        }

        func evict(_ path: String) {
            _ = remote.withLock { $0.insert(path) }
            report.withLock { $0 }?([path])
        }
    }

    @MainActor final class Jobs {
        let delivery = Delivery()
        var tasks: [Task<Void, Never>] = []
        var event: (@Sendable (ExternalMediaWatcher.Batch) -> Void)?

        func start(_ work: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
            let task = Task(operation: work)
            tasks.append(task)
            return task
        }

        func finish() async {
            while !delivery.pending.isEmpty || !tasks.isEmpty {
                let queued = delivery.pending
                delivery.pending.removeAll()
                for action in queued { action() }
                let started = tasks
                tasks.removeAll()
                for task in started { await task.value }
            }
        }
    }

    @MainActor final class Fixture {
        private let jobs = Jobs()
        private var batchCompletions: [() -> Void] = []
        private let cloud = Cloud()
        var folder: URL { root.appendingPathComponent("Pictures", isDirectory: true) }
        var preferences: URL { root.appendingPathComponent("Preferences", isDirectory: true) }
        func file(_ index: Int) -> URL { folder.appendingPathComponent(String(format: "fixture-%02d.png", index)) }
        func changes(_ files: URL...) async throws {
            let event = try #require(jobs.event)
            event(.paths(Set(files.map { $0.standardizedFileURL.path })))
            await finish()
        }
        func evict(_ url: URL) async { cloud.evict(url.path); await finish() }
        func finish() async {
            await jobs.finish()
            view.layoutSubtreeIfNeeded()
            let completions = batchCompletions
            batchCompletions.removeAll()
            completions.forEach { $0() }
            await jobs.finish()
        }
        var count: Int { grid.numberOfItems(inSection: 0) }
        func select(_ index: Int) { grid.selectionIndexPaths = [IndexPath(item: index, section: 0)] }
        func title(_ index: Int) -> String? { tile(index)?.subviews.compactMap { $0 as? NSButton }.first?.toolTip }

        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let catalog: CaptureLibraryStore
        let media: ExternalMediaLibrary
        let client = UUID()
        let window: KeyedWindow
        let view: CaptureLibraryView
        let grid: CaptureCollectionView

        static func png(_ width: Int = 2, _ height: Int = 2) -> Data {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let output = NSMutableData()
            let encoder = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(encoder, context.makeImage()!, nil)
            CGImageDestinationFinalize(encoder)
            return output as Data
        }

        init(files: Int = 0, captures: Int = 0, missingFolder: Bool = false, regularHeader: Bool = true, corrupt: Bool = false,
             width: CGFloat = 304, height: CGFloat = 600, persistentFolders: Bool = false, synced: Bool = false) async throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: root.appendingPathComponent("profile", isDirectory: true))
            profile = store.activeSpace.profileID
            let captureDirectory = store.capturesDirectory(for: profile)
            if corrupt {
                try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
                try Data("not a catalog".utf8).write(to: captureDirectory.appendingPathComponent("Captures.json"))
            }
            catalog = CaptureLibraryStore.shared(directory: captureDirectory, profileID: profile)
            await catalog.reload()
            for index in 0..<captures {
                _ = try await catalog.save(CaptureLibraryInput(id: UUID(), expectedRevision: nil,
                    capturedAt: Date(timeIntervalSince1970: 1_920_000_000 + Double(index)), profileID: profile,
                    spaceID: store.activeSpaceID, spaceName: "Captures", title: "Capture \(index)",
                    sourceURL: "https://captures.example.invalid", kind: .region, pngData: Self.png()))
            }
            let folder = root.appendingPathComponent("Pictures", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<files {
                let file = folder.appendingPathComponent(String(format: "fixture-%02d.png", index))
                try Self.png(index.isMultiple(of: 2) ? 20 : 10, index.isMultiple(of: 2) ? 10 : 20).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 60)],
                                                      ofItemAtPath: file.path)
            }
            let folders = missingFolder ? [folder, root.appendingPathComponent("Missing", isDirectory: true)] : [folder]
            media = ExternalMediaLibrary(directory: root.appendingPathComponent("Preferences", isDirectory: true),
                preferencesAreEphemeral: !persistentFolders, systemFolders: { folders }, cloud: synced ? cloud.source : .system, screenshotPreferences: nil,
                startTask: jobs.start, deliverEvent: { action in MainActor.assumeIsolated { action() } },
                makeWatcher: { [jobs] _, _, event in jobs.event = event; return NSObject() })
            await media.activate(client)?.value
            view = CaptureLibraryView(store: catalog, profileOwner: store, media: media, regularHeader: regularHeader,
                delivery: jobs.delivery, startTask: jobs.start, fileThumbnail: { try Data(contentsOf: $0.url) }, ownerValid: { true })
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            window = KeyedWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            grid = try #require(Self.descendants(view).compactMap { $0 as? CaptureCollectionView }.first)
            view.updateGrid = { [weak self] grid, updates, finished in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    grid.performBatchUpdates(updates, completionHandler: nil)
                }
                self?.batchCompletions.append { finished(true) }
            }
            await finish()
        }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            media.deactivate(client)
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: root)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func rightClick(_ target: NSView) -> NSEvent {
            NSEvent.mouseEvent(with: .rightMouseDown, location: target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }

        func isFolderMenu(_ titles: [String]?) -> Bool {
            titles?.contains("Add Media Folder…") == true && titles?.contains("Refresh") == true
        }

        func press(_ code: UInt16, _ flags: NSEvent.ModifierFlags, on target: NSCollectionView? = nil) {
            (target ?? grid).keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!)
        }

        var message: NSTextField? {
            Self.descendants(view).compactMap { $0 as? NSTextField }.first { !$0.isHidden && $0.stringValue.hasPrefix("Saved captures") }
        }

        var status: String? {
            Self.descendants(view).compactMap { $0 as? NSTextField }.first { !$0.isHidden && $0.font?.pointSize == 10.5 }?.stringValue
        }

        var search: NSTextField {
            Self.descendants(view).compactMap { $0 as? NSTextField }.first {
                $0.placeholderString == "Search Media…" || $0.accessibilityLabel() == "Search Media"
            }!
        }

        func query(_ text: String) {
            search.stringValue = text
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        }

        func tile(_ index: Int) -> CaptureLibraryTile? { grid.item(at: IndexPath(item: index, section: 0))?.view as? CaptureLibraryTile }
    }

    @MainActor static func litFrameMatches(_ tile: CaptureLibraryTile, lit: Bool) -> Bool {
        let plate = tile.layer!.sublayers![0].frame
        let expected = tile.bounds.insetBy(dx: lit ? 0 : 4, dy: lit ? 0 : 4)
        return abs(plate.width - expected.width) < 0.01 && abs(plate.minX - expected.minX) < 0.01
    }
}

typealias CaptureLibraryViewTests = CaptureLibraryViewTestsSupport
