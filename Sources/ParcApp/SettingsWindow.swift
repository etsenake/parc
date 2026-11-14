import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    private let focusState = SettingsFocusState()
    private var sheetFocusContext: String?
    private var lifecycleRevision: UInt64 = 0
    private var isClosing = false
    private let store: BrowserStore
    var onSheetEnded: (() -> Void)?
    let contextSpaceID: UUID?
    private let applicationProfileID: UUID?
    private let engine = PointingHandPopUpButton()
    private let searchSuggestions = PointingHandSwitch()
    private let sharedNote = NSTextField(labelWithString: "")
    private var searchNote = "" {
        didSet { engine.toolTip = searchNote.isEmpty ? nil : searchNote; engine.setAccessibilityHelp(engine.toolTip) }
    }
    private var searchPreferences: PCNativeSearchPreferences?
    private var searchGeneration: UInt64 = 0
    private var searchSubscription: AnyCancellable?
    @MainActor
    private final class SearchChoice: NSObject {
        let identifier: String
        let preferences: PCNativeSearchPreferences
        init(_ engine: PCNativeSearchEngine, _ preferences: PCNativeSearchPreferences) {
            identifier = engine.identifier; self.preferences = preferences
        }
    }
    private let archive = PointingHandPopUpButton()
    private let archiveInfo = PointingHandButton()
    private var archiveInfoPopover: NSPopover?
    private let restore = PointingHandSwitch()
    private let warnBeforeQuitting = PointingHandSwitch()
    private var defaultBrowserSubscription: AnyCancellable?
    private var quitWarningSubscription: AnyCancellable?
    private var windowDraggingSubscription: AnyCancellable?
    private let windowDragging = PointingHandSwitch()
    private var feedbackSubscription: AnyCancellable?
    private let soundEffects = PointingHandSwitch()
    private let reorderingHaptics = PointingHandSwitch()
    private var sharedQuoteSubscription: AnyCancellable?
    private let sharedQuotes = PointingHandSwitch()
    private var websiteThemeSubscription: AnyCancellable?
    private let websiteTheme = PointingHandSwitch()
    private var toolbarSubscription: AnyCancellable?
    private let toolbarFullURL = PointingHandSwitch()
    enum Pane: String, CaseIterable {
        static func named(_ name: String?) -> Pane? { name == "Profiles" ? .spaces : name.flatMap(Pane.init(rawValue:)) }
        case membership = "Membership", general = "General", spaces = "Spaces", links = "Links", shortcuts = "Shortcuts", icon = "Icon", advanced = "Advanced"
        var symbol: String {
            switch self { case .membership: return "person.crop.square.filled.and.at.rectangle"; case .general: return "gearshape"; case .spaces: return "square.stack"; case .shortcuts: return "keyboard"; case .icon: return "app"; case .links: return "macwindow.on.rectangle"; case .advanced: return "slider.horizontal.3" }
        }
    }
    enum Destination: Equatable {
        case pane(Pane), space(UUID)
        var pane: Pane { if case .pane(let pane) = self { return pane }; return .spaces }
    }
    private static let backItem = NSToolbarItem.Identifier("Parc.Settings.Back")
    private static let forwardItem = NSToolbarItem.Identifier("Parc.Settings.Forward")
    private static let titleItem = NSToolbarItem.Identifier("Parc.Settings.Title")
    private let titleLabel = NSTextField(labelWithString: "")
    private let membershipPane: MembershipCardSettingsView
    private let shortcutsPane = ShortcutsSettingsView(shortcuts: .shared)
    private let iconPane = IconSettingsView(icons: .shared)
    private let sidebar = SettingsSidebarController(panes: Pane.allCases)
    private var selectedPane = Pane.general
    private var shownDestination: Destination?
    private var navigation = SettingsNavigation<Destination>()
    private let paneHost = SettingsPaneHost(frame: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsLayout.contentHeight))
    private var panes: [Pane: NSScrollView] = [:]
    private var spaceEditor = NSScrollView()
    private let spaceList = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: 0, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight))
    private var spaceRows: [UUID: SettingsSpaceButton] = [:]
    private struct SpaceRowState: Equatable { let id: UUID; let name: String; let symbol: String; let emoji: String? }
    private var renderedSpaceRows: [SpaceRowState] = []
    private let newSpace = SettingsPillButton(title: "New Space…")
    private var selectedSpaceID: UUID?
    private let spaceNameValue = NSTextField(labelWithString: "")
    private let renameSpace = SettingsPillButton(title: "Rename…")
    private var spaceNameDialog: (dialog: PArcDialog, spaceID: UUID)?
    private var previewSettingsSheet: SidebarPreviewSettingsSheet?
    private let deleteSpace = SettingsPillButton(title: "Delete Space…")
    private let shareData = PointingHandPopUpButton(frame: .zero, pullsDown: true)
    private var shareChoices: [SpaceDataSharing] = []
    private let removalNote = NSTextField(labelWithString: "Removing old data…")
    private let removalRetry = SettingsPillButton(title: "Retry")
    private let removalRow = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: 0, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight))
    private var removalSubscription: AnyCancellable?
    private var membershipSubscription: AnyCancellable?

    private let downloadLocationPicker = DownloadLocationPicker()
    private let downloadHelp = NSTextField(wrappingLabelWithString: "")
    private var profilePageButtons: [ProfileSettingsPage: NSButton] = [:]
    var onProfileSettingsPage: ((UUID, UUID, ProfileSettingsPage) -> Bool)?
    var onDeleteSpace: ((UUID) -> Bool)?
    private let moreSettings = SettingsPillButton(title: "More Settings…")
    private let exportData = SettingsPillButton(title: "Export Data")
    private let replay = SettingsPillButton(title: "Replay onboarding")
    private let adjustWindowFrame = SettingsPillButton(title: "Adjust")
    private let windowFrameValue = NSTextField(labelWithString: "")
    private var windowFrameSubscription: AnyCancellable?
    private var dataExportPanel: NSSavePanel?
    private var dataExportID: UUID?
    var onMoreSettings: ((UUID, UUID) -> Bool)?
    private var loadedPreferencesProfileID: UUID?
    private var downloadPreferences: PCNativeDownloadPreferences?
    private var downloadFolderPanel: NSOpenPanel?
    private var downloadPreferencesGeneration: UInt64 = 0
    private let downloadRetry = PointingHandButton(title: "Retry", target: nil, action: nil)
    private var subscription: AnyCancellable?
    private struct Snapshot: Equatable {
        let settings: BrowserSettings
        let profiles: [BrowserProfile]
        let spaces: [BrowserSpace]
    }

    init(store: BrowserStore, spaceID: UUID?, applicationProfileID: UUID? = nil) {
        precondition(!store.isEphemeral, "Application Settings requires the normal store")
        self.store = store
        membershipPane = MembershipCardSettingsView(cards: .shared(directory: store.directory, name: NSFullUserName()))
        contextSpaceID = spaceID
        self.applicationProfileID = applicationProfileID
        let savedProfileID = store.state.settings.settingsProfileID
        selectedSpaceID = store.state.spaces.first { $0.id == spaceID }?.id
            ?? store.state.spaces.first { $0.profileID == applicationProfileID }?.id
            ?? store.state.spaces.first { $0.profileID == savedProfileID }?.id
            ?? store.state.spaces.first?.id
        let width = SettingsLayout.sidebarWidth + SettingsLayout.contentWidth
        let window = SettingsNativeWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: SettingsLayout.contentHeight),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Pane.general.rawValue
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        super.init(window: window)
        window.delegate = self
        configureControls()
        let frame = NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsLayout.contentHeight)
        let membershipScroll = NSScrollView(frame: frame)
        membershipScroll.drawsBackground = false; membershipScroll.hasVerticalScroller = true
        membershipScroll.autohidesScrollers = true; membershipScroll.documentView = membershipPane
        panes[.membership] = membershipScroll
        membershipPane.onNameChanged = { [weak self] _ in self?.refreshMembershipTitle() }
        membershipPane.onMakeDefault = { [weak self] in self?.makeDefaultBrowser() }
        membershipSubscription = membershipPane.cards.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshMembershipTitle()
        }
        panes[.general] = makeGeneralPane()
        panes[.spaces] = makeSpacesPane()
        spaceEditor = makeSpaceEditorPane()
        panes[.advanced] = makeAdvancedPane()
        let shortcutScroll = NSScrollView(frame: frame)
        shortcutScroll.drawsBackground = false; shortcutScroll.documentView = shortcutsPane
        panes[.shortcuts] = shortcutScroll
        let iconScroll = NSScrollView(frame: frame)
        iconScroll.drawsBackground = false; iconScroll.hasVerticalScroller = true
        iconScroll.autohidesScrollers = true; iconScroll.documentView = iconPane
        panes[.icon] = iconScroll
        let linksScroll = NSScrollView(frame: frame)
        linksScroll.drawsBackground = false
        linksScroll.documentView = LinksSettingsView(store: store)
        panes[.links] = linksScroll
        let split = SettingsSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = SettingsLayout.sidebarWidth
        sidebarItem.maximumThickness = SettingsLayout.sidebarWidth
        sidebarItem.titlebarSeparatorStyle = .none
        let contentController = NSViewController()
        contentController.view = paneHost
        let contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = SettingsLayout.contentWidth
        contentItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        split.view.frame = NSRect(x: 0, y: 0, width: width, height: SettingsLayout.contentHeight)
        window.contentViewController = split
        window.initialFirstResponder = sidebar.table
        sidebar.onSelect = { [weak self] pane in self?.selectFromSidebar(pane) }
        let toolbar = NSToolbar(identifier: "Parc.Settings.Navigation")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        let chrome = max(0, window.frame.height - window.contentLayoutRect.height)
        window.setContentSize(NSSize(width: width, height: SettingsLayout.contentHeight + chrome))
        refreshMembershipTitle()
        showPane(store.state.settings.settingsPane.flatMap { Pane.named($0) } ?? .membership, persist: false)
        subscription = store.statePublisher.map { state in
            Snapshot(settings: state.settings, profiles: state.profiles, spaces: state.spaces)
        }.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] snapshot in
            guard let self else { return }
            self.refresh()
        }
        searchSubscription = NotificationCenter.default.publisher(for: Notification.Name("PCNativeSearchPreferencesDidChange"))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshSearchPreferences() }
        removalSubscription = ProfileRemovalController.shared.$revision.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refresh()
        }
        toolbarSubscription = BrowserToolbarPreferences.shared.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshToolbarPreferences()
        }
        refreshToolbarPreferences()
        windowDraggingSubscription = WebpageWindowDraggingPreferences.shared.$state.sink { [weak self] state in
            self?.refreshWindowDragging(state)
        }
        feedbackSubscription = InterfaceFeedbackPreferences.shared.$state.sink { [weak self] state in
            self?.refreshFeedbackPreferences(state)
        }
        refresh()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureControls() {
        defaultBrowserSubscription = DefaultBrowserController.shared.$state.sink { [weak self] state in
            self?.refreshDefaultBrowser(state)
        }
        engine.target = self; engine.action = #selector(searchEngineChanged)
        engine.menu?.autoenablesItems = false
        engine.setAccessibilityLabel("Search engine")
        searchSuggestions.target = self; searchSuggestions.action = #selector(searchSuggestionsChanged)
        archive.target = self; archive.action = #selector(archiveChanged)
        archive.menu?.autoenablesItems = false
        archive.setAccessibilityLabel("Auto-archive inactive Today tabs after")
        archiveInfo.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Learn more about auto-archiving")
        archiveInfo.isBordered = false
        archiveInfo.toolTip = "Learn more about auto-archiving"
        archiveInfo.target = self; archiveInfo.action = #selector(showArchiveInformation)
        restore.target = self; restore.action = #selector(restoreChanged)
        warnBeforeQuitting.target = self; warnBeforeQuitting.action = #selector(quitWarningChanged)
        quitWarningSubscription = QuitWarningPreferences.shared.$state.sink { [weak self] state in
            self?.refreshQuitWarning(state)
        }
        toolbarFullURL.target = self; toolbarFullURL.action = #selector(toolbarFullURLChanged)
        sharedQuotes.target = self; sharedQuotes.action = #selector(sharedQuotesChanged)
        sharedQuoteSubscription = SharedQuotePreferences.shared.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshSharedQuotes()
        }
        refreshSharedQuotes()
        websiteTheme.target = self; websiteTheme.action = #selector(websiteThemeChanged)
        websiteThemeSubscription = WebsiteThemePreferences.shared.$state.sink { [weak self] state in
            self?.refreshWebsiteTheme(state)
        }
        windowDragging.target = self; windowDragging.action = #selector(windowDraggingChanged)
        soundEffects.target = self; soundEffects.action = #selector(soundEffectsChanged)
        reorderingHaptics.target = self; reorderingHaptics.action = #selector(reorderingHapticsChanged)
        for toggle in [windowDragging, soundEffects, reorderingHaptics, sharedQuotes, websiteTheme, toolbarFullURL, searchSuggestions, restore, warnBeforeQuitting] {
            toggle.controlSize = .small
        }
        downloadLocationPicker.onChoose = { [weak self] choice in self?.downloadLocationChosen(choice) }
        downloadRetry.target = self; downloadRetry.action = #selector(retryDownloadPreferences)
        downloadRetry.bezelStyle = .rounded; downloadRetry.isHidden = true
        moreSettings.target = self; moreSettings.action = #selector(openMoreSettings)
        exportData.target = self; exportData.action = #selector(exportBrowserData)
        replay.target = self; replay.action = #selector(replayWelcome)
        adjustWindowFrame.target = self; adjustWindowFrame.action = #selector(adjustWindowFrameSelected)
        adjustWindowFrame.setAccessibilityLabel("Adjust window frame")
        windowFrameSubscription = WindowFramePreferences.shared.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.refreshWindowFrame(state)
        }
        exportData.setAccessibilityHelp("Export your Spaces and saved tab links as Markdown.")
        moreSettings.setAccessibilityHelp(applicationProfileID == nil ? "Open browser settings for this window’s Space." : "Open browser settings for the original Space.")
        deleteSpace.destructive = true
        deleteSpace.setAccessibilityLabel("Delete Space")
        deleteSpace.target = self; deleteSpace.action = #selector(deleteSelectedSpace)
        renameSpace.toolTip = "Rename Space"
        renameSpace.setAccessibilityLabel("Rename Space")
        renameSpace.target = self; renameSpace.action = #selector(renameSelectedSpace)
        newSpace.target = self; newSpace.action = #selector(addSpace)
        newSpace.setAccessibilityLabel("New Space")
        newSpace.toolTip = "Create a Space"
        spaceNameValue.font = .systemFont(ofSize: 13); spaceNameValue.textColor = .secondaryLabelColor
        spaceNameValue.alignment = .right; spaceNameValue.lineBreakMode = .byTruncatingTail
        shareData.setAccessibilityLabel("Share data with")
        shareData.menu?.autoenablesItems = false
        removalNote.font = .systemFont(ofSize: 13); removalNote.textColor = .secondaryLabelColor
        removalRetry.target = self; removalRetry.action = #selector(retryRemoval)
        removalRetry.setAccessibilityLabel("Retry removing old data")
        for field in [downloadHelp, sharedNote] {
            field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor
        }
        sharedNote.lineBreakMode = .byTruncatingTail
    }
    @objc private func deleteSelectedSpace() { showSpaceDeletion() }
    @objc private func renameSelectedSpace() { showSpaceNameEditor() }
    @objc private func addSpace() { createSpace() }
    @objc private func retryRemoval() { retryPendingRemovals() }

    private func pane(height: CGFloat = SettingsLayout.contentHeight) -> (NSScrollView, LayoutView) {
        let content = LayoutView(frame: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: height))
        content.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: SettingsLayout.contentWidth, height: SettingsLayout.contentHeight))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.documentView = content
        return (scroll, content)
    }

    @discardableResult
    private func label(_ text: String, in parent: NSView, _ frame: NSRect, help: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: help ? 11 : 13)
        field.textColor = help ? .secondaryLabelColor : .labelColor
        field.frame = frame; parent.addSubview(field)
        return field
    }

    private func group(in parent: NSView, x: CGFloat = SettingsLayout.margin, y: CGFloat,
                       width: CGFloat = SettingsLayout.groupWidth, height: CGFloat) -> SettingsGroupView {
        let group = SettingsGroupView(frame: NSRect(x: x, y: y, width: width, height: height))
        parent.addSubview(group); return group
    }

    private func place(_ control: NSView, in parent: NSView, _ frame: NSRect) {
        if control is ActionButton { control.focusRingType = .exterior }
        control.frame = frame; parent.addSubview(control)
    }

    @discardableResult
    private func heading(_ title: String, in parent: NSView, above groupY: CGFloat) -> NSTextField {
        let field = SettingsSectionHeading(title: title)
        field.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset,
                             y: groupY - SettingsLayout.headingGap - SettingsLayout.headingHeight,
                             width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: SettingsLayout.headingHeight)
        parent.addSubview(field)
        return field
    }

    private func rowLabel(_ text: String, in group: NSView, row: Int, width: CGFloat = 360) {
        label(text, in: group, NSRect(x: SettingsLayout.rowInset, y: CGFloat(row) * SettingsLayout.rowHeight + 12, width: width, height: 18))
    }

    private func trailing(_ control: NSView, in group: NSView, top: CGFloat, rowHeight: CGFloat = SettingsLayout.rowHeight,
                          width: CGFloat, height: CGFloat) {
        place(control, in: group, NSRect(x: group.bounds.width - SettingsLayout.rowInset - width,
                                         y: top + ((rowHeight - height) / 2).rounded(), width: width, height: height))
    }

    private func trailingSwitch(_ toggle: NSSwitch, in group: NSView, top: CGFloat, rowHeight: CGFloat = SettingsLayout.rowHeight) {
        trailing(toggle, in: group, top: top, rowHeight: rowHeight, width: 38, height: 22)
    }

    private func trailingPill(_ button: SettingsPillButton, in group: NSView, top: CGFloat, rowHeight: CGFloat = SettingsLayout.rowHeight) {
        trailing(button, in: group, top: top, rowHeight: rowHeight, width: button.fittingWidth, height: SettingsLayout.buttonHeight)
    }

    private func refreshMembershipTitle() {
        if selectedPane == .membership { window?.title = membershipPane.displayName }
        let colors = membershipPane.cards.state.map { MembershipCardState.palettes[$0.palette].map(MembershipCardArtwork.color) } ?? []
        sidebar.updateMembership(name: membershipPane.displayName, colors: colors)
    }

    private func makeGeneralPane() -> NSScrollView {
        let (scroll, content) = pane()
        let rowHeight = SettingsLayout.rowHeight, noteHeight = SettingsLayout.noteRowHeight
        let quitting = group(in: content, y: 20, height: rowHeight)
        rowLabel("Warn before quitting", in: quitting, row: 0)
        warnBeforeQuitting.setAccessibilityLabel("Warn before quitting")
        trailingSwitch(warnBeforeQuitting, in: quitting, top: 0)
        let frameTitle = SettingsSectionHeading(title: "Window")
        content.addSubview(frameTitle)
        let frame = group(in: content, y: 0, height: rowHeight)
        rowLabel("Window frame", in: frame, row: 0, width: 200)
        trailingPill(adjustWindowFrame, in: frame, top: 0)
        windowFrameValue.font = .systemFont(ofSize: NSFont.systemFontSize)
        windowFrameValue.textColor = .secondaryLabelColor
        windowFrameValue.alignment = .right
        place(windowFrameValue, in: frame, NSRect(x: frame.bounds.width - SettingsLayout.rowInset - adjustWindowFrame.fittingWidth - 12 - 160,
                                                  y: 12, width: 160, height: 18))
        refreshWindowFrame(WindowFramePreferences.shared.state)
        let previewsTitle = SettingsSectionHeading(title: "Previews")
        content.addSubview(previewsTitle)
        let preferences = group(in: content, y: 0, height: rowHeight)
        rowLabel("Previews", in: preferences, row: 0)
        let previewSettings = SettingsPillButton(title: "Previews Settings…")
        previewSettings.target = self; previewSettings.action = #selector(openPreviewSettings)
        trailingPill(previewSettings, in: preferences, top: 0)

        let onboardingTitle = SettingsSectionHeading(title: "Onboarding")
        content.addSubview(onboardingTitle)
        let onboarding = group(in: content, y: 0, height: noteHeight + 6)
        label("Replay onboarding", in: onboarding, NSRect(x: SettingsLayout.rowInset, y: 10, width: 300, height: 18))
        label("Replay the full welcome and setup. Finishing applies your choices to this Space; existing tabs stay.",
              in: onboarding, NSRect(x: SettingsLayout.rowInset, y: 30,
                                     width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 3 - replay.fittingWidth, height: 28), help: true)
        trailingPill(replay, in: onboarding, top: 0, rowHeight: noteHeight + 6)
        generalLayout = GeneralLayout(quitting: quitting,
                                      sections: [(frameTitle, frame), (previewsTitle, preferences), (onboardingTitle, onboarding)],
                                      content: content)
        layoutGeneralPane()
        return scroll
    }

    private struct GeneralLayout {
        let quitting: SettingsGroupView
        let sections: [(NSTextField, SettingsGroupView)]
        let content: LayoutView
    }
    private var generalLayout: GeneralLayout?

    private func layoutGeneralPane() {
        guard let layout = generalLayout else { return }
        var bottom = layout.quitting.frame.maxY
        for (title, group) in layout.sections {
            let top = bottom + SettingsLayout.headingSpacing
            group.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: top))
            title.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset,
                                 y: top - SettingsLayout.headingGap - SettingsLayout.headingHeight,
                                 width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: SettingsLayout.headingHeight)
            bottom = group.frame.maxY
        }
        layout.content.setFrameSize(NSSize(width: layout.content.frame.width, height: max(SettingsLayout.contentHeight, bottom + 20)))
    }
    @objc private func openPreviewSettings() { showPreviewSettings() }

    private func makeSpacesPane() -> NSScrollView {
        let (scroll, content) = pane()
        let intro = NSTextField(wrappingLabelWithString: "Spaces that share data stay signed in to the same sites and share history, extensions and Favorites. A Space you keep separate starts fresh.")
        intro.font = .systemFont(ofSize: 12); intro.textColor = .secondaryLabelColor
        intro.maximumNumberOfLines = 3
        place(intro, in: content, NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset, y: 18,
                                         width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: 46))
        let listY: CGFloat = 104
        heading("Your Spaces", in: content, above: listY)
        spaceList.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: listY))
        spaceList.setAccessibilityElement(true)
        spaceList.setAccessibilityRole(.group)
        spaceList.setAccessibilityLabel("Your Spaces")
        content.addSubview(spaceList)
        content.addSubview(newSpace)
        removalRow.frame = NSRect(x: SettingsLayout.margin, y: 0, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight)
        removalRow.isHidden = true
        removalNote.frame = NSRect(x: SettingsLayout.rowInset, y: 12, width: 260, height: 18)
        removalRow.addSubview(removalNote)
        removalRow.addSubview(removalRetry)
        content.addSubview(removalRow)
        layoutSpaceList()
        return scroll
    }

    private func layoutSpaceList() {
        let height = max(SettingsLayout.rowHeight, CGFloat(renderedSpaceRows.count) * SettingsLayout.rowHeight)
        spaceList.setFrameSize(NSSize(width: SettingsLayout.groupWidth, height: height))
        newSpace.frame = NSRect(x: spaceList.frame.maxX - newSpace.fittingWidth, y: spaceList.frame.maxY + 12,
                                width: newSpace.fittingWidth, height: SettingsLayout.buttonHeight)
        var bottom = newSpace.frame.maxY
        if !removalRow.isHidden {
            removalRow.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: bottom + 16))
            removalRetry.frame = NSRect(x: removalRow.bounds.width - SettingsLayout.rowInset - removalRetry.fittingWidth,
                                        y: ((SettingsLayout.rowHeight - SettingsLayout.buttonHeight) / 2).rounded(),
                                        width: removalRetry.fittingWidth, height: SettingsLayout.buttonHeight)
            bottom = removalRow.frame.maxY
        }
        if let content = spaceList.superview {
            content.setFrameSize(NSSize(width: content.frame.width, height: max(SettingsLayout.contentHeight, bottom + 20)))
        }
    }

    private var pendingRemovals: [(id: UUID, name: String, running: Bool)] {
        let controller = ProfileRemovalController.shared
        var ids = store.state.profileRemovals.map(\.profileID)
        for profile in store.state.profiles where !ids.contains(profile.id)
            && !store.state.spaces.contains(where: { $0.profileID == profile.id }) && controller.status(for: profile.id) != nil {
            ids.append(profile.id)
        }
        return ids.compactMap { id in
            store.state.profiles.first { $0.id == id }.map { (id: id, name: $0.name, running: controller.status(for: id)?.running == true) }
        }
    }

    private func renderRemovalRow() {
        let pending = pendingRemovals
        let running = pending.contains { $0.running }
        removalRow.isHidden = pending.isEmpty
        removalNote.stringValue = running || pending.isEmpty ? "Removing old data…" : "Couldn’t finish removing old data."
        removalRetry.isHidden = pending.isEmpty || running
        layoutSpaceList()
    }

    private func retryPendingRemovals() {
        for pending in pendingRemovals where !pending.running {
            ProfileRemovalController.shared.remove(profileID: pending.id, expectedName: pending.name)
        }
    }

    private func renderSpaceList() {
        let rows = store.state.spaces.map { space in
            SpaceRowState(id: space.id, name: space.name, symbol: space.symbol, emoji: space.customIcon?.emoji)
        }
        guard rows != renderedSpaceRows else { renderRemovalRow(); return }
        let focused = spaceRows.first { window?.firstResponder === $0.value }?.key
        renderedSpaceRows = rows
        spaceList.subviews.forEach { $0.removeFromSuperview() }
        spaceRows.removeAll()
        for (index, row) in rows.enumerated() {
            let top = CGFloat(index) * SettingsLayout.rowHeight
            if index > 0 { spaceList.separator(at: top) }
            let button = SettingsSpaceButton { [weak self] in self?.openSpace(row.id) }
            let customImage = store.state.spaces.first { $0.id == row.id }?.customIcon?.image
            button.update(name: row.name, detail: "",
                          image: customImage ?? NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil), emoji: row.emoji)
            button.setAccessibilityIdentifier("settings.space.row." + row.id.uuidString)
            button.frame = NSRect(x: 0, y: top, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight)
            spaceList.addSubview(button)
            spaceRows[row.id] = button
        }
        renderRemovalRow()
        if selectedPane == .spaces, shownDestination == .pane(.spaces), let content = panes[.spaces] {
            connectKeyViews(in: content)
        }
        if let focused, let row = spaceRows[focused] { window?.makeFirstResponder(row) }
    }

    private func openSpace(_ id: UUID) {
        guard store.state.spaces.contains(where: { $0.id == id }) else { return }
        show(.space(id))
    }

    private func makeSpaceEditorPane() -> NSScrollView {
        let (scroll, content) = pane()
        let rowHeight = SettingsLayout.rowHeight
        let identity = group(in: content, y: 20, height: rowHeight * 2)
        rowLabel("Space Name", in: identity, row: 0, width: 160)
        trailingPill(renameSpace, in: identity, top: 0)
        place(spaceNameValue, in: identity, NSRect(x: 180, y: 12,
                                                   width: SettingsLayout.groupWidth - 180 - SettingsLayout.rowInset * 2 - renameSpace.fittingWidth, height: 18))
        identity.separator(at: rowHeight)
        rowLabel("Share data with", in: identity, row: 1, width: 160)
        trailing(shareData, in: identity, top: rowHeight, width: 220, height: 25)

        let searchTitle = SettingsSectionHeading(title: "Search")
        content.addSubview(searchTitle)
        let searching = group(in: content, y: 0, height: rowHeight * 3)
        rowLabel("Search engine", in: searching, row: 0)
        trailing(engine, in: searching, top: 0, width: 220, height: 25)
        searching.separator(at: rowHeight)
        rowLabel("Manage search", in: searching, row: 1)
        if let manage = profilePageButton(.search) as? SettingsPillButton { trailingPill(manage, in: searching, top: rowHeight) }
        searching.separator(at: rowHeight * 2)
        rowLabel("Include search engine suggestions", in: searching, row: 2)
        searchSuggestions.setAccessibilityLabel("Include search engine suggestions")
        trailingSwitch(searchSuggestions, in: searching, top: rowHeight * 2)

        let downloadsTitle = SettingsSectionHeading(title: "Downloads")
        content.addSubview(downloadsTitle)
        let downloads = group(in: content, y: 0, height: SettingsLayout.rowHeight)
        downloadLocationPicker.rowTitle = label("Download location", in: downloads, NSRect(x: 12, y: 12, width: 160, height: 18))
        place(downloadLocationPicker, in: downloads, NSRect(x: SettingsLayout.groupWidth - 12 - DownloadLocationPicker.width, y: 7,
                                                            width: DownloadLocationPicker.width, height: 28))
        place(downloadHelp, in: downloads, NSRect(x: 12, y: 50, width: SettingsLayout.groupWidth - 120, height: 32))
        place(downloadRetry, in: downloads, NSRect(x: SettingsLayout.groupWidth - 82, y: 52, width: 70, height: 28))

        sharedNote.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset, y: 0,
                                  width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: 16)
        content.addSubview(sharedNote)

        let browsingTitle = SettingsSectionHeading(title: "Tabs")
        content.addSubview(browsingTitle)
        let tabs = group(in: content, y: 0, height: SettingsLayout.rowHeight)
        let archiveTitle = label("Archive tabs after", in: tabs, NSRect(x: 12, y: 12, width: 116, height: 18))
        archiveTitle.sizeToFit()
        place(archiveInfo, in: tabs, NSRect(x: archiveTitle.frame.maxX + 4, y: 13, width: 16, height: 16))
        trailing(archive, in: tabs, top: 0, width: 220, height: 25)

        let dataTitle = SettingsSectionHeading(title: "Your Data and Settings")
        content.addSubview(dataTitle)
        let pages: [ProfileSettingsPage] = [.privacy, .passwords, .payments, .notifications]
        let data = group(in: content, y: 0, height: rowHeight * CGFloat(pages.count))
        for (index, page) in pages.enumerated() {
            if index > 0 { data.separator(at: CGFloat(index) * rowHeight) }
            place(profilePageButton(page), in: data, NSRect(x: 0, y: CGFloat(index) * rowHeight,
                                                            width: SettingsLayout.groupWidth, height: rowHeight))
        }
        if let clear = profilePageButton(.clearBrowsingData) as? SettingsPillButton { content.addSubview(clear) }
        content.addSubview(deleteSpace)
        spaceEditorLayout = SpaceEditorLayout(identity: identity,
            sections: [(searchTitle, searching), (downloadsTitle, downloads), (browsingTitle, tabs), (dataTitle, data)],
            downloads: downloads, content: content)
        layoutSpaceCards()
        return scroll
    }

    private struct SpaceEditorLayout {
        let identity: SettingsGroupView
        let sections: [(NSTextField, SettingsGroupView)]
        let downloads: SettingsGroupView
        let content: LayoutView
    }
    private var spaceEditorLayout: SpaceEditorLayout?

    private func layoutSpaceCards() {
        guard let layout = spaceEditorLayout else { return }
        var bottom = layout.identity.frame.maxY
        let note = !downloadHelp.isHidden || !downloadRetry.isHidden
        layout.downloads.setFrameSize(NSSize(width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight + (note ? 44 : 0)))
        for (title, group) in layout.sections {
            let top = bottom + SettingsLayout.headingSpacing
            group.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: top))
            title.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset,
                                 y: top - SettingsLayout.headingGap - SettingsLayout.headingHeight,
                                 width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: SettingsLayout.headingHeight)
            bottom = group.frame.maxY
            if group === layout.downloads, !sharedNote.isHidden {
                sharedNote.setFrameOrigin(NSPoint(x: sharedNote.frame.minX, y: bottom + 8))
                bottom = sharedNote.frame.maxY
            }
        }
        let buttonsY = bottom + 20
        let deleteWidth = max(deleteSpace.fittingWidth, 120)
        deleteSpace.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.groupWidth - deleteWidth, y: buttonsY,
                                   width: deleteWidth, height: SettingsLayout.buttonHeight)
        if let clear = profilePageButtons[.clearBrowsingData] as? SettingsPillButton {
            clear.frame = NSRect(x: deleteSpace.frame.minX - 12 - clear.fittingWidth, y: buttonsY,
                                 width: clear.fittingWidth, height: SettingsLayout.buttonHeight)
        }
        layout.content.setFrameSize(NSSize(width: layout.content.frame.width,
                                           height: max(SettingsLayout.contentHeight, buttonsY + SettingsLayout.buttonHeight + 20)))
    }

    private func profilePageButton(_ page: ProfileSettingsPage) -> NSButton {
        let button: NSButton
        let activate: () -> Void = { [weak self] in self?.openProfileSettingsPage(page) }
        switch page {
        case .search, .clearBrowsingData:
            let pill = SettingsPillButton(title: page == .search ? page.title : page.title + "…")
            pill.identifier = NSUserInterfaceItemIdentifier(page.rawValue)
            pill.target = self; pill.action = #selector(openProfilePageButton(_:))
            button = pill
        case .privacy: button = SettingsCommandButton(title: page.title, symbol: "lock.fill", color: .systemBlue, action: activate)
        case .passwords: button = SettingsCommandButton(title: page.title, symbol: "key.fill", color: .systemGreen, action: activate)
        case .payments: button = SettingsCommandButton(title: page.title, symbol: "creditcard.and.123", color: .systemYellow, action: activate)
        case .notifications: button = SettingsCommandButton(title: page.title, symbol: "bell.fill", color: .systemOrange, action: activate)
        }
        button.setAccessibilityLabel(page.title)
        button.setAccessibilityIdentifier("settings.profile." + page.rawValue)
        profilePageButtons[page] = button
        return button
    }
    @objc private func openProfilePageButton(_ sender: NSButton) {
        guard let page = sender.identifier.flatMap({ ProfileSettingsPage(rawValue: $0.rawValue) }) else { return }
        openProfileSettingsPage(page)
    }

    private struct AdvancedRow {
        let symbol: String, color: NSColor, title: String, control: NSSwitch
        var note: String? = nil
    }

    private func makeAdvancedPane() -> NSScrollView {
        let (scroll, content) = pane()
        var y: CGFloat = 20
        func section(_ title: String, _ rows: [AdvancedRow]) {
            let heights = rows.map { $0.note == nil ? SettingsLayout.rowHeight : SettingsLayout.noteRowHeight }
            let top = y + SettingsLayout.headingGap + SettingsLayout.headingHeight
            heading(title, in: content, above: top)
            let box = group(in: content, y: top, height: heights.reduce(0, +))
            var rowTop: CGFloat = 0
            let inset = SettingsLayout.rowInset
            for (index, row) in rows.enumerated() {
                if index > 0 { box.separator(at: rowTop) }
                let height = heights[index]
                place(SettingsSymbolBadge(symbol: row.symbol, color: row.color), in: box,
                      NSRect(x: inset, y: rowTop + (height - 20) / 2, width: 20, height: 20))
                let textWidth = box.bounds.width - inset * 3 - 30 - 38
                if let note = row.note {
                    label(row.title, in: box, NSRect(x: inset + 30, y: rowTop + 10, width: textWidth, height: 18))
                    label(note, in: box, NSRect(x: inset + 30, y: rowTop + 30, width: textWidth, height: 16), help: true)
                } else {
                    label(row.title, in: box, NSRect(x: inset + 30, y: rowTop + (height - 18) / 2, width: textWidth, height: 18))
                }
                row.control.setAccessibilityLabel(row.title.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                trailingSwitch(row.control, in: box, top: rowTop, rowHeight: height)
                rowTop += height
            }
            y = box.frame.maxY + SettingsLayout.headingSpacing - SettingsLayout.headingGap - SettingsLayout.headingHeight
        }
        section("Sound and Feedback", [
            AdvancedRow(symbol: "speaker.wave.2.fill", color: .systemBlue, title: "Play Parc sound effects", control: soundEffects),
            AdvancedRow(symbol: "hand.tap.fill", color: .systemBlue, title: "Haptic feedback when reordering tabs", control: reorderingHaptics)])
        section("Windows and Tabs", [
            AdvancedRow(symbol: "macwindow", color: .systemGreen, title: "When opening Parc, restore windows from previous session", control: restore),
            AdvancedRow(symbol: "rectangle.topthird.inset.filled", color: .systemGreen, title: "Allow window dragging from the top of webpages", control: windowDragging),
            AdvancedRow(symbol: "ellipsis.rectangle", color: .systemRed, title: "Show full URL when Toolbar is enabled", control: toolbarFullURL),
            AdvancedRow(symbol: "quote.opening", color: .systemRed, title: "Enable Shared Quotes when highlighting text.", control: sharedQuotes,
                        note: "If disabled, you can still use Copy URL as Quote from the Edit menu.")])
        section("Websites", [
            AdvancedRow(symbol: "paintpalette.fill", color: .systemPurple, title: "Allow websites to get your theme data", control: websiteTheme)])
        websiteTheme.setAccessibilityHelp("Allow webpages to match the colors of this window’s Space.")
        let buttonsY = y - SettingsLayout.headingSpacing + SettingsLayout.headingGap + SettingsLayout.headingHeight + 20
        place(moreSettings, in: content, NSRect(x: SettingsLayout.margin, y: buttonsY, width: moreSettings.fittingWidth, height: SettingsLayout.buttonHeight))
        place(exportData, in: content, NSRect(x: SettingsLayout.margin + SettingsLayout.groupWidth - exportData.fittingWidth, y: buttonsY,
                                              width: exportData.fittingWidth, height: SettingsLayout.buttonHeight))
        content.setFrameSize(NSSize(width: content.frame.width, height: max(SettingsLayout.contentHeight, buttonsY + SettingsLayout.buttonHeight + 20)))
        return scroll
    }

    @discardableResult func showShortcut(_ id: String) -> Bool {
        guard window?.attachedSheet == nil else { return false }
        showPane(.shortcuts)
        return shortcutsPane.selectCommand(id)
    }

    @discardableResult func showAutoArchiveSettings(spaceID: UUID) -> Bool {
        guard let window, window.attachedSheet == nil,
              let space = store.state.spaces.first(where: { $0.id == spaceID }),
              !store.isProfileRemovalPending(space.profileID) else { return false }
        do { try store.saveSettingsSelection(pane: Pane.spaces.rawValue, profileID: space.profileID) }
        catch { reportProfileSettingsError(error); return false }
        cancelDownloadFolderSelection()
        selectedSpaceID = spaceID
        show(.space(spaceID), persist: false)
        refresh()
        archive.scrollToVisible(archive.bounds)
        window.makeFirstResponder(archive)
        return true
    }

    func showPane(_ pane: Pane, persist: Bool = true) {
        show(.pane(pane), persist: persist)
    }

    private func content(for destination: Destination) -> NSScrollView? {
        switch destination {
        case .pane(let pane): return panes[pane]
        case .space(let id): return store.state.spaces.contains(where: { $0.id == id }) ? spaceEditor : nil
        }
    }

    private func title(for destination: Destination?) -> String {
        switch destination {
        case .pane(.membership)?: return membershipPane.displayName
        case .pane(let pane)?: return pane.rawValue
        case .space?: return "Edit Space"
        case nil: return Pane.general.rawValue
        }
    }

    private func selectFromSidebar(_ pane: Pane) {
        guard let window else { return }
        let keepsSidebarFocus = window.firstResponder === sidebar.table
        if !show(.pane(pane), focusContent: !keepsSidebarFocus) { syncChrome() }
    }

    @discardableResult
    private func show(_ destination: Destination, persist: Bool = true, record: Bool = true, focusContent: Bool = true) -> Bool {
        guard let content = content(for: destination), let window else { syncChrome(); return false }
        let pane = destination.pane
        guard window.attachedSheet == nil else { syncChrome(); return false }
        if case .space(let id) = destination, id != selectedSpaceID {
            if persist {
                do { try store.saveSettingsSelection(pane: pane.rawValue, profileID: store.state.spaces.first { $0.id == id }?.profileID) }
                catch { syncChrome(); reportProfileSettingsError(error); return false }
            }
            cancelDownloadFolderSelection()
            selectedSpaceID = id
            refresh()
        } else if persist {
            do { try store.saveSettingsSelection(pane: pane.rawValue, profileID: editedSpace?.profileID) }
            catch {
                syncChrome()
                reportProfileSettingsError(error)
                return false
            }
        }
        if selectedPane != pane {
            cancelDownloadFolderSelection()
        }
        if pane == .general { DefaultBrowserController.shared.refresh() }
        if record { navigation.visit(destination) }
        if shownDestination == destination, paneHost.pane === content {
            syncChrome()
            return true
        }
        if focusContent, let root = window.contentView { focusState.remember(in: window, root: root, context: focusContext) }
        shortcutsPane.endRecording()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        if focusContent { window.makeFirstResponder(nil) }
        selectedPane = pane
        shownDestination = destination
        paneHost.show(content, animated: window.isVisible)
        syncChrome()
        content.documentView?.setAccessibilityLabel(title(for: destination) + " settings")
        window.autorecalculatesKeyViewLoop = pane == .shortcuts || pane == .icon
        window.recalculateKeyViewLoop()
        if pane != .shortcuts && pane != .icon { connectKeyViews(in: content) }
        if focusContent { restorePaneFocus() }
        return true
    }

    private func connectKeyViews(in content: NSView) {
        SettingsFocusState.connectKeyViews(in: content)
        let controls = SettingsFocusState.controls(in: content)
        guard let first = controls.first, let last = controls.last else { sidebar.table.nextKeyView = nil; return }
        last.nextKeyView = sidebar.table
        sidebar.table.nextKeyView = first
    }

    private func syncChrome() {
        guard let window else { return }
        window.title = title(for: shownDestination)
        titleLabel.stringValue = window.title
        sidebar.select(selectedPane)
        updateNavigationControls()
    }

    private func updateNavigationControls() {
        let available = !isClosing && window?.attachedSheet == nil
        for item in window?.toolbar?.items ?? [] {
            if item.itemIdentifier == Self.backItem { item.isEnabled = available && navigation.canGoBack }
            if item.itemIdentifier == Self.forwardItem { item.isEnabled = available && navigation.canGoForward }
        }
    }

    private func moveInHistory(forward: Bool) {
        guard let target = forward ? navigation.next : navigation.previous else { return }
        guard show(target, record: false) else { return }
        if forward { navigation.moveForward() } else { navigation.moveBack() }
        syncChrome()
    }

    @objc func goBack(_ sender: Any?) { moveInHistory(forward: false) }
    @objc func goForward(_ sender: Any?) { moveInHistory(forward: true) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isClosing, window?.attachedSheet == nil else { return false }
        if item.action == #selector(goBack(_:)) { return navigation.canGoBack }
        if item.action == #selector(goForward(_:)) { return navigation.canGoForward }
        return true
    }

    private var focusContext: String {
        selectedPane.rawValue + (shownDestination.flatMap { if case .space(let id) = $0 { return ":" + id.uuidString }; return nil } ?? "")
    }

    private var spaceFallback: NSView? {
        guard selectedPane == .spaces else { return nil }
        if case .space? = shownDestination { return renameSpace }
        return store.state.spaces.first(where: { $0.id == selectedSpaceID }).flatMap { spaceRows[$0.id] }
            ?? store.state.spaces.first.flatMap { spaceRows[$0.id] }
    }

    private func restorePaneFocus(context: String? = nil) {
        guard !isClosing, context == nil || context == focusContext,
              let window, let content = window.contentView else { return }
        focusState.restore(in: window, root: content, context: focusContext, fallback: sidebar.table)
    }

    func windowWillBeginSheet(_ notification: Notification) {
        guard let window, let content = window.contentView else { return }
        focusState.remember(in: window, root: content, context: focusContext)
        sheetFocusContext = focusContext
        shortcutsPane.endRecording()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        updateNavigationControls()
    }

    func windowDidEndSheet(_ notification: Notification) {
        let context = sheetFocusContext
        sheetFocusContext = nil
        updateNavigationControls()
        guard !isClosing else { return }
        let revision = lifecycleRevision
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lifecycleRevision == revision, self.window?.attachedSheet == nil else { return }
            self.onSheetEnded?()
            guard !self.isClosing else { return }
            self.reportRemovalFailures()
            if context?.hasPrefix(Pane.spaces.rawValue + ":") == true, self.selectedPane == .spaces,
               context != self.focusContext {
                if let window = self.window, let content = window.contentView {
                    self.focusState.restore(in: window, root: content, context: nil, fallback: self.spaceFallback)
                }
            } else { self.restorePaneFocus(context: context) }
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard !isClosing, window?.attachedSheet == nil else { return false }
        if item.itemIdentifier == Self.backItem { return navigation.canGoBack }
        if item.itemIdentifier == Self.forwardItem { return navigation.canGoForward }
        return true
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.backItem, Self.forwardItem, .space, Self.titleItem, .flexibleSpace]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case Self.backItem, Self.forwardItem:
            let back = identifier == Self.backItem
            item.label = back ? "Back" : "Forward"
            item.paletteLabel = item.label
            item.toolTip = back ? "Show the previous settings page" : "Show the next settings page"
            item.image = NSImage(systemSymbolName: back ? "chevron.left" : "chevron.right", accessibilityDescription: item.label)
            item.isNavigational = true
            item.isBordered = true
            item.autovalidates = false
            item.target = self
            item.action = back ? #selector(goBack(_:)) : #selector(goForward(_:))
            DispatchQueue.main.async { [weak self] in self?.updateNavigationControls() }
        case Self.titleItem:
            titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setAccessibilityElement(false)
            item.view = titleLabel
            item.isBordered = false
            item.label = "Title"
            item.paletteLabel = "Title"
            item.visibilityPriority = .high
        default:
            return nil
        }
        return item
    }

    private func pruneRemovedSpaces() {
        let ids = Set(store.state.spaces.map(\.id))
        let removed: (Destination) -> Bool = { if case .space(let id) = $0 { return !ids.contains(id) }; return false }
        let currentRemoved = shownDestination.map(removed) ?? false
        navigation.removeAll(where: removed, replacingCurrentWith: .pane(.spaces))
        if currentRemoved, !isClosing {
            if !show(.pane(.spaces), persist: false, record: false) {
                shownDestination = .pane(.spaces)
                syncChrome()
            }
        } else {
            updateNavigationControls()
        }
    }

    private var editedSpace: BrowserSpace? {
        store.state.spaces.first { $0.id == selectedSpaceID }
    }

    private func profilePageSpace() -> BrowserSpace? {
        editedSpace.flatMap { space in
            !store.isProfileRemovalPending(space.profileID) && store.state.profiles.contains { $0.id == space.profileID } ? space : nil
        }
    }

    func refresh() {
        if editedSpace == nil { selectedSpaceID = store.state.spaces.first { $0.id == contextSpaceID }?.id ?? store.state.spaces.first?.id }
        let edited = editedSpace
        let removing = edited.map { store.isProfileRemovalPending($0.profileID) } ?? false
        archive.isEnabled = edited != nil && !removing
        archiveInfo.isEnabled = archive.isEnabled
        renameSpace.isEnabled = edited != nil && !removing
        spaceNameValue.stringValue = edited?.name ?? ""
        renderShareData(edited, removing: removing)
        if let edited, !removing {
            let canDelete = store.state.spaces.count > 1 && SpaceDeletionTarget(spaceID: edited.id, state: store.state) != nil
            deleteSpace.isEnabled = canDelete && onDeleteSpace != nil
            deleteSpace.toolTip = store.state.spaces.count <= 1 ? "Parc needs at least one Space."
                : canDelete ? "Delete this Space" : "This Space can’t be deleted right now."
        } else {
            deleteSpace.isEnabled = false
            deleteSpace.toolTip = "This Space isn’t available right now."
        }
        if let editing = spaceNameDialog,
           !store.state.spaces.contains(where: { $0.id == editing.spaceID }) {
            cancelSpaceNameEditor()
        }
        archive.removeAllItems()
        for choice in AutoArchiveInterval.settingsChoices {
            archive.addItem(withTitle: choice.title)
            archive.lastItem?.representedObject = choice.rawValue
        }
        let interval = edited.flatMap { store.autoArchiveInterval(forSpace: $0.id) } ?? .twelveHours
        if AutoArchiveInterval.settingsChoices.contains(interval) {
            archive.selectItem(at: AutoArchiveInterval.settingsChoices.firstIndex(of: interval)!)
        } else {
            archive.addItem(withTitle: "Saved setting: " + interval.title)
            archive.lastItem?.isEnabled = false
            archive.select(archive.lastItem)
        }
        archive.setAccessibilityHelp("Applies to \(edited?.name ?? "this Space") only.")
        let alsoApplies = edited.map { store.spaceSharing(of: $0.id).map(\.name) } ?? []
        sharedNote.stringValue = alsoApplies.isEmpty ? "" : "Also applies to " + alsoApplies.joined(separator: ", ") + "."
        sharedNote.toolTip = sharedNote.stringValue.isEmpty ? nil : sharedNote.stringValue
        sharedNote.isHidden = alsoApplies.isEmpty
        if editedProfileID != loadedPreferencesProfileID {
            loadedPreferencesProfileID = editedProfileID
            refreshSearchPreferences()
        }
        for button in profilePageButtons.values {
            let available = profilePageSpace() != nil
            button.isEnabled = available && onProfileSettingsPage != nil
            button.toolTip = button.isEnabled ? nil : "This Space’s browser settings aren’t available right now."
        }
        moreSettings.isEnabled = settingsContextSpace() != nil && onMoreSettings != nil
        replay.isEnabled = replaySpaceID != nil && NSApp.delegate?.responds(to: #selector(AppDelegate.replayOnboarding(_:))) == true
        restore.state = store.state.settings.restoreSession ? .on : .off
        renderSpaceList()
        layoutSpaceCards()
        pruneRemovedSpaces()
        reportRemovalFailures()
    }
    override func showWindow(_ sender: Any?) {
        isClosing = false
        super.showWindow(sender)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if window?.firstResponder === window || window?.firstResponder == nil { restorePaneFocus() }
        refreshDownloadPreferences(); refreshSearchPreferences()
        reportRemovalFailures()
        DefaultBrowserController.shared.refresh()
    }
    func windowDidResignKey(_ notification: Notification) {
        shortcutsPane.endRecording()
    }

    @discardableResult func showAirTrafficControl() -> Bool {
        showPane(.links)
        guard let links = panes[.links]?.documentView as? LinksSettingsView else { return false }
        return links.showRoutes()
    }

    private func prepareForClose() -> Bool {
        if let links = panes[.links]?.documentView as? LinksSettingsView,
           !links.prepareForParentClose() { return false }
        return window?.attachedSheet == nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { prepareForClose() }

    func prepareForTermination() -> Bool { prepareForClose() }

    func restoreAfterCancelledOwnerClose() {
        isClosing = false
        window?.orderFront(nil)
    }

    @discardableResult
    func attemptClose() -> Bool {
        guard prepareForClose() else { return false }
        super.close()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        isClosing = true
        lifecycleRevision &+= 1
        sheetFocusContext = nil
        membershipPane.cancelPresentation()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        downloadPreferencesGeneration &+= 1
        previewSettingsSheet?.dismiss()
        previewSettingsSheet = nil
        cancelPendingDataExport()
        cancelSpaceNameEditor()
        shortcutsPane.endRecording()
        searchGeneration &+= 1; searchPreferences = nil
        cancelDownloadFolderSelection()
        if let window { SettingsFocusState.cancelAttachedSheets(of: window) }
        window?.makeFirstResponder(nil)
        focusState.forget()
    }

    func showPreviewSettings() {
        guard let window, window.isVisible, window.attachedSheet == nil, previewSettingsSheet == nil else { return }
        let sheet = SidebarPreviewSettingsSheet()
        previewSettingsSheet = sheet
        if !sheet.present(for: window, completion: { [weak self, weak sheet] in
            if self?.previewSettingsSheet === sheet { self?.previewSettingsSheet = nil }
        }) {
            sheet.dismiss()
            previewSettingsSheet = nil
        }
    }

    @objc private func exportBrowserData() {
        guard let parent = window, parent.isVisible, parent.attachedSheet == nil,
              dataExportID == nil else { return }
        let snapshot = BrowserDataExport(state: store.state)
        let id = UUID(), panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md", conformingTo: .data) ?? .plainText]
        panel.nameFieldStringValue = "Parc Data Export.md"
        panel.canCreateDirectories = true
        dataExportID = id; dataExportPanel = panel; exportData.isEnabled = false
        panel.beginSheetModal(for: parent) { [weak self, weak panel] response in
            guard let self, let panel, self.dataExportID == id, self.dataExportPanel === panel else { return }
            self.dataExportPanel = nil
            guard response == .OK, let url = panel.url else {
                self.dataExportID = nil; self.exportData.isEnabled = true; return
            }
            Task { @MainActor [self] in
                do { try await Task.detached(priority: .utility) { try snapshot.write(to: url) }.value }
                catch { PArcDialog.present(error) }
                if self.dataExportID == id { self.dataExportID = nil; self.exportData.isEnabled = true }
            }
        }
    }

    private func cancelPendingDataExport() {
        guard let panel = dataExportPanel else { return }
        dataExportPanel = nil; dataExportID = nil; exportData.isEnabled = true
        panel.cancel(nil)
    }

    private func showSpaceDeletion() {
        guard let window, window.attachedSheet == nil, let space = editedSpace, let onDeleteSpace else { return }
        guard onDeleteSpace(space.id) else {
            PArcDialog.inform(in: window, .init(title: "Parc couldn’t delete this Space.",
                message: "Its window is unavailable or busy. Finish its current operation and try again."))
            return
        }
    }

    private func reportRemovalFailures() {
        guard !isClosing, let window, window.isVisible, window.isKeyWindow, window.attachedSheet == nil else { return }
        for profile in store.state.profiles {
            guard let status = ProfileRemovalController.shared.claimFailure(for: profile.id) else { continue }
            PArcDialog.inform(in: window, .init(title: "Parc couldn’t finish removing old data.", message: status.message))
            return
        }
    }

    private func renderShareData(_ edited: BrowserSpace?, removing: Bool) {
        shareData.menu?.removeAllItems()
        shareChoices = []
        func add(_ title: String, choice: SpaceDataSharing?, checked: Bool = false, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: choice == nil ? nil : #selector(shareDataChosen(_:)), keyEquivalent: "")
            item.target = self
            if let choice { item.tag = shareChoices.count; shareChoices.append(choice) }
            item.state = checked ? .on : .off
            item.isEnabled = enabled
            shareData.menu?.addItem(item)
        }
        guard let edited else {
            add("Keep separate", choice: nil, enabled: false)
            shareData.isEnabled = false
            return
        }
        let sharing = store.spaceSharing(of: edited.id)
        let others = store.state.spaces.filter { $0.id != edited.id }
        add(sharing.isEmpty ? "Keep separate" : sharing.map(\.name).joined(separator: ", "), choice: nil)
        for other in others {
            add(other.name, choice: .share(withSpace: other.id), checked: other.profileID == edited.profileID,
                enabled: !store.isProfileRemovalPending(other.profileID))
        }
        if !others.isEmpty { shareData.menu?.addItem(.separator()) }
        add("Keep separate", choice: .separate, checked: sharing.isEmpty)
        shareData.isEnabled = !removing && !others.isEmpty
        shareData.setAccessibilityHelp(others.isEmpty ? "Add another Space to share data between Spaces." : nil)
    }

    @objc private func shareDataChosen(_ sender: NSMenuItem) {
        guard let window, window.attachedSheet == nil, let space = editedSpace,
              shareChoices.indices.contains(sender.tag) else { return }
        let revision = lifecycleRevision
        SpaceSharingConfirmation.present(on: window, store: store, spaceID: space.id, sharing: shareChoices[sender.tag],
            ownerValid: { [weak self] in
                guard let self else { return false }
                return !self.isClosing && self.lifecycleRevision == revision && self.editedSpace?.id == space.id
            }, completion: { [weak self] result in
                guard let self, !self.isClosing, self.lifecycleRevision == revision else { return }
                if case .failure(let error) = result { self.reportProfileSettingsError(error) }
                self.refresh()
            })
    }

    private func showSpaceNameEditor() {
        guard let window, window.attachedSheet == nil, spaceNameDialog == nil, let space = editedSpace,
              !store.isProfileRemovalPending(space.profileID) else { return }
        let dialog = PArcDialog(.init(title: [("Rename Space", false)], confirm: "Save", cancel: "Cancel",
            field: .init(value: space.title ?? "", placeholder: space.name, required: false)))
        guard let field = dialog.textField else { return }
        field.setAccessibilityLabel("Space name")
        spaceNameDialog = (dialog, space.id)
        let began = dialog.begin(for: window) { [weak self, weak dialog] response in
            guard let self else { return }
            if self.spaceNameDialog?.dialog === dialog { self.spaceNameDialog = nil }
            if response == .confirm {
                do { try self.store.saveSpaceTitle(space, title: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
                catch { if (error as NSError).code != CocoaError.userCancelled.rawValue { self.reportProfileSettingsError(error) } }
            }
            self.refresh()
        }
        if !began { spaceNameDialog = nil }
    }

    private func cancelSpaceNameEditor() {
        guard let editing = spaceNameDialog else { return }
        spaceNameDialog = nil
        let panel = editing.dialog.panel
        panel.sheetParent?.endSheet(panel, returnCode: .cancel)
        panel.orderOut(nil)
    }

    private func reportProfileSettingsError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        PArcDialog.inform(in: window, .init(error: error, title: "Parc couldn’t save these settings."))
    }

    var replaySpaceID: UUID? { settingsContextSpace()?.id }

    @objc private func adjustWindowFrameSelected() {
        NSApp.sendAction(#selector(AppDelegate.adjustWindowFrameFromSettings(_:)), to: NSApp.delegate, from: self)
    }

    private func refreshWindowFrame(_ state: WindowFramePreferences.State) {
        windowFrameValue.stringValue = WindowFrameThickness.label(state.thickness)
        windowFrameValue.setAccessibilityLabel("Window frame, \(WindowFrameThickness.spokenValue(state.thickness))")
        let failure = WindowFramePreferences.shared.loadError
        adjustWindowFrame.isEnabled = !failure
        adjustWindowFrame.toolTip = failure ? WindowFramePreferences.Failure.unavailable.localizedDescription : nil
    }

    @objc private func replayWelcome() {
        NSApp.sendAction(#selector(AppDelegate.replayOnboarding(_:)), to: NSApp.delegate, from: self)
    }

    private var showsSpaceEditor: Bool {
        if case .space(let id)? = shownDestination { return id == selectedSpaceID }
        return false
    }

    private func openProfileSettingsPage(_ page: ProfileSettingsPage) {
        guard selectedPane == .spaces && showsSpaceEditor,
              window?.isKeyWindow == true, window?.attachedSheet == nil else { return }
        guard let space = profilePageSpace(),
              onProfileSettingsPage?(space.id, space.profileID, page) == true else {
            reportSettingsCommandRefusal(page.title)
            return
        }
        _ = attemptClose()
    }

    private func reportSettingsCommandRefusal(_ title: String) {
        guard let window, window.attachedSheet == nil else { return }
        PArcDialog.inform(in: window, .init(title: "Parc couldn’t open " + title.trimmingCharacters(in: CharacterSet(charactersIn: "…")) + ".",
            message: "The original window is unavailable or busy. Finish its current operation and try again."))
    }

    private func settingsContextSpace() -> BrowserSpace? {
        store.state.spaces.first { space in
            (space.id == contextSpaceID || (contextSpaceID == nil && space.profileID == applicationProfileID)) && !store.isProfileRemovalPending(space.profileID)
                && store.state.profiles.contains(where: { $0.id == space.profileID })
        }
    }

    func permitsPage(in ownerStore: BrowserStore, spaceID: UUID, profileID: UUID) -> Bool {
        store === ownerStore && !store.isEphemeral && window?.isKeyWindow == true
            && window?.attachedSheet == nil && !store.isProfileRemovalPending(profileID)
            && store.state.spaces.contains { $0.id == spaceID && $0.profileID == profileID }
    }

    func permitsProfilePage(in ownerStore: BrowserStore, spaceID: UUID, profileID: UUID) -> Bool {
        (selectedPane == .spaces && showsSpaceEditor && profilePageSpace()?.id == spaceID)
            && permitsPage(in: ownerStore, spaceID: spaceID, profileID: profileID)
    }

    @objc private func openMoreSettings() {
        guard window?.attachedSheet == nil, let space = settingsContextSpace(),
              let onMoreSettings else { return }
        if onMoreSettings(space.id, space.profileID) { _ = attemptClose(); return }
        guard let window else { return }
        PArcDialog.inform(in: window, .init(title: "Parc couldn’t open more settings.",
            message: "The original window is busy. Finish its current operation and try again."), queued: true)
    }

    private func cancelDownloadFolderSelection() {
        let panel = downloadFolderPanel
        downloadFolderPanel = nil
        panel?.cancel(nil)
        if panel != nil { renderDownloadLocation() }
    }

    private var editedProfileID: UUID? { profilePageSpace()?.profileID }

    @objc private func retryDownloadPreferences() { refreshDownloadPreferences() }
    private func refreshDownloadPreferences(message: String? = nil) {
        downloadPreferencesGeneration &+= 1
        let generation = downloadPreferencesGeneration
        downloadRetry.isHidden = true
        guard let profileID = editedProfileID else {
            downloadPreferences = nil; renderDownloadPreferences(message: "Download settings are unavailable.")
            return
        }
        let path = store.independentEngineProfilePath(for: profileID)
        if let current = PCNativeBrowserApplication.downloadPreferences(profilePath: path) {
            downloadPreferences = current; renderDownloadPreferences(message: message); return
        }
        downloadPreferences = nil; renderDownloadPreferences(message: message ?? "Loading download settings…")
        PCNativeBrowserApplication.downloadPreferences(profilePath: path) { [weak self] preferences, error in
            MainActor.assumeIsolated {
                guard let self, self.downloadPreferencesGeneration == generation,
                      self.editedProfileID == profileID else { return }
                self.downloadPreferences = preferences?.profilePath == path ? preferences : nil
                self.downloadRetry.isHidden = self.downloadPreferences != nil
                self.renderDownloadPreferences(message: error?.localizedDescription ??
                    (self.downloadPreferences == nil ? "Download settings couldn’t be loaded." : message))
            }
        }
    }
    private func renderDownloadLocation() {
        let current = downloadPreferences
        downloadLocationPicker.update(current.map { .init(directory: $0.directoryURL, prompt: $0.promptForDownload) },
                                      enabled: current.map { !$0.directoryManaged && !$0.promptManaged } ?? false,
                                      panelOpen: downloadFolderPanel != nil)
    }
    private func renderDownloadPreferences(message: String? = nil) {
        let current = downloadPreferences
        renderDownloadLocation()
        let managed = current?.directoryManaged == true || current?.promptManaged == true
        downloadHelp.maximumNumberOfLines = 2
        downloadHelp.lineBreakMode = .byWordWrapping
        downloadHelp.cell?.truncatesLastVisibleLine = true
        downloadHelp.stringValue = message ?? (managed ? "Some download settings for this Space are managed by your organization." : "")
        downloadHelp.toolTip = downloadHelp.stringValue
        downloadHelp.isHidden = !(managed || !downloadRetry.isHidden || (message != nil && current != nil))
        layoutSpaceCards()
    }
    private func reportDownloadPreferenceError(_ error: Error) {
        refreshDownloadPreferences(message: error.localizedDescription)
    }
    private func currentDownloadPreferences() -> PCNativeDownloadPreferences? {
        guard let profileID = editedProfileID, let current = downloadPreferences,
              current.profilePath == store.independentEngineProfilePath(for: profileID) else { return nil }
        return current
    }
    private func downloadLocationChosen(_ choice: DownloadLocationPicker.Choice) {
        guard let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged else {
            refreshDownloadPreferences(); return
        }
        if choice == .other { chooseDownloadDirectory(); return }
        do {
            _ = try PCNativeBrowserApplication.setPromptForDownload(choice == .prompt, for: current)
            refreshDownloadPreferences()
        } catch { reportDownloadPreferenceError(error) }
    }
    private func chooseDownloadDirectory() {
        guard let window, window.attachedSheet == nil, downloadFolderPanel == nil,
              let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged,
              let profileID = editedProfileID else { downloadLocationPicker.revert(); return }
        let panel = NSOpenPanel()
        panel.prompt = "Select"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = downloadLocationPicker.value?.directory ?? current.directoryURL
        downloadFolderPanel = panel
        renderDownloadLocation()
        panel.beginSheetModal(for: window) { [weak self, weak panel, weak window] response in
            guard let self, let panel, self.downloadFolderPanel === panel else { return }
            self.downloadFolderPanel = nil
            guard response == .OK, let window, self.window === window, window.isVisible,
                  self.editedProfileID == profileID,
                  let url = panel.url else { self.refreshDownloadPreferences(); return }
            do {
                let chosen = try PCNativeBrowserApplication.setDownloadDirectory(url, for: current)
                _ = try PCNativeBrowserApplication.setPromptForDownload(false, for: chosen)
                self.refreshDownloadPreferences()
            } catch { self.reportDownloadPreferenceError(error) }
        }
    }
    private func createSpace() {
        guard window?.attachedSheet == nil else { return }
        _ = attemptClose()
        DispatchQueue.main.async { NSApp.sendAction(NSSelectorFromString("createSpace:"), to: nil, from: nil) }
    }

    @objc private func archiveChanged() {
        guard let window, window.attachedSheet == nil, let space = editedSpace,
              !store.isProfileRemovalPending(space.profileID),
              let hours = archive.selectedItem?.representedObject as? Double,
              let interval = AutoArchiveInterval(rawValue: hours),
              AutoArchiveInterval.settingsChoices.contains(interval) else { refresh(); return }
        do { try store.setAutoArchiveInterval(interval, forSpace: space.id) }
        catch { refresh(); reportProfileSettingsError(error) }
    }

    @objc private func showArchiveInformation() {
        guard archiveInfo.isEnabled, window?.attachedSheet == nil else { return }
        if archiveInfoPopover?.isShown == true { archiveInfoPopover?.close(); return }
        let controller = NSViewController()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 126))
        let text = NSTextField(wrappingLabelWithString: "Parc automatically archives inactive Today tabs after this Space’s selected interval. Pinned tabs and Favorites stay put. Find automatically closed tabs in Library → Archive and choose Put Back to restore them.")
        text.font = .systemFont(ofSize: 12)
        text.frame = content.bounds.insetBy(dx: 14, dy: 14)
        content.addSubview(text); controller.view = content
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = controller
        archiveInfoPopover = popover
        popover.show(relativeTo: archiveInfo.bounds, of: archiveInfo, preferredEdge: .maxY)
    }
    private func refreshSearchPreferences(message: String? = nil) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchPreferences = nil; engine.isEnabled = false; searchSuggestions.isEnabled = false
        engine.removeAllItems(); engine.addItem(withTitle: "Loading…")
        searchNote = message ?? "Loading this Space’s search settings…"
        guard let profileID = editedProfileID else {
            engine.removeAllItems(); engine.addItem(withTitle: "Unavailable")
            searchNote = editedSpace.map { store.isProfileRemovalPending($0.profileID) } == true
                ? "Removing old data must finish before these settings can be used." : "Select an available Space."
            return
        }
        let path = store.independentEngineProfilePath(for: profileID)
        PCNativeBrowserApplication.searchPreferences(profilePath: path) { [weak self] preferences, error in
            MainActor.assumeIsolated {
                guard let self, self.searchGeneration == generation, self.editedProfileID == profileID else { return }
                self.searchPreferences = preferences
                self.engine.removeAllItems()
                guard let preferences, preferences.profilePath == path else {
                    self.engine.addItem(withTitle: "Unavailable")
                    self.searchNote = error?.localizedDescription ?? "Search settings are unavailable."
                    return
                }
                for choice in preferences.engines {
                    self.engine.addItem(withTitle: choice.name)
                    self.engine.lastItem?.representedObject = SearchChoice(choice, preferences)
                    self.engine.lastItem?.isEnabled = choice.canMakeDefault || choice.identifier == preferences.defaultIdentifier
                    if choice.identifier == preferences.defaultIdentifier { self.engine.select(self.engine.lastItem) }
                }
                if preferences.defaultIdentifier == nil {
                    self.engine.insertItem(withTitle: "No default search engine", at: 0); self.engine.selectItem(at: 0)
                    self.engine.item(at: 0)?.isEnabled = false
                }
                self.engine.isEnabled = preferences.defaultEditable && !preferences.engines.isEmpty
                self.searchSuggestions.state = preferences.suggestionsEnabled ? .on : .off
                self.searchSuggestions.isEnabled = preferences.suggestionsEditable
                if let message { self.searchNote = message }
                else if preferences.defaultManaged || preferences.suggestionsManaged {
                    self.searchNote = "Some search settings are managed by your organization."
                } else if preferences.defaultExtensionControlled {
                    self.searchNote = "An extension controls this Space’s default search engine."
                } else {
                    self.searchNote = ""
                }
                self.refreshDownloadPreferences()
            }
        }
    }
    @objc private func searchEngineChanged() {
        guard let choice = engine.selectedItem?.representedObject as? SearchChoice,
              let profileID = editedProfileID,
              choice.preferences.profilePath == store.independentEngineProfilePath(for: profileID) else {
            refreshSearchPreferences(); return
        }
        if choice.identifier == choice.preferences.defaultIdentifier { return }
        do {
            _ = try PCNativeBrowserApplication.setDefaultSearchEngine(choice.identifier, for: choice.preferences)
            refreshSearchPreferences()
        } catch { refreshSearchPreferences(message: error.localizedDescription) }
    }
    @objc private func searchSuggestionsChanged() {
        guard let current = searchPreferences, let profileID = editedProfileID,
              current.profilePath == store.independentEngineProfilePath(for: profileID) else {
            refreshSearchPreferences(); return
        }
        do {
            _ = try PCNativeBrowserApplication.setSearchSuggestionsEnabled(searchSuggestions.state == .on, for: current)
            refreshSearchPreferences()
        } catch { refreshSearchPreferences(message: error.localizedDescription) }
    }
    @objc private func restoreChanged() {
        do { try store.saveRestoreSession(restore.state == .on) }
        catch { restore.state = store.state.settings.restoreSession ? .on : .off; reportProfileSettingsError(error) }
    }
    private func refreshWindowDragging(_ state: WebpageWindowDraggingPreferences.State) {
        windowDragging.state = state.isEnabled ? .on : .off
        windowDragging.isEnabled = !WebpageWindowDraggingPreferences.shared.loadError
        windowDragging.toolTip = windowDragging.isEnabled ? nil : "The existing window dragging preference could not be read."
    }
    @objc private func windowDraggingChanged() {
        do { try WebpageWindowDraggingPreferences.shared.setEnabled(windowDragging.state == .on) }
        catch { refreshWindowDragging(WebpageWindowDraggingPreferences.shared.state); reportProfileSettingsError(error) }
    }

    private func refreshFeedbackPreferences(_ state: InterfaceFeedbackPreferences.State) {
        soundEffects.state = state.playsSoundEffects ? .on : .off
        reorderingHaptics.state = state.reorderingHaptics ? .on : .off
        for button in [soundEffects, reorderingHaptics] {
            button.isEnabled = !InterfaceFeedbackPreferences.shared.loadError
            button.toolTip = button.isEnabled ? nil : "The existing feedback preferences could not be read."
        }
    }
    @objc private func soundEffectsChanged() {
        do { try InterfaceFeedbackPreferences.shared.setPlaysSoundEffects(soundEffects.state == .on) }
        catch { refreshFeedbackPreferences(InterfaceFeedbackPreferences.shared.state); reportProfileSettingsError(error) }
    }
    @objc private func reorderingHapticsChanged() {
        do { try InterfaceFeedbackPreferences.shared.setReorderingHaptics(reorderingHaptics.state == .on) }
        catch { refreshFeedbackPreferences(InterfaceFeedbackPreferences.shared.state); reportProfileSettingsError(error) }
    }

    private func refreshToolbarPreferences() {
        toolbarFullURL.state = BrowserToolbarPreferences.shared.state.showsFullURL ? .on : .off
        toolbarFullURL.isEnabled = !BrowserToolbarPreferences.shared.loadError
        toolbarFullURL.toolTip = toolbarFullURL.isEnabled ? nil : "The existing Toolbar preferences could not be read."
    }
    private func refreshSharedQuotes() {
        sharedQuotes.state = SharedQuotePreferences.shared.state.isEnabled ? .on : .off
        sharedQuotes.isEnabled = !SharedQuotePreferences.shared.loadError
        sharedQuotes.toolTip = sharedQuotes.isEnabled ? nil : "The existing Shared Quote preferences could not be read."
    }
    @objc private func sharedQuotesChanged() {
        do { try SharedQuotePreferences.shared.setEnabled(sharedQuotes.state == .on) }
        catch { reportProfileSettingsError(error) }
        refreshSharedQuotes()
    }
    private func refreshWebsiteTheme(_ state: WebsiteThemePreferences.State) {
        websiteTheme.state = state.isEnabled ? .on : .off
        websiteTheme.isEnabled = !WebsiteThemePreferences.shared.loadError
        websiteTheme.toolTip = websiteTheme.isEnabled ? nil : "The saved theme sharing preference could not be read."
    }
    private func refreshQuitWarning(_ state: QuitWarningPreferences.State) {
        warnBeforeQuitting.state = state.isEnabled ? .on : .off
        warnBeforeQuitting.isEnabled = !QuitWarningPreferences.shared.loadError
        warnBeforeQuitting.toolTip = warnBeforeQuitting.isEnabled ? nil
            : QuitWarningPreferences.Failure.unavailable.localizedDescription
    }
    private func refreshDefaultBrowser(_ state: DefaultBrowserController.State) {
        membershipPane.showDefaultBrowserPrompt(DefaultBrowserController.shared.isApplication && !state.isDefault,
                                                waiting: state.isRequesting, failure: state.failure)
    }
    @objc private func makeDefaultBrowser() {
        DefaultBrowserController.shared.makeDefault()
    }
    @objc private func quitWarningChanged() {
        do { try QuitWarningPreferences.shared.setEnabled(warnBeforeQuitting.state == .on) }
        catch { refreshQuitWarning(QuitWarningPreferences.shared.state); reportProfileSettingsError(error) }
    }
    @objc private func websiteThemeChanged() {
        do { try WebsiteThemePreferences.shared.setEnabled(websiteTheme.state == .on) }
        catch { refreshWebsiteTheme(WebsiteThemePreferences.shared.state); reportProfileSettingsError(error) }
    }
    @objc private func toolbarFullURLChanged() {
        do { try BrowserToolbarPreferences.shared.setShowsFullURL(toolbarFullURL.state == .on) }
        catch { refreshToolbarPreferences(); reportProfileSettingsError(error) }
    }
}

@MainActor
final class SettingsSplitViewController: NSSplitViewController {
    override func toggleSidebar(_ sender: Any?) {}
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(toggleSidebar(_:)) ? false : super.validateUserInterfaceItem(item)
    }
}

@MainActor
final class SettingsPaneHost: NSView {
    private(set) var pane: NSView?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func show(_ next: NSView, animated: Bool) {
        guard pane !== next else { return }
        if animated, pane != nil {
            let fade = CATransition()
            fade.type = .fade; fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(fade, forKey: "pane")
        }
        pane?.removeFromSuperview()
        if let scroll = next as? NSScrollView {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsetsZero
        }
        next.autoresizingMask = []
        addSubview(next); pane = next
        layoutPane()
    }
    override func layout() { super.layout(); layoutPane() }
    private func layoutPane() {
        let top = safeAreaInsets.top
        pane?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - top))
    }
}
