import AppKit
import SwiftUI

/// The shared download owner projects the newest active item, not aggregate
/// throughput. Restored metadata without a live manager incarnation is inert.
struct DownloadActivity: Equatable {
    let identity: DownloadLibraryIdentity
    let name: String
    let progress: Double?
    let completed: Bool

    static func active(in downloads: [BrowserDownload], profiles: Set<UUID>) -> DownloadActivity? {
        newest(in: downloads, profiles: profiles, statuses: [.downloading, .pending])
    }

    ///
    ///
    ///
    static func inFlight(in downloads: [BrowserDownload], profiles: Set<UUID>) -> DownloadActivity? {
        newest(in: downloads, profiles: profiles, statuses: [.downloading])
    }

    private static func newest(in downloads: [BrowserDownload], profiles: Set<UUID>,
                               statuses: Set<BrowserDownloadStatus>) -> DownloadActivity? {
        let item = downloads.lazy.filter {
            guard let profile = $0.profileID, profiles.contains(profile),
                  let guid = $0.nativeID, !guid.isEmpty,
                  let incarnation = $0.nativeIdentity, !incarnation.isEmpty else { return false }
            return statuses.contains($0.status)
        }.min {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
        guard let item else { return nil }
        return DownloadActivity(identity: DownloadLibraryIdentity(item), name: item.name,
            progress: item.totalBytes > 0 ? min(1, max(0, Double(item.receivedBytes) / Double(item.totalBytes))) : nil,
            completed: false)
    }
}

struct DownloadActivityState {
    private(set) var displayed: DownloadActivity?
    private var completionDeadline: TimeInterval?
    mutating func update(_ downloads: [BrowserDownload], profiles: Set<UUID>, now: TimeInterval) -> DownloadActivity? {
        if let active = DownloadActivity.active(in: downloads, profiles: profiles) {
            displayed = active; completionDeadline = nil
        } else if let previous = displayed, !previous.completed,
                  let item = downloads.first(where: { DownloadLibraryIdentity($0) == previous.identity }),
                  item.profileID.map(profiles.contains) == true, item.status == .completed {
            displayed = DownloadActivity(identity: previous.identity, name: item.name, progress: 1, completed: true)
            completionDeadline = now + 1.45
        } else if let previous = displayed, previous.completed,
                  let deadline = completionDeadline, now < deadline,
                  downloads.contains(where: { DownloadLibraryIdentity($0) == previous.identity &&
                      $0.profileID.map(profiles.contains) == true && $0.status == .completed }) {
            return previous
        } else { reset() }
        return displayed
    }
    mutating func reset() { displayed = nil; completionDeadline = nil }
}

/// The window theme's SemanticColorPalette roles DownloadProgressBadge reads
///
///
struct DownloadBadgeColors: Equatable {
    /// foregroundPrimary: the disc's 1-point outline, at 0.5.
    var foreground: NSColor
    /// maxContrastColor: the icon, the 0.2 track and the progress stroke.
    var maxContrast: NSColor
    /// cutoutColor: the disc's fill.
    var cutout: NSColor
    static let standard = DownloadBadgeColors(foreground: .labelColor, maxContrast: .labelColor, cutout: .windowBackgroundColor)
}

/// Source-owned rendering of the recovered SwiftUI badge. Keep each original
/// animation on its original subtree: progress trim, the two ring rotations,
/// and whole-badge completion are separate transactions, not one keyframe curve.
private struct DownloadBadgeContent: View {
    let activity: DownloadActivity
    let colors: DownloadBadgeColors
    let reduceMotion: Bool
    @State private var ringOpacity = 1.0
    @State private var overallOpacity = 1.0
    @State private var overallScale = 1.0
    @State private var iconName = "arrow.down"
    @State private var iconSize = 10.0

    init(activity: DownloadActivity, colors: DownloadBadgeColors, reduceMotion: Bool) {
        self.activity = activity; self.colors = colors; self.reduceMotion = reduceMotion
        // Rebuilding for an accessibility change must not replay completion.
        _ringOpacity = State(initialValue: activity.completed ? 0.5 : 1)
        _iconName = State(initialValue: activity.completed ? "checkmark" : "arrow.down")
        _iconSize = State(initialValue: activity.completed ? 9 : 10)
    }

    private var progress: Double { activity.progress ?? 0.2 }
    @ViewBuilder var body: some View {
        if #available(macOS 14, *) {
            badge.onChange(of: activity.completed) { _, completed in
                if completed { complete() }
            }
        } else {
            badge.onChange(of: activity.completed) { completed in
                if completed { complete() }
            }
        }
    }

    private var badge: some View {
        ZStack {
            Circle().fill(Color(nsColor: colors.cutout))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color(nsColor: colors.foreground).opacity(0.5), lineWidth: 1))
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .heavy))
                .foregroundColor(Color(nsColor: colors.maxContrast))
                .animation(nil, value: iconName)
                .animation(nil, value: iconSize)
            Group {
                ZStack {
                    Circle().stroke(Color(nsColor: colors.maxContrast).opacity(0.2), lineWidth: 2.5)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color(nsColor: colors.maxContrast), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.radians(-.pi / 2))
                        .animation(reduceMotion ? nil : .easeOut, value: progress)
                }
                .opacity(ringOpacity)
                .rotationEffect(.radians(reduceMotion ? 0 : 2 * .pi))
                .animation(reduceMotion ? nil : .linear(duration: 1.5).repeatForever(autoreverses: false), value: progress)
            }
            .rotationEffect(.radians(reduceMotion ? 0 : 4 * .pi))
            .animation(reduceMotion ? nil : .interpolatingSpring(mass: 0.1, stiffness: 0.5,
                damping: 1.2, initialVelocity: 0.5).repeatForever(autoreverses: false), value: progress)
            .frame(width: 21.5, height: 21.5)
        }
        .scaleEffect(overallScale)
        .opacity(overallOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func complete() {
        iconName = "checkmark"; iconSize = 9; ringOpacity = 0.5
        guard !reduceMotion else { return }
        //
        // scheduling/interpolation instead of inventing linear intermediate keys.
        withAnimation(.default) { overallScale = 0.9 }
        withAnimation(.spring(response: 0.5, dampingFraction: 1, blendDuration: 0).delay(0.15)) {
            overallScale = 1
        }
        withAnimation(.easeOut(duration: 0.15).delay(1.15)) { overallScale = 1.03 }
        withAnimation(.easeIn(duration: 0.15).delay(1.3)) {
            overallScale = 0.97; overallOpacity = 0
        }
        // The reference also writes completionScale/completionOpacity, but its
        // actual Body never reads those fields. Do not synthesize an echo ring.
    }
}

/// NSHostingView supplies its own accessibility bridge, so suppress that bridge
/// explicitly as well as hiding the SwiftUI content. The parent button owns AX.
@MainActor private final class DownloadBadgeHostingView: NSHostingView<DownloadBadgeContent> {
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
}

/// Non-interactive decoration of the existing Downloads button. It never owns
/// a second command or intercepts the button's pointer/keyboard/accessibility.
@MainActor final class DownloadActivityBadge: NSView {
    var onChange: ((DownloadActivity?) -> Void)?
    var colors = DownloadBadgeColors.standard { didSet { if colors != oldValue { updateContent() } } }
    private var state = DownloadActivityState()
    private(set) var activity: DownloadActivity?
    private var content: DownloadBadgeHostingView?
    private var retirement: DispatchWorkItem?
    private var generation: UInt64 = 0
    /// The rail's played completion has reached its deadline: the renderer is
    /// gone, while the activity, and so the tile's badge slot, remain.
    private var settled = false
    private var motionObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private weak var retiredWindow: NSWindow?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true; setAccessibilityElement(false)
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.motionChanged() }
            }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    deinit {
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        if let window {
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated { self?.retiredWindow = window; self?.reset() }
                }
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { reset() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func layout() {
        super.layout()
        content?.frame = bounds
    }
    func update(_ downloads: [BrowserDownload], profiles: Set<UUID>, enabled: Bool) {
        guard enabled, let window, window !== retiredWindow else { reset(); return }
        let next = state.update(downloads, profiles: profiles, now: ProcessInfo.processInfo.systemUptime)
        guard next != activity else { return }
        let newIdentity = next?.identity != activity?.identity
        let reactivated = activity?.completed == true && next?.completed == false
        let justCompleted = next?.completed == true &&
            (activity?.completed != true || newIdentity)
        if newIdentity || next?.completed != true {
            cancelRetirement()
            if newIdentity || reactivated { retireContent() }
        }
        activity = next; isHidden = next == nil
        updateContent()
        let token = generation
        onChange?(next)
        // A publisher can synchronously retire this exact window/item.
        guard generation == token, activity == next else { return }
        if justCompleted { complete() }
    }
    /// The Library rail's DownloadProgressBadge (DownloadsPage.SidebarView
    ///
    /// progress follows whichever download that is. Its completion plays when
    ///
    /// settles at DL27's deadline; the slot leaves only when nothing is in flight.
    func updateInFlight(_ downloads: [BrowserDownload], profiles: Set<UUID>, enabled: Bool) {
        guard enabled, let window, window !== retiredWindow,
              let flight = DownloadActivity.inFlight(in: downloads, profiles: profiles) else { reset(); return }
        let completed = activity.map { $0.completed || (flight.progress != $0.progress && (flight.progress ?? 0) >= 1) } ?? false
        let next = DownloadActivity(identity: flight.identity, name: flight.name, progress: flight.progress, completed: completed)
        guard next != activity else { return }
        let justCompleted = completed && activity?.completed != true
        activity = next; isHidden = false
        updateContent()
        if justCompleted { complete(keepingSlot: true) }
        onChange?(next)
    }
    func reset() {
        state.reset(); cancelRetirement(); retireContent(); settled = false
        let hadActivity = activity != nil
        activity = nil; isHidden = true
        if hadActivity { onChange?(nil) }
    }
    private func cancelRetirement() {
        generation &+= 1; retirement?.cancel(); retirement = nil
    }
    private func retireContent() {
        content?.removeFromSuperview(); content = nil
    }
    private func updateContent() {
        guard let activity, !settled else { retireContent(); return }
        let view = DownloadBadgeContent(activity: activity, colors: colors,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let content { content.rootView = view }
        else {
            let host = DownloadBadgeHostingView(rootView: view)
            host.frame = bounds; host.autoresizingMask = [.width, .height]
            host.setAccessibilityElement(false)
            addSubview(host); content = host
        }
    }
    /// DL27's 1.45-second completion deadline. The entry badge then retires.
    /// The rail keeps its slot while anything is in flight and drops only the
    /// renderer, whatever Reduce Motion or a rebuild left of its fade.
    private func complete(keepingSlot: Bool = false) {
        cancelRetirement()
        let token = generation
        let task = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token, self.activity?.completed == true else { return }
                if keepingSlot { self.settled = true; self.retireContent() } else { self.reset() }
            }
        }
        retirement = task; DispatchQueue.main.asyncAfter(deadline: .now() + 1.45, execute: task)
    }
    private func motionChanged() {
        // Retire the actual renderer to stop its repeating/delayed animations.
        // The original item and completion deadline remain owned by this badge.
        retireContent(); updateContent()
    }
}
