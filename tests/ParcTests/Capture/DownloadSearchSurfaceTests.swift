import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary

struct DownloadSearchSurfaceTests {
    @MainActor private final class KeyedWindow: NSWindow {
        var key = true
        var pointer = NSPoint.zero
        override var isKeyWindow: Bool { key }
        override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let window: KeyedWindow
        let view: DownloadLibraryView
        let backdrop: DownloadSearchBackdrop
        let search: DownloadSearchField
        let table: DownloadLibraryTable
        var closed = 0

        init() throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            let first = store.state.profiles[0].id
            let second = store.createProfile(name: "Second Profile")
            for (id, profile) in [("z-original", first), ("a-later", first), ("other", second)] {
                store.recordDownload(["id": id, "profilePath": store.independentEngineProfilePath(for: profile), "name": id,
                                      "status": "completed", "available": true, "itemIdentity": id + "1", "canOpen": true,
                                      "startedAt": 1000])
            }
            view = DownloadLibraryView(store: store, ownerValid: { true })
            view.frame = NSRect(x: 0, y: 0, width: 304, height: 600)
            window = KeyedWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let all = Self.descendants(view)
            backdrop = try #require(all.compactMap { $0 as? DownloadSearchBackdrop }.first)
            search = try #require(all.compactMap { $0 as? DownloadSearchField }.first)
            table = try #require(all.compactMap { $0 as? DownloadLibraryTable }.first)
            view.onClose = { [weak self] in self?.closed += 1 }
        }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        var glyph: NSImageView { backdrop.subviews.compactMap { $0 as? NSImageView }.first! }

        var surfaceAlpha: CGFloat {
            backdrop.updateLayer()
            return NSColor(cgColor: backdrop.layer!.backgroundColor!)!.alphaComponent
        }

        func moved(to point: NSPoint) -> NSEvent {
            window.pointer = point
            return NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        }

        var inside: NSPoint { backdrop.convert(NSPoint(x: 20, y: 18), to: nil) }

        func enterExit(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }

        func click() -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
    }

    @MainActor @Test func thereIsNoFilterControlNowThatProfilesAreInvisible() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let all = Fixture.descendants(fixture.view)
        #expect(!all.compactMap { $0 as? NSButton }.contains { $0.title == "Filter" || $0.title == "Done" })
        #expect(!all.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Profiles" })
    }

    @MainActor @Test func downloadsFromEveryProfileAppearInOneListInSourceOrder() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let names = (0..<fixture.table.numberOfRows).compactMap { row -> String? in
            guard let cell = fixture.view.tableView(fixture.table, viewFor: fixture.table.tableColumns[0], row: row) as? NSTableCellView
            else { return nil }
            return Fixture.descendants(cell).compactMap { $0 as? NSTextField }.first?.stringValue
        }
        #expect(names.count == 3)
        #expect(names == fixture.store.downloadItems.map(\.name))
    }

    @MainActor @Test func thePlainEditorLineStaysCenteredInTheHeaderSurface() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(abs(fixture.search.frame.midY - fixture.backdrop.bounds.midY) <= 0.5)
        #expect(fixture.search.frame.height == fixture.search.cell!.cellSize.height)
    }

    @MainActor @Test func theSearchPaddingKeepsTheFullHeaderHitAreaWithoutASecondAccessibilityControl() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.backdrop.frame.height == 36 && fixture.backdrop.bounds.contains(fixture.search.frame))
        #expect(!fixture.backdrop.isAccessibilityElement() && !fixture.backdrop.isAccessibilityHidden())
    }

    @MainActor @Test func theQueryUsesAPlainNativeFieldWithoutSearchOrClearAccessories() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(!(fixture.search.cell is NSSearchFieldCell))
        #expect(!Fixture.descendants(fixture.backdrop).contains { $0 is NSButton })
    }

    @MainActor @Test func theTypedQueryIsPrimaryWhileThePlaceholderKeepsTheSystemGrey() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.search.textColor == .labelColor)
        let color = fixture.search.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .placeholderTextColor)
    }

    @MainActor @Test func theHeaderIsAnEightPointInsetFullWidthThirtySixPointField() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let frame = fixture.backdrop.frame
        #expect(frame.minX == 8 && frame.minY == 10 && frame.maxX == fixture.view.bounds.width - 8 && frame.height == 36)
    }

    @MainActor @Test func theNativeEditorHasTheOriginalTypographyWithoutABezelOrFocusShadow() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.search.font?.pointSize == 14)
        #expect(!fixture.search.isBezeled && !fixture.search.drawsBackground && fixture.search.focusRingType == .none)
    }

    @MainActor @Test func theMagnifierKeepsAFifteenPointOpticalBoxInsideAMarginedCanvas() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let image = try #require(fixture.glyph.image)
        let optical = image.alignmentRect
        #expect(optical.size == NSSize(width: 15, height: 15))
        #expect(fixture.glyph.frame.size == image.size)
        #expect(optical.minX >= 1 && optical.minY >= 1)
        #expect(image.size.width >= optical.maxX + 1 && image.size.height >= optical.maxY + 1)
    }

    @MainActor @Test func theMagnifierAndEditorKeepTheirInsetAndSpacingWithoutOverlap() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let optical = try #require(fixture.glyph.image).alignmentRect
        #expect(abs(fixture.glyph.frame.minX + optical.minX - 14.5) < 0.01)
        #expect(abs(fixture.glyph.frame.minX + optical.maxX + 11.5 - fixture.search.frame.minX) < 0.01)
    }

    @MainActor @Test func theMagnifierForwardsPointerFocusToTheSearchSurface() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let point = NSPoint(x: fixture.backdrop.frame.minX + fixture.glyph.frame.midX,
                            y: fixture.backdrop.frame.minY + fixture.glyph.frame.midY)
        #expect(fixture.backdrop.hitTest(point) === fixture.backdrop)
    }

    @MainActor @Test func theSurfaceInkResolvesInTheViewsOwnLightAppearance() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.appearance = NSAppearance(named: .aqua)
        fixture.backdrop.updateLayer()
        let color = try #require(NSColor(cgColor: fixture.backdrop.layer!.backgroundColor!)?.usingColorSpace(.deviceRGB))
        #expect(color.redComponent < 0.1 && abs(color.alphaComponent - 0.05) < 0.001)
    }

    @MainActor @Test func anAppearanceChangeReResolvesTheSemanticInkInsteadOfKeepingTheLightColor() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.appearance = NSAppearance(named: .aqua)
        fixture.backdrop.updateLayer()
        fixture.backdrop.appearance = NSAppearance(named: .darkAqua)
        fixture.backdrop.updateLayer()
        let color = try #require(NSColor(cgColor: fixture.backdrop.layer!.backgroundColor!)?.usingColorSpace(.deviceRGB))
        #expect(color.redComponent > 0.9 && abs(color.alphaComponent - 0.05) < 0.001)
    }

    @MainActor @Test func aSameWindowPointerHitRaisesOnlyTheSurfaceOpacity() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.mouseMoved(with: fixture.moved(to: fixture.inside))
        #expect(abs(fixture.surfaceAlpha - 0.1) < 0.001)
    }

    @MainActor @Test func replacingTheTrackingAreaResamplesTheCurrentPointer() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.mouseMoved(with: fixture.moved(to: fixture.inside))
        fixture.window.pointer = NSPoint(x: 1000, y: 1000)
        fixture.backdrop.updateTrackingAreas()
        #expect(abs(fixture.surfaceAlpha - 0.05) < 0.001)
    }

    @MainActor @Test func anObsoleteTrackingExitCannotClearANewerHover() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.mouseMoved(with: fixture.moved(to: fixture.inside))
        fixture.backdrop.mouseExited(with: fixture.enterExit(.mouseExited))
        #expect(abs(fixture.surfaceAlpha - 0.1) < 0.001)
    }

    @MainActor @Test func keyResignationAndAStaleQueuedEntryCannotRetainOrReassertHover() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.mouseMoved(with: fixture.moved(to: fixture.inside))
        fixture.window.key = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: fixture.window)
        fixture.backdrop.mouseEntered(with: fixture.enterExit(.mouseEntered))
        #expect(abs(fixture.surfaceAlpha - 0.05) < 0.001)
    }

    @MainActor @Test func aCurrentOutsideHitRestoresTheIdleOpacity() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.backdrop.mouseMoved(with: fixture.moved(to: fixture.inside))
        fixture.backdrop.mouseMoved(with: fixture.moved(to: NSPoint(x: 1000, y: 1000)))
        #expect(abs(fixture.surfaceAlpha - 0.05) < 0.001)
    }

    @MainActor @Test func clickingTheBackgroundKeepsTheEditingQueryRange() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.search.stringValue = "original"
        fixture.window.makeFirstResponder(fixture.search)
        let editor = try #require(fixture.search.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 2, length: 3))
        fixture.backdrop.mouseDown(with: fixture.click())
        #expect(fixture.search.currentEditor() === editor && editor.selectedRange() == NSRange(location: 2, length: 3))
    }

    @MainActor @Test func clickingTheBackgroundNeverCommitsAnInputMethodComposition() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.window.makeFirstResponder(fixture.search)
        let editor = try #require(fixture.search.currentEditor() as? NSTextView)
        editor.setMarkedText("input", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        fixture.backdrop.mouseDown(with: fixture.click())
        #expect(editor.hasMarkedText())
    }

    @MainActor @Test func escapeClearsOnlyTheSearchBeforeLeavingTheLibrary() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.search.stringValue = "original"
        fixture.window.makeFirstResponder(fixture.table)
        fixture.view.cancelOperation(nil)
        #expect(fixture.search.stringValue.isEmpty && fixture.closed == 0)
        fixture.view.cancelOperation(nil)
        #expect(fixture.closed == 1)
    }
}
