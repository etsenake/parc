import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore

struct CaptureLibraryViewTests {
    @MainActor private final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint(x: -1000, y: -1000)
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
             width: CGFloat = 304, height: CGFloat = 600) async throws {
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
                try Self.png().write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 60)],
                                                      ofItemAtPath: file.path)
            }
            let folders = missingFolder ? [folder, root.appendingPathComponent("Missing", isDirectory: true)] : [folder]
            media = ExternalMediaLibrary(directory: root.appendingPathComponent("Preferences", isDirectory: true),
                preferencesAreEphemeral: true, systemFolders: { folders }, screenshotPreferences: nil)
            await media.activate(client)?.value
            view = CaptureLibraryView(store: catalog, profileOwner: store, media: media, regularHeader: regularHeader, ownerValid: { true })
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            window = KeyedWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            grid = try #require(Self.descendants(view).compactMap { $0 as? CaptureCollectionView }.first)
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
