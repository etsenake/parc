import AppKit
import Combine
import os
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary

extension CaptureLibraryViewTestsSupport {
    struct CaptureLibraryViewGridTests {
        @MainActor private func hover(_ fixture: Fixture, _ tile: CaptureLibraryTile) {
            let center = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
            tile.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: center, modifierFlags: [], timestamp: 0,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        }

        @MainActor @Test func mediaHasNoParcInventedCountFooterOrFolderNote() async throws {
            let fixture = try await Fixture()
            defer { fixture.teardown() }
            #expect(!Fixture.descendants(fixture.view).compactMap { $0 as? NSTextField }.contains {
                $0.stringValue.contains("On this Mac") || $0.stringValue.contains("original folders")
            })
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
}
