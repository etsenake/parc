import AppKit
import Combine
import os
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary

extension CaptureLibraryViewTestsSupport {
    struct CaptureLibraryViewMenuTests {
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

        struct MenuShortcut: CustomTestStringConvertible, Sendable {
            let testDescription: String
            let code: UInt16
            let flags: NSEvent.ModifierFlags
            let foldersOnly: Bool

            static let cases: [Self] = [
                .init(testDescription: "Shift-F10", code: 109, flags: .shift, foldersOnly: false),
                .init(testDescription: "Shift-Option-F10", code: 109, flags: [.shift, .option], foldersOnly: true),
                .init(testDescription: "Control-Return", code: 36, flags: .control, foldersOnly: false),
            ]
        }

        @MainActor @Test(arguments: MenuShortcut.cases)
        func theKeyboardMenuShortcutsAskForTheMenuTheyNameWhileTheGridIsEmpty(_ sample: MenuShortcut) async throws {
            let fixture = try await Fixture()
            defer { fixture.teardown() }
            var request: Bool?
            fixture.grid.onKeyboardMenu = { request = $0; return true }
            fixture.press(sample.code, sample.flags)
            #expect(request == sample.foldersOnly)
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
    }
}
