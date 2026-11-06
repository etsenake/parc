import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

//
//
//
//
//
//
// value cites the flyout contract (claude-downloads-rea/flyout/CONTRACT.md);
// [I] marks an inference and "Parc adaptation" a recorded difference.

///
enum LibraryFlyoutDownloadStatus: Equatable {
    case inProgress(Double?), paused, notStarted, completed, failed, cancelled
    init(_ download: BrowserDownload) {
        switch download.status {
        case .downloading:
            self = .inProgress(download.totalBytes > 0
                ? min(1, max(0, Double(download.receivedBytes) / Double(download.totalBytes))) : nil)
        case .paused: self = .paused
        case .pending: self = .notStarted
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }
    var isInProgress: Bool { if case .inProgress = self { return true }; return false }
    ///
    /// with payload 1…3).
    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

/// `HomeBadgingFile` (`id`, `dateCreated`, `title`, `path`, `isScreenshot`).
/// Documents, Desktop and Screenshots each contribute folder files; a Desktop
/// screenshots location still tags screenshot-named files as the Screenshots
/// source so that source can be toggled on its own.
struct LibraryFlyoutFile: Equatable {
    let url: URL
    let dateCreated: Date
    let isScreenshot: Bool
    let source: LibraryBadgeSource
    var title: String { url.lastPathComponent }
    var path: String { url.path }
}

///
enum LibraryFlyoutFiles {
    static func defaultFolders() -> [(LibraryBadgeSource, URL)] {
        let manager = FileManager.default
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let setting = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let screenshots = setting.flatMap { path -> URL? in
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded, isDirectory: true) : nil
        } ?? desktop
        return [(.documents, documents), (.desktop, desktop), (.screenshots, screenshots)]
    }
    static func isScreenshotName(_ name: String) -> Bool {
        name.hasPrefix("Screen Shot") || name.hasPrefix("Screenshot")
    }
    static func scan(folders: [(LibraryBadgeSource, URL)] = defaultFolders()) -> [LibraryFlyoutFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isHiddenKey, .isAliasFileKey, .isPackageKey,
            .creationDateKey, .contentModificationDateKey,
        ]
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        var files: [LibraryFlyoutFile] = []
        for (source, folder) in folders {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            let screenshotsOnDesktop = source == .screenshots && folder.standardizedFileURL.path == desktopPath
            for url in children {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isHidden != true, values.isAliasFile != true else { continue }
                let isPackage = values.isPackage == true
                if values.isRegularFile != true && !isPackage { continue }
                let name = url.lastPathComponent
                if screenshotsOnDesktop && !isScreenshotName(name) { continue }
                let created = values.creationDate ?? values.contentModificationDate ?? .distantPast
                    files.append(LibraryFlyoutFile(
                    url: url, dateCreated: created,
                    isScreenshot: source == .screenshots || isScreenshotName(name), source: source))
            }
        }
        return files.sorted {
            $0.path != $1.path ? $0.path < $1.path : $0.source.rawValue < $1.source.rawValue
        }
    }
}

///
/// descriptor per source folder with delete/write/rename events, so folder
/// files are rescanned when a folder changes instead of on a polling clock.
@MainActor
final class LibraryFlyoutFolderMonitor {
    /// An iCloud Desktop or Documents folder or a privacy check can hold
    /// `open` for seconds. One serial queue keeps that off the main thread
    /// without leaving another blocked thread behind on every activation.
    private static let openQueue = DispatchQueue(label: "org.parc.library-flyout-folders", qos: .utility)
    /// One source per watched folder. A folder without one (missing,
    /// unmounted, or moved since) is opened again by the next `watch`, and
    /// the others keep watching meanwhile.
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var requested: [String] = []
    /// Folders macOS refused (no privacy access): not asked again on every
    /// activation, only when the window's monitor is rebuilt.
    private var refused: Set<String> = []
    /// Folders whose descriptors are being opened on `openQueue`.
    private var opening: Set<String> = []
    /// Bumped when the requested folders change and by `cancel`; descriptors
    /// from a superseded open are closed instead of watched.
    private var openGeneration: UInt64 = 0
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    deinit { sources.values.forEach { $0.cancel() } }

    func watch(_ folders: [URL]) {
        var paths: [String] = []
        for folder in folders {
            let path = folder.standardizedFileURL.path
            if !paths.contains(path) { paths.append(path) }
        }
        if paths != requested {
            requested = paths
            openGeneration &+= 1; opening = []
            for (path, source) in sources where !paths.contains(path) { source.cancel(); sources[path] = nil }
        }
        let missing = paths.filter { sources[$0] == nil && !opening.contains($0) && !refused.contains($0) }
        guard !missing.isEmpty else { return }
        opening.formUnion(missing)
        let generation = openGeneration
        Self.openQueue.async { [weak self] in
            let results = missing.map { path -> (descriptor: Int32, error: Int32) in
                let descriptor = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
                return (descriptor, descriptor < 0 ? errno : 0)
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.openGeneration == generation else {
                        for result in results where result.descriptor >= 0 { Darwin.close(result.descriptor) }
                        return
                    }
                    self.opening.subtract(missing)
                    var added = false
                    for (path, result) in zip(missing, results) {
                        if result.descriptor >= 0 {
                            self.observe(path, result.descriptor); added = true
                        } else if result.error == EPERM || result.error == EACCES {
                            self.refused.insert(path)
                        }
                    }
                    // The scan that asked for this watch ran before these
                    // folders were watched; one more catches a change made in
                    // between. A folder that keeps failing adds nothing.
                    if added { self.scheduleChange() }
                }
            }
        }
    }

    private func observe(_ path: String, _ descriptor: Int32) {
        guard sources[path] == nil else { Darwin.close(descriptor); return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .revoke], queue: .main)
        source.setCancelHandler { Darwin.close(descriptor) }
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                if !source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                    source.cancel(); self.sources[path] = nil
                }
                self.scheduleChange()
            }
        }
        source.resume()
        sources[path] = source
    }

    func cancel() {
        pending?.cancel(); pending = nil
        openGeneration &+= 1; opening = []
        sources.values.forEach { $0.cancel() }
        sources = [:]; requested = []; refused = []
    }

    /// One rescan shortly after the first change of a burst (an atomic save,
    /// a screenshot's temporary file); later changes in the burst join it.
    private func scheduleChange() {
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}

///
enum LibraryFlyoutItem: Identifiable, Equatable {
    case download(BrowserDownload)
    case capture(SavedCapture)
    case file(LibraryFlyoutFile)

    var id: String {
        switch self {
        case .download(let item): return "download:" + item.id
        case .capture(let item): return "capture:" + item.id.uuidString
        case .file(let item): return "file:" + item.path
        }
    }
    ///
    ///
    var dateCreated: Date {
        switch self {
        case .download(let item): return item.startedAt ?? .distantPast
        case .capture(let item): return item.createdAt
        case .file(let item): return item.dateCreated
        }
    }
    /// The file name a download's `localURL.lastPathComponent` names.
    private static func fileName(_ item: BrowserDownload) -> String {
        item.path.isEmpty ? item.name : URL(fileURLWithPath: item.path).lastPathComponent
    }
    ///
    /// the download's file name, or the folder file's name.
    var title: String {
        switch self {
        case .download(let item): return Self.fileName(item)
        case .capture(let item): return item.title.isEmpty ? item.sourceURL : item.title
        case .file(let item): return item.title
        }
    }
    ///
    ///
    var accessibilityLabel: String {
        switch self {
        case .download(let item): return "Download \u{2014} " + Self.fileName(item)
        case .capture(let item): return "Capture \u{2014} " + item.title
        case .file(let item): return "File \u{2014} " + item.title
        }
    }
    ///
    ///
    var uniqueKey: String {
        switch self {
        case .download(let item): return item.path.isEmpty ? "download-record:" + item.id : "file:" + item.path
        case .capture(let item): return "capture-asset:" + item.assetName
        case .file(let item): return "file:" + item.path
        }
    }
    var download: BrowserDownload? { if case .download(let item) = self { return item }; return nil }
    var capture: SavedCapture? { if case .capture(let item) = self { return item }; return nil }
    var file: LibraryFlyoutFile? { if case .file(let item) = self { return item }; return nil }
    var downloadStatus: LibraryFlyoutDownloadStatus? { download.map(LibraryFlyoutDownloadStatus.init) }
    var downloadIdentity: DownloadLibraryIdentity? { download.map(DownloadLibraryIdentity.init) }
    ///
    ///
    var showsImage: Bool { file != nil || capture != nil || downloadStatus == .completed }
    /// A changed file or capture revision needs a new image.
    var imageKey: String {
        switch self {
        case .download(let item): return id + "|" + item.path + "|\(item.receivedBytes)"
        case .capture(let item): return id + "|" + item.revision.uuidString
        case .file(let item): return id + "|\(item.dateCreated.timeIntervalSince1970)"
        }
    }
}

enum LibraryFlyoutItems {
    /// The flyout lists HomeButtonBadgingViewState's `items`: the first
    ///
    ///
    static let limit = 4
    static func merge(downloads: [BrowserDownload], captures: [SavedCapture],
                      files: [LibraryFlyoutFile] = []) -> [LibraryFlyoutItem] {
        var seen = Set<String>(), items: [LibraryFlyoutItem] = []
        for item in downloads.map(LibraryFlyoutItem.download)
            + captures.map(LibraryFlyoutItem.capture)
            + files.map(LibraryFlyoutItem.file)
        where seen.insert(item.uniqueKey).inserted { items.append(item) }
        // Equal dates keep their source order (Parc: a stable sort).
        return items.enumerated().sorted {
            $0.element.dateCreated != $1.element.dateCreated ? $0.element.dateCreated > $1.element.dateCreated : $0.offset < $1.offset
        }.map(\.element)
    }
}

///
/// `SidebarItemBackground`, `ForegroundPrimary`, `ForegroundSecondary` and
///
///
struct LibraryFlyoutColors: Equatable {
    let itemBackground: NSColor
    let primary: NSColor
    let secondary: NSColor
    let shadow: NSColor
    static func standard(dark: Bool) -> LibraryFlyoutColors {
        func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
            NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
        }
        return dark
            ? LibraryFlyoutColors(itemBackground: p3(0.980, 0.984, 1.000, 0.10), primary: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.8),
                                  secondary: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.5), shadow: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
            : LibraryFlyoutColors(itemBackground: p3(0.055, 0.059, 0.063, 0.05), primary: p3(0.0549, 0.0588, 0.0627, 0.9),
                                  secondary: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5), shadow: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.2))
    }
}

/// HomeBadgingCell and HomeBadgingCellStack geometry and motion.
enum LibraryFlyoutLayout {
    ///
    static let iconSize: CGFloat = 40
    ///
    static let detailInset: CGFloat = 12
    ///
    /// 8 × 0.5 = 4).
    static let padding: CGFloat = 4
    ///
    static let cornerRadius: CGFloat = 12
    /// The cancel button: 24 × 24, radius 6, then a 2-point Spacer
    ///
    static let cancelSize: CGFloat = 24
    static let cancelRadius: CGFloat = 6
    static let cancelTrailing: CGFloat = 2
    ///
    /// outline: radius 8 − 1, 1-point stroke dashed [3, 2] at opacity 0.3,
    ///
    static let imageRadius: CGFloat = 6
    static let captureOutlineRadius: CGFloat = 7
    static let captureOutlinePadding: CGFloat = 1
    ///
    /// others 56.
    static func hiddenOffset(reverseIndex: Int) -> CGFloat { reverseIndex == 0 ? 20 : 56 }
    ///
    /// response and the isAnimating window.
    static let animationDuration: TimeInterval = 0.15
    ///
    static func stagger(reverseIndex: Int) -> TimeInterval { min(max(Double(reverseIndex) / 4, 0), 1) * 0.05 }
    static func animation(reverseIndex: Int) -> Animation {
        .interactiveSpring(response: animationDuration, dampingFraction: 0.86, blendDuration: 0.25).delay(stagger(reverseIndex: reverseIndex))
    }
    ///
    /// from above and scale 1.5; removal is opacity.
    static let transition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: AnyTransition.offset(x: 0, y: -80).combined(with: .scale(scale: 1.5, anchor: .center))),
        removal: .opacity)
    /// Parc adaptation: a collapsed row's DL27 renderer retires once the
    /// collapse has faded it (the spring is within 0.5% by 0.17 s, after the
    ///
    static let ringRetirement: TimeInterval = 0.25
}

///
/// dock and flyout regions, registered only while tracked, each reporting
/// once its HoverState passes the region's fidelity.
@MainActor final class LibraryFlyoutHoverTracker {
    enum Region: CaseIterable { case button, dock, flyout }
    ///
    static let linger: [Region: TimeInterval] = [.button: 0.15, .dock: 0.5, .flyout: 0.15]
    /// The button and dock report once the pointer has lingered (HoverState
    ///
    static func reportsWhenInside(_ region: Region) -> Bool { region == .flyout }

    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    ///
    /// change of its cached state).
    var onChange: ((Region, Bool) -> Void)?
    private var inside: [Region: Bool] = [:]
    private var lingered: [Region: Bool] = [:]
    private var reported: [Region: Bool] = [:]
    private var tokens: [Region: Int] = [:]
    private(set) var pointer: NSPoint?
    private var rects: [Region: NSRect] = [:]
    private var tracked: Set<Region> = []

    func isHovered(_ region: Region) -> Bool { reported[region] ?? false }

    /// The pointer (nil: gone), each region's rect and which regions are
    /// registered. Unregistering (HoverRegionTracker.unregisterRegion
    ///
    ///
    /// reports that it is no longer hovered. A newly tracked one starts from
    /// `none`.
    func update(pointer: NSPoint?, rects: [Region: NSRect], tracked: Set<Region>) {
        self.pointer = pointer; self.rects = rects; self.tracked = tracked
        for region in Region.allCases { evaluate(region) }
    }
    /// Whether registration or a region's rect changed since the last update.
    func needsPass(tracked: Set<Region>, rects: [Region: NSRect]) -> Bool { tracked != self.tracked || rects != self.rects }

    private func evaluate(_ region: Region) {
        guard tracked.contains(region) else {
            if inside[region] == true { tokens[region, default: 0] &+= 1 }
            inside[region] = false; lingered[region] = false
            report(region)
            return
        }
        let now = pointer.map { rects[region]?.contains($0) ?? false } ?? false
        if now != (inside[region] ?? false) {
            inside[region] = now; lingered[region] = false
            tokens[region, default: 0] &+= 1
            if now {
                let token = tokens[region]!
                after(Self.linger[region]!) { [weak self] in
                    guard let self, self.tokens[region] == token, self.inside[region] == true else { return }
                    self.lingered[region] = true
                    self.report(region)
                }
            }
        }
        report(region)
    }
    private func report(_ region: Region) {
        let hovered = Self.reportsWhenInside(region) ? (inside[region] ?? false) : (lingered[region] ?? false)
        guard (reported[region] ?? false) != hovered else { reported[region] = hovered; return }
        reported[region] = hovered
        onChange?(region, hovered)
    }
}

/// HomeBadgingFeatureState's hover and expansion fields with the reducer's
/// rules, and the cell stack's per-row presentation state.
@MainActor final class LibraryFlyoutModel: ObservableObject {
    /// Newest first; the view draws them oldest at the top, newest beside the
    /// button.
    @Published private(set) var rows: [LibraryFlyoutItem] = []
    /// `displayAsExpanded` = canExpand && eligibleToExpand && !items.isEmpty
    ///
    @Published private(set) var expanded = false
    /// The cell stack's `animationUUID != nil`: true for animationDuration
    ///
    @Published private(set) var animating = false
    ///
    @Published var hoveredRow: String?
    @Published var containerWidth: CGFloat = 228
    ///
    /// cell stack reads no reduce-motion environment): rows fade in place and
    /// the visible badge fades at the button instead of travelling.
    @Published var reduceMotion = false
    @Published private(set) var images: [String: NSImage] = [:]
    /// Row and cancel-button frames as the layout reports them (including the
    /// rows' current offsets); hit testing uses `rowFrame`/`cancelFrame`.
    @Published var measuredRowFrames: [String: CGRect] = [:]
    @Published var measuredCancelFrames: [String: CGRect] = [:]
    /// The cell stack's bottom-leading corner in the canvas: the button's
    /// bottom-left offset (−4, −30).
    var stackOrigin = CGPoint.zero
    @Published var colors = LibraryFlyoutColors.standard(dark: false)

    private(set) var buttonHovered = false
    private(set) var flyoutHovered = false
    private(set) var visibleBadgeHovered = false
    private(set) var eligibleToExpand = false
    /// The window's `canExpandHomeBadge` (Parc adaptation: the window's
    ///
    var canExpand = false { didSet { if canExpand != oldValue { updateExpanded() } } }
    /// `lastClosedArcHomeAt`: hover within 100 ms of the Library closing
    ///
    var libraryClosedAt: Date?
    var now: () -> Date = Date.init
    var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    /// Loads a row image (QuickLook icon or thumbnail for a file, the capture's
    /// thumbnail); returns a cancel.
    var imageLoader: (LibraryFlyoutItem, @escaping @MainActor (NSImage?) -> Void) -> (() -> Void) = { _, completion in
        completion(nil); return {}
    }
    /// Expansion changes for the sidebar's content mask and the entry.
    var onExpansionChange: ((Bool) -> Void)?
    private var animationToken = 0
    private var loads: [String: (key: String, cancel: () -> Void)] = [:]

    var expandedCellWidth: CGFloat {
        min(containerWidth, LibraryEntryLayout.maximumWidth) - LibraryEntryLayout.expandedInset
    }

    func setRows(_ items: [LibraryFlyoutItem]) {
        let next = Array(items.prefix(LibraryFlyoutItems.limit))
        if next != rows { rows = next }
        if let hoveredRow, !rows.contains(where: { $0.id == hoveredRow }) { self.hoveredRow = nil }
        loadImages()
        updateExpanded()
    }

    // MARK: Hover (HomeBadgingFeature cases 0–2, 17)

    func setButtonHovered(_ hovered: Bool) { buttonHovered = hovered; hoverChanged() }
    func setFlyoutHovered(_ hovered: Bool) { flyoutHovered = hovered; hoverChanged() }
    func setVisibleBadgeHovered(_ hovered: Bool) { visibleBadgeHovered = hovered; hoverChanged() }

    ///
    /// Library closed at most 100 ms ago while something is hovered.
    private func hoverChanged() {
        let hovered = buttonHovered || flyoutHovered || visibleBadgeHovered
        if hovered, let closed = libraryClosedAt, now().timeIntervalSince(closed) * 1000 <= 100 { return }
        eligibleToExpand = hovered
        updateExpanded()
    }

    /// Which hover regions HomeButtonHoverRegionTracker.ViewState registers
    ///
    var trackedRegions: Set<LibraryFlyoutHoverTracker.Region> {
        var regions = Set<LibraryFlyoutHoverTracker.Region>()
        if canExpand { regions.insert(.button) }
        if canExpand && eligibleToExpand { regions.insert(.flyout) }
        if canExpand && eligibleToExpand && !rows.isEmpty { regions.insert(.dock) }
        return regions
    }

    private func updateExpanded() {
        let next = canExpand && eligibleToExpand && !rows.isEmpty
        guard next != expanded else { return }
        expanded = next
        //
        animationToken &+= 1
        let token = animationToken
        animating = true
        after(LibraryFlyoutLayout.animationDuration) { [weak self] in
            guard let self, self.animationToken == token else { return }
            self.animating = false
        }
        if next {
            // onDidExpandFlyout (case 17): the visible badge's hover clears.
            visibleBadgeHovered = false
        } else {
            hoveredRow = nil
        }
        onExpansionChange?(next)
    }

    //

    private func loadImages() {
        let wanted = Dictionary(rows.filter(\.showsImage).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, load) in loads where wanted[id]?.imageKey != load.key {
            load.cancel(); loads[id] = nil
        }
        for id in images.keys where wanted[id] == nil { images[id] = nil }
        for (id, item) in wanted where loads[id] == nil {
            let key = item.imageKey
            loads[id] = (key, {})
            let cancel = imageLoader(item) { [weak self] image in
                guard let self, self.loads[id]?.key == key else { return }
                if let image { self.images[id] = image }
            }
            if loads[id]?.key == key { loads[id] = (key, cancel) } else { cancel() }
        }
    }
    func reset() {
        for load in loads.values { load.cancel() }
        loads.removeAll(); images.removeAll()
    }

    /// A row's expanded slot: 56 points tall, stacked up from the stack's
    /// corner, the newest lowest.
    func rowFrame(_ id: String) -> CGRect? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        let height = LibraryEntryLayout.cellHeight
        return CGRect(x: stackOrigin.x, y: stackOrigin.y - height * CGFloat(index + 1), width: expandedCellWidth, height: height)
    }
    /// The cancel button where the layout put it within its row.
    func cancelFrame(_ id: String) -> CGRect? {
        guard let row = rowFrame(id), let measuredRow = measuredRowFrames[id], let cancel = measuredCancelFrames[id] else { return nil }
        return cancel.offsetBy(dx: row.minX - measuredRow.minX, dy: row.minY - measuredRow.minY)
    }
    /// The row under a point in the canvas, while expanded.
    func row(at point: NSPoint) -> LibraryFlyoutItem? {
        guard expanded else { return nil }
        return rows.first { rowFrame($0.id)?.contains(point) == true }
    }
    func cancelHit(_ point: NSPoint) -> LibraryFlyoutItem? {
        guard expanded else { return nil }
        return rows.first { $0.downloadStatus?.isInProgress == true && cancelFrame($0.id)?.contains(point) == true }
    }
}

// MARK: - Views

private struct LibraryFlyoutRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
private struct LibraryFlyoutCancelFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// A downloading row's DownloadProgressBadge: Parc's DL26/DL27 renderer.
struct LibraryFlyoutRing: NSViewRepresentable {
    let badge: DownloadActivityBadge
    func makeNSView(context: Context) -> DownloadActivityBadge { badge }
    func updateNSView(_ nsView: DownloadActivityBadge, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DownloadActivityBadge, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

///
///
/// (1, 0, −1: radius 1, y −1 [I]) in `Shadow`; a 40 × 40 Rectangle until the
/// image arrives.
private struct LibraryFlyoutIconImage: View {
    let image: NSImage?
    let colors: LibraryFlyoutColors
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: LibraryFlyoutLayout.iconSize, height: LibraryFlyoutLayout.iconSize)
                .mask(RoundedRectangle(cornerRadius: LibraryFlyoutLayout.imageRadius, style: .continuous))
                .shadow(color: Color(nsColor: colors.shadow), radius: 1, x: 0, y: -1)
        } else {
            Rectangle().frame(width: LibraryFlyoutLayout.iconSize, height: LibraryFlyoutLayout.iconSize)
        }
    }
}

///
/// outline, a downloading item's progress ring, a completed download's image,
/// nothing for a paused, pending, failed or cancelled download. The rows and
/// the collapsed visible badge cell both draw it.
struct LibraryFlyoutIcon: View {
    let item: LibraryFlyoutItem
    let image: NSImage?
    let ring: DownloadActivityBadge?
    let colors: LibraryFlyoutColors
    var body: some View {
        HStack(alignment: .center) {
            switch item {
            case .capture:
                LibraryFlyoutIconImage(image: image, colors: colors)
                    .padding(.all, LibraryFlyoutLayout.captureOutlinePadding)
                    .background(RoundedRectangle(cornerRadius: LibraryFlyoutLayout.captureOutlineRadius, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10, dash: [3, 2], dashPhase: 0))
                        .opacity(0.3), alignment: .center)
            case .file:
                LibraryFlyoutIconImage(image: image, colors: colors)
            case .download:
                switch item.downloadStatus {
                case .inProgress?:
                    if let ring { LibraryFlyoutRing(badge: ring) }
                case .completed?: LibraryFlyoutIconImage(image: image, colors: colors)
                default: EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

///
/// a 12-point spacer, title (14 regular, ForegroundPrimary, one line) over
/// subtitle (12, ForegroundSecondary, one line), then either a Spacer or, for
/// a running download, Spacer, the 24 × 24 xmark cancel button and a 2-point
/// Spacer; padded 4, the hovered row on SidebarItemBackground, clipped to a
/// 12-point continuous rounded rectangle.
struct LibraryFlyoutCell<Icon: View>: View {
    let item: LibraryFlyoutItem?
    let subtitle: String
    /// `shouldShowDetails`: false only for the collapsed visible badge cell.
    let showsDetails: Bool
    let hovered: Bool
    let colors: LibraryFlyoutColors
    let icon: Icon
    var body: some View {
        HStack(alignment: .center) {
            icon.frame(width: LibraryFlyoutLayout.iconSize, height: LibraryFlyoutLayout.iconSize)
            if showsDetails, let item {
                Spacer().frame(width: LibraryFlyoutLayout.detailInset)
                VStack(alignment: .leading) {
                    Text(item.title).lineLimit(1).font(.system(size: 14, weight: .regular)).foregroundColor(Color(nsColor: colors.primary))
                    Text(subtitle).lineLimit(1).font(.system(size: 12)).foregroundColor(Color(nsColor: colors.secondary))
                }
                if item.downloadStatus?.isInProgress == true {
                    Spacer()
                    // The xmark in ForegroundPrimary withAlphaSafe(0.6)
                    //
                    // opacity 0.1 behind it.
                    Image(systemName: "xmark").foregroundColor(Color(nsColor: colors.primary.withAlphaComponent(0.6)))
                        .frame(width: LibraryFlyoutLayout.cancelSize, height: LibraryFlyoutLayout.cancelSize)
                        .background(hovered ? Color(nsColor: colors.primary).opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: LibraryFlyoutLayout.cancelRadius, style: .continuous))
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: LibraryFlyoutCancelFrames.self, value: [item.id: proxy.frame(in: .named(LibraryFlyoutStack.space))])
                        })
                    Spacer().frame(width: LibraryFlyoutLayout.cancelTrailing)
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, LibraryFlyoutLayout.padding)
        .padding(.vertical, LibraryFlyoutLayout.padding)
        .background(hovered ? Color(nsColor: colors.itemBackground) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: LibraryFlyoutLayout.cornerRadius, style: .continuous))
    }
}

extension LibraryFlyoutCell where Icon == LibraryFlyoutIcon {
    init(item: LibraryFlyoutItem, subtitle: String, image: NSImage?, ring: DownloadActivityBadge?, hovered: Bool, colors: LibraryFlyoutColors) {
        self.init(item: item, subtitle: subtitle, showsDetails: true, hovered: hovered, colors: colors,
                  icon: LibraryFlyoutIcon(item: item, image: image, ring: ring, colors: colors))
    }
}

/// The cell stack's rows (VStack leading, spacing 0), drawn oldest at the top
/// so the newest sits beside the button. Each row is
/// `.frame(width, 56).scaleEffect.rotationEffect.offset.opacity
/// .animation(spring.delay(stagger), value: expanded).transition(…)`.
/// Parc adaptation: the visible badge keeps its own cell (DL26/27's renderer
/// must stay in the tree), which draws its row in both states; that row here
/// only keeps its slot and frames (`presented`). Under Reduce Motion rows
/// fade in place and insert without the drop.
struct LibraryFlyoutStack: View {
    static let space = "LibraryFlyoutCanvas"
    @ObservedObject var model: LibraryFlyoutModel
    let presented: String?
    let ring: (LibraryFlyoutItem) -> DownloadActivityBadge?
    let subtitle: (LibraryFlyoutItem) -> String
    var body: some View {
        let rows = Array(model.rows.reversed())
        let count = rows.count, expanded = model.expanded, still = model.reduceMotion
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                let reverseIndex = count - index - 1, drawn = item.id != presented
                LibraryFlyoutCell(item: item, subtitle: subtitle(item), image: model.images[item.id], ring: drawn ? ring(item) : nil,
                                  hovered: model.hoveredRow == item.id, colors: model.colors)
                    .frame(width: model.expandedCellWidth, height: LibraryEntryLayout.cellHeight)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: LibraryFlyoutRowFrames.self, value: [item.id: proxy.frame(in: .named(Self.space))])
                    })
                    .scaleEffect(1)
                    .rotationEffect(.zero)
                    .offset(x: 0, y: expanded || still ? 0 : LibraryFlyoutLayout.hiddenOffset(reverseIndex: reverseIndex))
                    .opacity(expanded && drawn ? 1 : 0)
                    .animation(LibraryFlyoutLayout.animation(reverseIndex: reverseIndex), value: expanded)
                    .transition(still ? .opacity : LibraryFlyoutLayout.transition)
            }
        }
        .onPreferenceChange(LibraryFlyoutRowFrames.self) { frames in
            MainActor.assumeIsolated { if model.measuredRowFrames != frames { model.measuredRowFrames = frames } }
        }
        .onPreferenceChange(LibraryFlyoutCancelFrames.self) { frames in
            MainActor.assumeIsolated { if model.measuredCancelFrames != frames { model.measuredCancelFrames = frames } }
        }
    }
}

// MARK: - Text

enum LibraryFlyoutText {
    ///
    /// full units).
    @MainActor static let relative: RelativeDateTimeFormatter = {
        let value = RelativeDateTimeFormatter()
        value.dateTimeStyle = .numeric; value.unitsStyle = .full
        return value
    }()
    ///
    /// download; otherwise `DownloadsInterfaceUtils.downloadSubtitleString`
    ///
    @MainActor static func subtitle(_ item: LibraryFlyoutItem, now: Date) -> String {
        switch item {
        case .capture(let capture): return relative.localizedString(for: capture.createdAt, relativeTo: now)
        case .file(let file): return relative.localizedString(for: file.dateCreated, relativeTo: now)
        case .download(let download):
            if download.status == .completed { return relative.localizedString(for: item.dateCreated, relativeTo: now) }
            return DownloadRowSubtitle.text(for: download)
        }
    }
    ///
    static func kindDescription(_ url: URL, mimeType: String? = nil) -> String {
        let ext = url.pathExtension
        guard let type = UTType(filenameExtension: ext) ?? mimeType.flatMap({ UTType(mimeType: $0) }) else { return "File" }
        if type.conforms(to: .image) { return "Image" }
        if type.conforms(to: .movie) { return "Video" }
        if type.conforms(to: .pdf) { return "PDF" }
        return "File"
    }
    static func kindDescription(_ item: BrowserDownload) -> String {
        kindDescription(URL(fileURLWithPath: item.path.isEmpty ? item.name : item.path), mimeType: item.mimeType)
    }
    ///
    static func openInApp(_ url: URL?) -> String {
        guard let url, let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return "Open" }
        let bundle = Bundle(url: app)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? app.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Open" : "Open in " + name
    }
    ///
    static func canPreview(_ item: BrowserDownload) -> Bool {
        let ext = URL(fileURLWithPath: item.path.isEmpty ? item.name : item.path).pathExtension
        guard let type = UTType(filenameExtension: ext) ?? item.mimeType.flatMap({ UTType(mimeType: $0) }) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }
}

// MARK: - Actions and menu

enum LibraryFlyoutFileAction: Equatable {
    case open, reveal, copyFile
}

/// What a row asks of the window: Parc's existing download and capture routes
/// plus opening a folder file.
enum LibraryFlyoutAction {
    case download(BrowserDownload, DownloadLibraryAction)
    case file(LibraryFlyoutFile, LibraryFlyoutFileAction)
    /// Parc adaptation for ItemPreviewPresenter on a capture: Parc's capture
    /// preview belongs to the Library's Media page, so the tap opens that page.
    case showCapture(SavedCapture)
    case copyCapture(SavedCapture)
    case openCaptureSource(SavedCapture)
    case copyCaptureSource(SavedCapture)
    /// "Send via iMessage" and "AirDrop" (Feature actions 6 and 8).
    case share(LibraryFlyoutItem, LibraryFlyoutShare)
    ///
    ///
    case deleteCapture(SavedCapture)
}

enum LibraryFlyoutMenu {
    static let cancelTitle = "Cancel Download"
    ///
    static let hideTitle = "Hide from Parc"
    ///
    /// Dividers. The menu has no disabled modifier, so Send via iMessage and
    /// AirDrop are always enabled; the copy, open, reveal, hide and trash
    /// items keep the download route's policy gates (Parc's DL18/DL28 rules).
    @MainActor static func make(_ item: LibraryFlyoutItem, fileURL: URL?, perform: @escaping (LibraryFlyoutAction) -> Void) -> NSMenu? {
        let menu = NSMenu(); menu.autoenablesItems = false
        func add(_ title: String, _ action: LibraryFlyoutAction?, enabled: Bool = true) {
            let entry = MenuAction.item(title) { if let action { perform(action) } }
            entry.isEnabled = enabled && action != nil
            menu.addItem(entry)
        }
        func divider() { menu.addItem(.separator()) }
        switch item {
        case .download(let download):
            switch LibraryFlyoutDownloadStatus(download) {
            case .inProgress:
                add(cancelTitle, .download(download, .cancel), enabled: download.canCancel)
            case .completed:
                add("Copy " + LibraryFlyoutText.kindDescription(download), .download(download, .copyFile), enabled: download.canCopyFile)
                divider()
                add("Send via iMessage", .share(item, .message))
                add("AirDrop", .share(item, .airDrop))
                divider()
                add(LibraryFlyoutText.openInApp(fileURL), .download(download, .open), enabled: download.canOpen)
                add("Show in Finder", .download(download, .reveal), enabled: download.canReveal)
                divider()
                add(hideTitle, .download(download, .remove), enabled: download.canRemove)
                add("Move to Trash", .download(download, .trash), enabled: download.canRemove)
            default:
                return nil
            }
        case .file(let file):
            add("Copy " + LibraryFlyoutText.kindDescription(file.url), .file(file, .copyFile))
            divider()
            add("Send via iMessage", .share(item, .message))
            add("AirDrop", .share(item, .airDrop))
            divider()
            add(LibraryFlyoutText.openInApp(file.url), .file(file, .open))
            add("Show in Finder", .file(file, .reveal))
        case .capture(let capture):
            let web = URL(string: capture.sourceURL).map { ["https", "http"].contains($0.scheme?.lowercased() ?? "") } ?? false
            add("Copy Image", .copyCapture(capture))
            divider()
            add("Send via iMessage", .share(item, .message))
            add("AirDrop", .share(item, .airDrop))
            divider()
            add("Open Source URL", .openCaptureSource(capture), enabled: web)
            add("Copy Source URL", .copyCaptureSource(capture), enabled: web)
            divider()
            add("Delete", .deleteCapture(capture))
        }
        return menu
    }
}

//

/// The two share items of a cell's menu.
enum LibraryFlyoutShare: Equatable {
    ///
    case message
    ///
    case airDrop
    var serviceName: NSSharingService.Name { self == .message ? .composeMessage : .sendViaAirDrop }
}

enum LibraryFlyoutSharing {
    ///
    ///
    static func isImage(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension, conformingTo: .data)
        return type?.conforms(to: .image) == true
    }
    ///
    ///
    ///
    /// and, for a capture, its source address as text.
    static func items(_ share: LibraryFlyoutShare, image: NSImage?, url: URL?, text: String?) -> [Any] {
        switch share {
        case .airDrop:
            if let image { return [image] }
            return url.map { [$0] } ?? []
        case .message:
            var items: [Any] = []
            if let image { items.append(image) } else if let url { items.append(url) }
            if let text, !text.isEmpty { items.append(text) }
            return items
        }
    }
}

extension LibraryFlyoutSharing {
    /// The real macOS service performs the items and owns its own UI, as
    ///
    ///
    /// performed without items or a service.
    @MainActor @discardableResult static func perform(_ share: LibraryFlyoutShare, items: [Any]) -> Bool {
        guard !items.isEmpty, let service = NSSharingService(named: share.serviceName) else { return false }
        service.perform(withItems: items)
        return true
    }
}

//

enum LibraryFlyoutCaptureDeletion {
    ///
    ///
    static let title = "Are you sure you want to delete this capture?"
    static let message = "Doing so will delete this capture permanently."
    ///
    /// sets `ButtonsConfig.destructive`), not an NSAlert.
    @MainActor static func dialog() -> PArcDialog {
        var content = PArcDialog.Content(title: [(title, false)], message: [(message, false)], confirm: "Delete", cancel: "Cancel")
        content.destructive = true
        return PArcDialog(content)
    }
    @MainActor static func confirm(in window: NSWindow, decided: @escaping (Bool) -> Void) -> Bool {
        dialog().begin(for: window) { decided($0 == .confirm) }
    }
}

//

///
///
/// Parc offers the PNG bytes only: they are read from the profile's capture
/// store when the drag starts and supplied lazily, after the original capture
/// is checked again, at delivery. Copy only, like DL28's file drag.
@MainActor final class LibraryCaptureDrag: NSObject {
    let item = NSPasteboardItem()
    private var valid: (() -> Bool)?
    private var data: Data?
    private var load: Task<Void, Never>?
    private let provider = Provider()
    init(load: @escaping @MainActor () async -> Data?, valid: @escaping () -> Bool) {
        self.valid = valid
        super.init()
        provider.owner = self
        item.setDataProvider(provider, forTypes: [.png])
        self.load = Task { @MainActor [weak self] in
            let bytes = await load()
            guard let self, !Task.isCancelled, self.valid != nil else { return }
            self.data = bytes
        }
    }
    func invalidate() { valid = nil; data = nil; load?.cancel(); load = nil; provider.owner = nil }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .png, item === self.item, valid?() == true, let data else { return }
        item.setData(data, forType: .png)
    }
    @MainActor private final class Provider: NSObject, NSPasteboardItemDataProvider {
        weak var owner: LibraryCaptureDrag?
        nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                                    provideDataForType type: NSPasteboard.PasteboardType) {
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { owner?.pasteboard(pasteboard, item: item, provideDataForType: type) }
        }
        nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            if Thread.isMainThread { MainActor.assumeIsolated { owner?.invalidate() } }
            else { Task { @MainActor [weak self] in self?.owner?.invalidate() } }
        }
    }
}

// MARK: - Accessibility

///
///
/// its "Cancel Download" button. None carries a value.
@MainActor final class LibraryEntryElement: NSAccessibilityElement {
    weak var host: NSView?
    /// The row listing this element (a Cancel Download button's cell).
    weak var parentElement: LibraryEntryElement?
    var rect: () -> NSRect = { .zero }
    var press: () -> Bool = { false }
    var children: () -> [Any] = { [] }
    init(host: NSView, label: String) {
        self.host = host
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }
    override func isAccessibilityElement() -> Bool { true }
    /// Its row, otherwise the canvas's unignored ancestor: the canvas is no
    /// element, so its children are promoted to that ancestor.
    override func accessibilityParent() -> Any? {
        if let parentElement { return parentElement }
        return host.flatMap { NSAccessibility.unignoredAncestor(of: $0) }
    }
    override func accessibilityFrame() -> NSRect {
        guard let host, let window = host.window else { return .zero }
        return window.convertToScreen(host.convert(rect(), to: nil))
    }
    override func accessibilityPerformPress() -> Bool { press() }
    override func accessibilityChildren() -> [Any]? { children() }
    override func accessibilityValue() -> Any? { nil }
}

// MARK: - Sidebar content mask

///
///
///
/// above the dock hides the content under the rows.
///
///
/// from the dock's top up. Core Animation rasterizes coincident gradient stops
/// softly, by an amount that grows with the layer's height, so a single
/// full-height gradient let the mini-player deck resting on the dock show
/// through as a bar above it.
@MainActor final class LibraryFlyoutContentMask {
    let layer = CALayer()
    let band = CAGradientLayer()
    private let dock = CALayer()
    ///
    /// clear/black 0.8, clear/black 0.8, black, black.
    static var expandedColors: [CGColor] { [CGColor.black, CGColor.black, CGColor.clear, CGColor.clear, CGColor.black, CGColor.black] }
    static var restingColors: [CGColor] {
        let partial = NSColor.black.withAlphaComponent(0.8).cgColor
        return [CGColor.black, CGColor.black, partial, partial, CGColor.black, CGColor.black]
    }
    ///
    /// height / H and h = totalHeight(count) / H; k is 0.04 expanded and
    /// 0.14 resting.
    static func locations(totalHeight: CGFloat, height: CGFloat, dockHeight: CGFloat, inset: CGFloat) -> [NSNumber] {
        let denominator = height > 0 ? height : totalHeight * 3
        let dock = dockHeight / denominator, band = dock + totalHeight / denominator - inset
        return [0, dock, dock, band, band + 0.15, 1].map { NSNumber(value: Double($0)) }
    }
    /// `locations` from the dock's top (stop 2) up, over the band layer.
    static func bandLocations(_ locations: [NSNumber]) -> [NSNumber] {
        let values = locations.map { CGFloat($0.doubleValue) }, dock = values[2], span = 1 - dock
        return values.dropFirst(2).map { NSNumber(value: Double(span > 0 ? max(0, $0 - dock) / span : 0)) }
    }
    static func bandColors(_ colors: [CGColor]) -> [CGColor] { Array(colors.dropFirst(2)) }
    static let duration: CFTimeInterval = 0.1
    private(set) var installed = false
    private var generation = 0
    private var dockHeight: CGFloat = 0
    weak var view: NSView?

    init() {
        dock.backgroundColor = CGColor.black
        layer.addSublayer(dock); layer.addSublayer(band)
    }

    /// Installs and animates the mask from its resting band to the expanded one.
    func expand(on view: NSView, totalHeight: CGFloat, dockHeight: CGFloat) {
        generation &+= 1
        self.view = view
        self.dockHeight = dockHeight
        view.wantsLayer = true
        guard let host = view.layer else { return }
        band.removeAllAnimations()
        layOut(in: host)
        let from = (installed ? band.presentation()?.locations : nil)
            ?? Self.bandLocations(Self.locations(totalHeight: totalHeight, height: host.bounds.height, dockHeight: dockHeight, inset: 0.14))
        let to = Self.bandLocations(Self.locations(totalHeight: totalHeight, height: host.bounds.height, dockHeight: dockHeight, inset: 0.04))
        let fromColors = (installed ? band.presentation()?.colors : nil) ?? Self.bandColors(Self.restingColors)
        if host.mask !== layer { host.mask = layer }
        installed = true
        animate(locations: from, to: to, colors: fromColors, to: Self.bandColors(Self.expandedColors), completion: nil)
    }
    /// Animates back to the resting band, then removes the mask.
    func collapse(totalHeight: CGFloat, dockHeight: CGFloat) {
        guard installed, let host = view?.layer else { return }
        generation &+= 1
        let token = generation
        let from = band.presentation()?.locations ?? band.locations
            ?? Self.bandLocations(Self.locations(totalHeight: totalHeight, height: host.bounds.height, dockHeight: dockHeight, inset: 0.04))
        let to = Self.bandLocations(Self.locations(totalHeight: totalHeight, height: host.bounds.height, dockHeight: dockHeight, inset: 0.14))
        animate(locations: from, to: to, colors: band.presentation()?.colors ?? Self.bandColors(Self.expandedColors),
                to: Self.bandColors(Self.restingColors)) { [weak self] in
            guard let self, self.generation == token else { return }
            self.remove()
        }
    }
    func remove() {
        generation &+= 1
        band.removeAllAnimations()
        if let host = view?.layer, host.mask === layer { host.mask = nil }
        installed = false
    }
    func resize() {
        guard installed, let host = view?.layer else { return }
        layOut(in: host)
    }
    private func layOut(in host: CALayer) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = host.bounds
        let bounds = layer.bounds, dockHeight = min(self.dockHeight, bounds.height)
        //
        // its flipped content view).
        let flipped = host.contentsAreFlipped()
        dock.frame = CGRect(x: 0, y: flipped ? bounds.height - dockHeight : 0, width: bounds.width, height: dockHeight)
        band.frame = CGRect(x: 0, y: flipped ? 0 : dockHeight, width: bounds.width, height: bounds.height - dockHeight)
        band.startPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0); band.endPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        CATransaction.commit()
    }
    private func animate(locations from: [Any], to: [NSNumber], colors fromColors: [Any], to toColors: [CGColor], completion: (() -> Void)?) {
        CATransaction.begin()
        // Setting the model values would otherwise add Core Animation's 0.25 s
        // implicit actions over the 0.1 s animations below.
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock(completion.map { body in { MainActor.assumeIsolated { body() } } })
        let locations = CABasicAnimation(keyPath: "locations")
        locations.fromValue = from; locations.toValue = to
        locations.duration = Self.duration; locations.isRemovedOnCompletion = false
        band.add(locations, forKey: "parc.flyout.locations")
        band.locations = to
        let colors = CABasicAnimation(keyPath: "colors")
        colors.fromValue = fromColors; colors.toValue = toColors
        colors.duration = Self.duration; colors.isRemovedOnCompletion = false
        band.add(colors, forKey: "parc.flyout.colors")
        band.colors = toColors
        CATransaction.commit()
    }
}

// MARK: - Images

enum LibraryFlyoutImages {
    ///
    /// for icon and thumbnail representations, delivered on the main queue.
    static func fileThumbnail(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> () -> Void {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 256, height: 256),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: [.icon, .thumbnail])
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { representation, _, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(image) } }
        }
        return { QLThumbnailGenerator.shared.cancel(request) }
    }
}
