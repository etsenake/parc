import AppKit
import Combine

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSPopoverDelegate, PCBrowserViewDelegate, NSSearchFieldDelegate, PCNativeBrowserWindowClient {
    let store: BrowserStore
    var isPrivateBrowsing: Bool { store.isEphemeral }
    private let nativeWindowRequest: PCNativeWindowRequest?
    var isPopupWindow: Bool { nativeWindowRequest?.kind == .popup }
    private let popupChrome = PopupChromeView()
    private let ownership: NativePageOwnership
    private let folderUndo = FolderUndoManager()
    private let closeUndoOperations = NSHashTable<ClosedTabsUndoOperation>.weakObjects()
    private let peekUndoOperations = NSHashTable<ClosedPeekUndoOperation>.weakObjects()
    private var peekRedo: (peek: UUID, done: (ClosedPeekRecord?) -> Void)?
    private var peekUndoOpen: (parent: String, operation: ClosedPeekUndoOperation, token: UUID)? {
        didSet {
            guard oldValue != nil, peekUndoOpen == nil else { return }
            let retry = peekUndoSlotWaiters.release(selected: selectedTabIDs)
            guard !retry.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in retry.forEach { self?.openAwaitedPeek(over: $0) } }
        }
    }
    private var peekUndoSlotWaiters = PeekUndoSlotWaiters()
    private var peekUndoAwaitingParent: [UUID: ClosedPeekUndoOperation] = [:]
    private var awaitedPeekRetries: Set<UUID> = []
    private var undoHiddenPeek: UUID?
    private var retiringPageHistory: [UUID: NSObject] = [:]
    private var closedItems = WindowClosedItems()
    private let nativeEditingUndo = UndoManager()
    private lazy var folderUndoKeyItem: NSMenuItem = {
        let item = NSMenuItem(title: "Undo", action: #selector(performFolderUndoCommand(_:)), keyEquivalent: "")
        item.target = self
        return item
    }()
    private let presentationID = UUID()
    let sessionID: UUID
    private var splitLinkGeneration: UInt64 = 0
    private var presentation: WindowPresentation {
        didSet {
            if presentation.sessionSelection != oldValue.sessionSelection {
                splitLinkGeneration &+= 1
                schedulePresentationSessionRecord()
            }
            if presentation.selectedTabIDs != oldValue.selectedTabIDs {
                for id in presentation.selectedTabIDs where peekUndoAwaitingParent[id] != nil {
                    DispatchQueue.main.async { [weak self] in self?.openAwaitedPeek(over: id) }
                }
            }
        }
    }
    private var presentationSessionRecordScheduled = false

    private func schedulePresentationSessionRecord() {
        guard !presentationSessionRecordScheduled else { return }
        presentationSessionRecordScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentationSessionRecordScheduled = false
            guard self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                  self.transferringTabIDs.isEmpty, self.collectionTransfer == nil else { return }
            self.onSessionRecordChange?()
        }
    }
    var activeSpaceID: UUID { presentation.activeSpaceID }
    private var presentedState: BrowserState { presentation.projected(store.state) }
    private var selectedTabIDs: [UUID] { presentation.selectedTabIDs }
    private var activeSpace: BrowserSpace {
        store.state.spaces.first { $0.id == activeSpaceID } ?? store.state.spaces[0]
    }
    private var visibleTabs: [BrowserTab] {
        store.state.tabs.filter { $0.archivedAt == nil && $0.profileID == activeSpace.profileID
            && ($0.kind == .favorite || $0.spaceID == activeSpaceID) }
    }
    private var activeSplitLayout: BrowserSplitLayout? {
        SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs == selectedTabIDs }
    }
    var activeEaselsDirectory: URL { store.easelsDirectory(for: activeSpace.profileID) }
    var activeProfileID: UUID { activeSpace.profileID }
    var hasReadyPresentation: Bool { presentation.isReady }
    var canReopenFromDock: Bool {
        presentation.isReady && window != nil && !isClosing && !wholeWindowClose
            && !windowClosePending && !windowCloseApproved
    }
    func canAcceptBrowserTab(for profileID: UUID) -> Bool {
        !isPopupWindow && canOwnDownloadDialog(for: profileID)
    }
    func canOwnDownloadDialog(for profileID: UUID) -> Bool {
        presentation.isReady && activeProfileID == profileID && !isClosing
            && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
    }
    private let rootView = ThemeRendererView()
    private let sidebarContainer = ThemeRendererView()
    private let sidebar = SidebarView()
    private let sidebarHover = SidebarHoverTracker()
    private var spaceCreation: SpaceCreationSession?
    @MainActor private final class SpaceCreationSession {
        var draft: SidebarNewSpaceDraft
        let view: SpaceCreationView
        let originalPresentation: WindowPresentation
        let originalFocus: UUID?
        let originalSidebar: SidebarPresentation
        let claims: [UUID: NativePageOwnership.Claim]
        let validateOwners: () -> Bool
        weak var window: NSWindow?
        weak var originalResponder: NSResponder?
        var committing = false
        var iconPicker: SidebarGroupIconPicker?
        var themePopover: NSPopover?
        var themeEditor: SpaceThemeEditorView?
        var sharedSpaceID: UUID?

        init(draft: SidebarNewSpaceDraft, owner: BrowserWindowController,
             claims: [UUID: NativePageOwnership.Claim], validateOwners: @escaping () -> Bool) {
            self.draft = draft; self.claims = claims; self.validateOwners = validateOwners
            originalPresentation = owner.presentation; originalFocus = owner.focusedTabID
            originalSidebar = owner.sidebarPresentation
            window = owner.window; originalResponder = owner.window?.firstResponder
            sharedSpaceID = draft.source.spaceID
            view = SpaceCreationView(spaceID: draft.source.spaceID, spaces: owner.creationSharingSpaces)
        }
    }
    private weak var sidebarMoveToast: ParcToastPresentation?
    private var sidebarPreviews: SidebarPreviewController?
    private var contentFocusRequest: ContentFocusRequest?
    private let pageHost = ExternalSplitDropHost()
    private let pageShadow = PageCardShadowView()
    private let extensionSidePanel = ExtensionSidePanelView()
    private let parkedPages = LayoutView()
    private let splitView = ParcSplitView()
    private let splitMarginHandle = SplitMarginHandleView()
    private var splitDropView: SplitDropView?
    private var splitDropReplacementID: UUID?
    private var foreignSplitDropView: SplitDropView?
    private var interProfileDialog: InterProfileMoveDialog?
    private let loadingIndicator = PageLoadingIndicatorHost()
    private var paneFrameObservers: [UUID: NSObjectProtocol] = [:]
    private let findHost = PageFindView(frame: .zero)
    private lazy var windowKeyViews = WindowKeyViewLoop(
        root: rootView, sidebar: sidebar,
        excluded: { [sidebarContainer, parkedPages, pageHost, weak self] in
            EaselBrowserObjects.excludesFromKeyboardNavigation($0) ||
            WindowKeyViewLoop.windowExcludes($0, sidebarContainer: sidebarContainer, parkedPages: parkedPages,
                                             pageHost: pageHost, activePeek: { self?.activePeek?.view })
        },
        isPage: { [extensionSidePanel] in $0 is PCBrowserView || $0 === extensionSidePanel.content },
        passesThrough: { $0 is PeekHostView })
    private var findField: NSTextField { findHost.field }
    private var findStates: [String: BrowserFindState<PCNativePage>] = [:]
    private var visibleFind: BrowserFindState<PCNativePage>?
    private var subscription: AnyCancellable?
    private var archiveEducationSubscription: AnyCancellable?
    private var updateCompleteSubscription: AnyCancellable?
    private var updateReadySubscription: AnyCancellable?
    private var developerModeSubscription: AnyCancellable?
    private var windowDraggingSubscription: AnyCancellable?
    private var toolbarSubscription: AnyCancellable?
    private var websiteThemeSubscription: AnyCancellable?
    private var lastPushedWebsiteTheme: (binding: ObjectIdentifier, stylesheet: String?)?
    private var shortcutDiscoverySubscription: AnyCancellable?
    private var windowFrameSubscription: AnyCancellable?
    private var windowFrameLayoutPending = false
    private var windowFrameAdjustApplied = false
    private var frameCrank: WindowFrameCrankView?
    private static weak var frameCrankOwner: BrowserWindowController?
    var onFrameCrankFinished: (() -> Void)?
    private var lastAppliedShortcutTooltipDiscovery: String?
    private var browsers: [UUID: PCBrowserView] = [:] {
        didSet {
            for id in browsers.keys where oldValue[id] == nil {
                store.closedPageHistory.pageCreated(id)
                store.tabHistory?.pageCreated(id)
            }
        }
    }
    private var tabHistoryCapture: DispatchWorkItem?
    private var tabHistoryChanged = Set<UUID>()
    private var cookieFlush: DispatchWorkItem?
    private var peeks: [String: PeekController] = [:] { didSet { noteReturnGate() } }
    private var archivePreviewRequest: (parent: String, lease: ArchivePreviewLease, token: UUID)?
    private var archivePreviews: [UUID: ArchivePreviewLease] = [:]
    private var queuedArchivePreview: (id: UUID, profileID: UUID)?
    private var archivePreviewRemnants = Set<UUID>()
    private var peekRetirementParents = Set<UUID>()
    private var favoriteBadgeIcons: [UUID: (image: NSImage, data: Data)] = [:]
    private var lastFavoriteOverlayFingerprint: String?
    private var promotingPeek = false { didSet { noteReturnGate() } }
    private var activePeek: PeekController? {
        guard let id = currentTabID else { return nil }
        return peeks.values.first { $0.parentTabID == id && !$0.page.isClosed
            && browsers[id]?.nativePage === $0.parentPage }
    }
    private var browserProfiles: [UUID: UUID] = [:]
    private var easelImageDestination: EaselImageDestinationController?
    private var privateMediaSource: (catalog: BrowserStore, profileID: UUID, media: ExternalMediaLibrary)?
    private var pageCapture: PageCaptureController?
    private var pageCaptureGesture: PageCaptureGesture?
    private struct EaselPane {
        let documentID: UUID
        let profileID: UUID
        let editor: EaselEditorViewController
        let originalTab: BrowserTab
    }
    private struct NotePane {
        let documentID: UUID
        let profileID: UUID
        let editor: NoteEditorViewController
        let originalTab: BrowserTab
    }
    private var noteEditors: [UUID: NotePane] = [:]
    private var noteExport: NoteExportController?
    private var easelEditors: [UUID: EaselPane] = [:]
    private var easelFailures: [UUID: (destination: String, message: String)] = [:]
    private var panes: [UUID: BrowserPane] = [:]
    private var requestedURLs: [UUID: String] = [:]
    private var failures: [UUID: String] = [:]
    private var loadingTabs = Set<UUID>()
    private var recentTabOrder = RecentTabOrder()
    private var tabSelectionHistory = TabSelectionHistory()
    private var tabSwitcher: RecentTabSwitcher? { didSet { updateLibraryEntryExpansion() } }
    private var shortcutInvocationEvent: NSEvent?
    private var focusedTabID: UUID? {
        didSet {
            if focusedTabID != oldValue { splitLinkGeneration &+= 1 }
            presentation.recordFocusedTab(focusedTabID)
            if focusedTabID != oldValue && !isClosing && !wholeWindowClose && transferringTabIDs.isEmpty {
                onSessionRecordChange?()
            }
        }
    }
    private var sidebarPresentation: SidebarPresentation = .locked {
        didSet {
            if sidebarPresentation != .floating { sidebarHoverActive = false }
            if (sidebarPresentation == .locked) != (oldValue == .locked) { onSessionRecordChange?() }
        }
    }
    private let sidebarMotion = SidebarMotionController()
    private var sidebarMotionLayoutKey: [CGFloat]?
    private var libraryContentWidth: CGFloat = 0
    private let libraryMotion = SidebarMotionController()
    private var lastAppliedChromeGeometryFingerprint: LayoutChromeGeometryFingerprint?
    private var preparingSidebarMotion = false
    private enum SidebarChromePass { case full, preparation, geometry }
    private var sidebarChromePass = SidebarChromePass.full
    private var sidebarMotionVisible = false
    private var sidebarFloatingSurface = false
    private var sidebarRevealsAnchored = false
    private var fullscreenPhase: WindowFullscreenPhase?
    private var systemWindowButtons: [NSButton] = []
    private let sidebarResizeRegion = SidebarResizeRegionView()
    private var sidebarResize: SidebarResizeGesture?
    private var windowSidebarWidth: SidebarWindowWidth {
        didSet { if windowSidebarWidth != oldValue { onSessionRecordChange?() } }
    }
    private let originalWindowLevel: NSWindow.Level
    private(set) var stayOnTop: Bool
    var canStayOnTop: Bool { !isPopupWindow && canReopenFromDock }
    func toggleStayOnTop() {
        guard canStayOnTop, let window else { return }
        stayOnTop.toggle()
        window.level = stayOnTop ? NSWindow.Level(rawValue: 3) : originalWindowLevel
        onSessionRecordChange?()
    }
    static let sharedFrameAutosaveName = "ParcBrowserWindow"
    private static func placeNewStandardWindow(_ window: NSWindow) {
        if !window.setFrameUsingName(sharedFrameAutosaveName) { window.center() }
        guard let source = activeBrowserWindow(excluding: window) else { return }
        window.setFrame(source.frame, display: false)
        window.cascadeTopLeft(from: source.cascadeTopLeft(from: .zero))
    }
    private static func activeBrowserWindow(excluding window: NSWindow) -> NSWindow? {
        func isBrowser(_ candidate: NSWindow?) -> Bool {
            guard let candidate, candidate !== window,
                  let controller = candidate.windowController as? BrowserWindowController else { return false }
            return !controller.isPopupWindow
        }
        if isBrowser(NSApp.keyWindow) { return NSApp.keyWindow }
        if isBrowser(NSApp.mainWindow) { return NSApp.mainWindow }
        return NSApp.orderedWindows.first { isBrowser($0) }
    }
    var sessionRecord: BrowserWindowRecord {
        BrowserWindowRecord(sidebarWidth: windowSidebarWidth.width, itemLastActiveDates: closedItems.itemLastActiveDates,
                            id: sessionID, focusedSpaceID: activeSpaceID, selectedTabIDs: selectedTabIDs,
                            focusedTabID: currentTabID, sidebarHidden: sidebarPresentation != .locked,
                            stayOnTop: stayOnTop, peekedFolders: savedFolderPeeks.isEmpty ? nil : savedFolderPeeks)
    }
    var onSessionRecordChange: (() -> Void)?
    private var savedFolderPeeks: [UUID: [SidebarItemReference]] = [:]
    private var isSidebarResizing = false {
        didSet {
            sidebarResizeRegion.isResizing = isSidebarResizing
            refreshPreviewHover()
            sidebarHover.isEnabled = !isSidebarResizing && frameCrank == nil
            setContentResizeReason(.sidebarResize, active: isSidebarResizing)
        }
    }
    private var contentResizeReasons: PageContentResizeReasons = [] {
        didSet {
            guard contentResizeReasons.mode != oldValue.mode else { return }
            for case let pane as BrowserPane in splitView.arrangedSubviews { pane.contentResize.mode = contentResizeReasons.mode }
        }
    }
    func setContentResizeReason(_ reason: PageContentResizeReasons, active: Bool) {
        if active { contentResizeReasons.insert(reason) } else { contentResizeReasons.remove(reason) }
    }
    private func refreshPreviewHover() {
        sidebarPreviews?.isHoverEnabled = !sidebarMotion.isAnimating && !isSidebarResizing
    }
    private var sidebarLayoutWidth: CGFloat {
        CGFloat(sidebarResize.map { $0.isPreviewingHidden ? $0.widthOnBegin : $0.effectiveWidth } ?? windowSidebarWidth.width)
    }
    private var sidebarPreviewingHidden: Bool { sidebarResize?.isPreviewingHidden == true }
    private var sidebarAccessibilityObserver: NSObjectProtocol?
    private var sidebarPointerDown = false
    private var sidebarHoverActive = false
    private var sidebarHoverLayoutKey: [CGFloat]?
    private var navigationHistory: NavigationHistoryController?
    private var menuTrackingDepth = 0
    private var menuObservers: [NSObjectProtocol] = []
    private var isClosing = false
    private var nativeBinding: PCNativeBrowserWindow?
    private var closingTabIDs = Set<UUID>()
    private var modelRetirementIDs = Set<UUID>()
    private var transferringTabIDs = Set<UUID>() {
        didSet { if transferringTabIDs.isEmpty, !oldValue.isEmpty { onReturnUnblocked?() } }
    }
    private var collectionTransfer: SidebarWindowTransfer? {
        didSet { if collectionTransfer == nil, oldValue != nil { onReturnUnblocked?() } }
    }
    private var transferContainers: [String: NSView] = [:]
    private var transferRecoveries: [UUID: () -> Void] = [:]
    private var resolvingTransfers = Set<UUID>()
    private var placeholderCapturesPending: [UUID: Int] = [:]
    private var placeholderCaptureGeneration = 0
    private var untargetedReturnScheduled = false
    private var shownSinceArrival = Set<UUID>()
    private var heldReturns = Set<UUID>()
    private var failedReturns = Set<UUID>()
    private var failedDuringReturn: UUID?
    private var returnGateWasOpen = true
    private var returnGateSpaceID: UUID?
    private var ejectionAttempts = Set<UUID>()
    private var closeAfterEjecting = false
    private(set) var lastActivatedAt = Date.distantPast
    var onUntargetedReturn: ((UUID, BrowserWindowController, PageReparenting.Trigger) -> PageReparenting.ReturnOutcome)?
    var onReturnUnblocked: (() -> Void)?
    private var liveTabModels: [UUID: BrowserTab] = [:]
    var scriptingAuthorization: (() -> Bool)?
    private var scriptingWindowCloseCompletions: [(Bool) -> Void] = []
    private var windowClosePending = false
    private var windowCloseApproved = false
    private var onboardingCloseRequested = false
    private var onboardingCloseNotes: [(editor: NoteEditorViewController, bodyEditable: Bool, titleEditable: Bool)]?
    private var wholeWindowClose = false {
        didSet { if !wholeWindowClose, oldValue { onReturnUnblocked?() } }
    }
    private var pendingApprovedWindowClose = false
    private var restoreSettingsAfterCancelledTermination = false
    private var nativeFullscreenTabID: UUID? {
        didSet { if nativeFullscreenTabID == nil, oldValue != nil { onReturnUnblocked?() } }
    }
    private var nativeFullscreenPresentation: (sidebar: SidebarPresentation, findHidden: Bool)?
    private var extensionSidePanelVisible = false
    private var attachedPageIDs = Set<String>()
    private var switchHold = PageSwitchHold<BrowserPane>()
    private var rendering = false
    private var lastChromeState: BrowserState?
    private var lastChromeRevision: UInt64?
    private var synchronizingNativeLayout = false
    private var applyingNativeSelection = false
    private struct NativePageSelectionRequest {
        let tabID: UUID
        weak var view: PCBrowserView?
        var pageIdentifier: String?
    }
    private enum NativeSelectionRequest {
        case local(UUID?)
        case page(NativePageSelectionRequest)

        var tabID: UUID? {
            switch self {
            case .local(let id): return id
            case .page(let request): return request.tabID
            }
        }
        var view: PCBrowserView? {
            if case .page(let request) = self { return request.view }
            return nil
        }
    }
    private var pendingNativeSelection: NativeSelectionRequest?
    private var attachingOwnedPages = false
    private var sidebarKeyboardCursor: SidebarKeyboardCursor?
    private var sidebarKeyboardBrowsing = false
    private var commandBarHostCache: (profileID: UUID, revision: UInt64, hosts: Set<String>)?
    private var commandBarModelChecks: (revision: UInt64, spaceID: UUID, profileID: UUID,
                                        items: [SidebarItemReference], answers: [String: Bool])?
    private var commandBar: CommandBar? {
        didSet {
            commandBar?.onDismissalSettled = onCommandBarDismissalSettled
            updateLibraryEntryExpansion()
            if commandBar == nil { commandBarCreatesNewTab = false; commandBarShowsNewTabPlaceholder = false }
            refreshSplitPaneHighlights()
            refreshNewTabPlaceholder()
            noteReturnGate()
        }
    }
    var hasCommandBarDuringActivation: Bool { commandBar != nil }
    private var loadedStartPage: StartPageView?
    private var startPage: StartPageView { loadedStartPage ?? loadStartPage() }
    private var residentCommandBar: CommandBar?
    private var residentCommandOwner: (spaceID: UUID, profileID: UUID)?
    private var startPagePresented = false
    private var startPageRefreshScheduled = false
    private var startPageDeparting = false
    private var residentTypedCommands: (items: [SidebarItemReference]?, commands: [CommandBarTypedCommand]) = (nil, [])
    private var residentTopDomainRevision: UInt64?
    private var residentCommandInputs: ResidentCommandBarInputs?
    private struct ResidentCommandBarInputs: Equatable {
        let state: UInt64
        let history: UInt64
        let space: UUID
        let profile: UUID
        let selection: [UUID]
        let undo: String?
        let redo: String?
    }
    private func refreshResidentTopDomains(_ bar: CommandBar) {
        guard !isPrivateBrowsing, residentTopDomainRevision != store.historyRevision else { return }
        residentTopDomainRevision = store.historyRevision
        deliverCommandBarTopDomains(to: bar, profileID: activeProfileID)
    }
    private func presentsCommandBar(_ panel: CommandBar) -> Bool { commandBar === panel || residentCommandBar === panel }
    var onCommandBarDismissalSettled: (() -> Void)?
    private var commandBarCreatesNewTab = false
    private var commandBarShowsNewTabPlaceholder = false
    private func refreshNewTabPlaceholder() {
        let active = commandBar != nil && commandBarShowsNewTabPlaceholder
        guard sidebar.newTabPlaceholderActive != active else { return }
        sidebar.newTabPlaceholderActive = active
        if presentation.isReady, !rendering, !isClosing { updateNavigation() }
    }
    private var commandBarHistoryCache: (revision: UInt64, profileID: UUID, currentURL: String?, entries: [BrowserHistoryEntry])?
    private var commandBarDocumentCache: (profileID: UUID, stamp: [Date], documents: [CommandBarDocument])?
    private var commandBarTopDomainCache: (profileID: UUID, revision: UInt64, domains: [CommandBarRanking.Domain])?
    private var commandBarRecentPages: (query: PCNativeHistoryQuery, profileID: UUID, revision: UInt64)?
    private var shortcutEssentials: ShortcutEssentialsWindow?
    private var settings: SettingsWindow?
    private var libraryView: LibraryView? { didSet { updateLibraryEntryExpansion() } }
    private var paymentFeedbackWork: DispatchWorkItem?
    private var shortcutHint: ShortcutPriorityHintView?
    private var shortcutHintCommand: PCNativeShortcutCommand?
    private weak var shortcutHintPage: PCNativePage?
    private let toasts = ParcToastPresenter(share: { PaneShareMenu.popUp(for: $0) })
    private var copyLinkOperation = UUID()
    private lazy var sharedQuotes: SharedQuoteController = SharedQuoteController(isCurrent: { [weak self] page in
        guard let self else { return false }
        return !self.isClosing && !self.wholeWindowClose && self.commandBar == nil &&
            self.libraryView == nil && self.pageCapture == nil && self.selectedNativePage() === page
    }, display: { [weak self] selection in
        guard let self else { return }
        guard let selection, let page = self.selectedNativePage(), self.commandBar == nil,
              self.libraryView == nil, self.pageCapture == nil, !self.isClosing, !self.wholeWindowClose,
              !WhatsNewPage.matches(page.url?.absoluteString ?? "") else {
            self.sidebar.updateSharedQuote(action: nil); return
        }
        self.sidebar.updateSharedQuote { [weak self, weak page] in
            guard let self, let page, self.selectedNativePage() === page,
                  self.sharedQuotes.canPerform(selection) else { return }
            self.copySharedQuote(selection, page: page)
        }
    })
    private var capturePresentations: [UUID: CaptureIndicatorPresentation] = [:]
    private var lastCapturePresentationFingerprint: String?
    private var lastShareableAudioFingerprint: String?
    private var lastAppliedShareable = Set<UUID>()
    private var lastAppliedAudio: [UUID: SidebarTabAudio] = [:]
    private var themePopover: NSPopover? { didSet { noteReturnGate() } }
    private var siteControlCenter: SiteControlCenterController? { didSet { noteReturnGate() } }
    private var siteControlCenterDefers: Bool { siteControlCenter.map { !$0.isDetached } ?? false }
    private let siteControlCenterDismissal = SiteControlCenterDismissal()
    private var extensionActionGeneration = UUID()
    private weak var extensionControlsPage: PCNativePage?
    private var siteControlCenterItems: [String: ExtensionControlItem] = [:]
    private var siteControlCenterPermissions: [[String: Any]] = []
    private var siteControlCenterPermissionTargets: [String: (Int, UInt)] = [:]
    private var siteControlCenterRevision: UInt?
    private var siteControlCenterPageTools: Set<PCNativePageTool> = []
    private var siteControlCenterOwner: (space: UUID, profile: UUID)?
    private var lastExtensionControlsSignature: String?
    private var themeEditor: SpaceThemeEditorView?
    private var themeEditingSpaceID: UUID?
    private var themeEditingProfileID: UUID?
    private var themeEditingContextSpaceID: UUID?
    private var themePreview: (spaceID: UUID, theme: SpaceTheme)?
    private var themeEditorPresetPage = 0
    private var downloadReview: DownloadReviewController?
    private var downloadReviewItem: BrowserDownload?
    private let downloadArrival = DownloadArrivalOwner()
    private var recyclingDownloads: [String: DownloadLibraryIdentity] = [:]
    private var loadingDownloadProfiles = Set<UUID>()
    private var downloadProfileErrors: [UUID: String] = [:]
    private var libraryFlyoutFileGeneration: UInt64 = 0
    private var libraryFlyoutFileMonitor: LibraryFlyoutFolderMonitor?
    private var libraryFlyoutFileActivation: NSObjectProtocol?
    private var eventMonitor: Any?
    private var zoomLevels: [UUID: Double] = [:]
    private var renderedPaneIDs: [UUID] = []
    private let archiveActivityScheduling = ArchiveScheduling()
    private var renderedSpaceCreationID: UUID?
    var onClose: (() -> Void)?
    var onActivateWindow: (() -> Void)?
    var onMiniPlayerSourceChange: (() -> Void)?
    private var lastMiniPlayerSourceSignature: String?
    private let mediaRefresh = NextTurnCoalescer()
    var onRequestBrowserTab: ((String?) -> Void)?
    var onRequestTabTransfer: ((UUID, BrowserWindowController, (() -> Bool)?) -> Bool)?
    var tabHolder: ((UUID, BrowserWindowController) -> TabHolder)?
    enum TabHolder {
        case none
        case content(BrowserWindowController)
        case emptyClaim(BrowserWindowController)
    }
    var onPrepareLinkRoute: ((PCNativeLinkRoute) -> PCNativeBrowserWindow?)?
    private var preparedForRoutedPage = false
    var retirementUnavailableReason: ((Set<UUID>) -> String?)?
    var prepareSidebarSpaceMoveOwners: ((Set<UUID>) -> (() -> Bool)?)?
    var onSplitDragBegan: ((SidebarSplitDrag, BrowserWindowController) -> Void)?
    var onInterProfileMoveCommitted: ((Set<UUID>) -> Void)?
    var resolveSidebarCopyDestinations: (([BrowserTab]) -> SidebarCopySources?)?

    static let discardAfter: TimeInterval = 14_400
    private func discardIdleBackgroundPages() {
        guard !isClosing, !wholeWindowClose, presentation.isReady else { return }
        let cutoff = Date().addingTimeInterval(-Self.discardAfter)
        var shown = Set(renderedPaneIDs).union(selectedTabIDs)
        if let pending = pendingNativeSelection?.tabID { shown.insert(pending) }
        for (id, browser) in browsers where !shown.contains(id) && !closingTabIDs.contains(id)
            && !transferringTabIDs.contains(id) && !peeks.values.contains(where: { $0.parentTabID == id }) {
            guard let tab = store.state.tabs.first(where: { $0.id == id }), tab.lastAccessed < cutoff,
                  let page = browser.nativePage, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.discardIfIdle)) else { continue }
            _ = page.discardIfIdle()
        }
    }

    var visibleTabIDsForActivity: Set<UUID> {
        guard !isClosing, !wholeWindowClose, let window,
              window.occlusionState.contains(.visible) else { return [] }
        return Set(renderedPaneIDs)
    }
    var automaticArchiveProtectionSnapshot: (protectedIDs: Set<UUID>, unavailable: Int) {
        var protected = Set(renderedPaneIDs).union(selectedTabIDs), unavailable = 0
        if let pending = pendingNativeSelection?.tabID { protected.insert(pending) }
        protected.formUnion(transferringTabIDs)
        protected.formUnion(peeks.values.map(\.parentTabID))
        for (id, browser) in browsers {
            let state = browser.automaticArchiveProtectionState
            if state != .eligible { protected.insert(id) }
            if state == .unknown { unavailable += 1 }
        }
        for (id, pane) in easelEditors {
            for view in pane.editor.pageObjects?.ownedViews.values ?? Dictionary<UUID, PCBrowserView>().values {
                let state = view.automaticArchiveProtectionState
                if state != .eligible { protected.insert(id) }
                if state == .unknown { unavailable += 1 }
            }
        }
        return (protected, unavailable)
    }
    var hasPageInUse: Bool {
        let inUse = { (view: PCBrowserView) in view.automaticArchiveProtectionState == .protected }
        return browsers.values.contains(where: inUse) || easelEditors.values.contains { pane in
            pane.editor.pageObjects?.ownedViews.values.contains(where: inUse) == true
        }
    }
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) != true, sidebarMotion.isAnimating {
            settleSidebarMotion()
            layoutChrome()
        }
        refreshPaymentControls()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        guard window === self.window else { return }
        PCNativeBrowserWindow.nativeWindowDidFailToEnterFullscreen(window)
        setFullscreenPhase(window.styleMask.contains(.fullScreen) ? .expanded : nil)
    }
    func windowWillEnterFullScreen(_ notification: Notification) { setFullscreenPhase(.entering) }
    func windowDidEnterFullScreen(_ notification: Notification) {
        setFullscreenPhase(.expanded)
        guard !isPopupWindow,
              let exit = KeyboardShortcuts.shared.activeShortcut(for: "exit:")
                ?? KeyboardShortcuts.shared.activeShortcut(for: "toggleFullScreen:") else { return }
        showToast(.fullScreenExit(shortcut: exit.display), at: .window)
    }
    func windowWillExitFullScreen(_ notification: Notification) { setFullscreenPhase(.exiting) }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        guard window === self.window else { return }
        setFullscreenPhase(.expanded)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        setFullscreenPhase(window?.styleMask.contains(.fullScreen) == true ? .expanded : nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        lastActivatedAt = Date()
        guard presentation.isReady else { return }
        onActivateWindow?()
        showImportFailures()
        for id in awaitedPeekRetries where selectedTabIDs.contains(id) {
            DispatchQueue.main.async { [weak self] in self?.openAwaitedPeek(over: id) }
        }
        if !rendering, !isClosing { updateNavigation() }
    }

    init(store: BrowserStore, ownership: NativePageOwnership, renderInitialSelection: Bool = true,
         preferredProfileID: UUID? = nil, nativeWindowRequest: PCNativeWindowRequest? = nil,
         restoredRecord: BrowserWindowRecord? = nil) throws {
        self.nativeWindowRequest = nativeWindowRequest
        self.store = store
        self.ownership = ownership
        let originalSessionID = restoredRecord?.id ?? UUID()
        sessionID = originalSessionID
        closedItems = WindowClosedItems(itemLastActiveDates: restoredRecord?.itemLastActiveDates ?? [:])
        windowSidebarWidth = SidebarWindowWidth(lastUsed: store.state.settings.sidebarWidth, restored: restoredRecord?.sidebarWidth)
        let initialPresentation = WindowPresentation(state: store.state, ready: renderInitialSelection,
                                                     preferredProfileID: preferredProfileID, restoredRecord: restoredRecord)
        presentation = initialPresentation
        focusedTabID = initialPresentation.preferredFocusedTabID
        if restoredRecord?.sidebarHidden == true { sidebarPresentation = .hidden }
        let popup = nativeWindowRequest?.kind == .popup
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if nativeWindowRequest?.canResize != false { style.insert(.resizable) }
        let initialRect = NSRect(x: 0, y: 0, width: popup ? 900 : 1280, height: popup ? 680 : 840)
        let window: NSWindow = popup
            ? BrowserPopupWindow(contentRect: initialRect, styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: initialRect, styleMask: style, backing: .buffered, defer: false)
        originalWindowLevel = window.level
        stayOnTop = !popup && (restoredRecord?.stayOnTop ?? false)
        window.title = "Parc"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = popup
        window.minSize = popup ? NSSize(width: 300, height: 360) : NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        if popup || store.isEphemeral { window.isRestorable = false }
        else {
            window.identifier = NSUserInterfaceItemIdentifier(ParcWindowRestoration.identifierPrefix + sessionID.uuidString)
            window.restorationClass = ParcWindowRestoration.self
        }
        if !popup && nativeWindowRequest == nil && !store.isEphemeral { window.setFrameAutosaveName(Self.sharedFrameAutosaveName) }
        if store.isEphemeral { window.appearance = NSAppearance(named: .darkAqua); window.title = "Space 1" }
        super.init(window: window)
        if stayOnTop { window.level = NSWindow.Level(rawValue: 3) }
        if !popup, let peeks = restoredRecord?.peekedFolders {
            savedFolderPeeks = peeks
            sidebar.restoreFolderPeeks(peeks)
        }
        shortcutDiscoverySubscription = NotificationCenter.default.publisher(for: LiveShortcutToolTip.didChange).sink { [weak self] _ in
            guard let self else { return }
            let discovery = self.shortcutTooltipDiscoveryFingerprint()
            if ShortcutTooltipDiscoverySkip.shouldSkip(
                previous: self.lastAppliedShortcutTooltipDiscovery, next: discovery
            ) {
                return
            }
            self.toasts.dismissShortcutToasts()
            self.popupChrome.updateCopyTooltip()
            self.updateSiteControlCenterShortcuts()
            self.lastAppliedShortcutTooltipDiscovery = discovery
        }
        window.delegate = self
        window.contentView = rootView
        if nativeWindowRequest == nil && restoredRecord == nil { Self.placeNewStandardWindow(window) }
        else { window.center() }
        if let request = nativeWindowRequest {
            var frame = window.frame
            if request.initialFrame.width > 0 { frame.size.width = max(window.minSize.width, request.initialFrame.width) }
            if request.initialFrame.height > 0 { frame.size.height = max(window.minSize.height, request.initialFrame.height) }
            if request.initialOriginSpecified {
                frame.origin.x = request.initialFrame.minX
                frame.origin.y = request.initialFrame.maxY - frame.height
            } else {
                let sourceFrame = request.source?.window?.frame ?? window.screen?.visibleFrame
                if let sourceFrame { frame.origin = NSPoint(x: sourceFrame.midX - frame.width / 2, y: sourceFrame.midY - frame.height / 2) }
            }
            let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? window.screen
            if let screen { frame = window.constrainFrameRect(frame, to: screen) }
            window.setFrame(frame, display: false)
            window.standardWindowButton(.zoomButton)?.isEnabled = request.canMaximize
            if !request.canFullscreen { window.collectionBehavior.insert(.fullScreenNone) }
        }
        PCNativeBrowserWindow.prepareNativeWindowFullscreen(window)
        systemWindowButtons = WindowStandardButtons.systemButtons(of: window)
        if popup { sidebarPresentation = .hidden }
        rootView.wantsLayer = true
        rootView.addSubview(pageShadow)
        rootView.addSubview(pageHost)
        pageCaptureGesture = PageCaptureGesture(view: rootView) { [weak self] point in
            self?.prepareCaptureGesture(at: point)
        }
        rootView.addSubview(splitMarginHandle)
        splitView.marginHandle = splitMarginHandle
        pageHost.makeSession = { [weak self] view, info in self?.beginExternalSplitDrop(from: view, info: info) }
        parkedPages.isHidden = true
        rootView.addSubview(parkedPages)
        extensionSidePanel.isHidden = true
        extensionSidePanel.onClose = { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose,
                  self.extensionSidePanelVisible, self.extensionSidePanel.window === self.window else { return false }
            return self.nativeBinding?.closeExtensionSidePanel() == true
        }
        rootView.addSubview(extensionSidePanel)
        rootView.addSubview(loadingIndicator)
        rootView.addSubview(findHost)
        rootView.addSubview(popupChrome)
        popupChrome.isHidden = !popup
        rootView.addSubview(sidebarContainer)
        sidebarContainer.coordinateSpace = rootView
        let incognitoTheme = store.isEphemeral && !popup
        rootView.incognito = incognitoTheme; sidebarContainer.incognito = incognitoTheme
        toasts.basicBackground = windowBasicBackground
        sidebarContainer.addSubview(sidebar)
        SidebarMotionController.pinSurface(of: sidebarContainer, except: sidebar)
        rootView.onPaletteChange = { [weak self] palette in
            if let self, let window = self.window {
                TooltipController.controller(for: window).palette = TooltipColorPalette(theme: self.rootView.paletteTheme)
            }
            self?.libraryView?.palette = palette
            self?.sidebar.palette = palette
            self?.sidebarResizeRegion.color = palette.foregroundPrimary
            self?.loadingIndicator.appearance = palette.contentAppearance
            if let self {
                for peek in self.peeks.values { peek.view.adoptWindowTheme(self.rootView) }
                self.shortcutHint?.update(theme: self.rootView.theme, basicBackground: self.windowBasicBackground)
                self.toasts.update(theme: self.rootView.theme)
                self.commandBar?.theme = self.rootView.paletteTheme
                self.commandBar?.contentAppearance = palette.contentAppearance
                self.residentCommandBar?.theme = self.rootView.paletteTheme
            }
            self?.popupChrome.palette = palette
            NotificationCenter.default.post(name: NSNotification.Name(PCNativeAirPlayThemeDidChangeNotification), object: self?.window)
            self?.pageHost.refreshDropAppearance()
            self?.splitDropView?.refreshAppearance(); self?.foreignSplitDropView?.refreshAppearance()
            self?.refreshSplitPaneHighlights()
            self?.refreshWebsiteTheme()
            self?.refreshNoteCanvasTheme(palette)
        }
        popupChrome.onNavigation = { [weak self] kind in self?.prepareNavigationInteraction(kind) }
        popupChrome.prepareCopy = { [weak self] in self?.preparePopupCopyURL() }
        popupChrome.prepareExtensions = { [weak self] in self?.preparePopupSiteControls(requireExtensions: true) }
        popupChrome.prepareSiteControls = { [weak self] in self?.preparePopupSiteControls(requireExtensions: false) }
        popupChrome.onAddress = { [weak self] in
            guard let self else { return }; self.focusAddress(anchor: self.popupChrome.addressAnchor)
        }
        popupChrome.onPageMenu = { [weak self] in
            guard let self else { return }; self.showPageMenu(from: self.popupChrome.addressAnchor)
        }
        sidebar.onCaptureMenu = { [weak self] id, anchor in self?.showCaptureMenu(tabID: id, anchor: anchor) }
        sidebar.captureIsActive = { [weak self] id in
            guard let self else { return false }
            return self.captureOwnerIDs(of: id).contains { self.capturePresentations[$0]?.active == true }
        }
        sidebar.prepareShareThisTab = { [weak self] id in
            guard let self, let browser = self.browsers[id], browser.window === self.window,
                  self.ownership.canUse(id, owner: self.presentationID), browser.canShareThisTabInstead else { return nil }
            return { [weak self, weak browser] in
                guard let self, let browser, self.browsers[id] === browser, browser.canShareThisTabInstead else { return false }
                return browser.shareThisTabInstead()
            }
        }
        rootView.addSubview(sidebarResizeRegion)
        sidebarResizeRegion.referenceView = rootView
        sidebarResizeRegion.color = rootView.palette.foregroundPrimary
        sidebarResizeRegion.onPan = { [weak self] state, translation, velocity in
            self?.sidebarResizeChanged(state, translationX: translation, velocityX: velocity)
        }
        sidebarResizeRegion.onDoubleClick = { [weak self] in
            guard let self, self.sidebarResize == nil else { return }
            let lastUsed = self.windowSidebarWidth.reset()
            self.store.updateSettings { $0.sidebarWidth = lastUsed }
            self.layoutChrome()
        }
        pageHost.wantsLayer = true
        PageCard.follow(thickness: WindowFramePreferences.shared.thickness)
        pageHost.layer?.cornerRadius = PageCard.cornerRadius
        pageHost.layer?.cornerCurve = .continuous
        pageHost.layer?.masksToBounds = true
        pageHost.layer?.backgroundColor = NSColor.white.cgColor
        pageHost.addSubview(splitView)
        splitView.prepareDividerResize = { [weak self] in self?.prepareSplitResize() }
        splitView.onDividerPanActivity = { [weak self] in self?.setContentResizeReason(.splitDividerResize, active: $0) }
        splitView.onInteractivePaneEditing = { [weak self] active in
            self?.setContentResizeReason(.splitInteractiveEditing, active: active)
            self?.splitPaneEditDidChange(active)
        }
        splitView.constrain(to: pageHost)
        loadingIndicator.appearance = rootView.palette.contentAppearance
        setupFindBar()
        sidebar.isPrivateBrowsing = store.isEphemeral
        wireSidebar()
        sidebarHover.view = rootView
        sidebarHover.regions = { [weak self] info in self?.sidebarHoverRegions(info) ?? [:] }
        sidebarHover.onChange = { [weak self] _ in self?.applySidebarHover() }
        sidebarHover.attach(to: window)
        windowKeyViews.attach(to: window)
        let notifications = NotificationCenter.default
        menuObservers.append(notifications.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTrackingDepth += 1 }
        })
        menuObservers.append(notifications.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                self.refreshSidebarPointer()
            }
        })
        menuObservers.append(notifications.addObserver(forName: SidebarPlusMenuController.visibilityDidChange, object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { if note.userInfo?["shown"] as? Bool == false { self?.refreshSidebarPointer() } }
        })
        menuObservers.append(notifications.addObserver(forName: Self.expandCurrentSplitNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.expandDisplayedSplit() }
        })
        menuObservers.append(notifications.addObserver(forName: SidebarWindowWidth.settingDidChange, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windowSidebarWidth.applySetting(self.store.state.settings.sidebarWidth)
                self.layoutChrome()
            }
        })
        menuObservers.append(notifications.addObserver(
            forName: PCNativeBrowserApplication.tabSwitcherAvailabilityDidChangeNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sidebar.updateSpaceAvailability(); self?.refreshDeveloperToolbars() }
        })
        rootView.layer?.masksToBounds = true
        rootView.onLayout = { [weak self] in self?.layoutChrome() }
        rootView.contextMenu = { [weak self] hit in self?.windowFrameContextMenu(rootHit: hit) }
        sidebarContainer.contextMenu = { [weak self] hit in self?.windowFrameContextMenu(sidebarHit: hit) }
        HistorySwipeForwarding.install()
        nativeBinding = try PCNativeBrowserApplication.register(self)
        websiteThemeSubscription = WebsiteThemePreferences.shared.$state.sink { [weak self] state in
            self?.refreshWebsiteTheme(enabled: state.isEnabled)
        }
        if store.isEphemeral, let binding = nativeBinding {
            if let request = nativeWindowRequest { try binding.adoptPrivateContext(request: request) }
            else { try binding.beginPrivateBrowsing(profilePath: store.independentEngineProfilePath(for: activeProfileID)) }
        }
        configureSidebarPreviews()
        sidebarAccessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                self.settleSidebarMotion()
                self.layoutChrome()
            }
        }
        archiveEducationSubscription = store.$autoArchiveEducationPending.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSidebarBanners() }
        updateCompleteSubscription = SoftwareUpdateBanner.shared.$completedUpdate.removeDuplicates()
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSidebarBanners() }
        updateReadySubscription = NotificationCenter.default.publisher(for: SoftwareUpdater.phaseDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSidebarBanners() }
        subscription = store.statePublisher.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.applyPublishedState(self.store.state)
        }
        developerModeSubscription = DeveloperModePreferences.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshDeveloperToolbars()
                self.refreshNavigationControls()
                self.refreshFavoriteOverlays(from: self.presentedState)
            }
        }
        toolbarSubscription = BrowserToolbarPreferences.shared.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.navigationHistory?.dismiss(); self.dismissSiteControlCenter()
            self.refreshDeveloperToolbars(); self.refreshExtensionControls()
            self.sidebarHover.setNeedsRefresh()
        }
        windowDraggingSubscription = WebpageWindowDraggingPreferences.shared.$state.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.refreshDeveloperToolbars() }
        }
        windowFrameSubscription = WindowFramePreferences.shared.objectWillChange.sink { [weak self] _ in
            self?.scheduleWindowFrameLayout()
        }
        if renderInitialSelection { render(store.state); requestNativeSelection() }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose else { return }
            self.refreshDownloadProfiles()
            LibraryFolderPrompts.shared.whenAnswered { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose else { return }
                self.startLibraryFlyoutFileQuery()
            }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.window, event.type != .leftMouseUp, self.sidebarMotion.isAnimating {
                self.settleSidebarMotion()
                self.layoutChrome()
            }
            if event.type == .leftMouseUp {
                self.sidebarPointerDown = false
                self.refreshSidebarPointer()
            }
            if event.type == .leftMouseDown, event.window === self.window {
                let inputSnapshot = NativeInputDiagnostics.beforeDispatch(event, phase: "monitor")
                defer { NativeInputDiagnostics.afterDispatch(event, snapshot: inputSnapshot, phase: "monitor") }
                if self.commandBar?.contains(event) == true { return event }
                if self.activePeek?.contains(event) == true { return event }
                let point = self.rootView.convert(event.locationInWindow, from: nil)
                if self.sidebarPreviews?.contains(windowPoint: event.locationInWindow) == true { return event }
                if !self.sidebarResizeRegion.isHidden, self.sidebarResizeRegion.frame.contains(point) {
                    self.sidebarPointerDown = self.sidebarPresentation == .floating
                } else {
                    if self.libraryView == nil && !self.isPopupWindow && self.sidebarPresentation == .hidden && point.x >= 0 && point.x <= 8 && self.rootView.bounds.contains(point) {
                        self.setSidebarPresentation(.floating)
                    }
                    self.sidebarPointerDown = self.sidebarPresentation == .floating && self.sidebarContainer.frame.contains(point)
                    if self.sidebarPresentation == .floating && !self.sidebarPointerDown { self.setSidebarPresentation(.hidden) }
                    if self.sidebarPresentation == .hidden || !self.sidebarContainer.frame.contains(point) {
                        for (id, pane) in self.panes where self.renderedPaneIDs.contains(id) {
                            if pane.bounds.contains(pane.convert(event.locationInWindow, from: nil)) { self.focusedTabID = id; self.updateNavigation(); self.requestNativeSelection() }
                        }
                    }
                }
                if self.commandBar != nil { self.commandBar?.dismiss(restoreFocus: false) }
            }
            return event
        }
        store.placeholderImages.observe(in: presentationID) { [weak self] in
            guard let self, !self.rendering else { return }
            self.render(self.store.state)
        }
        archiveActivityScheduling.start(.discard) { [weak self] in self?.discardIdleBackgroundPages() }
        archiveActivityScheduling.start(.activity) { [weak self] in
            guard let self else { return }
            self.store.refreshVisibleTabs(self.visibleTabIDsForActivity)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func prepareStoreContext(restoringSplitLayout: BrowserSplitLayout? = nil) {
        presentation.reconcile(store.state) { ownership.canUse($0, owner: presentationID) }
        let restoredLayout = restoringSplitLayout.flatMap {
            $0.spaceID == activeSpaceID && $0.tabIDs == selectedTabIDs ? $0 : nil
        }
        if store.activeSpaceID != activeSpaceID || store.state.selectedTabIDs != selectedTabIDs
            || (restoredLayout != nil && store.activeSplitLayout != restoredLayout) {
            store.setWindowPresentation(spaceID: activeSpaceID, selectedTabIDs: selectedTabIDs,
                                        splitLayout: restoredLayout ?? presentation.splitLayout)
        }
    }

    private func performWindowCommand<T>(selectNativePage: Bool = true, afterCapture: (() -> Void)? = nil, _ action: () -> T) {
        cancelSpaceCreation(restoreFocus: false)
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        pendingNativeSelection = nil
        let previousFocus = focusedTabID
        prepareStoreContext()
        _ = action()
        presentation.captureCommand(store.state) { ownership.canUse($0, owner: presentationID) }
        afterCapture?()
        focusedTabID = previousFocus.flatMap { selectedTabIDs.contains($0) ? $0 : nil } ?? selectedTabIDs.last
        presentation.recordSelectionForReturn(currentTabID, state: store.state)
        onSessionRecordChange?()
        render(store.state)
        if selectNativePage { requestNativeSelection() }
        if !isPopupWindow && !isPrivateBrowsing { store.linkRouting.noteVisitedSpace(activeSpaceID) }
    }

    private var pendingSearchNavigations: [UUID: PCNativeSearchNavigation] = [:]
    private var inputRevisions: [UUID: UUID] = [:]
    private var commandSubmissionRevision = UUID()
    private var residentCommandSubmissionRevision = UUID()
    private var splitInsertion: SplitPaneInsertionSession?
    private var renderedSplitInsertionID: UUID?
    private var pendingCommandSplitValidation: (() -> Bool)?
    private weak var pendingCommandSplitBrowser: PCBrowserView?
    private func cancelPendingCommandSplit() {
        guard pendingCommandSplitValidation != nil else { return }
        commandSubmissionRevision = UUID()
        pendingCommandSplitValidation = nil; pendingCommandSplitBrowser = nil
    }

    func openInput(_ input: String) {
        if isPopupWindow { onRequestBrowserTab?(input); return }
        resolveInput(input, replacing: nil)
    }

    func openAddress(_ url: URL) {
        if isPopupWindow { openInput(url.absoluteString) } else { openExactAddress(url) }
    }

    private func resolveInput(_ input: String, replacing tabID: UUID?) {
        if openLocalNoteAddress(input) { return }
        if let tabID, !prepareNotesToClose([tabID]) { return }
        let spaceID = activeSpaceID
        let profileID = activeProfileID
        let originalPage = tabID.flatMap { browsers[$0]?.nativePage }
        let originalURL = tabID.flatMap { id in store.state.tabs.first { $0.id == id }?.url }
        let revision = UUID()
        if let tabID { inputRevisions[tabID] = revision }
        PCNativeBrowserApplication.resolveSearchInput(input,
            profilePath: store.independentEngineProfilePath(for: profileID), page: currentBrowser?.nativePage, window: nativeBinding) { [weak self, weak originalPage] navigation, error in
            MainActor.assumeIsolated {
                guard let self, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                      !self.isClosing, !self.wholeWindowClose else { return }
                if let tabID {
                    guard self.currentTabID == tabID, self.inputRevisions[tabID] == revision,
                          self.browsers[tabID]?.nativePage === originalPage,
                          self.store.state.tabs.first(where: { $0.id == tabID })?.url == originalURL else { return }
                    self.inputRevisions.removeValue(forKey: tabID)
                }
                guard let navigation else {
                    self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.")
                    return
                }
                self.openSearchNavigation(navigation, replacing: tabID)
            }
        }
    }

    private func showSearchError(_ message: String) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(title: "Couldn’t open search", message: message))
    }

    private func creationProvenance(activeTabID: UUID?) -> TabCreationProvenance {
        TabCreationProvenance(referrerID: nil, activeTabID: activeTabID,
            profileID: activeProfileID, state: store.state)
    }

    private func creationSourceTab(_ page: PCNativePage) -> UUID? {
        guard !page.isClosed,
              let binding = PCNativeBrowserApplication.owner(of: page),
              let original = binding.client as? BrowserWindowController,
              original.store === store, original.ownership === ownership,
              binding === original.nativeBinding,
              !original.isClosing, !original.wholeWindowClose,
              !original.windowClosePending, !original.windowCloseApproved,
              let window = original.window, page.nativeView.window === window,
              let id = original.browsers.first(where: { $0.value.nativePage === page })?.key
                  ?? original.peekSource(of: page),
              original.ownership.canUse(id, owner: original.presentationID),
              !original.closingTabIDs.contains(id), !original.modelRetirementIDs.contains(id),
              !original.transferringTabIDs.contains(id), !store.retiringTabIDs.contains(id) else { return nil }
        return id
    }
    private func alternateNavigationReceipt(_ page: PCNativePage) -> (referrer: UUID?, top: Bool)? {
        guard page.responds(to: #selector(getter: PCNativePage.alternateNavigationSourcePage)),
              let source = page.alternateNavigationSourcePage,
              let binding = nativeBinding,
              PCNativeBrowserApplication.owner(of: source) === binding else { return nil }
        let top = page.alternateNavigationPlacesAtTop
        let referrer = creationSourceTab(source)
        if top, let referrer, browsers[referrer]?.nativePage !== source { return (nil, true) }
        return (referrer, top)
    }

    private func peekSource(of page: PCNativePage) -> UUID? {
        guard let peek = peeks[page.identifier], peek.page === page, !page.isClosed,
              !peek.parentPage.isClosed, browsers[peek.parentTabID]?.nativePage === peek.parentPage,
              PCNativeBrowserApplication.owner(of: peek.parentPage) === nativeBinding,
              peek.parentPage.profilePath == page.profilePath,
              !peekRetirementParents.contains(peek.parentTabID) else { return nil }
        return peek.parentTabID
    }

    private func openSearchNavigation(_ navigation: PCNativeSearchNavigation, replacing tabID: UUID?) {
        guard navigation.profilePath == store.independentEngineProfilePath(for: activeProfileID),
              presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        if openLocalNoteAddress(navigation.url.absoluteString) { return }
        if let tabID {
            guard currentTabID == tabID, !store.retiringTabIDs.contains(tabID), !closingTabIDs.contains(tabID) else { return }
            performWindowCommand {
                pendingSearchNavigations[tabID] = navigation
                requestedURLs.removeValue(forKey: tabID)
                store.updateTab(tabID, url: navigation.url.absoluteString)
            }
        } else {
            let id = UUID()
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                pendingSearchNavigations[id] = navigation
                store.openResolvedURL(navigation.url, id: id, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
    }

    var canAcceptExternalLink: Bool {
        !isPrivateBrowsing && !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose &&
        !windowClosePending && !windowCloseApproved && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
    }

    @discardableResult
    func openExternalURL(_ url: URL, inSpace spaceID: UUID) -> Bool {
        guard canAcceptExternalLink,
              store.state.spaces.contains(where: { $0.id == spaceID }) else { return false }
        if activeSpaceID != spaceID { selectSpace(spaceID) }
        else { cancelSpaceCreation(restoreFocus: false); sidebarPreviews?.dismiss() }
        guard activeSpaceID == spaceID, canAcceptExternalLink else { return false }
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.openResolvedURL(url, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        return true
    }

    var canShowLibrary: Bool {
        if isPrivateBrowsing { return false }
        return !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose && nativeFullscreenTabID == nil
    }
    var canShowMedia: Bool {
        if !isPrivateBrowsing { return canShowLibrary }
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, nativeFullscreenTabID == nil,
              privateCaptureContextIsValid, let parent = store.privateParentProfileID,
              let catalog = downloadCatalog, !catalog.isEphemeral else { return false }
        return catalog.state.profiles.contains(where: { $0.id == parent }) && !catalog.isProfileRemovalPending(parent)
    }
    var canShowDownloads: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose && nativeFullscreenTabID == nil
            && (!isPrivateBrowsing || nativeBinding?.privateDownloadsAvailable == true)
    }
    func showLibrary(_ kind: LibraryView.Kind) {
        cancelSpaceCreation(restoreFocus: false)
        sidebarPreviews?.dismiss()
        guard kind == .downloads ? canShowDownloads : kind == .captures ? canShowMedia : canShowLibrary else { return }
        pageCapture?.dismiss(restoreFocus: false)
        if let libraryView, libraryView.profileID == activeProfileID {
            libraryView.show(kind); return
        }
        closeLibrary(restoreFocus: false)
        commandBar?.dismiss()
        let profileID = activeProfileID
        let privateMedia: LibraryView.PrivateMediaContext?
        if isPrivateBrowsing, let parent = store.privateParentProfileID, let catalog = downloadCatalog {
            if privateMediaSource?.catalog !== catalog || privateMediaSource?.profileID != parent {
                privateMediaSource = (catalog, parent, ExternalMediaLibrary(
                    directory: catalog.capturesDirectory(for: parent), preferencesAreEphemeral: true))
            }
            guard let media = privateMediaSource?.media else { return }
            privateMedia = .init(store: catalog, profileID: parent, media: media, isValid: { [weak self, weak catalog] in
                guard let self, let catalog else { return false }
                return self.downloadCatalog === catalog && self.store.privateParentProfileID == parent
                    && self.activeProfileID == profileID && self.canShowMedia
            })
        } else { privateMedia = nil }
        let view = LibraryView(store: store, kind: kind, profileID: profileID, downloadStore: downloadStore,
                               privateMediaContext: privateMedia)
        view.onCreateNote = { [weak self] in self?.createNote() }
        view.onOpenDocument = { [weak self] page, title in
            guard let self, self.activeProfileID == profileID else { return }
            switch page { case .note(let id): self.openNote(id: id, title: title)
            case .easel(let id): self.closeLibrary(restoreFocus: false); self.openEasel(id: id, title: title) }
        }
        view.onRenameDocument = { [weak self] page, title in
            guard let self else { return }
            switch page { case .note(let id): self.store.updateNoteTitle(id: id, profileID: profileID, title: title)
            case .easel(let id): self.store.updateEaselTitle(id: id, profileID: profileID, title: title) }
        }
        view.onDeleteDocument = { [weak self, weak view] page, done in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID else { done(CocoaError(.userCancelled)); return }
            do {
                let note = try page.noteID.map { try NoteStore.sharedStore(directory: self.store.notesDirectory(for: profileID)).load($0) }
                let revision = note?.document.revision
                let easel = try page.easelID.map { try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID)).load($0) }
                let easelSnapshot = easel?.document
                self.store.deleteLocalDocument(page, profileID: profileID, ownerValid: { [weak self, weak view] in
                    guard let self, let view else { return false }
                    return self.libraryView === view && self.activeProfileID == profileID && !self.isClosing
                        && note?.document.revision == revision && easel?.document == easelSnapshot
                }, deleteDocument: {
                    if let id = page.noteID, let revision {
                        try NoteStore.sharedStore(directory: self.store.notesDirectory(for: profileID)).delete(id, expectedRevision: revision)
                    } else if let id = page.easelID {
                        try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: profileID)).delete(id)
                    }
                }, completion: done)
            } catch { done(error) }
        }
        view.palette = rootView.palette
        view.onClose = { [weak self] in self?.closeLibrary() }
        view.onToast = { [weak self, weak view] content in
            guard let self, let view, self.libraryView === view else { return }
            self.showToast(content, at: .window)
        }
        view.onOpenURLs = { [weak self, weak view] urls in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID,
                  !self.isPrivateBrowsing || (view.kind == .captures && self.canShowMedia) else { return }
            self.openLibraryURLs(urls, profileID: profileID)
        }
        view.archiveOwnerValid = { [weak self, weak view] in
            guard let self, let view else { return false }
            return self.libraryView === view && self.activeProfileID == profileID && !self.isClosing
                && !self.wholeWindowClose && !self.windowClosePending
        }
        view.onRestore = { [weak self, weak view] ids, destination in
            guard let self, let view, self.libraryView === view, self.activeProfileID == profileID else { return }
            if let peek = self.activePeek, let lease = self.archivePreviews[peek.identity],
               ids.contains(where: { id in lease.tabs.contains { $0.id == id } }) {
                if ids.count == 1 { self.promotePeek(peek, split: false) }
                return
            }
            self.restoreArchivedTabs(ids, profileID: profileID,
                destination: .putBack(currentSpaceID: self.activeSpaceID, requestedSpaceID: destination))
        }
        view.onPreview = { [weak self, weak view] id in
            guard let self, let view, self.libraryView === view, view.kind == .archive,
                  self.activeProfileID == profileID else { return false }
            return self.previewArchivedItem(id, profileID: profileID)
        }
        view.onDownloadAction = { [weak self, weak view] item, action in
            guard let self, let view, self.libraryView === view, view.kind == .downloads,
                  self.activeProfileID == profileID else { return false }
            return self.performLibraryDownload(item, action: action)
        }
        view.onLoadDownloads = { [weak self, weak view] in
            guard let self, let view, self.libraryView === view, view.kind == .downloads else { return }
            self.refreshDownloadProfiles()
        }
        view.downloadFileURL = { [weak self, weak view] item in
            guard let self, let view, self.libraryView === view, view.kind == .downloads,
                  self.activeProfileID == profileID else { return nil }
            return self.libraryDownloadFileURL(item)
        }
        libraryView = view
        libraryContentWidth = view.contentWidth
        view.onContentWidthChange = { [weak self, weak view] in
            guard let self, let view, self.libraryView === view else { return }
            self.setLibraryContentWidth(view.contentWidth)
        }
        configureSpaceManager(view)
        view.onShowKind = { [weak self] kind in self?.recordLibraryPage(kind) }
        recordLibraryPage(view.kind)
        sidebar.libraryDidOpen()
        view.requestIcon = { [weak self, weak view] url, requestedProfile, completion in
            guard let self, let view, self.libraryView === view,
                  requestedProfile == profileID, self.activeProfileID == profileID else { return }
            let path = self.store.independentEngineProfilePath(for: profileID)
            PCNativeBrowserApplication.favicon(for: url, profilePath: path) { [weak self, weak view] image in
                MainActor.assumeIsolated {
                    guard let self, let view, self.libraryView === view,
                          self.activeProfileID == profileID, !self.isClosing else { return }
                    completion(image)
                }
            }
        }
        rootView.addSubview(view)
        layoutChrome()
        refreshLibraryDownloadActivity()
        view.focusSearch()
        if kind == .downloads { refreshDownloadProfiles() }
    }

    private func configureSpaceManager(_ library: LibraryView) {
        let manager = library.spaceManager
        let valid: () -> Bool = { [weak self, weak library] in
            guard let self, let library else { return false }
            return self.libraryView === library && library.kind == .spaces && self.spaceCommandsAvailable
        }
        manager.ownerValid = valid
        manager.windowSpaceID = { [weak self] in self?.activeSpaceID }
        manager.onClose = { [weak self] in if valid() { self?.closeLibrary() } }
        library.onLeaveSpaces = { [weak self] in self?.spaceIconPicker?.cancel(); self?.themePopover?.performClose(nil) }
        manager.onCreate = { [weak self] in
            guard let self, valid() else { return }
            self.createSpace()
        }
        manager.onReorder = { [weak self] id, before, order in
            guard let self, valid(), self.managementSpace(id) != nil else { return false }
            do { return try self.store.reorderSpace(id, before: before, expectedOrder: order) }
            catch { showError(error); return false }
        }
        manager.makeMenu = { [weak self] id, _ in
            guard let self, valid() else { return nil }
            return self.spaceManagementMenu(id)?.makeMenu()
        }
        manager.configureSidebar = { [weak self, weak library] id, sidebar in
            guard let self, let library else { return }
            let targetValid: () -> Bool = { [weak self] in valid() && self?.managementSpace(id) != nil }
            sidebar.makeSpaceManagementMenu = { [weak self] target in targetValid() ? self?.spaceManagementMenu(target) : nil }
            sidebar.onRenameSpace = { [weak self] target in if targetValid() { self?.renameSpace(target) } }
            sidebar.onChangeSpaceIcon = { [weak self] target in if targetValid() { self?.changeSpaceIcon(target) } }
            sidebar.onEditTheme = { [weak self] in if targetValid() { self?.editTheme(spaceID: id) } }
            sidebar.onNewFolder = { [weak self] in if targetValid() { self?.createFolder(in: id) } }
            sidebar.onToggleFolder = { [weak self] folderID in
                guard let self, targetValid(), let space = self.managementSpace(id),
                      let folder = self.store.state.folders.first(where: { $0.id == folderID && $0.spaceID == id }) else { return }
                do { _ = try self.store.setFolderExpanded(!folder.isExpanded, expected: folder, profileID: space.profileID) }
                catch { showError(error) }
            }
            sidebar.prepareTabActivation = { [weak self] expected in
                guard let self, targetValid(), expected.spaceID == id,
                      self.store.state.tabs.contains(where: { $0.id == expected.id && $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                      self.canUseOrMoveHere(expected.id) else { return nil }
                return { [weak self] in
                    guard let self, targetValid(), self.store.state.tabs.contains(where: { $0.id == expected.id && $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                          self.canUseOrMoveHere(expected.id), self.selectSpaceFromUser(id, profileID: expected.profileID) else { return false }
                    self.closeLibrary(restoreFocus: false); self.selectTab(expected.id); return true
                }
            }
            sidebar.configureManagementInteraction(ownerValid: targetValid, onCancel: { [weak self] in
                if targetValid() { self?.closeLibrary() }
            })
            sidebar.prepareTabClose = { [weak self] expected in
                guard let self, targetValid(), expected.spaceID == id, self.canCloseOrMoveHere(expected.id),
                      self.retirementUnavailableReason?([expected.id]) == nil else { return nil }
                return { [weak self] in
                    guard let self, targetValid(), self.store.state.tabs.contains(where: { $0.id == expected.id && $0.spaceID == id && $0.profileID == expected.profileID && $0.archivedAt == nil }),
                          self.canCloseOrMoveHere(expected.id), self.retirementUnavailableReason?([expected.id]) == nil else { return false }
                    return self.closeTabMovingHere(expected.id)
                }
            }
            sidebar.onNewTab = { [weak self] in
                guard let self, targetValid(), let space = self.managementSpace(id), self.selectSpaceFromUser(id, profileID: space.profileID) else { return }
                self.closeLibrary(restoreFocus: false); self.newTab()
            }
            let clearable = { [weak self] () -> Set<UUID> in
                guard let self, let space = self.managementSpace(id) else { return [] }
                return SpaceClearToday.ids(in: self.store.state, spaceID: id, profileID: space.profileID)
                    .filter { self.ownership.canUse($0, owner: self.presentationID) }
            }
            sidebar.canClearToday = { targetValid() && !clearable().isEmpty }
            sidebar.onClearToday = { [weak self] in
                guard let self, targetValid(), let space = self.managementSpace(id) else { return }
                let ids = clearable()
                guard !ids.isEmpty else { NSSound.beep(); return }
                self.archiveTabs(ids, reason: .clearButton, in: space)
            }
            sidebar.managementItemMenu = { [weak self, weak sidebar] item in
                guard let self, let sidebar, targetValid() else { return nil }
                let menu = NSMenu(); menu.autoenablesItems = false
                switch item {
                case .folder(let folderID):
                    guard let folder = self.store.state.folders.first(where: { $0.id == folderID && $0.spaceID == id }) else { return nil }
                    menu.addItem(MenuAction.item(folder.isExpanded ? "Collapse Folder" : "Expand Folder") { sidebar.onToggleFolder?(folderID) })
                    menu.addItem(MenuAction.item("New Folder Inside…") { [weak self] in if targetValid() { self?.createFolder(in: id, parent: folder) } })
                    menu.addItem(MenuAction.item("Rename Folder…") { [weak self] in if targetValid() { self?.renameFolder(folderID) } })
                case .tab(let tabID), .split(let tabID):
                    let actual = { if case .split = item { return self.store.state.splitLayouts.first { $0.id == tabID }?.sidebarAnchorID }; return tabID }()
                    guard let tab = self.store.state.tabs.first(where: { $0.id == actual && $0.spaceID == id && $0.archivedAt == nil }) else { return nil }
                    let open = sidebar.prepareTabActivation?(tab)
                    let entry = MenuAction.item("Open Tab") { _ = open?() }; entry.isEnabled = open != nil; menu.addItem(entry)
                    if case .tab = item {
                        let close = sidebar.prepareTabClose?(tab)
                        let entry = MenuAction.item("Close Tab") { _ = close?() }; entry.isEnabled = close != nil; menu.addItem(entry)
                    }
                }
                return menu
            }
            sidebar.requestTabFavicon = { [weak self, weak library] tab, completion in
                guard let self, let library, self.libraryView === library, tab.spaceID == id,
                      let url = URL(string: tab.url), self.managementSpace(id, profileID: tab.profileID) != nil else { completion(nil); return }
                PCNativeBrowserApplication.favicon(for: url, profilePath: self.store.independentEngineProfilePath(for: tab.profileID)) { image in
                    MainActor.assumeIsolated { completion(image) }
                }
            }
        }
        manager.reload(store.state)
    }

    func clearArchive() {
        showLibrary(.archive)
        guard libraryView?.kind == .archive else { return }
        libraryView?.clearAll()
    }

    func showLibraryFromEntry(_ target: LibraryEntryPage?) {
        let showing = libraryView.flatMap { $0.profileID == activeProfileID ? Self.libraryPage($0.kind) : nil }
        switch LibraryEntryRoute.decide(target: target, showing: showing,
                                        lastSelected: LibraryEntryPreferences.shared.lastSelectedPage) {
        case .close: closeLibrary()
        case .open(let page): showLibrary(isPrivateBrowsing && page != .captures ? .downloads : Self.libraryKind(page))
        }
    }
    private func performLibraryFlyout(_ action: LibraryFlyoutAction) -> Bool {
        switch action {
        case let .download(item, command): return performLibraryDownload(item, action: command)
        case let .file(file, command): return performLibraryFlyoutFile(file, action: command)
        case .showCapture: showLibrary(.captures); return libraryView?.kind == .captures
        case .copyCapture(let capture):
            guard !isPrivateBrowsing, capture.profileID == activeProfileID else { return false }
            let library = CaptureLibraryStore.shared(directory: store.capturesDirectory(for: capture.profileID), profileID: capture.profileID)
            guard library.contains(capture) else { return false }
            Task { @MainActor in
                guard let data = try? await library.data(for: capture), library.contains(capture) else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .png)
            }
            return true
        case .openCaptureSource(let capture):
            guard !isPrivateBrowsing, capture.profileID == activeProfileID else { return false }
            openLibraryURLs([capture.sourceURL], profileID: capture.profileID); return true
        case .copyCaptureSource(let capture):
            NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(capture.sourceURL, forType: .string)
        case let .share(item, share): return shareLibraryFlyoutItem(item, share)
        case .deleteCapture(let capture): return deleteLibraryFlyoutCapture(capture)
        }
    }
    private func performLibraryFlyoutFile(_ file: LibraryFlyoutFile, action: LibraryFlyoutFileAction) -> Bool {
        guard window?.attachedSheet == nil, FileManager.default.fileExists(atPath: file.url.path) else { return false }
        switch action {
        case .open: return NSWorkspace.shared.open(file.url)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([file.url]); return true
        case .copyFile:
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([file.url as NSURL])
        }
    }
    private func libraryFlyoutCaptureStore(_ capture: SavedCapture) -> CaptureLibraryStore? {
        guard !isPrivateBrowsing, !isClosing, !wholeWindowClose, capture.profileID == activeProfileID else { return nil }
        let library = CaptureLibraryStore.shared(directory: store.capturesDirectory(for: capture.profileID), profileID: capture.profileID)
        return library.contains(capture) ? library : nil
    }
    private func shareLibraryFlyoutItem(_ item: LibraryFlyoutItem, _ share: LibraryFlyoutShare) -> Bool {
        guard let parent = window, parent.attachedSheet == nil else { return false }
        switch item {
        case .download(let download):
            guard let url = libraryDownloadFileURL(download) else { return false }
            Task.detached(priority: .userInitiated) { [weak self] in
                let bytes = LibraryFlyoutSharing.isImage(url) ? (try? Data(contentsOf: url)) : nil
                await MainActor.run { [weak self] in
                    guard let self, self.window === parent, self.libraryDownloadFileURL(download) == url else { return }
                    let items = LibraryFlyoutSharing.items(share, image: bytes.flatMap(NSImage.init(data:)), url: url, text: nil)
                    LibraryFlyoutSharing.perform(share, items: items)
                }
            }
            return true
        case .file(let file):
            guard FileManager.default.fileExists(atPath: file.url.path) else { return false }
            let url = file.url
            Task.detached(priority: .userInitiated) { [weak self] in
                let bytes = LibraryFlyoutSharing.isImage(url) ? (try? Data(contentsOf: url)) : nil
                await MainActor.run { [weak self] in
                    guard let self, self.window === parent else { return }
                    let items = LibraryFlyoutSharing.items(share, image: bytes.flatMap(NSImage.init(data:)), url: url, text: nil)
                    LibraryFlyoutSharing.perform(share, items: items)
                }
            }
            return true
        case .capture(let capture):
            guard let library = libraryFlyoutCaptureStore(capture) else { return false }
            Task { @MainActor [weak self] in
                guard let data = try? await library.data(for: capture), let self, self.window === parent,
                      self.libraryFlyoutCaptureStore(capture) === library else { return }
                let items = LibraryFlyoutSharing.items(share, image: NSImage(data: data), url: nil,
                                                       text: share == .message ? capture.sourceURL : nil)
                LibraryFlyoutSharing.perform(share, items: items)
            }
            return true
        }
    }
    private func deleteLibraryFlyoutCapture(_ capture: SavedCapture) -> Bool {
        guard let parent = window, parent.attachedSheet == nil, libraryFlyoutCaptureStore(capture) != nil else { return false }
        return LibraryFlyoutCaptureDeletion.confirm(in: parent) { [weak self, weak parent] approved in
            MainActor.assumeIsolated {
                guard approved, let self, let parent, self.window === parent,
                      let library = self.libraryFlyoutCaptureStore(capture),
                      let reservation = library.reserveDeletion(owner: self.store, item: capture) else { return }
                Task { @MainActor [weak self, weak parent] in
                    do { try await reservation.perform { try await library.delete(capture) } }
                    catch {
                        guard let self, let parent, self.window === parent, parent.attachedSheet == nil else { return }
                        ParcDialog.inform(in: parent, .init(error: error))
                    }
                }
            }
        }
    }
    private func updateLibraryEntryExpansion() {
        sidebar.libraryEntryExpansionAllowed = libraryView == nil && tabSwitcher == nil && commandBar == nil
    }
    private func recordLibraryPage(_ kind: LibraryView.Kind) {
        guard !isPrivateBrowsing else { return }
        LibraryEntryPreferences.shared.lastSelectedPage = Self.libraryPage(kind)
    }
    private static func libraryPage(_ kind: LibraryView.Kind) -> LibraryEntryPage {
        switch kind {
        case .downloads: return .downloads
        case .captures: return .captures
        case .documents: return .documents
        case .archive: return .archive
        case .spaces: return .spaces
        }
    }
    private static func libraryKind(_ page: LibraryEntryPage) -> LibraryView.Kind {
        switch page {
        case .downloads: return .downloads
        case .captures: return .captures
        case .documents: return .documents
        case .archive: return .archive
        case .spaces: return .spaces
        }
    }

    private func closeLibrary(restoreFocus: Bool = true) {
        if libraryView?.kind == .spaces {
            libraryView?.spaceManager.cancelEditing()
            spaceIconPicker?.cancel(); themePopover?.performClose(nil)
        }
        if libraryView != nil { sidebar.libraryDidClose() }
        libraryMotion.cancel()
        libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0
        layoutChrome()
        refreshPendingPaneSidebar()
        if restoreFocus, let window, window.isKeyWindow, window.attachedSheet == nil {
            if let currentBrowser { window.makeFirstResponder(currentBrowser) }
            else if showsStartPage, let bar = residentCommandBar { bar.focusResident() }
            else { focusSelectedLocalContent() }
        }
    }
    private func setLibraryContentWidth(_ width: CGFloat) {
        guard libraryContentWidth != width else { return }
        libraryContentWidth = width
        guard let libraryView, window?.isVisible == true, window?.isMiniaturized != true, !rootView.inLiveResize else {
            libraryMotion.cancel(); layoutChrome(); return
        }
        sidebarChromePass = .geometry
        libraryMotion.animate(layoutRoot: rootView,
                              views: [libraryView, pageHost, pageShadow, extensionSidePanel, findHost, loadingIndicator],
                              style: .libraryWidth) {
            layoutChrome()
        } completion: { [weak self] in
            guard let self, !self.isClosing, self.libraryView != nil else { return }
            self.pageHost.needsLayout = true
            self.extensionSidePanel.needsLayout = true
            self.layoutChrome()
        }
        sidebarChromePass = .full
    }

    private func openLibraryURLs(_ inputs: [String], profileID: UUID) {
        guard activeProfileID == profileID else { return }
        let urls = inputs.compactMap(URL.init(string:))
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            for url in urls {
                let id = store.openResolvedURL(url, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
    }

    private func restoreArchivedTabs(_ ids: [UUID], profileID: UUID, destination: ArchiveRestoreDestination) {
        guard activeProfileID == profileID else { return }
        let items = store.archivedItems(profileID: profileID).filter { ids.contains($0.id) }
        let allIDs = items.flatMap { $0.tabs.map(\.id) }
        guard !allIDs.isEmpty, allIDs.allSatisfy({ !store.retiringTabIDs.contains($0) }) else { return }
        guard allIDs.allSatisfy({ ownership.canUse($0, owner: presentationID) }) else { refuseTabMove(); return }
        var restored: [UUID] = []
        performWindowCommand {
            for item in items {
                restored += store.restoreArchivedTab(item.id, profileID: profileID, destination: destination)
            }
        }
        guard let first = restored.first, let tab = store.state.tabs.first(where: { $0.id == first }),
              let space = store.state.spaces.first(where: { $0.id == tab.spaceID }) else { return }
        showToast(.tabRestored(to: space.name, selected: selectedTabIDs.contains(first)), at: .window, onTap: { [weak self] in
            guard let self, self.activeProfileID == profileID,
                  let tab = self.store.state.tabs.first(where: { $0.id == first && $0.archivedAt == nil }) else { return }
            if tab.spaceID != self.activeSpaceID, !self.selectSpaceFromUser(tab.spaceID, profileID: profileID) { return }
            self.closeLibrary(restoreFocus: false)
            _ = self.selectTab(first)
        })
    }

    private func splitHomePlan(_ homes: [BrowserTab]) -> (ids: [UUID: UUID], documents: [UUID: SidebarDocumentReference])? {
        SplitMembership.homePlan(homes) { [resolveSidebarCopyDestinations] typed in resolveSidebarCopyDestinations?(typed)?.documents }
    }

    private func openSplitHomes(_ ids: [UUID: UUID], profileID: UUID, originatingSpaceID: UUID) {
        guard let window else { return }
        for homeID in ids.values {
            guard let home = store.state.tabs.first(where: { $0.id == homeID }) else { continue }
            openDuplicatedChildren([homeID], spaceID: home.spaceID, profileID: profileID,
                window: window, originatingSpaceID: originatingSpaceID)
        }
    }

    @discardableResult
    private func selectTab(_ id: UUID, extendingSplit: Bool = false) -> Bool {
        sidebarPreviews?.dismiss()
        guard !isPopupWindow || (id == currentTabID && !extendingSplit) else { return false }
        if let retry = transferRecoveries[id] { retry(); return false }
        guard presentation.isReady else { return false }
        let members: [UUID] = {
            guard !extendingSplit, let tab = store.state.tabs.first(where: { $0.id == id }) else { return [id] }
            let space = tab.kind == .favorite ? activeSpaceID : tab.spaceID
            return SidebarSplitItems.groups(in: store.state, spaceID: space).first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]
        }()
        guard let elsewhere = PageReparenting.pagesToMove(members,
                usableHere: { $0 == id && extendingSplit ? ownership.canUse($0, owner: presentationID) : switcherCanUse($0) },
                movable: canMovePageHere) else { return false }
        if !elsewhere.isEmpty {
            return movePagesHere(elsewhere[...]) { [weak self] in self?.selectTab(id, extendingSplit: extendingSplit) ?? false }
        }
        if extendingSplit {
            let space = activeSpaceID, profile = activeProfileID
            var plan: (ids: [UUID: UUID], documents: [UUID: SidebarDocumentReference])?
            performWindowCommand(selectNativePage: false) {
                guard let made = splitHomePlan(store.splitExtensionHomes(id)) else { return }
                plan = made
                store.selectTab(id, extendingSplit: true, savedHomeIDs: made.ids, documents: made.documents)
            }
            guard let plan else { return false }
            if selectedTabIDs.contains(id) { openSplitHomes(plan.ids, profileID: profile, originatingSpaceID: space) }
        } else {
            let previous = selectedTabIDs
            let expected: [UUID] = {
                guard let tab = store.state.tabs.first(where: { $0.id == id }) else { return [id] }
                let space = tab.kind == .favorite ? activeSpaceID : tab.spaceID
                return SidebarSplitItems.groups(in: store.state, spaceID: space)
                    .first { $0.tabIDs.contains(id) }?.tabIDs ?? [id]
            }()
            var committed = false
            let removal = previous == expected ? nil
                : presentationSetMediaRemoval(capturing: previous, remaining: { Set(self.selectedTabIDs) }) {
                    self.selectedTabIDs == expected && self.store.state.selectedTabIDs == expected
                }
            performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
                store.selectTab(id, extendingSplit: false)
                committed = store.state.selectedTabIDs == expected
            }
        }
        if selectedTabIDs.contains(id) {
            focusedTabID = id; updateNavigation(); requestNativeSelection(); focusSelectedContent(); return true
        }
        return false
    }

    var ownsSpaceCommandFocus: Bool {
        guard let window, NSApp.isActive, window.isVisible, !window.isMiniaturized else { return false }
        return window.isKeyWindow
    }

    var windowCommandSecurityAvailable: Bool {
        guard let window, let binding = nativeBinding, binding.window === window else { return false }
        return binding.canParticipateInPageTransfer
    }

    var ownsWindowCommandFocus: Bool {
        guard let window, NSApp.isActive, window.isVisible, !window.isMiniaturized else { return false }
        return ownsSpaceCommandFocus || (window.isMainWindow && navigationHistory?.ownsKeyWindow(in: window) == true)
    }

    func prepareLibraryMenuCommand() -> Bool {
        let profileID = activeProfileID
        guard let original = window, ownsWindowCommandFocus,
              windowCommandSecurityAvailable, canOwnDownloadDialog(for: profileID) else { return false }
        func current() -> Bool {
            window === original && activeProfileID == profileID && ownsWindowCommandFocus
                && windowCommandSecurityAvailable && canOwnDownloadDialog(for: profileID)
        }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard current() else { return false }
        }
        if commandBar?.hasFocus == true {
            commandBar?.dismiss()
            guard current() else { return false }
        }
        return original.isKeyWindow && current()
    }

    private var canCloseBrowserWindow: Bool {
        presentation.isReady && nativeBinding != nil && !isClosing
            && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && ownsSpaceCommandFocus
    }
    func prepareCloseWindowMenuItem(_ item: NSMenuItem) -> Bool {
        guard let original = window else { item.representedObject = nil; return false }
        let command = BrowserWindowCloseCommand(window: original,
            ownerIsAvailable: { [weak self, weak original] in
                guard let self, let original, self.window === original else { return false }
                return self.canCloseBrowserWindow
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) })
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    func prepareExitMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let original = window, let binding = nativeBinding else { return false }
        let common: () -> Bool = { [weak self, weak original, weak binding] in
            guard let self, let original, let binding, self.window === original,
                  self.nativeBinding === binding, binding.window === original else { return false }
            return self.presentation.isReady && self.ownsSpaceCommandFocus
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.windowCloseApproved && self.closingTabIDs.isEmpty
                && self.modelRetirementIDs.isEmpty && self.peekRetirementParents.isEmpty
                && self.transferringTabIDs.isEmpty && self.resolvingTransfers.isEmpty
                && self.transferRecoveries.isEmpty && self.pageCapture == nil
                && self.tabSwitcher == nil && self.navigationHistory == nil
                && self.themePopover == nil && !self.siteControlCenterDefers
                && PCNativeBrowserApplication.canUseWindowUndo(in: original)
        }
        guard common() else { return false }
        let available: () -> Bool
        let execute: () -> Bool
        if let session = spaceCreation {
            available = { [weak self, weak session] in
                guard let self, let session else { return false }
                return common() && self.creationOwnerIsCurrent(session)
                    && !session.committing && !session.view.hasMarkedText
            }
            execute = { [weak self, weak session] in
                guard let self, let session, self.creationOwnerIsCurrent(session),
                      !session.committing, !session.view.hasMarkedText else { return false }
                self.cancelSpaceCreation(); return true
            }
        } else if let peek = activePeek {
            available = { [weak self, weak peek] in
                guard let self, let peek else { return false }
                return common() && self.activePeek === peek && self.peeks[peek.page.identifier] === peek
                    && self.selectedNativePage() === peek.page && peek.canPrepareExit
            }
            execute = { [weak peek] in
                guard let peek, peek.canRequestExit else { return false }
                peek.requestDismiss(.exit); return true
            }
        } else if let page = selectedNativePage(), let native = binding.prepareFullscreenExit(for: page) {
            available = { [weak self, weak page] in
                guard let self, let page else { return false }
                return common() && self.activePeek == nil && self.selectedNativePage() === page && native.isAvailable
            }
            execute = { native.perform() }
        } else {
            guard nativeFullscreenTabID == nil,
                  original.styleMask.contains(.fullScreen) else { return false }
            let fullscreen = BrowserWindowFullscreenCommand(window: original,
                ownerIsAvailable: { [weak self, weak original] in
                    guard let self, let original else { return false }
                    return common() && self.activePeek == nil && self.nativeFullscreenTabID == nil
                        && original.styleMask.contains(.fullScreen)
                })
            available = {
                let validation = NSMenuItem(title: "Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
                return fullscreen.validate(validation)
            }
            execute = { fullscreen.perform(nil) }
        }
        let command = BrowserExitCommand(window: original, targetIsAvailable: available,
            prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) }, execute: execute)
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    func prepareFullscreenMenuItem(_ item: NSMenuItem) -> Bool {
        guard let original = window else { item.representedObject = nil; return false }
        let command = BrowserWindowFullscreenCommand(window: original,
            ownerIsAvailable: { [weak self, weak original] in
                guard let self, let original, self.window === original else { return false }
                return self.presentation.isReady && self.nativeBinding != nil && !self.isClosing
                    && !self.wholeWindowClose && !self.windowClosePending && !self.windowCloseApproved
                    && self.ownsSpaceCommandFocus
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) })
        let available = command.validate(item)
        item.representedObject = available ? command : nil
        return available
    }

    private var spaceStateAvailable: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && tabSwitcher == nil && themePopover == nil
    }
    private var spaceCommandsAvailable: Bool {
        guard spaceStateAvailable, ownsSpaceCommandFocus,
              let window, window.attachedSheet == nil else { return false }
        return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }

    func canSelectSpace(_ id: UUID, profileID: UUID? = nil) -> Bool {
        if isPrivateBrowsing { return false }
        return spaceCommandsAvailable && store.state.spaces.contains { space in
            space.id == id && (profileID == nil || space.profileID == profileID)
                && store.state.profiles.contains(where: { $0.id == space.profileID })
        }
    }

    @discardableResult
    func selectSpaceFromUser(_ id: UUID, profileID: UUID? = nil) -> Bool {
        guard canSelectSpace(id, profileID: profileID) else { return false }
        commandBar?.dismiss()
        guard canSelectSpace(id, profileID: profileID), let window,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
        cancelSpaceCreation(restoreFocus: false)
        guard activeSpaceID != id else { return true }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss()
        closeLibrary(restoreFocus: false)
        selectSpace(id)
        return activeSpaceID == id
    }

    private func adjacentSpace(forward: Bool) -> BrowserSpace? {
        let spaces = store.state.spaces
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return nil }
        return spaces[(index + (forward ? 1 : spaces.count - 1)) % spaces.count]
    }

    func canCycleSpace(forward: Bool) -> Bool {
        guard let destination = adjacentSpace(forward: forward) else { return false }
        return canSelectSpace(destination.id, profileID: destination.profileID)
    }

    func cycleSpace(forward: Bool) {
        guard let destination = adjacentSpace(forward: forward) else { return }
        selectSpaceFromUser(destination.id, profileID: destination.profileID)
    }

    func selectSpace(_ id: UUID) {
        cancelSpaceCreation(restoreFocus: false)
        sidebarPreviews?.dismiss()
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty else { return }
        let previousProfile = activeProfileID
        let outgoing = renderedPaneIDs
        let removal = presentationSetMediaRemoval(capturing: outgoing, remaining: { Set(self.renderedPaneIDs) }) {
            self.activeSpaceID == id
        }
        presentation.recordFocusedTab(currentTabID)
        pendingNativeSelection = nil
        presentation.selectSpace(id, state: store.state) { ownership.canUse($0, owner: presentationID) }
        focusedTabID = presentation.preferredFocusedTabID
        onSessionRecordChange?()
        let restoredLayout = presentation.splitLayout
        prepareStoreContext(restoringSplitLayout: restoredLayout)
        render(store.state)
        removal?()
        requestNativeSelection()
        focusSelectedContent()
        if previousProfile != activeProfileID { downloadReview?.dismiss() }
        refreshDownloads()
        if !isPopupWindow && !isPrivateBrowsing { store.linkRouting.noteVisitedSpace(activeSpaceID) }
        noteReturnGate()
    }

    private func movePagesHere(_ ids: ArraySlice<UUID>, then completion: @escaping () -> Bool) -> Bool {
        guard let id = ids.first else { return completion() }
        guard ownership.isClaimed(id), !ownership.canUse(id, owner: presentationID),
              let request = onRequestTabTransfer else { return movePagesHere(ids.dropFirst(), then: completion) }
        return request(id, self) { [weak self] in self?.movePagesHere(ids.dropFirst(), then: completion) ?? false }
    }

    private func moveRootsHere(_ ids: ArraySlice<UUID>, moved: [UUID], then close: @escaping ([UUID]) -> Bool) -> Bool {
        guard let id = ids.first else { return close(moved) }
        guard ownership.isClaimed(id), !ownership.canUse(id, owner: presentationID),
              let request = onRequestTabTransfer else { return moveRootsHere(ids.dropFirst(), moved: moved, then: close) }
        let arrival = PendingArrival { [weak self] in self?.returnMovedRoots(moved) }
        let started = request(id, self) { [weak self] in
            arrival.ran = true
            _ = self?.moveRootsHere(ids.dropFirst(), moved: moved + [id], then: close)
            return true
        }
        if !started { arrival.ran = true; returnMovedRoots(moved) }
        return started
    }
    private func returnMovedRoots(_ ids: [UUID]) { for id in ids { returnIfUnshown(id) } }

    func refuseTabMove() { NSSound.beep() }

    func displaysPlaceholder(for id: UUID) -> Bool { presentation.displayedPlaceholders.contains(id) }
    func showsPlaceholder(for id: UUID) -> Bool { presentation.showsPlaceholder(id) }

    private func pullBackPlaceholder(_ id: UUID) {
        guard presentation.displayedPlaceholders.contains(id), commandBar == nil, activePeek == nil,
              window?.attachedSheet == nil else { return }
        _ = selectTab(id)
    }

    private func capturePlaceholderSnapshot(_ id: UUID, page: PCNativePage, from source: BrowserWindowController,
                                            attempt: Int = 0, generation: Int? = nil) {
        let generation = generation ?? { placeholderCaptureGeneration += 1; return placeholderCaptureGeneration }()
        if attempt == 0 {
            source.syncPlaceholderImageHolders()
            placeholderCapturesPending[id] = generation
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + Double(attempt) * 0.15) { [weak self, weak source, weak page] in
            guard let self, self.placeholderCapturesPending[id] == generation else { return }
            guard let page, !page.isClosed, self.store.placeholderImages.isShown(id),
                  self.pageCapture == nil, let window = self.window,
                  self.browsers[id]?.nativePage === page, page.nativeView.window === window else {
                self.placeholderCapturesPending.removeValue(forKey: id); return
            }
            if attempt < 3, !PagePlaceholderCaptureOrder.mayCapture(id, pending: Set(self.placeholderCapturesPending.keys),
                                                                    focused: self.currentTabID) {
                self.capturePlaceholderSnapshot(id, page: page, from: source ?? self, attempt: attempt + 1, generation: generation)
                return
            }
            let key = ObjectIdentifier(page)
            guard Self.placeholderCaptureLeases[key] == nil, page.canCapture(in: window),
                  let capture = page.beginCapture(in: window) else {
                if attempt < 5, let source {
                    self.capturePlaceholderSnapshot(id, page: page, from: source, attempt: attempt + 1, generation: generation)
                } else { self.placeholderCapturesPending.removeValue(forKey: id) }
                return
            }
            Self.placeholderCaptureLeases[key] = capture
            capture.captureViewport { [weak self, weak source] result in
                capture.invalidate()
                if Self.placeholderCaptureLeases[key] === capture { Self.placeholderCaptureLeases.removeValue(forKey: key) }
                guard let self, self.placeholderCapturesPending[id] == generation else { return }
                guard let data = result.pngData, self.store.placeholderImages.isShown(id) else {
                    self.placeholderCapturesPending.removeValue(forKey: id); return
                }
                let size = PagePlaceholderSnapshot.maxPixelSize(source: result.pixelSize, filling: source?.placeholderPixelSize(for: id))
                PagePlaceholderSnapshot.thumbnail(fromPNG: data, maxPixelSize: size) { [weak self, weak source] image in
                    MainActor.assumeIsolated {
                        guard let self, self.placeholderCapturesPending[id] == generation else { return }
                        self.placeholderCapturesPending.removeValue(forKey: id)
                        source?.syncPlaceholderImageHolders()
                        if let image { self.store.placeholderImages.store(image, for: id) }
                    }
                }
            }
        }
    }

    private func syncPlaceholderImageHolders() {
        store.placeholderImages.setShown(presentation.allPlaceholders, in: presentationID)
    }
    private static var placeholderCaptureLeases: [ObjectIdentifier: PCNativePageCapture] = [:]
    private static func yieldPlaceholderCapture(of page: PCNativePage) {
        placeholderCaptureLeases.removeValue(forKey: ObjectIdentifier(page))?.invalidate()
    }
    private func placeholderPixelSize(for id: UUID) -> CGSize? {
        guard let size = panes[id]?.bounds.size, size.width > 0, size.height > 0 else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    private func paneSizedSnapshot(_ image: CGImage, for id: UUID) -> CGImage {
        guard let pixels = placeholderPixelSize(for: id) else { return image }
        return PagePlaceholderView.downsampled(image, toFill: pixels)
    }

    private func scheduleUntargetedReturns() {
        guard !untargetedReturnScheduled, onUntargetedReturn != nil else { return }
        untargetedReturnScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.untargetedReturnScheduled = false
            guard self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.transferringTabIDs.isEmpty, self.resolvingTransfers.isEmpty, self.collectionTransfer == nil,
                  self.nativeFullscreenTabID == nil else { return }
            let shown = Set(self.presentation.displayedTabIDs)
            for id in self.returnableIDs.sorted(by: { $0.uuidString < $1.uuidString })
            where !shown.contains(id) && self.shownSinceArrival.contains(id)
                && (self.canHandOverPage(id) || self.holdsEmptyClaim(id)) {
                self.shownSinceArrival.remove(id)
                let outcome = self.onUntargetedReturn?(id, self, .deselected)
                if outcome == .started { return }
                if outcome == .blocked, self.failedDuringReturn != id { self.heldReturns.insert(id) }
            }
        }
    }
    func retryHeldReturns() {
        guard !heldReturns.isEmpty, !isClosing else { return }
        shownSinceArrival.formUnion(heldReturns)
        heldReturns.removeAll()
        scheduleUntargetedReturns()
    }
    private func holdFailedReturn(_ id: UUID) {
        failedDuringReturn = id
        guard !presentation.displayedTabIDs.contains(id), heldContentIDs.contains(id) || holdsEmptyClaim(id) else { return }
        if failedReturns.insert(id).inserted { heldReturns.insert(id) } else {
            failedReturns.remove(id); heldReturns.remove(id); shownSinceArrival.remove(id)
        }
    }
    func returnFailed(_ id: UUID) -> Bool { failedDuringReturn == id }
    private var returnGateOpen: Bool {
        presentation.isReady && activePeek == nil && !promotingPeek && commandBar == nil && tabSwitcher == nil
            && themePopover == nil && !siteControlCenterDefers && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty
            && peekRetirementParents.isEmpty && peeks.values.allSatisfy({ !$0.closePending })
            && !store.isProfileRemovalPending(activeProfileID) && nativeBinding?.canParticipateInPageTransfer == true
    }
    private func noteReturnGate() {
        let open = returnGateOpen, space = activeSpaceID
        defer { returnGateWasOpen = open; returnGateSpaceID = space }
        if open, !returnGateWasOpen || space != returnGateSpaceID { onReturnUnblocked?() }
    }

    private var heldContentIDs: Set<UUID> {
        Set(browsers.keys).union(noteEditors.keys).union(easelEditors.keys)
    }
    private var returnableIDs: Set<UUID> {
        heldContentIDs.union(panes.keys.filter(holdsEmptyClaim)).union(shownSinceArrival.union(heldReturns).filter(holdsEmptyClaim))
    }
    private func returnIfUnshown(_ id: UUID) {
        guard !presentation.displayedTabIDs.contains(id), heldContentIDs.contains(id) || holdsEmptyClaim(id) else { return }
        shownSinceArrival.insert(id)
        scheduleUntargetedReturns()
    }
    private func placeArrival(_ id: UUID, placement: @escaping () -> Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !placement(), !self.selectTab(id) { self.returnIfUnshown(id) }
        }
    }
    private func canHandOverPage(_ id: UUID) -> Bool {
        guard claimsTab(id), switcherCanUse(id), !peekRetirementParents.contains(id) else { return false }
        if let browser = browsers[id] { return browser.nativePage.map { !$0.isClosed } == true }
        return noteEditors[id] != nil || easelEditors[id] != nil
    }

    func showTabTransferFailure(_ detail: String) {
        if let window { ParcDialog.inform(in: window, .init(title: "This tab couldn’t move", message: detail)) }
    }

    @discardableResult
    func transferTab(_ id: UUID, to destination: BrowserWindowController, placement: (() -> Bool)? = nil,
                     untargeted: Bool = false) -> Bool {
        if untargeted { failedDuringReturn = nil }
        if untargeted, holdsEmptyClaim(id) {
            guard handOverEmptyClaim(id, to: destination) else { return false }
            if !destination.rendering { destination.render(destination.store.state) }
            return true
        }
        if let peek = peeks.values.first(where: { $0.parentTabID == id && !$0.page.isClosed }) {
            return transferTabWithPeek(id, peek: peek, to: destination, placement: placement, untargeted: untargeted)
        }
        if browsers[id] == nil, noteEditors[id] != nil || easelEditors[id] != nil {
            return transferDocument(id, to: destination, placement: placement, untargeted: untargeted)
        }
        guard self !== destination, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              transferringTabIDs.isEmpty, destination.transferringTabIDs.isEmpty,
              !isClosing, !wholeWindowClose, !destination.isClosing, !destination.wholeWindowClose,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id),
              nativeFullscreenTabID != id, destination.nativeFullscreenTabID == nil,
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed,
              let sourceWindow = window, browser.window === sourceWindow,
              let destinationWindow = destination.window, destinationWindow !== sourceWindow,
              let binding = destination.nativeBinding,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == browserProfiles[id], tab.profileID == destination.activeProfileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              destination.browsers[id] == nil,
              let reservation = ownership.reserveTransfer(id, page: page.identifier,
                  from: presentationID, to: destination.presentationID) else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transferringTabIDs.insert(id)
        destination.transferringTabIDs.insert(id)
        let container = NSView(frame: destination.pageHost.bounds)
        container.autoresizingMask = [.width, .height]
        destination.parkedPages.addSubview(container)
        destination.transferContainers[page.identifier] = container
        attachedPageIDs.remove(page.identifier)
        binding.transferPage(page, profilePath: page.profilePath, container: container) { [self, destination, browser, page, container] result, error in
            MainActor.assumeIsolated {
                resolveTabTransfer(id, reservation: reservation, tab: tab, browser: browser,
                    page: page, container: container, destination: destination,
                    placement: placement, untargeted: untargeted, detail: error?.localizedDescription)
            }
        }
        return true
    }

    private func transferDocument(_ id: UUID, to destination: BrowserWindowController,
                                  placement: (() -> Bool)?, untargeted: Bool) -> Bool {
        let snapshot: CGImage? = panes[id].flatMap { pane in
            guard pane.window != nil, !pane.isHiddenOrHasHiddenAncestor, !pane.bounds.isEmpty,
                  let bitmap = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) else { return nil }
            pane.cacheDisplay(in: pane.bounds, to: bitmap)
            return bitmap.cgImage
        }
        var plan = SidebarWindowTransfer.Plan(tabIDs: [id], sourceSpaceID: activeSpaceID, profileID: activeProfileID,
            destinationSpaceID: destination.activeSpaceID, isCurrent: { _ in true }, commit: { _ in true })
        plan.leavesPlaceholder = true
        plan.failureReport = untargeted ? .silent : .beep
        guard self !== destination, store === destination.store, activeProfileID == destination.activeProfileID,
              !isPopupWindow, !destination.isPopupWindow,
              sidebarWindowMoveAvailable, destination.sidebarWindowMoveAvailable,
              let transaction = SidebarWindowTransfer(source: self, destination: destination, plan: plan) else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transaction.onFinish = { [weak self, weak destination] committed in
            guard let self else { return }
            defer { self.resumeCloseAfterEjecting() }
            guard committed else { if untargeted { self.holdFailedReturn(id) }; return }
            guard let destination else { return }
            if let snapshot, self.presentation.showsPlaceholder(id) {
                self.syncPlaceholderImageHolders()
                self.store.placeholderImages.store(self.paneSizedSnapshot(snapshot, for: id), for: id)
                if !self.rendering { self.render(self.store.state) }
            }
            guard !untargeted else { return }
            destination.window?.makeKeyAndOrderFront(nil)
            destination.placeArrival(id, placement: placement ?? { false })
        }
        guard transaction.begin() else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        return true
    }

    private func resolveTabTransfer(_ id: UUID, reservation: NativePageOwnership.Transfer,
                                    tab: BrowserTab, browser: PCBrowserView, page: PCNativePage,
                                    container: NSView, destination: BrowserWindowController,
                                    placement: (() -> Bool)?, untargeted: Bool, detail: String?) {
        guard !resolvingTransfers.contains(id), transferringTabIDs.contains(id) else { return }
        resolvingTransfers.insert(id)
        defer { resolvingTransfers.remove(id) }
        let finish = {
            self.transferRecoveries.removeValue(forKey: id)
            destination.transferRecoveries.removeValue(forKey: id)
            self.transferringTabIDs.remove(id)
            destination.transferringTabIDs.remove(id)
            destination.transferContainers.removeValue(forKey: page.identifier)
            self.refreshMiniPlayers(force: true)
            destination.refreshMiniPlayers(force: true)
            self.schedulePresentationSessionRecord()
            destination.schedulePresentationSessionRecord()
            if container.subviews.isEmpty { container.removeFromSuperview() }
            self.resumeCloseAfterEjecting()
        }
        let finishClosed = {
            _ = self.ownership.finishTransfer(reservation, moved: false)
            finish()
            self.releaseClosedTab(id, updateSavedTab: false)
            destination.discardTransferPane(id)
            self.render(self.store.state)
            destination.render(self.store.state)
            self.requestNativeSelection()
            destination.requestNativeSelection()
        }
        if page.isClosed { finishClosed(); return }
        let owner = PCNativeBrowserApplication.owner(of: page)
        var resolved = false
        var moved = false
        var leftPlaceholder = false
        if browsers[id] === browser, ownership.isCurrent(reservation),
           let binding = destination.nativeBinding, owner === binding,
           let destinationWindow = destination.window {
            let pane = destination.panes[id] ?? destination.makePane(tab)
            destination.panes[id] = pane
            if pane.superview == nil { destination.parkedPages.addSubview(pane) }
            if panes[id]?.browser === browser { panes[id]?.browser = nil }
            if pane.browser !== browser || browser.window !== destinationWindow { pane.browser = browser }
            pane.showBrowser()
            if binding.pageDidAttach(page, container: browser), !page.isClosed,
               PCNativeBrowserApplication.owner(of: page) === binding,
               browser.window === destinationWindow,
               ownership.finishTransfer(reservation, moved: true) {
                let request = requestedURLs.removeValue(forKey: id)
                let zoom = zoomLevels.removeValue(forKey: id)
                let loading = loadingTabs.remove(id) != nil
                failures.removeValue(forKey: id)
                browsers.removeValue(forKey: id)
                browserProfiles.removeValue(forKey: id)
                liveTabModels.removeValue(forKey: id)
                panes.removeValue(forKey: id)?.removeFromSuperview()
                leftPlaceholder = presentation.leavePlaceholder(id, state: store.state)
                renderedPaneIDs.removeAll { $0 == id }
                if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
                destination.browsers[id] = browser
                destination.browserProfiles[id] = tab.profileID
                destination.liveTabModels[id] = store.state.tabs.first { $0.id == id } ?? tab
                destination.requestedURLs[id] = request ?? tab.url
                destination.zoomLevels[id] = zoom
                destination.failures.removeValue(forKey: id)
                if loading { destination.loadingTabs.insert(id) }
                browser.delegate = destination
                destination.attachedPageIDs.insert(page.identifier)
                destination.presentation.adopt(id, state: store.state, foreground: placement == nil)
                if placement == nil { destination.focusedTabID = id }
                resolved = true
                moved = true
            }
        } else if browsers[id] === browser, ownership.isCurrent(reservation),
                  let binding = nativeBinding, owner === binding, let sourceWindow = window {
            if destination.panes[id]?.browser === browser { destination.panes[id]?.browser = nil }
            if let pane = panes[id], pane.browser !== browser || browser.window !== sourceWindow { pane.browser = browser }
            if binding.pageDidAttach(page, container: browser), !page.isClosed,
               PCNativeBrowserApplication.owner(of: page) === binding,
               browser.window === sourceWindow,
               ownership.finishTransfer(reservation, moved: false) {
                attachedPageIDs.insert(page.identifier)
                failures.removeValue(forKey: id)
                destination.discardTransferPane(id)
                resolved = true
            }
        }
        if page.isClosed { finishClosed(); return }
        if resolved {
            finish()
            render(store.state)
            destination.render(store.state)
            requestNativeSelection()
            destination.requestNativeSelection()
            if moved {
                destination.prepareStoreContext()
                if !untargeted { destination.window?.makeKeyAndOrderFront(nil) }
                if leftPlaceholder { destination.capturePlaceholderSnapshot(id, page: page, from: self) }
                if let placement { destination.placeArrival(id, placement: placement) }
            } else if detail != nil, !untargeted {
                destination.refuseTabMove()
            } else if untargeted {
                holdFailedReturn(id)
            }
            return
        }
        let retry: () -> Void = { [weak self, weak destination, browser, page, container] in
            guard let self, let destination else { return }
            self.resolveTabTransfer(id, reservation: reservation, tab: tab, browser: browser,
                page: page, container: container, destination: destination,
                placement: placement, untargeted: untargeted, detail: detail)
        }
        presentTransferRecovery(id, destination: destination, pages: [page], retry: retry)
    }

    private func presentTransferRecovery(_ id: UUID, destination: BrowserWindowController,
                                         pages: [PCNativePage], retry: @escaping () -> Void) {
        transferRecoveries[id] = retry
        destination.transferRecoveries[id] = retry
        var content = ParcDialog.Content(title: "The page move needs attention",
            message: "The live page is retained, but its current owner or attachment couldn’t be confirmed. Retry to reconnect it, or close the actual page with its normal leave-page confirmation.",
            confirm: "Retry")
        content.secondary = "Close Page"; content.auxiliary = "Keep Open"
        func close(_ remaining: ArraySlice<PCNativePage>) {
            guard let page = remaining.first else { retry(); return }
            guard !page.isClosed else { close(remaining.dropFirst()); return }
            page.requestClose { _ in MainActor.assumeIsolated { close(remaining.dropFirst()) } }
        }
        if let window = destination.window {
            _ = ParcDialog(content).begin(for: window) { response in
                if response == .confirm { retry() }
                else if response == .secondary { close(pages[...]) }
            }
        }
    }

    private func transferTabWithPeek(_ id: UUID, peek: PeekController, to destination: BrowserWindowController,
                                     placement: (() -> Bool)?, untargeted: Bool) -> Bool {
        guard self !== destination, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              transferringTabIDs.isEmpty, destination.transferringTabIDs.isEmpty,
              collectionTransfer == nil, destination.collectionTransfer == nil,
              !isClosing, !wholeWindowClose, !destination.isClosing, !destination.wholeWindowClose,
              !promotingPeek, !peek.closePending, peeks[peek.page.identifier] === peek,
              peeks.values.filter({ $0.parentTabID == id && !$0.page.isClosed }).count == 1,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id), !peekRetirementParents.contains(id),
              nativeFullscreenTabID != id, destination.nativeFullscreenTabID == nil, destination.activePeek == nil,
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed, peek.parentPage === page,
              !peek.page.isClosed, let sourceWindow = window, browser.window === sourceWindow,
              peek.browser.window === sourceWindow, let sourceBinding = nativeBinding,
              PCNativeBrowserApplication.owner(of: page) === sourceBinding,
              PCNativeBrowserApplication.owner(of: peek.page) === sourceBinding,
              let destinationWindow = destination.window, destinationWindow !== sourceWindow,
              let binding = destination.nativeBinding,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == browserProfiles[id], tab.profileID == destination.activeProfileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              peek.page.profilePath == page.profilePath, destination.browsers[id] == nil,
              let reservation = ownership.reserveCollection([id, peek.identity], from: presentationID, to: destination.presentationID)
        else {
            if !untargeted { destination.refuseTabMove() }
            return false
        }
        transferringTabIDs.insert(id)
        destination.transferringTabIDs.insert(id)
        let moving = [page, peek.page]
        let containers = moving.map { movingPage -> NSView in
            let container = NSView(frame: destination.pageHost.bounds)
            container.autoresizingMask = [.width, .height]
            destination.parkedPages.addSubview(container)
            destination.transferContainers[movingPage.identifier] = container
            return container
        }
        attachedPageIDs.remove(page.identifier)
        binding.transferPages(moving, profilePath: page.profilePath, containers: containers, commit: { true }) { [self] _, error in
            MainActor.assumeIsolated {
                resolvePeekTransfer(id, peek: peek, reservation: reservation, tab: tab, browser: browser, page: page,
                    containers: containers, destination: destination, placement: placement,
                    untargeted: untargeted, failed: error != nil)
            }
        }
        return true
    }

    private func resolvePeekTransfer(_ id: UUID, peek: PeekController, reservation: NativePageOwnership.CollectionTransfer,
                                     tab: BrowserTab, browser: PCBrowserView, page: PCNativePage, containers: [NSView],
                                     destination: BrowserWindowController, placement: (() -> Bool)?,
                                     untargeted: Bool, failed: Bool) {
        guard transferringTabIDs.contains(id), !resolvingTransfers.contains(id) else { return }
        resolvingTransfers.insert(id)
        defer { resolvingTransfers.remove(id) }
        let moving = [page, peek.page]
        var closed = Set<UUID>()
        if page.isClosed { closed.insert(id) }
        if peek.page.isClosed { closed.insert(peek.identity) }
        let retry: () -> Void = { [weak self, weak destination, weak peek, browser, page] in
            guard let self, let destination, let peek else { return }
            self.resolvePeekTransfer(id, peek: peek, reservation: reservation, tab: tab, browser: browser, page: page,
                containers: containers, destination: destination, placement: placement, untargeted: untargeted, failed: failed)
        }
        let finish = {
            self.transferRecoveries.removeValue(forKey: id)
            destination.transferRecoveries.removeValue(forKey: id)
            self.transferringTabIDs.remove(id)
            destination.transferringTabIDs.remove(id)
            for (movingPage, container) in zip(moving, containers) {
                destination.transferContainers.removeValue(forKey: movingPage.identifier)
                if container.subviews.isEmpty { container.removeFromSuperview() }
            }
            self.refreshMiniPlayers(force: true)
            destination.refreshMiniPlayers(force: true)
            self.schedulePresentationSessionRecord()
            destination.schedulePresentationSessionRecord()
            self.resumeCloseAfterEjecting()
        }
        let live = moving.filter { !$0.isClosed }
        guard ownership.isCurrent(reservation, closed: closed), !live.isEmpty else {
            if live.isEmpty, ownership.finishCollection(reservation, moved: false, closed: closed) {
                finish()
                releaseClosedTab(id, updateSavedTab: false)
                removePeek(peek)
                render(store.state); destination.render(store.state)
                requestNativeSelection(); destination.requestNativeSelection()
                return
            }
            presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
        }
        if live.allSatisfy({ PCNativeBrowserApplication.owner(of: $0) === destination.nativeBinding }),
           let binding = destination.nativeBinding, let destinationWindow = destination.window {
            if !page.isClosed {
                let pane = destination.panes[id] ?? destination.makePane(tab)
                destination.panes[id] = pane
                if pane.superview == nil { destination.parkedPages.addSubview(pane) }
                if panes[id]?.browser === browser { panes[id]?.browser = nil }
                if pane.browser !== browser || browser.window !== destinationWindow { pane.browser = browser }
                pane.showBrowser()
                guard binding.pageDidAttach(page, container: browser), browser.window === destinationWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            if !peek.page.isClosed {
                if peek.view.superview !== destination.pageHost {
                    destination.pageHost.addSubview(peek.view, positioned: .above, relativeTo: nil)
                }
                peek.view.frame = destination.pageHost.bounds
                guard binding.pageDidAttach(peek.page, container: peek.browser), peek.browser.window === destinationWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            guard ownership.finishCollection(reservation, moved: true, closed: closed) else {
                presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
            }
            let request = requestedURLs.removeValue(forKey: id)
            let zoom = zoomLevels.removeValue(forKey: id)
            let loading = loadingTabs.remove(id) != nil
            failures.removeValue(forKey: id)
            browsers.removeValue(forKey: id); browserProfiles.removeValue(forKey: id); liveTabModels.removeValue(forKey: id)
            panes.removeValue(forKey: id)?.removeFromSuperview()
            let leftPlaceholder = presentation.leavePlaceholder(id, state: store.state)
            renderedPaneIDs.removeAll { $0 == id }
            if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
            peeks.removeValue(forKey: peek.page.identifier)
            if !page.isClosed {
                destination.browsers[id] = browser
                destination.browserProfiles[id] = tab.profileID
                destination.liveTabModels[id] = store.state.tabs.first { $0.id == id } ?? tab
                destination.requestedURLs[id] = request ?? tab.url
                destination.zoomLevels[id] = zoom
                destination.failures.removeValue(forKey: id)
                if loading { destination.loadingTabs.insert(id) }
                browser.delegate = destination
                destination.attachedPageIDs.insert(page.identifier)
            }
            if !peek.page.isClosed {
                destination.peeks[peek.page.identifier] = peek
                destination.wirePeek(peek, binding: binding)
                destination.zoomLevels[peek.identity] = zoomLevels.removeValue(forKey: peek.identity)
                destination.inputRevisions[peek.identity] = inputRevisions.removeValue(forKey: peek.identity)
            } else {
                zoomLevels.removeValue(forKey: peek.identity); inputRevisions.removeValue(forKey: peek.identity)
                peek.finish()
            }
            destination.presentation.adopt(id, state: store.state, foreground: placement == nil)
            if placement == nil { destination.focusedTabID = id }
            finish()
            render(store.state); destination.render(store.state)
            destination.layoutPeeks()
            requestNativeSelection(); destination.requestNativeSelection()
            destination.prepareStoreContext()
            if !untargeted { destination.window?.makeKeyAndOrderFront(nil) }
            if leftPlaceholder, !page.isClosed { destination.capturePlaceholderSnapshot(id, page: page, from: self) }
            if let placement { destination.placeArrival(id, placement: placement) }
            return
        }
        if live.allSatisfy({ PCNativeBrowserApplication.owner(of: $0) === nativeBinding }),
           let binding = nativeBinding, let sourceWindow = window {
            if !page.isClosed {
                if destination.panes[id]?.browser === browser { destination.panes[id]?.browser = nil }
                if let pane = panes[id], pane.browser !== browser || browser.window !== sourceWindow { pane.browser = browser }
                guard binding.pageDidAttach(page, container: browser), browser.window === sourceWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            if !peek.page.isClosed {
                guard binding.pageDidAttach(peek.page, container: peek.browser), peek.browser.window === sourceWindow else {
                    presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
                }
            }
            guard ownership.finishCollection(reservation, moved: false, closed: closed) else {
                presentTransferRecovery(id, destination: destination, pages: live, retry: retry); return
            }
            if !page.isClosed { attachedPageIDs.insert(page.identifier) }
            destination.discardTransferPane(id)
            finish()
            render(store.state); destination.render(store.state)
            layoutPeeks()
            requestNativeSelection(); destination.requestNativeSelection()
            if failed, !untargeted { destination.refuseTabMove() }
            if untargeted, !page.isClosed { holdFailedReturn(id) }
            return
        }
        presentTransferRecovery(id, destination: destination, pages: live, retry: retry)
    }

    private func discardTransferPane(_ id: UUID) {
        guard browsers[id] == nil, let pane = panes.removeValue(forKey: id) else { return }
        pane.browser = nil
        pane.removeFromSuperview()
        if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
    }

    func nativePage(forTabID id: UUID) -> PCNativePage? {
        guard let page = browsers[id]?.nativePage, !page.isClosed else { return nil }
        return page
    }
    func holdsContent(forTabID id: UUID) -> Bool {
        nativePage(forTabID: id) != nil || noteEditors[id] != nil || easelEditors[id] != nil
    }

    func hasPendingNativePage(in ids: Set<UUID>) -> Bool {
        ids.contains { id in
            (browsers[id].map { $0.nativePage == nil && $0.isLoading } ?? false)
                || easelEditors[id]?.editor.pageObjects?.hasPendingCreation == true
        }
    }

    private var currentTabID: UUID? {
        if let nativeFullscreenTabID { return nativeFullscreenTabID }
        if let focusedTabID, selectedTabIDs.contains(focusedTabID) { return focusedTabID }
        return selectedTabIDs.first
    }
    private var currentBrowser: PCBrowserView? {
        if let peek = activePeek { return peek.browser }
        guard let id = currentTabID, !transferringTabIDs.contains(id), let tab = store.state.tabs.first(where: { $0.id == id }),
              !InternalPage.isInternal(tab.url) else { return nil }
        return browsers[id]
    }

    var canCreateNote: Bool {
        !isPopupWindow && !isPrivateBrowsing && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && window?.attachedSheet == nil && !store.isProfileRemovalPending(activeProfileID)
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty && activePeek == nil
    }
    var canCreateNoteInSplit: Bool { canCreateNote && !selectedTabIDs.isEmpty && selectedTabIDs.count < 4 }
    var isExportingNotes: Bool { noteExport != nil }
    var canExportNotes: Bool { canCreateNote && noteExport == nil }
    func prepareNotesForExport(profileID: UUID) -> Bool {
        var ready = true
        for note in noteEditors.values where note.profileID == profileID {
            if !note.editor.prepareToClose() { ready = false }
        }
        guard ready else { return false }
        do {
            try NoteStore.sharedStore(directory: store.notesDirectory(for: profileID)).flushAllDelayedDiskSaves()
            return true
        } catch { return false }
    }
    func exportNotes() {
        guard canExportNotes, let originalWindow = window else { return }
        let profile = activeProfileID
        do {
            let notes = try NoteStore.sharedStore(directory: store.notesDirectory(for: profile))
            try notes.flushAllDelayedDiskSaves()
            let documents = try notes.list()
            guard !documents.isEmpty else { throw NoteExportError.empty }
            let owner = NoteExportController(window: originalWindow, isValid: { [weak self, weak originalWindow] in
                guard let self, let originalWindow else { return false }
                return self.window === originalWindow && self.presentation.isReady
                    && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && !self.isPrivateBrowsing && self.activeProfileID == profile
                    && !self.store.isProfileRemovalPending(profile)
            }, onFinish: { [weak self] in self?.noteExport = nil },
               onError: { [weak self] in self?.showNoteError($0) })
            noteExport = owner; owner.begin(documents)
        } catch { showNoteError(error) }
    }

    func createNote(inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        do {
            let notes = try NoteStore.sharedStore(directory: store.notesDirectory(for: activeProfileID))
            let session = try notes.create()
            openNote(id: session.document.id, title: session.displayTitle, inSplit: inSplit)
        } catch { showNoteError(error) }
    }
    private func openLocalNoteAddress(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "parc",
              parts.host?.lowercased() == "note" else { return false }
        guard canCreateNote else { return true }
        do {
            guard let id = InternalPage(urlString: value)?.noteID else { throw NoteError.invalid }
            let note = try NoteStore.sharedStore(directory: store.notesDirectory(for: activeProfileID)).load(id)
            openNote(id: id, title: note.displayTitle)
        } catch { showNoteError(error) }
        return true
    }
    func openNote(id: UUID, title: String, inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        closeLibrary(restoreFocus: false)
        performWindowCommand { _ = store.openNote(id: id, title: title, inSplit: inSplit) }
        focusSelectedLocalContent()
    }
    func noteEditorsForRetirement(in ids: Set<UUID>) -> [UUID: NoteEditorViewController] {
        Dictionary(uniqueKeysWithValues: noteEditors.filter { ids.contains($0.key) }.map {
            ($0.key, $0.value.editor)
        })
    }
    func prepareNotesToClose(_ ids: Set<UUID>? = nil) -> Bool {
        var accepted = true
        for (id, note) in noteEditors where ids == nil || ids!.contains(id) {
            if !note.editor.prepareToClose() { accepted = false }
        }
        return accepted
    }
    private func showError(_ error: Error) {
        if window != nil { ParcDialog.present(error) }
    }
    private func showNoteError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(error: error), queued: true)
    }
    private func showNote(_ tab: BrowserTab, id: UUID, in pane: BrowserPane) {
        guard !isPrivateBrowsing, !store.isProfileRemovalPending(tab.profileID) else { pane.showError("Notes are unavailable in this Space."); return }
        if let cached = noteEditors[tab.id], cached.documentID == id, cached.profileID == tab.profileID {
            pane.showNativeContent(cached.editor.view); return
        }
        do {
            let editor = try NoteEditorViewController(directory: store.notesDirectory(for: tab.profileID), documentID: id)
            configureNoteOwner(tab, id: id, editor: editor)
            noteEditors[tab.id] = NotePane(documentID: id, profileID: tab.profileID, editor: editor, originalTab: tab)
            pane.showNativeContent(editor.view)
        } catch { pane.showNativeContent(NoteLoadErrorView(error: error)) }
    }

    private func configureNoteOwner(_ tab: BrowserTab, id: UUID, editor: NoteEditorViewController) {
            editor.onTitleChange = { [weak self] title in self?.store.updateNoteTitle(id: id, profileID: tab.profileID, title: title) }
            editor.onOpenURL = { [weak self, weak editor] url in
                guard let self, let editor, self.noteEditors[tab.id]?.editor === editor,
                      self.currentTabID == tab.id, self.activeProfileID == tab.profileID, !self.isClosing else { return }
                self.openInput(url.absoluteString)
            }
    }

    func createEasel(inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : canCreateNote else { return }
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: activeProfileID))
            let session = try easels.create()
            openEasel(id: session.document.id, title: session.document.title, inSplit: inSplit)
        } catch { showEaselError(error) }
    }

    func openEasel(id: UUID, title: String, inSplit: Bool = false) {
        guard inSplit ? canCreateNoteInSplit : !isPrivateBrowsing else { return }
        if inSplit { closeLibrary(restoreFocus: false) }
        performWindowCommand { _ = store.openEasel(id: id, title: title, inSplit: inSplit) }
        if inSplit { focusSelectedLocalContent() }
    }

    private func showEaselError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(title: "Couldn’t open Easels", message: error.localizedDescription), queued: true)
    }
    func createEaselFromPlusMenu() {
        guard canCreateNote else { return }
        do {
            let easels = try EaselEditorViewController.sharedStore(directory: activeEaselsDirectory)
            let session = try easels.create()
            openEasel(id: session.document.id, title: session.document.title)
        } catch { showNoteError(error) }
    }

    func captureRenderingMetrics() {
        guard !isPrivateBrowsing, ProcessInfo.processInfo.arguments.contains("--parc-diagnostics"), let browser = currentBrowser else { return }
        let origin = browser.url.flatMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host else { return nil }
            return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        }
        let directory = store.directory.appendingPathComponent("diagnostics", isDirectory: true)
        browser.captureRenderingMetrics { metrics, error in
            do {
                if let error { throw error }
                guard let metrics else { return }
                var record = metrics
                record["capturedAt"] = ISO8601DateFormatter().string(from: Date())
                record["pageOrigin"] = origin ?? "local"
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let output = directory.appendingPathComponent(UUID().uuidString + ".json")
                try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
                FileHandle.standardError.write(Data(("Parc rendering metrics: " + output.path + "\n").utf8))
            } catch {
                FileHandle.standardError.write(Data(("Parc rendering metrics failed: " + error.localizedDescription + "\n").utf8))
            }
        }
    }

    private func configureSidebarPreviews() {
        guard !isPrivateBrowsing, let window else { return }
        let previews = SidebarPreviewController(sidebar: sidebar, host: rootView, window: window)
        sidebarPreviews = previews
        previews.permitted = { [weak self] in
            guard let self, let window = self.window else { return false }
            return self.presentation.isReady && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.isPopupWindow && self.libraryView == nil && self.nativeFullscreenTabID == nil
                && self.sidebarPresentation != .hidden && !self.sidebarMotion.isAnimating && !self.isSidebarResizing
                && self.commandBar == nil && self.themePopover == nil && !self.siteControlCenterDefers && self.tabSwitcher == nil
                && self.transferringTabIDs.isEmpty && self.resolvingTransfers.isEmpty
                && self.activePeek == nil && PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        previews.source = { [weak self] target in self?.sidebarPreviewSource(target) }
        previews.onPresentationChange = { [weak self] in self?.refreshSidebarPointer() }
        previews.openSettings = { [weak self] in
            guard let self else { return }
            self.showSettings(pane: .general)
            self.settings?.showPreviewSettings()
        }
        previews.perform = { [weak self] source, row, action in self?.performSidebarPreview(source, row: row, action: action) }
        previews.requestRecent = { [weak self] domain, profileID, completion in
            guard let self, self.activeProfileID == profileID, !self.isClosing else { return nil }
            let path = self.store.independentEngineProfilePath(for: profileID)
            guard let query = PCNativeBrowserApplication.recentPages(forDomain: domain.rawValue, profilePath: path, completion: { pages in
                MainActor.assumeIsolated {
                    completion(pages.map { SidebarPreviewRow(id: $0.url.absoluteString, tabID: nil,
                        title: $0.title, url: $0.url, visitedAt: $0.visitedAt) })
                }
            }) else { return nil }
            return { query.invalidate() }
        }
        previews.requestPicture = { [weak self] id, deliver in
            guard let self, let window = self.window, let page = self.browsers[id]?.nativePage, !page.isClosed,
                  let lease = page.observePreview(in: window, handler: deliver) else { return nil }
            return { lease.invalidate() }
        }
        previews.favicon = { [weak self] url, profileID, completion in
            guard let self, self.activeProfileID == profileID, !self.isClosing else { return }
            PCNativeBrowserApplication.favicon(for: url, profilePath: self.store.independentEngineProfilePath(for: profileID)) { image in
                MainActor.assumeIsolated { completion(image) }
            }
        }
        sidebar.onPreview = { [weak previews] target in previews?.showFromKeyboard(target) }
        sidebar.onPreviewPreferencesChanged = { [weak self] in
            guard let self else { return }
            self.sidebarPreviews?.dismiss(); self.render(self.store.state)
        }
    }

    private func sidebarPreviewSource(_ target: SidebarPreviewTarget) -> SidebarPreviewSource? {
        guard !isClosing, presentation.isReady, !wholeWindowClose else { return nil }
        let profileID = activeProfileID
        switch target {
        case .tab(let id):
            guard let tab = visibleTabs.first(where: { $0.id == id }), tab.profileID == profileID,
                  !store.retiringTabIDs.contains(id), !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
                  ownership.canUse(id, owner: presentationID), let url = URL(string: tab.url) else { return nil }
            if SidebarPreviewPreference.recentPages.isEnabled, let domain = SidebarRecentDomain.matching(url) {
                return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                    selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: domain.title, domain: domain, originalURL: url, rows: [])
            }
            guard SidebarPreviewPreference.tabPictures.isEnabled, !selectedTabIDs.contains(id),
                  let page = browsers[id]?.nativePage, !page.isClosed,
                  let presented = URL(string: WhatsNewPage.presented(tab.url)) else { return nil }
            let title = SidebarPreviewRow.folderTitle(custom: tab.customTitle, url: presented, title: tab.title)
            return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: title,
                domain: nil, originalURL: presented,
                rows: [SidebarPreviewRow(id: id.uuidString, tabID: id, title: title, url: url, visitedAt: nil)])
        case .folder(let id):
            guard SidebarPreviewPreference.folders.isEnabled,
                  let folder = store.state.folders.first(where: { $0.id == id && $0.spaceID == activeSpaceID }) else { return nil }
            let orderedIDs = SidebarHierarchy.tabIDs(in: .folder(id), state: store.state, spaceID: activeSpaceID)
            let rows = orderedIDs.compactMap { tabID -> SidebarPreviewRow? in
                guard let tab = store.state.tabs.first(where: { $0.id == tabID }) else { return nil }
                guard tab.archivedAt == nil, tab.spaceID == activeSpaceID, tab.profileID == profileID,
                      tab.kind != .favorite, !store.retiringTabIDs.contains(tab.id), !closingTabIDs.contains(tab.id),
                      !transferringTabIDs.contains(tab.id),
                      let url = URL(string: WhatsNewPage.presented(tab.url)) else { return nil }
                return SidebarPreviewRow(id: tab.id.uuidString, tabID: tab.id,
                    title: SidebarPreviewRow.folderTitle(custom: tab.customTitle, url: url, title: tab.title),
                    url: url, visitedAt: tab.lastAccessed)
            }
            return SidebarPreviewSource(target: target, profileID: profileID, spaceID: activeSpaceID,
                selectedTabIDs: selectedTabIDs, focusedTabID: focusedTabID, theme: activeSpace.theme, title: folder.name,
                domain: nil, originalURL: nil, rows: SidebarPreviewRow.newestFirst(rows))
        }
    }

    private func performSidebarPreview(_ source: SidebarPreviewSource, row: SidebarPreviewRow, action: SidebarPreviewAction) {
        guard activeProfileID == source.profileID, activeSpaceID == source.spaceID,
              sidebarPreviewSource(source.target) == source, !isClosing, !wholeWindowClose else { return }
        if let id = row.tabID {
            guard source.rows.contains(row), let tab = visibleTabs.first(where: { $0.id == id }),
                  tab.profileID == source.profileID, tab.url == row.url.absoluteString,
                  !store.retiringTabIDs.contains(id) else { return }
            switch action {
            case .activate(let modifiers):
                switch SidebarPreviewActivation.folderItem(modifiers) {
                case .selectOriginal(let split):
                    revealPreviewTab(id)
                    if !split || !insertPreviewSplit(tabID: id) { selectTab(id) }
                case .duplicate:
                    guard !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).contains(where: { $0.tabIDs.contains(id) }) else { return }
                    _ = prepareSidebarDuplicate([.tab(id)])?()
                case .reveal:
                    if revealPreviewTab(id) { render(store.state) }
                case .excludedMiniWindow, .navigateSource, .openNewTab: break
                }
            case .split: selectTab(id, extendingSplit: true)
            case .archive:
                closeTabsWithReopen(Set([id]), reason: .manual)
            case .duplicate:
                guard !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).contains(where: { $0.tabIDs.contains(id) }) else { return }
                _ = prepareSidebarDuplicate([.tab(id)])?()
            case .copyURL, .copyIssueID, .create: break
            }
        } else {
            guard let domain = source.domain, case .tab(let sourceID) = source.target,
                  let sourceTab = visibleTabs.first(where: { $0.id == sourceID }),
                  let activation = action.activation(for: row) else { return }
            switch action {
            case .create: guard row.url == domain.createURL else { return }
            case .activate: guard SidebarRecentDomain.matching(row.url) == domain else { return }
            case .split, .duplicate, .archive, .copyURL, .copyIssueID: return
            }
            openRecentPreviewURL(row.url, from: sourceTab, activation: activation)
        }
    }

    private func openRecentPreviewURL(_ url: URL, from sourceTab: BrowserTab, activation: SidebarPreviewActivation) {
        func openNewTab(split: Bool) {
            let creation = TabCreationProvenance(referrerID: sourceTab.id, activeTabID: currentTabID,
                                                 profileID: activeProfileID, state: store.state)
            if split, insertPreviewSplit(url: url, creation: creation) { return }
            performWindowCommand {
                let id = store.openResolvedURL(url, creation: creation)
                presentation.recordCreation(id, state: store.state)
            }
        }
        switch activation {
        case .openNewTab(let split): openNewTab(split: split)
        case .navigateSource(let split):
            let page = browsers[sourceTab.id]?.nativePage
            let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(sourceTab.id) }
            let route = SidebarPreviewSourceRoute.route(to: url, isSavedItem: sourceTab.kind == .pinned || sourceTab.kind == .favorite,
                inSplit: group != nil, currentHost: page?.url?.host ?? URL(string: sourceTab.url)?.host,
                savedHost: URL(string: sourceTab.savedURL)?.host, authenticationUnlocked: page?.authenticationFlowUnlocked == true)
            guard route == .inPlace else { openNewTab(split: split); return }
            guard canPerformSidebarTabAction(sourceTab, closing: false),
                  let elsewhere = PageReparenting.pagesToMove(group?.tabIDs ?? [sourceTab.id],
                      usableHere: switcherCanUse, movable: canMovePageHere) else { return }
            if !elsewhere.isEmpty {
                _ = movePagesHere(elsewhere[...]) { [weak self] in
                    self?.openRecentPreviewURL(url, from: sourceTab, activation: activation); return self != nil
                }
                return
            }
            requestedURLs.removeValue(forKey: sourceTab.id)
            performWindowCommand(selectNativePage: false) { store.updateTab(sourceTab.id, url: url.absoluteString) }
            selectTab(sourceTab.id)
        case .selectOriginal, .duplicate, .reveal, .excludedMiniWindow: break
        }
    }

    @discardableResult
    private func revealPreviewTab(_ id: UUID) -> Bool {
        guard !store.isEphemeral, window != nil else { return false }
        let item = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(id) }
            .map { SidebarItemReference.split($0.id) } ?? .tab(id)
        guard let reveal = SidebarItemReveal(item: item, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) else { return false }
        do { return try store.revealSidebarItem(reveal) }
        catch { showError(error); return false }
    }

    private func insertPreviewSplit(tabID existing: UUID? = nil, url: URL? = nil, creation: TabCreationProvenance? = nil,
                                    after anchor: UUID? = nil) -> Bool {
        let selection = selectedTabIDs, id = existing ?? UUID()
        guard splitCommandsAvailable, splitInsertion == nil, !isPopupWindow,
              nativeFullscreenTabID == nil, let focus = anchor ?? currentTabID, selection.allSatisfy({ switcherCanUse($0) }),
              selection.contains(id) || selection.count < 4, existing != nil || url != nil else { return false }
        if let existing {
            guard switcherCanUse(existing), transferRecoveries[existing] == nil,
                  visibleTabs.contains(where: { $0.id == existing }) else { return false }
        }
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            inserted = store.insertCommandBarSplit(after: focus, expectedSelection: selection, tabID: id,
                newURL: existing == nil ? url : nil, creation: creation)
            if inserted && existing == nil { presentation.recordCreation(id, state: store.state) }
        }
        guard inserted, selectedTabIDs.contains(id) else { return false }
        focusedTabID = id
        render(store.state); requestNativeSelection(); focusSelectedLocalContent()
        return true
    }

    private func joinOriginalSplitPage(_ id: UUID, page: PCNativePage, source: PCNativePage,
                                       browser: PCNativeBrowserWindow, lease: SplitLinkLease) -> Bool {
        guard switcherCanUse(id), browsers[id]?.nativePage === page,
              nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: source) else { return false }
        let selection = lease.snapshot.selection, focused = lease.snapshot.focusedID
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            guard let homes = store.commandBarSplitHomes(after: focused, expectedSelection: selection,
                    tabID: id, isNew: false), let plan = splitHomePlan(homes),
                  page.splitLinkLease as? SplitLinkLease === lease, page.creationSourcePage === source,
                  browsers[id]?.nativePage === page,
                  nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: source) else { return }
            inserted = store.insertCommandBarSplit(after: focused, expectedSelection: selection, tabID: id,
                savedHomeIDs: plan.ids, documents: plan.documents)
        }
        guard inserted, selectedTabIDs.contains(id) else { return false }
        focusedTabID = id
        render(store.state); requestNativeSelection(); focusSelectedLocalContent()
        return true
    }

    private func wireSidebar() {
        sidebar.onAddress = { [weak self] in
            guard let self else { return }; self.focusAddress(anchor: self.sidebar.addressEditorAnchor)
        }
        sidebar.onNewTab = { [weak self] in self?.newTab() }
        sidebar.onNavigation = { [weak self] kind in self?.prepareNavigationInteraction(kind) }
        sidebar.onReloadOptions = { [weak self] anchor in self?.showReloadOptions(from: anchor) }
        sidebar.onSettings = { [weak self] in self?.showSettings() }
        sidebar.onBannerRelinquishFocus = { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(nil)
            guard !self.isClosing, !self.wholeWindowClose, window.isKeyWindow,
                  window.attachedSheet == nil, self.commandBar == nil,
                  self.libraryView == nil else { return }
            if self.currentTabID == nil { self.sidebar.focusIfPresented() }
            else { self.focusSelectedContent() }
        }
        sidebar.onLibrary = { [weak self] page in self?.showLibraryFromEntry(page) }
        sidebar.onLibraryItem = { [weak self] action in self?.performLibraryFlyout(action) ?? false }
        sidebar.libraryDownloadFileURL = { [weak self] item in self?.libraryDownloadFileURL(item) }
        sidebar.onLibraryHover = { LibraryFolderPrompts.shared.ask() }
        sidebar.onToggle = { [weak self] in self?.toggleSidebar() }
        sidebar.onNewSpace = { [weak self] in self?.createSpace() }
        sidebar.prepareSidebarNewSpace = { [weak self] items in self?.prepareSidebarNewSpace(items) }
        sidebar.prepareTurnFolderIntoSpace = { [weak self] id in self?.prepareTurnFolderIntoSpace(id) }
        sidebar.onEditTheme = { [weak self] in self?.editTheme() }
        sidebar.onNewFolder = { [weak self] in self?.createFolder() }
        sidebar.onNewEasel = { [weak self] in self?.createEaselFromPlusMenu() }
        sidebar.onNewNote = { [weak self] in self?.createNote() }
        sidebar.onNewSplit = { [weak self] in self?.toggleSplit() }
        sidebar.plusMenuCanCreateEasel = { [weak self] in self?.canCreateNote ?? false }
        sidebar.plusMenuCanCreateNote = { [weak self] in self?.canCreateNote ?? false }
        sidebar.plusMenuCanSplit = { [weak self] in
            guard let self, !self.isPopupWindow, self.splitInsertion == nil else { return false }
            return self.splitCommandIsAvailable(.add(.addAfter))
        }
        sidebar.onSelectTab = { [weak self] id in self?.selectTab(id) }
        sidebar.onCloseTab = { [weak self] id in _ = self?.closeTab(id) }
        sidebar.prepareResetTab = { [weak self] tab in self?.prepareSavedTabReset(tab) }
        sidebar.prepareIconReset = { [weak self] tab, separating in self?.prepareSavedTabIconReset(tab, separating: separating) }
        sidebar.requestTabFavicon = { [weak self] tab, completion in self?.requestSidebarFavicon(tab, completion: completion) }
        sidebar.requestSavedFavicon = { [weak self] tab, completion in self?.requestSidebarSavedFavicon(tab, completion: completion) }
        sidebar.prepareTabMute = { [weak self] tab, audio in self?.prepareSidebarTabMute(tab, audio: audio) }
        sidebar.prepareTabActivation = { [weak self] tab in self?.prepareSidebarTabAction(tab, closing: false) }
        sidebar.prepareTabClose = { [weak self] tab in self?.prepareSidebarTabAction(tab, closing: true) }
        sidebar.prepareTabRename = { [weak self] tab in self?.prepareSidebarTitleEdit(tab) }
        sidebar.prepareSplitRename = { [weak self] target in self?.prepareSidebarSplitTitleEdit(target) }
        sidebar.revealForEditing = { [weak self] in self?.revealSidebarForEditing() }
        sidebar.prepareFavoriteSplitRename = { [weak self] in self?.prepareFavoriteSplitRename($0) }
        sidebar.prepareSplitAppearance = { [weak self] in self?.prepareSplitAppearance($0, reset: $1) }
        sidebar.onTitleEditFinished = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isClosing else { return }
                self.render(self.store.state)
                self.refreshSidebarPointer()
            }
        }
        sidebar.onOutlineInvalidated = { [weak self] in
            guard let self, !self.isClosing else { return }
            self.render(self.store.state)
            self.refreshSidebarPointer()
        }
        sidebar.prepareFavoriteRename = { [weak self] tab in self?.prepareFavoriteRename(tab) }
        sidebar.prepareFavoritePointerAction = { [weak self] tab, intent in
            self?.prepareFavoritePointerAction(tab, intent: intent)
        }
        sidebar.prepareFavoriteActivation = { [weak self] tab in self?.prepareFavoriteActivation(tab) }
        sidebar.prepareFavoriteClose = { [weak self] tab in self?.prepareFavoriteAction(tab, closing: true) }
        sidebar.dismissFavoritesEmptyState = { [weak self] profileID in self?.store.dismissFavoritesEmptyState(profileID: profileID) }
        sidebar.toggleSpaceHeaderOnSingleUnnamedSpaces = { [weak self] in self?.store.toggleSpaceHeaderOnSingleUnnamedSpaces() }
        sidebar.onArchiveTabs = { [weak self] anchor, order, ids in
            self?.archiveTodayTabs(anchor: anchor, order: order, ids: ids)
        }
        sidebar.prepareSeparateSplitTab = { [weak self] id in self?.prepareSeparateSplitTab(id) }
        sidebar.prepareWindowDrop = { [weak self] session, location, before in
            self?.prepareSidebarWindowDrop(session, to: location, before: before)
        }
        sidebar.prepareCopyDrop = { [weak self] session, items, location, before in
            self?.prepareSidebarCopyDrop(session, items: items, to: location, before: before)
        }
        sidebar.prepareDockDrop = { [weak self] session, items, location, before in
            self?.prepareSidebarDockDrop(session, items: items, to: location, before: before)
        }
        sidebar.onBeginSplitDrag = { [weak self] id in self?.beginSidebarSplitDrag(id) }
        sidebar.onSplitTab = { [weak self] id in self?.selectTab(id, extendingSplit: true) }
        sidebar.prepareSidebarSpaceMove = { [weak self] items, space in self?.prepareSidebarSpaceMove(items, to: space) }
        sidebar.prepareSidebarMove = { [weak self] item in self?.prepareSidebarMove(item) }
        sidebar.prepareSidebarMoves = { [weak self] items in self?.prepareSidebarMoves(items) }
        sidebar.canSelectItems = { [weak self] in
            guard let self else { return false }
            return self.spaceCommandsAvailable && self.commandBar == nil && self.libraryView == nil
        }
        sidebar.prepareSidebarCopy = { [weak self] items, format in
            guard let self, let lease = self.prepareSidebarMoves(items),
                  let links = FolderLinks.links(in: self.store.state, items: items,
                    spaceID: self.activeSpaceID, profileID: self.activeProfileID), !links.isEmpty else { return nil }
            let spaceID = self.activeSpaceID, profileID = self.activeProfileID
            return { [weak self] in
                guard let self, lease.isValid,
                      let current = FolderLinks.links(in: self.store.state, items: items, spaceID: spaceID, profileID: profileID),
                      let text = FolderLinks.text(for: current, format: format) else { return false }
                self.copyLinkOperation = UUID()
                NSPasteboard.general.clearContents()
                let copied = NSPasteboard.general.setString(text, forType: .string)
                if copied { self.showToast(.copiedItemLinks(current.compactMap { URL(string: $0.url) })) }
                return copied
            }
        }
        sidebar.prepareSidebarClose = { [weak self] items in
            guard let self, let current = self.sidebar.itemSelectionValidator(items),
                  let target = SidebarKeyboardCloseTarget(items: items, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, state: self.store.state) else { return nil }
            return self.prepareSidebarRootsClose(items, archive: target.archivesItems,
                requiresConfirmation: target.requiresConfirmation, isSelectionCommand: true, selectionIsCurrent: current)
        }
        sidebar.prepareSplitClose = { [weak self] id in
            guard let self, let action = self.splitCellCloseAction(id) else { return nil }
            return self.prepareSidebarRootsClose([.split(id)], archive: action == .close, requiresConfirmation: false,
                                                 isSelectionCommand: false, selectionIsCurrent: { true })
        }
        sidebar.canCloseSplit = { [weak self] id in self?.splitCellCloseAvailable(id) ?? false }
        sidebar.prepareSplitCellCommand = { [weak self] id, command in self?.prepareSplitCellCommand(id, command) }
        sidebar.prepareSplitCellClose = { [weak self] id, archive in
            self?.prepareSidebarRootsClose([.split(id)], archive: archive, requiresConfirmation: false,
                                           isSelectionCommand: false, selectionIsCurrent: { true })
        }
        sidebar.hasPresentedContent = { [weak self] id in self?.hasPresentedContent(id) ?? false }

        sidebar.canSelectSpace = { [weak self] id, profile in self?.canSelectSpace(id, profileID: profile) ?? false }
        sidebar.onSelectSpace = { [weak self] id, profile in _ = self?.selectSpaceFromUser(id, profileID: profile) }
        sidebar.onPagingTheme = { [weak self] transition in
            self?.rootView.pagingTransition = transition; self?.sidebarContainer.pagingTransition = transition
            self?.loadedStartPage?.pagingTransition = transition
        }
        sidebar.onToggleFolder = { [weak self] id in self?.store.toggleFolder(id) }
        sidebar.onCopyFolderLinks = { [weak self] target, format in
            self?.copyFolderLinks(target, format: format)
        }
        sidebar.onRenameFolder = { [weak self] id in self?.renameFolder(id) }
        sidebar.prepareFolderRename = { [weak self] folder in self?.prepareFolderInlineRename(folder) }
        sidebar.prepareFolderFromSelection = { [weak self] items in self?.prepareFolderFromItems(items) }
        sidebar.prepareFolderIcon = { [weak self] folder in self?.prepareFolderIconChange(folder) }
        sidebar.prepareSidebarDeletion = { [weak self] items in
            guard let self, let current = self.sidebar.itemSelectionValidator(items) else { return nil }
            return self.prepareSidebarDeletion(items, isSelectionCommand: true, selectionIsCurrent: current)
        }
        sidebar.prepareFolderDeletion = { [weak self] id in self?.prepareFolderDeletion(id) }
        sidebar.prepareFolderDuplicate = { [weak self] id in self?.prepareFolderDuplicate(id) }
        sidebar.prepareSidebarDuplicate = { [weak self] items in self?.prepareSidebarDuplicate(items) }
        sidebar.onNewSubfolder = { [weak self] id in self?.createFolder(parentID: id) }
        sidebar.onRenameSpace = { [weak self] id in self?.renameSpace(id) }
        sidebar.makeSpaceManagementMenu = { [weak self] id in self?.spaceManagementMenu(id) }
        sidebar.onChangeSpaceIcon = { [weak self] id in self?.changeSpaceIcon(id) }
        sidebar.onClearToday = { [weak self] in self?.clearToday() }
        sidebar.onPageMenu = { [weak self] in self?.showSiteControlCenter() }
        sidebar.onFolderPeeksChange = { [weak self] peeks in
            guard let self, !self.isPopupWindow else { return }
            self.savedFolderPeeks = peeks
            self.onSessionRecordChange?()
        }
        sidebar.onPageActionsMenu = { [weak self] in self?.showPageMenu() }
        sidebar.onPaymentMenu = { [weak self] anchor in self?.showPaymentControls(anchor: anchor) }
    }

    private func render(_ sharedState: BrowserState) {
        reconcileSpaceCreation()
        favoriteRename?.reconcile(); favoriteSplitRename?.reconcile(); splitIconPicker?.reconcile(); spaceIconPicker?.reconcile()
        pageHost.validateDrop()
        if splitDropView?.drag.isValid == false { splitDropView?.drag.end() }
        if splitInsertion?.isValid == false { cancelSplitInsertion(restoreFocus: false) }
        if pendingCommandSplitValidation?() == false { cancelPendingCommandSplit() }
        tabSwitcher?.dismissIfInvalid()
        defer { reconcileFind(); pageCapture?.reconcile(); easelImageDestination?.dismissIfInvalid(); sidebarPreviews?.reconcile(); reconcileCommandBar(); checkPanePresentation() }
        guard canRender else { return }
        let presentedRevision = store.stateRevision
        let previousSession = sessionRecord
        presentation.reconcile(sharedState) { ownership.canUse($0, owner: presentationID) }
        if sessionRecord != previousSession { onSessionRecordChange?() }
        if let libraryView, libraryView.profileID != activeProfileID { closeLibrary(restoreFocus: false) }
        let state = presentation.projected(sharedState)
        rendering = true
        defer { rendering = false }
        let liveIDs = Set(state.tabs.filter { $0.archivedAt == nil }.map(\.id))
        for id in Array(browsers.keys) where !liveIDs.contains(id)
            || state.tabs.first(where: { $0.id == id })?.profileID != browserProfiles[id]
            || state.tabs.first(where: { $0.id == id }).map({ InternalPage.isInternal($0.url) }) == true {
            retireBrowserAfterModelChange(id)
        }
        for id in Array(noteEditors.keys) {
            guard let cached = noteEditors[id] else { continue }
            let tab = state.tabs.first { $0.id == id && $0.archivedAt == nil }
            if tab?.profileID != cached.profileID || tab.flatMap({ InternalPage(urlString: $0.url)?.noteID }) != cached.documentID {
                guard cached.editor.prepareToClose() else {
                    _ = store.restoreLiveTab(cached.originalTab, replacing: store.state.tabs.first { $0.id == id })
                    continue
                }
                cached.editor.view.removeFromSuperview(); noteEditors.removeValue(forKey: id)
            } else if let tab {
                noteEditors[id] = NotePane(documentID: cached.documentID, profileID: cached.profileID,
                    editor: cached.editor, originalTab: tab)
            }
        }
        for id in Array(easelEditors.keys) {
            guard let cached = easelEditors[id] else { continue }
            let tab = state.tabs.first { $0.id == id && $0.archivedAt == nil }
            if tab?.profileID != cached.profileID || tab.flatMap({ InternalPage(urlString: $0.url)?.easelID }) != cached.documentID {
                if !embeddedEaselPages(forTabID: id).isEmpty {
                    retireEaselAfterModelChange(id, cached: cached); continue
                }
                cached.editor.retirePageOwner()
                panes[id]?.clearNativeContent()
                easelEditors.removeValue(forKey: id)
            }
        }
        for id in Array(panes.keys) where !liveIDs.contains(id) && browsers[id] == nil && easelEditors[id] == nil && noteEditors[id] == nil {
            ownership.release(id, owner: presentationID)
            panes[id]?.removeFromSuperview(); panes.removeValue(forKey: id)
            failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
            if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
        }
        let placeholderIDs = presentation.displayedPlaceholders
        syncPlaceholderImageHolders()
        for (id, pane) in Array(panes) where pane.showsPlaceholder && !presentation.showsPlaceholder(id)
            && browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil {
            pane.removeFromSuperview(); panes.removeValue(forKey: id)
            if renderedPaneIDs.contains(id) { renderedPaneIDs = [] }
        }
        let selected = presentation.displayedTabIDs.compactMap { id in state.tabs.first { $0.id == id && $0.archivedAt == nil } }
        let displayed = nativeFullscreenTabID.map { id in selected.filter { $0.id == id } } ?? selected
        let displayedIDs = displayed.map(\.id)
        shownSinceArrival.formIntersection(returnableIDs)
        shownSinceArrival.formUnion(displayedIDs.filter { !placeholderIDs.contains($0) })
        heldReturns.formIntersection(returnableIDs); heldReturns.subtract(displayedIDs)
        failedReturns.formIntersection(returnableIDs); failedReturns.subtract(displayedIDs)
        if renderedPaneIDs != displayedIDs || splitView.arrangedSubviews.isEmpty
            || renderedSpaceCreationID != spaceCreation?.draft.spaceID
            || renderedSplitInsertionID != splitInsertion?.id {
            updateSplitArrangement(displayed: displayed, displayedIDs: displayedIDs)
        } else {
            for (id, pane) in panes {
                pane.contentResize.mode = displayedIDs.contains(id) ? contentResizeReasons.mode : .intrinsic
            }
        }
        let layout = placeholderIDs.isEmpty ? activeSplitLayout : presentation.displayedSplitLayout
        splitMarginHandle.windowAllows = displayed.count == 1 && layout == nil
            && splitInsertion == nil && spaceCreation == nil && !isPopupWindow
        splitView.configure(orientation: splitInsertion?.request.orientation ?? layout?.orientation ?? .horizontal,
                            factors: splitInsertion?.request.previewFactors ?? layout?.widthFactors ?? [1])
        for tab in selected {
            if placeholderIDs.contains(tab.id) {
                panes[tab.id]?.showPlaceholder(store.placeholderImages.image(for: tab.id, in: presentationID), title: tab.title) { [weak self] in
                    self?.pullBackPlaceholder(tab.id)
                }
                continue
            }
            if closingTabIDs.contains(tab.id), easelEditors[tab.id] != nil { continue }
            guard ownership.claim(tab.id, owner: presentationID), let pane = panes[tab.id] else { continue }
            if InternalPage.isInternal(tab.url) {
                showInternalPage(tab, in: pane)
            } else if rendersBlank(tab) {
                pane.showBlank()
            } else {
                var restoredHistory: NSObject?
                if browsers[tab.id] == nil {
                    guard !applyingNativeSelection, !store.retiringTabIDs.contains(tab.id) else { continue }
                    restoredHistory = store.closedPageHistory.takeRestored(tab.id) as? NSObject ?? launchHistory(for: tab)
                    pane.layoutSubtreeIfNeeded()
                    let enginePath = store.independentEngineProfilePath(for: tab.profileID)
                    let browser = PCBrowserView(frame: pane.contentBounds, profilePath: enginePath)
                    browser.delegate = self
                    browsers[tab.id] = browser
                    browserProfiles[tab.id] = tab.profileID
                    liveTabModels[tab.id] = tab
                    pane.browser = browser
                }
                refreshPagePresentation(tab.id)
                if !applyingNativeSelection, !closingTabIDs.contains(tab.id), requestedURLs[tab.id] != tab.url, let url = URL(string: tab.url) {
                    failures.removeValue(forKey: tab.id)
                    refreshPagePresentation(tab.id)
                    requestedURLs[tab.id] = tab.url
                    if let navigation = pendingSearchNavigations.removeValue(forKey: tab.id), BrowserInternalURL.publicString(navigation.url.absoluteString) == BrowserInternalURL.publicString(url.absoluteString) {
                        browsers[tab.id]?.loadSearchNavigation(navigation)
                    } else if let history = restoredHistory, browsers[tab.id]?.restoreNavigationState(history, url: url) == true {
                    } else {
                        browsers[tab.id]?.loadURL(url)
                    }
                }
            }
        }
        for (id, browser) in browsers where !closingTabIDs.contains(id) {
            if let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
               tab.profileID == browserProfiles[id], !InternalPage.isInternal(tab.url) {
                liveTabModels[id] = tab
                if browser.nativePage?.isClosed == true { releaseClosedTab(id, updateSavedTab: false) }
            }
        }
        refreshPageHostBacking()
        if let context = themeEditingContextSpaceID, context != activeSpaceID { themePopover?.performClose(nil) }
        synchronizeThemeEditor()
        let preview = themePreview.flatMap { $0.spaceID == activeSpaceID ? $0.theme : nil }
        applyChromeTheme(spaceCreation?.draft.theme ?? preview ?? activeSpace.theme)
        layoutChrome()
        attachOwnedPages()
        updateNavigation()
        lastChromeState = sharedState
        lastChromeRevision = presentedRevision
        noteReturnGate()
        refreshStartPage()
        refreshPendingPaneSidebar()
        scheduleUntargetedReturns()
    }

    private var canRender: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && !rendering && !promotingPeek
            && transferringTabIDs.isEmpty && collectionTransfer == nil
    }
    private func rendersBlank(_ tab: BrowserTab) -> Bool {
        (tab.url == "about:blank" || tab.url.isEmpty) && browsers[tab.id]?.nativePage == nil
            && pendingSearchNavigations[tab.id] == nil
    }

    private var panePresentationRetries = 0
    private var panePresentationRetryPending = false
    private func checkPanePresentation() {
        guard canRender else { return }
        guard panesMissingTheirPage() else {
            panePresentationRetries = 0
            return
        }
        guard !panePresentationRetryPending, panePresentationRetries < 4 else { return }
        panePresentationRetries += 1
        panePresentationRetryPending = true
        let delay = 0.05 * Double(1 << (panePresentationRetries - 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.panePresentationRetryPending = false
            guard self.canRender else { self.panePresentationRetries -= 1; return }
            if self.panesMissingTheirPage() { self.render(self.store.state) } else { self.panePresentationRetries = 0 }
        }
    }
    private func panesMissingTheirPage() -> Bool {
        let placeholderIDs = presentation.displayedPlaceholders
        for id in presentation.displayedTabIDs {
            guard let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
                  !placeholderIDs.contains(id), !(closingTabIDs.contains(id) && easelEditors[id] != nil),
                  ownership.canUse(id, owner: presentationID), let pane = panes[id],
                  !InternalPage.isInternal(tab.url), !rendersBlank(tab) else { continue }
            guard let browser = browsers[id] else {
                if !applyingNativeSelection && !store.retiringTabIDs.contains(id) { return true }
                continue
            }
            if pane.browser === browser, pane.showsLocalContent || (!pane.showsFailure && browser.isHidden) {
                return true
            }
        }
        return false
    }

    private var pendingPaneHoldsSidebar: Bool {
        PendingSplitPaneSidebarRule.holdsSidebar(pendingSplitPane: splitInsertion != nil, creatingSpace: spaceCreation != nil,
                                                 popup: isPopupWindow, library: libraryView != nil)
    }
    private var sidebarHeldByPendingPane = false
    private func refreshPendingPaneSidebar() {
        let holds = pendingPaneHoldsSidebar
        defer { sidebarHeldByPendingPane = holds }
        switch PendingSplitPaneSidebarRule.refresh(sidebarPresentation, pendingPane: holds, heldBefore: sidebarHeldByPendingPane) {
        case .keep: break
        case .float: setSidebarPresentation(.floating)
        case .applyHover: refreshSidebarPointer()
        }
    }

    private func applyPublishedState(_ sharedState: BrowserState) {
        if rendering { return }
        if favoriteRename == nil, favoriteSplitRename == nil, splitIconPicker == nil, spaceIconPicker == nil,
           spaceCreation == nil, splitInsertion == nil,
           presentation.isReady, !isClosing, !wholeWindowClose, !promotingPeek,
           transferringTabIDs.isEmpty, collectionTransfer == nil,
           let previous = lastChromeState, sharedState.preservesChromeLayout(relativeTo: previous),
           !needsNativeLoad(sharedState) {
            if store.stateRevision == lastChromeRevision { return }
            applyLivePageMetadata(sharedState)
            return
        }
        render(sharedState)
    }

    private func needsNativeLoad(_ sharedState: BrowserState) -> Bool {
        let state = presentation.projected(sharedState)
        return state.tabs.contains { tab in
            tab.archivedAt == nil && !InternalPage.isInternal(tab.url)
                && browsers[tab.id] != nil && !closingTabIDs.contains(tab.id)
                && !applyingNativeSelection && !store.retiringTabIDs.contains(tab.id)
                && requestedURLs[tab.id] != tab.url && URL(string: tab.url) != nil
        }
    }

    private func applyLivePageMetadata(_ sharedState: BrowserState) {
        let presentedRevision = store.stateRevision
        let state = presentation.projected(sharedState)
        for (id, browser) in browsers where !closingTabIDs.contains(id) {
            if let tab = state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
               tab.profileID == browserProfiles[id], !InternalPage.isInternal(tab.url) {
                liveTabModels[id] = tab
                if browser.nativePage?.isClosed == true { releaseClosedTab(id, updateSavedTab: false) }
            }
        }
        if !refreshLivePageChrome() { render(sharedState); return }
        lastChromeState = sharedState
        lastChromeRevision = presentedRevision
    }

    private func refreshLivePageChromeOrRender() {
        if refreshLivePageChrome() { return }
        if !rendering { render(store.state) }
    }

    @discardableResult
    private func refreshLivePageChrome() -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return true }
        refreshSidebarBanners()
        navigationHistory?.validate()
        refreshExtensionControls()
        refreshPaymentControls()
        refreshCaptureIndicators()
        refreshMiniPlayers()
        let leading = renderedPaneIDs.first
        for (id, pane) in panes where selectedTabIDs.contains(id) {
            let developerPage = pane.browser?.nativePage?.developerModeSiteHost
                .map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
            let topBar = paneTopBarDisplayed && !developerPage
            configurePaneDeveloperToolbar(pane,
                visible: selectedTabIDs.contains(id) && activePeek == nil && nativeFullscreenTabID == nil)
            if let browser = pane.livePage {
                configureBrowserToolbar(pane.browserToolbar, browser: browser, visible: topBar,
                                        failing: pane.showsFailure, themeBackground: rootView.palette.background,
                                        leading: id == leading, tabID: id)
            } else {
                configureDocumentToolbar(pane, tabID: id, visible: topBar, leading: id == leading)
            }
        }
        for peek in peeks.values {
            configureDeveloperToolbar(peek.view.developerToolbar, browser: peek.browser,
                visible: activePeek === peek)
            configureBrowserToolbar(peek.view.browserToolbar, browser: peek.browser,
                visible: PaneTopBarAdmission.peekDisplayed(
                    toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
                    isActivePeek: activePeek === peek,
                    developerToolbarHidden: peek.view.developerToolbar.isHidden),
                failing: peek.showsFailure, themeBackground: nil)
        }
        applySidebarToolbarOwnership()
        let state = presentedState
        refreshFavoriteOverlays(from: state)
        let published = publishedShareableAndAudio()
        if !sidebar.applyLivePageMetadata(state: state, focusedTabID: currentTabID, loading: loadingTabs,
            canBack: navigationPage?.canShowBackHistory ?? false,
            canForward: navigationPage?.canShowForwardHistory ?? false,
            captures: capturePresentations, shareable: published.shareable, audio: published.audio,
            applyShareableAudio: published.changed) {
            return false
        }
        if published.changed {
            rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)
        }
        refreshDownloads()
        refreshNavigationControls()
        let tab = store.state.tabs.first { $0.id == currentTabID }
        window?.title = activePeek.map { "\($0.browser.title) — Peek — Parc" } ?? tab.map { "\($0.title) — Parc" } ?? "Parc"
        refreshLoadingIndicators()
        checkPanePresentation()
        return true
    }

    private func showInternalPage(_ tab: BrowserTab, in pane: BrowserPane) {
        guard let page = InternalPage(urlString: tab.url) else {
            pane.showError("This internal address is not supported.")
            return
        }
        if case let .note(id) = page { showNote(tab, id: id, in: pane); return }
        guard let documentID = page.easelID else { return }
        if let cached = easelEditors[tab.id], cached.documentID == documentID, cached.profileID == tab.profileID {
            pane.showNativeContent(cached.editor.view)
            return
        }
        let destination = tab.profileID.uuidString + ":" + page.urlString
        if let failure = easelFailures[tab.id], failure.destination == destination { pane.showError(failure.message); return }
        do {
            let editor = try EaselEditorViewController(directory: store.easelsDirectory(for: tab.profileID), documentID: documentID)
            easelEditors[tab.id] = EaselPane(documentID: documentID, profileID: tab.profileID, editor: editor, originalTab: tab)
            easelFailures.removeValue(forKey: tab.id)
            pane.showNativeContent(editor.view)
            configureEaselOwner(tab, documentID: documentID, editor: editor)

        } catch {
            easelFailures[tab.id] = (destination, error.localizedDescription)
            pane.showError(error.localizedDescription)
        }
    }

    @discardableResult private func configureEaselOwner(_ tab: BrowserTab, documentID: UUID, editor: EaselEditorViewController,
                                                       windowTransfer: EaselBrowserObjects.WindowTransfer? = nil) -> Bool {
            editor.onTitleChange = { [weak self] title in
                self?.store.updateEaselTitle(id: documentID, profileID: tab.profileID, title: title)
            }
            editor.onKeyboardStructureChange = { [weak self, weak editor] in
                guard let self, let editor, self.easelEditors[tab.id]?.editor === editor,
                      editor.view.window === self.window, !self.isClosing else { return }
                self.windowKeyViews.relink()
            }
            editor.onOpenURL = { [weak self] url in
                guard let self, self.currentTabID == tab.id, self.activeProfileID == tab.profileID,
                      self.easelEditors[tab.id]?.documentID == documentID,
                      !self.isClosing, !self.wholeWindowClose,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
                self.openInput(url.absoluteString)
            }
            editor.exportAdmission = { [weak self, weak editor] in
                guard let self, let editor else { return false }
                return self.currentEaselEditor === editor
            }
            if let binding = nativeBinding, !isPrivateBrowsing {
                return editor.configurePages(binding: binding,
                    profilePath: store.independentEngineProfilePath(for: tab.profileID),
                    validOwner: { [weak self, weak editor, weak binding] in
                        guard let self, let editor, let binding,
                              self.easelEditors[tab.id]?.editor === editor,
                              binding === self.nativeBinding, editor.view.window === self.window,
                              let actual = self.store.state.tabs.first(where: { $0.id == tab.id && $0.archivedAt == nil }),
                              actual.profileID == tab.profileID,
                              InternalPage(urlString: actual.url)?.easelID == documentID,
                              !self.store.isProfileRemovalPending(tab.profileID),
                              !self.transferringTabIDs.contains(tab.id) else { return false }
                        return !self.isClosing && !self.wholeWindowClose && !self.windowCloseApproved
                    }, activeOwner: { [weak self] in
                        guard let self else { return false }
                        return !self.transferringTabIDs.contains(tab.id) && self.currentTabID == tab.id && self.activePeek == nil && self.libraryView == nil
                            && self.commandBar == nil && !self.windowClosePending && !self.isClosing
                    }, selectionChanged: { [weak self] in
                        guard let self, !self.isClosing else { return }
                        self.nativeBinding?.synchronizeSelectionAndLayout()
                        self.refreshCaptureIndicators(); self.refreshNavigationControls()
                        self.windowKeyViews.relink()
                    }, metadataChanged: { [weak self] in self?.refreshLivePageChromeOrRender() },
                    contextImage: { [weak self] view, image in self?.browserView(view, addContextImageToEasel: image) },
                    windowTransfer: windowTransfer)
            }
        return windowTransfer == nil
    }

    private func applyChromeTheme(_ theme: SpaceTheme) {
        rootView.theme = theme
        sidebarContainer.theme = theme
        sidebar.palette = rootView.palette
        sidebar.plusMenuTheme = rootView.paletteTheme
        commandBar?.theme = rootView.paletteTheme
        commandBar?.contentAppearance = rootView.palette.contentAppearance
        loadedStartPage?.theme = theme
        residentCommandBar?.theme = rootView.paletteTheme
    }
    private var windowPaletteTheme: SpaceTheme { rootView.incognito ? IncognitoWindowTheme.paletteTheme : activeSpace.theme }
    private var windowBasicBackground: NSColor? { rootView.incognito ? IncognitoWindowTheme.background : nil }

    private func refreshWebsiteTheme(enabled: Bool? = nil) {
        guard !isClosing else { return }
        let allowed = (enabled ?? WebsiteThemePreferences.shared.state.isEnabled)
            && !WebsiteThemePreferences.shared.loadError
        guard let binding = nativeBinding else { return }
        let stylesheet = allowed ? rootView.palette.websiteStylesheet(
            theme: rootView.theme, basicBackground: windowBasicBackground) : nil
        let identity = ObjectIdentifier(binding)
        if let last = lastPushedWebsiteTheme,
           last.binding == identity,
           last.stylesheet == stylesheet {
            return
        }
        binding.setWebsiteThemeStylesheet(stylesheet)
        lastPushedWebsiteTheme = (identity, stylesheet)
    }

    var canEditThemeFromMenu: Bool {
        guard let window else { return false }
        if let session = spaceCreation {
            return creationOwnerIsCurrent(session) && !session.committing
                && session.view.themeAnchor.window === window
        }
        guard managementSpace(activeSpaceID) != nil else { return false }
        let manager = libraryView?.kind == .spaces ? libraryView?.spaceManager : nil
        return (manager?.anchor(for: activeSpaceID) ?? sidebar.spaceAppearanceAnchor(activeSpaceID))?.window === window
    }

    func editTheme() {
        if let session = spaceCreation { chooseCreationTheme(session, from: session.view.themeAnchor); return }
        editTheme(spaceID: activeSpaceID)
    }
    private func editTheme(spaceID: UUID) {
        guard !isPrivateBrowsing, managementSpace(spaceID) != nil else { return }
        themePopover?.performClose(nil)
        guard !isClosing, let window, let original = managementSpace(spaceID) else { return }
        let profileID = original.profileID
        let manager = libraryView?.kind == .spaces ? libraryView?.spaceManager : nil
        if manager == nil { revealSidebarForEditing() }
        guard let anchor = manager?.anchor(for: spaceID) ?? sidebar.spaceAppearanceAnchor(spaceID), anchor.window === window else { return }
        let editor = makeThemeEditor(theme: original.theme)
        editor.windowThemeUndo = folderUndo
        editor.onPreview = { [weak self, weak editor] theme in
            guard let self, let editor, self.themeEditor === editor,
                  self.store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return }
            self.libraryView?.spaceManager.previewTheme(theme, spaceID: spaceID)
            guard self.activeSpaceID == spaceID, self.activeProfileID == profileID else { return }
            self.themePreview = (spaceID, theme)
            self.applyChromeTheme(theme)
        }
        editor.onSetAppearance = { [weak self, weak editor] appearance in
            guard let self, let editor, self.themeEditor === editor,
                  self.themeEditingSpaceID == spaceID,
                  self.managementSpace(spaceID, profileID: profileID) != nil, !self.isClosing, self.window?.attachedSheet == nil else { return }
            self.setThemeEditorAppearance(appearance)
        }
        editor.onCommitChange = { [weak self, weak editor] previous, theme in
            guard let self else { return previous }
            let current = self.store.state.spaces.first { $0.id == spaceID && $0.profileID == profileID }?.theme
            guard let editor, self.themeEditor === editor, current != nil,
                  !self.folderUndo.isBusy else { return current ?? previous }
            do {
                if let change = try self.store.saveSpaceTheme(spaceID: spaceID, profileID: profileID,
                                                              previous: previous, theme: theme) {
                    self.folderUndo.appendSpaceThemeChange(change, store: self.store,
                        available: { [weak self] in self?.windowUndoContextAvailable == true },
                        onApplied: { [weak self] in
                            guard let self else { return }
                            self.synchronizeThemeEditor()
                            self.applyChromeTheme(self.activeSpace.theme)
                        }, onError: { [weak self] in self?.showError($0) })
                }
            } catch {
                if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) }
            }
            return self.store.state.spaces.first { $0.id == spaceID && $0.profileID == profileID }?.theme ?? previous
        }
        let content = NSViewController(); content.view = editor
        let popover = NSPopover()
        popover.contentViewController = content
        popover.contentSize = NSSize(width: 356, height: 508)
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        editor.onDismiss = { [weak popover] in popover?.performClose(nil) }
        themeEditor = editor; themePopover = popover; themeEditingSpaceID = spaceID; themeEditingProfileID = profileID
        themeEditingContextSpaceID = activeSpaceID
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        editor.window?.makeFirstResponder(editor)
    }

    private func makeThemeEditor(theme: SpaceTheme) -> SpaceThemeEditorView {
        let editor = SpaceThemeEditorView(theme: theme, presetPage: themeEditorPresetPage)
        editor.onPresetPageChange = { [weak self] page in self?.themeEditorPresetPage = page }
        editor.onTooltipThemeChange = { [weak editor] theme in
            guard let window = editor?.window else { return }
            TooltipController.controller(for: window).palette = TooltipColorPalette(theme: theme)
        }
        return editor
    }

    private func setThemeEditorAppearance(_ appearance: AppAppearance) {
        let previous = AppAppearance.current
        guard AppAppearance.apply(appearance) else { return }
        registerAppearanceUndo(from: previous, to: appearance)
    }

    private func synchronizeThemeEditor() {
        guard let editor = themeEditor, let spaceID = themeEditingSpaceID,
              let profileID = themeEditingProfileID else { return }
        guard let space = store.state.spaces.first(where: { $0.id == spaceID && $0.profileID == profileID }),
              !store.isProfileRemovalPending(profileID) else {
            themePopover?.performClose(nil); return
        }
        if editor.synchronizeTheme(space.theme) { themePreview = nil }
    }

    func popoverWillClose(_ notification: Notification) {
        if let session = spaceCreation, notification.object as? NSPopover === session.themePopover {
            session.themeEditor?.finishEditing()
            session.themeEditor = nil; session.themePopover = nil
            if !session.committing, window?.isKeyWindow == true, window?.attachedSheet == nil {
                session.view.focusName()
            }
            return
        }
        guard notification.object as? NSPopover === themePopover else { return }
        themeEditor?.finishEditing()
        themePreview = nil; themeEditor = nil; themePopover = nil; themeEditingSpaceID = nil; themeEditingProfileID = nil; themeEditingContextSpaceID = nil
        libraryView?.spaceManager.reload(store.state)
        applyChromeTheme(activeSpace.theme)
        refreshSidebarPointerIfKey()
    }
    private func refreshSidebarPointerIfKey() {
        if window?.isKeyWindow == true { refreshSidebarPointer() }
    }
    private func reloadTab(_ id: UUID) {
        failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
        if let tab = store.state.tabs.first(where: { $0.id == id }), InternalPage.isInternal(tab.url) {
            if let cached = easelEditors[id] {
                cached.editor.refreshPageVisibility(); render(store.state); return
            }
            panes[id]?.clearNativeContent()
            render(store.state)
        } else if let browser = browsers[id] {
            refreshPagePresentation(id)
            browser.reload()
        }
    }

    private func rendererPresentation(_ browser: PCBrowserView) -> RendererCrashPresentation? {
        guard let page = browser.nativePage, !page.isClosed,
              let crash = browser.rendererCrash else { return nil }
        return RendererCrashPresentation(pageIdentifier: page.identifier, identity: crash,
            terminationStatus: crash.terminationStatus, errorCode: crash.errorCode)
    }

    private func currentRendererPresentation(_ id: UUID, _ expected: RendererCrashPresentation,
                                             selected: Bool = false) -> (PCBrowserView, PCNativeRendererCrash)? {
        guard !isClosing, !wholeWindowClose, !closingTabIDs.contains(id),
              !modelRetirementIDs.contains(id), !transferringTabIDs.contains(id),
              ownership.canUse(id, owner: presentationID),
              let browser = browsers[id], let page = browser.nativePage, !page.isClosed,
              page.identifier == expected.pageIdentifier, page.observer === browser,
              let crash = browser.rendererCrash, crash === expected.identity,
              let binding = nativeBinding, PCNativeBrowserApplication.owner(of: page) === binding,
              let window, window.isVisible, !window.isMiniaturized,
              browser.window === window, page.nativeView.window === window,
              page.nativeView.isDescendant(of: browser), attachedPageIDs.contains(page.identifier),
              let pane = panes[id], pane.window === window,
              renderedPaneIDs.contains(id), !pane.isHiddenOrHasHiddenAncestor,
              pane.rendererPresentation == expected,
              !selected || selectedNativePage() === page else { return nil }
        return (browser, crash)
    }

    private func refreshPagePresentation(_ id: UUID) {
        defer { checkPanePresentation() }
        guard !isClosing, !wholeWindowClose, !transferringTabIDs.contains(id),
              let browser = browsers[id], let pane = panes[id] else { return }
        let rendererHadFocus = browser.window?.firstResponder as? NSView
        let moveFocusToError = rendererHadFocus.map { $0 === browser || $0.isDescendant(of: browser) } ?? false
        let restorePageFocus = pane.rendererFailureOwnsFocus
        let crash = rendererPresentation(browser)
        if let crash {
            if pane.rendererPresentation != crash { failures.removeValue(forKey: id) }
            pane.showRendererFailure(crash)
        }
        else if let message = failures[id] { pane.showError(message) }
        else { pane.showBrowser() }
        synchronizeNativeLayout()
        guard browsers[id] === browser else { return }
        if let crash, moveFocusToError {
            focusRendererFailure(id, crash)
        } else if crash == nil, restorePageFocus, failures[id] == nil,
                  let page = browser.nativePage, !page.isClosed, page.rendererCrash == nil,
                  selectedNativePage() === page, let binding = nativeBinding,
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let window, browser.window === window, !browser.isHiddenOrHasHiddenAncestor {
            window.makeFirstResponder(page.nativeView)
        }
    }

    private func focusRendererFailure(_ id: UUID, _ expected: RendererCrashPresentation) {
        guard currentRendererPresentation(id, expected, selected: true) != nil else { return }
        panes[id]?.focusRendererFailure(expected)
    }

    private func refreshPageHostBacking() {
        let translucentPane = splitView.arrangedSubviews.contains {
            guard let pane = $0 as? BrowserPane else { return false }
            return pane.showsNoteCanvas || pane.showsTopBar || pane.showsPlaceholder
        }
        let showsEmpty = splitView.arrangedSubviews.count == 1
            && (splitView.arrangedSubviews.first is SplitPanePlaceholder || splitView.arrangedSubviews.first === loadedStartPage)
        let backing = (splitView.arrangedSubviews.first as? BrowserPane)?.contentBacking ?? .white
        splitView.configureBacking(in: pageHost, hasTranslucentPane: translucentPane || showsEmpty, backing: backing)
        refreshPageShadow()
        refreshSplitPaneHighlights()
    }
    private func refreshPageShadow() {
        pageShadow.isHidden = splitView.arrangedSubviews.count > 1 || nativeFullscreenTabID != nil
    }

    private func refreshNoteCanvasTheme(_ palette: ThemeChromePalette) {
        for pane in panes.values { pane.inheritNoteCanvasTheme(palette.contentAppearance) }
    }

    private func refreshSplitPaneHighlights() {
        let palette = rootView.palette
        let color = palette.isDark ? palette.shaded : palette.shadedDark
        let shown = splitView.arrangedSubviews
        let placeholder = splitInsertion?.placeholder
        let focused: NSView? = commandBar != nil && commandBarCreatesNewTab ? nil
            : placeholder.flatMap { $0.superview === splitView ? $0 : nil } ?? currentTabID.flatMap { panes[$0] }
        let proposedPane: NSView? = splitDropReplacementID.flatMap { renderedPaneIDs.contains($0) ? panes[$0] : nil }
        for view in shown {
            let highlight: SplitPaneHighlight
            if let pane = view as? BrowserPane { highlight = pane.splitHighlight }
            else if let pending = view as? SplitPanePlaceholder { highlight = pending.splitHighlight }
            else { continue }
            let state = SplitPaneHighlightState.resolve(
                isProposedDropTarget: proposedPane != nil && view === proposedPane,
                isFocused: view === focused, paneCount: shown.count, dragEditActive: splitView.isInteractivePaneEditing)
            highlight.color = color
            highlight.layout(bounds: view.bounds, cornerRadius: view.layer?.cornerRadius ?? 0)
            highlight.update(display: state.display, width: state.width)
        }
        for pane in panes.values where !shown.contains(where: { $0 === pane }) {
            pane.splitHighlight.update(display: false, width: 2)
        }
    }

    private func setSplitDropProposal(_ target: SplitDropTarget?, selection: [UUID]) {
        if case .replace(let index)? = target, selection.indices.contains(index) {
            splitDropReplacementID = selection[index]
        } else { splitDropReplacementID = nil }
        refreshSplitPaneHighlights()
    }
    private func splitPaneEditDidChange(_ active: Bool) {
        if !active { splitDropReplacementID = nil }
        refreshSplitPaneHighlights()
    }
    private func updateSplitArrangement(displayed: [BrowserTab], displayedIDs: [UUID]) {
        var wanted: [NSView] = displayed.map { tab in
            let pane = panes[tab.id] ?? makePane(tab)
            panes[tab.id] = pane
            return pane
        }
        if let draft = splitInsertion, draft.isValid {
            let index = min(max(0, draft.request.index), wanted.count)
            wanted.insert(draft.placeholder, at: index)
        }
        if wanted.isEmpty {
            if spaceCreation != nil {
                wanted = [LayoutView()]
            } else {
                wanted = [startPage]
            }
        }
        let previous = splitView.arrangedSubviews
        let leaving = splitView.reconcileArrangedSubviews(wanted)
        for view in leaving where !(view is BrowserPane) {
            if view === loadedStartPage { playStartPageDeparture() } else { view.removeFromSuperview() }
        }
        let arriving = wanted.filter { view in !previous.contains { $0 === view } }.compactMap { $0 as? BrowserPane }
        let drawing = displayed.compactMap { tab in drawsReportedFrame(tab) ? panes[tab.id] : nil }
        let leavingPanes = leaving.compactMap { $0 as? BrowserPane }
        let hold = switchHold.hold
        let parking = switchHold.rearrange(leaving: leavingPanes, arriving: arriving, drawing: drawing,
                                           canHold: canHoldPageSwitch, now: ProcessInfo.processInfo.systemUptime)
        for case let pane as BrowserPane in wanted { pane.heldOverSwitch = false }
        retirePages(leavingPanes)
        for pane in switchHold.held { pane.heldOverSwitch = true }
        parkPanes(parking)
        if switchHold.isHolding {
            if let binding = nativeBinding {
                for pane in switchHold.waiting {
                    if let page = pane.browser?.nativePage { binding.reportNextFrame(of: page) }
                }
            }
            if switchHold.hold != hold { scheduleSwitchHoldCap() }
        }
        for (id, pane) in panes {
            pane.contentResize.mode = displayedIDs.contains(id) ? contentResizeReasons.mode : .intrinsic
        }
        renderedPaneIDs = displayedIDs
        renderedSplitInsertionID = splitInsertion?.id
        renderedSpaceCreationID = spaceCreation?.draft.spaceID
    }
    private func makePane(_ tab: BrowserTab) -> BrowserPane {
        let pane = BrowserPane()
        pane.inheritNoteCanvasTheme(rootView.palette.contentAppearance)
        pane.onContentBackingChange = { [weak self] in self?.refreshPageHostBacking() }
        pane.onReload = { [weak self] in self?.reloadTab(tab.id) }
        pane.onRendererPresented = { [weak self] expected in
            guard let self, let (browser, crash) = self.currentRendererPresentation(tab.id, expected) else { return false }
            return browser.rendererCrashDidPresent(crash)
        }
        pane.onRetryRenderer = { [weak self] expected in
            guard let self, let (browser, crash) = self.currentRendererPresentation(tab.id, expected) else { return }
            _ = browser.performRendererCrashAction(crash)
        }
        return pane
    }
    private func requestSidebarFavicon(_ expected: BrowserTab, completion: @escaping (NSImage?) -> Void) {
        let spaceID = activeSpaceID
        func current() -> Bool {
            !isClosing && !wholeWindowClose && presentation.isReady && activeSpaceID == spaceID
                && activeProfileID == expected.profileID && expected.archivedAt == nil
                && sidebarFaviconTabMatches(expected) && isSidebarFaviconTabVisible(expected.id)
                && !store.isProfileRemovalPending(expected.profileID) && !store.retiringTabIDs.contains(expected.id)
                && !closingTabIDs.contains(expected.id) && !transferringTabIDs.contains(expected.id)
                && !resolvingTransfers.contains(expected.id) && transferRecoveries[expected.id] == nil
        }
        guard current(), InternalPage(urlString: expected.url) == nil else { completion(nil); return }
        if let browser = browsers[expected.id] {
            guard browserProfiles[expected.id] == expected.profileID,
                  ownership.canUse(expected.id, owner: presentationID),
                  let page = browser.nativePage, !page.isClosed, page.url?.absoluteString == expected.url else { completion(nil); return }
            completion(page.favicon)
            return
        }
        guard mayReadCachedFavicons, let url = URL(string: expected.url) else { completion(nil); return }
        PCNativeBrowserApplication.favicon(for: url,
            profilePath: store.independentEngineProfilePath(for: expected.profileID)) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, !self.isClosing, !self.wholeWindowClose,
                      self.activeSpaceID == spaceID, self.activeProfileID == expected.profileID,
                      self.sidebarFaviconTabMatches(expected), self.browsers[expected.id] == nil,
                      !self.store.isProfileRemovalPending(expected.profileID), !self.store.retiringTabIDs.contains(expected.id),
                      !self.closingTabIDs.contains(expected.id), !self.transferringTabIDs.contains(expected.id),
                      !self.resolvingTransfers.contains(expected.id), self.transferRecoveries[expected.id] == nil else { return }
                completion(image)
            }
        }
    }
    private func requestSidebarSavedFavicon(_ expected: BrowserTab, completion: @escaping (NSImage?) -> Void) {
        let spaceID = activeSpaceID
        guard sidebarSavedFaviconIsCurrent(expected, spaceID: spaceID), mayReadCachedFavicons,
              let destination = expected.resetDestination else { completion(nil); return }
        PCNativeBrowserApplication.favicon(for: destination,
            profilePath: store.independentEngineProfilePath(for: expected.profileID)) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.sidebarSavedFaviconIsCurrent(expected, spaceID: spaceID) else { return }
                completion(image)
            }
        }
    }
    private var mayReadCachedFavicons: Bool {
        guard !store.isEphemeral, let binding = nativeBinding, !binding.isPrivateBrowsing else { return false }
        return binding.browsingContextKind == .regular || binding.browsingContextKind == .unavailable
    }
    private func isSidebarFaviconTabVisible(_ id: UUID) -> Bool {
        let spaceID = activeSpaceID, profileID = activeProfileID
        return store.state.tabs.contains { $0.id == id && $0.archivedAt == nil && $0.profileID == profileID
            && ($0.kind == .favorite || $0.spaceID == spaceID) }
    }
    private func sidebarFaviconTabMatches(_ expected: BrowserTab) -> Bool {
        store.state.tabs.contains {
            $0.id == expected.id && $0.url == expected.url && $0.profileID == expected.profileID
                && $0.archivedAt == nil
        }
    }
    private func sidebarSavedFaviconIsCurrent(_ expected: BrowserTab, spaceID: UUID) -> Bool {
        !isClosing && !wholeWindowClose && presentation.isReady && activeSpaceID == spaceID
            && activeProfileID == expected.profileID && sidebarFaviconTabMatches(expected)
            && isSidebarFaviconTabVisible(expected.id)
            && !store.isProfileRemovalPending(expected.profileID) && !store.retiringTabIDs.contains(expected.id)
            && !closingTabIDs.contains(expected.id) && !transferringTabIDs.contains(expected.id)
            && !resolvingTransfers.contains(expected.id) && transferRecoveries[expected.id] == nil
    }

    static var updateReadyToInstall: Bool {
        switch SoftwareUpdater.shared.phase {
        case .readyToInstall, .installing: return true
        default: return false
        }
    }
    private func refreshSidebarBanners() {
        let presentable = !isPrivateBrowsing && !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
        let mayActOnReady: () -> Bool = { [weak self] in
            guard let self else { return false }
            return Self.updateReadyToInstall && !self.isClosing && !self.wholeWindowClose
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onRestartAndUpdate = { guard mayActOnReady() else { return }; SoftwareUpdater.shared.installAndRelaunch() }
        sidebar.onToggleAutomaticUpdates = { [weak self] in
            guard mayActOnReady() else { return }
            SoftwareUpdater.shared.automaticallyInstallsUpdates.toggle()
            self?.refreshSidebarBanners()
        }
        let ready = presentable && Self.updateReadyToInstall
        sidebar.showUpdateReady(ready, automaticUpdates: ready ? SoftwareUpdater.shared.automaticallyInstallsUpdates : nil)

        let updateComplete = SoftwareUpdateBanner.shared
        let completeVisible = presentable && updateComplete.showsCompletedUpdate && !Self.updateReadyToInstall
        if completeVisible && sidebarPresentation != .hidden && libraryView == nil && nativeFullscreenTabID == nil {
            updateComplete.markCompletedUpdateShown()
        }
        let mayActOnUpdate: () -> Bool = { [weak self] in
            guard let self else { return false }
            return updateComplete.showsCompletedUpdate && !self.isClosing && !self.wholeWindowClose
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onSeeWhatsNew = { [weak self] in
            guard mayActOnUpdate(), let self, self.canOpenPageInNewTab, self.windowCommandSecurityAvailable else { return }
            self.openReleaseNotes(fragment: updateComplete.completedUpdateFragment)
            updateComplete.retireCompletedUpdate()
        }
        sidebar.onShareParc = { [weak self] in
            guard mayActOnUpdate(), let self else { return }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(SoftwareUpdateBanner.shareURL.absoluteString, forType: .string) else { return }
            self.showToast(.copiedLink(SoftwareUpdateBanner.shareURL), at: .window)
        }
        sidebar.onDismissUpdateComplete = { guard mayActOnUpdate() else { return }; updateComplete.retireCompletedUpdate() }
        sidebar.showUpdateComplete(completeVisible)

        let visible = store.autoArchiveEducationPending && !updateComplete.showsCompletedUpdate
            && !Self.updateReadyToInstall && presentable
        let originalSpace = activeSpaceID, originalProfile = activeProfileID
        let mayAct: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.store.autoArchiveEducationPending && !self.isClosing && !self.wholeWindowClose
                && !self.isPrivateBrowsing && !self.isPopupWindow && self.spaceCreation == nil
                && self.activeSpaceID == originalSpace && self.activeProfileID == originalProfile
                && self.window?.isKeyWindow == true && self.window?.attachedSheet == nil
        }
        sidebar.onDismissAutoArchiveEducation = { [weak self] in
            guard mayAct(), let self else { return }
            self.store.dismissAutoArchiveEducation()
            self.refreshSidebarBanners()
        }
        sidebar.onAutoArchiveEducationSettings = { [weak self] in
            guard mayAct(), let self else { return }
            self.showSettings(pane: .spaces)
            guard self.settings?.showAutoArchiveSettings(spaceID: originalSpace) == true else { return }
            self.store.dismissAutoArchiveEducation()
            self.refreshSidebarBanners()
        }
        sidebar.showAutoArchiveEducation(visible)
    }

    private func refreshHandoffActivity() {
        let url = isPrivateBrowsing || isClosing || wholeWindowClose ? nil : store.state.tabs.first { $0.id == currentTabID }
            .flatMap { URL(string: $0.url) }.flatMap(HandoffActivity.publishable)
        guard userActivity?.webpageURL != url else { return }
        userActivity?.invalidate()
        userActivity = url.map(HandoffActivity.browsing)
    }

    private func updateNavigation() {
        refreshHandoffActivity()
        refreshSidebarBanners()
        navigationHistory?.validate()
        refreshDeveloperToolbars()
        synchronizeNativeLayout()
        refreshExtensionControls()
        refreshPaymentControls()
        refreshCaptureIndicators()
        refreshMiniPlayers()
        let state = presentedState
        refreshFavoriteOverlays(from: state)
        let published = publishedShareableAndAudio()
        let canBack = navigationPage?.canShowBackHistory ?? false
        let canForward = navigationPage?.canShowForwardHistory ?? false
        if !sidebar.applyLivePageMetadata(state: state, focusedTabID: currentTabID,
                                          loading: loadingTabs, canBack: canBack, canForward: canForward,
                                          captures: capturePresentations, shareable: published.shareable,
                                          audio: published.audio, applyShareableAudio: published.changed) {
            sidebar.render(state: state, focusedTabID: currentTabID, loading: loadingTabs,
                           canBack: canBack, canForward: canForward, captures: capturePresentations,
                           shareable: published.shareable, audio: published.audio)
        }
        if published.changed {
            rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)
        }
        refreshDownloads()
        let tab = store.state.tabs.first { $0.id == currentTabID }
        refreshNavigationControls()
        window?.title = activePeek.map { "\($0.browser.title) — Peek — Parc" } ?? tab.map { "\($0.title) — Parc" } ?? "Parc"
        refreshLoadingIndicators()
        noteReturnGate()
    }

    private func refreshLoadingIndicators() {
        for (id, observer) in paneFrameObservers where panes[id] == nil {
            NotificationCenter.default.removeObserver(observer); paneFrameObservers.removeValue(forKey: id)
        }
        guard !isPopupWindow, !isClosing, !wholeWindowClose, libraryView == nil else { loadingIndicator.update([]); return }
        let ids = renderedPaneIDs.filter { panes[$0]?.superview === splitView }
        let eligible = PageLoadingIndicatorHost.eligible(ids, stacked: !splitView.isVertical && ids.count > 1)
        loadingIndicator.update(eligible.compactMap { id in
            guard let pane = panes[id] else { return nil }
            if paneFrameObservers[id] == nil {
                paneFrameObservers[id] = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: pane, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshLoadingIndicators() }
                }
            }
            let rect = pane.convert(pane.bounds, to: pageHost)
            return PageLoadingIndicatorHost.Pane(id: id, minX: rect.minX, width: rect.width, loading: loadingTabs.contains(id))
        })
    }

    private func refreshNavigationControls() {
        sidebar.updateSpaceAvailability()
        let page = navigationPage, loading = page?.loading == true
        sidebar.updateNavigation(canBack: navigationPage?.canShowBackHistory ?? false,
                                 canForward: navigationPage?.canShowForwardHistory ?? false,
                                 loading: loading, enabled: canPerformNavigation(loading ? .stop : reloadAction),
                                 developerReload: developerReloadPage != nil,
                                 forceReload: DeveloperReloadPreference.state == .forceReload)
        popupChrome.update(url: page?.url, canGoBack: navigationPage?.canShowBackHistory ?? false, loading: loading)
    }

    private func embeddedCaptureOwner(_ identity: UUID) -> (UUID, EaselBrowserObjects, PCBrowserView)? {
        for (tabID, pane) in easelEditors {
            if let objects = pane.editor.pageObjects, let view = objects.ownedViews[identity] { return (tabID, objects, view) }
        }
        return nil
    }
    private func canUseCaptureOwner(_ id: UUID) -> Bool {
        let parent = embeddedCaptureOwner(id)?.0 ?? id
        return ownership.canUse(parent, owner: presentationID) && !transferringTabIDs.contains(parent)
    }
    private func captureBrowser(_ id: UUID) -> PCBrowserView? {
        browsers[id] ?? peeks.values.first(where: { $0.identity == id })?.browser ?? embeddedCaptureOwner(id)?.2
    }
    private func refreshMiniPlayers(force: Bool = false) {
        let (signature, pendingAdmission) = miniPlayerSourceSignature()
        if !force, !pendingAdmission, signature == lastMiniPlayerSourceSignature { return }
        lastMiniPlayerSourceSignature = signature
        onMiniPlayerSourceChange?()
    }

    private func miniPlayerSourceSignature() -> (String, Bool) {
        var parts: [String] = [
            canPresentMiniPlayers ? "P1" : "P0",
            (isClosing || wholeWindowClose || windowClosePending || windowCloseApproved) ? "W1" : "W0",
            "H\(canPresentMiniPlayer(offTheRecord: false) ? 1 : 0)\(canPresentMiniPlayer(offTheRecord: true) ? 1 : 0)",
        ]
        func appendGate(_ prefix: String, _ ids: Set<UUID>) {
            parts.append(prefix + ids.map(\.uuidString).sorted().joined(separator: ","))
        }
        appendGate("C", closingTabIDs)
        appendGate("T", transferringTabIDs)
        appendGate("R", modelRetirementIDs)
        appendGate("K", peekRetirementParents)
        let statusSel = #selector(getter: PCNativePage.mediaSessionStatus)
        let revisionSel = #selector(getter: PCNativePage.mediaControlsRevision)
        let audioSel = #selector(getter: PCNativePage.tabAudioState)
        var pendingAdmission = false
        for id in browsers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let view = browsers[id], view.window === window,
                  let profileID = browserProfiles[id],
                  let page = view.nativePage, !page.isClosed else { continue }
            let pageSig = miniPlayerPageSignature(kind: "b", id: id, profileID: profileID,
                                                  page: page, statusSel: statusSel,
                                                  revisionSel: revisionSel, audioSel: audioSel)
            if pageSig.pendingAdmission { pendingAdmission = true }
            parts.append(pageSig.token)
        }
        for peek in peeks.values.sorted(by: { $0.identity.uuidString < $1.identity.uuidString }) {
            guard peek.browser.window === window, !peek.page.isClosed,
                  let profileID = browserProfiles[peek.parentTabID] else { continue }
            let parentPage = browsers[peek.parentTabID]?.nativePage
            let pageSig = miniPlayerPageSignature(kind: "p", id: peek.identity, profileID: profileID,
                                                  page: peek.page, statusSel: statusSel,
                                                  revisionSel: revisionSel, audioSel: audioSel)
            if pageSig.pendingAdmission { pendingAdmission = true }
            parts.append(pageSig.token
                + "|parent:\(peek.parentTabID.uuidString)|pending:\(peek.closePending ? 1 : 0)"
                + "|ppage:\(parentPage?.identifier ?? "-")|pmatch:\(parentPage === peek.parentPage ? 1 : 0)")
        }
        return (parts.joined(separator: ";"), pendingAdmission)
    }

    private func miniPlayerPageSignature(kind: String, id: UUID, profileID: UUID,
                                         page: PCNativePage, statusSel: Selector,
                                         revisionSel: Selector, audioSel: Selector)
        -> (token: String, pendingAdmission: Bool) {
        let status = page.responds(to: statusSel) ? page.mediaSessionStatus.rawValue : -1
        let revision = page.responds(to: revisionSel) ? page.mediaControlsRevision : 0
        var part = "\(kind):\(id.uuidString)|\(profileID.uuidString)|\(page.identifier)|s\(status)|g\(revision)"
        if page.responds(to: audioSel), let audio = page.tabAudioState,
           page.responds(to: #selector(PCNativePage.tabAudioIsMuted(_:))),
           page.responds(to: #selector(PCNativePage.tabAudioIsAudible(_:))) {
            part += "|tm\(page.tabAudioIsMuted(audio) ? 1 : 0)|ta\(page.tabAudioIsAudible(audio) ? 1 : 0)"
        } else {
            part += "|tm-|ta-"
        }
        if let media = page.mediaState {
            part += "|m\(media.identifier)|a\(media.admissionSequence)|o\(media.isOffTheRecord ? 1 : 0)"
            part += "|play\(media.playing ? 1 : 0)|mute\(media.muted ? 1 : 0)|vol\(Int((media.volume * 100).rounded()))"
            part += "|t\(media.title)|u\(media.sourceURL)"
            part += "|pp\(media.canPlayPause ? 1 : 0)|pv\(media.hasPreviousTrack ? 1 : 0)|nx\(media.hasNextTrack ? 1 : 0)"
            part += "|sv\(media.canSetVolume ? 1 : 0)|mic\(media.canToggleMicrophone ? 1 : 0)|cam\(media.canToggleCamera ? 1 : 0)"
            part += "|mo\(media.microphoneOn ? 1 : 0)|co\(media.cameraOn ? 1 : 0)"
            part += "|pip\(media.canEnterPictureInPicture ? 1 : 0)"
            if let icon = media.icon, let data = icon.tiffRepresentation {
                var hasher = Hasher()
                hasher.combine(data.count)
                hasher.combine(data)
                part += "|icon\(hasher.finalize())"
            } else {
                part += "|icon0"
            }
            return (part, false)
        }
        part += "|m-"
        let pending = status != PCNativeMediaSessionStatus.inactive.rawValue && status >= 0
        return (part, pending)
    }
    func prepareMiniPlayerSourcesForAdmission() {
        let closingWindow = isClosing || wholeWindowClose || windowClosePending || windowCloseApproved
        for (id, view) in browsers where !transferringTabIDs.contains(id) {
            if closingWindow || closingTabIDs.contains(id) || modelRetirementIDs.contains(id) {
                view.nativePage?.withdrawMediaState()
            }
        }
        for peek in peeks.values where !transferringTabIDs.contains(peek.parentTabID) {
            if closingWindow || peek.closePending || closingTabIDs.contains(peek.parentTabID) ||
                modelRetirementIDs.contains(peek.parentTabID) || peekRetirementParents.contains(peek.parentTabID) ||
                browsers[peek.parentTabID]?.nativePage !== peek.parentPage {
                peek.page.withdrawMediaState()
            }
        }
    }
    func applyMiniPlayers(_ items: [MiniPlayerItem]) {
        let current = canPresentMiniPlayers ? items.filter { $0.valid() }.sorted {
            $0.state.admissionSequence < $1.state.admissionSequence
        } : []
        sidebar.updateMiniPlayers(current)
    }
    private var canPresentMiniPlayers: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose &&
            !windowClosePending && !windowCloseApproved && window != nil
    }
    private func canPresentMiniPlayer(offTheRecord: Bool) -> Bool {
        guard canPresentMiniPlayers, let window, let binding = nativeBinding,
              binding.window === window, PCNativeBrowserApplication.window(forNativeWindow: window) === binding,
              binding.browsingContextKind != .mixed, binding.isPrivateBrowsing == offTheRecord else { return false }
        let kind = binding.browsingContextKind
        return kind == .unavailable || kind == (offTheRecord ? .offTheRecord : .regular)
    }
    func miniPlayerItems(for host: BrowserWindowController) -> [MiniPlayerItem] {
        guard canPresentMiniPlayers, host.canPresentMiniPlayers,
              let hostWindow = host.window else { return [] }
        let hostLease = MiniPlayerHostLease(hostWindow)
        var items: [MiniPlayerItem] = []
        for id in browsers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let view = browsers[id], view.window === window,
                  let profileID = browserProfiles[id],
                  liveTabModels[id]?.profileID == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
                  let page = view.nativePage, !page.isClosed, let state = page.admitMediaState(),
                  host.canPresentMiniPlayer(offTheRecord: state.isOffTheRecord),
                  page.canPresentMediaState(state, in: hostWindow) else { continue }
            let offTheRecord = state.isOffTheRecord
            let episodeID = state.identifier
            let valid = { [weak self, weak host, weak view, weak page, weak hostWindow] in
                guard let self, let host, let hostWindow, let view, let page,
                      host.window === hostWindow, host.canPresentMiniPlayer(offTheRecord: offTheRecord),
                      self.canPresentMiniPlayers,
                      !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved,
                      self.browsers[id] === view, self.liveTabModels[id]?.profileID == profileID,
                      self.browserProfiles[id] == profileID, view.nativePage === page,
                      view.window === self.window, !page.isClosed,
                      self.ownership.canUse(id, owner: self.presentationID),
                      !self.transferringTabIDs.contains(id), !self.closingTabIDs.contains(id),
                      !self.modelRetirementIDs.contains(id), let current = page.mediaState,
                      current.identifier == episodeID,
                      page.canPresentMediaState(current, in: hostWindow) else { return false }
                return true
            }
            items.append(MiniPlayerItem(page: page, state: state, icon: state.icon, host: hostLease,
                valid: valid, reveal: { [weak self, weak page, weak hostWindow] in
                    guard valid(), let self, let page, let state = page.mediaState, let hostWindow, hostWindow.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: hostWindow),
                          page.canRevealMediaState(state, in: hostWindow), let window = self.window else { return }
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow) else { return }
                    window.makeKeyAndOrderFront(nil)
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow, NSApp.isActive,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    self.closeLibrary(restoreFocus: false)
                    guard valid(), page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    _ = self.selectTab(id)
                }))
        }
        for peek in peeks.values.sorted(by: { $0.identity.uuidString < $1.identity.uuidString }) {
            guard let profileID = browserProfiles[peek.parentTabID],
                  peek.browser.window === window, !peek.closePending, !peek.page.isClosed,
                  peeks[peek.page.identifier] === peek,
                  browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                  ownership.canUse(peek.parentTabID, owner: presentationID),
                  !closingTabIDs.contains(peek.parentTabID), !modelRetirementIDs.contains(peek.parentTabID),
                  !peekRetirementParents.contains(peek.parentTabID), !transferringTabIDs.contains(peek.parentTabID),
                  let state = peek.page.admitMediaState(),
                  host.canPresentMiniPlayer(offTheRecord: state.isOffTheRecord),
                  peek.page.canPresentMediaState(state, in: hostWindow) else { continue }
            let offTheRecord = state.isOffTheRecord
            let episodeID = state.identifier
            let valid = { [weak self, weak host, weak hostWindow, weak peek] in
                guard let self, let host, let hostWindow, let peek,
                      host.window === hostWindow, host.canPresentMiniPlayer(offTheRecord: offTheRecord),
                      self.canPresentMiniPlayers,
                      !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved,
                      !peek.closePending, !peek.page.isClosed,
                      self.peeks[peek.page.identifier] === peek,
                      self.browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                      self.browserProfiles[peek.parentTabID] == profileID,
                      peek.browser.window === self.window,
                      self.ownership.canUse(peek.parentTabID, owner: self.presentationID),
                      !self.closingTabIDs.contains(peek.parentTabID),
                      !self.modelRetirementIDs.contains(peek.parentTabID),
                      !self.peekRetirementParents.contains(peek.parentTabID),
                      !self.transferringTabIDs.contains(peek.parentTabID),
                      let current = peek.page.mediaState, current.identifier == episodeID,
                      peek.page.canPresentMediaState(current, in: hostWindow) else { return false }
                return true
            }
            items.append(MiniPlayerItem(page: peek.page, state: state, icon: state.icon, host: hostLease,
                valid: valid, reveal: { [weak self, weak peek, weak hostWindow] in
                    guard valid(), let self, let peek, let state = peek.page.mediaState, let hostWindow, hostWindow.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: hostWindow),
                          peek.page.canRevealMediaState(state, in: hostWindow), let window = self.window else { return }
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow) else { return }
                    window.makeKeyAndOrderFront(nil)
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow, NSApp.isActive,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    self.closeLibrary(restoreFocus: false)
                    guard valid(), peek.page.canContinueMediaReveal(state, in: hostWindow), window.isKeyWindow,
                          PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
                    if self.selectTab(peek.parentTabID), valid(),
                       peek.page.canContinueMediaReveal(state, in: hostWindow) { peek.focus() }
                }))
        }
        return items
    }

    private func liveShareableTabs() -> Set<UUID> {
        Set(browsers.compactMap { id, browser in
            ownership.canUse(id, owner: presentationID) && browser.window === window
                && browser.canShareThisTabInstead ? id : nil
        })
    }

    private func liveTabAudio() -> [UUID: SidebarTabAudio] {
        browsers.reduce(into: [UUID: SidebarTabAudio]()) { result, pair in
            let (id, browser) = pair
            guard browser.window === window, ownership.canUse(id, owner: presentationID),
                  browserProfiles[id] == activeProfileID, let page = browser.nativePage,
                  page.responds(to: #selector(getter: PCNativePage.tabAudioState)),
                  page.responds(to: #selector(PCNativePage.tabAudioIsAudible(_:))),
                  page.responds(to: #selector(PCNativePage.tabAudioIsMuted(_:))),
                  page.responds(to: #selector(PCNativePage.toggleTabAudioMuted(_:))),
                  let state = page.tabAudioState else { return }
            result[id] = SidebarTabAudio(lease: state, audible: page.tabAudioIsAudible(state),
                                         muted: page.tabAudioIsMuted(state))
        }
    }

    private func shareableAudioFingerprint(shareable: Set<UUID>,
                                           audio: [UUID: SidebarTabAudio]) -> String {
        let sharePart = shareable.map(\.uuidString).sorted().joined(separator: ",")
        let audioPart = audio.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let entry = audio[id] else { return id.uuidString }
            return [
                id.uuidString,
                String(describing: ObjectIdentifier(entry.lease)),
                entry.audible ? "1" : "0",
                entry.muted ? "1" : "0",
            ].joined(separator: "\u{1f}")
        }.joined(separator: ";")
        return sharePart + "\u{1e}" + audioPart
    }

    private func publishedShareableAndAudio()
        -> (shareable: Set<UUID>, audio: [UUID: SidebarTabAudio], changed: Bool) {
        let shareable = liveShareableTabs()
        let audio = liveTabAudio()
        let fingerprint = shareableAudioFingerprint(shareable: shareable, audio: audio)
        if fingerprint == lastShareableAudioFingerprint {
            return (lastAppliedShareable, lastAppliedAudio, false)
        }
        return (shareable, audio, true)
    }

    private func rememberAppliedShareableAudio(shareable: Set<UUID>,
                                               audio: [UUID: SidebarTabAudio]) {
        lastShareableAudioFingerprint = shareableAudioFingerprint(shareable: shareable, audio: audio)
        lastAppliedShareable = shareable
        lastAppliedAudio = audio
    }

    private func capturePresentationFingerprint(
        _ presentations: [UUID: CaptureIndicatorPresentation]
    ) -> String {
        presentations.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let p = presentations[id] else { return id.uuidString }
            return [
                id.uuidString,
                p.camera ? "1" : "0",
                p.microphone ? "1" : "0",
                p.tab ? "1" : "0",
                p.window ? "1" : "0",
                p.display ? "1" : "0",
                p.mirrored ? "1" : "0",
                p.shared ? "1" : "0",
            ].joined(separator: "\u{1f}")
        }.joined(separator: ";")
    }

    private func refreshCaptureIndicators() {
        var next: [UUID: CaptureIndicatorPresentation] = [:]
        for (id, browser) in browsers {
            guard ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), browser.window === window,
                  browserProfiles[id] == liveTabModels[id]?.profileID,
                  let state = browser.captureState, state.active else { continue }
            next[id] = CaptureIndicatorPresentation(state)
        }
        for peek in peeks.values where !peek.page.isClosed && peek.browser.window === window {
            if let state = peek.browser.captureState, state.active { next[peek.identity] = CaptureIndicatorPresentation(state) }
        }
        for pane in easelEditors.values {
            for (identity, view) in pane.editor.pageObjects?.ownedViews ?? [:] {
                if view.window === window, let state = view.captureState, state.active {
                    next[identity] = CaptureIndicatorPresentation(state)
                }
            }
        }
        let fingerprint = capturePresentationFingerprint(next)
        if fingerprint == lastCapturePresentationFingerprint {
            return
        }
        capturePresentations = next
        lastCapturePresentationFingerprint = fingerprint
    }

    private func refreshFavoriteOverlays(from state: BrowserState) {
        let fingerprint = favoriteOverlayPresentationFingerprint(state)
        if FavoriteOverlayPresentationSkip.shouldSkip(previous: lastFavoriteOverlayFingerprint,
                                                      next: fingerprint) {
            return
        }
        lastFavoriteOverlayFingerprint = fingerprint
        sidebar.updateFavoriteOverlays(favoriteOverlayStates(state))
    }

    private func favoriteOverlayPresentationFingerprint(_ state: BrowserState) -> String {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose else {
            return FavoriteOverlayPresentationSkip.gatedToken
        }
        let profileID = activeProfileID
        let splitIDs = Set(SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID).flatMap(\.tabIDs))
        let sessionStatus = #selector(getter: PCNativePage.mediaSessionStatus)
        var parts: [String] = []
        for tab in state.tabs where tab.kind == .favorite && tab.archivedAt == nil
            && tab.profileID == profileID && !splitIDs.contains(tab.id) {
            let id = tab.id
            guard let view = browsers[id], view.window === window, browserProfiles[id] == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
                  let page = view.nativePage, !page.isClosed else { continue }
            var recording = false
            if let capture = capturePresentations[id] {
                recording = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                    microphone: capture.microphone, tab: capture.tab, window: capture.window,
                    display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
            }
            var badge: String?
            if !peekRetirementParents.contains(id), let peek = peeks.values
                .filter({ $0.parentTabID == id && $0.parentPage === page && !$0.page.isClosed
                    && !$0.closePending && $0.browser.window === window })
                .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                badge = FavoriteOverlayPresentationSkip.badgeToken(
                    peekID: peek.identity, tiffData: peek.page.favicon?.tiffRepresentation)
            }
            var developerTab = false
            if let host = page.developerModeSiteHost {
                developerTab = DeveloperModePreferences.shared.isEnabled(host: host)
            }
            let music: Bool
            if FavoriteOverlayPresentationSkip.needsMediaSessionRead(
                savedURL: tab.savedURL, engineRespondsToStatus: page.responds(to: sessionStatus)) {
                let status = FavoriteMediaSessionStatus(rawStatus: page.mediaSessionStatus.rawValue)
                music = FavoriteTileOverlayRules.showsMusic(singlePage: true, status: status,
                                                            savedURL: tab.savedURL)
            } else {
                music = false
            }
            parts.append(FavoriteOverlayPresentationSkip.tileToken(
                id: id, pageIdentifier: page.identifier, recording: recording,
                badge: badge, developerTab: developerTab, music: music))
        }
        return parts.sorted().joined(separator: ";")
    }

    private func favoriteOverlayStates(_ state: BrowserState) -> [UUID: FavoriteTileOverlayState] {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose else {
            favoriteBadgeIcons = [:]; return [:]
        }
        let profileID = activeProfileID
        let splitIDs = Set(SidebarSplitItems.groups(in: state, spaceID: state.activeSpaceID).flatMap(\.tabIDs))
        let sessionStatus = #selector(getter: PCNativePage.mediaSessionStatus)
        var overlays: [UUID: FavoriteTileOverlayState] = [:]
        var badgeIcons: [UUID: (image: NSImage, data: Data)] = [:]
        defer { favoriteBadgeIcons = badgeIcons }
        for tab in state.tabs where tab.kind == .favorite && tab.archivedAt == nil
            && tab.profileID == profileID && !splitIDs.contains(tab.id) {
            let id = tab.id
            guard let view = browsers[id], view.window === window, browserProfiles[id] == profileID,
                  ownership.canUse(id, owner: presentationID),
                  !transferringTabIDs.contains(id), !closingTabIDs.contains(id),
                  let page = view.nativePage, !page.isClosed else { continue }
            var overlay = FavoriteTileOverlayState()
            if let capture = capturePresentations[id] {
                overlay.recording = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                    microphone: capture.microphone, tab: capture.tab, window: capture.window,
                    display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
            }
            if !peekRetirementParents.contains(id), let peek = peeks.values
                .filter({ $0.parentTabID == id && $0.parentPage === page && !$0.page.isClosed
                    && !$0.closePending && $0.browser.window === window })
                .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                var favicon = peek.page.favicon
                if let icon = favicon, let data = icon.tiffRepresentation {
                    if let shown = favoriteBadgeIcons[peek.identity], shown.data == data { favicon = shown.image }
                    badgeIcons[peek.identity] = (favicon ?? icon, data)
                }
                overlay.badge = FavoriteTileBadge(favicon: favicon)
            }
            if let host = page.developerModeSiteHost {
                overlay.developerTab = DeveloperModePreferences.shared.isEnabled(host: host)
            }
            let listed = FavoriteTileOverlayRules.isMusicHost(URL(string: tab.savedURL)?.host)
            let status = listed && page.responds(to: sessionStatus)
                ? FavoriteMediaSessionStatus(rawStatus: page.mediaSessionStatus.rawValue) : nil
            overlay.music = FavoriteTileOverlayRules.showsMusic(singlePage: true, status: status, savedURL: tab.savedURL)
            if overlay != .none { overlays[id] = overlay }
        }
        return overlays
    }

    private func captureOwnerIDs(of tabID: UUID) -> [UUID] {
        [tabID] + peeks.values.filter { $0.parentTabID == tabID }.map(\.identity)
            + Array(easelEditors[tabID]?.editor.pageObjects?.ownedViews.keys ?? Dictionary<UUID, PCBrowserView>().keys)
    }

    private func showCaptureMenu(tabID: UUID, anchor: NSView) {
        guard let parent = window, anchor.window === parent, !isClosing,
              !wholeWindowClose, parent.attachedSheet == nil else { return }
        let menu = NSMenu()
        for id in captureOwnerIDs(of: tabID) {
            guard let browser = captureBrowser(id), browser.window === parent,
                  canUseCaptureOwner(id),
                  !transferringTabIDs.contains(id),
                  let page = browser.nativePage,
                  let state = browser.captureState, state.active else { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let label = NSMenuItem(title: browser.title.isEmpty ? "Untitled tab" : browser.title, action: nil, keyEquivalent: "")
            menu.addItem(label)
            if let origin = browser.url?.host {
                menu.addItem(NSMenuItem(title: origin, action: nil, keyEquivalent: ""))
            }
            for detail in CaptureIndicatorPresentation(state).details {
                menu.addItem(NSMenuItem(title: detail, action: nil, keyEquivalent: ""))
            }
            func stopItem(_ title: String, sharing: Bool) {
                menu.addItem(MenuAction.item(title) { [weak self, weak browser, weak parent] in
                    guard let self, let browser, let parent,
                          self.window === parent, browser.window === parent,
                          self.captureBrowser(id) === browser, browser.nativePage === page,
                          self.canUseCaptureOwner(id),
                          !self.transferringTabIDs.contains(id), !self.isClosing,
                          !self.wholeWindowClose else { return }
                    _ = browser.stopCapture(state, sharing: sharing)
                    self.updateNavigation()
                })
            }
            if state.canStopSharing { stopItem("Stop sharing", sharing: true) }
            if state.canStopDevices {
                stopItem(state.camera && state.microphone ? "Stop camera and microphone" : state.camera ? "Stop camera" : "Stop microphone", sharing: false)
            }
            if !state.canStopSharing && !state.canStopDevices {
                menu.addItem(NSMenuItem(title: "Stop is controlled by the capture owner", action: nil, keyEquivalent: ""))
            }
            menu.addItem(MenuAction.item("Go to tab") { [weak self, weak browser] in
                guard let self, let browser, self.captureBrowser(id) === browser,
                      browser.nativePage === page, self.canUseCaptureOwner(id) else { return }
                if let owner = self.embeddedCaptureOwner(id) {
                    if self.selectTab(owner.0) { owner.1.reveal(page) }
                } else { self.selectTab(id) }
            })
        }
        guard !menu.items.isEmpty else { refreshCaptureIndicators(); return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
    }

    private func layoutChrome() {
        let fingerprint = chromeGeometryFingerprint()
        let dirtyHostedLayout = pageHost.needsLayout
            || pageHost.subviews.contains(where: \.needsLayout)
            || extensionSidePanel.needsLayout
            || extensionSidePanel.subviews.contains(where: \.needsLayout)
        if LayoutChromeGeometrySkip.shouldReturnEarly(
            previous: lastAppliedChromeGeometryFingerprint,
            next: fingerprint,
            dirtyHostedLayout: dirtyHostedLayout
        ) {
            return
        }
        refreshSidebarHoverZones()
        refreshStartPageChrome()
        if sidebarChromePass == .geometry {
            layoutChromeGeometry()
            lastAppliedChromeGeometryFingerprint = fingerprint
            return
        }
        let fullPass = sidebarChromePass == .full
        defer { if fullPass { pageHost.validateDrop() } }
        defer { if fullPass { pageCapture?.reconcile() } }
        let sidebarAvailable = libraryView == nil && !isPopupWindow && nativeFullscreenTabID == nil
        let sidebarVisible = sidebarAvailable && sidebarPresentation != .hidden
        let resizable = sidebarVisible && (!sidebarMotionVisible || isSidebarResizing)
        if !resizable { sidebarResizeRegion.isHidden = true }
        let sidebarWidth = sidebarLayoutWidth
        let bounds = rootView.bounds
        let layoutKey: [CGFloat] = [bounds.width, bounds.height, sidebarWidth,
            nativeFullscreenTabID == nil ? 0 : 1, libraryView == nil ? 0 : 1,
            findHost.isHidden ? 0 : 1,
            extensionSidePanelVisible ? 1 : 0]
        if sidebarMotionLayoutKey != layoutKey {
            sidebarPreviews?.dismiss()
            if libraryMotion.isAnimating {
                libraryMotion.cancel(); pageHost.needsLayout = true; extensionSidePanel.needsLayout = true
            }
            if !preparingSidebarMotion, sidebarMotion.isAnimating {
                settleSidebarMotion()
            }
        }
        sidebarMotionLayoutKey = layoutKey
        sidebarContainer.isHidden = !sidebarAvailable
        let floatingSurface = sidebarPresentation == .floating || sidebarFloatingSurface
        if sidebarContainer.drawsBackground != floatingSurface { sidebarContainer.drawsBackground = floatingSurface }
        let frames = chromeFrames(sidebarWidth: sidebarWidth, in: bounds)
        let sidebarMoved = sidebarContainer.frame != frames.sidebar
        sidebarContainer.frame = frames.sidebar
        sidebarContainer.floatingCornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : nil
        sidebarContainer.docksFloatingSurface = fullPass && sidebarFloatingSurface && sidebarPresentation == .locked
        if fullPass { sidebarContainer.preparesFloatingDock = false }
        sidebar.layer?.cornerRadius = floatingSurface ? FloatingSidebarSurface.cornerRadius : 0
        sidebar.clipsToBounds = floatingSurface
        if fullPass, sidebarMoved { sidebarContainer.invalidateCoordinates() }
        sidebar.frame = sidebarContainer.bounds
        let presented = sidebarAvailable && sidebarPresentation.presents(inMotion: sidebarMotionVisible)
        let dismissed = sidebar.isPresented && !presented
        sidebar.isPresented = presented
        if dismissed, sidebarOwnsFirstResponder { window?.makeFirstResponder(nil) }
        sidebar.setFloating(sidebarPresentation != .locked)
        if resizable {
            sidebarResizeRegion.frame = SidebarResizeRegionView.frame(trailing: sidebarContainer.frame, in: bounds)
            sidebarResizeRegion.isHidden = false
        }
        libraryView?.isHidden = nativeFullscreenTabID != nil
        pageHost.layer?.cornerRadius = pageCornerRadius
        pageShadow.cornerRadius = isPopupWindow ? WindowFrameThickness.cornerRadius(for: SidebarChromeFrames.pageInset) : nil
        libraryView?.frame = frames.library
        popupChrome.isHidden = frames.popupChrome.height == 0
        popupChrome.frame = frames.popupChrome
        var flushedHostedLayout = false
        let pageHostMoved = pageHost.frame != frames.pageHost
        pageHost.frame = frames.pageHost
        if pageHostMoved, loadedStartPage?.superview != nil { loadedStartPage?.invalidateCoordinates() }
        splitView.dividerThickness = frameThickness
        pageShadow.place(around: frames.pageHost)
        refreshPageShadow()
        splitMarginHandle.frame = splitMarginFrame(frames)
        let sidePanelHidden = !frames.showsSidePanel
        let sidePanelMoved = extensionSidePanel.isHidden != sidePanelHidden
            || extensionSidePanel.frame != frames.sidePanel
        extensionSidePanel.isHidden = sidePanelHidden
        extensionSidePanel.frame = frames.sidePanel
        if sidePanelMoved || extensionSidePanel.needsLayout
            || extensionSidePanel.subviews.contains(where: \.needsLayout) {
            extensionSidePanel.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        }
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        layoutFrameCrank(frames)
        refreshWindowButtons()
        defer { lastAppliedChromeGeometryFingerprint = fingerprint }
        guard fullPass else { return }
        if pageHostMoved {
            pageHost.needsLayout = true
            pageHost.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        } else if pageHost.needsLayout
            || pageHost.subviews.contains(where: \.needsLayout) {
            pageHost.layoutSubtreeIfNeeded()
            flushedHostedLayout = true
        }
        refreshLoadingIndicators()
        layoutPeeks()
        for pane in easelEditors.values { pane.editor.refreshPageVisibility() }
        if flushedHostedLayout {
            synchronizeNativeLayout()
        }
        layoutFindBar()
        refreshPaymentControls()
        commandBar?.refreshPosition()
        windowKeyViews.relink()
    }

    private func chromeGeometryFingerprint() -> LayoutChromeGeometryFingerprint {
        let bounds = rootView.bounds
        return LayoutChromeGeometryFingerprint(
            boundsWidth: bounds.width,
            boundsHeight: bounds.height,
            sidebarWidth: sidebarLayoutWidth,
            presentation: sidebarPresentation,
            motionVisible: sidebarMotionVisible,
            floatingSurface: sidebarFloatingSurface,
            revealsAnchored: sidebarRevealsAnchored,
            previewingHidden: sidebarPreviewingHidden,
            fullscreen: nativeFullscreenTabID != nil,
            library: libraryView != nil,
            libraryContentWidth: libraryContentWidth,
            popup: isPopupWindow,
            sidePanel: extensionSidePanelVisible,
            findVisible: !findHost.isHidden,
            resizing: isSidebarResizing,
            currentTabID: currentTabID,
            activePeekID: activePeek?.identity,
            commandBarOpen: commandBar != nil,
            windowClosePending: windowClosePending,
            transferringTabIDs: transferringTabIDs.sorted { $0.uuidString < $1.uuidString },
            frameThickness: frameThickness
        )
    }

    private var frameThickness: CGFloat {
        isPopupWindow ? SidebarChromeFrames.pageInset : WindowFramePreferences.shared.thickness
    }

    private var pageCornerRadius: CGFloat {
        nativeFullscreenTabID != nil ? 0
            : isPopupWindow ? WindowFrameThickness.cornerRadius(for: SidebarChromeFrames.pageInset) : PageCard.cornerRadius
    }

    private func splitMarginFrame(_ frames: SidebarChromeFrames) -> NSRect {
        let page = frames.pageHost, inset = frameThickness
        guard WindowFrameThickness.showsSplitGrip(inset), !frames.showsSidePanel, nativeFullscreenTabID == nil, page.height > 0,
              rootView.bounds.maxX - page.maxX >= inset else { return .zero }
        return NSRect(x: page.maxX, y: page.minY, width: inset, height: page.height)
    }

    private func chromeFrames(sidebarWidth: CGFloat, in bounds: NSRect) -> SidebarChromeFrames {
        let placement = SidebarPresentationFrame(sidebarPresentation, inMotion: sidebarMotionVisible,
                                                 floatingSurface: sidebarFloatingSurface, revealsAnchored: sidebarRevealsAnchored)
        return SidebarChromeFrames(bounds: bounds, sidebarWidth: sidebarWidth, presentation: sidebarPresentation, placement: placement,
            previewingHidden: sidebarPreviewingHidden, fullscreen: nativeFullscreenTabID != nil, library: libraryView != nil,
            libraryContentWidth: libraryContentWidth, popup: isPopupWindow,
            sidePanel: extensionSidePanelVisible, thickness: frameThickness)
    }
    private func refreshWindowButtons() {
        let sidebarless = isPopupWindow && nativeFullscreenTabID == nil
        let phase = WindowFullscreenPhase.current(fullscreenPhase, inFullScreen: window?.styleMask.contains(.fullScreen) == true)
        let showsOwn = WindowFullscreenPhase.apply(phase, sidebarless: sidebarless, system: systemWindowButtons)
        sidebar.showsWindowButtons = showsOwn
        libraryView?.showsWindowButtons = showsOwn && !sidebarless
        loadedStartPage?.showsWindowButtons = showsOwn
    }
    private func setFullscreenPhase(_ phase: WindowFullscreenPhase?) {
        guard fullscreenPhase != phase else { return }
        fullscreenPhase = phase
        refreshWindowButtons()
    }

    private func scheduleWindowFrameLayout() {
        guard !windowFrameLayoutPending else { return }
        windowFrameLayoutPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windowFrameLayoutPending = false
            self.applyWindowFrameThickness()
        }
    }

    private func applyWindowFrameThickness() {
        guard !isClosing, !wholeWindowClose else { return }
        let preferences = WindowFramePreferences.shared
        PageCard.follow(thickness: preferences.thickness)
        setContentResizeReason(.frameAdjust, active: preferences.isAdjusting)
        pageShadow.needsDisplay = true
        if !isPopupWindow { splitView.refreshPaneCorners(radius: PageCard.cornerRadius) }
        let ending = windowFrameAdjustApplied && !preferences.isAdjusting
        windowFrameAdjustApplied = preferences.isAdjusting
        if ending { lastAppliedChromeGeometryFingerprint = nil }
        guard sidebarChromePass == .full, !sidebarMotion.isAnimating, !libraryMotion.isAnimating else { return }
        if preferences.isAdjusting {
            sidebarChromePass = .geometry
            layoutChrome()
            sidebarChromePass = .full
        } else {
            layoutChrome()
        }
    }

    var isPresentingFrameCrank: Bool { frameCrank != nil }

    var canAdjustWindowFrame: Bool {
        frameCrank == nil && !isClosing && !wholeWindowClose && !isPopupWindow && libraryView == nil
            && nativeFullscreenTabID == nil && window != nil && !WindowFramePreferences.shared.loadError
    }

    private func windowFrameContextMenu(rootHit hit: NSView?) -> NSMenu? {
        guard let hit else { return windowFrameContextMenu() }
        for owner in [pageHost, sidebarContainer, extensionSidePanel, findHost, popupChrome, splitMarginHandle] as [NSView]
        where hit === owner || hit.isDescendant(of: owner) { return nil }
        if let libraryView, hit.isDescendant(of: libraryView) { return nil }
        return Self.isInsideControl(hit, below: rootView) ? nil : windowFrameContextMenu()
    }

    private func windowFrameContextMenu(sidebarHit hit: NSView?) -> NSMenu? {
        guard let hit else { return windowFrameContextMenu() }
        return Self.isInsideControl(hit, below: sidebarContainer) ? nil : windowFrameContextMenu()
    }

    private static func isInsideControl(_ view: NSView, below root: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current, candidate !== root {
            if candidate is NSControl || candidate is NSTextView { return true }
            current = candidate.superview
        }
        return false
    }

    private func windowFrameContextMenu() -> NSMenu? {
        guard canAdjustWindowFrame else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Adjust Window Frame…", action: #selector(adjustWindowFrameFromMenu(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func adjustWindowFrameFromMenu(_ sender: Any?) { presentFrameCrank() }

    func presentFrameCrank() {
        guard canAdjustWindowFrame else { return }
        if let other = Self.frameCrankOwner, other !== self { other.frameCrank?.finishNow(commit: true) }
        if let bar = commandBar { bar.dismiss(restoreFocus: false) }
        if sidebarPresentation == .floating { setSidebarPresentation(.hidden) }
        let crank = WindowFrameCrankView(value: WindowFramePreferences.shared.state.thickness, palette: frameCrankPalette())
        crank.onPreview = { WindowFramePreferences.shared.setPreview($0) }
        crank.onEvent = { [weak self] event in
            if case .end = event { self?.shudderWindowFrame() }
        }
        crank.onFinish = { [weak self, weak crank] commit, value in
            crank?.removeFromSuperview()
            guard let self else { WindowFramePreferences.shared.setPreview(nil); return }
            if Self.frameCrankOwner === self || Self.frameCrankOwner == nil {
                let preferences = WindowFramePreferences.shared
                if commit { try? preferences.setThickness(value) }
                preferences.setPreview(nil)
            }
            if self.frameCrank === crank { self.frameCrank = nil }
            if Self.frameCrankOwner === self { Self.frameCrankOwner = nil }
            self.sidebarHover.isEnabled = !self.isSidebarResizing
            self.onFrameCrankFinished?()
            self.onFrameCrankFinished = nil
        }
        rootView.addSubview(crank, positioned: .above, relativeTo: nil)
        frameCrank = crank
        Self.frameCrankOwner = self
        sidebarHover.isEnabled = false
        layoutFrameCrank(chromeFrames(sidebarWidth: sidebarLayoutWidth, in: rootView.bounds))
        window?.makeKeyAndOrderFront(nil)
        crank.present()
    }

    private func abandonFrameCrank() {
        frameCrank?.finishNow(commit: true)
    }

    private func layoutFrameCrank(_ frames: SidebarChromeFrames) {
        guard let crank = frameCrank else { return }
        if libraryView != nil || nativeFullscreenTabID != nil || isClosing {
            crank.finishNow(commit: true)
            return
        }
        let bounds = rootView.bounds
        let docked: CGFloat? = sidebarPresentation == .locked && libraryView == nil && !frames.sidebar.isEmpty ? frames.sidebar.maxX : nil
        let hub = WindowFrameCrankPlacement.hub(in: bounds, dockedSidebarEdge: docked)
        let flippedY = rootView.isFlipped ? bounds.maxY - (hub.y - bounds.minY) : hub.y
        let side = WindowFrameCrankView.side
        crank.frame = NSRect(x: hub.x - side / 2, y: flippedY - side / 2, width: side, height: side)
    }

    private func frameCrankPalette() -> WindowFrameCrankPalette {
        let dark = rootView.palette.isDark
        if store.isEphemeral {
            return WindowFrameCrankPalette(accent: NSColor(srgbRed: 0.30, green: 0.55, blue: 1, alpha: 1),
                                           deep: NSColor(srgbRed: 0.17, green: 0.29, blue: 0.53, alpha: 1),
                                           cap: NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 1), dark: true)
        }
        guard let primary = rootView.theme.primaryColor, rootView.theme.isValid else {
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return WindowFrameCrankPalette(accent: accent, deep: accent.blended(withFraction: 0.35, of: .black) ?? accent,
                                           cap: NSColor(white: dark ? 0.32 : 0.78, alpha: 1), dark: dark)
        }
        let base: NSColor = primary.colorSpace == .displayP3
            ? NSColor(displayP3Red: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
            : NSColor(srgbRed: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
        let rgb = base.usingColorSpace(.sRGB) ?? base
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let accent = NSColor(hue: hue, saturation: max(0.55, saturation), brightness: dark ? 0.92 : 0.78, alpha: 1)
        let deep = NSColor(hue: hue, saturation: max(0.4, saturation * 0.9), brightness: dark ? 0.55 : 0.62, alpha: 1)
        let cap = NSColor(hue: hue, saturation: min(0.6, max(0.25, saturation)), brightness: dark ? 0.5 : max(0.7, brightness), alpha: 1)
        return WindowFrameCrankPalette(accent: accent, deep: deep, cap: cap, dark: dark)
    }

    private func shudderWindowFrame() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, 3.2, -2.8, 2, -1.4, 0.7, 0]
        shake.keyTimes = [0, 0.14, 0.32, 0.5, 0.68, 0.84, 1]
        shake.duration = 0.38
        shake.isAdditive = true
        for view in [pageHost, pageShadow, extensionSidePanel, splitMarginHandle, loadingIndicator] as [NSView] {
            view.layer?.add(shake, forKey: "windowFrameShudder")
        }
    }

    private func layoutChromeGeometry() {
        let bounds = rootView.bounds
        let frames = chromeFrames(sidebarWidth: sidebarLayoutWidth, in: bounds)
        sidebarContainer.frame = frames.sidebar
        sidebar.frame = sidebarContainer.bounds
        libraryView?.frame = frames.library
        if isSidebarResizing, !sidebarResizeRegion.isHidden {
            sidebarResizeRegion.frame = SidebarResizeRegionView.frame(trailing: sidebarContainer.frame, in: bounds)
        }
        if sidebarFloatingSurface && sidebarPresentation == .locked { sidebarContainer.docksFloatingSurface = true }
        pageHost.layer?.cornerRadius = pageCornerRadius
        splitView.dividerThickness = frameThickness
        pageHost.frame = frames.pageHost
        extensionSidePanel.isHidden = !frames.showsSidePanel
        extensionSidePanel.frame = frames.sidePanel
        pageShadow.place(around: frames.pageHost)
        loadingIndicator.frame = PageLoadingIndicatorHost.frame(pageHost: frames.pageHost)
        splitMarginHandle.frame = splitMarginFrame(frames)
        pageHost.needsLayout = true
        pageHost.layoutSubtreeIfNeeded()
        layoutFrameCrank(frames)
        refreshLoadingIndicators()
        for peek in peeks.values { peek.view.frame = pageHost.bounds; peek.view.layoutSubtreeIfNeeded() }
        layoutFindBar()
    }

    func newTab() {
        if isPopupWindow {
            guard window?.isKeyWindow == true, windowCommandSecurityAvailable else { return }
            onRequestBrowserTab?(nil); return
        }
        if focusResidentCommandBar() { return }
        presentCommandBar(newTab: true)
    }
    func focusAddress(anchor: NSView? = nil) {
        if !isPopupWindow, focusResidentCommandBar() { return }
        presentCommandBar(newTab: false, addressAnchor: anchor)
    }

    private var showsStartPage: Bool {
        guard let page = loadedStartPage else { return false }
        return page.superview === splitView && !isClosing && !isPopupWindow
    }
    private func loadStartPage() -> StartPageView {
        let page = StartPageView()
        page.coordinateSpace = rootView; page.incognito = rootView.incognito
        page.barRestHeight = CommandBar.residentRestHeight
        page.theme = rootView.theme; page.pagingTransition = rootView.pagingTransition
        page.showsWindowButtons = sidebar.showsWindowButtons
        page.onToggleSidebar = { [weak self] in self?.toggleSidebar() }
        loadedStartPage = page
        return page
    }
    private func scheduleStartPageRefresh() {
        guard !startPageRefreshScheduled else { return }
        startPageRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startPageRefreshScheduled = false
            if !self.rendering { self.refreshStartPage() }
        }
    }
    private func refreshStartPageChrome() {
        guard let page = loadedStartPage else { return }
        let chrome = sidebarPresentation != .locked && nativeFullscreenTabID == nil
        if page.showsWindowChrome != chrome { page.showsWindowChrome = chrome }
        page.sidebarToolbarWidth = sidebarLayoutWidth
        page.sidebarShowsNavigation = !sidebar.usesContentToolbar && !sidebar.navigationInContentToolbar
    }
    private func refreshStartPage() {
        guard showsStartPage, let window else {
            startPagePresented = false
            guard !startPageDeparting else { return }
            residentCommandOwner = nil
            if let bar = residentCommandBar { residentCommandBar = nil; bar.dismiss(restoreFocus: false) }
            return
        }
        refreshStartPageChrome()
        let owner = (spaceID: activeSpaceID, profileID: activeProfileID)
        if let bar = residentCommandBar, residentCommandOwner.map({ $0 != owner }) ?? true {
            residentCommandBar = nil; residentCommandOwner = nil; bar.dismiss(restoreFocus: false)
        }
        var rebuilt = false
        if residentCommandBar == nil, canOwnDownloadDialog(for: owner.profileID) {
            let panel = makeCommandBar(in: window, newTab: true, inSidebar: false, addressAnchor: nil, initialEdit: nil, resident: true)
            residentCommandBar = panel; residentCommandOwner = owner; rebuilt = true
            panel.restorePageFocus = { [weak self, weak panel] in
                DispatchQueue.main.async {
                    guard let self, let panel, self.residentCommandBar === panel, self.showsStartPage,
                          let window = self.window, window.isKeyWindow, window.attachedSheet == nil, self.commandBar == nil,
                          ContentFocusRequest.holdsContentFocus(window.firstResponder, window: window, content: self.startPage) else { return }
                    panel.focusResident()
                }
            }
            panel.presentResident(in: startPage.commandBarSlot)
            residentCommandInputs = nil
            refreshResidentTopDomains(panel)
        }
        let arrived = !startPagePresented
        startPagePresented = true
        if arrived { playStartPageArrival() }
        guard arrived || rebuilt else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, self.showsStartPage, window.isKeyWindow,
                  window.attachedSheet == nil, self.commandBar == nil, self.libraryView == nil, self.spaceCreation == nil,
                  ContentFocusRequest.holdsContentFocus(window.firstResponder, window: window, content: self.startPage) else { return }
            self.residentCommandBar?.focusResident()
        }
    }
    private func playStartPageDeparture() {
        let frame = startPage.convert(startPage.bounds, to: pageHost)
        guard window?.isVisible == true, window?.isMiniaturized != true, presentation.isReady, !isClosing else {
            startPage.removeFromSuperview(); return
        }
        pageHost.addSubview(startPage, positioned: .above, relativeTo: nil)
        startPage.frame = frame
        startPageDeparting = true
        startPage.isDeparting = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            startPage.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startPageDeparting = false
                guard self.startPage.superview !== self.splitView else { return }
                self.startPage.isDeparting = false
                self.startPage.removeFromSuperview()
                self.startPage.alphaValue = 1
                self.refreshStartPage()
            }
        })
    }
    private func playStartPageArrival() {
        startPage.isDeparting = false
        guard window?.isVisible == true, window?.isMiniaturized != true, presentation.isReady else { return }
        startPage.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            startPage.animator().alphaValue = 1
        }
    }
    private func focusResidentCommandBar() -> Bool {
        guard showsStartPage, libraryView == nil, spaceCreation == nil, splitInsertion == nil,
              let bar = residentCommandBar, let window, ownsWindowCommandFocus, window.attachedSheet == nil else { return false }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        if let open = commandBar { commandBar = nil; open.dismiss(restoreFocus: false) }
        if !window.isKeyWindow { window.makeKey() }
        bar.focusResident()
        refreshResidentTopDomains(bar)
        return true
    }

    var canFocusSidebar: Bool {
        !isPopupWindow && libraryView == nil && nativeFullscreenTabID == nil && activePeek == nil
            && canOwnDownloadDialog(for: activeProfileID) && window.map {
                PCNativeBrowserApplication.canPresentTabSwitcher(in: $0)
            } == true
    }

    func focusSidebar() {
        guard canFocusSidebar else { return }
        presentCommandBar(newTab: true, inSidebar: true)
    }

    private func sidebarKeyboardItems() -> [SidebarKeyboardNavigation.Item] {
        SidebarKeyboardNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID, peeks: sidebar.peekedItems, available: { self.switcherCanUse($0) })
    }

    private func reconcileSidebarKeyboardFocus(scroll: Bool = false) {
        guard sidebarKeyboardCursor != nil else { return }
        let items = sidebarKeyboardItems()
        sidebarKeyboardCursor?.reconcile(items.map(\.id))
        let item = items.first { $0.id == sidebarKeyboardCursor?.highlightedID }
        sidebar.highlightItemForKeyboard(sidebarKeyboardBrowsing ? item?.reference : nil, scrollToHighlight: scroll)
    }

    private func splitInsertionTabs(profileID: UUID) -> [BrowserTab] {
        let spaces = Set(store.state.spaces.filter { $0.profileID == profileID }.map(\.id))
        return store.state.tabs.filter { $0.archivedAt == nil && $0.profileID == profileID
            && ($0.kind == .favorite || spaces.contains($0.spaceID)) }
    }
    private func commandBarDocuments(profileID: UUID) -> [CommandBarDocument] {
        guard !isPopupWindow, !isPrivateBrowsing, !store.isProfileRemovalPending(profileID),
              let notes = try? NoteStore.sharedStore(directory: store.notesDirectory(for: profileID)),
              let easels = try? EaselEditorViewController.sharedStore(directory: store.easelsDirectory(for: profileID)) else { return [] }
        let stamp = [store.notesDirectory(for: profileID), easels.documentsDirectory].map {
            (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date) ?? .distantPast
        }
        let all: [CommandBarDocument]
        if let cache = commandBarDocumentCache, cache.profileID == profileID, cache.stamp == stamp {
            all = cache.documents
        } else {
            let noteList = try? notes.list(), easelList = try? easels.list()
            all = (noteList ?? []).map { CommandBarDocument(kind: .note, id: $0.id, title: $0.title) }
                + (easelList ?? []).map { CommandBarDocument(kind: .easel, id: $0.id, title: $0.title) }
            commandBarDocumentCache = noteList != nil && easelList != nil ? (profileID, stamp, all) : nil
        }
        let open = store.state.tabs.filter { $0.profileID == profileID && $0.archivedAt == nil }.compactMap { InternalPage(urlString: $0.url) }
        return all.filter { !open.contains($0.kind == .note ? .note($0.id) : .easel($0.id)) }
    }
    private func deliverCommandBarTopDomains(to panel: CommandBar, profileID: UUID) {
        if let cache = commandBarTopDomainCache, cache.profileID == profileID, cache.revision == store.historyRevision {
            panel.updateTopDomains(cache.domains); return
        }
        let history = commandBarHistory(profileID: profileID), revision = store.historyRevision
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak panel] in
            let domains = CommandBarRanking.topDomains(history.map { ($0.url, $0.title) })
            DispatchQueue.main.async {
                guard let self else { return }
                if self.store.historyRevision == revision { self.commandBarTopDomainCache = (profileID, revision, domains) }
                if let panel, self.presentsCommandBar(panel) { panel.updateTopDomains(domains) }
            }
        }
    }
    private func deliverCommandBarRecentPages(to panel: CommandBar, profileID: UUID) {
        commandBarRecentPages?.query.invalidate()
        commandBarRecentPages = nil
        let path = store.independentEngineProfilePath(for: profileID)
        guard let query = PCNativeBrowserApplication.recentPages(forDomain: "all", profilePath: path, completion: { [weak self, weak panel] pages in
            MainActor.assumeIsolated {
                guard let self, let panel, self.commandBar === panel else { return }
                panel.updateRecentPages(pages.map { ($0.url.absoluteString, $0.title) })
            }
        }) else { return }
        commandBarRecentPages = (query, profileID, store.historyRevision)
    }
    private func commandBarTabs(profileID: UUID, excluding currentID: UUID?) -> [BrowserTab] {
        guard !isPopupWindow else { return [] }
        return store.state.tabs.filter {
            $0.profileID == profileID && $0.id != currentID && $0.archivedAt == nil
                && !closingTabIDs.contains($0.id) && !modelRetirementIDs.contains($0.id)
                && !store.retiringTabIDs.contains($0.id) && !transferringTabIDs.contains($0.id)
        }
    }
    private func commandBarTabCaption(_ tab: BrowserTab) -> CommandBarResultText.TabCaption {
        CommandBarResultText.tabCaption(isFavorite: tab.kind == .favorite, isInActiveSpace: tab.spaceID == activeSpaceID,
                                        spaceName: store.state.spaces.first { $0.id == tab.spaceID }?.name,
                                        isInSplit: store.state.splitLayouts.contains { $0.tabIDs.contains(tab.id) })
    }
    private func commandBarHistory(profileID: UUID) -> [BrowserHistoryEntry] {
        let currentURL = currentBrowser?.url?.absoluteString ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
        if let cache = commandBarHistoryCache,
           cache.revision == store.historyRevision,
           cache.profileID == profileID,
           cache.currentURL == currentURL {
            return cache.entries
        }
        let entries = store.state.history.filter { $0.profileID == profileID && $0.url != currentURL }
        commandBarHistoryCache = (store.historyRevision, profileID, currentURL, entries)
        return entries
    }
    private func commandBarSpaceActions() -> [CommandBarSpaceAction] {
        guard !isPrivateBrowsing, !isPopupWindow else { return [] }
        return CommandBarSpaceAction.snapshot(spaces: store.state.spaces, profiles: store.state.profiles)
    }
    private func commandBarFolderActions() -> [CommandBarFolderAction] {
        guard !isPrivateBrowsing, !isPopupWindow else { return [] }
        return CommandBarFolderAction.snapshot(state: store.state, profileID: activeProfileID)
    }
    private func reconcileCommandBar() {
        reconcileSidebarKeyboardFocus()
        CommandBarReconcileInputs.withPresentedBar(commandBar) { bar in
            let profileID = activeProfileID
            let currentURL = currentBrowser?.url?.absoluteString ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
            bar.reconcile(tabs: splitInsertion == nil ? commandBarTabs(profileID: profileID, excluding: currentTabID) : splitInsertionTabs(profileID: profileID).filter { splitInsertion?.candidateIDs.contains($0.id) == true && !selectedTabIDs.contains($0.id) && canUseOrMoveHere($0.id) },
                          history: commandBarHistory(profileID: profileID),
                          historyRevision: store.historyRevision,
                          historyExcludedURL: currentURL,
                          spaces: commandBarSpaceActions(), folders: commandBarFolderActions())
        }
        CommandBarReconcileInputs.withPresentedBar(residentCommandBar) { bar in
            let profileID = activeProfileID
            let stamp = ResidentCommandBarInputs(state: store.stateRevision, history: store.historyRevision, space: activeSpaceID,
                                                 profile: profileID, selection: selectedTabIDs,
                                                 undo: folderUndo.command(.undo)?.name, redo: folderUndo.command(.redo)?.name)
            if residentCommandInputs != stamp {
                residentCommandInputs = stamp
                bar.reconcile(tabs: commandBarTabs(profileID: profileID, excluding: nil),
                              history: commandBarHistory(profileID: profileID),
                              historyRevision: store.historyRevision, historyExcludedURL: nil,
                              spaces: commandBarSpaceActions(), folders: commandBarFolderActions())
                let items = currentSidebarMenuItems
                let commands = commandBarTypedCommands(items: items, profileID: profileID)
                residentTypedCommands = (items, commands)
                bar.updateTypedCommands(commands)
            }
            if bar.hasFocus { refreshResidentTopDomains(bar) }
        }
        if let bar = commandBar, let asked = commandBarRecentPages, asked.revision != store.historyRevision {
            deliverCommandBarRecentPages(to: bar, profileID: asked.profileID)
        }
    }
    private func presentCommandBar(newTab: Bool, inSidebar: Bool = false, addressAnchor: NSView? = nil, initialEdit: (String, NSRange)? = nil) {
        let originalProfileID = activeProfileID
        guard let original = window, ownsWindowCommandFocus, original.attachedSheet == nil,
              canOwnDownloadDialog(for: originalProfileID), windowCommandSecurityAvailable else { return }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard window === original, ownsSpaceCommandFocus, windowCommandSecurityAvailable else { return }
        }
        if original.isKeyWindow && !PCNativeBrowserApplication.canPresentTabSwitcher(in: original) { return }
        func stillOwnsInteraction() -> Bool {
            guard window === original, ownsSpaceCommandFocus, original.attachedSheet == nil,
                  canOwnDownloadDialog(for: originalProfileID), windowCommandSecurityAvailable else { return false }
            return !original.isKeyWindow || PCNativeBrowserApplication.canPresentTabSwitcher(in: original)
        }
        guard WindowOwnerSequence.run(while: stillOwnsInteraction, steps: [
            { self.cancelSplitInsertion(restoreFocus: false) },
            { self.cancelSpaceCreation(restoreFocus: false) },
            { self.pageCapture?.dismiss(restoreFocus: false) },
            { self.cancelPendingCommandSplit() },
            { self.commandBar?.dismiss() },
            { self.navigationHistory?.dismiss() },
            { self.sidebarPreviews?.dismiss() },
            { self.tabSwitcher?.cancel() }
        ]), let window, window === original,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
        if inSidebar {
            if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
            settleSidebarMotion(); layoutChrome()
            let current = sidebarKeyboardItems().first { $0.selection?.tabIDs == selectedTabIDs }
            sidebarKeyboardCursor = SidebarKeyboardCursor(highlightedID: current?.id)
            sidebarKeyboardBrowsing = true
            sidebar.setKeyboardSearchActive(true)
            reconcileSidebarKeyboardFocus(scroll: true)
        }
        let panel = makeCommandBar(in: window, newTab: newTab, inSidebar: inSidebar, addressAnchor: addressAnchor,
                                   initialEdit: initialEdit, resident: false)
        commandBarCreatesNewTab = newTab; commandBarShowsNewTabPlaceholder = newTab && !inSidebar
        commandBar = panel; panel.present()
        if !isPopupWindow, !isPrivateBrowsing {
            deliverCommandBarTopDomains(to: panel, profileID: activeProfileID)
            deliverCommandBarRecentPages(to: panel, profileID: activeProfileID)
        }
    }
    private func makeCommandBar(in window: NSWindow, newTab: Bool, inSidebar: Bool, addressAnchor: NSView?,
                                initialEdit: (String, NSRange)?, resident: Bool) -> CommandBar {
        let membershipItems = sidebar.commandBarSelectionItems()
            ?? (selectedTabIDs.count == 1 ? currentTabID.map { [.tab($0)] } : nil) ?? []
        let favoriteAction = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFavoriteAction(items: membershipItems, spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) : nil
        let favoriteOwners: [() -> Bool] = favoriteAction?.tabIDs.map { id in
            let browser = browsers[id], page = browser?.nativePage
            let note = noteEditors[id]?.editor, easel = easelEditors[id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil
            let hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self, let tab = self.visibleTabs.first(where: { $0.id == id }),
                      self.canPerformSidebarTabAction(tab, closing: false),
                      !self.modelRetirementIDs.contains(id),
                      hadBrowser == (self.browsers[id] != nil), self.browsers[id] === browser,
                      hadPage == (self.browsers[id]?.nativePage != nil), self.browsers[id]?.nativePage === page,
                      page?.isClosed != true,
                      hadNote == (self.noteEditors[id]?.editor != nil), self.noteEditors[id]?.editor === note,
                      hadEasel == (self.easelEditors[id]?.editor != nil), self.easelEditors[id]?.editor === easel else { return false }
                return true
            }
        } ?? []
        let folderMoveItems = sidebar.commandBarSelectionItems() ?? {
            if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: {
                $0.tabIDs == selectedTabIDs && $0.sidebarAnchorID != nil
            }) { return [.split(group.id)] }
            return selectedTabIDs.count == 1 ? currentTabID.map { [.tab($0)] } ?? [] : []
        }()
        let folderMoveSource = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFolderMoveSource(items: folderMoveItems, spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) : nil
        let folderMoves = folderMoveSource.map { CommandBarFolderMove.snapshot(source: $0, state: store.state) } ?? []
        let folderMoveOwners = folderMoveSource.flatMap { prepareSidebarSpaceMoveOwners?(Set($0.tabIDs)) }
        let folderMoveClaims = Dictionary(uniqueKeysWithValues: (folderMoveSource?.tabIDs ?? []).map {
            ($0, ownership.claimSnapshot($0))
        })
        let folderMoveFocus = focusedTabID
        let favoriteRenameAction = !isPrivateBrowsing && !isPopupWindow && activePeek == nil
            ? CommandBarFavoriteRenameAction(state: store.state, spaceID: activeSpaceID,
                profileID: activeProfileID, selectedTabIDs: selectedTabIDs) : nil
        let renameBinding = nativeBinding
        let renameNote = favoriteRenameAction.flatMap { noteEditors[$0.tab.id]?.editor }
        let renameEasel = favoriteRenameAction.flatMap { easelEditors[$0.tab.id]?.editor }
        let hadRenameNote = renameNote != nil, hadRenameEasel = renameEasel != nil
        let submissionRevision = UUID()
        if resident { residentCommandSubmissionRevision = submissionRevision } else { commandSubmissionRevision = submissionRevision }
        let submissionIsCurrent: () -> Bool = { [weak self] in
            (resident ? self?.residentCommandSubmissionRevision : self?.commandSubmissionRevision) == submissionRevision
        }
        let commandSelection = selectedTabIDs
        let commandSpace = activeSpaceID
        let commandProfile = activeProfileID
        let commandTab = currentTabID
        let sourcePeek = activePeek
        let commandPeek = newTab ? nil : sourcePeek
        let commandBrowser = currentBrowser
        let commandPage = selectedNativePage()
        let isOriginal: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  self.canOwnDownloadDialog(for: commandProfile),
                  self.activeSpaceID == commandSpace, self.activeProfileID == commandProfile,
                  self.currentTabID == commandTab, self.activePeek === sourcePeek,
                  self.currentBrowser === commandBrowser, self.selectedNativePage() === commandPage,
                  commandPage?.isClosed != true else { return false }
            if resident { return self.showsStartPage }
            guard window.isVisible, !window.isMiniaturized,
                  window.attachedSheet == nil || self.commandBar?.ownsAttachedSheet == true else { return false }
            if inSidebar && (self.libraryView != nil || self.sidebarPresentation == .hidden
                || self.nativeFullscreenTabID != nil) { return false }
            if let id = commandTab {
                return !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                    && !self.store.retiringTabIDs.contains(id)
                    && self.store.state.tabs.contains { $0.id == id && $0.profileID == commandProfile && $0.archivedAt == nil }
            }
            return true
        }
        let historyExcludedURL = currentBrowser?.url?.absoluteString
            ?? store.state.tabs.first(where: { $0.id == commandTab })?.url
        let seedURL = newTab || WhatsNewPage.matches(historyExcludedURL ?? "") ? nil : historyExcludedURL
        let typedItems = currentSidebarMenuItems
        let typedCommands = commandBarTypedCommands(items: typedItems, profileID: commandProfile)
        if resident { residentTypedCommands = (typedItems, typedCommands) }
        let typedSnapshot: () -> (items: [SidebarItemReference]?, commands: [CommandBarTypedCommand]) = { [weak self] in
            resident ? self?.residentTypedCommands ?? (nil, []) : (typedItems, typedCommands)
        }
        let panel = CommandBar(parent: window,
            tabs: commandBarTabs(profileID: commandProfile, excluding: commandTab),
            history: commandBarHistory(profileID: commandProfile),
            historyRevision: store.historyRevision,
            historyExcludedURL: historyExcludedURL,
            spaces: commandBarSpaceActions(), folders: commandBarFolderActions(), favoriteAction: favoriteAction, folderMoves: folderMoves, favoriteRename: favoriteRenameAction,
            documents: { [weak self] in self?.commandBarDocuments(profileID: commandProfile) ?? [] },
            typedCommands: typedCommands, currentURL: seedURL,
            profilePath: store.independentEngineProfilePath(for: commandProfile), page: commandPage, nativeWindow: nativeBinding,
            sidebarAnchor: inSidebar ? sidebar.keyboardSearchAnchor : addressAnchor,
            addressOnly: addressAnchor != nil,
            currentPageTitle: currentBrowser?.title ?? store.state.tabs.first(where: { $0.id == commandTab })?.title,
            initialEdit: initialEdit,
            extensionDisposition: isPopupWindow && newTab ? nil : (newTab ? .newForegroundTab : .currentTab),
            theme: windowPaletteTheme, contentAppearance: resident ? nil : rootView.palette.contentAppearance, resident: resident)
        panel.isOwnerValid = isOriginal
        panel.tabCaption = { [weak self] tab in self?.commandBarTabCaption(tab)
            ?? .switchToTab }
        let canPerformTyped: (CommandBarTypedCommand) -> Bool = { [weak self] command in
            guard isOriginal(), let self, submissionIsCurrent(),
                  typedSnapshot().commands.contains(command) else { return false }
            return self.typedCommandIsAvailable(command, items: typedSnapshot().items, profileID: commandProfile)
        }
        panel.canPerformTypedCommand = canPerformTyped
        panel.onPerformTypedCommand = { [weak self] command in
            guard let self, self.commandBar == nil, canPerformTyped(command),
                  let action = self.prepareTypedCommand(command, items: typedSnapshot().items, profileID: commandProfile),
                  action() else { NSSound.beep(); return }
        }
        if PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.setAllTabAudioMuted(_:in:))) {
            panel.onMuteAllTabs = { [weak self, weak window] muted in
                guard let self, let window, isOriginal(), self.commandBar == nil,
                      submissionIsCurrent(),
                      self.window === window, window.isKeyWindow, NSApp.isActive,
                      window.attachedSheet == nil,
                      PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.setAllTabAudioMuted(_:in:))) else { return false }
                return PCNativeBrowserApplication.setAllTabAudioMuted(muted, in: window)
            }
        }
        let extensionBinding = nativeBinding
        let extensionCandidates: () -> [PCNativeExtensionAction] = { [weak self, weak extensionBinding, weak commandPage] in
            guard let self, let binding = extensionBinding, let page = commandPage,
                  isOriginal(), self.nativeBinding === binding, !page.isClosed else { return [] }
            return binding.extensionActions(for: page)
        }
        panel.extensionLaunchActions = extensionCandidates
        panel.onLaunchExtension = { [weak self, weak extensionBinding, weak commandPage] action in
            guard let self, let binding = extensionBinding, let page = commandPage,
                  isOriginal(), self.commandBar == nil, self.nativeBinding === binding,
                  !page.isClosed else { return false }
            return binding.executeExtensionAction(action, for: page)
        }
        panel.onCopyText = { [weak self, weak panel, weak commandBrowser] text in
            guard let self, let panel, self.presentsCommandBar(panel), isOriginal(), self.currentTabID == commandTab else { return }
            let pageURL = commandBrowser?.url?.absoluteString
                ?? self.store.state.tabs.first(where: { $0.id == commandTab })?.url
            let upsell = SuperCopyUpsell()
            let shortcut = KeyboardShortcuts.shared.activeShortcut(for: "copyCurrentURL:")
            guard let shortcut, let message = upsell.message(copied: text, pageURL: pageURL, shortcut: shortcut) else { return }
            if self.showToast(.superCopyUpsell(shortcut: shortcut.display, message: message)) != nil { upsell.recordShown() }
        }
        let canPerformFavorite: (CommandBarFavoriteAction) -> Bool = { [weak self] action in
            guard isOriginal(), let self, submissionIsCurrent(),
                  action == favoriteAction, action.isCurrent(in: self.store.state),
                  self.selectedTabIDs == commandSelection, self.spaceCommandsAvailable,
                  self.activePeek == nil, !self.isPrivateBrowsing,
                  !favoriteOwners.isEmpty, favoriteOwners.allSatisfy({ $0() }) else { return false }
            return true
        }
        panel.canPerformFavorite = canPerformFavorite
        panel.onPerformFavorite = { [weak self, weak window] action in
            guard let self, let window, self.commandBar == nil, canPerformFavorite(action),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            do {
                guard try self.store.performFavoriteAction(action) else { return }
                self.render(self.store.state)
            } catch { showError(error) }
        }
        let canMoveToFolder: (CommandBarFolderMove) -> Bool = { [weak self] move in
            guard isOriginal(), let self, submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, self.focusedTabID == folderMoveFocus,
                  self.spaceCommandsAvailable, self.activePeek == nil,
                  move.source == folderMoveSource, folderMoves.contains(move),
                  self.store.state.tabs.first(where: { $0.id == commandTab })?.folderID != move.folder.folderID,
                  move.isCurrent(in: self.store.state), folderMoveOwners?() == true,
                  move.tabIDs.allSatisfy({ id in
                      !self.store.retiringTabIDs.contains(id)
                          && self.ownership.claimSnapshot(id) == folderMoveClaims[id]
                          && folderMoveClaims[id]?.transfer == nil
                  }), self.store.state.splitLayouts.filter({ move.source.groupIDs.contains($0.id) }).allSatisfy({ group in
                      group.tabIDs.allSatisfy { folderMoveClaims[$0]?.owner == nil || folderMoveClaims[$0]?.owner == self.presentationID }
                  }) else { return false }
            return true
        }
        let copyDestinations: (CommandBarFolderMove) -> SidebarCopySources? = { [weak self] move in
            guard canMoveToFolder(move), let self else { return nil }
            let originals = move.tabIDs.compactMap { id in self.store.state.tabs.first { $0.id == id } }
            guard originals.count == move.tabIDs.count,
                  let urls = self.resolveSidebarCopyDestinations?(originals), urls.validates(originals) else { return nil }
            return urls
        }
        panel.canCopyToFolder = { copyDestinations($0) != nil }
        var folderCopyConsumed = false
        panel.onCopyToFolder = { [weak self, weak window] move in
            guard let self, let window, !folderCopyConsumed, self.commandBar == nil,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  let urls = copyDestinations(move) else { return }
            folderCopyConsumed = true
            do {
                guard let copy = try self.store.copyCommandBarItemsToFolder(move, destinations: urls.destinations, documents: urls.documents,
                    creation: self.creationProvenance(activeTabID: self.currentTabID)) else { return }
                self.render(self.store.state)
                self.openDuplicatedChildren(copy.openTabIDs, spaceID: move.folder.spaceID,
                    profileID: move.source.profileID, window: window, originatingSpaceID: commandSpace)
                if let item = copy.roots.first {
                    self.showSidebarMoveNotice(item: item, space: move.folder.spaceID, profile: move.source.profileID,
                        message: "Copied to folder. Click to go there.")
                }
            } catch { showError(error) }
        }
        panel.canMoveToFolder = canMoveToFolder
        var folderMoveConsumed = false
        panel.onMoveToFolder = { [weak self, weak window] move in
            guard let self, let window, !folderMoveConsumed, self.commandBar == nil,
                  canMoveToFolder(move), PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            folderMoveConsumed = true
            do {
                guard try self.store.performCommandBarFolderMove(move) else { return }
                self.render(self.store.state); self.requestNativeSelection()
                self.showToast(.pinnedToFolder(move.folder.name), at: .window)
            } catch { showError(error) }
        }
        let canRenameFavorite: (CommandBarFavoriteRenameAction) -> Bool = { [weak self, weak renameBinding, weak renameNote, weak renameEasel] action in
            guard isOriginal(), let self, let renameBinding, action == favoriteRenameAction,
                  commandTab == action.tab.id, self.nativeBinding === renameBinding,
                  !renameBinding.isPrivateBrowsing, renameBinding.browsingContextKind != .mixed,
                  submissionIsCurrent(),
                  self.favoriteRename == nil, !self.folderUndo.isBusy, !self.sidebar.isEditingTitle,
                  !self.isPrivateBrowsing, self.activePeek == nil, self.spaceCommandsAvailable,
                  let tab = action.currentTab(in: self.store.state, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, selectedTabIDs: self.selectedTabIDs),
                  self.canPerformSidebarTabAction(tab, closing: false),
                  hadRenameNote == (self.noteEditors[tab.id]?.editor != nil), self.noteEditors[tab.id]?.editor === renameNote,
                  hadRenameEasel == (self.easelEditors[tab.id]?.editor != nil), self.easelEditors[tab.id]?.editor === renameEasel else { return false }
            return true
        }
        panel.canRenameFavorite = canRenameFavorite
        panel.onRenameFavorite = { [weak self] action in
            guard let self, self.commandBar == nil, canRenameFavorite(action),
                  let tab = action.currentTab(in: self.store.state, spaceID: self.activeSpaceID,
                      profileID: self.activeProfileID, selectedTabIDs: self.selectedTabIDs) else { return }
            _ = self.prepareFavoriteRename(tab, selectOriginal: false)?()
        }
        panel.canFocusSpace = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(spaces: self.store.state.spaces, profiles: self.store.state.profiles) else { return false }
            return self.canSelectSpace(target.spaceID, profileID: target.profileID)
        }
        panel.onFocusSpace = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(spaces: self.store.state.spaces, profiles: self.store.state.profiles) else { return }
            _ = self.selectSpaceFromUser(target.spaceID, profileID: target.profileID)
        }
        panel.canOpenFolder = { [weak self] target in
            guard isOriginal(), let self, self.activePeek == nil,
                  target.isCurrent(in: self.store.state, profileID: commandProfile) else { return false }
            return self.canSelectSpace(target.spaceID, profileID: target.profileID)
        }
        panel.onOpenFolder = { [weak self] target in
            guard isOriginal(), let self,
                  target.isCurrent(in: self.store.state, profileID: commandProfile) else { return }
            _ = self.revealSidebarItem(target.reveal.item, spaceID: target.spaceID, profileID: target.profileID)
        }
        if inSidebar {
            panel.onSidebarMove = { [weak self] delta in
                guard isOriginal(), let self else { return }
                self.sidebarKeyboardCursor?.move(delta, in: self.sidebarKeyboardItems().map(\.id))
                self.reconcileSidebarKeyboardFocus(scroll: true)
            }
            panel.onSidebarQueryState = { [weak self] browsing in
                guard isOriginal(), let self else { return }
                self.sidebarKeyboardBrowsing = browsing
                self.reconcileSidebarKeyboardFocus()
            }
            panel.onSidebarCommit = { [weak self, weak panel] in
                guard isOriginal(), let self else { return }
                let target = self.sidebarKeyboardItems().first { $0.id == self.sidebarKeyboardCursor?.highlightedID }
                if let folder = target?.folder {
                    do {
                        guard try self.store.setFolderExpanded(!folder.isExpanded, expected: folder,
                                                               profileID: commandProfile) else { NSSound.beep(); return }
                        self.reconcileSidebarKeyboardFocus(scroll: true)
                    } catch {
                        panel?.dismiss()
                        showError(error)
                    }
                    return
                }
                panel?.dismiss()
                guard isOriginal(), self.canFocusSidebar, let selection = target?.selection else { return }
                if selection.tabIDs == self.selectedTabIDs { self.requestNativeSelection() }
                else { self.selectRecentItem(selection) }
            }
        }
        panel.mayRestoreOriginal = { [weak self] view in
            guard isOriginal(), let self else { return false }
            let find = self.visibleFind.flatMap { self.isCurrentFind($0) && !self.findHost.isHidden ? self.findHost : nil }
            let peek = self.activePeek.flatMap { $0.view.isHidden ? nil : $0.view }
            return ContentFocusRequest.returnsToSaved(view, find: find,
                                                      content: peek ?? self.currentTabID.flatMap { self.panes[$0] })
        }
        panel.restorePageFocus = { [weak self] in
            guard isOriginal(), let self else { return }
            if let find = self.visibleFind, self.isCurrentFind(find), !self.findHost.isHidden,
               self.window?.makeFirstResponder(self.findField) == true { return }
            if let browser = self.currentBrowser { self.window?.makeFirstResponder(browser.nativePage?.nativeView ?? browser); return }
            if !resident, self.activePeek == nil, self.currentTabID == nil, self.showsStartPage {
                self.residentCommandBar?.focusResident(); return
            }
            guard self.activePeek == nil, let id = self.currentTabID, self.renderedPaneIDs.contains(id) else { return }
            if let editor = self.noteEditors[id]?.editor { editor.focusContent() }
            else if let editor = self.easelEditors[id]?.editor { editor.focusContent() }
            else if self.panes[id]?.showsBlank == true { self.window?.makeFirstResponder(nil) }
        }
        panel.onNavigate = { [weak self] input in
            guard isOriginal(), let self else { return }
            if let peek = commandPeek { self.resolvePeekInput(input, peek: peek) }
            else if newTab || commandTab == nil { self.openInput(input) }
            else { self.resolveInput(input, replacing: commandTab) }
        }
        panel.onSearchNavigation = { [weak self] navigation in
            guard isOriginal(), let self else { return }
            if self.isPopupWindow && newTab { return }
            if let peek = commandPeek { peek.browser.loadSearchNavigation(navigation) }
            else { self.openSearchNavigation(navigation, replacing: newTab ? nil : commandTab) }
        }
        panel.onSelectTab = { [weak self] id in
            guard isOriginal(), let self,
                  self.commandBarTabs(profileID: commandProfile, excluding: commandTab).contains(where: { $0.id == id }) else { return }
            self.selectTab(id)
        }
        let canSplit: (UUID?) -> Bool = { [weak self] target in
            guard isOriginal(), let self, submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, let commandTab,
                  self.activePeek == nil, !self.isPopupWindow, self.libraryView == nil,
                  self.nativeFullscreenTabID == nil, !self.promotingPeek,
                  self.peekRetirementParents.isEmpty,
                  commandSelection.allSatisfy({ id in
                      self.ownership.canUse(id, owner: self.presentationID)
                          && !self.store.retiringTabIDs.contains(id)
                          && !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                  }), commandSelection.contains(commandTab) else { return false }
            if let target {
                guard self.visibleTabs.contains(where: { $0.id == target })
                        || self.splitInsertionTabs(profileID: commandProfile).contains(where: { $0.id == target }),
                      self.ownership.canUse(target, owner: self.presentationID) || self.canMovePageHere(target),
                      !self.transferringTabIDs.contains(target), !self.closingTabIDs.contains(target),
                      !self.modelRetirementIDs.contains(target), !self.store.retiringTabIDs.contains(target) else { return false }
                if commandSelection.contains(target) { return true }
            }
            return commandSelection.count < 4
        }
        let commitSplit: (PCNativeSearchNavigation?, UUID?) -> Void = { [weak self, weak window] navigation, existingID in
            guard let self, let window, let commandTab, self.commandBar == nil,
                  canSplit(existingID), PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            if let navigation {
                guard navigation.profilePath == self.store.independentEngineProfilePath(for: commandProfile) else { return }
            } else if existingID == nil { return }
            let id = existingID ?? UUID()
            if let navigation { self.pendingSearchNavigations[id] = navigation }
            var inserted = false
            var homeIDs: [UUID: UUID] = [:]
            self.performWindowCommand(selectNativePage: false) {
                guard let homes = self.store.commandBarSplitHomes(after: commandTab, expectedSelection: commandSelection,
                          tabID: id, isNew: existingID == nil) ?? (commandSelection.contains(id) ? [] : nil),
                      let plan = self.splitHomePlan(homes) else { return }
                homeIDs = plan.ids
                inserted = self.store.insertCommandBarSplit(after: commandTab,
                    expectedSelection: commandSelection, tabID: id, newURL: navigation?.url,
                    creation: self.creationProvenance(activeTabID: commandTab),
                    savedHomeIDs: plan.ids, documents: plan.documents)
                if inserted && existingID == nil { self.presentation.recordCreation(id, state: self.store.state) }
            }
            guard inserted, self.selectedTabIDs.contains(id) else {
                self.pendingSearchNavigations.removeValue(forKey: id); return
            }
            self.openSplitHomes(homeIDs, profileID: commandProfile, originatingSpaceID: self.activeSpaceID)
            self.focusedTabID = id
            self.render(self.store.state); self.requestNativeSelection()
            self.focusSelectedLocalContent()
        }
        panel.canSplitSelection = canSplit
        panel.onSplitNavigation = { navigation in commitSplit(navigation, nil) }
        panel.onSplitTab = { [weak self] id in
            guard let self, self.canMovePageHere(id), canSplit(id) else { commitSplit(nil, id); return }
            _ = self.movePagesHere([id]) { guard canSplit(id) else { return false }; commitSplit(nil, id); return true }
        }
        panel.onSplitInput = { [weak self, weak commandPage] input in
            guard let self, canSplit(nil) else { return }
            let originalURL = commandBrowser?.url
            self.pendingCommandSplitBrowser = commandBrowser
            self.pendingCommandSplitValidation = { canSplit(nil) && commandBrowser?.url == originalURL }
            PCNativeBrowserApplication.resolveSearchInput(input,
                profilePath: self.store.independentEngineProfilePath(for: commandProfile), page: commandPage, window: self.nativeBinding) { [weak self] navigation, error in
                MainActor.assumeIsolated {
                    guard let self, canSplit(nil), self.commandBar == nil,
                          commandBrowser?.url == originalURL else { return }
                    self.pendingCommandSplitValidation = nil; self.pendingCommandSplitBrowser = nil
                    guard let navigation else {
                        self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.")
                        return
                    }
                    commitSplit(navigation, nil)
                }
            }
        }
        let backgroundOwner: () -> Bool = { [weak self, weak panel] in
            guard isOriginal(), let self, let panel, self.presentsCommandBar(panel),
                  submissionIsCurrent(),
                  self.selectedTabIDs == commandSelection, !self.isPopupWindow,
                  !self.store.isProfileRemovalPending(commandProfile),
                  self.transferringTabIDs.isEmpty else { return false }
            return true
        }
        let background: (PCNativeSearchNavigation, @escaping () -> Bool, @escaping (String?) -> Void) -> Void = { [weak self] request, valid, complete in
            guard let self, backgroundOwner(), valid() else { complete("The original search owner changed."); return }
            self.openCommandBarBackground(request, sourcePage: commandPage, spaceID: commandSpace,
                profileID: commandProfile, selection: commandSelection,
                validate: { backgroundOwner() && valid() }, completion: complete)
        }
        let classifyBackground: (String, @escaping () -> Bool, @escaping (String?) -> Void) -> Void = { [weak self, weak commandPage] input, valid, complete in
            guard let self, backgroundOwner(), valid() else { complete("The original search owner changed."); return }
            PCNativeBrowserApplication.resolveSearchInput(input,
                profilePath: self.store.independentEngineProfilePath(for: commandProfile), page: commandPage, window: self.nativeBinding) { navigation, error in
                MainActor.assumeIsolated {
                    guard backgroundOwner(), valid() else { complete("The original search owner changed."); return }
                    guard let navigation else { complete(error?.localizedDescription ?? "This input cannot open."); return }
                    background(navigation, valid, complete)
                }
            }
        }
        panel.onBackgroundNavigation = background
        panel.onBackgroundInput = classifyBackground
        panel.onBackgroundTab = { [weak self] id, valid, complete in
            guard let self, backgroundOwner(), valid(),
                  let original = self.commandBarTabs(profileID: commandProfile, excluding: commandTab).first(where: { $0.id == id }),
                  !InternalPage.isInternal(original.url) else {
                complete("This tab cannot open as a new background page."); return
            }
            let stillOriginal: () -> Bool = { [weak self] in
                guard let self, valid(), backgroundOwner() else { return false }
                return self.commandBarTabs(profileID: commandProfile, excluding: commandTab).contains {
                    $0.id == original.id && $0.spaceID == original.spaceID && $0.profileID == original.profileID && $0.url == original.url
                }
            }
            classifyBackground(original.url, stillOriginal, complete)
        }
        panel.onManagePasswords = { [weak self] in if isOriginal() { self?.showPasswordManager() } }
        panel.onOpenDocument = { [weak self] document in
            guard isOriginal(), let self else { return }
            switch document.kind {
            case .note: self.openNote(id: document.id, title: document.title)
            case .easel: self.openEasel(id: document.id, title: document.title)
            }
        }
        panel.onManageSiteSearch = { [weak self] in
            guard isOriginal(), let self, !self.isPrivateBrowsing else { return }
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            self.performWindowCommand {
                let id = self.store.open("parc://settings/searchEngines", creation: creation)
                self.presentation.recordCreation(id, state: self.store.state)
            }
        }
        panel.onSearchSettings = { [weak self] in if isOriginal() { self?.showSettings(pane: .spaces) } }
        panel.onDismiss = { [weak self, weak panel] in
            guard let self else { return }
            if resident {
                if self.residentCommandBar === panel { self.residentCommandBar = nil; self.scheduleStartPageRefresh() }
                return
            }
            guard self.commandBar === panel else { return }
            self.commandBar = nil
            self.commandBarRecentPages?.query.invalidate(); self.commandBarRecentPages = nil
            if inSidebar {
                self.sidebarKeyboardCursor = nil; self.sidebarKeyboardBrowsing = false
                self.sidebar.highlightItemForKeyboard(nil, scrollToHighlight: false)
                self.sidebar.setKeyboardSearchActive(false)
            }
            self.refreshSidebarPointer()
        }
        return panel
    }
    private func openCommandBarBackground(_ navigation: PCNativeSearchNavigation, sourcePage: PCNativePage?,
        spaceID: UUID, profileID: UUID, selection: [UUID], validate: @escaping () -> Bool,
        completion: @escaping (String?) -> Void) {
        guard validate(), let window, !isClosing, !wholeWindowClose, !windowClosePending,
              navigation.profilePath == store.independentEngineProfilePath(for: profileID) else {
            completion("The original search owner changed."); return
        }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        pendingSearchNavigations[id] = navigation
        var inserted = false
        performWindowCommand(selectNativePage: false) {
            inserted = store.insertCommandBarBackground(tabID: id, url: navigation.url,
                spaceID: spaceID, profileID: profileID, expectedSelection: selection, creation: creation)
            if inserted { presentation.recordCreation(id, state: store.state) }
        }
        guard inserted, let tab = store.state.tabs.first(where: { $0.id == id }),
              ownership.claim(id, owner: presentationID) else {
            pendingSearchNavigations.removeValue(forKey: id)
            completion("The original destination changed."); return
        }
        let pane = makePane(tab)
        pane.frame = pageHost.bounds; panes[id] = pane; parkedPages.addSubview(pane)
        pane.layoutSubtreeIfNeeded()
        let browser = PCBrowserView(frame: pane.contentBounds, profilePath: navigation.profilePath)
        browser.delegate = self
        browsers[id] = browser; browserProfiles[id] = profileID; liveTabModels[id] = tab
        pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
        requestedURLs[id] = tab.url
        let admitted = browser.loadBackgroundSearchNavigation(navigation, sourcePage: sourcePage, validateOwner: { [weak self, weak browser, weak window] in
            guard let self, let browser, let window, validate(), self.window === window,
                  self.browsers[id] === browser, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.ownership.canUse(id, owner: self.presentationID),
                  !self.closingTabIDs.contains(id), !self.store.retiringTabIDs.contains(id),
                  !self.modelRetirementIDs.contains(id), !self.transferringTabIDs.contains(id) else { return false }
            return self.store.state.tabs.contains { $0.id == id && $0.spaceID == spaceID && $0.profileID == profileID && $0.archivedAt == nil }
        }) { [weak self, weak browser] success, error in
            MainActor.assumeIsolated {
                guard let self, let browser, self.browsers[id] === browser else { completion("The background page owner closed."); return }
                if success { self.pendingSearchNavigations.removeValue(forKey: id) }
                else {
                    self.failures[id] = error?.localizedDescription ?? "The background page could not open."
                    self.requestedURLs.removeValue(forKey: id)
                }
                self.attachOwnedPages()
                completion(success ? nil : self.failures[id])
            }
        }
        if !admitted {
            failures[id] = "The background page could not open. Select it to retry the original request."
            requestedURLs.removeValue(forKey: id)
            completion(failures[id])
        }
        attachOwnedPages()
    }

    private func resolvePeekInput(_ input: String, peek: PeekController) {
        let revision = UUID(); inputRevisions[peek.identity] = revision
        let originalURL = peek.browser.url
        PCNativeBrowserApplication.resolveSearchInput(input, profilePath: peek.page.profilePath, page: peek.page) { [weak self, weak peek] navigation, error in
            MainActor.assumeIsolated {
                guard let self, let peek, self.activePeek === peek,
                      self.peeks[peek.page.identifier] === peek, !peek.page.isClosed,
                      self.inputRevisions[peek.identity] == revision, peek.browser.url == originalURL else { return }
                self.inputRevisions.removeValue(forKey: peek.identity)
                if let navigation { peek.browser.loadSearchNavigation(navigation) }
                else if let error, let window = self.window { ParcDialog.inform(in: window, .init(error: error)) }
            }
        }
    }

    func toggleSidebar() {
        if libraryView != nil { closeLibrary(); return }
        setSidebarPresentation(sidebarPresentation == .locked ? .hidden : .locked)
    }
    private func setSidebarPresentation(_ requested: SidebarPresentation, allowsMotion: Bool = true) {
        var presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)
        if sidebarResize != nil { sidebarResizeRegion.cancelInteraction() }
        if presentation == .hidden, spaceCreation != nil {
            cancelSpaceCreation(restoreFocus: false)
            presentation = PendingSplitPaneSidebarRule.presentation(for: requested, pendingPane: pendingPaneHoldsSidebar)
        }
        if presentation == .hidden {
            SidebarPlusMenuController.dismiss(in: window)
            if let open = siteControlCenter, !open.isDetached, open.isAnchored(to: sidebar.pageControlsAnchor) {
                dismissSiteControlCenter()
            }
        }
        navigationHistory?.dismiss()
        sidebarPreviews?.dismiss()
        guard !isPopupWindow, !isClosing, libraryView == nil, nativeFullscreenTabID == nil else { return }
        if presentation == .floating { sidebarHoverActive = true }
        guard sidebarPresentation != presentation else { return }
        if presentation == .hidden, commandBar?.isSidebarSession == true { commandBar?.dismiss() }
        let previous = sidebarPresentation
        let moveFocus = presentation == .hidden && sidebarOwnsFirstResponder
        let animated = allowsMotion && window?.isVisible == true && window?.isMiniaturized != true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !rootView.inLiveResize
        if animated {
            let transition = SidebarTransition(from: previous, to: presentation)
            preparingSidebarMotion = true
            sidebarMotionVisible = true
            sidebarFloatingSurface = transition.keepsFloatingSurface
            sidebarRevealsAnchored = transition.revealsAnchored
            sidebarChromePass = .preparation
            layoutChrome()
            sidebarContainer.preparesFloatingDock = transition.docksFloatingSurface
            sidebarChromePass = .geometry
            sidebarMotion.animate(layoutRoot: rootView, views: [sidebarContainer, pageHost, pageShadow, findHost, loadingIndicator],
                                  style: transition.style, flushesPreviousLayout: transition.flushesPreparation) {
                sidebarPresentation = presentation
                layoutChrome()
            } completion: { [weak self] in
                guard let self else { return }
                self.sidebarMotionVisible = false
                self.sidebarFloatingSurface = false
                self.refreshPreviewHover()
                self.layoutChrome()
                if self.sidebarPresentation != .hidden { self.sidebar.retestPointer() }
                if self.sidebarPresentation == .floating { self.refreshSidebarPointer() }
            }
            sidebarChromePass = .full
            refreshPreviewHover()
            sidebarRevealsAnchored = false
            preparingSidebarMotion = false
        } else {
            settleSidebarMotion()
            sidebarPresentation = presentation
            layoutChrome()
        }
        if presentation != .hidden { refreshSidebarBanners() }
        if moveFocus { if window?.isKeyWindow == true { requestNativeSelection() } else { window?.makeFirstResponder(nil) } }
    }
    private func sidebarResizeChanged(_ state: NSGestureRecognizer.State, translationX: CGFloat, velocityX: CGFloat) {
        switch state {
        case .began:
            guard sidebarResize == nil, !sidebarMotion.isAnimating, !isClosing, libraryView == nil, !isPopupWindow,
                  nativeFullscreenTabID == nil, sidebarPresentation != .hidden else { return }
            sidebarPreviews?.dismiss()
            sidebarResize = SidebarResizeGesture(width: windowSidebarWidth.width, locked: sidebarPresentation == .locked)
            isSidebarResizing = true
        case .changed:
            guard var gesture = sidebarResize else { return }
            let change = gesture.change(translationX: Double(translationX), velocityX: Double(velocityX))
            sidebarResize = gesture
            sidebarResizeRegion.present(change.events)
            guard change.widthChanged else { return }
            sidebarChromePass = .geometry
            layoutChrome()
            sidebarChromePass = .full
        case .ended, .cancelled, .failed:
            guard let gesture = sidebarResize else { return }
            let completion: SidebarResizeGesture.Completion = state == .ended ? .ended : state == .cancelled ? .cancelled : .failed
            let commit = gesture.end(completion, translationX: Double(translationX))
            sidebarResize = nil
            if let lastUsed = windowSidebarWidth.end(commit, completion) { store.updateSettings { $0.sidebarWidth = lastUsed } }
            isSidebarResizing = false
            if commit.collapses { setSidebarPresentation(.hidden, allowsMotion: false) } else { layoutChrome() }
            refreshSidebarPointer()
        default: break
        }
    }
    private func settleSidebarMotion() {
        sidebarMotion.cancel()
        sidebarMotionVisible = false
        sidebarFloatingSurface = false
        refreshPreviewHover()
    }
    private var sidebarOwnsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        if responder === sidebar || responder.isDescendant(of: sidebar) { return true }
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView { return field.isDescendant(of: sidebar) }
        return false
    }
    private var sidebarHoverPresentation: SidebarHoverZones.Presentation {
        switch sidebarPresentation {
        case .locked: .locked
        case .floating: .floating
        case .hidden: .hidden
        }
    }
    private var paneTopBarDisplayed: Bool {
        PaneTopBarAdmission.displayed(
            toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
            inSplit: activeSplitLayout != nil || splitInsertion != nil,
            isPopup: isPopupWindow,
            hasLibrary: libraryView != nil,
            tabFullscreen: nativeFullscreenTabID != nil)
    }
    private var sidebarHoverShowsToolbar: Bool {
        !isPopupWindow && libraryView == nil && BrowserToolbarPreferences.shared.state.isVisible
    }
    private func sidebarHoverRegions(_ info: SidebarHoverInfo) -> [SidebarHoverRegion: NSRect] {
        guard let window, libraryView == nil, !isPopupWindow, !isClosing, nativeFullscreenTabID == nil else { return [:] }
        let bounds = rootView.bounds
        let trafficLight = SidebarHoverZones.trafficLightHeight(windowMaxY: Double(window.frame.maxY),
            screenHeight: Double(window.screen?.frame.height ?? 0), menuBarHeight: Double(NSApp.mainMenu?.menuBarHeight ?? 0))
        let rects = SidebarHoverZones.rects(size: bounds.size, presentation: sidebarHoverPresentation, sidebarWidth: Double(sidebarLayoutWidth),
                                            showingToolbar: sidebarHoverShowsToolbar, trafficLightHeight: trafficLight, info: info)
        return rects.mapValues { NSRect(x: $0.minX, y: bounds.height - $0.maxY, width: $0.width, height: $0.height) }
    }
    private func refreshSidebarHoverZones() {
        let key: [CGFloat] = [rootView.bounds.width, rootView.bounds.height, sidebarLayoutWidth,
            sidebarPresentation == .locked ? 0 : sidebarPresentation == .floating ? 1 : 2,
            libraryView == nil && !isPopupWindow && nativeFullscreenTabID == nil ? 1 : 0, sidebarHoverShowsToolbar ? 1 : 0]
        guard sidebarHoverLayoutKey != key else { return }
        sidebarHoverLayoutKey = key
        sidebarHover.setNeedsRefresh()
    }
    private func applySidebarHover() {
        guard libraryView == nil, !isPopupWindow, !isClosing, nativeFullscreenTabID == nil, !isSidebarResizing else { return }
        let decision = SidebarHoverPresentationRule.decide(stored: sidebarHoverActive, presentation: sidebarHoverPresentation,
            info: sidebarHover.info, fullscreen: window?.styleMask.contains(.fullScreen) == true,
            includesTopLeft: !sidebarHoverShowsToolbar, isKeyWindow: window?.isKeyWindow == true,
            ownerDefers: navigationHistory != nil || commandBar != nil || themePopover != nil || siteControlCenterDefers
                || frameCrank != nil
                || spaceIconPicker != nil || SidebarPlusMenuController.isShown(in: window)
                || window?.attachedSheet != nil,
            interactionDefers: sidebarOwnsFirstResponder || sidebarPointerDown || sidebarPreviews?.holdsSidebarOpen == true
                || menuTrackingDepth > 0)
        sidebarHoverActive = decision.isActive
        switch decision.action {
        case .keep: break
        case .reveal: setSidebarPresentation(.floating)
        case .dismiss: setSidebarPresentation(.hidden)
        }
    }
    private func refreshSidebarPointer() {
        sidebarHover.refresh()
        applySidebarHover()
    }
    private var navigationPage: PCNativePage? {
        guard !isClosing, !wholeWindowClose, !windowClosePending, libraryView == nil,
              let page = selectedNativePage(), page.nativeView.window === window, !page.isClosed else { return nil }
        return page
    }
    func canPerformNavigation(_ action: PCNativeNavigationAction) -> Bool {
        if let page = navigationPage { return page.canPerformNavigation(action) }
        return action == .reload && !isClosing && !wholeWindowClose && !windowClosePending &&
            libraryView == nil && activePeek == nil && window?.attachedSheet == nil &&
            currentTabID.flatMap { id in store.state.tabs.first { $0.id == id } }
                .map { InternalPage.isInternal($0.url) } == true
    }
    private func performNavigation(_ action: PCNativeNavigationAction) {
        navigationHistory?.dismiss()
        if let page = navigationPage {
            if page.performNavigation(action, inNewTab: false), action != .stop { navigationRequested(on: page) }
        }
        else if action == .reload, canPerformNavigation(action), let id = currentTabID { reloadTab(id) }
    }
    private func navigationRequested(on page: PCNativePage) {
        guard navigationPage === page, let id = currentTabID, browsers[id]?.nativePage === page else { return }
        failures.removeValue(forKey: id)
        refreshPagePresentation(id)
    }
    private var developerReloadPage: PCNativePage? {
        guard let page = navigationPage, let host = page.developerModeSiteHost,
              DeveloperModePreferences.shared.isEnabled(host: host) else { return nil }
        return page
    }
    private var reloadAction: PCNativeNavigationAction {
        developerReloadPage != nil && DeveloperReloadPreference.state == .forceReload ? .reloadBypassingCache : .reload
    }
    private func showReloadOptions(from anchor: NSView) {
        guard let page = developerReloadPage, anchor.window === window else { return }
        let browser = currentBrowser
        let isOriginal: () -> Bool = { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.developerReloadPage === page
        }
        let menu = ReloadOptionsMenu.make(state: DeveloperReloadPreference.state,
                                          canReload: page.canPerformNavigation(.reload),
                                          canForceReload: page.canPerformNavigation(.reloadBypassingCache),
                                          canClearCookies: canPerformPageTool(.clearCookiesAndRefresh)) { [weak self, weak page, weak browser] choice in
            guard let self, let page, isOriginal() else { return }
            switch choice {
            case .reload, .forceReload:
                let action: PCNativeNavigationAction = choice == .reload ? .reload : .reloadBypassingCache
                DeveloperReloadPreference.state = choice == .reload ? .reload : .forceReload
                self.navigationHistory?.dismiss()
                if page.performNavigation(action, inNewTab: false) { self.navigationRequested(on: page) }
                self.refreshNavigationControls()
            case .clearCookies:
                guard let browser, self.currentBrowser === browser, browser.nativePage === page,
                      self.canPerformPageTool(.clearCookiesAndRefresh) else { return }
                _ = browser.performPageTool(.clearCookiesAndRefresh)
            }
        }
        ReloadOptionsMenu.present(menu, from: anchor)
    }
    func goBack() { performNavigation(.back) }
    func goForward() { performNavigation(.forward) }
    func reload() { performNavigation(.reload) }
    func forceReload() { performNavigation(.reloadBypassingCache) }
    func stopLoading() { performNavigation(.stop) }

    private func prepareNavigationInteraction(_ kind: NavigationControlKind) -> NavigationControlInteraction? {
        guard let page = navigationPage else {
            guard kind == .reload, canPerformNavigation(.reload), let id = currentTabID else { return nil }
            return NavigationControlInteraction(activate: { [weak self] alternate in
                guard let self, !alternate, self.currentTabID == id, self.navigationPage == nil,
                      self.canPerformNavigation(.reload) else { return }
                self.reloadTab(id)
            })
        }
        let action: PCNativeNavigationAction = kind == .back ? .back : kind == .forward ? .forward : page.loading ? .stop : reloadAction
        let snapshot = kind == .reload ? nil : page.navigationHistory(back: kind == .back)
        let isOriginal: () -> Bool = { [weak self, weak page] in
            guard let self, let page else { return false }
            return self.navigationPage === page
        }
        return NavigationControlInteraction(activate: { [weak self, weak page] alternate in
            guard isOriginal(), let page else { return }
            if kind != .reload, snapshot?.isValid != true { return }
            self?.navigationHistory?.dismiss()
            if page.performNavigation(action, inNewTab: alternate), !alternate, action != .stop {
                self?.navigationRequested(on: page)
            }
        }, showHistory: snapshot.map { snapshot in
            { [weak self, weak page] anchor in
                guard let self, let page, let window = self.window,
                      isOriginal(), snapshot.isValid, !snapshot.entries.isEmpty else { return }
                self.navigationHistory?.dismiss()
                self.sidebarPreviews?.dismiss(); self.tabSwitcher?.cancel()
                let history = NavigationHistoryController(page: page, snapshot: snapshot, window: window,
                    theme: self.windowPaletteTheme)
                history.stillSelected = isOriginal
                history.address = { WhatsNewPage.matches($0.absoluteString) ? nil : $0.absoluteString }
                history.onNavigate = { [weak self, weak page] in
                    if let page { self?.navigationRequested(on: page) }
                }
                history.onClose = { [weak self, weak history] in
                    guard let self, self.navigationHistory === history else { return }
                    self.navigationHistory = nil; self.refreshSidebarPointer()
                }
                self.navigationHistory = history
                history.show(from: anchor)
            }
        })
    }
    var hasSidebarCommandSelection: Bool { sidebar.hasCommandSelection }
    func prepareSidebarSelectionCommand(_ kind: SidebarSelectionCommandKind) -> SidebarSelectionCommandTarget? {
        sidebar.prepareSelectionCommand(kind)
    }

    var closeTabMenuTitle: String {
        if activePeek != nil { return "Close Peek" }
        if isPopupWindow { return "Close Window" }
        if isPrivateBrowsing { return "Close Tab" }
        return visibleTabs.first(where: { $0.id == currentTabID })?.kind == .today ? "Archive Tab" : "Close Tab"
    }
    var canCloseCurrentTab: Bool {
        guard !isClosing, !wholeWindowClose, !windowClosePending,
              window?.attachedSheet == nil else { return false }
        if isPopupWindow { return true }
        guard let id = currentTabID else { return false }
        return !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && !store.retiringTabIDs.contains(id)
    }
    private var reopenClosedStep: ClosedItemStep? {
        guard !isPopupWindow, !isPrivateBrowsing, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending,
              window?.attachedSheet == nil, activePeek == nil,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let step = closedItems.nextStep(in: store.state, restorable: { store.canUndoFolderDeletion($0) })
        else { return nil }
        switch step {
        case .items(let record):
            return record.tabIDs.allSatisfy({ id in
                !store.retiringTabIDs.contains(id) && !closingTabIDs.contains(id)
                    && !ownership.isClaimed(id) && browsers[id] == nil
            }) ? step : nil
        case .folder(let undo):
            let ids = Set(undo.tabs.map(\.id))
            return !folderUndo.isBusy && folderUndoContextAvailable && undo.documentsAreAvailable
                && ids.isDisjoint(with: store.retiringTabIDs) && ids.allSatisfy({ switcherCanUse($0) }) ? step : nil
        case .peek(let record):
            let parent = record.parentTabID
            return canUseOrMoveHere(parent) && !peeks.values.contains(where: { $0.parentTabID == parent }) ? step : nil
        }
    }
    var canRestoreClosedTab: Bool { reopenClosedStep != nil }
    private func prepareSidebarTabMute(_ expected: BrowserTab, audio: SidebarTabAudio) -> (() -> Bool)? {
        guard canPerformSidebarTabAction(expected, closing: false), let browser = browsers[expected.id],
              let page = browser.nativePage, !page.isClosed else { return nil }
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, let browser, let page, !used,
                  self.canPerformSidebarTabAction(expected, closing: false),
                  self.browsers[expected.id] === browser, browser.nativePage === page,
                  browser.window === self.window, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.toggleTabAudioMuted(_:))) else { return false }
            used = true
            return page.toggleTabAudioMuted(audio.lease)
        }
    }

    private func canPerformSidebarTabAction(_ expected: BrowserTab, closing: Bool) -> Bool {
        guard sidebarTabActionWindowAvailable,
              window?.isKeyWindow == true,
              expected.profileID == activeProfileID, visibleTabs.contains(expected),
              PageReparenting.rowAction(closing: closing, busy: !sidebarTabActionAvailable(expected.id),
                  usableHere: closing ? ownership.canUse(expected.id, owner: presentationID) : switcherCanUse(expected.id),
                  heldElsewhere: canMovePageHere(expected.id)) != nil else { return false }
        return !closing || retirementUnavailableReason?([expected.id]) == nil
    }

    private var sidebarTabActionWindowAvailable: Bool {
        !isPopupWindow && presentation.isReady && !isClosing && !wholeWindowClose
            && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && window?.attachedSheet == nil && !store.isProfileRemovalPending(activeProfileID)
    }

    private func sidebarTabActionAvailable(_ id: UUID) -> Bool {
        !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && !resolvingTransfers.contains(id)
            && transferRecoveries[id] == nil && !store.retiringTabIDs.contains(id)
    }

    private func sidebarRootsCloseAvailable(_ ids: Set<UUID>, movingHere: Bool = true) -> Bool {
        guard sidebarTabActionWindowAvailable, commandBar == nil, !ids.isEmpty,
              ids.allSatisfy({ id in
                  visibleTabs.contains { $0.id == id }
                      && PageReparenting.rowAction(closing: true, busy: !sidebarTabActionAvailable(id),
                          usableHere: switcherCanUse(id), heldElsewhere: movingHere && canMovePageHere(id)) != nil
              })
        else { return false }
        return retirementUnavailableReason?(ids) == nil
    }

    private var currentRenameTab: BrowserTab? {
        SidebarTabTitle.currentRenameTab(state: store.state, spaceID: activeSpaceID,
            profileID: activeProfileID, selectedTabIDs: selectedTabIDs)
    }

    private var currentRenameSplit: SidebarSplitTitleEdit? {
        SidebarSplitTitleEdit.current(state: store.state, spaceID: activeSpaceID,
            profileID: activeProfileID, selectedTabIDs: selectedTabIDs)
    }

    var canRenameCurrentItem: Bool {
        guard spaceCommandsAvailable, activePeek == nil, !sidebar.isEditingTitle else { return false }
        if let target = currentRenameSplit {
            return target.children.allSatisfy { canPerformSidebarTabAction($0, closing: false) }
        }
        guard let tab = currentRenameTab, !InternalPage.isInternal(tab.url) else { return false }
        return canPerformSidebarTabAction(tab, closing: false)
    }

    func renameCurrentItem() {
        if let target = currentRenameSplit { renameCurrentSplit(target); return }
        guard canRenameCurrentItem, let expected = currentRenameTab else { return }
        commandBar?.dismiss()
        guard canRenameCurrentItem, let current = currentRenameTab,
              SidebarTabTitle.sameItemForEditing(current, expected),
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              canPerformSidebarTabAction(current, closing: false) else { return }
        if !store.isEphemeral {
            guard let reveal = SidebarItemReveal(item: .tab(current.id), spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) else { return }
            do { guard try store.revealSidebarItem(reveal) else { return } }
            catch { showError(error); return }
        }
        closeLibrary(restoreFocus: false)
        render(store.state)
        revealSidebarForEditing()
        guard let target = currentRenameTab, SidebarTabTitle.sameItemForEditing(target, expected),
              canPerformSidebarTabAction(target, closing: false) else { return }
        _ = sidebar.beginTitleEditing(target)
    }

    private var currentSidebarMenuItems: [SidebarItemReference]? {
        if let selection = sidebar.commandBarSelectionItems() { return selection }
        guard activePeek == nil, let id = currentTabID else { return nil }
        if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) {
            return [.split(group.id)]
        }
        return [.tab(id)]
    }
    var canDuplicateCurrentItem: Bool {
        commandBar == nil && currentSidebarMenuItems.flatMap { prepareSidebarDuplicate($0) } != nil
    }
    func duplicateCurrentItem() {
        guard commandBar == nil, let items = currentSidebarMenuItems,
              let duplicate = prepareSidebarDuplicate(items) else { return }
        _ = duplicate()
    }

    private func commandBarTypedCommands(items: [SidebarItemReference]?, profileID: UUID) -> [CommandBarTypedCommand] {
        guard !isPopupWindow else { return [] }
        var commands: [CommandBarTypedCommand] = []
        if let undo = folderUndo.command(.undo), !undo.name.isEmpty { commands.append(.init(kind: .undo(undo.name))) }
        if let redo = folderUndo.command(.redo), !redo.name.isEmpty { commands.append(.init(kind: .redo(redo.name))) }
        if let items, !isPrivateBrowsing {
            let allSpaces = store.state.spaces
            commands += allSpaces.enumerated().filter { _, space in
                space.id != activeSpaceID && commandBarSpaceMoveIsPossible(items, to: space)
            }.map { offset, space in
                let shared = allSpaces.filter { $0.name == space.name }.count > 1
                return .init(kind: .pinToSpace(space.id, name: space.name, position: shared ? offset + 1 : nil))
            }
            if commandBarFolderCollectionIsPossible(items) {
                commands.append(.init(kind: .pinToNewFolder))
            }
            if commandBarDuplicateIsPossible(items) {
                commands.append(.init(kind: .duplicateCurrentTab))
            }
        }
        commands.append(.init(kind: .replacePinWithCurrentPage))
        commands += CommandBarTypedCommand.splitCommands(paneCount: selectedTabIDs.count,
                                                         vertical: activeSplitLayout?.orientation == .vertical)
        if !isPrivateBrowsing {
            commands += CommandBarWebDocument.available(visitedHosts: commandBarVisitedHosts(profileID: profileID))
                .map { .init(kind: .newWebDocument($0)) }
            commands += [.init(kind: .searchSettings), .init(kind: .airTrafficControl)]
        }
        commands += CommandBarTypedCommand.SettingsPane.allCases.map { .init(kind: .settingsPane($0)) }
        commands += CommandBarTypedCommand.Appearance.allCases.map { .init(kind: .appearance($0)) }
        commands += [.init(kind: .copyAppInfo), .init(kind: .revealAppData), .init(kind: .capturePortrait)]
        if canPerformPageTool(.taskManager) { commands.append(.init(kind: .openTaskManager)) }
        return commands
    }

    private func commandBarVisitedHosts(profileID: UUID) -> Set<String> {
        if let cache = commandBarHostCache, cache.profileID == profileID, cache.revision == store.historyRevision {
            return cache.hosts
        }
        let hosts = Set(store.state.history.lazy.filter { $0.profileID == profileID }
            .compactMap { URL(string: $0.url)?.host?.lowercased() })
        commandBarHostCache = (profileID, store.historyRevision, hosts)
        return hosts
    }

    private func commandBarModelCheck(_ key: String, items: [SidebarItemReference], _ check: () -> Bool) -> Bool {
        if let cache = commandBarModelChecks, cache.revision == store.stateRevision, cache.spaceID == activeSpaceID,
           cache.profileID == activeProfileID, cache.items == items {
            if let answer = cache.answers[key] { return answer }
        } else {
            commandBarModelChecks = (store.stateRevision, activeSpaceID, activeProfileID, items, [:])
        }
        let answer = check()
        commandBarModelChecks?.answers[key] = answer
        return answer
    }
    private func commandBarSpaceMoveIsPossible(_ items: [SidebarItemReference], to space: BrowserSpace) -> Bool {
        commandBarModelCheck("space:" + space.id.uuidString, items: items) { sidebarSpaceMoveIsPossible(items, to: space) }
    }
    private func commandBarFolderCollectionIsPossible(_ items: [SidebarItemReference]) -> Bool {
        commandBarModelCheck("folder", items: items) {
            SidebarMoveCollection(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
        }
    }
    private func commandBarDuplicateIsPossible(_ items: [SidebarItemReference]) -> Bool {
        commandBarModelCheck("duplicate", items: items) {
            SidebarDuplicateTarget(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
        }
    }

    private func sidebarSpaceMoveIsPossible(_ items: [SidebarItemReference], to space: BrowserSpace) -> Bool {
        guard let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: space.id, profileID: space.profileID) else { return false }
        return SidebarSpaceMove(items: items, from: source, to: target, state: store.state) != nil
    }

    private func typedSplitCommand(_ kind: CommandBarTypedCommand.Kind) -> SplitCommand? {
        switch kind {
        case .addSplit(.left): return .add(.addBefore)
        case .addSplit(.right): return .add(.addAfter)
        case .addSplit(.top): return .add(.addAbove)
        case .addSplit(.bottom), .addVerticalSplit: return .add(.addBelow)
        case .convertSplit(let vertical): return .orientation(vertical ? .vertical : .horizontal)
        default: return nil
        }
    }

    private var replaceablePinnedTab: (tab: BrowserTab, url: String)? {
        guard activePeek == nil, !isPrivateBrowsing, let id = currentTabID,
              let tab = visibleTabs.first(where: { $0.id == id }), tab.resetDestination != nil else { return nil }
        let url = browsers[id]?.url?.absoluteString ?? tab.url
        guard !InternalPage.isInternal(url), url != tab.savedURL else { return nil }
        return (tab, url)
    }

    private func typedCommandIsAvailable(_ command: CommandBarTypedCommand, items: [SidebarItemReference]?, profileID: UUID) -> Bool {
        switch command.kind {
        case .undo(let name):
            return windowUndoContextAvailable && folderUndoContextAvailable && folderUndo.command(.undo)?.name == name
        case .redo(let name):
            return windowUndoContextAvailable && folderUndoContextAvailable && folderUndo.command(.redo)?.name == name
        case .pinToSpace(let id, _, _):
            guard let items, let space = store.state.spaces.first(where: { $0.id == id }) else { return false }
            return !store.isEphemeral && !isPrivateBrowsing && spaceCommandsAvailable && activePeek == nil
                && id != activeSpaceID && commandBarSpaceMoveIsPossible(items, to: space)
        case .pinToNewFolder:
            guard let items else { return false }
            return !isPrivateBrowsing && folderUndoContextAvailable && !folderUndo.isBusy
                && spaceCommandsAvailable && activePeek == nil
                && commandBarFolderCollectionIsPossible(items)
        case .duplicateCurrentTab:
            guard let items else { return false }
            return folderDuplicateContextAvailable && spaceCommandsAvailable && activePeek == nil
                && commandBarDuplicateIsPossible(items)
        case .replacePinWithCurrentPage:
            return replaceablePinnedTab != nil
        case .addSplit, .convertSplit, .addVerticalSplit:
            guard let split = typedSplitCommand(command.kind), splitCommandIsAvailable(split) else { return false }
            if case .convertSplit(let vertical) = command.kind {
                return activeSplitLayout.map { ($0.orientation == .vertical) != vertical } == true
            }
            return true
        case .newWebDocument, .searchSettings, .airTrafficControl:
            return !isPrivateBrowsing && !isPopupWindow
        case .settingsPane, .appearance, .copyAppInfo:
            return !isPopupWindow && !isClosing
        case .revealAppData:
            return !store.isEphemeral && !isPrivateBrowsing && !isPopupWindow
        case .capturePortrait:
            return canCapturePage
        case .openTaskManager:
            return canPerformPageTool(.taskManager)
        }
    }

    private func prepareTypedCommand(_ command: CommandBarTypedCommand, items: [SidebarItemReference]?, profileID: UUID) -> (() -> Bool)? {
        guard typedCommandIsAvailable(command, items: items, profileID: profileID) else { return nil }
        switch command.kind {
        case .undo, .redo:
            let direction: FolderUndoManager.Direction
            if case .undo = command.kind { direction = .undo } else { direction = .redo }
            guard let action = folderUndo.command(direction), folderUndo.canPerform(action) else { return nil }
            return { [weak self] in self?.folderUndo.perform(action) == true }
        case .pinToSpace(let id, _, _):
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareSidebarSpaceMove(items, to: id, pinsToday: true)
        case .pinToNewFolder:
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareFolderFromItems(items)
        case .duplicateCurrentTab:
            guard let items, currentSidebarMenuItems == items else { return nil }
            return prepareSidebarDuplicate(items)
        case .replacePinWithCurrentPage:
            guard let replaceable = replaceablePinnedTab else { return nil }
            let expected = replaceable.tab, url = replaceable.url
            return { [weak self] in
                guard let self, self.replaceablePinnedTab?.tab == expected,
                      self.store.replaceSavedHome(expected, url: url, title: expected.title) else { return false }
                self.render(self.store.state)
                return true
            }
        case .addSplit, .convertSplit, .addVerticalSplit:
            guard let split = typedSplitCommand(command.kind), let target = splitCommandTarget(split) else { return nil }
            return { guard target.isAvailable else { return false }; target.perform(); return true }
        case .newWebDocument(let document):
            return openTypedDestination(document.url)
        case .searchSettings:
            return openTypedDestination("parc://settings/searchEngines")
        case .airTrafficControl:
            return { [weak self] in
                guard let self else { return false }
                self.showSettings(pane: .links)
                return self.settings?.showAirTrafficControl() == true
            }
        case .settingsPane(let pane):
            let destination: SettingsWindow.Pane
            switch pane {
            case .account: destination = .membership
            case .general: destination = .general
            case .profiles: destination = .spaces
            case .shortcuts: destination = .shortcuts
            case .links: destination = .links
            case .appIcon: destination = .icon
            case .advanced: destination = .advanced
            }
            return { [weak self] in
                guard let self else { return false }
                self.showSettings(pane: destination)
                return self.isPrivateBrowsing || self.settings?.window?.isVisible == true
            }
        case .appearance(let appearance):
            let action = NSSelectorFromString(appearance.selectorName)
            return { NSApp.sendAction(action, to: nil, from: nil) }
        case .copyAppInfo:
            return { [weak self] in
                guard let self else { return false }
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(Self.buildInfo, forType: .string) else { return false }
                _ = self.showToast(.copiedBuildInfo)
                return true
            }
        case .revealAppData:
            let directory = store.directory
            return { NSWorkspace.shared.activateFileViewerSelecting([directory]); return true }
        case .capturePortrait:
            return { [weak self] in
                guard let self, self.canCapturePage else { return false }
                self.capturePage(.portrait)
                return self.pageCapture != nil
            }
        case .openTaskManager:
            guard let browser = currentBrowser else { return nil }
            return { [weak self, weak browser] in
                guard let self, let browser, self.currentBrowser === browser,
                      self.canPerformPageTool(.taskManager) else { return false }
                return browser.performPageTool(.taskManager)
            }
        }
    }

    private static var buildInfo: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let engine = Bundle.main.privateFrameworksURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Chromium Embedded Framework.framework")) }?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return ["Parc \(version) (\(build))", "Chromium Engine Version \(engine)",
                "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"].joined(separator: "\n")
    }

    private func openTypedDestination(_ url: String) -> () -> Bool {
        { [weak self] in
            guard let self, !self.isPrivateBrowsing else { return false }
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            var opened = false
            self.performWindowCommand {
                let id = self.store.open(url, creation: creation)
                self.presentation.recordCreation(id, state: self.store.state)
                opened = true
            }
            return opened
        }
    }
    private var currentRevealSidebarItem: SidebarItemReference? {
        guard activePeek == nil, let id = currentTabID else { return nil }
        if let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) {
            return .split(group.id)
        }
        return .tab(id)
    }
    var canRevealCurrentTabInSidebar: Bool {
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable,
              let item = currentRevealSidebarItem else { return false }
        return SidebarItemReveal(item: item, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) != nil
    }
    func revealCurrentTabInSidebar() {
        guard canRevealCurrentTabInSidebar, let item = currentRevealSidebarItem else { return }
        let spaceID = activeSpaceID, profileID = activeProfileID
        commandBar?.dismiss()
        guard canRevealCurrentTabInSidebar, currentRevealSidebarItem == item,
              activeSpaceID == spaceID, activeProfileID == profileID else { return }
        revealSidebarItem(item, spaceID: spaceID, profileID: profileID)
    }
    var canRenameActiveSpace: Bool {
        spaceCommandsAvailable && managementSpace(activeSpaceID) != nil && !sidebar.isEditingSpaceName
    }
    func renameActiveSpace() {
        guard canRenameActiveSpace else { return }
        renameSpace(activeSpaceID)
    }
    var canOpenPageInNewTab: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && !isPrivateBrowsing && !isPopupWindow
    }
    func openExtensionsPage(addExtension: Bool) {
        openPageInNewTab(addExtension ? "https://chromewebstore.google.com/category/extensions" : "parc://extensions/")
    }
    func openHistoryPage() { openPageInNewTab("parc://history/") }
    func openReleaseNotes(fragment: String? = nil) {
        guard let url = SoftwareUpdateBanner.releaseNotesURL else { return }
        openPageInNewTab(url.absoluteString + (fragment.map { "#" + $0 } ?? ""))
    }
    private func openPageInNewTab(_ address: String) {
        guard canOpenPageInNewTab, window?.isKeyWindow == true, windowCommandSecurityAvailable,
              let url = URL(string: address) else { return }
        openExactAddress(url)
    }
    private func openExactAddress(_ url: URL) {
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.openResolvedURL(url, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
    }

    private func revealSidebarForEditing() {
        if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
        settleSidebarMotion(); layoutChrome(); rootView.layoutSubtreeIfNeeded()
    }

    private func renameCurrentSplit(_ expected: SidebarSplitTitleEdit) {
        guard canRenameCurrentItem else { return }
        commandBar?.dismiss()
        if expected.isFavorite { _ = prepareFavoriteSplitRename(expected)?(); return }
        guard canRenameCurrentItem, currentRenameSplit == expected,
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return }
        if !store.isEphemeral {
            guard let reveal = SidebarItemReveal(item: .split(expected.group.id), spaceID: activeSpaceID,
                profileID: activeProfileID, state: store.state) else { return }
            do { guard try store.revealSidebarItem(reveal) else { return } }
            catch { showError(error); return }
        }
        closeLibrary(restoreFocus: false)
        render(store.state)
        revealSidebarForEditing()
        guard currentRenameSplit == expected,
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return }
        _ = sidebar.beginTitleEditing(expected)
    }

    private func prepareSidebarSplitTitleEdit(_ expected: SidebarSplitTitleEdit) -> ((String) -> Bool)? {
        guard !folderUndo.isBusy, expected.group.spaceID == activeSpaceID, expected.profileID == activeProfileID,
              expected.matches(store.state), activePeek == nil,
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return nil }
        let leases: [() -> Bool] = expected.children.map { original in
            let browser = browsers[original.id], page = browser?.nativePage
            let note = noteEditors[original.id]?.editor, easel = easelEditors[original.id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil
            let hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self,
                      let current = self.visibleTabs.first(where: { $0.id == original.id }),
                      SidebarTabTitle.sameItemForEditing(current, original),
                      self.canPerformSidebarTabAction(current, closing: false),
                      (self.browsers[original.id] != nil) == hadBrowser,
                      (self.noteEditors[original.id]?.editor != nil) == hadNote,
                      (self.easelEditors[original.id]?.editor != nil) == hadEasel else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[original.id] === browser,
                          (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[original.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[original.id]?.editor === easel else { return false } }
                return true
            }
        }
        var used = false
        return { [weak self] title in
            guard let self, !used, !self.folderUndo.isBusy, self.activeSpaceID == expected.group.spaceID,
                  self.activeProfileID == expected.profileID, expected.matches(self.store.state),
                  self.activePeek == nil, leases.allSatisfy({ $0() }) else { return false }
            used = true
            do {
                if let change = try self.store.saveSidebarSplitTitle(expected, title: title) {
                    self.folderUndo.appendSplitTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
                return true
            } catch { showError(error); return false }
        }
    }

    private func prepareSidebarTitleEdit(_ expected: BrowserTab) -> ((String) -> Bool)? {
        guard !folderUndo.isBusy, SidebarTabTitle.isRenameable(expected),
              canPerformSidebarTabAction(expected, closing: false) else { return nil }
        let space = activeSpaceID, browser = browsers[expected.id], page = browser?.nativePage
        let hadBrowser = browser != nil, hadPage = page != nil
        let group = store.state.splitLayouts.first { $0.tabIDs.contains(expected.id) }
        var used = false
        return { [weak self, weak browser, weak page] title in
            guard let self, !used, !self.folderUndo.isBusy, self.activeSpaceID == space,
                  let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                  SidebarTabTitle.sameItemForEditing(current, expected),
                  self.canPerformSidebarTabAction(current, closing: false),
                  !InternalPage.isInternal(current.url),
                  self.store.state.splitLayouts.first(where: { $0.tabIDs.contains(expected.id) }) == group,
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, self.browsers[expected.id] === browser,
                      (browser.nativePage != nil) == hadPage else { return false }
                if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
            }
            used = true
            do {
                if let change = try self.store.saveSidebarTitle(expected, title: title) {
                    self.folderUndo.appendTabTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
                return true
            } catch { showError(error); return false }
        }
    }


    private var favoriteSplitRename: FavoriteRenameDialog?
    private var splitIconPicker: SidebarGroupIconPicker?

    private func splitCustomizationOwner(_ expected: SidebarSplitTitleEdit,
        presentationWindow: @escaping () -> NSWindow? = { nil },
        current: @escaping () -> SidebarSplitTitleEdit? = { nil }) -> (() -> Bool)? {
        guard !folderUndo.isBusy, expected.profileID == activeProfileID,
              expected.isVisible(in: activeSpaceID, state: store.state), expected.matches(store.state),
              activePeek == nil, let window,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              expected.children.allSatisfy({ canPerformSidebarTabAction($0, closing: false) }) else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs, focus = focusedTabID
        let leases: [() -> Bool] = expected.children.map { original in
            let browser = browsers[original.id], page = browser?.nativePage
            let note = noteEditors[original.id]?.editor, easel = easelEditors[original.id]?.editor
            let hadBrowser = browser != nil, hadPage = page != nil, hadNote = note != nil, hadEasel = easel != nil
            return { [weak self, weak browser, weak page, weak note, weak easel] in
                guard let self, self.ownership.canUse(original.id, owner: self.presentationID),
                      !self.closingTabIDs.contains(original.id), !self.transferringTabIDs.contains(original.id),
                      !self.resolvingTransfers.contains(original.id), self.transferRecoveries[original.id] == nil,
                      !self.store.retiringTabIDs.contains(original.id), !self.modelRetirementIDs.contains(original.id),
                      (self.browsers[original.id] != nil) == hadBrowser,
                      (self.noteEditors[original.id]?.editor != nil) == hadNote,
                      (self.easelEditors[original.id]?.editor != nil) == hadEasel else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[original.id] === browser, (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[original.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[original.id]?.editor === easel else { return false } }
                return true
            }
        }
        return { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending, !self.windowCloseApproved,
                  self.presentation.isReady, self.nativeFullscreenTabID == nil, self.activePeek == nil,
                  !self.folderUndo.isBusy, self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  (current() ?? expected).matches(self.store.state), leases.allSatisfy({ $0() }) else { return false }
            return SplitCustomizationFocus.isHeld(window: window, presentation: presentationWindow())
        }
    }

    private func prepareFavoriteSplitRename(_ expected: SidebarSplitTitleEdit) -> (() -> Bool)? {
        guard expected.isFavorite, favoriteSplitRename == nil, favoriteRename == nil, splitIconPicker == nil,
              splitCustomizationOwner(expected) != nil else { return nil }
        let space = activeSpaceID
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, let window = self.window,
                  self.splitCustomizationOwner(expected) != nil,
                  let anchor = expected.group.sidebarAnchorID else { return false }
            self.selectTab(anchor)
            guard self.selectedTabIDs == expected.group.tabIDs,
                  let dialogOwner = self.splitCustomizationOwner(expected, presentationWindow: { [weak self] in self?.favoriteSplitRename?.sheetWindow }) else { return false }
            used = true
            let title = expected.group.customTitle ?? expected.children.map(SidebarTabTitle.display).joined(separator: " / ")
            let dialog = FavoriteRenameDialog(title: title)
            dialog.isCurrent = dialogOwner
            dialog.onCommit = { [weak self] title in
                guard let self, dialogOwner() else { throw SidebarSplitTitleEdit.EditError.unavailable }
                if let change = try self.store.saveSidebarSplitTitle(expected, title: title) {
                    self.folderUndo.appendSplitTitleChange(change, store: self.store,
                        available: { [weak self] in self?.windowUndoContextAvailable == true && self?.activeProfileID == change.profileID },
                        onError: { [weak self] in self?.showError($0) })
                }
            }
            dialog.onFinish = { [weak self, weak dialog] in
                guard let self, self.favoriteSplitRename === dialog else { return }
                self.favoriteSplitRename = nil
                if self.activeSpaceID == space, self.selectedTabIDs == expected.group.tabIDs {
                    self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            }
            self.favoriteSplitRename = dialog; dialog.present(in: window)
            return self.favoriteSplitRename === dialog
        }
    }

    private func prepareSplitAppearance(_ expected: SidebarSplitTitleEdit, reset: Bool) -> (() -> Bool)? {
        guard favoriteSplitRename == nil, favoriteRename == nil, splitIconPicker == nil,
              !sidebar.isEditingTitle, let valid = splitCustomizationOwner(expected),
              !reset || expected.group.customTitle != nil || expected.group.customIcon != nil else { return nil }
        var used = false
        return { [weak self] in
            guard let self, !used, valid() else { return false }
            if reset {
                used = true
                do { try self.commitSplitAppearance(expected, icon: nil, reset: true); return true }
                catch { showError(error); return false }
            }
            guard let anchor = self.sidebar.appearanceAnchor(for: expected.group), anchor.window === self.window else { return false }
            let picker = SidebarGroupIconPicker(selected: expected.group.customIcon, iconSet: .tabAndSpacePicker)
            var current = expected
            guard let owner = self.splitCustomizationOwner(expected, presentationWindow: { [weak picker] in picker?.presentationWindow },
                                                           current: { current }) else { return false }
            picker.isCurrent = owner
            picker.onCommit = { [weak self] icon in
                guard let self, owner() else { throw SidebarSplitTitleEdit.EditError.unavailable }
                try self.commitSplitAppearance(current, icon: icon)
                if let group = self.store.state.splitLayouts.first(where: { $0.id == current.group.id }),
                   let next = SidebarSplitTitleEdit(group: group, profileID: current.profileID, state: self.store.state) { current = next }
            }
            picker.onFailure = { [weak self] in self?.showError($0) }
            picker.onFinish = { [weak self, weak picker] in
                guard let self, self.splitIconPicker === picker else { return }
                self.splitIconPicker = nil
            }
            used = true; self.splitIconPicker = picker
            let rect = (anchor as? SidebarSplitGroupView)?.appearanceAnchorRect ?? anchor.bounds
            let host = anchor.enclosingScrollView?.documentView ?? anchor
            picker.present(from: host, rect: host.convert(rect, from: anchor))
            return self.splitIconPicker === picker
        }
    }

    private func commitSplitAppearance(_ expected: SidebarSplitTitleEdit, icon: SidebarGroupIcon?, reset: Bool = false) throws {
        if let change = try store.saveSplitAppearance(expected, icon: icon, reset: reset) {
            folderUndo.appendSplitAppearance(change, store: store,
                available: { [weak self] in self?.windowUndoContextAvailable == true && self?.activeProfileID == change.profileID },
                onError: { [weak self] in self?.showError($0) })
        }
    }

    private var favoriteRename: FavoriteRenameDialog?

    private func prepareFavoriteRename(_ expected: BrowserTab, selectOriginal: Bool = true) -> (() -> Bool)? {
        guard favoriteRename == nil, !folderUndo.isBusy, !sidebar.isEditingTitle,
              !isPrivateBrowsing, expected.kind == .favorite,
              let window, let binding = nativeBinding, binding.window === window,
              !binding.isPrivateBrowsing, binding.browsingContextKind != .mixed,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              canPerformSidebarTabAction(expected, closing: false) else { return nil }
        let space = activeSpaceID
        var used = false
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding, !used, self.activeSpaceID == space,
                  self.window === window, self.nativeBinding === binding, binding.window === window,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  self.favoriteRename == nil, !self.folderUndo.isBusy,
                  let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                  SidebarTabTitle.sameItemForEditing(current, expected) else { return false }
            if selectOriginal {
                guard let activate = self.prepareFavoriteAction(current, closing: false), activate() else { return false }
            }
            guard window.attachedSheet == nil, self.selectedTabIDs == [expected.id] else { return false }
            used = true
            let browser = self.browsers[expected.id], page = browser?.nativePage
            let hadBrowser = browser != nil, hadPage = page != nil
            let note = self.noteEditors[expected.id]?.editor, easel = self.easelEditors[expected.id]?.editor
            let hadNote = note != nil, hadEasel = easel != nil
            let dialog = FavoriteRenameDialog(title: SidebarTabTitle.display(current))
            dialog.isCurrent = { [weak self, weak window, weak binding, weak dialog, weak browser, weak page, weak note, weak easel] in
                guard let self, let window, let binding, let dialog,
                      self.window === window, self.favoriteRename === dialog,
                      self.nativeBinding === binding, binding.window === window,
                      !binding.isPrivateBrowsing, binding.browsingContextKind != .mixed,
                      self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                      !self.windowClosePending, !self.windowCloseApproved, self.nativeFullscreenTabID == nil,
                      self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                      self.selectedTabIDs == [expected.id], self.activePeek == nil,
                      self.commandBar == nil, !self.folderUndo.isBusy,
                      !self.store.isProfileRemovalPending(expected.profileID),
                      !self.closingTabIDs.contains(expected.id), !self.transferringTabIDs.contains(expected.id),
                      !self.resolvingTransfers.contains(expected.id), self.transferRecoveries[expected.id] == nil,
                      !self.store.retiringTabIDs.contains(expected.id), !self.modelRetirementIDs.contains(expected.id),
                      self.ownership.canUse(expected.id, owner: self.presentationID),
                      let tab = self.visibleTabs.first(where: { $0.id == expected.id }),
                      SidebarTabTitle.sameItemForEditing(tab, expected),
                      (self.browsers[expected.id] != nil) == hadBrowser,
                      (self.noteEditors[expected.id]?.editor != nil) == hadNote,
                      (self.easelEditors[expected.id]?.editor != nil) == hadEasel,
                      window.attachedSheet == nil || window.attachedSheet === dialog.sheetWindow else { return false }
                if hadBrowser {
                    guard let browser, self.browsers[expected.id] === browser,
                          (browser.nativePage != nil) == hadPage else { return false }
                    if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
                }
                if hadNote { guard let note, self.noteEditors[expected.id]?.editor === note else { return false } }
                if hadEasel { guard let easel, self.easelEditors[expected.id]?.editor === easel else { return false } }
                return true
            }
            dialog.onCommit = { [weak self] title in
                guard let self else { throw SidebarTabTitle.EditError.unavailable }
                if let change = try self.store.saveFavoriteTitle(expected, title: title) {
                    self.folderUndo.appendTabTitleChange(change, store: self.store, available: { [weak self] in
                        guard let self, self.windowUndoContextAvailable,
                              self.activeProfileID == change.profileID else { return false }
                        return true
                    }, onError: { [weak self] in self?.showError($0) })
                }
            }
            dialog.onFinish = { [weak self, weak dialog] in
                guard let self, self.favoriteRename === dialog else { return }
                self.favoriteRename = nil
                if self.selectedTabIDs == [expected.id], self.activeSpaceID == space {
                    self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            }
            self.favoriteRename = dialog
            dialog.present(in: window)
            return self.favoriteRename === dialog
        }
    }

    private func prepareFavoritePointerAction(_ expected: BrowserTab,
                                             intent: FavoritePointerAction) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing else { return nil }
        if intent == .activate { return prepareFavoriteActivation(expected) }
        if intent == .openInSplit { return prepareFavoriteOptionRelease(expected) }
        let force = intent == .resetAndSelect
        guard let reset = prepareSavedTabReset(expected, allowUnchanged: force) else { return nil }
        if force && prepareFavoriteAction(expected, closing: false) == nil { return nil }
        return { [weak self] in
            guard let self, reset() else { return false }
            if force {
                guard let current = self.visibleTabs.first(where: { $0.id == expected.id }),
                      current.profileID == expected.profileID, current.kind == .favorite,
                      current.createdAt == expected.createdAt, current.savedURL == expected.savedURL,
                      let select = self.prepareFavoriteAction(current, closing: false) else { return false }
                return select()
            }
            return true
        }
    }

    private func prepareFavoriteActivation(_ expected: BrowserTab) -> (() -> Bool)? {
        prepareFavoriteTransferOffer(expected) ?? prepareFavoriteAction(expected, closing: false)
    }

    private func favoritePanes(_ expected: BrowserTab) -> [UUID] {
        SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID)
            .first { $0.tabIDs.contains(expected.id) }?.tabIDs ?? [expected.id]
    }

    private func currentFavorite(_ expected: BrowserTab) -> BrowserTab? {
        visibleTabs.first { $0.id == expected.id && $0.kind == .favorite
            && $0.profileID == expected.profileID && $0.createdAt == expected.createdAt }
    }

    private func canOfferFavoriteTransfer(_ expected: BrowserTab) -> Bool {
        expected.kind == .favorite && !isPrivateBrowsing && !isPopupWindow && presentation.isReady
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && window?.isKeyWindow == true
            && window?.attachedSheet == nil && onRequestTabTransfer != nil
            && expected.profileID == activeProfileID && !store.isProfileRemovalPending(expected.profileID)
            && visibleTabs.contains(expected)
    }

    private func canMovePageHere(_ id: UUID) -> Bool {
        guard !isPopupWindow, !closingTabIDs.contains(id), !transferringTabIDs.contains(id), !resolvingTransfers.contains(id),
              transferRecoveries[id] == nil, !store.retiringTabIDs.contains(id),
              let owner = ownership.owner(of: id), owner != presentationID else { return false }
        if case .none = tabHolder?(id, self) ?? .none { return false }
        return true
    }

    func holdsEmptyClaim(_ id: UUID) -> Bool {
        !isPopupWindow && !isClosing && claimsTab(id)
            && browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil
            && !transferringTabIDs.contains(id) && !closingTabIDs.contains(id) && !modelRetirementIDs.contains(id)
            && !store.retiringTabIDs.contains(id) && pendingSearchNavigations[id] == nil
    }
    func handOverEmptyClaim(_ id: UUID, to destination: BrowserWindowController) -> Bool {
        guard destination !== self, destination.store === store, !destination.isPopupWindow, holdsEmptyClaim(id) else { return false }
        ownership.release(id, owner: presentationID)
        guard ownership.claim(id, owner: destination.presentationID) else {
            _ = ownership.claim(id, owner: presentationID); return false
        }
        presentation.leavePlaceholder(id, state: store.state)
        failures.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
        if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
        if !rendering { render(store.state) }
        return true
    }

    func canMoveContent(_ id: UUID, to destination: BrowserWindowController) -> Bool {
        guard destination !== self, store === destination.store, !isPopupWindow, !destination.isPopupWindow,
              !destination.isClosing, !destination.wholeWindowClose, destination.transferringTabIDs.isEmpty,
              destination.collectionTransfer == nil, destination.nativeFullscreenTabID == nil,
              let destinationWindow = destination.window, destinationWindow !== window, destination.nativeBinding != nil,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == destination.activeProfileID, destination.browsers[id] == nil else { return false }
        if browsers[id] == nil, noteEditors[id] != nil || easelEditors[id] != nil {
            return !destination.isPrivateBrowsing && !destination.store.isEphemeral && destination.presentation.isReady
                && !destination.windowClosePending && !destination.windowCloseApproved && destination.activePeek == nil
        }
        if peeks.values.contains(where: { $0.parentTabID == id && !$0.page.isClosed }) { return destination.activePeek == nil }
        return true
    }
    func claimsTab(_ id: UUID) -> Bool { ownership.owner(of: id) == presentationID }
    private func closeTabMovingHere(_ id: UUID) -> Bool {
        if ownership.canUse(id, owner: presentationID) { return closeTab(id) }
        guard canMovePageHere(id), let request = onRequestTabTransfer else { refuseTabMove(); return false }
        return request(id, self) { [weak self] in self?.closeTab(id) ?? false }
    }
    func finishEmptyClaimHandOver(_ id: UUID, placement: (() -> Bool)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !(placement?() ?? false) { _ = self.selectTab(id) }
        }
    }

    private func favoritePagesElsewhere(_ expected: BrowserTab) -> [UUID] {
        guard canOfferFavoriteTransfer(expected) else { return [] }
        let pages = favoritePanes(expected).filter {
            ownership.isClaimed($0) && !ownership.canUse($0, owner: presentationID)
        }
        return pages.allSatisfy(canMovePageHere) ? pages : []
    }

    private func prepareFavoriteTransferOffer(_ expected: BrowserTab) -> (() -> Bool)? {
        let pages = favoritePagesElsewhere(expected)
        guard let first = pages.first else { return nil }
        let space = activeSpaceID, panes = favoritePanes(expected)
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, self.favoritePanes(expected) == panes,
                  self.favoritePagesElsewhere(expected) == pages else { return false }
            used = true
            guard panes.count > 1 else { return self.onRequestTabTransfer?(first, self, nil) ?? false }
            return self.movePagesHere(pages[...]) { [weak self] in
                guard let self, self.activeSpaceID == space, self.favoritePanes(expected) == panes,
                      let current = self.currentFavorite(expected),
                      let select = self.prepareFavoriteAction(current, closing: false) else { return false }
                return select()
            }
        }
    }

    private func prepareFavoriteOptionRelease(_ expected: BrowserTab) -> (() -> Bool)? {
        switch FavoriteOptionRoute(favoriteID: expected.id, selection: selectedTabIDs, focusedID: currentTabID) {
        case .split: return prepareFavoriteSplit(expected) ?? prepareFavoriteSplitTransfer(expected)
        case .present: return prepareFavoriteActivation(expected)
        case .paneLimit: return prepareFavoritePaneLimit(expected)
        case .unchanged: return nil
        }
    }

    private func prepareFavoritePaneLimit(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing, splitCommandsAvailable, commandBar == nil,
              window?.isKeyWindow == true, window?.attachedSheet == nil,
              expected.profileID == activeProfileID, visibleTabs.contains(expected) else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        var used = false
        return { [weak self] in
            guard let self, !used, self.activeSpaceID == space, self.selectedTabIDs == selection,
                  self.splitCommandsAvailable, self.commandBar == nil, self.window?.isKeyWindow == true,
                  self.window?.attachedSheet == nil, self.visibleTabs.contains(expected),
                  FavoriteOptionRoute(favoriteID: expected.id, selection: selection,
                                      focusedID: self.currentTabID) == .paneLimit else { return false }
            used = true
            self.showToast(.cannotAddNewPane, at: .window); return true
        }
    }

    private func prepareFavoriteSplitTransfer(_ expected: BrowserTab) -> (() -> Bool)? {
        guard splitCommandsAvailable, commandBar == nil, canOfferFavoriteTransfer(expected),
              canMovePageHere(expected.id), let focus = currentTabID else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        let unchanged = { (owner: BrowserWindowController) in
            owner.activeSpaceID == space && owner.selectedTabIDs == selection && owner.currentTabID == focus
        }
        var used = false
        return { [weak self] in
            guard let self, !used, unchanged(self), self.splitCommandsAvailable, self.commandBar == nil,
                  self.canOfferFavoriteTransfer(expected), self.canMovePageHere(expected.id) else { return false }
            used = true
            return self.onRequestTabTransfer?(expected.id, self) { [weak self] in
                guard let self, unchanged(self), let current = self.currentFavorite(expected),
                      let insert = self.prepareFavoriteSplit(current) else { return false }
                return insert()
            } ?? false
        }
    }

    private func prepareFavoriteSplit(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .favorite, !isPrivateBrowsing, splitCommandsAvailable,
              commandBar == nil, transferRecoveries.isEmpty,
              canPerformSidebarTabAction(expected, closing: false), switcherCanUse(expected.id),
              let window, let focus = currentTabID else { return nil }
        let space = activeSpaceID, selection = selectedTabIDs
        var identities: [UUID: SplitPaneIdentity] = [:]
        for id in selection {
            guard let identity = splitPaneIdentity(id) else { return nil }
            identities[id] = identity
        }
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadBrowser = browser != nil
        let sourceURL: String
        if let browser {
            guard browser.window === window, browserProfiles[expected.id] == expected.profileID,
                  let page, !page.isClosed, let binding = nativeBinding,
                  existingNativeSelection(binding, page)?.1 === browser,
                  let url = page.url else { return nil }
            sourceURL = url.absoluteString
        } else {
            guard !ownership.isClaimed(expected.id) else { return nil }
            sourceURL = expected.savedURL
        }
        let revision = browser?.readerRevision
        guard let probe = FavoriteSplitRequest(favorite: expected, spaceID: space,
                  selection: selection, focusedID: focus, state: store.state,
                  duplicateURL: sourceURL, duplicateTitle: page?.title),
              let plan = splitHomePlan(probe.savedHomeSources(in: store.state)),
              let request = FavoriteSplitRequest(favorite: expected, spaceID: space,
                  selection: selection, focusedID: focus, state: store.state,
                  duplicateURL: sourceURL, duplicateTitle: page?.title, newID: probe.newID, homeIDs: plan.ids) else { return nil }
        var consumed = false
        return { [weak self, weak window, weak browser, weak page] in
            guard let self, let window, !consumed, self.window === window,
                  self.splitCommandsAvailable, self.commandBar == nil, self.transferRecoveries.isEmpty,
                  self.activeSpaceID == space, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focus,
                  self.canPerformSidebarTabAction(expected, closing: false), self.switcherCanUse(expected.id),
                  selection.allSatisfy({ self.splitPaneIdentity($0) == identities[$0] }),
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, let page, self.browsers[expected.id] === browser,
                      browser.nativePage === page, !page.isClosed, browser.window === window,
                      browser.readerRevision == revision, page.url?.absoluteString == sourceURL,
                      let binding = self.nativeBinding,
                      self.existingNativeSelection(binding, page)?.1 === browser else { return false }
            } else if self.ownership.isClaimed(expected.id) { return false }
            guard SidebarDocumentReference.validates(request.savedHomeSources(in: self.store.state),
                                                     references: plan.documents) else { return false }
            consumed = true
            var target: UUID?
            self.performWindowCommand(selectNativePage: false) {
                do { target = try self.store.commitFavoriteSplit(request) }
                catch { self.showError(error) }
            }
            guard let target else { return false }
            self.openSplitHomes(plan.ids, profileID: expected.profileID, originatingSpaceID: space)
            self.focusedTabID = target
            self.render(self.store.state)
            self.requestNativeSelection(); self.focusSelectedLocalContent()
            return true
        }
    }

    private func prepareFavoriteAction(_ expected: BrowserTab, closing: Bool) -> (() -> Bool)? {
        guard !isPrivateBrowsing, expected.kind == .favorite else { return nil }
        return prepareSidebarTabAction(expected, closing: closing)
    }

    private func prepareSidebarTabAction(_ expected: BrowserTab, closing: Bool) -> (() -> Bool)? {
        guard canPerformSidebarTabAction(expected, closing: closing) else { return nil }
        let space = activeSpaceID, browser = browsers[expected.id], page = browser?.nativePage
        let group = SidebarSplitItems.groups(in: store.state, spaceID: space).first { $0.tabIDs.contains(expected.id) }
        let hadBrowser = browser != nil, hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space,
                  self.canPerformSidebarTabAction(expected, closing: closing),
                  SidebarSplitItems.groups(in: self.store.state, spaceID: space).first(where: { $0.tabIDs.contains(expected.id) }) == group,
                  (self.browsers[expected.id] != nil) == hadBrowser else { return false }
            if hadBrowser {
                guard let browser, self.browsers[expected.id] === browser,
                      (browser.nativePage != nil) == hadPage else { return false }
                if hadPage { guard let page, browser.nativePage === page, !page.isClosed else { return false } }
            }
            used = true
            if closing {
                return self.closeTabMovingHere(expected.id)
            }
            return self.selectTab(expected.id)
        }
    }

    private func canResetSavedTab(_ expected: BrowserTab, allowUnchanged: Bool = false) -> Bool {
        guard !isPopupWindow, !isClosing, !wholeWindowClose, !windowClosePending,
              libraryView == nil, window?.isKeyWindow == true, window?.attachedSheet == nil,
              savedResetDestination(expected, allowUnchanged: allowUnchanged) != nil, expected.profileID == activeProfileID,
              let current = visibleTabs.first(where: { $0.id == expected.id }),
              current.kind == expected.kind, current.profileID == expected.profileID,
              current.url == expected.url, current.savedURL == expected.savedURL,
              !closingTabIDs.contains(expected.id), !transferringTabIDs.contains(expected.id),
              !resolvingTransfers.contains(expected.id), transferRecoveries[expected.id] == nil,
              !store.retiringTabIDs.contains(expected.id), peekPages(forTabID: expected.id).isEmpty,
              ownership.canUse(expected.id, owner: presentationID) else { return false }
        if let browser = browsers[expected.id] {
            guard browserProfiles[expected.id] == expected.profileID,
                  browser.window === window, let page = browser.nativePage, !page.isClosed,
                  page.url?.absoluteString == expected.url else { return false }
        } else if ownership.isClaimed(expected.id) { return false }
        return true
    }
    private func prepareSavedTabReset(_ expected: BrowserTab, allowUnchanged: Bool = false) -> (() -> Bool)? {
        guard canResetSavedTab(expected, allowUnchanged: allowUnchanged) else { return nil }
        let space = activeSpaceID
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space, self.canResetSavedTab(expected, allowUnchanged: allowUnchanged) else { return false }
            if hadPage {
                guard let browser, let page, self.browsers[expected.id] === browser,
                      browser.nativePage === page else { return false }
            } else if self.browsers[expected.id] != nil { return false }
            used = true
            self.resetSavedTab(expected, allowUnchanged: allowUnchanged); return true
        }
    }
    private func prepareSavedTabIconReset(_ expected: BrowserTab, separating: Bool) -> (() -> Bool)? {
        guard let action = separating ? prepareSavedTabSeparation(expected) : prepareSavedTabReset(expected) else { return nil }
        return { [weak self] in
            guard let self, action() else { return false }
            if !self.selectedTabIDs.contains(expected.id) { _ = self.selectTab(expected.id) }
            return true
        }
    }
    private func prepareSavedTabSeparation(_ expected: BrowserTab) -> (() -> Bool)? {
        guard expected.kind == .pinned, nativeFullscreenTabID != expected.id, canResetSavedTab(expected),
              !SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID)
                  .contains(where: { $0.tabIDs.contains(expected.id) }) else { return nil }
        let space = activeSpaceID
        let browser = browsers[expected.id], page = browser?.nativePage
        let hadPage = page != nil
        var used = false
        return { [weak self, weak browser, weak page] in
            guard let self, !used, self.activeSpaceID == space, self.nativeFullscreenTabID != expected.id,
                  self.canResetSavedTab(expected) else { return false }
            guard hadPage else {
                guard self.browsers[expected.id] == nil else { return false }
                used = true; return true
            }
            guard let browser, let page, self.browsers[expected.id] === browser,
                  browser.nativePage === page else { return false }
            used = true
            return self.separateFromPinnedTab(expected, browser: browser, page: page)
        }
    }
    private func separateFromPinnedTab(_ expected: BrowserTab, browser: PCBrowserView, page: PCNativePage) -> Bool {
        guard let binding = nativeBinding, !page.isClosed, browser.window === window,
              PCNativeBrowserApplication.owner(of: page) === binding else { return false }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        let id = UUID()
        prepareStoreContext()
        guard store.separateFromPinnedTab(expected, todayID: id, title: browser.title),
              let tab = store.state.tabs.first(where: { $0.id == id }),
              let reset = store.state.tabs.first(where: { $0.id == expected.id }) else { return false }
        let source = panes[expected.id]
        binding.pageWillDetach(page)
        source?.browser = nil
        let pane = makePane(tab)
        pane.frame = pageHost.bounds; parkedPages.addSubview(pane)
        pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
        func restore() {
            pane.browser = nil; pane.removeFromSuperview()
            source?.browser = browser
            _ = binding.pageDidAttach(page, container: browser)
            store.removeTab(id)
            _ = store.restoreLiveTab(expected, replacing: reset)
        }
        guard binding.pageDidAttach(page, container: browser) else { restore(); return false }
        ownership.release(expected.id, owner: presentationID)
        guard ownership.claim(id, owner: presentationID, page: page.identifier) else {
            _ = ownership.claim(expected.id, owner: presentationID, page: page.identifier)
            binding.pageWillDetach(page); restore(); return false
        }
        browsers.removeValue(forKey: expected.id); browsers[id] = browser
        browserProfiles.removeValue(forKey: expected.id); browserProfiles[id] = tab.profileID
        liveTabModels.removeValue(forKey: expected.id); liveTabModels[id] = tab
        requestedURLs.removeValue(forKey: expected.id); requestedURLs[id] = tab.url
        zoomLevels[id] = zoomLevels.removeValue(forKey: expected.id)
        failures[id] = failures.removeValue(forKey: expected.id)
        if loadingTabs.remove(expected.id) != nil { loadingTabs.insert(id) }
        inputRevisions.removeValue(forKey: expected.id); pendingSearchNavigations.removeValue(forKey: expected.id)
        if pendingNativeSelection?.tabID == expected.id { pendingNativeSelection = nil }
        panes[id] = pane; attachedPageIDs.insert(page.identifier)
        render(store.state); requestNativeSelection()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, let tab = self.store.state.tabs.first(where: { $0.id == id }) else { return }
            let other = tab.spaceID != self.activeSpaceID ? self.store.state.spaces.first { $0.id == tab.spaceID }?.name : nil
            self.showToast(.backgroundTabCreated(inSpace: other, document: InternalPage.isInternal(tab.url)),
                           onTap: { [weak self] in _ = self?.selectTab(id) })
        }
        return true
    }
    var canResetCurrentTab: Bool {
        activePeek == nil && currentTabID.flatMap { id in visibleTabs.first { $0.id == id } }
            .map { canResetSavedTab($0) } == true
    }
    func resetCurrentTab() {
        guard activePeek == nil, let tab = visibleTabs.first(where: { $0.id == currentTabID }) else { return }
        resetSavedTab(tab)
    }
    private var visibleSavedResetTargets: [BrowserTab] {
        SavedTabResetTargets.collect(in: store.state, spaceID: activeSpaceID)
    }
    var canResetVisibleSavedTabs: Bool { visibleSavedResetTargets.contains { canResetSavedTab($0) } }
    func resetVisibleSavedTabs() {
        let actions = visibleSavedResetTargets.compactMap { prepareSavedTabReset($0) }
        for action in actions { _ = action() }
    }
    private func savedResetDestination(_ expected: BrowserTab, allowUnchanged: Bool) -> URL? {
        if !allowUnchanged { return expected.resetDestination }
        guard expected.archivedAt == nil, expected.kind == .favorite,
              !InternalPage.isInternal(expected.url), !InternalPage.isInternal(expected.savedURL),
              let url = URL(string: expected.savedURL), url.scheme != nil else { return nil }
        return url
    }
    private func resetSavedTab(_ expected: BrowserTab, allowUnchanged: Bool = false) {
        guard canResetSavedTab(expected, allowUnchanged: allowUnchanged),
              let destination = savedResetDestination(expected, allowUnchanged: allowUnchanged) else { return }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss(); tabSwitcher?.cancel()
        if let browser = browsers[expected.id] {
            pendingSearchNavigations.removeValue(forKey: expected.id)
            inputRevisions.removeValue(forKey: expected.id)
            browser.loadURL(destination)
        } else if !ownership.isClaimed(expected.id) {
            store.resetDormantSavedTab(expected)
        }
    }

    private func archiveTodayTabs(anchor: BrowserTab, order: [UUID], ids: Set<UUID>) {
        guard !isPopupWindow, !isClosing, !wholeWindowClose, !windowClosePending,
              window?.isKeyWindow == true, window?.attachedSheet == nil,
              anchor.profileID == activeProfileID, anchor.spaceID == activeSpaceID,
              SidebarTodayArchive.admits(anchorID: anchor.id, order: order, ids: ids, state: store.state,
                  spaceID: activeSpaceID, profileID: activeProfileID) else { return }
        archiveTabs(ids, reason: .manual)
    }

    private func archiveTabs(_ ids: Set<UUID>, reason: ArchiveReason, in space: BrowserSpace? = nil) {
        guard !isClosing, !wholeWindowClose, !ids.isEmpty else { return }
        if let message = retirementUnavailableReason?(ids) {
            if let window { ParcDialog.inform(in: window, .init(title: "These tabs can’t be closed together yet", message: message)) }
            return
        }
        let originSpace = activeSpaceID, originProfile = activeProfileID
        let spaceID = space?.id ?? originSpace, profileID = space?.profileID ?? originProfile
        prepareStoreContext()
        let undo: CloseUndo = reason == .clearButton
            ? .register(.clear, registered: { [weak self] in self?.showToast(.clearedTabs, at: .window) })
            : .register(.archive)
        closeTabsWithReopen(ids, reason: reason, undo: undo, shouldCommit: { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose,
                  self.activeSpaceID == originSpace, self.activeProfileID == originProfile else { return false }
            return ids.allSatisfy { id in self.store.state.tabs.contains {
                $0.id == id && $0.archivedAt == nil && $0.kind == .today
                    && $0.spaceID == spaceID && $0.profileID == profileID
            } }
        }) { [weak self] allowed in
            guard let self, allowed, !self.isClosing else { return }
            for id in ids { self.presentation.remove(id) }
            self.render(self.store.state)
            self.requestNativeSelection()
        }
    }

    private enum CloseUndo {
        case register(ClosedTabsUndo.Prompt, registered: (() -> Void)? = nil)
        case redo(ClosedTabsUndo.Prompt, (ClosedTabsUndo?) -> Void)
    }

    private func registerClosedTabsUndo(_ record: ClosedTabsUndo, registered: (() -> Void)?) {
        guard windowUndoOwnerAvailable else { return }
        let operation = folderUndo.appendClosedTabs(record, store: store, canUse: { [weak self] ids, direction in
            guard let self, self.windowUndoContextAvailable else { return false }
            return direction == .undo ? ids.allSatisfy { self.canUseOrMoveHere($0) } : self.retirementUnavailableReason?(ids) == nil
        }, close: { [weak self] ids, current, done in
            guard let self, self.windowUndoContextAvailable else { done(nil); return }
            self.prepareStoreContext()
            self.closeTabsWithReopen(ids, reason: .manual, undo: .redo(record.prompt, done), shouldCommit: { [weak self] in
                guard let self, self.windowUndoOwnerAvailable else { return false }
                return current()
            }) { [weak self] approved in
                guard let self, approved, !self.isClosing else { return }
                for id in ids { self.presentation.remove(id) }
                self.render(self.store.state)
                self.requestNativeSelection()
            }
        }, didUndo: { [weak self] undone in
            guard let self else { return }
            self.store.closedPageHistory.restore(undone.tabs.map(\.id).filter { id in
                self.store.state.tabs.contains { $0.id == id && $0.archivedAt == nil }
            })
            let focused = self.presentation.finishClosedTabsUndo(undone, state: self.store.state,
                available: { self.switcherCanUse($0) })
            if focused { self.focusedTabID = undone.focusedTabID }
            self.render(self.store.state)
            if focused { self.requestNativeSelection(); self.focusSelectedLocalContent() }
        }, onError: { [weak self] in self?.showError($0) }) { _ in registered?() }
        closeUndoOperations.add(operation)
    }

    private func closeTabsWithReopen(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                                     undo: CloseUndo = .register(.archive),
                                     completion: ((Bool) -> Void)? = nil) {
        closeTabsWithReopen(ids, reason: reason, undo: undo, shouldCommit: { true }, completion: completion)
    }

    private func closeTabsWithReopen(_ ids: Set<UUID>, reason: ArchiveReason = .manual,
                                     undo: CloseUndo = .register(.archive),
                                     shouldCommit: @escaping () -> Bool,
                                     completion: ((Bool) -> Void)? = nil) {
        let originals = store.state.tabs.filter { ids.contains($0.id) && $0.archivedAt == nil }
        let sourceSpace = originals.first(where: { $0.kind != .favorite })?.spaceID ?? activeSpaceID
        let profile = originals.first?.profileID ?? activeProfileID
        let intent = isPrivateBrowsing ? nil : ClosedItemIntent(ids: ids, state: store.state,
            spaceID: sourceSpace, profileID: profile, focusedTabID: currentTabID)
        let selection = selectedTabIDs, focus = focusedTabID, current = currentTabID
        let originSpace = activeSpaceID, originProfile = activeProfileID
        guard let nextSelection = FolderRemovalSelection.resolve(removing: Set(originals.map(\.id)),
            spaceID: originSpace, profileID: originProfile, state: store.state,
            selected: selection, focused: focus, referrerPool: presentation.referrerPool,
            previouslySelectedItemID: presentation.previouslySelectedItemID,
            available: { self.switcherCanUse($0) }) else {
            if case .redo(_, let done) = undo { done(nil) }
            completion?(false); return
        }
        let prompt: ClosedTabsUndo.Prompt
        switch undo { case .register(let value, _), .redo(let value, _): prompt = value }
        var record: ClosedTabsUndo?
        store.closeTabs(ids, reason: reason, selection: nextSelection, didCommit: { [weak self] before in
            guard let self else { return }
            record = ClosedTabsUndo(prompt: prompt, ids: ids, spaceID: sourceSpace, profileID: profile,
                                    focusedTabID: current, before: before, after: self.store.state)
        }, shouldCommit: { [weak self] in
            guard let self, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activeSpaceID == originSpace, self.activeProfileID == originProfile,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  shouldCommit() else { return false }
            return FolderRemovalSelection.resolve(removing: Set(originals.map(\.id)),
                spaceID: originSpace, profileID: originProfile, state: self.store.state,
                selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
                previouslySelectedItemID: self.presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) == nextSelection
        }) { [weak self] approved in
            guard let self else {
                if case .redo(_, let done) = undo { done(nil) }
                completion?(false); return
            }
            if approved, !self.isClosing {
                if let intent { self.closedItems.record(intent, in: self.store.state) }
                switch undo {
                case .register(_, let registered): if let record { self.registerClosedTabsUndo(record, registered: registered) }
                case .redo(_, let done): done(record)
                }
                let applied = self.presentation.finishFolderRemoval(nextSelection, state: self.store.state,
                    available: { self.switcherCanUse($0) })
                if applied { self.focusedTabID = nextSelection.focusedTabID }
                for id in ids where !self.selectedTabIDs.contains(id)
                    && self.store.state.tabs.contains(where: { $0.id == id && $0.archivedAt == nil }) {
                    if let note = self.noteEditors[id], note.editor.prepareToClose() {
                        note.editor.view.removeFromSuperview(); self.noteEditors.removeValue(forKey: id)
                    }
                    if let easel = self.easelEditors[id], self.embeddedEaselPages(forTabID: id).isEmpty {
                        easel.editor.retirePageOwner(); self.panes[id]?.clearNativeContent()
                        self.easelEditors.removeValue(forKey: id); self.easelFailures.removeValue(forKey: id)
                    }
                }
                if applied && !ids.isDisjoint(with: selection) {
                    self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()
                }
            } else if case .redo(_, let done) = undo { done(nil) }
            completion?(approved)
        }
    }

    @discardableResult
    private func closeTab(_ id: UUID) -> Bool {
        guard prepareNotesToClose([id]) else { return false }
        guard !wholeWindowClose, !isClosing, !windowClosePending,
              !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
              ownership.canUse(id, owner: presentationID),
              retirementUnavailableReason?([id]) == nil else { return false }
        prepareStoreContext()
        closeTabsWithReopen([id]) { [weak self] approved in
            guard let self, !self.isClosing else { return }
            guard approved else { self.returnIfUnshown(id); return }
            self.presentation.remove(id)
            if self.focusedTabID == id { self.focusedTabID = self.presentation.preferredFocusedTabID }
            self.render(self.store.state); self.requestNativeSelection()
        }
        return true
    }

    private func closeClickedSplitPane(_ id: UUID) {
        guard SplitPaneCloseAdmission.accepts(tabID: id, selected: selectedTabIDs, isPeek: activePeek != nil) else { return }
        closeTab(id)
    }

    func prepareClearTodayMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let original = window, let binding = nativeBinding else { return false }
        let spaceID = activeSpaceID, profileID = activeProfileID
        let command = BrowserClearTodayCommand(window: original,
            ownerIsAvailable: { [weak self, weak original, weak binding] in
                guard let self, let original, let binding, self.window === original,
                      self.nativeBinding === binding, binding.window === original else { return false }
                return !self.isPopupWindow && self.presentation.isReady && self.ownsSpaceCommandFocus
                    && self.activeSpaceID == spaceID && self.activeProfileID == profileID
                    && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && !self.windowCloseApproved && self.closingTabIDs.isEmpty
                    && self.modelRetirementIDs.isEmpty && self.transferringTabIDs.isEmpty
                    && self.resolvingTransfers.isEmpty && self.transferRecoveries.isEmpty
                    && self.spaceCreation == nil && self.pageCapture == nil
                    && self.tabSwitcher == nil && self.navigationHistory == nil
                    && self.themePopover == nil && !self.siteControlCenterDefers
                    && self.visibleTabs.contains { $0.kind == .today }
                    && PCNativeBrowserApplication.canUseWindowUndo(in: original)
            }, prepare: { [weak self] in self?.commandBar?.dismiss(restoreFocus: true) },
            clear: { [weak self] in self?.clearToday() })
        item.representedObject = command.isAvailable ? command : nil
        return command.isAvailable
    }

    private func clearToday() {
        archiveTabs(SpaceClearToday.ids(in: store.state, spaceID: activeSpaceID, profileID: activeProfileID), reason: .clearButton)
    }

    static func flushCookieStores() {
        if PCNativeBrowserApplication.responds(to: #selector(PCNativeBrowserApplication.flushCookieStores)) {
            PCNativeBrowserApplication.flushCookieStores()
        }
    }

    func persistTabHistory(all: Bool = false) {
        tabHistoryCapture?.cancel(); tabHistoryCapture = nil
        let ids = all ? Set(browsers.keys) : tabHistoryChanged
        tabHistoryChanged.removeAll()
        guard let archive = store.tabHistory,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.archivedNavigationState)) else { return }
        for id in ids where !closingTabIDs.contains(id) {
            guard let page = browsers[id]?.nativePage, !page.isClosed,
                  let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
                  tab.profileID == browserProfiles[id],
                  let navigation = page.archivedNavigationState() else { continue }
            archive.store(.init(url: tab.url, profileID: tab.profileID, navigation: navigation), for: id)
        }
    }

    private func scheduleTabHistoryCapture(_ id: UUID) {
        guard store.tabHistory != nil else { return }
        tabHistoryChanged.insert(id)
        guard tabHistoryCapture == nil else { return }
        let capture = DispatchWorkItem { [weak self] in self?.persistTabHistory() }
        tabHistoryCapture = capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: capture)
    }

    private func launchHistory(for tab: BrowserTab) -> NSObject? {
        guard let archive = store.tabHistory,
              PCNativePage.responds(to: #selector(PCNativePage.navigationState(archive:profilePath:))),
              let navigation = archive.takeLaunchNavigation(for: tab.id, url: tab.url, profileID: tab.profileID) else { return nil }
        return PCNativePage.navigationState(archive: navigation,
                                            profilePath: store.independentEngineProfilePath(for: tab.profileID))
    }

    private func scheduleCookieFlush() {
        guard cookieFlush == nil, !store.isEphemeral else { return }
        let flush = DispatchWorkItem { [weak self] in
            self?.cookieFlush = nil
            Self.flushCookieStores()
        }
        cookieFlush = flush
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: flush)
    }

    func canBeginPageRetirement(_ id: UUID) -> Bool {
        !wholeWindowClose && !isClosing && !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) && (nativePage(forTabID: id) != nil || !embeddedEaselPages(forTabID: id).isEmpty)
    }

    func beginPageRetirement(_ id: UUID) {
        if peeks.values.contains(where: { $0.parentTabID == id }) { peekRetirementParents.insert(id) }
        if let page = nativePage(forTabID: id), page.responds(to: #selector(PCNativePage.captureNavigationState)) {
            retiringPageHistory[id] = page.captureNavigationState()
        }
        closingTabIDs.insert(id)
        modelRetirementIDs.insert(id)
    }

    func canCommitPageRetirement(_ id: UUID, page: PCNativePage) -> Bool {
        !wholeWindowClose && !isClosing && modelRetirementIDs.contains(id)
            && (nativePage(forTabID: id) === page || peekPages(forTabID: id).contains { $0 === page }
                || embeddedEaselPages(forTabID: id).contains { $0 === page })
    }

    func finishPageRetirement(_ id: UUID, page: PCNativePage, closed: Bool) {
        if page.isEmbedded {
            if closed || page.isClosed { easelEditors[id]?.editor.pageObjects?.didClose(page) }
            closingTabIDs.remove(id); modelRetirementIDs.remove(id)
            return
        }
        if let peek = peeks[page.identifier] {
            if closed || page.isClosed { removePeek(peek) }
            else if peek.parentPage.isClosed { promotePeek(peek, split: false, orphaned: true) }
            return
        }
        peekRetirementParents.remove(id)
        closingTabIDs.remove(id)
        modelRetirementIDs.remove(id)
        if let history = retiringPageHistory.removeValue(forKey: id), closed {
            store.closedPageHistory.closed(id, state: history)
        }
        if closed, browsers[id]?.nativePage === page {
            releaseClosedTab(id, updateSavedTab: false)
        }
    }

    func refreshAfterPageRetirement() { render(store.state); requestNativeSelection() }

    private func releaseClosedTab(_ id: UUID, updateSavedTab: Bool) {
        pendingSearchNavigations.removeValue(forKey: id)
        inputRevisions.removeValue(forKey: id)
        if let retry = transferRecoveries[id] { retry(); return }
        guard browsers[id] != nil || panes[id] != nil || store.state.tabs.contains(where: { $0.id == id }) else { return }
        if pendingNativeSelection?.tabID == id { pendingNativeSelection = nil }
        if let browser = browsers.removeValue(forKey: id) {
            if let page = browser.nativePage { attachedPageIDs.remove(page.identifier) }
            browser.delegate = nil
            browser.removeFromSuperview()
        }
        closingTabIDs.remove(id); modelRetirementIDs.remove(id)
        liveTabModels.removeValue(forKey: id); browserProfiles.removeValue(forKey: id)
        requestedURLs.removeValue(forKey: id); failures.removeValue(forKey: id); loadingTabs.remove(id)
        panes[id]?.browser = nil
        easelEditors[id]?.editor.retirePageOwner()
        panes[id]?.clearNativeContent(); easelEditors.removeValue(forKey: id); easelFailures.removeValue(forKey: id)
        if nativeFullscreenTabID == id { restoreNativeFullscreenPresentation() }
        presentation.remove(id)
        ownership.release(id, owner: presentationID)
        tabHistoryChanged.remove(id)
        if updateSavedTab { store.closeTab(id) }
        if focusedTabID == id { focusedTabID = presentation.preferredFocusedTabID }
    }

    private func retireBrowserAfterModelChange(_ id: UUID) {
        if let page = browsers[id]?.nativePage, !peekPages(forTabID: id).isEmpty {
            closePageAndPeeks(id, page: page, updateSavedTab: false); return
        }
        guard !closingTabIDs.contains(id), !transferringTabIDs.contains(id), let browser = browsers[id] else { return }
        let original = liveTabModels[id]
        let expected = store.state.tabs.first { $0.id == id }
        closingTabIDs.insert(id); modelRetirementIDs.insert(id)
        browser.requestClose { [weak self, weak browser] result in
            guard let self, let browser, self.browsers[id] === browser else { return }
            self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
            if result == .closed { self.releaseClosedTab(id, updateSavedTab: false) }
            else if let original {
                if !self.store.restoreLiveTab(original, replacing: expected) {
                    self.failures[id] = "This page is still open because closing was cancelled."
                }
            }
            self.render(self.store.state)
        }
    }

    private func retirePages(_ leaving: [BrowserPane]) {
        for pane in leaving {
            if let page = pane.browser?.nativePage, let binding = nativeBinding, attachedPageIDs.contains(page.identifier) {
                if binding.responds(to: #selector(PCNativeBrowserWindow.pageWillPark(_:))) {
                    if !binding.pageWillPark(page) { attachedPageIDs.remove(page.identifier) }
                } else {
                    attachedPageIDs.remove(page.identifier)
                    binding.pageWillDetach(page)
                }
            }
            resignFocus(in: pane)
        }
    }
    private func parkPanes(_ leaving: [BrowserPane]) {
        for pane in leaving where pane.superview === splitView && !splitView.arrangedSubviews.contains(where: { $0 === pane }) {
            resignFocus(in: pane)
            parkedPages.addSubview(pane)
        }
    }
    private func resignFocus(in pane: BrowserPane) {
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: pane) {
            window?.makeFirstResponder(nil)
        }
    }
    private var canHoldPageSwitch: Bool {
        guard let window, window.isVisible, !window.isMiniaturized, !isClosing, !wholeWindowClose,
              let binding = nativeBinding else { return false }
        return binding.responds(to: #selector(PCNativeBrowserWindow.reportNextFrame(of:)))
    }
    private func drawsReportedFrame(_ tab: BrowserTab) -> Bool {
        guard !InternalPage.isInternal(tab.url), !rendersBlank(tab), !presentation.showsPlaceholder(tab.id),
              failures[tab.id] == nil, !closingTabIDs.contains(tab.id),
              let page = browsers[tab.id]?.nativePage, !page.isClosed, page.rendererCrash == nil,
              attachedPageIDs.contains(page.identifier),
              page.responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return false }
        return page.pageBackgroundColor != nil
    }
    private func scheduleSwitchHoldCap() {
        guard let deadline = switchHold.deadline else { return }
        let hold = switchHold.hold
        let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, self.switchHold.hold == hold, self.switchHold.isHolding else { return }
            let ended = self.switchHold.expire(at: ProcessInfo.processInfo.systemUptime)
            if ended.isEmpty { self.scheduleSwitchHoldCap() } else { self.finishPageSwitch(ended) }
        }
    }
    private func finishPageSwitch(_ ended: [BrowserPane]) {
        guard !ended.isEmpty else { return }
        guard !rendering else {
            DispatchQueue.main.async { [weak self] in self?.finishPageSwitch(ended) }
            return
        }
        parkPanes(ended)
        attachOwnedPages()
        synchronizeNativeLayout()
    }

    private func attachOwnedPages() {
        guard !attachingOwnedPages, let binding = nativeBinding, let window else { return }
        attachingOwnedPages = true
        defer { attachingOwnedPages = false; flushPendingNativeSelection() }
        for (id, browser) in browsers {
            guard !transferringTabIDs.contains(id), let page = browser.nativePage, !page.isClosed,
                  browser.window === window, !attachedPageIDs.contains(page.identifier) else { continue }
            guard ownership.claim(id, owner: presentationID, page: page.identifier) else { continue }
            if binding.pageDidAttach(page, container: browser) { attachedPageIDs.insert(page.identifier) }
            else { failures[id] = "The page could not attach to its browser window." }
        }
    }

    private func synchronizeNativeLayout() {
        guard !synchronizingNativeLayout, !isClosing else { return }
        synchronizingNativeLayout = true
        defer { synchronizingNativeLayout = false }
        nativeBinding?.synchronizeLayout()
    }

    private func requestNativeSelection() {
        reconcileCommandBar()
        navigationHistory?.validate()
        guard !applyingNativeSelection else { return }
        if let peek = activePeek, !peek.view.isHidden, !isClosing, !wholeWindowClose,
           !windowClosePending, !peek.page.isClosed {
            pendingNativeSelection = nil
            nativeBinding?.synchronizeSelectionAndLayout()
            refreshNavigationControls()
            return
        }
        closedItems.selected(selectedTabIDs)
        if currentBrowser == nil, selectedNativePage()?.isEmbedded == true {
            pendingNativeSelection = nil; nativeBinding?.synchronizeSelectionAndLayout(); refreshNavigationControls(); return
        }
        recordRecentTabSelection()
        pendingNativeSelection = nil
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              transferringTabIDs.isEmpty else { return }
        if presentation.isLocalSelection(currentTabID, state: store.state,
                                         hasNativeWrapper: currentBrowser != nil) {
            pendingNativeSelection = .local(currentTabID)
        } else {
            guard let id = currentTabID, let view = browsers[id],
                  !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
                  !store.retiringTabIDs.contains(id) else { return }
            pendingNativeSelection = .page(NativePageSelectionRequest(
                tabID: id, view: view, pageIdentifier: view.nativePage?.identifier))
        }
        flushPendingNativeSelection()
    }

    private func flushPendingNativeSelection() {
        guard !applyingNativeSelection, !synchronizingNativeLayout, !attachingOwnedPages,
              let pending = pendingNativeSelection else { return }
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              transferringTabIDs.isEmpty, pending.tabID == currentTabID,
              let binding = nativeBinding, let window, binding.window === window else {
            pendingNativeSelection = nil
            return
        }
        switch pending {
        case .local(let id):
            guard presentation.isLocalSelection(id, state: store.state,
                                                hasNativeWrapper: currentBrowser != nil),
                  selectedNativePage() == nil else {
                pendingNativeSelection = nil
                return
            }
        case .page(var request):
            guard let view = request.view, browsers[request.tabID] === view,
                  !closingTabIDs.contains(request.tabID), !modelRetirementIDs.contains(request.tabID),
                  !store.retiringTabIDs.contains(request.tabID) else {
                pendingNativeSelection = nil
                return
            }
            guard let page = view.nativePage else { return }
            guard request.pageIdentifier == nil || request.pageIdentifier == page.identifier,
                  existingNativeSelection(binding, page)?.1 === view else {
                pendingNativeSelection = nil
                return
            }
            request.pageIdentifier = page.identifier
            pendingNativeSelection = .page(request)
            guard attachedPageIDs.contains(page.identifier),
                  page.nativeView.window === window, page.nativeView.isDescendant(of: view) else { return }
        }
        pendingNativeSelection = nil
        synchronizingNativeLayout = true
        defer { synchronizingNativeLayout = false }
        binding.synchronizeSelectionAndLayout()
        refreshNavigationControls()
    }

    func embeddedEaselPages(forTabID id: UUID) -> [PCNativePage] { easelEditors[id]?.editor.pageObjects?.pages ?? [] }
    private func embeddedEaselOwner(_ page: PCNativePage) -> (UUID, EaselBrowserObjects)? {
        for (id, pane) in easelEditors {
            if let objects = pane.editor.pageObjects, objects.contains(page) { return (id, objects) }
        }
        return nil
    }
    private func retireEaselAfterModelChange(_ id: UUID, cached: EaselPane) {
        guard !closingTabIDs.contains(id), let objects = cached.editor.pageObjects else { return }
        let pages = objects.pages, expected = store.state.tabs.first { $0.id == id }
        closingTabIDs.insert(id); modelRetirementIDs.insert(id)
        PCNativeBrowserApplication.requestClosePages(pages, shouldCommit: { [weak self, weak objects] in
            MainActor.assumeIsolated {
                guard let self, let objects else { return false }
                return !self.isClosing && self.easelEditors[id]?.editor.pageObjects === objects
                    && self.store.state.tabs.first(where: { $0.id == id }) == expected
            }
        }, completion: { [weak self, weak objects] allowed in
            MainActor.assumeIsolated {
                guard let self, let objects, self.easelEditors[id]?.editor.pageObjects === objects else { return }
                self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
                if allowed {
                    cached.editor.retirePageOwner(); self.panes[id]?.clearNativeContent(); self.easelEditors.removeValue(forKey: id)
                } else { _ = self.store.restoreLiveTab(cached.originalTab, replacing: expected) }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func peekPages(forTabID id: UUID) -> [PCNativePage] {
        peeks.values.filter { $0.parentTabID == id && !$0.page.isClosed }.map(\.page)
    }

    @MainActor private final class SplitLinkLease: NSObject {
        weak var owner: BrowserWindowController?
        weak var source: PCNativePage?
        let snapshot: SplitLinkSnapshot
        let layout: BrowserSplitLayout?

        init(owner: BrowserWindowController, source: PCNativePage, focusedID: UUID) {
            self.owner = owner; self.source = source
            layout = owner.activeSplitLayout
            snapshot = SplitLinkSnapshot(spaceID: owner.activeSpaceID, profileID: owner.activeProfileID,
                selection: owner.selectedTabIDs, focusedID: focusedID, sourceURL: source.url,
                generation: owner.splitLinkGeneration)
        }
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, splitLinkLeaseFor page: PCNativePage) -> Any? {
        guard nativeBrowser(browser, canRouteCurrentLinkFrom: page),
              let entry = browsers.first(where: { $0.value.nativePage === page }),
              currentTabID == entry.key, browserViewCanOpenLinkInSplitView(entry.value) else { return nil }
        return SplitLinkLease(owner: self, source: page, focusedID: entry.key)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, isSplitLinkLeaseCurrent value: Any,
                       for page: PCNativePage) -> Bool {
        guard let lease = value as? SplitLinkLease, lease.owner === self, lease.source === page,
              lease.layout == activeSplitLayout,
              lease.snapshot.accepts(spaceID: activeSpaceID, profileID: activeProfileID,
                  selection: selectedTabIDs, focusedID: currentTabID, sourceURL: page.url,
                  generation: splitLinkGeneration),
              nativeBrowser(browser, canRouteCurrentLinkFrom: page),
              let view = browsers[lease.snapshot.focusedID], view.nativePage === page else { return false }
        return browserViewCanOpenLinkInSplitView(view)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canRouteCurrentLinkFrom page: PCNativePage) -> Bool {
        browser === nativeBinding && !isPopupWindow && activePeek == nil
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty && commandBar == nil
            && libraryView == nil && window?.attachedSheet == nil && window?.isKeyWindow == true
            && selectedNativePage() === page && !page.isClosed
            && PCNativeBrowserApplication.owner(of: page) === browser
            && !store.isProfileRemovalPending(activeProfileID)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, linkRouteSourceSpaceFor page: PCNativePage) -> String? {
        guard nativeBrowser(browser, canRouteCurrentLinkFrom: page) else { return nil }
        return activeSpaceID.uuidString
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, routeCurrentLinkFrom page: PCNativePage,
                       targetURL: URL, authenticationContinuation: Bool) -> PCNativeLinkRoute? {
        guard nativeBrowser(browser, canRouteCurrentLinkFrom: page),
              ["http", "https"].contains(targetURL.scheme?.lowercased() ?? ""),
              let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == activeProfileID else { return nil }
        if selectedTabIDs.count == 1 && (tab.kind == .favorite || tab.kind == .pinned) {
            guard let targetHost = targetURL.host,
                  targetHost != page.url?.host,
                  targetHost != URL(string: tab.savedURL)?.host,
                  !authenticationContinuation, !page.authenticationFlowUnlocked else { return nil }
        }
        let spaces = store.state.spaces.map { LinkRoutingSpace(id: $0.id, profileID: $0.profileID) }
        guard let decision = store.linkRouting.decision(for: targetURL, spaces: spaces, currentSpaceID: activeSpaceID),
              let rule = decision.matchedRuleID, !decision.usedUnavailableDestinationFallback,
              decision.spaceID != activeSpaceID,
              let space = store.state.spaces.first(where: { $0.id == decision.spaceID }),
              !store.isProfileRemovalPending(space.profileID) else { return nil }
        return PCNativeLinkRoute(ruleIdentifier: rule.uuidString, spaceIdentifier: space.id.uuidString,
                                 profilePath: store.independentEngineProfilePath(for: space.profileID))
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, authenticationReturnURLFor page: PCNativePage) -> URL? {
        guard browser === nativeBinding,
              let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.kind == .favorite || tab.kind == .pinned else { return nil }
        return URL(string: tab.savedURL)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canAcceptLinkRoute route: PCNativeLinkRoute) -> Bool {
        guard browser === nativeBinding, let spaceID = UUID(uuidString: route.spaceIdentifier),
              let space = store.state.spaces.first(where: { $0.id == spaceID }),
              route.profilePath == store.independentEngineProfilePath(for: space.profileID) else { return false }
        return canAcceptNativeLinkRoute(profileID: space.profileID)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, prepareLinkRoute route: PCNativeLinkRoute) -> PCNativeBrowserWindow? {
        guard browser === nativeBinding, !isClosing, !wholeWindowClose else { return nil }
        return onPrepareLinkRoute?(route)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didFailLinkRoute error: Error) {
        guard browser === nativeBinding, !isClosing, let window, window.attachedSheet == nil else { return }
        ParcDialog.inform(in: window, .init(title: "Couldn’t open link in its Space", message: error.localizedDescription), queued: true)
    }

    func canAcceptNativeLinkRoute(profileID: UUID) -> Bool {
        if isPrivateBrowsing { return false }
        return !isPopupWindow && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && window?.attachedSheet == nil
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && activeProfileID == profileID && !store.isProfileRemovalPending(profileID)
    }

    func prepareNativeLinkDestination(profileID: UUID) -> PCNativeBrowserWindow? {
        guard canAcceptNativeLinkRoute(profileID: profileID), let nativeBinding else { return nil }
        if !presentation.isReady && browsers.isEmpty { preparedForRoutedPage = true }
        return nativeBinding
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, shouldOpenCurrentLinkInPeekFrom page: PCNativePage,
                       targetURL: URL) -> Bool {
        guard nativeBrowser(browser, shouldOpenNewPageInPeekFrom: page, targetURL: targetURL),
              !page.authenticationFlowUnlocked,
              let targetHost = targetURL.host,
              let currentHost = page.url?.host,
              let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              let tab = store.state.tabs.first(where: { $0.id == id }),
              let savedHost = URL(string: tab.savedURL)?.host else { return false }
        return targetHost != currentHost && targetHost != savedHost
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, allowsPeekWithShift shift: Bool) -> Bool {
        guard browser === nativeBinding, !isClosing, !wholeWindowClose else { return false }
        return shift ? store.state.settings.shiftPeekEnabled : store.state.settings.automaticPeekEnabled
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, shouldOpenNewPageInPeekFrom page: PCNativePage,
                       targetURL: URL) -> Bool {
        guard nativeBrowser(browser, canPresentPeekFrom: page), selectedTabIDs.count == 1,
              ["http", "https"].contains(targetURL.scheme?.lowercased() ?? ""),
              let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == activeProfileID else { return false }
        return tab.kind == .favorite || tab.kind == .pinned
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canPresentPeekFrom page: PCNativePage) -> Bool {
        let shown = activePeek == nil && selectedNativePage() === page
        return (shown || peekUndoOpen?.parent == page.identifier)
            && canHostPeek(browser, over: page, overLibrary: archivePreviewRequest?.parent == page.identifier)
    }

    private func canHostPeek(_ browser: PCNativeBrowserWindow, over page: PCNativePage, overLibrary: Bool = false) -> Bool {
        windowAdmitsPeek(browser, overLibrary: overLibrary) && !page.isClosed
            && PCNativeBrowserApplication.owner(of: page) === browser
            && !peeks.values.contains { $0.parentPage === page }
    }

    private func windowAdmitsPeek(_ browser: PCNativeBrowserWindow, overLibrary: Bool = false) -> Bool {
        browser === nativeBinding && !isPopupWindow
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved && nativeFullscreenTabID == nil
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && commandBar == nil && (libraryView == nil || overLibrary) && window?.attachedSheet == nil
            && window?.isKeyWindow == true
    }

    @discardableResult
    private func previewArchivedItem(_ id: UUID, profileID: UUID) -> Bool {
        if let peek = activePeek, archivePreviews[peek.identity] != nil {
            guard archivePreviews[peek.identity]?.tabs.first?.id != id else { return true }
            guard peek.canRequestExit else { return false }
            queuedArchivePreview = (id, profileID)
            peek.requestDismiss(.closeButton)
            return true
        }
        guard archivePreviewRequest == nil, peekUndoOpen == nil, activePeek == nil, let binding = nativeBinding,
              let current = currentTabID, store.state.tabs.contains(where: { $0.id == current && $0.archivedAt == nil }),
              let parent = browsers[current]?.nativePage, selectedNativePage() === parent,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
              canHostPeek(binding, over: parent, overLibrary: true),
              let lease = store.acquireArchivePreview(id: id, profileID: profileID) else { return false }
        guard lease.tabs.count == 1, let url = URL(string: lease.tabs[0].url),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            store.releaseArchivePreview(lease); return false
        }
        let token = UUID()
        archivePreviewRequest = (parent.identifier, lease, token)
        guard parent.openPeek(url: url) else {
            archivePreviewRequest = nil; store.releaseArchivePreview(lease); return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let request = self.archivePreviewRequest, request.token == token else { return }
            self.archivePreviewRequest = nil; self.store.releaseArchivePreview(request.lease)
        }
        return true
    }

    private func adoptPeek(_ page: PCNativePage, binding: PCNativeBrowserWindow) -> NSView? {
        guard let parent = page.peekParent else { return nil }
        var undo = peekUndoOpen.flatMap { $0.parent == parent.identifier ? $0.operation : nil }
        if let pending = undo, !(page.responds(to: #selector(getter: PCNativePage.isReopenedPeek))
            ? page.isReopenedPeek : page.url?.absoluteString == pending.record.url.absoluteString) {
            undo = nil; peekUndoOpen = nil
        }
        defer { if undo != nil { peekUndoOpen = nil } }
        let request = archivePreviewRequest.flatMap { $0.parent == parent.identifier ? $0 : nil }
        let admitted = nativeBrowser(binding, canPresentPeekFrom: parent)
        if request != nil { archivePreviewRequest = nil }
        let archive = request.flatMap { request in undo == nil
            && page.responds(to: #selector(getter: PCNativePage.isReopenedPeek)) && page.isReopenedPeek ? request.lease : nil }
        if let request, archive == nil { store.releaseArchivePreview(request.lease) }
        var previewAdopted = false
        defer { if let archive, !previewAdopted { store.releaseArchivePreview(archive) } }
        guard admitted, request == nil || archive != nil,
              let id = browsers.first(where: { $0.value.nativePage === parent })?.key,
              let profile = browserProfiles[id],
              let parentTab = store.state.tabs.first(where: { $0.id == id }),
              page.profilePath == parent.profilePath,
              parent.profilePath == store.independentEngineProfilePath(for: profile),
              archive.map({ $0.profileID == profile && store.archivePreviewIsValid($0) }) ?? true,
              ownership.canAdopt(page.identifier) else { return nil }
        let peek = PeekController(page: page, parent: parent, parentTabID: id, sourceSpaceID: parentTab.spaceID)
        guard ownership.claim(peek.identity, owner: presentationID, page: page.identifier) else { peek.finish(); return nil }
        peeks[page.identifier] = peek
        if let archive { archivePreviews[peek.identity] = archive; previewAdopted = true }
        undo?.openedPeek = peek.identity
        wirePeek(peek, binding: binding)
        let shown = activePeek === peek
        if shown { tabSwitcher?.cancel(); sidebarPreviews?.dismiss(); if archive == nil { closeLibrary(restoreFocus: false) } }
        else if undo != nil { undoHiddenPeek = peek.identity }
        let entryFocus = PeekFocusReturn(source: parent.nativeView)
        pageHost.addSubview(peek.view, positioned: .above, relativeTo: nil)
        peek.view.frame = pageHost.bounds; peek.view.layoutSubtreeIfNeeded()
        if !shown { peek.setVisible(false) }
        DispatchQueue.main.async { [weak self, weak peek] in
            guard let self, let peek, self.peeks[page.identifier] === peek, !page.isClosed else { return }
            self.layoutPeeks()
            if self.activePeek === peek { peek.view.animatePresentation() }
            self.nativeBinding?.synchronizeSelectionAndLayout()
            if let window = self.window {
                entryFocus?.perform(in: window, ownerIsAvailable: {
                    self.activePeek === peek && peek.canInteract?() == true
                        && PCNativeBrowserApplication.canUseWindowUndo(in: window)
                }) { _ in peek.focus() }
            }
        }
        return peek.browser
    }

    private func wirePeek(_ peek: PeekController, binding: PCNativeBrowserWindow) {
        let page = peek.page, id = peek.parentTabID
        peek.view.adoptWindowTheme(rootView)
        peek.canInteract = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.peeks[page.identifier] === peek && self.activePeek === peek
                && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.closingTabIDs.contains(id) && !self.transferringTabIDs.contains(id)
                && !page.isClosed && PCNativeBrowserApplication.owner(of: page) === binding
                && peek.browser.window === self.window && binding.window === self.window
        }
        peek.canExpand = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.peekPromotionDestination(peek) != nil
        }
        peek.canSplit = { [weak self, weak peek] in
            guard let self, let peek else { return false }
            return self.activePeek === peek && self.selectedTabIDs.contains(id)
                && self.selectedTabIDs.count < 4 && self.nativeFullscreenTabID == nil
        }
        peek.onClose = { [weak self, weak peek] in
            guard let self, let peek, page.isClosed else { return }; self.removePeek(peek)
        }
        peek.onCloseRefused = { [weak self, weak peek] in
            guard let self, let peek else { return }
            if self.archivePreviews[peek.identity] != nil { self.queuedArchivePreview = nil }
            guard let redo = self.peekRedo, redo.peek == peek.identity else { return }
            self.peekRedo = nil; redo.done(nil)
        }
        peek.onPromote = { [weak self, weak peek] split in
            guard let self, let peek else { return }; self.promotePeek(peek, split: split)
        }
        peek.onUpdate = { [weak self] in self?.refreshLivePageChromeOrRender() }
        peek.onMediaChange = { [weak self] in self?.scheduleMediaRefresh() }
        peek.onContextImage = { [weak self, weak peek] image in
            guard let self, let peek else { return }; self.browserView(peek.browser, addContextImageToEasel: image)
        }
    }

    private func layoutPeeks() {
        for peek in peeks.values {
            peek.view.frame = pageHost.bounds
            let visible = activePeek === peek
            peek.setVisible(visible)
            peek.view.layoutSubtreeIfNeeded()
        }
    }

    private func recordClosedPeek(_ peek: PeekController, url: URL) {
        let redo = peekRedo.flatMap { $0.peek == peek.identity ? $0 : nil }
        if redo != nil { peekRedo = nil }
        guard peeks[peek.page.identifier] === peek, !isPopupWindow,
              !isClosing, !wholeWindowClose,
              PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
              let parent = store.state.tabs.first(where: { $0.id == peek.parentTabID && $0.archivedAt == nil })
        else { redo?.done(nil); return }
        let record = ClosedPeekRecord(id: UUID(), url: url, parentTabID: parent.id, profileID: parent.profileID)
        if let history = peek.dismissedNavigationState { store.closedPageHistory.closed(record.id, state: history) }
        if !isPrivateBrowsing { closedItems.recordPeek(record, in: store.state) }
        if let redo { redo.done(record) } else { registerClosedPeekUndo(record) }
    }

    private func registerClosedPeekUndo(_ record: ClosedPeekRecord) {
        guard windowUndoOwnerAvailable, record.isValid(in: store.state) else { return }
        let operation = folderUndo.appendClosedPeek(record, state: { [weak self] in self?.store.state }, canOpen: { [weak self] operation in
            guard let self, self.windowUndoContextAvailable, self.peekUndoOpen == nil, self.archivePreviewRequest == nil,
                  let binding = self.nativeBinding,
                  PCNativePage.instancesRespond(to: #selector(PCNativePage.openPeek(url:))),
                  self.switcherCanUse(operation.record.parentTabID) else { return false }
            guard let page = self.closedPeekParentPage(operation.record) else {
                self.pruneAwaitedPeeks()
                return self.peekUndoAwaitingParent[operation.record.parentTabID] == nil
                    && self.browsers[operation.record.parentTabID] == nil && self.windowAdmitsPeek(binding)
            }
            return self.canHostPeek(binding, over: page)
        }, open: { [weak self] operation in
            guard let self, self.windowUndoContextAvailable, self.peekUndoOpen == nil,
                  self.switcherCanUse(operation.record.parentTabID) else { return false }
            if let page = self.closedPeekParentPage(operation.record) {
                guard self.openUndonePeek(operation, over: page) else { return false }
            } else {
                self.pruneAwaitedPeeks()
                let parent = operation.record.parentTabID
                guard self.peekUndoAwaitingParent[parent] == nil, self.browsers[parent] == nil else { return false }
                self.peekUndoAwaitingParent[parent] = operation; self.awaitedPeekRetries.remove(parent)
            }
            _ = self.closedItems.consume(stepID: operation.record.id)
            return true
        }, isOpen: { [weak self] operation in
            guard let self else { return false }
            self.pruneAwaitedPeeks()
            return self.peekUndoOpen?.operation === operation || self.peekUndoAwaitingParent.values.contains { $0 === operation }
                || self.peek(operation.openedPeek) != nil
        }, canClose: { [weak self] operation in
            guard let self, self.windowUndoContextAvailable, self.peekRedo == nil else { return false }
            if self.peekUndoAwaitingParent.values.contains(where: { $0 === operation }) { return true }
            guard let peek = self.peek(operation.openedPeek), !peek.closePending, !peek.page.isClosed else { return false }
            return self.activePeek === peek ? peek.canPrepareExit : peek.view.isHidden
        }, close: { [weak self] operation, done in
            guard let self, self.windowUndoContextAvailable, self.peekRedo == nil else { done(nil); return }
            if let parent = self.peekUndoAwaitingParent.first(where: { $0.value === operation })?.key {
                self.peekUndoAwaitingParent.removeValue(forKey: parent); self.awaitedPeekRetries.remove(parent)
                let previous = operation.record
                let record = ClosedPeekRecord(id: UUID(), url: previous.url, parentTabID: previous.parentTabID,
                                              profileID: previous.profileID)
                if let history = self.store.closedPageHistory.take(previous.id) { self.store.closedPageHistory.closed(record.id, state: history) }
                if !self.isPrivateBrowsing { self.closedItems.recordPeek(record, in: self.store.state) }
                done(record)
                return
            }
            guard let peek = self.peek(operation.openedPeek), !peek.closePending else { done(nil); return }
            self.peekRedo = (peek.identity, done)
            if self.activePeek === peek { peek.requestDismiss(.closeShortcut) } else { peek.closeWhileHidden() }
            if !peek.closePending, let redo = self.peekRedo, redo.peek == peek.identity {
                self.peekRedo = nil; redo.done(nil)
            }
        }) { _ in }
        peekUndoOperations.add(operation)
    }

    private func closedPeekParentPage(_ record: ClosedPeekRecord) -> PCNativePage? {
        guard let page = browsers[record.parentTabID]?.nativePage, !page.isClosed,
              page.profilePath == store.independentEngineProfilePath(for: record.profileID),
              page.responds(to: #selector(PCNativePage.openPeek(url:))) else { return nil }
        return page
    }

    private func peek(_ identity: UUID?) -> PeekController? {
        identity.flatMap { identity in peeks.values.first { $0.identity == identity } }
    }

    private func openUndonePeek(_ operation: ClosedPeekUndoOperation, over page: PCNativePage) -> Bool {
        guard peekUndoOpen == nil, archivePreviewRequest == nil else { return false }
        let token = UUID()
        peekUndoOpen = (page.identifier, operation, token)
        guard openClosedPeek(operation.record, over: page) else { peekUndoOpen = nil; return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.peekUndoOpen?.token == token else { return }
            self.peekUndoOpen = nil
        }
        return true
    }

    private func openClosedPeek(_ record: ClosedPeekRecord, over page: PCNativePage) -> Bool {
        guard let history = store.closedPageHistory.take(record.id) as? NSObject else { return page.openPeek(url: record.url) }
        let opened = page.responds(to: #selector(PCNativePage.openPeek(url:navigationState:)))
            ? page.openPeek(url: record.url, navigationState: history) : page.openPeek(url: record.url)
        if !opened { store.closedPageHistory.closed(record.id, state: history) }
        return opened
    }

    private func openAwaitedPeek(over parentTabID: UUID) {
        pruneAwaitedPeeks()
        guard let operation = peekUndoAwaitingParent[parentTabID], selectedTabIDs.contains(parentTabID),
              let page = closedPeekParentPage(operation.record), browsers[parentTabID]?.url != nil,
              !loadingTabs.contains(parentTabID) else { return }
        if openUndonePeek(operation, over: page) {
            peekUndoAwaitingParent.removeValue(forKey: parentTabID); awaitedPeekRetries.remove(parentTabID)
        } else {
            awaitedPeekRetries.insert(parentTabID)
            if peekUndoOpen != nil { peekUndoSlotWaiters.refused(parentTabID) }
        }
    }

    private func pruneAwaitedPeeks() {
        for (parent, operation) in peekUndoAwaitingParent
        where !operation.record.isValid(in: store.state) || !ownership.canUse(parent, owner: presentationID) {
            peekUndoAwaitingParent.removeValue(forKey: parent); awaitedPeekRetries.remove(parent)
        }
    }

    private func removePeek(_ peek: PeekController) {
        guard peeks[peek.page.identifier] === peek else { return }
        let archive = archivePreviews.removeValue(forKey: peek.identity)
        if let archive { store.releaseArchivePreview(archive) }
        else if archivePreviewRemnants.remove(peek.identity) == nil, peek.page.isClosed, let url = peek.dismissedURL {
            recordClosedPeek(peek, url: url)
        }
        if let redo = peekRedo, redo.peek == peek.identity { peekRedo = nil; redo.done(nil) }
        if undoHiddenPeek == peek.identity { undoHiddenPeek = nil }
        let focusReturn = peek.takeFocusReturn()
        let binding = nativeBinding
        peeks.removeValue(forKey: peek.page.identifier)
        ownership.release(peek.identity, owner: presentationID)
        inputRevisions.removeValue(forKey: peek.identity); zoomLevels.removeValue(forKey: peek.identity)
        peek.finish()
        if !isClosing && !wholeWindowClose {
            layoutPeeks(); updateNavigation(); requestNativeSelection()
            if let window, let binding {
                focusReturn?.perform(in: window, ownerIsAvailable: {
                    self.currentTabID == peek.parentTabID && self.activePeek == nil
                        && self.browsers[peek.parentTabID]?.nativePage === peek.parentPage
                        && self.nativeBinding === binding && self.commandBar == nil
                        && !self.closingTabIDs.contains(peek.parentTabID)
                        && !self.modelRetirementIDs.contains(peek.parentTabID)
                        && !self.peekRetirementParents.contains(peek.parentTabID)
                        && !self.store.retiringTabIDs.contains(peek.parentTabID)
                        && !self.transferringTabIDs.contains(peek.parentTabID)
                        && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                        && PCNativeBrowserApplication.canUseWindowUndo(in: window)
                }) { _ in _ = binding.requestFocus(for: peek.parentPage) }
            }
            if archive != nil, let next = queuedArchivePreview {
                queuedArchivePreview = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.libraryView?.kind == .archive, self.activeProfileID == next.profileID else { return }
                    self.previewArchivedItem(next.id, profileID: next.profileID)
                }
            }
        }
    }

    private func peekPromotionDestination(_ peek: PeekController) -> BrowserSpace? {
        guard activePeek === peek, peek.canInteract?() == true,
              let parent = store.state.tabs.first(where: { $0.id == peek.parentTabID && $0.archivedAt == nil }),
              let space = store.state.spaces.first(where: { $0.id == activeSpaceID }),
              space.profileID == parent.profileID, space.profileID == activeProfileID,
              peek.page.profilePath == store.independentEngineProfilePath(for: space.profileID) else { return nil }
        return space
    }

    func preparePeekOpenMenuItem(_ item: NSMenuItem, preservingTarget: Bool) -> Bool {
        if preservingTarget, let command = item.representedObject as? PeekOpenCommand {
            return command.isAvailable
        }
        item.representedObject = nil; item.isHidden = true; item.image = nil
        item.title = "Open Peek in Current Space"
        guard let original = window, let peek = activePeek,
              let space = peekPromotionDestination(peek) else { return false }
        let command = PeekOpenCommand(window: original, targetIsAvailable: { [weak self, weak original, weak peek] in
            guard let self, let original, let peek, self.window === original else { return false }
            return self.ownsSpaceCommandFocus && self.commandBar == nil && peek.canRequestExit
                && self.peekPromotionDestination(peek)?.id == space.id
        }, execute: { [weak self, weak peek] in
            guard let self, let peek else { return }
            self.promotePeek(peek, split: false)
        })
        guard command.isAvailable else { return false }
        item.representedObject = command; item.isHidden = false
        item.title = "Open in " + space.name
        let icon = (space.customIcon?.image(size: 12)
            ?? NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil))?.copy() as? NSImage
        icon?.size = NSSize(width: 12, height: 12)
        item.showImage(icon)
        return true
    }

    private func promotePeek(_ peek: PeekController, split: Bool, orphaned: Bool = false) {
        guard peeks[peek.page.identifier] === peek, !peek.page.isClosed, !peek.closePending,
              !isClosing, !wholeWindowClose, !promotingPeek,
              !split || peek.canSplit?() == true,
              let binding = nativeBinding else { return }
        promotingPeek = true
        defer { promotingPeek = false }
        let oldSelection = selectedTabIDs
        let focusReturn = orphaned ? nil : PeekFocusReturn(source: peek.view)
        let creation: TabCreationProvenance?
        let destinationID: UUID
        if orphaned {
            creation = nil
            destinationID = peek.sourceSpaceID
        } else {
            guard let destination = peekPromotionDestination(peek),
                  let parent = store.state.tabs.first(where: {
                      $0.id == peek.parentTabID && $0.archivedAt == nil
                  }), browsers[parent.id]?.nativePage === peek.parentPage,
                  !peek.parentPage.isClosed,
                  PCNativeBrowserApplication.owner(of: peek.parentPage) === binding,
                  PCNativeBrowserApplication.owner(of: peek.page) === binding,
                  peek.parentPage.profilePath == peek.page.profilePath,
                  peek.page.profilePath == store.independentEngineProfilePath(for: parent.profileID)
            else { return }
            destinationID = destination.id
            creation = TabCreationProvenance(referrerID: parent.id, activeTabID: nil,
                profileID: parent.profileID, state: store.state)
        }
        let archive = orphaned ? nil : archivePreviews.removeValue(forKey: peek.identity)
        if orphaned, let lease = archivePreviews.removeValue(forKey: peek.identity) { store.releaseArchivePreview(lease) }
        let restored = archive.map { store.restoreArchivePreview($0, destination: .putBack(currentSpaceID: destinationID, requestedSpaceID: nil)) }
        if let archive, restored?.count != 1 {
            if restored?.isEmpty == true, store.archivePreviewIsValid(archive) { archivePreviews[peek.identity] = archive }
            else { store.releaseArchivePreview(archive) }
            return
        }
        guard let id = restored?.first ?? store.adoptNativePage(url: peek.browser.url, title: peek.browser.title,
              profilePath: peek.page.profilePath, preferredSpaceID: destinationID, select: false,
              creation: creation),
              let tab = store.state.tabs.first(where: { $0.id == id }) else { return }
        binding.pageWillDetach(peek.page)
        let pane = makePane(tab)
        let view = peek.browser
        pane.browser = view; pane.showBrowser(); parkedPages.addSubview(pane)
        guard binding.pageDidAttach(peek.page, container: view) else {
            pane.browser = nil; pane.removeFromSuperview()
            peek.view.content.addSubview(view); view.frame = peek.view.content.bounds
            _ = binding.pageDidAttach(peek.page, container: view)
            if archive == nil { store.removeTab(id) } else { abandonRestoredPreview(peek) }
            return
        }
        ownership.release(peek.identity, owner: presentationID)
        guard ownership.claim(id, owner: presentationID, page: peek.page.identifier) else {
            binding.pageWillDetach(peek.page)
            pane.browser = nil; pane.removeFromSuperview()
            peek.view.content.addSubview(view); view.frame = peek.view.content.bounds
            _ = binding.pageDidAttach(peek.page, container: view)
            _ = ownership.claim(peek.identity, owner: presentationID, page: peek.page.identifier)
            if archive == nil { store.removeTab(id) } else { abandonRestoredPreview(peek) }
            return
        }
        browsers[id] = view; browserProfiles[id] = tab.profileID; liveTabModels[id] = tab
        requestedURLs[id] = tab.url; panes[id] = pane
        peeks.removeValue(forKey: peek.page.identifier)
        peek.finish(); view.delegate = self
        attachedPageIDs.insert(peek.page.identifier)
        zoomLevels[id] = zoomLevels.removeValue(forKey: peek.identity)
        inputRevisions.removeValue(forKey: peek.identity)
        if !orphaned { presentation.recordPeekPromotion(id, state: store.state) }
        let removal = (!split && !orphaned)
            ? presentationSetMediaRemoval(capturing: oldSelection, remaining: { Set(self.selectedTabIDs) }) {
                self.selectedTabIDs == [id]
            }
            : nil
        presentation.adopt(id, state: store.state, foreground: !orphaned)
        if split {
            prepareStoreContext(); store.setSplit(oldSelection + [id])
            presentation.captureCommand(store.state) { ownership.canUse($0, owner: presentationID) }
        }
        if !orphaned { focusedTabID = id }
        if archive != nil { closeLibrary(restoreFocus: false) }
        promotingPeek = false
        render(store.state)
        removal?()
        requestNativeSelection()
        if let window {
            focusReturn?.perform(in: window, ownerIsAvailable: {
                self.nativeBinding === binding && self.currentBrowser?.nativePage === peek.page
                    && self.activePeek == nil && self.commandBar == nil
                    && !self.closingTabIDs.contains(id) && !self.modelRetirementIDs.contains(id)
                    && !self.store.retiringTabIDs.contains(id) && !self.transferringTabIDs.contains(id)
                    && !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                    && PCNativeBrowserApplication.canUseWindowUndo(in: window)
            }) { _ in _ = binding.requestFocus(for: peek.page) }
        }
    }

    private func abandonRestoredPreview(_ peek: PeekController) {
        archivePreviewRemnants.insert(peek.identity)
        promotingPeek = false
        render(store.state); layoutPeeks()
        if peek.view.isHidden { peek.closeWhileHidden() } else { peek.requestDismiss(.closeButton) }
    }

    private func closePageAndPeeks(_ id: UUID, page: PCNativePage, updateSavedTab: Bool) {
        guard !closingTabIDs.contains(id), !wholeWindowClose, !isClosing,
              !transferringTabIDs.contains(id) else { return }
        let original = liveTabModels[id], expected = store.state.tabs.first { $0.id == id }
        let children = peekPages(forTabID: id)
        peekRetirementParents.insert(id)
        closingTabIDs.insert(id)
        if !updateSavedTab { modelRetirementIDs.insert(id) }
        PCNativeBrowserApplication.requestClosePages([page] + children, shouldCommit: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return false }
                return !self.wholeWindowClose && !self.isClosing && self.browsers[id]?.nativePage === page
                    && children.allSatisfy { self.peeks[$0.identifier]?.parentTabID == id }
            }
        }, completion: { [weak self] allowed in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.peekRetirementParents.remove(id)
                self.closingTabIDs.remove(id); self.modelRetirementIDs.remove(id)
                if allowed { self.releaseClosedTab(id, updateSavedTab: updateSavedTab) }
                else if page.isClosed {
                    for child in children {
                        if let peek = self.peeks[child.identifier], !child.isClosed {
                            self.promotePeek(peek, split: false, orphaned: true)
                        }
                    }
                } else if !updateSavedTab, self.browsers[id]?.nativePage === page, let original {
                    _ = self.store.restoreLiveTab(original, replacing: expected)
                }
                self.render(self.store.state); self.requestNativeSelection()
            }
        })
    }

    func nativeBrowserWindow() -> NSWindow { window! }
    func selectedNativePage() -> PCNativePage? {
        if let page = currentBrowser?.nativePage { return page }
        guard let id = currentTabID else { return nil }
        return easelEditors[id]?.editor.pageObjects?.selectedPage
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, allowsHistorySwipeFor page: PCNativePage) -> Bool {
        browser === nativeBinding && !page.isClosed
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && commandBar == nil && libraryView == nil && tabSwitcher == nil
            && navigationHistory == nil && themePopover == nil && !siteControlCenterDefers && pageCapture == nil
            && menuTrackingDepth == 0 && window?.attachedSheet == nil
            && PCNativeBrowserApplication.owner(of: page) === browser
            && historySwipePages.contains { $0 === page }
    }
    var historySwipePalette: ThemeChromePalette { rootView.palette }
    private var historySwipePages: [PCNativePage] {
        let peek = activePeek
        let panes = renderedPaneIDs.map { id in
            let tab = store.state.tabs.first(where: { $0.id == id })
            let browser = tab == nil ? nil : browsers[id]
            return HistorySwipeTargets.Pane(easelPage: easelEditors[id]?.editor.pageObjects?.selectedPage,
                                            page: browser?.nativePage,
                                            isInternal: tab.map { InternalPage.isInternal($0.url) } ?? true,
                                            isHidden: browser?.isHiddenOrHasHiddenAncestor ?? true)
        }
        return HistorySwipeTargets.pages(peek: peek?.page, peekShown: peek?.view.isHidden == false, panes: panes)
    }
    override func cancelOperation(_ sender: Any?) {
        if let session = spaceCreation, !session.committing, !session.view.hasMarkedText {
            cancelSpaceCreation(); return
        }
        guard let responder = window?.firstResponder as? NSView,
              !(responder is NSTextView),
              !(selectedNativePage().map { responder === $0.nativeView || responder.isDescendant(of: $0.nativeView) } ?? false)
        else { super.cancelOperation(sender); return }
        let item = NSMenuItem(title: "Exit", action: nil, keyEquivalent: "")
        guard prepareExitMenuItem(item), let command = item.representedObject as? BrowserExitCommand,
              command.perform() else { super.cancelOperation(sender); return }
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canHandlePeekEscapeFrom page: PCNativePage) -> Bool {
        guard browser === nativeBinding, let peek = activePeek,
              peek.page === page, peeks[page.identifier] === peek,
              selectedNativePage() === page, PCNativeBrowserApplication.owner(of: page) === browser,
              browser.window === window, commandBar == nil, libraryView == nil,
              findHost.isHidden, pageCapture == nil, nativeFullscreenTabID == nil,
              !wholeWindowClose, !windowClosePending,
              !isClosing, peekRetirementParents.isEmpty, modelRetirementIDs.isEmpty,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty else { return false }
        return peek.canHandleEscape
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, handlePeekEscapeFrom page: PCNativePage,
                       prefersConfirmation: Bool) {
        guard nativeBrowser(browser, canHandlePeekEscapeFrom: page),
              let peek = activePeek, peek.page === page else { return }
        peek.rendererEscape(prefersConfirmation: prefersConfirmation)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, shortcutFor event: NSEvent,
                       page: PCNativePage, editable: Bool) -> PCNativeShortcutCommand? {
        guard browser === nativeBinding, selectedNativePage() === page, !page.isClosed,
              !isClosing, !wholeWindowClose, !windowClosePending,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              window?.isKeyWindow == true, NSApp.isActive else { return nil }
        if !editable, let command = folderUndoShortcut(event) { return command }
        return KeyboardShortcuts.shared.nativeCommand(for: event, editable: editable)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, performShortcut command: PCNativeShortcutCommand,
                       event: NSEvent, page: PCNativePage, editable: Bool) -> Bool {
        guard let current = nativeBrowser(browser, shortcutFor: event, page: page, editable: editable),
              current.item === command.item, current.revision == command.revision,
              current.priority == command.priority else { return false }
        let previousEvent = shortcutInvocationEvent
        shortcutInvocationEvent = event
        defer { shortcutInvocationEvent = previousEvent }
        if command.item === folderUndoKeyItem,
           let target = command.item?.representedObject as? FolderUndoManager.Command {
            return !editable && folderUndo.perform(target)
        }
        return KeyboardShortcuts.shared.perform(command, event: event, editable: editable)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, showShortcutHint command: PCNativeShortcutCommand?,
                       page: PCNativePage?) -> Bool {
        guard browser === nativeBinding else { return false }
        removeShortcutHint()
        guard let command, let item = command.item, let page,
              selectedNativePage() === page, !page.isClosed, !isClosing,
              window?.isKeyWindow == true, page.nativeView.window === window,
              !page.nativeView.isHiddenOrHasHiddenAncestor else { return false }
        if KeyboardShortcuts.shared.isExitCommand(command) {
            let phase = WindowFullscreenPhase.current(fullscreenPhase,
                inFullScreen: window?.styleMask.contains(.fullScreen) == true)
            guard activePeek == nil, spaceCreation == nil, phase == .expanded else { return false }
        }
        let commandID = KeyboardShortcuts.shared.settingsCommandID(for: command)
        let shortcut = KeyboardShortcut(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
        let hint = ShortcutPriorityHintView(title: item.title, shortcut: shortcut.display,
                                           canEdit: commandID != nil, theme: rootView.theme, basicBackground: windowBasicBackground)
        hint.onEdit = { [weak self, weak hint, weak page] in
            guard let self, let hint, self.shortcutHint === hint,
                  self.shortcutHintCommand === command, let page,
                  self.shortcutHintPage === page,
                  let id = KeyboardShortcuts.shared.settingsCommandID(for: command),
                  page.consumeShortcutHint(command) else { return }
            self.showSettings(pane: .shortcuts, shortcutID: id)
        }
        hint.onDismiss = { [weak self, weak hint, weak page] in
            guard let self, let hint, self.shortcutHint === hint,
                  self.shortcutHintCommand === command, let page,
                  self.shortcutHintPage === page else { return }
            _ = page.consumeShortcutHint(command)
        }
        guard let window, hint.present(in: window) else { return false }
        shortcutHint = hint; shortcutHintCommand = command; shortcutHintPage = page
        toasts.dismiss(animated: true)
        NSAccessibility.post(element: hint, notification: .announcementRequested,
                             userInfo: [.announcement: "Press Again to " + item.title,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        return true
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, dismissShortcutHint command: PCNativeShortcutCommand,
                       page: PCNativePage) {
        guard browser === nativeBinding, shortcutHintCommand === command, shortcutHintPage === page else { return }
        removeShortcutHint(animated: true)
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, isShortcutHintHovered command: PCNativeShortcutCommand,
                       page: PCNativePage) -> Bool {
        guard browser === nativeBinding, shortcutHintCommand === command, shortcutHintPage === page,
              selectedNativePage() === page else { return false }
        return shortcutHint?.containsPointer == true
    }
    private func retireShortcutHint() {
        if let command = shortcutHintCommand, let page = shortcutHintPage { _ = page.consumeShortcutHint(command) }
        removeShortcutHint(animated: true)
    }
    private func removeShortcutHint(animated: Bool = false) {
        let hint = shortcutHint; shortcutHint = nil
        shortcutHintCommand = nil; shortcutHintPage = nil
        hint?.dismiss(animated: animated)
    }

    func visibleNativePages() -> [PCNativePage] {
        let peek = activePeek.flatMap { $0.view.isHidden ? nil : $0 }
        let parents: [PCNativePage] = renderedPaneIDs.compactMap { id in
            guard let browser = browsers[id], !browser.isHiddenOrHasHiddenAncestor else { return nil }
            return browser.nativePage
        }
        let embedded = renderedPaneIDs.flatMap { easelEditors[$0]?.editor.pageObjects?.visiblePages ?? [] }
        let held: [PCNativePage] = switchHold.held.compactMap { pane in
            guard pane.superview === splitView, let browser = pane.browser, !browser.isHiddenOrHasHiddenAncestor else { return nil }
            return browser.nativePage
        }
        return parents + embedded + held + (peek.map { [$0.page] } ?? [])
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, containerFor page: PCNativePage,
                       disposition: PCNativePageDisposition) -> NSView? {
        guard browser === nativeBinding, !wholeWindowClose, !isClosing, !page.isClosed else { return nil }
        if let peek = peeks[page.identifier] { return peek.browser }
        if page.isEmbedded { return embeddedEaselOwner(page)?.1.container(for: page) }
        if disposition == .peek { return adoptPeek(page, binding: browser) }
        if let pending = peekUndoOpen, page.creationSourcePage?.identifier == pending.parent { peekUndoOpen = nil }
        if let container = transferContainers[page.identifier] { return container }
        if let existing = browsers.values.first(where: { $0.nativePage === page }) { return existing }
        let splitLease = disposition == .splitTab ? page.splitLinkLease as? SplitLinkLease : nil
        let splitSource = splitLease.flatMap { _ in page.creationSourcePage }
        let splitAdmitted = splitLease.flatMap { lease in
            splitSource.map { nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: $0) }
        } == true
        if disposition == .splitTab && !splitAdmitted { return nil }
        let routedSpaceID: UUID?
        if let route = page.routedSpaceIdentifier {
            guard let id = UUID(uuidString: route),
                  let space = store.state.spaces.first(where: { $0.id == id }),
                  page.profilePath == store.independentEngineProfilePath(for: space.profileID),
                  !store.isProfileRemovalPending(space.profileID) else { return nil }
            routedSpaceID = id
        } else { routedSpaceID = nil }
        let alternate = routedSpaceID == nil ? alternateNavigationReceipt(page) : nil
        let source = alternate?.referrer ?? page.creationSourcePage.flatMap(creationSourceTab)
        let creation: TabCreationProvenance
        if routedSpaceID != nil {
            let openedLink = page.responds(to: #selector(getter: PCNativePage.routedLinkCreation))
                && page.routedLinkCreation
            creation = TabCreationProvenance(routedFrom: source, openedLink: openedLink,
                profileID: activeProfileID, state: store.state)
        } else {
            creation = TabCreationProvenance(referrerID: source, activeTabID: currentTabID,
                profileID: activeProfileID, state: store.state)
        }
        let insertion: TodayInsertion = routedSpaceID == nil && alternate?.top != true ? .automatic : .top
        guard ownership.canAdopt(page.identifier), let id = store.adoptNativePage(url: page.url, title: page.title, profilePath: page.profilePath,
                                            preferredSpaceID: routedSpaceID ?? activeSpaceID,
                                            select: false, creation: creation, insertion: insertion),
              let tab = store.state.tabs.first(where: { $0.id == id }),
              ownership.claim(id, owner: presentationID, page: page.identifier) else { return nil }
        let pane = makePane(tab)
        let view = PCBrowserView(frame: pageHost.bounds, adoptingNativePage: page)
        view.delegate = self
        browsers[id] = view; browserProfiles[id] = tab.profileID; liveTabModels[id] = tab
        requestedURLs[id] = tab.url
        panes[id] = pane; pane.browser = view; pane.showBrowser()
        parkedPages.addSubview(pane)
        cancelSpaceCreation(restoreFocus: false, renderContent: false)
        let firstPage = !presentation.isReady
        preparedForRoutedPage = false
        presentation.recordCreation(id, state: store.state)
        let foreground = disposition != .backgroundTab && !splitAdmitted
        presentation.adopt(id, state: store.state, foreground: foreground)
        if foreground || firstPage {
            focusedTabID = id; recordRecentTabSelection()
        }
        DispatchQueue.main.async { [weak self, weak page, weak browser, weak splitSource, weak view] in
            defer { if let page, let lease = splitLease { page.finishSplitLinkLease(lease) } }
            guard let self else { return }
            if let view, self.browsers[id] === view, view.isLoading { self.loadingTabs.insert(id) }
            self.render(self.store.state)
            if splitAdmitted, let page, let browser, let lease = splitLease, let source = splitSource,
               page.splitLinkLease as? SplitLinkLease === lease,
               page.creationSourcePage === source,
               self.browsers[id]?.nativePage === page,
               self.nativeBrowser(browser, isSplitLinkLeaseCurrent: lease, for: source) {
                if !self.joinOriginalSplitPage(id, page: page, source: source, browser: browser, lease: lease),
                   self.selectedTabIDs.count >= 4 {
                    self.showToast(.cannotAddNewPane, at: .window)
                }
            }
            if firstPage && foreground && self.nativeWindowRequest == nil {
                self.showWindow(nil)
                self.window?.makeKeyAndOrderFront(nil)
            }
        }
        return view
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didClose page: PCNativePage) {
        if browser === nativeBinding, page.isEmbedded {
            embeddedEaselOwner(page)?.1.didClose(page); refreshCaptureIndicators(); return
        }
        if browser === nativeBinding, let peek = peeks[page.identifier] { removePeek(peek); return }
        if browser === nativeBinding, !wholeWindowClose {
            for peek in Array(peeks.values) where peek.parentPage === page && !peek.page.isClosed
                && !closingTabIDs.contains(peek.parentTabID) && !modelRetirementIDs.contains(peek.parentTabID)
                && !peekRetirementParents.contains(peek.parentTabID) {
                promotePeek(peek, split: false, orphaned: true)
            }
        }
        guard browser === nativeBinding,
              let id = browsers.first(where: { $0.value.nativePage === page })?.key else { return }
        releaseClosedTab(id, updateSavedTab: !wholeWindowClose && !modelRetirementIDs.contains(id) && !transferringTabIDs.contains(id))
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didSelect page: PCNativePage) {
        if browser === nativeBinding, spaceCreation != nil {
            browser.synchronizeSelectionAndLayout(); return
        }
        if browser === nativeBinding, page.isEmbedded {
            if selectedNativePage() !== page { browser.synchronizeSelectionAndLayout() }
            return
        }
        if browser === nativeBinding, let peek = peeks[page.identifier], !page.isClosed {
            if undoHiddenPeek == peek.identity {
                undoHiddenPeek = nil
                if peek.view.isHidden { browser.synchronizeSelectionAndLayout(); return }
            }
            guard !applyingNativeSelection, !isClosing, !wholeWindowClose else { return }
            applyingNativeSelection = true
            _ = selectTab(peek.parentTabID)
            applyingNativeSelection = false
            layoutPeeks(); peek.focus(); return
        }
        guard !applyingNativeSelection, let (id, view) = existingNativeSelection(browser, page),
              !rendering else { return }
        var next = presentation
        guard next.selectExistingTab(id, state: store.state,
                                     available: { ownership.canUse($0, owner: presentationID) }) else { return }
        pendingNativeSelection = nil
        if let peek = activePeek, peek.parentPage === page {
            DispatchQueue.main.async { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek, !peek.page.isClosed,
                      !self.isClosing, !self.wholeWindowClose else { return }
                self.nativeBinding?.synchronizeSelectionAndLayout()
            }
        }
        applyingNativeSelection = true
        defer { applyingNativeSelection = false }
        presentation = next
        focusedTabID = id
        prepareStoreContext()
        store.selectTab(id, extendingSplit: true)
        presentation.captureCommand(store.state) { ownership.canUse($0, owner: presentationID) }
        recordRecentTabSelection()
        guard existingNativeSelection(browser, page)?.1 === view else { return }
        render(store.state)
        guard existingNativeSelection(browser, page)?.1 === view,
              currentTabID == id, renderedPaneIDs.contains(id),
              let window, window.attachedSheet == nil, commandBar == nil,
              page.nativeView.window === window,
              page.nativeView.isDescendant(of: view), attachedPageIDs.contains(page.identifier) else { return }
        if let crash = rendererPresentation(view) { focusRendererFailure(id, crash) }
        else if !view.isHiddenOrHasHiddenAncestor { window.makeFirstResponder(page.nativeView) }
    }

    private func existingNativeSelection(_ binding: PCNativeBrowserWindow,
                                         _ page: PCNativePage) -> (UUID, PCBrowserView)? {
        guard binding === nativeBinding, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, !page.isClosed,
              PCNativeBrowserApplication.owner(of: page) === binding,
              let (id, view) = browsers.first(where: { $0.value.nativePage === page }),
              ownership.isClaimed(id), ownership.canUse(id, owner: presentationID),
              !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
              !store.retiringTabIDs.contains(id), page.observer === view, view.delegate === self,
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              browserProfiles[id] == tab.profileID,
              page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
              let window, binding.window === window, view.window === window else { return nil }
        return (id, view)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, didFailWithError error: Error) {
        guard browser === nativeBinding else { return }
        NSLog("Parc native window: %@", error.localizedDescription)
    }

    func nativeBrowserFocusAddress(_ browser: PCNativeBrowserWindow) { if browser === nativeBinding { focusAddress() } }
    func nativeBrowserShowTabSearch(_ browser: PCNativeBrowserWindow) { if browser === nativeBinding { newTab() } }
    func nativeBrowserCloseTabSearch(_ browser: PCNativeBrowserWindow) { if browser === nativeBinding { commandBar?.dismiss() } }
    func nativeBrowserShowProfiles(_ browser: PCNativeBrowserWindow) { if browser === nativeBinding { showSettings(pane: .spaces) } }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, bookmarkURL url: URL) {
        guard browser === nativeBinding else { return }
        if let peek = activePeek, peek.browser.url == url { promotePeek(peek, split: false) }
        if let id = currentTabID, activePeek == nil, currentBrowser?.url == url {
            if store.state.tabs.first(where: { $0.id == id })?.kind == .favorite { _ = moveFavoriteToPinned(id) }
            else { store.setKind(id, .pinned) }
        }
        else { performWindowCommand { store.importBookmarks([(title: url.host ?? url.absoluteString, url: url.absoluteString)]) } }
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, rotateFocusForward forward: Bool) -> Bool {
        guard browser === nativeBinding, let window else { return false }
        let previous = window.firstResponder
        if forward { window.selectNextKeyView(nil) } else { window.selectPreviousKeyView(nil) }
        return window.firstResponder !== previous
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setTabFullscreenPage page: PCNativePage?) -> Bool {
        guard browser === nativeBinding, !wholeWindowClose, !isClosing else { return false }
        guard let page else { restoreNativeFullscreenPresentation(); render(store.state); return true }
        if let peek = peeks[page.identifier] {
            guard activePeek === peek else { return false }
            promotePeek(peek, split: false)
            guard peeks[page.identifier] == nil else { return false }
        }
        guard let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              renderedPaneIDs.contains(id) else { return false }
        let outgoing = renderedPaneIDs.filter { $0 != id }
        let removal = presentationSetMediaRemoval(capturing: outgoing, remaining: { Set(self.renderedPaneIDs) }) {
            self.nativeFullscreenTabID == id && self.renderedPaneIDs == [id]
        }
        if nativeFullscreenPresentation == nil { nativeFullscreenPresentation = (sidebarPresentation, findHost.isHidden) }
        nativeFullscreenTabID = id
        findHost.isHidden = true
        render(store.state)
        removal?()
        return renderedPaneIDs == [id] && page.nativeView.window === window
    }
    private func restoreNativeFullscreenPresentation() {
        nativeFullscreenTabID = nil
        if let saved = nativeFullscreenPresentation {
            sidebarPresentation = saved.sidebar; findHost.isHidden = saved.findHidden
        }
        nativeFullscreenPresentation = nil
    }
    func nativeBrowserSidePanelContainer(_ browser: PCNativeBrowserWindow) -> NSView { extensionSidePanel.content }
    func nativeBrowserSidePanelFocusScope(_ browser: PCNativeBrowserWindow) -> NSView { extensionSidePanel }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, setSidePanelVisible visible: Bool) -> Bool {
        guard browser === nativeBinding, !isClosing, nativeFullscreenTabID == nil || !visible else { return false }
        extensionSidePanelVisible = visible
        layoutChrome()
        rootView.layoutSubtreeIfNeeded()
        return extensionSidePanel.window === window && extensionSidePanel.isHidden == !visible
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, capabilityUnavailable capability: String) {
        guard browser === nativeBinding else { return }
        NSLog("Parc capability unavailable: %@", capability)
        if let window { ParcDialog.inform(in: window, .init(title: "This feature isn’t available yet", message: capability)) }
    }
    func closeCurrentTab() {
        if let peek = activePeek { peek.requestDismiss(.closeShortcut); return }
        if isPopupWindow { window?.performClose(nil); return }
        if let id = currentTabID { closeTab(id) }
    }
    func togglePinFocusedTab() {
        guard !isPrivateBrowsing else { return }
        if let peek = activePeek { promotePeek(peek, split: false); guard activePeek == nil else { return } }
        guard let id = currentTabID, let tab = store.state.tabs.first(where: { $0.id == id }) else { return }
        if tab.kind == .favorite { _ = moveFavoriteToPinned(id) }
        else { store.setKind(id, tab.kind == .pinned ? .today : .pinned) }
    }
    private func moveFavoriteToPinned(_ id: UUID) -> Bool {
        let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first { $0.tabIDs.contains(id) }
        let item = group.map { SidebarItemReference.split($0.id) } ?? .tab(id)
        return prepareSidebarMove(item)?.move(to: .init(spaceID: activeSpaceID, folderID: nil, section: .pinned), before: nil) == true
    }
    enum SplitCommand {
        case focus(Int), next, previous, expand, separate, close
        case orientation(SplitOrientation), move(Int), add(SplitPaneOperation), addNew, copyLink
    }

    private func prepareSeparateSplitTab(_ id: UUID) -> (() -> Bool)? {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(id) }) else { return nil }
        return prepareSplitSeparation(group) { [weak self] focus in
            self?.separateSplitTab(id, group: group, originalFocus: focus) ?? false
        }
    }

    private func prepareSplitCellCommand(_ id: UUID, _ command: SplitCellMenuCommand) -> (() -> Bool)? {
        switch command {
        case .separateAll:
            guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }) else { return nil }
            return prepareSplitSeparation(group) { [weak self] focus in
                self?.separateAllSplitTabs(group, originalFocus: focus) ?? false
            }
        case .addTab:
            guard splitInsertion == nil, let target = splitCommandTarget(.addNew) else { return nil }
            return { guard target.isAvailable else { return false }; target.perform(); return true }
        case .convertOrientation:
            return prepareSplitOrientationFlip(id)
        case .newFolder:
            return prepareFolderFromItems([.split(id)])
        }
    }

    private func prepareFolderFromItems(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard !isPrivateBrowsing, folderUndoContextAvailable, !folderUndo.isBusy, let window,
              let lease = prepareSidebarMoves(items),
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID,
                  profileID: activeProfileID, includesFavorites: true) else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window, lease.isValid,
                  !self.folderUndo.isBusy else { return false }
            consumed = true; lease.end()
            do {
                guard let receipt = try self.store.createFolder(containing: items, folderID: UUID(), expected: expected) else { return false }
                self.registerFolderCreationUndo(receipt)
                self.render(self.store.state)
                self.sidebar.scrollItemToVisible(.folder(receipt.folderID))
                let spaceID = receipt.spaceID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                    guard let self, let window, self.window === window, window.isKeyWindow, window.attachedSheet == nil,
                          self.activeSpaceID == spaceID,
                          self.store.state.folders.contains(where: { $0.id == receipt.folderID }) else { return }
                    if !self.sidebar.beginFolderTitleEditing(receipt.folderID, untitled: true) { self.renameFolder(receipt.folderID) }
                }
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    private func registerFolderCreationUndo(_ receipt: SidebarFolderFromItems) {
        var receipt = receipt
        _ = folderUndo.append(.init(name: SidebarFolderFromItems.undoName, isValid: { [weak self] direction in
            guard let self else { return false }
            return receipt.reverting(self.store.state, undo: direction == .undo) != nil
        }, isAvailable: { [weak self] _ in
            guard let self else { return false }
            return self.folderUndoContextAvailable && self.activeSpaceID == receipt.spaceID
                && self.activeProfileID == receipt.profileID
        }, perform: { [weak self] direction, done in
            guard let self else { done(false); return }
            do {
                let updated = try self.store.revertFolderCreation(receipt, undo: direction == .undo)
                if let updated { receipt = updated }
                done(updated != nil); self.render(self.store.state)
            }
            catch { showError(error); done(false) }
        }))
    }

    private func prepareSplitOrientationFlip(_ id: UUID) -> (() -> Bool)? {
        guard splitCommandsAvailable, let window,
              let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }),
              group.tabIDs.allSatisfy({ !store.retiringTabIDs.contains($0) }) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window, self.splitCommandsAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.store.state.splitLayouts.contains(group) else { return false }
            consumed = true
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = self.store.flipSplitOrientation(expected: group)
            }
            return committed
        }
    }

    private func prepareSplitSeparation(_ group: BrowserSplitLayout, perform: @escaping (UUID?) -> Bool) -> (() -> Bool)? {
        guard splitCommandsAvailable, let window,
              group.tabIDs.allSatisfy({ switcherCanUse($0) }) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID
        let selection = selectedTabIDs, focus = currentTabID
        let ids = group.tabIDs
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        let wrappers = Dictionary(uniqueKeysWithValues: ids.compactMap { id in browsers[id].map { (id, ObjectIdentifier($0)) } })
        let pages = Dictionary(uniqueKeysWithValues: ids.compactMap { id in browsers[id]?.nativePage.map { (id, ObjectIdentifier($0)) } })
        let notes = Dictionary(uniqueKeysWithValues: ids.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let easels = Dictionary(uniqueKeysWithValues: ids.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  self.splitCommandsAvailable, self.activeSpaceID == spaceID,
                  self.activeProfileID == profileID, self.selectedTabIDs == selection, self.currentTabID == focus,
                  self.store.state.splitLayouts.contains(group),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
                  ids.allSatisfy({ self.switcherCanUse($0) && self.ownership.claimSnapshot($0) == claims[$0] }),
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.browsers[id].map { (id, ObjectIdentifier($0)) } }) == wrappers,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.browsers[id]?.nativePage.map { (id, ObjectIdentifier($0)) } }) == pages,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == notes,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == easels else { return false }
            consumed = true
            return perform(focus)
        }
    }

    private func presentationSetMediaRemoval(
        capturing candidates: [UUID],
        remaining: @escaping () -> Set<UUID>,
        gate: (() -> Bool)? = nil
    ) -> (() -> Void)? {
        guard let window, let binding = nativeBinding, !candidates.isEmpty else { return nil }
        let originals = Array(Set(candidates)).compactMap { id -> (UUID, PCBrowserView, PCNativePage, NSObject, UUID)? in
            guard let view = browsers[id], view.window === window,
                  let page = view.nativePage, !page.isClosed,
                  attachedPageIDs.contains(page.identifier),
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let sourceProfile = browserProfiles[id],
                  liveTabModels[id]?.profileID == sourceProfile,
                  page.responds(to: #selector(PCNativePage.captureMediaPresentationLease)),
                  page.responds(to: #selector(PCNativePage.mediaPresentationDidRemove(_:))),
                  let lease = page.captureMediaPresentationLease() else { return nil }
            return (id, view, page, lease, sourceProfile)
        }
        guard !originals.isEmpty else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: originals.map { ($0.0, ownership.claimSnapshot($0.0)) })
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding else { return }
            let isCurrent = {
                self.window === window && self.nativeBinding === binding && (gate?() ?? true)
            }
            guard isCurrent() else { return }
            let kept = remaining()
            for (id, view, page, lease, sourceProfile) in originals where !kept.contains(id) {
                guard isCurrent() else { return }
                guard self.ownership.claimSnapshot(id) == claims[id],
                      self.browsers[id] === view, view.nativePage === page, view.window === window,
                      self.attachedPageIDs.contains(page.identifier),
                      !page.isClosed, self.browserProfiles[id] == sourceProfile,
                      self.liveTabModels[id]?.profileID == sourceProfile,
                      PCNativeBrowserApplication.owner(of: page) === binding else { continue }
                page.mediaPresentationDidRemove(lease)
            }
        }
    }

    private func splitMediaRemoval(_ group: BrowserSplitLayout, expectedSelection: [UUID]) -> (() -> Void)? {
        guard splitCommandsAvailable, nativeFullscreenTabID == nil,
              selectedTabIDs == group.tabIDs, renderedPaneIDs == group.tabIDs,
              let window, let binding = nativeBinding else { return nil }
        let space = activeSpaceID, profile = activeProfileID
        let originals = group.tabIDs.compactMap { id -> (UUID, PCBrowserView, PCNativePage, NSObject, UUID, BrowserPane)? in
            guard switcherCanUse(id), let view = browsers[id], view.window === window,
                  let pane = panes[id], pane.superview === splitView, !pane.isHiddenOrHasHiddenAncestor,
                  let page = view.nativePage, !page.isClosed, attachedPageIDs.contains(page.identifier),
                  PCNativeBrowserApplication.owner(of: page) === binding,
                  let sourceProfile = browserProfiles[id], liveTabModels[id]?.profileID == sourceProfile,
                  page.responds(to: #selector(PCNativePage.captureMediaPresentationLease)),
                  page.responds(to: #selector(PCNativePage.mediaPresentationDidRemove(_:))),
                  let lease = page.captureMediaPresentationLease() else { return nil }
            return (id, view, page, lease, sourceProfile, pane)
        }
        let claims = Dictionary(uniqueKeysWithValues: group.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        return { [weak self, weak window, weak binding] in
            guard let self, let window, let binding else { return }
            let isCurrent = {
                self.window === window && self.nativeBinding === binding && self.splitCommandsAvailable
                    && self.nativeFullscreenTabID == nil && self.activeSpaceID == space
                    && self.activeProfileID == profile && self.renderedPaneIDs == group.tabIDs
                    && self.selectedTabIDs == expectedSelection && self.store.state.selectedTabIDs == expectedSelection
            }
            guard isCurrent() else { return }
            let remaining = Set(expectedSelection)
            for (id, view, page, lease, sourceProfile, originalPane) in originals where !remaining.contains(id) {
                guard isCurrent() else { return }
                guard self.switcherCanUse(id), self.ownership.claimSnapshot(id) == claims[id],
                      self.browsers[id] === view, view.nativePage === page, view.window === window,
                      let pane = self.panes[id], pane === originalPane,
                      pane.superview === self.splitView, !pane.isHiddenOrHasHiddenAncestor,
                      self.attachedPageIDs.contains(page.identifier),
                      !page.isClosed, self.browserProfiles[id] == sourceProfile,
                      self.liveTabModels[id]?.profileID == sourceProfile,
                      PCNativeBrowserApplication.owner(of: page) === binding else { continue }
                page.mediaPresentationDidRemove(lease)
            }
        }
    }

    @discardableResult
    private func separateAllSplitTabs(_ group: BrowserSplitLayout, originalFocus: UUID?) -> Bool {
        var committed = false
        let kept = originalFocus.flatMap { group.tabIDs.contains($0) ? $0 : nil } ?? group.tabIDs.first
        let removal = kept.flatMap { splitMediaRemoval(group, expectedSelection: [$0]) }
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            committed = store.separateAllTabsFromSplit(expected: group, focusedID: originalFocus)
        }
        guard committed else { return false }
        requestNativeSelection()
        reclaimFocusAfterSplitPresentation()
        return true
    }

    @discardableResult
    private func separateSplitTab(_ id: UUID, group: BrowserSplitLayout, originalFocus: UUID?) -> Bool {
        var committed = false
        let expected = originalFocus == id ? [id] : group.tabIDs.filter { $0 != id }
        let removal = splitMediaRemoval(group, expectedSelection: expected)
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            committed = store.separateTabFromSplit(id, expected: group, focusedID: originalFocus)
        }
        guard committed else { return false }
        requestNativeSelection()
        reclaimFocusAfterSplitPresentation()
        return true
    }

    private func prepareSidebarMove(_ item: SidebarItemReference) -> SidebarMoveSession? {
        prepareSidebarMoves([item])
    }

    private func prepareSidebarMoves(_ items: [SidebarItemReference]) -> SidebarMoveSession? {
        guard spaceCommandsAvailable, commandBar == nil, let window,
              var expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID, includesFavorites: true),
              let collection = SidebarMoveCollection(items: items, spaceID: activeSpaceID, profileID: activeProfileID, state: store.state) else { return nil }
        func undisclosed(_ state: BrowserState) -> SidebarHierarchySnapshot? {
            var state = state
            for index in state.folders.indices { state.folders[index].isExpanded = false }
            return SidebarHierarchySnapshot(state: state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true)
        }
        let structure = undisclosed(store.state)
        let ids = collection.tabIDs
        guard ids.allSatisfy({ switcherCanUse($0) }) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let owners = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, SplitPaneIdentity(pane: panes[id].map(ObjectIdentifier.init) ?? ObjectIdentifier(self),
                                  browser: browsers[id].map(ObjectIdentifier.init), page: browsers[id]?.nativePage?.identifier))
        })
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, self.sidebarWindowMoveAvailable,
                  self.commandBar == nil, self.activeSpaceID == expected.spaceID,
                  self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  let current = SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID, includesFavorites: true) else { return false }
            if current != expected {
                guard structure != nil, undisclosed(self.store.state) == structure else { return false }
                expected = current
            }
            return ids.allSatisfy { id in
                guard self.switcherCanUse(id), self.browsers[id]?.nativePage?.isClosed != true else { return false }
                let actual = SplitPaneIdentity(pane: self.panes[id].map(ObjectIdentifier.init) ?? ObjectIdentifier(self),
                    browser: self.browsers[id].map(ObjectIdentifier.init), page: self.browsers[id]?.nativePage?.identifier)
                return owners[id] == actual
            }
        }
        let wholeSplits = items.allSatisfy { if case .split = $0 { return true } else { return false } }
        let session = SidebarMoveSession(items: items, window: window,
            validate: { [weak self] in self?.spaceCommandsAvailable == true && valid() },
            validateTransfer: valid, allowsCopy: wholeSplits, propose: { [weak self] location, before in
                guard valid(), let self, self.spaceCommandsAvailable else { return false }
                return SidebarHierarchy.moving(items, to: location, before: before, expected: expected, state: self.store.state) != nil
            }, commit: { [weak self] location, before in
                guard valid(), let self, self.spaceCommandsAvailable else { return false }
                do {
                    return try self.store.moveSidebarItems(items, to: location, before: before, expected: expected)
                } catch {
                    showError(error)
                    return false
                }
            })
        session.owner = self
        return session
    }

    private var copyDropCache: (key: String, revision: UInt64, action: (() -> Bool)?)?

    private var sidebarWindowMoveAvailable: Bool {
        sidebarWindowMoveEnvironment && collectionTransfer == nil && transferringTabIDs.isEmpty
    }

    private var sidebarWindowMoveEnvironment: Bool {
        !isPopupWindow && !isPrivateBrowsing && !store.isEphemeral && presentation.isReady
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && activePeek == nil && commandBar == nil
            && tabSwitcher == nil && themePopover == nil && !siteControlCenterDefers
            && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty && peekRetirementParents.isEmpty
            && resolvingTransfers.isEmpty && !store.isProfileRemovalPending(activeProfileID)
            && nativeBinding?.canParticipateInPageTransfer == true
    }

    private func prepareSidebarWindowDrop(_ session: SidebarMoveSession, to location: SidebarContainerLocation,
                                          before: SidebarItemReference?) -> (() -> Bool)? {
        if let source = session.owner, source !== self, source.activeProfileID != activeProfileID {
            return prepareInterProfileWindowDrop(session, from: source, to: location, before: before)
        }
        guard session.isValidForWindowTransfer, let source = session.owner, source !== self,
              source.store === store, source.ownership === ownership,
              source.window === session.window, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              source.activeProfileID == activeProfileID, location.spaceID == activeSpaceID,
              let move = SidebarWindowMove(items: session.items, sourceSpaceID: source.activeSpaceID,
                  profileID: activeProfileID, to: location, before: before, state: store.state),
              let transaction = SidebarWindowTransfer(source: source, destination: self, move: move) else { return nil }
        return { transaction.begin() }
    }

    private func prepareInterProfileWindowDrop(_ session: SidebarMoveSession, from source: BrowserWindowController,
                                               to location: SidebarContainerLocation,
                                               before: SidebarItemReference?) -> (() -> Bool)? {
        guard session.isValidForWindowTransfer, source.store === store, source.ownership === ownership,
              source.window === session.window, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              location.spaceID == activeSpaceID,
              let move = SidebarWindowMove(items: session.items, sourceSpaceID: source.activeSpaceID,
                  profileID: source.activeProfileID, destinationProfileID: activeProfileID,
                  to: location, before: before, state: store.state), move.crossesProfiles,
              Set(move.tabIDs).isDisjoint(with: store.retiringTabIDs) else { return nil }
        let selection = selectedTabIDs, spaceID = activeSpaceID, profileID = activeProfileID
        let placement: (BrowserState) -> BrowserState? = { state in
            guard SidebarHierarchySnapshot(state: state, spaceID: move.source.spaceID, profileID: move.source.profileID,
                                           includesFavorites: true) == move.source,
                  SidebarHierarchySnapshot(state: state, spaceID: move.destination.spaceID,
                                           profileID: move.destination.profileID, includesFavorites: true) == move.destination,
                  let current = SidebarWindowMove(items: move.roots, sourceSpaceID: move.source.spaceID,
                      profileID: move.source.profileID, destinationProfileID: move.destination.profileID,
                      to: move.location, before: move.before, state: state),
                  current.tabIDs == move.tabIDs else { return nil }
            return current.applying(to: state)
        }
        return { [weak self, weak source] in
            guard let self, let source, session.isValidForWindowTransfer,
                  source.sidebarWindowMoveAvailable, self.sidebarWindowMoveAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  placement(self.store.state) != nil else { return false }
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [move.source.profileID],
                                                destinationSpaceID: spaceID) { [weak self] in
                guard let self, self.activeSpaceID == spaceID, self.activeProfileID == profileID else { return }
                let moved = Set(move.tabIDs)
                self.store.moveAcrossProfiles(moved, proposal: placement) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(moved)
                        if selection.isEmpty, self.selectedTabIDs.isEmpty, let first = move.tabIDs.first {
                            self.finishInterProfileArrival(first)
                        } else { self.render(self.store.state) }
                    case .success(false): NSSound.beep()
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    private func prepareSidebarCopyDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                        to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        let key = ([session.identifier.uuidString, location.key, before.map { "\($0)" } ?? ""] + items.map { "\($0)" })
            .joined(separator: "|")
        if let cached = copyDropCache, cached.key == key, cached.revision == store.stateRevision { return cached.action }
        let action = makeSidebarCopyDrop(session, items: items, to: location, before: before)
        copyDropCache = (key, store.stateRevision, action)
        return action
    }

    private func makeSidebarCopyDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                     to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        guard session.allowsCopy, session.isValidForWindowTransfer, let window,
              let source = session.owner, source.store === store, source.window === session.window,
              folderDuplicateContextAvailable, source.folderDuplicateContextAvailable,
              sidebarWindowMoveEnvironment, source.sidebarWindowMoveEnvironment,
              let destinationProfile = store.state.spaces.first(where: { $0.id == location.spaceID })?.profileID,
              location.profileID == nil || location.profileID == destinationProfile,
              destinationProfile == source.activeProfileID
                || InterProfileMove.profilesAvailable(source.activeProfileID, destinationProfile, in: store.state),
              let copy = SidebarSplitCopy(items: items, spaceID: source.activeSpaceID,
                  profileID: source.activeProfileID, state: store.state) else { return nil }
        let sourceProfile = source.activeProfileID, spaceID = activeSpaceID, profileID = activeProfileID
        let focus = source.focusedTabID
        let focusIndex = copy.groups.last.flatMap { group in focus.flatMap { group.tabIDs.firstIndex(of: $0) } } ?? 0
        let current: () -> (copy: SidebarSplitCopy, sources: SidebarCopySources)? = { [weak self] in
            guard let self, self.folderDuplicateContextAvailable,
                  let now = SidebarSplitCopy(items: copy.roots, spaceID: copy.source.spaceID,
                      profileID: copy.source.profileID, state: self.store.state), now.matchesPlacement(of: copy),
                  let resolved = self.resolveSidebarCopyDestinations?(now.tabs), resolved.validates(now.tabs) else { return nil }
            return (now, resolved)
        }
        guard let proposed = current(),
              store.canCopySidebarSplits(proposed.copy, to: location, before: before,
                  destinations: proposed.sources.destinations, documents: proposed.sources.documents) else { return nil }
        let sourceShown = source.selectedTabIDs.filter { id in copy.tabs.contains { $0.id == id } }
        let sourceFocus = source.focusedTabID.flatMap { sourceShown.contains($0) ? $0 : nil } ?? sourceShown.first
        let sourceSpace = source.activeSpaceID
        let arrive: (SidebarDuplicateResult) -> Void = { [weak self, weak window] result in
            guard let self, let window, self.window === window else { return }
            if location.spaceID != self.activeSpaceID {
                if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                guard self.selectSpaceFromUser(location.spaceID, profileID: destinationProfile) else { self.render(self.store.state); return }
            }
            guard self.activeSpaceID == location.spaceID, self.activeProfileID == destinationProfile else { self.render(self.store.state); return }
            self.openDuplicatedChildren(result.openTabIDs, spaceID: location.spaceID, profileID: destinationProfile, window: window)
            if case .split(let id)? = result.roots.last,
               let copied = self.store.state.splitLayouts.first(where: { $0.id == id }), !copied.tabIDs.isEmpty {
                _ = self.selectTab(copied.tabIDs[min(focusIndex, copied.tabIDs.count - 1)])
            } else { self.render(self.store.state) }
        }
        let perform: () -> Bool = { [weak self, weak window, weak source] in
            guard let self, let window, self.window === window, self.sidebarWindowMoveEnvironment,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  let resolved = current() else { return false }
            let now = resolved.copy, urls = resolved.sources
            let creation = self.creationProvenance(activeTabID: self.currentTabID)
            guard destinationProfile != sourceProfile else {
                do {
                    guard let result = try self.store.copySidebarSplits(now, to: location, before: before,
                        destinations: urls.destinations, documents: urls.documents, creation: creation) else { return false }
                    arrive(result); return true
                } catch {
                    showError(error); return false
                }
            }
            self.store.copySidebarSplitsReloadingOriginals(now, to: location, before: before,
                destinations: urls.destinations, documents: urls.documents, creation: creation) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .success(let result?):
                    if let source, source !== self, source.activeSpaceID == sourceSpace, let shown = sourceFocus {
                        _ = source.selectTab(shown)
                    }
                    arrive(result)
                case .success(nil): NSSound.beep()
                case .failure(let error): showError(error)
                }
            }
            return true
        }
        var consumed = false
        return { [weak self] in
            guard !consumed, let self else { return false }
            consumed = true
            guard destinationProfile != sourceProfile else { return perform() }
            var deciding = true
            var immediate: Bool?
            let began = self.confirmInterProfileMove(tabCount: copy.tabs.count, sourceProfiles: [sourceProfile],
                                                     destinationSpaceID: location.spaceID) {
                let done = perform()
                if deciding { immediate = done } else if !done { NSSound.beep() }
            }
            deciding = false
            return immediate ?? began
        }
    }

    private func prepareSidebarDockDrop(_ session: SidebarMoveSession, items: [SidebarItemReference],
                                        to location: SidebarContainerLocation, before: SidebarItemReference?) -> (() -> Bool)? {
        guard !items.isEmpty, session.isValidForWindowTransfer, let window,
              let source = session.owner, source.store === store, source.window === session.window,
              let space = store.state.spaces.first(where: { $0.id == location.spaceID }),
              location.profileID == nil else { return nil }
        let crosses = space.profileID != source.activeProfileID
        guard !crosses || InterProfileMove.profilesAvailable(source.activeProfileID, space.profileID, in: store.state),
              let move = SidebarWindowMove(items: items, sourceSpaceID: source.activeSpaceID, profileID: source.activeProfileID,
                  destinationProfileID: space.profileID, to: location, before: before, state: store.state) else { return nil }
        if source !== self {
            guard items == session.items, sidebarWindowMoveAvailable, source.sidebarWindowMoveAvailable else { return nil }
            return { [weak self, weak window] in
                guard let self, let window, self.window === window else { return false }
                if location.spaceID != self.activeSpaceID {
                    if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
                    guard self.selectSpaceFromUser(location.spaceID, profileID: space.profileID) else { return false }
                }
                let top = SidebarHierarchy.children(in: location, state: self.store.state).first { !items.contains($0) }
                guard let begin = self.prepareSidebarWindowDrop(session, to: location, before: top) else { return false }
                return begin()
            }
        }
        guard sidebarWindowMoveAvailable, let validateOwners = prepareSidebarSpaceMoveOwners?(Set(move.tabIDs)) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: move.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        let splitChildren = Set(move.collection.roots.flatMap { root -> [UUID] in
            guard case .split(let id) = root else { return [] }
            return move.source.groups.first { $0.id == id }?.tabIDs ?? []
        })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              splitChildren.allSatisfy({ claims[$0]?.owner == nil || claims[$0]?.owner == presentationID }) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID, spaceID = activeSpaceID, profileID = activeProfileID
        let current: (BrowserState) -> SidebarWindowMove? = { state in
            guard let now = SidebarWindowMove(items: move.roots, sourceSpaceID: move.source.spaceID, profileID: move.source.profileID,
                      destinationProfileID: move.destination.profileID, to: move.location, before: move.before, state: state),
                  now.tabIDs == move.tabIDs else { return nil }
            return now
        }
        let arrive: () -> Void = { [weak self, weak window] in
            guard let self, let window else { return }
            self.render(self.store.state); self.requestNativeSelection()
            guard location.spaceID != self.activeSpaceID else { return }
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            _ = self.selectSpaceFromUser(location.spaceID, profileID: space.profileID)
        }
        return { [weak self] in
            guard let self, self.sidebarWindowMoveAvailable, self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus, validateOwners(),
                  move.tabIDs.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  let now = current(self.store.state) else { return false }
            guard crosses else {
                do {
                    guard try self.store.commitSidebarWindowMove(now) else { return false }
                    arrive(); return true
                } catch {
                    showError(error); return false
                }
            }
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [profileID],
                                                destinationSpaceID: location.spaceID) { [weak self] in
                guard let self else { return }
                let moved = Set(move.tabIDs)
                self.store.moveAcrossProfiles(moved, proposal: { current($0)?.applying(to: $0) }) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true): self.onInterProfileMoveCommitted?(moved); arrive()
                    case .success(false): NSSound.beep()
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    @MainActor private final class SidebarWindowTransfer {
        let source: BrowserWindowController
        let destination: BrowserWindowController
        struct Plan {
            let tabIDs: [UUID]
            let sourceSpaceID: UUID, profileID: UUID, destinationSpaceID: UUID
            let isCurrent: (BrowserState) -> Bool
            let commit: (BrowserStore) throws -> Bool
            var arrival: UUID? = nil
            var leavesPlaceholder = false
            enum FailureReport { case alert, beep, silent }
            var failureReport = FailureReport.alert
        }
        let plan: Plan
        var onFinish: ((Bool) -> Void)?
        let sourceWindow: NSWindow
        let destinationWindow: NSWindow
        let sourceSelection: [UUID]
        let destinationSelection: [UUID]
        let sourceFocus: UUID?
        let destinationFocus: UUID?
        let claims: [UUID: NativePageOwnership.Claim]
        let wrappers: [UUID: PCBrowserView]
        let pages: [UUID: PCNativePage]
        let allWrappers: [UUID: PCBrowserView]
        let nativeIDs: [UUID]
        let easelTransfers: [UUID: EaselBrowserObjects.WindowTransfer]
        var begunEasels: Set<UUID> = []
        let notes: [UUID: NotePane]
        let easels: [UUID: EaselPane]
        var reservation: NativePageOwnership.CollectionTransfer?
        var containers: [UUID: NSView] = [:]
        var started = false
        var committed = false
        var resolving = false
        var recoveryInFlight = false
        var recoveryDialog: ParcDialog?
        var failure: String?
        var ids: Set<UUID> { Set(plan.tabIDs) }

        convenience init?(source: BrowserWindowController, destination: BrowserWindowController, move: SidebarWindowMove) {
            self.init(source: source, destination: destination, plan: Plan(tabIDs: move.tabIDs,
                sourceSpaceID: move.source.spaceID, profileID: move.source.profileID,
                destinationSpaceID: move.destination.spaceID,
                isCurrent: { move.applying(to: $0) != nil }, commit: { try $0.commitSidebarWindowMove(move) }))
        }

        init?(source: BrowserWindowController, destination: BrowserWindowController, plan: Plan) {
            guard let sourceWindow = source.window, let destinationWindow = destination.window else { return nil }
            self.source = source; self.destination = destination; self.plan = plan
            self.sourceWindow = sourceWindow; self.destinationWindow = destinationWindow
            sourceSelection = source.selectedTabIDs; destinationSelection = destination.selectedTabIDs
            sourceFocus = source.focusedTabID; destinationFocus = destination.focusedTabID
            claims = Dictionary(uniqueKeysWithValues: plan.tabIDs.map { ($0, source.ownership.claimSnapshot($0)) })
            wrappers = source.browsers.filter { plan.tabIDs.contains($0.key) }
            notes = source.noteEditors.filter { plan.tabIDs.contains($0.key) }
            easels = source.easelEditors.filter { plan.tabIDs.contains($0.key) }
            easelTransfers = easels.compactMapValues { $0.editor.pageObjects?.snapshotForWindowTransfer() }
            var originals = wrappers
            var ordered: [UUID] = []
            for id in plan.tabIDs {
                if wrappers[id] != nil { ordered.append(id) }
                if let transfer = easelTransfers[id] {
                    for child in transfer.views.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                        guard originals[child] == nil else { return nil }
                        originals[child] = transfer.views[child]; ordered.append(child)
                    }
                }
            }
            allWrappers = originals; pages = originals.compactMapValues(\.nativePage); nativeIDs = ordered
            guard validate() else { return nil }
        }

        func validate() -> Bool {
            guard source.window === sourceWindow, destination.window === destinationWindow,
                  source.sidebarWindowMoveEnvironment, destination.sidebarWindowMoveEnvironment,
                  source.activeSpaceID == plan.sourceSpaceID, destination.activeSpaceID == plan.destinationSpaceID,
                  source.activeProfileID == plan.profileID, destination.activeProfileID == plan.profileID,
                  source.selectedTabIDs == sourceSelection, destination.selectedTabIDs == destinationSelection,
                  source.focusedTabID == sourceFocus, destination.focusedTabID == destinationFocus,
                  source.store.retiringTabIDs.isDisjoint(with: ids), !source.hasPendingNativePage(in: ids),
                  source.peekPagesForRelocation(ids).isEmpty,
                  plan.isCurrent(source.store.state),
                  allWrappers.count == pages.count,
                  ids.allSatisfy({ id in
                      let claim = source.ownership.claimSnapshot(id)
                      return claim == claims[id] && (claim.owner == nil || claim.owner == source.presentationID)
                          && claim.transfer == nil && destination.browsers[id] == nil
                          && destination.noteEditors[id] == nil && destination.easelEditors[id] == nil
                          && source.browsers[id] === wrappers[id]
                          && source.noteEditors[id]?.editor === notes[id]?.editor
                          && source.easelEditors[id]?.editor === easels[id]?.editor
                  }), easels.allSatisfy({ id, pane in
                      guard let objects = pane.editor.pageObjects else { return easelTransfers[id] == nil }
                      guard let transfer = easelTransfers[id] else { return false }
                      return objects.isCurrent(transfer)
                  }) else { return false }
            return pages.allSatisfy { id, page in
                !page.isClosed && allWrappers[id]?.nativePage === page && allWrappers[id]?.window === sourceWindow
                    && page.profilePath == source.store.independentEngineProfilePath(for: plan.profileID)
                    && PCNativeBrowserApplication.owner(of: page) === source.nativeBinding
            }
        }

        func begin() -> Bool {
            let responder = sourceWindow.firstResponder
            defer {
                if !started, sourceWindow.isKeyWindow, sourceWindow.firstResponder == nil, let responder,
                   (responder as? NSView).map({ SavedFocus.mayReturn(to: $0, in: sourceWindow) }) ?? true {
                    sourceWindow.makeFirstResponder(responder)
                }
            }
            guard !started, source.sidebarWindowMoveAvailable, destination.sidebarWindowMoveAvailable,
                  validate(), source.prepareNotesToClose(ids),
                  sourceWindow.makeFirstResponder(nil), validate(),
                  let reservation = source.ownership.reserveCollection(plan.tabIDs,
                      from: source.presentationID, to: destination.presentationID) else { return false }
            started = true; self.reservation = reservation
            source.collectionTransfer = self; destination.collectionTransfer = self
            source.transferringTabIDs.formUnion(ids); destination.transferringTabIDs.formUnion(ids)
            source.sidebarPreviews?.dismiss(); destination.sidebarPreviews?.dismiss()
            source.pageCapture?.dismiss(restoreFocus: false); destination.pageCapture?.dismiss(restoreFocus: false)
            for id in plan.tabIDs {
                guard let transfer = easelTransfers[id] else { continue }
                guard easels[id]?.editor.beginPageOwnerWindowTransfer(transfer) == true else {
                    failure = "An Easel changed before it could move."; resolve(); return false
                }
                begunEasels.insert(id)
            }
            for id in nativeIDs {
                let container = NSView(frame: destination.pageHost.bounds)
                container.autoresizingMask = [.width, .height]
                destination.parkedPages.addSubview(container); containers[id] = container
                destination.transferContainers[pages[id]!.identifier] = container
                source.attachedPageIDs.remove(pages[id]!.identifier)
            }
            if pages.isEmpty {
                _ = commitModel(); resolve(); return committed
            }
            let ordered = nativeIDs
            destination.nativeBinding?.transferPages(ordered.map { pages[$0]! },
                profilePath: source.store.independentEngineProfilePath(for: plan.profileID),
                containers: ordered.map { containers[$0]! }, commit: { [self] in
                    MainActor.assumeIsolated { commitModel() }
                }, completion: { [self] _, error in
                    MainActor.assumeIsolated { failure = failure ?? error?.localizedDescription; resolve() }
                })
            return true
        }

        func commitModel() -> Bool {
            guard let reservation, source.ownership.isCurrent(reservation),
                  source.window === sourceWindow, destination.window === destinationWindow,
                  source.sidebarWindowMoveEnvironment, destination.sidebarWindowMoveEnvironment,
                  source.activeSpaceID == plan.sourceSpaceID, destination.activeSpaceID == plan.destinationSpaceID,
                  source.selectedTabIDs == sourceSelection, destination.selectedTabIDs == destinationSelection,
                  source.focusedTabID == sourceFocus, destination.focusedTabID == destinationFocus,
                  source.prepareNotesToClose(ids),
                  pages.allSatisfy({ !$0.value.isClosed && PCNativeBrowserApplication.owner(of: $0.value) === destination.nativeBinding }),
                  easels.allSatisfy({ id, pane in
                      guard let transfer = easelTransfers[id] else { return pane.editor.pageObjects == nil }
                      return begunEasels.contains(id) && pane.editor.pageObjects?.isCurrent(transfer) == true
                  }) else { return false }
            do { committed = try plan.commit(source.store); return committed }
            catch { failure = error.localizedDescription; return false }
        }

        func resolve() {
            guard !resolving, !recoveryInFlight, let reservation else { return }
            resolving = true
            defer { resolving = false }
            let target = committed ? destination : source
            let targetWindow = committed ? destinationWindow : sourceWindow
            let closed = Set(pages.filter { $0.value.isClosed }.map(\.key)).intersection(ids)
            guard pages.allSatisfy({ $0.value.isClosed || PCNativeBrowserApplication.owner(of: $0.value) === target.nativeBinding }),
                  source.ownership.isCurrent(reservation, closed: closed) else { presentRecovery(); return }
            for id in plan.tabIDs {
                guard let page = pages[id], !page.isClosed, let browser = wrappers[id],
                      let tab = source.store.state.tabs.first(where: { $0.id == id }) else { continue }
                let pane = target.panes[id] ?? target.makePane(tab)
                target.panes[id] = pane
                if pane.superview == nil { target.parkedPages.addSubview(pane) }
                let other = committed ? source : destination
                if other.panes[id]?.browser === browser { other.panes[id]?.browser = nil }
                pane.browser = browser; pane.showBrowser()
                guard target.nativeBinding?.pageDidAttach(page, container: browser) == true,
                      browser.window === targetWindow, !page.isClosed,
                      PCNativeBrowserApplication.owner(of: page) === target.nativeBinding else { presentRecovery(); return }
            }
            for id in plan.tabIDs {
                guard let easel = easels[id], let tab = source.store.state.tabs.first(where: { $0.id == id }) else { continue }
                let pane = target.panes[id] ?? target.makePane(tab); target.panes[id] = pane
                if pane.superview == nil { target.parkedPages.addSubview(pane) }
                pane.showNativeContent(easel.editor.view)
                if let transfer = easelTransfers[id], begunEasels.contains(id) {
                    guard easel.editor.pageObjects?.isCurrent(transfer, checkingDocument: false) == true else { presentRecovery(); return }
                    for (child, page) in transfer.pages where !page.isClosed {
                        guard let view = transfer.views[child], view.window === targetWindow,
                              target.nativeBinding?.pageDidAttach(page, container: view) == true,
                              page.embeddedOwnerValid, PCNativeBrowserApplication.owner(of: page) === target.nativeBinding else { presentRecovery(); return }
                    }
                    guard target.configureEaselOwner(tab, documentID: easel.documentID, editor: easel.editor,
                        windowTransfer: transfer) else { presentRecovery(); return }
                }
            }
            guard begunEasels.allSatisfy({ id in
                guard let transfer = easelTransfers[id] else { return false }
                return easels[id]?.editor.pageObjects?.canFinishWindowTransfer(transfer) == true
            }), source.ownership.finishCollection(reservation, moved: committed, closed: closed) else { presentRecovery(); return }
            for id in begunEasels {
                if let transfer = easelTransfers[id] { _ = easels[id]?.editor.pageObjects?.finishWindowTransfer(transfer) }
            }
            if committed {
                for id in plan.tabIDs {
                    guard let tab = source.store.state.tabs.first(where: { $0.id == id }) else { continue }
                    if let browser = wrappers[id], let page = pages[id], !page.isClosed {
                        destination.browsers[id] = browser; browser.delegate = destination
                        destination.browserProfiles[id] = tab.profileID; destination.liveTabModels[id] = tab
                        destination.requestedURLs[id] = source.requestedURLs[id] ?? tab.url
                        destination.zoomLevels[id] = source.zoomLevels[id]
                        if source.loadingTabs.contains(id) { destination.loadingTabs.insert(id) }
                        destination.attachedPageIDs.insert(page.identifier)
                    }
                    if let note = notes[id] {
                        destination.noteEditors[id] = NotePane(documentID: note.documentID, profileID: note.profileID,
                            editor: note.editor, originalTab: tab)
                        destination.configureNoteOwner(tab, id: note.documentID, editor: note.editor)
                        let pane = destination.panes[id] ?? destination.makePane(tab); destination.panes[id] = pane
                        if pane.superview == nil { destination.parkedPages.addSubview(pane) }
                        pane.showNativeContent(note.editor.view)
                    }
                    if let easel = easels[id] {
                        destination.easelEditors[id] = EaselPane(documentID: easel.documentID, profileID: easel.profileID,
                            editor: easel.editor, originalTab: tab)
                        destination.configureEaselOwner(tab, documentID: easel.documentID, editor: easel.editor)
                        let pane = destination.panes[id] ?? destination.makePane(tab); destination.panes[id] = pane
                        if pane.superview == nil { destination.parkedPages.addSubview(pane) }
                        pane.showNativeContent(easel.editor.view)
                    }
                    source.browsers.removeValue(forKey: id); source.noteEditors.removeValue(forKey: id); source.easelEditors.removeValue(forKey: id)
                    source.browserProfiles.removeValue(forKey: id); source.liveTabModels.removeValue(forKey: id)
                    source.requestedURLs.removeValue(forKey: id); source.zoomLevels.removeValue(forKey: id)
                    source.loadingTabs.remove(id); source.failures.removeValue(forKey: id); source.easelFailures.removeValue(forKey: id)
                    source.panes.removeValue(forKey: id)?.removeFromSuperview()
                    if !plan.leavesPlaceholder || !source.presentation.leavePlaceholder(id, state: source.store.state) {
                        source.presentation.remove(id)
                    }
                    source.renderedPaneIDs.removeAll { $0 == id }
                }
                if source.focusedTabID.map(ids.contains) == true { source.focusedTabID = source.presentation.preferredFocusedTabID }
                if let arrival = plan.arrival {
                    if destination.presentation.selectExistingTab(arrival, state: source.store.state,
                        available: { destination.ownership.canUse($0, owner: destination.presentationID) }) {
                        destination.presentation.recordFocusedTab(arrival); destination.focusedTabID = arrival
                    }
                } else if destinationSelection.isEmpty, let first = plan.tabIDs.first {
                    _ = destination.presentation.selectExistingTab(first, state: source.store.state,
                        available: { destination.ownership.canUse($0, owner: destination.presentationID) })
                    destination.focusedTabID = destination.selectedTabIDs.first
                }
            } else {
                for (id, page) in pages where !closed.contains(id) { source.attachedPageIDs.insert(page.identifier) }
            }
            for (id, container) in containers {
                if let page = pages[id] { destination.transferContainers.removeValue(forKey: page.identifier) }
                if container.subviews.isEmpty { container.removeFromSuperview() }
            }
            source.transferringTabIDs.subtract(ids); destination.transferringTabIDs.subtract(ids)
            source.collectionTransfer = nil; destination.collectionTransfer = nil
            source.refreshMiniPlayers(force: true); destination.refreshMiniPlayers(force: true)
            source.schedulePresentationSessionRecord(); destination.schedulePresentationSessionRecord()
            source.render(source.store.state); destination.render(destination.store.state)
            source.requestNativeSelection(); destination.requestNativeSelection()
            if !committed, let failure {
                switch plan.failureReport {
                case .alert: destination.showTabTransferFailure(failure)
                case .beep: destination.refuseTabMove()
                case .silent: break
                }
            }
            let finished = onFinish; onFinish = nil; finished?(committed)
        }

        func presentRecovery() {
            guard recoveryDialog == nil, destinationWindow.attachedSheet == nil else { return }
            var content = ParcDialog.Content(title: "Some tabs couldn’t be moved",
                message: "Retry to reconnect the affected tabs, or close them with their normal leave-page confirmation.",
                confirm: "Retry")
            content.secondary = "Close Affected Tabs"; content.auxiliary = "Keep Open"
            let dialog = ParcDialog(content)
            recoveryDialog = dialog
            _ = dialog.begin(for: destinationWindow) { [self] response in
                self.recoveryDialog = nil
                if response == .confirm { retry() }
                else if response == .secondary { closeOriginalPages() }
            }
        }

        func closeOriginalPages() {
            guard !recoveryInFlight, source.prepareNotesToClose(ids) else { return }
            let originals = nativeIDs.compactMap { pages[$0] }.filter { !$0.isClosed }
            recoveryInFlight = true
            PCNativeBrowserApplication.requestClosePages(originals, shouldCommit: { [self] in
                MainActor.assumeIsolated {
                    source.collectionTransfer === self && destination.collectionTransfer === self
                        && source.prepareNotesToClose(ids)
                        && originals.allSatisfy { !$0.isClosed }
                }
            }, completion: { [self] _ in
                MainActor.assumeIsolated { recoveryInFlight = false; resolve() }
            })
        }

        func retry() {
            guard !recoveryInFlight else { return }
            let target = committed ? destination : source
            let other = committed ? source : destination
            let misplaced = nativeIDs.filter { id in
                guard let page = pages[id], !page.isClosed else { return false }
                return PCNativeBrowserApplication.owner(of: page) === other.nativeBinding
            }
            guard !misplaced.isEmpty, let binding = target.nativeBinding else { resolve(); return }
            let views = misplaced.map { id -> NSView in
                if target === source { return allWrappers[id]! }
                return containers[id]!
            }
            recoveryInFlight = true
            binding.transferPages(misplaced.map { pages[$0]! },
                profilePath: source.store.independentEngineProfilePath(for: plan.profileID),
                containers: views, commit: { true }, completion: { [self] _, error in
                    MainActor.assumeIsolated { recoveryInFlight = false; failure = error?.localizedDescription; resolve() }
                })
        }
    }

    func prepareSidebarSpaceRelocationOwnership(_ ids: Set<UUID>) -> (() -> Bool)? {
        guard ids.contains(where: { ownership.claimSnapshot($0).owner == presentationID || browsers[$0] != nil || easelEditors[$0] != nil || noteEditors[$0] != nil }) else { return { true } }
        guard !store.isEphemeral, !isPrivateBrowsing, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, let window, window.attachedSheet == nil,
              transferringTabIDs.isDisjoint(with: ids), resolvingTransfers.isDisjoint(with: ids),
              Set(transferRecoveries.keys).isDisjoint(with: ids), closingTabIDs.isDisjoint(with: ids),
              !hasPendingNativePage(in: ids), nativeFullscreenTabID.map({ !ids.contains($0) }) ?? true,
              peekPagesForRelocation(ids).isEmpty else { return nil }
        let wrappers = ids.compactMap { id -> (UUID, PCBrowserView, PCNativePage?)? in
            browsers[id].map { (id, $0, $0.nativePage) }
        }
        let embedded = ids.flatMap { embeddedEaselPages(forTabID: $0) }
        let editors = Dictionary(uniqueKeysWithValues: ids.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let notes = Dictionary(uniqueKeysWithValues: ids.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending, !self.windowCloseApproved,
                  window.attachedSheet == nil, !self.hasPendingNativePage(in: ids),
                  self.transferringTabIDs.isDisjoint(with: ids), self.resolvingTransfers.isDisjoint(with: ids),
                  Set(self.transferRecoveries.keys).isDisjoint(with: ids), self.closingTabIDs.isDisjoint(with: ids),
                  self.nativeFullscreenTabID.map({ !ids.contains($0) }) ?? true,
                  self.peekPagesForRelocation(ids).isEmpty,
                  ids.compactMap({ self.browsers[$0] }).count == wrappers.count,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == editors,
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == notes,
                  Set(ids.flatMap { self.embeddedEaselPages(forTabID: $0) }.map(ObjectIdentifier.init)) == Set(embedded.map(ObjectIdentifier.init)) else { return false }
            for (id, browser, page) in wrappers {
                guard self.browsers[id] === browser, browser.nativePage === page else { return false }
                if let page {
                    guard !page.isClosed, PCNativeBrowserApplication.owner(of: page) === self.nativeBinding,
                          browser.window === window, let tab = self.store.state.tabs.first(where: { $0.id == id }),
                          tab.profileID == self.browserProfiles[id],
                          page.profilePath == self.store.independentEngineProfilePath(for: tab.profileID) else { return false }
                }
            }
            return embedded.allSatisfy { !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === self.nativeBinding }
        }
        return valid() ? valid : nil
    }

    private func peekPagesForRelocation(_ ids: Set<UUID>) -> [PCNativePage] {
        ids.flatMap { peekPages(forTabID: $0) }
    }

    private func prepareSidebarSpaceMove(_ items: [SidebarItemReference], to destinationID: UUID,
                                         pinsToday: Bool = false) -> (() -> Bool)? {
        if let destination = store.state.spaces.first(where: { $0.id == destinationID }), destination.profileID != activeProfileID {
            return prepareInterProfileSpaceMove(items, to: destination, pinsToday: pinsToday)
        }
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable, commandBar == nil,
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: destinationID, profileID: activeProfileID),
              var move = SidebarSpaceMove(items: items, from: expected, to: target, state: store.state),
              let validateOwners = prepareSidebarSpaceMoveOwners?(Set(move.tabIDs)) else { return nil }
        move.pinsToday = pinsToday
        let claims = Dictionary(uniqueKeysWithValues: move.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              move.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCommandsAvailable, self.commandBar == nil,
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus, validateOwners(),
                  move.tabIDs.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  move.applying(to: self.store.state) != nil else { return false }
            consumed = true
            do {
                guard try self.store.moveSidebarItemsAcrossSpaces(move) else { return false }
                self.render(self.store.state); self.requestNativeSelection()
                if let item = move.roots.first {
                    self.showSidebarMoveNotice(item: item, space: destinationID, profile: expected.profileID)
                }
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    private func prepareInterProfileSpaceMove(_ items: [SidebarItemReference], to destination: BrowserSpace,
                                              pinsToday: Bool = false) -> (() -> Bool)? {
        guard !store.isEphemeral, !isPrivateBrowsing, spaceCommandsAvailable, commandBar == nil,
              let expected = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let target = SidebarHierarchySnapshot(state: store.state, spaceID: destination.id, profileID: destination.profileID),
              var move = SidebarSpaceMove(items: items, from: expected, to: target, state: store.state), move.crossesProfiles,
              Set(move.tabIDs).isDisjoint(with: store.retiringTabIDs) else { return nil }
        move.pinsToday = pinsToday
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCommandsAvailable, self.commandBar == nil,
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus,
                  move.applying(to: self.store.state) != nil else { return false }
            consumed = true
            return self.confirmInterProfileMove(tabCount: move.tabIDs.count,
                                                sourceProfiles: move.tabIDs.isEmpty ? [] : [expected.profileID],
                                                destinationSpaceID: destination.id) { [weak self] in
                guard let self else { return }
                let moved = Set(move.tabIDs)
                self.store.moveAcrossProfiles(moved, proposal: { move.applying(to: $0) }) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(moved)
                        self.render(self.store.state); self.requestNativeSelection()
                        if let item = move.roots.first {
                            self.showSidebarMoveNotice(item: item, space: destination.id, profile: destination.profileID)
                        }
                    case .success(false): NSSound.beep()
                    case .failure(let error): showError(error)
                    }
                }
            }
        }
    }

    private func dismissSidebarMoveNotice() {
        sidebarMoveToast?.dismiss(animated: false); sidebarMoveToast = nil
    }

    private func showSidebarMoveNotice(item: SidebarItemReference, space: UUID, profile: UUID, message: String? = nil) {
        dismissSidebarMoveNotice()
        let toast = showToast(.standard(message ?? "Tab moved! Click to go there."), at: .window, onTap: { [weak self] in
            _ = self?.revealSidebarItem(item, spaceID: space, profileID: profile)
        }, onRetire: { [weak self] in
            guard let self, self.sidebarMoveToast?.isRetiring != false else { return }
            self.sidebarMoveToast = nil
        })
        sidebarMoveToast = toast
    }

    @discardableResult
    func revealSidebarItem(_ item: SidebarItemReference, spaceID: UUID, profileID: UUID) -> Bool {
        guard !store.isEphemeral, !isPrivateBrowsing, activeProfileID == profileID,
              commandBar == nil, activePeek == nil, canSelectSpace(spaceID, profileID: profileID),
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              let target = SidebarItemReveal(item: item, spaceID: spaceID, profileID: profileID, state: store.state) else { return false }
        do {
            guard try store.revealSidebarItem(target), selectSpaceFromUser(spaceID, profileID: profileID) else { return false }
            closeLibrary(restoreFocus: false)
            render(store.state)
            if sidebarPresentation == .hidden { setSidebarPresentation(.floating) }
            rootView.layoutSubtreeIfNeeded()
            sidebar.revealItem(item)
            return true
        } catch { showError(error); return false }
    }

    private var folderDuplicateContextAvailable: Bool {
        guard !store.isEphemeral, nativeWindowRequest?.isOffTheRecord != true,
              let binding = nativeBinding, !binding.isPrivateBrowsing else { return false }
        switch binding.browsingContextKind {
        case .regular, .unavailable: return true
        case .offTheRecord, .mixed: return false
        @unknown default: return false
        }
    }

    private func prepareFolderDuplicate(_ folderID: UUID) -> (() -> Bool)? {
        prepareSidebarDuplicate([.folder(folderID)])
    }

    private func prepareSidebarDuplicate(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard folderDuplicateContextAvailable, let window, let lease = prepareSidebarMoves(items),
              let target = SidebarDuplicateTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let selectionIsCurrent: () -> Bool
        if items.count > 1 {
            guard let validator = sidebar.itemSelectionValidator(items) else { return nil }
            selectionIsCurrent = validator
        } else { selectionIsCurrent = { true } }
        let destinations: () -> SidebarCopySources? = { [weak self] in
            guard let self, selectionIsCurrent(), lease.isValid, self.folderDuplicateContextAvailable,
                  let sources = self.resolveSidebarCopyDestinations?(target.tabs),
                  sources.validates(target.tabs) else { return nil }
            return sources
        }
        guard destinations() != nil else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  let urls = destinations() else { return false }
            consumed = true; lease.end()
            do {
                guard let result = try self.store.duplicateSidebarItems(target, destinations: urls.destinations, documents: urls.documents,
                    creation: self.creationProvenance(activeTabID: self.currentTabID)) else { return false }
                self.openDuplicatedChildren(result.openTabIDs, spaceID: target.hierarchy.spaceID,
                    profileID: target.hierarchy.profileID, window: window)
                return true
            } catch {
                showError(error); return false
            }
        }
    }

    private func prepareFolderDeletion(_ folderID: UUID) -> (() -> Bool)? {
        prepareSidebarDeletion([.folder(folderID)])
    }

    private func prepareSidebarRootsClose(_ items: [SidebarItemReference], archive: Bool, requiresConfirmation: Bool,
                                          isSelectionCommand: Bool, selectionIsCurrent current: @escaping () -> Bool,
                                          declined: @escaping () -> Void = {}) -> (() -> Bool)? {
        guard let target = SidebarKeyboardCloseTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let ids = Set(target.items.tabs.map(\.id))
        let expected = target.items.hierarchy
        let elsewhere = target.items.tabs.map(\.id).filter { !switcherCanUse($0) }
        if !elsewhere.isEmpty {
            let valid: () -> Bool = { [weak self] in
                guard let self, current(), self.sidebarRootsCloseAvailable(ids),
                      self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID else { return false }
                return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
            }
            guard valid() else { return nil }
            var consumed = false
            return { [weak self] in
                guard !consumed, let self, valid() else { return false }
                consumed = true
                return self.moveRootsHere(elsewhere[...], moved: []) { [weak self] moved in
                    let giveBack = { [weak self] in self?.returnMovedRoots(moved); declined() }
                    guard let self, ids.allSatisfy(self.switcherCanUse),
                          let close = self.prepareSidebarRootsClose(items, archive: archive, requiresConfirmation: requiresConfirmation,
                              isSelectionCommand: isSelectionCommand, selectionIsCurrent: current, declined: giveBack),
                          close() else { giveBack(); return false }
                    return true
                }
            }
        }
        if !isPrivateBrowsing, archive {
            return prepareSidebarDeletion(items, isSelectionCommand: isSelectionCommand,
                requiresConfirmation: requiresConfirmation, recordsKeyboardReopen: true, selectionIsCurrent: current,
                declined: declined)
        }
        guard current(), let window else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let valid: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, current(),
                  self.sidebarRootsCloseAvailable(ids, movingHere: false),
                  self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                  self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
            return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
        }
        guard valid() else { return nil }
        var consumed = false
        return { [weak self] in
            guard !consumed, let self, valid(),
                  let releaseSelection = isSelectionCommand ? self.sidebar.retainItemSelectionForSheet(items) : {} else { return false }
            consumed = true
            self.prepareStoreContext()
            self.closeTabsWithReopen(ids, shouldCommit: { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose, current(),
                      self.activeSpaceID == expected.spaceID, self.activeProfileID == expected.profileID,
                      self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
                return SidebarHierarchySnapshot(state: self.store.state, spaceID: expected.spaceID, profileID: expected.profileID) == expected
            }) { [weak self] allowed in
                releaseSelection()
                guard let self, allowed else { declined(); return }
                for id in ids { self.presentation.remove(id) }
                self.render(self.store.state); self.requestNativeSelection()
            }
            return true
        }
    }

    private func splitCellCloseAvailable(_ id: UUID) -> Bool {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }) else { return false }
        return sidebarRootsCloseAvailable(Set(group.tabIDs))
    }

    private func splitCellCloseAction(_ id: UUID) -> SidebarSplitCellLayout.CloseAction? {
        guard let group = SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.id == id }),
              let location = SidebarHierarchy.location(of: .split(id), state: store.state, spaceID: activeSpaceID) else { return nil }
        return SidebarSplitCellLayout.closeAction(today: location.section == .today,
            anyChildPresented: group.tabIDs.contains { hasPresentedContent($0) })
    }

    private func hasPresentedContent(_ id: UUID) -> Bool {
        browsers[id] != nil || noteEditors[id] != nil || easelEditors[id] != nil
    }

    private func prepareSidebarDeletion(_ items: [SidebarItemReference], isSelectionCommand: Bool = false,
                                        requiresConfirmation: Bool = true, recordsKeyboardReopen: Bool = false,
                                        selectionIsCurrent: @escaping () -> Bool = { true },
                                        declined: @escaping () -> Void = {}) -> (() -> Bool)? {
        guard !folderUndo.isBusy, folderDuplicateContextAvailable, let window,
              selectionIsCurrent(), let lease = prepareSidebarMoves(items),
              let target = FolderRemovalTarget(items: items, spaceID: activeSpaceID,
                  profileID: activeProfileID, state: store.state) else { return nil }
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents) else { return nil }
        let ids = Set(target.tabs.map(\.id))
        guard retirementUnavailableReason?(ids) == nil else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        let reopen = recordsKeyboardReopen ? ClosedItemIntent(
            ids: Set(target.tabs.filter { $0.kind == .today }.map(\.id)), state: store.state,
            spaceID: activeSpaceID, profileID: activeProfileID, focusedTabID: currentTabID) : nil
        guard let nextSelection = FolderRemovalSelection.resolve(target: target, state: store.state,
            selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
            previouslySelectedItemID: self.presentation.previouslySelectedItemID,
            available: { self.switcherCanUse($0) }) else { return nil }
        var consumed = false
        return { [weak self, weak window] in
            guard !consumed, let self, let window, self.window === window,
                  !self.folderUndo.isBusy, self.folderDuplicateContextAvailable, selectionIsCurrent(), lease.isValid, window.attachedSheet == nil else { return false }
            guard let releaseSelection = isSelectionCommand ? self.sidebar.retainItemSelectionForSheet(items) : {} else { return false }
            consumed = true
            let proceed: (Bool) -> Void = { [weak self, weak window] approved in
                DispatchQueue.main.async {
                    guard let self, let window, self.window === window else { releaseSelection(); lease.end(); return }
                    guard approved, selectionIsCurrent(), lease.isValid,
                          !self.folderUndo.isBusy, self.folderDuplicateContextAvailable,
                          self.retirementUnavailableReason?(ids) == nil else {
                        releaseSelection(); lease.end()
                        self.updateNavigation(); declined()
                        return
                    }
                    lease.end()
                    self.store.deleteFolder(target, selection: nextSelection, documents: documents, shouldCommit: { [weak self, weak window] in
                        guard let self, let window, self.window === window,
                              !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                              !self.folderUndo.isBusy, self.folderDuplicateContextAvailable,
                              self.activeSpaceID == target.hierarchy.spaceID,
                              self.activeProfileID == target.hierarchy.profileID,
                              self.selectedTabIDs == selection, self.focusedTabID == focus, selectionIsCurrent() else { return false }
                        return FolderRemovalSelection.resolve(target: target, state: self.store.state,
                            selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
                            previouslySelectedItemID: self.presentation.previouslySelectedItemID,
                            available: { self.switcherCanUse($0) }) == nextSelection
                    }, didCommit: { [weak self, weak window] undo in
                        guard let self, let window, self.window === window, !self.isClosing else { return }
                        self.registerFolderUndo(undo)
                        if !target.folderIDs.isEmpty {
                            if !self.isPrivateBrowsing { self.closedItems.recordFolderDeletion(undo) }
                        } else if let reopen { self.closedItems.record(reopen, in: self.store.state) }
                    }) { [weak self, weak window] result in
                        releaseSelection()
                        guard let self, let window, self.window === window else { return }
                        switch result {
                        case .success(true):
                            for id in ids { self.presentation.remove(id) }
                            let applied = self.presentation.finishFolderRemoval(nextSelection, state: self.store.state,
                                available: { self.switcherCanUse($0) })
                            if applied { self.focusedTabID = nextSelection.focusedTabID }
                            self.render(self.store.state)
                            if applied && !ids.isDisjoint(with: selection) {
                                self.requestNativeSelection(); self.focusSelectedLocalContent()
                            }
                        case .success(false): self.updateNavigation(); declined()
                        case .failure(let error): self.updateNavigation(); declined(); showError(error)
                        }
                    }
                }
            }
            if requiresConfirmation {
                let singleFolder = target.roots.count == 1 && !target.folderIDs.isEmpty
                ParcDialog.confirm(in: window,
                    title: singleFolder ? "Delete your “\(target.name)” folder?"
                        : target.folderIDs.isEmpty ? "Archive the selected tabs?" : "Delete the selected items?",
                    message: singleFolder ? "Deleting this folder will archive the tabs inside it."
                        : "All selected tabs, including tabs inside selected folders, will be archived. Notes and Easels will remain in your Library.",
                    confirm: singleFolder ? "Delete Folder" : target.folderIDs.isEmpty ? "Archive Tabs" : "Delete",
                    destructive: true, decided: proceed)
            } else {
                proceed(true)
            }
            return true
        }
    }

    private var windowUndoContextAvailable: Bool {
        windowUndoOwnerAvailable && window?.attachedSheet == nil
    }

    private var windowUndoOwnerAvailable: Bool {
        guard let binding = nativeBinding, binding.window === window,
              presentation.isReady, !isPopupWindow, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              window?.isVisible == true else { return false }
        switch binding.browsingContextKind {
        case .regular: return !store.isEphemeral && !binding.isPrivateBrowsing
        case .offTheRecord: return store.isEphemeral && binding.isPrivateBrowsing
        case .unavailable: return !store.isEphemeral && !binding.isPrivateBrowsing
        case .mixed: return false
        @unknown default: return false
        }
    }

    private var folderUndoOwnerAvailable: Bool {
        folderDuplicateContextAvailable && presentation.isReady && !isPopupWindow
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && window?.isVisible == true
    }

    private var folderUndoContextAvailable: Bool {
        folderUndoOwnerAvailable && window?.attachedSheet == nil
    }

    private var usesFolderUndoResponder: Bool {
        if windowUndoContextAvailable, let editor = themeEditor,
           editor.window?.isKeyWindow == true,
           let responder = editor.window?.firstResponder as? NSView,
           responder === editor || responder.isDescendant(of: editor) { return true }
        guard windowUndoContextAvailable, let window, NSApp.mainWindow === window,
              PCNativeBrowserApplication.canUseWindowUndo(in: window),
              let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSControl { return false }
        guard let view = responder as? NSView else { return responder === window }
        if let page = selectedNativePage(), view === page.nativeView || view.isDescendant(of: page.nativeView) {
            return page.canUseWindowUndo
        }
        return view === sidebar || view.isDescendant(of: sidebar) || view === rootView || view === pageHost
            || libraryView.map { view === $0.spaceManager || view.isDescendant(of: $0.spaceManager) } == true
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard sender === window else { return nil }
        return commandBar?.fieldEditor(for: client) ?? residentCommandBar?.fieldEditor(for: client)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard self.window === window else { return nil }
        return usesFolderUndoResponder ? folderUndo : nativeEditingUndo
    }

    func configureFolderUndoMenuItem(_ item: NSMenuItem, redo: Bool) {
        let direction: FolderUndoManager.Direction = redo ? .redo : .undo
        if usesFolderUndoResponder, let command = folderUndo.command(direction) {
            item.action = #selector(performFolderUndoCommand(_:)); item.target = self
            item.representedObject = command
            item.title = (redo ? "Redo " : "Undo ") + command.name
        } else {
            item.action = NSSelectorFromString(redo ? "redo:" : "undo:")
            item.target = nil; item.representedObject = nil; item.title = redo ? "Redo" : "Undo"
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performFolderUndoCommand(_:)) else { return true }
        guard usesFolderUndoResponder, let command = item.representedObject as? FolderUndoManager.Command else { return false }
        return folderUndo.canPerform(command)
    }

    func registerAppearanceUndo(from previous: AppAppearance, to next: AppAppearance) {
        guard folderUndoContextAvailable else { return }
        folderUndo.append(.init(name: "Update Appearance",
            isValid: { direction in AppAppearance.current == (direction == .undo ? next : previous) },
            isAvailable: { [weak self] _ in self?.folderUndoContextAvailable == true },
            perform: { direction, done in done(AppAppearance.apply(direction == .undo ? previous : next)) }))
    }

    @objc private func performFolderUndoCommand(_ sender: NSMenuItem) {
        guard validateMenuItem(sender), let command = sender.representedObject as? FolderUndoManager.Command else { return }
        _ = folderUndo.perform(command)
    }

    private func folderUndoShortcut(_ event: NSEvent) -> PCNativeShortcutCommand? {
        guard event.type == .keyDown, !event.isARepeat,
              let key = KeyboardShortcut.capture(event), key.key == "z",
              key.flags == .command || key.flags == [.command, .shift],
              usesFolderUndoResponder,
              let command = folderUndo.command(key.flags.contains(.shift) ? .redo : .undo) else { return nil }
        folderUndoKeyItem.representedObject = command
        return PCNativeShortcutCommand(item: folderUndoKeyItem, revision: folderUndo.revision, priority: .preferParc)
    }

    private func registerFolderUndo(_ record: FolderDeletionUndo) {
        let operation = FolderUndoOperation(record)
        _ = folderUndo.append(.init(name: record.actionName, isValid: { [weak self] direction in
            guard let self else { return false }
            switch direction {
            case .undo: return self.store.canUndoFolderDeletion(operation.record)
            case .redo: return operation.record.redoTarget(in: self.store.state) != nil
            }
        }, isAvailable: { [weak self] direction in
            guard let self, self.folderUndoContextAvailable,
                  operation.record.documentsAreAvailable else { return false }
            let ids = Set(operation.record.tabs.map(\.id))
            guard ids.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            switch direction {
            case .undo: return ids.allSatisfy { self.switcherCanUse($0) }
            case .redo: return self.retirementUnavailableReason?(ids) == nil
            }
        }, perform: { [weak self] direction, completion in
            guard let self else { completion(false); return }
            switch direction {
            case .undo: self.undoFolder(operation, completion: completion)
            case .redo: self.redoFolder(operation, completion: completion)
            }
        }))
    }

    private func undoFolder(_ operation: FolderUndoOperation, completion: @escaping (Bool) -> Void) {
        guard folderUndoContextAvailable, let window else { completion(false); return }
        let record = operation.record
        do {
            let committed = try store.undoFolderDeletion(record, shouldCommit: { [weak self, weak window] in
                guard let self, let window, self.window === window, self.folderUndoContextAvailable else { return false }
                return record.tabs.allSatisfy { self.switcherCanUse($0.id) }
            })
            if committed {
                let focused = presentation.finishFolderUndo(record, state: store.state, available: { self.switcherCanUse($0) })
                if focused { focusedTabID = record.focusedTabID }
                render(store.state)
                if focused { requestNativeSelection(); focusSelectedLocalContent() }
            }
            completion(committed)
        } catch { completion(false); showError(error) }
    }

    private func redoFolder(_ operation: FolderUndoOperation, completion: @escaping (Bool) -> Void) {
        guard folderUndoContextAvailable, let window,
              let target = operation.record.redoTarget(in: store.state) else { completion(false); return }
        let space = activeSpaceID, profile = activeProfileID, selection = selectedTabIDs, focus = focusedTabID
        let ids = Set(target.tabs.map(\.id))
        guard retirementUnavailableReason?(ids) == nil else { completion(false); return }
        let nextSelection = space == target.hierarchy.spaceID
            ? FolderRemovalSelection.resolve(target: target, state: store.state, selected: selection,
                focused: focus, referrerPool: presentation.referrerPool,
                previouslySelectedItemID: presentation.previouslySelectedItemID,
                available: { self.switcherCanUse($0) }) : nil
        guard space != target.hierarchy.spaceID || nextSelection != nil else { completion(false); return }
        store.deleteFolder(target, selection: nextSelection, documents: operation.record.documentReferences, shouldCommit: { [weak self, weak window] in
            guard let self, let window, self.window === window, self.folderUndoOwnerAvailable,
                  self.activeSpaceID == space, self.activeProfileID == profile,
                  self.selectedTabIDs == selection, self.focusedTabID == focus else { return false }
            guard let nextSelection else { return true }
            return FolderRemovalSelection.resolve(target: target, state: self.store.state,
                selected: selection, focused: focus, referrerPool: self.presentation.referrerPool,
            previouslySelectedItemID: self.presentation.previouslySelectedItemID,
            available: { self.switcherCanUse($0) }) == nextSelection
        }, didCommit: { [weak self] undo in
            operation.record = undo
            if let self, !target.folderIDs.isEmpty, !self.isPrivateBrowsing { self.closedItems.recordFolderDeletion(undo) }
        }) { [weak self, weak window] result in
            guard let self, let window, self.window === window else { completion(false); return }
            switch result {
            case .success(let committed):
                if committed {
                    for id in ids { self.presentation.remove(id) }
                    let applied = nextSelection.map { self.presentation.finishFolderRemoval($0, state: self.store.state,
                        available: { self.switcherCanUse($0) }) } ?? false
                    if applied { self.focusedTabID = nextSelection?.focusedTabID }
                    self.render(self.store.state)
                    if applied && !ids.isDisjoint(with: selection) { self.requestNativeSelection(); self.focusSelectedLocalContent() }
                }
                completion(committed)
            case .failure(let error): completion(false); showError(error)
            }
        }
    }

    private func openDuplicatedChildren(_ ids: [UUID], spaceID: UUID, profileID: UUID, window: NSWindow,
                                        originatingSpaceID: UUID? = nil) {
        for id in ids {
            guard self.window === window, folderDuplicateContextAvailable, !isClosing, !wholeWindowClose, !windowClosePending,
                  activeSpaceID == (originatingSpaceID ?? spaceID), activeProfileID == profileID,
                  !store.isProfileRemovalPending(profileID), !store.retiringTabIDs.contains(id),
                  !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
                  browsers[id] == nil,
                  let tab = store.state.tabs.first(where: { $0.id == id && ($0.spaceID == spaceID || $0.kind == .favorite)
                      && $0.profileID == profileID && $0.archivedAt == nil }),
                  FolderDuplicateTarget.validDestination(tab.url), let url = URL(string: tab.url),
                  ownership.claim(id, owner: presentationID) else { continue }
            let pane = makePane(tab)
            pane.frame = pageHost.bounds
            panes[id] = pane; parkedPages.addSubview(pane)
            pane.layoutSubtreeIfNeeded()
            let browser = PCBrowserView(frame: pane.contentBounds,
                profilePath: store.independentEngineProfilePath(for: profileID))
            browser.delegate = self
            browsers[id] = browser; browserProfiles[id] = profileID; liveTabModels[id] = tab
            pane.browser = browser; pane.showBrowser(); pane.layoutSubtreeIfNeeded()
            requestedURLs[id] = tab.url
            if browser.loadBackgroundURL(url) {
                presentation.recordCreation(id, state: store.state)
            } else {
                failures[id] = "This copied page could not open. Select it to try again."
                requestedURLs.removeValue(forKey: id)
            }
        }
        attachOwnedPages()
    }

    private func externalSplitDropContent(_ id: UUID) -> (view: NSView, local: Bool, valid: () -> Bool)? {
        if let browser = browsers[id], let page = browser.nativePage {
            return (page.nativeView, false, { [weak self, weak browser, weak page] in
                guard let self, let browser, let page else { return false }
                return self.browsers[id] === browser && browser.nativePage === page && !page.isClosed
            })
        }
        if let note = noteEditors[id], note.editor.isViewLoaded, note.editor.canAcceptExternalSplitDrop {
            let editor = note.editor, documentID = note.documentID, profileID = note.profileID
            return (editor.view, true, { [weak self, weak editor] in
                guard let self, let editor, self.noteEditors[id]?.editor === editor,
                      self.noteEditors[id]?.documentID == documentID,
                      self.noteEditors[id]?.profileID == profileID,
                      let tab = self.store.state.tabs.first(where: { $0.id == id }),
                      tab.profileID == profileID, InternalPage(urlString: tab.url)?.noteID == documentID else { return false }
                return editor.canAcceptExternalSplitDrop
            })
        }
        if let easel = easelEditors[id], easel.editor.isViewLoaded, easel.editor.canAcceptExternalSplitDrop {
            let editor = easel.editor, documentID = easel.documentID, profileID = easel.profileID
            return (editor.view, true, { [weak self, weak editor] in
                guard let self, let editor, self.easelEditors[id]?.editor === editor,
                      self.easelEditors[id]?.documentID == documentID,
                      self.easelEditors[id]?.profileID == profileID,
                      let tab = self.store.state.tabs.first(where: { $0.id == id }),
                      tab.profileID == profileID, InternalPage(urlString: tab.url)?.easelID == documentID else { return false }
                return editor.canAcceptExternalSplitDrop
            })
        }
        return nil
    }

    private func beginExternalSplitDrop(from nativeView: NSView, info: NSDraggingInfo) -> ExternalSplitDropSession? {
        let otherWindow = window.map { !$0.isKeyWindow && NSApp.isActive && info.draggingSource != nil } ?? false
        guard otherWindow ? interProfileDropAvailable : splitCommandsAvailable,
              splitDropView == nil, commandBar == nil, pageCapture == nil,
              let window, window.isKeyWindow || otherWindow,
              let url = ExternalSplitDropSession.readURL(info.draggingPasteboard),
              selectedTabIDs.allSatisfy({ id in
                  store.state.tabs.contains { $0.id == id && $0.archivedAt == nil } &&
                  peekPages(forTabID: id).isEmpty
              }) else { return nil }
        let selection = selectedTabIDs, layout = activeSplitLayout
        let contents = selection.compactMap(externalSplitDropContent)
        guard contents.count == selection.count,
              let receiver = contents.first(where: { nativeView === $0.view || nativeView.isDescendant(of: $0.view) }) else { return nil }
        if receiver.local {
            let richTypes: [NSPasteboard.PasteboardType] = [EaselStyledText.pasteboardType,
                EaselStyledText.previousPasteboardType, EaselStyledText.legacyPasteboardType,
                .rtfd, .rtf, .png, .tiff]
            guard info.draggingPasteboard.availableType(from: richTypes) == nil else { return nil }
            if let source = info.draggingSource as? NSView,
               source === receiver.view || source.isDescendant(of: receiver.view) { return nil }
        }
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let bounds = pageHost.bounds, hostFrame = pageHost.frame, windowFrame = window.frame
        let identities = selection.compactMap { splitPaneIdentity($0) }
        let frames = selection.compactMap { panes[$0].map { $0.content.convert($0.content.bounds, to: pageHost) } }
        let originalTabs = selection.compactMap { id in store.state.tabs.first { $0.id == id } }
        let tabID = UUID(), savedHomeID = UUID()
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let possibleHome = ExternalSplitDrop.savedHomeSource(state: store.state, selection: selection, layout: layout, target: .insert(0))
        let typedHome = possibleHome.flatMap { InternalPage(urlString: $0.savedURL) != nil ? $0 : nil }
        let documents = typedHome.flatMap { resolveSidebarCopyDestinations?([$0])?.documents } ?? [:]
        guard hierarchy != nil, identities.count == selection.count, frames.count == selection.count,
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return nil }
        let validate: () -> Bool = { [weak self, weak window, weak nativeView] in
            guard let self, let window, let nativeView, self.window === window,
                  otherWindow ? self.interProfileDropAvailable : (window.isKeyWindow && self.splitCommandsAvailable),
                  self.commandBar == nil, self.pageCapture == nil, self.splitDropView == nil,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID,
                  self.activeSplitLayout == layout, self.pageHost.bounds == bounds,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  contents.allSatisfy({ $0.valid() && $0.view.window === window && $0.view.isDescendant(of: self.pageHost) }),
                  self.pageHost.frame == hostFrame, window.frame == windowFrame,
                  nativeView.window === window, nativeView.isDescendant(of: self.pageHost),
                  selection.enumerated().allSatisfy({ item in
                      guard self.splitPaneIdentity(item.element) == identities[item.offset],
                            let tab = self.store.state.tabs.first(where: { $0.id == item.element }),
                            tab.archivedAt == nil, tab.spaceID == originalTabs[item.offset].spaceID,
                            tab.profileID == profileID, tab.kind == originalTabs[item.offset].kind,
                            tab.folderID == originalTabs[item.offset].folderID,
                            tab.savedURL == originalTabs[item.offset].savedURL,
                            tab.savedTitle == originalTabs[item.offset].savedTitle,
                            tab.customTitle == originalTabs[item.offset].customTitle,
                            self.peekPages(forTabID: item.element).isEmpty,
                            let pane = self.panes[item.element] else { return false }
                      return pane.window === window && reservation.isCurrent
                  }) else { return false }
            return otherWindow || PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID,
            profileID: profileID, state: store.state)
        var admissions: [(target: SplitDropTarget, orientation: SplitOrientation, allowed: Bool)] = []
        let session = ExternalSplitDropSession(host: pageHost, info: info, frames: frames,
            orientation: layout?.orientation ?? .horizontal, reservation: reservation, validate: validate,
            insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear },
            canPropose: { [weak self] target, orientation in
                guard validate(), let self else { return false }
                if let home = ExternalSplitDrop.savedHomeSource(state: self.store.state, selection: selection, layout: layout, target: target),
                   !SidebarDocumentReference.validates([home], references: documents) { return false }
                if let cached = admissions.first(where: { $0.target == target && $0.orientation == orientation }) {
                    return cached.allowed
                }
                let allowed = ExternalSplitDrop.proposal(url: url, tabID: tabID, state: self.presentedState,
                    spaceID: spaceID, profileID: profileID, selection: selection, layout: layout,
                    target: target, orientation: orientation, creation: creation, now: Date(), savedHomeID: savedHomeID) != nil
                admissions.append((target, orientation, allowed))
                return allowed
            }, commit: { [weak self] target, orientation in
                guard let self, validate() else { return false }
                var committed = false
                self.performWindowCommand {
                    do {
                        committed = try self.store.dropExternalURLIntoSplit(url, tabID: tabID,
                            spaceID: spaceID, profileID: profileID, expectedSelection: selection,
                            expectedLayout: layout, target: target, orientation: orientation, creation: creation,
                            savedHomeID: savedHomeID, documents: ExternalSplitDrop.savedHomeSource(state: self.store.state,
                                selection: selection, layout: layout, target: target) == nil ? [:] : documents)
                        if committed { self.presentation.recordCreation(tabID, state: self.store.state) }
                    } catch { self.showToast(.standard("Couldn’t add link"), at: .window) }
                }
                if committed {
                    self.focusedTabID = tabID; self.updateNavigation(); self.requestNativeSelection()
                    if let home = self.store.state.tabs.first(where: { $0.id == savedHomeID }) {
                        self.openDuplicatedChildren([savedHomeID], spaceID: home.spaceID, profileID: profileID,
                            window: window, originatingSpaceID: spaceID)
                    }
                }
                return committed
            })
        if session == nil { reservation.end() }
        session?.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        return session
    }

    private func beginSplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard splitCommandsAvailable, splitDropView == nil,
              let window, window.isKeyWindow, commandBar == nil,
              let source = store.state.tabs.first(where: { $0.id == sourceID && $0.archivedAt == nil }),
              source.profileID == activeProfileID, source.spaceID == activeSpaceID, source.kind != .favorite,
              switcherCanUse(sourceID) || canMovePageHere(sourceID), peekPages(forTabID: sourceID).isEmpty else { return nil }
        let sourceElsewhere = !switcherCanUse(sourceID)
        let selection = selectedTabIDs, layout = activeSplitLayout
        guard !selection.contains(sourceID) else { return nil }
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let frame = pageHost.bounds, windowFrame = window.frame
        let sourceBrowser = browsers[sourceID], sourcePage = sourceBrowser?.nativePage
        let sourcePane = panes[sourceID]
        let sourceBrowserIdentity = sourceBrowser.map(ObjectIdentifier.init)
        let sourcePaneIdentity = sourcePane.map(ObjectIdentifier.init)
        let sourcePageIdentity = sourcePage?.identifier
        let groups = store.state.splitLayouts.filter { $0.spaceID == spaceID }
        let allIDs = Set(selection + [sourceID])
        let originals = allIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let homes = originals.filter { ($0.kind == .pinned || $0.kind == .favorite) && !(layout?.tabIDs.contains($0.id) ?? false) }
        let savedHomeIDs = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, UUID()) })
        let typed = homes.filter { InternalPage(urlString: $0.savedURL) != nil }
        let documents = typed.isEmpty ? [:] : (resolveSidebarCopyDestinations?(typed)?.documents ?? [:])
        let claims = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, ownership.claimSnapshot($0)) })
        let noteOwners = Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let easelOwners = Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } })
        let embedded = allIDs.flatMap { embeddedEaselPages(forTabID: $0) }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID, profileID: profileID, state: store.state)
        let identities = selection.compactMap { splitPaneIdentity($0) }
        guard hierarchy != nil, originals.count == allIDs.count, identities.count == selection.count, selection.allSatisfy({ panes[$0] != nil }),
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return nil }
        let validate: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isKeyWindow,
                  self.splitCommandsAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID, self.activeSplitLayout == layout,
                  self.pageHost.bounds == frame, window.frame == windowFrame,
                  sourceElsewhere ? self.canMovePageHere(sourceID) : self.switcherCanUse(sourceID),
                  self.peekPages(forTabID: sourceID).isEmpty,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  allIDs.allSatisfy({ id in self.ownership.claimSnapshot(id) == claims[id]
                      && (id == sourceID && sourceElsewhere || self.switcherCanUse(id)) }),
                  originals.allSatisfy({ original in self.store.state.tabs.contains { actual in
                      actual.id == original.id && actual.archivedAt == nil && actual.savedURL == original.savedURL
                          && actual.savedTitle == original.savedTitle && actual.customTitle == original.customTitle
                  } }),
                  Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in self.noteEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == noteOwners,
                  Dictionary(uniqueKeysWithValues: allIDs.compactMap { id in self.easelEditors[id].map { (id, ObjectIdentifier($0.editor)) } }) == easelOwners,
                  Set(allIDs.flatMap { self.embeddedEaselPages(forTabID: $0) }.map(ObjectIdentifier.init)) == Set(embedded.map(ObjectIdentifier.init)),
                  embedded.allSatisfy({ !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === self.nativeBinding }),
                  self.store.state.splitLayouts.filter({ $0.spaceID == spaceID }) == groups,
                  let actual = self.store.state.tabs.first(where: { $0.id == sourceID }),
                  actual.archivedAt == nil, actual.profileID == source.profileID,
                  actual.spaceID == source.spaceID, actual.kind == source.kind, actual.folderID == source.folderID,
                  self.browsers[sourceID].map(ObjectIdentifier.init) == sourceBrowserIdentity,
                  self.panes[sourceID].map(ObjectIdentifier.init) == sourcePaneIdentity,
                  self.browsers[sourceID]?.nativePage?.identifier == sourcePageIdentity,
                  self.browsers[sourceID]?.nativePage?.isClosed != true,
                  selection.enumerated().allSatisfy({ item in
                      guard self.splitPaneIdentity(item.element) == identities[item.offset], let pane = self.panes[item.element] else { return false }
                      return pane.window === window && reservation.isCurrent
                  }) else { return false }
            return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
        }
        let drag = SidebarSplitDrag(tabID: sourceID, window: window, validate: validate,
            commit: { [weak self] target, orientation in
                guard validate(), let self else { return false }
                guard let required = OriginalSplitDrop.savedHomes(source: sourceID, state: self.presentedState,
                    selection: selection, layout: layout, target: target, orientation: orientation, spaceID: spaceID) else { return false }
                let requiredIDs = Set(required.map(\.id))
                var committed = false
                self.performWindowCommand {
                    committed = self.store.dropTabIntoSplit(sourceID, expectedSelection: selection,
                        expectedLayout: layout, target: target, orientation: orientation,
                        savedHomeIDs: savedHomeIDs, creation: creation,
                        documents: documents.filter { requiredIDs.contains($0.key) })
                }
                if committed {
                    if sourceElsewhere { _ = self.selectTab(sourceID) }
                    self.focusedTabID = sourceID; self.updateNavigation(); self.requestNativeSelection()
                    for original in required {
                        if let homeID = savedHomeIDs[original.id], let home = self.store.state.tabs.first(where: { $0.id == homeID }) {
                            self.openDuplicatedChildren([homeID], spaceID: home.spaceID, profileID: profileID,
                                window: window, originatingSpaceID: spaceID)
                        }
                    }
                } else if self.store.persistenceError != nil { self.showToast(.standard("Couldn’t move tab"), at: .window) }
                return committed
            }, finish: { [weak self] in
                reservation.end(animated: true); self?.splitDropView?.targets.reset()
                self?.splitDropView?.removeFromSuperview(); self?.splitDropView = nil
            })
        let overlay = SplitDropView(frame: frame, drag: drag,
            reservation: reservation, insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear })
        overlay.canPropose = { [weak self] target, orientation in
            guard let self, validate(), let required = OriginalSplitDrop.savedHomes(source: sourceID, state: self.presentedState,
                selection: selection, layout: layout, target: target, orientation: orientation, spaceID: spaceID) else { return false }
            let requiredIDs = Set(required.map(\.id))
            return SidebarDocumentReference.validates(required, references: documents.filter { requiredIDs.contains($0.key) })
                && OriginalSplitDrop.proposal(source: sourceID, state: self.presentedState, selection: selection,
                    layout: layout, target: target, orientation: orientation, spaceID: spaceID, profileID: profileID,
                    now: Date(), savedHomeIDs: savedHomeIDs, creation: creation) != nil
        }
        overlay.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        pageHost.addSubview(overlay, positioned: .above, relativeTo: splitView); splitDropView = overlay
        return drag
    }

    private func beginSidebarSplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard let drag = beginSplitDrag(sourceID) ?? beginForeignOnlySplitDrag(sourceID) else { return nil }
        onSplitDragBegan?(drag, self)
        return drag
    }

    private func beginForeignOnlySplitDrag(_ sourceID: UUID) -> SidebarSplitDrag? {
        guard let window, window.isKeyWindow, !isPopupWindow, !isPrivateBrowsing, !store.isEphemeral,
              let source = store.state.tabs.first(where: { $0.id == sourceID }),
              source.profileID == activeProfileID, source.spaceID == activeSpaceID,
              source.kind == .pinned || source.kind == .today, InterProfileMove.admits(source),
              switcherCanUse(sourceID), peekPages(forTabID: sourceID).isEmpty else { return nil }
        return SidebarSplitDrag(tabID: sourceID, window: window, validate: { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isKeyWindow,
                  let actual = self.store.state.tabs.first(where: { $0.id == sourceID }),
                  InterProfileMove.samePlacement(actual, source),
                  self.switcherCanUse(sourceID), self.peekPages(forTabID: sourceID).isEmpty else { return false }
            return true
        }, commit: { _, _ in false }, finish: {})
    }

    private var interProfileDropAvailable: Bool {
        guard !isPopupWindow, !isPrivateBrowsing, !store.isEphemeral, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              nativeFullscreenTabID == nil, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              collectionTransfer == nil, closingTabIDs.isEmpty, modelRetirementIDs.isEmpty,
              peekRetirementParents.isEmpty, tabSwitcher == nil, themePopover == nil, activePeek == nil,
              libraryView == nil, commandBar == nil, splitInsertion == nil,
              splitDropView == nil, spaceCreation == nil, !store.isProfileRemovalPending(activeProfileID),
              !selectedTabIDs.isEmpty, selectedTabIDs.count == 1 || activeSplitLayout != nil,
              let window, window.isVisible, !window.isMiniaturized, window.attachedSheet == nil,
              let binding = nativeBinding, binding.window === window else { return false }
        return binding.canParticipateInPageTransfer
    }

    func beginForeignSplitDrop(_ drag: SidebarSplitDrag, from source: BrowserWindowController) {
        guard source !== self, source.store === store, source.ownership === ownership,
              foreignSplitDropView == nil, interProfileDropAvailable, drag.isValid,
              let dragWindow = drag.window, dragWindow === source.window, let window,
              let original = store.state.tabs.first(where: { $0.id == drag.tabID }),
              original.kind == .pinned || original.kind == .today, InterProfileMove.admits(original),
              original.profileID == activeProfileID
                || InterProfileMove.profilesAvailable(original.profileID, activeProfileID, in: store.state) else { return }
        let selection = selectedTabIDs, layout = activeSplitLayout
        let spaceID = activeSpaceID, profileID = activeProfileID, focusID = currentTabID
        let frame = pageHost.bounds, windowFrame = window.frame
        let hierarchy = SidebarHierarchySnapshot(state: store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true)
        let identities = selection.compactMap { splitPaneIdentity($0) }
        let members = selection.compactMap { id in store.state.tabs.first { $0.id == id } }
        let homes = members.filter { ($0.kind == .pinned || $0.kind == .favorite) && !(layout?.tabIDs.contains($0.id) ?? false) }
        let homeIDs = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, UUID()) })
        let typed = (homes + (original.kind == .pinned ? [original] : [])).filter { InternalPage(urlString: $0.savedURL) != nil }
        let documents = typed.isEmpty ? [:] : (resolveSidebarCopyDestinations?(typed)?.documents ?? [:])
        let sourceHomeID = UUID()
        guard hierarchy != nil, identities.count == selection.count, selection.allSatisfy({ panes[$0] != nil }),
              members.count == selection.count,
              let reservation = splitView.prepareDropReservation(in: pageHost,
                  contents: selection.compactMap { panes[$0]?.content }) else { return }
        let current: () -> Bool = { [weak self, weak window] in
            guard let self, let window, self.window === window, self.interProfileDropAvailable,
                  self.activeSpaceID == spaceID, self.activeProfileID == profileID,
                  self.selectedTabIDs == selection, self.currentTabID == focusID, self.activeSplitLayout == layout,
                  SidebarHierarchySnapshot(state: self.store.state, spaceID: spaceID, profileID: profileID, includesFavorites: true) == hierarchy,
                  selection.enumerated().allSatisfy({ self.splitPaneIdentity($0.element) == identities[$0.offset] }),
                  let actual = self.store.state.tabs.first(where: { $0.id == original.id }),
                  InterProfileMove.samePlacement(actual, original), !self.store.retiringTabIDs.contains(original.id) else { return false }
            return true
        }
        let gesture: () -> Bool = { [weak self, weak window] in
            guard let self, let window, current(), drag.isValid, self.pageHost.bounds == frame,
                  window.frame == windowFrame, reservation.isCurrent else { return false }
            return true
        }
        let creation = TabCreationProvenance(referrerID: nil, activeTabID: focusID, profileID: profileID, state: store.state)
        let request: (SplitDropTarget, SplitOrientation) -> ForeignSplitDrop.Request = { target, orientation in
            .init(source: original, sourceHomeID: sourceHomeID, spaceID: spaceID, profileID: profileID, selection: selection,
                  layout: layout, target: target, orientation: orientation, destinationHomeIDs: homeIDs)
        }
        let proposal: (ForeignSplitDrop.Request, BrowserState) -> BrowserState? = { value, state in
            guard let required = ForeignSplitDrop.destinationHomes(value, state: state) else { return nil }
            let checked = original.profileID == profileID ? required : required.filter { $0.id != original.id }
            let ids = Set(checked.map(\.id))
            guard SidebarDocumentReference.validates(checked, references: documents.filter { ids.contains($0.key) }) else { return nil }
            return ForeignSplitDrop.proposal(value, state: state, now: Date(), creation: creation)
        }
        let overlay = SplitDropView(frame: frame, drag: drag,
            reservation: reservation, perform: { [weak self, weak source] target, orientation in
                guard let self, gesture() else { return false }
                let value = request(target, orientation)
                guard proposal(value, self.store.state) != nil else { return false }
                if original.profileID == profileID, let source {
                    return self.moveForeignSplitDropHere(original.id, from: source, sourceSpaceID: original.spaceID,
                        proposal: { proposal(value, $0) }, sourceHomeID: sourceHomeID, homeIDs: Array(homeIDs.values))
                }
                return self.confirmInterProfileMove(tabCount: 1, sourceProfiles: [original.profileID], destinationSpaceID: spaceID) { [weak self, weak source] in
                    guard let self, current() else { return }
                    let moved: Set<UUID> = [original.id]
                    self.store.moveAcrossProfiles(moved, proposal: { proposal(value, $0) }) { [weak self, weak source] result in
                        guard let self else { return }
                        switch result {
                        case .success(true):
                            self.onInterProfileMoveCommitted?(moved)
                            self.finishInterProfileArrival(original.id)
                            source?.openSavedHomeInBackground(sourceHomeID)
                            if let window = self.window {
                                for homeID in homeIDs.values where self.store.state.tabs.contains(where: { $0.id == homeID }) {
                                    self.openDuplicatedChildren([homeID], spaceID: spaceID, profileID: profileID,
                                        window: window, originatingSpaceID: spaceID)
                                }
                            }
                        case .success(false): NSSound.beep()
                        case .failure: self.showToast(.standard("Couldn’t move tab"), at: .window)
                        }
                    }
                }
            }, insertionColor: { [weak self] in self.map { ThemeChromePalette.appearanceBasedMaxContrast(theme: $0.rootView.paletteTheme) } ?? .clear })
        overlay.canPropose = { [weak self] target, orientation in
            guard let self, gesture() else { return false }
            return proposal(request(target, orientation), self.store.state) != nil
        }
        overlay.targets.onChange = { [weak self] target in self?.setSplitDropProposal(target, selection: selection) }
        pageHost.addSubview(overlay, positioned: .above, relativeTo: splitView); foreignSplitDropView = overlay
        drag.onEnd { [weak self, weak overlay] in
            reservation.end(animated: true)
            guard let self, let overlay, self.foreignSplitDropView === overlay else { return }
            overlay.targets.reset(); overlay.removeFromSuperview(); self.foreignSplitDropView = nil
        }
    }

    private func moveForeignSplitDropHere(_ id: UUID, from source: BrowserWindowController, sourceSpaceID: UUID,
                                          proposal: @escaping (BrowserState) -> BrowserState?,
                                          sourceHomeID: UUID, homeIDs: [UUID]) -> Bool {
        guard source.activeSpaceID == sourceSpaceID, source.sidebarWindowMoveAvailable, sidebarWindowMoveAvailable,
              let window else { return false }
        let spaceID = activeSpaceID, profileID = activeProfileID
        var plan = SidebarWindowTransfer.Plan(tabIDs: [id], sourceSpaceID: sourceSpaceID, profileID: profileID,
            destinationSpaceID: spaceID, isCurrent: { proposal($0) != nil },
            commit: { try $0.commitForeignSplitDrop([id], proposal: proposal) })
        plan.arrival = id
        guard let transaction = SidebarWindowTransfer(source: source, destination: self, plan: plan) else { return false }
        transaction.onFinish = { [weak self, weak source, weak window] committed in
            guard committed, let self, let window else { return }
            source?.openSavedHomeInBackground(sourceHomeID)
            for homeID in homeIDs where self.store.state.tabs.contains(where: { $0.id == homeID }) {
                self.openDuplicatedChildren([homeID], spaceID: spaceID, profileID: profileID, window: window, originatingSpaceID: spaceID)
            }
        }
        return transaction.begin()
    }

    private func confirmInterProfileMove(tabCount: Int, sourceProfiles: Set<UUID>, destinationSpaceID: UUID,
                                         proceed: @escaping () -> Void) -> Bool {
        guard let destination = store.state.spaces.first(where: { $0.id == destinationSpaceID }),
              let gate = InterProfileMoveGate.resolve(sourceProfiles: sourceProfiles, destination: destination.profileID,
                  decision: nil, bypass: store.bypassesInterProfileMoveConfirmation) else { return false }
        switch gate {
        case .abort: return false
        case .proceed: proceed(); return true
        case .confirm:
            guard let window, window.attachedSheet == nil, interProfileDialog == nil,
                  let prompt = InterProfileMovePrompt(tabCount: tabCount, destinationSpaceID: destinationSpaceID, state: store.state) else { return false }
            let dialog = InterProfileMoveDialog(prompt: prompt)
            interProfileDialog = dialog
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            let began = dialog.begin(for: window) { [weak self] decision in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.interProfileDialog = nil
                    guard case .proceed(let remember)? = InterProfileMoveGate.resolve(sourceProfiles: sourceProfiles,
                        destination: destination.profileID, decision: decision, bypass: self.store.bypassesInterProfileMoveConfirmation) else { return }
                    if remember { self.store.rememberInterProfileMoveChoice() }
                    proceed()
                }
            }
            if !began { interProfileDialog = nil }
            return began
        }
    }

    private func finishInterProfileArrival(_ id: UUID) {
        if presentation.selectExistingTab(id, state: store.state, available: { ownership.canUse($0, owner: presentationID) }) {
            presentation.recordFocusedTab(id); focusedTabID = id
        }
        render(store.state); updateNavigation(); requestNativeSelection()
    }

    func easelEditorsForRelocation(in ids: Set<UUID>) -> [UUID: EaselEditorViewController] {
        Dictionary(uniqueKeysWithValues: easelEditors.filter { ids.contains($0.key) }.map { ($0.key, $0.value.editor) })
    }

    func closeLocalDocumentEditors(_ ids: Set<UUID>) -> Bool {
        guard ids.allSatisfy({ noteEditors[$0]?.editor.prepareToClose() ?? true }),
              ids.allSatisfy({ embeddedEaselPages(forTabID: $0).isEmpty && !hasPendingNativePage(in: [$0]) }),
              easelEditorsForRelocation(in: ids).values.allSatisfy({ $0.canPrepareForProfileRelocation }),
              easelEditorsForRelocation(in: ids).values.allSatisfy({ $0.prepareForProfileRelocation() }) else { return false }
        for id in ids {
            if let note = noteEditors.removeValue(forKey: id) { note.editor.view.removeFromSuperview() }
            if let easel = easelEditors.removeValue(forKey: id) {
                easel.editor.retirePageOwner(); panes[id]?.clearNativeContent(); easelFailures.removeValue(forKey: id)
            }
        }
        return true
    }

    func openSavedHomeInBackground(_ id: UUID) {
        guard let window, let home = store.state.tabs.first(where: { $0.id == id }) else { return }
        openDuplicatedChildren([id], spaceID: home.spaceID, profileID: home.profileID, window: window)
    }

    func releaseInterProfileClaims(_ ids: Set<UUID>) {
        let released = ids.filter { id in
            browsers[id] == nil && noteEditors[id] == nil && easelEditors[id] == nil
                && !transferringTabIDs.contains(id) && ownership.claimSnapshot(id).owner == presentationID
        }
        for id in released { ownership.release(id, owner: presentationID); presentation.remove(id) }
        render(store.state)
        for id in released where !renderedPaneIDs.contains(id) {
            panes.removeValue(forKey: id)?.removeFromSuperview(); failures.removeValue(forKey: id)
        }
    }

    private func showSplitPaneMenu(_ paneID: UUID, from anchor: NSView) {
        guard splitCommandsAvailable, splitInsertion == nil,
              let index = selectedTabIDs.firstIndex(of: paneID),
              let pane = panes[paneID], anchor.window === window,
              anchor.isDescendant(of: pane) else { return }
        let orientation = activeSplitLayout?.orientation ?? .horizontal
        let menu = SplitPaneMenu.make(orientation: orientation, index: index, count: selectedTabIDs.count) { [weak self] operation in
            guard let self else { return nil }
            let command: SplitCommand
            switch operation {
            case .movePrevious: command = .move(-1)
            case .moveNext: command = .move(1)
            case .addBefore, .addAfter, .addAbove, .addBelow: command = .add(operation)
            case .separate: command = .separate
            case .copyLink: command = .copyLink
            case .flip: command = .orientation(orientation == .horizontal ? .vertical : .horizontal)
            case .share:
                let urls = self.splitShareURLs()
                guard !urls.isEmpty else { return nil }
                return { self.shareSplitView(from: anchor, urls: urls) }
            }
            guard let target = self.splitCommandTarget(command, paneID: paneID) else { return nil }
            return { target.perform() }
        }
        menu.appearance = anchor.effectiveAppearance
        pane.trackSplitMenu {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
        }
    }

    private func fillSplitInsertionWithNewDocument(_ session: SplitPaneInsertionSession,
                                                   create: () throws -> (InternalPage, String),
                                                   reportError: (Error) -> Void) {
        guard splitInsertion === session, session.isValid, commandBar == nil, canCreateNoteInSplit else {
            cancelSplitInsertion(restoreFocus: true); return
        }
        let request = session.request
        let document: (InternalPage, String)
        do { document = try create() } catch {
            cancelSplitInsertion(restoreFocus: true); reportError(error); return
        }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        guard let prepared = request.preparedState(presentedState, tabID: id,
            navigationURL: nil, localPage: document.0, localTitle: document.1,
            now: Date(), creation: creation),
            let homes = OriginalSplitDrop.savedHomes(source: id, state: prepared,
                selection: request.selection, layout: request.layout, target: .insert(request.index),
                orientation: request.orientation, spaceID: request.spaceID),
            let plan = splitHomePlan(homes) else {
            cancelSplitInsertion(restoreFocus: true); return
        }
        splitInsertion = nil; session.cancel()
        var committed = false
        performWindowCommand(selectNativePage: false) {
            committed = store.insertSplitPane(request, tabID: id, navigationURL: nil,
                creation: creation, savedHomeIDs: plan.ids, documents: plan.documents,
                localPage: document.0, localTitle: document.1)
        }
        guard committed else {
            render(store.state); requestNativeSelection()
            showToast(.standard("Couldn’t add split pane"), at: .window); return
        }
        focusedTabID = id; render(store.state)
        requestNativeSelection(); focusSelectedLocalContent()
        openSplitHomes(plan.ids, profileID: request.profileID, originatingSpaceID: request.spaceID)
    }

    private func cancelSplitInsertion(restoreFocus: Bool) {
        guard let session = splitInsertion else { return }
        splitInsertion = nil; session.cancel()
        let panel = commandBar; commandBar = nil; panel?.dismiss(restoreFocus: false)
        render(store.state)
        guard restoreFocus else { return }
        requestNativeSelection()
        if let find = visibleFind, isCurrentFind(find), !findHost.isHidden, window?.isKeyWindow == true {
            if let editor = findField.currentEditor(), window?.firstResponder === editor { return }
            if window?.makeFirstResponder(findField) == true { return }
        }
        focusSelectedContent()
    }

    private func beginSplitInsertion(_ operation: SplitPaneOperation, paneID: UUID) {
        guard splitInsertion == nil, commandBar == nil,
              splitCommandsAvailable, let window, window.isKeyWindow,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              let request = SplitPaneInsertion(paneID: paneID, operation: operation, state: presentedState),
              let index = selectedTabIDs.firstIndex(of: paneID),
              let owner = splitCommandTarget(.focus(index + 1), paneID: paneID) else { return }
        let focus = currentTabID, binding = nativeBinding
        let candidates = splitInsertionTabs(profileID: request.profileID).filter { !selectedTabIDs.contains($0.id)
            && (switcherCanUse($0.id) && ownership.canUse($0.id, owner: presentationID) || canMovePageHere($0.id)) }
        let elsewhere = Set(candidates.filter { canMovePageHere($0.id) }.map(\.id))
        var movedIn = Set<UUID>()
        let all = Set(request.selection + candidates.map(\.id))
        let originalCandidates = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let embedded = Dictionary(uniqueKeysWithValues: all.map { ($0, embeddedEaselPages(forTabID: $0)) })
        let claims = Dictionary(uniqueKeysWithValues: all.map { ($0, ownership.claimSnapshot($0)) })
        let wrappers = Dictionary(uniqueKeysWithValues: all.compactMap { id in browsers[id].map { (id, $0) } })
        let pages = Dictionary(uniqueKeysWithValues: all.compactMap { id in browsers[id]?.nativePage.map { (id, $0) } })
        let notes = Dictionary(uniqueKeysWithValues: all.compactMap { id in noteEditors[id].map { (id, $0.editor) } })
        let easels = Dictionary(uniqueKeysWithValues: all.compactMap { id in easelEditors[id].map { (id, $0.editor) } })
        let validItem: (UUID) -> Bool = { [weak self, weak window, weak binding] id in
            guard let self, let window, self.window === window, self.nativeBinding === binding else { return false }
            if elsewhere.contains(id) {
                guard movedIn.contains(id) else { return self.canMovePageHere(id) }
                guard self.switcherCanUse(id), self.peekPages(forTabID: id).isEmpty else { return false }
                return self.browsers[id]?.nativePage.map { !$0.isClosed && PCNativeBrowserApplication.owner(of: $0) === binding } ?? true
            }
            guard self.switcherCanUse(id), self.peekPages(forTabID: id).isEmpty,
                  self.ownership.claimSnapshot(id) == claims[id],
                  self.browsers[id] === wrappers[id], self.browsers[id]?.nativePage === pages[id],
                  self.noteEditors[id]?.editor === notes[id], self.easelEditors[id]?.editor === easels[id],
                  Set(self.embeddedEaselPages(forTabID: id).map(ObjectIdentifier.init)) == Set((embedded[id] ?? []).map(ObjectIdentifier.init)),
                  (embedded[id] ?? []).allSatisfy({ !$0.isClosed && $0.embeddedOwnerValid && PCNativeBrowserApplication.owner(of: $0) === binding }) else { return false }
            if let page = pages[id] {
                return !page.isClosed && PCNativeBrowserApplication.owner(of: page) === binding
                    && wrappers[id]?.window === window
            }
            return true
        }
        let session = SplitPaneInsertionSession(request: request, candidateIDs: Set(candidates.map(\.id))) { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isVisible,
                  window.attachedSheet == nil || self.commandBar?.ownsAttachedSheet == true,
                  owner.isAvailable, self.currentTabID == focus,
                  self.activePeek == nil,
                  self.nativeFullscreenTabID == nil, self.libraryView == nil,
                  request.isCurrent(in: self.presentedState), request.selection.allSatisfy(validItem) else { return false }
            return true
        }
        guard session.isValid else { return }
        splitInsertion = session
        render(store.state)
        let splitHistoryExcludedURL = currentBrowser?.url?.absoluteString
            ?? store.state.tabs.first(where: { $0.id == currentTabID })?.url
        let panel = CommandBar(parent: window, tabs: candidates, history: commandBarHistory(profileID: request.profileID),
            historyRevision: store.historyRevision, historyExcludedURL: splitHistoryExcludedURL,
            currentURL: nil, profilePath: store.independentEngineProfilePath(for: request.profileID),
            page: selectedNativePage(), nativeWindow: nativeBinding, extensionDisposition: nil, theme: windowPaletteTheme,
            contentAppearance: rootView.palette.contentAppearance)
        panel.tabCaption = { [weak self] tab in self?.commandBarTabCaption(tab)
            ?? .switchToTab }
        panel.isOwnerValid = session.validate
        panel.onWillSubmitDestination = { [weak session] in session?.submitting = true }
        panel.onRejectedDestination = { [weak self, weak session] in
            guard let self, let session, self.splitInsertion === session else { return }
            self.cancelSplitInsertion(restoreFocus: false)
        }
        panel.onDismiss = { [weak self, weak session, weak panel] in
            guard let self, let session, self.commandBar === panel else { return }
            self.commandBar = nil
            if !session.submitting { self.cancelSplitInsertion(restoreFocus: true) }
        }
        panel.restorePageFocus = { [weak self] in self?.requestNativeSelection(); self?.focusSelectedLocalContent() }
        @MainActor final class Submission { var run: (PCNativeSearchNavigation?, UUID?) -> Void = { _, _ in } }
        let submission = Submission()
        submission.run = { [weak self, weak session, weak window, weak submission] navigation, existing in
            guard let self, let session, let submission, self.splitInsertion === session else { return }
            guard let window, self.window === window, session.isValid, self.commandBar == nil,
                  window.isKeyWindow, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else {
                self.cancelSplitInsertion(restoreFocus: false); return
            }
            if let navigation {
                guard navigation.profilePath == self.store.independentEngineProfilePath(for: request.profileID) else {
                    self.cancelSplitInsertion(restoreFocus: true); return
                }
            } else if let existing {
                guard let expected = originalCandidates[existing], validItem(existing),
                      self.store.state.tabs.first(where: { $0.id == existing }) == expected,
                      self.splitInsertionTabs(profileID: request.profileID).contains(where: { $0.id == existing }) else {
                    self.cancelSplitInsertion(restoreFocus: true); return
                }
                if elsewhere.contains(existing), !movedIn.contains(existing) {
                    let started = self.movePagesHere([existing]) {
                        movedIn.insert(existing); submission.run(nil, existing); return true
                    }
                    if !started { self.cancelSplitInsertion(restoreFocus: true) }
                    return
                }
            } else { self.cancelSplitInsertion(restoreFocus: true); return }
            let id = existing ?? UUID()
            let creation = self.creationProvenance(activeTabID: focus)
            guard let prepared = request.preparedState(self.presentedState, tabID: id,
                navigationURL: navigation?.url, now: Date(), creation: creation),
                let homes = OriginalSplitDrop.savedHomes(source: id, state: prepared,
                    selection: request.selection, layout: request.layout, target: .insert(request.index),
                    orientation: request.orientation, spaceID: request.spaceID) else {
                self.cancelSplitInsertion(restoreFocus: true); return
            }
            guard let plan = self.splitHomePlan(homes) else {
                self.cancelSplitInsertion(restoreFocus: true); return
            }
            let homeIDs = plan.ids, documents = plan.documents
            if let navigation { self.pendingSearchNavigations[id] = navigation }
            self.splitInsertion = nil; session.cancel()
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = self.store.insertSplitPane(request, tabID: id, navigationURL: navigation?.url,
                    creation: creation, savedHomeIDs: homeIDs, documents: documents)
                if committed && navigation != nil { self.presentation.recordCreation(id, state: self.store.state) }
            }
            guard committed else {
                self.pendingSearchNavigations.removeValue(forKey: id)
                self.render(self.store.state); self.requestNativeSelection()
                self.showToast(.standard("Couldn’t add split pane"), at: .window); return
            }
            self.focusedTabID = id; self.render(self.store.state)
            self.requestNativeSelection(); self.focusSelectedLocalContent()
            self.openSplitHomes(homeIDs, profileID: request.profileID, originatingSpaceID: request.spaceID)
        }
        panel.onSearchNavigation = { submission.run($0, nil) }
        panel.onSelectTab = { submission.run(nil, $0) }
        panel.onSplitNavigation = { submission.run($0, nil) }
        panel.onSplitTab = { submission.run(nil, $0) }
        panel.canSplitSelection = { [weak session] existing in
            guard let session, session.isValid else { return false }
            if let existing {
                return originalCandidates[existing] != nil && validItem(existing)
            }
            return true
        }
        let localDocumentCommands: Set<String> = ["createNote:", "createNoteInSplit:", "createEasel:"]
        panel.canSplitCommand = { localDocumentCommands.contains($0.id) }
        panel.onSplitCommand = { [weak self, weak session] command in
            guard let self, let session, self.splitInsertion === session, session.isValid else {
                self?.cancelSplitInsertion(restoreFocus: true); return
            }
            switch command.id {
            case "createNote:", "createNoteInSplit:":
                self.fillSplitInsertionWithNewDocument(session, create: {
                    let notes = try NoteStore.sharedStore(directory: self.store.notesDirectory(for: self.activeProfileID))
                    let created = try notes.create()
                    return (.note(created.document.id), created.displayTitle)
                }, reportError: { self.showNoteError($0) })
            case "createEasel:":
                self.fillSplitInsertionWithNewDocument(session, create: {
                    let easels = try EaselEditorViewController.sharedStore(directory: self.store.easelsDirectory(for: self.activeProfileID))
                    let created = try easels.create()
                    return (.easel(created.document.id), created.document.title)
                }, reportError: { self.showEaselError($0) })
            default:
                self.cancelSplitInsertion(restoreFocus: true)
            }
        }
        let navigate: (String) -> Void = { [weak self, weak session] input in
            guard let self, let session, self.splitInsertion === session else { return }
            guard session.isValid else { self.cancelSplitInsertion(restoreFocus: false); return }
            PCNativeBrowserApplication.resolveSearchInput(input,
                profilePath: self.store.independentEngineProfilePath(for: request.profileID),
                page: self.selectedNativePage(), window: self.nativeBinding) { [weak self, weak session] navigation, error in
                    MainActor.assumeIsolated {
                        guard let self, let session, self.splitInsertion === session else { return }
                        guard session.isValid else { self.cancelSplitInsertion(restoreFocus: false); return }
                        if let navigation { submission.run(navigation, nil) }
                        else { self.cancelSplitInsertion(restoreFocus: true); self.showSearchError(error?.localizedDescription ?? "Search is unavailable for this Space.") }
                    }
                }
        }
        panel.onNavigate = navigate
        panel.onSplitInput = navigate
        commandBarCreatesNewTab = true; commandBarShowsNewTabPlaceholder = true
        commandBar = panel; panel.present()
    }

    fileprivate struct SplitPaneIdentity: Equatable {
        let pane: ObjectIdentifier
        let browser: ObjectIdentifier?
        let page: String?
    }

    @MainActor final class SplitCommandTarget {
        private weak var owner: BrowserWindowController?
        private weak var window: NSWindow?
        private let command: SplitCommand
        private let spaceID: UUID
        private let profileID: UUID
        private let tabIDs: [UUID]
        private let originalFocus: UUID
        private let targetID: UUID
        private let identities: [UUID: SplitPaneIdentity]
        private let layout: BrowserSplitLayout?
        private var consumed = false

        fileprivate init(owner: BrowserWindowController, command: SplitCommand,
                         originalFocus: UUID, targetID: UUID, identities: [UUID: SplitPaneIdentity]) {
            self.owner = owner; window = owner.window; self.command = command
            spaceID = owner.activeSpaceID; profileID = owner.activeProfileID
            tabIDs = owner.selectedTabIDs; self.originalFocus = originalFocus
            self.targetID = targetID; self.identities = identities
            layout = owner.activeSplitLayout
        }

        var isAvailable: Bool {
            guard !consumed, let owner, let window, owner.window === window,
                  owner.splitCommandIsAvailable(command), owner.activeSpaceID == spaceID,
                  owner.activeProfileID == profileID, owner.selectedTabIDs == tabIDs,
                  owner.currentTabID == originalFocus, owner.activeSplitLayout == layout else { return false }
            return tabIDs.allSatisfy { owner.splitPaneIdentity($0) == identities[$0] }
        }

        func perform() {
            guard isAvailable, let owner else { return }
            owner.commandBar?.dismiss(restoreFocus: false)
            guard isAvailable, let window,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            owner.navigationHistory?.dismiss()
            owner.sidebarPreviews?.dismiss()
            guard isAvailable, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            consumed = true
            owner.executeSplitCommand(command, targetID: targetID)
        }
    }

    private func prepareSplitResize() -> (([Double]) -> Bool)? {
        guard splitInsertion == nil, renderedPaneIDs == selectedTabIDs,
              let window, window.isKeyWindow, let layout = activeSplitLayout,
              let target = splitCommandTarget(.orientation(layout.orientation)), target.isAvailable,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return nil }
        let originalBounds = pageHost.bounds
        var used = false
        return { [weak self, weak window] factors in
            guard !used else { return false }; used = true
            guard let self, let window, self.window === window, window.isKeyWindow,
                  target.isAvailable,
                  self.renderedPaneIDs == layout.tabIDs, self.activeSplitLayout == layout,
                  self.pageHost.bounds == originalBounds,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            var committed = false
            self.performWindowCommand(selectNativePage: false) {
                committed = self.store.resizeSplit(expected: layout, widthFactors: factors)
            }
            return committed
        }
    }

    private var splitCommandsAvailable: Bool {
        spaceCommandsAvailable && activePeek == nil && libraryView == nil
            && !selectedTabIDs.isEmpty
            && (selectedTabIDs.count == 1 || activeSplitLayout != nil)
    }

    private func splitCommandIsAvailable(_ command: SplitCommand) -> Bool {
        guard splitCommandsAvailable else { return false }
        switch command {
        case .focus(let number): return (1...selectedTabIDs.count).contains(number)
        case .next, .previous: return true
        case .add, .addNew: return selectedTabIDs.count < 4 && splitInsertion == nil
        default: return selectedTabIDs.count > 1
        }
    }

    private func splitPaneIdentity(_ id: UUID) -> SplitPaneIdentity? {
        guard selectedTabIDs.contains(id), switcherCanUse(id),
              let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
              tab.profileID == activeProfileID, tab.kind == .favorite || tab.spaceID == activeSpaceID,
              let pane = panes[id], pane.window === window else { return nil }
        if let browser = browsers[id] {
            guard let page = browser.nativePage, !page.isClosed, let binding = nativeBinding,
                  existingNativeSelection(binding, page)?.1 === browser else { return nil }
            return SplitPaneIdentity(pane: ObjectIdentifier(pane), browser: ObjectIdentifier(browser), page: page.identifier)
        }
        guard presentation.isLocalSelection(id, state: store.state, hasNativeWrapper: false) else { return nil }
        return SplitPaneIdentity(pane: ObjectIdentifier(pane), browser: nil, page: nil)
    }

    func splitCommandTarget(_ command: SplitCommand, paneID: UUID? = nil) -> SplitCommandTarget? {
        guard splitCommandIsAvailable(command), let focus = currentTabID,
              let index = selectedTabIDs.firstIndex(of: focus) else { return nil }
        let target: UUID
        switch command {
        case .focus(let number):
            guard (1...selectedTabIDs.count).contains(number) else { return nil }
            target = selectedTabIDs[number - 1]
        case .next: target = selectedTabIDs[(index + 1) % selectedTabIDs.count]
        case .previous: target = selectedTabIDs[(index + selectedTabIDs.count - 1) % selectedTabIDs.count]
        default: target = paneID ?? focus
        }
        guard selectedTabIDs.contains(target) else { return nil }
        if case .move(let delta) = command {
            guard let position = selectedTabIDs.firstIndex(of: target), selectedTabIDs.indices.contains(position + delta) else { return nil }
        }
        if case .copyLink = command {
            if let page = browsers[target]?.nativePage, !page.canCopyLink(as: .plain) { return nil }
            if WhatsNewPage.matches(browsers[target]?.url?.absoluteString ?? visibleTabs.first { $0.id == target }?.url ?? "") { return nil }
        }
        var identities: [UUID: SplitPaneIdentity] = [:]
        for id in selectedTabIDs {
            guard let identity = splitPaneIdentity(id) else { return nil }
            identities[id] = identity
        }
        return SplitCommandTarget(owner: self, command: command, originalFocus: focus, targetID: target, identities: identities)
    }

    func prepareSplitMenuItem(_ item: NSMenuItem, command: SplitCommand, preservingTarget: Bool) -> Bool {
        if !preservingTarget { item.representedObject = splitCommandTarget(command) }
        return (item.representedObject as? SplitCommandTarget)?.isAvailable == true
    }

    private func splitMenuItem(_ title: String, command: SplitCommand) -> NSMenuItem {
        let target = splitCommandTarget(command)
        let item = MenuAction.item(title) { target?.perform() }
        item.isEnabled = target != nil
        return item
    }

    private func focusSelectedContent() {
        contentFocusRequest?.cancel(); contentFocusRequest = nil
        guard let window, window.isKeyWindow, presentation.isReady else { return }
        let tabID = currentTabID, peek = activePeek.flatMap { $0.view.isHidden ? nil : $0 }
        let browser = currentBrowser, hadPeek = peek != nil, hadBrowser = browser != nil
        let request = ContentFocusRequest(window: window, content: pageHost) { [weak self, weak window, weak peek, weak browser] in
            guard let self, let window, self.currentTabID == tabID, self.commandBar == nil, self.libraryView == nil,
                  self.spaceCreation == nil, self.pageCapture == nil, self.tabSwitcher == nil,
                  !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activePeek === peek, (peek != nil) == hadPeek,
                  !hadBrowser || (browser != nil && self.currentBrowser === browser) else { return .cancelled }
            if let peek {
                guard !peek.view.isHidden else { return .cancelled }
                peek.focus()
                return (window.firstResponder as? NSView)?.isDescendant(of: peek.view) == true ? .focused : .waiting
            }
            guard let id = tabID else { return .cancelled }
            let paneHoldsFocus = { @MainActor () -> Bool in
                guard let pane = self.panes[id] else { return false }
                return (window.firstResponder as? NSView)?.isDescendant(of: pane) == true
            }
            if let browser = self.currentBrowser {
                guard let page = browser.nativePage, self.renderedPaneIDs.contains(id) else { return .waiting }
                guard !page.isClosed else { return .cancelled }
                if let crash = self.rendererPresentation(browser) {
                    self.focusRendererFailure(id, crash); return paneHoldsFocus() ? .focused : .waiting
                }
                return self.nativeBinding?.requestFocus(for: page) == true ? .focused : .waiting
            }
            guard self.presentation.isLocalSelection(id, state: self.store.state, hasNativeWrapper: false) else { return .waiting }
            if self.panes[id]?.showsBlank == true { window.makeFirstResponder(nil); return .focused }
            self.focusSelectedLocalContent()
            return paneHoldsFocus() ? .focused : .waiting
        }
        contentFocusRequest = request
        request.start()
    }

    private func reclaimFocusAfterSplitPresentation() {
        guard let window, ContentFocusRequest.lostByPresentation(window.firstResponder, window: window) else { return }
        focusSelectedContent()
    }

    func focusSelectedLocalContent() {
        guard let id = currentTabID, renderedPaneIDs.contains(id),
              activePeek == nil, commandBar == nil, let window, window.isKeyWindow,
              window.attachedSheet == nil,
              presentation.isLocalSelection(id, state: store.state, hasNativeWrapper: browsers[id] != nil) else { return }
        if let editor = noteEditors[id]?.editor { editor.focusContent() }
        else if let editor = easelEditors[id]?.editor { editor.focusContent() }
        else if panes[id]?.showsBlank == true { window.makeFirstResponder(nil) }
    }

    private func executeSplitCommand(_ command: SplitCommand, targetID: UUID) {
        switch command {
        case .focus, .next, .previous:
            pendingNativeSelection = nil
            focusedTabID = targetID
            render(store.state)
            requestNativeSelection()
            focusSelectedContent()
        case .move(let offset):
            guard let layout = activeSplitLayout else { return }
            performWindowCommand { store.moveSplitPane(targetID, offset: offset, expected: layout) }
            reclaimFocusAfterSplitPresentation()
        case .addNew: toggleSplit()
        case .add(let operation): beginSplitInsertion(operation, paneID: targetID)
        case .copyLink:
            if let page = browsers[targetID]?.nativePage {
                guard page.canCopyLink(as: .plain) else { return }
                let identity = splitPaneIdentity(targetID)
                page.copyLink(as: .plain) { [weak self, weak page] result in
                    MainActor.assumeIsolated {
                        guard let self, let page, self.browsers[targetID]?.nativePage === page,
                              self.splitPaneIdentity(targetID) == identity else { return }
                        if result == .copied { self.showToast(.copiedCurrentURL(self.copiedLink(page: self.browsers[targetID]?.url)), at: .content(targetID)) }
                    }
                }
            } else if let tab = visibleTabs.first(where: { $0.id == targetID }) {
                NSPasteboard.general.clearContents()
                if NSPasteboard.general.setString(tab.url, forType: .string) { showToast(.copiedCurrentURL(URL(string: tab.url)), at: .content(targetID)) }
            }
        case .close:
            closeClickedSplitPane(targetID)
        case .separate:
            guard let group = activeSplitLayout else { return }
            separateSplitTab(targetID, group: group, originalFocus: currentTabID)
        case .expand:
            NotificationCenter.default.post(name: Self.expandCurrentSplitNotification, object: nil)
        case .orientation(let orientation):
            guard let layout = activeSplitLayout else { return }
            performWindowCommand { store.setSplitLayout(orientation: orientation, widthFactors: layout.widthFactors) }
        }
    }

    static let expandCurrentSplitNotification = Notification.Name("ParcExpandCurrentSplit")

    private func expandDisplayedSplit() {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              spaceCreation == nil, splitInsertion == nil, nativeFullscreenTabID == nil,
              transferringTabIDs.isEmpty, let focus = currentTabID, let layout = activeSplitLayout,
              let factors = layout.expandedFactors(focusing: focus), factors != layout.widthFactors else { return }
        prepareStoreContext()
        guard store.resizeSplit(expected: layout, widthFactors: factors) else { return }
        render(store.state)
    }
    private func recordRecentTabSelection() {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              transferringTabIDs.isEmpty, !selectedTabIDs.isEmpty else { return }
        presentation.recordSelectionForReturn(currentTabID, state: store.state)
        recentTabOrder.record(selectedTabIDs, focus: currentTabID)
        if let first = selectedTabIDs.first, selectedTabIDs.allSatisfy({ switcherCanUse($0) }) {
            closedItems.recordSelection(selectedTabIDs, focusedTabID: currentTabID ?? first, state: store.state)
            onSessionRecordChange?()
            if TabSelectionHistory.isEnabled { tabSelectionHistory.record(.init(tabIDs: selectedTabIDs, focusedTabID: currentTabID ?? first,
                spaceID: activeSpaceID, profileID: activeProfileID,
                orientation: activeSplitLayout?.orientation ?? .horizontal)) }
        }
        tabSwitcher?.dismissIfInvalid()
    }

    private func switcherCanUse(_ id: UUID) -> Bool {
        ownership.canUse(id, owner: presentationID) && !closingTabIDs.contains(id)
            && !modelRetirementIDs.contains(id) && !transferringTabIDs.contains(id)
            && !store.retiringTabIDs.contains(id) && transferRecoveries[id] == nil
    }
    private func canUseOrMoveHere(_ id: UUID) -> Bool { switcherCanUse(id) || canMovePageHere(id) }
    private func canCloseOrMoveHere(_ id: UUID) -> Bool { ownership.canUse(id, owner: presentationID) || canMovePageHere(id) }

    private var tabCommandsAvailable: Bool {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let window else { return false }
        return PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }

    private func canSelectTabCommandItem(_ item: RecentTabOrder.Item) -> Bool {
        item.spaceID == activeSpaceID && item.profileID == activeProfileID
            && item.tabIDs != selectedTabIDs && !item.tabIDs.isEmpty
            && item.tabIDs.allSatisfy { id in
                canUseOrMoveHere(id) && store.state.tabs.contains {
                    $0.id == id && $0.archivedAt == nil && $0.profileID == item.profileID
                        && ($0.kind == .favorite || $0.spaceID == item.spaceID)
                }
            }
    }

    private func positionalDestination(forward: Bool) -> RecentTabOrder.Item? {
        let items = PositionalTabNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID, available: { self.canUseOrMoveHere($0) })
        return PositionalTabNavigation.destination(items, selected: selectedTabIDs, forward: forward)
    }

    func canSelectAdjacentTab(forward: Bool) -> Bool {
        tabCommandsAvailable && tabSwitcher == nil
    }

    func selectAdjacentTab(forward: Bool) {
        guard canSelectAdjacentTab(forward: forward), let item = positionalDestination(forward: forward),
              canSelectTabCommandItem(item) else { return }
        sidebarPreviews?.dismiss()
        selectRecentItem(item)
    }

    private func sidebarItemDestination(number: Int) -> RecentTabOrder.Item? {
        let defaults = UserDefaults.standard
        let items = PositionalTabNavigation.items(state: store.state, spaceID: activeSpaceID,
            selected: selectedTabIDs, focused: currentTabID,
            includeFavorites: !defaults.bool(forKey: NumberedTarget.excludeFavoritesKey), available: { _ in true })
        return NumberedTarget.destination(items, number: number,
                                          ninthItemEnabled: defaults.bool(forKey: NumberedTarget.ninthItemKey))
    }

    func canSelectSidebarItem(number: Int) -> Bool {
        guard tabCommandsAvailable, tabSwitcher == nil, let item = sidebarItemDestination(number: number) else { return false }
        return item.tabIDs == selectedTabIDs || canSelectTabCommandItem(item)
    }

    func selectSidebarItem(number: Int) {
        guard canSelectSidebarItem(number: number), let item = sidebarItemDestination(number: number),
              item.tabIDs != selectedTabIDs else { return }
        sidebarPreviews?.dismiss()
        _ = selectRecentItem(item)
    }

    func canCycleTabHistory(forward: Bool) -> Bool {
        TabSelectionHistory.isEnabled && tabCommandsAvailable && tabSwitcher == nil
    }

    func cycleTabHistory(forward: Bool) {
        guard canCycleTabHistory(forward: forward) else { return }
        sidebarPreviews?.dismiss()
        let previous = tabSelectionHistory
        guard let item = tabSelectionHistory.move(in: activeSpaceID, forward: forward, available: canSelectTabCommandItem) else { return }
        if !selectRecentItem(item) { tabSelectionHistory = previous }
    }

    var canShowRecentTabSwitcher: Bool {
        guard tabCommandsAvailable else { return false }
        if tabSwitcher != nil { return true }
        var order = recentTabOrder
        return order.items(state: store.state, selected: selectedTabIDs, currentSpace: activeSpaceID,
                           available: { self.canUseOrMoveHere($0) }).count > 1
    }

    func cycleRecentTab(forward: Bool) {
        sidebarPreviews?.dismiss()
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, transferringTabIDs.isEmpty, resolvingTransfers.isEmpty,
              let window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
        if let tabSwitcher { tabSwitcher.cycle(forward: forward); return }
        recordRecentTabSelection()
        let selections = recentTabOrder.items(state: store.state, selected: selectedTabIDs,
            currentSpace: activeSpaceID, available: { self.canUseOrMoveHere($0) })
        guard !selections.isEmpty, selections.count > 1 || selectedTabIDs.isEmpty else { return }
        let items = recentSwitcherItems(selections, in: window)
        var sourceIDs = selectedTabIDs, sourceSpace = activeSpaceID
        var confirmedClosedIDs = Set<UUID>()
        let event = shortcutInvocationEvent ?? NSApp.currentEvent
        let controller = RecentTabSwitcher(items: items, currentTabIDs: sourceIDs, parent: window, theme: windowPaletteTheme,
            forward: forward, event: event,
            next: KeyboardShortcuts.shared.activeShortcut(for: "cycleToNextRecentTab:"),
            previous: KeyboardShortcuts.shared.activeShortcut(for: "cycleToPreviousRecentTab:"))
        controller.isCurrent = { [weak self, weak window] items in
            guard let self, let window, self.window === window,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                  !self.windowClosePending, self.transferringTabIDs.isEmpty,
                  self.resolvingTransfers.isEmpty, self.selectedTabIDs == sourceIDs,
                  self.activeSpaceID == sourceSpace else { return false }
            return items.allSatisfy { item in
                if let overlay = item.overlay {
                    guard let page = overlay.page, !page.isClosed,
                          let peek = self.peeks[page.identifier], peek.identity == overlay.id,
                          peek.page === page, !peek.closePending,
                          item.selection.tabIDs == [peek.parentTabID],
                          self.browsers[peek.parentTabID]?.nativePage === peek.parentPage,
                          !self.peekRetirementParents.contains(peek.parentTabID) else { return false }
                }
                return self.store.state.spaces.contains { $0.id == item.selection.spaceID && $0.profileID == item.selection.profileID }
                    && item.components.allSatisfy { component in
                        self.canUseOrMoveHere(component.id)
                            && self.store.state.tabs.contains { $0.id == component.id && $0.archivedAt == nil
                                && $0.profileID == item.selection.profileID
                                && ($0.kind == .favorite || $0.spaceID == item.selection.spaceID) }
                            && self.browsers[component.id]?.nativePage === component.page
                    }
            }
        }
        controller.onComplete = { [weak self, weak controller] selection in
            guard let self, let controller, self.tabSwitcher === controller else { return }
            self.tabSwitcher = nil
            self.noteReturnGate()
            if let selection { self.selectRecentItem(selection) }
        }
        controller.onCloseItem = { [weak self, weak controller, weak window] selection, completion in
            guard let self, let controller, self.tabSwitcher === controller,
                  let window, self.window === window,
                  selection.tabIDs.allSatisfy({ self.canUseOrMoveHere($0) }),
                  self.retirementUnavailableReason?(Set(selection.tabIDs)) == nil else { completion(nil); return }
            let elsewhere = selection.tabIDs.filter { !self.ownership.canUse($0, owner: self.presentationID) }
            if !elsewhere.isEmpty {
                completion(nil)
                guard elsewhere.allSatisfy(self.canMovePageHere) else { self.refuseTabMove(); return }
                _ = self.movePagesHere(elsewhere[...]) { [weak self] in
                    guard let self, selection.tabIDs.allSatisfy({ self.ownership.canUse($0, owner: self.presentationID) }),
                          self.retirementUnavailableReason?(Set(selection.tabIDs)) == nil else { return false }
                    self.prepareStoreContext()
                    self.closeTabsWithReopen(Set(selection.tabIDs)) { [weak self] approved in
                        guard let self, !self.isClosing else { return }
                        guard approved else { selection.tabIDs.forEach(self.returnIfUnshown); return }
                        for id in selection.tabIDs { self.presentation.remove(id) }
                        self.render(self.store.state); self.requestNativeSelection()
                    }
                    return true
                }
                return
            }
            self.prepareStoreContext()
            self.closeTabsWithReopen(Set(selection.tabIDs)) { [weak self, weak controller, weak window] approved in
                guard let self else { completion(nil); return }
                guard approved else { completion(.refused); return }
                confirmedClosedIDs.formUnion(selection.tabIDs)
                for id in selection.tabIDs { self.presentation.remove(id) }
                self.render(self.store.state); self.requestNativeSelection()
                guard let controller, self.tabSwitcher === controller,
                      let window, self.window === window else { completion(nil); return }
                sourceIDs = self.selectedTabIDs; sourceSpace = self.activeSpaceID
                let available = self.recentTabOrder.items(state: self.store.state,
                    selected: sourceIDs, currentSpace: sourceSpace, available: {
                        !confirmedClosedIDs.contains($0) && self.canUseOrMoveHere($0)
                    })
                completion(.closed(self.recentSwitcherItems(available, in: window), theme: self.windowPaletteTheme))
            }
        }
        tabSwitcher = controller
        controller.start(event: event)
    }

    private func recentSwitcherItems(_ selections: [RecentTabOrder.Item], in window: NSWindow) -> [RecentTabSwitcher.Item] {
        let privateWindow = store.isEphemeral
        return selections.map { selection in
            let components = selection.tabIDs.compactMap { id -> RecentTabSwitcher.Component? in
                guard let tab = store.state.tabs.first(where: { $0.id == id }) else { return nil }
                var preview: NSImage? = store.placeholderImages.image(for: id, in: presentationID).map { NSImage(cgImage: $0, size: .zero) }
                if preview == nil, InternalPage(urlString: tab.url) == nil, browsers[id] == nil, let pane = panes[id], pane.window === window,
                   !pane.isHiddenOrHasHiddenAncestor,
                   let bitmap = pane.bitmapImageRepForCachingDisplay(in: pane.bounds) {
                    pane.cacheDisplay(in: pane.bounds, to: bitmap)
                    let image = NSImage(size: pane.bounds.size); image.addRepresentation(bitmap); preview = image
                }
                let title = tab.title.isEmpty ? (tab.url.isEmpty ? "New Tab" : tab.url) : tab.title
                var component = RecentTabSwitcher.Component(id: id, title: title,
                    page: browsers[id]?.nativePage, localPreview: preview)
                switch InternalPage(urlString: tab.url) {
                case .note?: component.template = RecentSwitcherArtwork.note.map { .init(image: $0, title: title) }
                case .easel?: component.template = RecentSwitcherArtwork.easel.map { .init(image: $0, title: title) }
                case nil: if privateWindow { component.template = RecentSwitcherArtwork.incognito.map { .init(image: $0, title: nil) } }
                }
                if InternalPage(urlString: tab.url) != nil {
                    component.favicon = NSImage(
                        systemSymbolName: InternalPage.sidebarFallbackSymbol(urlString: tab.url),
                        accessibilityDescription: nil)
                } else if let page = browsers[id]?.nativePage, !page.isClosed, let icon = page.favicon {
                    component.favicon = icon
                } else if !privateWindow, mayReadCachedFavicons, let url = URL(string: tab.url) {
                    let path = store.independentEngineProfilePath(for: tab.profileID)
                    component.faviconRequest = { [weak self] completion in
                        PCNativeBrowserApplication.favicon(for: url, profilePath: path) { [weak self] image in
                            MainActor.assumeIsolated {
                                guard let self, !self.isClosing,
                                      self.store.state.tabs.contains(where: { $0.id == id && $0.url == tab.url
                                          && $0.profileID == tab.profileID && $0.archivedAt == nil }) else { completion(nil); return }
                                completion(image)
                            }
                        }
                    }
                }
                if let capture = capturePresentations[id] {
                    component.isRecordingMedia = FavoriteTileOverlayRules.isRecording(camera: capture.camera,
                        microphone: capture.microphone, tab: capture.tab, window: capture.window,
                        display: capture.display, mirrored: capture.mirrored, shared: capture.shared)
                }
                return component
            }
            var item = RecentTabSwitcher.Item(selection: selection, components: components,
                spaceName: store.state.spaces.first(where: { $0.id == selection.spaceID })?.name ?? "")
            if selection.tabIDs.count > 1,
               let layout = store.state.splitLayouts.first(where: { Set($0.tabIDs) == Set(selection.tabIDs) }),
               SidebarSplitCellLayout.usesCustomInfo(title: layout.customTitle, hasIcon: layout.customIcon != nil, editing: false) {
                let title = layout.customTitle.flatMap { $0.isEmpty ? nil : $0 }
                    ?? SidebarSplitCellLayout.defaultTitle(count: selection.tabIDs.count)
                item.customInfo = .init(icon: layout.customIcon?.image(size: SidebarSplitCellLayout.countIconSize), title: title)
            }
            if selection.tabIDs.count == 1, let id = selection.tabIDs.first, !peekRetirementParents.contains(id),
               let page = browsers[id]?.nativePage,
               let peek = peeks.values.filter({ $0.parentTabID == id && $0.parentPage === page
                   && !$0.page.isClosed && !$0.closePending })
                   .min(by: { $0.identity.uuidString < $1.identity.uuidString }) {
                item.overlay = RecentTabSwitcher.Component(id: peek.identity, title: peek.page.title,
                                                           page: peek.page, localPreview: nil)
            }
            return item
        }
    }

    @discardableResult
    private func selectRecentItem(_ item: RecentTabOrder.Item) -> Bool {
        guard store.state.spaces.contains(where: { $0.id == item.spaceID && $0.profileID == item.profileID }),
              item.tabIDs.allSatisfy({ id in store.state.tabs.contains {
                  $0.id == id && $0.archivedAt == nil && $0.profileID == item.profileID
                      && ($0.kind == .favorite || $0.spaceID == item.spaceID)
              } }),
              let elsewhere = PageReparenting.pagesToMove(item.tabIDs, usableHere: switcherCanUse, movable: canMovePageHere)
        else { return false }
        if !elsewhere.isEmpty { return movePagesHere(elsewhere[...]) { [weak self] in self?.selectRecentItem(item) ?? false } }
        let previous = selectedTabIDs
        let expected = item.tabIDs
        var committed = false
        let removal = previous == expected ? nil
            : presentationSetMediaRemoval(capturing: previous, remaining: { Set(self.selectedTabIDs) }) {
                self.selectedTabIDs == expected && self.store.state.selectedTabIDs == expected
            }
        performWindowCommand(selectNativePage: false, afterCapture: { if committed { removal?() } }) {
            store.selectSpace(item.spaceID)
            store.setSplit(item.tabIDs)
            committed = store.state.selectedTabIDs == expected
        }
        guard selectedTabIDs == item.tabIDs else { return false }
        focusedTabID = item.focusedTabID
        recordRecentTabSelection()
        updateNavigation(); requestNativeSelection(); focusSelectedContent()
        return true
    }
    func restoreClosedTab() {
        guard let original = window, ownsWindowCommandFocus, windowCommandSecurityAvailable,
              let step = reopenClosedStep else { return }
        func isCurrent() -> Bool {
            window === original && original.isKeyWindow && original.attachedSheet == nil
                && PCNativeBrowserApplication.canPresentTabSwitcher(in: original)
                && reopenClosedStep?.id == step.id
        }
        if navigationHistory?.ownsKeyWindow(in: original) == true {
            navigationHistory?.dismiss()
            guard window === original, ownsWindowCommandFocus, windowCommandSecurityAvailable else { return }
        }
        commandBar?.dismiss()
        guard WindowOwnerSequence.run(while: isCurrent, steps: [
            { self.navigationHistory?.dismiss() },
            { self.closeLibrary(restoreFocus: false) }
        ]) else { return }
        switch step {
        case .items(let record): restoreClosedRecord(record)
        case .folder(let undo): reopenDeletedFolder(undo)
        case .peek(let record): reopenClosedPeek(record)
        }
    }
    private func reopenDeletedFolder(_ undo: FolderDeletionUndo) {
        guard let window else { return }
        do {
            let committed = try store.undoFolderDeletion(undo, shouldCommit: { [weak self, weak window] in
                guard let self, let window, self.window === window, self.folderUndoContextAvailable,
                      !self.folderUndo.isBusy else { return false }
                return undo.tabs.allSatisfy { self.switcherCanUse($0.id) }
            })
            guard committed else { return }
            _ = closedItems.consume(stepID: undo.id)
            let focused = presentation.finishFolderUndo(undo, state: store.state, available: { self.switcherCanUse($0) })
            if focused { focusedTabID = undo.focusedTabID }
            render(store.state); updateNavigation()
            if focused { requestNativeSelection(); focusSelectedLocalContent() }
        } catch { showError(error) }
    }
    private func reopenClosedPeek(_ record: ClosedPeekRecord) {
        if canMovePageHere(record.parentTabID) {
            _ = movePagesHere([record.parentTabID]) { [weak self] in
                guard let self, self.selectTab(record.parentTabID) else { return false }
                DispatchQueue.main.async { [weak self] in self?.reopenClosedPeek(record) }
                return true
            }
            return
        }
        guard selectTab(record.parentTabID), currentTabID == record.parentTabID,
              let binding = nativeBinding, let page = closedPeekParentPage(record),
              nativeBrowser(binding, canPresentPeekFrom: page), openClosedPeek(record, over: page) else { return }
        _ = closedItems.consume(stepID: record.id)
        for operation in peekUndoOperations.allObjects { operation.didReopen(record) }
    }
    private func restoreClosedRecord(_ record: ClosedItemRecord) {
        var restored = false
        store.closedPageHistory.restore(record.tabIDs)
        performWindowCommand(selectNativePage: false) {
            do { restored = try store.restoreClosedItem(record, regroupable: { self.canUseOrMoveHere($0) }) }
            catch {
                if let window { ParcDialog.inform(in: window, .init(title: "This tab couldn’t be reopened", message: error.localizedDescription)) }
            }
        }
        guard restored else { store.closedPageHistory.unrestore(record.tabIDs); return }
        _ = closedItems.consume(record)
        for operation in closeUndoOperations.allObjects { operation.didReopen(record) }
        focusedTabID = record.focusedTabID
        if SidebarSplitItems.groups(in: store.state, spaceID: activeSpaceID).first(where: { $0.tabIDs.contains(record.focusedTabID) })?
               .tabIDs.contains(where: canMovePageHere) == true {
            _ = selectTab(record.focusedTabID)
        }
        updateNavigation(); requestNativeSelection(); focusSelectedLocalContent()
    }
    func toggleSplit() {
        guard let last = selectedTabIDs.last else { return }
        beginSplitInsertion(activeSplitLayout?.orientation == .vertical ? .addBelow : .addAfter, paneID: last)
    }
    private var currentURLForCopy: String? {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return nil }
        let url: String?
        if let commandBar { url = commandBar.selectedURL?.absoluteString }
        else { url = currentBrowser?.url?.absoluteString ?? currentTabID.flatMap { id in store.state.tabs.first { $0.id == id }?.url } }
        return url.map(WhatsNewPage.presented).flatMap { $0.isEmpty ? nil : $0 }
    }
    var canCopyCurrentURL: Bool {
        guard currentURLForCopy != nil else { return false }
        if commandBar != nil { return true }
        if let page = selectedNativePage() { return page.canCopyLink(as: .plain) }
        return true
    }
    private func preparePopupCopyURL() -> (() -> Bool)? {
        guard isPopupWindow, commandBar == nil, canCopyCurrentURL,
              let window, let browser = currentBrowser, browser.window === window,
              let page = browser.nativePage, !page.isClosed, let url = browser.url else { return nil }
        let revision = browser.readerRevision
        var used = false
        return { [weak self, weak window, weak browser, weak page] in
            guard !used, let self, let window, let browser, let page,
                  self.window === window, browser.window === window,
                  self.currentBrowser === browser, self.selectedNativePage() === page,
                  browser.readerRevision == revision, browser.url == url, !page.isClosed, self.commandBar == nil,
                  self.canCopyCurrentURL else { return false }
            used = true
            self.copyPageLink(as: .plain)
            return true
        }
    }
    var canCopyCurrentURLAsMarkdown: Bool {
        commandBar == nil && currentURLForCopy != nil &&
            selectedNativePage()?.canCopyLink(as: .markdown) == true
    }
    var canCopyCurrentURLAsQuote: Bool {
        commandBar == nil && currentURLForCopy != nil &&
            selectedNativePage()?.canCopyLink(as: .quote) == true
    }
    func copyCurrentURL() {
        guard let url = currentURLForCopy else { return }
        if commandBar == nil, let page = selectedNativePage() {
            guard page.canCopyLink(as: .plain) else { return }
            copyPageLink(as: .plain)
        } else {
            copyLinkOperation = UUID()
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(url, forType: .string) { showToast(.copiedCurrentURL(URL(string: url))) }
        }
    }
    func copyCurrentURLAsMarkdown() {
        guard canCopyCurrentURLAsMarkdown else { return }
        copyPageLink(as: .markdown)
    }
    func copyCurrentURLAsQuote() {
        guard canCopyCurrentURLAsQuote else { return }
        copyPageLink(as: .quote)
    }
    private var sharePageTarget: (browser: PCBrowserView, url: URL)? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              libraryView == nil, window?.attachedSheet == nil,
              let browser = currentBrowser, browser.window === window, !browser.isHiddenOrHasHiddenAncestor,
              let page = browser.nativePage, !page.isClosed,
              let url = browser.url, !url.absoluteString.isEmpty, !WhatsNewPage.matches(url.absoluteString) else { return nil }
        return (browser, url)
    }
    var canSharePage: Bool { sharePageTarget != nil }
    func sharePage() {
        guard let (browser, url) = sharePageTarget else { return }
        let bounds = browser.bounds
        let top = browser.isFlipped ? bounds.minY : bounds.maxY - 1
        NSSharingServicePicker(items: [url]).show(
            relativeTo: NSRect(x: bounds.minX, y: top, width: bounds.width, height: 1),
            of: browser, preferredEdge: browser.isFlipped ? .maxY : .minY)
    }
    private func splitShareURLs() -> [URL] {
        selectedTabIDs.compactMap { id in
            if let url = browsers[id]?.url, !url.absoluteString.isEmpty { return WhatsNewPage.matches(url.absoluteString) ? nil : url }
            guard let tab = store.state.tabs.first(where: { $0.id == id && $0.archivedAt == nil }),
                  let url = URL(string: WhatsNewPage.presented(tab.url)), tab.url != "about:blank" else { return nil }
            return url
        }
    }
    private func shareSplitView(from anchor: NSView, urls: [URL]) {
        guard !urls.isEmpty, anchor.window === window else { return }
        NSSharingServicePicker(items: urls).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
    private func copyPageLink(as format: PCNativeLinkCopyFormat) {
        guard let page = selectedNativePage(), page.canCopyLink(as: format) else { return }
        performLinkCopy(page: page, format: format) { completion in
            page.copyLink(as: format, completion: completion)
        }
    }
    private func copySharedQuote(_ selection: PCNativeSharedQuoteSelection, page: PCNativePage) {
        performLinkCopy(page: page, format: .quote) { completion in
            selection.copy(completion: completion)
        }
    }
    private func performLinkCopy(page: PCNativePage, format: PCNativeLinkCopyFormat,
                                 start: (@escaping @Sendable (PCNativeLinkCopyResult) -> Void) -> Void) {
        let operation = UUID(); copyLinkOperation = operation
        start { [weak self, weak page] result in
            MainActor.assumeIsolated {
                guard let self, let page, self.copyLinkOperation == operation,
                      self.selectedNativePage() === page, !page.isClosed,
                      !self.isClosing, !self.wholeWindowClose else { return }
                switch result {
                case .copied:
                    let url = self.copiedLink(page: self.currentBrowser?.url)
                    self.showToast(format == .quote ? .copiedQuoteLink(url) : .copiedCurrentURL(url))
                case .unavailable:
                    self.showToast(.standard(format == .quote ? "Couldn’t create a link to this selection" : "This page’s link is unavailable"))
                case .blocked: self.showToast(.standard("Copying this link is restricted"))
                case .cancelled: break
                @unknown default: break
                }
            }
        }
    }
    private func copiedLink(page url: URL?) -> URL? {
        guard let scheme = url?.scheme?.lowercased(),
              let copied = NSPasteboard.general.string(forType: .string).flatMap({ URL(string: $0) }),
              copied.scheme?.lowercased() == scheme else { return url }
        return copied
    }
    private enum ToastLocation { case content(UUID?), window }
    func showImportFailures() {
        guard presentation.isReady, !isClosing, !isPrivateBrowsing, !isPopupWindow else { return }
        if let outcome = ImportedBrowserDataFailures.take() {
            if showToast(outcome == .failed ? .importFailed : .importPartial, at: .window) == nil {
                ImportedBrowserDataFailures.restore(outcome)
            }
            return
        }
        guard !ImportedExtensionFailures.pending.isEmpty else { return }
        let names = ImportedExtensionFailures.take()
        if showToast(.extensionsNotAdded(names), at: .window) == nil { ImportedExtensionFailures.restore(names) }
    }

    @discardableResult
    private func showToast(_ content: ParcToastContent, at location: ToastLocation = .content(nil),
                           onTap: (() -> Void)? = nil, onRetire: (() -> Void)? = nil) -> ParcToastPresentation? {
        guard let window, !isClosing, !wholeWindowClose else { return nil }
        let anchor: NSView?
        switch location {
        case .window: anchor = nil
        case .content(let id):
            anchor = id.flatMap { panes[$0] } ?? activePeek.flatMap { $0.view.isHidden ? nil : $0.view }
                ?? currentTabID.flatMap { panes[$0] }
        }
        let toast = toasts.show(content, in: window, over: anchor, theme: rootView.theme, onTap: onTap, onRetire: onRetire)
        if toast != nil { retireShortcutHint() }
        return toast
    }

    func showEssentialShortcuts() {
        guard presentation.isReady, !isClosing, !wholeWindowClose else { return }
        if shortcutEssentials == nil {
            let controller = ShortcutEssentialsWindow(shortcuts: .shared)
            controller.onViewAll = { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose else { return }
                self.showSettings(pane: .shortcuts)
            }
            let originalWindow = window
            controller.isOwnerAvailable = { [weak self, weak originalWindow] in
                guard let self, let originalWindow, self.window === originalWindow else { return false }
                return self.presentation.isReady && !self.isClosing && !self.wholeWindowClose
                    && !self.windowClosePending && self.windowCommandSecurityAvailable
            }
            controller.canPerformCommand = { [weak self] id in
                guard let self else { return false }
                guard id == "copyCurrentURL:" else { return true }
                guard self.currentURLForCopy != nil else { return false }
                guard self.commandBar == nil, let page = self.selectedNativePage() else {
                    return self.canCopyCurrentURL
                }
                return !page.isClosed && page.nativeView.window === self.window
                    && !page.nativeView.isHiddenOrHasHiddenAncestor && self.nativeBinding != nil
            }
            controller.onEscape = { [weak self, weak controller] in
                guard controller?.isOwnerAvailable?() == true else { return }
                self?.commandBar?.dismiss()
            }
            controller.onCommand = { [weak self, weak controller, weak originalWindow] id, event in
                guard let self, let originalWindow, controller?.isOwnerAvailable?() == true else { return }
                let previousEvent = self.shortcutInvocationEvent
                self.shortcutInvocationEvent = event
                defer { self.shortcutInvocationEvent = previousEvent }
                if id != "copyCurrentURL:" { originalWindow.makeKeyAndOrderFront(nil) }
                switch id {
                case "newTab:": self.newTab()
                case "cycleToNextRecentTab:": self.cycleRecentTab(forward: true)
                case "copyCurrentURL:":
                    if self.commandBar == nil, let page = self.selectedNativePage(),
                       let binding = self.nativeBinding, let commandWindow = controller?.window {
                        self.performLinkCopy(page: page, format: .plain) { completion in
                            page.copyURL(fromCommandWindow: commandWindow, browser: binding, completion: completion)
                        }
                    } else { self.copyCurrentURL() }
                case "split:": self.toggleSplit()
                default: break
                }
            }
            shortcutEssentials = controller
        }
        shortcutEssentials?.show(relativeTo: window)
    }
    func prepareSettingsForTermination() -> Bool {
        settings?.prepareForTermination() ?? true
    }
    func closePreparedSettingsForTermination() -> Bool {
        let wasVisible = settings?.window?.isVisible == true
        guard settings?.attemptClose() ?? true else { return false }
        restoreSettingsAfterCancelledTermination = wasVisible
        return true
    }
    var onRequestApplicationSettings: ((SettingsWindow.Pane?, String?) -> Void)?

    func showSettings(pane: SettingsWindow.Pane? = nil, shortcutID: String? = nil, contextSpaceID: UUID? = nil) {
        guard !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved else { return }
        if isPrivateBrowsing { onRequestApplicationSettings?(pane, shortcutID); return }
        let spaceID = contextSpaceID ?? activeSpaceID
        if settings?.contextSpaceID != spaceID {
            guard settings?.window?.attachedSheet == nil else { return }
            if let settings, !settings.attemptClose() { return }
            settings = nil
        }
        if settings == nil {
            settings = SettingsWindow(store: store, spaceID: spaceID)
            settings?.onSheetEnded = { [weak self] in self?.retryPendingSettingsClose() }
            settings?.onProfileSettingsPage = { [weak self] spaceID, profileID, page in
                guard let self, let settings = self.settings else { return false }
                return self.showProfileSettingsPage(page, spaceID: spaceID, profileID: profileID, from: settings)
            }
            settings?.onMoreSettings = { [weak self] spaceID, profileID in
                guard let self, let settings = self.settings else { return false }
                return self.showAdvancedSettings(spaceID: spaceID, profileID: profileID, from: settings)
            }
            settings?.onDeleteSpace = { [weak self] spaceID in
                guard let self, let sheetWindow = self.settings?.window else { return false }
                return self.deleteSpace(spaceID, confirmingIn: sheetWindow)
            }
        }
        if shortcutID != nil, settings?.window?.attachedSheet != nil { return }
        settings?.refresh()
        if let shortcutID { guard settings?.showShortcut(shortcutID) == true else { return } }
        else if let pane { settings?.showPane(pane) }
        settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
    }

    func showPasswordManager() {
        guard let space = store.state.spaces.first(where: { $0.id == activeSpaceID }) else { return }
        showPasswordManager(spaceID: space.id, profileID: space.profileID)
    }

    func showAdvancedSettings(spaceID: UUID, profileID: UUID, from settings: SettingsWindow) -> Bool {
        guard !isPrivateBrowsing, settings.permitsPage(in: store, spaceID: spaceID, profileID: profileID),
              let window, window.attachedSheet == nil, !window.isMiniaturized,
              presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, transferringTabIDs.isEmpty,
              resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              !store.isProfileRemovalPending(profileID),
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        window.makeKeyAndOrderFront(nil)
        guard spaceCommandsAvailable else { return false }
        closeLibrary(restoreFocus: false)
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        let existing = store.state.tabs.first { tab in
            guard tab.spaceID == spaceID, tab.profileID == profileID, tab.archivedAt == nil,
                  ownership.canUse(tab.id, owner: presentationID),
                  let url = URL(string: tab.url) else { return false }
            return BrowserInternalURL.isWebUI(url) && url.host == "settings"
        }
        if let existing {
            guard selectTab(existing.id) else { return false }
        } else {
            var createdID: UUID?
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                let id = store.open("parc://settings/", creation: creation)
                presentation.recordCreation(id, state: store.state)
                store.updateTab(id, title: "Settings")
                createdID = id
            }
            guard let createdID, selectedTabIDs.contains(createdID),
                  store.state.tabs.contains(where: { $0.id == createdID && $0.spaceID == spaceID && $0.profileID == profileID }) else { return false }
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func showProfileSettingsPage(_ page: ProfileSettingsPage, spaceID: UUID, profileID: UUID,
                                 from settings: SettingsWindow) -> Bool {
        guard !isPrivateBrowsing, settings.permitsProfilePage(in: store, spaceID: spaceID, profileID: profileID),
              let window, window.attachedSheet == nil, !window.isMiniaturized,
              presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, transferringTabIDs.isEmpty,
              resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              !store.isProfileRemovalPending(profileID),
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        window.makeKeyAndOrderFront(nil)
        guard spaceCommandsAvailable else { return false }
        closeLibrary(restoreFocus: false)
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        if let existing = store.state.tabs.first(where: {
            $0.spaceID == spaceID && $0.profileID == profileID && $0.archivedAt == nil
                && ownership.canUse($0.id, owner: presentationID) && page.canReuse($0.url)
        }) {
            guard selectTab(existing.id) else { return false }
        } else {
            var createdID: UUID?
            let creation = creationProvenance(activeTabID: currentTabID)
            performWindowCommand {
                let id = store.open(page.address, creation: creation)
                presentation.recordCreation(id, state: store.state)
                store.updateTab(id, title: page.title)
                createdID = id
            }
            guard let createdID, selectedTabIDs.contains(createdID),
                  store.state.tabs.contains(where: { $0.id == createdID && $0.spaceID == spaceID && $0.profileID == profileID }) else { return false }
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    private func showPasswordManager(spaceID: UUID, profileID: UUID) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty,
              store.state.spaces.contains(where: { $0.id == spaceID && $0.profileID == profileID }) else { return false }
        let destination = "parc://password-manager/passwords"
        selectSpace(spaceID)
        guard activeSpaceID == spaceID, activeProfileID == profileID else { return false }
        let existing = store.state.tabs.first { tab in
            guard tab.spaceID == spaceID, tab.profileID == profileID, tab.archivedAt == nil,
                  ownership.canUse(tab.id, owner: presentationID),
                  let url = URL(string: tab.url) else { return false }
            return BrowserInternalURL.isWebUI(url) && url.host == "password-manager"
        }
        if let existing {
            guard selectTab(existing.id) else { return false }
            window?.makeKeyAndOrderFront(nil)
            return true
        }
        var createdID: UUID?
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.open(destination, creation: creation)
            presentation.recordCreation(id, state: store.state)
            createdID = id
            store.updateTab(id, title: "Password Manager")
        }
        window?.makeKeyAndOrderFront(nil)
        guard let createdID else { return false }
        return selectedTabIDs.contains(createdID) && store.state.tabs.contains {
            $0.id == createdID && $0.spaceID == spaceID && $0.profileID == profileID
        }
    }
    var canChangePageZoom: Bool {
        PageZoomAvailability.canChange(
            windowReady: presentation.isReady,
            closing: isClosing || wholeWindowClose,
            hasOriginalPage: currentBrowser != nil && (activePeek?.identity ?? currentTabID) != nil
        )
    }
    func zoomIn() { changeZoom(1) }
    func zoomOut() { changeZoom(-1) }
    func actualSize() { changeZoom(0) }
    private func changeZoom(_ direction: Int) {
        guard canChangePageZoom, let id = activePeek?.identity ?? currentTabID, let browser = currentBrowser else { return }
        if browser.zoomPage(direction) {
            if browser.nativePage != nil { showZoomToast(browser.pageZoomLevel) }
            return
        }
        let level = direction == 0 ? 0 : min(5, max(-5, (zoomLevels[id] ?? 0) + 0.5 * Double(direction)))
        zoomLevels[id] = level; browser.setZoomLevel(level); showZoomToast(level)
    }
    private func showZoomToast(_ level: Double) {
        showToast(.zoom(percent: Int((pow(1.2, level) * 100).rounded())))
    }
    @MainActor
    private final class CaptureMenuRequest {
        weak var owner: BrowserWindowController?
        weak var page: PCNativePage?
        let mode: PageCaptureController.Mode
        let profileID: UUID
        let spaceID: UUID
        init(owner: BrowserWindowController, page: PCNativePage, mode: PageCaptureController.Mode) {
            self.owner = owner; self.page = page; self.mode = mode
            profileID = owner.activeProfileID; spaceID = owner.activeSpaceID
        }
    }
    private func prepareCaptureGesture(at point: NSPoint) -> PageCaptureGesture.Admission? {
        guard privateCaptureContextIsValid, pageCapture == nil, commandBar == nil, libraryView == nil,
              canOwnDownloadDialog(for: activeProfileID), let window, window.isKeyWindow,
              NSApp.isActive, window.attachedSheet == nil,
              let hit = rootView.hitTest(rootView.superview?.convert(point, from: nil) ?? point) else { return nil }
        let candidates = activePeek.map { [$0.browser] }
            ?? selectedTabIDs.compactMap { browsers[$0] }
        guard let browser = candidates.first(where: { browser in
            guard let native = browser.nativePage?.nativeView as? PCNativePageHost,
                  let content = native.contentView, !content.isHiddenOrHasHiddenAncestor else { return false }
            return hit === content || hit.isDescendant(of: content)
        }), let page = browser.nativePage else { return nil }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        guard (currentBrowser === browser || activateDeveloperPage(browser, page: page, revision: revision)),
              page.canCapture(in: window) else { return nil }
        let current: () -> Bool = { [weak self, weak browser, weak page, weak window] in
            guard let self, let browser, let page, let window else { return false }
            return self.window === window && window.isKeyWindow && NSApp.isActive
                && self.privateCaptureContextIsValid && self.pageCapture == nil && self.commandBar == nil && self.libraryView == nil
                && self.activeProfileID == profileID && self.activeSpaceID == spaceID
                && self.canOwnDownloadDialog(for: profileID) && window.attachedSheet == nil
                && browser.nativePage === page && browser.readerRevision == revision && !page.isClosed
                && page.nativeView.window === window && !page.nativeView.isHiddenOrHasHiddenAncestor
                && page.profilePath == self.store.independentEngineProfilePath(for: profileID)
                && PCNativeBrowserApplication.owner(of: page) === self.nativeBinding
                && (self.activePeek.map { $0.browser === browser && !$0.closePending }
                    ?? self.selectedTabIDs.contains { self.browsers[$0] === browser })
                && page.canCapture(in: window)
        }
        guard current() else { return nil }
        return PageCaptureGesture.Admission(isCurrent: current, begin: { [weak self, weak browser] in
            guard current(), let self, let browser,
                  self.currentBrowser === browser else { return nil }
            self.capturePage(.region)
            return self.pageCapture
        })
    }
    private var privateCaptureContextIsValid: Bool {
        !isPrivateBrowsing || (nativeBinding?.isPrivateBrowsing == true && nativeBinding?.browsingContextKind == .offTheRecord)
    }
    var canCapturePage: Bool {
        guard privateCaptureContextIsValid else { return false }
        guard pageCapture == nil, let window, NSApp.isActive,
              window.isKeyWindow || (commandBar != nil && NSApp.mainWindow === window),
              canOwnDownloadDialog(for: activeProfileID), window.attachedSheet == nil,
              libraryView == nil, let id = currentTabID,
              !closingTabIDs.contains(id), !modelRetirementIDs.contains(id),
              !store.retiringTabIDs.contains(id),
              let browser = currentBrowser, let page = browser.nativePage, !page.isClosed,
              page.nativeView.window === window,
              page.profilePath == store.independentEngineProfilePath(for: activeProfileID),
              PCNativeBrowserApplication.owner(of: page) === nativeBinding else { return false }
        return page.canCapture(in: window)
    }
    func preparePageCaptureMenuItem(_ item: NSMenuItem, mode: PageCaptureController.Mode) -> Bool {
        item.representedObject = nil
        guard canCapturePage, let page = currentBrowser?.nativePage else { return false }
        item.representedObject = CaptureMenuRequest(owner: self, page: page, mode: mode)
        return true
    }
    func capturePage(from item: NSMenuItem) {
        guard let request = item.representedObject as? CaptureMenuRequest, request.owner === self,
              request.page === currentBrowser?.nativePage, request.profileID == activeProfileID,
              request.spaceID == activeSpaceID else { return }
        capturePage(request.mode)
    }
    private func capturePage(_ mode: PageCaptureController.Mode) {
        guard canCapturePage, let parent = window, let browser = currentBrowser,
              let page = browser.nativePage, let tabID = currentTabID else { return }
        commandBar?.dismiss(); navigationHistory?.dismiss()
        sidebarPreviews?.dismiss(); tabSwitcher?.cancel(); dismissSiteControlCenter()
        settleSidebarMotion(); layoutChrome(); rootView.layoutSubtreeIfNeeded()
        Self.yieldPlaceholderCapture(of: page)
        guard let lease = page.beginCapture(in: parent) else { return }
        let profileID = activeProfileID, spaceID = activeSpaceID
        let privateCatalog = isPrivateBrowsing && canShowMedia ? downloadCatalog : nil
        let privateParent = privateCatalog == nil ? nil : store.privateParentProfileID
        let destination = CaptureLibraryDestination.make(store: store, parent: privateCatalog,
                                                         profileID: profileID, spaceID: spaceID)
        let valid: () -> Bool = { [weak self, weak browser, weak page, weak parent, weak privateCatalog] in
            guard let self, let browser, let page, let parent else { return false }
            return self.window === parent && parent.isVisible && !parent.isMiniaturized
                && self.privateCaptureContextIsValid && self.canOwnDownloadDialog(for: profileID) && self.activeSpaceID == spaceID
                && (privateParent == nil || (privateCatalog != nil && self.downloadCatalog === privateCatalog
                    && self.store.privateParentProfileID == privateParent && self.canShowMedia))
                && self.currentTabID == tabID && self.currentBrowser === browser
                && browser.nativePage === page && !page.isClosed
                && !self.closingTabIDs.contains(tabID) && !self.modelRetirementIDs.contains(tabID)
                && !self.store.retiringTabIDs.contains(tabID)
                && self.browserProfiles[tabID] == profileID && self.libraryView == nil
                && page.profilePath == self.store.independentEngineProfilePath(for: profileID)
                && PCNativeBrowserApplication.owner(of: page) === self.nativeBinding
        }
        let controller = PageCaptureController(lease: lease, sourceView: page.nativeView, containerView: browser,
            host: rootView, parent: parent, valid: valid,
            destination: destination,
            easelDestinations: { [weak self] in
                guard let self, valid() else { throw CocoaError(.userCancelled) }
                let documents = try EaselEditorViewController.sharedStore(directory:
                    self.store.easelsDirectory(for: profileID)).list()
                let activity = self.store.state.tabs.filter { $0.archivedAt == nil }.flatMap { tab in
                    [InternalPage(urlString: tab.url)?.easelID, InternalPage(urlString: tab.savedURL)?.easelID]
                        .compactMap { $0 }.map {
                            CaptureEaselDestination.Activity(id: $0, profileID: tab.profileID, date: tab.lastAccessed)
                        }
                }
                return CaptureEaselDestination.catalog(documents: documents, activity: activity, profileID: profileID)
            }, addToEasel: { [weak self, weak parent] image, destinationID in
                guard let self, let parent, parent.isKeyWindow, parent.attachedSheet == nil,
                      valid(), image.isValid, self.easelImageDestination == nil,
                      self.presentation.isReady, !self.isClosing, !self.wholeWindowClose,
                      self.transferringTabIDs.isEmpty else {
                    throw CocoaError(.userCancelled)
                }
                let destinationStore = try EaselEditorViewController.sharedStore(directory:
                    self.store.easelsDirectory(for: profileID))
                let result = try EaselImagePlacement.place(image, in: destinationStore,
                    destinationID: destinationID, newTitle: image.pageTitle)
                self.pageCapture?.dismiss(restoreFocus: false)
                withExtendedLifetime(result) { self.openEasel(id: result.id, title: result.title) }
            }, finished: { [weak self, weak browser, weak parent] restoreFocus in
                guard let self else { return }
                self.pageCapture = nil
                self.sharedQuotes.bind(self.selectedNativePage(), window: self.window)
                self.easelImageDestination?.dismissIfInvalid()
                if restoreFocus, valid(), let browser, let parent, parent.isKeyWindow, parent.attachedSheet == nil {
                    parent.makeFirstResponder(browser.nativePage?.nativeView ?? browser)
                }
            })
        sharedQuotes.invalidate()
        controller.onCopied = { [weak self] in self?.showToast(.copiedImage) }
        pageCapture = controller; controller.present(mode)
    }
    private func captureMenuItem(_ title: String, mode: PageCaptureController.Mode) -> NSMenuItem {
        let page = currentBrowser?.nativePage, profileID = activeProfileID, spaceID = activeSpaceID
        let item = MenuAction.item(title) { [weak self, weak page] in
            guard let self, let page, self.currentBrowser?.nativePage === page,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID else { return }
            self.capturePage(mode)
        }
        let binding: String?
        switch mode {
        case .region: binding = "capturePage:"
        case .viewport: binding = "captureVisiblePage:"
        case .fullPage: binding = "captureFullPage:"
        case .portrait: binding = nil
        }
        if let binding { KeyboardShortcuts.shared.showBinding(on: item, for: binding) }
        item.isEnabled = canCapturePage; return item
    }

    @MainActor
    private final class ToolbarMenuRequest {
        weak var owner: BrowserWindowController?
        init(_ owner: BrowserWindowController) { self.owner = owner }
    }
    private var canToggleToolbar: Bool {
        guard !isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !BrowserToolbarPreferences.shared.loadError,
              ownsSpaceCommandFocus, let window else { return false }
        return commandBar != nil || PCNativeBrowserApplication.canPresentTabSwitcher(in: window)
    }
    func prepareToolbarMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = BrowserToolbarPreferences.shared.state.isVisible ? "Hide Toolbar" : "Show Toolbar"
        item.representedObject = canToggleToolbar ? ToolbarMenuRequest(self) : nil
        return canToggleToolbar
    }
    func toggleToolbar(from item: NSMenuItem) {
        guard let request = item.representedObject as? ToolbarMenuRequest,
              request.owner === self, canToggleToolbar else { return }
        commandBar?.dismiss(restoreFocus: true)
        guard canToggleToolbar else { return }
        do { try BrowserToolbarPreferences.shared.setVisible(!BrowserToolbarPreferences.shared.state.isVisible) }
        catch { showError(error) }
    }
    private var selectedBrowserToolbar: BrowserToolbarView? {
        if let peek = activePeek, !peek.view.browserToolbar.isHidden { return peek.view.browserToolbar }
        if let id = currentTabID, let toolbar = panes[id]?.browserToolbar, !toolbar.isHidden { return toolbar }
        return nil
    }
    private var sidebarShowsAddressBar: Bool {
        PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: selectedBrowserToolbar != nil,
                                                   toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible)
    }
    private func applySidebarToolbarOwnership() {
        sidebar.usesContentToolbar = !sidebarShowsAddressBar
        sidebar.navigationInContentToolbar = selectedBrowserToolbar != nil
    }
    private func configureBrowserToolbar(_ toolbar: BrowserToolbarView, browser: PCBrowserView?, visible: Bool, failing: Bool, themeBackground: NSColor?, leading: Bool = false, tabID: UUID? = nil) {
        guard visible, !isPopupWindow, libraryView == nil,
              let browser, let page = browser.nativePage, !page.isClosed else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil,
               let browser, currentBrowser === browser, let page = browser.nativePage, !page.isClosed {
                window?.makeFirstResponder(page.nativeView)
            }
            toolbar.isHidden = true; toolbar.setPageColor(nil, for: nil); toolbar.invalidate(); return
        }
        toolbar.isHidden = false; toolbar.themeBackground = themeBackground
        toolbar.showPageColor(of: page, failing: failing)
        let revision = browser.readerRevision
        let selected = currentBrowser === browser
        let enabled = !isClosing && !wholeWindowClose && !windowClosePending && commandBar == nil
            && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        let whatsNew = WhatsNewPage.matches(browser.url?.absoluteString ?? "")
        toolbar.update(url: browser.url, documentTitle: whatsNew ? browser.title : nil,
            fullURL: BrowserToolbarPreferences.shared.state.showsFullURL,
            enabled: enabled, canBack: page.canShowBackHistory, canForward: page.canShowForwardHistory,
            loading: page.loading, canReload: page.canPerformNavigation(page.loading ? .stop : .reload),
            canCopy: !whatsNew && (selected ? canCopyCurrentURL : browser.url != nil && page.canCopyLink(as: .plain)),
            canShowSiteInfo: true,
            canSplit: activePeek?.canSplit?() ?? true,
            close: activePeek?.browser !== browser && activeSplitLayout != nil,
            showSidebar: leading && sidebarPresentation != .locked,
            insecure: page.responds(to: #selector(getter: PCNativePage.secureContextState))
                && page.secureContextState == .insecure,
            extensionItems: selected ? extensionControlItems() : [])
        let original: () -> Bool = { [weak self, weak browser, weak page] in
            guard let self, let browser, let page else { return false }
            return self.activateDeveloperPage(browser, page: page, revision: revision)
        }
        toolbar.onNavigation = { [weak self] kind in
            guard original() else { return nil }; return self?.prepareNavigationInteraction(kind)
        }
        toolbar.onEscape = { [weak self, weak page] in
            guard original(), let page else { return }; self?.window?.makeFirstResponder(page.nativeView)
        }
        toolbar.onTitleMenu = { [weak self, weak browser] in
            guard let self, let browser else { return nil }
            return self.paneTitleMenu(browser: browser, admit: original)
        }
        toolbar.onAction = { [weak self, weak browser, weak page] action, anchor in
            guard let self else { return }
            if action == .closeSplit {
                if let tabID { self.closeClickedSplitPane(tabID) }
                return
            }
            guard original(), let browser, let page else { return }
            switch action {
            case .address: self.focusAddress(anchor: anchor)
            case .copy: self.copyCurrentURL()
            case .siteInfo, .siteInsecure: self.showSiteControlCenter(from: anchor)
            case .pageMenu: self.showPageMenu(from: anchor)
            case .split: self.showDeveloperSplitMenu(from: anchor, browser: browser, page: page, revision: revision)
            case .closeSplit: break
            case .sidebar: self.toggleSidebar()
            }
        }
    }

    private func configureDocumentToolbar(_ pane: BrowserPane, tabID: UUID, visible: Bool, leading: Bool) {
        let toolbar = pane.browserToolbar
        guard visible, !isPopupWindow, libraryView == nil,
              let tab = store.state.tabs.first(where: { $0.id == tabID && $0.archivedAt == nil }) else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil { focusSelectedLocalContent() }
            toolbar.isHidden = true; toolbar.setPageColor(nil, for: nil); toolbar.invalidate(); return
        }
        toolbar.isHidden = false; toolbar.themeBackground = rootView.palette.background
        toolbar.setPageColor(nil, for: nil)
        let enabled = !isClosing && !wholeWindowClose && !windowClosePending && commandBar == nil
            && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        toolbar.update(url: nil, documentTitle: tab.title.isEmpty ? "New tab" : tab.title,
            fullURL: false, enabled: enabled, canBack: false, canForward: false, loading: false,
            canReload: false, canCopy: false, canShowSiteInfo: false, canSplit: true,
            close: activeSplitLayout != nil, showSidebar: leading && sidebarPresentation != .locked,
            siteControls: false, extensionItems: [])
        let admit: () -> Bool = { [weak self, weak pane] in
            guard let self, let pane, self.panes[tabID] === pane, self.selectedTabIDs.contains(tabID),
                  pane.livePage == nil, self.activePeek == nil, self.commandBar == nil,
                  self.presentation.isReady, !self.isClosing, let window = self.window, window.isKeyWindow,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            if self.focusedTabID != tabID { self.focusedTabID = tabID; self.requestNativeSelection(); self.updateNavigation() }
            return self.currentTabID == tabID
        }
        toolbar.onNavigation = { _ in nil }
        toolbar.onEscape = { [weak self] in guard admit() else { return }; self?.focusSelectedLocalContent() }
        toolbar.onTitleMenu = { [weak self] in
            guard let self else { return nil }
            let model = self.store.state.tabs.first { $0.id == tabID && $0.archivedAt == nil }
            return self.paneTitleMenu(browser: nil, tab: model, admit: admit)
        }
        toolbar.onAction = { [weak self] action, anchor in
            guard let self else { return }
            if action == .closeSplit {
                self.closeClickedSplitPane(tabID)
                return
            }
            guard admit() else { return }
            switch action {
            case .address: self.focusAddress(anchor: anchor)
            case .split: self.showSplitPaneMenu(tabID, from: anchor)
            case .closeSplit: break
            case .sidebar: self.toggleSidebar()
            case .copy, .siteInfo, .siteInsecure, .pageMenu: break
            }
        }
    }

    private func paneTitleMenu(browser: PCBrowserView?, tab: BrowserTab? = nil, admit: @escaping () -> Bool) -> NSMenu? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              commandBar == nil, libraryView == nil, let window, window.isKeyWindow else { return nil }
        if let peek = activePeek, peek.browser !== browser { return nil }
        let content = PaneMenuContent(livePage: browser?.nativePage.map { !$0.isClosed } == true, tabURL: tab?.url,
                                      localDocument: tab.map { InternalPage.isInternal($0.url) } == true)
        guard content != .none else { return nil }
        let isWeb = content == .web
        let shareURL = (browser?.url ?? tab.flatMap { URL(string: $0.url) })
            .flatMap { WhatsNewPage.matches($0.absoluteString) ? nil : $0 }
        let menu = NSMenu(); menu.autoenablesItems = false
        func page(_ title: String, enabled: Bool = true, _ perform: @escaping (BrowserWindowController) -> Void) -> NSMenuItem {
            let item = MenuAction.item(title) { [weak self] in
                guard let self, !self.isClosing, admit() else { return }
                perform(self)
            }
            item.isEnabled = enabled; return item
        }
        func preference(_ title: String, enabled: Bool, _ change: @escaping () throws -> Void) -> NSMenuItem {
            let item = MenuAction.item(title) { [weak self] in
                guard let self, self.presentation.isReady, !self.isClosing, !self.wholeWindowClose else { return }
                do { try change() } catch { showError(error) }
            }
            item.isEnabled = enabled; return item
        }
        let copyURL = page("Copy URL", enabled: browser == nil || shareURL != nil) { $0.copyCurrentURL() }
        KeyboardShortcuts.shared.showBinding(on: copyURL, for: "copyCurrentURL:")
        menu.addItem(copyURL)
        if isWeb {
            let canCapture = browser != nil && privateCaptureContextIsValid
            menu.addItem(PaneShareMenu.item(for: shareURL))
            let portion = page("Capture Portion…", enabled: canCapture) { $0.capturePage(.region) }
            KeyboardShortcuts.shared.showBinding(on: portion, for: "capturePage:")
            menu.addItem(portion)
            menu.addItem(page("Capture Visible Area", enabled: canCapture) { $0.capturePage(.viewport) })
            menu.addItem(page("Capture Full Page", enabled: canCapture) { $0.capturePage(.fullPage) })
            menu.addItem(.separator())
            menu.addItem(page("Manage Extensions…") { $0.openAddress(URL(string: "parc://extensions/")!) })
        }
        var section: [NSMenuItem] = []
        let toolbar = BrowserToolbarPreferences.shared
        if isWeb {
            let full = toolbar.state.showsFullURL
            section.append(preference(full ? "Hide Full URL" : "Show Full URL", enabled: !toolbar.loadError) {
                try toolbar.setShowsFullURL(!full)
            })
        }
        if !isPopupWindow, activeSplitLayout == nil {
            let visible = toolbar.state.isVisible
            section.append(preference(visible ? "Hide Toolbar" : "Show as Toolbar", enabled: canToggleToolbar) {
                try toolbar.setVisible(!visible)
            })
        }
        if isWeb {
            let quotes = SharedQuotePreferences.shared, enabled = quotes.state.isEnabled
            section.append(preference(enabled ? "Disable Shared Quotes" : "Enable Shared Quotes", enabled: !quotes.loadError) {
                try quotes.setEnabled(!enabled)
            })
        }
        if !section.isEmpty { menu.addItem(.separator()); section.forEach(menu.addItem) }
        return menu
    }

    @MainActor
    private final class DeveloperModeMenuRequest {
        weak var owner: BrowserWindowController?
        weak var browser: PCBrowserView?
        let page: PCNativePage
        let revision: UInt
        let host: String
        init(owner: BrowserWindowController, browser: PCBrowserView, page: PCNativePage, host: String) {
            self.owner = owner; self.browser = browser; self.page = page
            revision = browser.readerRevision; self.host = host
        }
    }
    @MainActor
    private final class FairPlayIdentityMenuRequest {
        weak var owner: BrowserWindowController?
        weak var page: PCNativePage?
        let site: String
        let profilePath: String
        let offTheRecord: Bool
        let useChrome: Bool
        init(owner: BrowserWindowController, page: PCNativePage, site: String, offTheRecord: Bool, useChrome: Bool) {
            self.owner = owner; self.page = page; self.site = site
            profilePath = page.profilePath; self.offTheRecord = offTheRecord; self.useChrome = useChrome
        }
    }
    func prepareFairPlayIdentityMenuItem(_ item: NSMenuItem) -> Bool {
        item.representedObject = nil
        guard let page = currentBrowser?.nativePage, !page.isClosed, let site = page.fairPlayIdentitySite else { return false }
        let offTheRecord = page.fairPlayIdentityOffTheRecord
        let useChrome: Bool
        switch FairPlayIdentityController.shared.identity(of: site, profilePath: page.profilePath, offTheRecord: offTheRecord) {
        case .safari: useChrome = true
        case .chrome: useChrome = false
        case .undecided: return false
        }
        item.title = useChrome ? "Use Chrome Identity for This Site" : "Use Safari Identity for This Site"
        item.representedObject = FairPlayIdentityMenuRequest(owner: self, page: page, site: site,
                                                             offTheRecord: offTheRecord, useChrome: useChrome)
        return true
    }
    func toggleFairPlayIdentity(from item: NSMenuItem) {
        guard let request = item.representedObject as? FairPlayIdentityMenuRequest, request.owner === self,
              let page = request.page, currentBrowser?.nativePage === page, !page.isClosed,
              page.fairPlayIdentitySite == request.site else { return }
        let identity = FairPlayIdentityController.shared
        if request.useChrome {
            identity.useChromeIdentity(for: request.site, profilePath: request.profilePath, offTheRecord: request.offTheRecord)
        } else {
            identity.useSafariIdentity(for: request.site, profilePath: request.profilePath, offTheRecord: request.offTheRecord)
        }
    }
    private var developerModeTitle: String {
        guard let host = currentBrowser?.nativePage?.developerModeSiteHost else { return "Turn on Developer Mode for this site" }
        return DeveloperModePreferences.shared.isEnabled(host: host)
            ? "Turn off Developer Mode for this site" : "Turn on Developer Mode for this site"
    }
    private func makeDeveloperModeRequest() -> DeveloperModeMenuRequest? {
        guard !isPrivateBrowsing, !DeveloperModePreferences.shared.loadError, canPerformPageTool(.developerTools),
              let browser = currentBrowser, let page = browser.nativePage,
              let host = page.developerModeSiteHost else { return nil }
        return DeveloperModeMenuRequest(owner: self, browser: browser, page: page, host: host)
    }
    func prepareDeveloperModeMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = developerModeTitle
        item.representedObject = makeDeveloperModeRequest()
        return item.representedObject != nil
    }
    func toggleDeveloperMode(from item: NSMenuItem) {
        guard let request = item.representedObject as? DeveloperModeMenuRequest,
              request.owner === self, let browser = request.browser, currentBrowser === browser,
              browser.nativePage === request.page, browser.readerRevision == request.revision,
              request.page.developerModeSiteHost == request.host, canPerformPageTool(.developerTools) else { return }
        setDeveloperMode(!DeveloperModePreferences.shared.isEnabled(host: request.host), host: request.host,
                         browser: browser, page: request.page)
    }
    @objc private func toggleDeveloperModeMenuItem(_ sender: NSMenuItem) { toggleDeveloperMode(from: sender) }

    private func setDeveloperMode(_ on: Bool, host: String, browser: PCBrowserView, page: PCNativePage) {
        do {
            try DeveloperModePreferences.shared.setEnabled(on, host: host)
        } catch { showError(error); return }
        refreshDeveloperToolbars()
        guard Self.knowsDeveloperTools(page), on != page.hasDeveloperTools else { return }
        _ = browser.performPageTool(on ? .javaScriptConsole : .developerTools)
    }

    private static func knowsDeveloperTools(_ page: PCNativePage) -> Bool {
        page.responds(to: #selector(getter: PCNativePage.hasDeveloperTools))
    }

    private func toggleDeveloperTools(_ browser: PCBrowserView) {
        guard let page = browser.nativePage, Self.knowsDeveloperTools(page),
              let request = makeDeveloperModeRequest(), request.page === page else {
            _ = browser.performPageTool(.developerTools)
            return
        }
        setDeveloperMode(!page.hasDeveloperTools, host: request.host, browser: browser, page: page)
    }

    private func activateDeveloperPage(_ browser: PCBrowserView, page: PCNativePage, revision: UInt) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              commandBar == nil, libraryView == nil, nativeFullscreenTabID == nil,
              browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
              let window, browser.window === window, window.isKeyWindow,
              PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
        if let peek = activePeek { return peek.browser === browser && !peek.closePending }
        guard let id = browsers.first(where: { $0.value === browser })?.key,
              selectedTabIDs.contains(id), panes[id]?.browser === browser,
              !closingTabIDs.contains(id), !store.retiringTabIDs.contains(id),
              !transferringTabIDs.contains(id) else { return false }
        if focusedTabID != id {
            focusedTabID = id; requestNativeSelection(); updateNavigation()
        }
        return currentBrowser === browser
    }
    private func configureWebpageDragging(_ pane: BrowserPane, tabID: UUID) {
        guard !WebpageWindowDraggingPreferences.shared.loadError,
              WebpageWindowDraggingPreferences.shared.state.isEnabled,
              selectedTabIDs.contains(tabID), activePeek == nil, nativeFullscreenTabID == nil,
              libraryView == nil, !isPopupWindow, let browser = pane.browser,
              let page = browser.nativePage, !page.isClosed else {
            pane.windowGrabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil); return
        }
        let revision = browser.readerRevision
        let original: () -> Bool = { [weak self, weak pane, weak browser, weak page] in
            guard let self, let pane, let browser, let page,
                  !WebpageWindowDraggingPreferences.shared.loadError,
                  WebpageWindowDraggingPreferences.shared.state.isEnabled,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.activePeek == nil, self.pageCapture == nil, self.libraryView == nil,
                  self.commandBar == nil, self.nativeFullscreenTabID == nil,
                  self.selectedTabIDs.contains(tabID), self.panes[tabID] === pane, pane.browser === browser,
                  browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
                  !browser.isHiddenOrHasHiddenAncestor,
                  !self.closingTabIDs.contains(tabID), !self.store.retiringTabIDs.contains(tabID),
                  !self.transferringTabIDs.contains(tabID),
                  let window = self.window, browser.window === window,
                  window.isVisible, window.isMovable, !window.styleMask.contains(.fullScreen),
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return false }
            return true
        }
        pane.windowGrabber.configure(owner: page, revision: revision, isCurrent: original) { [weak page] event in
            guard original(), WebpageWindowDragState.permitsModifiers(event.modifierFlags), let page,
                  let host = page.nativeView as? PCNativePageHost,
                  let rendererContainer = host.contentView, !rendererContainer.isHiddenOrHasHiddenAncestor,
                  rendererContainer.bounds.contains(rendererContainer.convert(event.locationInWindow, from: nil)) else { return false }
            return true
        }
    }

    private func refreshDeveloperToolbars() {
        let modal = activePeek?.modalPhase
        let leading = renderedPaneIDs.first
        var flushedChromeLayout = false
        for (id, pane) in panes {
            let obstructed = modal == .presented
            if pane.controlsObstructed != obstructed { pane.controlsObstructed = obstructed }
            let focused = currentTabID == id || modal == .dismissing
            if pane.controlsFocused != focused { pane.controlsFocused = focused }
            configureWebpageDragging(pane, tabID: id)
            configurePaneDeveloperToolbar(pane,
                visible: selectedTabIDs.contains(id) && activePeek == nil && nativeFullscreenTabID == nil)
            let developerPage = pane.browser?.nativePage?.developerModeSiteHost
                .map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
            let topBar = selectedTabIDs.contains(id) && paneTopBarDisplayed && !developerPage
            if let browser = pane.livePage {
                configureBrowserToolbar(pane.browserToolbar, browser: browser, visible: topBar, failing: pane.showsFailure,
                                        themeBackground: rootView.palette.background, leading: id == leading, tabID: id)
            } else {
                configureDocumentToolbar(pane, tabID: id, visible: topBar, leading: id == leading)
            }
            let developerHeight: CGFloat = pane.loadedDeveloperToolbar?.isHidden == false ? DeveloperToolbarLayout.height : 0
            let browserHeight: CGFloat = pane.browserToolbar.isHidden ? 0 : BrowserToolbarView.height
            if pane.needsLayout
                || !DeveloperChromeGeometry.paneIsCurrent(
                    bounds: pane.bounds,
                    developerHeight: developerHeight,
                    browserHeight: browserHeight,
                    developerFrame: pane.loadedDeveloperToolbar?.frame
                        ?? NSRect(x: 0, y: 0, width: pane.bounds.width, height: 0),
                    browserFrame: pane.browserToolbar.frame,
                    contentFrame: pane.content.frame) {
                pane.needsLayout = true
                pane.layoutSubtreeIfNeeded()
                flushedChromeLayout = true
            }
        }
        refreshSplitPaneHighlights()
        for peek in peeks.values {
            configureDeveloperToolbar(peek.view.developerToolbar, browser: peek.browser,
                visible: activePeek === peek)
            configureBrowserToolbar(peek.view.browserToolbar, browser: peek.browser,
                visible: PaneTopBarAdmission.peekDisplayed(
                    toolbarVisible: BrowserToolbarPreferences.shared.state.isVisible,
                    isActivePeek: activePeek === peek,
                    developerToolbarHidden: peek.view.developerToolbar.isHidden),
                failing: peek.showsFailure, themeBackground: nil)
            let developerHeight: CGFloat = peek.view.developerToolbar.isHidden ? 0 : DeveloperToolbarLayout.height
            let browserHeight: CGFloat = peek.view.browserToolbar.isHidden ? 0 : BrowserToolbarView.height
            if peek.view.needsLayout
                || !DeveloperChromeGeometry.peekIsCurrent(
                    bounds: peek.view.bounds,
                    developerHeight: developerHeight,
                    browserHeight: browserHeight,
                    developerFrame: peek.view.developerToolbar.frame,
                    browserFrame: peek.view.browserToolbar.frame,
                    contentFrame: peek.view.content.frame) {
                peek.view.needsLayout = true
                peek.view.layoutSubtreeIfNeeded()
                flushedChromeLayout = true
            }
        }
        applySidebarToolbarOwnership()
        if flushedChromeLayout {
            synchronizeNativeLayout()
        }
    }
    private func configurePaneDeveloperToolbar(_ pane: BrowserPane, visible: Bool) {
        let shows = visible && libraryView == nil
            && pane.browser?.nativePage?.developerModeSiteHost.map { DeveloperModePreferences.shared.isEnabled(host: $0) } == true
        guard let toolbar = shows ? pane.developerToolbar : pane.loadedDeveloperToolbar else { return }
        configureDeveloperToolbar(toolbar, browser: pane.browser, visible: visible)
    }

    private func configureDeveloperToolbar(_ toolbar: DeveloperToolbarView, browser: PCBrowserView?, visible: Bool) {
        guard visible, libraryView == nil, let browser, let page = browser.nativePage,
              let host = page.developerModeSiteHost, DeveloperModePreferences.shared.isEnabled(host: host) else {
            if toolbar.ownsFocus, window?.isKeyWindow == true, commandBar == nil,
               let browser, currentBrowser === browser, let page = browser.nativePage, !page.isClosed {
                toolbar.restoreCommittedAddress(); window?.makeFirstResponder(page.nativeView)
            }
            toolbar.isHidden = true; toolbar.onAction = nil; toolbar.onFocus = nil
            toolbar.onEdit = nil; toolbar.onEscape = nil; return
        }
        toolbar.isHidden = false
        let revision = browser.readerRevision
        let selected = currentBrowser === browser
        let editing = !isClosing && !wholeWindowClose && !windowClosePending
            && commandBar == nil && window?.isKeyWindow == true
            && window.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
        let enabled = editing && selected && browser.canPerformPageTool(.developerTools)
        toolbar.update(url: WhatsNewPage.presented(browser.url?.absoluteString ?? ""), tint: page.developerModeTint,
            editing: editing, enabled: enabled, secure: page.developerModeSecure, siteInfo: browser.canShowSiteInfo,
            copy: selected && canCopyCurrentURL, capture: selected && canCapturePage,
            split: !isPopupWindow && (activePeek?.canSplit?() ?? true))
        let original: () -> Bool = { [weak self, weak browser, weak page] in
            guard let self, let browser, let page else { return false }
            return self.activateDeveloperPage(browser, page: page, revision: revision)
        }
        toolbar.onFocus = original
        toolbar.onEscape = { [weak self, weak page] in
            guard original(), let self, let page else { return }
            self.window?.makeFirstResponder(page.nativeView)
        }
        toolbar.onEdit = { [weak self, weak toolbar] text, selection in
            DispatchQueue.main.async { [weak self, weak toolbar] in
                guard original(), let self, let toolbar else { return }
                toolbar.restoreCommittedAddress()
                self.presentCommandBar(newTab: false, initialEdit: (text, selection))
            }
        }
        toolbar.onAction = { [weak self, weak browser, weak page] action, anchor in
            guard original(), let self, let browser, let page else { return }
            switch action {
            case .siteInfo: if browser.canShowSiteInfo { _ = browser.showSiteInfo(from: anchor) }
            case .copy: self.copyCurrentURL()
            case .portrait: self.capturePage(.portrait)
            case .capture: self.capturePage(.region)
            case .console: self.performPageTool(.javaScriptConsole)
            case .network: self.performPageTool(.networkInspector)
            case .inspect: self.performPageTool(.inspectElements)
            case .extensions: self.showSiteControlCenter(from: anchor)
            case .tools: self.showPageMenu(from: anchor)
            case .split: self.showDeveloperSplitMenu(from: anchor, browser: browser, page: page, revision: revision)
            }
        }
    }
    private func showDeveloperSplitMenu(from anchor: NSView, browser: PCBrowserView, page: PCNativePage, revision: UInt) {
        guard activateDeveloperPage(browser, page: page, revision: revision), !isPopupWindow else { return }
        let menu = NSMenu(); menu.autoenablesItems = false
        if let peek = activePeek {
            let item = MenuAction.item("Add Peek to Split View") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek,
                      self.activateDeveloperPage(browser, page: page, revision: revision) else { return }
                self.promotePeek(peek, split: true)
            }
            item.isEnabled = peek.canSplit?() == true; menu.addItem(item)
        } else if let paneID = currentTabID {
            showSplitPaneMenu(paneID, from: anchor); return
        } else if activeSplitLayout != nil {
            menu.addItem(splitMenuItem("Expand Current Split", command: .expand))
            menu.addItem(splitMenuItem("Separate Page from Split View", command: .separate))
            menu.addItem(splitMenuItem("Close this Split Pane", command: .close))
        } else {
            menu.addItem(MenuAction.item("Add Split View") { [weak self, weak browser, weak page] in
                guard let self, let browser, let page,
                      self.activateDeveloperPage(browser, page: page, revision: revision) else { return }
                self.toggleSplit()
            })
        }
        menu.appearance = anchor.effectiveAppearance
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    func showDeveloperTools() { performPageTool(.developerTools) }

    func canPerformPageTool(_ tool: PCNativePageTool) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              let browser = currentBrowser else { return false }
        return browser.canPerformPageTool(tool)
    }

    func performPageTool(_ tool: PCNativePageTool) {
        guard canPerformPageTool(tool), let browser = currentBrowser else { return }
        runPageTool(tool, in: browser)
    }

    private func runPageTool(_ tool: PCNativePageTool, in browser: PCBrowserView) {
        if tool == .developerTools { toggleDeveloperTools(browser); return }
        let opens = browser.nativePage.map { Self.knowsDeveloperTools($0) && !$0.hasDeveloperTools } ?? false
        _ = browser.performPageTool(tool)
        guard opens, [.javaScriptConsole, .networkInspector, .inspectElements].contains(tool),
              let request = makeDeveloperModeRequest(), request.browser === browser,
              !DeveloperModePreferences.shared.isEnabled(host: request.host) else { return }
        do {
            try DeveloperModePreferences.shared.setEnabled(true, host: request.host)
            refreshDeveloperToolbars()
        } catch { showError(error) }
    }

    var canExportEaselImage: Bool { currentEaselEditor?.canExportImage == true }
    func exportEaselImage() { currentEaselEditor?.exportImage() }
    private var currentEaselEditor: EaselEditorViewController? {
        guard presentation.isReady, !isClosing, !wholeWindowClose, activePeek == nil, window?.isKeyWindow == true,
              let id = currentTabID, !transferringTabIDs.contains(id), renderedPaneIDs.contains(id) else { return nil }
        return easelEditors[id]?.editor
    }

    var readerActionTitle: String {
        switch currentBrowser?.readerMode ?? .inactive {
        case .distilling: return "Cancel Reader"
        case .viewing, .failedViewer: return "Exit Reader"
        case .unavailable: return "Try Reader Again"
        default: return "Enter Reader"
        }
    }

    func canToggleReaderMode() -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              let browser = currentBrowser else { return false }
        return browser.canToggleReaderMode()
    }

    @MainActor
    private final class ReaderMenuRequest {
        weak var owner: BrowserWindowController?
        weak var browser: PCBrowserView?
        let revision: UInt
        init(owner: BrowserWindowController, browser: PCBrowserView) {
            self.owner = owner
            self.browser = browser
            revision = browser.readerRevision
        }
    }

    func prepareReaderMenuItem(_ item: NSMenuItem) -> Bool {
        item.title = readerActionTitle
        item.representedObject = currentBrowser.map { ReaderMenuRequest(owner: self, browser: $0) }
        return canToggleReaderMode()
    }

    func toggleReaderMode(from item: NSMenuItem) {
        guard let request = item.representedObject as? ReaderMenuRequest,
              request.owner === self, let browser = request.browser,
              currentBrowser === browser, browser.readerRevision == request.revision,
              canToggleReaderMode() else { return }
        _ = browser.toggleReaderMode()
    }

    private func addReaderMenuItems(to menu: NSMenu) {
        let browser = currentBrowser
        let revision = browser?.readerRevision
        let item = MenuAction.item(readerActionTitle) { [weak self, weak browser] in
            guard let self, let browser, self.currentBrowser === browser,
                  browser.readerRevision == revision, self.canToggleReaderMode() else { return }
            _ = browser.toggleReaderMode()
        }
        item.isEnabled = canToggleReaderMode()
        menu.addItem(item)
        if let message = browser?.readerMessage, !message.isEmpty {
            let detail = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }
    }

    @MainActor
    private final class PageToolMenuRequest {
        weak var owner: BrowserWindowController?
        weak var browser: PCBrowserView?
        let revision: UInt
        let tool: PCNativePageTool
        init(owner: BrowserWindowController, browser: PCBrowserView, tool: PCNativePageTool) {
            self.owner = owner
            self.browser = browser
            revision = browser.readerRevision
            self.tool = tool
        }
    }

    @MainActor
    private final class ScriptPermissionMenuRequest {
        weak var owner: BrowserWindowController?
        weak var page: PCNativePage?
        init(owner: BrowserWindowController, page: PCNativePage) { self.owner = owner; self.page = page }
    }
    func prepareScriptPermissionMenuItem(_ item: NSMenuItem, preservingTarget: Bool) -> Bool {
        if preservingTarget {
            guard let request = item.representedObject as? ScriptPermissionMenuRequest,
                  request.owner === self, let page = request.page,
                  currentBrowser?.nativePage === page else { return false }
            item.state = page.appleEventJavaScriptAllowed ? .on : .off
            return page.canToggleAppleEventJavaScript
        }
        guard let page = currentBrowser?.nativePage else {
            item.representedObject = nil; item.state = .off; return false
        }
        item.representedObject = ScriptPermissionMenuRequest(owner: self, page: page)
        item.state = page.appleEventJavaScriptAllowed ? .on : .off
        return page.canToggleAppleEventJavaScript
    }
    func toggleScriptPermission(from item: NSMenuItem) {
        guard let request = item.representedObject as? ScriptPermissionMenuRequest,
              request.owner === self, let page = request.page,
              currentBrowser?.nativePage === page, page.canToggleAppleEventJavaScript else { return }
        _ = page.toggleAppleEventJavaScript()
        item.state = page.appleEventJavaScriptAllowed ? .on : .off
    }

    func preparePageToolMenuItem(_ item: NSMenuItem, tool: PCNativePageTool) -> Bool {
        item.representedObject = currentBrowser.map { PageToolMenuRequest(owner: self, browser: $0, tool: tool) }
        return canPerformPageTool(tool)
    }

    func performPageTool(from item: NSMenuItem) {
        guard let request = item.representedObject as? PageToolMenuRequest,
              request.owner === self, let browser = request.browser,
              currentBrowser === browser, browser.readerRevision == request.revision,
              canPerformPageTool(request.tool) else { return }
        runPageTool(request.tool, in: browser)
    }

    private func pageToolItem(_ title: String, tool: PCNativePageTool) -> NSMenuItem {
        let browser = currentBrowser
        let revision = browser?.readerRevision
        let item = MenuAction.item(title) { [weak self, weak browser] in
            guard let self, let browser, self.currentBrowser === browser,
                  browser.readerRevision == revision,
                  self.canPerformPageTool(tool) else { return }
            self.runPageTool(tool, in: browser)
        }
        item.isEnabled = canPerformPageTool(tool)
        if tool == .clearCacheAndRefresh {
            item.toolTip = "Reload this page without using cached resources."
        } else if tool == .clearCookiesAndRefresh {
            item.toolTip = "Clear this site's cookies, storage and cached data, then refresh. This may sign you out."
        }
        return item
    }

    private func setupFindBar() {
        findHost.isHidden = true; findField.delegate = self
        findHost.onPrevious = { [weak self] in self?.performFind(forward: false, next: true) }
        findHost.onNext = { [weak self] in self?.performFind(forward: true, next: true) }
        findHost.onClose = { [weak self] in self?.dismissFind() }
        menuObservers.append(NotificationCenter.default.addObserver(
            forName: PCNativePage.findResultDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let page = notification.object as? PCNativePage,
                      self.visibleFind?.owner === page else { return }
                self.reconcileFind()
            }
        })
    }
    private func layoutFindBar() {
        guard !findHost.isHidden, let state = visibleFind, isCurrentFind(state),
              libraryView == nil, nativeFullscreenTabID == nil,
              let page = state.owner, page.nativeView.window === window,
              !page.nativeView.isHiddenOrHasHiddenAncestor else { return }
        let pageFrame = page.nativeView.convert(page.nativeView.bounds, to: rootView)
        findHost.frame = PageFindView.frame(in: pageFrame.intersection(rootView.bounds))
    }
    private var canOwnFind: Bool {
        ownsSpaceCommandFocus && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && currentTabID.map { !closingTabIDs.contains($0) && !modelRetirementIDs.contains($0) } != false
            && window?.attachedSheet == nil && pageCapture == nil && tabSwitcher == nil
            && spaceCreation == nil && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
    }
    private func findState(for page: PCNativePage) -> BrowserFindState<PCNativePage> {
        if let state = findStates[page.identifier], state.matches(page, revision: page.readerRevision) { return state }
        let state = BrowserFindState(owner: page, revision: page.readerRevision)
        findStates[page.identifier] = state; return state
    }
    private func isCurrentFind(_ state: BrowserFindState<PCNativePage>) -> Bool {
        guard let page = state.owner, !page.isClosed else { return false }
        return state.matches(selectedNativePage(), revision: page.readerRevision)
    }
    private func reconcileFind() {
        if FindReconcileSkip.shouldSkip(isPresented: visibleFind != nil) { return }
        findStates = findStates.filter { _, state in
            guard let page = state.owner else { return false }
            return !page.isClosed && page.readerRevision == state.revision
        }
        if let visibleFind, !isCurrentFind(visibleFind) || libraryView != nil { dismissFind(restoreFocus: false) }
        guard let state = visibleFind, let page = state.owner else { return }
        let result = page.findResult
        let presentation = PageFindResultPresentation.resolve(query: state.query, revision: state.revision,
            resultQuery: result?.query, resultRevision: result?.documentRevision,
            matches: result?.numberOfMatches, ordinal: result?.activeMatchOrdinal)
        findHost.update(result: presentation, available: canOwnFind && isCurrentFind(state))
        layoutFindBar()
    }
    func prepareFindMenuItem(_ item: NSMenuItem, action: BrowserFindAction, preservingTarget: Bool = false) -> Bool {
        if preservingTarget, let command = item.representedObject as? BrowserFindCommand {
            return command.action == action && command.isAvailable
        }
        item.representedObject = nil
        guard canOwnFind, let window else { return false }
        let prepare: () -> Void = { [weak self] in self?.commandBar?.dismiss() }
        let command: BrowserFindCommand
        if let responder = window.firstResponder as? NSView, activePeek == nil,
           let entry = noteEditors.first(where: { $0.value.editor.isViewLoaded
               && responder.isDescendant(of: $0.value.editor.view) }),
           renderedPaneIDs.contains(entry.key), entry.value.profileID == activeProfileID {
            let id = entry.key, editor = entry.value.editor
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak editor, weak window] in
                guard let self, let editor, let window, self.canOwnFind, self.activePeek == nil,
                      let note = self.noteEditors[id], note.editor === editor,
                      self.renderedPaneIDs.contains(id), note.profileID == self.activeProfileID,
                      self.switcherCanUse(id), !editor.session.document.deleted,
                      let tab = self.store.state.tabs.first(where: { $0.id == id && $0.profileID == note.profileID }),
                      InternalPage(urlString: tab.url)?.noteID == note.documentID,
                      !editor.text.hasMarkedText(), !editor.titleText.hasMarkedText(),
                      let current = window.firstResponder as? NSView else { return false }
                return current.isDescendant(of: editor.view)
            }, prepare: prepare, execute: { [weak self, weak editor] in
                self?.dismissFind(restoreFocus: false); editor?.findInDocument()
            })
        } else if action.isNativeTextOnly {
            return false
        } else if action == .show, let libraryView {
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak libraryView] in
                self?.canOwnFind == true && libraryView != nil && self?.libraryView === libraryView
            }, prepare: prepare, execute: { [weak self, weak libraryView] in
                self?.dismissFind(restoreFocus: false); libraryView?.focusSearch()
            })
        } else if activePeek == nil, let id = currentTabID, renderedPaneIDs.contains(id),
                  let note = noteEditors[id], note.profileID == activeProfileID,
                  let tab = store.state.tabs.first(where: { $0.id == id && $0.profileID == note.profileID }),
                  InternalPage(urlString: tab.url)?.noteID == note.documentID {
            let editor = note.editor
            let sender = NSMenuItem(title: action.title, action: #selector(NSTextView.performTextFinderAction(_:)), keyEquivalent: "")
            sender.tag = action.rawValue
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak editor] in
                guard let self, let editor else { return false }
                return self.canOwnFind && self.activePeek == nil && self.currentTabID == id
                    && self.noteEditors[id]?.editor === editor && !editor.session.document.deleted
                    && !editor.text.hasMarkedText() && !editor.titleText.hasMarkedText()
                    && (action == .show || editor.text.validateMenuItem(sender))
            }, prepare: prepare, execute: { [weak self, weak editor] in
                guard let editor else { return }
                self?.dismissFind(restoreFocus: false)
                if action == .show { editor.findInDocument() }
                else { editor.text.performTextFinderAction(sender) }
            })
        } else {
            guard libraryView == nil, let page = selectedNativePage(), page.canFindInPage else { return false }
            let state = findState(for: page)
            command = BrowserFindCommand(action: action, window: window, available: { [weak self, weak page] in
                guard let self, let page, self.canOwnFind, self.libraryView == nil,
                      self.isCurrentFind(state), page.canFindInPage else { return false }
                switch action {
                case .show: return true
                case .next, .previous: return !state.query.isEmpty
                case .useSelection: return !page.selectionForFind.isEmpty
                case .jumpToSelection, .replace: return false
                }
            }, prepare: prepare, execute: { [weak self, weak page] in
                guard let self, let page, self.isCurrentFind(state) else { return }
                switch action {
                case .show:
                    self.visibleFind = state
                    if self.findField.stringValue != state.query { self.findField.stringValue = state.query }
                    self.rootView.addSubview(self.findHost, positioned: .above, relativeTo: nil)
                    self.findHost.isHidden = false; self.layoutChrome(); self.reconcileFind()
                    self.window?.makeFirstResponder(self.findField); self.findField.selectText(nil)
                case .next, .previous:
                    page.findText(state.query, forward: action == .next, findNext: true)
                case .useSelection:
                    let selection = page.selectionForFind
                    guard !selection.isEmpty else { return }
                    state.query = selection
                    if self.visibleFind === state { self.findField.stringValue = selection }
                    page.findText(selection, forward: true, findNext: false); self.reconcileFind()
                case .jumpToSelection, .replace: return
                }
            })
        }
        item.representedObject = command; return command.isAvailable
    }
    func findInPage() {
        let item = NSMenuItem(title: "Find…", action: nil, keyEquivalent: "")
        guard prepareFindMenuItem(item, action: .show) else { return }
        _ = (item.representedObject as? BrowserFindCommand)?.perform()
    }
    func dismissFind(restoreFocus: Bool = true) {
        let state = visibleFind; visibleFind = nil
        let mayRestore = state.map(isCurrentFind) ?? false
        findHost.isHidden = true; state?.owner?.stopFinding(); layoutChrome()
        if restoreFocus, mayRestore, window?.isKeyWindow == true, commandBar == nil {
            if let page = state?.owner { _ = nativeBinding?.requestFocus(for: page) }
        }
    }
    private func performFind(forward: Bool, next: Bool) {
        guard let state = visibleFind, isCurrentFind(state), let page = state.owner,
              page.canFindInPage, window?.isKeyWindow == true,
              (findField.currentEditor() as? NSTextInputClient)?.hasMarkedText() != true else { return }
        state.query = findField.stringValue
        if state.query.isEmpty { page.stopFinding() }
        else { page.findText(state.query, forward: forward, findNext: next) }
        reconcileFind()
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSTextField === findField { performFind(forward: true, next: false) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === findField, !textView.hasMarkedText() else { return false }
        if let action = BrowserFindAction.fieldAction(selector,
            shift: NSApp.currentEvent?.modifierFlags.contains(.shift) == true, composing: false) {
            performFind(forward: action == .next, next: true); return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismissFind(); return true }
        return false
    }

    private func refreshPaymentControls() {
        sharedQuotes.bind(isClosing || wholeWindowClose ? nil : selectedNativePage(), window: window)
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else {
            paymentFeedbackWork?.cancel(); paymentFeedbackWork = nil
            sidebar.updatePaymentEntry(title: nil, symbol: "creditcard", enabled: false, savedLabel: "")
            return
        }
        let actions = binding.paymentActions(for: page)
        let title = actions.count > 1 ? "Payment methods" : actions.first?.title
        let saved = actions.map(\.savedLabel).filter { !$0.isEmpty }.joined(separator: " · ")
        if sidebar.updatePaymentEntry(title: title, symbol: actions.first?.symbolName ?? "creditcard",
                                      enabled: actions.contains { $0.isEnabled }, savedLabel: saved) {
            sidebar.layoutSubtreeIfNeeded()
        }
        guard sidebarPresentation != .hidden, sidebar.isPaymentEntryVisible else { return }
        for action in actions where action.requiresPresentationAcknowledgment {
            _ = binding.paymentFeedbackPresented(action, for: page)
            guard !isClosing, !page.isClosed, nativeBinding === binding,
                  currentBrowser?.nativePage === page, sidebar.isPaymentEntryVisible else { return }
        }
        guard !saved.isEmpty else { return }
        NSAccessibility.post(element: sidebar, notification: .announcementRequested,
                             userInfo: [.announcement: saved, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        for action in actions where !action.savedLabel.isEmpty {
            _ = binding.paymentFeedbackPresented(action, for: page)
        }
        paymentFeedbackWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak binding, weak page] in
            guard let self, let binding, let page,
                  self.nativeBinding === binding, self.currentBrowser?.nativePage === page else { return }
            self.refreshPaymentControls()
        }
        paymentFeedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func performPaymentAction(_ action: PCNativePaymentAction,
                                      binding: PCNativeBrowserWindow, page: PCNativePage) {
        guard nativeBinding === binding, currentBrowser?.nativePage === page,
              !isClosing, !page.isClosed else { return }
        _ = binding.executePaymentAction(action, for: page)
    }

    private func paymentMenuItems() -> [NSMenuItem] {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return [] }
        return binding.paymentActions(for: page).map { action in
            let item = MenuAction.item(action.title) { [weak self, weak binding, weak page] in
                guard let self, let binding, let page else { return }
                self.performPaymentAction(action, binding: binding, page: page)
            }
            item.isEnabled = action.isEnabled
            return item
        }
    }

    private func showPaymentControls(anchor: NSView) {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return }
        let actions = binding.paymentActions(for: page)
        if actions.count == 1, let action = actions.first {
            performPaymentAction(action, binding: binding, page: page)
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        paymentMenuItems().forEach { menu.addItem($0) }
        guard !menu.items.isEmpty else { refreshPaymentControls(); return }
        if anchor.isDescendant(of: sidebar), !sidebar.isPresented {
            let page = hiddenSidebarAnchor
            menu.popUp(positioning: nil, at: page.menuPoint, in: page.view)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
        }
    }

    private var hiddenSidebarAnchor: (view: NSView, rect: NSRect, menuPoint: NSPoint) {
        let page: NSView = currentBrowser ?? pageHost
        let top = page.isFlipped ? page.bounds.minY : page.bounds.maxY - 1
        return (page, NSRect(x: page.bounds.minX, y: top, width: 1, height: 1),
                NSPoint(x: page.bounds.minX, y: page.isFlipped ? page.bounds.minY : page.bounds.maxY))
    }

    @objc(parcSitePermissionAnchorForPage:)
    func sitePermissionAnchor(forPage page: NSView) -> NSDictionary? {
        guard let current = currentBrowser, page === current || page.isDescendant(of: current) else { return nil }
        let anchor: NSView? = selectedBrowserToolbar?.siteControlCenterAnchor
            ?? (activePeek != nil ? nil : isPopupWindow ? popupChrome.pageControlsAnchor
                : sidebar.isPresented ? sidebar.pageControlsAnchor : nil)
        guard let anchor, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor else { return nil }
        if anchor === sidebar.pageControlsAnchor { holdAddressButtonsForPermissionPrompt() }
        return ["view": anchor, "rect": NSValue(rect: anchor.bounds),
                "edge": NSNumber(value: NSRectEdge.maxY.rawValue)]
    }
    private var addressPromptHolds: [ObjectIdentifier: AddressPopoverRevealHold] = [:]
    private func holdAddressButtonsForPermissionPrompt() {
        let owner = NSObject()
        let hold = AddressPopoverRevealHold { [weak self] in
            guard let self else { return }
            self.sidebar.setAddressPopover(owner, open: false)
            self.addressPromptHolds[ObjectIdentifier(owner)] = nil
        }
        addressPromptHolds[ObjectIdentifier(owner)] = hold
        sidebar.setAddressPopover(owner, open: true)
    }

    func nativeBrowserPaymentActionsDidChange(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding else { return }
        refreshPaymentControls()
    }

    private func extensionControlItems() -> [ExtensionControlItem] {
        guard !isClosing, let binding = nativeBinding,
              let page = currentBrowser?.nativePage, !page.isClosed else { return [] }
        return extensionControlItems(actions: binding.extensionActions(for: page), binding: binding, page: page)
    }

    private func extensionControlItems(actions: [PCNativeExtensionAction],
                                       binding: PCNativeBrowserWindow,
                                       page: PCNativePage) -> [ExtensionControlItem] {
        actions.map { action in
            ExtensionControlItem(identifier: action.identifier, name: action.name,
                tooltip: action.tooltip, accessibilityLabel: action.accessibilityLabel,
                image: action.icon, pinnedIndex: action.pinnedIndex == NSNotFound ? nil : Int(action.pinnedIndex),
                canChangePin: action.canChangePin,
                execute: { [weak self, weak binding, weak page] in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !page.isClosed else { return }
                    self.performExtensionActionAfterDismissingControls {
                        _ = binding.executeExtensionAction(action, for: page)
                    }
                }, showContextMenu: { [weak self, weak binding, weak page] control in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !self.wholeWindowClose, !page.isClosed else { return }
                    self.showExtensionContextMenu(action, binding: binding, page: page, beside: control)
                }, setPinned: { [weak self, weak binding, weak page] pinned in
                    guard let self, let binding, let page,
                          self.nativeBinding === binding, self.currentBrowser?.nativePage === page,
                          !self.isClosing, !page.isClosed else { return }
                    _ = binding.setExtensionAction(action, pinned: pinned, for: page)
                    self.refreshExtensionControls()
                },
                pinnedArtwork: ExtensionPinnedArtwork(
                    unbadged: action.responds(to: #selector(getter: PCNativeExtensionAction.iconWithoutBadge))
                        ? action.iconWithoutBadge : nil,
                    badgeText: action.badgeText, textColor: action.badgeTextColor,
                    backgroundColor: action.badgeBackgroundColor),
                badgeText: action.badgeText)
        }
    }

    private func extensionControlsSignature(page: PCNativePage?,
                                            actions: [PCNativeExtensionAction],
                                            sidebarOwns: Bool,
                                            popupAvailable: Bool?) -> String {
        let pagePart = page.map { "p:\(ObjectIdentifier($0)):\($0.identifier)" } ?? "p:-"
        let avail = popupAvailable.map { $0 ? "1" : "0" } ?? "-"
        var parts: [String] = [
            pagePart,
            "s\(sidebarOwns ? 1 : 0)",
            "a\(avail)",
            "g\(actions.first?.generation ?? 0)",
        ]
        for action in actions {
            let pin = action.pinnedIndex == NSNotFound ? "-" : String(action.pinnedIndex)
            parts.append([
                action.identifier,
                action.name,
                action.tooltip,
                action.accessibilityLabel,
                pin,
                action.isEnabled ? "1" : "0",
                action.canChangePin ? "1" : "0",
            ].joined(separator: "\u{1f}"))
        }
        return parts.joined(separator: ";")
    }

    private func extensionControlsPopupAvailable(binding: PCNativeBrowserWindow?,
                                                 page: PCNativePage?) -> Bool? {
        guard isPopupWindow else { return nil }
        guard let binding, let page, !page.isClosed,
              binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:))) else {
            return false
        }
        return binding.hasEnabledExtensions(for: page)
    }

    private func showExtensionContextMenu(_ action: PCNativeExtensionAction, binding: PCNativeBrowserWindow,
                                          page: PCNativePage, beside control: NSView) {
        extensionActionGeneration = UUID()
        guard binding.responds(to: #selector(PCNativeBrowserWindow.showExtensionActionContextMenu(_:for:presenter:))),
              let window = control.window, window.isVisible else {
            _ = binding.showExtensionActionContextMenu(action, for: page)
            return
        }
        let show = { (menu: ParcContextMenu) in _ = binding.showExtensionActionContextMenu(action, for: page, presenter: menu) }
        if siteControlCenter?.presentExtensionMenu(beside: control, for: action.identifier, show) == true { return }
        let rect = window.convertToScreen(control.convert(control.bounds, to: nil))
        let screen = SiteControlCenterPlacement.screen(at: CGPoint(x: rect.midX, y: rect.midY)) ?? window.screen?.visibleFrame
        let menu = ParcContextMenu(anchor: rect, regions: SiteControlCenterPlacement.regions(window: window.frame, screen: screen),
                                  parent: window, colors: ParcMenuColors(theme: rootView.theme))
        let inSidebar = control.isDescendant(of: sidebar)
        if inSidebar { sidebar.setAddressPopover(menu, open: true) }
        if let center = siteControlCenter { center.keepingOpen { show(menu) } } else { show(menu) }
        if inSidebar { sidebar.setAddressPopover(menu, open: false) }
    }

    private func performExtensionActionAfterDismissingControls(_ action: @escaping () -> Void) {
        guard !isClosing, !wholeWindowClose, let window, let binding = nativeBinding,
              let browser = currentBrowser, let page = browser.nativePage, !page.isClosed else { return }
        let generation = UUID()
        extensionActionGeneration = generation
        let revision = browser.readerRevision
        let spaceID = activeSpaceID
        dismissSiteControlCenter { [weak self, weak window, weak binding, weak browser, weak page] in
            guard let self, let window, let binding, let browser, let page,
                  self.extensionActionGeneration == generation, !self.isClosing, !self.wholeWindowClose,
                  self.window === window, window.isKeyWindow, binding.window === window,
                  self.nativeBinding === binding, self.currentBrowser === browser,
                  self.activeSpaceID == spaceID, browser.nativePage === page, !page.isClosed,
                  browser.readerRevision == revision else { return }
            self.extensionActionGeneration = UUID()
            action()
        }
    }

    private func refreshExtensionControls() {
        if siteControlCenter != nil && (extensionControlsPage !== currentBrowser?.nativePage
            || currentBrowser?.readerRevision != siteControlCenterRevision
            || siteControlCenterOwner.map { $0.space != activeSpaceID || $0.profile != activeProfileID } ?? false) {
            dismissSiteControlCenter()
        }
        let page: PCNativePage? = {
            guard !isClosing, let page = currentBrowser?.nativePage, !page.isClosed else { return nil }
            return page
        }()
        let binding = nativeBinding
        let sidebarOwns = sidebarShowsAddressBar
        let popupAvailable = extensionControlsPopupAvailable(binding: binding, page: page)
        let actions: [PCNativeExtensionAction]
        if let binding, let page {
            actions = binding.extensionActions(for: page)
        } else {
            actions = []
        }
        let signature = extensionControlsSignature(page: page, actions: actions,
                                                   sidebarOwns: sidebarOwns,
                                                   popupAvailable: popupAvailable)
        if signature == lastExtensionControlsSignature {
            if let siteControlCenter, let sccPage = extensionControlsPage {
                updateSiteControlCenter(siteControlCenter, page: sccPage, items: nil)
            }
            return
        }
        lastExtensionControlsSignature = signature

        let items: [ExtensionControlItem]
        if let binding, let page {
            items = extensionControlItems(actions: actions, binding: binding, page: page)
        } else {
            items = []
        }
        if isPopupWindow {
            popupChrome.updateExtensions(available: popupAvailable ?? false)
        }
        sidebar.extensionToolbar.update(sidebarOwns ? items : [])
        selectedBrowserToolbar?.updateExtensionItems(items)
        if let siteControlCenter, let sccPage = extensionControlsPage {
            updateSiteControlCenter(siteControlCenter, page: sccPage, items: items)
        }
    }

    private func preparePopupSiteControls(requireExtensions: Bool) -> (() -> Bool)? {
        guard isPopupWindow, presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              let window, window.isKeyWindow, windowCommandSecurityAvailable,
              let browser = currentBrowser, browser.window === window, let page = browser.nativePage, !page.isClosed,
              let binding = nativeBinding else { return nil }
        if requireExtensions && (!binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:)))
            || !binding.hasEnabledExtensions(for: page)) { return nil }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        var used = false
        return { [weak self, weak window, weak browser, weak page, weak binding] in
            guard !used, let self, let window, let browser, let page, let binding,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  self.window === window, window.isKeyWindow, self.windowCommandSecurityAvailable,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID,
                  self.nativeBinding === binding, self.currentBrowser === browser, browser.window === window,
                  browser.nativePage === page, browser.readerRevision == revision, !page.isClosed else { return false }
            if requireExtensions && (!binding.responds(to: #selector(PCNativeBrowserWindow.hasEnabledExtensions(for:)))
                || !binding.hasEnabledExtensions(for: page)) { return false }
            used = true
            self.showSiteControlCenter(from: self.popupChrome.pageControlsAnchor)
            return true
        }
    }

    private func showSiteControlCenter(from sourceAnchor: NSView? = nil, picker: Bool = false) {
        guard presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              let initialWindow = window, initialWindow.isKeyWindow, windowCommandSecurityAvailable else { return }
        extensionActionGeneration = UUID()
        if let open = siteControlCenter, open.isShown {
            if picker && open.model.focusedExtension == nil && !open.model.extensions.isEmpty { open.beginPicker(); return }
            dismissSiteControlCenter(); return
        }
        guard let browser = currentBrowser, let page = browser.nativePage, !page.isClosed else {
            dismissSiteControlCenter()
            if !picker, window === initialWindow, initialWindow.isKeyWindow, windowCommandSecurityAvailable { showPageMenu() }
            return
        }
        let revision = browser.readerRevision, profileID = activeProfileID, spaceID = activeSpaceID
        dismissSiteControlCenter()
        guard let originalWindow = window, originalWindow === initialWindow,
              presentation.isReady, !isClosing, !wholeWindowClose, !windowClosePending,
              originalWindow.isKeyWindow, windowCommandSecurityAvailable,
              activeProfileID == profileID, activeSpaceID == spaceID, currentBrowser === browser,
              browser.nativePage === page, !page.isClosed, browser.readerRevision == revision,
              siteControlCenter == nil else { return }
        let controller = SiteControlCenterController(model: SiteControlCenterModel())
        let canShow: () -> Bool = { [weak self, weak controller, weak originalWindow, weak browser, weak page] in
            guard let self, let controller, let originalWindow, let browser, let page,
                  self.siteControlCenter === controller, self.window === originalWindow,
                  self.presentation.isReady, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending,
                  originalWindow.isKeyWindow, self.windowCommandSecurityAvailable,
                  self.activeProfileID == profileID, self.activeSpaceID == spaceID,
                  self.currentBrowser === browser, browser.window === originalWindow,
                  browser.nativePage === page, !page.isClosed, browser.readerRevision == revision else { return false }
            return true
        }
        siteControlCenter = controller
        extensionControlsPage = page
        siteControlCenterRevision = browser.readerRevision
        siteControlCenterOwner = (spaceID, profileID)
        updateSiteControlCenter(controller, page: page, items: extensionControlItems())
        wireSiteControlCenter(controller, browser: browser, page: page)
        controller.onClose = { [weak self, weak controller, weak page] in
            guard let self, let controller, self.siteControlCenter === controller else { return }
            self.siteControlCenterDismissal.track(controller)
            self.siteControlCenter = nil; self.extensionControlsPage = nil
            self.siteControlCenterItems = [:]; self.siteControlCenterPermissions = []
            self.siteControlCenterPermissionTargets = [:]; self.siteControlCenterRevision = nil
            self.siteControlCenterOwner = nil; self.siteControlCenterPageTools = []
            self.sidebar.setAddressPopover(controller, open: false)
            if page?.responds(to: #selector(PCNativePage.closeSiteControls)) == true { page?.closeSiteControls() }
            self.refreshSidebarPointerIfKey()
        }
        controller.onDetach = { [weak self, weak controller] in
            guard let self, let controller, self.siteControlCenter === controller else { return }
            self.sidebar.setAddressPopover(controller, open: false)
        }
        if browser.hasPageInfo, page.responds(to: #selector(PCNativePage.openSiteControls(handler:))) {
            _ = page.openSiteControls { [weak self, weak controller, weak page] rows in
                guard let self, let controller, let page, self.siteControlCenter === controller else { return }
                guard let rows else { self.dismissSiteControlCenter(); return }
                self.siteControlCenterPermissions = rows
                self.updateSiteControlCenter(controller, page: page, items: nil)
            }
        }
        if let anchor = sourceAnchor ?? (isPopupWindow ? popupChrome.pageControlsAnchor : sidebar.isPresented ? sidebar.pageControlsAnchor : nil) {
            let pill = sourceAnchor == nil && !isPopupWindow
            if anchor === sidebar.pageControlsAnchor { sidebar.setAddressPopover(controller, open: true) }
            controller.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY,
                            after: pill ? .milliseconds(anchor.isHiddenOrHasHiddenAncestor ? 100 : 10) : nil,
                            expectedWindow: originalWindow, when: canShow)
        } else {
            let page = hiddenSidebarAnchor
            controller.show(relativeTo: page.rect, of: page.view, preferredEdge: page.view.isFlipped ? .maxY : .minY,
                            expectedWindow: originalWindow, when: canShow)
        }
        if picker { controller.beginPicker() }
    }

    private func dismissSiteControlCenter(then action: (() -> Void)? = nil) {
        siteControlCenterDismissal.close(siteControlCenter, then: action)
    }
    private func dismissSiteControlCenter(when valid: @escaping () -> Bool, then action: @escaping () -> Void) {
        siteControlCenterDismissal.close(siteControlCenter, when: valid, then: action)
    }

    private func updateSiteControlCenter(_ controller: SiteControlCenterController, page: PCNativePage,
                                         items: [ExtensionControlItem]?) {
        let model = controller.model
        let canCopy = canCopyCurrentURL
        model.canCopy = canCopy
        model.canShare = canSharePage
        model.captureAvailable = privateCaptureContextIsValid
        if window?.isKeyWindow == true {
            model.canCapture = canCapturePage
            siteControlCenterPageTools = Set([PCNativePageTool.developerTools, .clearCacheAndRefresh,
                                              .clearCookiesAndRefresh].filter(canPerformPageTool))
        }
        controller.theme = rootView.theme
        updateSiteControlCenterShortcuts()
        if let items {
            siteControlCenterItems = Dictionary(items.map { ($0.identifier, $0) }) { $1 }
            let extensions = items.map {
                SiteControlCenterModel.Extension(id: $0.identifier, name: $0.name, tooltip: $0.tooltip,
                    accessibilityLabel: $0.accessibilityLabel, icon: $0.pinnedArtwork?.image ?? $0.image,
                    isPinned: $0.pinnedIndex != nil, canChangePin: $0.canChangePin,
                    badge: $0.pinnedArtwork?.badge, badgeText: $0.badgeText)
            }
            if model.extensions != extensions { model.extensions = extensions }
            if let focused = model.focusedExtension, !extensions.contains(where: { $0.id == focused }) {
                model.focusedExtension = extensions.first?.id
            }
        }
        let internalPage = ["chrome", "parc"].contains(page.url?.scheme?.lowercased() ?? "parc")
            || WhatsNewPage.matches(page.url?.absoluteString ?? "")
        model.isSecure = internalPage ? nil : page.developerModeSecure
        let settings = siteControlCenterSettings(page: page)
        if model.settings != settings { model.settings = settings }
    }

    private func updateSiteControlCenterShortcuts() {
        guard let model = siteControlCenter?.model else { return }
        let shortcuts = KeyboardShortcuts.shared
        model.shortcuts = Dictionary(uniqueKeysWithValues: SiteControlCenterModel.Button.allCases.compactMap { button in
            button.commandID.map { (button, shortcuts.activeShortcut(for: $0)?.display ?? "") }
        })
    }

    private func shortcutTooltipDiscoveryFingerprint() -> String {
        let shortcuts = KeyboardShortcuts.shared
        return ShortcutTooltipDiscoverySkip.fingerprint(
            copyURLTooltip: LiveShortcutToolTip.text("Copy URL", commandID: "copyCurrentURL:"),
            copyURLShortcut: shortcuts.activeShortcut(for: "copyCurrentURL:")?.display ?? "",
            captureShortcut: shortcuts.activeShortcut(for: "capturePage:")?.display ?? "",
            captureVisiblePageShortcut: shortcuts.activeShortcut(for: "captureVisiblePage:")?.display ?? "",
            captureFullPageShortcut: shortcuts.activeShortcut(for: "captureFullPage:")?.display ?? ""
        )
    }

    private func siteControlCenterSettings(page: PCNativePage) -> [SiteControlCenterModel.Setting] {
        typealias Setting = SiteControlCenterModel.Setting
        var rows: [Setting] = []
        let host = page.developerModeSiteHost
        let secure = page.developerModeHost != nil && page.developerModeSecure
        if secure, let url = currentBrowser?.url, SidebarRecentDomain.matching(url) != nil {
            let enabled = SidebarPreviewPreference.recentPages.isEnabled
            rows.append(Setting(id: "preview", symbol: "filemenu.and.cursorarrow", symbolSize: 14, symbolWeight: .bold,
                                title: "Preview", subtitle: enabled ? "Enabled" : "Disabled", isOn: enabled, isEnabled: true))
        }
        if let host, !isPrivateBrowsing, !DeveloperModePreferences.shared.loadError {
            let enabled = DeveloperModePreferences.shared.isEnabled(host: host)
            rows.append(Setting(id: "developerMode", symbol: "hammer.fill", symbolSize: 13, symbolWeight: .medium,
                                title: "Developer Mode", subtitle: enabled ? "On" : "Off", isOn: enabled,
                                isEnabled: siteControlCenterPageTools.contains(.developerTools)))
        }
        siteControlCenterPermissionTargets = [:]
        guard secure else { return rows }
        let permissions = siteControlCenterPermissions.filter { $0["autoPictureInPicture"] as? Bool == true }
            + siteControlCenterPermissions.filter { $0["autoPictureInPicture"] as? Bool != true }
        for row in permissions {
            guard let title = row["title"] as? String, let key = row["key"] as? String,
                  let index = row["index"] as? Int, let revision = row["revision"] as? UInt else { continue }
            let allowed = row["allowed"] as? Bool ?? false
            let id = "permission:" + key
            siteControlCenterPermissionTargets[id] = (index, revision)
            rows.append(Setting(id: id, symbol: "gearshape.fill", symbolSize: 13,
                                symbolWeight: .medium, title: title, subtitle: allowed ? "Allowed" : "Blocked",
                                isOn: allowed, isEnabled: row["changeable"] as? Bool ?? false))
        }
        return rows
    }

    private func wireSiteControlCenter(_ controller: SiteControlCenterController, browser: PCBrowserView, page: PCNativePage) {
        let model = controller.model
        let revision = browser.readerRevision
        let profileID = activeProfileID, spaceID = activeSpaceID, parent = window
        let current: () -> Bool = { [weak self, weak browser, weak page, weak parent] in
            guard let self, let browser, let page, let parent,
                  !self.isClosing, !self.wholeWindowClose, !page.isClosed else { return false }
            return self.window === parent && browser.window === parent
                && self.activeProfileID == profileID && self.activeSpaceID == spaceID
                && self.currentBrowser === browser && browser.nativePage === page && browser.readerRevision == revision
        }
        let currentPresentation: () -> Bool = { [weak self, weak controller] in
            guard current(), let self, let controller else { return false }
            return self.siteControlCenter === controller
        }
        model.onButton = { [weak self, weak controller] button in
            guard currentPresentation(), let self, let controller else { return }
            switch button {
            case .share:
                guard let url = self.sharePageTarget?.url, let (rect, view) = controller.rect(for: .share) else { return }
                NSSharingServicePicker(items: [url]).show(relativeTo: rect, of: view, preferredEdge: .minY)
            case .copyURL: self.dismissSiteControlCenter { [weak self] in self?.copyCurrentURL() }
            case .capture: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.region) }
            case .captureFullPage: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.fullPage) }
            case .captureVisiblePage: self.dismissSiteControlCenter(when: current) { [weak self] in self?.capturePage(.viewport) }
            }
        }
        model.onExtension = { [weak self] id in
            guard currentPresentation(), let self else { return }
            self.siteControlCenterItems[id]?.execute()
        }
        controller.preparePickerSelection = { [weak self] in
            guard currentPresentation(), let self else { return nil }
            let items = self.siteControlCenterItems
            return { id in items[id]?.execute() }
        }
        model.onExtensionContextMenu = { [weak self, weak controller] id in
            guard currentPresentation(), let self, let tile = controller?.tile(for: id) else { return }
            self.siteControlCenterItems[id]?.showContextMenu(tile)
        }
        model.onExtensionPin = { [weak self] id in
            guard currentPresentation(), let self, let item = self.siteControlCenterItems[id], item.canChangePin else { return }
            item.setPinned(item.pinnedIndex == nil)
        }
        let afterDismissal: () -> Bool = { [weak self, weak parent] in
            guard current(), let self, let parent, parent.isKeyWindow else { return false }
            return self.windowCommandSecurityAvailable
        }
        let openExtensionDestination: (String) -> Void = { [weak self] address in
            guard let self, afterDismissal(), let url = URL(string: address) else { return }
            self.openAddress(url)
        }
        model.onManageExtensions = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { openExtensionDestination("parc://extensions/") }
        }
        model.onAddExtension = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter(when: afterDismissal) { openExtensionDestination("https://chromewebstore.google.com/category/extensions") }
        }
        model.onSetting = { [weak self, weak controller, weak page] id in
            guard currentPresentation(), let self, let controller, let page else { return }
            self.toggleSiteControlCenterSetting(id, page: page, afterDismissal: afterDismissal)
            if currentPresentation() { self.updateSiteControlCenter(controller, page: page, items: nil) }
        }
        model.onSiteSettings = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.dismissSiteControlCenter { [weak self] in self?.openSiteControlCenterSiteSettings() }
        }
        model.onSecurity = { [weak self, weak browser, weak page] in
            guard currentPresentation(), let self, let browser, let page else { return }
            if page.responds(to: #selector(PCNativePage.showCertificate)) {
                guard page.canShowCertificate else { return }
                self.dismissSiteControlCenter(when: afterDismissal) { [weak page] in _ = page?.showCertificate() }
                return
            }
            let anchor: NSView = self.isPopupWindow ? self.popupChrome.pageControlsAnchor :
                self.sidebar.isPresented ? self.sidebar.pageControlsAnchor : browser
            self.dismissSiteControlCenter { [weak self, weak browser, weak anchor] in
                guard let self, let browser, self.currentBrowser === browser, browser.canShowSiteInfo else { return }
                _ = browser.showSiteInfo(from: self.selectedBrowserToolbar?.siteControlCenterAnchor ?? anchor ?? browser)
            }
        }
        model.onMore = { [weak self] in
            guard currentPresentation(), let self else { return }
            self.siteControlCenterMoreMenu(current: currentPresentation, afterDismissal: afterDismissal,
                                           openExtensionDestination: openExtensionDestination)
                .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func toggleSiteControlCenterSetting(_ id: String, page: PCNativePage, afterDismissal: @escaping () -> Bool) {
        switch id {
        case "preview":
            SidebarPreviewPreference.recentPages.isEnabled.toggle()
        case "developerMode":
            dismissSiteControlCenter(when: afterDismissal) { [weak self, weak page] in
                guard let self, let page, let host = page.developerModeSiteHost, !self.isPrivateBrowsing,
                      self.canPerformPageTool(.developerTools),
                      let browser = self.currentBrowser, browser.nativePage === page else { return }
                self.setDeveloperMode(!DeveloperModePreferences.shared.isEnabled(host: host), host: host, browser: browser, page: page)
            }
        default:
            guard let (index, revision) = siteControlCenterPermissionTargets[id],
                  page.responds(to: #selector(PCNativePage.toggleSiteControlsPermission(_:revision:))) else { return }
            _ = page.toggleSiteControlsPermission(index, revision: revision)
        }
    }

    private func siteControlCenterMoreMenu(current: @escaping () -> Bool,
                                           afterDismissal: @escaping () -> Bool,
                                           openExtensionDestination: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let close: (@escaping () -> Void) -> Void = { [weak self] action in
            guard let self, current() else { return }
            self.dismissSiteControlCenter(when: afterDismissal, then: action)
        }
        for (title, tool) in [("Clear Cache", PCNativePageTool.clearCacheAndRefresh), ("Clear Cookies", .clearCookiesAndRefresh)] {
            let item = MenuAction.item(title) { [weak self] in
                close { self?.performPageTool(tool) }
            }
            item.isEnabled = siteControlCenterPageTools.contains(tool)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Manage Extensions…") {
            close { openExtensionDestination("parc://extensions/") }
        })
        menu.addItem(MenuAction.item("Add Extension…") {
            close { openExtensionDestination("https://chromewebstore.google.com/category/extensions") }
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("All Site Settings…") { [weak self] in
            close { self?.openSiteControlCenterSiteSettings() }
        })
        return menu
    }

    private func openSiteControlCenterSiteSettings() {
        guard let url = currentBrowser?.url, let scheme = url.scheme, let host = url.host,
              ["http", "https"].contains(scheme.lowercased()) else { openAddress(URL(string: "parc://settings/content")!); return }
        let origin = scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
        var components = URLComponents(string: "parc://settings/content/siteDetails")
        components?.queryItems = [URLQueryItem(name: "site", value: origin)]
        openAddress(components?.url ?? URL(string: "parc://settings/content")!)
    }

    func openExtensionPicker() {
        guard presentation.isReady, !isClosing, !wholeWindowClose, commandBar == nil else { return }
        showSiteControlCenter(from: selectedBrowserToolbar?.siteControlCenterAnchor,
                              picker: NSEvent.modifierFlags.contains(.command))
    }
    var canOpenExtensionPicker: Bool {
        presentation.isReady && !isClosing && !wholeWindowClose && commandBar == nil
            && currentBrowser?.nativePage.map { !$0.isClosed } == true && !extensionControlItems().isEmpty
    }

    func nativeBrowserExtensionActionsDidChange(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding else { return }
        refreshExtensionControls()
        commandBar?.reconcileExtensionActions()
    }

    func nativeBrowserExtensionPopupAnchor(_ browser: PCNativeBrowserWindow) -> PCNativeExtensionPopupAnchor {
        guard browser === nativeBinding else { return .window() }
        if sidebar.isPresented && sidebarShowsAddressBar {
            return .sidebar(width: sidebarContainer.bounds.width)
        }
        if let peek = activePeek, peek.view.content.window === window {
            return .focusedView(peek.view.content)
        }
        if let id = currentTabID, let pane = panes[id], pane.window === window {
            return .focusedView(pane)
        }
        return .window()
    }

    private func showPageMenu(from sourceAnchor: NSView? = nil) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if isPopupWindow {
            let openControls = preparePopupSiteControls(requireExtensions: false)
            let item = MenuAction.item("Site Control Center…") { _ = openControls?() }
            item.isEnabled = openControls != nil
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if let binding = nativeBinding, let page = currentBrowser?.nativePage,
           let action = binding.openAppAction(for: page) {
            menu.addItem(MenuAction.item(action.title) { [weak self, weak binding, weak page] in
                guard let self, let binding, let page, !self.isClosing,
                      self.nativeBinding === binding, self.currentBrowser?.nativePage === page else { return }
                _ = binding.executeOpenAppAction(action, for: page)
            })
            menu.addItem(.separator())
        }
        if let browser = currentBrowser {
            let revision = browser.readerRevision
            let info = MenuAction.item("Site Settings and Security…") { [weak self, weak browser] in
                guard let self, let browser, self.presentation.isReady,
                      !self.isClosing, !self.wholeWindowClose,
                      self.currentBrowser === browser, browser.readerRevision == revision,
                      browser.canShowSiteInfo else { return }
                let anchor: NSView = self.isPopupWindow ? self.popupChrome.pageControlsAnchor :
                    self.sidebar.isPresented ? self.sidebar.pageControlsAnchor : browser
                _ = browser.showSiteInfo(from: anchor)
            }
            info.isEnabled = presentation.isReady && !isClosing && !wholeWindowClose && browser.canShowSiteInfo
            menu.addItem(info)
        }
        let paymentItems = paymentMenuItems()
        paymentItems.forEach { menu.addItem($0) }
        if !paymentItems.isEmpty { menu.addItem(.separator()) }
        if let peek = activePeek {
            let expand = MenuAction.item("Open Peek as Tab") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek else { return }; self.promotePeek(peek, split: false)
            }
            expand.isEnabled = !peek.closePending
            menu.addItem(expand)
            let split = MenuAction.item("Add Peek to Split View") { [weak self, weak peek] in
                guard let self, let peek, self.activePeek === peek else { return }; self.promotePeek(peek, split: true)
            }
            split.isEnabled = peek.canSplit?() == true; menu.addItem(split)
            menu.addItem(MenuAction.item("Close Peek") { [weak peek] in peek?.requestDismiss(.closeButton) })
        } else if !isPopupWindow {
            let add = MenuAction.item("Add Split View") { [weak self] in self?.toggleSplit() }
            add.isEnabled = splitCommandIsAvailable(.add(.addAfter)) && splitInsertion == nil
            menu.addItem(add)
        }
        if activePeek == nil, let layout = activeSplitLayout {
            let directions = NSMenu(title: "Split Layout")
            for (title, orientation) in [("Side by Side", SplitOrientation.horizontal), ("Stacked", SplitOrientation.vertical)] {
                let item = splitMenuItem(title, command: .orientation(orientation))
                item.state = layout.orientation == orientation ? .on : .off
                directions.addItem(item)
            }
            let layoutItem = NSMenuItem(title: "Split Layout", action: nil, keyEquivalent: "")
            layoutItem.submenu = directions; menu.addItem(layoutItem)
            menu.addItem(splitMenuItem("Expand Current Split", command: .expand))
            menu.addItem(splitMenuItem("Separate Page from Split View", command: .separate))
            menu.addItem(splitMenuItem("Close this Split Pane", command: .close))
            menu.addItem(.separator())
        }
        menu.addItem(MenuAction.item("Find in page…") { [weak self] in self?.findInPage() })
        let copyBrowser = currentBrowser
        let copyRevision = copyBrowser?.readerRevision
        let copy = MenuAction.item("Copy URL") { [weak self, weak copyBrowser] in
            guard let self, let copyBrowser, self.currentBrowser === copyBrowser,
                  copyBrowser.readerRevision == copyRevision else { return }
            self.copyCurrentURL()
        }
        copy.isEnabled = canCopyCurrentURL; menu.addItem(copy)
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Zoom in") { [weak self] in self?.zoomIn() })
        menu.addItem(MenuAction.item("Zoom out") { [weak self] in self?.zoomOut() })
        menu.addItem(MenuAction.item("Actual size") { [weak self] in self?.actualSize() })
        menu.addItem(.separator())
        addReaderMenuItems(to: menu)
        menu.addItem(captureMenuItem("Capture Portion…", mode: .region))
        menu.addItem(captureMenuItem("Capture Visible Area", mode: .viewport))
        menu.addItem(captureMenuItem("Capture Full Page", mode: .fullPage))
        menu.addItem(pageToolItem("Print…", tool: .print))
        menu.addItem(pageToolItem("Save Page As…", tool: .save))
        menu.addItem(pageToolItem("Cast", tool: .cast))
        menu.addItem(pageToolItem("View Source", tool: .viewSource))
        menu.addItem(.separator())
        menu.addItem(pageToolItem("Clear Cache and Refresh", tool: .clearCacheAndRefresh))
        menu.addItem(pageToolItem("Clear Cookies and Refresh", tool: .clearCookiesAndRefresh))
        menu.addItem(pageToolItem("Clear Browsing Data…", tool: .clearBrowsingData))
        menu.addItem(.separator())
        menu.addItem(pageToolItem("Developer Tools", tool: .developerTools))
        menu.addItem(pageToolItem("Inspect Elements", tool: .inspectElements))
        menu.addItem(pageToolItem("JavaScript Console", tool: .javaScriptConsole))
        menu.addItem(pageToolItem("Network Inspector", tool: .networkInspector))
        let developer = NSMenuItem(title: developerModeTitle, action: nil, keyEquivalent: "")
        let developerRequest = makeDeveloperModeRequest()
        developer.representedObject = developerRequest
        developer.target = self; developer.action = #selector(toggleDeveloperModeMenuItem(_:))
        developer.isEnabled = developerRequest != nil
        menu.addItem(developer)
        if isPopupWindow {
            menu.addItem(MenuAction.item("Downloads") { [weak self] in self?.showDownloads() })
        }
        menu.addItem(MenuAction.item("Settings…") { [weak self] in self?.showSettings() })
        if sourceAnchor == nil, !isPopupWindow, !sidebar.isPresented {
            let page = hiddenSidebarAnchor
            menu.popUp(positioning: nil, at: page.menuPoint, in: page.view); return
        }
        let anchor: NSView = sourceAnchor ?? (isPopupWindow ? popupChrome.pageControlsAnchor : sidebar)
        let point = sourceAnchor != nil || isPopupWindow ? NSPoint(x: 0, y: anchor.bounds.height) : NSPoint(x: sidebar.bounds.width - 35, y: 80)
        menu.popUp(positioning: nil, at: point, in: anchor)
    }

    var isCreatingSpace: Bool { spaceCreation != nil }
    private var newSpaceWait = 0
    private var newSpaceWaitActive = false

    func createSpace() {
        if let session = spaceCreation { session.view.focusName(); return }
        guard !isPrivateBrowsing, !isPopupWindow, !store.isEphemeral else { return }
        window?.makeKeyAndOrderFront(nil)
        let press = NewSpaceBlockerWait.press(peek: newSpaceBlockingPeekState, waitActive: newSpaceWaitActive)
        guard press != .bringForward else { return }
        if press == .dismissAndWait, presentation.isReady { dismissForNewSpaceForm() }
        newSpaceWait &+= 1
        newSpaceWaitActive = true
        presentNewSpaceForm(attemptsLeft: 40, wait: newSpaceWait)
    }

    private func dismissForNewSpaceForm() {
        closeLibrary(restoreFocus: false)
        commandBar?.dismiss()
        pageCapture?.dismiss(restoreFocus: false)
        if !findHost.isHidden { dismissFind(restoreFocus: false) }
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss()
        favoriteRename?.cancel(); favoriteSplitRename?.cancel(); splitIconPicker?.cancel()
        sidebar.cancelSpaceNameEditing()
        if let peek = activePeek { peek.requestDismiss(.closeShortcut) }
        if siteControlCenter != nil { dismissSiteControlCenter() }
    }

    private var newSpaceBlockingPeekState: NewSpaceBlockerWait.PeekState {
        guard let peek = activePeek else { return .none }
        switch peek.modalPhase {
        case .awaitingDismissConfirmation: return .awaitingConfirmation
        case .dismissing: return .closing
        case .presented: return .open
        }
    }

    private func presentNewSpaceForm(attemptsLeft: Int, wait: Int, confirmationShown: Bool = false) {
        guard wait == newSpaceWait else { return }
        if let session = spaceCreation { newSpaceWaitActive = false; session.view.focusName(); return }
        guard window != nil, !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved else {
            newSpaceWaitActive = false; return
        }
        if prepareSidebarNewSpace([])?() == true { newSpaceWaitActive = false; return }
        let peek = newSpaceBlockingPeekState
        let shown = confirmationShown || peek == .awaitingConfirmation
        let step = NewSpaceBlockerWait.next(peek: peek, confirmationShown: shown, attemptsLeft: attemptsLeft)
        guard step != .giveUp else { newSpaceWaitActive = false; return }
        let remaining = step == .waitForConfirmation ? attemptsLeft : attemptsLeft - 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentNewSpaceForm(attemptsLeft: remaining, wait: wait, confirmationShown: shown)
        }
    }

    private var spaceCreationCanBegin: Bool {
        !isPrivateBrowsing && !store.isEphemeral && spaceCreation == nil
            && spaceCommandsAvailable && activePeek == nil && commandBar == nil
            && libraryView == nil && pageCapture == nil && !siteControlCenterDefers
            && favoriteRename == nil && favoriteSplitRename == nil && splitIconPicker == nil
            && !sidebar.isEditingTitle && !folderUndo.isBusy && collectionTransfer == nil
            && transferRecoveries.isEmpty && !store.isProfileRemovalPending(activeProfileID)
    }

    private func prepareSidebarNewSpace(_ items: [SidebarItemReference]) -> (() -> Bool)? {
        guard spaceCreationCanBegin, let window,
              let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID),
              let draft = SidebarNewSpaceDraft(items: items, from: source, state: store.state,
                  theme: store.state.spaces.first { $0.id == source.spaceID }.map(store.savedTheme(of:))) else { return nil }
        let ids = Set(draft.tabIDs + selectedTabIDs)
        guard let owners = prepareSidebarSpaceMoveOwners?(ids), owners(),
              !hasPendingNativePage(in: ids) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        var probe = draft; probe.name = "Space"
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              probe.roots.isEmpty || probe.move(in: store.state)?.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) == true else { return nil }
        let selection = selectedTabIDs, focus = focusedTabID
        var consumed = false
        return { [weak self, weak window] in
            guard let self, let window, self.window === window, !consumed,
                  self.spaceCreationCanBegin, self.activeSpaceID == source.spaceID,
                  self.activeProfileID == source.profileID, self.selectedTabIDs == selection,
                  self.focusedTabID == focus, owners(),
                  ids.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }),
                  SidebarNewSpaceDraft(items: items, from: source, state: self.store.state,
                      spaceID: draft.spaceID) != nil,
                  self.prepareNotesToClose(Set(selection)), owners() else { return false }
            let session = SpaceCreationSession(draft: draft, owner: self, claims: claims, validateOwners: owners)
            guard window.makeFirstResponder(nil), owners() else { return false }
            consumed = true
            self.beginSpaceCreation(session)
            return self.spaceCreation === session
        }
    }

    private func prepareTurnFolderIntoSpace(_ folderID: UUID) -> (() -> Bool)? {
        guard spaceCreationCanBegin,
              let folder = store.state.folders.first(where: { $0.id == folderID }), folder.spaceID == activeSpaceID,
              let source = SidebarHierarchySnapshot(state: store.state, spaceID: activeSpaceID, profileID: activeProfileID) else { return nil }
        let items = SidebarHierarchy.children(in: .init(spaceID: folder.spaceID, folderID: folderID, section: .pinned), state: store.state)
        guard var draft = SidebarNewSpaceDraft(items: items, from: source, state: store.state,
                  theme: store.state.spaces.first { $0.id == source.spaceID }.map(store.savedTheme(of:))) else { return nil }
        let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.name = name.isEmpty ? "Untitled" : folder.name
        let ids = Set(draft.tabIDs)
        guard let owners = prepareSidebarSpaceMoveOwners?(ids), owners(),
              !hasPendingNativePage(in: ids) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: ids.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              draft.roots.isEmpty || draft.move(in: store.state)?.permitsSplitOwners(claims.compactMapValues(\.owner), in: presentationID) == true,
              draft.applying(to: store.state) != nil else { return nil }
        var consumed = false
        return { [weak self] in
            guard let self, !consumed, self.spaceCreationCanBegin, self.activeSpaceID == source.spaceID,
                  self.activeProfileID == source.profileID, owners(),
                  ids.allSatisfy({ self.ownership.claimSnapshot($0) == claims[$0] }) else { return false }
            consumed = true
            do {
                guard let spaceID = try self.store.turnFolderIntoSpace(draft, folder: folder) else { return false }
                self.selectSpace(spaceID); self.requestNativeSelection()
                return true
            } catch {
                showError(error)
                return false
            }
        }
    }

    private func creationOwnerIsCurrent(_ session: SpaceCreationSession) -> Bool {
        guard spaceCreation === session, let window = session.window, self.window === window,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              presentation.isReady, activeSpaceID == session.draft.source.spaceID,
              activeProfileID == session.draft.source.profileID, selectedTabIDs.isEmpty,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, collectionTransfer == nil,
              store.retiringTabIDs.isDisjoint(with: session.claims.keys),
              closingTabIDs.isDisjoint(with: session.claims.keys),
              modelRetirementIDs.isDisjoint(with: session.claims.keys),
              session.claims.allSatisfy({ ownership.claimSnapshot($0.key) == $0.value }) else { return false }
        var probe = session.draft; probe.name = "Space"
        return probe.applying(to: store.state) != nil
    }

    private func beginSpaceCreation(_ session: SpaceCreationSession) {
        navigationHistory?.dismiss(); sidebarPreviews?.dismiss()
        pageHost.cancelDrop(); sharedQuotes.invalidate()
        if !findHost.isHidden { dismissFind() }
        pendingNativeSelection = nil
        spaceCreation = session
        for id in selectedTabIDs { presentation.remove(id) }
        focusedTabID = nil
        let view = session.view
        view.onNameChange = { [weak self, weak session] name in
            guard let self, let session, self.spaceCreation === session, !session.committing else { return }
            session.draft.name = name
            self.refreshSpaceCreation(session)
        }
        view.onSharingChange = { [weak self, weak session] sharing in
            guard let self, let session, self.creationOwnerIsCurrent(session), !session.committing else { return }
            switch sharing {
            case .share(let id):
                guard session.draft.shareData(withSpace: id, in: self.store.state) else {
                    self.refreshSpaceCreation(session); return
                }
                session.sharedSpaceID = id
            case .separate:
                session.draft.keepSeparate()
                session.sharedSpaceID = nil
            }
            session.view.showError(nil); self.refreshSpaceCreation(session)
        }
        view.onChooseIcon = { [weak self, weak session] anchor in
            guard let self, let session else { return }; self.chooseCreationIcon(session, from: anchor)
        }
        view.onChooseTheme = { [weak self, weak session] anchor in
            guard let self, let session else { return }; self.chooseCreationTheme(session, from: anchor)
        }
        view.onCreate = { [weak self, weak session] in
            guard let self, let session else { return }; self.commitSpaceCreation(session)
        }
        view.onCancel = { [weak self, weak session] in
            guard let self, self.spaceCreation === session else { return }; self.cancelSpaceCreation()
        }
        sidebar.setSpaceCreationView(view)
        setSidebarPresentation(.locked)
        refreshSpaceCreation(session)
        render(store.state); requestNativeSelection(); view.focusName()
    }

    private var creationSharingSpaces: [BrowserSpace] {
        store.state.spaces.filter { !store.isProfileRemovalPending($0.profileID) }
    }

    private func refreshSpaceCreation(_ session: SpaceCreationSession) {
        guard spaceCreation === session else { return }
        session.view.replaceSpaces(creationSharingSpaces, selected: session.sharedSpaceID)
        session.view.setCreationAvailable(creationOwnerIsCurrent(session), committing: session.committing)
    }

    private func reconcileSpaceCreation() {
        guard let session = spaceCreation, !session.committing else { return }
        if !creationOwnerIsCurrent(session) {
            cancelSpaceCreation(restoreFocus: false, renderContent: false)
        } else {
            refreshSpaceCreation(session); session.iconPicker?.reconcile()
        }
    }

    private func finishSpaceCreation(_ session: SpaceCreationSession) {
        spaceCreation = nil
        session.iconPicker?.cancel(); session.iconPicker = nil
        session.themePopover?.close(); session.themePopover = nil; session.themeEditor = nil
        sidebar.setSpaceCreationView(nil)
        session.view.onNameChange = nil; session.view.onSharingChange = nil
        session.view.onChooseIcon = nil; session.view.onChooseTheme = nil
        session.view.onCreate = nil; session.view.onCancel = nil
    }

    private func cancelSpaceCreation(restoreFocus: Bool = true, renderContent: Bool = true) {
        guard let session = spaceCreation, !session.committing else { return }
        finishSpaceCreation(session)
        presentation = session.originalPresentation
        presentation.reconcile(store.state) { ownership.canUse($0, owner: presentationID) }
        focusedTabID = session.originalFocus.flatMap { selectedTabIDs.contains($0) ? $0 : nil }
            ?? presentation.preferredFocusedTabID
        pendingNativeSelection = nil
        setSidebarPresentation(session.originalSidebar)
        applyChromeTheme(activeSpace.theme)
        if renderContent, !isClosing, !wholeWindowClose {
            render(store.state); requestNativeSelection()
            if restoreFocus, window?.isKeyWindow == true, window?.attachedSheet == nil {
                if let responder = session.originalResponder as? NSView,
                   SavedFocus.mayReturn(to: responder, in: window) { window?.makeFirstResponder(responder) }
                else if let currentBrowser { window?.makeFirstResponder(currentBrowser) }
                else { focusSelectedLocalContent() }
            }
        }
    }

    private func commitSpaceCreation(_ session: SpaceCreationSession) {
        guard creationOwnerIsCurrent(session), !session.committing, !session.view.hasMarkedText,
              session.window?.isKeyWindow == true, session.window?.attachedSheet == nil,
              let window = session.window, PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              session.draft.applying(to: store.state) != nil else { return }
        guard session.validateOwners() else {
            session.view.showError("An original page is unavailable. Try again when it is ready, or Cancel."); return
        }
        session.themeEditor?.finishEditing()
        guard creationOwnerIsCurrent(session), session.validateOwners() else { return }
        session.committing = true; refreshSpaceCreation(session)
        store.createSpace(session.draft) { [weak self, weak session] result in
            guard let self, let session, self.spaceCreation === session else { return }
            switch result {
            case .failure(let error):
                session.committing = false; self.refreshSpaceCreation(session)
                session.view.showError(error.localizedDescription)
            case .success(nil):
                session.committing = false; self.refreshSpaceCreation(session)
                if !session.draft.movesItemsAcrossProfiles {
                    session.view.showError("The original items changed. Cancel and try again.")
                }
            case .success(let id?):
                self.finishSpaceCreation(session)
                self.presentation = session.originalPresentation
                self.presentation.reconcile(self.store.state) { self.ownership.canUse($0, owner: self.presentationID) }
                self.focusedTabID = self.presentation.preferredFocusedTabID
                self.selectSpace(id)
                session.window?.makeFirstResponder(self.sidebar)
            }
        }
    }

    private func chooseCreationIcon(_ session: SpaceCreationSession, from anchor: NSView) {
        guard creationOwnerIsCurrent(session), !session.committing, session.window?.attachedSheet == nil else { return }
        session.themePopover?.close(); session.iconPicker?.cancel()
        let picker = SidebarGroupIconPicker(selected: session.draft.customIcon, iconSet: .tabAndSpacePicker)
        picker.closesAfterChoice = true
        picker.isCurrent = { [weak self, weak session, weak picker] in
            guard let self, let session, let picker else { return false }
            return self.creationOwnerIsCurrent(session) && !session.committing && session.iconPicker === picker
        }
        picker.onCommit = { [weak self, weak session, weak picker] icon in
            guard let self, let session, let picker, session.iconPicker === picker,
                  self.creationOwnerIsCurrent(session), !session.committing else { return }
            session.draft.customIcon = icon; session.view.setIcon(icon)
        }
        picker.onFinish = { [weak session, weak picker] in
            guard let session, session.iconPicker === picker else { return }; session.iconPicker = nil
        }
        session.iconPicker = picker; picker.present(from: anchor)
    }

    private func chooseCreationTheme(_ session: SpaceCreationSession, from anchor: NSView) {
        guard creationOwnerIsCurrent(session), !session.committing,
              anchor.window === window, window?.isKeyWindow == true, window?.attachedSheet == nil else { return }
        session.iconPicker?.cancel(); session.themePopover?.close()
        let editor = makeThemeEditor(theme: session.draft.theme)
        let update: (SpaceTheme) -> Void = { [weak self, weak session, weak editor] theme in
            guard let self, let session, let editor, session.themeEditor === editor,
                  self.creationOwnerIsCurrent(session), !session.committing else { return }
            session.draft.theme = theme; self.applyChromeTheme(theme)
        }
        editor.onPreview = update; editor.onCommit = update
        editor.onSetAppearance = { [weak self, weak session, weak editor] appearance in
            guard let self, let session, let editor, session.themeEditor === editor,
                  self.creationOwnerIsCurrent(session), !session.committing,
                  session.window?.attachedSheet == nil else { return }
            self.setThemeEditorAppearance(appearance)
        }
        let content = NSViewController(); content.view = editor
        let popover = NSPopover(); popover.contentViewController = content
        popover.contentSize = NSSize(width: 356, height: 508); popover.behavior = .transient; popover.delegate = self
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        editor.onDismiss = { [weak popover] in popover?.performClose(nil) }
        session.themeEditor = editor; session.themePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        editor.window?.makeFirstResponder(editor)
    }

    private func copyFolderLinks(_ target: FolderLinkTarget, format: FolderLinkFormat) {
        guard presentation.isReady, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved,
              activeSpaceID == target.spaceID, activeProfileID == target.profileID,
              let links = FolderLinks.links(in: store.state, target: target),
              let text = FolderLinks.text(for: links, format: format) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor final class FolderDisclosureTarget {
        private weak var owner: BrowserWindowController?
        private weak var window: NSWindow?
        private let spaceID: UUID
        private let profileID: UUID
        private let folders: [BrowserFolder]
        private let expanded: Bool
        private var consumed = false

        fileprivate init(owner: BrowserWindowController, expanded: Bool) {
            self.owner = owner; window = owner.window
            spaceID = owner.activeSpaceID; profileID = owner.activeProfileID
            folders = owner.store.state.folders.filter { $0.spaceID == owner.activeSpaceID }
            self.expanded = expanded
        }

        var isAvailable: Bool {
            guard !consumed, let owner, let window, owner.window === window,
                  owner.spaceCommandsAvailable, owner.activePeek == nil, owner.libraryView == nil,
                  owner.activeSpaceID == spaceID, owner.activeProfileID == profileID,
                  owner.store.state.profiles.contains(where: { $0.id == profileID }),
                  !owner.store.state.profileRemovals.contains(where: { $0.profileID == profileID }),
                  owner.store.state.folders.filter({ $0.spaceID == spaceID }) == folders else { return false }
            return folders.contains { $0.isExpanded != expanded }
        }

        func perform() {
            guard isAvailable, let owner else { return }
            owner.commandBar?.dismiss()
            guard isAvailable, let window,
                  PCNativeBrowserApplication.canPresentTabSwitcher(in: window) else { return }
            owner.sidebarPreviews?.dismiss()
            guard isAvailable else { return }
            consumed = true
            do {
                _ = try owner.store.setFoldersExpanded(expanded, in: spaceID,
                    profileID: profileID, expectedFolders: folders)
            } catch {
                ParcDialog.inform(in: window, .init(title: "Parc couldn’t save the folder layout", message: error.localizedDescription), queued: true)
            }
        }
    }

    func prepareFolderDisclosureMenuItem(_ item: NSMenuItem, expanded: Bool,
                                         preservingTarget: Bool) -> Bool {
        if !preservingTarget { item.representedObject = FolderDisclosureTarget(owner: self, expanded: expanded) }
        return (item.representedObject as? FolderDisclosureTarget)?.isAvailable == true
    }

    func createFolder() { createFolder(in: activeSpaceID) }
    private func createFolder(parentID: UUID) {
        guard let parent = store.state.folders.first(where: { $0.id == parentID }) else { return }
        createFolder(in: parent.spaceID, parent: parent)
    }
    private func createFolder(in id: UUID, parent: BrowserFolder? = nil) {
        guard let expected = managementSpace(id), spaceCommandsAvailable, let window else { return }
        if id == activeSpaceID, libraryView == nil, activePeek == nil, !sidebar.isEditingTitle {
            let folderID: UUID?
            do {
                var container = parent
                if let parent, !parent.isExpanded {
                    _ = try store.setFolderExpanded(true, expected: parent, profileID: expected.profileID)
                    container = store.state.folders.first { $0.id == parent.id }
                    guard container != nil else { NSSound.beep(); return }
                }
                folderID = try store.createFolder(name: SidebarFolderFromItems.defaultName, in: expected, parent: container)
            } catch { showError(error); return }
            guard let folderID else { NSSound.beep(); return }
            render(store.state)
            sidebar.scrollItemToVisible(.folder(folderID))
            if !sidebar.beginFolderTitleEditing(folderID, untitled: true) { renameFolder(folderID) }
            return
        }
        prompt("New Folder", detail: parent.map { "Create a folder inside \($0.name)." } ?? "Organize pinned tabs in \(expected.name).",
               value: "", placeholder: "Folder name") { [weak self, weak window] name in
            guard let self, let window, self.window === window, self.managementSpace(id, profileID: expected.profileID) != nil else { return }
            do { _ = try self.store.createFolder(name: name, in: expected, parent: parent) }
            catch { showError(error) }
        }
    }
    private func prepareFolderInlineRename(_ expected: BrowserFolder) -> ((String) -> Bool)? {
        guard let space = managementSpace(expected.spaceID), store.state.folders.contains(where: { $0.id == expected.id }) else { return nil }
        return { [weak self, weak window] name in
            guard let self, let window, self.window === window,
                  self.managementSpace(space.id, profileID: space.profileID) != nil else { return false }
            do { return try self.store.renameFolder(expected, profileID: space.profileID, name: name) }
            catch { showError(error); return false }
        }
    }
    private enum FolderIconError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This folder changed while its icon was being chosen. Please try again." }
    }
    private func prepareFolderIconChange(_ expected: BrowserFolder) -> (() -> Bool)? {
        guard let space = managementSpace(expected.spaceID),
              store.state.folders.contains(where: { $0.id == expected.id }) else { return nil }
        var used = false
        return { [weak self] in
            guard let self, !used, let window = self.window, self.splitIconPicker == nil,
                  self.favoriteRename == nil, self.favoriteSplitRename == nil, !self.sidebar.isEditingTitle,
                  let anchor = self.sidebar.folderIconAnchor(expected.id), anchor.view.window === window else { return false }
            let picker = SidebarGroupIconPicker(selected: expected.customIcon, iconSet: .folderPicker)
            picker.isCurrent = { [weak self] in
                guard let self, self.managementSpace(space.id, profileID: space.profileID) != nil else { return false }
                return self.store.state.folders.contains { $0.id == expected.id && $0.spaceID == expected.spaceID }
            }
            picker.onCommit = { [weak self] icon in
                guard let self, let current = self.store.state.folders.first(where: { $0.id == expected.id }),
                      try self.store.setFolderIcon(icon, expected: current, profileID: space.profileID) else {
                    throw FolderIconError.unavailable
                }
            }
            picker.onFailure = { [weak self] in self?.showError($0) }
            picker.onFinish = { [weak self, weak picker] in
                guard let self, self.splitIconPicker === picker else { return }
                self.splitIconPicker = nil
            }
            used = true; self.splitIconPicker = picker
            picker.present(from: anchor.view, rect: anchor.rect)
            return self.splitIconPicker === picker
        }
    }
    private func renameFolder(_ id: UUID) {
        guard let folder = store.state.folders.first(where: { $0.id == id }),
              let space = managementSpace(folder.spaceID), let window else { return }
        prompt("Rename folder", detail: "Choose a name for this group of tabs.", value: folder.name, placeholder: "Folder name") { [weak self, weak window] name in
            guard let self, let window, self.window === window,
                  self.managementSpace(space.id, profileID: space.profileID) != nil else { return }
            do { _ = try self.store.renameFolder(folder, profileID: space.profileID, name: name) }
            catch { showError(error) }
        }
    }
    private func turnSpaceIntoFolder(_ id: UUID, destinationID: UUID) {
        guard spaceCommandsAvailable, !folderUndo.isBusy, managementSpace(id) != nil,
              managementSpace(destinationID) != nil,
              let target = SpaceDeletionTarget(spaceID: id, state: store.state) else { return }
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents),
              let conversion = SpaceFolderConversion(source: id, destination: destinationID, state: store.state, documents: documents) else { return }
        if conversion.crossesProfiles {
            _ = confirmInterProfileMove(tabCount: conversion.tabIDs.count,
                sourceProfiles: conversion.tabIDs.isEmpty ? [] : [target.space.profileID], destinationSpaceID: destinationID) { [weak self] in
                guard let self, self.spaceCommandsAvailable, self.managementSpace(id, profileID: target.space.profileID) != nil else { return }
                let wasFocused = self.activeSpaceID == id
                self.store.moveAcrossProfiles(conversion.tabIDs, proposal: { [weak self] state in
                    guard let self, !self.isClosing, !self.wholeWindowClose, !self.windowClosePending else { return nil }
                    return conversion.applying(to: state)?.0
                }) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(true):
                        self.onInterProfileMoveCommitted?(conversion.tabIDs)
                        self.finishSpaceConversion(conversion, wasFocused: wasFocused)
                    case .success(false): NSSound.beep()
                    case .failure(let error): showError(error)
                    }
                }
            }
        } else {
            do {
                guard let validOwners = spaceConversionOwners(conversion), validOwners() else { return }
                let wasFocused = activeSpaceID == id, selection = selectedTabIDs, focus = focusedTabID
                guard let record = try store.convertSpaceToFolder(conversion) else { return }
                registerSpaceConversionUndo(record, wasFocused: wasFocused, selection: selection, focus: focus)
                finishSpaceConversion(conversion, wasFocused: wasFocused)
            } catch { showError(error) }
        }
    }
    private func spaceConversionOwners(_ conversion: SpaceFolderConversion) -> (() -> Bool)? {
        guard let owners = prepareSidebarSpaceMoveOwners?(conversion.tabIDs), owners(),
              conversion.tabIDs.isDisjoint(with: store.retiringTabIDs) else { return nil }
        let claims = Dictionary(uniqueKeysWithValues: conversion.tabIDs.map { ($0, ownership.claimSnapshot($0)) })
        guard claims.values.allSatisfy({ $0.transfer == nil }),
              conversion.target.groups.allSatisfy({ $0.tabIDs.allSatisfy { claims[$0]?.owner == nil || claims[$0]?.owner == presentationID } }) else { return nil }
        return { [weak self] in
            guard let self, !self.isClosing, owners(), conversion.tabIDs.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            return conversion.tabIDs.allSatisfy { self.ownership.claimSnapshot($0) == claims[$0] }
        }
    }
    private func finishSpaceConversion(_ conversion: SpaceFolderConversion, wasFocused: Bool) {
        if wasFocused {
            presentation.selectSpace(conversion.destination.spaceID, state: store.state, available: { self.switcherCanUse($0) })
        }
        render(store.state); requestNativeSelection()
        if libraryView?.kind == .spaces { libraryView?.spaceManager.focusFirst() }
        else { showSidebarMoveNotice(item: .folder(conversion.folderID), space: conversion.destination.spaceID,
                                    profile: conversion.destination.profileID) }
    }
    private func registerSpaceConversionUndo(_ initial: SpaceFolderUndo, wasFocused: Bool, selection: [UUID], focus: UUID?) {
        var record = initial, focused = wasFocused, selected = selection, focusedTab = focus
        folderUndo.append(.init(name: "Turn into Folder", isValid: { [weak self] direction in
            guard let self else { return false }
            return direction == .undo ? record.restoring(in: self.store.state) != nil : record.redo(in: self.store.state) != nil
        }, isAvailable: { [weak self] _ in
            guard let self, self.windowUndoContextAvailable, record.documentsAreAvailable,
                  let owners = self.spaceConversionOwners(record.conversion) else { return false }
            return owners()
        }, perform: { [weak self] direction, done in
            guard let self, self.windowUndoContextAvailable, let owners = self.spaceConversionOwners(record.conversion), owners() else { done(false); return }
            do {
                switch direction {
                case .undo:
                    let restored = try self.store.undoSpaceFolderConversion(record)
                    if restored && focused {
                        self.presentation.restoreDeletedSpace(record.conversion.target.space.id, selection: selected, focus: focusedTab,
                            state: self.store.state, available: { self.switcherCanUse($0) })
                    }
                    if restored { self.render(self.store.state); self.requestNativeSelection() }
                    done(restored)
                case .redo:
                    guard let conversion = record.redo(in: self.store.state) else { done(false); return }
                    let wasFocused = self.activeSpaceID == conversion.target.space.id
                    let selection = self.selectedTabIDs, focus = self.focusedTabID
                    guard let next = try self.store.convertSpaceToFolder(conversion) else { done(false); return }
                    record = next; focused = wasFocused; selected = selection; focusedTab = focus
                    self.finishSpaceConversion(conversion, wasFocused: wasFocused); done(true)
                }
            } catch { showError(error); done(false) }
        }))
    }

    private final class SpaceUndoOperation {
        var record: SpaceDeletionUndo
        var wasFocused: Bool
        var selection: [UUID]
        var focus: UUID?
        init(record: SpaceDeletionUndo, wasFocused: Bool, selection: [UUID], focus: UUID?) {
            self.record = record; self.wasFocused = wasFocused; self.selection = selection; self.focus = focus
        }
    }

    @discardableResult
    func deleteSpace(_ id: UUID, confirmingIn sheetWindow: NSWindow? = nil) -> Bool {
        guard let window, sheetWindow == nil ? spaceCommandsAvailable : (spaceStateAvailable && !isPrivateBrowsing),
              !folderUndo.isBusy, managementSpace(id) != nil,
              let target = SpaceDeletionTarget(spaceID: id, state: store.state),
              retirementUnavailableReason?(target.tabIDs) == nil else { return false }
        commandBar?.dismiss(); sidebar.cancelSpaceNameEditing(); spaceIconPicker?.cancel()
        let typed = target.tabs.filter { InternalPage(urlString: $0.savedURL) != nil }
        guard let documents = typed.isEmpty ? [:] : resolveSidebarCopyDestinations?(typed)?.documents,
              SidebarDocumentReference.validates(target.tabs, references: documents) else { return false }
        let wasFocused = activeSpaceID == id, selection = selectedTabIDs, focus = focusedTabID
        let unused = store.unusedProfile(ifDeletingSpace: id)
        let message = "This will archive all the tabs and folders inside it."
            + (unused == nil ? "" : " " + SpaceSharingWarning.deletionNote)
        let dialogWindow = sheetWindow ?? window
        return ParcDialog.confirm(in: dialogWindow, title: "Delete your “\(target.space.name)” Space?", message: message,
                                 confirm: "Delete", destructive: true) { [weak self, weak window] approved in
            DispatchQueue.main.async {
                guard approved, let self, let window, self.window === window else { return }
                if sheetWindow != nil {
                    window.makeKeyAndOrderFront(nil)
                }
                guard sheetWindow == nil ? self.spaceCommandsAvailable : (self.spaceStateAvailable && !self.isPrivateBrowsing),
                      !self.folderUndo.isBusy,
                      SpaceDeletionTarget(spaceID: id, state: self.store.state) == target,
                      self.store.unusedProfile(ifDeletingSpace: id) == unused else { return }
                self.performSpaceDeletion(target, documents: documents, wasFocused: wasFocused,
                    didCommit: { [weak self] record in
                        guard unused == nil else { return }
                        self?.registerSpaceDeletionUndo(SpaceUndoOperation(record: record,
                            wasFocused: wasFocused, selection: selection, focus: focus))
                    }, completion: { committed in
                        if committed, let unused { SpaceSharingConfirmation.handOff(unused) }
                    })
            }
        }
    }

    private func performSpaceDeletion(_ target: SpaceDeletionTarget,
                                      documents: [UUID: SidebarDocumentReference], wasFocused: Bool,
                                      didCommit: @escaping (SpaceDeletionUndo) -> Void,
                                      completion: @escaping (Bool) -> Void) {
        guard let window, retirementUnavailableReason?(target.tabIDs) == nil else { completion(false); return }
        var record: SpaceDeletionUndo?
        store.deleteSpace(target, documents: documents, shouldCommit: { [weak self, weak window] in
            guard let self, let window, self.window === window else { return false }
            return !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                && !self.windowCloseApproved && self.spaceCreation == nil
        }, didCommit: { value in record = value; didCommit(value) }) { [weak self, weak window] result in
            guard let self, let window, self.window === window else { completion(false); return }
            switch result {
            case .success(let committed):
                if committed, let record {
                    if wasFocused {
                        self.presentation.selectSpace(record.replacementSpaceID, state: self.store.state, available: { self.switcherCanUse($0) })
                    }
                    self.render(self.store.state)
                    if self.libraryView?.kind == .spaces { self.libraryView?.spaceManager.focusFirst() }
                    else if wasFocused { self.requestNativeSelection(); self.focusSelectedLocalContent() }
                }
                completion(committed)
            case .failure(let error): completion(false); showError(error)
            }
        }
    }

    private func registerSpaceDeletionUndo(_ operation: SpaceUndoOperation) {
        folderUndo.append(.init(name: "Delete Space", isValid: { [weak self] direction in
            guard let self else { return false }
            return direction == .undo ? self.store.canUndoSpaceDeletion(operation.record)
                : operation.record.redoTarget(in: self.store.state) != nil
                    && self.store.unusedProfile(ifDeletingSpace: operation.record.target.space.id) == nil
        }, isAvailable: { [weak self] direction in
            guard let self, self.windowUndoContextAvailable, operation.record.documentsAreAvailable,
                  operation.record.target.tabIDs.isDisjoint(with: self.store.retiringTabIDs) else { return false }
            return direction == .undo ? operation.record.target.tabIDs.allSatisfy { self.switcherCanUse($0) }
                : self.retirementUnavailableReason?(operation.record.target.tabIDs) == nil
        }, perform: { [weak self] direction, done in
            guard let self, self.windowUndoContextAvailable, let window else { done(false); return }
            switch direction {
            case .undo:
                do {
                    let restored = try self.store.undoSpaceDeletion(operation.record, shouldCommit: { [weak self, weak window] in
                        guard let self, let window, self.window === window, self.windowUndoContextAvailable else { return false }
                        return operation.record.target.tabIDs.allSatisfy { self.switcherCanUse($0) }
                    })
                    if restored, operation.wasFocused {
                        self.presentation.restoreDeletedSpace(operation.record.target.space.id,
                            selection: operation.selection, focus: operation.focus, state: self.store.state,
                            available: { self.switcherCanUse($0) })
                        self.render(self.store.state); self.requestNativeSelection(); self.focusSelectedLocalContent()
                    }
                    done(restored)
                } catch { done(false); showError(error) }
            case .redo:
                guard let target = operation.record.redoTarget(in: self.store.state) else { done(false); return }
                let wasFocused = self.activeSpaceID == target.space.id
                let selection = self.selectedTabIDs, focus = self.focusedTabID
                self.performSpaceDeletion(target, documents: operation.record.documents, wasFocused: wasFocused,
                    didCommit: {
                        operation.record = $0; operation.wasFocused = wasFocused
                        operation.selection = selection; operation.focus = focus
                    }, completion: done)
            }
        }))
    }

    private var spaceIconPicker: SidebarGroupIconPicker?

    private func managementSpace(_ id: UUID, profileID: UUID? = nil) -> BrowserSpace? {
        guard !isPrivateBrowsing, !store.isEphemeral, !isPopupWindow, presentation.isReady,
              !isClosing, !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              nativeFullscreenTabID == nil, spaceCreation == nil,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, closingTabIDs.isEmpty,
              modelRetirementIDs.isEmpty, collectionTransfer == nil,
              let space = store.state.spaces.first(where: { $0.id == id && (profileID == nil || $0.profileID == profileID) }),
              store.state.profiles.contains(where: { $0.id == space.profileID }),
              !store.isProfileRemovalPending(space.profileID) else { return nil }
        return space
    }

    private func spaceManagementMenu(_ id: UUID) -> SidebarSpaceMenu? {
        guard let expected = managementSpace(id) else { return nil }
        let valid: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.spaceCommandsAvailable && self.managementSpace(id, profileID: expected.profileID) != nil
        }
        let choose: (SpaceDataSharing) -> Void = { [weak self] sharing in
            guard let self, valid() else { return }
            self.commandBar?.dismiss()
            guard let window = self.window else { return }
            SpaceSharingConfirmation.present(on: window, store: self.store, spaceID: id, sharing: sharing,
                ownerValid: { [weak self, weak window] in
                    guard let self, let window, self.window === window else { return false }
                    return !self.isClosing && !self.wholeWindowClose && !self.windowClosePending
                        && !self.windowCloseApproved && self.spaceCreation == nil
                }, completion: { [weak self] result in
                    if case .failure(let error) = result { self?.showError(error) }
                })
        }
        let others = store.state.spaces.filter { $0.id != id }
        let shareData = others.map { other in
            (name: other.name, shared: other.profileID == expected.profileID,
             action: store.isProfileRemovalPending(other.profileID) ? nil : { choose(.share(withSpace: other.id)) } as (() -> Void)?)
        }
        return SidebarSpaceMenu(includesManagement: true, changeIcon: { [weak self] in if valid() { self?.changeSpaceIcon(id) } },
            shareData: shareData,
            keepSeparate: (selected: !shareData.contains { $0.shared }, action: { choose(.separate) }),
            delete: store.state.spaces.count > 1 ? { [weak self] in if valid() { self?.deleteSpace(id) } } : nil,
            manage: { [weak self] in if valid() { self?.showLibrary(.spaces) } },
            turnIntoFolder: store.state.spaces.filter { $0.id != id }.map { destination in
                (name: destination.name, action: store.isProfileRemovalPending(destination.profileID) ? nil : { [weak self] in
                    guard let self, valid(), self.managementSpace(destination.id, profileID: destination.profileID) != nil else { return }
                    self.turnSpaceIntoFolder(id, destinationID: destination.id)
                })
            },
            rename: { [weak self] in if valid() { self?.renameSpace(id) } },
            editTheme: { [weak self] in if valid() { self?.editTheme(spaceID: id) } },
            newFolder: { [weak self] in if valid() { self?.createFolder(in: id) } }, toggleTitle: SidebarChromeLayout.SpaceHeader.toggleTitle(spaceCount: store.state.spaces.count,
                titled: expected.title != nil, customIcon: expected.customIcon != nil,
                showOnSingleUnnamedSpace: store.state.settings.showSpaceHeaderOnSingleUnnamedSpaces ?? false),
            toggleHeader: { [weak self] in if valid() { self?.store.toggleSpaceHeaderOnSingleUnnamedSpaces() } })
    }

    private func renameSpace(_ id: UUID) {
        guard let expected = managementSpace(id), spaceCommandsAvailable, let window else { return }
        commandBar?.dismiss()
        guard spaceCommandsAvailable else { return }
        let managerSidebar = libraryView?.kind == .spaces ? libraryView?.spaceManager.sidebar(for: id) : nil
        if id != activeSpaceID && managerSidebar == nil {
            let dialog = ParcDialog(.init(title: [("Rename Space", false)], confirm: "Save", cancel: "Cancel",
                field: .init(value: expected.title ?? "", placeholder: expected.name, required: false)))
            guard let field = dialog.textField else { return }
            _ = dialog.begin(for: window, queued: true) { [weak self, weak window] response in
                guard response == .confirm, let self, let window, self.window === window,
                      self.managementSpace(id, profileID: expected.profileID) != nil else { return }
                do { try self.store.saveSpaceTitle(expected, title: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
                catch { if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) } }
            }
            return
        }
        guard PCNativeBrowserApplication.canPresentTabSwitcher(in: window),
              managementSpace(id, profileID: expected.profileID)?.title == expected.title else { return }
        spaceIconPicker?.cancel()
        if managerSidebar == nil { closeLibrary(restoreFocus: false); revealSidebarForEditing() }
        let editingSidebar = managerSidebar ?? sidebar
        _ = editingSidebar.beginSpaceNameEditing(expected) { [weak self, weak window, weak editingSidebar] value in
            guard let self, let window, self.window === window else { return }
            if let value, self.managementSpace(id, profileID: expected.profileID) != nil,
               (self.activeSpaceID == id || self.libraryView?.spaceManager.sidebar(for: id) === editingSidebar) {
                do { try self.store.saveSpaceTitle(expected, title: value.trimmingCharacters(in: .whitespacesAndNewlines)) }
                catch { if (error as NSError).code != CocoaError.userCancelled.rawValue { showError(error) } }
            }
            self.render(self.store.state)
        }
    }

    private func changeSpaceIcon(_ id: UUID) {
        guard spaceIconPicker == nil, let expected = managementSpace(id),
              spaceCommandsAvailable, let window else { return }
        commandBar?.dismiss(); sidebar.cancelSpaceNameEditing()
        let manager = libraryView?.kind == .spaces ? libraryView?.spaceManager : nil
        if manager == nil { closeLibrary(restoreFocus: false); revealSidebarForEditing() }
        guard self.window === window, spaceCommandsAvailable,
              let actual = managementSpace(id, profileID: expected.profileID), actual.customIcon == expected.customIcon,
              let anchor = manager?.anchor(for: id) ?? sidebar.spaceAppearanceAnchor(id), anchor.window === window else { return }
        let picker = SidebarGroupIconPicker(selected: expected.customIcon, iconSet: .tabAndSpacePicker)
        var current = expected
        picker.isCurrent = { [weak self, weak window, weak picker] in
            guard let self, let window, let picker, self.window === window,
                  self.spaceIconPicker === picker,
                  SplitCustomizationFocus.isHeld(window: window, presentation: picker.presentationWindow),
                  let actual = self.managementSpace(id, profileID: current.profileID) else { return false }
            return actual.customIcon == current.customIcon
        }
        picker.onCommit = { [weak self, weak picker] icon in
            guard let self, let picker, picker.isCurrent() else { throw CocoaError(.userCancelled) }
            try self.store.saveSpaceIcon(current, icon: icon)
            current.customIcon = icon
        }
        picker.onFinish = { [weak self, weak picker] in
            guard let self, self.spaceIconPicker === picker else { return }
            self.spaceIconPicker = nil
            self.refreshSidebarPointerIfKey()
        }
        picker.onFailure = { [weak self] in self?.showError($0) }
        spaceIconPicker = picker
        picker.present(from: anchor)
    }

    private func prompt(_ title: String, detail: String, value: String, placeholder: String, accept: @escaping (String) -> Void) {
        guard let window else { return }
        let dialog = ParcDialog(.init(title: [(title, false)], message: [(detail, false)], confirm: "Save", cancel: "Cancel",
                                     field: .init(value: value, placeholder: placeholder)))
        guard let field = dialog.textField else { return }
        _ = dialog.begin(for: window, queued: true) { response in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .confirm && !name.isEmpty { accept(name) }
        }
    }

    var downloadCatalog: BrowserStore?
    private var downloadStore: BrowserStore { downloadCatalog ?? store }
    var onOpenDownloadSource: ((BrowserDownload, URL) -> Bool)?
    private var loadingPrivateDownloadContexts = Set<String>()
    private var privateDownloadErrors: [String: String] = [:]
    private func privateDownloadContext(_ item: BrowserDownload) -> PCNativePrivateDownloadContext? {
        guard let id = item.privateContextID, let profile = item.profileID else { return nil }
        return PCNativeBrowserApplication.privateDownloadContexts().first {
            $0.identifier == id && $0.isValid && $0.profilePath == downloadStore.independentEngineProfilePath(for: profile)
        }
    }

    func showDownloads() { showLibrary(.downloads) }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, privateDownloadDidUpdate update: [String: Any]) {
        guard isPrivateBrowsing, browser === nativeBinding, browser.window === window else { return }
        refreshDownloads()
    }
    func nativeBrowser(_ browser: PCNativeBrowserWindow, downloadDidBegin arrival: PCNativeDownloadArrival) {
        guard let parent = window, browser === nativeBinding, browser.window === parent,
              !isClosing, !wholeWindowClose, presentation.isReady else { return }
        let profile = downloadStore.profileID(forEnginePath: arrival.profilePath)
        let context = arrival.privateContextIdentifier
        guard DownloadArrivalOwner.admits(valid: arrival.isValid, hasPage: arrival.page != nil,
                popupWindow: isPopupWindow, privateWindow: isPrivateBrowsing, privateContext: context,
                privateContextLive: context.map { id in PCNativeBrowserApplication.privateDownloadContexts().contains {
                    $0.identifier == id && $0.isValid && $0.profilePath == arrival.profilePath } } ?? false,
                profileKnown: profile.map { !downloadStore.isProfileRemovalPending($0) } ?? false) else { return }
        downloadArrival.arrive(at: arrival.sourceScreenPoint, in: parent,
                               showsBin: sidebarPresentation == .hidden, palette: rootView.palette)
    }
    func nativeBrowserPrivateDownloadsDidInvalidate(_ browser: PCNativeBrowserWindow) {
        guard isPrivateBrowsing, browser === nativeBinding, browser.window === window else { return }
        downloadReview?.dismiss(); closeLibrary(restoreFocus: false)
        refreshDownloads()
    }
    private func startLibraryFlyoutFileQuery() {
        guard libraryFlyoutFileMonitor == nil else { return }
        libraryFlyoutFileActivation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshLibraryFlyoutFiles() } }
        libraryFlyoutFileMonitor = LibraryFlyoutFolderMonitor { [weak self] in self?.refreshLibraryFlyoutFiles() }
        refreshLibraryFlyoutFiles()
    }
    private func stopLibraryFlyoutFileQuery() {
        libraryFlyoutFileGeneration &+= 1
        libraryFlyoutFileMonitor?.cancel(); libraryFlyoutFileMonitor = nil
        if let libraryFlyoutFileActivation {
            NotificationCenter.default.removeObserver(libraryFlyoutFileActivation)
            self.libraryFlyoutFileActivation = nil
        }
        sidebar.updateLibraryFlyoutFiles([])
    }
    private func refreshLibraryFlyoutFiles() {
        libraryFlyoutFileGeneration &+= 1
        let generation = libraryFlyoutFileGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let folders = LibraryFlyoutFiles.defaultFolders()
            let files = LibraryFlyoutFiles.scan(folders: folders)
            DispatchQueue.main.async {
                guard let self, generation == self.libraryFlyoutFileGeneration, !self.isClosing, !self.wholeWindowClose else { return }
                self.libraryFlyoutFileMonitor?.watch(folders.map(\.1))
                self.sidebar.updateLibraryFlyoutFiles(files)
            }
        }
    }
    private func refreshDownloadProfiles() {
        let catalog = downloadStore
        for profile in catalog.state.profiles where !loadingDownloadProfiles.contains(profile.id) && !catalog.isProfileRemovalPending(profile.id) {
            loadingDownloadProfiles.insert(profile.id); downloadProfileErrors[profile.id] = nil
            PCNativeBrowserApplication.refreshDownloads(profilePath: catalog.independentEngineProfilePath(for: profile.id)) { [weak self, weak catalog] identifiers, error in
                MainActor.assumeIsolated {
                    guard let self, let catalog, self.downloadStore === catalog else { return }
                    self.loadingDownloadProfiles.remove(profile.id)
                    if catalog.state.profiles.contains(where: { $0.id == profile.id }) {
                        if error == nil, let identifiers { catalog.reconcileDownloads(profileID: profile.id, nativeIDs: Set(identifiers)) }
                        let spaceName = catalog.state.spaces.first { $0.profileID == profile.id }?.name
                        self.downloadProfileErrors[profile.id] = error.map { error in
                            spaceName.map { $0 + ": " + error.localizedDescription } ?? error.localizedDescription
                        }
                    }
                    self.updateDownloadLoading()
                }
            }
        }
        for context in PCNativeBrowserApplication.privateDownloadContexts() where context.isValid && !loadingPrivateDownloadContexts.contains(context.identifier) {
            let id = context.identifier
            loadingPrivateDownloadContexts.insert(id); privateDownloadErrors[id] = nil
            context.refresh { [weak self, weak catalog, weak context] identifiers, error in
                MainActor.assumeIsolated {
                    guard let self, let catalog, self.downloadStore === catalog else { return }
                    self.loadingPrivateDownloadContexts.remove(id)
                    if let context, context.isValid {
                        if error == nil, let identifiers { catalog.reconcileTransientDownloads(contextID: id, nativeIDs: Set(identifiers)) }
                        self.privateDownloadErrors[id] = error?.localizedDescription
                    } else { catalog.retireTransientDownloads(contextID: id); self.privateDownloadErrors[id] = nil }
                    self.updateDownloadLoading()
                }
            }
        }
        updateDownloadLoading()
    }
    private func updateDownloadLoading() {
        let profiles = Set(downloadStore.state.profiles.map(\.id))
        let liveContexts = Set(PCNativeBrowserApplication.privateDownloadContexts().filter(\.isValid).map(\.identifier))
        privateDownloadErrors = privateDownloadErrors.filter { liveContexts.contains($0.key) }
        let message = (Array(downloadProfileErrors.filter { profiles.contains($0.key) }.values) + Array(privateDownloadErrors.values)).sorted().joined(separator: " · ")
        if libraryView?.kind == .downloads {
            for item in downloadStore.downloadItems where recyclingDownloads[item.id] == DownloadLibraryIdentity(item) {
                libraryView?.setDownloadOperation(item, message: "Moving to Trash…")
            }
        }
        libraryView?.setDownloadsLoading(count: loadingDownloadProfiles.intersection(profiles).count + loadingPrivateDownloadContexts.intersection(liveContexts).count,
                                         message: message.isEmpty ? nil : message)
    }
    private var downloadActivityProfiles: Set<UUID> {
        Set(downloadStore.state.profiles.filter { !downloadStore.isProfileRemovalPending($0.id) }.map(\.id))
    }
    private var downloadActivityEnabled: Bool {
        (!isPrivateBrowsing || nativeBinding?.privateDownloadsAvailable == true) && !isClosing && !wholeWindowClose && presentation.isReady
    }
    private func refreshLibraryDownloadActivity() {
        libraryView?.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles,
                                            privateWindow: isPrivateBrowsing, enabled: downloadActivityEnabled)
    }
    func refreshDownloads() {
        sidebar.updateDownloadActivity(downloadStore.downloadItems, profiles: downloadActivityProfiles, enabled: downloadActivityEnabled)
        refreshLibraryDownloadActivity()
        sidebar.updateLibraryCaptures(isPrivateBrowsing || isClosing || wholeWindowClose ? nil
            : CaptureLibraryStore.shared(directory: store.capturesDirectory(for: activeProfileID), profileID: activeProfileID))
        if let downloadReview, let item = downloadReviewItem {
            if let current = currentDownloadReview(item) { downloadReview.update(current) }
            else { downloadReview.dismiss() }
        }
    }
    private func liveLibraryDownload(_ expected: BrowserDownload) -> BrowserDownload? {
        guard !isClosing, !wholeWindowClose, presentation.isReady,
              let identity = expected.nativeIdentity, !identity.isEmpty,
              let profile = expected.profileID, !downloadStore.isProfileRemovalPending(profile),
              downloadStore.state.profiles.contains(where: { $0.id == profile }),
              let current = downloadStore.downloadItems.first(where: { $0.id == expected.id }),
              current.profileID == profile, current.nativeID == expected.nativeID,
              current.nativeIdentity == identity, current.privateContextID == expected.privateContextID,
              current.privateContextID == nil || privateDownloadContext(current) != nil else { return nil }
        return current
    }
    private func libraryDownloadFileURL(_ expected: BrowserDownload) -> URL? {
        guard window?.attachedSheet == nil,
              let item = liveLibraryDownload(expected), item.canCopyFile,
              let profile = item.profileID, let nativeID = item.nativeID,
              let identity = item.nativeIdentity, recyclingDownloads[item.id] == nil else { return nil }
        if item.privateContextID != nil { return privateDownloadContext(item)?.fileURL(identifier: nativeID, itemIdentity: identity) }
        return PCNativeBrowserApplication.downloadFileURL(identifier: nativeID,
            profilePath: downloadStore.independentEngineProfilePath(for: profile), itemIdentity: identity)
    }
    private func currentDownloadReview(_ expected: BrowserDownload) -> PCNativeDownloadReview? {
        guard let item = liveLibraryDownload(expected), item.canReview,
              let profile = item.profileID, let nativeID = item.nativeID else { return nil }
        if item.privateContextID != nil {
            guard let identity = item.nativeIdentity else { return nil }
            return privateDownloadContext(item)?.review(identifier: nativeID, itemIdentity: identity)
        }
        return PCNativeBrowserApplication.downloadReview(identifier: nativeID,
            profilePath: downloadStore.independentEngineProfilePath(for: profile))
    }
    private func reviewDownload(_ item: BrowserDownload) -> Bool {
        guard downloadReview == nil, let parent = window, parent.attachedSheet == nil,
              let profile = item.profileID, let snapshot = currentDownloadReview(item) else { return false }
        let path = downloadStore.independentEngineProfilePath(for: profile)
        let controller = DownloadReviewController(review: snapshot, theme: activeSpace.theme, incognito: rootView.incognito)
        downloadReview = controller; downloadReviewItem = item
        controller.onDecision = { [weak self, weak controller, weak parent] displayed, action, password, justification in
            guard let self, let controller, let parent, self.window === parent,
                  self.downloadReview === controller, controller.window?.sheetParent === parent,
                  displayed.profilePath == path, self.currentDownloadReview(item) != nil else { return false }
            if item.privateContextID != nil {
                return self.privateDownloadContext(item)?.performReview(action, for: displayed,
                    password: password, justification: justification) ?? false
            }
            return PCNativeBrowserApplication.performDownloadReviewAction(action, for: displayed,
                password: password, justification: justification)
        }
        controller.onOpenLink = { [weak self, weak controller, weak parent] displayed, index in
            guard let self, let controller, let parent, self.window === parent,
                  self.downloadReview === controller, controller.window?.sheetParent === parent,
                  displayed.profilePath == path, self.currentDownloadReview(item) != nil,
                  let nativeIndex = UInt(exactly: index),
                  let url = (item.privateContextID != nil ? self.privateDownloadContext(item)?.reviewLink(at: nativeIndex, for: displayed)
                    : PCNativeBrowserApplication.downloadReviewLink(at: nativeIndex, for: displayed)) else { return false }
            controller.dismiss()
            return self.onOpenDownloadSource?(item, url) ?? false
        }
        controller.onRefresh = { [weak self] in self?.currentDownloadReview(item) }
        controller.onClose = { [weak self, weak controller] in
            if self?.downloadReview === controller { self?.downloadReview = nil; self?.downloadReviewItem = nil }
        }
        controller.present(on: parent)
        return true
    }
    func openDownloadSourceURL(_ url: URL, profileID: UUID) -> Bool {
        guard presentation.isReady, !isClosing, !wholeWindowClose, transferringTabIDs.isEmpty,
              let window, window.attachedSheet == nil,
              ["http", "https", "parc", "chrome", "chrome-extension"].contains(url.scheme?.lowercased() ?? ""),
              let destination = (activeProfileID == profileID ? activeSpaceID :
                  store.state.spaces.first(where: { $0.profileID == profileID })?.id),
              (isPrivateBrowsing ? (nativeBinding?.privateDownloadsAvailable == true && activeProfileID == profileID && destination == activeSpaceID)
                 : selectSpaceFromUser(destination, profileID: profileID)), activeProfileID == profileID else { return false }
        closeLibrary(restoreFocus: false)
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            let id = store.open(url.absoluteString, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
    private func performNativeDownloadAction(_ command: PCNativeDownloadAction, item: BrowserDownload) -> Bool {
        guard let current = liveLibraryDownload(item), let identifier = current.nativeID,
              let itemIdentity = current.nativeIdentity, let profile = current.profileID else { return false }
        if current.privateContextID != nil {
            return privateDownloadContext(current)?.perform(command, identifier: identifier, itemIdentity: itemIdentity) ?? false
        }
        return PCNativeBrowserApplication.performDownloadAction(command, identifier: identifier,
            profilePath: downloadStore.independentEngineProfilePath(for: profile), itemIdentity: itemIdentity)
    }
    private func performLibraryDownload(_ expected: BrowserDownload, action: DownloadLibraryAction) -> Bool {
        guard let window, window.attachedSheet == nil, !isClosing, !wholeWindowClose,
              presentation.isReady, transferringTabIDs.isEmpty else { return false }
        if action == .copyLink || action == .openSource {
            guard let current = downloadStore.downloadItems.first(where: { $0.id == expected.id }),
                  current.profileID == expected.profileID, current.sourceURL == expected.sourceURL,
                  current.privateContextID == expected.privateContextID,
                  current.privateContextID == nil || privateDownloadContext(current) != nil,
                  expected.nativeIdentity == nil || current.nativeIdentity == expected.nativeIdentity,
                  let profile = current.profileID, downloadStore.state.profiles.contains(where: { $0.id == profile }),
                  !downloadStore.isProfileRemovalPending(profile), let source = current.sourceURL, let url = URL(string: source) else { return false }
            if action == .openSource { return onOpenDownloadSource?(current, url) ?? false }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(source, forType: .string) else { return false }
            showToast(.copiedCurrentURL(url), at: .window)
            return true
        }
        guard let item = liveLibraryDownload(expected), recyclingDownloads[item.id] == nil else { return false }
        if action == .review { return reviewDownload(item) }
        if action == .copyFile {
            guard let url = libraryDownloadFileURL(item) else { return false }
            NSPasteboard.general.clearContents(); return NSPasteboard.general.writeObjects([url as NSURL])
        }
        if action == .trash {
            guard item.canRemove, let url = libraryDownloadFileURL(item) else { return false }
            recyclingDownloads[item.id] = DownloadLibraryIdentity(item)
            libraryView?.setDownloadOperation(item, message: "Moving to Trash…")
            NSWorkspace.shared.recycle([url]) { [weak self] moved, error in
                let succeeded = error == nil && moved[url] != nil
                let message = error?.localizedDescription
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.recyclingDownloads.removeValue(forKey: item.id)
                    self.libraryView?.setDownloadOperation(item, message: nil)
                    guard let current = self.liveLibraryDownload(item), current.path == item.path else { return }
                    if succeeded {
                        _ = self.performNativeDownloadAction(.remove, item: item)
                    } else if let owner = self.window, !self.isClosing, owner.attachedSheet == nil {
                        ParcDialog.inform(in: owner, .init(title: "Couldn’t move the download to Trash",
                            message: message ?? "The file was not moved. Its download record has been kept."))
                    }
                }
            }
            return true
        }
        let command: PCNativeDownloadAction
        switch action {
        case .open: command = .open
        case .reveal: command = .reveal
        case .toggleOpen: command = .toggleOpen
        case .pause: command = .pause
        case .resume: command = .resume
        case .cancel: command = .cancel
        case .retry: command = .retry
        case .remove: command = .remove
        case .review, .copyFile, .copyLink, .openSource, .trash: return false
        }
        return performNativeDownloadAction(command, item: item)
    }

    private func id(for browser: PCBrowserView) -> UUID? { browsers.first { $0.value === browser }?.key }
    func browserView(_ view: PCBrowserView, openLinkInSplitView url: URL) {
        guard browserViewCanOpenLinkInSplitView(view), let id = id(for: view),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        let creation = TabCreationProvenance(referrerID: id, activeTabID: currentTabID,
                                             profileID: activeProfileID, state: store.state)
        if insertPreviewSplit(url: url, creation: creation, after: id) { return }
        if selectedTabIDs.count >= 4 { showToast(.cannotAddNewPane, at: .window) }
    }

    func browserViewCanOpenLinkInSplitView(_ view: PCBrowserView) -> Bool {
        guard let id = id(for: view), selectedTabIDs.contains(id), browserProfiles[id] == activeProfileID,
              let window, window.attachedSheet == nil, !isClosing, commandBar == nil else { return false }
        return splitCommandsAvailable && splitInsertion == nil && !isPopupWindow
            && nativeFullscreenTabID == nil && selectedTabIDs.allSatisfy({ switcherCanUse($0) })
    }

    func browserView(_ view: PCBrowserView, addContextImageToEasel image: PCNativeContextImage) {
        let embedded = view.nativePage.flatMap { embeddedEaselOwner($0) }
        guard !isPrivateBrowsing, let id = id(for: view) ?? peeks.values.first(where: { $0.browser === view })?.parentTabID ?? embedded?.0,
              let profileID = browserProfiles[id] ?? easelEditors[id]?.profileID,
              profileID == activeProfileID, selectedTabIDs.contains(id),
              let window, window.attachedSheet == nil, easelImageDestination == nil, !isClosing, image.isValid,
              let page = view.nativePage,
              page.profilePath == store.independentEngineProfilePath(for: profileID) else { return }
        do {
            let controller = try EaselImageDestinationController(image: image,
                directory: store.easelsDirectory(for: profileID),
                valid: { [weak self, weak view, weak page] in
                    guard let self, let view, let page else { return false }
                    return !self.isClosing && self.activeProfileID == profileID
                        && self.selectedNativePage() === page && view.nativePage === page
                        && (self.browserProfiles[id] ?? self.easelEditors[id]?.profileID) == profileID && self.selectedTabIDs.contains(id)
                        && !self.transferringTabIDs.contains(id) && image.isValid
                }, saved: { [weak self] documentID, title in
                    guard let self, self.activeProfileID == profileID, !self.isClosing else { return }
                    self.openEasel(id: documentID, title: title)
                }, finished: { [weak self] in self?.easelImageDestination = nil })
            easelImageDestination = controller
            controller.present(on: window)
        } catch {
            ParcDialog.inform(in: window, .init(error: error), queued: true)
        }
    }

    func browserViewDidChangeFavicon(_ view: PCBrowserView) {
        guard let id = id(for: view), !rendering, !isClosing, !wholeWindowClose else { return }
        sidebar.reloadFavicon(for: id)
        refreshFavoriteOverlays(from: presentedState)
    }
    func browserViewDidChangePageColor(_ view: PCBrowserView) {
        guard let id = id(for: view), let pane = panes[id], pane.browser === view, !isClosing, !wholeWindowClose else { return }
        pane.showPageBacking(of: view.nativePage)
        guard pane.livePage === view, !pane.browserToolbar.isHidden else { return }
        pane.browserToolbar.showPageColor(of: view.nativePage, failing: pane.showsFailure)
    }
    func browserViewDidPresentFrame(_ view: PCBrowserView) {
        guard let id = id(for: view), let pane = panes[id], pane.browser === view else { return }
        finishPageSwitch(switchHold.presented(pane))
    }
    func browserView(_ view: PCBrowserView, didChangeCaptureState state: PCNativeCaptureState?) {
        guard id(for: view) != nil, !rendering, !isClosing, !wholeWindowClose else { return }
        refreshLivePageChromeOrRender()
    }
    private var publicationRefreshesChrome: Bool {
        RunLoop.current.currentMode == .default && !promotingPeek
            && transferringTabIDs.isEmpty && collectionTransfer == nil
    }
    func browserView(_ view: PCBrowserView, didChangeTitle title: String) {
        guard let id = id(for: view) else { return }
        let revision = store.stateRevision
        store.updateTab(id, title: title)
        if store.stateRevision == revision || !publicationRefreshesChrome,
           !rendering, !isClosing, !wholeWindowClose { refreshLivePageChromeOrRender() }
    }
    func browserView(_ view: PCBrowserView, didChangeURL url: URL) {
        if selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        if view === pendingCommandSplitBrowser { cancelPendingCommandSplit() }
        if let id = id(for: view) {
            requestedURLs[id] = url.absoluteString
            let revision = store.stateRevision
            store.updateTab(id, url: url.absoluteString)
            if store.stateRevision == revision || !publicationRefreshesChrome,
               !rendering, !isClosing, !wholeWindowClose { refreshLivePageChromeOrRender() }
            scheduleTabHistoryCapture(id)
            if id == currentTabID { refreshHandoffActivity() }
        }
    }
    func browserViewDidChangeMedia(_ view: PCBrowserView) {
        guard id(for: view) != nil else { return }
        scheduleMediaRefresh()
    }
    private func scheduleMediaRefresh() {
        mediaRefresh.schedule { [weak self] in
            guard let self, !self.rendering, !self.isClosing, !self.wholeWindowClose else { return }
            self.refreshLivePageChromeOrRender()
        }
    }
    func browserView(_ view: PCBrowserView, didChangeRendererCrash crash: PCNativeRendererCrash?) {
        if selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        guard let id = id(for: view) else { return }
        refreshPagePresentation(id)
    }
    func browserView(_ view: PCBrowserView, requestFocusForRendererCrash crash: PCNativeRendererCrash) {
        guard let id = id(for: view), view.rendererCrash === crash,
              let expected = rendererPresentation(view) else { return }
        refreshPagePresentation(id)
        focusRendererFailure(id, expected)
    }
    func browserView(_ view: PCBrowserView, didChangeLoading loading: Bool, canGoBack back: Bool, canGoForward forward: Bool) {
        reconcileFind()
        if loading, selectedTabIDs.contains(where: { browsers[$0] === view }) { pageHost.cancelDrop() }
        if loading, view === pendingCommandSplitBrowser { cancelPendingCommandSplit() }
        if let id = id(for: view) {
            if loading {
                loadingTabs.insert(id)
            } else {
                loadingTabs.remove(id); scheduleCookieFlush(); scheduleTabHistoryCapture(id)
            }
            refreshLivePageChromeOrRender()
            if !loading, !rendering, !isClosing, !wholeWindowClose { sidebar.reloadFavicon(for: id) }
            if pendingNativeSelection?.view === view { attachOwnedPages() }
            if !loading, peekUndoAwaitingParent[id] != nil, !awaitedPeekRetries.contains(id) {
                DispatchQueue.main.async { [weak self] in self?.openAwaitedPeek(over: id) }
            }
        }
    }
    func browserViewDidRequestClose(_ view: PCBrowserView) {
        guard let id = id(for: view), view.nativePage?.isClosed == true else { return }
        releaseClosedTab(id, updateSavedTab: !wholeWindowClose && !modelRetirementIDs.contains(id) && !transferringTabIDs.contains(id))
    }
    func browserView(_ view: PCBrowserView, didLearnSafariIdentityForSite site: String,
                     profilePath: String, offTheRecord: Bool) {
        FairPlayIdentityController.shared.didLearn(site, profilePath: profilePath, offTheRecord: offTheRecord)
    }
    func browserView(_ view: PCBrowserView, didFailWithError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        if let id = id(for: view) {
            if view.rendererCrash == nil { failures[id] = error.localizedDescription }
            loadingTabs.remove(id)
            refreshPagePresentation(id)
            updateNavigation()
        }
    }
    func shutdownBrowsers() {
        guard !isClosing else { return }
        guard browsers.values.allSatisfy({ $0.nativePage == nil || $0.nativePage?.isClosed == true }),
              peeks.values.allSatisfy({ $0.page.isClosed }) else {
            NSLog("Parc refused window disposal with live native pages")
            return
        }
        isClosing = true
        store.placeholderImages.removeWindow(presentationID)
        placeholderCapturesPending.removeAll()
        stopLibraryFlyoutFileQuery()
        archiveActivityScheduling.cancel()
        for peek in peeks.values { peek.finish() }; peeks.removeAll()
        archivePreviews.values.forEach(store.releaseArchivePreview); archivePreviews.removeAll()
        if let request = archivePreviewRequest { store.releaseArchivePreview(request.lease) }
        archivePreviewRequest = nil; queuedArchivePreview = nil; archivePreviewRemnants.removeAll()
        sidebarPreviews?.shutdown(); sidebarPreviews = nil
        settleSidebarMotion()
        libraryMotion.cancel()
        if let sidebarAccessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sidebarAccessibilityObserver)
            self.sidebarAccessibilityObserver = nil
        }
        pendingNativeSelection = nil
        dismissSiteControlCenter()
        themePopover?.performClose(nil)
        sidebarHover.invalidate()
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }; menuObservers.removeAll()
        commandBar?.dismiss()
        for view in browsers.values { view.delegate = nil; view.removeFromSuperview() }
        browsers.removeAll()
        ownership.releaseAll(owner: presentationID)
        subscription = nil
        developerModeSubscription = nil
        toolbarSubscription = nil
        windowDraggingSubscription = nil
        websiteThemeSubscription = nil
        for pane in panes.values { pane.windowGrabber.configure(owner: nil, revision: 0, isCurrent: nil, eligibility: nil) }
        for (id, pane) in easelEditors { pane.editor.retirePageOwner(); panes[id]?.clearNativeContent() }
        easelEditors.removeAll(); easelFailures.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
    }
    @objc func nativeBrowserCreationReservationDidAbort(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding, nativeWindowRequest != nil || preparedForRoutedPage,
              !presentation.isReady, browsers.isEmpty, !isClosing else { return }
        retireEmptyNativeWindow()
    }
    @objc func nativeBrowserDidReleaseLastBrowser(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding, nativeWindowRequest != nil || preparedForRoutedPage || isPrivateBrowsing, !isClosing else { return }
        guard !presentation.hasPlaceholders else { return }
        retireEmptyNativeWindow()
    }
    private func retireEmptyNativeWindow() {
        guard settings?.window?.isVisible != true,
              settings?.window?.attachedSheet == nil else { return }
        windowCloseApproved = true
        windowClosePending = false
        wholeWindowClose = true
        window?.close()
    }
    func prepareForApplicationClose() { wholeWindowClose = true }
    func cancelApplicationClose() {
        wholeWindowClose = false
        if restoreSettingsAfterCancelledTermination { settings?.restoreAfterCancelledOwnerClose() }
        restoreSettingsAfterCancelledTermination = false
        render(store.state)
    }
    func ownsSettings(_ candidate: SettingsWindow) -> Bool { settings === candidate }
    func prepareAuxiliaryWindowForOnboarding(completion: @escaping (Bool) -> Void) {
        guard isPrivateBrowsing || isPopupWindow, hasReadyPresentation, let window,
              window.attachedSheet == nil, !isClosing, !wholeWindowClose,
              !windowClosePending, !windowCloseApproved, let binding = nativeBinding else {
            completion(false); return
        }
        func pages() -> [PCNativePage] {
            Array(browsers.values.compactMap(\.nativePage)) + peeks.values.map(\.page)
                + easelEditors.values.flatMap { $0.editor.pageObjects?.pages ?? [] }
        }
        func hasStableOwners() -> Bool {
            collectionTransfer == nil && transferRecoveries.isEmpty && transferringTabIDs.isEmpty
                && resolvingTransfers.isEmpty && transferContainers.isEmpty
                && !hasPendingNativePage(in: Set(browsers.keys).union(easelEditors.keys))
        }
        guard hasStableOwners() else { completion(false); return }
        let originals = pages()
        let identities = Set(originals.map(ObjectIdentifier.init))
        guard identities.count == originals.count else { completion(false); return }
        windowClosePending = true
        func isCurrent() -> Bool {
            self.window === window && self.nativeBinding === binding && !isClosing && !wholeWindowClose
                && windowClosePending && hasStableOwners()
                && Set(pages().map(ObjectIdentifier.init)) == identities
                && originals.allSatisfy { !$0.isClosed && PCNativeBrowserApplication.owner(of: $0) === binding }
        }
        var consented = false
        PCNativeBrowserApplication.requestClosePages(originals, shouldCommit: {
            MainActor.assumeIsolated {
                consented = isCurrent()
                return false
            }
        }, completion: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { completion(false); return }
                let approved = consented && isCurrent()
                self.windowClosePending = false
                completion(approved)
            }
        })
    }
    func closeForOnboarding(completion: @escaping (Bool) -> Void) {
        guard hasReadyPresentation, let window, window.attachedSheet == nil,
              !isClosing, !wholeWindowClose, !windowClosePending,
              !windowCloseApproved, nativeBinding != nil else { completion(false); return }
        onboardingCloseRequested = true
        scriptingWindowCloseCompletions.append { [weak self] approved in
            if let self {
                if !approved {
                    for saved in self.onboardingCloseNotes ?? [] {
                        saved.editor.text.isEditable = saved.bodyEditable && !saved.editor.session.document.deleted
                        saved.editor.titleText.isEditable = saved.titleEditable && !saved.editor.session.document.deleted
                        saved.editor.view.needsLayout = true
                    }
                }
                self.onboardingCloseNotes = nil
                self.onboardingCloseRequested = false
            }
            completion(approved)
        }
        window.performClose(nil)
        if !windowClosePending && !windowCloseApproved && !closeAfterEjecting && !pendingApprovedWindowClose {
            finishScriptingWindowClose(false)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return false }
        if windowCloseApproved, onboardingCloseNotes != nil { return true }
        guard !windowClosePending else { return false }
        func refuse() -> Bool { finishScriptingWindowClose(false); return false }
        guard prepareNotesToClose() else { return refuse() }
        if let transfer = collectionTransfer { transfer.retry(); return refuse() }
        if let retry = transferRecoveries.values.first { retry(); return refuse() }
        guard transferringTabIDs.isEmpty else { return refuse() }
        if windowCloseApproved {
            guard settings?.attemptClose() ?? true else {
                pendingApprovedWindowClose = true
                return false
            }
            pendingApprovedWindowClose = false
            return true
        }
        guard let binding = nativeBinding else { return refuse() }
        if ejectPageBeforeClose() { return false }
        let settingsWasVisible = settings?.window?.isVisible == true
        guard settings?.attemptClose() ?? true else {
            finishScriptingWindowClose(false)
            return false
        }
        if onboardingCloseRequested {
            guard prepareNotesToClose() else { return refuse() }
            onboardingCloseNotes = noteEditors.values.map { note in
                let editor = note.editor
                let saved = (editor: editor, bodyEditable: editor.text.isEditable,
                             titleEditable: editor.titleText.isEditable)
                editor.text.isEditable = false
                editor.titleText.isEditable = false
                editor.view.needsLayout = true
                return saved
            }
        }
        windowClosePending = true
        wholeWindowClose = true
        binding.requestClose { [weak self, weak sender] allowed in
            guard let self else { return }
            self.windowClosePending = false
            if allowed {
                self.windowCloseApproved = true
                sender?.performClose(nil)
            } else {
                self.wholeWindowClose = false
                self.render(self.store.state)
                if settingsWasVisible { self.settings?.restoreAfterCancelledOwnerClose() }
                self.finishScriptingWindowClose(false)
            }
        }
        return false
    }
    private func ejectPageBeforeClose() -> Bool {
        for id in heldContentIDs.sorted(by: { $0.uuidString < $1.uuidString })
        where !ejectionAttempts.contains(id) && canHandOverPage(id) {
            ejectionAttempts.insert(id)
            if onUntargetedReturn?(id, self, .ownerClosing) == .started { closeAfterEjecting = true; return true }
        }
        ejectionAttempts.removeAll()
        return false
    }
    private func resumeCloseAfterEjecting() {
        guard closeAfterEjecting else { return }
        closeAfterEjecting = false
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isClosing, let window = self.window else { return }
            window.performClose(nil)
        }
    }
    private func retryPendingSettingsClose() {
        guard !isClosing else { return }
        if pendingApprovedWindowClose { window?.performClose(nil) }
    }
    func windowWillClose(_ notification: Notification) { abandonFrameCrank(); archiveEducationSubscription?.cancel(); updateCompleteSubscription?.cancel(); updateReadySubscription?.cancel(); sidebar.resetAutoArchiveEducation(); sidebar.resetUpdateComplete(); sidebar.resetUpdateReady(); loadingIndicator.reset(); paneFrameObservers.values.forEach(NotificationCenter.default.removeObserver); paneFrameObservers.removeAll(); if isPrivateBrowsing { store.clearPrivateDownloads() }; if let session = spaceCreation { finishSpaceCreation(session) }; pageHost.cancelDrop(); favoriteRename?.cancel(); favoriteSplitRename?.cancel(); splitIconPicker?.cancel(); spaceIconPicker?.cancel(); sidebar.cancelSpaceNameEditing(); noteExport?.cancel(); dismissSidebarMoveNotice(); sharedQuotes.invalidate(); noteEditors.removeAll(); closedItems = WindowClosedItems(); peekRedo = nil; peekUndoOpen = nil; peekUndoAwaitingParent.removeAll(); awaitedPeekRetries.removeAll(); undoHiddenPeek = nil; retiringPageHistory.removeAll(); folderUndo.removeAllActions(); nativeEditingUndo.removeAllActions(); finishScriptingWindowClose(true); pageCapture?.dismiss(restoreFocus: false); navigationHistory?.dismiss(); shortcutEssentials?.close(); tabSwitcher?.cancel(); libraryMotion.cancel(); libraryView?.removeFromSuperview(); libraryView = nil; libraryContentWidth = 0; easelImageDestination?.dismiss(); downloadReview?.dismiss(); downloadArrival.dismiss(force: true); dismissSiteControlCenter(); addressPromptHolds.values.forEach { $0.end() }; if let bar = residentCommandBar { residentCommandBar = nil; bar.dismiss(restoreFocus: false) }; shutdownBrowsers(); userActivity?.invalidate(); userActivity = nil; onClose?() }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { splitLinkGeneration &+= 1 }
        pageHost.cancelDrop()
        refreshDeveloperToolbars()
        cancelPendingCommandSplit()
        sidebar.updateSpaceAvailability()
        sidebarPreviews?.dismiss()
        refreshSidebarPointer()
    }
    func windowDidEndSheet(_ notification: Notification) {
        if !rendering, !isClosing { updateNavigation() }
        refreshSidebarPointer()
    }
}


extension SidebarView: SidebarKeyViewEnds {}

private final class PendingArrival {
    var ran = false
    private let abandoned: () -> Void
    init(abandoned: @escaping () -> Void) { self.abandoned = abandoned }
    deinit {
        guard !ran else { return }
        DispatchQueue.main.async(execute: abandoned)
    }
}

private final class BrowserPane: NSView {
    let content = LayoutView()
    private(set) var loadedDeveloperToolbar: DeveloperToolbarView?
    var developerToolbar: DeveloperToolbarView {
        if let loadedDeveloperToolbar { return loadedDeveloperToolbar }
        let toolbar = DeveloperToolbarView()
        toolbar.isHidden = true
        addSubview(toolbar, positioned: .below, relativeTo: browserToolbar)
        loadedDeveloperToolbar = toolbar
        return toolbar
    }
    let browserToolbar = BrowserToolbarView()
    let windowGrabber = WebpageWindowGrabber()
    private let controlVisibility = PaneControlVisibility()
    let splitHighlight = SplitPaneHighlight()
    var controlsFocused = true { didSet { needsLayout = true } }
    var controlsObstructed = false {
        didSet {
            guard oldValue != controlsObstructed else { return }
            browserToolbar.setObstructedByModal(controlsObstructed, animated: true); needsLayout = true
        }
    }
    func trackSplitMenu(_ body: () -> Void) { controlVisibility.trackMenu(body) }
    private let error = PageFailureView()
    private var nativeContent: NSView?
    private(set) var showsBlank = false
    private(set) var showsNoteCanvas = false
    private(set) var showsTopBar = false
    private var noteCanvasContentAppearance: NSAppearance?
    var onContentBackingChange: (() -> Void)?
    private var pageBacking: NSColor?
    var contentBacking: NSColor { showsNoteCanvas ? .clear : (surface == .page ? pageBacking : nil) ?? .white }
    var heldOverSwitch = false {
        didSet {
            guard heldOverSwitch != oldValue else { return }
            HeldPaneLayout.apply(heldOverSwitch, to: self)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { heldOverSwitch ? nil : super.hitTest(point) }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        heldOverSwitch = false; super.viewWillMove(toSuperview: newSuperview)
    }
    func showPageBacking(of page: PCNativePage?) {
        let color = page.flatMap { page -> NSColor? in
            guard !page.isClosed, page.responds(to: #selector(getter: PCNativePage.pageBackgroundColor)) else { return nil }
            return PaneTopBarColor.fill(from: page.pageBackgroundColor)
        }
        guard color != pageBacking else { return }
        pageBacking = color
        applyContentBacking()
    }
    private func applyContentBacking() {
        let color = contentBacking.cgColor
        guard content.layer?.backgroundColor != color else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        content.layer?.backgroundColor = color
        CATransaction.commit()
        onContentBackingChange?()
    }
    let contentResize = PageContentResizer()
    var browser: PCBrowserView? { didSet { oldValue?.removeFromSuperview(); error.pageView = browser; if let browser { content.addSubview(browser); contentResize.place(browser, in: content) } } }
    private var surface = PaneSurface.page {
        didSet {
            guard surface != oldValue else { return }
            applyContentBacking()
            guard !browserToolbar.isHidden else { return }
            browserToolbar.showPageColor(of: livePage?.nativePage, failing: showsFailure)
        }
    }
    var livePage: PCBrowserView? {
        guard let browser, surface.usesPageBar(pageLive: browser.nativePage.map { !$0.isClosed } == true) else { return nil }
        return browser
    }
    var showsFailure: Bool { surface == .failure }
    var showsLocalContent: Bool { surface == .local }
    var onReload: (() -> Void)? { didSet { error.onReload = onReload } }
    var onRetryRenderer: ((RendererCrashPresentation) -> Void)? { didSet { error.onRetryRenderer = onRetryRenderer } }
    var onRendererPresented: ((RendererCrashPresentation) -> Bool)? { didSet { error.onRendererPresented = onRendererPresented } }
    var rendererPresentation: RendererCrashPresentation? {
        if case .renderer(let crash) = error.presentation { return crash }
        return nil
    }
    var rendererFailureOwnsFocus: Bool { rendererPresentation != nil && error.ownsFirstResponder }
    func focusRendererFailure(_ crash: RendererCrashPresentation) { error.focusRendererAction(crash) }
    var contentBounds: NSRect { content.bounds }
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true; content.wantsLayer = true; content.layer?.backgroundColor = NSColor.white.cgColor
        splitHighlight.attach(to: self)
        addSubview(content); addSubview(windowGrabber)
        browserToolbar.isHidden = true; addSubview(browserToolbar)
        content.addSubview(error); error.isHidden = true
        controlVisibility.onChange = { [weak self] revealed, duration in
            self?.browserToolbar.setControlsRevealed(revealed, duration: duration)
        }
        content.onLayout = { [weak self] in
            guard let self else { return }
            self.error.frame = self.content.bounds
            if let browser = self.browser { self.contentResize.place(browser, in: self.content) }
            self.nativeContent?.frame = self.content.bounds
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layout() {
        super.layout()
        let developerHeight: CGFloat = loadedDeveloperToolbar?.isHidden == false ? DeveloperToolbarLayout.height : 0
        let toolbarHeight: CGFloat = browserToolbar.isHidden ? 0 : BrowserToolbarView.height
        let headerHeight = max(developerHeight, toolbarHeight)
        if showsTopBar != !browserToolbar.isHidden { showsTopBar = !browserToolbar.isHidden; onContentBackingChange?() }
        browserToolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbarHeight)
        loadedDeveloperToolbar?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: developerHeight)
        let nextContent = NSRect(x: 0, y: headerHeight, width: bounds.width, height: bounds.height - headerHeight)
        let contentMoved = content.frame != nextContent
        content.frame = nextContent
        if contentMoved { content.needsLayout = true }
        if PaneContentHostedLayoutFlush.shouldLayoutContent(
            frameChanged: contentMoved, needsLayout: content.needsLayout
        ) {
            content.layout()
        }
        for child in content.subviews
            where PaneContentHostedLayoutFlush.shouldLayoutChild(needsLayout: child.needsLayout) {
            child.layoutSubtreeIfNeeded()
        }
        windowGrabber.frame = WebpageWindowDragState.region(in: bounds, topStripHeight: headerHeight)
        let bar = headerHeight == PaneTopBarLayout.height ? NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight) : nil
        controlVisibility.update(host: self, bar: bar, focused: controlsFocused, obstructed: controlsObstructed)
        splitHighlight.layout(bounds: bounds, cornerRadius: layer?.cornerRadius ?? 0)
    }
    override func viewDidHide() { super.viewDidHide(); controlVisibility.invalidate() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        controlVisibility.invalidate(); super.viewWillMove(toWindow: newWindow)
    }
    func showNativeContent(_ view: NSView) {
        hidePlaceholder()
        if nativeContent !== view {
            clearNativeContent()
            nativeContent = view
            content.addSubview(view)
            view.autoresizingMask = [.width, .height]
        }
        view.frame = content.bounds; view.isHidden = false
        error.clear(); browser?.isHidden = true; showsBlank = false
        surface = .local
        setNoteCanvasBacking(view is NoteCanvasView)
        applyNoteCanvasTheme()
    }
    func inheritNoteCanvasTheme(_ appearance: NSAppearance?) {
        noteCanvasContentAppearance = appearance
        applyNoteCanvasTheme()
    }
    private func applyNoteCanvasTheme() {
        if let canvas = nativeContent as? NoteCanvasView {
            canvas.inheritSpaceContentAppearance(noteCanvasContentAppearance)
        } else if let easel = nativeContent as? EaselDocumentView {
            easel.inheritSpaceContentAppearance(noteCanvasContentAppearance)
        }
    }
    private func setNoteCanvasBacking(_ visible: Bool) {
        guard showsNoteCanvas != visible else { return }
        showsNoteCanvas = visible
        content.layer?.backgroundColor = contentBacking.cgColor
        applyNoteCanvasTheme()
        onContentBackingChange?()
    }
    func clearNativeContent() { nativeContent?.removeFromSuperview(); nativeContent = nil; setNoteCanvasBacking(false) }
    func showBlank() { hidePlaceholder(); error.clear(); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = true; surface = .local; setNoteCanvasBacking(false) }
    func showBrowser() {
        hidePlaceholder(); error.clear(); browser?.isHidden = false; nativeContent?.isHidden = true; showsBlank = false; surface = .page; setNoteCanvasBacking(false)
        showPageBacking(of: browser?.nativePage)
    }
    func showError(_ message: String) { hidePlaceholder(); error.showNavigationFailure(message); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false; surface = .failure; setNoteCanvasBacking(false) }
    private var placeholder: PagePlaceholderView?
    private var placeholderSnapshot: CGImage?
    private(set) var showsPlaceholder = false
    func showPlaceholder(_ snapshot: CGImage?, title: String, onClick: @escaping () -> Void) {
        let view = placeholder ?? PagePlaceholderView(frame: content.bounds)
        if view.superview !== content || content.subviews.last !== view { content.addSubview(view) }
        placeholder = view
        view.autoresizingMask = [.width, .height]; view.frame = content.bounds; view.isHidden = false
        view.onClick = onClick; view.setAccessibilityLabel(title)
        error.clear(); browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false
        surface = .local; setNoteCanvasBacking(false)
        if snapshot !== placeholderSnapshot || !showsPlaceholder {
            view.show(snapshot)
            placeholderSnapshot = snapshot
        }
        guard !showsPlaceholder else { return }
        showsPlaceholder = true
        if let layer { PagePlaceholderDim.apply(true, to: layer, animated: window != nil) }
        onContentBackingChange?()
    }
    private func hidePlaceholder() {
        guard showsPlaceholder else { return }
        showsPlaceholder = false
        placeholder?.removeFromSuperview(); placeholder = nil; placeholderSnapshot = nil
        if let layer { PagePlaceholderDim.apply(false, to: layer, animated: window != nil) }
        onContentBackingChange?()
    }
    func showRendererFailure(_ crash: RendererCrashPresentation) {
        hidePlaceholder()
        error.showRendererFailure(crash)
        browser?.isHidden = true; nativeContent?.isHidden = true; showsBlank = false
        surface = .failure
        setNoteCanvasBacking(false)
    }
}

extension BrowserPane: SplitLayoutFollowing {
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { splitHighlight.followLayout(from: previous, animation: animation) }
    func cancelSplitLayoutFollow() { splitHighlight.cancelFollow() }
}

extension SplitPanePlaceholder: SplitLayoutFollowing {
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { splitHighlight.followLayout(from: previous, animation: animation) }
    func cancelSplitLayoutFollow() { splitHighlight.cancelFollow() }
}


extension BrowserWindowController: BrowserScriptOwner {
    var scriptingID: UUID { presentationID }
    var scriptingIsIncognito: Bool { isPrivateBrowsing }
    var scriptingWindow: NSWindow? { window }
    var scriptingAvailable: Bool {
        guard presentation.isReady, !isClosing, !preparedForRoutedPage,
              scriptingAuthorization?() == true, let nativeBinding else { return false }
        if isPrivateBrowsing {
            return !isPopupWindow && nativeBinding.isPrivateBrowsing && nativeBinding.browsingContextKind == .offTheRecord
        }
        let origin: ScriptWindowOrigin
        if let request = nativeWindowRequest {
            origin = request.isOffTheRecord ? .offTheRecord : request.kind == .browser ? .nativeBrowser : .auxiliary
        } else { origin = .application }
        let context: ScriptWindowContext
        switch nativeBinding.browsingContextKind {
        case .regular: context = .regular
        case .offTheRecord: context = .offTheRecord
        case .mixed: context = .mixed
        case .unavailable: context = .unavailable
        @unknown default: return false
        }
        return scriptWindowHasNormalOwner(origin: origin, context: context)
    }
    var scriptingActiveTabID: UUID? { currentTabID }
    var scriptingActiveSpaceID: UUID { activeSpaceID }
    var scriptingSpaces: [ScriptSpaceRecord] {
        guard scriptingAvailable else { return [] }
        return store.state.spaces.filter { !store.isProfileRemovalPending($0.profileID) }
            .map { ScriptSpaceRecord(id: $0.id, profileID: $0.profileID, title: $0.name) }
    }
    private func scriptingRecord(_ tab: BrowserTab) -> ScriptTabRecord {
        let browser: PCBrowserView? = {
            guard let browser = browsers[tab.id], browserProfiles[tab.id] == tab.profileID,
                  let page = browser.nativePage, !page.isClosed,
                  page.profilePath == store.independentEngineProfilePath(for: tab.profileID),
                  page.observer === browser, let binding = nativeBinding,
                  PCNativeBrowserApplication.owner(of: page) === binding else { return nil }
            return browser
        }()
        let location = tab.kind == .favorite ? "topApp" : tab.kind == .pinned ? "pinned" : "unpinned"
        return ScriptTabRecord(id: tab.id, profileID: tab.profileID,
            title: browser.map { $0.title.isEmpty ? tab.title : $0.title } ?? tab.title,
            url: browser?.url?.absoluteString ?? tab.url,
            loading: browser?.isLoading ?? false, location: location)
    }
    var scriptingTabs: [ScriptTabRecord] {
        guard scriptingAvailable else { return [] }
        return store.state.tabs.filter { tab in
            tab.archivedAt == nil && !store.isProfileRemovalPending(tab.profileID)
                && ownership.canUse(tab.id, owner: presentationID)
                && store.state.spaces.contains { $0.id == tab.spaceID && $0.profileID == tab.profileID }
        }.map(scriptingRecord)
    }
    func scriptingTabs(in space: UUID, profile: UUID) -> [ScriptTabRecord] {
        guard scriptingSpaces.contains(where: { $0.id == space && $0.profileID == profile }) else { return [] }
        let ids = Set(store.state.tabs.filter {
            $0.profileID == profile && ($0.spaceID == space || $0.kind == .favorite)
        }.map(\.id))
        return scriptingTabs.filter { ids.contains($0.id) }
    }
    private func scriptingCheck() throws {
        guard scriptingAvailable else { throw BrowserScriptError.missing }
        guard !wholeWindowClose, !windowClosePending, !windowCloseApproved,
              transferringTabIDs.isEmpty, resolvingTransfers.isEmpty, transferRecoveries.isEmpty,
              window?.attachedSheet == nil, NSApp.modalWindow == nil else { throw BrowserScriptError.busy }
    }
    private func scriptingTab(_ id: UUID, profile: UUID) throws -> BrowserTab {
        try scriptingCheck()
        guard let tab = store.state.tabs.first(where: { $0.id == id && $0.profileID == profile && $0.archivedAt == nil }),
              !store.isProfileRemovalPending(profile), ownership.canUse(id, owner: presentationID) else { throw BrowserScriptError.missing }
        guard !closingTabIDs.contains(id), !transferringTabIDs.contains(id),
              !modelRetirementIDs.contains(id), !store.retiringTabIDs.contains(id),
              !peekRetirementParents.contains(id) else { throw BrowserScriptError.busy }
        return tab
    }
    private func scriptingBrowser(_ id: UUID, profile: UUID) throws -> PCBrowserView {
        _ = try scriptingTab(id, profile: profile)
        guard let browser = browsers[id], browserProfiles[id] == profile,
              let page = browser.nativePage, !page.isClosed,
              page.profilePath == store.independentEngineProfilePath(for: profile),
              page.observer === browser, let binding = nativeBinding,
              PCNativeBrowserApplication.owner(of: page) === binding else {
            throw BrowserScriptError.unsupported("This tab has no live browser page. Select it before issuing a page command.")
        }
        return browser
    }
    func scriptingPerform(_ action: ScriptTabAction, tab id: UUID, profile: UUID) throws {
        _ = try scriptingTab(id, profile: profile)
        if action == .select {
            guard activePeek == nil else { throw BrowserScriptError.busy }
            commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
            guard selectTab(id) else { throw BrowserScriptError.busy }
            focusSelectedLocalContent()
            return
        }
        let browser = try scriptingBrowser(id, profile: profile)
        switch action {
        case .back: if browser.canGoBack { browser.goBack() }
        case .forward: if browser.canGoForward { browser.goForward() }
        case .reload: browser.reload()
        case .stop: browser.stop()
        case .select: break
        }
    }
    func scriptingExecuteJavaScript(_ script: String, tab id: UUID, profile: UUID,
        completion: @escaping (Result<String?, Error>) -> Void) throws -> () -> Void {
        let browser = try scriptingBrowser(id, profile: profile)
        guard let page = browser.nativePage else { throw BrowserScriptError.missing }
        let execution = page.executeAppleEventJavaScript(script) { [weak self, weak browser, weak page] result in
            guard let self, let browser, let page,
                  (try? self.scriptingBrowser(id, profile: profile)) === browser,
                  browser.nativePage === page else {
                completion(.failure(BrowserScriptError.missing)); return
            }
            if result.errorNumber != 0 {
                completion(.failure(BrowserScriptError.execution(
                    result.errorMessage ?? "The JavaScript request could not finish.", result.errorNumber)))
            } else { completion(.success(result.json)) }
        }
        return { execution.cancel() }
    }

    func scriptingNavigate(_ url: URL, tab id: UUID, profile: UUID) throws {
        let url = try BrowserScriptError.url(url.absoluteString)
        let browser = try scriptingBrowser(id, profile: profile)
        inputRevisions.removeValue(forKey: id); pendingSearchNavigations.removeValue(forKey: id)
        browser.loadURL(url)
    }
    func scriptingMakeTab(_ url: URL, space: UUID?, profile: UUID?) throws -> ScriptTabRecord {
        try scriptingCheck()
        guard activePeek == nil else { throw BrowserScriptError.busy }
        let destination = space ?? activeSpaceID
        guard let target = scriptingSpaces.first(where: { $0.id == destination && (profile == nil || $0.profileID == profile) }) else {
            throw BrowserScriptError.missing
        }
        let url = try BrowserScriptError.url(url.absoluteString)
        commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
        if activeSpaceID != destination { selectSpace(destination) }
        guard activeSpaceID == target.id, activeProfileID == target.profileID else { throw BrowserScriptError.busy }
        let id = UUID()
        let creation = creationProvenance(activeTabID: currentTabID)
        performWindowCommand {
            store.openResolvedURL(url, id: id, creation: creation)
            presentation.recordCreation(id, state: store.state)
        }
        guard let result = scriptingTabs.first(where: { $0.id == id && $0.profileID == target.profileID }) else { throw BrowserScriptError.busy }
        return result
    }
    func scriptingFocus(space: UUID, profile: UUID) throws {
        try scriptingCheck()
        guard activePeek == nil, nativeFullscreenTabID == nil else { throw BrowserScriptError.busy }
        guard scriptingSpaces.contains(where: { $0.id == space && $0.profileID == profile }) else { throw BrowserScriptError.missing }
        commandBar?.dismiss(); navigationHistory?.dismiss(); closeLibrary(restoreFocus: false)
        if activeSpaceID != space { selectSpace(space) }
        guard activeSpaceID == space else { throw BrowserScriptError.busy }
        requestNativeSelection(); focusSelectedLocalContent()
    }
    func scriptingClose(tab: UUID?, profile: UUID?, completion: @escaping (Bool) -> Void) throws {
        try scriptingCheck()
        if let tab, let profile {
            _ = try scriptingTab(tab, profile: profile)
            closeTabsWithReopen([tab], shouldCommit: { [weak self] in
                guard let self, !self.isClosing, !self.wholeWindowClose,
                      self.ownership.canUse(tab, owner: self.presentationID) else { return false }
                return self.store.state.tabs.contains { $0.id == tab && $0.profileID == profile && $0.archivedAt == nil }
            }, completion: completion)
        } else {
            guard let window, window.styleMask.contains(.closable), nativeBinding != nil else { throw BrowserScriptError.busy }
            scriptingWindowCloseCompletions.append(completion)
            window.performClose(nil)
        }
    }
    private func finishScriptingWindowClose(_ approved: Bool) {
        let callbacks = scriptingWindowCloseCompletions
        scriptingWindowCloseCompletions.removeAll()
        callbacks.forEach { $0(approved) }
    }
}

extension BrowserWindowController: PCNativeStatusTextThemeSource {
    func statusTextThemeBackgroundColor() -> NSColor? { rootView.palette.background }
    func statusTextThemeAppearance() -> NSAppearance? {
        NSAppearance(named: rootView.palette.isDark ? .darkAqua : .aqua)
    }
}

extension BrowserWindowController: PCNativeAirPlayThemeSource {
    func airPlayThemeTintColor() -> NSColor? {
        ThemeChromePalette.airPlayOnDarkSurfaceColor(theme: rootView.paletteTheme)
    }
    func airPlayThemeTintColorOnLightSurface() -> NSColor? {
        ThemeChromePalette.airPlayOnLightSurfaceColor(theme: rootView.paletteTheme)
    }
}

extension PCNativePage {
    var developerModeSiteHost: String? {
        if let host = developerModeHost { return host }
        guard responds(to: #selector(getter: PCNativePage.developerModeExtensionHost)) else { return nil }
        return developerModeExtensionHost?.lowercased()
    }
}

extension BrowserWindowController: TopBarColorWindow {}
