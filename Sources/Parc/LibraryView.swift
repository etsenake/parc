import AppKit
import Combine
import ParcCore
import QuartzCore

@MainActor
protocol LibrarySpacesPage: NSView {
    func cancelEditing()
    func focusFirst()
    func reload(_ state: BrowserState)
}

@MainActor
final class LibraryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    enum Kind: Equatable { case archive, captures, downloads, documents, spaces }
    struct PrivateMediaContext {
        let store: BrowserStore
        let profileID: UUID
        let media: ExternalMediaLibrary
        let isValid: () -> Bool
    }
    private enum ClosureFilter: Hashable { case automatic, manual }
    private struct Item: Equatable {
        let id: UUID
        let tabIDs: [UUID]
        let title: String
        let urls: [String]
        let date: Date
        let spaceID: UUID?
        let spaceName: String?
        let reason: ArchiveReason?
        let archivedTabs: [BrowserTab]?
    }
    private enum Row { case heading(String), item(Item) }
    let profileID: UUID
    private(set) var kind: Kind
    private let store: BrowserStore
    private let downloadStore: BrowserStore
    private let privateMediaContext: PrivateMediaContext?
    private var privateMediaView: CaptureLibraryView?
    private var privateMediaSubscription: AnyCancellable?
    var onClose: (() -> Void)?
    var onOpenURLs: (([String]) -> Void)?
    var onToast: ((ParcToastContent) -> Void)?
    var onRestore: (([UUID], UUID?) -> Void)?
    var onPreview: ((UUID) -> Bool)?
    private var clickStartedPreview = false
    var archiveOwnerValid: (() -> Bool)?
    var onDownloadAction: ((BrowserDownload, DownloadLibraryAction) -> Bool)?
    var downloadFileURL: ((BrowserDownload) -> URL?)?
    var onLoadDownloads: (() -> Void)?
    var onShowKind: ((Kind) -> Void)?
    var onLeaveSpaces: (() -> Void)?
    private(set) var contentWidth = SidebarChromeFrames.libraryMinimumWidth
    var onContentWidthChange: (() -> Void)?
    var requestIcon: ((URL, UUID, @escaping (NSImage?) -> Void) -> Void)? { didSet { table.reloadData() } }
    var palette: ThemeChromePalette? { didSet { applyPalette() } }
    var showsWindowButtons = false {
        didSet { if showsWindowButtons != oldValue { windowButtons.isHidden = !showsWindowButtons } }
    }
    private let depth = LibraryDepthView()
    private let windowButtons = WindowStandardButtons()
    private let searchBackdrop = DownloadSearchBackdrop()
    private let search = DownloadSearchField(frame: .zero)
    private let filter = DownloadFilterButton("Filter", symbol: "line.3.horizontal.decrease.circle", style: .header)
    private let filterTitle = LibraryInkField(string: "Filter Archived Tabs", size: 14, weight: .bold, light: 0.565, dark: 0.592)
    private let table = LibraryTable()
    private let scroll = NSScrollView()
    private let rail = LayoutView()
    private let filterScroll = NSScrollView()
    private let filterContent = LayoutView()
    private lazy var archiveButton = LibraryRailTile("Archived Tabs", animation: .archive)
    private lazy var capturesButton = LibraryRailTile("Media", animation: .media)
    private lazy var capturesView: CaptureLibraryView = {
        let catalog = CaptureLibraryStore.shared(directory: store.capturesDirectory(for: profileID), profileID: profileID)
        let view = CaptureLibraryView(store: catalog, profileOwner: store, media: ExternalMediaLibrary.shared(directory: store.capturesDirectory(for: profileID)), regularHeader: true, ownerValid: { [weak self] in
            guard let self else { return false }
            return self.kind == .captures && self.window != nil
                && self.store.state.profiles.contains { $0.id == self.profileID }
        })
        view.onClose = { [weak self] in self?.onClose?() }
        view.onOpenSource = { [weak self] url in self?.onOpenURLs?([url]) }
        view.onToast = { [weak self] in self?.onToast?($0) }
        return view
    }()
    private lazy var downloadsButton = LibraryRailTile("Downloads", animation: .downloads, hasProgressBadge: true)
    private lazy var downloadsView: DownloadLibraryView = {
        let view = DownloadLibraryView(store: downloadStore, ownerValid: { [weak self] in
            guard let self else { return false }
            return self.kind == .downloads && self.window != nil
                && self.store.state.profiles.contains { $0.id == self.profileID }
        })
        view.onClose = { [weak self] in self?.onClose?() }
        view.onToast = { [weak self] in self?.onToast?($0) }
        view.onAction = { [weak self] item, action in self?.onDownloadAction?(item, action) ?? false }
        view.fileURL = { [weak self] item in self?.downloadFileURL?(item) }
        view.onLoad = { [weak self] in self?.onLoadDownloads?() }
        return view
    }()
    func setDownloadOperation(_ item: BrowserDownload, message: String?) {
        downloadsView.setOperation(item, message: message)
    }
    func updateDownloadActivity(_ items: [BrowserDownload], profiles: Set<UUID>, privateWindow: Bool, enabled: Bool) {
        downloadsButton.progress?.updateInFlight(items.filter { ($0.privateContextID != nil) == privateWindow },
                                                 profiles: profiles, enabled: enabled)
    }
    var onOpenDocument: ((InternalPage, String) -> Void)?
    var onCreateNote: (() -> Void)?
    var onRenameDocument: ((InternalPage, String) -> Void)?
    var onDeleteDocument: ((InternalPage, @escaping (Error?) -> Void) -> Void)?
    private lazy var documentsButton = LibraryRailTile("Easels & Notes", animation: .easels)
    private lazy var documentsView: DocumentsLibraryView = {
        let view = DocumentsLibraryView(store: store, profileID: profileID, files: files, easelIcons: easelIcons,
                                        easelStore: easelStore)
        view.ownerValid = { [weak self] in
            guard let self else { return false }
            return self.kind == .documents && self.window != nil && self.store.state.profiles.contains { $0.id == self.profileID }
                && !self.store.isProfileRemovalPending(self.profileID)
        }
        view.onOpen = { [weak self] page, title in self?.onOpenDocument?(page, title) }
        view.onCreate = { [weak self] in self?.onCreateNote?() }
        view.onRename = { [weak self] page, title in self?.onRenameDocument?(page, title) }
        view.onDelete = { [weak self] page, done in self?.onDeleteDocument?(page, done) }
        view.onClose = { [weak self] in self?.onClose?() }
        return view
    }()
    let spaceManager: any LibrarySpacesPage
    private lazy var spacesButton = LibraryRailTile("Spaces", animation: .spaces)
    private var categoryButtons: [LibraryRailTile] { [capturesButton, downloadsButton, documentsButton, spacesButton, archiveButton] }
    private let back = ActionButton("Back", symbol: "arrow.left")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var listControls: [NSView] { [searchBackdrop, filterTitle, filter, filterScroll, scroll, empty] }
    private var rows: [Row] = []
    private var allItems: [Item] = []
    private var renderedKind: Kind?
    private var closureFilter: ClosureFilter?
    private var selectedSpaceFilter: UUID?
    private var filtersExpanded = false
    private var subscription: AnyCancellable?
    private var icons: [URL: NSImage] = [:]
    private var resolvedIcons = Set<URL>()
    private var pendingIcons = Set<URL>()
    private var filterControls: [NSView] = []
    private var filterSpaceSignature: [String] = []
    private var filterHeight: CGFloat = 0
    private var filterAnimationGeneration: UInt64 = 0
    private var filterControlsGeneration: UInt64 = 0
    private var archiveMenuGeneration: UInt64 = 0
    private var animatingFilterLayout = false
    private var savedSearchSelection: NSRange?
    private var observedTabs: [BrowserTab] = []
    private var observedArchivedTabs: [BrowserTab] = []
    private var observedSpaces: [BrowserSpace] = []
    private var observedProfiles: [BrowserProfile] = []
    private var observedFolders: [BrowserFolder] = []
    private var observedSplitLayouts: [BrowserSplitLayout] = []
    private var observedSidebarItemOrder: [String: [SidebarItemReference]] = [:]
    private var observedActiveSpaceID: UUID?
    private var observedSelectedTabIDs: [UUID] = []
    private var observedSelectionBySpace: [String: [UUID]] = [:]
    private var observedProfileRemovals: [ProfileRemovalRecord] = []
    private var observedSettings = BrowserSettings()
    private var observedProfileRemovalPending = false
    private let reduceMotion: @MainActor () -> Bool
    private let files: NoteFiles
    private let easelIcons: EaselTabIcons?
    private let easelStore: ((URL) throws -> EaselStore)?
    override var isFlipped: Bool { true }

    init(store: BrowserStore, kind: Kind, profileID: UUID, spaceManager: any LibrarySpacesPage, downloadStore: BrowserStore? = nil,
         privateMediaContext: PrivateMediaContext? = nil, files: NoteFiles? = nil, easelIcons: EaselTabIcons? = nil,
         easelStore: ((URL) throws -> EaselStore)? = nil,
         reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         scheduleReload: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil) {
        self.reduceMotion = reduceMotion
        self.files = files ?? .shared
        self.easelIcons = easelIcons
        self.easelStore = easelStore
        self.downloadStore = downloadStore ?? store
        self.privateMediaContext = store.isEphemeral ? privateMediaContext : nil
        self.store = store
        self.kind = store.isEphemeral && !(kind == .captures && privateMediaContext?.isValid() == true) ? .downloads : kind
        self.profileID = profileID
        self.spaceManager = spaceManager
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(store.isEphemeral && privateMediaContext == nil ? "Downloads" : "Library")
        for view in [depth, rail, searchBackdrop, filterTitle, filter, filterScroll, scroll, empty, windowButtons] { addSubview(view) }
        windowButtons.isHidden = true
        for button in categoryButtons { rail.addSubview(button) }
        back.imagePosition = .imageOnly
        back.image = back.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        back.focusRingCornerRadius = 7
        LiveShortcutToolTip.set(back, "Exit Library")
        rail.addSubview(back)
        searchBackdrop.wantsLayer = true; searchBackdrop.addSubview(search)
        searchBackdrop.setAccessibilityElement(false)
        searchBackdrop.onFocus = { [weak self] in
            guard let self, !self.filtersExpanded, !self.searchBackdrop.isHiddenOrHasHiddenAncestor,
                  let window = self.window, window.attachedSheet == nil else { return }
            if self.search.currentEditor() !== window.firstResponder { window.makeFirstResponder(self.search) }
        }
        for button in [documentsButton, archiveButton, spacesButton] { button.isHidden = store.isEphemeral }
        capturesButton.isHidden = store.isEphemeral && privateMediaContext == nil
        spacesButton.actionBlock = { [weak self] in self?.show(.spaces) }
        documentsButton.actionBlock = { [weak self] in self?.show(.documents) }
        downloadsButton.actionBlock = { [weak self] in self?.show(.downloads) }
        capturesButton.actionBlock = { [weak self] in self?.show(.captures) }
        archiveButton.actionBlock = { [weak self] in self?.show(.archive) }
        back.actionBlock = { [weak self] in self?.onClose?() }
        search.delegate = self
        search.setAccessibilityLabel("Search Library")
        filter.actionBlock = { [weak self] in self?.toggleFilters() }
        filterTitle.isHidden = true
        filterScroll.documentView = filterContent
        filterScroll.drawsBackground = false
        filterScroll.hasVerticalScroller = true
        filterScroll.autohidesScrollers = true
        let column = NSTableColumn(identifier: .init("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.floatsGroupRows = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.allowsMultipleSelection = self.kind != .archive
        table.allowsEmptySelection = true
        table.delegate = self; table.dataSource = self
        table.target = self; table.action = #selector(clickRow); table.doubleAction = #selector(doubleClickRow)
        table.onActivate = { [weak self] in self?.activate() }
        table.onDelete = { [weak self] in self?.deleteSelection() }
        table.onClose = { [weak self] in self?.onClose?() }
        table.onSearch = { [weak self] in self?.focusSearch() }
        table.onCopy = { [weak self] in self?.copySelection() }
        table.singleCursor = { [weak self] in self?.kind == .archive }
        table.onMoveCursor = { [weak self] forward in self?.moveArchiveCursor(forward: forward) }
        table.selectContextRow = { [weak self] in self?.kind != .archive }
        table.contextMenu = { [weak self] row in self?.rowMenu(row) }
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(listDidScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        empty.font = .systemFont(ofSize: 13)
        empty.alignment = .center
        if let scheduleReload {
            subscription = store.statePublisher.sink { [weak self] _ in
                scheduleReload { [weak self] in self?.reload() }
            }
        } else {
            subscription = store.statePublisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
        }
        if let privateMediaContext = self.privateMediaContext {
            privateMediaSubscription = privateMediaContext.store.statePublisher.receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, self.window != nil else { return }
                if !privateMediaContext.isValid() { self.onClose?() }
            }
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setDownloadsLoading(count: Int, message: String?) { downloadsView.setLoading(count: count, message: message) }
    func show(_ kind: Kind) {
        if kind == self.kind && kind == .archive {
            restoreCategorySelection(); return
        }
        if kind != self.kind, (search.currentEditor() as? NSTextView)?.hasMarkedText() == true {
            restoreCategorySelection(); return
        }
        guard !store.isEphemeral || kind == .downloads || (kind == .captures && privateMediaContext?.isValid() == true) else { return }
        if self.kind == .spaces && kind != .spaces { spaceManager.cancelEditing(); onLeaveSpaces?() }
        if self.kind == .captures && kind != .captures {
            if store.isEphemeral { privateMediaView?.suspend() } else { capturesView.suspend() }
        }
        if self.kind == .downloads && kind != .downloads { downloadsView.suspend() }
        if self.kind != kind { archiveMenuGeneration &+= 1 }

        settleFilterAnimation()
        let shownKind = renderedKind
        if kind == .documents { documentsView.scope(to: nil) }
        self.kind = kind
        table.allowsMultipleSelection = kind != .archive
        filtersExpanded = false
        savedSearchSelection = nil
        search.stringValue = ""
        table.deselectAll(nil)
        reload()
        reloadRows()
        if renderedKind != shownKind { fadeInPage() }
        focusSearch()
        if kind == .downloads { onLoadDownloads?() }
        onShowKind?(kind)
    }
    func showDocuments(in folder: URL) {
        show(.documents)
        guard kind == .documents else { return }
        documentsView.scope(to: folder)
    }
    func revealDocument(_ target: DocumentsLibraryReveal.Target) {
        show(.documents)
        guard kind == .documents else { return }
        documentsView.revealItem(target)
    }
    func focusSearch() {
        if kind == .spaces { spaceManager.focusFirst() }
        else if kind == .documents { documentsView.focusSearch() }
        else if kind == .captures { if store.isEphemeral { privateMediaView?.focusSearch() } else { capturesView.focusSearch() } }
        else if kind == .downloads { downloadsView.focusSearch() }
        else {
            if filtersExpanded { setFiltersExpanded(false, animated: false) }
            guard !filtersExpanded, window?.attachedSheet == nil else { return }
            window?.makeFirstResponder(search); search.selectText(nil)
        }
    }
    func controlTextDidChange(_ obj: Notification) { reloadRows() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            focusFirstItem(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            if filtersExpanded { toggleFilters() }
            else if !search.stringValue.isEmpty { search.stringValue = ""; reloadRows() }
            else { onClose?() }
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            focusFirstItem(); activate(); return true
        }
        return false
    }
    override func cancelOperation(_ sender: Any?) {
        if filtersExpanded { setFiltersExpanded(false); return }
        if !search.stringValue.isEmpty { search.stringValue = ""; reloadRows(); return }
        onClose?()
    }
    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { settleFilterAnimation() }
        super.setFrameSize(newSize)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            settleFilterAnimation(); savedSearchSelection = nil; filterControlsGeneration &+= 1
            archiveMenuGeneration &+= 1
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && kind == .archive && filtersExpanded { rebuildFilters() }
    }
    private func focusFirstItem() {
        guard let index = rows.firstIndex(where: { if case .item = $0 { return true }; return false }) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        window?.makeFirstResponder(table)
    }
    private var selectableRows: IndexSet {
        IndexSet(rows.indices.filter { if case .item = rows[$0] { return true }; return false })
    }
    private func moveArchiveCursor(forward: Bool) {
        guard kind == .archive,
              let index = DownloadLibrarySelection.nextRow(in: selectableRows,
                  selected: table.selectedRowIndexes, forward: forward) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }
    private var selectedItems: [Item] {
        table.selectedRowIndexes.compactMap { index in
            guard rows.indices.contains(index), case let .item(item) = rows[index] else { return nil }
            return item
        }
    }
    private func reload() {
        guard store.state.profiles.contains(where: { $0.id == profileID }) else { onClose?(); return }
        if shouldSkipCatalogReload() { return }
        defer {
            let width = kind == .spaces ? SpaceManagementLayout.libraryWidth(count: store.state.spaces.count) : SidebarChromeFrames.libraryMinimumWidth
            if contentWidth != width { contentWidth = width; onContentWidthChange?() }
        }
        if store.isEphemeral {
            if kind == .captures, let context = privateMediaContext, context.isValid() {
                for view in listControls { view.isHidden = true }
                if renderedKind == .downloads { downloadsView.isHidden = true }
                let media: CaptureLibraryView
                if let existing = privateMediaView { media = existing }
                else {
                    let catalog = CaptureLibraryStore.shared(directory: context.store.capturesDirectory(for: context.profileID), profileID: context.profileID)
                    media = CaptureLibraryView(store: catalog, profileOwner: context.store, media: context.media, ownerValid: { [weak self] in
                        guard let self else { return false }
                        return self.kind == .captures && self.window != nil && context.isValid()
                    })
                    media.onClose = { [weak self] in self?.onClose?() }
                    media.onOpenSource = { [weak self] url in self?.onOpenURLs?([url]) }
                    media.onToast = { [weak self] in self?.onToast?($0) }
                    privateMediaView = media
                }
                if media.superview == nil { addSubview(media) }
                media.isHidden = false; media.palette = palette; media.activate()
                capturesButton.state = .on; downloadsButton.state = .off
            } else {
                for view in listControls { view.isHidden = true }
                privateMediaView?.isHidden = true
                if downloadsView.superview == nil { addSubview(downloadsView) }
                downloadsView.isHidden = false
                if renderedKind != .downloads { downloadsView.palette = palette }
                downloadsButton.state = .on; capturesButton.state = .off
            }
            renderedKind = kind; needsLayout = true; return
        }
        if kind == .spaces {
            for view in listControls + [capturesView, downloadsView, documentsView] { view.isHidden = true }
            if spaceManager.superview == nil { addSubview(spaceManager) }
            spaceManager.isHidden = false; spaceManager.reload(store.state)
            for button in [capturesButton, downloadsButton, documentsButton, archiveButton] { button.state = .off }
            spacesButton.state = .on; renderedKind = kind; rememberAppliedCatalog(); needsLayout = true; return
        }
        spaceManager.isHidden = true; spacesButton.state = .off
        if kind == .documents {
            if renderedKind == .documents, documentsView.superview != nil, !documentsView.isHidden {
                documentsView.reload()
                rememberAppliedCatalog()
                return
            }
            for view in listControls { view.isHidden = true }
            capturesView.isHidden = true; downloadsView.isHidden = true
            if documentsView.superview == nil { addSubview(documentsView) }
            documentsView.isHidden = false; documentsView.palette = palette; documentsView.reload()
            documentsButton.state = .on; downloadsButton.state = .off; capturesButton.state = .off; archiveButton.state = .off
            renderedKind = kind; rememberAppliedCatalog(); needsLayout = true; return
        }
        documentsView.isHidden = true; documentsButton.state = .off
        if kind == .downloads {
            for view in listControls { view.isHidden = true }
            capturesView.isHidden = true
            if downloadsView.superview == nil { addSubview(downloadsView) }
            downloadsView.isHidden = false
            if renderedKind != kind { downloadsView.palette = palette }
            downloadsButton.state = .on; capturesButton.state = .off; archiveButton.state = .off
            renderedKind = kind; needsLayout = true; return
        }
        downloadsView.isHidden = true; downloadsButton.state = .off
        if kind == .captures {
            for view in listControls { view.isHidden = true }
            if capturesView.superview == nil { addSubview(capturesView) }
            capturesView.isHidden = false; capturesView.palette = palette; capturesView.activate()
            capturesButton.state = .on; archiveButton.state = .off
            renderedKind = kind; needsLayout = true; return
        }
        capturesView.isHidden = true; capturesButton.state = .off
        let archived = store.state.archivedTabs(where: { $0.profileID == profileID })
        observedTabs = store.state.tabs
        observedArchivedTabs = archived
        let nextItems = store.archivedItems(profileID: profileID).map { item in
            Item(id: item.id, tabIDs: item.tabs.map(\.id), title: item.title, urls: item.urls,
                 date: item.archivedAt, spaceID: item.provenance?.spaceID ?? item.tabs[0].spaceID,
                 spaceName: item.provenance?.spaceName ?? store.state.spaces.first { $0.id == item.tabs[0].spaceID }?.name,
                 reason: item.provenance?.reason, archivedTabs: item.tabs)
        }
        let spaces = store.state.spaces.filter { $0.profileID == profileID }
        let spaceSignature = spaces.map { $0.id.uuidString + ":" + $0.name }
        guard nextItems != allItems || renderedKind != kind || spaceSignature != filterSpaceSignature else { return }
        filterSpaceSignature = spaceSignature
        if let selectedSpaceFilter, !spaces.contains(where: { $0.id == selectedSpaceFilter }) {
            self.selectedSpaceFilter = nil
        }
        for view in listControls { view.isHidden = false }
        allItems = nextItems; renderedKind = kind
        settleFilterAnimation()
        search.placeholderString = "Search Archive…"
        filter.isHidden = false
        archiveButton.state = .on
        rebuildFilters()
        reloadRows()
    }

    private func shouldSkipCatalogReload() -> Bool {
        guard renderedKind == kind else { return false }
        switch kind {
        case .archive:
            let spaces = store.state.spaces.filter { $0.profileID == profileID }
            let spaceSignature = spaces.map { $0.id.uuidString + ":" + $0.name }
            if libraryArrayUnchanged(store.state.tabs, observedTabs),
               spaceSignature == filterSpaceSignature { return true }
            let archived = store.state.archivedTabs(where: { $0.profileID == profileID })
            if archived == observedArchivedTabs, spaceSignature == filterSpaceSignature {
                observedTabs = store.state.tabs
                return true
            }
            return false
        case .downloads:
            return downloadsView.superview != nil && !downloadsView.isHidden
        case .captures:
            if store.isEphemeral {
                return privateMediaContext?.isValid() == true
                    && privateMediaView?.superview != nil
                    && privateMediaView?.isHidden == false
            }
            return capturesView.superview != nil && !capturesView.isHidden
        case .documents:
            return documentsView.superview != nil && !documentsView.isHidden
                && observedProfileRemovalPending == store.isProfileRemovalPending(profileID)
        case .spaces:
            return libraryArrayUnchanged(store.state.tabs, observedTabs)
                && libraryArrayUnchanged(store.state.spaces, observedSpaces)
                && libraryArrayUnchanged(store.state.profiles, observedProfiles)
                && libraryArrayUnchanged(store.state.folders, observedFolders)
                && libraryArrayUnchanged(store.state.splitLayouts, observedSplitLayouts)
                && store.state.sidebarItemOrder == observedSidebarItemOrder
                && store.state.activeSpaceID == observedActiveSpaceID
                && store.state.selectedTabIDs == observedSelectedTabIDs
                && store.state.selectionBySpace == observedSelectionBySpace
                && store.state.profileRemovals == observedProfileRemovals
                && store.state.settings == observedSettings
        }
    }

    private func rememberAppliedCatalog() {
        switch kind {
        case .documents:
            observedProfileRemovalPending = store.isProfileRemovalPending(profileID)
        case .spaces:
            observedTabs = store.state.tabs
            observedSpaces = store.state.spaces
            observedProfiles = store.state.profiles
            observedFolders = store.state.folders
            observedSplitLayouts = store.state.splitLayouts
            observedSidebarItemOrder = store.state.sidebarItemOrder
            observedActiveSpaceID = store.state.activeSpaceID
            observedSelectedTabIDs = store.state.selectedTabIDs
            observedSelectionBySpace = store.state.selectionBySpace
            observedProfileRemovals = store.state.profileRemovals
            observedSettings = store.state.settings
        case .archive, .downloads, .captures:
            break
        }
    }
    private func reloadRows() {
        guard kind != .captures && kind != .downloads && kind != .documents && kind != .spaces else { needsLayout = true; return }
        let selected = Set(selectedItems.map(\.id))
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = allItems.filter { item in
            if !query.isEmpty && !item.title.localizedCaseInsensitiveContains(query)
                && !item.urls.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return false }
            if kind == .archive {
                if let closureFilter {
                    guard let reason = item.reason,
                          closureFilter == (reason.isManual ? .manual : .automatic) else { return false }
                }
                if let selectedSpaceFilter, item.spaceID != selectedSpaceFilter { return false }
            }
            return true
        }
        rows = []
        var previousHeading: String?
        let today = Date(), calendar = Calendar.current
        for item in items {
            let heading = kind == .archive ? Self.heading(for: item.date, relativeTo: today)
                : calendar.isDateInToday(item.date) ? "Today" : calendar.isDateInYesterday(item.date) ? "Yesterday"
                : calendar.startOfDay(for: item.date).formatted(date: .abbreviated, time: .omitted)
            if heading != previousHeading { rows.append(.heading(heading)); previousHeading = heading }
            rows.append(.item(item))
        }
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { index in
            if case let .item(item) = rows[index] { return selected.contains(item.id) }; return false
        }), byExtendingSelection: false)
        table.resampleHover()
        empty.isHidden = !items.isEmpty
        empty.stringValue = allItems.isEmpty ? (kind == .archive ? "Your closed tabs will appear here.\nArchived tabs are kept for 60 days." : "Pages you visit will appear here.") : "No matching pages.\nTry another search or filter."
        needsLayout = true
    }
    private static let relativeDays: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    static func heading(for date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date), today = calendar.startOfDay(for: now)
        if day == today { return "Today" }
        if calendar.date(byAdding: .day, value: -1, to: today) == day { return "Yesterday" }
        return relativeDays.localizedString(for: day, relativeTo: today)
    }
    @objc private func listDidScroll() { table.resampleHover() }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        let items = proposed.intersection(selectableRows)
        guard kind == .archive else { return items }
        return items.first.map { IndexSet(integer: $0) } ?? []
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard rows.indices.contains(row), case .item = rows[row] else { return false }; return true
    }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .heading = rows[row] { return true }; return false
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .heading = rows[row] { return 27.5 }; return 56
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = LibraryRowView()
        if case .heading = rows[row] { view.isHeading = true }
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .heading(let title):
            let field = LibraryInkField(string: title, size: 12, weight: .semibold, light: 0.565, dark: 0.592)
            let view = LayoutView(); view.addSubview(field)
            view.onLayout = { [weak field, weak view] in field?.frame = NSRect(x: 10, y: 8.5, width: max(0, (view?.bounds.width ?? 0) - 20), height: 16) }
            return view
        case .item(let item):
            let subtitle = Self.subtitle(urls: item.urls, spaceName: item.spaceName)
            let view = LibraryItemView(title: item.title, subtitle: subtitle)
            view.toolTip = (item.urls.filter { !$0.isEmpty } + [item.date.formatted(date: .abbreviated, time: .shortened)]).joined(separator: "\n")
            view.setAccessibilityLabel(item.title + ", " + subtitle)
            if kind == .archive && !store.isEphemeral {
                view.onPutBack = { [weak self] in self?.archiveAction(item) { $0.onRestore?([item.id], item.spaceID) } }
                view.onDelete = { [weak self] in
                    self?.archiveAction(item) { $0.store.deleteArchivedTabs(Set(item.tabIDs), profileID: $0.profileID) }
                }
            }
            if item.urls.count > 1 { view.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split view") }
            else if let url = item.urls.first.flatMap(URL.init(string:)) {
                view.image = icons[url]
                if let requestIcon, !resolvedIcons.contains(url), pendingIcons.insert(url).inserted {
                    requestIcon(url, profileID) { [weak self, weak view] image in
                        guard let self, self.window != nil else { return }
                        self.pendingIcons.remove(url); self.resolvedIcons.insert(url)
                        if let image { self.icons[url] = image }
                        view?.image = image
                        let matching = IndexSet(self.rows.indices.filter { index in
                            if case let .item(item) = self.rows[index] { return item.urls.count == 1 && item.urls[0] == url.absoluteString }; return false
                        })
                        self.table.reloadData(forRowIndexes: matching, columnIndexes: IndexSet(integer: 0))
                    }
                }
            }
            return view
        }
    }
    static func subtitle(urls: [String], spaceName: String?) -> String {
        func address(_ string: String) -> String {
            guard let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return string }
            var text = string
            if url.user != nil || url.password != nil, var components = URLComponents(string: string) {
                components.user = nil; components.password = nil
                text = components.string ?? text
            }
            if scheme == "http" || scheme == "https", let range = text.range(of: "://") {
                text = String(text[range.upperBound...])
                if text.lowercased().hasPrefix("www.") { text.removeFirst(4) }
            }
            if text.hasSuffix("/") && !text.hasSuffix("://") { text.removeLast() }
            return text
        }
        let first = urls.first.map(address) ?? ""
        if urls.count > 1 { return "\(urls.count) tabs · \(spaceName ?? first)" }
        return first
    }
    private func archiveAction(_ item: Item, _ action: (LibraryView) -> Void) {
        guard validArchiveOwner, archiveOwnerValid?() == true, let snapshot = item.archivedTabs,
              store.archivedItems(profileID: profileID).first(where: { $0.id == item.id })?.tabs == snapshot else { return }
        action(self)
    }
    @objc private func clickRow() {
        let row = table.clickedRow
        guard (NSApp.currentEvent?.clickCount ?? 1) <= 1 else { return }
        clickStartedPreview = false
        guard kind == .archive, rows.indices.contains(row), case let .item(item) = rows[row] else { return }
        archiveAction(item) { $0.clickStartedPreview = $0.onPreview?(item.id) == true }
    }
    @objc private func doubleClickRow() {
        if !clickStartedPreview { activate() }
    }
    @objc private func activate() {
        let items = selectedItems
        guard kind == .archive, !items.isEmpty else { return }
        onRestore?(items.map(\.id), selectedSpaceFilter)
    }
    private func deleteSelection() {
        let items = selectedItems
        guard kind == .archive, !items.isEmpty else { return }
        let ids = Set(items.flatMap(\.tabIDs))
        confirm(message: "Delete these archived tabs?",
                detail: "These tabs will no longer be available to put back. Open tabs and browsing history are unchanged.", button: "Delete") { [weak self] in
            guard let self else { return }
            self.store.deleteArchivedTabs(ids, profileID: self.profileID)
        }
    }
    func clearAll() {
        guard kind == .archive else { return }
        confirm(message: "Are you sure you'd like to Clear Archive?", detail: "This action is permanent.",
                button: "Clear Archive") { [weak self] in
            guard let self else { return }
            self.store.clearArchive(profileID: self.profileID)
            DispatchQueue.main.async { [weak self] in self?.onToast?(.archiveCleared) }
        }
    }
    private func confirm(message: String, detail: String, button: String, action: @escaping () -> Void) {
        guard let window, window.attachedSheet == nil else { return }
        ParcDialog.confirm(in: window, title: message, message: detail, confirm: button, destructive: true) { [weak self] approved in
            guard approved, let self, self.window === window,
                  self.store.state.profiles.contains(where: { $0.id == self.profileID }) else { return }
            action()
        }
    }
    private func copySelection() {
        let text = selectedItems.flatMap(\.urls).filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    private func rowMenu(_ row: Int) -> NSMenu? {
        guard rows.indices.contains(row), case let .item(item) = rows[row] else { return clearMenu() }
        if kind == .archive {
            guard validArchiveOwner, archiveOwnerValid?() == true,
                  let originalWindow = window, let snapshot = item.archivedTabs,
                  store.archivedItems(profileID: profileID).first(where: { $0.id == item.id })?.tabs == snapshot else { return nil }
            let generation = archiveMenuGeneration
            let lease = ArchiveMenuLease(store: store, profileID: profileID, tabs: snapshot)
            let valid: () -> Bool = { [weak self, weak originalWindow] in
                guard lease.isValid, let self, self.archiveMenuGeneration == generation,
                      let originalWindow, self.window === originalWindow,
                      self.validArchiveOwner, self.archiveOwnerValid?() == true else { return false }
                return self.store.archivedItems(profileID: self.profileID)
                    .first(where: { $0.id == item.id })?.tabs == snapshot
            }
            let menu = NSMenu()
            menu.addItem(MenuAction.item("Restore") { [weak self] in
                guard valid(), let self else { return }
                self.onRestore?([item.id], item.spaceID)
            })
            menu.addItem(MenuAction.item("Delete") { [weak self] in
                guard valid(), let self else { return }
                self.store.deleteArchivedTabs(Set(snapshot.map(\.id)), profileID: self.profileID)
            })
            menu.addItem(.separator())
            menu.addItem(clearItem())
            return menu
        }
        return nil
    }
    private func clearMenu() -> NSMenu? {
        guard validArchiveOwner else { return nil }
        let menu = NSMenu(); menu.addItem(clearItem()); return menu
    }
    private func clearItem() -> NSMenuItem {
        MenuAction.item("Clear Archive…") { [weak self] in self?.clearAll() }
    }
    private var validArchiveOwner: Bool {
        kind == .archive && !store.isEphemeral && window != nil && window?.attachedSheet == nil &&
            store.state.profiles.contains { $0.id == profileID } && !store.isProfileRemovalPending(profileID)
    }
    private func toggleFilters() { setFiltersExpanded(!filtersExpanded) }
    private func setFiltersExpanded(_ expanded: Bool, animated: Bool = true) {
        guard validArchiveOwner, let window, expanded != filtersExpanded else { return }
        if expanded, let editor = search.currentEditor() as? NSTextView, window.firstResponder === editor {
            guard !editor.hasMarkedText() else { return }
            savedSearchSelection = editor.selectedRange()
            guard window.makeFirstResponder(filter) else { savedSearchSelection = nil; return }
        }
        let focusWasInFilters = (window.firstResponder as? NSView)?.isDescendant(of: filterContent) == true
        let restoreSearch = !expanded && savedSearchSelection != nil &&
            (window.firstResponder === filter || focusWasInFilters)
        layoutSubtreeIfNeeded()
        filterAnimationGeneration &+= 1
        filtersExpanded = expanded
        rebuildFilters()
        let token = filterAnimationGeneration
        let duration = animated && !reduceMotion() ? 0.3 : 0
        searchBackdrop.isHidden = false; filterTitle.isHidden = false; filterScroll.isHidden = false
        search.isEnabled = !expanded
        search.setAccessibilityHidden(expanded); filterTitle.setAccessibilityHidden(!expanded)
        filterScroll.setAccessibilityHidden(!expanded)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            context.allowsImplicitAnimation = duration > 0
            animatingFilterLayout = duration > 0
            searchBackdrop.animator().alphaValue = expanded ? 0 : 1
            filterTitle.animator().alphaValue = expanded ? 1 : 0
            filterScroll.animator().alphaValue = expanded ? 1 : 0
            needsLayout = true; layoutSubtreeIfNeeded()
            animatingFilterLayout = false
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.filterAnimationGeneration == token else { return }
                self.settleFilterAnimation()
            }
        }
        if duration == 0 { settleFilterAnimation() }
        if restoreSearch, let range = savedSearchSelection {
            window.makeFirstResponder(search)
            let length = search.stringValue.utf16.count
            let location = min(range.location, length)
            (search.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: location, length: min(range.length, length - location)))
        }
        if !expanded {
            if !restoreSearch && focusWasInFilters { window.makeFirstResponder(filter) }
            savedSearchSelection = nil
        }
    }
    private func settleFilterAnimation() {
        filterAnimationGeneration &+= 1
        for view in [searchBackdrop, filterTitle, filterScroll, scroll, empty] {
            for key in ["position", "bounds", "opacity"] { view.layer?.removeAnimation(forKey: key) }
        }
        let archive = kind == .archive && !store.isEphemeral
        let showsSearch = !store.isEphemeral && kind == .archive
        searchBackdrop.alphaValue = filtersExpanded && archive ? 0 : 1
        searchBackdrop.isHidden = !showsSearch || (filtersExpanded && archive)
        filterTitle.alphaValue = filtersExpanded && archive ? 1 : 0
        filterTitle.isHidden = !filtersExpanded || !archive
        filterScroll.alphaValue = filtersExpanded && archive ? 1 : 0
        filterScroll.isHidden = !filtersExpanded || !archive
        search.isEnabled = !filtersExpanded || !archive
        search.setAccessibilityHidden(filtersExpanded && archive)
        filterTitle.setAccessibilityHidden(filterTitle.isHidden)
        filterScroll.setAccessibilityHidden(filterScroll.isHidden)
        needsLayout = true
    }
    private func rebuildFilters() {
        filterControlsGeneration &+= 1
        let generation = filterControlsGeneration
        let ownerWindow = window
        let focused = (window?.firstResponder as? NSButton)?.identifier
        filterControls.forEach { $0.removeFromSuperview() }; filterControls = []
        filter.title = filtersExpanded ? "Done" : "Filter"
        filter.symbol = filtersExpanded ? nil : "line.3.horizontal.decrease.circle"
        filter.setAccessibilityLabel(filter.title)
        guard kind == .archive && filtersExpanded else { filterHeight = 0; needsLayout = true; return }
        func label(_ text: String) {
            let label = LibraryInkField(string: text, size: 12, weight: .semibold, light: 0.565, dark: 0.592)
            filterControls.append(label); filterContent.addSubview(label)
        }
        func chip(_ title: String, key: String, selected: Bool, action: @escaping () -> Void) {
            let button = DownloadFilterButton(title, action: action)
            button.identifier = NSUserInterfaceItemIdentifier(key)
            button.isChosen = selected; button.ink = LibraryInk.chrome(effectiveAppearance)
            button.setAccessibilityValue(NSNumber(value: selected))
            filterControls.append(button); filterContent.addSubview(button)
        }
        label("How was the tab closed?")
        for (title, value) in [("Auto-Closed", ClosureFilter.automatic), ("Manually Closed", .manual)] {
            chip(title, key: title, selected: closureFilter == value) { [weak self, weak ownerWindow] in
                guard let self, let ownerWindow, self.validArchiveOwner, self.filtersExpanded, self.filterControlsGeneration == generation, self.window === ownerWindow else { return }
                self.closureFilter = self.closureFilter == value ? nil : value
                self.rebuildFilters(); self.reloadRows()
            }
        }
        label("Where was the tab?")
        for space in store.state.spaces where space.profileID == profileID {
            let id = space.id
            chip(space.name, key: id.uuidString, selected: selectedSpaceFilter == id) { [weak self, weak ownerWindow] in
                guard let self, let ownerWindow, self.validArchiveOwner, self.filtersExpanded, self.filterControlsGeneration == generation, self.window === ownerWindow else { return }
                self.selectedSpaceFilter = self.selectedSpaceFilter == id ? nil : id
                self.rebuildFilters(); self.reloadRows()
            }
        }
        if let focused, let replacement = filterControls.first(where: { $0.identifier == focused }) {
            window?.makeFirstResponder(replacement)
        }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        func place(_ view: NSView, _ frame: NSRect) {
            if animatingFilterLayout { view.animator().frame = frame } else { view.frame = frame }
        }
        let railWidth = LibraryRailLayout.width, listX = railWidth + 8, listRight = bounds.width - 10
        let listWidth = max(0, listRight - listX)
        depth.frame = NSRect(x: 0, y: 0, width: LibraryDepthView.width, height: bounds.height)
        windowButtons.frame = NSRect(origin: NSPoint(x: 16, y: 21), size: WindowStandardButtons.stackSize)
        rail.frame = NSRect(x: 0, y: 0, width: railWidth, height: bounds.height)
        let visible = categoryButtons.filter { !$0.isHidden }
        for (button, frame) in zip(visible, LibraryRailLayout.tiles(count: visible.count, height: bounds.height)) {
            button.frame = frame; button.showsLabel = frame.height >= 65
        }
        back.frame = LibraryRailLayout.back(height: bounds.height)
        downloadsView.frame = NSRect(x: railWidth, y: 0, width: max(0, bounds.width - railWidth), height: bounds.height)
        if store.isEphemeral {
            privateMediaView?.frame = downloadsView.frame
            return
        }
        capturesView.frame = downloadsView.frame
        documentsView.frame = downloadsView.frame
        let spacesInset = SpaceManagementLayout.pageInset
        spaceManager.frame = NSRect(x: railWidth + spacesInset, y: 0, width: max(0, downloadsView.frame.width - 2 * spacesInset),
                                    height: bounds.height)
        let headerX = railWidth + LibraryPageHeader.inset
        let headerWidth = max(0, bounds.width - railWidth - 2 * LibraryPageHeader.inset)
        let filterWidth = kind == .archive ? min(filter.fittingSize.width, headerWidth) : 0
        let fieldWidth = headerWidth - (kind == .archive ? filterWidth + LibraryPageHeader.spacing : 0)
        searchBackdrop.frame = NSRect(x: headerX, y: LibraryPageHeader.top, width: max(0, fieldWidth), height: LibraryPageHeader.height)
        place(filter, NSRect(x: headerX + headerWidth - filterWidth, y: LibraryPageHeader.top, width: filterWidth, height: LibraryPageHeader.height))
        filterTitle.frame = NSRect(x: listX + 4, y: 19, width: max(0, listWidth - filterWidth - 8), height: 18)
        let chipHeight: CGFloat = 31, gap: CGFloat = 7
        var x: CGFloat = 0, y: CGFloat = 5
        for view in filterControls {
            if let label = view as? NSTextField {
                if x != 0 { y += chipHeight + 16 }; x = 0
                label.frame = NSRect(x: 4, y: y, width: max(0, listWidth - 4), height: 15); y += 23.5
            } else {
                let width = min(listWidth, max(0, view.fittingSize.width))
                if x > 0 && x + width > listWidth { x = 0; y += chipHeight + gap }
                view.frame = NSRect(x: x, y: y, width: width, height: chipHeight); x += width + gap
            }
        }
        if x != 0 { y += chipHeight + 16 }
        filterContent.frame = NSRect(x: 0, y: 0, width: listWidth, height: y)
        filterHeight = filtersExpanded && kind == .archive ? min(y, min(250, bounds.height * 0.38)) : 0
        place(filterScroll, NSRect(x: listX, y: 56, width: listWidth, height: filterHeight))
        let top = 56 + filterHeight
        place(scroll, NSRect(x: railWidth, y: top, width: max(0, bounds.width - railWidth), height: max(0, bounds.height - top)))
        place(empty, NSRect(x: listX + 12, y: top + 45, width: max(0, listWidth - 24), height: 90))
    }
    private func fadeInPage() {
        guard window != nil else { return }
        for view in subviews where !view.isHidden && view !== depth && view !== rail && view !== windowButtons {
            guard let layer = view.layer else { continue }
            layer.add(LibraryRailMotion.fade("opacity", from: 0, to: layer.opacity, duration: LibraryRailMotion.pageFade),
                      forKey: "parc.library.pageFade")
        }
    }
    private func restoreCategorySelection() {
        capturesButton.state = kind == .captures ? .on : .off
        downloadsButton.state = kind == .downloads ? .on : .off
        documentsButton.state = kind == .documents ? .on : .off
        spacesButton.state = kind == .spaces ? .on : .off
        archiveButton.state = kind == .archive ? .on : .off
    }
    private func applyPalette() {
        appearance = palette?.contentAppearance
        windowButtons.appearance = palette.map { NSAppearance(named: $0.isDark ? .darkAqua : .aqua) } ?? nil
        let iconColors = palette.map { ($0.maxContrastColor, $0.cutoutColor) }
        for button in categoryButtons { button.iconColors = iconColors }
        downloadsButton.progress?.colors = DownloadBadgeColors(foreground: palette?.foregroundPrimary ?? .labelColor,
            maxContrast: palette?.maxContrastColor ?? .labelColor, cutout: palette?.cutoutColor ?? .windowBackgroundColor)
        if !store.isEphemeral {
            capturesView.palette = palette
            documentsView.palette = palette
        } else { privateMediaView?.palette = palette }
        if !store.isEphemeral || kind == .downloads { downloadsView.palette = palette }
        empty.textColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        back.contentTintColor = LibraryInk.chrome(effectiveAppearance)
        rebuildFilters(); table.reloadData()
    }
}

private func libraryArrayUnchanged<T>(_ current: [T], _ observed: [T]) -> Bool {
    current.withUnsafeBufferPointer { left in
        observed.withUnsafeBufferPointer { right in
            left.baseAddress == right.baseAddress && left.count == right.count
        }
    }
}

@MainActor
private final class ArchiveMenuLease {
    private(set) var isValid = true
    private var subscription: AnyCancellable?
    init(store: BrowserStore, profileID: UUID, tabs: [BrowserTab]) {
        subscription = store.statePublisher.sink { [weak self] state in
            guard let self, self.isValid else { return }
            if !state.profiles.contains(where: { $0.id == profileID }) ||
                !tabs.allSatisfy({ expected in state.tabs.contains(where: { $0 == expected }) }) {
                self.isValid = false
            }
        }
    }
}

@MainActor
private final class LibraryTable: NSTableView {
    var onActivate: (() -> Void)?
    var onDelete: (() -> Void)?
    var onClose: (() -> Void)?
    var onSearch: (() -> Void)?
    var onCopy: (() -> Void)?
    var singleCursor: (() -> Bool)?
    var onMoveCursor: ((Bool) -> Void)?
    var selectContextRow: (() -> Bool)?
    var contextMenu: ((Int) -> NSMenu?)?
    private var hoverTracking: NSTrackingArea?
    private var keyObservers: [NSObjectProtocol] = []
    private(set) var hoveredRow = -1 {
        didSet {
            guard hoveredRow != oldValue else { return }
            for row in [oldValue, hoveredRow] where row >= 0 && row < numberOfRows {
                (rowView(atRow: row, makeIfNecessary: false) as? LibraryRowView)?.hovered = row == hoveredRow
            }
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        hoverTracking = next; addTrackingArea(next)
    }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); resampleHover() }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); resampleHover() }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); hoveredRow = -1 }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        keyObservers.forEach { NotificationCenter.default.removeObserver($0) }; keyObservers = []
        hoveredRow = -1
        if let newWindow {
            keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.resampleHover() }
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }
    func resampleHover() {
        guard let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor else { hoveredRow = -1; return }
        let location = window.mouseLocationOutsideOfEventStream, point = convert(location, from: nil)
        let row = visibleRect.contains(point) && isTopmost(atWindowPoint: location) ? row(at: point) : -1
        hoveredRow = row >= 0 && delegate?.tableView?(self, shouldSelectRow: row) != false ? row : -1
    }
    override func didAdd(_ rowView: NSTableRowView, forRow row: Int) {
        super.didAdd(rowView, forRow: row)
        (rowView as? LibraryRowView)?.hovered = row == hoveredRow
    }
    @objc func copy(_ sender: Any?) { onCopy?() }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(selectAll(_:)), singleCursor?() == true { return false }
        return super.validateUserInterfaceItem(item)
    }
    override func selectAll(_ sender: Any?) {
        if singleCursor?() != true { super.selectAll(sender) }
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if singleCursor?() == true {
            let cursorModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if cursorModifiers == .command && event.charactersIgnoringModifiers == "a" { return }
            if cursorModifiers.isEmpty || cursorModifiers == .shift {
                if event.keyCode == 125 { onMoveCursor?(true); return }
                if event.keyCode == 126 { onMoveCursor?(false); return }
            }
        }
        if modifiers.contains(.command) {
            if event.charactersIgnoringModifiers == "f" { onSearch?(); return }
            if event.charactersIgnoringModifiers == "c" { onCopy?(); return }
        }
        switch event.keyCode {
        case 36, 76: onActivate?()
        case 51, 117: onDelete?()
        case 53: onClose?()
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let index = row(at: convert(event.locationInWindow, from: nil))
        guard index >= 0, delegate?.tableView?(self, shouldSelectRow: index) != false else { return contextMenu?(-1) }
        if selectContextRow?() != false && !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        return contextMenu?(index)
    }
}

@MainActor
private final class LibraryRowView: NSTableRowView {
    var isHeading = false
    var hovered = false { didSet { if hovered != oldValue { refresh() } } }
    private let backdrop = DownloadRowBackdrop()
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(backdrop, positioned: .below, relativeTo: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isSelected: Bool { didSet { refresh() } }
    override var isEmphasized: Bool { didSet { refresh() } }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) {}
    override func drawSelection(in dirtyRect: NSRect) {}
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== backdrop { refresh() }
    }
    override func layout() {
        super.layout()
        backdrop.frame = bounds.insetBy(dx: 8, dy: 0)
    }
    private func refresh() {
        let active = !isHeading && (hovered || isSelected)
        backdrop.highlighted = active; backdrop.emphasized = isEmphasized
        for case let cell as LibraryItemView in subviews { cell.setHighlighted(active) }
    }
}

@MainActor enum LibraryInk {
    static func chrome(_ appearance: NSAppearance) -> NSColor {
        DownloadAccessoryColors.foreground(hovered: false, appearance: appearance)
    }
}

@MainActor final class LibraryInkField: NSTextField {
    var lightAlpha: CGFloat { didSet { needsDisplay = true } }
    var darkAlpha: CGFloat { didSet { needsDisplay = true } }
    init(string: String, size: CGFloat, weight: NSFont.Weight, light: CGFloat, dark: CGFloat) {
        lightAlpha = light; darkAlpha = dark
        super.init(frame: .zero)
        stringValue = string
        font = .systemFont(ofSize: size, weight: weight)
        isBezeled = false; drawsBackground = false; isEditable = false; isSelectable = false
        lineBreakMode = .byTruncatingTail; maximumNumberOfLines = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ dirtyRect: NSRect) {
        let dark = WindowStandardButtons.isDark(effectiveAppearance)
        let color = NSColor(srgbRed: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0, alpha: dark ? darkAlpha : lightAlpha)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let face = font ?? .systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [.font: face, .foregroundColor: color, .paragraphStyle: paragraph]
        let text = stringValue as NSString
        let height = text.size(withAttributes: attributes).height
        text.draw(in: NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height), withAttributes: attributes)
    }
}

@MainActor
private final class LibraryItemView: NSTableCellView {
    static func primary(_ opacity: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            var color = NSColor.black
            appearance.performAsCurrentDrawingAppearance {
                let label = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
                color = label.withAlphaComponent(label.alphaComponent * opacity)
            }
            return color
        }
    }
    private let title = LibraryInkField(string: "", size: 14, weight: .regular, light: 0.75, dark: 0.85)
    private let subtitle = LibraryInkField(string: "", size: 12, weight: .regular, light: 0.50, dark: 0.55)
    private let icon = NSImageView()
    private let placeholder = NSView()
    private let deleteButton = LibraryRowButton(symbol: "trash", label: "Delete")
    private let putBackButton = LibraryRowButton(symbol: "arrow.uturn.backward", label: "Put Back", tooltip: "Restore")
    private var highlighted = false
    var image: NSImage? { didSet { icon.image = image; placeholder.isHidden = image != nil } }
    var onDelete: (() -> Void)? { didSet { deleteButton.actionBlock = onDelete } }
    var onPutBack: (() -> Void)? { didSet { putBackButton.actionBlock = onPutBack } }
    override var isFlipped: Bool { true }
    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        self.title.stringValue = title; self.subtitle.stringValue = subtitle
        for label in [self.title, self.subtitle] {
            label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
            label.setAccessibilityHidden(true); addSubview(label)
        }
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = 8; placeholder.layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyDown; icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityHidden(true)
        addSubview(placeholder); addSubview(icon)
        for button in [deleteButton, putBackButton] { button.isHidden = true; addSubview(button) }
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func accessibilityChildren() -> [Any]? {
        [deleteButton, putBackButton].filter { !$0.isHidden && $0.actionBlock != nil }
    }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let actions = [("Put Back", onPutBack), ("Delete", onDelete)].compactMap { name, action in
            action.map { action in NSAccessibilityCustomAction(name: name) { action(); return true } }
        }
        return actions.isEmpty ? nil : actions
    }
    func setHighlighted(_ value: Bool) {
        highlighted = value
        let controls = value && onDelete != nil
        if !controls { for button in [deleteButton, putBackButton] where window?.firstResponder === button { window?.makeFirstResponder(superview?.superview) } }
        for button in [deleteButton, putBackButton] { button.isHidden = !controls }
        refreshColors(); needsLayout = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
    private func refreshColors() {
        title.lightAlpha = highlighted ? 0.85 : 0.75
        title.darkAlpha = highlighted ? 0.92 : 0.85
        effectiveAppearance.performAsCurrentDrawingAppearance {
            placeholder.layer?.backgroundColor = Self.primary(0.05).cgColor
        }
    }
    override func layout() {
        super.layout()
        let leading: CGFloat = 8, trailing = bounds.width - 8
        placeholder.frame = NSRect(x: leading + 10, y: (bounds.height - 24) / 2, width: 24, height: 24)
        icon.frame = NSRect(x: leading + 14, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let controlsX = deleteButton.isHidden ? trailing - 26 : trailing - 12 - 32 - 2 - 32 - 8
        let textX = leading + 42.5, textWidth = max(0, controlsX - textX)
        title.frame = NSRect(x: textX, y: 11, width: textWidth, height: 17)
        subtitle.frame = NSRect(x: textX, y: 30, width: textWidth, height: 15)
        putBackButton.frame = NSRect(x: trailing - 12 - 32, y: (bounds.height - 32) / 2, width: 32, height: 32)
        deleteButton.frame = NSRect(x: putBackButton.frame.minX - 2 - 32, y: putBackButton.frame.minY, width: 32, height: 32)
    }
}

@MainActor
private final class LibraryRowButton: PointingHandButton {
    var actionBlock: (() -> Void)?
    private var area: NSTrackingArea?
    private var hovered = false
    init(symbol: String, label: String, tooltip: String? = nil) {
        super.init(frame: .zero)
        title = ""; isBordered = false; bezelStyle = .regularSquare
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        imagePosition = .imageOnly; focusRingType = .default
        LiveShortcutToolTip.set(self, tooltip ?? label); setAccessibilityLabel(label)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        target = self; action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        area = next; addTrackingArea(next)
    }
    override var isHidden: Bool { didSet { if isHidden { hovered = false }; refreshTint() } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshTint() }
    override func mouseEntered(with event: NSEvent) { hovered = isTopmost(atWindowPoint: event.locationInWindow); refreshTint() }
    override func mouseMoved(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { super.mouseMoved(with: event); return }
        let value = isTopmost(atWindowPoint: event.locationInWindow)
        guard value != hovered else { return }
        hovered = value; refreshTint()
    }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshTint() }
    private func refreshTint() {
        contentTintColor = DownloadAccessoryColors.foreground(hovered: hovered, appearance: effectiveAppearance)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            DownloadAccessoryColors.background(pressed: isHighlighted, appearance: effectiveAppearance).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
    @objc private func invoke() { actionBlock?() }
}

@MainActor
private final class LibraryDepthView: NSView {
    static let width = LibraryRailLayout.width + 1 + 32
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let rail = LibraryRailLayout.width
        NSGradient(starting: NSColor(white: 1, alpha: 0.05), ending: NSColor(white: 1, alpha: 0))?
            .draw(in: NSRect(x: 0, y: 0, width: rail, height: bounds.height), angle: 180)
        LibraryItemView.primary(0.1).setFill()
        NSRect(x: rail, y: 0, width: 1, height: bounds.height).fill(using: .sourceOver)
        NSGradient(starting: NSColor(white: 0, alpha: 0.05), ending: NSColor(white: 0, alpha: 0))?
            .draw(in: NSRect(x: rail + 1, y: 0, width: 32, height: bounds.height), angle: 0)
    }
}

extension LibraryView {
    func harnessIcons(_ images: [URL: NSImage]) {
        icons = images; resolvedIcons = Set(images.keys); table.reloadData()
    }
    func harnessHover(_ title: String?) {
        table.layoutSubtreeIfNeeded()
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true) as? LibraryRowView else { continue }
            let cell = view.subviews.compactMap { $0 as? LibraryItemView }.first
            view.hovered = title != nil && cell?.harnessTitle == title
        }
        table.layoutSubtreeIfNeeded()
    }
    func harnessRowFrame(_ title: String) -> NSRect? {
        table.layoutSubtreeIfNeeded()
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true) else { continue }
            if let cell = view.subviews.compactMap({ $0 as? LibraryItemView }).first, cell.harnessTitle == title {
                return convert(view.bounds, from: view)
            }
        }
        return nil
    }
    func harnessPutBackFrame(_ title: String) -> NSRect? {
        for row in 0..<table.numberOfRows {
            guard let view = table.rowView(atRow: row, makeIfNecessary: true),
                  let cell = view.subviews.compactMap({ $0 as? LibraryItemView }).first, cell.harnessTitle == title else { continue }
            return convert(cell.harnessPutBack.bounds, from: cell.harnessPutBack)
        }
        return nil
    }
    var harnessRowCount: Int { table.numberOfRows }
}

extension LibraryItemView {
    var harnessTitle: String { title.stringValue }
    var harnessPutBack: NSView { putBackButton }
}
