import AppKit
import Foundation
import Testing
@testable import Parc
@testable import ParcCore

enum ClosedTabsUndoSupport {
    @MainActor final class Consent {
        var authorize: (() -> Bool)?
        var finish: ((Bool) -> Void)?
        var autoApprove = false
        var usable = true
        var undone = 0
        var errors: [Error] = []
        var redoCurrent: (() -> Bool)?
        var refused = Set<UUID>()
        var lastOperation: ClosedTabsUndoOperation?

        func attach(_ store: BrowserStore) {
            store.requestPageRetirement = { [unowned self] _, canCommit, done in
                if autoApprove { done(canCommit()) } else { authorize = canCommit; finish = done }
            }
        }

        func approve() {
            _ = authorize?()
            finish?(true)
        }

        func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager, on owner: BrowserStore) -> Bool {
            lastOperation = nil
            manager.appendClosedTabs(record, store: owner, canUse: { [unowned self] ids, _ in usable && ids.isDisjoint(with: refused) },
                                     close: { [unowned self] ids, current, done in
                redoCurrent = current
                var next: ClosedTabsUndo?
                owner.closeTabs(ids, reason: .manual, didCommit: { before in
                    next = ClosedTabsUndo(prompt: record.prompt, ids: ids, spaceID: record.spaceID, profileID: record.profileID,
                                          focusedTabID: nil, before: before, after: owner.state)
                }, shouldCommit: current) { done($0 ? next : nil) }
            }, didUndo: { [unowned self] _ in undone += 1 }, onError: { [unowned self] in errors.append($0) }) { [unowned self] in lastOperation = $0 }
            return lastOperation != nil
        }
    }

    static func makeTab(_ title: String, _ space: BrowserSpace, profile: BrowserProfile, kind: TabKind = .today, folder: UUID? = nil) -> BrowserTab {
        let url = "https://" + title.lowercased().replacingOccurrences(of: " ", with: "-") + ".invalid/"
        return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title,
                     kind: kind, folderID: folder, createdAt: Date(timeIntervalSince1970: 10),
                     lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
    }

    static func writeSeed(_ state: BrowserState, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url)
        return url
    }

    static let storeClock: () -> Date = { Date(timeIntervalSince1970: 1_900_000_000) }

    static func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-close-undo-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @MainActor final class ClearFixture {
        let consent = Consent()
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let here: BrowserSpace, there: BrowserSpace
        let folder: BrowserFolder
        let pinned: BrowserTab, filed: BrowserTab, first: BrowserTab, left: BrowserTab, right: BrowserTab, last: BrowserTab
        let elsewhere: BrowserTab, elsewhereToo: BrowserTab, earlier: BrowserTab
        let split: BrowserSplitLayout
        let today: SidebarContainerLocation, thereToday: SidebarContainerLocation, pinnedList: SidebarContainerLocation
        let sessionURL: URL
        let store: BrowserStore
        let initial: BrowserState
        var record: ClosedTabsUndo?
        var committed: Bool?
        var hereIDs: Set<UUID> { [first.id, left.id, right.id, last.id] }

        init() throws {
            root = try temporaryRoot()
            here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            there = BrowserSpace(id: UUID(), name: "There", symbol: "square", color: "123456", profileID: profile.id)
            folder = BrowserFolder(id: UUID(), spaceID: here.id, name: "Pinned folder")
            let profile = profile, here = here, there = there
            pinned = makeTab("Pinned", here, profile: profile, kind: .pinned)
            filed = makeTab("Filed", here, profile: profile, kind: .pinned, folder: folder.id)
            first = makeTab("First", here, profile: profile)
            left = makeTab("Left", here, profile: profile)
            right = makeTab("Right", here, profile: profile)
            last = makeTab("Last", here, profile: profile)
            elsewhere = makeTab("Elsewhere", there, profile: profile)
            elsewhereToo = makeTab("Elsewhere too", there, profile: profile)
            var archived = makeTab("Earlier archive", here, profile: profile)
            archived.archivedAt = Date(timeIntervalSince1970: 1_000)
            earlier = archived
            split = BrowserSplitLayout(sidebarAnchorID: left.id, customTitle: "Pair", spaceID: here.id,
                                       tabIDs: [left.id, right.id], orientation: .vertical, widthFactors: [0.3, 0.7])
            var seed = BrowserState(profiles: [profile], spaces: [here, there], activeSpaceID: here.id)
            seed.folders = [folder]
            seed.tabs = [pinned, filed, first, left, right, last, elsewhere, elsewhereToo, earlier]
            seed.splitLayouts = [split]
            today = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .today)
            thereToday = SidebarContainerLocation(spaceID: there.id, folderID: nil, section: .today)
            pinnedList = SidebarContainerLocation(spaceID: here.id, folderID: nil, section: .pinned)
            seed.sidebarItemOrder[today.key] = [.tab(last.id), .tab(left.id), .tab(first.id)]
            seed.sidebarItemOrder[pinnedList.key] = [.folder(folder.id), .tab(pinned.id)]
            seed.sidebarItemOrder[thereToday.key] = [.tab(elsewhereToo.id), .tab(elsewhere.id)]
            seed.selectedTabIDs = [first.id]
            seed.selectionBySpace[here.id.uuidString] = [first.id]
            sessionURL = try writeSeed(seed, to: root)
            store = try BrowserStore(directory: root, now: storeClock)
            initial = store.state
            consent.attach(store)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func todayIDs(_ space: BrowserSpace) -> Set<UUID> {
            Set(store.state.tabs.filter { $0.archivedAt == nil && $0.kind == .today && $0.spaceID == space.id && $0.profileID == profile.id }.map(\.id))
        }

        func clear(_ space: BrowserSpace) {
            record = nil
            committed = nil
            let ids = todayIDs(space)
            let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
                profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
                focused: store.state.selectedTabIDs.last, available: { _ in true })
            store.closeTabs(ids, reason: .clearButton, selection: selection, didCommit: { [unowned self] before in
                record = ClosedTabsUndo(prompt: .clear, ids: ids, spaceID: space.id, profileID: profile.id, focusedTabID: nil,
                                        before: before, after: store.state)
            }, shouldCommit: { true }) { [unowned self] in committed = $0 }
        }

        func approvedClear() -> ClosedTabsUndo {
            clear(here)
            _ = consent.authorize?()
            consent.finish?(true)
            return record!
        }

        func register(_ record: ClosedTabsUndo, in manager: FolderUndoManager) -> Bool {
            consent.register(record, in: manager, on: store)
        }

        func goToThere() {
            _ = store.setWindowPresentation(spaceID: there.id, selectedTabIDs: [elsewhere.id])
        }

        func registeredClear() -> (ClosedTabsUndo, FolderUndoManager) {
            let record = approvedClear()
            let window = FolderUndoManager()
            _ = register(record, in: window)
            goToThere()
            return (record, window)
        }

        func autoClear(_ space: BrowserSpace) -> ClosedTabsUndo {
            consent.autoApprove = true
            clear(space)
            return record!
        }
    }

    @MainActor final class ArchiveFixture {
        let consent = Consent()
        let root: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let work: BrowserSpace
        let shelf: BrowserFolder
        let note: BrowserTab, shelved: BrowserTab, keep: BrowserTab
        let t1: BrowserTab, t2: BrowserTab, t3: BrowserTab, s1: BrowserTab, s2: BrowserTab
        let duo: BrowserSplitLayout
        let workToday: SidebarContainerLocation, shelfBox: SidebarContainerLocation
        let store: BrowserStore
        let original: [SidebarItemReference]

        init() throws {
            root = try temporaryRoot()
            work = BrowserSpace(id: UUID(), name: "Work", symbol: "circle", color: "FFEEDD", profileID: profile.id)
            shelf = BrowserFolder(id: UUID(), spaceID: work.id, name: "Shelf")
            let profile = profile, work = work, shelf = shelf
            var noteTab = makeTab("Note", work, profile: profile, kind: .pinned, folder: shelf.id)
            noteTab.url = "parc://note/" + UUID().uuidString.lowercased()
            noteTab.savedURL = noteTab.url
            note = noteTab
            shelved = makeTab("Shelved", work, profile: profile, kind: .pinned, folder: shelf.id)
            keep = makeTab("Keep", work, profile: profile, kind: .pinned)
            t1 = makeTab("T1", work, profile: profile)
            t2 = makeTab("T2", work, profile: profile)
            t3 = makeTab("T3", work, profile: profile)
            s1 = makeTab("S1", work, profile: profile)
            s2 = makeTab("S2", work, profile: profile)
            duo = BrowserSplitLayout(sidebarAnchorID: s1.id, customTitle: "Duo", spaceID: work.id,
                                     tabIDs: [s1.id, s2.id], orientation: .horizontal, widthFactors: [0.4, 0.6])
            var seed = BrowserState(profiles: [profile], spaces: [work], activeSpaceID: work.id)
            seed.folders = [shelf]
            seed.tabs = [note, shelved, keep, t1, t2, t3, s1, s2]
            seed.splitLayouts = [duo]
            workToday = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .today)
            let workPinned = SidebarContainerLocation(spaceID: work.id, folderID: nil, section: .pinned)
            shelfBox = SidebarContainerLocation(spaceID: work.id, folderID: shelf.id, section: .pinned)
            seed.sidebarItemOrder[workToday.key] = [.tab(t1.id), .tab(s1.id), .tab(t2.id), .tab(t3.id)]
            seed.sidebarItemOrder[workPinned.key] = [.folder(shelf.id), .tab(keep.id)]
            seed.sidebarItemOrder[shelfBox.key] = [.tab(note.id), .tab(shelved.id)]
            seed.selectedTabIDs = [t2.id]
            seed.selectionBySpace[work.id.uuidString] = [t2.id]
            _ = try writeSeed(seed, to: root)
            store = try BrowserStore(directory: root, now: storeClock)
            consent.attach(store)
            consent.autoApprove = true
            original = SidebarHierarchy.children(in: workToday, state: store.state)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        var order: [SidebarItemReference] { SidebarHierarchy.children(in: workToday, state: store.state) }

        func close(_ ids: Set<UUID>, focused: UUID?, prompt: ClosedTabsUndo.Prompt = .archive) -> ClosedTabsUndo? {
            var made: ClosedTabsUndo?
            let selection = FolderRemovalSelection.resolve(removing: ids, spaceID: store.state.activeSpaceID,
                profileID: profile.id, state: store.state, selected: store.state.selectedTabIDs,
                focused: store.state.selectedTabIDs.last, available: { _ in true })
            store.closeTabs(ids, reason: prompt == .clear ? .clearButton : .manual, selection: selection, didCommit: { [unowned self] before in
                made = ClosedTabsUndo(prompt: prompt, ids: ids, spaceID: work.id, profileID: profile.id,
                                      focusedTabID: focused, before: before, after: store.state)
            }, shouldCommit: { true })
            return made
        }

        func register(_ record: ClosedTabsUndo, in existing: FolderUndoManager? = nil) -> FolderUndoManager {
            let manager = existing ?? FolderUndoManager()
            #expect(consent.register(record, in: manager, on: store))
            return manager
        }

        func select(_ ids: [UUID]) {
            _ = store.setWindowPresentation(spaceID: work.id, selectedTabIDs: ids)
        }
    }
}
