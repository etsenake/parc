import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary

struct LibraryRailLayoutTests {
    @MainActor @Test(arguments: [LibraryRailAnimation.Name.archive, .easels])
    func theNamedRailCompositionLoadsFromTheLibrary(_ name: LibraryRailAnimation.Name) {
        #expect(LibraryRailAnimation.named(name, in: LibraryArtwork.directory(in: .module)) != nil)
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let profile: UUID
        let view: LibraryView
        let window: NSWindow
        let tiles: [LibraryRailTile]
        let back: NSButton

        init(height: CGFloat = 832, kind: LibraryView.Kind = .downloads) throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            profile = store.state.profiles[0].id
            view = LibraryView(isolatingNotesIn: store, kind: kind, profileID: profile, reduceMotion: { true })
            view.frame = NSRect(x: 0, y: 0, width: 416, height: height)
            view.appearance = NSAppearance(named: .aqua)
            window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let all = Self.descendants(view)
            tiles = all.compactMap { $0 as? LibraryRailTile }
            back = try #require(all.compactMap { $0 as? NSButton }.first { $0.title == "Back" })
            var animations: [LibraryRailAnimation.Name: LibraryRailAnimation] = [:]
            for name in [LibraryRailAnimation.Name.media, .downloads, .easels, .spaces, .archive] {
                animations[name] = try LibraryRailMotionTests.animation(name.rawValue)
            }
            for tile in tiles { tile.loadAnimation = { animations[$0] }; tile.progress?.after = { _, _ in } }
        }

        func teardown() {
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func tile(_ title: String) -> LibraryRailTile { tiles.first { $0.title == title }! }

        func labelBands(_ tile: NSView) -> Int {
            guard let rep = tile.bitmapImageRepForCachingDisplay(in: tile.bounds) else { return -1 }
            tile.cacheDisplay(in: tile.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / tile.bounds.width
            let x = Int(tile.bounds.midX * scale), gapNeeded = Int(4 * scale)
            var bands = 0, gap = gapNeeded * 3
            for y in Int(47 * scale)..<Int(74 * scale) {
                var ink = false
                if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    ink = color.alphaComponent > 0.2 && color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5
                }
                if ink { if gap >= gapNeeded { bands += 1 }; gap = 0 } else { gap += 1 }
            }
            return bands
        }

        func firstInk(_ tile: NSView, _ rows: Range<CGFloat>) -> CGFloat? {
            tile.layoutSubtreeIfNeeded()
            guard let rep = tile.bitmapImageRepForCachingDisplay(in: tile.bounds) else { return nil }
            tile.cacheDisplay(in: tile.bounds, to: rep)
            let scale = CGFloat(rep.pixelsHigh) / tile.bounds.height
            for row in Int(rows.lowerBound * scale)..<Int(rows.upperBound * scale) {
                for x in Int((tile.bounds.midX - 30) * scale)..<Int((tile.bounds.midX + 30) * scale) {
                    if let color = rep.colorAt(x: x, y: row)?.usingColorSpace(.sRGB), color.alphaComponent > 0.2,
                       color.redComponent < 0.5 && color.greenComponent < 0.5 && color.blueComponent < 0.5 { return CGFloat(row) / scale }
                }
            }
            return nil
        }

        func flight(_ name: String = "rail", received: Int64 = 40, status: BrowserDownloadStatus = .downloading,
                    started: Date = Date()) -> BrowserDownload {
            var item = BrowserDownload(id: profile.uuidString + ":" + name, name: "Rail.dmg", path: "/nonexistent/Rail.dmg",
                                       receivedBytes: received, totalBytes: 100, status: status)
            item.profileID = profile
            item.nativeID = name
            item.nativeIdentity = name + "-1"
            item.startedAt = started
            return item
        }

        func report(_ items: [BrowserDownload], enabled: Bool = true, privateWindow: Bool = false) {
            view.updateDownloadActivity(items, profiles: [profile], privateWindow: privateWindow, enabled: enabled)
            view.layoutSubtreeIfNeeded()
        }
    }

    @MainActor @Test func theRegularRailListsTheLibraryPagesWithoutBoostsOrHistory() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.tiles.map(\.title) == ["Media", "Downloads", "Easels & Notes", "Spaces", "Archived Tabs"])
    }

    @MainActor @Test func theTallRailUsesNinetySevenByEightyTiles() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.tiles.allSatisfy { $0.frame.size == NSSize(width: 97, height: 80) && $0.frame.minX == 8 && $0.showsLabel })
    }

    @MainActor @Test func tilesSitInHundredPointSlots() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(zip(fixture.tiles, fixture.tiles.dropFirst()).allSatisfy { $1.frame.minY - $0.frame.minY == 100 })
    }

    @MainActor @Test func tilesAreCentredBetweenTheRailPaddingAndBack() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(abs(fixture.tiles[0].frame.minY + fixture.tiles[4].frame.maxY - (48 + 832 - 56)) < 0.01)
    }

    @MainActor @Test func theShownPagesTileIsSelected() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.tile("Downloads").state == .on)
    }

    @MainActor @Test func theRegularBackKeepsItsAccessibleTitleAndShowsItsArrow() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.back.imagePosition == .imageOnly)
    }

    @MainActor @Test func easelsAndNotesWrapsOntoTwoCenteredLines() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.labelBands(fixture.tile("Easels & Notes")) == 2)
    }

    @MainActor @Test func shorterRailLabelsStayOnOneLine() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.labelBands(fixture.tile("Archived Tabs")) == 1)
    }

    @MainActor @Test func railTilesAnnounceAsRadioButtonsWithTheShownPageSelected() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.tiles.allSatisfy { $0.accessibilityRole() == .radioButton })
        #expect(fixture.tile("Downloads").isAccessibilitySelected() && !fixture.tile("Media").isAccessibilitySelected())
    }

    @MainActor @Test func clickingTheSelectedTileKeepsItSelected() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let selected = fixture.tile("Downloads")
        selected.sendClick()
        #expect(selected.state == .on && selected.isAccessibilitySelected() && fixture.view.kind == .downloads)
    }

    @MainActor @Test func aTileNeverTogglesItsOwnSelection() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let other = fixture.tile("Media")
        other.state = .off
        other.cell?.setNextState()
        #expect(other.state == .off)
    }

    @MainActor @Test func onlyTheDownloadsTileCarriesAProgressBadgeHiddenWhileNothingDownloads() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let downloads = fixture.tile("Downloads")
        #expect(fixture.tiles.allSatisfy { ($0.progress != nil) == ($0 === downloads) } && downloads.progress?.isHidden == true)
    }

    @MainActor @Test func theIdleDownloadsTileDrawsItsIconOverTheLabel() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let tile = fixture.tile("Downloads")
        #expect(fixture.firstInk(tile, 46..<76) != nil && fixture.firstInk(tile, 10..<44) != nil)
    }

    @MainActor @Test func aNormalWindowsRailIgnoresPrivateDownloads() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        var item = fixture.flight()
        item.privateContextID = "private-rail"
        fixture.report([item])
        #expect(fixture.tile("Downloads").progress?.isHidden == true)
    }

    @MainActor @Test func theRailBadgesOnlyWhileTheWindowCan() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()], enabled: false)
        #expect(fixture.tile("Downloads").progress?.isHidden == true)
    }

    @MainActor @Test func theNewestInFlightDownloadsProgressBadgeShowsOnTheDownloadsTile() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let item = fixture.flight()
        fixture.report([item])
        let badge = try #require(fixture.tile("Downloads").progress)
        #expect(!badge.isHidden && badge.activity?.progress == 0.4 && badge.activity?.identity == DownloadLibraryIdentity(item))
    }

    @MainActor @Test func theBadgeKeepsItsOwnTwentyFourPointFrameCentredInTheIconSlot() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()])
        let tile = fixture.tile("Downloads")
        let badge = try #require(tile.progress)
        let frame = tile.convert(badge.bounds, from: badge)
        #expect(frame.size == NSSize(width: LibraryRailTile.progressSize, height: LibraryRailTile.progressSize))
        #expect(abs(frame.midX - tile.bounds.midX) < 0.01)
    }

    @MainActor @Test func theLabelRisesTwoPointsAsTheBadgeReplacesTheTwentyEightPointIcon() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let tile = fixture.tile("Downloads")
        let idle = try #require(fixture.firstInk(tile, 46..<76))
        fixture.report([fixture.flight()])
        let downloading = try #require(fixture.firstInk(tile, 46..<76))
        #expect(abs(idle - downloading - 2) <= 0.5)
    }

    @MainActor @Test func theBadgeLeavesTheTilesRadioButtonAccessibilityUnchanged() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()])
        let tile = fixture.tile("Downloads")
        #expect(tile.accessibilityRole() == .radioButton && tile.accessibilityLabel() == "Downloads" && tile.isAccessibilitySelected())
        #expect(tile.progress?.isAccessibilityElement() == false)
    }

    @MainActor @Test func pointerInputOverTheBadgeStillReachesTheTile() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()])
        let tile = fixture.tile("Downloads")
        let badge = try #require(tile.progress)
        let point = tile.superview!.convert(NSPoint(x: badge.bounds.midX, y: badge.bounds.midY), from: badge)
        let hit = try #require(tile.hitTest(point))
        #expect((hit === tile || hit.isDescendant(of: tile)) && !hit.isDescendant(of: badge))
    }

    @MainActor @Test func aProgressTickUpdatesOnlyTheRingWithoutRelayingOutTheTile() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let item = fixture.flight()
        fixture.report([item])
        var progressed = item
        progressed.receivedBytes = 70
        fixture.report([progressed])
        let tile = fixture.tile("Downloads")
        #expect(tile.progress?.activity?.progress == 0.7 && tile.progress?.isHidden == false && !tile.needsLayout)
    }

    @MainActor @Test func theBadgeStaysOnTheUnselectedDownloadsTileWhileAnotherPageShows() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()])
        fixture.view.show(.archive)
        #expect(fixture.tile("Downloads").state == .off && fixture.tile("Downloads").progress?.isHidden == false)
    }

    @MainActor @Test func switchingPagesFadesTheNewPageInWhileTheRailStaysPut() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.show(.archive)
        let faded = fixture.view.subviews.filter { $0.layer?.animation(forKey: "parc.library.pageFade") != nil }
        #expect(!faded.isEmpty)
        #expect(faded.allSatisfy { !$0.isHidden && $0.frame.minX >= LibraryRailLayout.width && !($0 is WindowStandardButtons)
            && !$0.subviews.contains { $0 is LibraryRailTile } })
    }

    @MainActor @Test func notStartedAndPausedDownloadsAreNotInFlightSoTheRingStaysOnTheProgressingOne() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        var progressed = fixture.flight()
        progressed.receivedBytes = 70
        let pending = fixture.flight("pending", received: 0, status: .pending, started: Date().addingTimeInterval(60))
        let paused = fixture.flight("paused", received: 30, status: .paused, started: Date().addingTimeInterval(60))
        fixture.report([progressed, pending, paused])
        let badge = try #require(fixture.tile("Downloads").progress)
        #expect(badge.activity?.identity == DownloadLibraryIdentity(progressed) && badge.activity?.progress == 0.7)
    }

    @MainActor @Test func onlyNotStartedAndPausedDownloadsShowTheIcon() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let pending = fixture.flight("pending", received: 0, status: .pending)
        let paused = fixture.flight("paused", received: 30, status: .paused)
        fixture.report([pending, paused])
        #expect(fixture.tile("Downloads").progress?.isHidden == true)
    }

    @MainActor @Test func progressReachingOneWhileInFlightPlaysTheCheckmark() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.report([fixture.flight()])
        fixture.report([fixture.flight(received: 100)])
        let badge = try #require(fixture.tile("Downloads").progress)
        #expect(!badge.isHidden && badge.activity?.completed == true)
    }

    @MainActor @Test func onceNothingIsInFlightTheIconReturnsAtOnceAndTheLabelSettlesBack() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let tile = fixture.tile("Downloads")
        let idle = fixture.firstInk(tile, 46..<76)
        fixture.report([fixture.flight()])
        fixture.report([fixture.flight(received: 100, status: .completed)])
        #expect(tile.progress?.isHidden == true && fixture.firstInk(tile, 46..<76) == idle && fixture.firstInk(tile, 10..<44) != nil)
    }

    @MainActor @Test func theLibraryLightsStayHiddenUntilTheWindowListsThem() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let lights = try #require(Fixture.descendants(fixture.view).compactMap { $0 as? WindowStandardButtons }.first)
        #expect(lights.isHidden)
        fixture.view.showsWindowButtons = true
        #expect(!lights.isHidden)
    }

    @MainActor @Test func aShortRailCompressesItsSlotsAboveBackAndDropsItsLabels() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.view.frame.size.height = 400
        fixture.view.layout()
        #expect(fixture.tiles.last!.frame.maxY <= fixture.back.frame.minY && fixture.tiles.allSatisfy { !$0.showsLabel })
    }
}
