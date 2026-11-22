import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SplitAppearanceFavoriteTests {
    @Test func aFavoriteEditorUsesTheOriginalHomeGroupFromAnotherActiveSpace() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        #expect(editor.isFavorite)
        #expect(editor.group.spaceID == f.space)
        #expect(editor.isVisible(in: other.id, state: favorite.state))
    }

    @Test func aForeignProfileIsRefused() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        #expect(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: UUID(),
                                              selectedTabIDs: [f.first, f.second]) == nil)
    }

    @Test func theRequiredNameDialogPreservesLiteralTextAndGroup() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "  Exact favorite title  ")
        let group = try #require(favorite.state.splitLayouts.first)
        #expect(group.customTitle == "  Exact favorite title  ")
        #expect(group.id == editor.group.id)
    }

    @Test func favoriteRenameNeverTargetsTheAnchorChild() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let tabs = favorite.state.tabs
        let editor = try #require(SidebarSplitTitleEdit.current(state: favorite.state, spaceID: other.id, profileID: f.profile,
                                                               selectedTabIDs: [f.first, f.second]))
        try favorite.saveSidebarSplitTitle(editor, title: "Exact")
        #expect(favorite.state.tabs == tabs)
    }

    @Test func anEmptyFavoriteNameDoesNotClearThroughTheDialog() throws {
        let f = try SplitAppearanceSupport.SplitFixture()
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
        let f = try SplitAppearanceSupport.SplitFixture()
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
        let f = try SplitAppearanceSupport.SplitFixture()
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
        let f = try SplitAppearanceSupport.SplitFixture()
        let (favorite, other) = try f.favoriteStore()
        let group = try #require(favorite.state.splitLayouts.first)
        var retired = favorite.state
        retired.tabs[0].archivedAt = Date()
        #expect(other.id != f.space)
        #expect(SidebarSplitTitleEdit(group: group, profileID: f.profile, state: retired) == nil)
    }
}
