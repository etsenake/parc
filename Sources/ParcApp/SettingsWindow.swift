import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSTableViewDataSource, NSTableViewDelegate, NSToolbarItemValidation {
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
        var identifier: NSToolbarItem.Identifier { .init("Parc.Settings." + rawValue) }
        var symbol: String {
            switch self { case .membership: return "person.crop.square.filled.and.at.rectangle"; case .general: return "gearshape"; case .profiles: return "person"; case .shortcuts: return "keyboard"; case .icon: return "app"; case .links: return "macwindow.on.rectangle"; case .advanced: return "slider.horizontal.3" }
        }
    }
    private let membershipPane: MembershipCardSettingsView
    private let shortcutsPane = ShortcutsSettingsView(shortcuts: .shared)
    private let iconPane = IconSettingsView(icons: .shared)
    private var selectedPane = Pane.general
    private let paneHost = SettingsPaneHost(frame: NSRect(x: 0, y: 0, width: 684, height: 562))
    private var panes: [Pane: NSScrollView] = [:]
    private let profileList = NSTableView()
    private var selectedProfileID: UUID?
    private var refreshingProfiles = false
    private let renameProfile = ActionButton("", symbol: "rectangle.and.pencil.and.ellipsis")
    private var profileNameSheet: ProfileNameSheet?
    private var previewSettingsSheet: SidebarPreviewSettingsSheet?
    private let removeProfile = ActionButton("", symbol: "minus")
    private var removalSubscription: AnyCancellable?

    private let downloadLocationPicker = DownloadLocationPicker()
    private let downloadHelp = NSTextField(wrappingLabelWithString: "")
    private var profilePageButtons: [ProfileSettingsPage: NSButton] = [:]
    var onProfileSettingsPage: ((UUID, UUID, ProfileSettingsPage) -> Bool)?
    private let moreSettings = SettingsPillButton(title: "More Settings…")
    private let exportData = SettingsPillButton(title: "Export Data")
    private let replay = SettingsPillButton(title: "Replay onboarding")
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
        let window = SettingsNativeWindow(contentRect: NSRect(x: 0, y: 0, width: 684, height: 562),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = Pane.general.rawValue
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
        window.contentView = paneHost
        configureControls()
        let membershipScroll = NSScrollView(frame: membershipPane.bounds)
        membershipScroll.drawsBackground = false; membershipScroll.hasVerticalScroller = true
        membershipScroll.autohidesScrollers = true; membershipScroll.documentView = membershipPane
        panes[.membership] = membershipScroll
        membershipPane.onNameChanged = { [weak self] _ in self?.refreshMembershipTitle() }
        membershipPane.onMakeDefault = { [weak self] in self?.makeDefaultBrowser() }
        panes[.general] = makeGeneralPane()
        panes[.profiles] = makeProfilesPane()
        panes[.advanced] = makeAdvancedPane()
        let shortcutScroll = NSScrollView(frame: shortcutsPane.bounds)
        shortcutScroll.drawsBackground = false; shortcutScroll.documentView = shortcutsPane
        panes[.shortcuts] = shortcutScroll
        let iconScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 684, height: 562))
        iconScroll.drawsBackground = false; iconScroll.hasVerticalScroller = true
        iconScroll.autohidesScrollers = true; iconScroll.documentView = iconPane
        panes[.icon] = iconScroll
        let linksScroll = NSScrollView(frame: iconScroll.frame)
        linksScroll.drawsBackground = false
        linksScroll.documentView = LinksSettingsView(store: store)
        panes[.links] = linksScroll
        let toolbar = NSToolbar(identifier: "Parc.Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = true
        window.toolbar = toolbar
        showPane(store.state.settings.settingsPane.flatMap(Pane.init(rawValue:)) ?? .membership, persist: false)
        subscription = store.statePublisher.map { state in
            Snapshot(settings: state.settings, profiles: state.profiles, spaces: state.spaces)
        }.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] snapshot in
            guard let self else { return }
            if let id = self.displayedProfileID, !snapshot.profiles.contains(where: { $0.id == id }) {
                self.cancelDownloadFolderSelection()
            }
            self.refresh()
        }
        searchSubscription = NotificationCenter.default.publisher(for: Notification.Name("PCNativeSearchPreferencesDidChange"))
            .receive(on: RunLoop.main).sink { [weak self] notification in
                guard let self, let id = self.displayedProfileID,
                      notification.object as? String == self.store.independentEngineProfilePath(for: id) else { return }
                self.refreshSearchPreferences()
            }
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
        engine.setAccessibilityLabel("Default search engine for this profile")
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
        exportData.setAccessibilityHelp("Export your Spaces and saved tab links as Markdown.")
        moreSettings.setAccessibilityHelp(applicationProfileID == nil ? "Open browser settings for this window’s Space and profile." : "Open browser settings for the original regular profile.")
        removeProfile.contentTintColor = .labelColor
        removeProfile.setAccessibilityLabel("Delete profile")
        removeProfile.actionBlock = { [weak self] in self?.showProfileRemoval() }
        renameProfile.contentTintColor = .labelColor
        renameProfile.toolTip = "Rename profile"
        renameProfile.setAccessibilityLabel("Rename profile")
        renameProfile.actionBlock = { [weak self] in self?.showProfileNameEditor() }
        for field in [downloadHelp] {
            field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor
        }
    }

    private func pane(height: CGFloat = 562) -> (NSScrollView, LayoutView) {
        let content = LayoutView(frame: NSRect(x: 0, y: 0, width: 684, height: height))
        content.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 684, height: 562))
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

    private func group(in parent: NSView, x: CGFloat = 64, y: CGFloat, width: CGFloat = 556, height: CGFloat) -> SettingsGroupView {
        let group = SettingsGroupView(frame: NSRect(x: x, y: y, width: width, height: height))
        parent.addSubview(group); return group
    }

    private func place(_ control: NSView, in parent: NSView, _ frame: NSRect) {
        if control is ActionButton { control.focusRingType = .exterior }
        control.frame = frame; parent.addSubview(control)
    }

    private func refreshMembershipTitle() {
        if selectedPane == .membership { window?.title = membershipPane.displayName }
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Pane.membership.identifier }) {
            item.label = membershipPane.displayName
            item.paletteLabel = membershipPane.displayName
        }
    }

    private func makeGeneralPane() -> NSScrollView {
        let (scroll, content) = pane()
        let quitting = group(in: content, y: 20, height: 37)
        label("Warn before quitting", in: quitting, NSRect(x: 10, y: 9, width: 480, height: 18))
        warnBeforeQuitting.setAccessibilityLabel("Warn before quitting")
        place(warnBeforeQuitting, in: quitting, NSRect(x: 508, y: 7, width: 38, height: 22))
        let preferences = group(in: content, y: 66, height: 89)
        label("Previews", in: preferences, NSRect(x: 10, y: 13, width: 300, height: 18))
        let previewSettings = SettingsPillButton(title: "Previews Settings…")
        previewSettings.target = self; previewSettings.action = #selector(openPreviewSettings)
        place(previewSettings, in: preferences, NSRect(x: 546 - previewSettings.fittingWidth, y: 10,
                                                      width: previewSettings.fittingWidth, height: 24))
        preferences.separator(at: 44)
        label("Manage your default search engine, Auto-Archive, and downloads in Profile Settings.",
              in: preferences, NSRect(x: 10, y: 50, width: 340, height: 34))
        let jump = SettingsPillButton(title: "Profile Settings…")
        jump.target = self; jump.action = #selector(openProfilesPane)
        place(jump, in: preferences, NSRect(x: 546 - jump.fittingWidth, y: 55, width: jump.fittingWidth, height: 24))
        let onboarding = group(in: content, y: 164, height: 82)
        label("Onboarding", in: onboarding, NSRect(x: 10, y: 13, width: 300, height: 18))
        place(replay, in: onboarding, NSRect(x: 546 - replay.fittingWidth, y: 10, width: replay.fittingWidth, height: 24))
        label("Replay the full welcome and setup. Finishing applies your choices to this Space; existing tabs stay.",
              in: onboarding, NSRect(x: 10, y: 44, width: 536, height: 32), help: true)
        return scroll
    }
    @objc private func openPreviewSettings() { showPreviewSettings() }
    @objc private func openProfilesPane() { showPane(.profiles) }

    private func makeProfilesPane() -> NSScrollView {
        let (scroll, content) = pane()
        let intro = NSTextField(labelWithAttributedString: profilesIntroduction())
        intro.isSelectable = true; intro.allowsEditingTextAttributes = true
        intro.maximumNumberOfLines = 2; intro.lineBreakMode = .byWordWrapping
        place(intro, in: content, NSRect(x: 64, y: 14, width: 556, height: 40))
        let list = group(in: content, y: 72, width: 206, height: 477)
        let heading = label("Your Profiles", in: list, NSRect(x: 16, y: 6, width: 174, height: 18))
        heading.font = .systemFont(ofSize: 13, weight: .semibold); heading.textColor = .secondaryLabelColor
        for y in [CGFloat(28), 445] {
            let rule = NSBox(frame: NSRect(x: 0, y: y, width: 206, height: 1)); rule.boxType = .separator; list.addSubview(rule)
        }
        let column = NSTableColumn(identifier: .init("profile"))
        column.width = 190
        profileList.addTableColumn(column)
        profileList.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        profileList.frame = NSRect(x: 0, y: 0, width: 190, height: 400)
        profileList.autoresizingMask = [.width]
        profileList.headerView = nil; profileList.rowHeight = 40
        profileList.intercellSpacing = .zero; profileList.style = .plain
        profileList.backgroundColor = .clear
        profileList.allowsEmptySelection = false
        profileList.dataSource = self; profileList.delegate = self
        profileList.setAccessibilityLabel("Your Profiles")
        let profileScroll = NSScrollView(frame: NSRect(x: 8, y: 38, width: 190, height: 400))
        profileScroll.drawsBackground = false
        profileScroll.hasVerticalScroller = true; profileScroll.autohidesScrollers = true
        profileScroll.documentView = profileList; list.addSubview(profileScroll)
        let add = ActionButton("", symbol: "plus") { [weak self] in self?.createProfile() }
        add.contentTintColor = .labelColor; add.setAccessibilityLabel("New profile")
        add.toolTip = applicationProfileID == nil ? "Create a profile for this Space" : "Create a regular profile"
        place(add, in: list, NSRect(x: 2, y: 447, width: 26, height: 26))
        place(removeProfile, in: list, NSRect(x: 33, y: 447, width: 26, height: 26))
        place(renameProfile, in: list, NSRect(x: 64, y: 447, width: 30, height: 26))
        for x in [CGFloat(30), 61] {
            let rule = NSBox(frame: NSRect(x: x, y: 452, width: 1, height: 19)); rule.boxType = .separator; list.addSubview(rule)
        }

        let searching = group(in: content, x: 280, y: 72, width: 340, height: 125)
        label("Search engine", in: searching, NSRect(x: 10, y: 13, width: 138, height: 18))
        place(engine, in: searching, NSRect(x: 150, y: 10, width: 180, height: 25))
        searching.separator(at: 44)
        label("Manage search", in: searching, NSRect(x: 10, y: 58, width: 150, height: 18))
        place(profilePageButton(.search), in: searching, NSRect(x: 200, y: 55, width: 130, height: 24))
        searching.separator(at: 89)
        label("Include search engine suggestions", in: searching, NSRect(x: 10, y: 99, width: 270, height: 18))
        searchSuggestions.setAccessibilityLabel("Include search engine suggestions")
        place(searchSuggestions, in: searching, NSRect(x: 292, y: 97, width: 38, height: 22))

        let downloads = group(in: content, x: 280, y: 206, width: 340, height: 129)
        downloadLocationPicker.rowTitle = label("Download location", in: downloads, NSRect(x: 10, y: 58, width: 132, height: 18))
        place(downloadLocationPicker, in: downloads, NSRect(x: 150, y: 54, width: DownloadLocationPicker.width, height: 28))
        place(downloadHelp, in: downloads, NSRect(x: 10, y: 92, width: 240, height: 32))
        place(downloadRetry, in: downloads, NSRect(x: 260, y: 94, width: 70, height: 28))

        label("Archive tabs after", in: downloads, NSRect(x: 10, y: 13, width: 116, height: 18))
        place(archiveInfo, in: downloads, NSRect(x: 128, y: 14, width: 16, height: 16))
        place(archive, in: downloads, NSRect(x: 150, y: 10, width: 180, height: 25))
        downloads.separator(at: 44)
        profileCards = downloads

        let dataTitle = label("Your Data and Settings", in: content, NSRect(x: 290, y: 306, width: 320, height: 18))
        dataTitle.textColor = .secondaryLabelColor
        let data = group(in: content, x: 280, y: 327, width: 340, height: 178)
        for (index, page) in [ProfileSettingsPage.privacy, .passwords, .payments, .notifications, .clearBrowsingData].enumerated() {
            place(profilePageButton(page), in: data, NSRect(x: 10, y: 5 + CGFloat(index) * 34, width: 320, height: 34))
        }
        profileDataTitle = dataTitle; profileData = data
        layoutProfileCards()
        return scroll
    }

    private weak var profileCards: SettingsGroupView?
    private weak var profileDataTitle: NSTextField?
    private weak var profileData: SettingsGroupView?

    private func layoutProfileCards() {
        guard let cards = profileCards, let title = profileDataTitle, let data = profileData else { return }
        let note = !downloadHelp.isHidden || !downloadRetry.isHidden
        cards.setFrameSize(NSSize(width: cards.frame.width, height: note ? 129 : 89))
        title.setFrameOrigin(NSPoint(x: title.frame.minX, y: cards.frame.maxY + 11))
        data.setFrameOrigin(NSPoint(x: data.frame.minX, y: title.frame.maxY + 3))
    }

    private func profilesIntroduction() -> NSAttributedString {
        let text = NSMutableAttributedString(string: "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces. ",
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(string: "Learn more.", attributes: [.font: NSFont.systemFont(ofSize: 13),
            .link: URL(string: "https://resources.arc.net/hc/en-us/articles/19227964556183-Profiles-Separate-Work-Personal-Browsing")!]))
        return text
    }

    private func profilePageButton(_ page: ProfileSettingsPage) -> NSButton {
        let button: NSButton
        let activate: () -> Void = { [weak self] in self?.openProfileSettingsPage(page) }
        switch page {
        case .search:
            let search = ActionButton(page.title, action: activate)
            search.isBordered = true; search.bezelStyle = .rounded; search.contentTintColor = .labelColor
            button = search
        case .privacy: button = SettingsCommandButton(title: page.title, symbol: "lock.fill", color: .systemBlue, action: activate)
        case .passwords: button = SettingsCommandButton(title: page.title, symbol: "key.fill", color: .systemGreen, action: activate)
        case .payments: button = SettingsCommandButton(title: page.title, symbol: "creditcard.and.123", color: .systemYellow, action: activate)
        case .notifications: button = SettingsCommandButton(title: page.title, symbol: "bell.fill", color: .systemOrange, action: activate)
        case .clearBrowsingData: button = SettingsCommandButton(title: page.title, symbol: "trash.fill", color: .systemRed, action: activate)
        }
        button.setAccessibilityLabel(page.title)
        button.setAccessibilityIdentifier("settings.profile." + page.rawValue)
        profilePageButtons[page] = button
        return button
    }

    private struct AdvancedRow {
        let symbol: String, color: NSColor, title: String, control: NSSwitch
        var note: String? = nil
    }

    private func makeAdvancedPane() -> NSScrollView {
        let (scroll, content) = pane()
        var y: CGFloat = 20
        func section(_ rows: [AdvancedRow]) {
            let heights = rows.map { $0.note == nil ? CGFloat(40) : 50 }
            let box = group(in: content, y: y, height: heights.reduce(0, +) + CGFloat(rows.count - 1))
            var top: CGFloat = 0
            for (index, row) in rows.enumerated() {
                if index > 0 { box.separator(at: top); top += 1 }
                let height = heights[index]
                place(SettingsSymbolBadge(symbol: row.symbol, color: row.color), in: box,
                      NSRect(x: 10, y: top + (height - 20) / 2, width: 20, height: 20))
                if let note = row.note {
                    label(row.title, in: box, NSRect(x: 38, y: top + 7, width: 452, height: 18))
                    label(note, in: box, NSRect(x: 38, y: top + 26, width: 452, height: 16), help: true)
                } else {
                    label(row.title, in: box, NSRect(x: 38, y: top + (height - 18) / 2, width: 452, height: 18))
                }
                row.control.setAccessibilityLabel(row.title.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                place(row.control, in: box, NSRect(x: box.bounds.width - 48, y: top + (height - 22) / 2, width: 38, height: 22))
                top += height
            }
            y = box.frame.maxY + 10
        }
        section([AdvancedRow(symbol: "speaker.wave.2.fill", color: .systemBlue, title: "Play Parc sound effects", control: soundEffects),
                 AdvancedRow(symbol: "hand.tap.fill", color: .systemBlue, title: "Haptic feedback when reordering tabs", control: reorderingHaptics)])
        section([AdvancedRow(symbol: "macwindow", color: .systemGreen, title: "When opening Parc, restore windows from previous session", control: restore),
                 AdvancedRow(symbol: "rectangle.topthird.inset.filled", color: .systemGreen, title: "Allow window dragging from the top of webpages", control: windowDragging),
                 AdvancedRow(symbol: "ellipsis.rectangle", color: .systemRed, title: "Show full URL when Toolbar is enabled", control: toolbarFullURL),
                 AdvancedRow(symbol: "quote.opening", color: .systemRed, title: "Enable Shared Quotes when highlighting text.", control: sharedQuotes,
                             note: "If disabled, you can still use Copy URL as Quote from the Edit menu.")])
        section([AdvancedRow(symbol: "paintpalette.fill", color: .systemPurple, title: "Allow websites to get your theme data", control: websiteTheme)])
        websiteTheme.setAccessibilityHelp("Allow webpages to match the colors of this window’s Space.")
        place(moreSettings, in: content, NSRect(x: 64, y: y, width: moreSettings.fittingWidth, height: 24))
        place(exportData, in: content, NSRect(x: content.bounds.width - 64 - exportData.fittingWidth, y: y,
                                              width: exportData.fittingWidth, height: 24))
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
        showPane(.profiles, persist: false)
        refresh()
        archive.scrollToVisible(archive.bounds)
        window.makeFirstResponder(archive)
        return true
    }

    func showPane(_ pane: Pane, persist: Bool = true) {
        guard let content = panes[pane], let window else { return }
        guard window.attachedSheet == nil else {
            window.toolbar?.selectedItemIdentifier = selectedPane.identifier
            return
        }
        if persist {
            do { try store.saveSettingsSelection(pane: pane.rawValue, profileID: selectedProfileID) }
            catch {
                window.toolbar?.selectedItemIdentifier = selectedPane.identifier
                reportProfileSettingsError(error)
                return
            }
        }
        if selectedPane != pane {
            cancelDownloadFolderSelection()
        }
        if pane == .general { DefaultBrowserController.shared.refresh() }
        if selectedPane == pane, paneHost.pane === content {
            window.title = pane == .membership ? membershipPane.displayName : pane.rawValue
            window.toolbar?.selectedItemIdentifier = pane.identifier
            return
        }
        if let current = window.contentView { focusState.remember(in: window, root: current, context: focusContext) }
        shortcutsPane.endRecording()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        window.makeFirstResponder(nil)
        selectedPane = pane
        paneHost.show(content, animated: window.isVisible)
        window.title = pane == .membership ? membershipPane.displayName : pane.rawValue
        window.toolbar?.selectedItemIdentifier = pane.identifier
        content.documentView?.setAccessibilityLabel(pane.rawValue + " settings")
        window.autorecalculatesKeyViewLoop = pane == .shortcuts || pane == .icon
        window.recalculateKeyViewLoop()
        if pane != .shortcuts && pane != .icon { SettingsFocusState.connectKeyViews(in: content) }
        restorePaneFocus()
    }

    private var focusContext: String {
        selectedPane.rawValue + (selectedPane == .profiles ? ":" + (selectedProfileID?.uuidString ?? "none") : "")
    }

    private func restorePaneFocus(context: String? = nil) {
        guard !isClosing, context == nil || context == focusContext,
              let window, let content = window.contentView else { return }
        focusState.restore(in: window, root: content, context: focusContext,
                           fallback: selectedPane == .profiles ? profileList : nil)
    }

    func windowWillBeginSheet(_ notification: Notification) {
        guard let window, let content = window.contentView else { return }
        focusState.remember(in: window, root: content, context: focusContext)
        sheetFocusContext = focusContext
        shortcutsPane.endRecording()
        archiveInfoPopover?.close(); archiveInfoPopover = nil
        window.toolbar?.items.forEach { $0.isEnabled = false }
    }

    func windowDidEndSheet(_ notification: Notification) {
        let context = sheetFocusContext
        sheetFocusContext = nil
        window?.toolbar?.items.forEach { $0.isEnabled = true }
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
                    self.focusState.restore(in: window, root: content, context: nil, fallback: self.profileList)
                }
            } else { self.restorePaneFocus(context: context) }
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { !isClosing && window?.attachedSheet == nil }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + Pane.allCases.map(\.identifier) + [.flexibleSpace]
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Pane.allCases.map(\.identifier)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = Pane.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane == .membership ? membershipPane.displayName : pane.rawValue
        item.paletteLabel = item.label
        item.toolTip = pane == .membership ? "Your local Parc card" : pane.rawValue + " settings"
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.rawValue)
        item.target = self; item.action = #selector(selectPane(_:))
        return item
    }
    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = Pane.allCases.first(where: { $0.identifier == sender.itemIdentifier }) else { return }
        showPane(pane)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { store.state.profiles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.state.profiles.indices.contains(row) else { return nil }
        let profile = store.state.profiles[row]
        let count = store.state.spaces.filter { $0.profileID == profile.id }.count
        let cell = SettingsProfileCell()
        cell.name.stringValue = profile.name
        cell.count.stringValue = store.isProfileRemovalPending(profile.id) ? (ProfileRemovalController.shared.status(for: profile.id)?.running == true ? "Removing…" : "Retry") : "\(count) \(count == 1 ? "Space" : "Spaces")"
        cell.setAccessibilityLabel(profile.name + ", " + cell.count.stringValue)
        return cell
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SettingsProfileRowView() }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !refreshingProfiles, store.state.profiles.indices.contains(profileList.selectedRow) else { return }
        let id = store.state.profiles[profileList.selectedRow].id
        guard id != selectedProfileID else { return }
        do { try store.saveSettingsSelection(pane: selectedPane.rawValue, profileID: id) }
        catch {
            refresh()
            reportProfileSettingsError(error)
            return
        }
        cancelDownloadFolderSelection()
        selectedProfileID = id
        refresh()
    }
    private func profilePageSpace() -> BrowserSpace? {
        store.settingsPageSpace(profileID: selectedProfileID, originatingSpaceID: contextSpaceID)
    }

    func refresh() {
        let space = store.state.spaces.first { $0.id == contextSpaceID }
        if !store.state.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = space?.profileID ?? store.state.profiles.first?.id
        }
        if displayedProfileID != selectedProfileID { cancelDownloadFolderSelection() }
        displayedSpaceID = space?.id
        displayedProfileID = selectedProfileID
        let removing = displayedProfileID.map(store.isProfileRemovalPending) ?? false
        if removing { cancelDownloadFolderSelection() }
        archive.isEnabled = displayedProfileID != nil && !removing
        archiveInfo.isEnabled = archive.isEnabled
        if let change = archiveScopeChange,
           change.profileID != displayedProfileID || change.profiles != store.state.profiles || removing {
            cancelArchiveScopeSheet()
        }
        renameProfile.isEnabled = displayedProfileID != nil && !removing
        if let id = displayedProfileID {
            if removing {
                let status = ProfileRemovalController.shared.status(for: id)
                removeProfile.isEnabled = status?.running != true || status?.canCancel == true
                removeProfile.toolTip = status?.running == true ? (status?.canCancel == true ? "Cancel this profile’s removal" : "This profile is being removed") : "Retry this profile’s removal"
            } else {
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
            removeProfile.isEnabled = false
            removeProfile.toolTip = "Select an available profile."
        }
        if let sheet = profileNameSheet,
           !store.state.profiles.contains(where: { $0.id == sheet.profileID }) {
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
        for button in profilePageButtons.values {
            button.isEnabled = profilePageSpace() != nil && onProfileSettingsPage != nil
            button.toolTip = button.isEnabled ? nil : "Use this profile for a Space to manage its browser settings."
        }
        moreSettings.isEnabled = settingsContextSpace() != nil && onMoreSettings != nil
        replay.isEnabled = replaySpaceID != nil && NSApp.delegate?.responds(to: #selector(AppDelegate.replayOnboarding(_:))) == true
        restore.state = store.state.settings.restoreSession ? .on : .off
        refreshingProfiles = true
        profileList.reloadData()
        if let index = store.state.profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            profileList.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        refreshingProfiles = false
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
        guard let window, window.attachedSheet == nil, profileNameSheet == nil,
              let profile = store.state.profiles.first(where: { $0.id == displayedProfileID }) else { return }
        let editor = ProfileNameSheet(profile: profile) { [weak self] name in
            guard let self else { throw ProfileSettingsError.unavailable }
            try self.store.saveProfileName(profile.id, expectedName: profile.name, name: name)
        }
        guard let sheet = editor.window else { return }
        profileNameSheet = editor
        window.beginSheet(sheet) { [weak self, weak editor] _ in
            sheet.orderOut(nil)
            if self?.profileNameSheet === editor { self?.profileNameSheet = nil }
            self?.refresh()
        }
        editor.focusName()
    }

    private func cancelProfileNameEditor() {
        guard let editor = profileNameSheet, let sheet = editor.window else { return }
        profileNameSheet = nil
        sheet.sheetParent?.endSheet(sheet, returnCode: .cancel)
        sheet.orderOut(nil)
    }

    private func reportProfileSettingsError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        PArcDialog.inform(in: window, .init(error: error, title: "Parc couldn’t save these settings."))
    }

    var replaySpaceID: UUID? { settingsContextSpace()?.id }

    @objc private func replayWelcome() {
        NSApp.sendAction(#selector(AppDelegate.replayOnboarding(_:)), to: NSApp.delegate, from: self)
    }

    private func openProfileSettingsPage(_ page: ProfileSettingsPage) {
        guard selectedPane == .profiles, window?.isKeyWindow == true,
              window?.attachedSheet == nil else { return }
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
        selectedPane == .profiles && selectedProfileID == profileID
            && profilePageSpace()?.id == spaceID
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

    @objc private func retryDownloadPreferences() { refreshDownloadPreferences() }
    private func refreshDownloadPreferences(message: String? = nil) {
        downloadPreferencesGeneration &+= 1
        let generation = downloadPreferencesGeneration
        downloadRetry.isHidden = true
        guard let profileID = displayedProfileID,
              store.state.profiles.contains(where: { $0.id == profileID }),
              !store.isProfileRemovalPending(profileID) else {
            downloadPreferences = nil; renderDownloadPreferences(message: "Select an available profile.")
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
                      self.displayedProfileID == profileID,
                      self.store.state.profiles.contains(where: { $0.id == profileID }),
                      !self.store.isProfileRemovalPending(profileID) else { return }
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
        let name = store.state.profiles.first { $0.id == displayedProfileID }?.name ?? "Default"
        downloadHelp.maximumNumberOfLines = 2
        downloadHelp.lineBreakMode = .byWordWrapping
        downloadHelp.cell?.truncatesLastVisibleLine = true
        downloadHelp.stringValue = message ?? (current?.directoryManaged == true || current?.promptManaged == true
            ? "Some download settings for “\(name)” are managed by your organization."
            : "Applies to all Spaces using the “\(name)” profile.")
        downloadHelp.toolTip = downloadHelp.stringValue
        let managed = current?.directoryManaged == true || current?.promptManaged == true
        downloadHelp.isHidden = !(managed || !downloadRetry.isHidden || (message != nil && current != nil))
        layoutProfileCards()
    }
    private func reportDownloadPreferenceError(_ error: Error) {
        refreshDownloadPreferences(message: error.localizedDescription)
    }
    private func currentDownloadPreferences() -> PCNativeDownloadPreferences? {
        guard let profileID = displayedProfileID,
              store.state.profiles.contains(where: { $0.id == profileID }), let current = downloadPreferences,
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
              let profileID = displayedProfileID else { downloadLocationPicker.revert(); return }
        let panel = NSOpenPanel()
        panel.prompt = "Select"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = current.directoryURL
        downloadFolderPanel = panel
        renderDownloadLocation()
        panel.beginSheetModal(for: window) { [weak self, weak panel, weak window] response in
            guard let self, let panel, self.downloadFolderPanel === panel else { return }
            self.downloadFolderPanel = nil
            guard response == .OK, let window, self.window === window, window.isVisible,
                  self.displayedProfileID == profileID,
                  self.store.state.profiles.contains(where: { $0.id == profileID }),
                  let url = panel.url else { self.refreshDownloadPreferences(); return }
            do {
                let chosen = try PCNativeBrowserApplication.setDownloadDirectory(url, for: current)
                _ = try PCNativeBrowserApplication.setPromptForDownload(false, for: chosen)
                self.refreshDownloadPreferences()
            } catch { self.reportDownloadPreferenceError(error) }
        }
    }
    func beginProfileCreation() {
        showPane(.profiles)
        createProfile()
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
    private func refreshSearchPreferences(message: String? = nil) {
        searchGeneration &+= 1
        let generation = searchGeneration
        searchPreferences = nil; engine.isEnabled = false; searchSuggestions.isEnabled = false
        engine.removeAllItems(); engine.addItem(withTitle: "Loading…")
        searchNote = message ?? "Loading this profile’s search settings…"
        guard let profileID = displayedProfileID, store.state.profiles.contains(where: { $0.id == profileID }),
              !store.isProfileRemovalPending(profileID) else {
            engine.removeAllItems(); engine.addItem(withTitle: "Unavailable")
            searchNote = displayedProfileID.map(store.isProfileRemovalPending) == true
                ? "Profile removal must finish before these settings can be used." : "Select an available profile."
            return
        }
        let path = store.independentEngineProfilePath(for: profileID)
        PCNativeBrowserApplication.searchPreferences(profilePath: path) { [weak self] preferences, error in
            MainActor.assumeIsolated {
                guard let self, self.searchGeneration == generation, self.displayedProfileID == profileID,
                      self.store.state.profiles.contains(where: { $0.id == profileID }) else { return }
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
                    self.searchNote = "An extension controls this profile’s default search engine."
                } else {
                    self.searchNote = ""
                }
                self.refreshDownloadPreferences()
            }
        }
    }
    @objc private func searchEngineChanged() {
        guard let choice = engine.selectedItem?.representedObject as? SearchChoice,
              let profileID = displayedProfileID,
              store.state.profiles.contains(where: { $0.id == profileID }),
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
        guard let current = searchPreferences, let profileID = displayedProfileID,
              store.state.profiles.contains(where: { $0.id == profileID }),
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
        next.frame = bounds; next.autoresizingMask = [.width, .height]
        addSubview(next); pane = next
    }
}
