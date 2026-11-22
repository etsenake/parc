import AppKit
import ParcCore
import ParcEngine

@MainActor
protocol EmbeddedPageOwner: AnyObject {
    var embeddedPagesOpen: Bool { get }
    func embeddedPage(_ id: UUID, wants url: String, variant: EmbeddedPageFingerprint?) -> Bool
    func embeddedPageFingerprint(for ids: Set<UUID>) -> EmbeddedPageFingerprint
    func recordEmbeddedPageNavigation(_ url: URL, for id: UUID, expectedURL: String) throws
}

@MainActor
protocol EmbeddedPageSurface: NSView {
    var browser: PCBrowserView { get }
    var interactive: Bool { get set }
    var positioningAllowed: Bool { get set }
    var inputAvailable: Bool { get }
    var showsRecovery: Bool { get }
    var pageArea: (page: NSRect, visible: NSRect) { get }
    var onLayout: (() -> Void)? { get set }
    var onRetry: (() -> Void)? { get set }
    var onNavigate: ((URL) -> Bool)? { get set }
    var onDone: (() -> Void)? { get set }
    func setStatus(_ text: String?, retry: Bool)
    func setRetryTitle(_ title: String)
    func refresh()
    func validateInput()
    func cancelPositioning()
    func positionCapture(force: Bool)
    func focusRecovery() -> Bool
    func focusRetry()
}

@MainActor
protocol EmbeddedKeyLoopMember: NSView {
    var keyLoopAvailable: Bool { get }
}

@MainActor
final class EmbeddedPageEntry {
    let identity = UUID()
    var originalURL: String
    let surface: EmbeddedPageSurface
    let variant: EmbeddedPageFingerprint?
    var request: PCNativeEmbeddedPageRequest?
    var started = false
    var wasLoading = true
    var crash: PCNativeRendererCrash?
    var retainedPage: PCNativePage?
    var page: PCNativePage? { surface.browser.nativePage ?? retainedPage }
    var attempt = UUID()
    func cancelRequest() {
        request?.cancel()
        guard request?.isPending != true else { return }
        attempt = UUID(); request = nil
    }
    init(url: String, variant: EmbeddedPageFingerprint?, surface: EmbeddedPageSurface) {
        originalURL = url; self.variant = variant; self.surface = surface
    }
}

@MainActor
class EmbeddedPagePool: NSObject, PCBrowserViewDelegate {
    private static var owners: [UUID: EmbeddedPagePool] = [:]
    static var liveOwners: [EmbeddedPagePool] { Array(owners.values) }
    let token = UUID()
    let owner: EmbeddedPageOwner
    weak var hostView: NSView?
    private(set) weak var binding: PCNativeBrowserWindow?
    let profilePath: String
    private(set) var validOwner: () -> Bool
    private(set) var activeOwner: () -> Bool
    private var selectionChanged: () -> Void
    private var metadataChanged: () -> Void
    private var metadataRefreshPending = false
    var scheduleMetadataDelivery: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.async { work() }
    }
    var entries: [UUID: EmbeddedPageEntry] = [:]
    private(set) var selectedID: UUID?
    private(set) var interacting = false
    var gate = EmbeddedPageOwnerGate()
    private(set) var windowTransfer: WindowTransfer?
    var onError: ((Error) -> Void)?
    var onContextImage: ((PCBrowserView, PCNativeContextImage) -> Void)?

    init(owner: EmbeddedPageOwner, hostView: NSView, binding: PCNativeBrowserWindow,
         profilePath: String, validOwner: @escaping () -> Bool,
         activeOwner: @escaping () -> Bool, selectionChanged: @escaping () -> Void,
         metadataChanged: @escaping () -> Void) {
        self.owner = owner; self.hostView = hostView; self.binding = binding; self.profilePath = profilePath
        self.validOwner = validOwner; self.activeOwner = activeOwner; self.selectionChanged = selectionChanged
        self.metadataChanged = metadataChanged
        super.init()
    }

    var disposed: Bool { gate.isDisposed }
    var retirementPending: Bool { gate.isRetiring }

    func wants(_ id: UUID, _ entry: EmbeddedPageEntry) -> Bool {
        owner.embeddedPage(id, wants: entry.originalURL, variant: entry.variant)
    }

    final class WindowTransfer {
        fileprivate let generation: UInt64
        fileprivate let owner: UUID
        fileprivate let entryIDs: [UUID: UUID]
        fileprivate let fingerprint: EmbeddedPageFingerprint
        let views: [UUID: PCBrowserView]
        let pages: [UUID: PCNativePage]
        fileprivate init(owner: UUID, generation: UInt64, entryIDs: [UUID: UUID], fingerprint: EmbeddedPageFingerprint,
                         views: [UUID: PCBrowserView], pages: [UUID: PCNativePage]) {
            self.owner = owner; self.generation = generation; self.entryIDs = entryIDs; self.fingerprint = fingerprint
            self.views = views; self.pages = pages
        }
    }
    func snapshotForWindowTransfer() -> WindowTransfer? {
        guard gate.admitsTransferSnapshot, windowTransfer == nil, !hasPendingCreation,
              validOwner(), let window = binding?.window, hostView?.window === window else { return nil }
        let views = ownedViews
        let pages = views.compactMapValues(\.nativePage)
        guard views.count == pages.count, pages.values.allSatisfy({
            !$0.isClosed && $0.isEmbedded && $0.embeddedOwnerValid
                && PCNativeBrowserApplication.owner(of: $0) === binding
        }), views.values.allSatisfy({ $0.window === window }) else { return nil }
        return WindowTransfer(owner: token, generation: gate.transferGeneration, entryIDs: entries.mapValues(\.identity),
            fingerprint: owner.embeddedPageFingerprint(for: Set(entries.keys)), views: views, pages: pages)
    }
    func isCurrent(_ transfer: WindowTransfer, checkingDocument: Bool = true) -> Bool {
        guard transfer.owner == token, gate.admitsTransfer(generation: transfer.generation), !hasPendingCreation,
              windowTransfer == nil || windowTransfer === transfer else { return false }
        if checkingDocument {
            guard entries.mapValues(\.identity) == transfer.entryIDs,
                  owner.embeddedPageFingerprint(for: Set(transfer.entryIDs.keys)) == transfer.fingerprint else { return false }
        }
        return transfer.pages.allSatisfy { id, page in
            page.isClosed || (transfer.views[id]?.nativePage === page
                && entries.values.contains { $0.identity == id && $0.surface.browser === transfer.views[id] && $0.page === page })
        } && pages.allSatisfy { page in transfer.pages.values.contains { $0 === page } }
    }
    func beginWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard windowTransfer == nil, isCurrent(transfer), gate.beginTransfer(generation: transfer.generation) else { return false }
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
              hostView?.window === window, transfer.pages.allSatisfy({ id, page in
                  page.isClosed || (page.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: page) === binding
                      && transfer.views[id]?.window === window)
              }) else { return false }
        self.binding = binding; self.validOwner = validOwner; self.activeOwner = activeOwner
        self.selectionChanged = selectionChanged; self.metadataChanged = metadataChanged
        return true
    }
    func canFinishWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard windowTransfer === transfer, isCurrent(transfer, checkingDocument: false),
              let binding, hostView?.window === binding.window else { return false }
        return transfer.pages.values.allSatisfy {
            $0.isClosed || ($0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === binding)
        }
    }
    func finishWindowTransfer(_ transfer: WindowTransfer) -> Bool {
        guard canFinishWindowTransfer(transfer) else { return false }
        windowTransfer = nil
        gate.finishTransfer()
        return true
    }

    var ownedViews: [UUID: PCBrowserView] {
        Dictionary(uniqueKeysWithValues: entries.values.filter { $0.page?.isClosed == false }.map { ($0.identity, $0.surface.browser) })
    }
    func revealEntry(_ id: UUID) {}
    func reveal(_ page: PCNativePage) {
        guard let id = entries.first(where: { $0.value.page === page })?.key, validOwner() else { return }
        revealEntry(id)
        selectionChanged()
        if selectedPage === page { hostView?.window?.makeFirstResponder(page.nativeView) }
    }
    func focusPage(for id: UUID) -> Bool {
        guard let surface = accessibilitySurface(for: id) as? EmbeddedPageSurface,
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
        guard !gate.isDisposed, owner.embeddedPagesOpen, gate.admitsInput, validOwner(), activeOwner(),
              interacting, selectedID == id, let entry = entries[id], entry.surface.interactive,
              entry.surface.window === binding?.window, !entry.surface.isHiddenOrHasHiddenAncestor,
              wants(id, entry) else { return nil }
        if let page = entry.page, !page.isClosed,
           !page.embeddedOwnerValid || PCNativeBrowserApplication.owner(of: page) !== binding { return nil }
        return entry.surface
    }
    static func excludesFromKeyboardNavigation(_ view: NSView) -> Bool {
        if let surface = view as? EmbeddedPageSurface { return !surface.inputAvailable }
        return (view as? EmbeddedKeyLoopMember).map { !$0.keyLoopAvailable } ?? false
    }
    var pages: [PCNativePage] { entries.values.compactMap { $0.page }.filter { !$0.isClosed } }
    var hasPendingCreation: Bool { entries.values.contains { $0.request != nil } }
    var selectedPage: PCNativePage? {
        guard gate.publishesPages, validOwner(), activeOwner(), interacting, let id = selectedID,
              let entry = entries[id], entry.surface.window === binding?.window,
              !entry.surface.isHiddenOrHasHiddenAncestor, let page = entry.page, !page.isClosed, page.embeddedOwnerValid else { return nil }
        return page
    }
    var visiblePages: [PCNativePage] {
        guard gate.publishesPages, validOwner() else { return [] }
        return entries.values.compactMap { entry in
            guard entry.surface.window === binding?.window, !entry.surface.isHiddenOrHasHiddenAncestor,
                  !entry.surface.visibleRect.isEmpty, let page = entry.page, !page.isClosed, page.embeddedOwnerValid else { return nil }
            return page
        }
    }
    func contains(_ page: PCNativePage) -> Bool { entries.values.contains { $0.page === page } }
    func container(for page: PCNativePage) -> NSView? { entries.values.first { $0.page === page }?.surface.browser }

    func surface(id: UUID, url: String, variant: EmbeddedPageFingerprint?,
                 make: () -> EmbeddedPageSurface) -> EmbeddedPageEntry? {
        guard !gate.isDisposed else { return nil }
        if let existing = entries[id] { return existing }
        let entry = EmbeddedPageEntry(url: url, variant: variant, surface: make())
        entry.surface.browser.delegate = self
        entry.surface.setStatus("Loading webpage…", retry: false)
        entry.surface.onLayout = { [weak self, weak entry] in
            guard let self, let entry else { return }; self.start(id, entry: entry)
        }
        entry.surface.onRetry = { [weak self, weak entry] in
            guard let self, let entry, self.entries[id] === entry else { return }
            if let page = entry.page, !page.isClosed {
                if let crash = page.rendererCrash { _ = page.performRendererCrashAction(crash) }
                else { _ = page.performNavigation(.reload, inNewTab: false) }
            }
            else { entry.started = false; self.start(id, entry: entry) }
        }
        entry.surface.onNavigate = { [weak self, weak entry] url in
            guard let self, let entry, self.entries[id] === entry,
                  self.selectedPage === entry.page, !self.gate.isRetiring,
                  entry.surface.window?.attachedSheet == nil, let page = entry.page,
                  page.embeddedOwnerValid, page.canPerformNavigation(.reload) else { return false }
            entry.surface.browser.loadURL(url)
            return true
        }
        entries[id] = entry
        return entry
    }

    func start(_ id: UUID, entry: EmbeddedPageEntry) {
        guard !entry.started, gate.admitsCreation, validOwner(),
              entries[id] === entry, let hostView, let binding,
              hostView.window === binding.window, !hostView.isHiddenOrHasHiddenAncestor,
              entry.surface.window === binding.window, !entry.surface.visibleRect.isEmpty,
              wants(id, entry), let url = URL(string: entry.originalURL) else { return }
        entry.started = true
        entry.attempt = UUID(); let attempt = entry.attempt
        entry.surface.setStatus("Loading webpage…", retry: false)
        Self.owners[token] = self
        let validate = { [weak self, weak entry, weak binding] in
            guard let self, let entry, let binding else { return false }
            return self.gate.admitsCreation && self.validOwner()
                && self.entries[id] === entry && self.hostView?.window === binding.window
                && entry.surface.window === binding.window && !entry.surface.isHiddenOrHasHiddenAncestor
                && self.wants(id, entry)
        }
        entry.request = entry.surface.browser.beginEmbeddedNavigation(loadURL(for: url, entry: entry), referrer: referrer(for: entry),
                                                                      validateOwner: validate) { [weak self, weak entry] page, error in
            MainActor.assumeIsolated {
                guard let self, let entry else { return }
                guard entry.attempt == attempt, self.entries[id] === entry else { return }
                entry.request = nil
                if let page {
                    entry.retainedPage = page
                    entry.surface.setStatus(nil, retry: false); entry.surface.refresh()
                    self.recordURL(entry.surface.browser)
                    self.selectionChanged()
                    if page.isClosed { self.didClose(page) }
                } else {
                    entry.surface.setStatus(error?.localizedDescription ?? "The webpage could not open.", retry: true)
                    self.releaseIfIdle()
                }
            }
        }
        if entry.request == nil { entry.surface.setStatus("This webpage owner is unavailable.", retry: true); releaseIfIdle() }
    }

    func loadURL(for url: URL, entry: EmbeddedPageEntry) -> URL {
        (entry.surface as? NoteEmbedSurface)?.liveAddress ?? url
    }

    func referrer(for entry: EmbeddedPageEntry) -> URL? {
        guard (entry.surface as? NoteEmbedSurface)?.sendsAppReferrer == true else { return nil }
        return NoteEmbedAddress.embedderReferrer(appID: Bundle.main.bundleIdentifier)
    }

    func synchronize(wanted: (UUID, EmbeddedPageEntry) -> Bool, selection: UUID?, interacting: Bool) {
        let before = selectedPage
        self.interacting = interacting && !gate.isRetiring
        selectedID = selection
        for (id, entry) in Array(entries) {
            if !wanted(id, entry) {
                entry.cancelRequest()
                if entry.page?.isClosed != false && entry.request == nil { entry.surface.removeFromSuperview(); entries.removeValue(forKey: id) }
            }
            entry.surface.validateInput()
            entry.surface.positioningAllowed = gate.admitsPositioning && validOwner()
            entry.surface.interactive = self.interacting && selectedID == id && activeOwner() && validOwner() && !gate.isTransferring
            entry.surface.refresh()
        }
        if before !== selectedPage { selectionChanged() }
        releaseIfIdle()
    }
    func refreshVisibility() {
        let before = selectedPage
        for (id, entry) in entries {
            entry.surface.validateInput()
            entry.surface.positioningAllowed = gate.admitsPositioning && validOwner()
            entry.surface.interactive = interacting && selectedID == id && activeOwner() && validOwner() && gate.admitsInput
            entry.surface.refresh()
        }
        if before !== selectedPage { selectionChanged() }
    }

    static func requestRetirement(of targets: [(EmbeddedPagePool, EmbeddedPageEntry)], owners: [EmbeddedPagePool],
                           valid: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        for (_, entry) in targets { entry.cancelRequest() }
        let pages = targets.compactMap { $0.1.page }.filter { !$0.isClosed }
        guard !pages.isEmpty else { completion(valid()); return }
        guard owners.allSatisfy({ !$0.gate.isRetiring && !$0.gate.isTransferring }) else { completion(false); return }
        owners.forEach { $0.gate.beginRetirement(); $0.refreshVisibility() }
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: {
            MainActor.assumeIsolated {
                valid() && targets.allSatisfy { owner, entry in
                    owner.validOwner() && owner.entries.values.contains { $0 === entry }
                }
            }
        }, completion: { allowed in
            MainActor.assumeIsolated {
                owners.forEach { $0.gate.endRetirement(); $0.refreshVisibility() }
                completion(allowed && valid())
            }
        })
    }

    func didClose(_ page: PCNativePage) {
        guard let entry = entries.values.first(where: { $0.page === page }) else { return }
        entry.surface.cancelPositioning()
        entry.surface.setStatus("Webpage closed", retry: true); entry.surface.refresh()
        selectionChanged(); releaseIfIdle()
    }
    func disposeAfterClosure() {
        gate.dispose()
        entries.values.forEach { $0.surface.positioningAllowed = false; $0.cancelRequest() }
        guard pages.isEmpty && !hasPendingCreation else { return }
        entries.values.forEach { $0.surface.cancelPositioning(); $0.surface.browser.delegate = nil; $0.surface.removeFromSuperview() }; entries.removeAll()
        didDispose()
        Self.owners.removeValue(forKey: token)
    }
    func didDispose() {}
    func releaseIfIdle() {
        if pages.isEmpty && !hasPendingCreation {
            Self.owners.removeValue(forKey: token)
            if gate.isDisposed { disposeAfterClosure() }
        }
    }
    static func pageScrollBegan(momentum: Bool, from source: PCNativeHistorySwipeSource) {
        for pool in liveOwners { pool.pageScrollBegan(momentum: momentum, from: source) }
    }
    static func pageScrollUpdated(consumed: Bool, from source: PCNativeHistorySwipeSource) {
        for pool in liveOwners { pool.pageScrollUpdated(consumed: consumed, from: source) }
    }
    func pageScrollBegan(momentum: Bool, from source: PCNativeHistorySwipeSource) {}
    func pageScrollUpdated(consumed: Bool, from source: PCNativeHistorySwipeSource) {}
    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) {
        guard selectedPage === view.nativePage, image.isValid, validOwner() else { return }
        onContextImage?(view, image)
    }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) {
        guard let entry = entries.values.first(where: { $0.surface.browser === view }) else { return }
        let previous = entry.crash; entry.crash = crash
        if let crash {
            entry.surface.setStatus(SadTabContent.plainMessage, retry: true)
            entry.surface.setRetryTitle(crash.actionTitle)
            if selectedPage === entry.page { _ = entry.page?.rendererCrashDidPresent(crash) }
        } else if previous != nil { entry.surface.setStatus(nil, retry: false); entry.surface.setRetryTitle("Retry") }
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) {
        guard let entry = entries.values.first(where: { $0.surface.browser === view }),
              entry.page?.rendererCrash === crash, selectedPage === entry.page else { return }
        entry.surface.focusRetry()
    }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) { scheduleMetadataRefresh() }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) { refresh(view) }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) { recordURL(view); refresh(view) }
    func recordURL(_ view: PCBrowserView) {
        guard !gate.isDisposed, !gate.isRetiring, validOwner(), let page = view.nativePage, !page.isClosed,
              page.embeddedOwnerValid, selectedPage === page, let url = page.url,
              let (id, entry) = entries.first(where: { $0.value.surface.browser === view && $0.value.page === page }),
              entry.request == nil, entry.variant == nil, !playsEmbed(entry, at: url) else { return }
        do { try owner.recordEmbeddedPageNavigation(url, for: id, expectedURL: entry.originalURL) }
        catch { onError?(error) }
    }
    private func playsEmbed(_ entry: EmbeddedPageEntry, at url: URL) -> Bool {
        guard let surface = entry.surface as? NoteEmbedSurface, surface.liveAddress != surface.address else { return false }
        return url.absoluteString == surface.liveAddress.absoluteString
    }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack back: Bool, canGoForward forward: Bool) {
        if let entry = entries.values.first(where: { $0.surface.browser === view }) {
            if loading != entry.wasLoading {
                if loading { entry.surface.cancelPositioning() }
                else { entry.surface.positionCapture(force: true) }
            }
            entry.wasLoading = loading
        }
        if !loading { recordURL(view) }
        refresh(view)
    }
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        entries.values.first { $0.surface.browser === view }?.surface.setStatus(error.localizedDescription, retry: true)
    }
    func browserViewDidRequestClose(_ view: PCBrowserView) { if let page = entries.values.first(where: { $0.surface.browser === view })?.page { didClose(page) } }
    func refresh(_ view: PCBrowserView) {
        entries.values.first { $0.surface.browser === view }?.surface.refresh()
        scheduleMetadataRefresh()
    }
    private func scheduleMetadataRefresh() {
        guard !gate.isDisposed, !metadataRefreshPending else { return }
        metadataRefreshPending = true
        scheduleMetadataDelivery { [weak self] in
            guard let self else { return }
            self.metadataRefreshPending = false
            if !self.gate.isDisposed { self.metadataChanged() }
        }
    }
}
