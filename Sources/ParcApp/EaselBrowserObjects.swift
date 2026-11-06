import AppKit
import Combine

/// One editor/window's real auxiliary pages. Durable objects live in the shared
/// session; WebContents and input/permission ownership stay window-local.
@MainActor
final class EaselBrowserObjects: NSObject, EaselBrowserObjectHosting, PCBrowserViewDelegate {
    private static var owners: [UUID: EaselBrowserObjects] = [:]
    private let token = UUID()
    private let session: EaselSession
    private weak var canvas: EaselCanvasView?
    private weak var binding: PCNativeBrowserWindow?
    private let profilePath: String
    private var validOwner: () -> Bool
    private var activeOwner: () -> Bool
    private var selectionChanged: () -> Void
    private var metadataChanged: () -> Void
    private var metadataRefreshPending = false
    private var replacementObserver: UUID?
    private var documentObserver: AnyCancellable?
    private var entries: [UUID: Entry] = [:]
    private var selectedID: UUID?
    private var interacting = false
    private var retirementPending = false
    private var windowTransferGeneration: UInt64 = 0
    private var windowTransfer: WindowTransfer?
    private var disposed = false
    var onError: ((Error) -> Void)?
    var onContextImage: ((PCBrowserView, PCNativeContextImage) -> Void)?

    @MainActor private final class Entry {
        let identity = UUID()
        var originalURL: String
        let view: EaselBrowserSurface
        let captureLayout: EaselCaptureLayout?
        func matches(_ item: EaselItem) -> Bool {
            item.ownsEmbeddedPage && item.url == originalURL && item.captureLayout == captureLayout
        }
        var request: PCNativeEmbeddedPageRequest?
        var started = false
        var wasLoading = true
        var crash: PCNativeRendererCrash?
        var retainedPage: PCNativePage?
        var page: PCNativePage? { view.browser.nativePage ?? retainedPage }
        var attempt = UUID()
        func cancelRequest() {
            request?.cancel()
            // A committed native request cannot be cancelled. Keep the entry
            // and accept its actual page callback rather than abandoning it.
            guard request?.isPending != true else { return }
            attempt = UUID(); request = nil
        }
        init(url: String, profilePath: String, captureLayout: EaselCaptureLayout?) {
            self.captureLayout = captureLayout
            originalURL = url; view = EaselBrowserSurface(profilePath: profilePath, captureLayout: captureLayout)
        }
    }

    init(session: EaselSession, canvas: EaselCanvasView, binding: PCNativeBrowserWindow,
         profilePath: String, validOwner: @escaping () -> Bool,
         activeOwner: @escaping () -> Bool, selectionChanged: @escaping () -> Void,
         metadataChanged: @escaping () -> Void) {
        self.session = session; self.canvas = canvas; self.binding = binding; self.profilePath = profilePath
        self.validOwner = validOwner; self.activeOwner = activeOwner; self.selectionChanged = selectionChanged
        self.metadataChanged = metadataChanged
        super.init()
        replacementObserver = session.observeReplacement { [weak self] next in
            guard let self else { return true }
            return self.entries.allSatisfy { id, entry in
                guard entry.page?.isClosed == false || entry.request?.isPending == true else { return true }
                return next?.items.contains { item in
                    guard item.id == id, item.ownsEmbeddedPage, item.captureLayout == entry.captureLayout, let url = item.url else { return false }
                    return url == entry.originalURL || (entry.page?.isClosed == false && entry.request == nil
                        && self.session.isRecordingBrowserNavigation(id, from: entry.originalURL, to: url))
                } == true
            }
        }
        // Observe each committed value synchronously: a delete followed by Undo
        // before the next layout must retire the closed entry, so restoration
        // can create a fresh runtime page for that same durable object.
        documentObserver = session.$document.sink { [weak self] next in
            guard let self else { return }
            for (id, entry) in self.entries {
                if let item = next.items.first(where: { $0.id == id && $0.kind == .browser }), let url = item.url,
                   self.session.isRecordingBrowserNavigation(id, from: entry.originalURL, to: url) {
                    entry.originalURL = url // Same real page; never replay this observation.
                }
            }
            for (id, entry) in Array(self.entries) where
                !next.items.contains(where: { $0.id == id && entry.matches($0) })
                && entry.page?.isClosed != false {
                entry.cancelRequest()
                if entry.request == nil { entry.view.removeFromSuperview(); self.entries.removeValue(forKey: id) }
            }
            self.releaseIfIdle()
        }
        canvas.pageObjects = self
    }

    /// A retained original pool snapshot. It never represents a new page or
    /// grants a view permission to claim an arbitrary native Browser.
    final class WindowTransfer {
        fileprivate let generation: UInt64
        fileprivate let owner: UUID
        fileprivate let entryIDs: [UUID: UUID]
        fileprivate let objects: [UUID: EaselItem]
        let views: [UUID: PCBrowserView]
        let pages: [UUID: PCNativePage]
        fileprivate init(owner: UUID, generation: UInt64, entryIDs: [UUID: UUID], objects: [UUID: EaselItem],
                         views: [UUID: PCBrowserView], pages: [UUID: PCNativePage]) {
            self.owner = owner; self.generation = generation; self.entryIDs = entryIDs; self.objects = objects
            self.views = views; self.pages = pages
        }
    }
    func snapshotForWindowTransfer() -> WindowTransfer? {
        guard !disposed, windowTransfer == nil, !retirementPending, !hasPendingCreation,
              validOwner(), let window = binding?.window, canvas?.window === window else { return nil }
        let views = ownedViews
        let pages = views.compactMapValues(\.nativePage)
        guard views.count == pages.count, pages.values.allSatisfy({
            !$0.isClosed && $0.isEmbedded && $0.embeddedOwnerValid
                && PCNativeBrowserApplication.owner(of: $0) === binding
        }), views.values.allSatisfy({ $0.window === window }) else { return nil }
        return WindowTransfer(owner: token, generation: windowTransferGeneration, entryIDs: entries.mapValues(\.identity),
            objects: Dictionary(uniqueKeysWithValues: session.document.items.filter { entries[$0.id] != nil }.map { ($0.id, $0) }),
            views: views, pages: pages)
    }
    func isCurrent(_ transfer: WindowTransfer, checkingDocument: Bool = true) -> Bool {
        guard !disposed, transfer.owner == token, transfer.generation == windowTransferGeneration,
              !retirementPending, !hasPendingCreation,
              windowTransfer == nil || windowTransfer === transfer else { return false }
        if checkingDocument {
            guard entries.mapValues(\.identity) == transfer.entryIDs,
                  Dictionary(uniqueKeysWithValues: session.document.items.filter { transfer.entryIDs[$0.id] != nil }.map { ($0.id, $0) }) == transfer.objects else { return false }
        }
        return transfer.pages.allSatisfy { id, page in
            page.isClosed || (transfer.views[id]?.nativePage === page
                && entries.values.contains { $0.identity == id && $0.view.browser === transfer.views[id] && $0.page === page })
        } && pages.allSatisfy { page in transfer.pages.values.contains { $0 === page } }
    }
    func beginWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard windowTransfer == nil, isCurrent(transfer) else { return false }
        windowTransfer = transfer
        refreshVisibility()
        return true
    }
    func rebindWindowTransfer(_ transfer: WindowTransfer, binding: PCNativeBrowserWindow,
                             profilePath: String, validOwner: @escaping () -> Bool,
                             activeOwner: @escaping () -> Bool, selectionChanged: @escaping () -> Void,
                             metadataChanged: @escaping () -> Void) -> Bool {
        guard windowTransfer === transfer, self.profilePath == profilePath,
              isCurrent(transfer, checkingDocument: false), let window = binding.window,
              canvas?.window === window, transfer.pages.allSatisfy({ id, page in
                  page.isClosed || (page.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: page) === binding
                      && transfer.views[id]?.window === window)
              }) else { return false }
        self.binding = binding; self.validOwner = validOwner; self.activeOwner = activeOwner
        self.selectionChanged = selectionChanged; self.metadataChanged = metadataChanged
        return true
    }
    func canFinishWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard windowTransfer === transfer, isCurrent(transfer, checkingDocument: false),
              let binding, canvas?.window === binding.window else { return false }
        return transfer.pages.values.allSatisfy {
            $0.isClosed || ($0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === binding)
        }
    }
    func finishWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard canFinishWindowTransfer(transfer) else { return false }
        windowTransfer = nil
        windowTransferGeneration &+= 1
        // The collection clears all pool/window gates before its ordinary
        // render/layout publication. No callback can interleave this release.
        return true
    }

    var ownedViews: [UUID: PCBrowserView] {
        Dictionary(uniqueKeysWithValues: entries.values.filter { $0.page?.isClosed == false }.map { ($0.identity, $0.view.browser) })
    }
    func reveal(_ page: PCNativePage) {
        guard let id = entries.first(where: { $0.value.page === page })?.key, validOwner() else { return }
        canvas?.selectBrowserObject(id)
        selectionChanged()
        if selectedPage === page { canvas?.window?.makeFirstResponder(page.nativeView) }
    }
    /// Native keyboard/AX entry uses the same selected original page as pointer
    /// interaction. A loading/error surface can focus its real recovery control.
    func focusPage(for id: UUID) -> Bool {
        guard let surface = accessibilitySurface(for: id) as? EaselBrowserSurface,
              let window = surface.window, window.attachedSheet == nil else { return false }
        if let page = entries[id]?.page, !page.isClosed {
            guard selectedPage === page, page.nativeView.window === window,
                  page.nativeView.isDescendant(of: surface) else { return false }
            if surface.showsRecovery { return surface.focusRecovery() }
            return window.makeFirstResponder(page.nativeView)
        }
        return surface.focusRecovery()
    }
    func accessibilitySurface(for id: UUID) -> NSView? {
        guard !disposed, !session.isClosed, !session.isDeleted, windowTransfer == nil, !retirementPending, validOwner(), activeOwner(),
              interacting, selectedID == id, let entry = entries[id], entry.view.interactive,
              entry.view.window === binding?.window, !entry.view.isHiddenOrHasHiddenAncestor,
              session.document.items.contains(where: { $0.id == id && entry.matches($0) }) else { return nil }
        if let page = entry.page, !page.isClosed,
           !page.embeddedOwnerValid || PCNativeBrowserApplication.owner(of: page) !== binding { return nil }
        return entry.view
    }
    static func excludesFromKeyboardNavigation(_ view: NSView) -> Bool {
        (view as? EaselBrowserSurface).map { !$0.inputAvailable } ?? false
    }
    var pages: [PCNativePage] { entries.values.compactMap { $0.page }.filter { !$0.isClosed } }
    /// An engine without the embedded snapshot, a refused or empty reply and a
    /// surface not yet laid out all leave their object to the export's card.
    func exportSnapshots(within deadline: TimeInterval, _ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) {
        let collection = SnapshotCollection(completion)
        for (id, entry) in entries where !disposed && session.document.items.contains(where: { $0.id == id && entry.matches($0) }) {
            let area = entry.view.pageArea
            guard let page = entry.page, !page.isClosed, page.embeddedOwnerValid, !area.page.isEmpty, !area.visible.isEmpty,
                  page.responds(to: #selector(PCNativePage.snapshotEmbeddedPage(completion:))) else { continue }
            collection.request()
            let started = page.snapshotEmbeddedPage { result in
                MainActor.assumeIsolated {
                    collection.receive(id, result.image.map { EaselPageSnapshot(image: $0, pageFrame: area.page, visibleFrame: area.visible) })
                }
            }
            if !started { collection.receive(id, nil) }
        }
        collection.requested()
        DispatchQueue.main.asyncAfter(deadline: .now() + deadline) { MainActor.assumeIsolated { collection.expire() } }
    }
    /// Replies once: when every requested page has answered, or at the deadline
    /// with what has arrived.
    @MainActor private final class SnapshotCollection {
        private var snapshots: [UUID: EaselPageSnapshot] = [:]
        private var pending = 0, requesting = true, delivered = false
        private let completion: ([UUID: EaselPageSnapshot]) -> Void
        init(_ completion: @escaping ([UUID: EaselPageSnapshot]) -> Void) { self.completion = completion }
        func request() { pending += 1 }
        func receive(_ id: UUID, _ snapshot: EaselPageSnapshot?) {
            guard !delivered else { return }
            if let snapshot { snapshots[id] = snapshot }
            pending -= 1; finish()
        }
        func requested() { requesting = false; finish() }
        func expire() { requesting = false; pending = 0; finish() }
        private func finish() {
            guard !delivered, !requesting, pending == 0 else { return }
            delivered = true; completion(snapshots)
        }
    }
    var hasPendingCreation: Bool { entries.values.contains { $0.request != nil } }
    var selectedPage: PCNativePage? {
        guard !disposed, windowTransfer == nil, validOwner(), activeOwner(), interacting, let id = selectedID,
              let entry = entries[id], entry.view.window === binding?.window,
              !entry.view.isHiddenOrHasHiddenAncestor, let page = entry.page, !page.isClosed, page.embeddedOwnerValid else { return nil }
        return page
    }
    var visiblePages: [PCNativePage] {
        guard !disposed, windowTransfer == nil, validOwner() else { return [] }
        return entries.values.compactMap { entry in
            guard entry.view.window === binding?.window, !entry.view.isHiddenOrHasHiddenAncestor,
                  !entry.view.visibleRect.isEmpty, let page = entry.page, !page.isClosed, page.embeddedOwnerValid else { return nil }
            return page
        }
    }
    func contains(_ page: PCNativePage) -> Bool { entries.values.contains { $0.page === page } }
    func container(for page: PCNativePage) -> NSView? { entries.values.first { $0.page === page }?.view.browser }

    func surface(for item: EaselItem) -> NSView? {
        guard item.ownsEmbeddedPage, let url = item.url, !disposed else { return nil }
        if let existing = entries[item.id] { return existing.view }
        let entry = Entry(url: url, profilePath: profilePath, captureLayout: item.captureLayout)
        entry.view.browser.delegate = self
        entry.view.setStatus("Loading webpage…")
        entry.view.onLayout = { [weak self, weak entry] in
            guard let self, let entry else { return }; self.start(item.id, entry: entry)
        }
        entry.view.onRetry = { [weak self, weak entry] in
            guard let self, let entry, self.entries[item.id] === entry else { return }
            if let page = entry.page, !page.isClosed {
                if let crash = page.rendererCrash { _ = page.performRendererCrashAction(crash) }
                else { _ = page.performNavigation(.reload, inNewTab: false) }
            }
            else { entry.started = false; self.start(item.id, entry: entry) }
        }
        entry.view.onNavigate = { [weak self, weak entry] url in
            guard let self, let entry, self.entries[item.id] === entry,
                  self.selectedPage === entry.page, !self.retirementPending,
                  entry.view.window?.attachedSheet == nil, let page = entry.page,
                  page.embeddedOwnerValid, page.canPerformNavigation(.reload) else { return false }
            entry.view.browser.loadURL(url) // Chromium owns navigation/beforeunload, not canvas replacement.
            return true
        }
        entry.view.onDone = { [weak self, weak entry] in
            guard let self, let entry, self.entries[item.id] === entry,
                  self.accessibilitySurface(for: item.id) === entry.view, let canvas = self.canvas,
                  let window = canvas.window, window.attachedSheet == nil else { return }
            canvas.cancelOperation(nil); window.makeFirstResponder(canvas)
            canvas.layoutSubtreeIfNeeded()
        }
        entry.view.onSnapshot = { [weak self] in self?.canvas?.setLiveCapture(item.id, enabled: false) }
        entries[item.id] = entry
        return entry.view
    }

    private func start(_ id: UUID, entry: Entry) {
        guard !entry.started, !disposed, windowTransfer == nil, !retirementPending, validOwner(),
              entries[id] === entry, let canvas, let binding,
              canvas.window === binding.window, !canvas.isHiddenOrHasHiddenAncestor,
              entry.view.window === binding.window, !entry.view.visibleRect.isEmpty,
              session.document.items.contains(where: { $0.id == id && entry.matches($0) }),
              let url = URL(string: entry.originalURL) else { return }
        entry.started = true
        entry.attempt = UUID(); let attempt = entry.attempt
        entry.view.setStatus("Loading webpage…")
        Self.owners[token] = self // Keep a refused actual close owned, never orphaned.
        let validate = { [weak self, weak entry, weak binding] in
            guard let self, let entry, let binding else { return false }
            return !self.disposed && self.windowTransfer == nil && !self.retirementPending && self.validOwner()
                && self.entries[id] === entry && self.canvas?.window === binding.window
                && entry.view.window === binding.window && !entry.view.isHiddenOrHasHiddenAncestor
                && self.session.document.items.contains { $0.id == id && entry.matches($0) }
        }
        entry.request = entry.view.browser.beginEmbeddedNavigation(url, validateOwner: validate) { [weak self, weak entry] page, error in
            MainActor.assumeIsolated {
                guard let self, let entry else { return }
                guard entry.attempt == attempt, self.entries[id] === entry else { return }
                entry.request = nil
                if let page {
                    entry.retainedPage = page
                    entry.view.setStatus(nil); entry.view.refresh()
                    self.recordURL(entry.view.browser)
                    self.selectionChanged()
                    if page.isClosed { self.didClose(page) }
                } else {
                    entry.view.setStatus(error?.localizedDescription ?? "The webpage could not open.", retry: true)
                    self.releaseIfIdle()
                }
            }
        }
        if entry.request == nil { entry.view.setStatus("This webpage owner is unavailable.", retry: true); releaseIfIdle() }
    }

    func synchronize(items: [EaselItem], selection: Set<UUID>, interacting: Bool) {
        let before = selectedPage
        self.interacting = interacting && !retirementPending
        selectedID = selection.count == 1 ? selection.first : nil
        let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (id, entry) in Array(entries) {
            if current[id].map(entry.matches) != true {
                entry.cancelRequest()
                if entry.page?.isClosed != false && entry.request == nil { entry.view.removeFromSuperview(); entries.removeValue(forKey: id) }
            }
            entry.view.validateInput()
            entry.view.positioningAllowed = !disposed && validOwner() && windowTransfer == nil && !retirementPending
            entry.view.interactive = self.interacting && selectedID == id && activeOwner() && validOwner() && windowTransfer == nil
            entry.view.refresh()
        }
        if before !== selectedPage { selectionChanged() }
        releaseIfIdle()
    }
    func refreshVisibility() {
        let before = selectedPage
        for (id, entry) in entries {
            entry.view.validateInput()
            entry.view.positioningAllowed = !disposed && validOwner() && windowTransfer == nil && !retirementPending
            entry.view.interactive = interacting && selectedID == id && activeOwner() && validOwner() && windowTransfer == nil && !retirementPending
            entry.view.refresh()
        }
        if before !== selectedPage { selectionChanged() }
    }

    func prepareReplacement(_ next: EaselDocument, valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        let original = session.document
        guard valid(), windowTransfer == nil, !retirementPending else { completion(false); return }
        let owners = Self.owners.values.filter { $0.session === session }
        let targets = owners.flatMap { owner in owner.entries.compactMap { id, entry -> (EaselBrowserObjects, Entry)? in
            next.items.contains { $0.id == id && entry.matches($0) } ? nil : (owner, entry)
        } }
        for (_, entry) in targets { entry.cancelRequest() }
        let pages = targets.compactMap { $0.1.page }.filter { !$0.isClosed }
        guard !pages.isEmpty else { completion(valid() && session.document == original); return }
        guard owners.allSatisfy({ !$0.retirementPending && $0.windowTransfer == nil }) else { completion(false); return }
        owners.forEach { $0.retirementPending = true; $0.refreshVisibility() }
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return valid() && self.session.document == original && targets.allSatisfy { owner, entry in
                    owner.validOwner() && owner.entries.values.contains { $0 === entry }
                }
            }
        }, completion: { [weak self] allowed in
            MainActor.assumeIsolated {
                owners.forEach { $0.retirementPending = false; $0.refreshVisibility() }
                guard let self else { completion(false); return }
                completion(allowed && valid() && self.session.document == original)
            }
        })
    }

    func didClose(_ page: PCNativePage) {
        guard let entry = entries.values.first(where: { $0.page === page }) else { return }
        entry.view.cancelPositioning()
        entry.view.setStatus("Webpage closed", retry: true); entry.view.refresh()
        selectionChanged(); releaseIfIdle()
    }
    func disposeAfterClosure() {
        disposed = true
        entries.values.forEach { $0.view.positioningAllowed = false; $0.cancelRequest() }
        // Parent/tab retirement must already have closed every page. If a
        // caller violates that boundary, retain the real owner rather than
        // silently destroying or re-creating its WebContents.
        guard pages.isEmpty && !hasPendingCreation else { return }
        entries.values.forEach { $0.view.cancelPositioning(); $0.view.browser.delegate = nil; $0.view.removeFromSuperview() }; entries.removeAll()
        if let replacementObserver { session.removeReplacementObserver(replacementObserver); self.replacementObserver = nil }
        documentObserver = nil
        Self.owners.removeValue(forKey: token)
    }
    private func releaseIfIdle() {
        if pages.isEmpty && !hasPendingCreation {
            Self.owners.removeValue(forKey: token)
            if disposed { disposeAfterClosure() }
        }
    }
    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) {
        guard selectedPage === view.nativePage, image.isValid, validOwner() else { return }
        onContextImage?(view, image)
    }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) {
        guard let entry = entries.values.first(where: { $0.view.browser === view }) else { return }
        let previous = entry.crash; entry.crash = crash
        if let crash {
            //
            //
            entry.view.setStatus(SadTabContent.plainMessage, retry: true)
            entry.view.setRetryTitle(crash.actionTitle)
            if selectedPage === entry.page { _ = entry.page?.rendererCrashDidPresent(crash) }
        } else if previous != nil { entry.view.setStatus(nil); entry.view.setRetryTitle("Retry") }
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) {
        guard let entry = entries.values.first(where: { $0.view.browser === view }),
              entry.page?.rendererCrash === crash, selectedPage === entry.page else { return }
        entry.view.focusRetry()
    }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) { scheduleMetadataRefresh() }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) { refresh(view) }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) { recordURL(view); refresh(view) }
    private func recordURL(_ view: PCBrowserView) {
        guard !disposed, !retirementPending, validOwner(), let page = view.nativePage, !page.isClosed,
              page.embeddedOwnerValid, selectedPage === page, let url = page.url,
              let (id, entry) = entries.first(where: { $0.value.view.browser === view && $0.value.page === page }),
              entry.request == nil, entry.captureLayout == nil else { return }
        do { _ = try session.recordBrowserNavigation(url, itemID: id, expectedURL: entry.originalURL) }
        catch EaselStoreError.browserInUse { /* A different owner is still admitting its page. Retry on its next metadata event. */ }
        catch { onError?(error) }
    }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack back: Bool, canGoForward forward: Bool) {
        if let entry = entries.values.first(where: { $0.view.browser === view }) {
            if loading != entry.wasLoading {
                if loading { entry.view.cancelPositioning() }
                else { entry.view.positionCapture(force: true) }
            }
            entry.wasLoading = loading
        }
        if !loading { recordURL(view) }
        refresh(view)
    }
    /// The engine learned a FairPlay site for Safari's identity (docs/fairplay-identity.md).
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        entries.values.first { $0.view.browser === view }?.view.setStatus(error.localizedDescription, retry: true)
    }
    func browserViewDidRequestClose(_ view: PCBrowserView) { if let page = entries.values.first(where: { $0.view.browser === view })?.page { didClose(page) } }
    private func refresh(_ view: PCBrowserView) {
        entries.values.first { $0.view.browser === view }?.view.refresh()
        scheduleMetadataRefresh()
    }
    private func scheduleMetadataRefresh() {
        guard !disposed, !metadataRefreshPending else { return }
        metadataRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.metadataRefreshPending = false
            if !self.disposed { self.metadataChanged() }
        }
    }
}

/// The native page stays intact below a canvas input blocker. A separate
/// control strip makes current security/navigation state available without
/// replaying a durable URL update back into the live navigation stack.
@MainActor
private final class EaselBrowserSurface: NSView {
    let browser: PCBrowserView
    private let captureLayout: EaselCaptureLayout?
    private let clip = EaselLiveCaptureClip()
    private var positioning: PCNativeLiveCapturePosition?
    private var positionGeneration: UInt64 = 0
    private var positionedWidth: CGFloat = 0
    private var positionedZoom: Double = 0
    var positioningAllowed = true {
        didSet {
            guard positioningAllowed != oldValue else { return }
            if !positioningAllowed, positioning != nil { cancelPositioning() }
            if positioningAllowed { needsLayout = true }
        }
    }
    var onSnapshot: (() -> Void)?
    private let snapshot = NSButton(title: "Snapshot", target: nil, action: nil)
    var interactive = false { didSet { if oldValue != interactive { if !interactive { input?.cancel(restoreFocus: false) }; needsLayout = true } } }
    var onLayout: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDone: (() -> Void)?
    var onNavigate: ((URL) -> Bool)?
    private var input: EaselWebInput?
    private var lastDraft = EaselWebNavigation.Draft()
    private let label = NSButton(title: "Webpage", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let cover = NSView()
    private let retry = NSButton(title: "Retry", target: nil, action: nil)
    private let back = NSButton(), forward = NSButton(), reload = NSButton(), done = NSButton()
    private let security = NSButton()
    var inputAvailable: Bool {
        interactive && (browser.nativePage?.isClosed != false || browser.nativePage?.embeddedOwnerValid == true)
    }
    override var isFlipped: Bool { true }
    init(profilePath: String, captureLayout: EaselCaptureLayout?) {
        self.captureLayout = captureLayout
        browser = PCBrowserView(frame: .zero, profilePath: profilePath)
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.masksToBounds = true
        clip.wantsLayer = true; clip.layer?.masksToBounds = true
        addSubview(clip); clip.addSubview(browser)
        cover.wantsLayer = true; cover.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor; cover.isHidden = true
        addSubview(cover); addSubview(label); addSubview(status); addSubview(retry)
        snapshot.target = self; snapshot.action = #selector(showSnapshot); snapshot.isHidden = captureLayout == nil
        snapshot.toolTip = "Return to the original captured image"; addSubview(snapshot)
        label.font = .systemFont(ofSize: 11); label.lineBreakMode = .byTruncatingMiddle
        label.isBordered = false; label.alignment = .left; label.target = self; label.action = #selector(editAddress)
        label.setAccessibilityLabel("Edit webpage address or search")
        status.font = .systemFont(ofSize: 12); status.alignment = .center; status.textColor = .secondaryLabelColor
        for (button, title, symbol, selector) in [(back,"Back","chevron.left",#selector(goBack)),(forward,"Forward","chevron.right",#selector(goForward)),(reload,"Reload","arrow.clockwise",#selector(reloadOrStop)),(done,"Return to Easel","checkmark",#selector(finish)),(security,"Site information","lock",#selector(siteInfo))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.bezelStyle = .texturedRounded; button.toolTip = title; button.setAccessibilityLabel(title)
            button.target = self; button.action = selector; addSubview(button)
        }
        retry.target = self; retry.action = #selector(retryPage)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = EaselAppearance.surface.cgColor }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func layout() {
        super.layout()
        clip.frame = NSRect(x: 0, y: 32, width: bounds.width, height: max(1, bounds.height - 32))
        if let captureLayout {
            let zoom = browser.nativePage?.liveCaptureZoomFactor ?? 1
            let width = min(bounds.width, max(1, bounds.height - 32) * captureLayout.region.width / captureLayout.region.height,
                            captureLayout.viewport.x * zoom, captureLayout.viewport.y * zoom * captureLayout.region.width / captureLayout.region.height)
            let height = width * captureLayout.region.height / captureLayout.region.width
            clip.frame = NSRect(x: (bounds.width - width) / 2, y: 32 + (max(1, bounds.height - 32) - height) / 2, width: width, height: height)
            browser.frame = NSRect(x: 0, y: 0, width: captureLayout.viewport.x * zoom, height: captureLayout.viewport.y * zoom)
            clip.isHidden = false
            positionCapture()
        } else { browser.frame = clip.bounds }
        back.frame = NSRect(x: 4, y: 3, width: 25, height: 25)
        forward.frame = NSRect(x: 30, y: 3, width: 25, height: 25)
        reload.frame = NSRect(x: 56, y: 3, width: 25, height: 25)
        done.frame = NSRect(x: max(82, bounds.width - 30), y: 3, width: 25, height: 25)
        security.frame = NSRect(x: 82, y: 3, width: 25, height: 25)
        label.frame = NSRect(x: 140, y: 9, width: max(0, bounds.width - 178), height: 17)
        status.frame = NSRect(x: 14, y: max(38, bounds.midY - 25), width: max(0, bounds.width - 28), height: 48)
        retry.frame = NSRect(x: max(0, bounds.midX - 40), y: min(bounds.maxY - 32, status.frame.maxY), width: 80, height: 26)
        cover.frame = clip.frame
        snapshot.frame = NSRect(x: 110, y: 3, width: 80, height: 25)
        if captureLayout != nil { label.isHidden = true; back.isHidden = true; forward.isHidden = true }
        onLayout?()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactive else { return nil } // Canvas owns select/move/marquee.
        return super.hitTest(point)
    }
    /// Where the page's pixels sit in this surface, and the part of them shown.
    var pageArea: (page: NSRect, visible: NSRect) { (convert(browser.bounds, from: browser), clip.frame) }
    func setRetryTitle(_ title: String) { retry.title = title }
    func focusRetry() { if interactive && !retry.isHidden { window?.makeFirstResponder(retry) } }
    var showsRecovery: Bool { !status.isHidden || browser.nativePage?.rendererCrash != nil }
    func focusRecovery() -> Bool {
        guard interactive, let window else { return false }
        return window.makeFirstResponder(retry.isHidden ? done : retry)
    }
    override func cancelOperation(_ sender: Any?) {
        if input != nil { input?.cancel(); return }
        if interactive { onDone?() }
    }
    override func accessibilityChildren() -> [Any]? { inputAvailable ? super.accessibilityChildren() : [] }
    func setStatus(_ text: String?, retry retryVisible: Bool = false) {
        status.stringValue = text ?? ""; status.isHidden = text == nil; retry.isHidden = !retryVisible
        cover.isHidden = captureLayout == nil || text == nil; needsLayout = true
    }
    func refresh() {
        input?.validate()
        let page = browser.nativePage
        let interactive = inputAvailable
        label.title = page?.url?.host ?? "Webpage"
        label.isEnabled = interactive && page?.canPerformNavigation(.reload) == true
        label.toolTip = page?.url?.absoluteString
        back.isEnabled = interactive && page?.canPerformNavigation(.back) == true
        forward.isEnabled = interactive && page?.canPerformNavigation(.forward) == true
        let action: PCNativeNavigationAction = browser.isLoading ? .stop : .reload
        reload.isEnabled = interactive && page?.canPerformNavigation(action) == true
        reload.image = NSImage(systemSymbolName: browser.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: browser.isLoading ? "Stop" : "Reload")
        done.isEnabled = interactive; retry.isEnabled = interactive; snapshot.isEnabled = interactive
        setAccessibilityHidden(!interactive)
        security.isEnabled = interactive && browser.canShowSiteInfo
    }
    func validateInput() { input?.validate() }
    @objc private func editAddress() {
        guard interactive, let page = browser.nativePage, page.embeddedOwnerValid else { return }
        input?.cancel()
        var draft = lastDraft
        if draft.mode == .address { draft.text = page.url?.absoluteString ?? "" }
        let editor = EaselWebInput(draft: draft, validOwner: { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.interactive && self.browser.nativePage === page && !page.isClosed && page.embeddedOwnerValid
        }, submit: { [weak self] url, draft in
            guard let self, self.onNavigate?(url) == true else { return false }
            self.lastDraft = draft; return true
        })
        input = editor
        editor.onClose = { [weak self, weak editor] in if self?.input === editor { self?.input = nil } }
        if !editor.show(from: label) { editor.cancel(restoreFocus: false) }
    }
    func cancelPositioning() {
        positionGeneration &+= 1; positioning?.cancel(); positioning = nil
        positionedWidth = 0; positionedZoom = 0
    }
    func positionCapture(force: Bool = false) {
        guard positioningAllowed, let layout = captureLayout, let page = browser.nativePage, !page.isClosed,
              page.embeddedOwnerValid, !browser.isLoading, window != nil else { return }
        let zoom = page.liveCaptureZoomFactor
        let width = min(clip.bounds.width, clip.bounds.height * layout.region.width / layout.region.height)
        guard width > 0, zoom.isFinite, zoom > 0,
              force || positionedWidth != width || positionedZoom != zoom else { return }
        cancelPositioning(); positionedWidth = width; positionedZoom = zoom
        let generation = positionGeneration
        browser.frame = NSRect(x: 0, y: 0, width: layout.viewport.x * zoom, height: layout.viewport.y * zoom)
        setStatus("Positioning live capture…")
        // Keep the renderer attached and sized while positioning; cover it until
        // its real document acknowledges the captured offset.
        positioning = page.positionLiveCapture(NSRect(x: layout.region.x, y: layout.region.y,
            width: layout.region.width, height: layout.region.height),
            scrollOffset: NSPoint(x: layout.scroll.x, y: layout.scroll.y), displayWidth: width) { [weak self, weak page] success in
                MainActor.assumeIsolated {
                    guard let self, let page, self.positionGeneration == generation,
                          self.browser.nativePage === page, page.embeddedOwnerValid else { return }
                    self.positioning = nil
                    self.setStatus(success ? nil : "This page could not align with the captured region.", retry: !success)
                }
            }
        if positioning == nil { setStatus("Live capture is unavailable for this page.", retry: true) }
    }
    @objc private func showSnapshot() { onSnapshot?() }
    @objc private func goBack() { _ = browser.nativePage?.performNavigation(.back, inNewTab: false) }
    @objc private func goForward() { _ = browser.nativePage?.performNavigation(.forward, inNewTab: false) }
    @objc private func reloadOrStop() { _ = browser.nativePage?.performNavigation(browser.isLoading ? .stop : .reload, inNewTab: false) }
    @objc private func siteInfo() { _ = browser.showSiteInfo(from: security) }
    @objc private func finish() { onDone?() }
    @objc private func retryPage() { onRetry?() }
}

@MainActor
private final class EaselLiveCaptureClip: NSView {
    override var isFlipped: Bool { true }
}
