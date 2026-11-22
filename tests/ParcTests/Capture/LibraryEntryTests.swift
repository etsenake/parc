import AppKit
import ParcTestSupport
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcLibrary
@testable import ParcSidebar

@MainActor private final class LibraryTestSchedule {
    private(set) var jobs: [(delay: TimeInterval, job: @MainActor () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ job: @escaping @MainActor () -> Void) {
        jobs.append((delay, job))
    }

    func runNext() throws {
        let next = try #require(jobs.first)
        jobs.removeFirst()
        next.job()
    }
}

private struct LibraryEntryItems {
    let date = Date(timeIntervalSince1970: 2_000)
    let profile = UUID()

    func download(_ id: String, _ status: BrowserDownloadStatus, age: TimeInterval = 0) -> BrowserDownload {
        var item = BrowserDownload(id: id, name: id + ".pdf", path: "/Downloads/" + id + ".pdf",
            receivedBytes: 60, totalBytes: 100, status: status)
        item.profileID = profile
        item.nativeID = id
        item.nativeIdentity = "current"
        item.startedAt = date.addingTimeInterval(-age)
        return item
    }

    func file(_ name: String, age: TimeInterval = 0) -> LibraryFlyoutFile {
        LibraryFlyoutFile(url: URL(fileURLWithPath: "/Desktop/" + name), dateCreated: date.addingTimeInterval(-age),
                          isScreenshot: false, source: .desktop)
    }
}

struct LibraryEntryPreferencesTests {
    @MainActor private func withPreferences(_ body: (LibraryEntryPreferences, LibraryEntryPreferences) throws -> Void) throws {
        let defaults = try #require(TestDefaults("ParcTests.libraryEntry."))
        try body(LibraryEntryPreferences(defaults: defaults), LibraryEntryPreferences(defaults: defaults))
    }

    @MainActor @Test func aFreshLibraryOpensToDownloads() throws {
        try withPreferences { fresh, _ in #expect(fresh.lastSelectedPage == .downloads) }
    }

    @MainActor @Test(arguments: LibraryEntryPage.allCases)
    func theLastLibraryPagePersists(_ page: LibraryEntryPage) throws {
        try withPreferences { first, reopened in
            first.lastSelectedPage = page
            #expect(reopened.lastSelectedPage == page)
        }
    }

    @MainActor @Test(arguments: LibraryBadgeSource.allCases)
    func hidingABadgeSourceLeavesTheOtherSourcesEnabled(_ source: LibraryBadgeSource) throws {
        try withPreferences { first, reopened in
            first.setEnabled(false, source)
            #expect(!reopened.isEnabled(source))
            #expect(LibraryBadgeSource.allCases.filter { $0 != source }.allSatisfy { reopened.isEnabled($0) })
        }
    }
}

struct LibraryEntryRouteTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test(arguments: [(299.0, true), (300.0, false), (301.0, false)])
    func anUnreadBadgeOnlyRoutesWhileItIsRecent(_ age: Double, _ recent: Bool) {
        let unread = LibraryEntryUnread(page: .captures, since: now.addingTimeInterval(-age))
        #expect(LibraryEntryRoute.target(unread: unread, now: now) == (recent ? .captures : nil))
    }

    @Test func aClosedLibraryWithoutUnreadActivityUsesItsLastPage() {
        #expect(LibraryEntryRoute.decide(target: nil, showing: nil, lastSelected: .archive) == .open(.archive))
    }

    @Test func clickingTheVisibleUnreadPageClosesTheLibrary() {
        #expect(LibraryEntryRoute.decide(target: .downloads, showing: .downloads, lastSelected: .spaces) == .close)
    }

    @Test func unreadActivityCanSwitchTheOpenLibraryToItsPage() {
        #expect(LibraryEntryRoute.decide(target: .captures, showing: .downloads, lastSelected: .downloads) == .open(.captures))
    }
}

struct LibraryBadgeLifecycleTests {
    private let items = LibraryEntryItems()

    @MainActor private func lifecycle(_ schedule: LibraryTestSchedule) -> LibraryBadgeLifecycle {
        let owner = LibraryBadgeLifecycle()
        owner.now = { items.date }
        owner.after = schedule.schedule
        return owner
    }

    @MainActor @Test func aLiveDownloadKeepsItsBadgeWithoutSchedulingDismissal() {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        let live = items.download("current", .downloading, age: 900)
        let item = LibraryFlyoutItem.download(live)
        owner.update([item], newestLive: DownloadLibraryIdentity(live), itemsChanged: false)
        #expect(owner.visibleID == item.id && schedule.jobs.isEmpty)
        #expect(owner.unread?.page == .downloads)
    }

    @MainActor @Test(arguments: [(BrowserDownloadStatus.completed, 30.0), (.failed, 5.0), (.cancelled, 5.0)])
    func aTerminalDownloadReceivesItsOwnDismissalTime(_ status: BrowserDownloadStatus, _ delay: Double) throws {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        let live = items.download("current", .downloading)
        let item = LibraryFlyoutItem.download(live)
        owner.update([item], newestLive: DownloadLibraryIdentity(live), itemsChanged: false)
        owner.update([.download(items.download("current", status))], newestLive: nil, itemsChanged: true)
        #expect(schedule.jobs.map(\.delay) == [delay])
        try schedule.runNext()
        #expect(owner.visibleID == nil)
    }

    @MainActor @Test func aPriorBadgeTimeoutCannotDismissANewerItem() throws {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        owner.update([.file(items.file("old.png"))], newestLive: nil, itemsChanged: true)
        let newer = LibraryFlyoutItem.file(items.file("new.png"))
        owner.update([newer], newestLive: nil, itemsChanged: true)
        try schedule.runNext()
        #expect(owner.visibleID == newer.id)
    }

    @MainActor @Test func expandingTheFlyoutDismissesACompletedBadge() {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        owner.update([.download(items.download("done", .completed))], newestLive: nil, itemsChanged: true)
        owner.flyoutDidExpand()
        #expect(owner.visibleID == nil)
    }

    @MainActor @Test func expandingTheFlyoutKeepsADownloadingBadge() {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        let item = LibraryFlyoutItem.download(items.download("live", .downloading))
        owner.update([item], newestLive: nil, itemsChanged: true)
        owner.flyoutDidExpand()
        #expect(owner.visibleID == item.id)
    }

    @MainActor @Test func markingTheLibraryReadClearsItsUnreadRoute() {
        let schedule = LibraryTestSchedule(), owner = lifecycle(schedule)
        owner.update([.file(items.file("recent.png"))], newestLive: nil, itemsChanged: true)
        owner.markRead()
        #expect(owner.unread == nil)
    }
}

struct LibraryEntryModelTests {
    @MainActor private func model(_ schedule: LibraryTestSchedule) -> LibraryEntryModel {
        let model = LibraryEntryModel()
        model.after = schedule.schedule
        model.animate = { _, body in body() }
        return model
    }

    @MainActor @Test(arguments: [(false, 0.8), (true, 0.55)])
    func theBadgeLandsAtTheScaleForItsContent(_ compact: Bool, _ scale: Double) throws {
        let schedule = LibraryTestSchedule(), model = model(schedule)
        model.show("download", compact: compact)
        #expect(model.phase == .landing)
        #expect(Double(model.cell.scale) == scale)
        try schedule.runNext()
        #expect(model.phase == .shown && model.cell.y == LibraryEntryModel.base)
    }

    @MainActor @Test func hidingTheBadgeSettlesItsPoseAndNotifiesTheOwner() throws {
        let schedule = LibraryTestSchedule(), model = model(schedule)
        var hidden = false
        model.onHidden = { hidden = true }
        model.show("download", compact: false)
        try schedule.runNext()
        model.hide()
        #expect(model.phase == .hiding && model.cell.opacity == 0)
        try schedule.runNext()
        #expect(model.phase == .hidden && hidden)
    }

    @MainActor @Test func aStaleHideCannotEraseTheReplacementBadge() throws {
        let schedule = LibraryTestSchedule(), model = model(schedule)
        model.show("one", compact: true)
        try schedule.runNext()
        model.hide()
        model.show("two", compact: false)
        try schedule.runNext()
        #expect(model.visibleBadge == "two" && model.phase == .landing)
    }

    @MainActor @Test(arguments: [false, true])
    func theAnimatedBadgeOnlyHandsItsSlotToTheCurrentFlyoutRow(_ reducedMotion: Bool) {
        let schedule = LibraryTestSchedule(), model = model(schedule)
        let item = LibraryFlyoutItem.file(LibraryEntryItems().file("photo.png"))
        model.visibleItem = item
        model.show(item.id, compact: false)
        #expect(model.presentedSlot(in: [item], reduceMotion: reducedMotion) == (reducedMotion ? nil : 0))
    }
}

struct LibraryFlyoutTests {
    private let items = LibraryEntryItems()

    @Test func aFileAndItsDownloadEntryAreShownOnlyOnce() {
        let download = items.download("paper", .completed)
        let file = LibraryFlyoutFile(url: URL(fileURLWithPath: download.path), dateCreated: items.date,
            isScreenshot: false, source: .desktop)
        let merged = LibraryFlyoutItems.merge(downloads: [download, download], captures: [], files: [file])
        #expect(merged.count == 1 && merged.first?.download?.id == download.id)
    }

    @Test func downloadsAndExternalFilesShareARecencyOrder() {
        let download = items.download("paper", .completed, age: 60)
        let merged = LibraryFlyoutItems.merge(downloads: [download], captures: [],
            files: [items.file("old.png", age: 120), items.file("new.png")])
        #expect(merged.map(\.title) == ["new.png", "paper.pdf", "old.png"])
    }

    @MainActor @Test func theFlyoutDisplaysItsFourMostRecentInputRows() {
        let flyout = LibraryFlyoutModel()
        let rows = (1...5).map { LibraryFlyoutItem.file(items.file("\($0).png")) }
        flyout.setRows(rows)
        #expect(flyout.rows.map(\.id) == Array(rows.prefix(4)).map(\.id))
    }

    @MainActor @Test func movingFromTheButtonIntoTheFlyoutKeepsItOpen() {
        let schedule = LibraryTestSchedule()
        let flyout = LibraryFlyoutModel()
        flyout.after = schedule.schedule
        flyout.canExpand = true
        flyout.setRows([.file(items.file("photo.png"))])
        flyout.setButtonHovered(true)
        flyout.setFlyoutHovered(true)
        flyout.setButtonHovered(false)
        #expect(flyout.expanded)
    }

    @MainActor @Test func recentLibraryCloseSuppressesImmediateHoverExpansion() {
        let schedule = LibraryTestSchedule()
        let flyout = LibraryFlyoutModel()
        flyout.after = schedule.schedule
        flyout.now = { items.date }
        flyout.libraryClosedAt = items.date.addingTimeInterval(-0.05)
        flyout.canExpand = true
        flyout.setRows([.file(items.file("photo.png"))])
        flyout.setButtonHovered(true)
        #expect(!flyout.expanded)
    }

    @MainActor @Test func retiredRowsDiscardTheirImageCallbacks() throws {
        let flyout = LibraryFlyoutModel()
        var callback: (@MainActor (NSImage?) -> Void)?
        var cancelled = false
        flyout.imageLoader = { _, finish in
            callback = finish
            return { cancelled = true }
        }
        let item = LibraryFlyoutItem.file(items.file("photo.png"))
        flyout.setRows([item])
        flyout.setRows([])
        let finish = try #require(callback)
        finish(NSImage(size: CGSize(width: 16, height: 16)))
        #expect(cancelled && flyout.images[item.id] == nil)
    }

    @MainActor @Test func aButtonHoverReportsOnlyAfterLinger() throws {
        let schedule = LibraryTestSchedule()
        let hover = LibraryFlyoutHoverTracker()
        hover.after = schedule.schedule
        let frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        hover.update(pointer: CGPoint(x: 16, y: 16), rects: [.button: frame], tracked: [.button])
        #expect(!hover.isHovered(.button) && schedule.jobs.map(\.delay) == [0.15])
        try schedule.runNext()
        #expect(hover.isHovered(.button))
    }

    @MainActor @Test func leavingBeforeLingerCancelsThePendingHover() throws {
        let schedule = LibraryTestSchedule()
        let hover = LibraryFlyoutHoverTracker()
        hover.after = schedule.schedule
        let frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        hover.update(pointer: CGPoint(x: 16, y: 16), rects: [.button: frame], tracked: [.button])
        hover.update(pointer: nil, rects: [.button: frame], tracked: [.button])
        try schedule.runNext()
        #expect(!hover.isHovered(.button))
    }
}

struct SidebarLibraryEntryTests {
    @MainActor private final class Fixture {
        let window: NSWindow
        let sidebar = NSView(frame: CGRect(x: 0, y: 0, width: 228, height: 400))
        let entry = SidebarLibraryEntry()
        let items = LibraryEntryItems()
        let schedule = LibraryTestSchedule()
        let defaults: UserDefaults
        var opened: [LibraryEntryPage?] = []
        var actions: [LibraryFlyoutAction] = []

        init() throws {
            _ = NSApplication.shared
            window = NSWindow(contentRect: sidebar.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = sidebar
            defaults = try #require(TestDefaults("ParcTests.sidebarLibrary."))
            entry.preferences = LibraryEntryPreferences(defaults: defaults)
            entry.model.after = schedule.schedule
            entry.badge.after = schedule.schedule
            entry.model.animate = { _, apply in apply() }
            entry.flyout.imageLoader = { _, finish in finish(nil); return {} }
            entry.now = { [items] in items.date }
            entry.onOpen = { [weak self] in self?.opened.append($0) }
            entry.onItemAction = { [weak self] action in self?.actions.append(action); return true }
            sidebar.addSubview(entry)
            entry.place(button: slot)
            sidebar.layoutSubtreeIfNeeded()
        }

        var slot: CGRect { SidebarChromeLayout.dockLeadingButton(height: sidebar.bounds.height) }

        func update(_ downloads: [BrowserDownload], privateWindow: Bool = false, badging: Bool = true) {
            entry.updateFlyoutDownloads(downloads, profiles: [items.profile], privateWindow: privateWindow, badging: badging)
        }
    }

    @MainActor @Test func theHomeButtonOccupiesTheOriginalLeadingDockSlot() throws {
        let fixture = try Fixture()
        #expect(fixture.entry.convert(fixture.entry.buttonRect, to: fixture.sidebar) == fixture.slot)
        #expect(fixture.entry.hostRect == fixture.entry.buttonRect)
    }

    @MainActor @Test func theEntryCanvasLeavesOutsideClicksToTheSidebar() throws {
        let fixture = try Fixture()
        let button = fixture.entry.buttonRect
        let inside = fixture.entry.convert(CGPoint(x: button.midX, y: button.midY), to: fixture.sidebar)
        let outside = fixture.entry.convert(CGPoint(x: button.maxX + 20, y: button.midY), to: fixture.sidebar)
        #expect(fixture.entry.hitTest(inside) === fixture.entry)
        #expect(fixture.entry.hitTest(outside) == nil)
    }

    @MainActor @Test func theDecorativeEntryRendererDoesNotAddKeyboardStops() throws {
        let fixture = try Fixture()
        #expect(!fixture.entry.acceptsFirstResponder && !fixture.entry.canBecomeKeyView)
        #expect(!fixture.entry.host.acceptsFirstResponder && !fixture.entry.host.canBecomeKeyView)
    }

    @MainActor @Test func aLiveDownloadBadgeRoutesTheHomeButtonToDownloads() throws {
        let fixture = try Fixture()
        fixture.update([fixture.items.download("current", .downloading)])
        fixture.entry.perform()
        #expect(fixture.opened == [.downloads])
    }

    @MainActor @Test func aPrivateWindowOnlyProjectsDownloadsFromItsContextKind() throws {
        let fixture = try Fixture()
        let regular = fixture.items.download("regular", .downloading)
        var privateItem = fixture.items.download("private", .downloading)
        privateItem.privateContextID = "private-owner"
        fixture.update([regular, privateItem], privateWindow: true)
        #expect(fixture.entry.flyout.rows.compactMap { $0.download?.id } == ["private"])
    }

    @MainActor @Test func aNormalWindowDoesNotProjectPrivateDownloadBadges() throws {
        let fixture = try Fixture()
        var privateItem = fixture.items.download("private", .downloading)
        privateItem.privateContextID = "private-owner"
        fixture.update([privateItem])
        #expect(fixture.entry.flyout.rows.isEmpty && fixture.entry.lifecycle.visibleID == nil)
    }

    @MainActor @Test func cancelOnALiveFlyoutRowDispatchesItsOwnDownload() throws {
        let fixture = try Fixture()
        let transfer = fixture.items.download("live", .downloading)
        fixture.update([transfer])
        let row = try #require(fixture.entry.flyout.rows.first)
        #expect(fixture.entry.cancel(row.id))
        guard case .download(let item, .cancel) = fixture.actions.first else {
            Issue.record("Expected cancellation for the selected transfer"); return
        }
        #expect(item.id == transfer.id)
    }

    @MainActor @Test func aCompletedFlyoutRowCannotInvokeCancel() throws {
        let fixture = try Fixture()
        fixture.update([fixture.items.download("done", .completed)])
        let row = try #require(fixture.entry.flyout.rows.first)
        #expect(!fixture.entry.cancel(row.id) && fixture.actions.isEmpty)
    }

    @MainActor @Test func closingTheOriginalWindowRetiresTheEntryBadge() throws {
        let fixture = try Fixture()
        fixture.update([fixture.items.download("current", .downloading)])
        try #require(fixture.entry.lifecycle.visibleID != nil)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: fixture.window)
        fixture.update([fixture.items.download("next", .downloading)])
        #expect(fixture.entry.lifecycle.visibleID == nil && fixture.entry.badge.activity == nil)
    }
}

struct LibraryBoxOfThingsTests {
    @MainActor @Test func aHoverTwinklesThenSettlesBackToTheSamePose() throws {
        let clock = LibraryTestSchedule()
        let icon = BoxOfThingsIconState()
        icon.after = clock.schedule
        icon.hover(true, reduceMotion: false)
        #expect(icon.isHovered && icon.twinkle1 && !icon.twinkle2)
        try clock.runNext()
        #expect(!icon.twinkle1 && icon.twinkle2)
        try clock.runNext()
        #expect(!icon.twinkle1 && !icon.twinkle2)
    }

    @MainActor @Test func reducedMotionNeverSchedulesTheHoverTwinkle() {
        let clock = LibraryTestSchedule()
        let icon = BoxOfThingsIconState()
        icon.after = clock.schedule
        icon.hover(true, reduceMotion: true)
        #expect(!icon.isHovered && !icon.twinkle1 && clock.jobs.isEmpty)
    }
}
