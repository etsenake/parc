import AppKit
import Combine
import SwiftUI

@MainActor final class CommandBar: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Result {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        var subtitle: String? = nil
        var caption: CommandBarResultText.TabCaption? = nil
        var isSearch = false
        var url: URL? = nil
        var tabID: UUID? = nil
        var archivedTabID: UUID? = nil
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
        var completionHost: String? = nil
    }
    var onNavigate: ((String, String) -> Void)?
    var onSearchNavigation: ((PCNativeSearchNavigation) -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    var tabCaption: ((BrowserTab) -> CommandBarResultText.TabCaption)? {
        didSet { lastOpenResultsFingerprint = nil }
    }
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
    var canPerformTypedCommand: ((CommandBarTypedCommand) -> Bool)?
    var onPerformTypedCommand: ((CommandBarTypedCommand) -> Void)?
    var canSplitSelection: ((UUID?) -> Bool)?
    var onSplitInput: ((String, String) -> Void)?
    var onSplitNavigation: ((PCNativeSearchNavigation) -> Void)?
    var onSplitTab: ((UUID) -> Void)?
    var canSplitCommand: ((KeyboardShortcuts.MenuCommand) -> Bool)?
    var onSplitCommand: ((KeyboardShortcuts.MenuCommand) -> Void)?
    var onBackgroundNavigation: ((PCNativeSearchNavigation, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    var onBackgroundInput: ((String, String, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    var onBackgroundTab: ((UUID, String, @escaping () -> Bool, @escaping (String?) -> Void) -> Void)?
    private var backgroundOperation: UUID?
    private var backgroundGeneration: UInt64 = 0
    private var retainedBackgroundHistory: (result: Result, row: Int)?
    var onDismiss: (() -> Void)?
    var onDismissalSettled: (() -> Void)?
    private var submissionDepth = 0
    var onManagePasswords: (() -> Void)?
    var onOpenDocument: ((CommandBarDocument) -> Void)?
    var onRestoreArchived: ((UUID) -> Bool)?
    var onMuteAllTabs: ((Bool) -> Bool)?
    var onManageSiteSearch: (() -> Void)?
    var onSearchSettings: (() -> Void)?
    private let privacyBanner = CommandBarSearchPrivacyBanner()
    private let privacyInfoButton = CommandBarPrivacyInfoButton()
    private let privacyPolicy = CommandBarSearchPrivacyPolicy(defaults: .standard)
    private var privacyBannerVisible = false
    private var showsPrivacyBanner: Bool { privacyBannerVisible && sidebarAnchor == nil && !addressOnly }
    private var privacyBannerHeight: CGFloat { privacyBanner.isHidden ? 0 : privacyBanner.frame.height }
    var extensionLaunchActions: (() -> [PCNativeExtensionAction])? { didSet { extensionLaunchSnapshotIsStale = true } }
    var onLaunchExtension: ((PCNativeExtensionAction) -> Bool)?
    private var extensionLaunchSnapshot: [PCNativeExtensionAction] = []
    private var extensionLaunchSnapshotIsStale = true
    var isOwnerValid: (() -> Bool)?
    var onCopyText: ((String) -> Void)?
    var restorePageFocus: (() -> Void)?
    var mayRestoreOriginal: ((NSView) -> Bool)?
    var onSidebarMove: ((Int) -> Void)?
    var onSidebarCommit: (() -> Void)?
    var onSidebarQueryState: ((Bool) -> Void)?
    private weak var sidebarAnchor: NSView?
    private let resident: Bool
    var isResident: Bool { resident }
    static var residentRestHeight: CGFloat { CommandBarResidentLayout.restHeight }
    static var residentMaximumWidth: CGFloat { CommandBarResidentLayout.maximumWidth }
    private var residentRefocusPending = false
    private var residentExpanded: Bool {
        CommandBarResidentLayout.expands(resultCount: results.count, actionsScope: actionsScope, websiteScoped: isWebsiteScoped,
                                         inputIsEmpty: input.stringValue.isEmpty, scopeInvalidated: scopeInvalidated,
                                         hasError: nativeError != nil)
    }
    private let addressOnly: Bool
    private let popup: Bool
    private let currentPageTitle: String?
    private var addressWasEdited = false
    private var sidebarBrowsing: Bool { !addressOnly && sidebarAnchor != nil && input.stringValue.isEmpty && !isScoped && !scopeInvalidated }
    var isSidebarSession: Bool { sidebarAnchor != nil && !addressOnly }
    func refreshPosition() { if presented && !dismissed { position() } }

    private let input = CommandBarInputField()
    private let completionTitle = CommandBarCompletionTitleLabel.make()
    private var spokenCompletionTitle: String?
    private var completionTouched = false
    private var anchoredFieldSize = NSSize.zero
    private let inputIcon = NSImageView()
    private let scopePill = CommandBarScopePill()
    private var actionsScope = false
    private var scopeMenu: NSMenu?
    private var scopeMenuLease: PCNativeOmniboxScopeMenu?
    private var scopeAlert: ParcDialog?
    private let scopeOfferButton = CommandBarScopeHint()
    private var scopeHintOffersSpace = false
    private var scopeColor: NSColor?
    private var scopeColorRequest = 0
    private let extensionDisposition: PCNativeOmniboxExtensionDisposition?
    private let initialInput: String
    private var scopeOffers: [PCNativeOmniboxScope] = []
    private var siteScopes: [PCNativeOmniboxScope] = []
    private var activeScope: PCNativeOmniboxScope?
    private var enteringScopeName: String?
    private var scopeInvalidated = false
    private var unavailableScopeName: String?
    private var queryBeforeScope = ""
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
    private let scroll = CommandResultsScrollView()
    private var headerScrollerReserve: CGFloat = 0
    private let emptyLabel = NSTextField(labelWithString: "Search or Enter URL…")
    private let host = CommandBarHost()
    private let container = PopoverBackgroundView(blending: .withinWindow)
    private let shadowView = CommandBarShadowView()
    private var showsShadow = true
    private var splashView: NSView?
    private let fieldEditor: CommandFieldEditor = {
        let editor = CommandFieldEditor(); editor.isFieldEditor = true; return editor
    }()
    private var showsScopeSplash = false
    private let divider = CommandBarHairline()
    private var palette: CommandBarPalette
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
    private var historyRevision: UInt64
    private var historyExcludedURL: String?
    private var lastHistoryScanKey: CommandBarHistoryScanSkip.Key?
    private var cachedHistoryVisits: [CommandBarHistoryScanSkip.Visit] = []
    private var recentPages: [(url: String, title: String)]?
    private var recentPagesGeneration = 0
    private var spaces: [CommandBarSpaceAction]
    private var folders: [CommandBarFolderAction]
    private let folderMoves: [CommandBarFolderMove]
    private let favoriteAction: CommandBarFavoriteAction?
    private let favoriteRename: CommandBarFavoriteRenameAction?
    private let documentSource: (() -> [CommandBarDocument])?
    private lazy var documents: [CommandBarDocument] = documentSource?() ?? []
    private var topDomainList: [CommandBarRanking.Domain] = []
    private var topDomainGeneration = 0
    private var titleIndex: CommandBarTitleIndex?
    private var pendingTitleIndex: CommandBarTitleIndex?
    private var titleIndexGeneration = 0
    private var historyRemovals: UInt64 = 0
    private var hiddenPages: Set<String>? = []
    var removedHistoryURLs: ((UInt64) -> Set<String>?)?
    private var tabTitleTokens: [UUID: CommandBarTitleTokens] = [:]
    private var typedCommands: [CommandBarTypedCommand]
    private var commands: [KeyboardShortcuts.MenuCommand] = []
    private var commandSearch: [(title: String, text: String)] = []
    private func adoptCommands(_ list: [KeyboardShortcuts.MenuCommand]) {
        commands = addressOnly ? [] : list
        commandSearch = commands.map { command in
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
    private var focusObservation: NSKeyValueObservation?
    private var bindings: AnyCancellable?
    private var dismissed = false
    private var presented = false
    private var initialEditSelection: NSRange?
    private var lastOpenResultsFingerprint: String?
    private var presentedRows: [CommandBarRowDiff.Row] = []
    private var nativeHold = CommandBarNativeHold()
    private var nativeHoldDeadline: DispatchWorkItem?

    init(parent: NSWindow, tabs: [BrowserTab], history: [BrowserHistoryEntry], historyRevision: UInt64 = 0, historyExcludedURL: String? = nil, spaces: [CommandBarSpaceAction] = [], folders: [CommandBarFolderAction] = [], favoriteAction: CommandBarFavoriteAction? = nil, folderMoves: [CommandBarFolderMove] = [], favoriteRename: CommandBarFavoriteRenameAction? = nil, documents: (() -> [CommandBarDocument])? = nil, typedCommands: [CommandBarTypedCommand] = [], currentURL: String?, profilePath: String, page: PCNativePage?, nativeWindow: PCNativeBrowserWindow? = nil, sidebarAnchor: NSView? = nil, addressOnly: Bool = false, popup: Bool = false, currentPageTitle: String? = nil, initialEdit: (String, NSRange)? = nil, extensionDisposition: PCNativeOmniboxExtensionDisposition? = .currentTab, theme: SpaceTheme = SpaceTheme(), contentAppearance: NSAppearance? = nil, resident: Bool = false) {
        self.resident = resident
        self.addressOnly = addressOnly
        self.popup = popup
        self.currentPageTitle = currentPageTitle
        self.addressWasEdited = initialEdit != nil
        self.extensionDisposition = extensionDisposition
        self.theme = theme; palette = CommandBarPalette(theme: theme); self.contentAppearance = contentAppearance
        initialInput = currentURL == "about:blank" ? "" : currentURL ?? ""
        editState = CommandBarEditState(query: initialEdit?.0 ?? initialInput)
        self.sidebarAnchor = sidebarAnchor
        initialEditSelection = initialEdit?.1
        self.tabs = tabs; self.history = history; self.rankedHistory = BrowserHistoryOrder.newestFirst(history)
        self.historyRevision = historyRevision
        self.historyExcludedURL = historyExcludedURL ?? (currentURL == "about:blank" ? nil : currentURL)
        self.spaces = spaces; self.folders = folders; self.favoriteAction = favoriteAction; self.folderMoves = folderMoves; self.favoriteRename = favoriteRename; self.documentSource = documents; self.typedCommands = typedCommands; self.parent = parent; self.profilePath = profilePath
        if resident {
            originalResponder = nil
        } else if let editor = parent.firstResponder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSTextField {
            originalResponder = field; originalSelection = editor.selectedRange()
        } else { originalResponder = parent.firstResponder }
        host.appearance = CommandBarPalette.panelAppearance(inlineEmpty: sidebarAnchor != nil, resident: resident,
                                                            space: contentAppearance, window: parent.appearance)
        super.init()
        host.bar = container
        host.onKeyEquivalent = { [weak self] event in
            guard let self, self.hasFocus else { return false }
            return self.handleBackgroundReturn(event) || self.handleDeleteSuggestionKey(event)
        }
        fieldEditor.onCopy = { [weak self] text in
            guard let self, !self.dismissed, self.isOwnerValid?() != false else { return }
            self.onCopyText?(text)
        }
        fieldEditor.anchorsScroll = { [weak self] in self?.anchorField() ?? false }
        fieldEditor.onClipChange = { [weak self] resized in self?.fieldClipChanged(resized: resized) }
        fieldEditor.onUserScroll = { [weak self] in self?.completionTouched = true }
        host.addSubview(shadowView)
        host.addSubview(container)
        container.setAccessibilityElement(true)
        container.setAccessibilityRole(.group)
        container.setAccessibilityLabel(addressOnly ? "Current Tab Address" : "Command Bar")
        inputIcon.imageScaling = .scaleProportionallyDown; inputIcon.wantsLayer = true
        container.addSubview(inputIcon)
        input.isBordered = false; input.drawsBackground = false; input.wantsLayer = true
        input.font = CommandBarTypography.field
        input.placeholderString = "Search or Enter URL…"
        input.usesSingleLineMode = true; input.cell?.wraps = false
        input.cell?.isScrollable = true; input.lineBreakMode = .byClipping
        input.focusRingType = .none; input.delegate = self
        input.setAccessibilityLabel("Search or Enter URL")
        input.setAccessibilityHelp("Use Up and Down to choose a result, wrapping at either end while searching, Tab on empty input to search Actions, or Tab to accept its completion or enter its offered search scope, Return to open, Option-Return to open an eligible result in a split pane, Command-Option-Return to open a web result in a background tab and keep searching, Command-Option-Delete to remove a removable suggestion, or Escape to return to the page.")
        if addressOnly {
            input.setAccessibilityHelp("Search or enter an address for the current tab. Use Up and Down to choose a result, Return to open it, or Escape to return to the page.")
        } else if resident {
            input.setAccessibilityHelp("Use Up and Down to choose a result, wrapping at either end while searching, Tab on empty input to search Actions, or Tab to accept its completion or enter its offered search scope, Return to open, Command-Option-Return to open a web result in a background tab and keep searching, Command-Option-Delete to remove a removable suggestion, or Escape to clear the search.")
        }
        input.stringValue = initialEdit?.0 ?? initialInput
        previousInput = input.stringValue
        container.addSubview(input)
        container.addSubview(completionTitle)
        scopePill.onOpen = { [weak self] in self?.showScopeMenu() }
        scopePill.isHidden = true; container.addSubview(scopePill)
        scopeOfferButton.target = self; scopeOfferButton.action = #selector(enterOfferedScope)
        scopeOfferButton.isHidden = true; container.addSubview(scopeOfferButton)
        container.addSubview(divider)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion")))
        table.style = .plain
        table.headerView = nil; table.rowHeight = 50; table.intercellSpacing = .zero
        table.backgroundColor = .clear; table.selectionHighlightStyle = .none
        table.dataSource = self; table.delegate = self
        table.focusRingType = .none; table.allowsEmptySelection = false
        table.setAccessibilityLabel("Suggestions")
        table.onKey = { [weak self] event in self?.handleTableKey(event) ?? false }
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false; scroll.horizontalScrollElasticity = .none
        scroll.documentView = table; container.addSubview(scroll)
        scroll.onTile = { [weak self] in self?.scrollDidTile() }
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
            self.handOff(self.onSearchSettings)
        }
        container.onLayout = { [weak self] in self?.layoutContents() }
        container.onAppearanceChange = { [weak self] in self?.applyPalette() }
        applyPalette()
        adoptCommands(KeyboardShortcuts.shared.menuCommands(in: parent))
        bindings = KeyboardShortcuts.shared.$revision.dropFirst().sink { [weak self] _ in
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
            guard self.isOwnerValid?() != false else { self.respond(to: .ownerInvalid); return }
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

    func present() {
        guard !resident else { return }
        guard let parent, let content = parent.contentView, !dismissed, isOwnerValid?() != false else { dismiss(restoreFocus: false); return }
        presented = true
        host.frame = content.bounds; host.autoresizingMask = [.width, .height]
        content.addSubview(host, positioned: .above, relativeTo: nil)
        refreshResults(requestNative: false)
        position()
        if !parent.isKeyWindow { parent.makeKey() }
        parent.makeFirstResponder(input); applySelectionColor(); input.selectText(nil)
        if let selection = initialEditSelection, let editor = input.currentEditor() as? NSTextView {
            let count = (input.stringValue as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, count), length: min(selection.length, max(0, count - selection.location))))
            initialEditSelection = nil
        }
        if let editor = input.currentEditor() as? NSTextView { observeEditing(of: editor) }
        observeLifetime(of: parent)
        glideFromPill()
    }
    private func glideFromPill() {
        guard let anchor = sidebarAnchor, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor,
              input.stringValue.isEmpty, !isScoped, !scopeInvalidated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let pillIcon = anchor.subviews.first(where: { $0 is SidebarAddressSearchIcon && !$0.isHidden }) else { return }
        container.layoutSubtreeIfNeeded()
        let offsets = CommandBarCompactLayout.glideOffsets(
            pillIconX: container.convert(pillIcon.frame, from: anchor).minX,
            pillTextX: container.convert(NSPoint(x: SidebarAddressSearchIcon.textIndent, y: 0), from: anchor).x,
            iconX: inputIcon.frame.minX, inputX: input.frame.minX)
        Self.glide(inputIcon, from: offsets.icon)
        Self.glide(input, from: offsets.text)
    }
    private static func glide(_ view: NSView, from offset: CGFloat) {
        guard abs(offset) >= 0.5, let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = offset
        animation.toValue = 0
        animation.duration = CommandBarCompactLayout.glideDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "pillGlide")
    }
    func presentResident(in slot: NSView) {
        guard resident, !presented, !dismissed, let parent, slot.window == nil || slot.window === parent else { return }
        presented = true
        showsShadow = false
        container.flatFill = true
        host.frame = slot.bounds; host.autoresizingMask = [.width, .height]
        host.onGeometryChange = { [weak self] in self?.refreshPosition() }
        slot.addSubview(host, positioned: .above, relativeTo: nil)
        observeEditing(of: fieldEditor)
        observeLifetime(of: parent)
        refreshResults(requestNative: false)
        position(); layoutContents()
    }
    func focusResident() {
        guard resident, presented, !dismissed, let parent, host.window === parent,
              parent.isKeyWindow, parent.attachedSheet == nil else { return }
        guard holdsFirstResponder || parent.makeFirstResponder(input) else { return }
        applySelectionColor(); input.selectText(nil)
    }
    func resetResident() {
        guard resident, !dismissed else { return }
        let stopsNative = !editState.query.isEmpty || isScoped || scopeInvalidated
        retireScopeMenu()
        if isWebsiteScoped && !scopeInvalidated { _ = omnibox?.leaveScope() }
        if isWebsiteScoped || scopeInvalidated { clearScopeColor() }
        actionsScope = false; activeScope = nil; enteringScopeName = nil
        scopeInvalidated = false; unavailableScopeName = nil; queryBeforeScope = ""
        endNativeHold(); clearNativeResults()
        explicitSelectionID = nil; backgroundGeneration &+= 1; retainedBackgroundHistory = nil
        privacyBannerVisible = false
        editState.edit(""); deletingCharacters = false
        applyingCompletion = true
        input.stringValue = ""; previousInput = ""
        if let editor = input.currentEditor() as? NSTextView {
            editor.string = ""; editor.setSelectedRange(NSRange(location: 0, length: 0))
        }
        applyingCompletion = false
        if stopsNative { omnibox?.updateInput("", allowsInlineCompletion: false) }
        refreshResults(requestNative: false)
        position(); layoutContents()
    }
    private func releaseForAction() {
        guard resident, !dismissed else { return }
        residentRefocusPending = false
        if holdsFirstResponder, let parent { residentRefocusPending = parent.makeFirstResponder(nil) }
        resetResident()
    }
    private func refocusAfterAction() {
        guard residentRefocusPending, submissionDepth == 0 else { return }
        residentRefocusPending = false
        guard resident, presented, !dismissed, NSApp.isActive, let parent, parent.isKeyWindow, parent.isVisible,
              !parent.isMiniaturized, parent.attachedSheet == nil, parent.firstResponder === parent,
              isOwnerValid?() != false else { return }
        restorePageFocus?()
    }
    private func handOff(_ action: (() -> Void)?) {
        let valid = isOwnerValid
        respond(to: .submitted)
        if valid?() != false { action?() }
        refocusAfterAction()
    }
    private func respond(to event: CommandBarLifetime.Event) {
        switch CommandBarLifetime.response(to: event, resident: resident) {
        case .keep: break
        case .reposition: position()
        case .retireScopeMenu: retireScopeMenu()
        case .leaveScope: leaveScope()
        case .reset: resetResident()
        case .resetForAction: releaseForAction()
        case .dismiss: dismiss(restoreFocus: false)
        case .dismissRestoringFocus: dismiss()
        }
    }
    private func observeEditing(of editor: NSTextView) {
        if let storage = editor.textStorage {
            observe(NSTextStorage.didProcessEditingNotification, object: storage) { owner in
                guard !owner.applyingCompletion,
                      let storage = (owner.input.currentEditor() as? NSTextView)?.textStorage,
                      storage.editedMask.contains(.editedCharacters) else { return }
                owner.deletingCharacters = CommandBarEditState.deletesCharacters(
                    editedRange: storage.editedRange, changeInLength: storage.changeInLength)
            }
        }
        observe(NSTextView.didChangeSelectionNotification, object: editor) { owner in
            guard !owner.applyingCompletion else { return }
            if let projection = owner.editState.projection {
                owner.editState.stopAutomaticCompletion()
                owner.explicitSelectionID = projection.resultID
            }
            if (owner.input.currentEditor() as? NSTextView)?.string == owner.previousInput { owner.refreshScopeHint() }
            owner.fieldSelectionChanged()
        }
    }
    private func observeLifetime(of parent: NSWindow) {
        observe(NSWindow.didResignKeyNotification, object: parent) { $0.respond(to: .resignedKey(ownAlert: $0.ownsAttachedSheet)) }
        focusObservation = parent.observe(\.firstResponder) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.presented, !self.dismissed, !self.holdsFirstResponder else { return }
                    self.respond(to: .focusMoved)
                }
            }
        }
        observe(NSWindow.willCloseNotification, object: parent) { $0.respond(to: .closing) }
        observe(NSWindow.willMiniaturizeNotification, object: parent) { $0.respond(to: .miniaturizing) }
        observe(NSWindow.willBeginSheetNotification, object: parent) { $0.respond(to: .sheetBegan(ownAlert: $0.scopeAlert != nil)) }
        observe(Notification.Name("PCNativeWindowSecurityStateChanged"), object: parent) { $0.respond(to: .securityChanged) }
        observe(NSApplication.didResignActiveNotification, object: NSApp) { $0.respond(to: .appDeactivated) }
        observe(NSWindow.didResizeNotification, object: parent) { $0.respond(to: .resized) }
        observe(NSWindow.didMoveNotification, object: parent) { $0.respond(to: .moved) }
        observe(NSScroller.preferredScrollerStyleDidChangeNotification, object: nil) { $0.adoptScrollerStyle() }
    }
    private func adoptScrollerStyle() {
        guard !dismissed else { return }
        scroll.scrollerStyle = NSScroller.preferredScrollerStyle
        container.needsLayout = true
    }
    private func scrollDidTile() {
        guard !dismissed, !layingOutContents, scroll.scrollerReserve != headerScrollerReserve else { return }
        container.needsLayout = true
    }
    private var holdsFirstResponder: Bool {
        (parent?.firstResponder as? NSView)?.isDescendant(of: host) == true
    }
    var hasFocus: Bool { presented && !dismissed && parent?.isKeyWindow == true && holdsFirstResponder }
    var ownsAttachedSheet: Bool { scopeAlert.map { $0.panel === parent?.attachedSheet } ?? false }
    func contains(_ event: NSEvent) -> Bool {
        presented && !dismissed && event.window === parent
            && container.bounds.contains(container.convert(event.locationInWindow, from: nil))
    }
    func fieldEditor(for client: Any?) -> Any? {
        (client as? NSTextField) === input ? fieldEditor : nil
    }
    private func observe(_ name: Notification.Name, object: AnyObject?, action: @escaping @MainActor @Sendable (CommandBar) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        })
    }
    private func position() {
        guard let parent, host.window === parent else { return }
        applyAppearance()
        if resident {
            let slot = host.bounds
            let banner = showsPrivacyBanner
                ? privacyBanner.preferredHeight(forWidth: min(slot.width, CommandBarResidentLayout.maximumWidth)) : 0
            let height = CommandBarResidentLayout.height(expanded: residentExpanded, rows: results.count, banner: banner)
            let frame = host.backingAlignedRect(CommandBarResidentLayout.surfaceFrame(in: slot, height: height),
                                                options: .alignAllEdgesNearest)
            if container.frame != frame { container.frame = frame; container.needsLayout = true }
            syncShadow()
            return
        }
        let available = parent.screen?.visibleFrame ?? parent.frame
        if let anchor = sidebarAnchor, anchor.window === parent, !anchor.isHiddenOrHasHiddenAncestor {
            let anchorRect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let surface: NSRect
            if sidebarBrowsing {
                surface = CommandBarCompactLayout.restingFrame(anchor: anchorRect, sidebar: anchor.superview?.bounds.width ?? anchorRect.width,
                                                               screen: available)
            } else {
                let width = CommandBarCompactLayout.width(popup: popup, window: parent.frame, screen: available)
                let height = min(isScoped || scopeInvalidated ? compactScopeHeight : 309, available.height - 32)
                let lift = CommandBarCompactLayout.lift(anchorHeight: anchorRect.height)
                surface = NSRect(x: CommandBarCompactLayout.originX(anchor: anchorRect.minX, width: width, window: parent.frame, screen: available),
                                 y: CommandBarCompactLayout.originY(anchor: anchorRect, height: height, lift: lift, screen: available),
                                 width: width, height: height)
            }
            showsShadow = !sidebarBrowsing
            container.flatFill = sidebarBrowsing
            container.cornerRadius = sidebarBrowsing ? 7 : 12
            setSurfaceFrame(surface)
            input.placeholderString = sidebarBrowsing || isScoped ? "Search…" : "Search or Enter URL…"
            input.font = CommandBarTypography.label
            return
        }
        let width = addressOnly ? CommandBarCompactLayout.width(popup: popup, window: parent.frame, screen: available)
            : max(260, min(765, parent.frame.width - 48, available.width - 24))
        let baselineHeight = min(addressOnly ? 309 : 326, max(180, available.height - 32))
        let bannerHeight = showsPrivacyBanner ? privacyBanner.preferredHeight(forWidth: width) : 0
        let height = min((isScoped || scopeInvalidated ? compactScopeHeight : baselineHeight) + bannerHeight, available.height - 32)
        let x = min(max(parent.frame.midX - width / 2, available.minX + 12), available.maxX - width - 12)
        let top = addressOnly ? parent.frame.maxY - 48 : parent.frame.midY + baselineHeight / 2
        let y = min(max(top - height, available.minY + 16), available.maxY - height - 16)
        setSurfaceFrame(NSRect(x: x, y: y, width: width, height: height))
    }
    private func setSurfaceFrame(_ surface: NSRect) {
        guard let parent else { return }
        var frame = host.convert(parent.convertFromScreen(surface), from: nil)
        frame.origin.x = min(max(frame.minX, host.bounds.minX), host.bounds.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, host.bounds.minY), host.bounds.maxY - frame.height)
        frame = host.backingAlignedRect(frame, options: .alignAllEdgesNearest)
        if container.frame != frame { container.frame = frame; container.needsLayout = true }
        syncShadow()
    }
    private func syncShadow() {
        guard presented, !dismissed, showsShadow, host.window != nil else {
            shadowView.isHidden = true
            removeSplash()
            return
        }
        let bar = container.frame, m = CommandBarShadowView.margins
        shadowView.frame = NSRect(x: bar.minX - m.left, y: bar.minY - m.bottom,
                                  width: bar.width + m.left + m.right, height: bar.height + m.top + m.bottom)
        if shadowView.cornerRadius != container.cornerRadius { shadowView.cornerRadius = container.cornerRadius }
        shadowView.isHidden = false
        splashView?.frame = bar.insetBy(dx: -CommandBarSplashView.padding, dy: -CommandBarSplashView.padding)
    }
    var contentAppearance: NSAppearance? { didSet { applyAppearance() } }
    private func applyAppearance() {
        let inline = sidebarAnchor.map { $0.window === parent && !$0.isHiddenOrHasHiddenAncestor } ?? false
        let appearance = CommandBarPalette.panelAppearance(inlineEmpty: inline && sidebarBrowsing, resident: resident,
                                                           space: contentAppearance, window: parent?.appearance)
        if host.appearance != appearance { host.appearance = appearance }
    }
    private func applySelectionColor() {
        let attributes: [NSAttributedString.Key: Any] = [.backgroundColor: palette.inputSelection]
        fieldEditor.selectedTextAttributes = attributes
        (input.currentEditor() as? NSTextView)?.selectedTextAttributes = attributes
    }
    private func applyPalette() {
        input.textColor = palette.inputText
        inputIcon.contentTintColor = palette.inputIcon
        applySelectionColor()
        emptyLabel.textColor = CommandBarPalette.textSecondary
        scopePill.focusColor = scopeColor ?? palette.scopePill
        for row in 0..<table.numberOfRows {
            (table.rowView(atRow: row, makeIfNecessary: false) as? CommandResultRowView)?.selectedColor = selectedRowColor
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? CommandResultCell)?.selectedColor = selectedRowColor
        }
        updateScopeSplash()
    }
    private func updateScopeSplash() {
        let shows = isWebsiteScoped && scopeColor != nil
        guard shows != showsScopeSplash else { return }
        showsScopeSplash = shows
        removeSplash()
        guard presented, !dismissed, sidebarAnchor == nil, host.window != nil else { return }
        if shows, let color = scopeColor {
            let splash = NSHostingView(rootView: CommandBarSplashView(color: color, cornerRadius: container.cornerRadius,
                                                                      margin: CommandBarSplashView.padding))
            splash.setAccessibilityElement(false)
            splash.frame = container.frame.insetBy(dx: -CommandBarSplashView.padding, dy: -CommandBarSplashView.padding)
            host.addSubview(splash, positioned: .below, relativeTo: shadowView)
            splashView = splash
            DispatchQueue.main.asyncAfter(deadline: .now() + CommandBarSplashView.duration + 0.1) { [weak self, weak splash] in
                MainActor.assumeIsolated {
                    guard let self, let splash, self.splashView === splash else { return }
                    self.removeSplash()
                }
            }
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presented, !self.dismissed, self.host.window != nil else { return }
                CommandBarBounce.play(on: self.container.layer)
                if !self.shadowView.isHidden {
                    CommandBarBounce.play(on: self.shadowView.shadowLayer, about: self.shadowView.barCentreOffset)
                }
            }
        }
    }
    private func removeSplash() {
        splashView?.removeFromSuperview(); splashView = nil
    }
    private var layingOutContents = false
    private func layoutContents() {
        guard !layingOutContents else { return }
        layingOutContents = true
        defer { layoutScopeHeader(); layingOutContents = false }
        let width = container.bounds.width
        if sidebarAnchor != nil || addressOnly {
            typealias Compact = CommandBarCompactLayout
            let centre = sidebarBrowsing ? container.bounds.height / 2 : Compact.headerCentre
            inputIcon.frame = Compact.iconFrame(centre: centre)
            input.frame = Compact.inputFrame(width: width, centre: centre)
            divider.isHidden = true
            scroll.isHidden = sidebarBrowsing; emptyLabel.isHidden = sidebarBrowsing || !results.isEmpty
            scroll.frame = NSRect(x: Compact.listInset, y: 50, width: max(0, width - 2 * Compact.listInset),
                                  height: max(0, container.bounds.height - 59))
            emptyLabel.frame = NSRect(x: 16, y: 77, width: max(0, width - 32), height: 40)
            return
        }
        inputIcon.frame = NSRect(x: 22, y: 22, width: 18, height: 18)
        input.frame = NSRect(x: 49, y: 21, width: max(0, width - 71), height: 31)
        divider.frame = NSRect(x: 12, y: 64, width: max(0, width - 24), height: CommandBarHairline.height(in: parent))
        let bannerHeight = showsPrivacyBanner ? privacyBanner.preferredHeight(forWidth: width) : 0
        privacyBanner.isHidden = bannerHeight == 0
        privacyBanner.frame = NSRect(x: 0, y: container.bounds.height - bannerHeight, width: width, height: bannerHeight)
        scroll.frame = NSRect(x: 8, y: 68, width: max(0, width - 16), height: max(0, container.bounds.height - 76 - bannerHeight))
        emptyLabel.frame = NSRect(x: 24, y: resident ? 77 : 111, width: max(0, width - 48), height: 40)
    }
    func reconcile(tabs: [BrowserTab], history: [BrowserHistoryEntry], historyRevision: UInt64, historyExcludedURL: String?, spaces: [CommandBarSpaceAction], folders: [CommandBarFolderAction]) {
        guard !dismissed else { return }
        guard isOwnerValid?() != false else { respond(to: .ownerInvalid); return }
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
        self.tabs = tabs; self.spaces = spaces; self.folders = folders; tabTitleTokens = [:]
        refreshResults(requestNative: false)
    }
    func reconcileExtensionActions() {
        guard !dismissed else { return }
        guard isOwnerValid?() != false else { respond(to: .ownerInvalid); return }
        extensionLaunchSnapshotIsStale = true
        refreshResults(requestNative: false)
    }
    func dismiss(restoreFocus: Bool = true) {
        guard !dismissed else { return }
        let mayRestore = restoreFocus && presented && NSApp.isActive && parent?.isKeyWindow == true && isOwnerValid?() != false
        let heldFocus = holdsFirstResponder
        dismissed = true
        focusObservation = nil
        endNativeHold()
        retireScopeMenu()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); bindings = nil
        omnibox?.cancel(); omnibox = nil; nativeResults = []; extensionActions = []
        extensionLaunchSnapshot = []
        scopeOffers = []; activeScope = nil; enteringScopeName = nil; actionsScope = false
        removeSplash()
        if heldFocus, let parent {
            if mayRestore, parent.isVisible, !parent.isMiniaturized, parent.attachedSheet == nil {
                if !returnFocus(in: parent) { parent.makeFirstResponder(nil); restorePageFocus?() }
            } else if !returnFocus(in: parent) { parent.makeFirstResponder(nil) }
        }
        host.removeFromSuperview()
        onDismiss?()
        if submissionDepth == 0 { onDismissalSettled?() }
    }
    private func returnFocus(in parent: NSWindow) -> Bool {
        guard let view = originalResponder as? NSView, mayRestoreOriginal?(view) ?? true,
              SavedFocus.mayReturn(to: view, in: parent), parent.makeFirstResponder(view) else { return false }
        if let field = view as? NSTextField, let editor = field.currentEditor() as? NSTextView,
           let range = originalSelection, NSMaxRange(range) <= (editor.string as NSString).length { editor.setSelectedRange(range) }
        return true
    }
    func controlTextDidChange(_ obj: Notification) {
        addressWasEdited = true
        retireScopeMenu()
        backgroundGeneration &+= 1
        retainedBackgroundHistory = nil
        let edited = input.stringValue
        let previous = previousInput
        let deleted = deletingCharacters
        let editor = input.currentEditor() as? NSTextView
        editState.userEdit(edited, selection: editor?.selectedRange() ?? NSRange(location: NSNotFound, length: 0),
                           hasMarkedText: editor?.hasMarkedText() != false,
                           didBackspace: deleted)
        deletingCharacters = false
        previousInput = edited
        refreshCompletionField()
        if editor?.hasMarkedText() != true, !deleted, CommandBarScopeKeyboard.isTypedSpace(NSApp.currentEvent),
           let typed = CommandBarScopeKeyboard.typedBeforeSpace(previous: previous, edited: edited),
           let offer = selectedScopeOffer, spaceEnters(offer, typed: typed),
           enterScope(restoring: typed) { return }
        scopeInvalidated = false; unavailableScopeName = nil
        explicitSelectionID = nil
        refreshResults(holdsPresentation: true)
        refreshScopeHint()
    }
    private func spaceEnters(_ offer: PCNativeOmniboxScope, typed: String?) -> Bool {
        typed.map { CommandBarScopeKeyboard.spaceEnters(query: $0, keyword: offer.keyword, enabled: offer.spaceTriggerEnabled) } == true
    }
    private var typedBeforeSpace: String? {
        let editor = input.currentEditor() as? NSTextView
        let text = editor?.string ?? input.stringValue
        return CommandBarScopeKeyboard.typedBeforeSpace(text: text,
            selection: editor?.selectedRange() ?? NSRange(location: (text as NSString).length, length: 0))
    }
    private func refreshScopeHint() {
        guard !dismissed, !scopeOfferButton.isHidden,
              scopeHintOffersSpace != selectedScopeOffer.map({ spaceEnters($0, typed: typedBeforeSpace) }) else { return }
        layoutScopeHeader()
    }
    private func endNativeHold() {
        nativeHold.end()
        nativeHoldDeadline?.cancel(); nativeHoldDeadline = nil
    }
    private func clearNativeResults(keepingError: Bool = false) {
        nativeResults = []; extensionActions = []; scopeOffers = []
        if !keepingError { nativeError = nil }
        nativeHold.reset()
    }
    private func releaseNativeHold() {
        guard nativeHold.isHolding else { return }
        endNativeHold(); clearNativeResults(keepingError: true)
        refreshResults(requestNative: false)
    }
    private func refreshResults(requestNative: Bool = true, holdsPresentation: Bool = false) {
        guard !dismissed else { return }
        if explicitSelectionID == nil { adoptTitleIndex() }
        if extensionLaunchSnapshotIsStale {
            extensionLaunchSnapshot = extensionLaunchActions?() ?? []
            extensionLaunchSnapshotIsStale = false
        }
        let showsCurrentAddress = addressOnly && !addressWasEdited && !initialInput.isEmpty && !isScoped
        let query = showsCurrentAddress ? "" : isScoped ? editState.query : editState.query.trimmingCharacters(in: .whitespacesAndNewlines)
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
            omnibox?.updateInput(query, allowsInlineCompletion: !isScoped && query == editState.query && editState.allowsInlineCompletion)
        }
        if nativeHold.isHolding { return }
        if resident, CommandBarResidentLayout.rests(query: query, scoped: isScoped, scopeInvalidated: scopeInvalidated) {
            restResidentResults(); return
        }
        let fingerprint = openResultsFingerprint(query: query)
        if CommandBarOpenResultsSkip.shouldSkip(previous: lastOpenResultsFingerprint, next: fingerprint) {
            return
        }
        lastOpenResultsFingerprint = fingerprint
        resultPublication = UUID()
        let selectedContext = explicitSelectionID.flatMap { id in
            results.first { $0.id == id && ($0.spaceAction != nil || $0.folderAction != nil || $0.favoriteAction != nil || $0.folderMove != nil || $0.favoriteRename != nil || $0.typedCommand != nil || $0.extensionAction != nil || $0.extensionLaunch != nil) }
        }
        results = []
        if showsCurrentAddress, let url = URL(string: initialInput) {
            results.append(Result(id: "current-address", title: CommandBarResultText.historyTitle(pageTitle: currentPageTitle ?? "", url: initialInput),
                                  detail: "", symbol: "globe", url: url, input: initialInput))
        }
        if actionsScope {
            results = Array(commandResults(query: query, includesEmpty: true).prefix(100))
        } else if isWebsiteScoped {
            results = nativeResultRows(scoped: true)
        } else if !scopeInvalidated {
            if !query.isEmpty {
                results = rankedResults(query: query)
            } else {
                results += tabs.filter { $0.archivedAt == nil && (!addressOnly || Self.isAddressSuggestion($0.url)) }.prefix(8).map(tabResult)
            }
            if query.isEmpty {
                let tabURLs = tabs.map(\.url)
                let scanKey = CommandBarHistoryScanSkip.key(
                    query: query,
                    historyRevision: historyRevision,
                    excludedURL: historyExcludedURL,
                    tabURLs: tabURLs,
                    tabTitles: tabs.map { CommandBarResultText.tabTitle(customTitle: $0.customTitle, pageTitle: $0.title, url: $0.url) }
                )
                let visits: [CommandBarHistoryScanSkip.Visit]
                if CommandBarHistoryScanSkip.shouldReuse(previous: lastHistoryScanKey, next: scanKey) {
                    visits = cachedHistoryVisits
                } else {
                    visits = CommandBarHistoryScanSkip.emptyQueryVisits(
                        rankedURLsAndTitles: recentPages ?? rankedHistory.map { ($0.url, $0.title) },
                        tabURLs: Set(tabURLs + [historyExcludedURL].compactMap { $0 }),
                        tabPages: Set(tabs.filter { $0.archivedAt == nil }.compactMap {
                            CommandBarResultText.samePageKey(title: CommandBarResultText.tabTitle(customTitle: $0.customTitle,
                                                                                                 pageTitle: $0.title, url: $0.url), url: $0.url)
                        }),
                        samePage: CommandBarResultText.samePageKey,
                        limit: 8
                    )
                    lastHistoryScanKey = scanKey
                    cachedHistoryVisits = visits
                }
                let historyBudget = max(0, 8 - results.count)
                for visit in visits.prefix(historyBudget) {
                    guard let url = URL(string: visit.url) else { continue }
                    results.append(Result(id: "history:" + visit.url,
                                          title: CommandBarResultText.historyTitle(pageTitle: visit.title, url: visit.url),
                                          detail: "", symbol: "clock",
                                          subtitle: CommandBarResultText.pageSubtitle(title: visit.title, url: visit.url),
                                          url: url, input: visit.url))
                }
            }
        }
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
        if isScoped || scopeInvalidated || resident { position() }
        let previousIDs = presentedRows.map(\.id)
        let rows = results.map { CommandBarRowDiff.Row(id: $0.id, content: rowContent($0)) }
        let diff = CommandBarRowDiff(old: presentedRows, new: rows)
        presentedRows = rows
        selectingProgrammatically = true; table.apply(diff); selectingProgrammatically = false
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
    private func restResidentResults() {
        guard !CommandBarOpenResultsSkip.shouldSkip(previous: lastOpenResultsFingerprint,
                                                    next: CommandBarResidentLayout.restingToken) else { return }
        lastOpenResultsFingerprint = CommandBarResidentLayout.restingToken
        resultPublication = UUID()
        results = []; presentedRows = []; table.reloadData()
        selectingProgrammatically = true; table.deselectAll(nil); selectingProgrammatically = false
        clearCompletion(); emptyLabel.isHidden = true
        updateSelectionAppearance(); position(); layoutContents()
    }
    private func openResultsFingerprint(query: String) -> String {
        "\(addressOnly):\(addressWasEdited):" + CommandBarOpenResultsSkip.fingerprint(
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
            historyTokens: [CommandBarHistoryScanSkip.historyMembershipToken(revision: historyRevision,
                                                                             excludedURL: historyExcludedURL)]
                + (query.isEmpty ? ["recent-pages:\(recentPagesGeneration)"] : ["top-domains:\(topDomainGeneration)", "title-index:\(titleIndexGeneration):\(historyRemovals)"]),
            commandTokens: commands.map {
                CommandBarOpenResultsSkip.commandToken(id: $0.id, title: $0.title, group: $0.group)
            } + typedCommands.filter { canPerformTypedCommand?($0) == true }.map {
                CommandBarOpenResultsSkip.commandToken(id: $0.id, title: $0.title, group: "")
            },
            spaceTokens: spaces.map {
                CommandBarOpenResultsSkip.spaceToken(id: $0.id, name: $0.name,
                                                     position: $0.position,
                                                     needsPositionLabel: $0.needsPositionLabel)
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
        guard !addressOnly else { return [] }
        let passwords: [Result] = includesEmpty && (query.isEmpty || CommandBarScopeKeyboard.matchesPasswords(query: query))
            ? [Result(id: "passwords", title: "Manage Passwords", detail: "", symbol: "key", managesPasswords: true)] : []
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        let lowercasedQuery = query.lowercased()
        let matching = zip(commands, commandSearch).compactMap { command, search -> (command: KeyboardShortcuts.MenuCommand, title: String)? in
            if favoriteRename != nil && command.id == "renameCurrentItem:" { return nil }
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
            Result(id: "extension-launch:\($0.identifier):\($0.generation)",
                   title: $0.name, detail: "Extension", symbol: "puzzlepiece.extension",
                   extensionLaunch: $0)
        }
        let audioCommands: [Result] = onMuteAllTabs == nil ? [] : [true, false].compactMap { muted in
            let title = muted ? "Mute All Tabs" : "Unmute All Tabs"
            guard (query.isEmpty && includesEmpty) || (!query.isEmpty && words.allSatisfy({ title.lowercased().contains($0) })) else { return nil }
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
    private static func isAddressSuggestion(_ value: String) -> Bool {
        guard let scheme = URL(string: value)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "chrome", "about"].contains(scheme)
    }
    private func tabResult(_ tab: BrowserTab) -> Result {
        if addressOnly {
            return Result(id: "address:" + tab.id.uuidString,
                title: CommandBarResultText.tabTitle(customTitle: tab.customTitle, pageTitle: tab.title, url: tab.url),
                detail: "", symbol: "globe", url: URL(string: tab.url), input: tab.url)
        }
        return Result(id: "tab:" + tab.id.uuidString,
               title: CommandBarResultText.tabTitle(customTitle: tab.customTitle, pageTitle: tab.title, url: tab.url),
               detail: "", symbol: InternalPage.sidebarFallbackSymbol(urlString: tab.url), caption: caption(for: tab),
               url: URL(string: tab.url), tabID: tab.id)
    }
    private func rankedResults(query: String) -> [Result] {
        var pool: [Result] = []
        var candidates: [CommandBarRanking.Candidate] = []
        let titleQuery = titleMatchQuery(query), now = Date()
        var titled: [(index: Int, key: String, score: CommandBarTitleMatch.Score, keepsWeak: Bool)] = []
        func add(_ result: Result, _ candidate: CommandBarRanking.Candidate) {
            var candidate = candidate
            if !result.isSearch, let url = result.url {
                candidate.samePage = CommandBarResultText.samePageKey(title: result.title, url: url.absoluteString)
            }
            pool.append(result); candidates.append(candidate)
        }
        if !addressOnly && CommandBarScopeKeyboard.matchesPasswords(query: query) {
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
        let nativeRows = nativeResultRows(scoped: false)
        if nativeRows.isEmpty || explicitSelectionID == "query:" + query {
            add(Result(id: "query:" + query, title: query, detail: nativeError ?? "",
                       symbol: "magnifyingglass", subtitle: nativeError, isSearch: true, input: query),
                .init(archetype: .chromium, key: "query:" + query))
        }
        let lead = CommandBarRanking.siteLead(typed: query,
                                              defaultURL: nativeRows.first?.navigation.flatMap { $0.search ? nil : $0.url })
        for (rank, result) in nativeRows.enumerated() {
            let key = result.navigation.map { navigation in
                navigation.search
                    ? CommandBarRowDiff.searchKey(navigation.editText.isEmpty ? navigation.title : navigation.editText)
                    : CommandBarRanking.pageKey(navigation.url, title: navigation.title)
            } ?? result.id
            let urlKey = result.navigation.flatMap { $0.search ? nil : CommandBarRowDiff.pageKey($0.url) }
            var row = result
            if let lead, urlKey == lead.page { row.completionHost = lead.host }
            add(row, .init(archetype: .chromium, key: key, chromiumRank: rank, urlKey: urlKey))
        }
        for tab in tabs where tab.archivedAt == nil && (!addressOnly || Self.isAddressSuggestion(tab.url)) {
            let url = URL(string: tab.url)
            let key = InternalPage(urlString: tab.url).map {
                $0.noteID.map { "document:" + $0.uuidString.lowercased() } ?? "easel:" + ($0.easelID?.uuidString.lowercased() ?? "")
            } ?? url.map { CommandBarRanking.pageKey($0, title: tab.title) } ?? "tab:" + tab.id.uuidString
            let row = tabResult(tab)
            if let titleQuery, let score = CommandBarTitleMatch.score(titleQuery, titleTokens(for: tab, title: row.title), kind: .tab,
                                                                     lastUsed: tab.lastAccessed, visits: titleIndex?.visits(forKey: key) ?? 0, now: now) {
                titled.append((candidates.count, key, score, false))
            }
            add(row, .init(archetype: .tab, key: key, texts: [row.title, tab.title, url?.host ?? "", tab.url],
                           urlKey: url.map(CommandBarRowDiff.pageKey)))
        }
        if let titleQuery, let index = titleIndex {
            let hits = index.search(titleQuery, now: now, includesArchive: !addressOnly, hiddenPages: hiddenPages,
                                    excludingURLKey: historyExcludedURL.flatMap(URL.init(string:)).map(CommandBarRowDiff.pageKey))
            for hit in hits.archived {
                titled.append((candidates.count, hit.entry.key, hit.score, true))
                add(archivedResult(hit.entry, now: now), .init(archetype: .archived, key: hit.entry.key, urlKey: hit.entry.urlKey))
            }
            for hit in hits.pages {
                titled.append((candidates.count, hit.entry.key, hit.score, true))
                add(pageResult(hit.entry), .init(archetype: .history, key: hit.entry.key, urlKey: hit.entry.urlKey))
            }
        }
        for (entry, score) in zip(titled, CommandBarTitleMatch.resolve(titled.map { ($0.key, $0.score, $0.keepsWeak) })) {
            candidates[entry.index].titleScore = score
        }
        for document in (addressOnly ? [] : documents) {
            add(Result(id: document.key, title: document.title.isEmpty ? (document.kind == .note ? "Untitled Note" : "Untitled Easel") : document.title,
                       detail: document.kind == .note ? "Note" : "Easel",
                       symbol: (document.kind == .note ? InternalPage.note(document.id) : .easel(document.id)).sidebarFallbackSymbol,
                       document: document),
                .init(archetype: .document, key: document.key, texts: [document.title]))
        }
        for domain in topDomainList where CommandBarRanking.domainCompletion(typed: query, host: domain.host) != nil {
            add(Result(id: "top-domain:" + domain.host, title: domain.title.isEmpty ? domain.host : domain.title, detail: "",
                       symbol: "globe", subtitle: domain.title.isEmpty ? nil : CommandBarResultText.urlSubtitle(domain.url.absoluteString),
                       url: domain.url, input: domain.url.absoluteString, completionHost: domain.host),
                .init(archetype: .topDomain, key: CommandBarRowDiff.pageKey(domain.url), texts: [domain.host, "www." + domain.host],
                      urlKey: CommandBarRowDiff.pageKey(domain.url)))
        }
        return CommandBarRanking.rank(candidates, query: query, leadingPage: lead?.page).map { pool[$0] }
    }
    private func automaticCompletion(for result: Result) -> String? {
        guard let host = result.completionHost else { return result.navigation?.inlineCompletionText }
        return CommandBarRanking.domainCompletion(typed: editState.query, host: host)
    }
    private func selectedCompletion(for result: Result) -> String? {
        if let navigation = result.navigation { return navigation.editText.isEmpty ? nil : navigation.editText }
        return result.completionHost.flatMap { CommandBarRanking.domainCompletion(typed: editState.query, host: $0) }
    }
    func updateTypedCommands(_ list: [CommandBarTypedCommand]) {
        guard !dismissed, list != typedCommands else { return }
        typedCommands = list
        lastOpenResultsFingerprint = nil
        refreshResults(requestNative: false)
    }
    func updateTitleIndex(_ index: CommandBarTitleIndex?, historyRemovals: UInt64) {
        guard !dismissed else { return }
        let hidden = hiddenPages
        self.historyRemovals = historyRemovals
        var changed = false
        if let index, index !== titleIndex {
            pendingTitleIndex = index
            if explicitSelectionID == nil || titleIndex.map(index.withdrawsEntries(of:)) == true { adoptTitleIndex(); changed = true }
        }
        hidePagesRemovedSinceIndex()
        if (changed || hiddenPages != hidden) && !editState.query.isEmpty && !isScoped { refreshResults(requestNative: false) }
    }
    private func adoptTitleIndex() {
        guard let pending = pendingTitleIndex else { return }
        titleIndex = pending; pendingTitleIndex = nil; titleIndexGeneration += 1
        hidePagesRemovedSinceIndex()
    }
    private func hidePagesRemovedSinceIndex() {
        guard let index = titleIndex, index.historyRemovals != historyRemovals else { hiddenPages = []; return }
        hiddenPages = removedHistoryURLs?(index.historyRemovals) ?? nil
    }
    private func titleMatchQuery(_ query: String) -> CommandBarTitleQuery? {
        CommandBarTitleMatch.wordsQuery(query, nativeRowsAnswer: nativeHold.nativeRowsAnswer(query),
                                        defaultIsSearch: nativeResults.first?.search)
    }
    private func titleTokens(for tab: BrowserTab, title: String) -> CommandBarTitleTokens {
        if let tokens = tabTitleTokens[tab.id] { return tokens }
        let tokens = CommandBarTitleTokens(titles: [title, tab.title], host: URL(string: tab.url)?.host)
        tabTitleTokens[tab.id] = tokens
        return tokens
    }
    private func archivedResult(_ entry: CommandBarTitleIndex.Entry, now: Date) -> Result {
        Result(id: "archived:" + (entry.tabID?.uuidString ?? entry.url), title: entry.title, detail: "",
               symbol: InternalPage.sidebarFallbackSymbol(urlString: entry.url),
               caption: CommandBarTitleText.archivedCaption(archivedAt: entry.date, now: now),
               url: URL(string: entry.url), archivedTabID: entry.tabID)
    }
    private func pageResult(_ entry: CommandBarTitleIndex.Entry) -> Result {
        Result(id: "history:" + entry.url, title: entry.title, detail: "", symbol: "clock",
               subtitle: CommandBarResultText.pageSubtitle(title: entry.pageTitle, url: entry.url),
               url: URL(string: entry.url), input: entry.url)
    }
    func updateTopDomains(_ domains: [CommandBarRanking.Domain]) {
        guard !dismissed, domains != topDomainList else { return }
        topDomainList = domains; topDomainGeneration += 1
        if !editState.query.isEmpty && !isScoped { refreshResults(requestNative: false) }
    }
    func updateRecentPages(_ pages: [(url: String, title: String)]) {
        guard !dismissed, !pages.isEmpty || recentPages != nil else { return }
        recentPages = pages.isEmpty ? nil : pages; recentPagesGeneration += 1
        lastHistoryScanKey = nil; cachedHistoryVisits = []
        if (editState.query.isEmpty || (addressOnly && !addressWasEdited)) && !isScoped { refreshResults(requestNative: false) }
    }
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
        if scoped {
            return Result(id: id, title: navigation.title.isEmpty ? input.stringValue : navigation.title, detail: "",
                          symbol: "magnifyingglass", isSearch: true, url: navigation.url, navigation: navigation)
        }
        guard !WhatsNewPage.isBundledFile(navigation.url.absoluteString),
              let row = CommandBarResultText.nativeRow(matchType: Self.matchType(of: navigation), isSearch: navigation.search,
                                                      contents: navigation.title, description: navigation.detail,
                                                      url: navigation.url.absoluteString, input: nativeInput,
                                                      preserveDefault: preserveDefault) else { return nil }
        return Result(id: id, title: row.title, detail: "", symbol: row.symbol, subtitle: row.subtitle,
                      isSearch: row.isSearch, url: navigation.url, navigation: navigation)
    }
    private func caption(for tab: BrowserTab) -> CommandBarResultText.TabCaption {
        tabCaption?(tab) ?? .switchToTab
    }
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
        if result.archivedTabID != nil { return onRestoreArchived != nil }
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
              let text = selectedCompletion(for: results[table.selectedRow]) else { clearCompletion(); return }
        editState.project(resultID: results[table.selectedRow].id, text: text)
        applyCompletion(preserveEditorSelection: preserveEditorSelection)
    }
    private func projectDefaultCompletion() {
        guard explicitSelectionID == nil, !dismissed, parent?.isKeyWindow == true,
              isOwnerValid?() != false, omnibox?.canSubmit == true,
              !isScoped, !scopeInvalidated, table.selectedRow == 0,
              let result = results.first, let text = automaticCompletion(for: result),
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
        if preserveEditorSelection, input.stringValue == editState.displayedText { return }
        applyingCompletion = true
        defer { applyingCompletion = false }
        input.stringValue = editState.displayedText
        previousInput = input.stringValue
        if let editor = input.currentEditor() as? NSTextView {
            editor.string = input.stringValue
            editor.setSelectedRange(editState.selection)
            completionTouched = false
            if !anchorField() { editor.scrollRangeToVisible(editor.selectedRange()) }
        }
        refreshCompletionField()
    }
    private var activeFieldEditor: CommandFieldEditor? {
        (input.currentEditor() as? CommandFieldEditor).flatMap { $0.superview == nil ? nil : $0 }
    }
    @discardableResult private func anchorField() -> Bool {
        guard !dismissed, let editor = activeFieldEditor,
              let range = CommandBarFieldAnchor.visibleRange(
                text: editor.string, displayed: editState.displayedText, selection: editor.selectedRange(),
                completion: CommandBarFieldAnchor.completion(editState), hasMarkedText: editor.hasMarkedText(),
                touched: completionTouched) else { return false }
        editor.reveal(range)
        return true
    }
    private func fieldClipChanged(resized: Bool) {
        if resized { anchorField() }
        refreshCompletionField()
    }
    private func fieldSelectionChanged() {
        if let editor = activeFieldEditor, CommandBarFieldAnchor.leavesCompletion(
            selection: editor.selectedRange(), completion: CommandBarFieldAnchor.completion(editState)) {
            completionTouched = true
        }
        refreshCompletionField()
    }
    private func layoutCompletionField() {
        if input.frame.size != anchoredFieldSize {
            anchoredFieldSize = input.frame.size
            anchorField()
        }
        refreshCompletionField()
    }
    private func refreshCompletionField() {
        guard !dismissed else { return }
        let font = input.font ?? CommandBarTypography.field
        let editor = activeFieldEditor, end = editor?.textEnd
        let fades: Bool
        if let editor {
            fades = CommandBarFieldAnchor.fades(text: editor.string, textEnd: end, visibleEnd: editor.visibleEnd,
                                                padding: editor.trailingPadding)
        } else {
            let text = input.stringValue
            fades = CommandBarFieldAnchor.fades(
                text: text, textEnd: text.utf16.count > CommandBarFieldAnchor.measuredLength ? nil : input.singleLineWidth,
                visibleEnd: input.bounds.width, padding: 0)
        }
        input.setTrailingFade(fades, width: CommandBarFieldAnchor.fadeWidth(fieldWidth: input.bounds.width, fontSize: font.pointSize))
        if editState.query.isEmpty { spokenCompletionTitle = nil }
        let projected = editState.projection.flatMap { projection in results.first { $0.id == projection.resultID } }
        guard let editor, let end, let projected,
              CommandBarCompletionTitle.isInline(query: editState.query, text: editor.string, displayed: editState.displayedText,
                                                 selection: editor.selectedRange(), completion: CommandBarFieldAnchor.completion(editState),
                                                 hasMarkedText: editor.hasMarkedText()),
              let title = CommandBarCompletionTitle.text(title: projected.title, url: projected.url?.absoluteString,
                                                         isSearch: projected.isSearch, completion: editor.string) else {
            completionTitle.isHidden = true; return
        }
        let shown = CommandBarCompletionTitle.display(title)
        if completionTitle.font != font { completionTitle.font = font }
        if completionTitle.stringValue != shown { completionTitle.stringValue = shown }
        let natural = completionTitle.singleLineWidth
        let inset = max(0, (natural - (shown as NSString).size(withAttributes: [.font: font]).width) / 2)
        let gap = (" " as NSString).size(withAttributes: [.font: font]).width - inset
        guard let frame = CommandBarCompletionTitle.frame(textEnd: container.convert(NSPoint(x: end, y: 0), from: editor).x,
                                                          fieldEnd: input.frame.maxX, natural: natural, gap: gap,
                                                          minimum: font.pointSize * 4) else {
            completionTitle.isHidden = true; return
        }
        completionTitle.frame = NSRect(x: frame.x, y: input.frame.minY, width: frame.width, height: input.frame.height)
        completionTitle.spokenTitle = title
        completionTitle.isHidden = false
        let spoken = projected.id + "\u{0}" + title
        guard spokenCompletionTitle != spoken else { return }
        spokenCompletionTitle = spoken
        NSAccessibility.post(element: input, notification: .announcementRequested,
            userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.low.rawValue])
    }
    private func acceptCompletion() -> Bool {
        guard !dismissed, isOwnerValid?() != false,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        let scope: CommandBarScopeKeyboard.Scope = actionsScope ? .actions
            : isWebsiteScoped ? .website : scopeInvalidated ? .unavailable : .ordinary
        switch CommandBarScopeKeyboard.tab(query: editState.query, scope: scope) {
        case .enterActions: if !addressOnly { enterActionsScope(); return true }
        case .leaveScope: leaveScope(); return true
        case .complete: break
        }
        if nativeHold.presentsBeforeSubmitting(explicitSelection: explicitSelectionID != nil) { releaseNativeHold() }
        if selectedScopeOffer != nil { enterOfferedScope(); return true }
        if !isScoped, !scopeInvalidated, results.indices.contains(table.selectedRow),
           nativeHold.nativeRowsAnswer(editState.query.trimmingCharacters(in: .whitespacesAndNewlines)),
           results[table.selectedRow].navigation?.canCompleteWithTab == true {
            projectSelectedCompletion()
        }
        if editState.projection != nil {
            editState.accept(); applyCompletion()
        }
        parent?.makeFirstResponder(input)
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
        guard (isScoped || scopeInvalidated || !input.stringValue.isEmpty),
              results.indices.contains(table.selectedRow) else {
            inputIcon.image = sidebarAnchor != nil || addressOnly ? SidebarAddressSearchIcon.glyph
                : NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            return
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
                                     isTab: result.tabID != nil || result.archivedTabID != nil,
                                     icon: result.extensionLaunch?.icon ?? result.url.flatMap { icons[$0] } ?? Self.iconImage(result.symbol),
                                     spokenAccessory: result.caption?.spoken, spokenSubtitle: CommandBarResultText.spokenSubtitle(result.subtitle),
                                     enabled: enabled(result), spaceAction: result.spaceAction, folderAction: result.folderAction ?? result.folderMove?.folder,
                                     isAction: result.command != nil || result.spaceAction != nil || result.folderAction != nil
                                        || result.favoriteAction != nil || result.folderMove != nil || result.favoriteRename != nil
                                        || result.managesPasswords || result.muteAllTabs != nil)
        bind(cell, to: result)
        cell.toolTip = result.command?.id == "checkForUpdates:" ? result.command?.toolTip : nil
        cell.selectedColor = selectedRowColor
        cell.setSelected(row == table.selectedRow)
        return cell
    }
    private func accessoryText(_ result: Result) -> String {
        let shortcut = result.favoriteRename != nil
            ? KeyboardShortcuts.shared.activeShortcut(for: "renameCurrentItem:") : result.command?.shortcut
        return result.tabID != nil || result.archivedTabID != nil ? (result.caption ?? .switchToTab).text : shortcut?.display ?? ""
    }
    private func isDeletable(_ result: Result) -> Bool {
        if let navigation = result.navigation { return omnibox?.canDeleteResult(navigation) == true }
        if let action = result.extensionAction { return omnibox?.canDeleteExtensionAction(action) == true }
        return false
    }
    private func rowContent(_ result: Result) -> String {
        let context = result.spaceAction.map { "\($0.name)\u{1}\($0.symbol)" }
            ?? (result.folderAction ?? result.folderMove?.folder).map { "\($0.name)\u{1}\($0.detail)" } ?? ""
        return [result.title, result.subtitle ?? "", result.caption?.spoken ?? "", result.isSearch ? "search" : "",
                result.detail, result.symbol, accessoryText(result), result.url?.absoluteString ?? "",
                result.tabID == nil ? "" : "tab", enabled(result) ? "on" : "off", isDeletable(result) ? "delete" : "",
                result.extensionLaunch.map { "\($0.generation)" } ?? "", context].joined(separator: "\u{0}")
    }
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
            cell.onDelete = { [weak self] in self?.deleteSuggestion(navigation) ?? false }
        } else if let action = result.extensionAction, omnibox?.canDeleteExtensionAction(action) == true {
            cell.onDelete = { [weak self] in self?.deleteExtensionSuggestion(action) ?? false }
        } else if cell.onDelete != nil {
            cell.onDelete = nil
        }
        if result.input != nil && result.url == nil { cell.setAccessibilityHelp("Search or open address") }
        mark(cell, for: result)
        cell.onPress = { [weak self, weak cell] in
            guard let self, let cell, cell.window === self.parent,
                  !cell.isHiddenOrHasHiddenAncestor else { return false }
            return self.activateResult(result, publication: publication, disposition: .ordinary)
        }
    }
    private func mark(_ cell: CommandResultCell, for result: Result) {
        let url = result.url?.absoluteString ?? ""
        let query = result.isSearch || url.isEmpty || (addressOnly && !addressWasEdited) ? "" : editState.query
        func marks(_ text: String?) -> CommandResultCell.Marks {
            guard let text, !url.isEmpty else { return .init() }
            return .init(host: CommandBarResultText.hostRange(in: text, url: url),
                         matches: CommandBarResultText.matchRanges(in: text, query: query))
        }
        cell.setMarks(title: marks(result.title), subtitle: marks(result.subtitle))
    }
    private func deleteSuggestion(_ navigation: PCNativeSearchNavigation) -> Bool {
        guard !dismissed, parent?.isKeyWindow == true, isOwnerValid?() != false,
              !scopeInvalidated, (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              let row = results.firstIndex(where: { $0.navigation === navigation }),
              omnibox?.deleteResult(navigation) == true else { return false }
        backgroundGeneration &+= 1
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
        guard !dismissed, parent?.isKeyWindow == true, isOwnerValid?() != false,
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
            pageURL = result.url
        } else {
            return nil
        }
        guard let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              let host = pageURL.host else { return nil }
        return CommandBarSiteColor.scope(forPageHost: host, in: siteScopes) { Self.site(of: $0)?.host }
    }
    private static func site(of scope: PCNativeOmniboxScope) -> (template: String, host: String, prepopulated: Bool)? {
        guard scope.responds(to: #selector(getter: PCNativeOmniboxScope.searchHost)) else { return nil }
        return (scope.templateURL, scope.searchHost, scope.isPrepopulated)
    }
    private var selectedRowColor: NSColor { (isWebsiteScoped ? scopeColor : nil) ?? palette.selected }
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
    private func siteVisit(searchHost: String) -> URL? {
        func matches(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(searchHost) }
        let visit = historyExcludedURL.flatMap { matches($0) ? $0 : nil }
            ?? rankedHistory.first { matches($0.url) || matches($0.title) }?.url
        return visit.flatMap(URL.init(string:)).flatMap { ["https", "http"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
    }
    private func layoutScopeHeader() {
        let showsScope = isScoped || scopeInvalidated
        let displayedName = unavailableScopeName ?? scopedName
        scopePill.isHidden = !showsScope
        if actionsScope { scopePill.showActions() }
        else if activeScope?.isExtension == true { scopePill.showExtension(name: displayedName) }
        else { scopePill.showSite(name: displayedName, unavailable: scopeInvalidated) }
        scopePill.isEnabled = actionsScope || (activeScope != nil && !scopeInvalidated)
        input.placeholderString = isScoped ? "Search…" : (sidebarBrowsing ? "Search…" : "Search or Enter URL…")
        if (isWebsiteScoped && input.stringValue.isEmpty && results.isEmpty && nativeError == nil) || (resident && !residentExpanded) {
            emptyLabel.isHidden = true; scroll.isHidden = true; divider.isHidden = true
        } else {
            scroll.isHidden = sidebarBrowsing; divider.isHidden = sidebarAnchor != nil || addressOnly
        }
        if isScoped || scopeInvalidated {
            emptyLabel.frame = NSRect(x: 24, y: 77, width: max(0, container.bounds.width - 48), height: 40)
            if sidebarAnchor == nil && !addressOnly {
                scroll.frame.origin.y = 68
                scroll.frame.size.height = max(0, container.bounds.height - 76 - privacyBannerHeight)
            }
        }
        table.fit(in: scroll, rowCount: results.count)
        headerScrollerReserve = scroll.scrollerReserve
        let large = sidebarAnchor == nil && !addressOnly
        let baseX = large ? 49 : CommandBarCompactLayout.textX
        let right = (large ? 22 : CommandBarCompactLayout.trailing) + headerScrollerReserve
        let headerCentre = large ? 32 : CommandBarCompactLayout.headerCentre
        var left = baseX
        if showsScope {
            let size = scopePill.intrinsicContentSize
            let width = min(max(50, size.width), max(50, container.bounds.width * 0.4))
            scopePill.frame = NSRect(x: left, y: headerCentre - size.height / 2, width: width, height: size.height)
            left += width + 10
        }
        let offer = selectedScopeOffer
        scopeOfferButton.isHidden = offer == nil
        scopeHintOffersSpace = offer.map { spaceEnters($0, typed: typedBeforeSpace) } == true
        var trailing = right
        if let offer {
            let spaceEnters = scopeHintOffersSpace
            scopeOfferButton.show(site: offer.name, spaceTriggerEnabled: spaceEnters)
            scopeOfferButton.setAccessibilityLabel("Search \(offer.name)")
            scopeOfferButton.setAccessibilityHelp(spaceEnters ? "Press Space or Tab to enter this search scope." : "Press Tab to enter this search scope.")
            let size = scopeOfferButton.intrinsicContentSize
            let width = min(size.width, max(0, container.bounds.width * 0.45))
            scopeOfferButton.frame = NSRect(x: container.bounds.width - right - width,
                y: headerCentre - size.height / 2, width: width, height: size.height)
            trailing += width + 12
        }
        let showsPrivacyInfo = CommandBarSearchPrivacyPolicy.showsInfoAccessory(
            dismissed: privacyPolicy.hasBeenExplicitlyDismissed, bannerVisible: privacyBannerVisible,
            scoped: showsScope, offeringSiteSearch: offer != nil, hasResults: !results.isEmpty,
            sidebarSession: sidebarAnchor != nil || addressOnly)
        privacyInfoButton.isHidden = !showsPrivacyInfo
        if showsPrivacyInfo {
            privacyInfoButton.frame = NSRect(x: container.bounds.width - right - 24, y: 20, width: 24, height: 24)
            trailing += 24 + 12
        }
        input.frame.origin.x = left
        input.frame.size.width = max(24, container.bounds.width - left - trailing)
        layoutCompletionField()
    }
    private func setScopeInput(_ value: String, selectAll: Bool) {
        backgroundGeneration &+= 1
        retainedBackgroundHistory = nil
        editState.edit(value)
        input.stringValue = value
        previousInput = value
        parent?.makeFirstResponder(input)
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
        guard !addressOnly else { return }
        guard !dismissed, isOwnerValid?() != false, !isScoped, !scopeInvalidated,
              editState.query.isEmpty,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        retireScopeMenu()
        actionsScope = true
        endNativeHold(); clearNativeResults(); explicitSelectionID = nil
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
        guard isScoped || scopeInvalidated, !dismissed, isOwnerValid?() != false else { respond(to: .scopeExitFailed); return }
        retireScopeMenu()
        if actionsScope {
            actionsScope = false; explicitSelectionID = nil
            endNativeHold(); clearNativeResults()
            setScopeInput("", selectAll: !restoringQuery)
            refreshResults(); position(); layoutContents()
            announceScope("Actions search ended")
            return
        }
        if !scopeInvalidated, omnibox?.leaveScope() != true { respond(to: .scopeExitFailed); return }
        clearScopeColor()
        activeScope = nil; enteringScopeName = nil; endNativeHold(); clearNativeResults()
        scopeInvalidated = false; unavailableScopeName = nil; explicitSelectionID = nil; nativeError = nil
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
            if let owner = alert.panel.sheetParent { owner.endSheet(alert.panel, returnCode: .cancel) }
            alert.panel.orderOut(nil)
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
                self.refreshScopeColor(for: choice)
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
            self.handOff(self.onManageSiteSearch)
        }
        manage.isEnabled = lease.canManage && onManageSiteSearch != nil; menu.addItem(manage)
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Learn More") { [weak self] in
            guard let self, self.scopeMenuIsCurrent(lease) else { return }
            let alert = ParcDialog(.init(title: "Site Search", message: "Type a site's search shortcut, then press Tab to search that site. Space also enters when enabled in your search settings. Use Change Site Search to keep your query and search another site. Removing a site search deletes its saved shortcut from this Space; you can add it again in Manage. Press Escape to return to your original address.", confirm: "Done"))
            self.presentScopeAlert(alert, lease: lease) { _ in }
        })
        scopeMenu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: scopePill.bounds.maxY), in: scopePill)
        if scopeMenu === menu { scopeMenu = nil }
        if !dismissed, scopeAlert == nil, scopeMenuIsCurrent(lease) {
            parent?.makeFirstResponder(input)
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
    private func presentScopeAlert(_ alert: ParcDialog, lease: PCNativeOmniboxScopeMenu,
                                   completion: @escaping (ParcDialog.Response) -> Void) {
        guard scopeMenuIsCurrent(lease), let window = parent, window.attachedSheet == nil, scopeAlert == nil else { return }
        scopeAlert = alert
        _ = alert.begin(for: window) { [weak self, weak alert] response in
            guard let self, let alert, self.scopeAlert === alert else { return }
            let current = self.scopeMenuIsCurrent(lease)
            self.scopeAlert = nil
            guard current else { return }
            self.parent?.makeFirstResponder(self.input)
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
            let alert = ParcDialog(.init(title: "Remove “\(lease.activeScope.name)” Site Search?",
                message: "This removes the saved search shortcut from this Space.", confirm: "Remove", cancel: "Cancel"))
            presentScopeAlert(alert, lease: lease) { [weak self] response in
                if response == .confirm { remove(true) }
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
        guard resultPublication == publication, !dismissed, parent?.isKeyWindow == true,
              isOwnerValid?() != false, !scopeInvalidated, !sidebarBrowsing,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              enabled(result) else { return false }
        submitResult(result, disposition: disposition, retainsSelection: false)
        return true
    }
    private func submitSelection(_ disposition: CommandBarSubmission) {
        guard !dismissed, isOwnerValid?() != false else { respond(to: .ownerInvalid); return }
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
        if result.document != nil, disposition != .ordinary { NSSound.beep(); return }
        submissionDepth += 1
        defer {
            submissionDepth -= 1
            if dismissed && submissionDepth == 0 { onDismissalSettled?() }
            refocusAfterAction()
        }
        if let action = result.extensionLaunch {
            guard disposition == .ordinary, !dismissed, parent?.isKeyWindow == true,
                  isOwnerValid?() != false,
                  (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
                NSSound.beep(); return
            }
            let launch = onLaunchExtension, stillValid = isOwnerValid
            respond(to: .submitted)
            if stillValid?() == false || launch?(action) != true { NSSound.beep() }
            return
        }
        if let id = result.archivedTabID {
            guard disposition == .ordinary, !dismissed, isOwnerValid?() != false else { NSSound.beep(); return }
            let restore = onRestoreArchived, stillValid = isOwnerValid
            respond(to: .submitted)
            if stillValid?() == false || restore?(id) != true { NSSound.beep() }
            return
        }
        if let action = result.extensionAction {
            guard let extensionDisposition, !inSplit, !dismissed, parent?.isKeyWindow == true,
                  isOwnerValid?() != false,
                  (input.currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  omnibox?.executeExtensionAction(action, disposition: disposition == .background ? .newBackgroundTab : extensionDisposition) == true else {
                NSSound.beep(); return
            }
            if disposition == .background {
                extensionActions = []; explicitSelectionID = nil
                refreshResults(requestNative: false)
                announceScope("Request sent to \(action.detail)")
            } else { respond(to: .submitted) }
            return
        }
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
            guard result.navigation != nil || result.input != nil || result.tabID != nil || splitCommand != nil,
                  splitCommand != nil || canSplitSelection?(result.tabID) == true else { NSSound.beep(); return }
            let canCommit = splitCommand != nil ? onSplitCommand != nil
                : result.navigation != nil ? onSplitNavigation != nil
                : result.tabID != nil ? onSplitTab != nil
                : onSplitInput != nil
            guard canCommit else { NSSound.beep(); return }
        }
        let navigate = onNavigate, search = onSearchNavigation, selectTab = onSelectTab
        let splitInput = onSplitInput, splitNavigation = onSplitNavigation, splitTab = onSplitTab
        let splitCommandHandler = onSplitCommand
        let managePasswords = onManagePasswords, focusSpace = onFocusSpace, openFolder = onOpenFolder
        let openDocument = onOpenDocument
        let muteAllTabs = onMuteAllTabs, performTyped = onPerformTypedCommand
        let performFavorite = onPerformFavorite, moveToFolder = onMoveToFolder, renameFavorite = onRenameFavorite, copyToFolder = onCopyToFolder
        let stillValid = isOwnerValid, rejectDestination = onRejectedDestination
        let isDestination = result.navigation != nil || result.tabID != nil || result.input != nil || result.document != nil || splitCommand != nil
        let typed = editState.query
        if isDestination { onWillSubmitDestination?() }
        respond(to: .submitted)
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
            else if let input = result.input { splitInput?(input, typed) }
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
        else if let command = result.command { if !KeyboardShortcuts.shared.performMenuCommand(command) { NSSound.beep() } }
        else if let id = result.tabID { selectTab?(id) }
        else if result.managesPasswords { managePasswords?() }
        else if let document = result.document { openDocument?(document) }
        else if let input = result.input { navigate?(input, typed) }
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
            guard let self, !self.dismissed, self.parent?.isKeyWindow == true,
                  self.backgroundOperation == operation, self.backgroundGeneration == generation, self.isOwnerValid?() != false,
                  self.omnibox?.canSubmit == true, self.editState.query == query,
                  self.activeScope === scope, !self.scopeInvalidated else { return false }
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
        else if let id = result.tabID, let open = onBackgroundTab { open(id, query, valid, completed) }
        else if let input = result.input, let open = onBackgroundInput { open(input, query, valid, completed) }
        else { completed("This result cannot open in the background.") }
    }
    private func handleBackgroundReturn(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, [36, 76].contains(event.keyCode),
              CommandBarSubmission.resolve(event.modifierFlags) == .background,
              (input.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        submitSelection(.background); return true
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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
            respond(to: .escape(scoped: isScoped || scopeInvalidated))
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
            respond(to: .escape(scoped: isScoped || scopeInvalidated))
            return true
        case 125: moveSelection(1); return true
        case 126: moveSelection(-1); return true
        default: return false
        }
    }
}

private final class CommandFieldEditor: CommandBarAnchoredEditor {
    var onCopy: ((String) -> Void)?
    private let undo = UndoManager()
    override var undoManager: UndoManager? { undo }
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
private final class CommandBarHost: NSView {
    weak var bar: NSView?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onGeometryChange: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        bar?.hitTest(convert(point, from: superview))
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize); onGeometryChange?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); onGeometryChange?()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyEquivalent?(event) == true || super.performKeyEquivalent(with: event)
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}
