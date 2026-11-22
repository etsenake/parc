import AppKit
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

@MainActor
enum DuplicateUndoTestsSupport {
    final class Gate {
        var value = false
    }

    @MainActor final class Dup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-duplicate-undo-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let first: BrowserFolder
        let nested: BrowserFolder
        let second: BrowserFolder
        let target: BrowserFolder
        let noteFile: URL
        let noteBytes: Data
        let easels: EaselStore
        let easel: EaselSession
        let n: BrowserTab
        let w: BrowserTab
        let e: BrowserTab
        let loose: BrowserTab
        let today: BrowserTab
        let keep: BrowserTab
        let split: BrowserSplitLayout
        let pinned: SidebarContainerLocation
        let todayLocation: SidebarContainerLocation
        let secondLocation: SidebarContainerLocation
        let targetLocation: SidebarContainerLocation
        let containers: [SidebarContainerLocation]
        let store: BrowserStore
        let initial: BrowserState
        let blockedDocuments = Gate()
        var documentsBlocked: Bool {
            get { blockedDocuments.value }
            set { blockedDocuments.value = newValue }
        }
        var references: [UUID: SidebarDocumentReference] = [:]
        let copy: SidebarDuplicateResult
        let duplicated: BrowserState
        let record: SidebarCopyUndo
        let copiedIDs: Set<UUID>
        var retired: [Set<UUID>] = []
        var allowRetirement = true
        var restored: [SidebarCopyUndo] = []
        var removals = 0
        var undoUsable = true
        let manager = FolderUndoManager()
        var edited: BrowserState!
        var copiedFolderID: UUID!

        func tab(_ title: String, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            Self.tab(title, space: space, profile: profile, parent: parent, kind: kind, url: url)
        }

        static func tab(_ title: String, space: BrowserSpace, profile: BrowserProfile, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title, kind: kind, folderID: parent,
                         createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }

        init() throws {
            let profile = self.profile
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            self.space = space
            first = BrowserFolder(id: UUID(), spaceID: space.id, name: "First")
            nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: first.id, isExpanded: false)
            second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
            target = BrowserFolder(id: UUID(), spaceID: space.id, name: "Target")
            let notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteFile = notesFolder.appendingPathComponent("Original Note.md")
            try Data("Original body\n".utf8).write(to: noteFile)
            noteBytes = try Data(contentsOf: noteFile)
            easels = try EaselStore(directory: root.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Shared Easel")
            let noteFile = self.noteFile
            n = Self.tab("Note", space: space, profile: profile, parent: nested.id, url: InternalPage.note(noteFile).urlString)
            w = Self.tab("Web", space: space, profile: profile, parent: nested.id)
            e = Self.tab("Easel", space: space, profile: profile, parent: second.id, url: InternalPage.easel(easel.document.id).urlString)
            loose = Self.tab("Loose", space: space, profile: profile, parent: second.id)
            today = Self.tab("Today", space: space, profile: profile, kind: .today)
            keep = Self.tab("Keep", space: space, profile: profile)
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id, tabIDs: [n.id, w.id],
                                       orientation: .vertical, widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.folders = [first, nested, second, target]
            state.tabs = [n, w, e, loose, today, keep]
            state.splitLayouts = [split]
            pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
            todayLocation = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .today)
            secondLocation = SidebarContainerLocation(spaceID: space.id, folderID: second.id, section: .pinned)
            targetLocation = SidebarContainerLocation(spaceID: space.id, folderID: target.id, section: .pinned)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .folder(first.id), .folder(second.id), .folder(target.id)]
            state.sidebarItemOrder[secondLocation.key] = [.tab(loose.id), .tab(e.id)]
            state.selectedTabIDs = [keep.id]
            state.selectionBySpace[space.id.uuidString] = [keep.id]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: root.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            initial = store.state
            let firstLocation = SidebarContainerLocation(spaceID: space.id, folderID: first.id, section: .pinned)
            let nestedLocation = SidebarContainerLocation(spaceID: space.id, folderID: nested.id, section: .pinned)
            containers = [pinned, todayLocation, secondLocation, targetLocation, firstLocation, nestedLocation]
            let easels = self.easels
            let easelID = easel.document.id
            let noteAvailable: @MainActor () throws -> Void = {
                guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) }
            }
            let gate = blockedDocuments
            references = [n.id: SidebarDocumentReference(page: .note(noteFile), profileID: profile.id) {
                                if gate.value { throw CocoaError(.fileReadNoPermission) }
                                try noteAvailable() },
                          e.id: SidebarDocumentReference(page: .easel(easelID), profileID: profile.id) { try easels.validateReference(easelID) }]
            let items: [SidebarItemReference] = [.folder(first.id), .tab(e.id), .tab(today.id)]
            let duplicate = SidebarDuplicateTarget(items: items, spaceID: space.id, profileID: profile.id, state: initial)!
            let urls = Dictionary(uniqueKeysWithValues: duplicate.tabs.map { ($0.id, $0.savedURL) })
            copy = try store.duplicateSidebarItems(duplicate, destinations: urls, documents: references)!
            duplicated = store.state
            copiedIDs = Set(copy.tabIDs)
            record = SidebarCopyUndo(actionName: SidebarCopyUndo.duplicateName, roots: copy.roots, spaceID: space.id, profileID: profile.id,
                                     documents: Array(references.values), openTabIDs: copy.openTabIDs, state: duplicated)!
            store.requestPageRetirement = { [weak self] ids, canCommit, done in
                self?.retired.append(ids)
                done(self?.allowRetirement == true && canCommit())
            }
            let remover: (SidebarCopyUndo, FolderRemovalTarget, @escaping (SidebarCopyUndo?) -> Void) -> Void = { [weak self] record, target, done in
                guard let self else { return done(nil) }
                var refreshed: SidebarCopyUndo?
                removals += 1
                store.removeSidebarCopy(record, target: target, shouldCommit: { true }, didCommit: { refreshed = $0 }) { result in
                    done((try? result.get()) == true ? refreshed : nil)
                }
            }
            self.remover = remover
            manager.appendSidebarCopy(record, store: store, canUse: { [weak self] _, direction in direction == .redo || self?.undoUsable == true },
                                      remove: remover, didRestore: { [weak self] in self?.restored.append($0) }, onError: { _ in })
        }

        var remover: ((SidebarCopyUndo, FolderRemovalTarget, @escaping (SidebarCopyUndo?) -> Void) -> Void)!

        deinit { try? FileManager.default.removeItem(at: root) }

        func layout(_ state: BrowserState) -> [[SidebarItemReference]] { containers.map { SidebarHierarchy.children(in: $0, state: state) } }

        func edit() throws -> Dup {
            var renamed = store.state
            copiedFolderID = record.folders.first { $0.parentID == nil }!.id
            renamed.folders[renamed.folders.firstIndex { $0.id == copiedFolderID }!].name = "Renamed copy"
            let copiedWeb = record.tabs.first { $0.savedURL == w.savedURL }!.id
            renamed.tabs[renamed.tabs.firstIndex { $0.id == copiedWeb }!].url = "https://saved.invalid/Web/next"
            try store.commitProfileSettings(renamed)
            edited = store.state
            return self
        }

        func undone() throws -> Dup {
            _ = try edit()
            manager.undo()
            return self
        }

        func redone() throws -> Dup {
            _ = try undone()
            manager.redo()
            return self
        }

        func dragCopy(_ items: [SidebarItemReference], to destination: SidebarContainerLocation,
                      before: SidebarItemReference? = nil) throws -> (SidebarDuplicateResult, FolderUndoManager, SidebarCopyUndo) {
            store.requestPageRetirement = { _, canCommit, done in done(canCommit()) }
            let made = SidebarItemsCopy(items: items, spaceID: space.id, profileID: profile.id, state: store.state)!
            let sources = Dictionary(uniqueKeysWithValues: made.tabs.map { ($0.id, $0.savedURL) })
            let refs = references
            let docs = Dictionary(uniqueKeysWithValues: made.tabs.compactMap { tab -> (UUID, SidebarDocumentReference)? in
                guard let page = InternalPage(urlString: tab.savedURL) else { return nil }
                return refs.values.first { $0.page == page }.map { (tab.id, $0) }
            })
            let result = try store.copySidebarItems(made, to: destination, before: before, destinations: sources, documents: docs)!
            let record = SidebarCopyUndo(actionName: SidebarCopyUndo.dragCopyName, roots: result.roots, spaceID: space.id, profileID: profile.id,
                                         documents: Array(docs.values), openTabIDs: result.openTabIDs, state: store.state)!
            let manager = FolderUndoManager()
            manager.appendSidebarCopy(record, store: store, canUse: { _, _ in true }, remove: remover,
                                      didRestore: { [weak self] in self?.restored.append($0) }, onError: { _ in })
            return (result, manager, record)
        }
    }
}
