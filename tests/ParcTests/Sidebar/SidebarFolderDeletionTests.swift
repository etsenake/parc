import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarFolderDeletionTests {
    @MainActor private final class Deletion {
        let sidebar = SidebarView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window: SidebarTestWindow
        var state = BrowserState.initial()
        let space: BrowserSpace
        let folder: BrowserFolder
        let other: BrowserFolder
        let tab: BrowserTab
        var revision = 0
        var preparations = 0
        var commits = 0
        var deletions = 0
        var closes = 0
        var deletionResult: Bool? = true
        var closeResult: Bool? = true
        var deleted: [SidebarItemReference] = []
        var closed: [SidebarItemReference] = []
        let emptyFolders: Set<UUID>

        init() {
            window = sidebarTestWindow(containing: sidebar, deferred: false)
            space = state.spaces[0]
            let spaceID = space.id
            folder = BrowserFolder(id: UUID(), spaceID: spaceID, name: "First")
            other = BrowserFolder(id: UUID(), spaceID: spaceID, name: "Second")
            let profile = space.profileID
            tab = BrowserTab(id: UUID(), spaceID: spaceID, profileID: profile, url: "https://example.test/a", title: "a", kind: .pinned,
                             createdAt: Date(), lastAccessed: Date(), savedURL: "https://example.test/a", savedTitle: "a")
            state.folders = [folder, other]
            state.tabs = [tab]
            emptyFolders = [folder.id, other.id]
            sidebar.canSelectItems = { true }
            let id = folder.id
            sidebar.prepareFolderDeletion = { [weak self] target in
                guard let self, target == id else { return nil }
                preparations += 1
                let captured = revision
                return { [weak self] in
                    guard let self, captured == revision else { return false }
                    commits += 1
                    return true
                }
            }
            let empties = emptyFolders
            sidebar.holdsOnlyEmptyFolders = { items in
                items.allSatisfy { if case .folder(let folder) = $0 { return empties.contains(folder) }; return false }
            }
            sidebar.prepareSidebarDeletion = { [weak self] items in
                guard let self, let result = deletionResult else { return nil }
                return { [weak self] in self?.deleted = items; self?.deletions += 1; return result }
            }
            sidebar.prepareSidebarClose = { [weak self] items in
                guard let self, let result = closeResult else { return nil }
                return { [weak self] in self?.closed = items; self?.closes += 1; return result }
            }
            render()
        }

        deinit { MainActor.assumeIsolated { window.contentView = nil } }

        func render(_ state: BrowserState? = nil) {
            sidebar.render(state: state ?? self.state, focusedTabID: nil, loading: [], canBack: false, canForward: false)
            sidebar.layoutSubtreeIfNeeded()
        }

        func folderRow(_ id: UUID? = nil) -> SidebarFolderRow {
            let wanted = id ?? folder.id
            return sidebarDescendants(sidebar).compactMap { $0 as? SidebarFolderRow }.first { $0.folderID == wanted }!
        }

        func deleteItem(_ row: SidebarFolderRow? = nil) -> (NSMenu, NSMenuItem) {
            let menu = (row ?? folderRow()).makeMenu!()!
            return (menu, menu.items.first { $0.title == "Delete" }!)
        }

        func select(_ ids: [UUID]) {
            for id in ids {
                _ = folderRow(id).accessibilityCustomActions()?.first { $0.name == "Add or Remove from Selection" }?.handler?()
            }
        }

        func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                             context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        func focused() {
            _ = window.makeFirstResponder(sidebar)
        }
    }

    @Test func deleteMenuPreparesCurrentOwnersNotTheRenderTimeLease() {
        let d = Deletion()
        let (menu, item) = d.deleteItem()
        d.revision += 1
        menu.performActionForItem(at: menu.index(of: item))
        #expect(d.commits == 1)
    }

    @Test func aReusedMenuPreparesANewOneShotAction() {
        let d = Deletion()
        let (menu, item) = d.deleteItem()
        d.revision += 1
        menu.performActionForItem(at: menu.index(of: item))
        menu.performActionForItem(at: menu.index(of: item))
        #expect(d.commits == 2)
    }

    @Test func aRemovedFolderCannotBeRetargeted() {
        let d = Deletion()
        let (menu, item) = d.deleteItem()
        var without = d.state
        without.folders.removeAll { $0.id == d.folder.id }
        d.render(without)
        menu.performActionForItem(at: menu.index(of: item))
        #expect(d.commits == 0)
    }

    @Test func aChangedSpaceCannotRetargetACachedRow() {
        let d = Deletion()
        #expect(!d.sidebar.performFolderDeletion(d.folder.id, spaceID: UUID()))
        #expect(d.commits == 0)
    }

    @Test func aPrivateContextCannotDeleteSavedFolders() {
        let d = Deletion()
        let (menu, item) = d.deleteItem()
        d.sidebar.isPrivateBrowsing = true
        menu.performActionForItem(at: menu.index(of: item))
        #expect(d.commits == 0)
        #expect(!d.sidebar.performFolderDeletion(d.folder.id, spaceID: d.space.id))
    }

    @Test func theDeleteItemIsDisabledInAPrivateContext() {
        let d = Deletion()
        d.sidebar.isPrivateBrowsing = true
        #expect(!d.deleteItem().1.isEnabled)
    }

    @Test func theDeleteItemIsEnabledWithAnOwner() {
        #expect(Deletion().deleteItem().1.isEnabled)
    }

    @Test func aRestoredFolderWhoseWindowSelectionChangesStillDeletesThroughTheCurrentLease() {
        let d = Deletion()
        let (menu, item) = d.deleteItem()
        d.revision += 1
        menu.performActionForItem(at: menu.index(of: item))
        #expect(d.preparations == 1)
        #expect(d.commits == 1)
    }

    @Test(arguments: [UInt16(51), UInt16(117)])
    func bothDeleteKeysDispatchSingletonFolderDeletion(code: UInt16) {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        #expect(d.sidebar.handleFolderDeletionKey(d.key(code)))
        #expect(d.commits == 1)
    }

    @Test func aHiddenSidebarDoesNotHandleTheDeleteKey() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        d.sidebar.isPresented = false
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(51)))
    }

    @Test func aNonKeyWindowDoesNotHandleTheDeleteKey() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        d.window.key = false
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(51)))
    }

    @Test func anotherFirstResponderDoesNotHandleTheDeleteKey() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        _ = d.window.makeFirstResponder(nil)
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(51)))
    }

    @Test func aCommandDeleteIsNotHandled() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(51, .command)))
    }

    @Test func anotherKeyIsNotHandled() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(125)))
    }

    @Test func aPluralSelectionStaysOnTheExistingCloseRoute() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id, d.other.id])
        #expect(!d.sidebar.handleFolderDeletionKey(d.key(51)))
        #expect(d.commits == 0)
    }

    @Test func deleteOnOnlyEmptyFoldersTakesTheSelectionsFolderDeleteNotClose() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id, d.other.id])
        d.sidebar.keyDown(with: d.key(51))
        #expect(d.deletions == 1)
        #expect(d.closes == 0)
        #expect(d.deleted.count == 2)
    }

    @Test func selectionsHoldingTabsKeepClose() {
        let d = Deletion()
        d.focused()
        d.sidebar.holdsOnlyEmptyFolders = { _ in false }
        d.select([d.folder.id, d.other.id])
        d.sidebar.keyDown(with: d.key(51))
        #expect(d.closes == 1)
        #expect(d.deletions == 0)
        #expect(d.closed.count == 2)
    }

    @Test func withoutAFolderAnswerDeleteKeepsClose() {
        let d = Deletion()
        d.focused()
        d.sidebar.holdsOnlyEmptyFolders = nil
        d.select([d.folder.id, d.other.id])
        d.sidebar.keyDown(with: d.key(51))
        #expect(d.closes == 1)
        #expect(d.deletions == 0)
    }

    @Test func aRefusedFolderDeletionNeverFallsBackToClose() {
        let d = Deletion()
        d.focused()
        d.deletionResult = false
        d.select([d.folder.id, d.other.id])
        d.sidebar.keyDown(with: d.key(51))
        #expect(d.deletions == 1)
        #expect(d.closes == 0)
    }

    @Test func unavailableFolderDeletionNeverClosesInstead() {
        let d = Deletion()
        d.focused()
        d.deletionResult = nil
        d.select([d.folder.id, d.other.id])
        d.sidebar.keyDown(with: d.key(51))
        #expect(d.deletions == 0)
        #expect(d.closes == 0)
    }

    @Test func editDeleteDispatchesTheSelectedFolder() {
        let d = Deletion()
        d.focused()
        d.select([d.folder.id])
        d.sidebar.delete(nil)
        #expect(d.commits == 1)
    }

    @Test func editDeletePreservesAnotherRespondersOwnership() {
        let d = Deletion()
        d.select([d.folder.id])
        _ = d.window.makeFirstResponder(nil)
        d.sidebar.delete(nil)
        #expect(d.commits == 0)
    }
}
