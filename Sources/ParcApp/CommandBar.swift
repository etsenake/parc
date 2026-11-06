import AppKit
import Combine

/// One address-editing session. Navigation rows retain Chromium's classified
/// request; tab rows retain a tab ID; command rows retain the original menu item.
final class CommandBar: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Result {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        var subtitle: String? = nil
        /// The trailing Switch to Tab accessory, for tab rows only.
        var caption: CommandBarResultText.TabCaption? = nil
        /// Search glyphs stay off the selected row's icon tile.
        var isSearch = false
        var url: URL? = nil
        var tabID: UUID? = nil
        var command: KeyboardShortcuts.MenuCommand? = nil
        var spaceAction: CommandBarSpaceAction? = nil
        var folderAction: CommandBarFolderAction? = nil
        var favoriteAction: CommandBarFavoriteAction? = nil
        var folderMove: CommandBarFolderMove? = nil
        var favoriteRename: CommandBarFavoriteRenameAction? = nil
        var typedCommand: CommandBarTypedCommand? = nil
        var isExpired = false
        var navigation: PCNativeSearchNavigation? = nil
        var extensionAction: PCNativeOmniboxExtensionAction? = nil
        var extensionLaunch: PCNativeExtensionAction? = nil
        var input: String? = nil
        var managesPasswords = false
        var muteAllTabs: Bool? = nil
        var document: CommandBarDocument? = nil
    }
    var onNavigate: ((String) -> Void)?
    var onSearchNavigation: ((PCNativeSearchNavigation) -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    ///
    ///
    var tabCaption: ((BrowserTab) -> CommandBarResultText.TabCaption)? {
        didSet { lastOpenResultsFingerprint = nil }
    }
    /// The original window may own a temporary destination presentation. Mark
    /// only real input/navigation/tab submission before the common dismissal.
    var onWillSubmitDestination: (() -> Void)?
    var onRejectedDestination: (() -> Void)?
    var canFocusSpace: ((CommandBarSpaceAction) -> Bool)?
    var onFocusSpace: ((CommandBarSpaceAction) -> Void)?
    var canOpenFolder: ((CommandBarFolderAction) -> Bool)?
    var onOpenFolder: ((CommandBarFolderAction) -> Void)?
    var canMoveToFolder: ((CommandBarFolderMove) -> Bool)?
    var onMoveToFolder: ((CommandBarFolderMove) -> Void)?
    var canCopyToFolder: ((CommandBarFolderMove) -> Bool)?
    var onCopyToFolder: ((CommandBarFolderMove) -> Void)?
    var canPerformFavorite: ((CommandBarFavoriteAction) -> Bool)?
    var onPerformFavorite: ((CommandBarFavoriteAction) -> Void)?
    var canRenameFavorite: ((CommandBarFavoriteRenameAction) -> Bool)?
    var onRenameFavorite: ((CommandBarFavoriteRenameAction) -> Void)?
    ///
    /// answers availability while the panel is open and rechecks on commit.
    var canPerformTypedCommand: ((CommandBarTypedCommand) -> Bool)?
    var onPerformTypedCommand: ((CommandBarTypedCommand) -> Void)?
    var canSplitSelection: ((UUID?) -> Bool)?
    var onSplitInput: ((String) -> Void)?
    var onSplitNavigation: ((PCNativeSearchNavigation) -> Void)?
    var onSplitTab: ((UUID) -> Void)?
    /// Add Split's blank pane can be filled by New Note / New Easel. Ordinary
    /// command-bar commands still do not acquire a split destination.
    var canSplitCommand: ((KeyboardShortcuts.MenuCommand) -> Bool)?
    var onSplitCommand: ((KeyboardShortcuts.MenuCommand) -> Void)?
    // Completion reports an actual background page outcome. Validation stays
    // live during profile acquisition; no displayed URL substitutes for a token.
    var onBackgroundNavigation: ((PCNativeSearchNavigation, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    var onBackgroundInput: ((String, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    var onBackgroundTab: ((UUID, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    private var backgroundOperation: UUID?
    private var backgroundGeneration: UInt64 = 0
    private var retainedBackgroundHistory: (result: Result, row: Int)?
    var onDismiss: (() -> Void)?
    /// Runs after dismissal and any selected action have both returned.
    var onDismissalSettled: (() -> Void)?
    private var submissionDepth = 0
    var onManagePasswords: (() -> Void)?
    var onOpenDocument: ((CommandBarDocument) -> Void)?
    var onMuteAllTabs: ((Bool) -> Bool)?
    var onManageSiteSearch: (() -> Void)?
    /// The privacy banner's Search Settings…, after the bar is dismissed.
    var onSearchSettings: (() -> Void)?
    private let privacyBanner = CommandBarSearchPrivacyBanner()
    private let privacyInfoButton = CommandBarPrivacyInfoButton()
    private let privacyPolicy = CommandBarSearchPrivacyPolicy(defaults: .standard)
    private var privacyBannerVisible = false
    ///
    /// banner stays under the scoped results too.
    private var showsPrivacyBanner: Bool { privacyBannerVisible && sidebarAnchor == nil }
    private var privacyBannerHeight: CGFloat { privacyBanner.isHidden ? 0 : privacyBanner.frame.height }
    /// Profile/page-owned extension launch candidates, distinct from an
    /// extension's optional omnibox keyword and its query suggestions.
    var extensionLaunchActions: (() -> [PCNativeExtensionAction])? { didSet { extensionLaunchSnapshotIsStale = true } }
    var onLaunchExtension: ((PCNativeExtensionAction) -> Bool)?
    private var extensionLaunchSnapshot: [PCNativeExtensionAction] = []
    /// Set when the engine reports a change to its extension actions.
    private var extensionLaunchSnapshotIsStale = true
    var isOwnerValid: (() -> Bool)?
    /// Text the command field copied (the Super Copy upsell's input).
    var onCopyText: ((String) -> Void)?
    var restorePageFocus: (() -> Void)?
    /// Whether the responder saved at opening lies where the owner's close puts
    /// focus; one outside it gives way to `restorePageFocus`. Unset, any
    /// eligible saved responder returns.
    var mayRestoreOriginal: ((NSView) -> Bool)?
    var onSidebarMove: ((Int) -> Void)?
    var onSidebarCommit: (() -> Void)?
    var onSidebarQueryState: ((Bool) -> Void)?
    private weak var sidebarAnchor: NSView?
    private var sidebarBrowsing: Bool { sidebarAnchor != nil && input.stringValue.isEmpty && !isScoped && !scopeInvalidated }
    var isSidebarSession: Bool { sidebarAnchor != nil }
    func refreshPosition() { if presented && !dismissed { position() } }

    private let input = NSTextField()
    private let inputIcon = NSImageView()
    private let scopePill = CommandBarScopePill()
    private let actionsPill = CommandBarActionsPill()
    private var actionsScope = false
    private var scopeMenu: NSMenu?
    private var scopeMenuLease: PCNativeOmniboxScopeMenu?
    private var scopeAlert: NSAlert?
    private let scopeOfferButton = CommandBarScopeHint()
    ///
    private var scopeColor: NSColor?
    private var scopeColorRequest = 0
    private let extensionDisposition: PCNativeOmniboxExtensionDisposition?
    private let initialInput: String
    private var scopeOffers: [PCNativeOmniboxScope] = []
    /// Every active website engine in the snapshot that published `nativeResults`.
    private var siteScopes: [PCNativeOmniboxScope] = []
    private var activeScope: PCNativeOmniboxScope?
    private var enteringScopeName: String?
    private var scopeInvalidated = false
    private var unavailableScopeName: String?
    private var queryBeforeScope = ""
    /// The input the current native results answered.
    private var nativeInput = ""
    private var previousInput = ""
    private var editState: CommandBarEditState
    private var selectingProgrammatically = false
    private var applyingCompletion = false
    private var deletingCharacters = false
    private var snapshotRevision: UInt64 = 0
    private var isWebsiteScoped: Bool { activeScope != nil || enteringScopeName != nil }
    private var isScoped: Bool { actionsScope || isWebsiteScoped }
    private var scopedName: String { actionsScope ? "Actions" : activeScope?.name ?? enteringScopeName ?? "" }
    private var compactScopeHeight: CGFloat {
        if isWebsiteScoped && input.stringValue.isEmpty && results.isEmpty && nativeError == nil { return 64 }
        return 76 + CGFloat(max(1, min(5, results.count))) * 50
    }
    private let table = CommandResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Search or Enter URL…")
    private let container = CommandBarSurface()
    private let shadowWindow = CommandBarShadowWindow()
    private var showsShadow = true
    private var splashWindow: CommandBarSplashWindow?
    private var showsScopeSplash = false
    private let divider = CommandBarHairline()
    private var palette: CommandBarPalette
    /// The window's Space theme (its private-window palette in a private window).
    var theme: SpaceTheme {
        didSet {
            guard theme != oldValue else { return }
            palette = CommandBarPalette(theme: theme); applyPalette()
        }
    }
    private weak var parent: NSWindow?
    private weak var originalResponder: NSResponder?
    private var originalSelection: NSRange?
    private let profilePath: String
    private var tabs: [BrowserTab]
    private var history: [BrowserHistoryEntry]
    private var rankedHistory: [BrowserHistoryEntry]
    /// Store visit-list generation plus the current-URL exclusion used when the
    /// controller filtered `history`. Together they identify the scan input
    /// without remapping every visit on idle open-bar ticks.
    private var historyRevision: UInt64
    private var historyExcludedURL: String?
    /// Last empty-query history scan key and the visits it produced. Reused
    /// when query + historyRevision + excluded URL + tab URLs match.
    private var lastHistoryScanKey: CommandBarHistoryScanSkip.Key?
    private var cachedHistoryVisits: [CommandBarHistoryScanSkip.Visit] = []
    /// The profile's newest pages from Chromium's history, the one the History
    /// page shows, imported visits included. Asked for by the window; Parc's
    /// own visit list stands in until they arrive.
    private var recentPages: [(url: String, title: String)]?
    private var recentPagesGeneration = 0
    private var spaces: [CommandBarSpaceAction]
    private var folders: [CommandBarFolderAction]
    private let folderMoves: [CommandBarFolderMove]
    private let favoriteAction: CommandBarFavoriteAction?
    private let favoriteRename: CommandBarFavoriteRenameAction?
    /// Notes and Easels without a sidebar tab, read once on the first query.
    private let documentSource: (() -> [CommandBarDocument])?
    private lazy var documents: [CommandBarDocument] = documentSource?() ?? []
    /// Counted off the main thread by the window, which owns their cache.
    private var topDomainList: [CommandBarRanking.Domain] = []
    private var topDomainGeneration = 0
    private let typedCommands: [CommandBarTypedCommand]
    private var commands: [KeyboardShortcuts.MenuCommand] = []
    /// Each command's displayed title and lowercased searchable text, by index.
    private var commandSearch: [(title: String, text: String)] = []
    /// Builds the searchable text once per command list, not for every
    /// command on every update while typing.
    private func adoptCommands(_ list: [KeyboardShortcuts.MenuCommand]) {
        commands = list
        commandSearch = list.map { command in
            let title = Self.title(for: command)
            return (title, (title + " " + command.title + " " + command.group + " "
                + CommandBarTypedCommand.commandBarSearchText(forMenuCommand: command.id)).lowercased())
        }
    }
    private var results: [Result] = []
    private var resultPublication = UUID()
    private var omnibox: PCNativeOmnibox?
    private var nativeResults: [PCNativeSearchNavigation] = []
    private var extensionActions: [PCNativeOmniboxExtensionAction] = []
    private var nativeError: String?
    private var explicitSelectionID: String?
    private var icons: [URL: NSImage] = [:]
    private var requestedIcons = Set<URL>()
    private var observers: [NSObjectProtocol] = []
    private var bindings: AnyCancellable?
    private var dismissed = false
    private var presented = false
    private var initialEditSelection: NSRange?
    /// Last presented open-bar query/result-identity fingerprint. Refresh paths
    /// that leave query and result identity unchanged skip Result rebuild,
    /// `reloadData`, and `layoutContents`. Closed-bar gating stays separate.
    private var lastOpenResultsFingerprint: String?
    ///
    private var presentedRows: [CommandBarRowDiff.Row] = []
    ///
    ///
    /// current query, so typing never shows an intermediate list. A source
    ///
    ///
    private var nativeHold = CommandBarNativeHold()
    private var nativeHoldDeadline: DispatchWorkItem?

    init(parent: NSWindow, tabs: [BrowserTab], history: [BrowserHistoryEntry], historyRevision: UInt64 = 0, historyExcludedURL: String? = nil, spaces: [CommandBarSpaceAction] = [], folders: [CommandBarFolderAction] = [], favoriteAction: CommandBarFavoriteAction? = nil, folderMoves: [CommandBarFolderMove] = [], favoriteRename: CommandBarFavoriteRenameAction? = nil, documents: (() -> [CommandBarDocument])? = nil, typedCommands: [CommandBarTypedCommand] = [], currentURL: String?, profilePath: String, page: PCNativePage?, nativeWindow: PCNativeBrowserWindow? = nil, sidebarAnchor: NSView? = nil, initialEdit: (String, NSRange)? = nil, extensionDisposition: PCNativeOmniboxExtensionDisposition? = .currentTab, theme: SpaceTheme = SpaceTheme(), contentAppearance: NSAppearance? = nil) {
        self.extensionDisposition = extensionDisposition
        self.theme = theme; palette = CommandBarPalette(theme: theme); self.contentAppearance = contentAppearance
        initialInput = currentURL == "about:blank" ? "" : currentURL ?? ""
        editState = CommandBarEditState(query: initialEdit?.0 ?? initialInput)
        self.sidebarAnchor = sidebarAnchor
        initialEditSelection = initialEdit?.1
        self.tabs = tabs; self.history = history; self.rankedHistory = BrowserHistoryOrder.newestFirst(history)
        self.historyRevision = historyRevision
        // Prefer the controller's filter exclusion; fall back to the field seed
        // so membership tokens stay aligned with commandBarHistory.
        self.historyExcludedURL = historyExcludedURL ?? (currentURL == "about:blank" ? nil : currentURL)
        self.spaces = spaces; self.folders = folders; self.favoriteAction = favoriteAction; self.folderMoves = folderMoves; self.favoriteRename = favoriteRename; self.documentSource = documents; self.typedCommands = typedCommands; self.parent = parent; self.profilePath = profilePath
        if let editor = parent.firstResponder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSTextField {
            originalResponder = field; originalSelection = editor.selectedRange()
        } else { originalResponder = parent.firstResponder }
        let panel = CommandPanel(contentRect: NSRect(x: 0, y: 0, width: 765, height: 330),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.appearance = contentAppearance ?? parent.appearance
        panel.level = .normal; panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true; panel.animationBehavior = .none
        super.init(window: panel)
        panel.onBackgroundReturn = { [weak self] event in self?.handleBackgroundReturn(event) ?? false }
        panel.onDeleteSuggestion = { [weak self] event in self?.handleDeleteSuggestionKey(event) ?? false }
        panel.commandField = input
        panel.commandFieldEditor.onCopy = { [weak self] text in
            guard let self, !self.dismissed, self.isOwnerValid?() != false else { return }
            self.onCopyText?(text)
        }
        panel.contentView = container
        panel.setAccessibilityLabel("Command Bar")
        inputIcon.imageScaling = .scaleProportionallyDown
        container.addSubview(inputIcon)
        input.isBordered = false; input.drawsBackground = false
        input.font = CommandBarTypography.field
        input.placeholderString = "Search or Enter URL…"
        // CommandBarTextField is single-line unless isMultiline: a long URL
        // scrolls in place rather than wrapping under the field.
        input.usesSingleLineMode = true; input.cell?.wraps = false
        input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
        input.focusRingType = .none; input.delegate = self
        input.setAccessibilityLabel("Search or Enter URL")
        input.setAccessibilityHelp("Use Up and Down to choose a result, wrapping at either end while searching, Tab on empty input to search Actions, or Tab to accept its completion or enter its offered search scope, Return to open, Option-Return to open an eligible result in a split pane, Command-Option-Return to open a web result in a background tab and keep searching, Command-Option-Delete to remove a removable suggestion, or Escape to return to the page.")
        input.stringValue = initialEdit?.0 ?? initialInput
        previousInput = input.stringValue
        container.addSubview(input)
        scopePill.font = CommandBarTypography.label
        scopePill.contentTintColor = .white; scopePill.alignment = .center
        scopePill.cell?.lineBreakMode = .byTruncatingTail
        scopePill.onOpen = { [weak self] in self?.showScopeMenu() }
        scopePill.setAccessibilityLabel("Search scope")
        scopePill.isHidden = true; container.addSubview(scopePill)
        actionsPill.isHidden = true; container.addSubview(actionsPill)
        scopeOfferButton.target = self; scopeOfferButton.action = #selector(enterOfferedScope)
        scopeOfferButton.isHidden = true; container.addSubview(scopeOfferButton)
        container.addSubview(divider)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
        // SuggestionsView's ordinary NSTableView: rows span the clip, with no
        //
        table.style = .plain
        table.headerView = nil; table.rowHeight = 50; table.intercellSpacing = .zero
        //
        table.backgroundColor = .clear; table.selectionHighlightStyle = .none
        table.dataSource = self; table.delegate = self
        table.focusRingType = .none; table.allowsEmptySelection = false
        table.setAccessibilityLabel("Suggestions")
        table.onKey = { [weak self] event in self?.handleTableKey(event) ?? false }
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false; scroll.horizontalScrollElasticity = .none
        scroll.documentView = table; container.addSubview(scroll)
        emptyLabel.textColor = .secondaryLabelColor; emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.alignment = .center; container.addSubview(emptyLabel)
        privacyBanner.isHidden = true; container.addSubview(privacyBanner)
        privacyInfoButton.isHidden = true; container.addSubview(privacyInfoButton)
        privacyInfoButton.target = self; privacyInfoButton.action = #selector(showPrivacyBanner)
        privacyBanner.onDismiss = { [weak self] in
            guard let self, !self.dismissed else { return }
            self.privacyBannerVisible = false
            self.privacyPolicy.dismiss(); self.position(); self.layoutContents()
        }
        privacyBanner.onSearchSettings = { [weak self] in
            guard let self, !self.dismissed else { return }
            // Focus returns to the page first, so a Settings window that can't
            // open leaves it where Escape would.
            let action = self.onSearchSettings, valid = self.isOwnerValid
            self.dismiss()
            if valid?() != false { action?() }
        }
        container.onLayout = { [weak self] in self?.layoutContents() }
        container.onAppearanceChange = { [weak self] in self?.applyPalette() }
        applyPalette()
        adoptCommands(KeyboardShortcuts.shared.menuCommands(in: parent))
        bindings = KeyboardShortcuts.shared.$revision.dropFirst().sink { [weak self] _ in
            // Published emits before assignment; snapshot the committed registry
            // revision on the next main turn, not the previous revision.
            DispatchQueue.main.async { [weak self] in
                guard let self, let parent = self.parent, !self.dismissed else { return }
                self.adoptCommands(KeyboardShortcuts.shared.menuCommands(in: parent))
                self.refreshResults(requestNative: false)
            }
        }
        let session = PCNativeOmnibox(profilePath: profilePath, page: page, window: nativeWindow)
        omnibox = session
        session.snapshotChanged = { [weak self, weak session] snapshot in
            guard let self, !self.dismissed, snapshot.revision >= self.snapshotRevision else { return }
            guard self.isOwnerValid?() != false else { self.dismiss(restoreFocus: false); return }
            // Local Actions never adopts an autocomplete result, error or website
            // scope published by an earlier query. Exit starts a fresh request.
            if self.actionsScope { self.snapshotRevision = snapshot.revision; return }
            guard self.nativeHold.accept(input: snapshot.input, isError: snapshot.error != nil) else {
                self.snapshotRevision = snapshot.revision; return
            }
            self.endNativeHold()
            let previousScopeName = self.scopedName
            let lostScope = self.isWebsiteScoped && snapshot.activeScope == nil
            self.snapshotRevision = snapshot.revision
            if let menu = self.scopeMenuLease, session?.canUseScopeMenu(menu) != true {
                self.retireScopeMenu()
            }
            self.activeScope = snapshot.activeScope; self.enteringScopeName = nil
            self.scopeOffers = snapshot.scopeOffers
            self.siteScopes = snapshot.responds(to: #selector(getter: PCNativeOmniboxSnapshot.siteScopes)) ? snapshot.siteScopes : []
            let invalidationMessage = self.scopeInvalidated ? self.nativeError : nil
            self.nativeResults = snapshot.results; self.nativeInput = snapshot.input
            self.extensionActions = snapshot.extensionActions
            self.nativeError = snapshot.error?.localizedDescription ?? invalidationMessage
            if lostScope {
                // A removed/changed engine must not silently turn a scoped
                // Return into a request through the default search provider.
                self.scopeInvalidated = true; self.nativeResults = []; self.extensionActions = []
                self.nativeHold.reset()
                self.applyPalette()
                self.unavailableScopeName = previousScopeName
                self.nativeError = self.nativeError ?? "This search scope is no longer available. Edit your search to continue."
                self.announceScope("\(previousScopeName) is no longer available. Edit your search or press Escape.")
            }
            self.refreshResults(requestNative: false)
        }
        refreshResults()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        guard let parent, let window, !dismissed, isOwnerValid?() != false else { dismiss(restoreFocus: false); return }
        presented = true
        refreshResults(requestNative: false)
        position()
        parent.addChildWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        syncShadow()
        window.makeFirstResponder(input); applySelectionColor(); input.selectText(nil)
        if let selection = initialEditSelection, let editor = input.currentEditor() as? NSTextView {
            let count = (input.stringValue as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, count), length: min(selection.length, max(0, count - selection.location))))
            initialEditSelection = nil
        }
        if let editor = input.currentEditor() as? NSTextView {
            if let storage = editor.textStorage {
                observe(NSTextStorage.didProcessEditingNotification, object: storage) { owner in
                    guard !owner.applyingCompletion,
                          let storage = (owner.input.currentEditor() as? NSTextView)?.textStorage,
                          storage.editedMask.contains(.editedCharacters) else { return }
                    // Observe the actual replacement, including Cut/AX/native
                    // bindings. Replacing a selected address with shorter text
                    // is an insertion, not a reason to suppress completion.
                    owner.deletingCharacters = CommandBarEditState.deletesCharacters(
                        editedRange: storage.editedRange, changeInLength: storage.changeInLength)
                }
            }
            observe(NSTextView.didChangeSelectionNotification, object: editor) { owner in
                guard !owner.applyingCompletion, let projection = owner.editState.projection else { return }
                // Native caret/mouse selection belongs to the user. Preserve
                // its original intent while async provider results arrive.
                owner.editState.stopAutomaticCompletion()
                owner.explicitSelectionID = projection.resultID
            }
        }
        observe(NSWindow.didResignKeyNotification, object: window) { owner in
            if let alert = owner.scopeAlert, owner.window?.attachedSheet === alert.window { return }
            owner.dismiss(restoreFocus: false)
        }
        observe(NSWindow.willCloseNotification, object: parent) { $0.dismiss(restoreFocus: false) }
        observe(NSWindow.willMiniaturizeNotification, object: parent) { $0.dismiss(restoreFocus: false) }
        observe(NSWindow.willBeginSheetNotification, object: parent) { $0.dismiss(restoreFocus: false) }
        observe(Notification.Name("PCNativeWindowSecurityStateChanged"), object: parent) { $0.dismiss(restoreFocus: false) }
        observe(NSApplication.didResignActiveNotification, object: NSApp) { $0.dismiss(restoreFocus: false) }
        observe(NSWindow.didResizeNotification, object: parent) { $0.position() }
        observe(NSWindow.didMoveNotification, object: parent) { $0.position() }
    }
    private func observe(_ name: Notification.Name, object: AnyObject, action: @escaping @MainActor @Sendable (CommandBar) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        })
    }
    private func position() {
        guard let parent, window != nil else { return }
        let available = parent.screen?.visibleFrame ?? parent.frame
        if let anchor = sidebarAnchor, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor {
            let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let width = min(sidebarBrowsing ? max(180, anchor.superview?.bounds.width ?? anchorRect.width) - 18 : 350, available.width - 24)
            let height = sidebarBrowsing ? anchorRect.height : min(isScoped || scopeInvalidated ? compactScopeHeight : 309, available.height - 32)
            let x = min(max(anchorRect.minX, available.minX + 8), available.maxX - width - 8)
            let y = min(max(anchorRect.maxY - height, available.minY + 8), available.maxY - height - 8)
            // The inline sidebar bar has no material, border or shadow
            //
            showsShadow = !sidebarBrowsing
            container.sidebarBrowsing = sidebarBrowsing
            container.cornerRadius = sidebarBrowsing ? 7 : 12
            setSurfaceFrame(NSRect(x: x, y: y, width: width, height: height))
            input.placeholderString = sidebarBrowsing || isScoped ? "Search…" : "Search or Enter URL…"
            input.font = CommandBarTypography.label
            return
        }
        let width = max(260, min(765, parent.frame.width - 48, available.width - 24))
        // A 64-point header, the 4-point list inset, five 50-point rows and 8 below.
        let baselineHeight = min(326, max(180, available.height - 32))
        //
        // SuggestionsView does, without moving the input's top edge.
        let bannerHeight = showsPrivacyBanner ? privacyBanner.preferredHeight(forWidth: width) : 0
        let height = min((isScoped || scopeInvalidated ? compactScopeHeight : baselineHeight) + bannerHeight, available.height - 32)
        let x = min(max(parent.frame.midX - width / 2, available.minX + 12), available.maxX - width - 12)
        // Scoped results grow below the original input edge, as observed in
        // the installed reference, without moving the field under the user.
        let y = min(max(parent.frame.midY + baselineHeight / 2 - height, available.minY + 16), available.maxY - height - 16)
        setSurfaceFrame(NSRect(x: x, y: y, width: width, height: height))
    }
    private func setSurfaceFrame(_ surface: NSRect) {
        window?.setFrame(surface, display: true)
        syncShadow()
    }
    /// The shadow window follows the panel while the bar is shown; the inline
    /// sidebar bar has none.
    private func syncShadow() {
        guard let parent, let window, presented, !dismissed, showsShadow, window.isVisible else {
            if shadowWindow.parent != nil { shadowWindow.parent?.removeChildWindow(shadowWindow) }
            shadowWindow.orderOut(nil)
            removeSplash()
            return
        }
        shadowWindow.track(bar: window.frame, cornerRadius: container.cornerRadius)
        splashWindow?.track(bar: window.frame)
        guard shadowWindow.parent == nil || !shadowWindow.isVisible else { return }
        if shadowWindow.parent == nil { parent.addChildWindow(shadowWindow, ordered: .above) }
        shadowWindow.order(.below, relativeTo: window.windowNumber)
    }
    ///
    ///
    var contentAppearance: NSAppearance? {
        didSet { window?.appearance = contentAppearance ?? parent?.appearance }
    }
    /// CustomSelectionColorTextField puts its colour on the current editor when
    ///
    private func applySelectionColor() {
        let attributes: [NSAttributedString.Key: Any] = [.backgroundColor: palette.inputSelection]
        (window as? CommandPanel)?.commandFieldEditor.selectedTextAttributes = attributes
        (input.currentEditor() as? NSTextView)?.selectedTextAttributes = attributes
    }
    private func applyPalette() {
        input.textColor = palette.inputText
        inputIcon.contentTintColor = palette.inputIcon
        applySelectionColor()
        emptyLabel.textColor = CommandBarPalette.textSecondary
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            actionsPill.layer?.backgroundColor = palette.scopePill.cgColor
        }
        scopePill.focusColor = scopeColor ?? palette.scopePill
        for row in 0..<table.numberOfRows {
            (table.rowView(atRow: row, makeIfNecessary: false) as? CommandResultRowView)?.selectedColor = selectedRowColor
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandResultCell)?.selectedColor = selectedRowColor
        }
        updateScopeSplash()
    }
    ///
    ///
    /// splashes behind the bar and the bar bounces; when the scope loses it,
    /// the splash goes and the bar bounces again. The inline sidebar bar does
    /// neither.
    private func updateScopeSplash() {
        let shows = isWebsiteScoped && scopeColor != nil
        guard shows != showsScopeSplash else { return }
        showsScopeSplash = shows
        removeSplash()
        guard presented, !dismissed, sidebarAnchor == nil, let parent, let window, window.isVisible else { return }
        if shows, let color = scopeColor {
            let splash = CommandBarSplashWindow(color: color, cornerRadius: container.cornerRadius)
            splash.track(bar: window.frame)
            parent.addChildWindow(splash, ordered: .above)
            splash.order(.below, relativeTo: (shadowWindow.isVisible ? shadowWindow : window).windowNumber)
            splashWindow = splash
            // Faded out by then; the window goes rather than waiting for the scope to end.
            DispatchQueue.main.asyncAfter(deadline: .now() + CommandBarSplashView.duration + 0.1) { [weak self, weak splash] in
                MainActor.assumeIsolated {
                    guard let self, let splash, self.splashWindow === splash else { return }
                    self.removeSplash()
                }
            }
        }
        // Bounce at the size this change lays out: entry shrinks the bar to its
        // empty scoped surface.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presented, !self.dismissed, self.window?.isVisible == true else { return }
                CommandBarBounce.play(on: self.container.layer)
                //
                if self.shadowWindow.isVisible {
                    CommandBarBounce.play(on: self.shadowWindow.shadowView.shadowLayer,
                                          about: self.shadowWindow.shadowView.barCentreOffset)
                }
            }
        }
    }
    private func removeSplash() {
        guard let splash = splashWindow else { return }
        splashWindow = nil
        splash.parent?.removeChildWindow(splash); splash.orderOut(nil)
    }
    private var layingOutContents = false
    private func layoutContents() {
        guard !layingOutContents else { return }
        layingOutContents = true
        defer { layoutScopeHeader(); layingOutContents = false }
        let width = container.bounds.width
        if sidebarAnchor != nil {
            inputIcon.frame = NSRect(x: 15, y: sidebarBrowsing ? 10 : 17, width: 14, height: 14)
            input.frame = NSRect(x: 38, y: sidebarBrowsing ? 7 : 13, width: max(0, width - 49), height: 22)
            divider.isHidden = true
            scroll.isHidden = sidebarBrowsing; emptyLabel.isHidden = sidebarBrowsing || !results.isEmpty
            scroll.frame = NSRect(x: 9, y: 50, width: max(0, width - 18), height: max(0, container.bounds.height - 59))
            emptyLabel.frame = NSRect(x: 16, y: 77, width: max(0, width - 32), height: 40)
            return
        }
        inputIcon.frame = NSRect(x: 22, y: 22, width: 18, height: 18)
        input.frame = NSRect(x: 49, y: 21, width: max(0, width - 71), height: 31)
        divider.frame = NSRect(x: 12, y: 64, width: max(0, width - 24), height: CommandBarHairline.height(in: window))
        let bannerHeight = showsPrivacyBanner ? privacyBanner.preferredHeight(forWidth: width) : 0
        privacyBanner.isHidden = bannerHeight == 0
        privacyBanner.frame = NSRect(x: 0, y: container.bounds.height - bannerHeight, width: width, height: bannerHeight)
        scroll.frame = NSRect(x: 8, y: 68, width: max(0, width - 16), height: max(0, container.bounds.height - 76 - bannerHeight))
        emptyLabel.frame = NSRect(x: 24, y: 111, width: max(0, width - 48), height: 40)
    }
    func reconcile(tabs: [BrowserTab], history: [BrowserHistoryEntry], historyRevision: UInt64, historyExcludedURL: String?, spaces: [CommandBarSpaceAction], folders: [CommandBarFolderAction]) {
        guard !dismissed else { return }
        guard isOwnerValid?() != false else { dismiss(restoreFocus: false); return }
        // historyRevision + excluded URL identify the filtered visit input; skip
        // full-array equality and newestFirst when that input has not changed.
        let historyInputChanged = historyRevision != self.historyRevision
            || historyExcludedURL != self.historyExcludedURL
        guard tabs != self.tabs || historyInputChanged || spaces != self.spaces || folders != self.folders else { return }
        if historyInputChanged {
            rankedHistory = BrowserHistoryOrder.newestFirst(history)
            self.history = history
            self.historyRevision = historyRevision
            self.historyExcludedURL = historyExcludedURL
            lastHistoryScanKey = nil
            cachedHistoryVisits = []
        }
        self.tabs = tabs; self.spaces = spaces; self.folders = folders
        refreshResults(requestNative: false)
    }
    func reconcileExtensionActions() {
        guard !dismissed else { return }
        guard isOwnerValid?() != false else { dismiss(restoreFocus: false); return }
        extensionLaunchSnapshotIsStale = true
        refreshResults(requestNative: false)
    }
    func dismiss(restoreFocus: Bool = true) {
        guard !dismissed else { return }
        let mayRestore = restoreFocus && presented && NSApp.isActive && window?.isKeyWindow == true && isOwnerValid?() != false
        dismissed = true
        endNativeHold()
        retireScopeMenu()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); bindings = nil
        omnibox?.cancel(); omnibox = nil; nativeResults = []; extensionActions = []
        extensionLaunchSnapshot = []
        scopeOffers = []; activeScope = nil; enteringScopeName = nil; actionsScope = false
        parent?.removeChildWindow(shadowWindow); shadowWindow.orderOut(nil)
        removeSplash()
        if let window { parent?.removeChildWindow(window); window.orderOut(nil) }
        if mayRestore, let parent, parent.isVisible, !parent.isMiniaturized, parent.attachedSheet == nil {
            parent.makeKey()
            if let view = originalResponder as? NSView, mayRestoreOriginal?(view) ?? true,
               SavedFocus.mayReturn(to: view, in: parent), parent.makeFirstResponder(view) {
                if let field = view as? NSTextField, let editor = field.currentEditor() as? NSTextView,
                   let range = originalSelection, NSMaxRange(range) <= (editor.string as NSString).length { editor.setSelectedRange(range) }
            } else { restorePageFocus?() }
        }
        onDismiss?()
        if submissionDepth == 0 { onDismissalSettled?() }
    }
    func controlTextDidChange(_ obj: Notification) {
        retireScopeMenu()
        backgroundGeneration &+= 1
        retainedBackgroundHistory = nil
        let edited = input.stringValue
        let before = editState.projection?.automatic == true ? editState.query : previousInput
        let editor = input.currentEditor() as? NSTextView
        editState.userEdit(edited, selection: editor?.selectedRange() ?? NSRange(location: NSNotFound, length: 0),
                           hasMarkedText: editor?.hasMarkedText() != false,
                           didBackspace: deletingCharacters)
        deletingCharacters = false
        previousInput = edited
        //
        // actual profile preference and selected native offer own eligibility;
        // composition and arbitrary whitespace/paste transformations stay editing.
        if (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           !before.isEmpty, edited == before + " ",
           selectedScopeOffer?.spaceTriggerEnabled == true,
           enterScope(restoring: before) { return }
        // Explicit editing after an invalidation begins a new ordinary query;
        // merely receiving a native failure never does that on the user's behalf.
        scopeInvalidated = false; unavailableScopeName = nil
        explicitSelectionID = nil
        refreshResults(holdsPresentation: true)
    }
    private func endNativeHold() {
        nativeHold.end()
        nativeHoldDeadline?.cancel(); nativeHoldDeadline = nil
    }
    /// An edit keeps a native error until the next publication replaces it:
    /// a session that failed for good publishes nothing more.
    private func clearNativeResults(keepingError: Bool = false) {
        nativeResults = []; extensionActions = []; scopeOffers = []
        if !keepingError { nativeError = nil }
        nativeHold.reset()
    }
    ///
    /// 2,000 ms source timeout, or before Return/Tab act on the first row.
    private func releaseNativeHold() {
        guard nativeHold.isHolding else { return }
        endNativeHold(); clearNativeResults(keepingError: true)
        refreshResults(requestNative: false)
    }
    private func refreshResults(requestNative: Bool = true, holdsPresentation: Bool = false) {
        guard !dismissed else { return }
        // Snapshot rasterizes each extension's icons, so it is taken again
        // only after the engine reports a change (`reconcileExtensionActions`),
        // not on every keystroke and suggestion update; never per row.
        if extensionLaunchSnapshotIsStale {
            extensionLaunchSnapshot = extensionLaunchActions?() ?? []
            extensionLaunchSnapshotIsStale = false
        }
        let query = isScoped ? editState.query : editState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if sidebarAnchor != nil {
            onSidebarQueryState?(sidebarBrowsing)
            position()
            if sidebarBrowsing {
                let browsing = CommandBarOpenResultsSkip.sidebarBrowsingToken
                if CommandBarOpenResultsSkip.shouldSkip(previous: lastOpenResultsFingerprint, next: browsing) {
                    return
                }
                lastOpenResultsFingerprint = browsing
                endNativeHold(); nativeHold.reset()
                results = []; nativeResults = []; extensionActions = []; nativeError = nil
                table.reloadData(); presentedRows = []
                table.deselectAll(nil); updateInputIcon(); layoutContents()
                return
            }
        }
        if requestNative && !actionsScope {
            switch holdsPresentation ? nativeHold.edit(query, canHold: presented && omnibox != nil, scoped: isScoped) : .present {
            case .answered:
                endNativeHold()
            case .hold:
                if nativeHoldDeadline == nil {
                    let deadline = DispatchWorkItem { [weak self] in
                        MainActor.assumeIsolated { self?.releaseNativeHold() }
                    }
                    nativeHoldDeadline = deadline
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(2000), execute: deadline)
                }
            case .present:
                endNativeHold(); clearNativeResults(keepingError: holdsPresentation)
            }
            // Trimming changes the native query boundary, so it cannot own an
            // inline suffix for the untrimmed field. Scope retains its own owner.
            omnibox?.updateInput(query, allowsInlineCompletion: !isScoped && query == editState.query && editState.allowsInlineCompletion)
        }
        if nativeHold.isHolding { return }
        // True no-op: same open-bar query and result-identity fingerprint as the
        // last presentation. Skip Result rebuild, tab/history filtering into
        // rows, reloadData, and layoutContents. Membership tokens are still
        // hashed above; they are not the filtered result rows.
        let fingerprint = openResultsFingerprint(query: query)
        if CommandBarOpenResultsSkip.shouldSkip(previous: lastOpenResultsFingerprint, next: fingerprint) {
            return
        }
        lastOpenResultsFingerprint = fingerprint
        // A retained row must never activate a newer publication that happens
        // to reuse its label/URL/id. It captures this presentation and payload.
        resultPublication = UUID()
        // A selected contextual command that disappears cannot silently become a
        // web search when a model/native publication arrives under Return.
        let selectedContext = explicitSelectionID.flatMap { id in
            results.first { $0.id == id && ($0.spaceAction != nil || $0.folderAction != nil || $0.favoriteAction != nil || $0.folderMove != nil || $0.favoriteRename != nil || $0.typedCommand != nil || $0.extensionAction != nil || $0.extensionLaunch != nil) }
        }
        results = []
        if actionsScope {
            //
            // These remain original menu/typed commands, never navigation text.
            results = Array(commandResults(query: query, includesEmpty: true).prefix(100))
        } else if isWebsiteScoped {
            // There is no string/URL fallback in scope. Only an actual native
            // keyword-mode match can be activated (including Option-Return).
            results = nativeResultRows(scoped: true)
        } else if !scopeInvalidated {
            if !query.isEmpty {
                results = rankedResults(query: query)
            } else {
                results += tabs.filter { $0.archivedAt == nil }.prefix(8).map(tabResult)
            }
            if query.isEmpty {
                // This uses the profile's Chromium history (`recentPages`), else
                // Parc's own visit records. Recency is a
                //
                // Ranked recents match sorted-by-date descending; the top-8 slice is
                // reused while query + historyRevision + excluded URL + tab URLs match.
                let tabURLs = tabs.map(\.url)
                let scanKey = CommandBarHistoryScanSkip.key(
                    query: query,
                    historyRevision: historyRevision,
                    excludedURL: historyExcludedURL,
                    tabURLs: tabURLs
                )
                let visits: [CommandBarHistoryScanSkip.Visit]
                if CommandBarHistoryScanSkip.shouldReuse(previous: lastHistoryScanKey, next: scanKey) {
                    visits = cachedHistoryVisits
                } else {
                    // Cache a max-8 history slice; the combined empty-query
                    // tab+history budget below may take only a prefix.
                    // Chromium's pages include the current one; Parc's list
                    // already leaves it out.
                    visits = CommandBarHistoryScanSkip.emptyQueryVisits(
                        rankedURLsAndTitles: recentPages ?? rankedHistory.map { ($0.url, $0.title) },
                        tabURLs: Set(tabURLs + [historyExcludedURL].compactMap { $0 }),
                        limit: 8
                    )
                    lastHistoryScanKey = scanKey
                    cachedHistoryVisits = visits
                }
                // Pre-cache contract: tabs already occupy part of the 8-row
                // empty-query budget; only fill the remainder from history.
                let historyBudget = max(0, 8 - results.count)
                for visit in visits.prefix(historyBudget) {
                    guard let url = URL(string: visit.url) else { continue }
                    results.append(Result(id: "history:" + visit.url,
                                          title: CommandBarResultText.historyTitle(pageTitle: visit.title, url: visit.url),
                                          detail: "", symbol: "clock",
                                          subtitle: CommandBarResultText.urlSubtitle(visit.url), url: url, input: visit.url))
                }
            }
        }
        // The newly opened tab must not remove the still-selected empty-query
        // history intent through the usual open-URL deduplication. Retain that
        // original input only until the user edits or chooses another result.
        if !isScoped, !scopeInvalidated, editState.query.isEmpty,
           let retained = retainedBackgroundHistory,
           !results.contains(where: { $0.id == retained.result.id }) {
            results.insert(retained.result, at: min(retained.row, results.count))
        }
        if !isWebsiteScoped, !scopeInvalidated, var expired = selectedContext,
           !results.contains(where: { $0.id == expired.id }) {
            expired.isExpired = true
            results.insert(expired, at: 0)
        }
        emptyLabel.stringValue = actionsScope ? "No matching actions" : nativeError ?? (isScoped ? "Search \(scopedName)…" : "Search or Enter URL…")
        if isScoped || scopeInvalidated { position() }
        let previousIDs = presentedRows.map(\.id)
        let rows = results.map { CommandBarRowDiff.Row(id: $0.id, content: rowContent($0)) }
        let diff = CommandBarRowDiff(old: presentedRows, new: rows)
        presentedRows = rows
        selectingProgrammatically = true; table.apply(diff); selectingProgrammatically = false
        // Rows kept by the diff now present this publication's payload.
        for row in results.indices {
            if let view = table.rowView(atRow: row, makeIfNecessary: false) as? CommandResultRowView { bind(view, to: results[row]) }
            if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandResultCell { bind(cell, to: results[row]) }
        }
        emptyLabel.isHidden = !results.isEmpty
        if rows.count != previousIDs.count { layoutContents() }
        var row = 0
        if let id = explicitSelectionID, !(results.first?.isExpired == true && results.first?.id == id) {
            if let previous = previousIDs.firstIndex(of: id),
               CommandBarRowDiff.keepsSelection(at: previous, old: previousIDs, new: rows.map(\.id)) {
                row = previous
            } else {
                explicitSelectionID = nil
            }
        }
        if results.indices.contains(row) {
            let retainsProjection = editState.projection?.resultID == results[row].id
            let automatic = editState.projection?.automatic == true
            if retainsProjection && automatic {
                // No selection/field write for an unchanged accepted publication:
                // preserve native caret movement and the provider-owned suffix.
                selectingProgrammatically = true
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                selectingProgrammatically = false
                table.scrollRowToVisible(row); updateSelectionAppearance()
            } else {
                select(row: row, explicit: false, projectCompletion: retainsProjection, preserveEditorSelection: true)
            }
            projectDefaultCompletion()
        } else {
            selectingProgrammatically = true; table.deselectAll(nil); selectingProgrammatically = false
            clearCompletion(); updateSelectionAppearance()
        }
        for result in results where result.navigation?.search != true {
            guard let url = result.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""), requestedIcons.insert(url).inserted else { continue }
            PCNativeBrowserApplication.favicon(for: url, profilePath: profilePath) { [weak self] image in
                MainActor.assumeIsolated {
                    guard let self, !self.dismissed, self.isOwnerValid?() != false, let image else { return }
                    self.icons[url] = image
                    for row in self.results.indices where self.results[row].url == url {
                        (self.table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandResultCell)?.setIcon(image)
                    }
                    self.updateInputIcon()
                }
            }
        }
    }
    /// Query plus every input that feeds open-bar result identity. Everyday
    /// title/`lastAccessed` chrome noise is outside tab tokens; membership and
    /// selection changes alter the fingerprint and still rebuild.
    private func openResultsFingerprint(query: String) -> String {
        CommandBarOpenResultsSkip.fingerprint(
            query: query,
            actionsScope: actionsScope,
            websiteScoped: isWebsiteScoped,
            scopeInvalidated: scopeInvalidated,
            scopeName: unavailableScopeName ?? scopedName,
            selectionID: explicitSelectionID,
            nativeError: nativeError,
            nativeRevision: snapshotRevision,
            nativeResultIDs: nativeResults.map {
                "native:\($0.search):\($0.url.absoluteString):\($0.title)"
            },
            extensionActionIDs: extensionActions.map {
                // resultIndex owns insertion order among natives; omit it and a
                // reorder can skip with a stale table.
                "extension:\($0.extensionID):\($0.editText):\($0.title):\($0.resultIndex)"
            },
            extensionLaunchIDs: extensionLaunchSnapshot.map {
                "extension-launch:\($0.identifier):\($0.generation)"
            },
            tabTokens: tabs.map {
                CommandBarOpenResultsSkip.tabToken(id: $0.id, title: $0.title, url: $0.url,
                                                   archived: $0.archivedAt != nil, customTitle: $0.customTitle,
                                                   caption: caption(for: $0).text)
            },
            // Revision + excluded URL replace a full visit-token map so idle
            // open-bar ticks do not walk history just to decide skip vs rebuild.
            // Typed queries rank top domains counted from that history.
            historyTokens: [CommandBarHistoryScanSkip.historyMembershipToken(revision: historyRevision,
                                                                             excludedURL: historyExcludedURL)]
                + (query.isEmpty ? ["recent-pages:\(recentPagesGeneration)"] : ["top-domains:\(topDomainGeneration)"]),
            commandTokens: commands.map {
                CommandBarOpenResultsSkip.commandToken(id: $0.id, title: $0.title, group: $0.group)
            } + typedCommands.filter { canPerformTypedCommand?($0) == true }.map {
                CommandBarOpenResultsSkip.commandToken(id: $0.id, title: $0.title, group: "")
            },
            spaceTokens: spaces.map {
                CommandBarOpenResultsSkip.spaceToken(id: $0.id, name: $0.name,
                                                     profileName: $0.profileName,
                                                     needsProfileLabel: $0.needsProfileLabel)
            },
            folderTokens: folders.map {
                CommandBarOpenResultsSkip.folderToken(id: $0.id, name: $0.name, detail: $0.detail)
            },
            folderMoveIDs: folderMoves.filter { canMoveToFolder?($0) == true }.map(\.id),
            favoriteActionID: favoriteAction?.id,
            favoriteEligible: favoriteAction.map { canPerformFavorite?($0) == true } ?? false,
            favoriteRenameID: favoriteRename?.id,
            renameEligible: favoriteRename.map { canRenameFavorite?($0) == true } ?? false,
            retainedBackgroundID: retainedBackgroundHistory?.result.id,
            retainedBackgroundRow: retainedBackgroundHistory?.row,
            supportsMuteAllTabs: onMuteAllTabs != nil
        )
    }
    private func commandResults(query: String, includesEmpty: Bool) -> [Result] {
        // This actual app-owned command is not a registered menu action.
        // Ordinary search inserts it separately to retain its existing order.
        let passwords: [Result] = includesEmpty && (query.isEmpty || CommandBarScopeKeyboard.matchesPasswords(query: query))
            ? [Result(id: "passwords", title: "Manage Passwords", detail: "", symbol: "key", managesPasswords: true)] : []
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let lowercasedQuery = query.lowercased()
        let matching = zip(commands, commandSearch).compactMap { command, search -> (command: KeyboardShortcuts.MenuCommand, title: String)? in
            // The Type Travel dialog is distinct from the menu's inline
            // editing-ID command; do not show a second disabled alias.
            if favoriteRename != nil && command.id == "renameCurrentItem:" { return nil }
            //
            return words.allSatisfy({ search.text.contains($0) }) ? (command, search.title) : nil
        }.sorted { lhs, rhs in
            let left = lhs.title.lowercased().hasPrefix(lowercasedQuery)
            let right = rhs.title.lowercased().hasPrefix(lowercasedQuery)
            return left != right ? left : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        let contextual = (query.isEmpty && includesEmpty ? spaces : CommandBarSpaceAction.matching(spaces, query: query)).map {
            Result(id: $0.id, title: $0.title, detail: $0.detail,
                   symbol: "arrow.right.square.fill", spaceAction: $0)
        }
        let folderCommands = (query.isEmpty && includesEmpty ? folders : CommandBarFolderAction.matching(folders, query: query)).map {
            Result(id: $0.id, title: $0.title, detail: $0.detail,
                   symbol: "folder", folderAction: $0)
        }
        let favorites: [Result] = favoriteAction.flatMap { action in
            guard (query.isEmpty && includesEmpty) || action.matches(query: query), canPerformFavorite?(action) == true else { return nil }
            return Result(id: action.id, title: action.title, detail: "", symbol: "star.fill", favoriteAction: action)
        }.map { [$0] } ?? []
        let moves = (query.isEmpty && includesEmpty ? folderMoves : CommandBarFolderMove.matching(folderMoves, query: query)).filter {
            canMoveToFolder?($0) == true
        }.map { action in
            Result(id: action.id, title: action.title, detail: action.folder.detail,
                   symbol: "folder", folderMove: action)
        }
        let rename: [Result] = favoriteRename.flatMap { action in
            guard (query.isEmpty && includesEmpty) || action.matches(query: query), canRenameFavorite?(action) == true else { return nil }
            return Result(id: action.id, title: action.title, detail: "", symbol: "character.cursor.ibeam", favoriteRename: action)
        }.map { [$0] } ?? []
        let typed = typedCommands.filter {
            ((query.isEmpty && includesEmpty) || $0.matches(query: query)) && canPerformTypedCommand?($0) == true
        }.map { Result(id: $0.id, title: $0.title, detail: $0.detail, symbol: $0.symbol, typedCommand: $0) }
        let extensions = extensionLaunchSnapshot.filter {
            let name = $0.name.lowercased()
            return ((query.isEmpty && includesEmpty) || words.allSatisfy { name.contains($0) })
        }.sorted { $0.modelIndex < $1.modelIndex }.map {
            // The generation belongs to the exact document/model snapshot.
            // Replacing an extension must not reuse a selected result identity.
            Result(id: "extension-launch:\($0.identifier):\($0.generation)",
                   title: $0.name, detail: "Extension", symbol: "puzzlepiece.extension",
                   extensionLaunch: $0)
        }
        let audioCommands: [Result] = onMuteAllTabs == nil ? [] : [true, false].compactMap { muted in
            let title = muted ? "Mute All Tabs" : "Unmute All Tabs"
            guard (query.isEmpty && includesEmpty) || (!query.isEmpty && words.allSatisfy({ title.lowercased().contains($0) })) else { return nil }
            //
            return Result(id: muted ? "mute-all-tabs" : "unmute-all-tabs", title: title,
                          detail: "", symbol: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", muteAllTabs: muted)
        }
        let matchedCommands = contextual + folderCommands + favorites + moves + rename + typed + extensions + audioCommands + matching.map {
            Result(id: "command:" + $0.command.id, title: $0.title, detail: "",
                   symbol: CommandBarCommandPresentation.symbol(commandID: $0.command.id, title: $0.command.title, group: $0.command.group),
                   command: $0.command)
        }
        return passwords + matchedCommands
    }
    private func tabResult(_ tab: BrowserTab) -> Result {
        Result(id: "tab:" + tab.id.uuidString,
               title: CommandBarResultText.tabTitle(customTitle: tab.customTitle, pageTitle: tab.title, url: tab.url),
               detail: "", symbol: InternalPage.sidebarFallbackSymbol(urlString: tab.url), caption: caption(for: tab),
               url: URL(string: tab.url), tabID: tab.id)
    }
    ///
    private func rankedResults(query: String) -> [Result] {
        var pool: [Result] = []
        var candidates: [CommandBarRanking.Candidate] = []
        func add(_ result: Result, _ candidate: CommandBarRanking.Candidate) {
            pool.append(result); candidates.append(candidate)
        }
        if CommandBarScopeKeyboard.matchesPasswords(query: query) {
            add(Result(id: "passwords", title: "Manage Passwords", detail: "", symbol: "key", managesPasswords: true),
                .init(archetype: .typeTravel, key: "typeTravel:passwords", texts: ["Manage Passwords", "Passwords"]))
        }
        for result in commandResults(query: query, includesEmpty: false) {
            var texts = [result.title]
            if let space = result.spaceAction { texts += [space.name, result.title + " " + space.name] }
            if let folder = result.folderAction ?? result.folderMove?.folder { texts += [folder.name, result.title + " " + folder.name] }
            add(result, CommandBarRanking.commandCandidate(key: "typeTravel:" + result.id, texts: texts,
                menuCommandID: result.command?.id, menuText: result.command.map { $0.title + " " + $0.group },
                typed: result.typedCommand))
        }
        // The leading native request survives presentation filtering. A literal
        // input fallback is needed only before a native answer or after failure.
        let nativeRows = nativeResultRows(scoped: false)
        if nativeRows.isEmpty || explicitSelectionID == "query:" + query {
            // An explicitly selected input row remains the same intent when
            // autocomplete arrives. Do not move Return onto a new command.
            add(Result(id: "query:" + query, title: query, detail: nativeError ?? "",
                       symbol: "magnifyingglass", subtitle: nativeError, isSearch: true, input: query),
                .init(archetype: .chromium, key: "query:" + query))
        }
        for (rank, result) in nativeRows.enumerated() {
            let key = result.navigation.map { navigation in
                navigation.search
                    ? CommandBarRowDiff.searchKey(navigation.editText.isEmpty ? navigation.title : navigation.editText)
                    : CommandBarRanking.pageKey(navigation.url, title: navigation.title)
            } ?? result.id
            add(result, .init(archetype: .chromium, key: key, chromiumRank: rank,
                              urlKey: result.navigation.flatMap { $0.search ? nil : CommandBarRowDiff.pageKey($0.url) }))
        }
        for tab in tabs where tab.archivedAt == nil {
            let url = URL(string: tab.url)
            let key = InternalPage(urlString: tab.url).map {
                $0.noteID.map { "document:" + $0.uuidString.lowercased() } ?? "easel:" + ($0.easelID?.uuidString.lowercased() ?? "")
            } ?? url.map { CommandBarRanking.pageKey($0, title: tab.title) } ?? "tab:" + tab.id.uuidString
            // The displayed title (a custom title first) is searchable as well as the page's.
            let row = tabResult(tab)
            add(row, .init(archetype: .tab, key: key, texts: [row.title, tab.title, url?.host ?? "", tab.url],
                           urlKey: url.map(CommandBarRowDiff.pageKey)))
        }
        for document in documents {
            add(Result(id: document.key, title: document.title.isEmpty ? (document.kind == .note ? "Untitled Note" : "Untitled Easel") : document.title,
                       detail: document.kind == .note ? "Note" : "Easel",
                       symbol: (document.kind == .note ? InternalPage.note(document.id) : .easel(document.id)).sidebarFallbackSymbol,
                       document: document),
                .init(archetype: .document, key: document.key, texts: [document.title]))
        }
        let typed = query.lowercased()
        if !typed.contains(where: \.isWhitespace) {
            for domain in topDomainList where domain.host.hasPrefix(typed) {
                //
                add(Result(id: "top-domain:" + domain.host, title: domain.siteName, detail: "", symbol: "globe",
                           subtitle: CommandBarResultText.urlSubtitle(domain.url.absoluteString),
                           url: domain.url, input: domain.url.absoluteString),
                    .init(archetype: .topDomain, key: CommandBarRowDiff.pageKey(domain.url), texts: [domain.host],
                          urlKey: CommandBarRowDiff.pageKey(domain.url)))
            }
        }
        return CommandBarRanking.rank(candidates, query: query).map { pool[$0] }
    }
    func updateTopDomains(_ domains: [CommandBarRanking.Domain]) {
        guard !dismissed, domains != topDomainList else { return }
        topDomainList = domains; topDomainGeneration += 1
        if !editState.query.isEmpty && !isScoped { refreshResults(requestNative: false) }
    }
    /// An empty answer (a timed-out query, or history just cleared) falls back
    /// to Parc's own list; an engine without the all-pages query (before
    /// overlay 323) never answers.
    func updateRecentPages(_ pages: [(url: String, title: String)]) {
        guard !dismissed, !pages.isEmpty || recentPages != nil else { return }
        recentPages = pages.isEmpty ? nil : pages; recentPagesGeneration += 1
        lastHistoryScanKey = nil; cachedHistoryVisits = []
        if editState.query.isEmpty && !isScoped { refreshResults(requestNative: false) }
    }
    ///
    private static func iconImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? SidebarPlusMenuArtwork.image(name)
    }
    private static func title(for command: KeyboardShortcuts.MenuCommand) -> String {
        CommandBarTypedCommand.commandBarTitle(forMenuCommand: command.id, menuTitle: command.title)
    }
    private func nativeResultRows(scoped: Bool) -> [Result] {
        var keys = Set<String>()
        let extensionFirst = extensionActions.contains { $0.resultIndex == 0 }
        var rows: [Result?] = nativeResults.enumerated().map { index, navigation in
            let key = navigation.search
                ? CommandBarRowDiff.searchKey(navigation.editText.isEmpty ? navigation.title : navigation.editText)
                : CommandBarRowDiff.pageKey(navigation.url)
            var id = "native:" + key, occurrence = 1
            while !keys.insert(id).inserted { occurrence += 1; id = "native:\(key)#\(occurrence)" }
            return nativeRow(navigation, id: id, scoped: scoped, preserveDefault: index == 0 && !extensionFirst)
        }
        // Extension action positions refer to the same original native order;
        // they carry no copyable URL or synthetic navigation destination.
        for action in extensionActions.sorted(by: { $0.resultIndex < $1.resultIndex }) {
            let row = Result(id: "extension:\(action.extensionID):\(action.editText):\(action.title)",
                             title: action.title.isEmpty ? action.detail : action.title,
                             detail: action.detail, symbol: "puzzlepiece.extension",
                             subtitle: action.title.isEmpty ? nil : action.detail, extensionAction: action)
            rows.insert(row, at: min(Int(action.resultIndex), rows.count))
        }
        return rows.compactMap { $0 }
    }
    private func nativeRow(_ navigation: PCNativeSearchNavigation, id: String, scoped: Bool, preserveDefault: Bool) -> Result? {
        // A keyword scope lists only its own engine's matches.
        if scoped {
            return Result(id: id, title: navigation.title.isEmpty ? input.stringValue : navigation.title, detail: "",
                          symbol: "magnifyingglass", isSearch: true, url: navigation.url, navigation: navigation)
        }
        // A held snapshot belongs to the input it answered, not the field's text.
        guard let row = CommandBarResultText.nativeRow(matchType: Self.matchType(of: navigation), isSearch: navigation.search,
                                                      contents: navigation.title, description: navigation.detail,
                                                      url: navigation.url.absoluteString, input: nativeInput,
                                                      preserveDefault: preserveDefault) else { return nil }
        return Result(id: id, title: row.title, detail: "", symbol: row.symbol, subtitle: row.subtitle,
                      isSearch: row.isSearch, url: navigation.url, navigation: navigation)
    }
    private func caption(for tab: BrowserTab) -> CommandBarResultText.TabCaption {
        tabCaption?(tab) ?? .switchToTab
    }
    /// Chromium's AutocompleteMatchType name; engines before overlay 297 don't
    /// expose it. The single reader of the match type, calculator included.
    private static func matchType(of navigation: PCNativeSearchNavigation) -> String? {
        navigation.responds(to: #selector(getter: PCNativeSearchNavigation.matchType)) ? navigation.matchType : nil
    }
    private func enabled(_ result: Result) -> Bool {
        guard !result.isExpired else { return false }
        if let action = result.extensionAction {
            return extensionDisposition != nil && omnibox?.canExecuteExtensionAction(action) == true
        }
        if let action = result.extensionLaunch {
            return extensionLaunchSnapshot.contains {
                $0.identifier == action.identifier && $0.generation == action.generation
                    && $0.pageIdentifier == action.pageIdentifier && $0.profilePath == action.profilePath
            }
        }
        if result.managesPasswords { return onManagePasswords != nil }
        if result.document != nil { return onOpenDocument != nil }
        if result.muteAllTabs != nil { return onMuteAllTabs != nil }
        if let action = result.spaceAction { return canFocusSpace?(action) == true }
        if let action = result.folderAction { return canOpenFolder?(action) == true }
        if let action = result.favoriteAction { return canPerformFavorite?(action) == true }
        if let action = result.folderMove { return canMoveToFolder?(action) == true }
        if let action = result.favoriteRename { return canRenameFavorite?(action) == true }
        if let command = result.typedCommand { return canPerformTypedCommand?(command) == true }
        return result.command.map { KeyboardShortcuts.shared.canPerformMenuCommand($0) } ?? true
    }
    private func select(row: Int, explicit: Bool, projectCompletion: Bool = false, preserveEditorSelection: Bool = false) {
        guard results.indices.contains(row) else { return }
        if explicit {
            if row != table.selectedRow { backgroundGeneration &+= 1 }
            if retainedBackgroundHistory?.result.id != results[row].id { retainedBackgroundHistory = nil }
            explicitSelectionID = results[row].id
        }
        selectingProgrammatically = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        selectingProgrammatically = false
        if projectCompletion { projectSelectedCompletion(preserveEditorSelection: preserveEditorSelection) } else { clearCompletion() }
        table.scrollRowToVisible(row); updateSelectionAppearance()
    }
    private func moveSelection(_ delta: Int) {
        guard !dismissed, isOwnerValid?() != false,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        if sidebarBrowsing { onSidebarMove?(delta); return }
        guard let row = table.keyboardSelectionRow(moving: delta, wrapping: actionsScope || !editState.query.isEmpty) else { return }
        select(row: row, explicit: true, projectCompletion: true)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        // A direct accessibility/native table selection shares the keyboard
        // projection. Pointer hover has its own row owner and never selects.
        if !selectingProgrammatically, results.indices.contains(table.selectedRow) {
            backgroundGeneration &+= 1
            if retainedBackgroundHistory?.result.id != results[table.selectedRow].id { retainedBackgroundHistory = nil }
            explicitSelectionID = results[table.selectedRow].id
            projectSelectedCompletion()
        }
        updateSelectionAppearance()
    }
    private func projectSelectedCompletion(preserveEditorSelection: Bool = false) {
        guard !dismissed, isOwnerValid?() != false, !isScoped, !scopeInvalidated,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              results.indices.contains(table.selectedRow),
              let navigation = results[table.selectedRow].navigation,
              !navigation.editText.isEmpty else { clearCompletion(); return }
        editState.project(resultID: results[table.selectedRow].id, text: navigation.editText)
        applyCompletion(preserveEditorSelection: preserveEditorSelection)
    }
    private func projectDefaultCompletion() {
        guard explicitSelectionID == nil, !dismissed, window?.isKeyWindow == true,
              isOwnerValid?() != false, omnibox?.canSubmit == true,
              !isScoped, !scopeInvalidated, table.selectedRow == 0,
              let result = results.first, let navigation = result.navigation,
              let text = navigation.inlineCompletionText,
              let editor = input.currentEditor() as? NSTextView else { return }
        if editState.projection?.resultID == result.id, editState.displayedText == text { return }
        if editState.projectInline(resultID: result.id, text: text,
                                   selection: editor.selectedRange(), hasMarkedText: editor.hasMarkedText()) {
            applyCompletion()
        }
    }
    private func clearCompletion() {
        guard editState.projection != nil else { return }
        guard (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        editState.clearProjection()
        applyCompletion()
    }
    private func applyCompletion(preserveEditorSelection: Bool = false) {
        guard !dismissed, isOwnerValid?() != false,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        // A late provider refresh with the same displayed result must not undo
        // AppKit caret/selection changes (mouse, Left/Right or text bindings).
        if preserveEditorSelection, input.stringValue == editState.displayedText { return }
        applyingCompletion = true
        defer { applyingCompletion = false }
        input.stringValue = editState.displayedText
        previousInput = input.stringValue
        if let editor = input.currentEditor() as? NSTextView {
            editor.string = input.stringValue
            editor.setSelectedRange(editState.selection)
        }
    }
    private func acceptCompletion() -> Bool {
        guard !dismissed, isOwnerValid?() != false,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        let scope: CommandBarScopeKeyboard.Scope = actionsScope ? .actions
            : isWebsiteScoped ? .website : scopeInvalidated ? .unavailable : .ordinary
        switch CommandBarScopeKeyboard.tab(query: editState.query, scope: scope) {
        case .enterActions: enterActionsScope(); return true
        case .leaveScope: leaveScope(); return true
        case .complete: break
        }
        // As for Return, a scope offer or completion belongs to this query's rows.
        if nativeHold.presentsBeforeSubmitting(explicitSelection: explicitSelectionID != nil) { releaseNativeHold() }
        if selectedScopeOffer != nil { enterOfferedScope(); return true }
        // Tab is an editing action. Never submit a command, switch an original
        // tab or turn a typed local action into a URL/query string.
        if !isScoped, !scopeInvalidated, results.indices.contains(table.selectedRow),
           nativeHold.nativeRowsAnswer(editState.query.trimmingCharacters(in: .whitespacesAndNewlines)),
           results[table.selectedRow].navigation?.canCompleteWithTab == true {
            projectSelectedCompletion()
        }
        if editState.projection != nil {
            editState.accept(); applyCompletion()
        }
        window?.makeFirstResponder(input)
        if let editor = input.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        return true
    }
    private func updateSelectionAppearance() {
        for row in results.indices {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandResultCell)?.setSelected(row == table.selectedRow)
        }
        updateInputIcon(); layoutScopeHeader()
    }
    private func updateInputIcon() {
        // Zero-query tab/history selection does not replace the empty field's
        // search affordance, including when a favicon arrives asynchronously.
        guard (isScoped || scopeInvalidated || !input.stringValue.isEmpty),
              results.indices.contains(table.selectedRow) else {
            inputIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil); return
        }
        let result = results[table.selectedRow]
        inputIcon.image = result.extensionLaunch?.icon ?? result.url.flatMap { icons[$0] } ?? Self.iconImage(result.symbol)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard results.indices.contains(row) else { return nil }
        let view = CommandResultRowView()
        view.selectedColor = selectedRowColor
        bind(view, to: results[row])
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let result = results[row]
        let cell = CommandResultCell(title: result.title, subtitle: result.subtitle, detail: result.detail, accessory: accessoryText(result),
                                     isTab: result.tabID != nil,
                                     icon: result.extensionLaunch?.icon ?? result.url.flatMap { icons[$0] } ?? Self.iconImage(result.symbol),
                                     spokenAccessory: result.caption?.spoken, spokenSubtitle: CommandBarResultText.spokenSubtitle(result.subtitle),
                                     enabled: enabled(result), spaceAction: result.spaceAction, folderAction: result.folderAction ?? result.folderMove?.folder,
                                     isAction: result.command != nil || result.spaceAction != nil || result.folderAction != nil
                                        || result.favoriteAction != nil || result.folderMove != nil || result.favoriteRename != nil
                                        || result.managesPasswords || result.muteAllTabs != nil)
        bind(cell, to: result)
        cell.selectedColor = selectedRowColor
        cell.setSelected(row == table.selectedRow)
        return cell
    }
    private func accessoryText(_ result: Result) -> String {
        // TypeTravelCandidate.renameCurrentTab carries the Rename binding,
        //
        let shortcut = result.favoriteRename != nil
            ? KeyboardShortcuts.shared.activeShortcut(for: "renameCurrentItem:") : result.command?.shortcut
        return result.tabID != nil ? (result.caption ?? .switchToTab).text : shortcut?.display ?? ""
    }
    private func isDeletable(_ result: Result) -> Bool {
        if let navigation = result.navigation { return omnibox?.canDeleteResult(navigation) == true }
        if let action = result.extensionAction { return omnibox?.canDeleteExtensionAction(action) == true }
        return false
    }
    /// Everything a cell draws. A kept row whose content changes gets a new cell.
    private func rowContent(_ result: Result) -> String {
        let context = result.spaceAction.map { "\($0.name)\u{1}\($0.symbol)" }
            ?? (result.folderAction ?? result.folderMove?.folder).map { "\($0.name)\u{1}\($0.detail)" } ?? ""
        return [result.title, result.subtitle ?? "", result.caption?.spoken ?? "", result.isSearch ? "search" : "",
                result.detail, result.symbol, accessoryText(result), result.url?.absoluteString ?? "",
                result.tabID == nil ? "" : "tab", enabled(result) ? "on" : "off", isDeletable(result) ? "delete" : "",
                result.extensionLaunch.map { "\($0.generation)" } ?? "", context].joined(separator: "\u{0}")
    }
    /// A retained row or cell activates only this publication's payload.
    private func bind(_ view: CommandResultRowView, to result: Result) {
        let publication = resultPublication
        view.onPress = { [weak self] event in
            guard let disposition = CommandBarSubmission.resolve(event.modifierFlags) else { return false }
            return self?.activateResult(result, publication: publication, disposition: disposition) ?? false
        }
    }
    private func bind(_ cell: CommandResultCell, to result: Result) {
        let publication = resultPublication
        if let navigation = result.navigation, omnibox?.canDeleteResult(navigation) == true {
            // Capture the actual native publication object, never a row index,
            // display URL or string ID that a later result might reuse.
            cell.onDelete = { [weak self] in self?.deleteSuggestion(navigation) ?? false }
        } else if let action = result.extensionAction, omnibox?.canDeleteExtensionAction(action) == true {
            cell.onDelete = { [weak self] in self?.deleteExtensionSuggestion(action) ?? false }
        } else if cell.onDelete != nil {
            cell.onDelete = nil
        }
        if result.input != nil && result.url == nil { cell.setAccessibilityHelp("Search or open address") }
        cell.onPress = { [weak self, weak cell] in
            guard let self, let cell, cell.window === self.window,
                  !cell.isHiddenOrHasHiddenAncestor else { return false }
            return self.activateResult(result, publication: publication, disposition: .ordinary)
        }
    }
    private func deleteSuggestion(_ navigation: PCNativeSearchNavigation) -> Bool {
        guard !dismissed, window?.isKeyWindow == true, isOwnerValid?() != false,
              !scopeInvalidated, (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              let row = results.firstIndex(where: { $0.navigation === navigation }),
              omnibox?.deleteResult(navigation) == true else { return false }
        backgroundGeneration &+= 1
        // Native removal has accepted the exact provider object. Remove only
        // that presentation immediately; its authoritative replacement snapshot
        // follows on main without starting a fresh search or navigation.
        editState.stopAutomaticCompletion()
        clearCompletion()
        nativeResults.removeAll { $0 === navigation }
        scopeOffers.removeAll { $0.result === navigation }
        explicitSelectionID = nil
        refreshResults(requestNative: false)
        if !results.isEmpty { select(row: min(row, results.count - 1), explicit: true) }
        announceScope("Suggestion deleted.")
        return true
    }
    private func deleteExtensionSuggestion(_ action: PCNativeOmniboxExtensionAction) -> Bool {
        guard !dismissed, window?.isKeyWindow == true, isOwnerValid?() != false,
              !scopeInvalidated, (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              let row = results.firstIndex(where: { $0.extensionAction === action }),
              omnibox?.deleteExtensionAction(action) == true else { return false }
        backgroundGeneration &+= 1
        editState.stopAutomaticCompletion(); clearCompletion()
        extensionActions.removeAll { $0 === action }
        scopeOffers.removeAll { $0.extensionAction === action }
        explicitSelectionID = nil
        refreshResults(requestNative: false)
        if !results.isEmpty { select(row: min(row, results.count - 1), explicit: true) }
        announceScope("Suggestion deleted.")
        return true
    }
    private func handleDeleteSuggestionKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.keyCode == 51,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .option],
              results.indices.contains(table.selectedRow) else { return false }
        let result = results[table.selectedRow]
        if let action = result.extensionAction { return deleteExtensionSuggestion(action) }
        return result.navigation.map { deleteSuggestion($0) } ?? false
    }
    private var selectedScopeOffer: PCNativeOmniboxScope? {
        guard !isScoped, !scopeInvalidated, !dismissed,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              results.indices.contains(table.selectedRow) else { return nil }
        let result = results[table.selectedRow]
        guard !result.isExpired else { return nil }
        if let action = result.extensionAction {
            guard extensionDisposition != nil else { return nil }
            return scopeOffers.first { $0.extensionAction === action }
        }
        let pageURL: URL?
        if let navigation = result.navigation {
            if let offer = scopeOffers.first(where: { $0.result === navigation && (!$0.isExtension || extensionDisposition != nil) }) {
                return offer
            }
            guard !navigation.search, nativeResults.contains(where: { $0 === navigation }) else { return nil }
            pageURL = navigation.url
        } else if result.tabID != nil || result.input != nil {
            //
            //
            // a native website result becomes Switch to Tab. Return still
            // uses the original tab ID, never this URL as a navigation token.
            pageURL = result.url
        } else {
            return nil
        }
        //
        //
        guard let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              let host = pageURL.host else { return nil }
        return CommandBarSiteColor.scope(forPageHost: host, in: siteScopes) { Self.site(of: $0)?.host }
    }
    /// The engine's template, empty-query search host and prepopulated flag.
    /// An engine built before these bridge fields has none.
    private static func site(of scope: PCNativeOmniboxScope) -> (template: String, host: String, prepopulated: Bool)? {
        guard scope.responds(to: #selector(getter: PCNativeOmniboxScope.searchHost)) else { return nil }
        return (scope.templateURL, scope.searchHost, scope.isPrepopulated)
    }
    /// The theme's selected colour, or the site's while a website scope has one.
    private var selectedRowColor: NSColor { (isWebsiteScoped ? scopeColor : nil) ?? palette.selected }
    /// A bundled engine's colour applies at once. Any other engine waits for
    ///
    ///
    private func refreshScopeColor(for scope: PCNativeOmniboxScope) {
        scopeColorRequest &+= 1
        let request = scopeColorRequest
        let site = Self.site(of: scope)
        scopeColor = site.flatMap { CommandBarSiteColor.bundledColor(template: $0.template, searchHost: $0.host, prepopulated: $0.prepopulated) }
        applyPalette()
        guard scopeColor == nil, let host = site?.host, !host.isEmpty, let page = siteVisit(searchHost: host) else { return }
        PCNativeBrowserApplication.favicon(for: page, profilePath: profilePath) { [weak self] image in
            MainActor.assumeIsolated {
                guard let self, self.scopeColorRequest == request, !self.dismissed,
                      let image, let pixels = CommandBarSiteColor.faviconPixels(image) else { return }
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let rgb = CommandBarSiteColor.dominantRGB(pixels)
                    DispatchQueue.main.async { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.scopeColorRequest == request, !self.dismissed, let rgb else { return }
                            self.scopeColor = CommandBarSiteColor.faviconColor(rgb)
                            self.applyPalette()
                        }
                    }
                }
            }
        }
    }
    private func clearScopeColor() {
        scopeColorRequest &+= 1
        scopeColor = nil
        applyPalette()
    }
    ///
    /// host, one result. The open page leads, as it is the Profile's newest visit.
    private func siteVisit(searchHost: String) -> URL? {
        func matches(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(searchHost) }
        let visit = historyExcludedURL.flatMap { matches($0) ? $0 : nil }
            ?? rankedHistory.first { matches($0.url) || matches($0.title) }?.url
        return visit.flatMap(URL.init(string:)).flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }
    private func layoutScopeHeader() {
        let showsScope = isScoped || scopeInvalidated
        let displayedName = unavailableScopeName ?? scopedName
        // Extension ownership does not expose the saved website-template menu.
        let extensionScope = activeScope?.isExtension == true
        scopePill.isHidden = !showsScope || actionsScope || extensionScope
        actionsPill.isHidden = !actionsScope && !extensionScope
        if extensionScope { actionsPill.showExtension(name: displayedName) }
        else { actionsPill.showActions() }
        scopePill.title = displayedName
        scopePill.isEnabled = activeScope != nil && !scopeInvalidated
        scopePill.contentTintColor = scopeInvalidated ? .disabledControlTextColor : .white
        scopePill.setAccessibilityValue(scopeInvalidated ? "\(displayedName), unavailable" : displayedName)
        input.placeholderString = isScoped ? "Search…" : (sidebarBrowsing ? "Search…" : "Search or Enter URL…")
        let baseX: CGFloat = sidebarAnchor == nil ? 49 : 38
        let right: CGFloat = sidebarAnchor == nil ? 22 : 11
        var left = baseX
        if showsScope {
            let natural = actionsPill.isHidden ? scopePill.intrinsicContentSize.width
                : CommandBarScopePill.width(title: actionsPill.stringValue, font: actionsPill.font)
            let width = min(max(50, natural), max(50, container.bounds.width * 0.4))
            scopePill.frame = NSRect(x: left, y: sidebarAnchor == nil ? 20 : 12, width: width, height: 24)
            actionsPill.frame = scopePill.frame
            left += width + 10
        }
        let offer = selectedScopeOffer
        scopeOfferButton.isHidden = offer == nil
        var trailing = right
        if let offer {
            scopeOfferButton.show(site: offer.name, spaceTriggerEnabled: offer.spaceTriggerEnabled)
            scopeOfferButton.setAccessibilityLabel("Search \(offer.name)")
            scopeOfferButton.setAccessibilityHelp(offer.spaceTriggerEnabled ? "Press Space or Tab to enter this search scope." : "Press Tab to enter this search scope.")
            let size = scopeOfferButton.intrinsicContentSize
            let width = min(size.width, max(0, container.bounds.width * 0.45))
            scopeOfferButton.frame = NSRect(x: container.bounds.width - right - width,
                y: (sidebarAnchor == nil ? 32 : 24) - size.height / 2, width: width, height: size.height)
            trailing += width + 12
        }
        let showsPrivacyInfo = CommandBarSearchPrivacyPolicy.showsInfoAccessory(
            dismissed: privacyPolicy.hasBeenExplicitlyDismissed, bannerVisible: privacyBannerVisible,
            scoped: showsScope, offeringSiteSearch: offer != nil, hasResults: !results.isEmpty,
            sidebarSession: sidebarAnchor != nil)
        privacyInfoButton.isHidden = !showsPrivacyInfo
        if showsPrivacyInfo {
            privacyInfoButton.frame = NSRect(x: container.bounds.width - right - 24, y: 20, width: 24, height: 24)
            trailing += 24 + 12
        }
        input.frame.origin.x = left
        input.frame.size.width = max(24, container.bounds.width - left - trailing)
        if isWebsiteScoped, input.stringValue.isEmpty, results.isEmpty, nativeError == nil {
            emptyLabel.isHidden = true; scroll.isHidden = true; divider.isHidden = true
        } else {
            scroll.isHidden = sidebarBrowsing; divider.isHidden = sidebarAnchor != nil
        }
        if isScoped || scopeInvalidated {
            emptyLabel.frame = NSRect(x: 24, y: 77, width: max(0, container.bounds.width - 48), height: 40)
            if sidebarAnchor == nil {
                scroll.frame.origin.y = 68
                scroll.frame.size.height = max(0, container.bounds.height - 76 - privacyBannerHeight)
            }
        }
        table.fit(in: scroll, rowCount: results.count)
    }
    private func setScopeInput(_ value: String, selectAll: Bool) {
        backgroundGeneration &+= 1
        retainedBackgroundHistory = nil
        editState.edit(value)
        input.stringValue = value
        previousInput = value
        window?.makeFirstResponder(input)
        if let editor = input.currentEditor() as? NSTextView {
            editor.string = value
            editor.setSelectedRange(NSRange(location: selectAll ? 0 : (value as NSString).length,
                                            length: selectAll ? (value as NSString).length : 0))
        }
    }
    private func announceScope(_ message: String) {
        NSAccessibility.post(element: input, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    private func enterActionsScope() {
        guard !dismissed, isOwnerValid?() != false, !isScoped, !scopeInvalidated,
              editState.query.isEmpty,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        retireScopeMenu()
        actionsScope = true
        endNativeHold(); clearNativeResults(); explicitSelectionID = nil
        // Invalidate any outstanding ordinary publication without destroying
        // the original native session needed after this local scope exits.
        omnibox?.updateInput("", allowsInlineCompletion: false)
        setScopeInput("", selectAll: false)
        refreshResults(requestNative: false)
        announceScope("Actions. Search commands, or press Tab or Backspace on empty input to leave.")
    }
    @objc private func enterOfferedScope() { _ = enterScope(restoring: input.stringValue) }
    @objc private func showPrivacyBanner() {
        guard !dismissed, isOwnerValid?() != false else { return }
        privacyBannerVisible = true; position(); layoutContents()
        NSAccessibility.post(element: privacyBanner, notification: .announcementRequested, userInfo: [
            .announcement: privacyBanner.title.stringValue, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    @discardableResult private func enterScope(restoring query: String) -> Bool {
        guard !dismissed, isOwnerValid?() != false, let offer = selectedScopeOffer,
              let omnibox, omnibox.enterScope(offer) else { return false }
        // Entry invalidates earlier native publishes synchronously. Its next
        // authoritative snapshot owns a fresh active-scope identity.
        queryBeforeScope = query
        enteringScopeName = offer.name; endNativeHold(); clearNativeResults()
        scopeInvalidated = false; unavailableScopeName = nil; explicitSelectionID = nil
        if offer.isExtension { clearScopeColor() } else { refreshScopeColor(for: offer) }
        setScopeInput("", selectAll: false)
        refreshResults(requestNative: false)
        announceScope("Search \(offer.name)")
        return true
    }
    private func leaveScope(restoringQuery: Bool = false) {
        guard isScoped || scopeInvalidated, !dismissed, isOwnerValid?() != false else { dismiss(); return }
        retireScopeMenu()
        if actionsScope {
            actionsScope = false; explicitSelectionID = nil
            endNativeHold(); clearNativeResults()
            //
            // restores that input, not the address from before Cmd-L editing.
            setScopeInput("", selectAll: !restoringQuery)
            refreshResults(); position(); layoutContents()
            announceScope("Actions search ended")
            return
        }
        // An invalidated provider has already been retired natively. A user
        // exit may restore ordinary input; a notification alone never may.
        if !scopeInvalidated, omnibox?.leaveScope() != true { dismiss(); return }
        clearScopeColor()
        activeScope = nil; enteringScopeName = nil; endNativeHold(); clearNativeResults()
        scopeInvalidated = false; unavailableScopeName = nil; explicitSelectionID = nil; nativeError = nil
        // Empty Backspace restores the immediate pre-scope query with caret at
        // its end. Escape restores the address/new-tab session's selected input.
        setScopeInput(restoringQuery ? queryBeforeScope : initialInput, selectAll: !restoringQuery)
        refreshResults()
        position(); layoutContents()
        announceScope("Search scope ended")
    }
    private func retireScopeMenu() {
        scopeMenuLease = nil
        let menu = scopeMenu; scopeMenu = nil; menu?.cancelTracking()
        if let alert = scopeAlert {
            scopeAlert = nil
            if let owner = alert.window.sheetParent { owner.endSheet(alert.window, returnCode: .cancel) }
            alert.window.orderOut(nil)
        }
    }
    private func scopeMenuIsCurrent(_ lease: PCNativeOmniboxScopeMenu) -> Bool {
        !dismissed && isOwnerValid?() != false && scopeMenuLease === lease &&
            activeScope === lease.activeScope && !scopeInvalidated &&
            omnibox?.canUseScopeMenu(lease) == true &&
            (input.currentEditor() as? NSTextView)?.hasMarkedText() != true
    }
    private func showScopeMenu() {
        guard !dismissed, isOwnerValid?() != false, scopeAlert == nil,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              let lease = omnibox?.scopeMenu(), activeScope === lease.activeScope else { return }
        retireScopeMenu()
        scopeMenuLease = lease
        let editing = CommandBarScopeEditing(query: editState.query, displayedText: input.stringValue,
            selection: (input.currentEditor() as? NSTextView)?.selectedRange())
        let menu = NSMenu(); menu.autoenablesItems = false
        let remove = MenuAction.item("Remove “\(lease.activeScope.name)” Site Search") { [weak self] in
            self?.removeSiteSearch(lease, editing: editing)
        }
        remove.isEnabled = lease.canRemove; menu.addItem(remove)
        let change = NSMenuItem(title: "Change Site Search", action: nil, keyEquivalent: "")
        let choices = NSMenu(); choices.autoenablesItems = false
        for choice in lease.choices {
            let row = MenuAction.item(choice.name) { [weak self] in
                guard let self, self.scopeMenuIsCurrent(lease),
                      self.omnibox?.changeScope(choice, menu: lease) == true else { return }
                self.retireScopeMenu()
                self.activeScope = nil; self.enteringScopeName = choice.name
                self.endNativeHold(); self.clearNativeResults()
                self.explicitSelectionID = nil
                //
                self.refreshScopeColor(for: choice)
                // Preserve the original native edit range; only the chosen
                // engine changes. A projected old result cannot become a request.
                self.setScopeInput(editing.query, selectAll: false)
                self.restoreScopeSelection(editing.selectionForQuery)
                self.refreshResults(requestNative: false)
                self.announceScope("Search \(choice.name)")
            }
            row.toolTip = choice.keyword
            choices.addItem(row)
        }
        change.submenu = choices; change.isEnabled = !lease.choices.isEmpty; menu.addItem(change)
        menu.addItem(.separator())
        let manage = MenuAction.item("Manage…") { [weak self] in
            guard let self, self.scopeMenuIsCurrent(lease) else { return }
            let action = self.onManageSiteSearch, valid = self.isOwnerValid
            self.dismiss()
            if valid?() != false { action?() }
        }
        manage.isEnabled = lease.canManage && onManageSiteSearch != nil; menu.addItem(manage)
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Learn More") { [weak self] in
            guard let self, self.scopeMenuIsCurrent(lease) else { return }
            let alert = NSAlert()
            alert.messageText = "Site Search"
            alert.informativeText = "Type a site's search shortcut, then press Tab to search that site. Space also enters when enabled in your search settings. Use Change Site Search to keep your query and search another site. Removing a site search deletes its saved shortcut from this profile; you can add it again in Manage. Press Escape to return to your original address."
            alert.addButton(withTitle: "Done")
            self.presentScopeAlert(alert, lease: lease) { _ in }
        })
        scopeMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: scopePill.bounds.maxY), in: scopePill)
        if scopeMenu === menu { scopeMenu = nil }
        if !dismissed, scopeAlert == nil, scopeMenuIsCurrent(lease) {
            window?.makeFirstResponder(input)
            restoreScopeSelection(editing.selection)
        }
    }
    private func restoreScopeSelection(_ range: NSRange) {
        guard let editor = input.currentEditor() as? NSTextView,
              range.location != NSNotFound, range.location <= (editor.string as NSString).length,
              range.length <= (editor.string as NSString).length - range.location else { return }
        applyingCompletion = true
        editor.setSelectedRange(range)
        applyingCompletion = false
    }
    private func presentScopeAlert(_ alert: NSAlert, lease: PCNativeOmniboxScopeMenu,
                                   completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard scopeMenuIsCurrent(lease), let window, window.attachedSheet == nil, scopeAlert == nil else { return }
        scopeAlert = alert
        alert.beginSheetModal(for: window) { [weak self, weak alert] response in
            guard let self, let alert, self.scopeAlert === alert else { return }
            self.scopeAlert = nil
            guard self.scopeMenuIsCurrent(lease) else { return }
            self.window?.makeFirstResponder(self.input)
            completion(response)
        }
    }
    private func removeSiteSearch(_ lease: PCNativeOmniboxScopeMenu, editing: CommandBarScopeEditing) {
        guard scopeMenuIsCurrent(lease), lease.canRemove else { return }
        let remove: (Bool) -> Void = { [weak self] confirmed in
            guard let self, self.scopeMenuIsCurrent(lease),
                  self.omnibox?.removeScope(lease, confirmed: confirmed) == true else { return }
            let restored = editing.removingScope(prefix: self.queryBeforeScope)
            self.retireScopeMenu()
            self.clearScopeColor()
            self.activeScope = nil; self.enteringScopeName = nil
            self.endNativeHold(); self.clearNativeResults()
            self.scopeInvalidated = false; self.unavailableScopeName = nil; self.explicitSelectionID = nil
            self.setScopeInput(restored.text, selectAll: false)
            self.restoreScopeSelection(restored.selection)
            self.refreshResults(); self.position(); self.layoutContents()
            self.announceScope("\(lease.activeScope.name) Site Search removed")
        }
        if lease.requiresRemovalConfirmation {
            let alert = NSAlert()
            alert.messageText = "Remove “\(lease.activeScope.name)” Site Search?"
            alert.informativeText = "This removes the saved search shortcut from this profile."
            alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
            presentScopeAlert(alert, lease: lease) { [weak self] response in
                if response == .alertFirstButtonReturn { remove(true) }
                else { self?.restoreScopeSelection(editing.selection) }
            }
        } else { remove(false) }
    }

    var selectedURL: URL? {
        guard !dismissed, isOwnerValid?() != false, results.indices.contains(table.selectedRow) else { return nil }
        return results[table.selectedRow].url
    }
    @discardableResult func copySelectedURL() -> Bool {
        guard let url = selectedURL else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    private func activateResult(_ result: Result, publication: UUID, disposition: CommandBarSubmission) -> Bool {
        guard resultPublication == publication, !dismissed, window?.isKeyWindow == true,
              isOwnerValid?() != false, !scopeInvalidated, !sidebarBrowsing,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              enabled(result) else { return false }
        // Keep the exact row payload. In particular, a native request is not
        // looked up by URL, and a typed folder/Space command never becomes text.
        submitResult(result, disposition: disposition, retainsSelection: false)
        return true
    }
    private func submitSelection(_ disposition: CommandBarSubmission) {
        guard !dismissed, isOwnerValid?() != false else { dismiss(restoreFocus: false); return }
        if sidebarBrowsing {
            if disposition != .ordinary { NSSound.beep() } else { onSidebarCommit?() }
            return
        }
        if nativeHold.presentsBeforeSubmitting(explicitSelection: explicitSelectionID != nil) { releaseNativeHold() }
        guard results.indices.contains(table.selectedRow) else { return }
        submitResult(results[table.selectedRow], disposition: disposition, retainsSelection: true)
    }
    private func submitResult(_ result: Result, disposition: CommandBarSubmission, retainsSelection: Bool) {
        let inSplit = disposition == .split
        guard enabled(result) else { NSSound.beep(); return }
        // A local document opens in the window like its Library row; it has no
        // split request or background page.
        if result.document != nil, disposition != .ordinary { NSSound.beep(); return }
        submissionDepth += 1
        defer {
            submissionDepth -= 1
            if dismissed && submissionDepth == 0 { onDismissalSettled?() }
        }
        if let action = result.extensionLaunch {
            // A launch operates in the original page. It cannot promise a new
            // split/background destination. Dismiss the command surface before
            // Chromium validates and opens its genuine popup/context fallback.
            guard disposition == .ordinary, !dismissed, window?.isKeyWindow == true,
                  isOwnerValid?() != false,
                  (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
                NSSound.beep(); return
            }
            let launch = onLaunchExtension, stillValid = isOwnerValid
            dismiss()
            if stillValid?() == false || launch?(action) != true { NSSound.beep() }
            return
        }
        if let action = result.extensionAction {
            // Original Chromium onInputEntered must run while its keyword
            // provider is alive. Cancellation first would send the wrong event.
            // Extension API supports tab dispositions, not Parc split promises.
            guard let extensionDisposition, !inSplit, !dismissed, window?.isKeyWindow == true,
                  isOwnerValid?() != false,
                  (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  omnibox?.executeExtensionAction(action, disposition: disposition == .background ? .newBackgroundTab : extensionDisposition) == true else {
                NSSound.beep(); return
            }
            if disposition == .background {
                extensionActions = []; explicitSelectionID = nil
                refreshResults(requestNative: false)
                announceScope("Request sent to \(action.detail)")
            } else { dismiss() }
            return
        }
        // The same original folder row has a distinct force-open copy action.
        // Option-Return is still a navigation-only split intent.
        if let move = result.folderMove,
           disposition == .split || (disposition == .background && canCopyToFolder?(move) != true) {
            NSSound.beep(); return
        }
        if disposition == .background && (result.navigation != nil || result.input != nil || result.tabID != nil)
            && !(result.tabID != nil && result.url.map { InternalPage.isInternal($0.absoluteString) } == true) {
            submitInBackground(result, retainsSelection: retainsSelection); return
        }
        let splitCommand = result.command.flatMap { canSplitCommand?($0) == true ? $0 : nil }
        if inSplit {
            // A split destination is an actual navigation, original tab, or the
            // New Note / New Easel commands that fill Add Split's blank pane.
            guard result.navigation != nil || result.input != nil || result.tabID != nil || splitCommand != nil,
                  splitCommand != nil || canSplitSelection?(result.tabID) == true else { NSSound.beep(); return }
            let canCommit = splitCommand != nil ? onSplitCommand != nil
                : result.navigation != nil ? onSplitNavigation != nil
                : result.tabID != nil ? onSplitTab != nil
                : onSplitInput != nil
            guard canCommit else { NSSound.beep(); return }
        }
        // Keep the original token alive across cancellation of its producer.
        // The native token retains POST/headers and its original profile lease.
        let navigate = onNavigate, search = onSearchNavigation, selectTab = onSelectTab
        let splitInput = onSplitInput, splitNavigation = onSplitNavigation, splitTab = onSplitTab
        let splitCommandHandler = onSplitCommand
        let managePasswords = onManagePasswords, focusSpace = onFocusSpace, openFolder = onOpenFolder
        let openDocument = onOpenDocument
        let muteAllTabs = onMuteAllTabs, performTyped = onPerformTypedCommand
        let performFavorite = onPerformFavorite, moveToFolder = onMoveToFolder, renameFavorite = onRenameFavorite, copyToFolder = onCopyToFolder
        let stillValid = isOwnerValid, rejectDestination = onRejectedDestination
        let isDestination = result.navigation != nil || result.tabID != nil || result.input != nil || result.document != nil || splitCommand != nil
        if isDestination { onWillSubmitDestination?() }
        dismiss()
        guard stillValid?() != false else {
            if isDestination { rejectDestination?() }; return
        }
        if let command = splitCommand {
            splitCommandHandler?(command)
            return
        }
        if inSplit {
            if let navigation = result.navigation { splitNavigation?(navigation) }
            else if let id = result.tabID { splitTab?(id) }
            else if let input = result.input { splitInput?(input) }
            return
        }
        if let navigation = result.navigation { search?(navigation) }
        else if let action = result.spaceAction { focusSpace?(action) }
        else if let action = result.folderAction { openFolder?(action) }
        else if let action = result.favoriteAction { performFavorite?(action) }
        else if let move = result.folderMove {
            if disposition == .background { copyToFolder?(move) } else { moveToFolder?(move) }
        }
        else if let action = result.favoriteRename { renameFavorite?(action) }
        else if let command = result.typedCommand { performTyped?(command) }
        else if let muted = result.muteAllTabs { if muteAllTabs?(muted) != true { NSSound.beep() } }
        // Revalidated now the panel is gone; a refusal never runs another target.
        else if let command = result.command { if !KeyboardShortcuts.shared.performMenuCommand(command) { NSSound.beep() } }
        else if let id = result.tabID { selectTab?(id) }
        else if result.managesPasswords { managePasswords?() }
        else if let document = result.document { openDocument?(document) }
        else if let input = result.input { navigate?(input) }
    }
    private func submitInBackground(_ result: Result, retainsSelection: Bool) {
        guard backgroundOperation == nil, omnibox?.canSubmit == true else { NSSound.beep(); return }
        if retainsSelection { explicitSelectionID = result.id }
        if retainsSelection, editState.query.isEmpty, result.input != nil, result.url != nil {
            retainedBackgroundHistory = (result, table.selectedRow)
        }
        let operation = UUID(), query = editState.query, scope = activeScope
        let generation = backgroundGeneration
        backgroundOperation = operation
        let valid: () -> Bool = { [weak self] in
            guard let self, !self.dismissed, self.window?.isKeyWindow == true,
                  self.backgroundOperation == operation, self.backgroundGeneration == generation, self.isOwnerValid?() != false,
                  self.omnibox?.canSubmit == true, self.editState.query == query,
                  self.activeScope === scope, !self.scopeInvalidated else { return false }
            // The admitted request is immutable. Provider refresh or this
            // operation's own model publication cannot retarget/cancel it.
            // Actual user editing/selection invalidates the generation instead.
            return true
        }
        let completed: (String?) -> Void = { [weak self] error in
            guard let self, self.backgroundOperation == operation else { return }
            let mayAnnounce = valid()
            self.backgroundOperation = nil
            guard mayAnnounce else { return }
            self.announceScope(error ?? "Opened in a background tab")
            if error != nil { NSSound.beep() }
        }
        if let request = result.navigation, let open = onBackgroundNavigation { open(request, valid, completed) }
        else if let id = result.tabID, let open = onBackgroundTab { open(id, valid, completed) }
        else if let input = result.input, let open = onBackgroundInput { open(input, valid, completed) }
        else { completed("This result cannot open in the background.") }
    }
    private func handleBackgroundReturn(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, [36, 76].contains(event.keyCode),
              CommandBarSubmission.resolve(event.modifierFlags) == .background,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        submitSelection(.background); return true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Let the input method commit/cancel marked text before handling a
        // command-bar action. Ordinary editing/selection/copy stays AppKit-owned.
        guard !textView.hasMarkedText() else { return false }
        if let disposition = CommandBarSubmission.resolveTextCommand(commandSelector,
            event: NSApp.currentEvent, hasMarkedText: textView.hasMarkedText()) {
            submitSelection(disposition); return true
        }
        switch NSStringFromSelector(commandSelector) {
        case "insertTab:": return acceptCompletion()
        case "deleteBackward:", "deleteBackwardByDecomposingPreviousCharacter:", "deleteWordBackward:":
            editState.stopAutomaticCompletion()
            guard (isScoped || scopeInvalidated), textView.string.isEmpty else { return false }
            leaveScope(restoringQuery: true); return true
        case "cancelOperation:":
            if isScoped || scopeInvalidated { leaveScope() } else { dismiss() }
            return true
        case "moveDown:": moveSelection(1); return true
        case "moveUp:": moveSelection(-1); return true
        default: return false
        }
    }
    private func handleTableKey(_ event: NSEvent) -> Bool {
        if handleDeleteSuggestionKey(event) { return true }
        switch event.keyCode {
        case 36, 76:
            guard let disposition = CommandBarSubmission.resolveReturn(event.modifierFlags) else { return false }
            submitSelection(disposition); return true
        case 48:
            guard event.modifierFlags.intersection([.command, .control, .shift, .option]).isEmpty else { return false }
            return acceptCompletion()
        case 51:
            guard (isScoped || scopeInvalidated), input.stringValue.isEmpty else { return false }
            leaveScope(restoringQuery: true); return true
        case 53:
            if isScoped || scopeInvalidated { leaveScope() } else { dismiss() }
            return true
        case 125: moveSelection(1); return true
        case 126: moveSelection(-1); return true
        default: return false
        }
    }
}

///
///
private final class CommandFieldEditor: NSTextView {
    var onCopy: ((String) -> Void)?
    override func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general, before = pasteboard.changeCount
        let range = selectedRange(), value = string as NSString
        let text = range.location != NSNotFound && range.length > 0
            && range.location <= value.length && range.length <= value.length - range.location
            ? value.substring(with: range) : nil
        super.copy(sender)
        if let text, pasteboard.changeCount != before { onCopy?(text) }
    }
}
private final class CommandPanel: NSPanel {
    var onBackgroundReturn: ((NSEvent) -> Bool)?
    var onDeleteSuggestion: ((NSEvent) -> Bool)?
    lazy var commandFieldEditor: CommandFieldEditor = {
        let editor = CommandFieldEditor(); editor.isFieldEditor = true; return editor
    }()
    weak var commandField: NSTextField?
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard let field = object as? NSTextField, field === commandField else { return super.fieldEditor(createFlag, for: object) }
        return commandFieldEditor
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, onBackgroundReturn?(event) == true || onDeleteSuggestion?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
