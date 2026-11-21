import AppKit

@MainActor enum PCNativeNavigationAction { case back, forward, reload, stop }
@MainActor final class PCNativeRendererCrash { var title = "Crash"; var message = ""; var actionTitle = "Reload" }
@MainActor final class PCNativeCaptureState {}
@MainActor final class PCNativeContextImage { var isValid = true }
@MainActor final class PCNativeHistorySwipeSource { weak var overlayContainer: NSView? }
@MainActor protocol PCBrowserViewDelegate: AnyObject {}
@MainActor final class PCNativeBrowserWindow {
    weak var window: NSWindow?
    init(_ window: NSWindow) { self.window = window }
}
@MainActor final class FocusablePageBoundary: NSView { override var acceptsFirstResponder: Bool { true } }
@MainActor final class PCNativePageCaptureResult: NSObject {
    let image: NSImage?
    init(image: NSImage?) { self.image = image }
}
@MainActor final class PCNativeCaptureScrollContainer: NSObject {
    let anchorID: String?, path: String, scrollOffset: NSPoint, frame: NSRect
    init?(anchorID: String?, path: String, scrollOffset: NSPoint, frame: NSRect) {
        self.anchorID = anchorID; self.path = path; self.scrollOffset = scrollOffset; self.frame = frame
    }
}
@MainActor final class PCNativePage: NSObject {
    var supportsSnapshot = true
    var refusesSnapshot = false, withholdsSnapshot = false
    var snapshotImage: NSImage?
    var snapshotRequests = 0
    var withheldSnapshot: ((PCNativePageCaptureResult) -> Void)?
    override func responds(to selector: Selector!) -> Bool {
        selector == #selector(snapshotEmbeddedPage(completion:)) ? supportsSnapshot : super.responds(to: selector)
    }
    @objc func snapshotEmbeddedPage(completion: @escaping (PCNativePageCaptureResult) -> Void) -> Bool {
        snapshotRequests += 1
        guard embeddedOwnerValid, !isClosed, !refusesSnapshot else { return false }
        if withholdsSnapshot { withheldSnapshot = completion; return true }
        let image = snapshotImage
        DispatchQueue.main.async { completion(PCNativePageCaptureResult(image: image)) }
        return true
    }
    var liveCaptureZoomFactor = 1.0
    var positions: [(NSRect, NSPoint, Double)] = []
    var delayPositions = false
    var positionReplies: [(Bool) -> Void] = []
    var positionRequests: [PCNativeLiveCapturePosition] = []
    var positionContainers: [[PCNativeCaptureScrollContainer]] = []
    func positionLiveCapture(_ region: NSRect, scrollOffset: NSPoint, scrollContainers: [PCNativeCaptureScrollContainer],
                             displayWidth: Double, completion: @escaping (Bool) -> Void) -> PCNativeLiveCapturePosition? {
        positions.append((region, scrollOffset, displayWidth))
        positionContainers.append(scrollContainers)
        let request = PCNativeLiveCapturePosition()
        positionRequests.append(request)
        if delayPositions { positionReplies.append(completion) }
        else { DispatchQueue.main.async { if !request.cancelled { completion(true) } } }
        return request
    }
    var isClosed = false, isEmbedded = true, embeddedOwnerValid = true
    var url: URL? = URL(string: "https://fixture.invalid/original")
    var rendererCrash: PCNativeRendererCrash?
    var nativeView = FocusablePageBoundary()
    weak var owner: PCNativeBrowserWindow?
    func canPerformNavigation(_ action: PCNativeNavigationAction) -> Bool { !isClosed }
    func performNavigation(_ action: PCNativeNavigationAction, inNewTab: Bool) -> Bool { !isClosed }
    func performRendererCrashAction(_ crash: PCNativeRendererCrash) -> Bool { !isClosed }
    func rendererCrashDidPresent(_ crash: PCNativeRendererCrash) -> Bool { !isClosed }
}
@MainActor final class PCNativeEmbeddedPageRequest {
    var isPending = true
    let complete: (PCNativePage?, Error?) -> Void
    init(_ complete: @escaping (PCNativePage?, Error?) -> Void) { self.complete = complete }
    func cancel() { isPending = false }
    func reply(_ page: PCNativePage) { isPending = false; complete(page, nil) }
}
@MainActor final class PCBrowserView: NSView {
    weak var delegate: PCBrowserViewDelegate?
    var nativePage: PCNativePage?
    var isLoading = false, canShowSiteInfo = true
    var title = ""
    var blockedPopupCount: UInt = 0
    var request: PCNativeEmbeddedPageRequest?
    var loads = 0, creations = 0
    let profilePath: String
    var requestedURL: URL?
    init(frame: NSRect, profilePath: String) { self.profilePath = profilePath; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    func beginEmbeddedNavigation(_ url: URL, referrer: URL?, validateOwner: @escaping () -> Bool,
                                 completion: @escaping (PCNativePage?, Error?) -> Void) -> PCNativeEmbeddedPageRequest? {
        guard validateOwner() else { return nil }
        creations += 1; requestedURL = url
        let request = PCNativeEmbeddedPageRequest { [weak self] page, error in
            self?.nativePage = page; completion(page, error)
        }
        self.request = request
        return request
    }
    func loadURL(_ url: URL) { loads += 1 }
    func showSiteInfo(from view: NSView) -> Bool { true }
    func showBlockedPopups(from view: NSView) -> Bool { true }
}
@MainActor enum PCNativeBrowserApplication {
    static var closeCalls = 0
    static var closeAllowed = true
    static func owner(of page: PCNativePage) -> PCNativeBrowserWindow? { page.owner }
    static func requestClosePages(_ pages: [PCNativePage], shouldCommit: () -> Bool, completion: (Bool) -> Void) {
        closeCalls += 1
        let accepted = closeAllowed && shouldCommit()
        if accepted { pages.forEach { $0.isClosed = true } }
        completion(accepted)
    }
    static func setFairPlayIdentity(safariSites: [String], chromeSites: [String], profilePath: String, offTheRecord: Bool) {}
}

@MainActor final class PCNativeLiveCapturePosition {
    var cancelled = false
    func cancel() { cancelled = true }
}
@MainActor enum NoteMediaMotion { static func instant(_ body: () -> Void) { body() } }
@MainActor final class NoteMediaImageLoader {
    static let shared = NoteMediaImageLoader()
    func load(_ url: URL, pixels: Int, completion: @escaping (Result<[CGImage], Error>) -> Void) {}
}
@MainActor final class NoteLinkMetadata {
    enum Failure: Error, Equatable { case unavailable }
    static let shared = NoteLinkMetadata()
    func cached(_ url: URL) -> NoteLinkPreview? { nil }
    func failure(for url: URL) -> Failure? { .unavailable }
    func fetch(_ url: URL, completion: @escaping (Result<NoteLinkPreview, Failure>) -> Void) {}
}
@MainActor final class NoteEmbedFallbackView: NSView {
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?
    let retryChip = NoteChip("Retry", icon: .symbol("arrow.clockwise"))
    private let statusLabel = NSTextField(labelWithString: "")
    init(address: URL) { super.init(frame: .zero); retryChip.isHidden = true; addSubview(statusLabel); addSubview(retryChip) }
    required init?(coder: NSCoder) { fatalError() }
    func configure(preview: NoteLinkPreview?) {}
    func configure(status: String?, retryTitle: String?) {
        statusLabel.stringValue = status ?? ""
        retryChip.chipTitle = retryTitle ?? "Retry"; retryChip.isHidden = retryTitle == nil
    }
}
