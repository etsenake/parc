import AppKit
import ParcCore
import ParcEngine

enum SidebarPreviewTarget: Hashable {
    case tab(UUID)
    case folder(UUID)
}

enum SidebarRecentDomain: String, CaseIterable {
    case notion, figma, linear, confluence
    var title: String {
        switch self { case .notion: return "Notion"; case .figma: return "Figma"
        case .linear: return "Linear"; case .confluence: return "Confluence" }
    }
    var createTitle: String {
        switch self { case .figma: return "New File"; case .linear: return "New Issue"; case .notion, .confluence: return "New Page" }
    }
    var createURL: URL {
        switch self {
        case .notion: return URL(string: "https://notion.so/new")!
        case .figma: return URL(string: "https://figma.com/new")!
        case .linear: return URL(string: "https://linear.app/new")!
        case .confluence: return URL(string: "https://confluence.new")!
        }
    }
    var emptyMessage: String {
        switch self {
        case .notion: return "Recent Notion docs appear here."
        case .figma: return "Recent Figma files appear here."
        case .linear: return "Recent Linear projects and issues appear here."
        case .confluence: return "Recent Confluence pages appear here."
        }
    }
    var textProvider: RecentPageText.Provider {
        switch self { case .notion: return .notion; case .figma: return .figma
        case .linear: return .linear; case .confluence: return .confluence }
    }
    static func matching(_ url: URL) -> Self? {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return nil }
        func matches(_ suffix: String) -> Bool { host == suffix || host.hasSuffix("." + suffix) }
        if matches("notion.so") || matches("notion.site") {
            guard !matches("calendar.notion.so") else { return nil }
            return .notion
        }
        if matches("figma.com") { return .figma }
        if matches("linear.app") { return .linear }
        if matches("atlassian.net") && url.pathComponents.contains("wiki") { return .confluence }
        return nil
    }
}

struct SidebarPreviewRow: Equatable {
    let id: String
    let tabID: UUID?
    let title: String
    let url: URL
    let visitedAt: Date?
    var isBadged = false

    var hasIcon: Bool { tabID != nil }
    var isDocument: Bool { SidebarDocumentKind(url: url) != nil }
    func subtitle(now: Date = Date()) -> String {
        if isBadged { return "Recently Added" }
        if tabID == nil { return RecentPageText.subtitle(url: url, visitedAt: visitedAt, now: now) }
        return visitedAt.map { RecentPageText.relativeTime($0, now: now) } ?? ""
    }

    static func recentPages(_ rows: [SidebarPreviewRow], domain: SidebarRecentDomain) -> [SidebarPreviewRow] {
        let tidy = rows.filter { $0.tabID == nil && SidebarRecentDomain.matching($0.url) == domain }.map {
            SidebarPreviewRow(id: $0.id, tabID: nil, title: RecentPageText.tidyTitle(domain.textProvider, url: $0.url, title: $0.title),
                              url: $0.url, visitedAt: $0.visitedAt)
        }
        return RecentPageText.deduplicated(tidy, title: \.title, url: \.url)
    }
    static func folderTitle(custom: String?, url: URL, title: String) -> String {
        custom ?? TidyTitles.title(for: url, title: title) ?? title
    }
    static func newestFirst(_ rows: [SidebarPreviewRow]) -> [SidebarPreviewRow] {
        rows.enumerated().sorted { left, right in
            let a = left.element.visitedAt ?? .distantPast, b = right.element.visitedAt ?? .distantPast
            return a != b ? a > b : left.offset < right.offset
        }.map(\.element)
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || title.localizedCaseInsensitiveContains(query) || url.absoluteString.localizedCaseInsensitiveContains(query)
    }
}

struct SidebarPreviewSource: Equatable {
    let target: SidebarPreviewTarget
    let profileID: UUID
    let spaceID: UUID
    let selectedTabIDs: [UUID]
    let focusedTabID: UUID?
    let theme: SpaceTheme
    let title: String
    let domain: SidebarRecentDomain?
    let originalURL: URL?
    let rows: [SidebarPreviewRow]
    var document: SidebarDocumentKind? = nil

    var showsPicture: Bool {
        if case .tab = target { return domain == nil }
        return false
    }

    func hasSameOwner(as other: SidebarPreviewSource) -> Bool {
        target == other.target && profileID == other.profileID && spaceID == other.spaceID
            && selectedTabIDs == other.selectedTabIDs && focusedTabID == other.focusedTabID && theme == other.theme
            && domain == other.domain && document == other.document
            && (showsPicture || (title == other.title && originalURL == other.originalURL))
    }
}

enum SidebarPreviewAction: Equatable {
    case activate(SidebarPreviewModifiers)
    case create(SidebarPreviewModifiers)
    case split, duplicate, archive, copyURL, peek
    case copyIssueID(String)

    func activation(for row: SidebarPreviewRow) -> SidebarPreviewActivation? {
        switch self {
        case .activate(let modifiers): return row.tabID == nil ? .recentPage(modifiers) : .folderItem(modifiers)
        case .create(let modifiers): return .recentPage(modifiers)
        case .split, .duplicate, .archive, .copyURL, .copyIssueID, .peek: return nil
        }
    }
}

enum SidebarPreviewMotion {
    static func remainsOnAnchor(windowPoint: NSPoint, anchor: NSView) -> Bool {
        guard anchor.window != nil, !anchor.isHiddenOrHasHiddenAncestor else { return false }
        let local = anchor.convert(windowPoint, from: nil)
        return anchor.visibleRect.intersection(anchor.bounds).contains(local)
    }

    static func keepsSessionTarget(windowPoint: NSPoint, anchor: NSView) -> Bool {
        guard remainsOnAnchor(windowPoint: windowPoint, anchor: anchor),
              let superview = anchor.superview else { return false }
        let hitPoint = superview.convert(windowPoint, from: nil)
        guard let hit = anchor.hitTest(hitPoint) else { return false }
        return hit === anchor || (hit.isDescendant(of: anchor) && !(hit is NSButton))
    }
}

@MainActor
final class SidebarPreviewController {
    var source: ((SidebarPreviewTarget) -> SidebarPreviewSource?)?
    var permitted: (() -> Bool)?
    var perform: ((SidebarPreviewSource, SidebarPreviewRow, SidebarPreviewAction) -> Void)?
    var offers: ((SidebarPreviewSource, SidebarPreviewRow, SidebarPreviewAction) -> Bool)?
    var requestRecent: ((SidebarRecentDomain, UUID, @escaping ([SidebarPreviewRow]) -> Void) -> (() -> Void)?)?
    var requestPicture: ((UUID, @escaping (NSImage?) -> Void) -> (() -> Void)?)?
    var requestDocument: ((SidebarPreviewSource, SidebarDocumentKind, @escaping (SidebarDocumentUpdate) -> Void) -> (() -> Void)?)?
    var favicon: ((URL, UUID, @escaping (NSImage?) -> Void) -> Void)?
    var onPresentationChange: (() -> Void)?
    var openSettings: (() -> Void)?
    var isHoverEnabled = true {
        didSet { if !isHoverEnabled, current != nil, card == nil, !keyboardPresentation { dismiss() } }
    }
    private weak var sidebar: SidebarView?
    private weak var host: NSView?
    private weak var window: NSWindow?
    private var current: SidebarPreviewSource?
    private var anchor = NSRect.zero
    private var card: SidebarPreviewCard? {
        didSet {
            guard let window else { return }
            TooltipController.controller(for: window).exemptView = card
            TooltipController.controller(for: window).isSuppressed = card != nil
        }
    }
    private var leaving: [SidebarPreviewCard] = []
    private var dwell: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var cancelQuery: (() -> Void)?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var generation: UInt64 = 0
    private var keyboardPresentation = false
    private var contextMenuDepth = 0
    private var previousAcceptsMouseMoved = false
    private var lastPointer: NSPoint?
    private var trackingView: SidebarPreviewTrackingView?
    private weak var previousResponder: NSResponder?
    private weak var lastAnchorView: NSView?

    var isPresented: Bool { card != nil }
    var holdsSidebarOpen: Bool { card != nil || dwell != nil || cancelQuery != nil }
    func contains(windowPoint: NSPoint) -> Bool {
        guard let host, let card else { return false }
        return card.frame.contains(host.convert(windowPoint, from: nil))
    }

    init(sidebar: SidebarView, host: NSView, window: NSWindow) {
        self.sidebar = sidebar; self.host = host; self.window = window
        previousAcceptsMouseMoved = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        let tracker = SidebarPreviewTrackingView(frame: host.bounds)
        tracker.autoresizingMask = [.width, .height]
        tracker.onExit = { [weak self] in self?.pointerLeftWindow() }
        host.addSubview(tracker); trackingView = tracker
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .keyDown, .scrollWheel]) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated { if let self { result = self.handle(event) } }
            return result
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: PCNativeBrowserApplication.tabSwitcherAvailabilityDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        })
        observers.append(center.addObserver(forName: SidebarPreviewPreference.didChangeNotification,
            object: UserDefaults.standard, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
                self?.sidebar?.onPreviewPreferencesChanged?()
            }
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: host, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ([self.card].compactMap { $0 } + self.leaving).forEach { $0.place() }
            }
        })
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.willStartLiveResizeNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let menu = note.object as? NSMenu, self.card?.owns(menu) == true { self.contextMenuDepth += 1 }
                else { self.dismiss() }
            }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.contextMenuDepth = max(0, self.contextMenuDepth - 1)
            }
        })
    }

    func shutdown() {
        dismiss(animated: false)
        leaving.forEach { $0.removeFromSuperview() }; leaving.removeAll()
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        trackingView?.removeFromSuperview(); trackingView = nil
        window?.acceptsMouseMovedEvents = previousAcceptsMouseMoved
    }

    func reconcile() {
        guard var current else { return }
        if let card, current.domain == nil, let fresh = source?(current.target), fresh != current, fresh.hasSameOwner(as: current) {
            current = fresh; self.current = fresh; card.setRows(fresh.rows)
            if fresh.document != nil { card.setTitle(fresh.title) }
            else if fresh.showsPicture { card.setHeading(fresh.title, site: Self.site(fresh.originalURL)) }
        }
        guard valid(current), let next = anchorRect(current.target) else {
            dismiss(); return
        }
        lastAnchorView = sidebar?.previewAnchor(for: current.target)
        card?.refreshPeek()
        guard next != anchor else { return }
        anchor = next
        if let card { card.placement.row = next; card.place() }
    }

    func showFromKeyboard(_ target: SidebarPreviewTarget) {
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.begin(target, keyboard: true)
        }
    }

    func dismiss() { dismiss(animated: true) }

    private func dismiss(animated: Bool) {
        let hadSession = current != nil || card != nil || dwell != nil
        generation &+= 1
        dwell?.cancel(); dwell = nil; timeout?.cancel(); timeout = nil
        cancelQuery?(); cancelQuery = nil
        if let card {
            if card.ownsFirstResponder, let window {
                if window.isKeyWindow, window.attachedSheet == nil,
                   let responder = previousResponder as? NSView, SavedFocus.mayReturn(to: responder, in: window) {
                    window.makeFirstResponder(responder)
                }
                if card.ownsFirstResponder { window.makeFirstResponder(nil) }
            }
            card.retire()
            if animated {
                leaving.append(card)
                card.animateOut { [weak self, weak card] in self?.leaving.removeAll { $0 === card } }
            } else { card.removeFromSuperview() }
        }
        card = nil; current = nil; contextMenuDepth = 0
        keyboardPresentation = false; previousResponder = nil; lastAnchorView = nil
        if hadSession { onPresentationChange?() }
    }

    private func valid(_ value: SidebarPreviewSource) -> Bool {
        permitted?() == true && source?(value.target) == value && window?.isKeyWindow == true
            && window?.isVisible == true && window?.isMiniaturized == false && window?.attachedSheet == nil
    }
    private func sessionNeedsReconcile() -> Bool {
        guard current != nil else { return false }
        guard permitted?() == true, let window, window.isKeyWindow, window.isVisible,
              !window.isMiniaturized, window.attachedSheet == nil else { return true }
        if let host, let view = lastAnchorView, view.window === window,
           !view.isHiddenOrHasHiddenAncestor {
            let visible = view.visibleRect.intersection(view.bounds)
            if visible.isEmpty { return true }
            return host.convert(visible, from: view) != anchor
        }
        guard let sidebar, let host, let current,
              let view = sidebar.previewAnchor(for: current.target),
              view.window === window, !view.isHiddenOrHasHiddenAncestor else { return true }
        lastAnchorView = view
        let visible = view.visibleRect.intersection(view.bounds)
        if visible.isEmpty { return true }
        return host.convert(visible, from: view) != anchor
    }
    private func anchorRect(_ target: SidebarPreviewTarget) -> NSRect? {
        guard let sidebar, let host, let view = sidebar.previewAnchor(for: target),
              view.window === window, !view.isHiddenOrHasHiddenAncestor else { return nil }
        let visible = view.visibleRect.intersection(view.bounds)
        guard !visible.isEmpty else { return nil }
        return host.convert(visible, from: view)
    }
    private func location(_ target: SidebarPreviewTarget) -> SidebarPreviewLocation {
        sidebar?.previewAnchor(for: target) is FavoriteTile ? .diagonal : .right
    }
    private func begin(_ target: SidebarPreviewTarget, keyboard: Bool) {
        guard let next = source?(target), valid(next), let rect = anchorRect(target) else { dismiss(); return }
        if current == next && card != nil {
            if keyboard { keyboardPresentation = true; card?.focusKeyboard() }; return
        }
        dismiss(); current = next; anchor = rect; keyboardPresentation = keyboard
        lastAnchorView = sidebar?.previewAnchor(for: target)
        let token = generation
        if keyboard { commit(next, token: token); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.dwell = nil
            guard self.isHoverEnabled, self.current == next, self.targetUnderPointer() == next.target,
                  self.anchorRect(next.target) == self.anchor else { self.dismiss(); return }
            self.commit(next, token: token)
        }
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: work)
    }
    private func commit(_ value: SidebarPreviewSource, token: UInt64) {
        guard generation == token, valid(value) else { dismiss(); return }
        if let document = value.document { commitDocument(value, kind: document, token: token); return }
        if value.showsPicture, case .tab(let id) = value.target { commitPicture(value, tabID: id, token: token); return }
        guard let domain = value.domain else { present(value, rows: value.rows, token: token); return }
        let timeout = scheduleTimeout(token: token)
        let cancel = requestRecent?(domain, value.profileID) { [weak self] rows in
            guard let self, self.generation == token, self.timeout?.isCancelled == false else { return }
            self.timeout?.cancel(); self.timeout = nil; self.cancelQuery = nil
            self.present(value, rows: SidebarPreviewRow.recentPages(rows, domain: domain), token: token)
            if self.card == nil { self.onPresentationChange?() }
        }
        if self.timeout === timeout { cancelQuery = cancel }
        if cancel == nil { timeout.cancel(); self.timeout = nil }
        onPresentationChange?()
    }
    private func commitPicture(_ value: SidebarPreviewSource, tabID: UUID, token: UInt64) {
        let timeout = scheduleTimeout(token: token)
        let cancel = requestPicture?(tabID) { [weak self] image in
            guard let self, self.generation == token else { return }
            guard let image else {
                DispatchQueue.main.async { [weak self] in if self?.generation == token { self?.dismiss() } }
                return
            }
            if let card = self.card { card.setPicture(image); return }
            guard self.timeout?.isCancelled == false else { return }
            self.timeout?.cancel(); self.timeout = nil
            self.present(value, rows: value.rows, picture: image, token: token)
            if self.card == nil { self.cancelQuery?(); self.cancelQuery = nil; self.onPresentationChange?() }
        }
        if self.timeout === timeout { cancelQuery = cancel }
        if cancel == nil { timeout.cancel(); self.timeout = nil }
        onPresentationChange?()
    }
    private func commitDocument(_ value: SidebarPreviewSource, kind: SidebarDocumentKind, token: UInt64) {
        var latest = SidebarDocumentUpdate(content: SidebarDocumentContent(), picture: nil, settled: false)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.card == nil else { return }
            self.timeout = nil
            self.present(value, rows: value.rows, document: latest, token: token)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: timeout)
        let cancel = requestDocument?(value, kind) { [weak self] update in
            guard let self, self.generation == token else { return }
            latest = update
            if let card = self.card { card.setDocument(update.content, picture: update.picture); return }
            guard update.picture != nil || update.settled, self.timeout?.isCancelled == false else { return }
            self.timeout?.cancel(); self.timeout = nil
            self.present(value, rows: value.rows, document: update, token: token)
        }
        if generation == token { cancelQuery = cancel } else { cancel?() }
        onPresentationChange?()
    }
    private static func site(_ url: URL?) -> String {
        url.map { SidebarAddressSearchIcon.host(of: $0) ?? $0.absoluteString } ?? ""
    }
    private func scheduleTimeout(token: UInt64) -> DispatchWorkItem {
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.cancelQuery?(); self.cancelQuery = nil; self.timeout = nil
            self.onPresentationChange?()
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500), execute: timeout)
        return timeout
    }
    private func present(_ value: SidebarPreviewSource, rows: [SidebarPreviewRow], picture: NSImage? = nil,
                         document: SidebarDocumentUpdate? = nil, token: UInt64) {
        guard generation == token, card == nil, current == value, valid(value), let host else { return }
        let card = SidebarPreviewCard(title: value.title, domain: value.domain, providerURL: value.originalURL,
                                      picture: picture ?? document?.picture,
                                      site: value.document == nil ? Self.site(value.originalURL) : "", document: value.document)
        card.placement = SidebarPreviewPlacement(row: anchor, location: location(value.target))
        let live: () -> SidebarPreviewSource? = { [weak self] in
            guard let self, self.generation == token, let current = self.current,
                  current.target == value.target, self.valid(current) else { return nil }
            return current
        }
        card.onAction = { [weak self] row, action in
            guard let self, let value = live() else { return }
            if action == .copyURL {
                NSPasteboard.general.clearContents()
                if row.isDocument { NSPasteboard.general.writeObjects([row.url as NSURL]) }
                NSPasteboard.general.setString(row.url.absoluteString, forType: .string)
            } else if case .copyIssueID(let id) = action {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string)
            } else {
                if action.activation(for: row)?.dismissesPreview != false { self.dismiss() }
                self.perform?(value, row, action)
            }
        }
        card.offersPeek = { [weak self] row in
            guard let self, let value = live() else { return false }
            return self.offers?(value, row, .peek) == true
        }
        card.onEscape = { [weak self] in self?.dismiss() }
        card.onSettings = { [weak self] in self?.showSettings(token: token, live: live) }
        card.onHover = { [weak self] inside in if !inside { self?.pointerLeftCard() } }
        card.onHeightChange = { [weak card] in card?.place() }
        card.requestFavicon = { [weak self] url, completion in
            guard let self, let value = live() else { return }
            self.favicon?(url, value.profileID) { image in
                guard live() != nil else { return }
                completion(image)
            }
        }
        card.setRows(rows)
        if let document { card.setDocument(document.content, picture: document.picture) }
        previousResponder = window?.firstResponder
        self.card = card
        host.addSubview(card, positioned: .above, relativeTo: nil)
        card.place()
        card.animateIn(from: card.convert(card.placement.anchor, from: host))
        if keyboardPresentation { card.focusKeyboard() }
        onPresentationChange?()
    }
    private func showSettings(token: UInt64, live: () -> SidebarPreviewSource?) {
        guard generation == token, live() != nil else { return }
        dismiss()
        openSettings?()
    }
    private func targetUnderPointer() -> SidebarPreviewTarget? {
        guard let window, let sidebar else { return nil }
        return sidebar.previewTarget(atWindowPoint: window.mouseLocationOutsideOfEventStream)
    }
    private func pointerLeftWindow() {
        if !keyboardPresentation && contextMenuDepth == 0 { dismiss() }
    }
    private func pointerLeftCard() {
        guard let window, let host, contextMenuDepth == 0 else { return }
        let point = window.mouseLocationOutsideOfEventStream
        pointerMoved(to: host.convert(point, from: nil), windowPoint: point, from: nil)
    }
    private func pointerMoved(to point: NSPoint, windowPoint: NSPoint, from last: NSPoint?) {
        if let card, card.hoverFrame.contains(point) { return }
        if current != nil, let view = lastAnchorView,
           SidebarPreviewMotion.keepsSessionTarget(windowPoint: windowPoint, anchor: view) {
            return
        }
        let target = targetUnderPointer()
        if let target, target == current?.target { return }
        if let card, let last, let sidebar, sidebar.bounds.contains(sidebar.convert(windowPoint, from: nil)),
           SidebarPreviewAim.keepsCurrent(from: last, to: windowPoint, location: card.placement.location) { return }
        if let target {
            if isHoverEnabled { begin(target, keyboard: false) }
        } else if !keyboardPresentation {
            dismiss()
        }
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else {
            if event.type == .mouseMoved && !keyboardPresentation { dismiss() }; return event
        }
        guard permitted?() == true else { dismiss(); return event }
        if current != nil {
            let overCard: Bool
            if event.type == .mouseMoved, let host {
                overCard = card?.hoverFrame.contains(host.convert(event.locationInWindow, from: nil)) == true
            } else {
                overCard = false
            }
            if !overCard, sessionNeedsReconcile() { reconcile() }
        }
        guard let host else { return event }
        let point = host.convert(event.locationInWindow, from: nil)
        switch event.type {
        case .mouseMoved:
            let last = lastPointer; lastPointer = event.locationInWindow
            guard contextMenuDepth == 0 else { return event }
            pointerMoved(to: point, windowPoint: event.locationInWindow, from: last)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if card?.frame.contains(point) != true { dismiss() }
            else { keyboardPresentation = true }
        case .leftMouseDragged, .rightMouseDragged:
            if card?.ownsFirstResponder != true { dismiss() }
        case .scrollWheel:
            if card?.frame.contains(point) != true { dismiss() }
        case .keyDown:
            if card != nil, event.keyCode == 53 { dismiss(); return nil }
            if let card, card.ownsFirstResponder { return event }
            if card != nil { dismiss() }
        default: break
        }
        return event
    }
}

private final class SidebarPreviewTrackingView: NSView {
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(next); area = next
    }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
