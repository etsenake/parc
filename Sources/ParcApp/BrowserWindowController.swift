import AppKit
import Combine

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSPopoverDelegate, PCBrowserViewDelegate, NSSearchFieldDelegate, PCNativeBrowserWindowClient {
    let store: BrowserStore
    var isPrivateBrowsing: Bool { store.isEphemeral }
    let nativeWindowRequest: PCNativeWindowRequest?
    var isPopupWindow: Bool { nativeWindowRequest?.kind == .popup }
    let popupChrome = PopupChromeView()
    let ownership: NativePageOwnership
    let folderUndo = FolderUndoManager()
    let closeUndoOperations = NSHashTable<ClosedTabsUndoOperation>.weakObjects()
    let peekUndoOperations = NSHashTable<ClosedPeekUndoOperation>.weakObjects()
    var peekRedo: (peek: UUID, done: (ClosedPeekRecord?) -> Void)?
    var peekUndoOpen: (parent: String, operation: ClosedPeekUndoOperation, token: UUID)? {
        didSet {
            guard oldValue != nil, peekUndoOpen == nil else { return }
            let retry = peekUndoSlotWaiters.release(selected: selectedTabIDs)
            guard !retry.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in retry.forEach { self?.openAwaitedPeek(over: $0) } }
        }
    }
    var peekUndoSlotWaiters = PeekUndoSlotWaiters()
    var peekUndoAwaitingParent: [UUID: ClosedPeekUndoOperation] = [:]
    var awaitedPeekRetries: Set<UUID> = []
    var undoHiddenPeek: UUID?
    var retiringPageHistory: [UUID: NSObject] = [:]
    var closedItems = WindowClosedItems()
    let nativeEditingUndo = UndoManager()
    lazy var folderUndoKeyItem: NSMenuItem = {
        let item = NSMenuItem(title: "Undo", action: #selector(performFolderUndoCommand(_:)), keyEquivalent: "")
        item.target = self
        return item
    }()
    let presentationID = UUID()
    let sessionID: UUID
    var splitLinkGeneration: UInt64 = 0
    var presentation: WindowPresentation {
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

    func schedulePresentationSessionRecord() {
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
    var presentedState: BrowserState { presentation.projected(store.state) }
    var selectedTabIDs: [UUID] { presentation.selectedTabIDs }
    var activeSpace: BrowserSpace {
        store.state.spaces.first { $0.id == activeSpaceID } ?? store.state.spaces[0]
    }
    var visibleTabs: [BrowserTab] {
        store.state.openTabs(where: { $0.profileID == activeSpace.profileID && ($0.kind == .favorite || $0.spaceID == activeSpaceID) })
    }
    var activeSplitLayout: BrowserSplitLayout? {
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
    let rootView = ThemeRendererView()
    let sidebarContainer = ThemeRendererView()
    let sidebar = SidebarView()
    let sidebarHover = SidebarHoverTracker()
    var spaceCreation: SpaceCreationSession?
    @MainActor final class SpaceCreationSession {
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
    weak var sidebarMoveToast: ParcToastPresentation?
    var sidebarPreviews: SidebarPreviewController?
    var contentFocusRequest: ContentFocusRequest?
    let pageHost = ExternalSplitDropHost()
    let pageShadow = PageCardShadowView()
    let extensionSidePanel = ExtensionSidePanelView()
    let parkedPages = LayoutView()
    let splitView = ParcSplitView()
    let splitMarginHandle = SplitMarginHandleView()
    var splitDropView: SplitDropView?
    var splitDropReplacementID: UUID?
    var foreignSplitDropView: SplitDropView?
    var interProfileDialog: InterProfileMoveDialog?
    let loadingIndicator = PageLoadingIndicatorHost()
    let peekLayer = PeekLayerView()
    lazy var peekStepBack = PeekStepBack([pageHost, pageShadow])
    var paneFrameObservers: [UUID: NSObjectProtocol] = [:]
    let findHost = PageFindView(frame: .zero)
    lazy var windowKeyViews = WindowKeyViewLoop(
        root: rootView, sidebar: sidebar,
        excluded: { [sidebarContainer, parkedPages, pageHost, peekLayer, weak self] in
            EaselBrowserObjects.excludesFromKeyboardNavigation($0) ||
            WindowKeyViewLoop.windowExcludes($0, sidebarContainer: sidebarContainer, parkedPages: parkedPages,
                                             pageHost: pageHost, peekLayer: peekLayer, activePeek: { self?.activePeek?.view })
        },
        isPage: { [extensionSidePanel] in $0 is PCBrowserView || $0 === extensionSidePanel.content },
        passesThrough: { $0 is PeekHostView })
    var findField: NSTextField { findHost.field }
    var findStates: [String: BrowserFindState<PCNativePage>] = [:]
    var visibleFind: BrowserFindState<PCNativePage>?
    var subscription: AnyCancellable?
    var archiveEducationSubscription: AnyCancellable?
    var updateCompleteSubscription: AnyCancellable?
    var updateReadySubscription: AnyCancellable?
    var developerModeSubscription: AnyCancellable?
    var windowDraggingSubscription: AnyCancellable?
    var toolbarSubscription: AnyCancellable?
    var websiteThemeSubscription: AnyCancellable?
    var pinnedSectionSubscription: AnyCancellable?
    var lastPushedWebsiteTheme: (binding: ObjectIdentifier, stylesheet: String?)?
    private var shortcutDiscoverySubscription: AnyCancellable?
    private var windowFrameSubscription: AnyCancellable?
    var windowFrameLayoutPending = false
    var windowFrameAdjustApplied = false
    var frameCrank: WindowFrameCrankView?
    static weak var frameCrankOwner: BrowserWindowController?
    var onFrameCrankFinished: (() -> Void)?
    private var lastAppliedShortcutTooltipDiscovery: String?
    var browsers: [UUID: PCBrowserView] = [:] {
        didSet {
            for id in browsers.keys where oldValue[id] == nil {
                store.closedPageHistory.pageCreated(id)
                store.tabHistory?.pageCreated(id)
            }
        }
    }
    var tabHistoryCapture: DispatchWorkItem?
    var tabHistoryChanged = Set<UUID>()
    var cookieFlush: DispatchWorkItem?
    var peeks: [String: PeekController] = [:] { didSet { noteReturnGate() } }
    let tabPeeks = TabPeekSlot()
    var archivePreviewRequest: (parent: String?, lease: ArchivePreviewLease, token: UUID)?
    var archivePreviews: [UUID: ArchivePreviewLease] = [:]
    var queuedArchivePreview: (id: UUID, profileID: UUID)?
    var archivePreviewRemnants = Set<UUID>()
    var peekRetirementParents = Set<UUID>() { didSet { noteRetiringPeekParents(from: oldValue) } }
    var favoriteBadgeIcons: [UUID: (image: NSImage, data: Data)] = [:]
    var lastFavoriteOverlayFingerprint: String?
    var promotingPeek = false { didSet { noteReturnGate() } }
    var activePeek: PeekController? {
        guard let id = peekHostID else { return nil }
        return peek(over: id)
    }
    var peekHostID: UUID? {
        PeekBackdrop.hostID(currentTabID: currentTabID, showsStartPage: showsStartPage, activeSpaceID: activeSpaceID)
    }
    func peek(over id: UUID) -> PeekController? {
        if let held = tabPeeks.current?.shownController, held.parentTabID == id, !held.page.isClosed,
           browsers[id]?.nativePage === held.parentPage { return held }
        return peeks.values.first { $0.parentTabID == id && !$0.page.isClosed
            && PeekBackdrop.peekStays(parent: $0.parentPage, hostPage: browsers[id]?.nativePage) }
    }
    var browserProfiles: [UUID: UUID] = [:]
    var easelImageDestination: EaselImageDestinationController?
    var privateMediaSource: (catalog: BrowserStore, profileID: UUID, media: ExternalMediaLibrary)?
    var pageCapture: PageCaptureController?
    private var pageCaptureGesture: PageCaptureGesture?
    struct EaselPane {
        let documentID: UUID
        let profileID: UUID
        let editor: EaselEditorViewController
        let originalTab: BrowserTab
    }
    struct NotePane {
        let documentID: UUID
        let profileID: UUID
        let editor: NoteEditorViewController
        let originalTab: BrowserTab
    }
    var noteEditors: [UUID: NotePane] = [:]
    var noteExport: NoteExportController?
    var easelEditors: [UUID: EaselPane] = [:]
    var easelFailures: [UUID: (destination: String, message: String)] = [:]
    var panes: [UUID: BrowserPane] = [:]
    var requestedURLs: [UUID: String] = [:]
    var failures: [UUID: String] = [:]
    var loadingTabs = Set<UUID>()
    var recentTabOrder = RecentTabOrder()
    var tabSelectionHistory = TabSelectionHistory()
    var tabSwitcher: RecentTabSwitcher? { didSet { updateLibraryEntryExpansion() } }
    var shortcutInvocationEvent: NSEvent?
    var focusedTabID: UUID? {
        didSet {
            if focusedTabID != oldValue { splitLinkGeneration &+= 1 }
            presentation.recordFocusedTab(focusedTabID)
            if focusedTabID != oldValue && !isClosing && !wholeWindowClose && transferringTabIDs.isEmpty {
                onSessionRecordChange?()
            }
        }
    }
    var sidebarPresentation: SidebarPresentation = .locked {
        didSet {
            if sidebarPresentation != .floating { sidebarHoverActive = false }
            if (sidebarPresentation == .locked) != (oldValue == .locked) { onSessionRecordChange?() }
        }
    }
    let sidebarMotion = SidebarMotionController()
    var sidebarMotionLayoutKey: [CGFloat]?
    var libraryContentWidth: CGFloat = 0
    let libraryMotion = SidebarMotionController()
    var lastAppliedChromeGeometryFingerprint: LayoutChromeGeometryFingerprint?
    var peekSplitBlockers: PeekSplitBlockers?
    var preparingSidebarMotion = false
    enum SidebarChromePass { case full, preparation, geometry }
    var sidebarChromePass = SidebarChromePass.full
    var sidebarMotionVisible = false
    var sidebarFloatingSurface = false
    var sidebarRevealsAnchored = false
    var fullscreenPhase: WindowFullscreenPhase?
    var windowedFrame: SavedWindowFrame?
    var systemWindowButtons: [NSButton] = []
    let sidebarResizeRegion = SidebarResizeRegionView()
    var sidebarResize: SidebarResizeGesture?
    var windowSidebarWidth: SidebarWindowWidth {
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
                            stayOnTop: stayOnTop, peekedFolders: savedFolderPeeks.isEmpty ? nil : savedFolderPeeks,
                            frame: savedFrame)
    }
    var onSessionRecordChange: (() -> Void)?
    var savedFolderPeeks: [UUID: [SidebarItemReference]] = [:]
    var isSidebarResizing = false {
        didSet {
            sidebarResizeRegion.isResizing = isSidebarResizing
            refreshPreviewHover()
            sidebarHover.isEnabled = !isSidebarResizing && frameCrank == nil
            setContentResizeReason(.sidebarResize, active: isSidebarResizing)
        }
    }
    var contentResizeReasons: PageContentResizeReasons = [] {
        didSet {
            guard contentResizeReasons.mode != oldValue.mode else { return }
            for case let pane as BrowserPane in splitView.arrangedSubviews { pane.contentResize.mode = contentResizeReasons.mode }
        }
    }
    func setContentResizeReason(_ reason: PageContentResizeReasons, active: Bool) {
        if active { contentResizeReasons.insert(reason) } else { contentResizeReasons.remove(reason) }
    }
    func refreshPreviewHover() {
        sidebarPreviews?.isHoverEnabled = !sidebarMotion.isAnimating && !isSidebarResizing
    }
    var sidebarLayoutWidth: CGFloat {
        CGFloat(sidebarResize.map { $0.isPreviewingHidden ? $0.widthOnBegin : $0.effectiveWidth } ?? windowSidebarWidth.width)
    }
    var sidebarPreviewingHidden: Bool { sidebarResize?.isPreviewingHidden == true }
    var sidebarAccessibilityObserver: NSObjectProtocol?
    var sidebarPointerDown = false
    var sidebarHoverActive = false
    var sidebarHoverLayoutKey: [CGFloat]?
    var navigationHistory: NavigationHistoryController?
    var menuTrackingDepth = 0
    var menuObservers: [NSObjectProtocol] = []
    var blockedContentAnnouncements: [String: UInt] = [:]
    var isClosing = false
    var nativeBinding: PCNativeBrowserWindow?
    var closingTabIDs = Set<UUID>()
    var modelRetirementIDs = Set<UUID>()
    var transferringTabIDs = Set<UUID>() {
        didSet {
            if transferringTabIDs.isEmpty, !oldValue.isEmpty { onReturnUnblocked?() }
            if transferringTabIDs != oldValue { notePeekSplitBlockers() }
        }
    }
    var collectionTransfer: SidebarWindowTransfer? {
        didSet { if collectionTransfer == nil, oldValue != nil { onReturnUnblocked?() } }
    }
    var transferContainers: [String: NSView] = [:]
    var transferRecoveries: [UUID: () -> Void] = [:]
    var resolvingTransfers = Set<UUID>()
    var placeholderCapturesPending: [UUID: Int] = [:]
    var placeholderCaptureGeneration = 0
    var untargetedReturnScheduled = false
    var shownSinceArrival = Set<UUID>()
    var heldReturns = Set<UUID>()
    var failedReturns = Set<UUID>()
    var failedDuringReturn: UUID?
    var returnGateWasOpen = true
    var returnGateSpaceID: UUID?
    var ejectionAttempts = Set<UUID>()
    var closeAfterEjecting = false
    private(set) var lastActivatedAt = Date.distantPast
    var onUntargetedReturn: ((UUID, BrowserWindowController, PageReparenting.Trigger) -> PageReparenting.ReturnOutcome)?
    var onReturnUnblocked: (() -> Void)?
    var liveTabModels: [UUID: BrowserTab] = [:]
    var scriptingAuthorization: (() -> Bool)?
    var scriptingWindowCloseCompletions: [(Bool) -> Void] = []
    var windowClosePending = false {
        didSet { if windowClosePending != oldValue { notePeekSplitBlockers() } }
    }
    var windowCloseApproved = false
    var onboardingCloseRequested = false
    var onboardingCloseNotes: [(editor: NoteEditorViewController, bodyEditable: Bool, titleEditable: Bool)]?
    var wholeWindowClose = false {
        didSet {
            if !wholeWindowClose, oldValue { onReturnUnblocked?() }
            if wholeWindowClose != oldValue { notePeekOwnersClosing() }
            if wholeWindowClose != oldValue { notePeekSplitBlockers() }
        }
    }
    var pendingApprovedWindowClose = false
    var restoreSettingsAfterCancelledTermination = false
    var nativeFullscreenTabID: UUID? {
        didSet {
            if nativeFullscreenTabID == nil, oldValue != nil { onReturnUnblocked?() }
            if nativeFullscreenTabID != oldValue { notePeekSplitBlockers() }
        }
    }
    var nativeFullscreenPresentation: (sidebar: SidebarPresentation, findHidden: Bool)?
    var extensionSidePanelVisible = false
    var attachedPageIDs = Set<String>()
    var switchHold = PageSwitchHold<BrowserPane>()
    var rendering = false
    var lastChromeState: BrowserState?
    var lastChromeRevision: UInt64?
    var synchronizingNativeLayout = false
    var applyingNativeSelection = false
    struct NativePageSelectionRequest {
        let tabID: UUID
        weak var view: PCBrowserView?
        var pageIdentifier: String?
    }
    enum NativeSelectionRequest {
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
    var pendingNativeSelection: NativeSelectionRequest?
    var attachingOwnedPages = false
    var sidebarKeyboardCursor: SidebarKeyboardCursor?
    var sidebarKeyboardBrowsing = false
    var commandBarHostCache: (profileID: UUID, revision: UInt64, hosts: Set<String>)?
    var commandBarModelChecks: (revision: UInt64, spaceID: UUID, profileID: UUID,
                                        items: [SidebarItemReference], answers: [String: Bool])?
    var commandBar: CommandBar? {
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
    var loadedStartPage: StartPageView?
    var startPage: StartPageView { loadedStartPage ?? loadStartPage() }
    var residentCommandBar: CommandBar?
    var residentCommandOwner: (spaceID: UUID, profileID: UUID)?
    var startPagePresented = false
    var startPageRefreshScheduled = false
    var startPageDeparting = false
    var closeFade: TabCloseFade?
    var residentTypedCommands: (items: [SidebarItemReference]?, commands: [CommandBarTypedCommand]) = (nil, [])
    private var residentTopDomainRevision: UInt64?
    var residentCommandInputs: ResidentCommandBarInputs?
    struct ResidentCommandBarInputs: Equatable {
        let state: UInt64
        let history: UInt64
        let space: UUID
        let profile: UUID
        let selection: [UUID]
        let undo: String?
        let redo: String?
    }
    func refreshResidentTopDomains(_ bar: CommandBar) {
        deliverCommandBarTitleIndex(to: bar)
        guard !isPrivateBrowsing, residentTopDomainRevision != store.historyRevision else { return }
        residentTopDomainRevision = store.historyRevision
        deliverCommandBarTopDomains(to: bar, profileID: activeProfileID)
    }
    func presentsCommandBar(_ panel: CommandBar) -> Bool { commandBar === panel || residentCommandBar === panel }
    var onCommandBarDismissalSettled: (() -> Void)?
    var commandBarCreatesNewTab = false
    var commandBarShowsNewTabPlaceholder = false
    private func refreshNewTabPlaceholder() {
        let active = commandBar != nil && commandBarShowsNewTabPlaceholder
        guard sidebar.newTabPlaceholderActive != active else { return }
        sidebar.newTabPlaceholderActive = active
        if presentation.isReady, !rendering, !isClosing { updateNavigation() }
    }
    var commandBarHistoryCache: (revision: UInt64, profileID: UUID, currentURL: String?, entries: [BrowserHistoryEntry])?
    var commandBarDocumentCache: (profileID: UUID, stamp: [Date], documents: [CommandBarDocument])?
    var commandBarTopDomainCache: (profileID: UUID, revision: UInt64, domains: [CommandBarRanking.Domain])?
    let commandBarTitleIndex = CommandBarTitleIndexCache()
    var commandBarRecentPages: (query: PCNativeHistoryQuery, profileID: UUID, revision: UInt64)?
    var shortcutEssentials: ShortcutEssentialsWindow?
    var settings: SettingsWindow?
    var libraryView: LibraryView? {
        didSet {
            updateLibraryEntryExpansion()
            if libraryView !== oldValue { notePeekSplitBlockers() }
        }
    }
    var paymentFeedbackWork: DispatchWorkItem?
    var shortcutHint: ShortcutPriorityHintView?
    var shortcutHintCommand: PCNativeShortcutCommand?
    weak var shortcutHintPage: PCNativePage?
    let toasts = ParcToastPresenter(share: { PaneShareMenu.popUp(for: $0, at: $1) })
    lazy var importNotices = makeImportNotices()
    var copyLinkOperation = UUID()
    lazy var sharedQuotes: SharedQuoteController = SharedQuoteController(isCurrent: { [weak self] page in
        guard let self else { return false }
        return !self.isClosing && !self.wholeWindowClose && self.commandBar == nil &&
            self.libraryView == nil && self.pageCapture == nil && self.selectedNativePage() === page
    }, display: { [weak self] selection in
        guard let self else { return }
        guard let selection, let page = self.selectedNativePage(), self.commandBar == nil,
              self.libraryView == nil, self.pageCapture == nil, !self.isClosing, !self.wholeWindowClose else {
            self.sidebar.updateSharedQuote(action: nil); return
        }
        self.sidebar.updateSharedQuote { [weak self, weak page] in
            guard let self, let page, self.selectedNativePage() === page,
                  self.sharedQuotes.canPerform(selection) else { return }
            self.copySharedQuote(selection, page: page)
        }
    })
    var capturePresentations: [UUID: CaptureIndicatorPresentation] = [:]
    var lastCapturePresentationFingerprint: String?
    var lastShareableAudioFingerprint: String?
    var lastAppliedShareable = Set<UUID>()
    var lastAppliedAudio: [UUID: SidebarTabAudio] = [:]
    var themePopover: NSPopover? { didSet { noteReturnGate() } }
    var siteControlCenter: SiteControlCenterController? { didSet { noteReturnGate() } }
    var siteControlCenterDefers: Bool { siteControlCenter.map { !$0.isDetached } ?? false }
    let siteControlCenterDismissal = SiteControlCenterDismissal()
    var extensionActionGeneration = UUID()
    weak var extensionControlsPage: PCNativePage?
    var siteControlCenterItems: [String: ExtensionControlItem] = [:]
    var siteControlCenterPermissions: [[String: Any]] = []
    var siteControlCenterPermissionTargets: [String: (Int, UInt)] = [:]
    var siteControlCenterRevision: UInt?
    var siteControlCenterPageTools: Set<PCNativePageTool> = []
    var siteControlCenterOwner: (space: UUID, profile: UUID)?
    var lastExtensionControlsSignature: String?
    var themeEditor: SpaceThemeEditorView?
    var themeEditingSpaceID: UUID?
    var themeEditingProfileID: UUID?
    var themeEditingContextSpaceID: UUID?
    var themePreview: (spaceID: UUID, theme: SpaceTheme)?
    var themeEditorPresetPage = 0
    var downloadReview: DownloadReviewController?
    var downloadReviewItem: BrowserDownload?
    let downloadArrival = DownloadArrivalOwner()
    var recyclingDownloads: [String: DownloadLibraryIdentity] = [:]
    var loadingDownloadProfiles = Set<UUID>()
    var downloadProfileErrors: [UUID: String] = [:]
    var libraryFlyoutFileGeneration: UInt64 = 0
    var libraryFlyoutFileMonitor: LibraryFlyoutFolderMonitor?
    var libraryFlyoutFileActivation: NSObjectProtocol?
    var eventMonitor: Any?
    var zoomLevels: [UUID: Double] = [:]
    var renderedPaneIDs: [UUID] = []
    let archiveActivityScheduling = ArchiveScheduling()
    var renderedSpaceCreationID: UUID?
    var onClose: (() -> Void)?
    var onActivateWindow: (() -> Void)?
    var onMiniPlayerSourceChange: (() -> Void)?
    var lastMiniPlayerSourceSignature: String?
    let mediaRefresh = NextTurnCoalescer()
    var onRequestBrowserTab: ((String?) -> Void)?
    var onRequestTabTransfer: ((UUID, BrowserWindowController, (() -> Bool)?) -> Bool)?
    var tabHolder: ((UUID, BrowserWindowController) -> TabHolder)?
    enum TabHolder {
        case none
        case content(BrowserWindowController)
        case emptyClaim(BrowserWindowController)
    }
    var onPrepareLinkRoute: ((PCNativeLinkRoute) -> PCNativeBrowserWindow?)?
    var preparedForRoutedPage = false
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
            && !transferringTabIDs.contains(id) && !peeks.values.contains(where: { $0.parentTabID == id })
            && tabPeeks.current?.tabID != id {
            guard let tab = store.state.tab(id), tab.lastAccessed < cutoff,
                  let page = browser.nativePage, !page.isClosed,
                  page.responds(to: #selector(PCNativePage.discardIfIdle)) else { continue }
            _ = page.discardIfIdle()
        }
        for (id, pane) in easelEditors where !shown.contains(id) && !closingTabIDs.contains(id) && !transferringTabIDs.contains(id) {
            guard let tab = store.state.tab(id, where: { $0.archivedAt == nil }), tab.lastAccessed < cutoff,
                  easelPagesCanSleep(pane) else { continue }
            releaseIdleEaselPages(id, cached: pane)
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
        if let held = tabPeeks.current { protected.formUnion([held.tabID, held.parentTabID]) }
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
    func windowWillEnterFullScreen(_ notification: Notification) {
        if fullscreenPhase == nil, let frame = window.flatMap({ SavedWindowFrame($0.frame) }) { windowedFrame = frame }
        setFullscreenPhase(.entering)
    }
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
         restoredRecord: BrowserWindowRecord? = nil, restoresSavedFrame: Bool = false) throws {
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
        windowedFrame = restoredRecord?.frame
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
        if restoresSavedFrame, let frame = Self.restoredFrame(restoredRecord, minimumSize: window.minSize) {
            window.setFrame(frame, display: false)
        } else if nativeWindowRequest == nil && restoredRecord == nil { Self.placeNewStandardWindow(window) }
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
        rootView.addSubview(peekLayer)
        rootView.addSubview(findHost)
        rootView.addSubview(popupChrome)
        popupChrome.isHidden = !popup
        rootView.addSubview(sidebarContainer)
        sidebarContainer.coordinateSpace = rootView
        let incognitoTheme = store.isEphemeral && !popup
        rootView.incognito = incognitoTheme; sidebarContainer.incognito = incognitoTheme
        toasts.basicBackground = windowBasicBackground
        toasts.onIdle = { [weak self] in self?.showImportFailuresWhenIdle() }
        toasts.yieldsShortcut = { KeyboardShortcuts.shared.isAssigned($0) }
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
                for peek in self.presentedPeeks { peek.view.adoptWindowTheme(self.rootView) }
                self.shortcutHint?.update(theme: self.rootView.theme, basicBackground: self.windowBasicBackground)
                self.toasts.update(theme: self.rootView.theme)
                self.refreshDebuggerWarningPalettes()
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
        popupChrome.prepareBlocked = { [weak self] anchor in self?.preparePopupSiteControls(requireExtensions: false, from: anchor) }
        sidebar.onBlockedContent = { [weak self] anchor in self?.showSiteControlCenter(from: anchor) }
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
        splitView.prepareStackedResize = { [weak self] in self?.prepareStackedSplitResize() }
        splitView.onDividerPanActivity = { [weak self] in self?.setContentResizeReason(.splitDividerResize, active: $0) }
        splitView.onInteractivePaneEditing = { [weak self] active in
            self?.setContentResizeReason(.splitInteractiveEditing, active: active)
            self?.splitPaneEditDidChange(active)
        }
        splitView.constrain(to: pageHost)
        loadingIndicator.appearance = rootView.palette.contentAppearance
        setupFindBar()
        setupBlockedContent()
        sidebar.isPrivateBrowsing = store.isEphemeral
        wireSidebar()
        pinnedSectionSubscription = wirePinnedSection()
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
                self.settleLibraryMotion()
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

    var pendingSearchNavigations: [UUID: PCNativeSearchNavigation] = [:]
    var inputRevisions: [UUID: UUID] = [:]
    var commandSubmissionRevision = UUID()
    var residentCommandSubmissionRevision = UUID()
    var splitInsertion: SplitPaneInsertionSession?
    var renderedSplitInsertionID: UUID?
    var pendingCommandSplitValidation: (() -> Bool)?
    weak var pendingCommandSplitBrowser: PCBrowserView?
    static var placeholderCaptureLeases: [ObjectIdentifier: PCNativePageCapture] = [:]
    var panePresentationRetries = 0
    var panePresentationRetryPending = false
    var sidebarHeldByPendingPane = false
    static var updateReadyToInstall: Bool {
        switch SoftwareUpdater.shared.phase {
        case .readyToInstall, .installing: return true
        default: return false
        }
    }
    static var buildInfo: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let engine = Bundle.main.privateFrameworksURL
            .flatMap { Bundle(url: $0.appendingPathComponent("Chromium Embedded Framework.framework")) }?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return ["Parc \(version) (\(build))", "Chromium Engine Version \(engine)",
                "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"].joined(separator: "\n")
    }

    var favoriteSplitRename: FavoriteRenameDialog?
    var splitIconPicker: SidebarGroupIconPicker?

    var favoriteRename: FavoriteRenameDialog?

    enum CloseUndo {
        case register(ClosedTabsUndo.Prompt, registered: (() -> Void)? = nil)
        case redo(ClosedTabsUndo.Prompt, (ClosedTabsUndo?) -> Void)
    }

    @MainActor final class SplitLinkLease: NSObject {
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
        guard let id = splitLinkSourceID(browser, page) else { return nil }
        return SplitLinkLease(owner: self, source: page, focusedID: id)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canSplitLinkFrom page: PCNativePage) -> Bool {
        guard linkRouteWindowAdmits(browser, page), let id = linkClickPaneID(showing: page),
              let view = browsers[id], view.nativePage === page else { return false }
        return canOpenLinkInSplitView(view, ignoringCommandBar: true) && selectedTabIDs.count < 4
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canPeekLinkFrom page: PCNativePage) -> Bool {
        (linkClickPaneID(showing: page) != nil || peekUndoOpen?.parent == page.identifier)
            && canHostPeek(browser, over: page, overLibrary: archivePreviewRequest?.parent == page.identifier,
                           ignoringCommandBar: true)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canNavigatePeekLinkFrom page: PCNativePage) -> Bool {
        guard let peek = activePeek, peek.page === page, !page.isClosed, !peek.closePending, !promotingPeek,
              PCNativeBrowserApplication.owner(of: page) === browser, peek.canInteract?() == true else { return false }
        return windowAdmitsPeek(browser, overLibrary: archivePreviews[peek.identity] != nil, ignoringCommandBar: true)
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, isPeekPage page: PCNativePage) -> Bool {
        browser === nativeBinding && presentedPeek(for: page)?.page === page
    }

    private func linkClickPaneID(showing page: PCNativePage) -> UUID? {
        guard activePeek == nil else { return nil }
        return LinkClickPane.id(selection: selectedTabIDs, current: currentTabID, rendered: renderedPaneIDs,
                                covered: { peek(over: $0) != nil }, shows: { paneNativePage($0) === page })
    }

    private func splitLinkSourceID(_ browser: PCNativeBrowserWindow, _ page: PCNativePage) -> UUID? {
        guard nativeBrowser(browser, canRouteCurrentLinkFrom: page),
              let entry = browsers.first(where: { $0.value.nativePage === page }),
              currentTabID == entry.key, browserViewCanOpenLinkInSplitView(entry.value) else { return nil }
        return entry.key
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
        linkRouteWindowAdmits(browser, page) && activePeek == nil && commandBar == nil
            && selectedNativePage() === page
    }

    private func linkRouteWindowAdmits(_ browser: PCNativeBrowserWindow, _ page: PCNativePage) -> Bool {
        browser === nativeBinding && !isPopupWindow
            && !isClosing && !wholeWindowClose && !windowClosePending && !windowCloseApproved
            && nativeFullscreenTabID == nil && closingTabIDs.isEmpty && modelRetirementIDs.isEmpty
            && transferringTabIDs.isEmpty && resolvingTransfers.isEmpty
            && libraryView == nil && window?.attachedSheet == nil && window?.isKeyWindow == true
            && !page.isClosed && PCNativeBrowserApplication.owner(of: page) === browser
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
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
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
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
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

    func nativeBrowser(_ browser: PCNativeBrowserWindow, shouldOpenCurrentLinkInPeekFrom page: PCNativePage,
                       targetURL: URL) -> Bool {
        guard nativeBrowser(browser, shouldOpenNewPageInPeekFrom: page, targetURL: targetURL),
              !page.authenticationFlowUnlocked,
              let targetHost = targetURL.host,
              let currentHost = page.url?.host,
              let id = browsers.first(where: { $0.value.nativePage === page })?.key,
              let tab = store.state.tab(id),
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
              let tab = store.state.tab(id, where: { $0.archivedAt == nil }),
              tab.profileID == activeProfileID else { return false }
        return tab.kind == .favorite || tab.kind == .pinned
    }

    func nativeBrowser(_ browser: PCNativeBrowserWindow, canPresentPeekFrom page: PCNativePage) -> Bool {
        let shown = activePeek == nil && selectedNativePage() === page
        return (shown || peekUndoOpen?.parent == page.identifier)
            && canHostPeek(browser, over: page, overLibrary: archivePreviewRequest?.parent == page.identifier)
    }

    func nativeBrowserWindow() -> NSWindow { window! }
    func selectedNativePage() -> PCNativePage? {
        if let peek = activePeek, peek.isLeaving { return peek.parentPage }
        if let page = currentBrowser?.nativePage { return page }
        guard let id = currentTabID else { return nil }
        return easelEditors[id]?.editor.pageObjects?.selectedPage
    }
    func paneNativePage(_ id: UUID) -> PCNativePage? {
        paneBrowser(id)?.nativePage ?? easelEditors[id]?.editor.pageObjects?.selectedPage
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
              peek.page === page, presentedPeek(for: page) === peek,
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
        let shortcut = KeyboardShortcuts.shared.boundShortcut(for: command)
            ?? KeyboardShortcut(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask)
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
              let tab = store.state.tab(id),
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
        if browser === nativeBinding, handleTabPeekSelection(page, browser: browser) { return }
        if browser === nativeBinding, let peek = peeks[page.identifier], !page.isClosed {
            if undoHiddenPeek == peek.identity {
                undoHiddenPeek = nil
                if peek.view.isHidden { browser.synchronizeSelectionAndLayout(); return }
            }
            guard !applyingNativeSelection, !isClosing, !wholeWindowClose else { return }
            let hostTab = store.state.tab(peek.parentTabID) != nil
            if !hostTab, peekHostID != peek.parentTabID { browser.synchronizeSelectionAndLayout(); return }
            applyingNativeSelection = true
            if hostTab { _ = selectTab(peek.parentTabID) }
            applyingNativeSelection = false
            layoutPeeks(); peek.focus(); return
        }
        guard !applyingNativeSelection, let (id, view) = existingNativeSelection(browser, page),
              !rendering else { return }
        guard presentation.admitsEngineSelection(of: id, closing: { closingTabIDs.contains($0) || modelRetirementIDs.contains($0) }) else {
            browser.synchronizeSelectionAndLayout(); presentation.engineSelectionSynchronized(); return
        }
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
            if store.state.tab(id)?.kind == .favorite { _ = moveFavoriteToPinned(id) }
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
        if tabPeekHolds(page), !promoteTabPeekForFullscreen(page) { return false }
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
    enum SplitCommand {
        case focus(Int), next, previous, expand, separate, close, widen, narrow, equalize
        case orientation(SplitOrientation), move(Int), moveInStack(Int), add(SplitPaneOperation), addNew, copyLinks
    }

    var copyDropCache: (key: String, revision: UInt64, action: (() -> Bool)?)?

    @MainActor final class SidebarWindowTransfer {
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
                      let tab = source.store.state.tab(id) else { continue }
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
                guard let easel = easels[id], let tab = source.store.state.tab(id) else { continue }
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
                    guard let tab = source.store.state.tab(id) else { continue }
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

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performFolderUndoCommand(_:)) else { return true }
        guard usesFolderUndoResponder, let command = item.representedObject as? FolderUndoManager.Command else { return false }
        return folderUndo.canPerform(command)
    }

    struct SplitPaneIdentity: Equatable {
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

        init(owner: BrowserWindowController, command: SplitCommand,
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

    static let expandCurrentSplitNotification = Notification.Name("ParcExpandCurrentSplit")

    enum ToastLocation { case content(UUID?), window }
    var onRequestApplicationSettings: ((SettingsWindow.Pane?, String?) -> Void)?

    @MainActor
    final class CaptureMenuRequest {
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
    @MainActor
    final class ToolbarMenuRequest {
        weak var owner: BrowserWindowController?
        init(_ owner: BrowserWindowController) { self.owner = owner }
    }
    @MainActor
    final class DeveloperModeMenuRequest {
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
    final class FairPlayIdentityMenuRequest {
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
    @MainActor
    final class ReaderMenuRequest {
        weak var owner: BrowserWindowController?
        weak var browser: PCBrowserView?
        let revision: UInt
        init(owner: BrowserWindowController, browser: PCBrowserView) {
            self.owner = owner
            self.browser = browser
            revision = browser.readerRevision
        }
    }

    @MainActor
    final class PageToolMenuRequest {
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
    final class ScriptPermissionMenuRequest {
        weak var owner: BrowserWindowController?
        weak var page: PCNativePage?
        init(owner: BrowserWindowController, page: PCNativePage) { self.owner = owner; self.page = page }
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

    var addressPromptHolds: [ObjectIdentifier: AddressPopoverRevealHold] = [:]
    var extensionPopupKeyObserver: NSObjectProtocol?
    var extensionPopupAtSidebar = false
    var extensionPopupSource: ExtensionPopupSource?
    var extensionPopupActivity = ExtensionPopupActivityTracker()
    var extensionPopupIndicators: [ExtensionPopupActivityIndicator] = []
    var extensionPopupCloseObserver: NSObjectProtocol?
    func nativeBrowserPaymentActionsDidChange(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding else { return }
        refreshPaymentControls()
    }

    func nativeBrowserExtensionActionsDidChange(_ browser: PCNativeBrowserWindow) {
        guard browser === nativeBinding else { return }
        refreshExtensionControls()
        commandBar?.reconcileExtensionActions()
    }

    func nativeBrowserExtensionPopupAnchor(_ browser: PCNativeBrowserWindow) -> PCNativeExtensionPopupAnchor {
        guard browser === nativeBinding else { return .window() }
        extensionPopupAtSidebar = extensionPopupsAnchorToSidebar
        if extensionPopupAtSidebar {
            followExtensionPopupsForAddressHold()
            holdAddressButtonsForLoadingExtensionPopups()
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

    var newSpaceWait = 0
    var newSpaceWaitActive = false

    @MainActor final class FolderDisclosureTarget {
        private weak var owner: BrowserWindowController?
        private weak var window: NSWindow?
        private let spaceID: UUID
        private let profileID: UUID
        private let folders: [BrowserFolder]
        private let expanded: Bool
        private var consumed = false

        init(owner: BrowserWindowController, expanded: Bool) {
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

    enum FolderIconError: LocalizedError {
        case unavailable
        var errorDescription: String? { "This folder changed while its icon was being chosen. Please try again." }
    }
    final class SpaceUndoOperation {
        var record: SpaceDeletionUndo
        var wasFocused: Bool
        var selection: [UUID]
        var focus: UUID?
        init(record: SpaceDeletionUndo, wasFocused: Bool, selection: [UUID], focus: UUID?) {
            self.record = record; self.wasFocused = wasFocused; self.selection = selection; self.focus = focus
        }
    }

    var spaceIconPicker: SidebarGroupIconPicker?

    var downloadCatalog: BrowserStore?
    var onOpenDownloadSource: ((BrowserDownload, URL) -> Bool)?
    var loadingPrivateDownloadContexts = Set<String>()
    var privateDownloadErrors: [String: String] = [:]
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
        let library = sidebar.convert(SidebarChromeLayout.dockLeadingButton(height: sidebar.bounds.height), to: nil)
        downloadArrival.arrive(at: arrival.sourceScreenPoint, in: parent, showsBin: sidebarPresentation == .hidden,
                               library: CGPoint(x: library.midX, y: library.midY), palette: rootView.palette)
    }
    func nativeBrowserPrivateDownloadsDidInvalidate(_ browser: PCNativeBrowserWindow) {
        guard isPrivateBrowsing, browser === nativeBinding, browser.window === window else { return }
        downloadReview?.dismiss(); closeLibrary(restoreFocus: false)
        refreshDownloads()
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
}


extension SidebarView: SidebarKeyViewEnds {}


extension SplitPanePlaceholder: SplitLayoutFollowing {
    func followSplitLayout(from previous: CGRect, animation: CAAnimation) { splitHighlight.followLayout(from: previous, animation: animation) }
    func cancelSplitLayoutFollow() { splitHighlight.cancelFollow() }
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
