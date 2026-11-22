import AppKit
import Testing
@testable import ParcCore
@testable import ParcSidebar

@MainActor
struct SplitTitleTests {
    @MainActor private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @MainActor private final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-title-" + UUID().uuidString)
        let store: BrowserStore
        let first: UUID
        let second: UUID
        let space: UUID
        let profile: UUID

        init() throws {
            store = try BrowserStore(directory: directory)
            first = store.openResolvedURL(URL(string: "https://one.test/")!)
            second = store.openResolvedURL(URL(string: "https://two.test/")!)
            store.updateTab(first, title: "One")
            store.updateTab(second, title: "Two")
            store.setSplit([first, second])
            space = store.activeSpaceID
            profile = store.activeSpace.profileID
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func target(_ selected: [UUID]? = nil, in state: BrowserState? = nil, profile override: UUID? = nil) -> SidebarSplitTitleEdit? {
            SidebarSplitTitleEdit.current(state: state ?? store.state, spaceID: space, profileID: override ?? profile,
                                          selectedTabIDs: selected ?? [first, second])
        }

        func current() throws -> SidebarSplitTitleEdit { try #require(target()) }

        func rename(_ title: String) throws {
            try store.saveSidebarSplitTitle(try current(), title: title)
        }

        var storedTitle: String? { store.state.splitLayouts.first { $0.tabIDs == [first, second] }?.customTitle }
    }

    @MainActor private final class Editor {
        let view = SidebarSplitTitleView(title: "Research", count: 2)
        let window = KeyWindow(contentRect: NSRect(x: -10000, y: -10000, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        var values: [String?] = []

        init(attached: Bool = true) {
            window.isReleasedWhenClosed = false
            view.frame = NSRect(x: 0, y: 0, width: 220, height: 35)
            if attached { window.contentView!.addSubview(view) }
        }

        deinit { MainActor.assumeIsolated { window.close() } }

        var field: SidebarTitleField { view.subviews.compactMap { $0 as? SidebarTitleField }.first! }
        var textView: NSTextView { field.currentEditor() as! NSTextView }

        @discardableResult func begin(_ title: String = "Research") -> Bool {
            view.begin(title: title, finished: { [self] in values.append($0) })
        }

        func drainMainQueue() async {
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    @Test func anUnnamedSplitHasNoInventedTitle() throws {
        #expect(try Fixture().current().group.customTitle == nil)
    }

    @Test func aFocusedChildIsNeverTheContainerTarget() throws {
        let fixture = try Fixture()
        #expect(fixture.target([fixture.second]) == nil)
    }

    @Test func paneOrderIsPartOfTheOriginalIdentity() throws {
        let fixture = try Fixture()
        #expect(fixture.target([fixture.second, fixture.first]) == nil)
    }

    @Test func aForeignProfileRefusesTheTarget() throws {
        #expect(try Fixture().target(profile: UUID()) == nil)
    }

    @Test func theContainerReceivesATrimmedName() throws {
        let fixture = try Fixture()
        try fixture.rename("  Research\n")
        #expect(try fixture.current().group.customTitle == "Research")
    }

    @Test func renamingKeepsTheOriginalGroupAndChildIdentities() throws {
        let fixture = try Fixture()
        let initial = try fixture.current()
        try fixture.rename("Research")
        let named = try fixture.current()
        #expect(named.group.id == initial.group.id)
        #expect(named.group.tabIDs == initial.group.tabIDs)
        #expect(named.group.sidebarAnchorID == initial.group.sidebarAnchorID)
    }

    @Test func renamingAltersNoChildPageSelectionOrHistory() throws {
        let fixture = try Fixture()
        let before = fixture.store.state
        try fixture.rename("Research")
        #expect(fixture.store.state.tabs == before.tabs)
        #expect(fixture.store.state.selectedTabIDs == before.selectedTabIDs)
        #expect(fixture.store.state.history == before.history)
    }

    @Test func theContainerTitlePersists() throws {
        let fixture = try Fixture()
        try fixture.rename("Research")
        let reopened = try BrowserStore(directory: fixture.directory)
        #expect(reopened.state.splitLayouts.first { $0.tabIDs == [fixture.first, fixture.second] }?.customTitle == "Research")
    }

    @Test func anEarlierEditorCannotOverwriteAConcurrentName() throws {
        let fixture = try Fixture()
        let stale = try fixture.current()
        try fixture.rename("Research")
        #expect(throws: SidebarSplitTitleEdit.EditError.unavailable) {
            try fixture.store.saveSidebarSplitTitle(stale, title: "Stale")
        }
        #expect(fixture.storedTitle == "Research")
    }

    @Test func liveMetadataKeepsTheOriginalGroupLease() throws {
        let fixture = try Fixture()
        try fixture.rename("Research")
        let named = try fixture.current()
        fixture.store.updateTab(fixture.first, title: "New live title", url: "https://one.test/next")
        #expect(named.matches(fixture.store.state))
    }

    @Test func anEmptyEditClearsTheContainerOverride() throws {
        let fixture = try Fixture()
        try fixture.rename("Research")
        try fixture.rename(" \n ")
        #expect(fixture.storedTitle == nil)
    }

    @Test func clearingTheNameNeverErasesLiveMetadata() throws {
        let fixture = try Fixture()
        try fixture.rename("Research")
        fixture.store.updateTab(fixture.first, title: "New live title", url: "https://one.test/next")
        try fixture.rename(" \n ")
        #expect(fixture.store.state.tabs.first { $0.id == fixture.first }?.title == "New live title")
    }

    @Test func existingSessionsDecodeWithoutAName() throws {
        let fixture = try Fixture()
        try fixture.rename("Research")
        let group = try fixture.current().group
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any])
        legacy.removeValue(forKey: "customTitle")
        let decoded = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.customTitle == nil)
        #expect(decoded.id == group.id)
    }

    enum Change: CaseIterable {
        case reorderedMembers, replacedContainer, movedChild, retiredChild

        func apply(to state: inout BrowserState, child: UUID) {
            let index = state.tabs.firstIndex { $0.id == child }!
            switch self {
            case .reorderedMembers: state.splitLayouts[0].tabIDs.reverse()
            case .replacedContainer: state.splitLayouts[0].id = UUID()
            case .movedChild: state.tabs[index].folderID = UUID()
            case .retiredChild: state.tabs[index].archivedAt = Date()
            }
        }
    }

    @Test(arguments: Change.allCases)
    func aChangedGroupInvalidatesAnOpenEdit(_ change: Change) throws {
        let fixture = try Fixture()
        let lease = try fixture.current()
        var changed = fixture.store.state
        change.apply(to: &changed, child: fixture.first)
        #expect(!lease.matches(changed))
    }

    @Test func anUnestablishedFavoriteGroupIsNotFabricated() throws {
        let fixture = try Fixture()
        let lease = try fixture.current()
        var changed = fixture.store.state
        changed.tabs[changed.tabs.firstIndex { $0.id == fixture.first }!].kind = .favorite
        #expect(SidebarSplitTitleEdit(group: lease.group, profileID: fixture.profile, state: changed) == nil)
    }

    @Test func orientationAndDividerChangesKeepTheContainerTitle() throws {
        let fixture = try Fixture()
        try fixture.rename("Preserved")
        #expect(fixture.store.setSplitLayout(orientation: .vertical, widthFactors: [1, 2]))
        #expect(try fixture.current().group.customTitle == "Preserved")
    }

    @Test func rememberedGeometryCannotOverwriteANewerSharedName() throws {
        let fixture = try Fixture()
        let oldLayout = try fixture.current().group
        try fixture.rename("Preserved")
        #expect(fixture.store.setWindowPresentation(spaceID: fixture.space, selectedTabIDs: [fixture.first, fixture.second], splitLayout: oldLayout))
        #expect(try fixture.current().group.customTitle == "Preserved")
    }

    @Test func theWindowLayoutProjectionKeepsTheTitle() throws {
        let fixture = try Fixture()
        try fixture.rename("Preserved")
        #expect(WindowPresentation(state: fixture.store.state, ready: true).splitLayout?.customTitle == "Preserved")
    }

    @Test func anExpandedOriginalGroupKeepsTheTitle() throws {
        let fixture = try Fixture()
        try fixture.rename("Preserved")
        let third = fixture.store.openResolvedURL(URL(string: "https://three.test/")!)
        fixture.store.setSplit([fixture.first, fixture.second])
        fixture.store.setSplit([fixture.first, fixture.second, third])
        #expect(fixture.store.state.splitLayouts.first { $0.tabIDs == [fixture.first, fixture.second, third] }?.customTitle == "Preserved")
    }

    @Test func theSurvivingGroupKeepsItsNameWhenAChildSeparates() throws {
        let fixture = try Fixture()
        try fixture.rename("Preserved")
        let third = fixture.store.openResolvedURL(URL(string: "https://three.test/")!)
        fixture.store.setSplit([fixture.first, fixture.second])
        fixture.store.setSplit([fixture.first, fixture.second, third])
        let three = try #require(fixture.target([fixture.first, fixture.second, third]))
        #expect(fixture.store.separateTabFromSplit(third, expected: three.group))
        #expect(try fixture.current().group.customTitle == "Preserved")
    }

    @Test func aPrivateGroupNameWorksWithoutPersistentStorage() throws {
        let fixture = try Fixture()
        let privateDirectory = fixture.directory.appendingPathComponent("uncreated-private")
        let privateStore = BrowserStore(privateParentProfileID: fixture.profile, engineProfilePath: "/not-opened",
                                        directory: privateDirectory, settings: fixture.store.state.settings)
        let one = privateStore.openResolvedURL(URL(string: "https://private-one.test")!)
        let two = privateStore.openResolvedURL(URL(string: "https://private-two.test")!)
        privateStore.setSplit([one, two])
        let target = try #require(SidebarSplitTitleEdit.current(state: privateStore.state, spaceID: privateStore.activeSpaceID,
                                                                profileID: privateStore.activeSpace.profileID, selectedTabIDs: [one, two]))
        try privateStore.saveSidebarSplitTitle(target, title: "Private")
        #expect(privateStore.state.splitLayouts.first?.customTitle == "Private")
        #expect(!FileManager.default.fileExists(atPath: privateDirectory.path))
    }

    @Test func aFailedSavePublishesNoContainerTitle() throws {
        let fixture = try Fixture()
        let lease = try fixture.current()
        let before = fixture.store.state
        try FileManager.default.removeItem(at: fixture.directory)
        try Data().write(to: fixture.directory)
        #expect(throws: (any Error).self) { try fixture.store.saveSidebarSplitTitle(lease, title: "Not published") }
        #expect(fixture.store.state == before)
    }

    @Test func theContainerNameAndCountAreAccessible() {
        #expect(SidebarSplitTitleView(title: "Research", count: 2).accessibilityLabel() == "Research, Split View, 2 tabs")
    }

    @Test func theContainerLabelKeepsTheSidebarThemeOwner() {
        let view = SidebarSplitTitleView(title: "Research", count: 2)
        view.applyColors(title: .systemPurple, secondary: .systemOrange)
        #expect(view.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Research" && $0.textColor == .systemPurple })
    }

    @Test func aDetachedEditorRefusesFocus() {
        #expect(!Editor(attached: false).begin())
    }

    @Test func theNativeEditorBegins() {
        #expect(Editor().begin())
    }

    @Test func editingExposesTheNativeFieldToAccessibility() {
        let editor = Editor()
        editor.begin()
        #expect(editor.view.accessibilityRole() == .group)
        #expect(editor.view.accessibilityChildren()?.contains { ($0 as? SidebarTitleField) === editor.field } == true)
    }

    @Test func theWholeContainerNameIsSelected() {
        let editor = Editor()
        editor.begin()
        #expect(editor.field.currentEditor()?.selectedRange == NSRange(location: 0, length: 8))
    }

    @Test func theFieldHasItsPlaceholderAndExplicitAccessibilityLabel() {
        let editor = Editor()
        editor.begin()
        #expect(editor.field.placeholderString == "Title")
        #expect(editor.field.accessibilityLabel() == "Split View name")
    }

    @Test func returnPreservesAnActiveInputMethodComposition() {
        let editor = Editor()
        editor.begin()
        editor.textView.setMarkedText("入力", selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    @Test func cancellingCommitsNoContainerName() {
        let editor = Editor()
        editor.begin()
        editor.view.cancel()
        #expect(editor.values.count == 1)
        #expect(editor.values[0] == nil)
    }

    @Test func cancellingRestoresTheActivationRole() {
        let editor = Editor()
        editor.begin()
        editor.view.cancel()
        #expect(editor.view.accessibilityRole() == .button)
    }

    @Test func theEditorCanBeEnteredAgainAfterCancelling() {
        let editor = Editor()
        editor.begin()
        editor.view.cancel()
        #expect(editor.begin())
    }

    @Test func returnCompletesTheNativeFieldWithItsActualText() {
        let editor = Editor()
        editor.begin()
        editor.textView.string = "New name"
        editor.textView.didChangeText()
        #expect(editor.field.control(editor.field, textView: editor.textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.values == ["New name"])
    }

    @Test func removingTheOwnerCancelsAQueuedBlurCompletion() async {
        let editor = Editor()
        editor.begin("Again")
        editor.field.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: editor.field))
        editor.view.removeFromSuperview()
        await editor.drainMainQueue()
        #expect(editor.values.count == 1)
        #expect(editor.values[0] == nil)
    }

    @Test func aDetachedNamedContainerCannotActivateAPage() {
        let editor = Editor(attached: false)
        var activations = 0
        editor.view.prepareActivation = { { activations += 1; return true } }
        #expect(!editor.view.accessibilityPerformPress())
        #expect(activations == 0)
    }

    @Test func anAttachedNamedContainerActivatesItsPage() {
        let editor = Editor()
        var activations = 0
        editor.view.prepareActivation = { { activations += 1; return true } }
        #expect(editor.view.accessibilityPerformPress())
        #expect(activations == 1)
    }
}
