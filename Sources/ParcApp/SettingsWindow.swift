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
    private let searchHelp = NSTextField(wrappingLabelWithString: "")
    private var searchMessage: String?
    private var generalLocks = AppWidePreferenceController.Locks()
    private var searchNote = "" {
        didSet {
            engine.toolTip = searchNote.isEmpty ? nil : searchNote; engine.setAccessibilityHelp(engine.toolTip)
            searchHelp.stringValue = searchNote; searchHelp.toolTip = searchNote
            searchHelp.isHidden = searchNote.isEmpty
            layoutGeneralPane()
        }
    }
    private var searchPreferences: PCNativeSearchPreferences?
    private var searchGeneration: UInt64 = 0
    private var searchSubscription: AnyCancellable?
    @MainActor
    private final class SearchChoice: NSObject {
        let identifier: String
        let keyword: String
        let preferences: PCNativeSearchPreferences
        init(_ engine: PCNativeSearchEngine, _ preferences: PCNativeSearchPreferences) {
            identifier = engine.identifier; keyword = engine.keyword; self.preferences = preferences
        }
    }
    private let archive = PointingHandPopUpButton()
    private let archiveInfo = PointingHandButton()
    private var archiveInfoPopover: NSPopover?
    private var archiveScopeAlert: PArcDialog?
    private var archiveScopeChange: AutoArchiveProfileChange?
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
        case membership = "Membership", general = "General", profiles = "Profiles", links = "Links", shortcuts = "Shortcuts", icon = "Icon", advanced = "Advanced"
        var symbol: String {
            switch self { case .membership: return "person.crop.square.filled.and.at.rectangle"; case .general: return "gearshape"; case .profiles: return "person"; case .shortcuts: return "keyboard"; case .icon: return "app"; case .links: return "macwindow.on.rectangle"; case .advanced: return "slider.horizontal.3" }
        }
    }
    enum Destination: Equatable {
        case pane(Pane), profile(UUID)
        var pane: Pane { if case .pane(let pane) = self { return pane }; return .profiles }
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
    private var profileEditor = NSScrollView()
    private let profileList = SettingsGroupView(frame: NSRect(x: SettingsLayout.margin, y: 0, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight))
    private var profileRows: [UUID: SettingsProfileButton] = [:]
    private struct ProfileRowState: Equatable { let id: UUID; let name: String; let detail: String }
    private var renderedProfileRows: [ProfileRowState] = []
    private let newProfile = SettingsPillButton(title: "New Profile…")
    private var selectedProfileID: UUID?
    private let profileNameValue = NSTextField(labelWithString: "")
    private let renameProfile = SettingsPillButton(title: "Rename…")
    private var profileNameDialog: (dialog: PArcDialog, profileID: UUID)?
    private var previewSettingsSheet: SidebarPreviewSettingsSheet?
    private let removeProfile = SettingsPillButton(title: "Delete Profile…")
    private var removalSubscription: AnyCancellable?
    private var membershipSubscription: AnyCancellable?

    private let downloadLocationPicker = DownloadLocationPicker()
    private let downloadHelp = NSTextField(wrappingLabelWithString: "")
    private var profilePageButtons: [ProfileSettingsPage: NSButton] = [:]
    var onProfileSettingsPage: ((UUID, UUID, ProfileSettingsPage) -> Bool)?
    private let moreSettings = SettingsPillButton(title: "More Settings…")
    private let exportData = SettingsPillButton(title: "Export Data")
    private let replay = SettingsPillButton(title: "Replay onboarding")
    private let adjustWindowFrame = SettingsPillButton(title: "Adjust")
    private let windowFrameValue = NSTextField(labelWithString: "")
    private var windowFrameSubscription: AnyCancellable?
    private var dataExportPanel: NSSavePanel?
    private var dataExportID: UUID?
    var onMoreSettings: ((UUID, UUID) -> Bool)?
    private var downloadPreferences: PCNativeDownloadPreferences?
    private var downloadFolderPanel: NSOpenPanel?
    private var downloadPreferencesGeneration: UInt64 = 0
    private let downloadRetry = PointingHandButton(title: "Retry", target: nil, action: nil)
    private var subscription: AnyCancellable?
    private var displayedProfileID: UUID?
    private var displayedSpaceID: UUID?
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
        selectedProfileID = store.state.profiles.first { $0.id == applicationProfileID }?.id
            ?? store.state.profiles.first { $0.id == savedProfileID }?.id
            ?? store.state.spaces.first { $0.id == spaceID }?.profileID
            ?? store.state.profiles.first?.id
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
        panes[.profiles] = makeProfilesPane()
        profileEditor = makeProfileEditorPane()
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
        showPane(store.state.settings.settingsPane.flatMap(Pane.init(rawValue:)) ?? .membership, persist: false)
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
        engine.setAccessibilityLabel("Default search engine")
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
        searchHelp.isHidden = true
        moreSettings.target = self; moreSettings.action = #selector(openMoreSettings)
        exportData.target = self; exportData.action = #selector(exportBrowserData)
        replay.target = self; replay.action = #selector(replayWelcome)
        adjustWindowFrame.target = self; adjustWindowFrame.action = #selector(adjustWindowFrameSelected)
        adjustWindowFrame.setAccessibilityLabel("Adjust window frame")
        windowFrameSubscription = WindowFramePreferences.shared.$state.receive(on: RunLoop.main).sink { [weak self] state in
            self?.refreshWindowFrame(state)
        }
        exportData.setAccessibilityHelp("Export your Spaces and saved tab links as Markdown.")
        moreSettings.setAccessibilityHelp(applicationProfileID == nil ? "Open browser settings for this window’s Space and profile." : "Open browser settings for the original regular profile.")
        removeProfile.destructive = true
        removeProfile.setAccessibilityLabel("Delete profile")
        removeProfile.target = self; removeProfile.action = #selector(deleteSelectedProfile)
        renameProfile.toolTip = "Rename profile"
        renameProfile.setAccessibilityLabel("Rename profile")
        renameProfile.target = self; renameProfile.action = #selector(renameSelectedProfile)
        newProfile.target = self; newProfile.action = #selector(addProfile)
        newProfile.setAccessibilityLabel("New profile")
        newProfile.toolTip = applicationProfileID == nil ? "Create a profile for this Space" : "Create a regular profile"
        profileNameValue.font = .systemFont(ofSize: 13); profileNameValue.textColor = .secondaryLabelColor
        profileNameValue.alignment = .right; profileNameValue.lineBreakMode = .byTruncatingTail
        for field in [downloadHelp, searchHelp] {
            field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor
        }
    }
    @objc private func deleteSelectedProfile() { showProfileRemoval() }
    @objc private func renameSelectedProfile() { showProfileNameEditor() }
    @objc private func addProfile() { createProfile() }

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
        place(searchHelp, in: searching, NSRect(x: 12, y: rowHeight * 3 + 6, width: SettingsLayout.groupWidth - 24, height: 32))
        let downloadsTitle = SettingsSectionHeading(title: "Downloads")
        content.addSubview(downloadsTitle)
        let downloads = group(in: content, y: 0, height: SettingsLayout.rowHeight)
        downloadLocationPicker.rowTitle = label("Download location", in: downloads, NSRect(x: 12, y: 12, width: 160, height: 18))
        place(downloadLocationPicker, in: downloads, NSRect(x: SettingsLayout.groupWidth - 12 - DownloadLocationPicker.width, y: 7,
                                                            width: DownloadLocationPicker.width, height: 28))
        place(downloadHelp, in: downloads, NSRect(x: 12, y: 50, width: SettingsLayout.groupWidth - 120, height: 32))
        place(downloadRetry, in: downloads, NSRect(x: SettingsLayout.groupWidth - 82, y: 52, width: 70, height: 28))

        let onboardingTitle = SettingsSectionHeading(title: "Onboarding")
        content.addSubview(onboardingTitle)
        let onboarding = group(in: content, y: 0, height: noteHeight + 6)
        label("Replay onboarding", in: onboarding, NSRect(x: SettingsLayout.rowInset, y: 10, width: 300, height: 18))
        label("Replay the full welcome and setup. Finishing applies your choices to this Space; existing tabs stay.",
              in: onboarding, NSRect(x: SettingsLayout.rowInset, y: 30,
                                     width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 3 - replay.fittingWidth, height: 28), help: true)
        trailingPill(replay, in: onboarding, top: 0, rowHeight: noteHeight + 6)
        generalLayout = GeneralLayout(quitting: quitting,
                                      sections: [(frameTitle, frame), (previewsTitle, preferences), (searchTitle, searching),
                                                 (downloadsTitle, downloads), (onboardingTitle, onboarding)],
                                      search: searching, downloads: downloads, content: content)
        layoutGeneralPane()
        return scroll
    }

    private struct GeneralLayout {
        let quitting: SettingsGroupView
        let sections: [(NSTextField, SettingsGroupView)]
        let search: SettingsGroupView
        let downloads: SettingsGroupView
        let content: LayoutView
    }
    private var generalLayout: GeneralLayout?

    private func layoutGeneralPane() {
        guard let layout = generalLayout else { return }
        let rowHeight = SettingsLayout.rowHeight
        layout.search.setFrameSize(NSSize(width: SettingsLayout.groupWidth, height: rowHeight * 3 + (searchHelp.isHidden ? 0 : 44)))
        let note = !downloadHelp.isHidden || !downloadRetry.isHidden
        layout.downloads.setFrameSize(NSSize(width: SettingsLayout.groupWidth, height: rowHeight + (note ? 44 : 0)))
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

    private func makeProfilesPane() -> NSScrollView {
        let (scroll, content) = pane()
        let intro = NSTextField(labelWithAttributedString: profilesIntroduction())
        intro.isSelectable = true; intro.allowsEditingTextAttributes = true
        intro.maximumNumberOfLines = 3; intro.lineBreakMode = .byWordWrapping
        place(intro, in: content, NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset, y: 18,
                                         width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: 46))
        let listY: CGFloat = 104
        heading("Your Profiles", in: content, above: listY)
        profileList.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: listY))
        profileList.setAccessibilityElement(true)
        profileList.setAccessibilityRole(.group)
        profileList.setAccessibilityLabel("Your Profiles")
        content.addSubview(profileList)
        content.addSubview(newProfile)
        layoutProfileList()
        return scroll
    }

    private func layoutProfileList() {
        let height = max(SettingsLayout.rowHeight, CGFloat(renderedProfileRows.count) * SettingsLayout.rowHeight)
        profileList.setFrameSize(NSSize(width: SettingsLayout.groupWidth, height: height))
        newProfile.frame = NSRect(x: profileList.frame.maxX - newProfile.fittingWidth, y: profileList.frame.maxY + 12,
                                  width: newProfile.fittingWidth, height: SettingsLayout.buttonHeight)
        if let content = profileList.superview {
            content.setFrameSize(NSSize(width: content.frame.width, height: max(SettingsLayout.contentHeight, newProfile.frame.maxY + 20)))
        }
    }

    private func renderProfileList() {
        let rows = store.state.profiles.map { profile -> ProfileRowState in
            let count = store.state.spaces.filter { $0.profileID == profile.id }.count
            let detail = store.isProfileRemovalPending(profile.id)
                ? (ProfileRemovalController.shared.status(for: profile.id)?.running == true ? "Removing…" : "Retry")
                : "\(count) \(count == 1 ? "Space" : "Spaces")"
            return ProfileRowState(id: profile.id, name: profile.name, detail: detail)
        }
        guard rows != renderedProfileRows else { return }
        let focused = profileRows.first { window?.firstResponder === $0.value }?.key
        renderedProfileRows = rows
        profileList.subviews.forEach { $0.removeFromSuperview() }
        profileRows.removeAll()
        for (index, row) in rows.enumerated() {
            let top = CGFloat(index) * SettingsLayout.rowHeight
            if index > 0 { profileList.separator(at: top) }
            let button = SettingsProfileButton { [weak self] in self?.openProfile(row.id) }
            button.update(name: row.name, detail: row.detail)
            button.setAccessibilityIdentifier("settings.profile.row." + row.id.uuidString)
            button.frame = NSRect(x: 0, y: top, width: SettingsLayout.groupWidth, height: SettingsLayout.rowHeight)
            profileList.addSubview(button)
            profileRows[row.id] = button
        }
        layoutProfileList()
        if selectedPane == .profiles, shownDestination == .pane(.profiles), let content = panes[.profiles] {
            connectKeyViews(in: content)
        }
        if let focused, let row = profileRows[focused] { window?.makeFirstResponder(row) }
    }

    private func openProfile(_ id: UUID) {
        guard store.state.profiles.contains(where: { $0.id == id }) else { return }
        show(.profile(id))
    }

    private func makeProfileEditorPane() -> NSScrollView {
        let (scroll, content) = pane()
        let rowHeight = SettingsLayout.rowHeight
        let identity = group(in: content, y: 20, height: rowHeight)
        rowLabel("Profile Name", in: identity, row: 0, width: 160)
        trailingPill(renameProfile, in: identity, top: 0)
        place(profileNameValue, in: identity, NSRect(x: 180, y: 12,
                                                     width: SettingsLayout.groupWidth - 180 - SettingsLayout.rowInset * 2 - renameProfile.fittingWidth, height: 18))

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
        content.addSubview(removeProfile)
        profileEditorLayout = ProfileEditorLayout(identity: identity, sections: [(browsingTitle, tabs), (dataTitle, data)],
                                                  content: content)
        layoutProfileCards()
        return scroll
    }

    private struct ProfileEditorLayout {
        let identity: SettingsGroupView
        let sections: [(NSTextField, SettingsGroupView)]
        let content: LayoutView
    }
    private var profileEditorLayout: ProfileEditorLayout?

    private func layoutProfileCards() {
        guard let layout = profileEditorLayout else { return }
        var bottom = layout.identity.frame.maxY
        for (title, group) in layout.sections {
            let top = bottom + SettingsLayout.headingSpacing
            group.setFrameOrigin(NSPoint(x: SettingsLayout.margin, y: top))
            title.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.rowInset,
                                 y: top - SettingsLayout.headingGap - SettingsLayout.headingHeight,
                                 width: SettingsLayout.groupWidth - SettingsLayout.rowInset * 2, height: SettingsLayout.headingHeight)
            bottom = group.frame.maxY
        }
        let buttonsY = bottom + 20
        let deleteWidth = max(removeProfile.fittingWidth, 120)
        removeProfile.frame = NSRect(x: SettingsLayout.margin + SettingsLayout.groupWidth - deleteWidth, y: buttonsY,
                                     width: deleteWidth, height: SettingsLayout.buttonHeight)
        if let clear = profilePageButtons[.clearBrowsingData] as? SettingsPillButton {
            clear.frame = NSRect(x: removeProfile.frame.minX - 12 - clear.fittingWidth, y: buttonsY,
                                 width: clear.fittingWidth, height: SettingsLayout.buttonHeight)
        }
        layout.content.setFrameSize(NSSize(width: layout.content.frame.width,
                                           height: max(SettingsLayout.contentHeight, buttonsY + SettingsLayout.buttonHeight + 20)))
    }

    private func profilesIntroduction() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12)
        let text = NSMutableAttributedString(string: "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces. ",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        text.append(NSAttributedString(string: "Learn more.", attributes: [.font: font,
            .link: URL(string: "https://resources.arc.net/hc/en-us/articles/19227964556183-Profiles-Separate-Work-Personal-Browsing")!]))
        return text
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

    @discardableResult func showAutoArchiveSettings(profileID: UUID) -> Bool {
        guard let window, window.attachedSheet == nil,
              store.state.profiles.contains(where: { $0.id == profileID }),
              !store.isProfileRemovalPending(profileID) else { return false }
        do { try store.saveSettingsSelection(pane: Pane.profiles.rawValue, profileID: profileID) }
        catch { reportProfileSettingsError(error); return false }
        cancelDownloadFolderSelection()
        selectedProfileID = profileID
        show(.profile(profileID), persist: false)
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
        case .profile(let id): return store.state.profiles.contains(where: { $0.id == id }) ? profileEditor : nil
        }
    }

    private func title(for destination: Destination?) -> String {
        switch destination {
        case .pane(.membership)?: return membershipPane.displayName
        case .pane(let pane)?: return pane.rawValue
        case .profile?: return "Edit Profile"
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
        if case .profile(let id) = destination, id != selectedProfileID {
            if persist {
                do { try store.saveSettingsSelection(pane: pane.rawValue, profileID: id) }
                catch { syncChrome(); reportProfileSettingsError(error); return false }
            }
            cancelDownloadFolderSelection()
            selectedProfileID = id
            refresh()
        } else if persist {
            do { try store.saveSettingsSelection(pane: pane.rawValue, profileID: selectedProfileID) }
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
        selectedPane.rawValue + (shownDestination.flatMap { if case .profile(let id) = $0 { return ":" + id.uuidString }; return nil } ?? "")
    }

    private var profileFallback: NSView? {
        guard selectedPane == .profiles else { return nil }
        if case .profile? = shownDestination { return renameProfile }
        return store.state.profiles.first(where: { $0.id == selectedProfileID }).flatMap { profileRows[$0.id] }
            ?? store.state.profiles.first.flatMap { profileRows[$0.id] }
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
            if context?.hasPrefix(Pane.profiles.rawValue + ":") == true, self.selectedPane == .profiles,
               context != self.focusContext {
                if let window = self.window, let content = window.contentView {
                    self.focusState.restore(in: window, root: content, context: nil, fallback: self.profileFallback)
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

    private func pruneRemovedProfiles() {
        let ids = Set(store.state.profiles.map(\.id))
        let removed: (Destination) -> Bool = { if case .profile(let id) = $0 { return !ids.contains(id) }; return false }
        let currentRemoved = shownDestination.map(removed) ?? false
        navigation.removeAll(where: removed, replacingCurrentWith: .pane(.profiles))
        if currentRemoved, !isClosing {
            if !show(.pane(.profiles), persist: false, record: false) {
                shownDestination = .pane(.profiles)
                syncChrome()
            }
        } else {
            updateNavigationControls()
        }
    }

    private func profilePageSpace() -> BrowserSpace? {
        store.settingsPageSpace(profileID: selectedProfileID, originatingSpaceID: contextSpaceID)
    }

    func refresh() {
        let space = store.state.spaces.first { $0.id == contextSpaceID }
        if !store.state.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = space?.profileID ?? store.state.profiles.first?.id
        }
        displayedSpaceID = space?.id
        displayedProfileID = selectedProfileID
        let removing = displayedProfileID.map(store.isProfileRemovalPending) ?? false
        archive.isEnabled = displayedProfileID != nil && !removing
        archiveInfo.isEnabled = archive.isEnabled
        if let change = archiveScopeChange,
           change.profileID != displayedProfileID || change.profiles != store.state.profiles || removing {
            cancelArchiveScopeSheet()
        }
        renameProfile.isEnabled = displayedProfileID != nil && !removing
        profileNameValue.stringValue = store.state.profiles.first { $0.id == displayedProfileID }?.name ?? ""
        if let id = displayedProfileID {
            if removing {
                let status = ProfileRemovalController.shared.status(for: id)
                removeProfile.isEnabled = status?.running != true || status?.canCancel == true
                removeProfile.toolTip = status?.running == true ? (status?.canCancel == true ? "Cancel this profile’s removal" : "This profile is being removed") : "Retry this profile’s removal"
                removeProfile.setLabel(status?.running == true ? (status?.canCancel == true ? "Cancel Removal" : "Removing…") : "Retry Removal")
            } else {
                removeProfile.setLabel("Delete Profile…")
                do {
                    _ = try store.profileRemovalSummary(id)
                    removeProfile.isEnabled = true
                    removeProfile.toolTip = "Delete profile"
                } catch {
                    removeProfile.isEnabled = false
                    removeProfile.toolTip = error.localizedDescription
                }
            }
        } else {
            removeProfile.setLabel("Delete Profile…")
            removeProfile.isEnabled = false
            removeProfile.toolTip = "Select an available profile."
        }
        if let editing = profileNameDialog,
           !store.state.profiles.contains(where: { $0.id == editing.profileID }) {
            cancelProfileNameEditor()
        }
        archive.removeAllItems()
        for choice in AutoArchiveInterval.settingsChoices {
            archive.addItem(withTitle: choice.title)
            archive.lastItem?.representedObject = choice.rawValue
        }
        let interval = displayedProfileID.flatMap { store.autoArchiveInterval(for: $0) } ?? .twelveHours
        if AutoArchiveInterval.settingsChoices.contains(interval) {
            archive.selectItem(at: AutoArchiveInterval.settingsChoices.firstIndex(of: interval)!)
        } else {
            archive.addItem(withTitle: "Saved setting: " + interval.title)
            archive.lastItem?.isEnabled = false
            archive.select(archive.lastItem)
        }
        let profileName = store.state.profiles.first { $0.id == displayedProfileID }?.name ?? "Default"
        archive.setAccessibilityHelp("Applies to all Spaces using the \(profileName) Profile.")
        for (page, button) in profilePageButtons {
            let available = (page == .search ? settingsContextSpace() : profilePageSpace()) != nil
            button.isEnabled = available && onProfileSettingsPage != nil
            button.toolTip = button.isEnabled ? nil : page == .search
                ? "Open Settings from a browser window to manage search."
                : "Use this profile for a Space to manage its browser settings."
        }
        moreSettings.isEnabled = settingsContextSpace() != nil && onMoreSettings != nil
        replay.isEnabled = replaySpaceID != nil && NSApp.delegate?.responds(to: #selector(AppDelegate.replayOnboarding(_:))) == true
        restore.state = store.state.settings.restoreSession ? .on : .off
        renderProfileList()
        layoutProfileCards()
        pruneRemovedProfiles()
        refreshDownloadPreferences()
        refreshSearchPreferences()
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
        cancelArchiveScopeSheet()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        downloadPreferencesGeneration &+= 1
        previewSettingsSheet?.dismiss()
        previewSettingsSheet = nil
        cancelPendingDataExport()
        cancelProfileNameEditor()
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

    private func showProfileRemoval() {
        guard let window, window.attachedSheet == nil,
              let profile = store.state.profiles.first(where: { $0.id == displayedProfileID }) else { return }
        let controller = ProfileRemovalController.shared
        if controller.status(for: profile.id)?.running == true {
            controller.cancel(profileID: profile.id)
            return
        }
        if store.isProfileRemovalPending(profile.id) {
            controller.remove(profileID: profile.id, expectedName: profile.name)
            return
        }
        let summary: ProfileRemovalSummary
        do { summary = try store.profileRemovalSummary(profile.id) }
        catch { reportProfileSettingsError(error); return }
        let tabs = summary.savedTabCount, entries = summary.historyEntryCount
        PArcDialog.confirm(in: window, title: "Delete your “\(profile.name)” Profile?",
                          message: "This permanently removes the Profile’s cookies, history, preferences and logins, plus its \(tabs) saved \(tabs == 1 ? "tab" : "tabs") and \(entries) local history \(entries == 1 ? "entry" : "entries"). Saved captures, downloaded files and Easels stay on this Mac.",
                          confirm: "Delete", destructive: true) { approved in
            if approved { ProfileRemovalController.shared.remove(profileID: profile.id, expectedName: profile.name) }
        }
    }

    private func reportRemovalFailures() {
        guard !isClosing, let window, window.isVisible, window.isKeyWindow, window.attachedSheet == nil else { return }
        for profile in store.state.profiles {
            guard let status = ProfileRemovalController.shared.claimFailure(for: profile.id) else { continue }
            PArcDialog.inform(in: window, .init(title: "Parc couldn’t delete “\(profile.name)”.", message: status.message))
            return
        }
    }

    private func showProfileNameEditor() {
        guard let window, window.attachedSheet == nil, profileNameDialog == nil,
              let profile = store.state.profiles.first(where: { $0.id == displayedProfileID }) else { return }
        let dialog = PArcDialog(.init(title: [("Rename your Profile", false)],
            message: [("This won’t affect the names of any of the Spaces associated with this Profile.", false)],
            confirm: "Save", cancel: "Cancel", field: .init(value: profile.name, placeholder: "Profile name")))
        guard let field = dialog.textField else { return }
        field.setAccessibilityLabel("Profile name")
        profileNameDialog = (dialog, profile.id)
        let began = dialog.begin(for: window) { [weak self, weak dialog] response in
            guard let self else { return }
            if self.profileNameDialog?.dialog === dialog { self.profileNameDialog = nil }
            if response == .confirm {
                do { try self.store.saveProfileName(profile.id, expectedName: profile.name, name: field.stringValue) }
                catch { self.reportProfileSettingsError(error) }
            }
            self.refresh()
        }
        if !began { profileNameDialog = nil }
    }

    private func cancelProfileNameEditor() {
        guard let editing = profileNameDialog else { return }
        profileNameDialog = nil
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

    private var showsProfileEditor: Bool {
        if case .profile(let id)? = shownDestination { return id == selectedProfileID }
        return false
    }

    private func openProfileSettingsPage(_ page: ProfileSettingsPage) {
        guard page == .search ? selectedPane == .general : (selectedPane == .profiles && showsProfileEditor),
              window?.isKeyWindow == true, window?.attachedSheet == nil else { return }
        guard let space = page == .search ? settingsContextSpace() : profilePageSpace(),
              onProfileSettingsPage?(space.id, space.profileID, page) == true else {
            reportSettingsCommandRefusal(page.title)
            return
        }
        _ = attemptClose()
    }

    private func reportSettingsCommandRefusal(_ title: String) {
        guard let window, window.attachedSheet == nil else { return }
        PArcDialog.inform(in: window, .init(title: "Parc couldn’t open " + title.trimmingCharacters(in: CharacterSet(charactersIn: "…")) + ".",
            message: "The original window or profile is unavailable or busy. Finish its current operation and try again."))
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
        (selectedPane == .general
            ? settingsContextSpace()?.id == spaceID
            : selectedPane == .profiles && showsProfileEditor && selectedProfileID == profileID && profilePageSpace()?.id == spaceID)
            && permitsPage(in: ownerStore, spaceID: spaceID, profileID: profileID)
    }

    @objc private func openMoreSettings() {
        guard window?.attachedSheet == nil, let space = settingsContextSpace(),
              let onMoreSettings else { return }
        if onMoreSettings(space.id, space.profileID) { _ = attemptClose(); return }
        guard let window else { return }
        PArcDialog.inform(in: window, .init(title: "Parc couldn’t open more settings.",
            message: "The original window or profile is busy. Finish its current operation and try again."), queued: true)
    }

    private func cancelDownloadFolderSelection() {
        let panel = downloadFolderPanel
        downloadFolderPanel = nil
        panel?.cancel(nil)
        if panel != nil { renderDownloadLocation() }
    }

    private var generalProfileID: UUID? {
        let id = settingsContextSpace()?.profileID ?? store.state.spaces.first?.profileID ?? store.state.profiles.first?.id
        return id.flatMap { id in store.state.profiles.contains { $0.id == id } && !store.isProfileRemovalPending(id) ? id : nil }
    }
    @objc private func retryDownloadPreferences() { refreshDownloadPreferences() }
    private func refreshDownloadPreferences(message: String? = nil) {
        downloadPreferencesGeneration &+= 1
        let generation = downloadPreferencesGeneration
        downloadRetry.isHidden = true
        guard let profileID = generalProfileID else {
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
                      self.generalProfileID == profileID else { return }
                self.downloadPreferences = preferences?.profilePath == path ? preferences : nil
                self.downloadRetry.isHidden = self.downloadPreferences != nil
                self.renderDownloadPreferences(message: error?.localizedDescription ??
                    (self.downloadPreferences == nil ? "Download settings couldn’t be loaded." : message))
            }
        }
    }
    private func renderDownloadLocation() {
        let current = downloadPreferences
        let stored = store.state.settings.appWidePreferences
        downloadLocationPicker.update(current.map { current in
            let directory = current.directoryManaged ? current.directoryURL
                : stored?.downloadDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? current.directoryURL
            let prompt = current.promptManaged ? current.promptForDownload : stored?.promptForDownload ?? current.promptForDownload
            return .init(directory: directory, prompt: prompt)
        },
                                      enabled: current.map { !$0.directoryManaged && !$0.promptManaged } ?? false,
                                      panelOpen: downloadFolderPanel != nil)
    }
    private func renderDownloadPreferences(message: String? = nil) {
        renderDownloadLocation()
        downloadHelp.maximumNumberOfLines = 2
        downloadHelp.lineBreakMode = .byWordWrapping
        downloadHelp.cell?.truncatesLastVisibleLine = true
        let locked = generalLocks.downloads
        downloadHelp.stringValue = message ?? (locked ? "Your organization manages download settings in at least one Space. Other Spaces follow this choice." : "")
        downloadHelp.toolTip = downloadHelp.stringValue
        downloadHelp.isHidden = downloadHelp.stringValue.isEmpty
        layoutGeneralPane()
    }
    private func reportDownloadPreferenceError(_ error: Error) {
        refreshDownloadPreferences(message: error.localizedDescription)
    }
    private func currentDownloadPreferences() -> PCNativeDownloadPreferences? {
        guard let profileID = generalProfileID, let current = downloadPreferences,
              current.profilePath == store.independentEngineProfilePath(for: profileID) else { return nil }
        return current
    }
    private func downloadLocationChosen(_ choice: DownloadLocationPicker.Choice) {
        guard let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged else {
            refreshDownloadPreferences(); return
        }
        if choice == .other { chooseDownloadDirectory(); return }
        do {
            try AppWidePreferenceController.shared.update { $0.promptForDownload = choice == .prompt }
            refreshDownloadPreferences()
        } catch { reportDownloadPreferenceError(error) }
    }
    private func chooseDownloadDirectory() {
        guard let window, window.attachedSheet == nil, downloadFolderPanel == nil,
              let current = currentDownloadPreferences(), !current.directoryManaged, !current.promptManaged,
              let profileID = generalProfileID else { downloadLocationPicker.revert(); return }
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
                  self.generalProfileID == profileID,
                  let url = panel.url else { self.refreshDownloadPreferences(); return }
            do {
                try AppWidePreferenceController.shared.update { $0.downloadDirectory = url.path; $0.promptForDownload = false }
                self.refreshDownloadPreferences()
            } catch { self.reportDownloadPreferenceError(error) }
        }
    }
    private func createProfile() {
        guard let window, window.attachedSheet == nil else { return }
        let revision = lifecycleRevision
        let spaceID = displayedSpaceID
        let originalSpace = store.state.spaces.first { $0.id == spaceID }
        let dialog = PArcDialog(.init(title: [("New local profile", false)],
            message: [(spaceID == nil
                ? "A profile keeps its own cookies and website sessions. You can assign it to a regular Space later."
                : "A profile keeps its own cookies and website sessions. This Space will use the new profile.", false)],
            confirm: "Create", cancel: "Cancel", field: .init(value: "", placeholder: "Profile name")))
        guard let field = dialog.textField else { return }
        field.setAccessibilityLabel("New profile name")
        _ = dialog.begin(for: window) { [weak self, weak window] response in
            guard let self, let window, self.window === window, window.isVisible,
                  !self.isClosing, self.lifecycleRevision == revision,
                  response == .confirm else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            do {
                let id = try self.store.createProfilePersisted(name: name)
                self.selectedProfileID = id
                if let originalSpace {
                    self.store.assignProfile(id, toSpace: originalSpace.id, shouldCommit: { [weak self, weak window] in
                        guard let self, let window else { return false }
                        return self.window === window && window.isVisible && !self.isClosing
                            && self.lifecycleRevision == revision && self.displayedSpaceID == originalSpace.id
                            && self.store.state.spaces.contains { $0.id == originalSpace.id && $0.profileID == originalSpace.profileID }
                    }, completion: { [weak self] result in
                        guard let self, self.lifecycleRevision == revision, !self.isClosing else { return }
                        if case .failure(let error) = result { self.reportProfileSettingsError(error) }
                        self.refresh()
                    })
                }
                self.refresh()
                try self.store.saveSettingsSelection(pane: self.selectedPane.rawValue, profileID: id)
                self.show(.profile(id), persist: false)
            } catch { self.reportProfileSettingsError(error) }
        }
    }
    @objc private func archiveChanged() {
        guard let window, window.attachedSheet == nil, let profileID = displayedProfileID,
              profileID == selectedProfileID, !store.isProfileRemovalPending(profileID),
              let hours = archive.selectedItem?.representedObject as? Double,
              let interval = AutoArchiveInterval(rawValue: hours),
              AutoArchiveInterval.settingsChoices.contains(interval) else { refresh(); return }
        do {
            guard let change = try store.changeAutoArchiveInterval(interval, for: profileID) else { return }
            var content = PArcDialog.Content(title: "Parc will now archive your tabs after \(interval.durationTitle)",
                message: "Would you like to apply this change to all of your Profiles, or only your \(change.profileName) Profile?",
                confirm: "All Profiles")
            content.secondary = "Only this Profile"
            let dialog = PArcDialog(content)
            archiveScopeChange = change; archiveScopeAlert = dialog
            _ = dialog.begin(for: window) { [weak self, weak dialog, weak window] response in
                guard let self, let dialog, self.archiveScopeAlert === dialog,
                      self.window === window else { return }
                self.archiveScopeAlert = nil; self.archiveScopeChange = nil
                guard response == .confirm,
                      self.displayedProfileID == change.profileID,
                      self.selectedProfileID == change.profileID else { return }
                do { try self.store.applyAutoArchiveIntervalToAllProfiles(change) }
                catch { self.refresh(); self.reportProfileSettingsError(error) }
            }
        } catch { refresh(); reportProfileSettingsError(error) }
    }

    private func cancelArchiveScopeSheet() {
        guard let dialog = archiveScopeAlert else { return }
        archiveScopeAlert = nil; archiveScopeChange = nil
        dialog.panel.sheetParent?.endSheet(dialog.panel, returnCode: .cancel)
        dialog.panel.orderOut(nil)
    }

    @objc private func showArchiveInformation() {
        guard archiveInfo.isEnabled, window?.attachedSheet == nil else { return }
        if archiveInfoPopover?.isShown == true { archiveInfoPopover?.close(); return }
        let controller = NSViewController()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 126))
        let text = NSTextField(wrappingLabelWithString: "Parc automatically archives inactive Today tabs after this Profile’s selected interval. Pinned tabs and Favorites stay put. Find automatically closed tabs in Library → Archive and choose Put Back to restore them.")
        text.font = .systemFont(ofSize: 12)
        text.frame = content.bounds.insetBy(dx: 14, dy: 14)
        content.addSubview(text); controller.view = content
        let popover = NSPopover(); popover.behavior = .transient
        popover.contentViewController = controller
        archiveInfoPopover = popover
        popover.show(relativeTo: archiveInfo.bounds, of: archiveInfo, preferredEdge: .maxY)
    }
    private func renderSearchNote() {
        if let searchMessage { searchNote = searchMessage; return }
        var lines: [String] = []
        if generalLocks.search { lines.append("Your organization or an extension controls the default search engine in at least one Space.") }
        if generalLocks.suggestions { lines.append("Your organization manages search suggestions in at least one Space.") }
        searchNote = lines.joined(separator: " ")
    }
    private func refreshSearchPreferences(message: String? = nil) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchPreferences = nil; engine.isEnabled = false; searchSuggestions.isEnabled = false
        engine.removeAllItems(); engine.addItem(withTitle: "Loading…")
        searchMessage = message; renderSearchNote()
        guard let profileID = generalProfileID else {
            engine.removeAllItems(); engine.addItem(withTitle: "Unavailable")
            generalLocks = AppWidePreferenceController.Locks()
            searchMessage = "Search settings are unavailable."; renderSearchNote()
            return
        }
        let path = store.independentEngineProfilePath(for: profileID)
        PCNativeBrowserApplication.searchPreferences(profilePath: path) { [weak self] preferences, error in
            MainActor.assumeIsolated {
                guard let self, self.searchGeneration == generation, self.generalProfileID == profileID else { return }
                self.searchPreferences = preferences
                self.engine.removeAllItems()
                guard let preferences, preferences.profilePath == path else {
                    self.engine.addItem(withTitle: "Unavailable")
                    self.generalLocks = AppWidePreferenceController.Locks()
                    self.searchMessage = error?.localizedDescription ?? "Search settings are unavailable."; self.renderSearchNote()
                    return
                }
                let wanted = self.store.state.settings.appWidePreferences?.searchKeyword.map(AppWidePreferences.normalizedKeyword)
                let wantedIdentifier = preferences.defaultEditable
                    ? wanted.flatMap { keyword in preferences.engines.first { $0.canMakeDefault && AppWidePreferences.normalizedKeyword($0.keyword) == keyword }?.identifier }
                    : nil
                let selected = wantedIdentifier ?? preferences.defaultIdentifier
                for choice in preferences.engines {
                    self.engine.addItem(withTitle: choice.name)
                    self.engine.lastItem?.representedObject = SearchChoice(choice, preferences)
                    self.engine.lastItem?.isEnabled = choice.canMakeDefault || choice.identifier == selected
                    if choice.identifier == selected { self.engine.select(self.engine.lastItem) }
                }
                if selected == nil {
                    self.engine.insertItem(withTitle: "No default search engine", at: 0); self.engine.selectItem(at: 0)
                    self.engine.item(at: 0)?.isEnabled = false
                }
                self.engine.isEnabled = preferences.defaultEditable && !preferences.engines.isEmpty
                let suggestions = preferences.suggestionsEditable
                    ? self.store.state.settings.appWidePreferences?.searchSuggestions ?? preferences.suggestionsEnabled
                    : preferences.suggestionsEnabled
                self.searchSuggestions.state = suggestions ? .on : .off
                self.searchSuggestions.isEnabled = preferences.suggestionsEditable
                self.searchMessage = message; self.renderSearchNote()
                self.refreshDownloadPreferences()
                AppWidePreferenceController.shared.locks { [weak self] locks in
                    guard let self, self.searchGeneration == generation else { return }
                    self.generalLocks = locks
                    self.renderSearchNote()
                    self.renderDownloadPreferences()
                }
            }
        }
    }
    @objc private func searchEngineChanged() {
        guard let choice = engine.selectedItem?.representedObject as? SearchChoice,
              let profileID = generalProfileID,
              choice.preferences.profilePath == store.independentEngineProfilePath(for: profileID) else {
            refreshSearchPreferences(); return
        }
        do {
            try AppWidePreferenceController.shared.update { $0.searchKeyword = choice.keyword }
            refreshSearchPreferences()
        } catch { refreshSearchPreferences(message: error.localizedDescription) }
    }
    @objc private func searchSuggestionsChanged() {
        let enabled = searchSuggestions.state == .on
        do {
            try AppWidePreferenceController.shared.update { $0.searchSuggestions = enabled }
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
