import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor private final class KeyTestWindow: NSWindow {
    var key = false
    override var isKeyWindow: Bool { key }
    convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        isReleasedWhenClosed = false
    }
}

@MainActor private final class SplitFixture {
    let directory: URL
    let store: BrowserStore
    let first: UUID
    let second: UUID
    let profile: UUID
    let space: UUID

    init() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-split-appearance-" + UUID().uuidString)
        store = try BrowserStore(directory: directory)
        first = store.openResolvedURL(URL(string: "https://one.invalid")!)
        second = store.openResolvedURL(URL(string: "https://two.invalid")!)
        store.setSplit([first, second])
        profile = store.activeSpace.profileID
        space = store.activeSpaceID
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var file: URL { directory.appendingPathComponent("session.json") }

    func target() -> SidebarSplitTitleEdit {
        SidebarSplitTitleEdit.current(state: store.state, spaceID: space, profileID: profile, selectedTabIDs: [first, second])!
    }

    func breakDisk() throws {
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    }

    func favoriteStore() throws -> (store: BrowserStore, other: BrowserSpace) {
        let other = BrowserSpace(id: UUID(), name: "Other Space", symbol: "circle", color: "AABBCC", profileID: profile)
        var state = store.state
        state.spaces.append(other)
        state.activeSpaceID = other.id
        for index in state.tabs.indices where [first, second].contains(state.tabs[index].id) {
            state.tabs[index].kind = .favorite
            state.tabs[index].folderID = nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: file)
        return (try BrowserStore(directory: directory), other)
    }
}

@MainActor
struct SplitAppearanceStoreTests {
    private static let star = SidebarGroupIcon.symbol("star")

    @Test(arguments: [SidebarGroupIcon.symbol("star"), SidebarGroupIcon.emoji("👩🏽‍💻")])
    func aNativeSymbolAndAComposedEmojiAreValid(_ icon: SidebarGroupIcon) {
        #expect(icon.isValid)
    }

    @Test(arguments: [SidebarGroupIcon.emoji("text"), SidebarGroupIcon.symbol("unknown")])
    func arbitraryUnsupportedInputIsRefused(_ icon: SidebarGroupIcon) {
        #expect(!icon.isValid)
    }

    @Test func iconOnlyCustomizationDoesNotNameTheGroup() throws {
        let f = try SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        #expect(f.target().group.customIcon == Self.star)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func iconCustomizationMutatesNoPageOrChildTitle() throws {
        let f = try SplitFixture()
        let original = f.target(), tabs = f.store.state.tabs
        _ = try f.store.saveSplitAppearance(original, icon: Self.star)
        #expect(f.store.state.tabs == tabs)
        #expect(f.target().group.id == original.group.id)
    }

    @Test func iconCustomizationPreservesPaneIdentityAndGeometry() throws {
        let f = try SplitFixture()
        let original = f.target()
        _ = try f.store.saveSplitAppearance(original, icon: Self.star)
        #expect(f.target().group.tabIDs == original.group.tabIDs)
        #expect(f.target().group.widthFactors == original.group.widthFactors)
    }

    @Test func iconUndoStaysValidAcrossAnIndependentTitleEdit() throws {
        let f = try SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        #expect(try f.store.applySplitAppearance(change, undo: true))
    }

    @Test func iconUndoPreservesALaterTitle() throws {
        let f = try SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        _ = try f.store.applySplitAppearance(change, undo: true)
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == "Research")
    }

    @Test func iconRedoRestoresTheSameOriginalIcon() throws {
        let f = try SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        _ = try f.store.applySplitAppearance(change, undo: true)
        #expect(try f.store.applySplitAppearance(change, undo: false))
        #expect(f.target().group.customIcon == Self.star)
    }

    @Test func titleUndoStaysValidAcrossAnIndependentIconEditAndPreservesTheIcon() throws {
        let f = try SplitFixture()
        let named = try #require(try f.store.saveSidebarSplitTitle(f.target(), title: "Research"))
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        #expect(try f.store.applySplitTitleChange(named, undo: true))
        #expect(f.target().group.customTitle == nil)
        #expect(f.target().group.customIcon == Self.star)
    }

    @Test func nativeUndoLabelsFollowTheRecoveredOperations() throws {
        let f = try SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        let reset = try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
        #expect(reset.actionName == "Reset Name and Icon")
        #expect(change.actionName == "Customize Tab")
    }

    private func customized(_ f: SplitFixture) throws -> SidebarSplitAppearanceChange {
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        return try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
    }

    @Test func resetRemovesBothOverrides() throws {
        let f = try SplitFixture()
        _ = try customized(f)
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func resetUndoRestoresBothFieldsAtomically() throws {
        let f = try SplitFixture()
        let reset = try customized(f)
        #expect(try f.store.applySplitAppearance(reset, undo: true))
        #expect(f.target().group.customIcon == Self.star)
        #expect(f.target().group.customTitle == "Together")
    }

    @Test func resetRedoIsComplete() throws {
        let f = try SplitFixture()
        let reset = try customized(f)
        _ = try f.store.applySplitAppearance(reset, undo: true)
        #expect(try f.store.applySplitAppearance(reset, undo: false))
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func theResetInverseRefusesAConcurrentNameReplacement() throws {
        let f = try SplitFixture()
        let reset = try customized(f)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        #expect(!f.store.canApplySplitAppearance(reset, undo: true))
    }

    @Test func aStaleEditorCannotReplaceTheSharedIcon() throws {
        let f = try SplitFixture()
        let stale = f.target()
        _ = try f.store.saveSplitAppearance(stale, icon: .emoji("🌙"))
        #expect(throws: SidebarSplitTitleEdit.EditError.unavailable) {
            _ = try f.store.saveSplitAppearance(stale, icon: .symbol("heart"))
        }
        #expect(f.target().group.customIcon == .emoji("🌙"))
    }

    @Test func cachedWindowGeometryCannotOverwriteCurrentSharedAppearance() throws {
        let f = try SplitFixture()
        let old = f.target().group
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        #expect(f.store.setWindowPresentation(spaceID: f.space, selectedTabIDs: old.tabIDs, splitLayout: old))
        #expect(f.target().group.customIcon == .emoji("🌙"))
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func aDividerOperationKeepsTheIcon() throws {
        let f = try SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        #expect(f.store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3]))
        #expect(f.target().group.customIcon == .emoji("🌙"))
    }

    @Test func theIconIsDurable() throws {
        let f = try SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        let reload = try BrowserStore(directory: f.directory)
        #expect(reload.state.splitLayouts.first?.customIcon == .emoji("🌙"))
    }

    @Test func olderStoredGroupsDecodeUnchanged() throws {
        let f = try SplitFixture()
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.target().group)) as? [String: Any])
        legacy.removeValue(forKey: "customIcon")
        let decoded = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.customIcon == nil)
        #expect(decoded.id == f.target().group.id)
    }

    @Test func anUnknownStoredIconDecodesAsAbsent() throws {
        let f = try SplitFixture()
        var unknown = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.target().group)) as? [String: Any])
        unknown["customIcon"] = ["icon": ["_0": "notAKnownIcon"]]
        let tolerant = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: unknown))
        #expect(tolerant.customIcon == nil)
        #expect(tolerant.id == f.target().group.id)
    }

    @Test func aFailedSavePreservesBothFieldsAndTheOriginals() throws {
        let f = try SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        let before = f.store.state
        try f.breakDisk()
        #expect(throws: (any Error).self) { _ = try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true) }
        #expect(f.store.state == before)
    }
}

@MainActor
struct SplitFavoriteAppearanceTests {
    @Test func aFavoriteEditorUsesTheOriginalHomeGroupFromAnotherActiveSpace() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        #expect(editor.isFavorite)
        #expect(editor.group.spaceID == f.space)
        #expect(editor.isVisible(in: other.id, state: favorite.state))
    }

    @Test func aForeignProfileIsRefused() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        #expect(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: UUID(),
                                              selectedTabIDs: [f.first, f.second]) == nil)
    }

    @Test func theRequiredNameDialogPreservesLiteralTextAndGroup() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "  Exact favorite title  ")
        let group = try #require(favorite.state.splitLayouts.first)
        #expect(group.customTitle == "  Exact favorite title  ")
        #expect(group.id == editor.group.id)
    }

    @Test func favoriteRenameNeverTargetsTheAnchorChild() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let tabs = favorite.state.tabs
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "Exact")
        #expect(favorite.state.tabs == tabs)
    }

    @Test func anEmptyFavoriteNameDoesNotClearThroughTheDialog() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "Named")
        let group = try #require(favorite.state.splitLayouts.first)
        let current = try #require(SidebarSplitTitleEdit(group: group, profileID: f.profile, state: favorite.state))
        #expect(throws: SidebarSplitTitleEdit.EditError.unavailable) { _ = try favorite.saveSidebarSplitTitle(current, title: "") }
        #expect(favorite.state.splitLayouts.first == group)
    }

    @Test func anExplicitResetClearsTheFavoriteNameAndItsUndoTargetsTheSharedContainer() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "Named")
        let group = try #require(favorite.state.splitLayouts.first)
        let current = try #require(SidebarSplitTitleEdit(group: group, profileID: f.profile, state: favorite.state))
        let restored = try #require(try favorite.saveSplitAppearance(current, icon: nil, reset: true))
        #expect(favorite.state.splitLayouts.first?.customTitle == nil)
        #expect(try favorite.applySplitAppearance(restored, undo: true))
    }

    @Test func movingAWholeFavoritePreservesItsCustomization() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "Named")
        _ = try favorite.saveSplitAppearance(SidebarSplitTitleEdit(group: favorite.state.splitLayouts[0], profileID: f.profile, state: favorite.state)!,
                                             icon: .emoji("🌙"))
        let group = favorite.state.splitLayouts[0]
        let move = try #require(SidebarWindowMove(items: [.split(group.id)], sourceSpaceID: other.id, profileID: f.profile,
                                                  to: .init(spaceID: other.id, folderID: nil, section: .pinned), before: nil,
                                                  state: favorite.state))
        let moved = try #require(move.applying(to: favorite.state))
        #expect(moved.splitLayouts.first?.customIcon == group.customIcon)
        #expect(moved.splitLayouts.first?.customTitle == group.customTitle)
    }

    @Test func anArchivedChildRefusesTheWholeEditor() throws {
        let f = try SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let group = try #require(favorite.state.splitLayouts.first)
        var retired = favorite.state
        retired.tabs[0].archivedAt = Date()
        #expect(other.id != f.space)
        #expect(SidebarSplitTitleEdit(group: group, profileID: f.profile, state: retired) == nil)
    }
}

@MainActor
struct SplitIconPickerTests {
    private final class Recorder {
        var commits: [SidebarGroupIcon?] = []
        var finished = 0
    }

    private func picker(selected: SidebarGroupIcon? = nil, recorder: Recorder, closesAfterChoice: Bool = false,
                        current: Bool = true) -> SidebarGroupIconPicker {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: selected)
        _ = picker.view
        picker.isCurrent = { current }
        picker.closesAfterChoice = closesAfterChoice
        picker.onCommit = { recorder.commits.append($0) }
        picker.onFinish = { recorder.finished += 1 }
        return picker
    }

    @Test func theTabAndSpacePickerIs272By272AndOpensOnEmojiWithoutAnIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.frame.size == NSSize(width: 272, height: 272))
        #expect(view.page == .emoji)
    }

    @Test func theSegmentOrderIsEmojiThenIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.segmentedControl?.label(forSegment: 0) == "Emoji")
        #expect(view.segmentedControl?.label(forSegment: 1) == "Icon")
    }

    @Test func removeOnlyAppearsWithAnIcon() throws {
        let view = try #require(picker(recorder: Recorder()).pickerView)
        #expect(view.removeButton.isHidden)
        #expect(!view.canRemoveIcon)
    }

    @Test func invalidNativeInputRetainsTheEdit() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("not emoji"))
        #expect(recorder.commits.isEmpty)
        #expect(!picker.finished)
    }

    @Test func aChoiceCommitsOnceAndKeepsThePickerOpen() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        #expect(recorder.commits == [.emoji("🌍")])
        #expect(!picker.finished)
        #expect(picker.selected == .emoji("🌍"))
    }

    @Test func aCommittedEmojiIsMarkedAndRemoveAppears() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        let view = try #require(picker.pickerView)
        #expect(view.canRemoveIcon)
        #expect(!view.removeButton.isHidden)
        #expect(view.emojiPage?.selectedEmoji == "🌍")
    }

    @Test func theSameIconIsNotRepublished() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        picker.choose(.emoji("🌍"))
        #expect(recorder.commits.count == 1)
    }

    @Test func aGridIndexPublishesItsCatalogIcon() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.choose(.emoji("🌍"))
        let view = try #require(picker.pickerView)
        view.iconGrid.selectIcon(at: 9)
        #expect(recorder.commits.last! == .icon(.shapes))
        #expect(view.iconGrid.selectedIcon == .shapes)
        #expect(view.emojiPage?.selectedEmoji == nil)
    }

    @Test func selectedOrOutOfRangeCellsPublishNothing() throws {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        let view = try #require(picker.pickerView)
        view.iconGrid.selectIcon(at: 9)
        view.iconGrid.selectIcon(at: 9)
        view.iconGrid.selectIcon(at: 56)
        #expect(recorder.commits.count == 1)
    }

    @Test func removePublishesNilAndKeepsThePicker() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌍"), recorder: recorder)
        let view = try #require(picker.pickerView)
        _ = view.removeButton.accessibilityPerformPress()
        #expect(recorder.commits.count == 1 && recorder.commits[0] == nil)
        #expect(!picker.finished)
        #expect(picker.selected == nil)
    }

    @Test func dismissalFinishesOnce() {
        let recorder = Recorder()
        let picker = picker(recorder: recorder)
        picker.cancel()
        picker.cancel()
        #expect(recorder.finished == 1)
        #expect(picker.finished)
    }

    @Test func dismissalIsNotIconRemoval() {
        let recorder = Recorder()
        let picker = picker(selected: .symbol("star"), recorder: recorder)
        picker.cancel()
        picker.choose(nil)
        #expect(recorder.commits.isEmpty)
    }

    @Test func anExpiredOwnerRefusesPublication() {
        let recorder = Recorder()
        let picker = picker(selected: .symbol("star"), recorder: recorder, current: false)
        picker.choose(nil)
        #expect(recorder.commits.isEmpty)
        #expect(picker.finished)
    }

    @Test func aSpaceCreationChoiceCommitsThenCloses() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌙"), recorder: recorder, closesAfterChoice: true)
        try #require(picker.pickerView).iconGrid.selectIcon(at: 0)
        #expect(recorder.commits == [.icon(.star)])
        #expect(picker.finished)
        #expect(recorder.finished == 1)
    }

    @Test func aSpaceCreationRemoveAlsoCloses() throws {
        let recorder = Recorder()
        let picker = picker(selected: .emoji("🌙"), recorder: recorder, closesAfterChoice: true)
        _ = try #require(picker.pickerView).removeButton.accessibilityPerformPress()
        #expect(recorder.commits.count == 1 && recorder.commits[0] == nil)
        #expect(picker.finished)
    }

    @Test func aFailedCommitKeepsThePickerAndTheOriginalSelectionForRetry() throws {
        let f = try SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .symbol("star"))
        let picker = SidebarGroupIconPicker(selected: f.target().group.customIcon)
        picker.isCurrent = { true }
        _ = picker.view
        var failures = 0
        picker.onFailure = { _ in failures += 1 }
        let target = f.target(), state = f.store.state
        let persisted = try Data(contentsOf: f.file)
        try f.breakDisk()
        var committed: [SidebarGroupIcon?] = []
        picker.onCommit = { value in
            _ = try f.store.saveSplitAppearance(target, icon: value)
            committed.append(value)
        }
        picker.choose(nil)
        #expect(!picker.finished)
        #expect(f.store.state == state)
        #expect(committed.isEmpty)
        #expect(failures == 1)
        #expect(picker.selected == target.group.customIcon)
        #expect(picker.pickerView?.canRemoveIcon == true)
        try FileManager.default.removeItem(at: f.file)
        try persisted.write(to: f.file)
        picker.choose(nil)
        #expect(!picker.finished)
        #expect(committed.count == 1 && committed[0] == nil)
        #expect(f.target().group.customIcon == nil)
        picker.cancel()
    }

    @Test func noKeyWindowLeavesTheLeaseUnheld() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        defer { pickerWindow.contentView = nil }
        #expect(owned.presentationWindow === pickerWindow)
        #expect(!SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func aKeyPickerPopoverHoldsTheLease() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        defer { pickerWindow.contentView = nil }
        pickerWindow.key = true
        #expect(SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func aKeySkinToneChildWindowHoldsTheLease() {
        let browser = KeyTestWindow(), pickerWindow = KeyTestWindow(), toneWindow = KeyTestWindow()
        let owned = SidebarGroupIconPicker(selected: nil)
        pickerWindow.contentView = owned.view
        pickerWindow.addChildWindow(toneWindow, ordered: .above)
        defer { pickerWindow.removeChildWindow(toneWindow); pickerWindow.contentView = nil }
        toneWindow.key = true
        #expect(owned.presentationWindow === toneWindow)
        #expect(SplitCustomizationFocus.isHeld(window: browser, presentation: owned.presentationWindow))
    }

    @Test func theTonePopoverWindowCountsEvenUnparented() {
        let pickerWindow = KeyTestWindow(), looseTone = KeyTestWindow()
        looseTone.key = true
        #expect(SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: looseTone) === looseTone)
        #expect(SidebarGroupIconPicker.ownedKeyWindow(of: pickerWindow, extra: nil) == nil)
    }

    @Test func aClosedPickerReleasesItsControllerViewAndEmojiGrid() {
        _ = NSApplication.shared
        weak var leakedPicker: SidebarGroupIconPicker?
        weak var leakedView: NSView?
        weak var leakedGrid: NSCollectionView?
        autoreleasepool {
            let transient = SidebarGroupIconPicker(selected: nil)
            _ = transient.view
            transient.isCurrent = { true }
            transient.configurePopover()
            transient.pickerView?.emojiPage?.submit("pizza")
            leakedPicker = transient
            leakedView = transient.view
            leakedGrid = transient.pickerView?.emojiPage?.collectionView
            transient.cancel()
        }
        #expect(leakedPicker == nil && leakedView == nil && leakedGrid == nil)
    }
}

@MainActor
struct SidebarIconCatalogTests {
    private static var fixtures: URL? {
        Bundle.module.url(forResource: "SplitViews", withExtension: nil)?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
    }

    private static let emoji = SidebarEmojiModel.load(from: fixtures)

    @Test func theIconResourcesLoadFromTheBundlesCustomInfoPickerFolder() {
        #expect(SidebarIconCatalog.resourceDirectory == Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true))
    }

    @Test func allSixtyOneCasesAreInOrder() {
        #expect(SidebarIconType.allCases.count == 61)
        #expect(SidebarIconType.allCases.first == .star)
        #expect(SidebarIconType.allCases.last == .search)
    }

    @Test func theTabAndSpaceCatalogStopsAtTrain() {
        #expect(SidebarIconType.tabAndSpacePicker.count == 56)
        #expect(SidebarIconType.tabAndSpacePicker.last == .train)
    }

    @Test func theFolderCatalogKeepsItsOrder() {
        #expect(SidebarIconType.folderPicker.count == 24)
        #expect(SidebarIconType.folderPicker[8] == .chatBubbleEllipses)
        #expect(SidebarIconType.folderPicker.last == .skull)
    }

    @Test func rawValuesAreTheImportedSidebarIconNames() {
        #expect(SidebarIconType(rawValue: "colorPallete") == .colorPallete)
        #expect(SidebarIconType.fileTrayFull.rawValue == "fileTrayFull")
    }

    @Test(arguments: [SidebarIconCatalog.Font.ionicons, .feather])
    func theBundledIconFontsLoad(_ font: SidebarIconCatalog.Font) {
        #expect(SidebarIconCatalog.font(font, size: 14, in: Self.fixtures).fontName == font.rawValue)
    }

    @Test func theIconFontComesFromTheBundledFileNotANameLookup() {
        let ionicons = SidebarIconCatalog.font(.ionicons, size: 14, in: Self.fixtures)
        let url = CTFontCopyAttribute(ionicons as CTFont, kCTFontURLAttribute) as? URL
        #expect(url?.standardizedFileURL == Self.fixtures?.appendingPathComponent("ionicons.ttf").standardizedFileURL)
    }

    @Test(arguments: SidebarIconType.allCases.filter { SidebarIconCatalog.glyph($0) != nil })
    func eachGlyphExistsInIoniconsAndRendersAsATemplate(_ type: SidebarIconType) throws {
        let ionicons = SidebarIconCatalog.font(.ionicons, size: 14, in: Self.fixtures)
        let code = try #require(SidebarIconCatalog.glyph(type))
        var units = Array(String(Character(try #require(Unicode.Scalar(code)))).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        #expect(CTFontGetGlyphsForCharacters(ionicons as CTFont, &units, &glyphs, units.count))
        #expect(SidebarIconCatalog.image(for: type, size: 14).isTemplate)
    }

    @Test(arguments: SidebarIconType.allCases.filter { SidebarIconCatalog.glyph($0) == nil })
    func theRemainingTypesAreCopiedImageAssets(_ type: SidebarIconType) {
        #expect([.linear, .figma].contains(type))
        #expect(SidebarIconCatalog.image(for: type, size: 16).size == NSSize(width: 16, height: 16))
    }

    @Test func theRecoveredGlyphMappingHolds() {
        #expect(SidebarIconCatalog.glyph(.star) == 0xF53B)
        #expect(SidebarIconCatalog.glyph(.bag) == 0xF166)
        #expect(SidebarIconCatalog.glyph(.ellipse) == 0xF29E)
    }

    @Test func catalogIconsRoundTrip() throws {
        let encoded = try JSONEncoder().encode(SidebarGroupIcon.icon(.chatBubbleEllipses))
        #expect(try JSONDecoder().decode(SidebarGroupIcon.self, from: encoded) == .icon(.chatBubbleEllipses))
    }

    @Test func theFolderPickerHostIs272By144() {
        #expect(SidebarIconPickerMetrics.size(.folderPicker) == NSSize(width: 272, height: 144))
    }

    @Test func aStoredIconOpensTheIconPageOnAnEightBySevenGrid() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.iconGrid.items.count == 56)
        #expect(view.iconGrid.fittingSize == NSSize(width: 247, height: 216))
    }

    @Test func cellsAreThirtyPointsOneApart() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        #expect(try #require(picker.pickerView).iconGrid.itemFrame(at: 9) == NSRect(x: 31, y: 31, width: 30, height: 30))
    }

    @Test func theGridCentersInTheTwoHundredSixtyFourPointPage() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        #expect(try #require(picker.pickerView).gridFrame.minX == 12.5)
    }

    private func gridItems() throws -> (star: SidebarIconItemView, heart: SidebarIconItemView) {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .icon(.star))
        _ = picker.view
        let grid = try #require(picker.pickerView).iconGrid
        let star = grid.items[0], heart = grid.items[2]
        star.appearance = NSAppearance(named: .aqua)
        heart.appearance = NSAppearance(named: .aqua)
        return (star, heart)
    }

    @Test func theSelectedItemCarriesTheRawNameLabel() throws {
        let (star, _) = try gridItems()
        #expect(star.isSelectedIcon)
        #expect(star.accessibilityLabel() == "star")
        #expect(star.isAccessibilitySelected())
    }

    @Test func theSelectedLightBackgroundIsBrandGrayAtAQuarter() throws {
        let (star, heart) = try gridItems()
        #expect(star.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.25))
        #expect(heart.backgroundColor == .clear)
    }

    @Test func theHoverBackgroundIsATenth() throws {
        let (_, heart) = try gridItems()
        let event = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                        context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        heart.mouseEntered(with: event)
        #expect(heart.backgroundColor == SidebarIconCatalog.brandGray.withAlphaComponent(0.1))
    }

    @Test func darkGlyphsAreWhite() throws {
        let (_, heart) = try gridItems()
        heart.appearance = NSAppearance(named: .darkAqua)
        #expect(heart.glyphColor == .white)
    }

    @Test func pressingDimsTheGlyphAndReleaseRestoresIt() throws {
        let (_, heart) = try gridItems()
        heart.setPressed(true)
        #expect(heart.glyphView.layer?.opacity == 0.75)
        heart.setPressed(false)
        #expect(heart.glyphView.layer?.opacity == 1)
    }

    @Test func aStoredSymbolOpensTheIconPageUnselected() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: .symbol("star"))
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.iconGrid.selectedIcon == nil)
    }

    @Test func theFolderPickerIsIconsOnly() throws {
        _ = NSApplication.shared
        let picker = SidebarGroupIconPicker(selected: nil, iconSet: .folderPicker)
        _ = picker.view
        let view = try #require(picker.pickerView)
        #expect(view.page == .icon)
        #expect(view.heading?.stringValue == "Icon")
        #expect(view.emojiPage == nil)
        #expect(view.iconGrid.items.count == 24)
    }

    @Test func theBundledEmojiListLoadsInCategoryOrder() {
        #expect(Self.emoji.emojis.count > 1800)
        #expect(Self.emoji.emojis.first?.emoji == "😀")
    }

    @Test func thereAreEightCategoriesInCaseOrder() {
        let starts = Self.emoji.categoryStarts.compactMap { $0 }
        #expect(starts.count == 8)
        #expect(starts == starts.sorted())
    }

    @Test func activitiesPrecedeTravelAndFlagsComeLast() {
        let starts = Self.emoji.categoryStarts.compactMap { $0 }
        #expect(Self.emoji.emojis[starts[4]].category == 4)
        #expect(Self.emoji.emojis[starts[3]].category == 3)
        #expect(Self.emoji.emojis[starts[7]].emoji.unicodeScalars.first!.value >= 0x1F3C1)
    }

    @Test func theFilterIsCaseInsensitiveWithSpacesAsWildcards() {
        #expect(Self.emoji.filtered("grinning").emojis.first?.emoji == "😀")
        #expect(Self.emoji.filtered("GRIN face").emojis.contains { $0.emoji == "😀" })
    }

    @Test func anInvalidPatternMatchesOnlyByEmoji() {
        #expect(Self.emoji.filtered("(").emojis.isEmpty)
        #expect(Self.emoji.filtered("😀").emojis.contains { $0.emoji == "😀" })
    }

    @Test func aSkinToneModifierFollowsTheFirstScalar() {
        #expect(SidebarEmojiModel.applying("\u{1F3FD}", to: "👋") == "👋🏽")
        #expect(SidebarEmojiModel.applying("\u{1F3FD}", to: "🧑‍💻") == "🧑🏽‍💻")
    }

    @Test func aToneReplacesTheOldOneAndABaseHasFiveVariants() {
        #expect(SidebarEmojiModel.applying("\u{1F3FB}", to: "👋🏽") == "👋🏻")
        #expect(SidebarEmojiModel.variants(of: "👋").count == 6)
    }

    @Test func aTonedChoiceMarksItsBaseCell() {
        #expect(Self.emoji.index(containing: "👋🏽") == Self.emoji.emojis.firstIndex { $0.emoji == "👋" })
    }

    @Test func theEmojiPageHasNoPlaceholderBeforeTypingAndEightCategoryButtons() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        #expect(page.searchField.placeholderString == nil)
        #expect(page.categoryBar.arrangedSubviews.count == 8)
    }

    @Test func searchWaitsForItsDebounce() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(page.searchField.placeholderString == nil)
        #expect(page.model.emojis.count == Self.emoji.emojis.count)
    }

    @Test func theDebouncedQueryFiltersTheGrid() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        #expect(page.model.emojis.contains { $0.emoji == "🍕" })
        #expect(page.model.emojis.count < 20)
    }

    @Test func anEmptiedSearchShowsSearchAndEveryEmoji() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        page.searchField.stringValue = "pizza"
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        page.searchField.stringValue = ""
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        page.applyQuery()
        #expect(page.searchField.placeholderString == "Search")
        #expect(page.model.emojis.count == Self.emoji.emojis.count)
    }

    @Test func aToneLessEmojiSelectsAtOnce() throws {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        var picked: [String] = []
        page.onEmojiSelected = { picked.append($0) }
        let pizza = try #require(Self.emoji.emojis.firstIndex { $0.emoji == "🍕" })
        page.collectionView(page.collectionView, didSelectItemsAt: [IndexPath(item: pizza, section: 0)])
        #expect(picked == ["🍕"])
        #expect(page.selectedEmoji == "🍕")
        #expect(page.skinTonePopover == nil)
    }

    @Test func emojiCellsAreTwentyEightPoints() {
        _ = NSApplication.shared
        let page = SidebarEmojiPickerView(selectedEmoji: nil, source: Self.emoji)
        let size = page.collectionView(page.collectionView, layout: page.collectionView.collectionViewLayout!,
                                       sizeForItemAt: IndexPath(item: 0, section: 0))
        #expect(size == NSSize(width: 28, height: 28))
    }
}

@MainActor
struct SplitTitleViewAppearanceTests {
    @MainActor private final class Fixture {
        let row: SidebarSplitTitleView
        let iconView: NSImageView
        let countIcon: NSView

        init(title: String = "Original", count: Int = 2) {
            _ = NSApplication.shared
            row = SidebarSplitTitleView(title: title, count: count)
            iconView = row.subviews.compactMap { $0 as? NSImageView }.first!
            countIcon = row.subviews.first { !($0 is NSTextField) && !($0 is NSImageView) && $0.layer?.cornerRadius == 4 }!
        }

        var shownCount: String? { countIcon.isHidden ? nil : countIcon.subviews.compactMap { $0 as? NSTextField }.first?.stringValue }
        var shownImage: NSImage? { iconView.isHidden ? nil : iconView.image }
        var title: NSTextField { row.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Original" }! }

        func layout() {
            row.frame = NSRect(x: 0, y: 0, width: 212, height: 36)
            row.titleTrailing = 164
            row.layoutSubtreeIfNeeded()
        }
    }

    private static func pixels(_ image: NSImage?) -> Data? {
        guard let image, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.bitmapData.map { Data(bytes: $0, count: bitmap.bytesPerRow * bitmap.pixelsHigh) }
    }

    @Test func aNativeSymbolShowsAsAGenuineTemplateSymbolWithNoCount() {
        let f = Fixture()
        f.row.setIcon(.symbol("star"))
        #expect(f.shownImage?.isTemplate == true)
        #expect(Self.pixels(f.shownImage) == Self.pixels(NSImage(systemSymbolName: "star", accessibilityDescription: nil)))
        #expect(f.shownCount == nil)
    }

    @Test func anEmojiIsDrawnAsAnUntintedSixteenPointImage() {
        let f = Fixture()
        f.row.setIcon(.emoji("🧭"))
        let compass = Self.pixels(SidebarGroupIcon.emoji("🧭").image(size: 16))
        #expect(compass != nil)
        #expect(Self.pixels(f.shownImage) == compass)
        #expect(compass != Self.pixels(SidebarGroupIcon.emoji("🍕").image(size: 16)))
        #expect(f.shownCount == nil)
        #expect(f.shownImage?.size == NSSize(width: 16, height: 16))
        #expect(f.shownImage?.isTemplate == false)
        #expect(!f.row.subviews.contains { ($0 as? NSTextField)?.stringValue == "🧭" })
    }

    @Test func resettingTheIconRestoresTheOriginalCount() {
        let f = Fixture()
        f.row.setIcon(.emoji("🧭"))
        f.row.setIcon(nil)
        #expect(f.shownCount == "2")
        #expect(f.shownImage == nil)
    }

    @Test func aCatalogIconIsASixteenPointTemplateGlyph() {
        let f = Fixture()
        f.row.setIcon(.icon(.star))
        f.row.layoutSubtreeIfNeeded()
        #expect(Self.pixels(f.shownImage) == Self.pixels(SidebarGroupIcon.icon(.star).image(size: 16)))
        #expect(f.shownCount == nil)
        #expect(f.shownImage?.isTemplate == true)
        #expect(f.shownImage?.size == NSSize(width: 16, height: 16))
    }

    @Test func theCustomTitleIsDrawnFromThirtySixAtFourteenPointsRegularBeforeClose() {
        let f = Fixture()
        f.layout()
        #expect(f.title.frame.minX == SidebarSplitCellLayout.infoTitleInset - SidebarRowAppearance.titleTextPadding)
        #expect(SidebarSplitCellLayout.infoTitleInset == 36)
        #expect(f.title.frame.maxX == 164 + SidebarRowAppearance.titleTextPadding)
        #expect(f.title.font?.pointSize == 14)
        #expect(f.title.font?.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    @Test func renamingEditsInTheTitlesFrame() {
        let f = Fixture()
        f.layout()
        #expect(f.row.subviews.compactMap { $0 as? SidebarTitleField }.first?.frame == f.title.frame)
    }

    @Test func theCountIconIsSixteenPointsCentredInTheTwentyFourPointSlot() {
        let f = Fixture()
        f.layout()
        #expect(f.countIcon.frame == NSRect(x: 10, y: 10, width: 16, height: 16))
    }

    @Test func theCountLabelIsBoldTen() throws {
        let f = Fixture()
        f.layout()
        let label = try #require(f.countIcon.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.font?.pointSize == 10)
        #expect(label.font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func theCountUsesMaxContrastOnACutoutAtEightyPercent() throws {
        let f = Fixture()
        f.layout()
        let label = try #require(f.countIcon.subviews.compactMap { $0 as? NSTextField }.first)
        f.row.applyColors(title: .systemPurple, secondary: .systemOrange, countText: .white, countBackground: .black, dark: true)
        #expect(label.textColor == .white)
        #expect(f.countIcon.layer?.backgroundColor?.alpha == 0.8)
    }

    @Test func withoutCloseTheTitleEndsTenInside() {
        let f = Fixture()
        f.layout()
        f.row.titleTrailing = nil
        f.row.layoutSubtreeIfNeeded()
        #expect(f.title.frame.maxX == 202 + SidebarRowAppearance.titleTextPadding)
    }

    @Test func anIconOnlySplitShowsTheDefaultTitleNamesItselfToAccessibilityAndHasNoTooltip() {
        _ = NSApplication.shared
        let unnamed = SidebarSplitTitleView(title: SidebarSplitCellLayout.defaultTitle(count: 3), count: 3, named: false)
        #expect(unnamed.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "3 Tabs" })
        #expect(unnamed.accessibilityLabel() == "Split View, 3 tabs")
        #expect(unnamed.toolTip == nil)
        #expect(unnamed.parcTooltip == nil)
    }

    @Test func aNamedSplitsTitleIsItsTooltipAfterAHundredthOfASecond() {
        let f = Fixture()
        #expect(f.row.parcTooltip == TooltipConfiguration("Original", behavior: .onMouseIdle(delay: 0.01)))
        #expect(f.row.toolTip == nil)
    }

    @Test func theTwentyFourPointSlotAnchorsThePicker() {
        let f = Fixture()
        f.layout()
        f.row.setIcon(.icon(.star))
        f.row.layoutSubtreeIfNeeded()
        #expect(f.row.iconContainerFrame == NSRect(x: SidebarSplitCellLayout.infoLeadingInset, y: 6, width: 24, height: 24))
    }
}

@MainActor
struct SplitAppearanceUndoTests {
    private final class Availability {
        var available = true
        var errors = 0
    }

    @Test func aCommittedIconRegistersNativeUndo() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        #expect(undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 }))
        #expect(undo.undoMenuItemTitle == "Undo Customize Tab")
    }

    @Test func aWindowInterruptionDisablesTheOriginalUndo() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        state.available = false
        #expect(!undo.canUndo)
    }

    @Test func nativeUndoRemovesOnlyTheOriginalIconAndRedoRestoresIt() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(change, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        undo.undo()
        #expect(f.target().group.customIcon == nil)
        #expect(undo.redoMenuItemTitle == "Redo Customize Tab")
        undo.redo()
        #expect(f.target().group.customIcon == .symbol("heart"))
    }

    private func chronology(_ f: SplitFixture, _ undo: FolderUndoManager, _ state: Availability) throws {
        let icon = try #require(try f.store.saveSplitAppearance(f.target(), icon: .symbol("heart")))
        _ = undo.appendSplitAppearance(icon, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 })
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        let reset = try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
        #expect(undo.appendSplitAppearance(reset, store: f.store, available: { state.available }, onError: { _ in state.errors += 1 }))
    }

    @Test func aCommittedResetJoinsTheSameNativeChronology() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        #expect(undo.undoMenuItemTitle == "Undo Reset Name and Icon")
    }

    @Test func theNativeResetInverseRestoresBothOriginalFields() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        undo.undo()
        #expect(f.target().group.customIcon == .symbol("heart"))
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func theEarlierIconInverseFollowsResetWithoutFlatteningTheTitle() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        try chronology(f, undo, Availability())
        undo.undo()
        undo.undo()
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func nativeRedoCompletesTheSameResetChronology() throws {
        let f = try SplitFixture()
        let undo = FolderUndoManager()
        let state = Availability()
        try chronology(f, undo, state)
        undo.undo()
        undo.undo()
        undo.redo()
        undo.redo()
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
        #expect(state.errors == 0)
    }
}
