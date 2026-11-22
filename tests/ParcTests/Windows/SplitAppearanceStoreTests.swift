import AppKit
import CoreText
import Testing
@testable import ParcCore

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
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        #expect(f.target().group.customIcon == Self.star)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func iconCustomizationMutatesNoPageOrChildTitle() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let original = f.target(), tabs = f.store.state.tabs
        _ = try f.store.saveSplitAppearance(original, icon: Self.star)
        #expect(f.store.state.tabs == tabs)
        #expect(f.target().group.id == original.group.id)
    }

    @Test func iconCustomizationPreservesPaneIdentityAndGeometry() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let original = f.target()
        _ = try f.store.saveSplitAppearance(original, icon: Self.star)
        #expect(f.target().group.tabIDs == original.group.tabIDs)
        #expect(f.target().group.widthFactors == original.group.widthFactors)
    }

    @Test func iconUndoStaysValidAcrossAnIndependentTitleEdit() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        #expect(try f.store.applySplitAppearance(change, undo: true))
    }

    @Test func iconUndoPreservesALaterTitle() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        _ = try f.store.applySplitAppearance(change, undo: true)
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == "Research")
    }

    @Test func iconRedoRestoresTheSameOriginalIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Research")
        _ = try f.store.applySplitAppearance(change, undo: true)
        #expect(try f.store.applySplitAppearance(change, undo: false))
        #expect(f.target().group.customIcon == Self.star)
    }

    @Test func titleUndoStaysValidAcrossAnIndependentIconEditAndPreservesTheIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let named = try #require(try f.store.saveSidebarSplitTitle(f.target(), title: "Research"))
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        #expect(try f.store.applySplitTitleChange(named, undo: true))
        #expect(f.target().group.customTitle == nil)
        #expect(f.target().group.customIcon == Self.star)
    }

    @Test func nativeUndoLabelsFollowTheRecoveredOperations() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let change = try #require(try f.store.saveSplitAppearance(f.target(), icon: Self.star))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        let reset = try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
        #expect(reset.actionName == "Reset Name and Icon")
        #expect(change.actionName == "Customize Tab")
    }

    private func customized(_ f: SplitAppearanceSupport.SplitFixture) throws -> SidebarSplitAppearanceChange {
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        return try #require(try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true))
    }

    @Test func resetRemovesBothOverrides() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try customized(f)
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func resetUndoRestoresBothFieldsAtomically() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let reset = try customized(f)
        #expect(try f.store.applySplitAppearance(reset, undo: true))
        #expect(f.target().group.customIcon == Self.star)
        #expect(f.target().group.customTitle == "Together")
    }

    @Test func resetRedoIsComplete() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let reset = try customized(f)
        _ = try f.store.applySplitAppearance(reset, undo: true)
        #expect(try f.store.applySplitAppearance(reset, undo: false))
        #expect(f.target().group.customIcon == nil)
        #expect(f.target().group.customTitle == nil)
    }

    @Test func theResetInverseRefusesAConcurrentNameReplacement() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let reset = try customized(f)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        #expect(!f.store.canApplySplitAppearance(reset, undo: true))
    }

    @Test func aStaleEditorCannotReplaceTheSharedIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let stale = f.target()
        _ = try f.store.saveSplitAppearance(stale, icon: .emoji("🌙"))
        #expect(throws: SidebarSplitTitleEdit.EditError.unavailable) {
            _ = try f.store.saveSplitAppearance(stale, icon: .symbol("heart"))
        }
        #expect(f.target().group.customIcon == .emoji("🌙"))
    }

    @Test func cachedWindowGeometryCannotOverwriteCurrentSharedAppearance() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let old = f.target().group
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Other")
        #expect(f.store.setWindowPresentation(spaceID: f.space, selectedTabIDs: old.tabIDs, splitLayout: old))
        #expect(f.target().group.customIcon == .emoji("🌙"))
        #expect(f.target().group.customTitle == "Other")
    }

    @Test func aDividerOperationKeepsTheIcon() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        #expect(f.store.setSplitLayout(orientation: .vertical, widthFactors: [1, 3]))
        #expect(f.target().group.customIcon == .emoji("🌙"))
    }

    @Test func theIconIsDurable() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: .emoji("🌙"))
        let reload = try BrowserStore(directory: f.directory)
        #expect(reload.state.splitLayouts.first?.customIcon == .emoji("🌙"))
    }

    @Test func olderStoredGroupsDecodeUnchanged() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.target().group)) as? [String: Any])
        legacy.removeValue(forKey: "customIcon")
        let decoded = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.customIcon == nil)
        #expect(decoded.id == f.target().group.id)
    }

    @Test func anUnknownStoredIconDecodesAsAbsent() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        var unknown = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.target().group)) as? [String: Any])
        unknown["customIcon"] = ["icon": ["_0": "notAKnownIcon"]]
        let tolerant = try JSONDecoder().decode(BrowserSplitLayout.self, from: JSONSerialization.data(withJSONObject: unknown))
        #expect(tolerant.customIcon == nil)
        #expect(tolerant.id == f.target().group.id)
    }

    @Test func aFailedSavePreservesBothFieldsAndTheOriginals() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        _ = try f.store.saveSplitAppearance(f.target(), icon: Self.star)
        _ = try f.store.saveSidebarSplitTitle(f.target(), title: "Together")
        let before = f.store.state
        try f.breakDisk()
        #expect(throws: (any Error).self) { _ = try f.store.saveSplitAppearance(f.target(), icon: nil, reset: true) }
        #expect(f.store.state == before)
    }
}
