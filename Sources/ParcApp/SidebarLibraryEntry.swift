import AppKit
import Combine
import SwiftUI

//
//
//
//
//
// .medium) with the "View Library" tooltip, the "Home" label, the "Show media
// from:" menu and the badge cells. [I] marks an inference; Parc adaptations
// are marked as such.

///
/// Downloads, screenshotsAndCaptures → Media (captures), easelsAndNotes →
/// Easels & Notes (documents), archive → Archive and spaces → Spaces. Boosts
/// remain excluded.
enum LibraryEntryPage: String, CaseIterable {
    case downloads, captures, documents, archive, spaces
}

///
///
enum LibraryBadgeSource: String, CaseIterable {
    case documents, desktop, screenshots, captures, downloads
    var title: String {
        switch self {
        case .documents: return "Documents"
        case .desktop: return "Desktop"
        case .screenshots: return "Screenshots"
        //
        // is Saved Captures (Window → View Media, Library → Media).
        case .captures: return "Saved Captures"
        case .downloads: return "Downloads"
        }
    }
    ///
    /// Screenshots, plus the browser's Downloads and Saved Captures catalogs.
    var isAvailable: Bool { true }
}

/// `HomePreferences.lastSelectedHomePage` and
/// `HomeBadgingPreferences.dataSourcePreferences`, shared by every window.
@MainActor final class LibraryEntryPreferences {
    static let shared = LibraryEntryPreferences()
    static let didChange = Notification.Name("ParcLibraryEntryPreferencesDidChange")
    private let defaults: UserDefaults
    private let pageKey = "parc.library.lastSelectedPage.v1"
    private let sourcesKey = "parc.library.badgeSources.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func value(_ key: String) -> Any? { defaults.object(forKey: key) }
    private func set(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    ///
    /// item names one ([I] from `didUpdateLastSelectedHomePage`); with none
    /// saved, Downloads, `HomePageID`'s first case and Parc's former entry
    /// page [I].
    var lastSelectedPage: LibraryEntryPage {
        get { (value(pageKey) as? String).flatMap(LibraryEntryPage.init(rawValue:)) ?? .downloads }
        set { set(newValue.rawValue, pageKey) }
    }

    ///
    /// reads the stored dictionary; with none stored, HomePreferences takes
    ///
    ///
    ///
    func isEnabled(_ source: LibraryBadgeSource) -> Bool {
        guard source.isAvailable else { return false }
        return ((value(sourcesKey) as? [String: Bool]) ?? [:])[source.rawValue] ?? true
    }
    func setEnabled(_ enabled: Bool, _ source: LibraryBadgeSource) {
        guard source.isAvailable else { return }
        var sources = (value(sourcesKey) as? [String: Bool]) ?? [:]
        sources[source.rawValue] = enabled
        set(sources, sourcesKey)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// `HomeBadgingClient.State.mostRecentUnreadItemVisibility`: the page the
/// newest visible badge item names and when it became visible.
struct LibraryEntryUnread: Equatable {
    let page: LibraryEntryPage
    let since: Date
}

///
///
enum LibraryEntryRoute {
    /// `now − event.date ≥ 300` names no page.
    static let recentInterval: TimeInterval = 300
    /// Downloads when the newest unread badge item is a download, Media
    /// (Parc's captures page) when it is a file or capture, provided it became
    /// visible less than 300 s ago; otherwise none, so the Library reopens on
    /// its last page.
    static func target(unread: LibraryEntryUnread?, now: Date) -> LibraryEntryPage? {
        guard let unread, now.timeIntervalSince(unread.since) < recentInterval else { return nil }
        return unread.page
    }
    enum Decision: Equatable { case open(LibraryEntryPage), close }
    ///
    /// a click closes it when it already shows the target, or when there is
    /// no target; otherwise it opens the target, or the last selected page.
    static func decide(target: LibraryEntryPage?, showing: LibraryEntryPage?, lastSelected: LibraryEntryPage) -> Decision {
        if let showing, target == nil || target == showing { return .close }
        return .open(target ?? lastSelected)
    }
}

///
/// collapsed badge cell shows, and when it goes away.
/// - `create` badges the new download (case 2/1 → `updateVisibleBadgeItemIfPossible`,
///
///   badged yet (DL26's original-item selection, `DownloadActivity.active`).
/// - `itemsChanged` badges the newest item when it is younger than 300 s
///
///   those changes.
/// - `updateVisibleBadgeItemIfPossible` (case 4) ignores the visible id, else
///   sets it with its unread time and runs the dismissal: 5 s for a file,
///   capture, failed or cancelled download, 30 s for a completed one, none
///
///
/// - A visible download's update to a terminal status runs that dismissal
///
/// - `onDidExpandFlyout` dismisses a visible download whose status is terminal
///
@MainActor final class LibraryBadgeLifecycle {
    static let recentInterval: TimeInterval = 300
    static let dismissal: TimeInterval = 5
    static let completedDismissal: TimeInterval = 30

    private(set) var visibleID: String?
    private(set) var unread: LibraryEntryUnread?
    var now: () -> Date = Date.init
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    /// The visible item changed (nil: dismissed).
    var onChange: ((String?) -> Void)?
    private(set) var items: [LibraryFlyoutItem] = []
    private var badgedDownloads = Set<DownloadLibraryIdentity>()
    private var dismissalToken = 0

    var visibleItem: LibraryFlyoutItem? { visibleID.flatMap { id in items.first { $0.id == id } } }

    /// A source publication: every merged item, newest first. `newestLive` is
    /// the newest live download (a creation the first time it is seen);
    /// `itemsChanged` marks a capture-library publication.
    func update(_ next: [LibraryFlyoutItem], newestLive: DownloadLibraryIdentity?, itemsChanged: Bool) {
        let previous = visibleItem
        items = next
        if let id = visibleID {
            if let item = visibleItem {
                // Parc publishes whole lists, so the terminal update is the
                // visible download's status transition into completed, failed
                // or cancelled.
                if let status = item.downloadStatus, status.isTerminal, previous?.downloadStatus != status { scheduleDismissal(item) }
            } else {
                // Parc adaptation: the visible item left the list (hidden,
                //
                // with it, so the badge is dismissed.
                dismiss(id)
            }
        }
        if let identity = newestLive, !badgedDownloads.contains(identity),
           let created = next.first(where: { $0.downloadIdentity == identity }) {
            badgedDownloads.insert(identity)
            setVisible(created)
        }
        if itemsChanged, let first = next.first, now().timeIntervalSince(first.dateCreated) < Self.recentInterval {
            setVisible(first)
        }
    }
    /// `onDidExpandFlyout` (case 9).
    func flyoutDidExpand() {
        guard let item = visibleItem, item.downloadStatus?.isTerminal == true else { return }
        dismiss(item.id)
    }
    /// `dismissVisibleBadgeItem(id)` (case 5): only the matching visible id.
    func dismiss(_ id: String) {
        guard visibleID == id else { return }
        visibleID = nil
        cancelDismissal()
        onChange?(nil)
    }
    /// `onDidOpenArcHome` (case 11) clears the unread item.
    func markRead() { unread = nil }
    /// The window stopped badging (closing, not ready, detached). Badging
    /// again starts afresh, as a new window's entry does.
    func reset() {
        items = []
        badgedDownloads.removeAll()
        cancelDismissal()
        guard let id = visibleID else { return }
        dismiss(id)
    }
    private func setVisible(_ item: LibraryFlyoutItem) {
        guard visibleID != item.id else { return }
        visibleID = item.id
        unread = LibraryEntryUnread(page: item.download == nil ? .captures : .downloads, since: now())
        scheduleDismissal(item)
        onChange?(item.id)
    }
    private func scheduleDismissal(_ item: LibraryFlyoutItem) {
        cancelDismissal()
        let delay: TimeInterval
        switch item.downloadStatus {
        case nil: delay = Self.dismissal
        case .completed?: delay = Self.completedDismissal
        case .failed?, .cancelled?: delay = Self.dismissal
        default: return
        }
        let token = dismissalToken, id = item.id
        after(delay) { [weak self] in
            guard let self, self.dismissalToken == token else { return }
            self.dismiss(id)
        }
    }
    private func cancelDismissal() { dismissalToken &+= 1 }
}

///
///
enum LibraryEntryLayout {
    static let buttonSize: CGFloat = 32
    static let cellHeight: CGFloat = 56
    /// A collapsed visible cell's width; an expanded one is
    /// min(containerWidth, 1000) − 16.
    static let collapsedCellWidth: CGFloat = 40
    static let badgeGrowth: CGFloat = 10
    static let maximumWidth: CGFloat = 1000
    static let expandedInset: CGFloat = 16
    /// The cell VStack's offset from the button's bottom-leading corner.
    static let overlayOffset = CGSize(width: -4, height: -30)
    ///
    /// (56 + 0) × index + 30 for its row in the newest-first stack, which
    /// returns any row to the bottom slot and cancels the overlay's −30 so the
    /// cell's bottom meets the button's. Parc's pose keeps the bottom slot's
    /// 30; the canvas adds the 56 × reverseIndex of the cell's row.
    static let collapsedCellX: CGFloat = 10
    static let collapsedCellY: CGFloat = 30
    ///
    static func totalHeight(count: Int) -> CGFloat { (cellHeight + 0) * CGFloat(count) + buttonSize }
    static func expandedCellWidth(containerWidth: CGFloat) -> CGFloat { min(containerWidth, maximumWidth) - expandedInset }
    ///
    /// badge, min(containerWidth, 1000) × maxHeight (256) while expanded.
    static func hostSize(badgeVisible: Bool, expanded: Bool = false, containerWidth: CGFloat = 0) -> CGSize {
        if expanded { return CGSize(width: min(containerWidth, maximumWidth), height: totalHeight(count: LibraryFlyoutItems.limit)) }
        return badgeVisible ? CGSize(width: buttonSize + badgeGrowth, height: buttonSize + badgeGrowth) : CGSize(width: buttonSize, height: buttonSize)
    }
    /// Room the entry's canvas keeps around the button for the badge cell's
    /// travel and the flyout's four rows with their 80-point insertion drop
    ///
    static let canvasInsets = NSEdgeInsets(top: 320, left: 8, bottom: 8, right: 24)
    static func canvasSize(containerWidth: CGFloat) -> CGSize {
        CGSize(width: max(canvasInsets.left + buttonSize + canvasInsets.right, min(containerWidth, maximumWidth)),
               height: canvasInsets.top + buttonSize + canvasInsets.bottom)
    }
}

/// One badge cell's `@State` pose: x and y offsets, opacity, scale and
/// rotation (degrees), as HomeBadgingCellStack applies them.
struct LibraryEntryCellPose: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacity: Double = 0
    var scale: CGFloat = 1
    var rotation: Double = 0
}

///
///
///
@MainActor final class LibraryEntryModel: ObservableObject {
    enum Phase: Equatable { case hidden, landing, shown, hiding }
    @Published var buttonYOffset: CGFloat = 0
    /// Scales the button 1.2 (0x3ff3333333333333). The show seed and the hide
    /// clear it; no traced path sets it.
    @Published var buttonScaled = false
    @Published var cell = LibraryEntryCellPose()
    /// The visible badge item's id (HomeBadgingCellStack's `visibleBadgeItemID` State).
    @Published private(set) var visibleBadge: String?
    /// The item the visible cell draws (its BadgingIcon), kept current with
    /// the item's status.
    @Published var visibleItem: LibraryFlyoutItem?
    /// Whether the DL27 renderer currently draws (running, or its completion
    /// transaction); the completed item's image shows once it has retired.
    @Published var ringActive = false
    @Published private(set) var phase = Phase.hidden
    /// The hide's cleanup ran (the visible cell no longer presents its row).
    var onHidden: (() -> Void)?
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    private var generation = 0

    private static let landing = Animation.timingCurve(0.78, 0, 0.7, 1, duration: 0.2)
    private static let settling = Animation.interpolatingSpring(mass: 1, stiffness: 500, damping: 25, initialVelocity: 10)
    private static let leaving = Animation.linear(duration: 0.14)
    ///
    static let base = LibraryEntryLayout.collapsedCellY

    private func change(_ animation: Animation?, _ body: () -> Void) {
        if let animation { withAnimation(animation, body) } else { body() }
    }

    ///
    /// capture or completed download, 0.8 for any other download.
    static func scale(compact: Bool) -> CGFloat { compact ? 0.55 : 0.8 }

    /// A new visible badge item. Seed without animation: x 10, y b − 8,
    ///
    /// timingCurve(0.78, 0, 0.7, 1) drops the cell to b + 12 at full opacity
    /// and nudges the button 6 down; 0.22 s later a spring (mass 1, stiffness
    /// 500, damping 25, velocity 10) returns both to rest. The seeded scale
    /// State stays until the next seed or expansion reset, so a download that
    /// completes while visible keeps its 0.8.
    func show(_ id: String, compact: Bool) {
        generation &+= 1
        let token = generation, b = Self.base
        visibleBadge = id
        change(nil) {
            cell = LibraryEntryCellPose(x: LibraryEntryLayout.collapsedCellX, y: b - 8, opacity: 0,
                                        scale: Self.scale(compact: compact), rotation: 0)
            buttonYOffset = 0; buttonScaled = false
        }
        phase = .landing
        change(Self.landing) { cell.y = b + 12; cell.opacity = 1; buttonYOffset = 6 }
        after(0.22) { [weak self] in
            guard let self, self.generation == token else { return }
            self.change(Self.settling) { self.cell.y = b; self.buttonYOffset = 0 }
            self.phase = .shown
        }
    }

    /// The visible item went away: clear buttonScaled, then 0.14 s linear to
    ///
    /// opacity 0, scale 0.2 and −45 (read as degrees [I]); the cell is cleared
    ///
    func hide() {
        guard visibleBadge != nil else { return }
        generation &+= 1
        let token = generation, b = Self.base
        visibleBadge = nil
        phase = .hiding
        change(nil) { buttonScaled = false }
        change(Self.leaving) {
            cell.y = b + 20; cell.x = LibraryEntryLayout.collapsedCellX - 14
            cell.opacity = 0; cell.scale = 0.2; cell.rotation = -45
        }
        after(0.16) { [weak self] in
            guard let self, self.generation == token else { return }
            self.change(nil) { self.cell = LibraryEntryCellPose(); self.buttonYOffset = 0 }
            self.phase = .hidden
            self.onHidden?()
        }
    }

    /// The newest-first slot (reverseIndex) of the row the visible cell draws
    ///
    /// no visible item, an item outside the four rows, or Reduce Motion,
    /// where the cell fades at the button and the stack draws the row.
    func presentedSlot(in rows: [LibraryFlyoutItem], reduceMotion: Bool) -> Int? {
        guard !reduceMotion, phase != .hidden, let id = visibleItem?.id else { return nil }
        return rows.firstIndex { $0.id == id }
    }

    ///
    ///
    /// now, rotation 0, the button at rest, opacity 1. It runs in the
    /// expansion's transaction (the rows' spring).
    func resetPose(compact: Bool) {
        guard visibleBadge != nil, phase == .landing || phase == .shown else { return }
        cell = LibraryEntryCellPose(x: LibraryEntryLayout.collapsedCellX, y: Self.base, opacity: 1,
                                    scale: Self.scale(compact: compact), rotation: 0)
        buttonScaled = false; buttonYOffset = 0
    }
}

///
/// DownloadActivityBadge renderer, centred in its cell. It stays in the tree
/// so the badge keeps its window and progress across choreography.
private struct LibraryEntryBadgeCell: NSViewRepresentable {
    let badge: DownloadActivityBadge
    func makeNSView(context: Context) -> DownloadActivityBadge { badge }
    func updateNSView(_ nsView: DownloadActivityBadge, context: Context) {}
    /// The cell's frame sizes the renderer; AppKit's fitting size is never
    /// asked (its engine frame is meaningless mid-retirement).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DownloadActivityBadge, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// The visible HomeBadgingCell. Its BadgingIcon: a running download draws
/// DownloadProgressBadge (Parc's DL27 renderer, kept in the tree so it keeps
/// its window); a completed download its QuickLook image, a capture its image
/// in the dashed outline; a paused, pending, failed or cancelled download
/// nothing (EmptyView). BadgingIcon swaps branches with no transition. While
/// it presents its expanded row (shouldShowDetails) the row's details and
/// hover background join it. Parc adaptation: DL26/DL27 confirm completion by
///
/// the renderer once that completion transaction has retired.
private struct LibraryEntryVisibleCell: View {
    @ObservedObject var model: LibraryEntryModel
    @ObservedObject var flyout: LibraryFlyoutModel
    let badge: DownloadActivityBadge
    let row: LibraryFlyoutItem?
    let details: Bool
    let subtitle: (LibraryFlyoutItem) -> String
    var body: some View {
        LibraryFlyoutCell(item: row, subtitle: row.map(subtitle) ?? "", showsDetails: details,
                          hovered: details && row != nil && flyout.hoveredRow == row?.id, colors: flyout.colors,
                          icon: ZStack {
                              if let item = model.visibleItem, item.showsImage, !model.ringActive {
                                  LibraryFlyoutIcon(item: item, image: flyout.images[item.id], ring: nil, colors: flyout.colors)
                              }
                              LibraryEntryBadgeCell(badge: badge)
                          })
    }
}

/// HomeButtonView/HomeBadgingCellStack laid out on the entry's canvas: the
/// button at the canvas's inset, its offset and scale, and the cell overlay
/// at its bottom-leading corner offset (−4, −30): the flyout's rows and the
/// collapsed visible badge cell.
struct LibraryEntryCanvas: View {
    @ObservedObject var model: LibraryEntryModel
    @ObservedObject var flyout: LibraryFlyoutModel
    let item: TranslucentItemState
    let badge: DownloadActivityBadge
    let ring: (LibraryFlyoutItem) -> DownloadActivityBadge?
    let subtitle: (LibraryFlyoutItem) -> String
    var body: some View {
        let pose = model.cell, expanded = flyout.expanded
        let slot = model.presentedSlot(in: flyout.rows, reduceMotion: flyout.reduceMotion)
        let row = slot.map { flyout.rows[$0] }, opened = expanded && slot != nil
        let reverseIndex = slot ?? 0, rise = LibraryEntryLayout.cellHeight * CGFloat(reverseIndex)
        TranslucentItemFace(state: item)
            .offset(x: 0, y: model.buttonYOffset)
            .scaleEffect(model.buttonScaled ? 1.2 : 1.0, anchor: .center)
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LibraryFlyoutStack(model: flyout, presented: row?.id, ring: ring, subtitle: subtitle)
                    //
                    // shapes a row: collapsed 40 × 56 in its choreography pose,
                    //
                    // reverseIndex + 30); expanded the full row at (0, 0), its
                    // width, scale and offset on the row's spring. Without a
                    // presented row it fades at the button instead.
                    LibraryEntryVisibleCell(model: model, flyout: flyout, badge: badge, row: row, details: opened, subtitle: subtitle)
                        .frame(width: opened ? flyout.expandedCellWidth : LibraryEntryLayout.collapsedCellWidth,
                               height: LibraryEntryLayout.cellHeight)
                        .scaleEffect(opened ? 1 : pose.scale)
                        .rotationEffect(.degrees(opened ? 0 : pose.rotation))
                        .offset(x: opened ? 0 : pose.x, y: opened ? 0 : pose.y + rise)
                        .opacity(opened ? 1 : expanded ? 0 : pose.opacity)
                        .animation(LibraryFlyoutLayout.animation(reverseIndex: reverseIndex), value: expanded)
                        .offset(x: 0, y: -rise)
                }
                .offset(LibraryEntryLayout.overlayOffset)
            }
            .frame(width: LibraryEntryLayout.buttonSize, height: LibraryEntryLayout.buttonSize)
            .padding(.leading, LibraryEntryLayout.canvasInsets.left)
            .padding(.top, LibraryEntryLayout.canvasInsets.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: LibraryFlyoutStack.space)
    }
}

/// The sidebar's Library entry. Its frame is a drawing canvas around the
/// 32-point button (`buttonRect`); only the button, the visible badge cell
/// and the expanded flyout's rows take the pointer.
@MainActor final class SidebarLibraryEntry: TranslucentBoxOfThingsItem, NSDraggingSource {
    ///
    static let accessibilityTitle = "Home"
    /// NSLocalizedString("View Library", comment: "Title for tooltip on the
    /// button to open Library"); 1.170 ships no English table, so the key.
    /// The current Library binding shows as keycaps when one is assigned.
    static let tooltipText = "View Library"
    static let menuTitle = "Show media from:"

    let model = LibraryEntryModel()
    let flyout = LibraryFlyoutModel()
    let hover = LibraryFlyoutHoverTracker()
    /// HomeBadgingItems' visible badge item and its dismissal.
    let lifecycle = LibraryBadgeLifecycle()
    /// The visible cell's DownloadProgressBadge: DL26/DL27's renderer, fed the
    /// visible download only.
    let badge = DownloadActivityBadge(frame: .zero)
    var preferences = LibraryEntryPreferences.shared { didSet { recomputeRows() } }
    /// `.delegate(.onDidClickEntryPoint)`: the window's route with the target
    /// page, nil when no recent unread item names one.
    var onOpen: ((LibraryEntryPage?) -> Void)?
    /// A row's download or capture action through the window's routes.
    var onItemAction: ((LibraryFlyoutAction) -> Bool)?
    /// The window's file URL for a download (Library's native file route).
    var downloadFileURL: ((BrowserDownload) -> URL?)?
    /// The flyout's expansion, for the sidebar content mask, with its row count.
    var onFlyoutExpansion: ((Bool, Int) -> Void)?
    var now: () -> Date {
        get { flyout.now }
        set { flyout.now = newValue; lifecycle.now = newValue }
    }
    /// The newest unread visible item's page and time; a click reads it.
    var unread: LibraryEntryUnread? { lifecycle.unread }
    private var preferenceObserver: NSObjectProtocol?
    private var captureObservation: AnyCancellable?
    private var downloads: [BrowserDownload] = []
    private var captures: [SavedCapture] = []
    private var files: [LibraryFlyoutFile] = []
    /// Every merged item (newest first); the flyout shows the first four.
    private var items: [LibraryFlyoutItem] = []
    /// The window's badging condition; the entry badges only while attached.
    private var badgingAllowed = false
    /// A closed window never badges again, even if a late publication arrives.
    private weak var retiredWindow: NSWindow?
    private var badging: Bool { badgingAllowed && window != nil && window !== retiredWindow }
    private var rings: [DownloadLibraryIdentity: DownloadActivityBadge] = [:]
    /// Whether rows' rings render: from expansion until the collapse has
    /// faded the rows (`LibraryFlyoutLayout.ringRetirement`).
    private var ringsShown = false
    private var ringGeneration = 0
    private var ringProfiles: Set<UUID> = []
    private var lastPointer: NSPoint?
    private var updatingHover = false
    private enum Press: Equatable { case row(String), cancel(String), badge }
    private var press: Press?
    private var pressStart: NSPoint?
    private var fileDrags: [DownloadFileDrag] = []
    private var captureDrags: [LibraryCaptureDrag] = []
    private var closeObserver: NSObjectProtocol?
    private(set) var preview: DownloadLibraryPreview?
    private var previewIdentity: DownloadLibraryIdentity?
    private var previewURL: URL?
    /// The previewable items listed when the preview was presented (Previous/Next).
    private var previewOrder: [DownloadLibraryIdentity] = []
    private var previewGeneration = 0
    /// Starts a drag after this many points of movement (Parc's sidebar drag
    /// threshold; SwiftUI's drag start distance is untraced).
    static let dragThreshold: CGFloat = 4
    private lazy var homeElement: LibraryEntryElement = {
        let element = LibraryEntryElement(host: self, label: Self.accessibilityTitle)
        element.rect = { [weak self] in self?.buttonRect ?? .zero }
        element.press = { [weak self] in self?.perform(); return self != nil }
        return element
    }()
    private var rowElements: [String: LibraryEntryElement] = [:]
    private var cancelElements: [String: LibraryEntryElement] = [:]
    private var badgeElement: LibraryEntryElement?

    init() {
        super.init(colors: nil, action: nil)
        install(AnyView(LibraryEntryCanvas(model: model, flyout: flyout, item: state, badge: badge,
            ring: { [weak self] item in self?.ring(for: item) },
            subtitle: { [weak self] item in LibraryFlyoutText.subtitle(item, now: self?.now() ?? Date()) })))
        frame.size = LibraryEntryLayout.canvasSize(containerWidth: flyout.containerWidth)
        let button = buttonRect
        flyout.stackOrigin = CGPoint(x: button.minX + LibraryEntryLayout.overlayOffset.width, y: button.maxY + LibraryEntryLayout.overlayOffset.height)
        action = { [weak self] in self?.click() }
        // The renderer only reports whether it draws; the visible item and its
        // lifetime are the lifecycle's.
        badge.onChange = { [weak self] activity in
            guard let self, self.model.ringActive != (activity != nil) else { return }
            self.model.ringActive = activity != nil
        }
        model.onHidden = { [weak self] in self?.refreshRings() }
        //
        // itself is not one.
        setAccessibilityElement(false)
        hover.after = { [weak self] delay, body in self?.model.after(delay, body) }
        flyout.after = { [weak self] delay, body in self?.model.after(delay, body) }
        lifecycle.after = { [weak self] delay, body in self?.model.after(delay, body) }
        lifecycle.onChange = { [weak self] id in self?.visibleItemChanged(id) }
        hover.onChange = { [weak self] region, hovered in self?.regionChanged(region, hovered) }
        flyout.onExpansionChange = { [weak self] expanded in self?.expansionChanged(expanded) }
        flyout.imageLoader = { [weak self] item, completion in self?.loadImage(item, completion) ?? {} }
        preferenceObserver = NotificationCenter.default.addObserver(forName: LibraryEntryPreferences.didChange,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recomputeRows() }
            }
        parcTooltip = buttonTooltip
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }

    /// The 32-point button inside the canvas.
    override var buttonRect: NSRect {
        let insets = LibraryEntryLayout.canvasInsets
        return NSRect(x: insets.left, y: insets.top, width: LibraryEntryLayout.buttonSize, height: LibraryEntryLayout.buttonSize)
    }
    ///
    /// bottom-left corner while a badge is visible or the flyout is expanded.
    var hostRect: NSRect {
        let size = LibraryEntryLayout.hostSize(badgeVisible: model.visibleBadge != nil, expanded: flyout.expanded,
                                               containerWidth: flyout.containerWidth)
        let button = buttonRect
        return NSRect(x: button.minX, y: button.maxY - size.height, width: size.width, height: size.height)
    }
    /// The sidebar's width (LayoutSpec.containerWidth).
    var containerWidth: CGFloat {
        get { flyout.containerWidth }
        set {
            guard newValue != flyout.containerWidth else { return }
            flyout.containerWidth = newValue
            frame.size = LibraryEntryLayout.canvasSize(containerWidth: newValue)
            updateHover()
        }
    }
    /// The window's `canExpandHomeBadge` (see LibraryFlyoutModel.canExpand).
    var canExpand: Bool {
        get { flyout.canExpand }
        set { guard newValue != flyout.canExpand else { return }; flyout.canExpand = newValue; updateHover() }
    }
    /// Puts the button on `button`, a rect in the (flipped) superview.
    func place(button: NSRect) {
        let insets = LibraryEntryLayout.canvasInsets, size = LibraryEntryLayout.canvasSize(containerWidth: flyout.containerWidth)
        let flipped = superview?.isFlipped ?? true
        frame = NSRect(x: button.minX - insets.left,
                       y: flipped ? button.minY - insets.top : button.minY - insets.bottom,
                       width: size.width, height: size.height)
    }
    /// Whether the Downloads source badges the entry.
    var showsDownloadBadges: Bool { preferences.isEnabled(.downloads) }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { retirePresentation() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Build the SwiftUI tree now, so the badge has its window before the
        // first download publication.
        host.layoutSubtreeIfNeeded()
        resolveFlyoutColors()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        if let window {
            // Nothing the entry owns outlives its window (DL27's rule for the
            // renderer, applied to the badge item, drags and preview).
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated { self?.retiredWindow = window; self?.retirePresentation() }
                }
            recomputeRows()
        }
    }
    /// Retires every presentation the entry owns: pointer (and with it the
    /// part its tooltip follows), rings, images, the visible badge item and
    /// its renderer, drags and preview. The window's TooltipController hides
    /// a shown tooltip itself.
    private func retirePresentation() {
        pointerMoved(to: nil)
        ringGeneration &+= 1; ringsShown = false
        for ring in rings.values { ring.reset() }
        flyout.reset()
        lifecycle.reset()
        badge.reset()
        retireDrags()
        closePreview()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveFlyoutColors()
    }
    override var appearance: NSAppearance? { didSet { resolveFlyoutColors() } }
    /// The BaseAssets colours follow the entry's appearance (the sidebar sets
    /// it from the theme, as for the button's GrayA colours).
    private func resolveFlyoutColors() {
        let colors = LibraryFlyoutColors.standard(dark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        if flyout.colors != colors { flyout.colors = colors }
    }

    // MARK: Click route

    private func click() {
        onOpen?(LibraryEntryRoute.target(unread: lifecycle.unread, now: now()))
    }
    /// `onDidOpenArcHome`: the window's layout setter (WindowState+WindowLayout
    ///
    /// client's sixth closure) on every switch into the Library, whichever
    ///
    ///
    /// the Library reads nothing.
    func libraryDidOpen() { lifecycle.markRead() }
    /// `onDidCloseArcHome`: the Library's close date (HomeBadgingFeatureState
    /// `lastClosedArcHomeAt`).
    func libraryDidClose() { flyout.libraryClosedAt = now() }

    // MARK: Items

    /// The window's downloads (`downloadStore.downloadItems`) for its profiles.
    /// A private window lists only its private downloads, a normal window none
    ///
    /// is false while the window cannot badge (closing, not ready, private
    /// downloads unavailable): no visible badge item or renderer then.
    func updateFlyoutDownloads(_ items: [BrowserDownload], profiles: Set<UUID>, privateWindow: Bool, badging: Bool = true) {
        let next = items.filter { item in
            item.profileID.map(profiles.contains) == true && (item.privateContextID != nil) == privateWindow
        }
        // Every page title, URL and loading change republishes downloads;
        // rebuilding identical rows cost each of those a merge, sort and layout.
        guard next != downloads || profiles != ringProfiles || badging != badgingAllowed else { return }
        ringProfiles = profiles
        downloads = next
        badgingAllowed = badging
        recomputeRows()
    }
    /// The active profile's capture library, nil in a private window.
    var captureStore: CaptureLibraryStore? {
        didSet {
            guard captureStore !== oldValue else { return }
            captureObservation = captureStore?.$items.sink { [weak self] items in
                MainActor.assumeIsolated { self?.updateFlyoutCaptures(items) }
            }
            if captureStore == nil { updateFlyoutCaptures([]) }
        }
    }
    /// The capture library's records (the Saved Captures source). A
    ///
    func updateFlyoutCaptures(_ items: [SavedCapture]) {
        captures = items
        recomputeRows(itemsChanged: true)
    }
    /// Documents, Desktop and Screenshots folder files (`fileQueryResultsLoaded`).
    func updateFlyoutFiles(_ next: [LibraryFlyoutFile]) {
        let changed = next != files
        files = next
        recomputeRows(itemsChanged: changed)
    }
    private func recomputeRows(itemsChanged: Bool = false) {
        items = LibraryFlyoutItems.merge(
            downloads: preferences.isEnabled(.downloads) ? downloads : [],
            captures: preferences.isEnabled(.captures) ? captures : [],
            files: files.filter { preferences.isEnabled($0.source) })
        flyout.setRows(items)
        if badging {
            let newest = DownloadActivity.active(in: preferences.isEnabled(.downloads) ? downloads : [], profiles: ringProfiles)
            lifecycle.update(items, newestLive: newest?.identity, itemsChanged: itemsChanged)
        } else {
            lifecycle.reset()
        }
        refreshVisibleItem()
        refreshRings()
        revalidatePreview()
        updateHover()
    }
    /// The row's DownloadProgressBadge, for a running download.
    private func ring(for item: LibraryFlyoutItem) -> DownloadActivityBadge? {
        guard let identity = item.downloadIdentity, item.downloadStatus?.isInProgress == true else { return nil }
        if let ring = rings[identity] { return ring }
        let ring = DownloadActivityBadge(frame: .zero)
        ring.colors = badge.colors
        rings[identity] = ring
        return ring
    }
    /// Rings render only while the flyout shows them: a row leaving retires
    /// its renderer at once, collapsing once the rows have faded (DL27's
    /// retirement guarantees). The row the visible cell presents draws that
    /// cell's renderer instead.
    private func refreshRings() {
        let presented = model.presentedSlot(in: flyout.rows, reduceMotion: flyout.reduceMotion).map { flyout.rows[$0].id }
        let live = Dictionary(flyout.rows.compactMap { item -> (DownloadLibraryIdentity, BrowserDownload)? in
            guard item.id != presented, let download = item.download, item.downloadStatus?.isInProgress == true else { return nil }
            return (DownloadLibraryIdentity(download), download)
        }, uniquingKeysWith: { first, _ in first })
        for (identity, ring) in rings where live[identity] == nil { ring.reset(); rings[identity] = nil }
        host.layoutSubtreeIfNeeded()
        for download in live.values {
            guard let ring = ring(for: .download(download)) else { continue }
            ring.colors = badge.colors
            ring.update([download], profiles: ringProfiles, enabled: ringsShown && window != nil)
        }
    }
    private func loadImage(_ item: LibraryFlyoutItem, _ completion: @escaping @MainActor (NSImage?) -> Void) -> () -> Void {
        switch item {
        case .download(let download):
            guard let url = downloadFileURL?(download) else { completion(nil); return {} }
            return LibraryFlyoutImages.fileThumbnail(url, completion: completion)
        case .file(let file):
            return LibraryFlyoutImages.fileThumbnail(file.url, completion: completion)
        case .capture(let capture):
            guard let store = captureStore else { completion(nil); return {} }
            let task = Task { @MainActor in
                let data = try? await store.thumbnail(for: capture)
                guard !Task.isCancelled else { return }
                completion(data.flatMap(NSImage.init(data:)))
            }
            return { task.cancel() }
        }
    }

    // MARK: Badge

    ///
    ///
    private func visibleItemChanged(_ id: String?) {
        setVisibleBadgeHovered(false)
        if let id, let item = lifecycle.visibleItem {
            model.visibleItem = item
            model.show(id, compact: Self.compact(item))
        } else {
            model.hide()
        }
        refreshBadgeRenderer()
        refreshRings()
        updateHover()
    }
    ///
    private static func compact(_ item: LibraryFlyoutItem) -> Bool {
        item.file != nil || item.capture != nil || item.downloadStatus == .completed
    }
    private func refreshVisibleItem() {
        let item = lifecycle.visibleItem
        if let item, model.visibleItem != item { model.visibleItem = item }
        refreshBadgeRenderer()
    }
    /// Feeds the visible cell's renderer the visible download alone: while it
    /// downloads, and on completion so DL27's completion transaction plays
    /// and retires. Any other state, or no visible download, retires it at
    /// once (BadgingIcon's EmptyView for paused, pending, failed, cancelled).
    private func refreshBadgeRenderer() {
        guard badging, let download = lifecycle.visibleItem?.download,
              download.status == .downloading || download.status == .completed else { badge.reset(); return }
        badge.update([download], profiles: ringProfiles, enabled: window != nil)
    }

    // MARK: Hover and expansion

    /// The collapsed visible cell: 40 × 56 at the cell stack's offset, moved
    /// by its pose (`onHover` sits inside the pose's geometry effects).
    var visibleCellRect: NSRect? {
        guard model.visibleBadge != nil, !flyout.expanded else { return nil }
        let button = buttonRect, pose = model.cell, offset = LibraryEntryLayout.overlayOffset
        let width = LibraryEntryLayout.collapsedCellWidth * pose.scale, height = LibraryEntryLayout.cellHeight * pose.scale
        let centre = NSPoint(x: button.minX + offset.width + LibraryEntryLayout.collapsedCellWidth / 2 + pose.x,
                             y: button.maxY + offset.height - LibraryEntryLayout.cellHeight / 2 + pose.y)
        return NSRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
    }
    ///
    /// the button; the dock to its right, as tall as the button; the flyout
    /// from the button's corner across the host.
    var hoverRegions: [LibraryFlyoutHoverTracker.Region: NSRect] {
        let button = buttonRect, host = hostRect
        return [.button: button,
                .dock: NSRect(x: button.maxX, y: button.minY, width: max(0, host.width - button.maxX), height: button.height),
                .flyout: NSRect(x: button.minX, y: host.minY, width: max(0, host.width - button.minX), height: host.height)]
    }
    private func updateHover() {
        guard !updatingHover else { return }
        updatingHover = true
        defer { updatingHover = false }
        var passes = 0
        repeat {
            passes += 1
            hover.update(pointer: lastPointer, rects: hoverRegions, tracked: flyout.trackedRegions)
        } while passes < 4 && hover.needsPass(tracked: flyout.trackedRegions, rects: hoverRegions)
        refreshRowHover()
    }
    private func regionChanged(_ region: LibraryFlyoutHoverTracker.Region, _ hovered: Bool) {
        switch region {
        case .button: flyout.setButtonHovered(hovered)
        case .flyout: flyout.setFlyoutHovered(hovered)
        //
        case .dock: if hovered { flyout.setFlyoutHovered(false) }
        }
        updateHover()
    }
    private func setVisibleBadgeHovered(_ hovered: Bool) {
        guard flyout.visibleBadgeHovered != hovered else { return }
        flyout.setVisibleBadgeHovered(hovered)
    }
    private func refreshRowHover() {
        let row = lastPointer.flatMap { flyout.row(at: $0)?.id }
        if flyout.hoveredRow != row { flyout.hoveredRow = row }
    }
    private func expansionChanged(_ expanded: Bool) {
        updateTooltip(lastPointer)
        refreshRowHover()
        flyout.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        //
        // onDidExpandFlyout dismisses a finished visible download (case 9).
        if let item = lifecycle.visibleItem { model.resetPose(compact: Self.compact(item)) }
        if expanded { lifecycle.flyoutDidExpand() }
        ringGeneration &+= 1
        if expanded {
            ringsShown = true
        } else {
            let token = ringGeneration
            model.after(LibraryFlyoutLayout.ringRetirement) { [weak self] in
                guard let self, self.ringGeneration == token else { return }
                self.ringsShown = false
                self.refreshRings()
            }
        }
        refreshRings()
        onFlyoutExpansion?(expanded, flyout.rows.count)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    // MARK: Accessibility

    ///
    /// each expanded row, or the collapsed visible badge cell.
    override func accessibilityChildren() -> [Any]? {
        var children: [Any] = [homeElement]
        let ids = Set(flyout.rows.map(\.id))
        rowElements = rowElements.filter { ids.contains($0.key) }
        cancelElements = cancelElements.filter { ids.contains($0.key) }
        if flyout.expanded {
            for item in flyout.rows.reversed() { children.append(rowElement(item)) }
        } else if let element = visibleBadgeElement() {
            children.append(element)
        }
        return children
    }
    var homeAccessibilityElement: LibraryEntryElement { homeElement }
    private func rowElement(_ item: LibraryFlyoutItem) -> LibraryEntryElement {
        let element = rowElements[item.id] ?? LibraryEntryElement(host: self, label: item.accessibilityLabel)
        rowElements[item.id] = element
        element.setAccessibilityLabel(item.accessibilityLabel)
        element.rect = { [weak self] in self?.flyout.rowFrame(item.id) ?? .zero }
        element.press = { [weak self] in self?.tapRow(item.id) ?? false }
        if item.downloadStatus?.isInProgress == true {
            let cancel = cancelElements[item.id] ?? LibraryEntryElement(host: self, label: LibraryFlyoutMenu.cancelTitle)
            cancelElements[item.id] = cancel
            cancel.parentElement = element
            cancel.rect = { [weak self] in self?.flyout.cancelFrame(item.id) ?? .zero }
            cancel.press = { [weak self] in self?.cancel(item.id) ?? false }
            element.children = { [cancel] }
        } else { element.children = { [] } }
        return element
    }
    private func visibleBadgeElement() -> LibraryEntryElement? {
        guard model.visibleBadge != nil, let item = lifecycle.visibleItem else { return nil }
        let label = item.accessibilityLabel
        let element = badgeElement ?? LibraryEntryElement(host: self, label: label)
        badgeElement = element
        element.setAccessibilityLabel(label)
        element.rect = { [weak self] in self?.visibleCellRect ?? .zero }
        element.press = { [weak self] in self?.tapVisibleBadge() ?? false }
        return element
    }

    // MARK: Pointer

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        if buttonRect.contains(local) || flyout.row(at: local) != nil || visibleCellRect?.contains(local) == true { return self }
        return nil
    }
    override func pointerDidMove(to point: NSPoint?) {
        lastPointer = point
        if let cell = visibleCellRect, let point, cell.contains(point) { setVisibleBadgeHovered(true) }
        else if !flyout.expanded { setVisibleBadgeHovered(false) }
        updateHover()
        updateTooltip(point)
    }

    // MARK: Rows

    private func item(_ id: String) -> LibraryFlyoutItem? {
        flyout.rows.first { $0.id == id } ?? (lifecycle.visibleID == id ? lifecycle.visibleItem : nil)
    }
    private func perform(_ action: LibraryFlyoutAction) -> Bool { onItemAction?(action) ?? false }

    ///
    ///
    ///
    /// download, the Library's Downloads page for any other
    /// (onDidSelectInProgressDownload). A completed download is previewable
    ///
    /// Parc adaptation: a capture's preview is the Library's (Media page), so a
    /// capture opens that page.
    @discardableResult func tapRow(_ id: String) -> Bool {
        guard let item = item(id) else { return false }
        if flyout.animating { click(); return true }
        guard flyout.expanded else { return false }
        switch item {
        case .capture(let capture): return perform(.showCapture(capture))
        case .file(let file): return perform(.file(file, .open))
        case .download(let download):
            guard download.status == .completed else { onOpen?(.downloads); return true }
            if LibraryFlyoutText.canPreview(download), previewDownload(download, rowID: id) { return true }
            return perform(.download(download, .open))
        }
    }
    /// The visible cell's tap: shouldShowDetails is false, so no preview, and
    /// `onDidTapItem` acts only while expanded.
    @discardableResult func tapVisibleBadge() -> Bool {
        if flyout.animating { click(); return true }
        return false
    }
    ///
    @discardableResult func cancel(_ id: String) -> Bool {
        guard let download = item(id)?.download, LibraryFlyoutDownloadStatus(download).isInProgress else { return false }
        return perform(.download(download, .cancel))
    }
    func rowMenu(_ id: String) -> NSMenu? {
        guard let item = item(id) else { return nil }
        return LibraryFlyoutMenu.make(item, fileURL: item.file?.url ?? item.download.flatMap { downloadFileURL?($0) }) { [weak self] action in
            _ = self?.perform(action)
        }
    }
    private func visibleBadgeRowID() -> String? {
        guard model.visibleBadge != nil, let id = lifecycle.visibleID, lifecycle.visibleItem != nil else { return nil }
        return id
    }
    private func pressTarget(_ point: NSPoint) -> Press? {
        if let item = flyout.cancelHit(point) { return .cancel(item.id) }
        if let item = flyout.row(at: point) { return .row(item.id) }
        if visibleCellRect?.contains(point) == true { return .badge }
        return nil
    }

    //

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: Self.menuTitle)
        menu.autoenablesItems = false
        let header = NSMenuItem(title: Self.menuTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for source in LibraryBadgeSource.allCases {
            let item = MenuAction.item(source.title) { [weak self] in
                guard let self else { return }
                self.preferences.setEnabled(!self.preferences.isEnabled(source), source)
            }
            item.state = preferences.isEnabled(source) ? .on : .off
            item.isEnabled = source.isAvailable
            menu.addItem(item)
        }
        return menu
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if buttonRect.contains(point) { return makeMenu() }
        switch pressTarget(point) {
        case .row(let id)?, .cancel(let id)?: return rowMenu(id)
        case .badge?: return visibleBadgeRowID().flatMap(rowMenu)
        case nil: return nil
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self); return
        }
        if !buttonRect.contains(point), event.type == .leftMouseDown, let target = pressTarget(point) {
            press = target; pressStart = point; return
        }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let target = press else { super.mouseDragged(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        guard let start = pressStart, hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
        // A drag ends the press: no tap follows it.
        press = nil; pressStart = nil
        switch target {
        case .row(let id): beginItemDrag(id, event: event)
        case .badge: if let id = visibleBadgeRowID() { beginItemDrag(id, event: event) }
        case .cancel: break
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let target = press else { super.mouseUp(with: event); return }
        press = nil; pressStart = nil
        guard pressTarget(convert(event.locationInWindow, from: nil)) == target else { return }
        switch target {
        case .row(let id): tapRow(id)
        case .cancel(let id): cancel(id)
        case .badge: tapVisibleBadge()
        }
    }
    //

    ///
    /// `localURL` as a file URL whatever its status (an unfinished one's path
    /// does not exist yet) and a capture through CapturePasteboardWriter.
    /// Parc drags a completed download through DL28's DownloadFileDrag (copy
    /// only, lazy, revalidated against the original item) and a capture as its
    /// PNG; an unfinished download drags nothing.
    func dragWriter(for id: String) -> NSPasteboardWriting? {
        guard let item = item(id), let parent = window else { return nil }
        switch item {
        case .download(let original):
            guard original.status == .completed else { return nil }
            let identity = DownloadLibraryIdentity(original)
            guard let drag = DownloadFileDrag(resolve: { [weak self, weak parent] in
                guard let self, let parent, self.window === parent, parent.attachedSheet == nil,
                      let current = self.downloads.first(where: { DownloadLibraryIdentity($0) == identity }),
                      current.status == .completed else { return nil }
                return self.downloadFileURL?(current)
            }) else { return nil }
            fileDrags.append(drag)
            return drag.item
        case .file(let file):
            return file.url as NSURL
        case .capture(let capture):
            guard let store = captureStore, store.contains(capture) else { return nil }
            let drag = LibraryCaptureDrag(load: { try? await store.data(for: capture) },
                valid: { [weak self, weak store, weak parent] in
                    guard let self, let store, let parent, self.window === parent,
                          self.captureStore === store, store.contains(capture) else { return false }
                    return true
                })
            captureDrags.append(drag)
            return drag.item
        }
    }
    private func beginItemDrag(_ id: String, event: NSEvent) {
        guard let writer = dragWriter(for: id) else { return }
        let frame = (flyout.expanded ? flyout.rowFrame(id) : visibleCellRect) ?? buttonRect
        let dragging = NSDraggingItem(pasteboardWriter: writer)
        dragging.setDraggingFrame(frame, contents: dragImage(frame, id: id))
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
    /// The cell as drawn (SwiftUI's drag preview is the view itself), or its
    /// image when the rendering cannot be cached.
    private func dragImage(_ rect: NSRect, id: String) -> NSImage {
        if let bitmap = bitmapImageRepForCachingDisplay(in: rect) {
            cacheDisplay(in: rect, to: bitmap)
            let image = NSImage(size: rect.size); image.addRepresentation(bitmap)
            return image
        }
        return flyout.images[id] ?? NSImage(size: rect.size)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // The receiver owns its copy; a move never removes the original.
        retireDrags()
    }
    private func retireDrags() {
        fileDrags.forEach { $0.invalidate() }; fileDrags.removeAll()
        captureDrags.forEach { $0.invalidate() }; captureDrags.removeAll()
    }

    //

    /// ItemPreviewPresenter builds BaseHomeComponents.MediaPreviewWindow
    ///
    /// same) and presents it on the cell's window with the cell's frame as the
    /// source, no source image, and the Library button's frame as the frame it
    ///
    /// MediaPreviewWindow is DL23/DL24's DownloadLibraryPreview. The file is
    /// checked off the main thread as the Library does (DownloadFileActivation):
    /// readable media previews, anything else opens, an unreadable file does
    /// nothing.
    ///
    /// Previous/Next walk ItemPreviewPresenter's items: `present` reads the
    /// tapped cell's scoped store state once (Store state subject +0x68), and
    ///
    ///
    ///
    /// screenshot files, and files or completed downloads whose URL
    /// `canPresentHomePreview`, newest first. MediaPreviewWindow takes that
    /// list as it stands at the tap. Parc adaptation: a capture previews on
    /// the Library's Media page, so Parc's list holds the previewable
    /// completed download rows; each step resolves the item again.
    @discardableResult func previewDownload(_ original: BrowserDownload, rowID: String) -> Bool {
        guard let parent = window, parent.attachedSheet == nil, let url = downloadFileURL?(original) else { return false }
        previewGeneration &+= 1
        let token = previewGeneration, identity = DownloadLibraryIdentity(original)
        let source = flyout.rowFrame(rowID).map { convert($0, to: nil) }
        let order = flyout.rows.compactMap { item -> DownloadLibraryIdentity? in
            guard let download = item.download, download.status == .completed, LibraryFlyoutText.canPreview(download) else { return nil }
            return DownloadLibraryIdentity(download)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let route = DownloadFileActivation.inspect(url)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.previewGeneration == token, self.window === parent, parent.attachedSheet == nil,
                          let current = self.downloads.first(where: { DownloadLibraryIdentity($0) == identity }),
                          current.status == .completed, self.downloadFileURL?(current) == url else { return }
                    switch route {
                    case .preview: self.presentPreview(current, url: url, order: order, source: source, in: parent)
                    case .open: _ = self.perform(.download(current, .open))
                    case .unavailable: break
                    }
                }
            }
        }
        return true
    }
    private func presentPreview(_ item: BrowserDownload, url: URL, order: [DownloadLibraryIdentity], source: NSRect?, in parent: NSWindow) {
        closePreview()
        let controller = DownloadLibraryPreview()
        preview = controller; previewIdentity = DownloadLibraryIdentity(item); previewURL = url; previewOrder = order
        let current: () -> BrowserDownload? = { [weak self] in
            guard let self, let identity = self.previewIdentity else { return nil }
            return self.downloads.first { DownloadLibraryIdentity($0) == identity }
        }
        controller.onMove = { [weak self, weak controller] forward in
            guard let self, let controller, self.preview === controller,
                  case let (item, url)? = self.previewNeighbour(forward: forward) else { return }
            self.previewIdentity = DownloadLibraryIdentity(item); self.previewURL = url
            self.updatePreview(controller, item, url: url)
        }
        controller.onOpen = { [weak self, weak controller] in
            guard let self, self.preview === controller, let item = current() else { return }
            _ = self.perform(.download(item, .open))
        }
        controller.onCopy = { [weak self, weak controller] in
            guard let self, self.preview === controller, let item = current() else { return }
            _ = self.perform(.download(item, .copyFile))
        }
        controller.onMenu = { [weak self, weak controller] in
            guard let self, self.preview === controller, let item = current() else { return nil }
            return LibraryFlyoutMenu.make(.download(item), fileURL: self.downloadFileURL?(item)) { [weak self] action in
                _ = self?.perform(action)
            }
        }
        controller.onClosed = { [weak self, weak controller] in
            guard let self, self.preview === controller else { return }
            self.preview = nil; self.previewIdentity = nil; self.previewURL = nil; self.previewOrder = []
        }
        controller.sourceRect = { source }
        updatePreview(controller, item, url: url)
        controller.present(on: parent)
        // Closing returns to the Library button (the presenter's view).
        controller.sourceRect = { [weak self] in self.map { $0.convert($0.buttonRect, to: nil) } }
    }
    /// The nearest item of the presented list before or after the current
    /// one that is still the same completed download with its file.
    private func previewNeighbour(forward: Bool) -> (BrowserDownload, URL)? {
        guard let identity = previewIdentity, let index = previewOrder.firstIndex(of: identity) else { return nil }
        let candidates = forward ? Array(previewOrder[(index + 1)...]) : Array(previewOrder[..<index].reversed())
        for candidate in candidates {
            if let item = downloads.first(where: { DownloadLibraryIdentity($0) == candidate }), item.status == .completed,
               let url = downloadFileURL?(item) { return (item, url) }
        }
        return nil
    }
    private func updatePreview(_ controller: DownloadLibraryPreview, _ item: BrowserDownload, url: URL) {
        let name = item.path.isEmpty ? item.name : URL(fileURLWithPath: item.path).lastPathComponent
        let index = previewOrder.firstIndex(of: DownloadLibraryIdentity(item)) ?? 0
        controller.update(url: url, title: name, ordinal: index + 1, count: max(1, previewOrder.count), canOpen: item.canOpen,
                          canMovePrevious: previewNeighbour(forward: false) != nil, canMoveNext: previewNeighbour(forward: true) != nil)
    }
    /// The previewed download must stay the same completed file; its
    /// neighbours are resolved again.
    private func revalidatePreview() {
        guard let controller = preview, let identity = previewIdentity else { return }
        guard let current = downloads.first(where: { DownloadLibraryIdentity($0) == identity }), current.status == .completed,
              let url = previewURL, downloadFileURL?(current) == url else { closePreview(); return }
        updatePreview(controller, current, url: url)
    }
    private func closePreview() {
        previewGeneration &+= 1
        let controller = preview
        preview = nil; previewIdentity = nil; previewURL = nil; previewOrder = []
        controller?.onClosed = nil; controller?.close()
    }

    //

    ///
    ///
    ///
    private func tooltip(at point: NSPoint) -> TooltipConfiguration? {
        if buttonRect.contains(point) { return buttonTooltip }
        if let item = flyout.cancelHit(point), let rect = flyout.cancelFrame(item.id) { return Self.tooltip(LibraryFlyoutMenu.cancelTitle, rect: rect) }
        if let item = flyout.row(at: point), let rect = flyout.rowFrame(item.id) { return Self.tooltip(item.title, rect: rect) }
        if let rect = visibleCellRect, rect.contains(point), let id = visibleBadgeRowID(), let item = item(id) {
            return Self.tooltip(item.title, rect: rect)
        }
        return nil
    }
    /// HomeButtonBadgingViewState.homeKeyboardShortcut is viewLibrary's live
    ///
    private var buttonTooltip: TooltipConfiguration {
        Self.tooltip(Self.tooltipText, shortcut: .command("viewLibrary:"), rect: buttonRect)
    }
    private static func tooltip(_ text: String, shortcut: TooltipConfiguration.Shortcut? = nil, rect: NSRect) -> TooltipConfiguration {
        TooltipConfiguration(text, shortcut: shortcut, anchorRect: rect)
    }
    /// The parts are drawn, not subviews, so the entry's one tooltip follows
    /// the part under the pointer. Between parts it keeps the last one, which
    /// shows nothing there because no part takes the pointer; once the pointer
    /// leaves, the button's is restored for the next entry.
    private func updateTooltip(_ point: NSPoint?) {
        guard let point else { parcTooltip = buttonTooltip; return }
        if let configuration = tooltip(at: point) { parcTooltip = configuration }
    }
}
