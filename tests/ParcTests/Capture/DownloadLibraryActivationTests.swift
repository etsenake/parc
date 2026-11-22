import AppKit
import Testing
@testable import ParcCore
@testable import ParcLibrary

struct DownloadLibraryActivationTests {
    @MainActor private final class Switches {
        var owner = true
        var previews: [DownloadLibraryPreview] = []
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let switches = Switches()
        let store: BrowserStore
        let path: String
        let window: NSWindow
        let view: DownloadLibraryView
        let table: DownloadLibraryTable
        let search: NSTextField
        let text: URL
        let image: URL
        let missing: URL
        var url: URL?
        var actions: [String] = []
        var pending: [@Sendable () -> Void] = []

        init() throws {
            _ = NSApplication.shared
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            text = directory.appendingPathComponent("original.txt")
            image = directory.appendingPathComponent("original.png")
            missing = directory.appendingPathComponent("missing.png")
            try Data("Temporary component file".utf8).write(to: text)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: image)
            store = try BrowserStore(directory: directory.appendingPathComponent("store", isDirectory: true))
            path = store.independentEngineProfilePath(for: store.state.profiles[0].id)
            url = text
            Self.publish(store, path, "first", "original")
            Self.publish(store, path, "second", "second")
            let switches = switches
            view = DownloadLibraryView(store: store, ownerValid: { switches.owner }, makePreview: {
                let preview = DownloadLibraryPreview(reduceMotion: { true }, presentWindow: { _, _ in }, isPresented: { _ in true })
                switches.previews.append(preview)
                return preview
            })
            view.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            window = NSWindow(contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            table = try #require(Self.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            search = try #require(Self.descendants(view).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Search Downloads" })
            view.fileURL = { [unowned self] _ in self.url }
            view.onAction = { [unowned self] item, action in
                self.actions.append(item.nativeID! + ":" + String(describing: action))
                return true
            }
            view.runInspection = { [unowned self] work in MainActor.assumeIsolated { self.pending.append(work) } }
            view.deliverInspection = { work in work() }
        }

        static func publish(_ store: BrowserStore, _ path: String, _ id: String, _ identity: String, status: String = "completed",
                            canOpen: Bool = true, canToggle: Bool = false, name: String? = nil) {
            store.recordDownload(["id": id, "profilePath": path, "name": name ?? id, "status": status, "available": true,
                "itemIdentity": identity, "canOpen": canOpen, "canRemove": true, "canCopyFile": status == "completed",
                "canToggleOpen": canToggle, "startedAt": 1000])
        }

        func publish(_ id: String = "first", identity: String = "original", status: String = "completed",
                     canOpen: Bool = true, canToggle: Bool = false, name: String? = nil) {
            Self.publish(store, path, id, identity, status: status, canOpen: canOpen, canToggle: canToggle, name: name)
            view.setLoading(count: 0, message: nil)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        func click(_ row: Int = 1) {
            let commit = table.prepareClick?(row)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            window.makeFirstResponder(table)
            commit?()
        }

        func deliver() {
            let work = pending
            pending = []
            work.forEach { $0() }
        }

        var previewCount: Int { switches.previews.count }
    }

    @MainActor @Test func aDateHeadingHasNoOriginalClickLease() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.table.prepareClick?(0) == nil)
    }

    @MainActor @Test func theViewRegistersItsNativeSingleClickOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(fixture.table.action == #selector(DownloadLibraryTable.activateOriginalClick))
        #expect(fixture.table.target === fixture.table)
    }

    @MainActor @Test func aCompletedNonMediaClickReachesTheOriginalOpenCallbackOnce() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.deliver()
        #expect(fixture.actions == ["first:open"])
    }

    @MainActor @Test func aReadableMediaClickPresentsAnOwnedPreviewWithoutDispatchingOpen() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.url = fixture.image
        fixture.click()
        fixture.deliver()
        #expect(fixture.previewCount == 1 && fixture.switches.previews[0].isShown && fixture.actions.isEmpty)
    }

    @MainActor @Test func retiringTheViewRemovesTheClickOwnedPreview() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.url = fixture.image
        fixture.click()
        fixture.deliver()
        fixture.view.invalidate()
        #expect(fixture.switches.previews[0].sourceRect == nil && fixture.switches.previews[0].sourceImage == nil)
    }

    @MainActor @Test func aMissingMediaFileRefusesBothPreviewAndFileOutput() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.url = fixture.missing
        fixture.click()
        fixture.deliver()
        #expect(fixture.actions.isEmpty && fixture.previewCount == 0)
    }

    @MainActor @Test func aMissingMediaFilePublishesAnHonestOriginalItemFailure() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.url = fixture.missing
        fixture.click()
        fixture.deliver()
        #expect(Fixture.descendants(fixture.view).compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "This file is no longer available to preview."
        })
    }

    @MainActor @Test func anUnfinishedOriginalDelegatesOpenWhenFinishedToTheRealManagerAction() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.publish(status: "downloading", canToggle: true)
        fixture.click()
        #expect(fixture.actions == ["first:toggleOpen"])
    }

    @MainActor @Test func aRestrictedUnfinishedOriginalNeverManufacturesAToggle() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.publish(status: "downloading", canToggle: false)
        fixture.click()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aReplacementIncarnationCannotInheritAPretrackingOriginalClick() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let stale = fixture.table.prepareClick?(1)
        fixture.publish(identity: "replacement")
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        stale?()
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aSelectionInterventionRetiresAsynchronousMetadataDelivery() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aChangedCurrentFilePathCannotRetargetPendingOriginalMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.url = fixture.image
        fixture.deliver()
        #expect(fixture.actions.isEmpty && fixture.previewCount == 0)
    }

    @MainActor @Test func contextRetirementCancelsPendingClickOutput() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.view.invalidate()
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func aRetiredOriginalOwnerSuppressesPendingFileOutput() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.switches.owner = false
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func anAcceptedItemOperationCancelsPendingClickOutput() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        let item = try #require(fixture.store.state.downloads.first { $0.nativeID == "first" })
        fixture.view.setOperation(item, message: "Busy")
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func openingTheOriginalContextMenuRetiresPendingSingleClickPublication() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        _ = fixture.table.makeMenu?()
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func interveningSearchFocusCannotBeStolenByLateMetadataCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.window.makeFirstResponder(fixture.search)
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor @Test func theSameOriginalIdentitySurvivesAHarmlessNameRefresh() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.click()
        fixture.publish(name: "Renamed while inspecting")
        fixture.deliver()
        #expect(fixture.actions == ["first:open"])
    }

    @MainActor @Test func theFinalOriginalCapabilityStillRefusesCompletedFileOpen() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.publish(canOpen: false)
        fixture.click()
        fixture.deliver()
        #expect(fixture.actions.isEmpty)
    }

    @MainActor private func dragWriter(_ fixture: Fixture, row: Int = 1) -> NSPasteboardItem? {
        fixture.view.tableView(fixture.table, pasteboardWriterForRow: row) as? NSPasteboardItem
    }

    @MainActor @Test func oneOriginalCompletedSelectedRowAdmitsFileDrag() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(fixture.table.canDrag?(IndexSet(integer: 1)) == true)
    }

    @MainActor @Test func thereIsNoInventedPluralFileDrag() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(fixture.table.canDrag?(IndexSet([1, 2])) == false)
    }

    @MainActor @Test func dateHeadingsCannotBeDragged() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(fixture.table.canDrag?(IndexSet(integer: 0)) == false)
    }

    @MainActor @Test func theActualTableDragSuppliesTheOriginalCompletedFileURL() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(try #require(dragWriter(fixture)).string(forType: .fileURL) == fixture.text.absoluteString)
    }

    @MainActor @Test func libraryRetirementCancelsAPendingOutgoingFileProvider() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let writer = try #require(dragWriter(fixture))
        fixture.view.invalidate()
        #expect(writer.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func aDragCannotRetargetAChangedPathUnderTheSameRecord() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let writer = try #require(dragWriter(fixture))
        fixture.url = fixture.image
        #expect(writer.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func aNewManagerIncarnationExpiresFileDelivery() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let writer = try #require(dragWriter(fixture))
        fixture.publish(identity: "replacement")
        #expect(writer.string(forType: .fileURL) == nil)
    }

    @MainActor @Test func aBusyOriginalFileRefusesAnOutgoingDrag() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let item = try #require(fixture.store.state.downloads.first { $0.nativeID == "first" })
        fixture.view.setOperation(item, message: "Moving to Trash…")
        #expect(dragWriter(fixture) == nil)
    }

    @MainActor private func openRowPreview(_ fixture: Fixture) throws -> DownloadLibraryPreview {
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        fixture.table.layoutSubtreeIfNeeded()
        try #require(fixture.table.view(atColumn: 0, row: 1, makeIfNecessary: true)).layoutSubtreeIfNeeded()
        fixture.url = fixture.image
        fixture.table.onPreview?()
        return try #require(fixture.switches.previews.first)
    }

    @MainActor @Test func theRowAdmissionRendersItsTwentyFourPointArtworkAtTwoXWithoutAnotherFileLoad() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let preview = try openRowPreview(fixture)
        let source = try #require(preview.sourceImage)
        #expect(source.representations.first?.pixelsWide == 48 && source.size == NSSize(width: 24, height: 24))
    }

    @MainActor @Test func invalidatingTheLibraryReleasesTheRowPreviewsSourceImageAndPresentation() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let preview = try openRowPreview(fixture)
        let modal = try #require(preview.window?.contentView?.subviews.last)
        let transition = try #require(modal.subviews.compactMap { $0 as? NSImageView }.first)
        fixture.view.invalidate()
        #expect(preview.sourceImage == nil && transition.image == nil)
    }
}
