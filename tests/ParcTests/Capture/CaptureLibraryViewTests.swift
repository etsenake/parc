import AppKit
import Combine
import os
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore

struct CaptureLibraryViewTests {
    @MainActor final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: -1000, y: -1000)
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    private final class Delivery: Scheduler {
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

    private final class Cloud: ExternalMediaCloudObservation, Sendable {
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

    @MainActor private final class Jobs {
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

    @MainActor private func failFileAction(_ fixture: Fixture) async throws {
        fixture.select(0)
        try FileManager.default.removeItem(at: fixture.file(0))
        fixture.press(51, [])
        await fixture.finish()
    }

    @MainActor @Test func aFailedFileActionKeepsItsErrorAfterTheGridRefreshes() async throws {
        let fixture = try await Fixture(files: 2, missingFolder: true)
        defer { fixture.teardown() }
        let notice = try #require(fixture.status)
        try await failFileAction(fixture)
        let error = try #require(fixture.status)
        #expect(error != notice && !fixture.media.isLoading && fixture.count == 1)
    }

    @MainActor @Test func theNextSearchClearsTheFileActionErrorAndRestoresTheFolderNotice() async throws {
        let fixture = try await Fixture(files: 1, missingFolder: true)
        defer { fixture.teardown() }
        let notice = try #require(fixture.status)
        try await failFileAction(fixture)
        try #require(fixture.status != nil && fixture.status != notice)
        fixture.query("")
        #expect(fixture.status == notice)
    }

    @MainActor @Test func leavingMediaClearsAStaleFileActionError() async throws {
        let fixture = try await Fixture(files: 1)
        defer { fixture.teardown() }
        try await failFileAction(fixture)
        try #require(fixture.status != nil)
        fixture.window.contentView = nil
        #expect(fixture.status == nil)
    }

    @MainActor @Test func aFolderToggleThatCannotBeSavedKeepsItsFilesAndShowsTheError() async throws {
        let fixture = try await Fixture(files: 1, persistentFolders: true)
        defer { fixture.teardown() }
        try FileManager.default.createDirectory(at: fixture.preferences.appendingPathComponent("MediaFolders.json"),
                                                withIntermediateDirectories: true)
        let menu = try #require(fixture.view.keyboardMenu(foldersOnly: true)?.menu)
        let item = try #require(menu.items.first?.submenu?.item(withTitle: "Stop Showing This Folder"))
        try #require(item.target as? MenuAction).invoke()
        await fixture.finish()
        #expect(fixture.status != nil && !fixture.media.isLoading && fixture.title(0) == "fixture-00.png")
    }

    @MainActor @Test func anUnchangedRefreshShowsLoadingWithoutApplyingPendingSearchText() async throws {
        let fixture = try await Fixture(files: 1, captures: 1)
        defer { fixture.teardown() }
        fixture.search.stringValue = "unapplied"
        fixture.media.refresh()
        #expect(fixture.media.isLoading)
        await fixture.finish()
        #expect(!fixture.media.isLoading && fixture.count == 2)
    }

    @MainActor @Test func regainingFolderAccessClearsTheNoticeWithoutRebuildingTheGrid() async throws {
        let fixture = try await Fixture(files: 1, missingFolder: true)
        defer { fixture.teardown() }
        try #require(fixture.status != nil)
        fixture.search.stringValue = "unapplied"
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Missing"), withIntermediateDirectories: true)
        fixture.media.refresh()
        await fixture.finish()
        #expect(fixture.status == nil && fixture.count == 1)
    }

    @MainActor @Test func anArrivalAppliesTheCurrentSearchAndClearingItRevealsBothFilesAndTheCapture() async throws {
        let fixture = try await Fixture(files: 1, captures: 1)
        defer { fixture.teardown() }
        fixture.search.stringValue = "unapplied"
        let arrival = fixture.folder.appendingPathComponent("arrival.png")
        try Fixture.png().write(to: arrival)
        try await fixture.changes(arrival)
        #expect(fixture.count == 0)
        fixture.query("")
        #expect(fixture.count == 3)
    }

    @MainActor private final class ItemRequests: NSObject, NSCollectionViewDataSource {
        let source: NSCollectionViewDataSource
        var requested: [IndexPath] = []

        init(_ grid: NSCollectionView) throws {
            source = try #require(grid.dataSource)
            super.init()
            grid.dataSource = self
        }

        func collectionView(_ grid: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            source.collectionView(grid, numberOfItemsInSection: section)
        }
        func collectionView(_ grid: NSCollectionView, itemForRepresentedObjectAt path: IndexPath) -> NSCollectionViewItem {
            requested.append(path)
            return source.collectionView(grid, itemForRepresentedObjectAt: path)
        }
    }

    @MainActor @Test func aNewFileSlidesIntoAScrolledGridWithoutLosingItsSelectionOrScrollPosition() async throws {
        let fixture = try await Fixture(files: 24, width: 400)
        defer { fixture.teardown() }
        let requests = try ItemRequests(fixture.grid)
        fixture.grid.reloadData()
        fixture.view.layoutSubtreeIfNeeded()
        let clip = try #require(fixture.grid.enclosingScrollView?.contentView)
        fixture.grid.scrollToItems(at: [IndexPath(item: 4, section: 0)], scrollPosition: .top)
        fixture.view.layoutSubtreeIfNeeded()
        fixture.select(7)
        let origin = clip.bounds.origin
        try #require(origin.y > 0)
        let arrival = fixture.folder.appendingPathComponent("arrival.png")
        try Fixture.png().write(to: arrival)
        requests.requested.removeAll()
        try await fixture.changes(arrival)
        #expect(fixture.count == 25 && clip.bounds.origin == origin)
        #expect(fixture.grid.selectionIndexPaths == [IndexPath(item: 8, section: 0)])
        #expect(fixture.title(8) == "fixture-07.png")
        #expect(!requests.requested.contains(IndexPath(item: 8, section: 0)))
    }

    @MainActor @Test func insertingAheadOfAHoveredTileKeepsTheHighlightUnderThePointer() async throws {
        let fixture = try await Fixture(files: 6)
        defer { fixture.teardown() }
        let hovered = try #require(fixture.tile(1))
        fixture.window.pointer = hovered.convert(NSPoint(x: hovered.bounds.midX, y: hovered.bounds.midY), to: nil)
        hovered.resamplePointer()
        try #require(litFrameMatches(hovered, lit: true))
        let arrival = fixture.folder.appendingPathComponent("arrival.png")
        try Fixture.png().write(to: arrival)
        try await fixture.changes(arrival)
        #expect(fixture.title(2) == "fixture-01.png")
        #expect(litFrameMatches(try #require(fixture.tile(2)), lit: false))
        #expect(litFrameMatches(try #require(fixture.tile(1)), lit: true))
    }

    @MainActor @Test func editingTheSelectedFileMovesItsSelectionToItsNewPosition() async throws {
        let fixture = try await Fixture(files: 5)
        defer { fixture.teardown() }
        let requests = try ItemRequests(fixture.grid)
        fixture.grid.reloadData()
        fixture.view.layoutSubtreeIfNeeded()
        fixture.select(3)
        let file = fixture.file(3)
        try Fixture.png(32, 8).write(to: file)
        requests.requested.removeAll()
        try await fixture.changes(file)
        #expect(fixture.title(0) == file.lastPathComponent && fixture.count == 5)
        #expect(fixture.grid.selectionIndexPaths == [IndexPath(item: 0, section: 0)])
        #expect(!requests.requested.contains(IndexPath(item: 4, section: 0)))
    }

    @MainActor @Test func renamingAFileReplacesOnlyItsTile() async throws {
        let fixture = try await Fixture(files: 4)
        defer { fixture.teardown() }
        let requests = try ItemRequests(fixture.grid)
        fixture.grid.reloadData()
        fixture.view.layoutSubtreeIfNeeded()
        let old = fixture.file(1), renamed = fixture.folder.appendingPathComponent("renamed.png")
        try FileManager.default.moveItem(at: old, to: renamed)
        requests.requested.removeAll()
        try await fixture.changes(old, renamed)
        #expect(fixture.count == 4 && fixture.title(1) == "renamed.png")
        #expect(requests.requested == [IndexPath(item: 1, section: 0)])
    }

    @MainActor @Test func iCloudEvictionReconfiguresOnlyTheAffectedTile() async throws {
        let fixture = try await Fixture(files: 4, synced: true)
        defer { fixture.teardown() }
        let requests = try ItemRequests(fixture.grid)
        fixture.grid.reloadData()
        fixture.view.layoutSubtreeIfNeeded()
        let file = fixture.file(1)
        requests.requested.removeAll()
        await fixture.evict(file)
        #expect(fixture.media.items.first { $0.url == file }?.isLocal == false)
        #expect(fixture.count == 4 && fixture.title(1) == file.lastPathComponent)
        #expect(requests.requested == [IndexPath(item: 1, section: 0)])
    }

    @MainActor @Test func removingTheSelectedFileDropsOnlyItsTileAndClearsSelection() async throws {
        let fixture = try await Fixture(files: 4)
        defer { fixture.teardown() }
        let requests = try ItemRequests(fixture.grid)
        fixture.grid.reloadData()
        fixture.view.layoutSubtreeIfNeeded()
        fixture.select(1)
        let file = fixture.file(1)
        try FileManager.default.removeItem(at: file)
        requests.requested.removeAll()
        try await fixture.changes(file)
        #expect(fixture.count == 3 && fixture.title(1) == "fixture-02.png")
        #expect(fixture.grid.selectionIndexPaths.isEmpty && !requests.requested.contains(IndexPath(item: 0, section: 0)))
    }

    @MainActor @Test func mediaHasNoParcInventedCountFooterOrFolderNote() async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        #expect(!Fixture.descendants(fixture.view).compactMap { $0 as? NSTextField }.contains {
            $0.stringValue.contains("On this Mac") || $0.stringValue.contains("original folders")
        })
    }

    @MainActor @Test func rightClickingEmptyGridSpaceOpensTheFolderMenu() async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        #expect(fixture.isFolderMenu(fixture.grid.menu(for: fixture.rightClick(fixture.grid))?.items.map(\.title)))
    }

    @MainActor @Test func rightClickingTheEmptyStateMessageOpensTheSameFolderMenu() async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        let message = try #require(fixture.message)
        #expect(fixture.isFolderMenu(message.menu(for: fixture.rightClick(message))?.items.map(\.title)))
    }

    @MainActor @Test(arguments: [(UInt16(109), NSEvent.ModifierFlags.shift, false), (109, [.shift, .option], true),
                                 (36, .control, false)] as [(UInt16, NSEvent.ModifierFlags, Bool)])
    func theKeyboardMenuShortcutsAskForTheMenuTheyNameWhileTheGridIsEmpty(_ code: UInt16, _ flags: NSEvent.ModifierFlags,
                                                                          _ foldersOnly: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        var request: Bool?
        fixture.grid.onKeyboardMenu = { request = $0; return true }
        fixture.press(code, flags)
        #expect(request == foldersOnly)
    }

    @MainActor @Test func accessibilityShowMenuAsksForTheKeyboardMenu() async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        var request: Bool?
        fixture.grid.onKeyboardMenu = { request = $0; return true }
        #expect(fixture.grid.accessibilityPerformShowMenu() && request == false)
    }

    @MainActor @Test func withNothingSelectedTheKeyboardMenuIsTheFolderMenu() async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        #expect(fixture.isFolderMenu(fixture.view.keyboardMenu(foldersOnly: false)?.menu.items.map(\.title)))
    }

    @MainActor @Test func captureMembershipPopulatesTheCollection() async throws {
        let fixture = try await Fixture(captures: 1)
        defer { fixture.teardown() }
        #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
    }

    @MainActor @Test func aSelectedItemsKeyboardMenuIsItsOwnMenuNotTheFolderMenu() async throws {
        let fixture = try await Fixture(captures: 1)
        defer { fixture.teardown() }
        fixture.grid.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        let titles = fixture.view.keyboardMenu(foldersOnly: false)?.menu.items.map(\.title)
        #expect(titles?.contains("Preview") == true && !fixture.isFolderMenu(titles))
    }

    @MainActor @Test func theFolderMenuStillOpensWithASelection() async throws {
        let fixture = try await Fixture(captures: 1)
        defer { fixture.teardown() }
        fixture.grid.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        #expect(fixture.isFolderMenu(fixture.view.keyboardMenu(foldersOnly: true)?.menu.items.map(\.title)))
    }

    @MainActor @Test func aSearchFilterForcesTheGridToReloadPastTheFingerprint() async throws {
        let fixture = try await Fixture(captures: 1)
        defer { fixture.teardown() }
        fixture.query("no-match-filter")
        #expect(fixture.grid.numberOfItems(inSection: 0) == 0)
    }

    @MainActor @Test func clearingTheSearchForcesMembershipToReload() async throws {
        let fixture = try await Fixture(captures: 1)
        defer { fixture.teardown() }
        fixture.query("no-match-filter")
        fixture.query("")
        #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
    }

    @MainActor @Test func theSearchFieldsClearButtonRestoresTheFullGrid() async throws {
        let fixture = try await Fixture(captures: 1, regularHeader: false)
        defer { fixture.teardown() }
        fixture.query("no-match-filter")
        fixture.search.stringValue = ""
        fixture.view.searchFieldDidEndSearching(try #require(fixture.search as? NSSearchField))
        #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
    }

    @MainActor @Test func endingASearchThatIsAlreadyAppliedLeavesTheGridAlone() async throws {
        let fixture = try await Fixture(captures: 1, regularHeader: false)
        defer { fixture.teardown() }
        fixture.view.searchFieldDidEndSearching(try #require(fixture.search as? NSSearchField))
        #expect(fixture.grid.numberOfItems(inSection: 0) == 1)
    }

    @MainActor @Test func anUnavailableFolderShowsTheBottomStatusLineAndShortensTheGrid() async throws {
        let fixture = try await Fixture(files: 2, missingFolder: true, regularHeader: true, width: 400)
        defer { fixture.teardown() }
        let scroll = try #require(fixture.grid.enclosingScrollView)
        #expect(fixture.status == "1 folder needs access. Right-click empty space to fix.")
        #expect(scroll.frame.height == fixture.view.bounds.height - scroll.frame.minY - 28)
    }

    @MainActor @Test func aSingleAvailableFolderStartsWithNoStatusLine() async throws {
        let fixture = try await Fixture(files: 1, width: 400)
        defer { fixture.teardown() }
        #expect(fixture.status == nil)
    }

    @MainActor @Test func aLoadFailureStillRendersTheMediaItem() async throws {
        let fixture = try await Fixture(files: 1, corrupt: true, width: 400)
        defer { fixture.teardown() }
        #expect(fixture.catalog.loadError != nil && fixture.grid.numberOfItems(inSection: 0) == 1)
    }

    @MainActor @Test func rightClickingTheLoadErrorMessageDoesNotOpenTheFolderMenuWhileItemsExistBehindIt() async throws {
        let fixture = try await Fixture(files: 1, corrupt: true, width: 400)
        defer { fixture.teardown() }
        let overlay = try #require(Fixture.descendants(fixture.view).compactMap { $0 as? NSTextField }.first {
            !$0.isHidden && $0.stringValue.contains("could not be read")
        })
        #expect(overlay.menu(for: fixture.rightClick(overlay)) == nil)
    }

    @MainActor @Test func anOffscreenSelectedItemsKeyboardMenuUsesTheVisibleAreasTopLeftFallback() async throws {
        let fixture = try await Fixture(files: 40, width: 400, height: 220)
        defer { fixture.teardown() }
        let last = fixture.grid.numberOfItems(inSection: 0) - 1
        fixture.grid.selectionIndexPaths = [IndexPath(item: last, section: 0)]
        fixture.grid.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
        fixture.view.layoutSubtreeIfNeeded()
        try #require(!fixture.grid.visibleRect.intersects(fixture.grid.frameForItem(at: last)))
        let request = try #require(fixture.view.keyboardMenu(foldersOnly: false))
        let visible = fixture.grid.visibleRect
        #expect(request.point == NSPoint(x: visible.minX + 10, y: visible.minY + 10))
    }

    @MainActor @Test(arguments: [false, true])
    func aThemeChangeKeepsTheMediaSearchPlaceholder(_ dark: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.teardown() }
        fixture.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        fixture.view.palette = ThemeChromePalette(theme: SpaceTheme(), isDark: dark)
        #expect(fixture.search.placeholderString == "Search Media…" && fixture.search.placeholderAttributedString?.string == "Search Media…")
    }

    @MainActor @Test func tilesInTheMediaGridAreOneHundredThirtySevenPointCellsInAThreeHundredFourPointPage() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        #expect(fixture.tile(0)?.bounds.size == NSSize(width: 137, height: 137))
    }

    @MainActor @Test func clickingACellsRingNeitherSelectsNorOpensIt() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        let tile = try #require(fixture.tile(0))
        let ring = tile.convert(NSPoint(x: 2, y: tile.bounds.midY), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: ring, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        fixture.grid.mouseDown(with: click)
        #expect(fixture.grid.selectionIndexPaths.isEmpty)
    }

    @MainActor @Test func rightClickingACellsRingOpensTheGridsFolderMenu() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        let tile = try #require(fixture.tile(0))
        let ring = tile.convert(NSPoint(x: 2, y: tile.bounds.midY), to: nil)
        let click = NSEvent.mouseEvent(with: .rightMouseDown, location: ring, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        #expect(fixture.isFolderMenu(fixture.grid.menu(for: click)?.items.map(\.title)))
    }

    @MainActor private func litFrameMatches(_ tile: CaptureLibraryTile, lit: Bool) -> Bool {
        let plate = tile.layer!.sublayers![0].frame
        let expected = tile.bounds.insetBy(dx: lit ? 0 : 4, dy: lit ? 0 : 4)
        return abs(plate.width - expected.width) < 0.01 && abs(plate.minX - expected.minX) < 0.01
    }

    @MainActor private func hover(_ fixture: Fixture, _ tile: CaptureLibraryTile) {
        let center = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        tile.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: center, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
    }

    @MainActor @Test func aLiveScrollStartingOnThePagesScrollViewRefusesHoverUntilItEnds() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        let tile = try #require(fixture.tile(0))
        let scroll = try #require(fixture.grid.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        hover(fixture, tile)
        #expect(litFrameMatches(tile, lit: false))
        fixture.window.pointer = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: NSScrollView())
        #expect(litFrameMatches(tile, lit: false))
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        #expect(litFrameMatches(tile, lit: true))
    }

    @MainActor @Test func theWindowLosingKeyClearsAHoveredTile() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        let tile = try #require(fixture.tile(0))
        fixture.window.pointer = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        tile.resamplePointer()
        try #require(litFrameMatches(tile, lit: true))
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        #expect(litFrameMatches(tile, lit: false))
    }

    @MainActor @Test func mediaLeavingItsWindowMidScrollDoesNotLeaveItsTilesRefusingHover() async throws {
        let fixture = try await Fixture(files: 2)
        defer { fixture.teardown() }
        fixture.view.layoutSubtreeIfNeeded()
        let scroll = try #require(fixture.grid.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        fixture.window.contentView = nil
        fixture.window.contentView = fixture.view
        fixture.view.layoutSubtreeIfNeeded()
        let tile = try #require(fixture.tile(0))
        hover(fixture, tile)
        #expect(litFrameMatches(tile, lit: true))
    }
}
