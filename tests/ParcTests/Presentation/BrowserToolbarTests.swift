import AppKit
import Combine
import Testing
import ParcCore
@testable import Parc

struct BrowserToolbarTests {
    private let key = "parc.browserToolbar.v1"

    @MainActor private func withPreferences(_ body: (BrowserToolbarPreferences, UserDefaults) throws -> Void) throws {
        let name = "parc.toolbar.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(BrowserToolbarPreferences(defaults: defaults), defaults)
    }

    @Test @MainActor func changingToolbarVisibilityKeepsTheFullAddressPreference() throws {
        try withPreferences { preferences, defaults in
            try preferences.setShowsFullURL(true)
            #expect(!preferences.state.isVisible)
            try preferences.setVisible(true)
            #expect(BrowserToolbarPreferences(defaults: defaults).state == .init(isVisible: true, showsFullURL: true))
        }
    }

    @Test @MainActor func repeatingToolbarVisibilityDoesNotPublishAnotherLayout() throws {
        try withPreferences { preferences, _ in
            try preferences.setVisible(true)
            let observation = preferences.$state.dropFirst().sink { _ in Issue.record("Published an unchanged layout") }
            try preferences.setVisible(true)
            withExtendedLifetime(observation) {}
        }
    }

    @Test(arguments: ["invalid", #"{"version":99,"isVisible":true,"showsFullURL":true}"#])
    @MainActor func invalidToolbarPreferencesArePreserved(unreadable: String) throws {
        try withPreferences { _, defaults in
            let bytes = Data(unreadable.utf8)
            defaults.set(bytes, forKey: key)
            let preferences = BrowserToolbarPreferences(defaults: defaults)
            #expect(preferences.loadError)
            #expect(throws: BrowserToolbarPreferences.Failure.unavailable) { try preferences.setVisible(true) }
            #expect(defaults.data(forKey: key) == bytes)
        }
    }

    @Test(arguments: [(false, false, false), (true, false, true), (false, true, true)])
    func onlySplitsShowAPaneBarWhenTheToolbarIsHidden(example: (Bool, Bool, Bool)) {
        #expect(PaneTopBarAdmission.displayed(toolbarVisible: example.0, inSplit: example.1) == example.2)
    }

    @Test(arguments: [(true, false, false), (false, true, false), (false, false, true)])
    func nonPagePresentationsHideTheOrdinaryPaneBar(example: (Bool, Bool, Bool)) {
        #expect(!PaneTopBarAdmission.displayed(toolbarVisible: true, inSplit: true,
                                              isPopup: example.0, hasLibrary: example.1, tabFullscreen: example.2))
    }

    @Test(arguments: [(true, true, true, true), (false, true, true, false), (true, false, true, false), (true, true, false, false)])
    func thePeekBarShowsOnlyInAnActiveOrdinaryPeek(example: (Bool, Bool, Bool, Bool)) {
        #expect(PaneTopBarAdmission.peekDisplayed(toolbarVisible: example.0, isActivePeek: example.1,
                                                  developerToolbarHidden: example.2) == example.3)
    }

    @Test(arguments: [(true, true, false), (false, true, true), (true, false, true)])
    func theSidebarKeepsItsAddressWhenTheToolbarDoesNotReplaceIt(example: (Bool, Bool, Bool)) {
        #expect(PaneTopBarAdmission.sidebarAddressBarShown(focusedHasTopBar: example.0, toolbarVisible: example.1) == example.2)
    }

    @Test(arguments: [(false, "sub.example.test"), (true, "sub.example.test:8443/a%20b?q=%2f#part")])
    func theAddressLabelFormatsTheDisplayWithoutChangingTheCopyURL(example: (Bool, String)) throws {
        let url = try #require(URL(string: "https://sub.example.test:8443/a%20b?q=%2F#part"))
        let address = BrowserToolbarAddress(url: url, full: example.0)
        #expect(address.title == example.1)
        #expect(address.fullURL == url.absoluteString)
    }

    @Test(arguments: ["parc://settings/content", "file:///tmp/MixedCase"])
    func nonWebAddressesKeepTheirOriginalSpelling(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(BrowserToolbarAddress(url: url, full: true).title == address)
    }

    @Test @MainActor func theTitleLabelKeepsTheFullAddressForVoiceOver() throws {
        _ = NSApplication.shared
        let url = try #require(URL(string: "https://example.test/doc?id=1"))
        let title = PaneTitleControl(frame: CGRect(x: 0, y: 0, width: 420, height: 28))
        title.update(BrowserToolbarAddress(url: url, full: false))
        #expect(title.accessibilityLabel() == "Address: " + url.absoluteString)
        #expect(title.accessibilityChildren()?.isEmpty == true)
    }

    @MainActor private func toolbar(width: CGFloat, insecure: Bool = false) -> BrowserToolbarView {
        _ = NSApplication.shared
        let toolbar = BrowserToolbarView(frame: CGRect(x: 0, y: 0, width: width, height: 32))
        toolbar.update(url: URL(string: "https://example.test/page"), fullURL: false, enabled: true, canBack: true, canForward: true,
                       loading: false, canReload: true, canCopy: true, canShowSiteInfo: true, canSplit: true,
                       close: true, showSidebar: true, insecure: insecure, extensionItems: [])
        toolbar.layoutSubtreeIfNeeded()
        return toolbar
    }

    @Test(arguments: [CGFloat(300), 480, 800])
    @MainActor func asymmetricControlsLeaveTheAddressCentered(width: CGFloat) throws {
        let toolbar = toolbar(width: width, insecure: true)
        let title = try #require(toolbar.subviews.compactMap { $0 as? PaneTitleControl }.first)
        #expect(title.frame.midX == toolbar.bounds.midX)
    }

    @Test @MainActor func aModalHidesNavigationWithoutMovingItsControls() throws {
        let toolbar = toolbar(width: 800)
        let back = try #require(toolbar.subviews.first { $0.parcTooltip?.label == "Go back" })
        let forward = try #require(toolbar.subviews.first { $0.parcTooltip?.label == "Go forward" })
        let frame = back.frame
        toolbar.setObstructedByModal(true, animated: false)
        #expect(back.alphaValue == 0 && forward.alphaValue == 0)
        #expect(back.frame == frame && !back.isHidden)
    }

    @Test @MainActor func dismissingAModalRestoresNavigation() throws {
        let toolbar = toolbar(width: 800)
        let back = try #require(toolbar.subviews.first { $0.parcTooltip?.label == "Go back" })
        toolbar.setObstructedByModal(true, animated: false)
        toolbar.setObstructedByModal(false, animated: false)
        #expect(back.alphaValue == 1)
    }
}

struct SidebarPaymentEntryTests {
    @MainActor private func sidebar() -> SidebarView {
        _ = NSApplication.shared
        return SidebarView(frame: CGRect(x: 0, y: 0, width: 260, height: 680))
    }

    @Test @MainActor func anIdenticalPaymentEntryDoesNotLayoutTheSidebarAgain() {
        let sidebar = sidebar()
        _ = sidebar.updatePaymentEntry(title: "Save card", symbol: "creditcard", enabled: true, savedLabel: "")
        let announced = sidebar.presentPaymentEntry(title: "Save card", symbol: "creditcard", enabled: true, savedLabel: "",
                                                   layout: { Issue.record("Laid out the unchanged payment entry") },
                                                   canAcknowledge: { true },
                                                   announce: { _ in Issue.record("Announced an empty saved label") })
        #expect(!announced)
    }

    @Test @MainActor func aNewSavedLabelIsLaidOutBeforeItIsAnnounced() {
        let sidebar = sidebar()
        _ = sidebar.updatePaymentEntry(title: "Save card", symbol: "creditcard", enabled: true, savedLabel: "")
        var layout = false
        var announcement: String?
        let announced = sidebar.presentPaymentEntry(title: "Save card", symbol: "creditcard", enabled: true,
                                                   savedLabel: "Card saved", layout: {
            layout = true
            sidebar.layoutSubtreeIfNeeded()
        }, canAcknowledge: { true }, announce: {
            #expect(layout)
            announcement = $0
        })
        #expect(announced)
        #expect(announcement == "Card saved")
    }

    @Test @MainActor func aHiddenPaymentEntryDoesNotAnnounceTheSavedLabel() {
        let sidebar = sidebar()
        let announced = sidebar.presentPaymentEntry(title: "Save card", symbol: "creditcard", enabled: true,
                                                   savedLabel: "Card saved", canAcknowledge: { false },
                                                   announce: { _ in Issue.record("Announced a hidden payment entry") })
        #expect(!announced)
    }
}

struct MenuImagesTests {
    @MainActor private func expectVisibleImage(_ item: NSMenuItem) {
        #expect(item.image != nil)
        if #available(macOS 27, *) { #expect(item.preferredImageVisibility == .visible) }
    }

    @Test @MainActor func textOnlyMenuActionsLeaveImageVisibilityAutomatic() {
        _ = NSApplication.shared
        let item = MenuAction.item("Copy URL") {}
        #expect(item.image == nil)
        if #available(macOS 27, *) { #expect(item.preferredImageVisibility == .automatic) }
    }

    @Test @MainActor func clearingTheSharedMenuImageRestoresAutomaticVisibility() {
        _ = NSApplication.shared
        let item = NSMenuItem(title: "Copy URL", action: nil, keyEquivalent: "")
        item.showImage(NSImage(size: CGSize(width: 16, height: 16)))
        expectVisibleImage(item)
        item.showImage(nil)
        #expect(item.image == nil)
        if #available(macOS 27, *) { #expect(item.preferredImageVisibility == .automatic) }
    }

    @Test(arguments: [false, true], [1, 2, 4])
    @MainActor func eachSplitOperationShowsItsImageThroughTheSharedPath(vertical: Bool, count: Int) {
        _ = NSApplication.shared
        let icon = NSImage(size: CGSize(width: 16, height: 16))
        let menu = SplitPaneMenu.make(orientation: vertical ? .vertical : .horizontal, index: 0, count: count,
                                     artwork: { _ in icon }, prepare: { _ in {} })
        let operations = menu.items.filter { !$0.isSeparatorItem }
        #expect(!operations.isEmpty)
        #expect(operations.allSatisfy { $0.image === icon })
        if #available(macOS 27, *) { #expect(operations.allSatisfy { $0.preferredImageVisibility == .visible }) }
        #expect(menu.items.filter(\.isSeparatorItem).allSatisfy { $0.image == nil })
    }

    @Test(arguments: [false, true])
    @MainActor func folderPickerMenusUseTheSharedImagePath(notes: Bool) throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "/untouched/Work", isDirectory: true)
        let icon = NSImage(size: CGSize(width: 16, height: 16))
        let picker: NSPopUpButton
        if notes {
            let notePicker = NoteLocationPicker()
            notePicker.iconProvider = { _ in icon }
            notePicker.update(folder, enabled: true)
            picker = notePicker
        } else {
            let downloadPicker = DownloadLocationPicker()
            downloadPicker.iconProvider = { _ in icon }
            downloadPicker.update(.init(directory: folder, prompt: false), enabled: true)
            picker = downloadPicker
        }
        let row = try #require(picker.menu?.items.first { $0.title == "Work" })
        expectVisibleImage(row)
    }

    @Test @MainActor func sharingServicesUseTheSharedImagePathAndKeepTheCapturedLinks() throws {
        _ = NSApplication.shared
        let urls = [try #require(URL(string: "https://example.test/first")), try #require(URL(string: "https://example.test/next"))]
        var performed = 0
        let image = NSImage(size: CGSize(width: 16, height: 16))
        let service = NSSharingService(title: "Test Service", image: image, alternateImage: nil) { performed += 1 }
        let menu = try #require(PaneShareMenu.menu(for: urls) { requested in
            #expect(requested == urls)
            return [service]
        })
        let entry = try #require(menu.items.first)
        expectVisibleImage(entry)
        let action = try #require(entry.representedObject as? PaneShareMenu.ShareAction)
        #expect(action.urls == urls)
        action.share()
        #expect(performed == 1)
    }

    @Test @MainActor func missingLinksNeverAskForSharingServices() {
        _ = NSApplication.shared
        let item = PaneShareMenu.item(for: nil) { _ in
            Issue.record("Requested services with no link")
            return []
        }
        #expect(!item.isEnabled && item.submenu == nil)
    }
}
