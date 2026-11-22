import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcLibrary

struct DownloadListPresentationTests {
    @MainActor final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store: BrowserStore
        let window: NSWindow
        let view: DownloadLibraryView
        let table: DownloadLibraryTable
        let search: NSTextField
        let path: String
        let started: TimeInterval
        var actions = 0

        init(width: CGFloat = 400, dated: Bool = true) throws {
            _ = NSApplication.shared
            store = try BrowserStore(directory: directory)
            let profile = store.state.profiles[0].id
            path = store.independentEngineProfilePath(for: profile)
            started = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3600).timeIntervalSince1970
            if dated {
                let fixtures: [(String, String, String, Int64, Int64)] = [
                    ("image", "Mountain photograph.png", "completed", 2_400_000, 2_400_000),
                    ("active", "Project resources.zip", "downloading", 52_000_000, 100_000_000),
                    ("paused", "Reference video.mov", "paused", 7_000_000, 12_000_000),
                    ("failed", "Document.pdf", "failed", 0, 0)]
                for (index, fixture) in fixtures.enumerated() {
                    store.recordDownload(["id": fixture.0, "profilePath": path, "name": fixture.1, "status": fixture.2,
                        "available": true, "itemIdentity": fixture.0, "canOpen": fixture.2 == "completed",
                        "canReveal": fixture.2 == "completed", "canCopyFile": fixture.2 == "completed",
                        "canPause": fixture.2 == "downloading", "canResume": fixture.2 == "paused",
                        "canRetry": fixture.2 == "failed", "canCancel": fixture.2 == "downloading", "canRemove": true,
                        "sourceURL": "https://example.invalid/" + fixture.0, "startedAt": started - Double(index * 60),
                        "receivedBytes": fixture.3, "totalBytes": fixture.4])
                }
            }
            view = DownloadLibraryView(store: store, ownerValid: { true })
            view.frame = NSRect(x: 0, y: 0, width: width, height: 590)
            window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            table = try #require(Self.descendants(view).compactMap { $0 as? DownloadLibraryTable }.first)
            search = try #require(Self.descendants(view).compactMap { $0 as? NSTextField }.first {
                $0.accessibilityLabel() == "Search Downloads"
            })
        }

        func teardown() {
            view.invalidate()
            window.contentView = nil
            store.flushPendingWrites()
            try? FileManager.default.removeItem(at: directory)
        }

        static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

        func cell(_ row: Int) throws -> NSView { try #require(table.view(atColumn: 0, row: row, makeIfNecessary: true)) }

        func labels(_ cell: NSView) -> [NSTextField] { cell.subviews.compactMap { $0 as? NSTextField } }

        func badge(_ cell: NSView) throws -> DownloadActivityBadge {
            try #require(Self.descendants(cell).compactMap { $0 as? DownloadActivityBadge }.first)
        }

        func publishActive(_ status: String = "downloading", bytes: Int64 = 60_000_000, identity: String = "active",
                           review: Bool = false, total: Int64 = 100_000_000) {
            store.recordDownload(["id": "active", "profilePath": path, "name": "Project resources.zip", "status": status,
                "available": true, "itemIdentity": identity, "canPause": status == "downloading",
                "canResume": status == "paused", "canCancel": status == "downloading", "canRemove": true,
                "requiresReview": review, "canReview": review, "sourceURL": "https://example.invalid/active",
                "startedAt": started - 60, "receivedBytes": bytes, "totalBytes": total])
            view.setLoading(count: 0, message: nil)
            view.layoutSubtreeIfNeeded()
        }

        func menuItem(_ title: String) -> NSMenuItem? { table.makeMenu?()?.items.first { $0.title == title } }

        func setSearch(_ text: String) {
            search.stringValue = text
            view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        }

        var statusLine: NSTextField? {
            Self.descendants(view).compactMap { $0 as? NSTextField }.first {
                !$0.isHidden && ($0.stringValue.hasPrefix("Loading ") || $0.stringValue == "Profile unavailable")
            }
        }

        func more(_ cell: NSView) -> NSButton? {
            cell.subviews.compactMap { $0 as? NSButton }.first { $0.parcTooltip?.label == "More download actions" }
        }
    }

    @MainActor @Test func aDownloadFromTodayUsesTheTodayHeading() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let heading = try fixture.cell(0)
        #expect(heading is DownloadSectionHeading)
        #expect(fixture.labels(heading).first?.stringValue == "Today")
    }

    @MainActor @Test func theLibraryHasNoFabricatedCountFooter() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(!Fixture.descendants(fixture.view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "4 downloads" })
    }

    @MainActor private static func headings(of fixture: Fixture) -> [String] {
        (0..<fixture.table.numberOfRows).compactMap { row -> String? in
            guard let cell = fixture.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? DownloadSectionHeading else { return nil }
            return Fixture.descendants(cell).compactMap { $0 as? NSTextField }.first?.stringValue
        }
    }

    @MainActor private func sectioned() throws -> (Fixture, [(String, TimeInterval?)]) {
        let fixture = try Fixture(dated: false)
        let now = Date()
        let samples: [(String, TimeInterval?)] = [
            ("today-late", now.timeIntervalSince1970),
            ("today-early", now.addingTimeInterval(-1).timeIntervalSince1970),
            ("yesterday", Calendar.current.date(byAdding: .day, value: -1, to: now)!.timeIntervalSince1970),
            ("older", now.addingTimeInterval(-10 * 86_400).timeIntervalSince1970),
            ("undated", nil)]
        for sample in samples {
            var record: [String: Any] = ["id": sample.0, "profilePath": fixture.path, "name": sample.0, "status": "completed",
                "available": true, "itemIdentity": sample.0, "canRemove": true, "sourceURL": "https://example.invalid/" + sample.0,
                "receivedBytes": 1, "totalBytes": 1]
            if let started = sample.1 { record["startedAt"] = started }
            fixture.store.recordDownload(record)
        }
        fixture.view.setLoading(count: 0, message: nil)
        fixture.view.layoutSubtreeIfNeeded()
        return (fixture, samples)
    }

    @MainActor @Test func sectionsFollowEachItemsOwnTitleWithUndatedDownloadsEarlierAtTheBottom() throws {
        let (fixture, samples) = try sectioned()
        defer { fixture.teardown() }
        let now = Date()
        let ordered = samples.map { _, started -> (Date, String) in
            let date = started.map { Date(timeIntervalSince1970: $0) }
            return (date ?? .distantPast, date.map { DownloadSectionHeading.title(for: $0, now: now) } ?? DownloadSectionHeading.undatedTitle)
        }.sorted { $0.0 > $1.0 }
        var expected: [String] = []
        var previous: String?
        for entry in ordered where entry.1 != previous { expected.append(entry.1); previous = entry.1 }
        let actual = Self.headings(of: fixture)
        #expect(actual == expected)
        #expect(expected.first == "Today" && expected.last == DownloadSectionHeading.undatedTitle && expected.contains("Yesterday"))
    }

    @MainActor @Test func itemsThatShareATitleShareOneSection() throws {
        let (fixture, _) = try sectioned()
        defer { fixture.teardown() }
        #expect(Self.headings(of: fixture).filter { $0 == "Today" }.count == 1)
    }

    @MainActor @Test func aCompletedFileRowUsesTheTwentyFourPointFileImage() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let icon = try #require(Fixture.descendants(try fixture.cell(1)).compactMap { $0 as? NSImageView }.first { $0.frame.width == 24 })
        #expect(icon.frame == NSRect(x: 20, y: 16, width: 24, height: 24))
    }

    @MainActor @Test func anIdleListReachesTheBottomWithNoStatusLine() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let scroll = try #require(fixture.table.enclosingScrollView)
        #expect(fixture.statusLine == nil && scroll.frame.height == fixture.view.bounds.height - scroll.frame.minY)
    }

    @MainActor @Test func loadingShowsTheBottomStatusLineAndShortensTheList() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let scroll = try #require(fixture.table.enclosingScrollView)
        let idle = scroll.frame.height
        fixture.view.setLoading(count: 1, message: nil)
        fixture.view.layoutSubtreeIfNeeded()
        #expect(fixture.statusLine?.stringValue == "Loading downloads…" && scroll.frame.height == idle - 36)
    }

    @MainActor @Test func aLoadFailureKeepsTheStatusLineAndTheShortenedList() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let scroll = try #require(fixture.table.enclosingScrollView)
        let idle = scroll.frame.height
        fixture.view.setLoading(count: 0, message: "Profile unavailable")
        fixture.view.layoutSubtreeIfNeeded()
        #expect(fixture.statusLine?.stringValue == "Profile unavailable" && scroll.frame.height == idle - 36)
    }

    @MainActor @Test func clearingTheStatusRestoresTheFullListHeight() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let scroll = try #require(fixture.table.enclosingScrollView)
        let idle = scroll.frame.height
        fixture.view.setLoading(count: 0, message: "Profile unavailable")
        fixture.view.layoutSubtreeIfNeeded()
        fixture.view.setLoading(count: 0, message: nil)
        fixture.view.layoutSubtreeIfNeeded()
        #expect(fixture.statusLine == nil && scroll.frame.height == idle)
    }

    @MainActor @Test func anUnchangedPublicationPreservesTheNativeRowAndItsThumbnailOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let original = try fixture.cell(1)
        fixture.view.setLoading(count: 0, message: nil)
        #expect(try fixture.cell(1) === original)
    }

    @MainActor @Test func identicalRowsUnderANewSearchContextReceiveFreshLeases() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let original = try fixture.cell(1)
        fixture.setSearch("example")
        #expect(try fixture.cell(1) !== original)
    }

    @MainActor @Test func aRebuiltRowRoutesTheCurrentCommandAfterAContextChange() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.setSearch("example")
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        var count = 0
        fixture.view.onAction = { _, _ in count += 1; return true }
        let item = try #require(fixture.menuItem("Show in Finder"))
        _ = NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item)
        #expect(count == 1)
    }

    @MainActor @Test func anInProgressDownloadShowsTheCircularBadgeInsteadOfTheFallbackIcon() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        cell.layoutSubtreeIfNeeded()
        let badge = try fixture.badge(cell)
        let icon = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        #expect(badge.activity?.progress == 0.52 && !badge.isHidden && icon.isHidden)
    }

    @MainActor @Test func theProgressBadgeKeepsItsThirtyTwoPointSlot() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        cell.layoutSubtreeIfNeeded()
        #expect(try fixture.badge(cell).frame == NSRect(x: 16, y: 12, width: 28, height: 32))
    }

    @MainActor @Test func noProvisionalProgressBarRemains() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        #expect(Fixture.descendants(try fixture.cell(2)).allSatisfy { !($0 is NSProgressIndicator) })
    }

    @MainActor @Test func theProgressArtworkAddsNoSecondAccessibleControl() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let owner = try #require(try fixture.badge(try fixture.cell(2)).subviews.first)
        #expect(!owner.isAccessibilityElement() && owner.accessibilityChildren()?.isEmpty == true)
    }

    @MainActor @Test func anActiveRowHasOneMoreControlAndKeepsTheManagersPause() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        #expect(cell.subviews.compactMap { $0 as? NSButton }.count == 1)
        #expect(fixture.menuItem("Pause")?.isEnabled == true)
    }

    @MainActor @Test func progressPublicationKeepsTheMoreControlsHoverColor() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let more = try #require(fixture.more(cell))
        more.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        let hovered = more.contentTintColor
        fixture.publishActive()
        #expect(more.contentTintColor == hovered)
    }

    @MainActor @Test func progressPublicationKeepsTheRowAndItsAnimationOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        let badge = try fixture.badge(cell)
        let owner = badge.subviews.first
        fixture.publishActive()
        #expect(try fixture.cell(2) === cell && badge.subviews.first === owner && badge.activity?.progress == 0.6)
    }

    @MainActor @Test func theSameMoreControlKeepsNativeFocusWhileProgressChanges() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let more = try #require(fixture.more(cell))
        fixture.window.makeFirstResponder(more)
        fixture.publishActive()
        #expect(fixture.window.firstResponder === more)
    }

    @MainActor @Test func pausingRemovesTheAnimatedArtworkAndKeepsTheFocusOwner() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        let badge = try fixture.badge(cell)
        let icon = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let more = try #require(fixture.more(cell))
        fixture.window.makeFirstResponder(more)
        fixture.publishActive("paused")
        #expect(badge.activity == nil && badge.subviews.isEmpty && icon.isHidden)
        #expect(fixture.window.firstResponder === more)
    }

    @MainActor @Test func pausedStateReplacesTheMenuCapabilityWithoutAnInlineControl() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        fixture.publishActive("paused")
        #expect(fixture.menuItem("Resume")?.isEnabled == true && fixture.menuItem("Pause") == nil)
    }

    @MainActor @Test func aNotStartedDownloadUsesTheFallbackArtworkInsteadOfProgress() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        let badge = try fixture.badge(cell)
        let icon = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        fixture.publishActive("pending")
        #expect(badge.activity == nil && !icon.isHidden)
    }

    @MainActor @Test func anUnknownTotalStaysTruthfulWhileTheBadgeSuppliesItsIndeterminateArtwork() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let badge = try fixture.badge(try fixture.cell(2))
        fixture.publishActive(total: 0)
        #expect(badge.activity?.progress == nil && !badge.isHidden)
    }

    @MainActor @Test func aSecurityReviewKeepsItsShieldInsteadOfOrdinaryProgress() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        let badge = try fixture.badge(cell)
        let icon = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        fixture.table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        fixture.publishActive(review: true)
        #expect(badge.activity == nil && !icon.isHidden)
        #expect(fixture.menuItem("Review…")?.isEnabled == true)
    }

    @MainActor @Test func aCompletedRowLeavesProgressImmediately() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        let badge = try fixture.badge(cell)
        let icon = try #require(cell.subviews.compactMap { $0 as? NSImageView }.first)
        let owner = try #require(badge.subviews.first)
        fixture.publishActive("completed", bytes: 100_000_000)
        #expect(badge.activity == nil && badge.subviews.isEmpty && owner.superview == nil && !icon.isHidden)
    }

    @MainActor @Test func invalidatingTheLibraryRetiresTheVisibleRowAnimation() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let badge = try fixture.badge(try fixture.cell(2))
        fixture.view.invalidate()
        #expect(badge.activity == nil && badge.subviews.isEmpty)
    }

    @MainActor @Test func aReopenedContextObtainsANewRowOwnedAnimationLease() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let cell = try fixture.cell(2)
        fixture.view.invalidate()
        fixture.view.setLoading(count: 0, message: nil)
        fixture.view.layoutSubtreeIfNeeded()
        let revived = try fixture.cell(2)
        let badge = try fixture.badge(revived)
        #expect(revived !== cell && badge.activity != nil)
    }

    @MainActor @Test func aReplacementIncarnationRetiresTheOriginalBadgeAndOwnsItsOwn() throws {
        let fixture = try Fixture()
        defer { fixture.teardown() }
        let original = try fixture.badge(try fixture.cell(2))
        fixture.publishActive(identity: "replacement")
        #expect(original.activity == nil && original.subviews.isEmpty)
        #expect(try fixture.badge(try fixture.cell(2)).activity?.identity.incarnation == "replacement")
    }
}
