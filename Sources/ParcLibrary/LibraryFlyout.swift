import AppKit
import Combine
import ParcCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import ParcKit

package enum LibraryFlyoutDownloadStatus: Equatable {
    case inProgress(Double?), paused, notStarted, completed, failed, cancelled
    package init(_ download: BrowserDownload) {
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
    package var isInProgress: Bool { if case .inProgress = self { return true }; return false }
    package var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

package struct LibraryFlyoutFile: Equatable {
    package let url: URL
    let dateCreated: Date
    let isScreenshot: Bool
    package let source: LibraryBadgeSource
    var title: String { url.lastPathComponent }
    var path: String { url.path }
}

package enum LibraryFlyoutFiles {
    package static func defaultFolders() -> [(LibraryBadgeSource, URL)] {
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
    package static func scan(folders: [(LibraryBadgeSource, URL)] = defaultFolders()) -> [LibraryFlyoutFile] {
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

@MainActor
package final class LibraryFlyoutFolderMonitor {
    private static let openQueue = DispatchQueue(label: "org.parc.library-flyout-folders", qos: .utility)
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var requested: [String] = []
    private var refused: Set<String> = []
    private var opening: Set<String> = []
    private var openGeneration: UInt64 = 0
    private var pending: DispatchWorkItem?
    private let onChange: () -> Void

    package init(onChange: @escaping () -> Void) { self.onChange = onChange }
    deinit { sources.values.forEach { $0.cancel() } }

    package func watch(_ folders: [URL]) {
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

    package func cancel() {
        pending?.cancel(); pending = nil
        openGeneration &+= 1; opening = []
        sources.values.forEach { $0.cancel() }
        sources = [:]; requested = []; refused = []
    }

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

@MainActor
package final class LibraryFolderPrompts {
    package static let shared = LibraryFolderPrompts()
    static let answeredKey = "ParcLibraryFolderPromptsAnswered"
    private let defaults: UserDefaults
    private let probe: (@escaping @MainActor @Sendable () -> Void) -> Void
    private var waiting: [() -> Void] = []
    private(set) var asking = false
    var answered: Bool { defaults.bool(forKey: Self.answeredKey) }

    init(defaults: UserDefaults = .standard,
         probe: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = LibraryFolderPrompts.scanOnce) {
        self.defaults = defaults; self.probe = probe
    }

    nonisolated static func scanOnce(_ done: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = LibraryFlyoutFiles.scan()
            DispatchQueue.main.async { MainActor.assumeIsolated(done) }
        }
    }

    package func whenAnswered(_ body: @escaping () -> Void) {
        if answered { body() } else { waiting.append(body) }
    }

    package func ask() {
        guard !answered, !asking else { return }
        asking = true
        probe { [weak self] in
            guard let self else { return }
            self.asking = false
            self.defaults.set(true, forKey: Self.answeredKey)
            let ready = self.waiting; self.waiting = []
            ready.forEach { $0() }
        }
    }
}

package enum LibraryFlyoutItem: Identifiable, Equatable {
    case download(BrowserDownload)
    case capture(SavedCapture)
    case file(LibraryFlyoutFile)

    package var id: String {
        switch self {
        case .download(let item): return "download:" + item.id
        case .capture(let item): return "capture:" + item.id.uuidString
        case .file(let item): return "file:" + item.path
        }
    }
    package var dateCreated: Date {
        switch self {
        case .download(let item): return item.startedAt ?? .distantPast
        case .capture(let item): return item.createdAt
        case .file(let item): return item.dateCreated
        }
    }
    private static func fileName(_ item: BrowserDownload) -> String {
        item.path.isEmpty ? item.name : URL(fileURLWithPath: item.path).lastPathComponent
    }
    package var title: String {
        switch self {
        case .download(let item): return Self.fileName(item)
        case .capture(let item): return item.title.isEmpty ? item.sourceURL : item.title
        case .file(let item): return item.title
        }
    }
    package var accessibilityLabel: String {
        switch self {
        case .download(let item): return "Download \u{2014} " + Self.fileName(item)
        case .capture(let item): return "Capture \u{2014} " + item.title
        case .file(let item): return "File \u{2014} " + item.title
        }
    }
    var uniqueKey: String {
        switch self {
        case .download(let item): return item.path.isEmpty ? "download-record:" + item.id : "file:" + item.path
        case .capture(let item): return "capture-asset:" + item.assetName
        case .file(let item): return "file:" + item.path
        }
    }
    package var download: BrowserDownload? { if case .download(let item) = self { return item }; return nil }
    package var capture: SavedCapture? { if case .capture(let item) = self { return item }; return nil }
    package var file: LibraryFlyoutFile? { if case .file(let item) = self { return item }; return nil }
    package var downloadStatus: LibraryFlyoutDownloadStatus? { download.map(LibraryFlyoutDownloadStatus.init) }
    package var downloadIdentity: DownloadLibraryIdentity? { download.map(DownloadLibraryIdentity.init) }
    package var showsImage: Bool { file != nil || capture != nil || downloadStatus == .completed }
    var imageKey: String {
        switch self {
        case .download(let item): return id + "|" + item.path + "|\(item.receivedBytes)"
        case .capture(let item): return id + "|" + item.revision.uuidString
        case .file(let item): return id + "|\(item.dateCreated.timeIntervalSince1970)"
        }
    }
}

package enum LibraryFlyoutItems {
    static let limit = 4
    package static func merge(downloads: [BrowserDownload], captures: [SavedCapture],
                      files: [LibraryFlyoutFile] = []) -> [LibraryFlyoutItem] {
        var seen = Set<String>(), items: [LibraryFlyoutItem] = []
        for item in downloads.map(LibraryFlyoutItem.download)
            + captures.map(LibraryFlyoutItem.capture)
            + files.map(LibraryFlyoutItem.file)
        where seen.insert(item.uniqueKey).inserted { items.append(item) }
        return items.enumerated().sorted {
            $0.element.dateCreated != $1.element.dateCreated ? $0.element.dateCreated > $1.element.dateCreated : $0.offset < $1.offset
        }.map(\.element)
    }
}

package struct LibraryFlyoutColors: Equatable {
    let itemBackground: NSColor
    let primary: NSColor
    let secondary: NSColor
    let shadow: NSColor
    package static func standard(dark: Bool) -> LibraryFlyoutColors {
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

package enum LibraryFlyoutLayout {
    static let iconSize: CGFloat = 40
    static let detailInset: CGFloat = 12
    static let padding: CGFloat = 4
    static let cornerRadius: CGFloat = 12
    static let cancelSize: CGFloat = 24
    static let cancelRadius: CGFloat = 6
    static let cancelTrailing: CGFloat = 2
    static let imageRadius: CGFloat = 6
    static let captureOutlineRadius: CGFloat = 7
    static let captureOutlinePadding: CGFloat = 1
    static func hiddenOffset(reverseIndex: Int) -> CGFloat { reverseIndex == 0 ? 20 : 56 }
    static let openingStep: TimeInterval = 0.04
    static let closingStep: TimeInterval = 0.03
    static let openingSettle: TimeInterval = 0.22
    static let closingSettle: TimeInterval = 0.21
    static let opening = Animation.spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0.25)
    static let closing = Animation.spring(response: 0.28, dampingFraction: 0.85, blendDuration: 0.25)
    static func stagger(reverseIndex: Int, count: Int, expanded: Bool) -> TimeInterval {
        let last = min(max(count, 1), LibraryFlyoutItems.limit) - 1, place = min(max(reverseIndex, 0), last)
        return expanded ? Double(place) * openingStep : Double(last - place) * closingStep
    }
    package static func duration(count: Int, expanded: Bool) -> TimeInterval {
        stagger(reverseIndex: expanded ? count - 1 : 0, count: count, expanded: expanded) + (expanded ? openingSettle : closingSettle)
    }
    package static func animation(reverseIndex: Int, count: Int, expanded: Bool) -> Animation {
        (expanded ? opening : closing).delay(stagger(reverseIndex: reverseIndex, count: count, expanded: expanded))
    }
    static let transition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: AnyTransition.offset(x: 0, y: -80).combined(with: .scale(scale: 1.5, anchor: .center))),
        removal: .opacity)
}

@MainActor package final class LibraryFlyoutHoverTracker {
    package init() {}
    package enum Region: CaseIterable { case button, dock, flyout }
    static let linger: [Region: TimeInterval] = [.button: 0.15, .dock: 0.5, .flyout: 0.15]
    static func reportsWhenInside(_ region: Region) -> Bool { region == .flyout }

    package var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    package var onChange: ((Region, Bool) -> Void)?
    private var inside: [Region: Bool] = [:]
    private var lingered: [Region: Bool] = [:]
    private var reported: [Region: Bool] = [:]
    private var tokens: [Region: Int] = [:]
    private(set) var pointer: NSPoint?
    private var rects: [Region: NSRect] = [:]
    private var tracked: Set<Region> = []

    func isHovered(_ region: Region) -> Bool { reported[region] ?? false }

    package func update(pointer: NSPoint?, rects: [Region: NSRect], tracked: Set<Region>) {
        self.pointer = pointer; self.rects = rects; self.tracked = tracked
        for region in Region.allCases { evaluate(region) }
    }
    package func needsPass(tracked: Set<Region>, rects: [Region: NSRect]) -> Bool { tracked != self.tracked || rects != self.rects }

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

@MainActor package final class LibraryFlyoutModel: ObservableObject {
    package init() {}
    @Published package private(set) var rows: [LibraryFlyoutItem] = []
    @Published package private(set) var expanded = false
    @Published package private(set) var animating = false
    @Published package var hoveredRow: String?
    @Published package var containerWidth: CGFloat = 228
    @Published package var reduceMotion = false
    @Published package private(set) var images: [String: NSImage] = [:]
    @Published var measuredRowFrames: [String: CGRect] = [:]
    @Published var measuredCancelFrames: [String: CGRect] = [:]
    package var stackOrigin = CGPoint.zero
    @Published package var colors = LibraryFlyoutColors.standard(dark: false)

    private(set) var buttonHovered = false
    private(set) var flyoutHovered = false
    package private(set) var visibleBadgeHovered = false
    private(set) var eligibleToExpand = false
    package var canExpand = false { didSet { if canExpand != oldValue { updateExpanded() } } }
    package var libraryClosedAt: Date?
    package var now: () -> Date = Date.init
    package var after: (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { body() } }
    }
    package var imageLoader: (LibraryFlyoutItem, @escaping @MainActor (NSImage?) -> Void) -> (() -> Void) = { _, completion in
        completion(nil); return {}
    }
    package var onExpansionChange: ((Bool) -> Void)?
    private var animationToken = 0
    private var loads: [String: (key: String, cancel: () -> Void)] = [:]

    package var expandedCellWidth: CGFloat {
        min(containerWidth, LibraryEntryLayout.maximumWidth) - LibraryEntryLayout.expandedInset
    }

    package func setRows(_ items: [LibraryFlyoutItem]) {
        let next = Array(items.prefix(LibraryFlyoutItems.limit))
        if next != rows { rows = next }
        if let hoveredRow, !rows.contains(where: { $0.id == hoveredRow }) { self.hoveredRow = nil }
        loadImages()
        updateExpanded()
    }

    package func setButtonHovered(_ hovered: Bool) { buttonHovered = hovered; hoverChanged() }
    package func setFlyoutHovered(_ hovered: Bool) { flyoutHovered = hovered; hoverChanged() }
    package func setVisibleBadgeHovered(_ hovered: Bool) { visibleBadgeHovered = hovered; hoverChanged() }

    private func hoverChanged() {
        let hovered = buttonHovered || flyoutHovered || visibleBadgeHovered
        if hovered, let closed = libraryClosedAt, now().timeIntervalSince(closed) * 1000 <= 100 { return }
        eligibleToExpand = hovered
        updateExpanded()
    }

    package var trackedRegions: Set<LibraryFlyoutHoverTracker.Region> {
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
        animationToken &+= 1
        let token = animationToken
        animating = true
        after(LibraryFlyoutLayout.duration(count: rows.count, expanded: next)) { [weak self] in
            guard let self, self.animationToken == token else { return }
            self.animating = false
        }
        if next {
            visibleBadgeHovered = false
        } else {
            hoveredRow = nil
        }
        onExpansionChange?(next)
    }

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
    package func reset() {
        for load in loads.values { load.cancel() }
        loads.removeAll(); images.removeAll()
    }

    package func rowFrame(_ id: String) -> CGRect? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        let height = LibraryEntryLayout.cellHeight
        return CGRect(x: stackOrigin.x, y: stackOrigin.y - height * CGFloat(index + 1), width: expandedCellWidth, height: height)
    }
    package func cancelFrame(_ id: String) -> CGRect? {
        guard let row = rowFrame(id), let measuredRow = measuredRowFrames[id], let cancel = measuredCancelFrames[id] else { return nil }
        return cancel.offsetBy(dx: row.minX - measuredRow.minX, dy: row.minY - measuredRow.minY)
    }
    package func row(at point: NSPoint) -> LibraryFlyoutItem? {
        guard expanded else { return nil }
        return rows.first { rowFrame($0.id)?.contains(point) == true }
    }
    package func cancelHit(_ point: NSPoint) -> LibraryFlyoutItem? {
        guard expanded else { return nil }
        return rows.first { $0.downloadStatus?.isInProgress == true && cancelFrame($0.id)?.contains(point) == true }
    }
}

private struct LibraryFlyoutRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
private struct LibraryFlyoutCancelFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct LibraryFlyoutRing: NSViewRepresentable {
    let badge: DownloadActivityBadge
    func makeNSView(context: Context) -> DownloadActivityBadge { badge }
    func updateNSView(_ nsView: DownloadActivityBadge, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DownloadActivityBadge, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

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

package struct LibraryFlyoutIcon: View {
    package let item: LibraryFlyoutItem
    package let image: NSImage?
    package let ring: DownloadActivityBadge?
    package let colors: LibraryFlyoutColors
    package init(item: LibraryFlyoutItem, image: NSImage?, ring: DownloadActivityBadge?, colors: LibraryFlyoutColors) {
        self.item = item
        self.image = image
        self.ring = ring
        self.colors = colors
    }
    package var body: some View {
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

package struct LibraryFlyoutCell<Icon: View>: View {
    package let item: LibraryFlyoutItem?
    package let subtitle: String
    package let showsDetails: Bool
    package let hovered: Bool
    package let colors: LibraryFlyoutColors
    package let icon: Icon
    package init(item: LibraryFlyoutItem?, subtitle: String, showsDetails: Bool, hovered: Bool, colors: LibraryFlyoutColors, icon: Icon) {
        self.item = item
        self.subtitle = subtitle
        self.showsDetails = showsDetails
        self.hovered = hovered
        self.colors = colors
        self.icon = icon
    }
    package var body: some View {
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

package struct LibraryFlyoutStack: View {
    package static let space = "LibraryFlyoutCanvas"
    @ObservedObject package var model: LibraryFlyoutModel
    package let presented: String?
    package let ring: (LibraryFlyoutItem) -> DownloadActivityBadge?
    package let subtitle: (LibraryFlyoutItem) -> String
    package init(model: LibraryFlyoutModel, presented: String?, ring: @escaping (LibraryFlyoutItem) -> DownloadActivityBadge?, subtitle: @escaping (LibraryFlyoutItem) -> String) {
        self.model = model
        self.presented = presented
        self.ring = ring
        self.subtitle = subtitle
    }
    package var body: some View {
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
                    .animation(LibraryFlyoutLayout.animation(reverseIndex: reverseIndex, count: count, expanded: expanded), value: expanded)
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

package enum LibraryFlyoutText {
    @MainActor static let relative: RelativeDateTimeFormatter = {
        let value = RelativeDateTimeFormatter()
        value.dateTimeStyle = .numeric; value.unitsStyle = .full
        return value
    }()
    @MainActor package static func subtitle(_ item: LibraryFlyoutItem, now: Date) -> String {
        switch item {
        case .capture(let capture): return relative.localizedString(for: capture.createdAt, relativeTo: now)
        case .file(let file): return relative.localizedString(for: file.dateCreated, relativeTo: now)
        case .download(let download):
            if download.status == .completed { return relative.localizedString(for: item.dateCreated, relativeTo: now) }
            return DownloadRowSubtitle.text(for: download)
        }
    }
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
    static func openInApp(_ url: URL?) -> String {
        guard let url, let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return "Open" }
        let bundle = Bundle(url: app)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? app.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Open" : "Open in " + name
    }
    package static func canPreview(_ item: BrowserDownload) -> Bool {
        let ext = URL(fileURLWithPath: item.path.isEmpty ? item.name : item.path).pathExtension
        guard let type = UTType(filenameExtension: ext) ?? item.mimeType.flatMap({ UTType(mimeType: $0) }) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }
}

package enum LibraryFlyoutFileAction: Equatable {
    case open, reveal, copyFile
}

package enum LibraryFlyoutAction {
    case download(BrowserDownload, DownloadLibraryAction)
    case file(LibraryFlyoutFile, LibraryFlyoutFileAction)
    case showCapture(SavedCapture)
    case copyCapture(SavedCapture)
    case openCaptureSource(SavedCapture)
    case copyCaptureSource(SavedCapture)
    case share(LibraryFlyoutItem, LibraryFlyoutShare)
    case deleteCapture(SavedCapture)
}

package enum LibraryFlyoutMenu {
    package static let cancelTitle = "Cancel Download"
    static let hideTitle = "Hide from Parc"
    @MainActor package static func make(_ item: LibraryFlyoutItem, fileURL: URL?, perform: @escaping (LibraryFlyoutAction) -> Void) -> NSMenu? {
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

package enum LibraryFlyoutShare: Equatable {
    case message
    case airDrop
    var serviceName: NSSharingService.Name { self == .message ? .composeMessage : .sendViaAirDrop }
}

package enum LibraryFlyoutSharing {
    package static func isImage(_ url: URL) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension, conformingTo: .data)
        return type?.conforms(to: .image) == true
    }
    package static func items(_ share: LibraryFlyoutShare, image: NSImage?, url: URL?, text: String?) -> [Any] {
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
    @MainActor @discardableResult package static func perform(_ share: LibraryFlyoutShare, items: [Any]) -> Bool {
        guard !items.isEmpty, let service = NSSharingService(named: share.serviceName) else { return false }
        service.perform(withItems: items)
        return true
    }
}

package enum LibraryFlyoutCaptureDeletion {
    static let title = "Are you sure you want to delete this capture?"
    static let message = "Doing so will delete this capture permanently."
    @MainActor static func dialog() -> ParcDialog {
        var content = ParcDialog.Content(title: [(title, false)], message: [(message, false)], confirm: "Delete", cancel: "Cancel")
        content.destructive = true
        return ParcDialog(content)
    }
    @MainActor package static func confirm(in window: NSWindow, decided: @escaping (Bool) -> Void) -> Bool {
        dialog().begin(for: window) { decided($0 == .confirm) }
    }
}

@MainActor package final class LibraryCaptureDrag: NSObject {
    package let item = NSPasteboardItem()
    private var valid: (() -> Bool)?
    private var data: Data?
    private var load: Task<Void, Never>?
    private let provider = Provider()
    package init(load: @escaping @MainActor () async -> Data?, valid: @escaping () -> Bool) {
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
    package func invalidate() { valid = nil; data = nil; load?.cancel(); load = nil; provider.owner = nil }
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

@MainActor package final class LibraryEntryElement: NSAccessibilityElement {
    weak var host: NSView?
    package weak var parentElement: LibraryEntryElement?
    package var rect: () -> NSRect = { .zero }
    package var press: () -> Bool = { false }
    package var children: () -> [Any] = { [] }
    package init(host: NSView, label: String) {
        self.host = host
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }
    package override func isAccessibilityElement() -> Bool { true }
    package override func accessibilityParent() -> Any? {
        if let parentElement { return parentElement }
        return host.flatMap { NSAccessibility.unignoredAncestor(of: $0) }
    }
    package override func accessibilityFrame() -> NSRect {
        guard let host, let window = host.window else { return .zero }
        return window.convertToScreen(host.convert(rect(), to: nil))
    }
    package override func accessibilityPerformPress() -> Bool { press() }
    package override func accessibilityChildren() -> [Any]? { children() }
    package override func accessibilityValue() -> Any? { nil }
}

@MainActor package final class LibraryFlyoutContentMask {
    let layer = CALayer()
    let band = CAGradientLayer()
    private let dock = CALayer()
    static var expandedColors: [CGColor] { [CGColor.black, CGColor.black, CGColor.clear, CGColor.clear, CGColor.black, CGColor.black] }
    static var restingColors: [CGColor] {
        let partial = NSColor.black.withAlphaComponent(0.8).cgColor
        return [CGColor.black, CGColor.black, partial, partial, CGColor.black, CGColor.black]
    }
    static func locations(totalHeight: CGFloat, height: CGFloat, dockHeight: CGFloat, inset: CGFloat) -> [NSNumber] {
        let denominator = height > 0 ? height : totalHeight * 3
        let dock = dockHeight / denominator, band = dock + totalHeight / denominator - inset
        return [0, dock, dock, band, band + 0.15, 1].map { NSNumber(value: Double($0)) }
    }
    static func bandLocations(_ locations: [NSNumber]) -> [NSNumber] {
        let values = locations.map { CGFloat($0.doubleValue) }, dock = values[2], span = 1 - dock
        return values.dropFirst(2).map { NSNumber(value: Double(span > 0 ? max(0, $0 - dock) / span : 0)) }
    }
    static func bandColors(_ colors: [CGColor]) -> [CGColor] { Array(colors.dropFirst(2)) }
    static let duration: CFTimeInterval = 0.1
    package static func collapseDelay(count: Int) -> CFTimeInterval { max(0, LibraryFlyoutLayout.duration(count: count, expanded: false) - duration) }
    private(set) var installed = false
    private var generation = 0
    private var dockHeight: CGFloat = 0
    weak var view: NSView?

    package init() {
        dock.backgroundColor = CGColor.black
        layer.addSublayer(dock); layer.addSublayer(band)
    }

    package func expand(on view: NSView, totalHeight: CGFloat, dockHeight: CGFloat) {
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
    package func collapse(totalHeight: CGFloat, dockHeight: CGFloat) {
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
    package func resize() {
        guard installed, let host = view?.layer else { return }
        layOut(in: host)
    }
    private func layOut(in host: CALayer) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.frame = host.bounds
        let bounds = layer.bounds, dockHeight = min(self.dockHeight, bounds.height)
        let flipped = view?.isFlipped ?? true
        dock.frame = CGRect(x: 0, y: flipped ? bounds.height - dockHeight : 0, width: bounds.width, height: dockHeight)
        band.frame = CGRect(x: 0, y: flipped ? 0 : dockHeight, width: bounds.width, height: bounds.height - dockHeight)
        band.startPoint = CGPoint(x: 0.5, y: flipped ? 1 : 0); band.endPoint = CGPoint(x: 0.5, y: flipped ? 0 : 1)
        CATransaction.commit()
    }
    private func animate(locations from: [Any], to: [NSNumber], colors fromColors: [Any], to toColors: [CGColor], completion: (() -> Void)?) {
        CATransaction.begin()
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

package enum LibraryFlyoutImages {
    package static func fileThumbnail(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> () -> Void {
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
