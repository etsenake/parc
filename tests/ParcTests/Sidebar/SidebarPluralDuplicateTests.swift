import AppKit
import Testing
@testable import Parc
@testable import ParcCore

@MainActor
struct SidebarPluralDuplicateTests {
    @MainActor private final class World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-plural-copy-" + UUID().uuidString)
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let space: BrowserSpace
        let first: BrowserFolder
        let nested: BrowserFolder
        let second: BrowserFolder
        let empty: BrowserFolder
        let noteFile: URL
        let easels: EaselStore
        let easel: EaselSession
        let asset: String
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
        let noteBytes: Data
        let assetBytes: Data
        let n: BrowserTab
        let w: BrowserTab
        let e: BrowserTab
        let loose: BrowserTab
        let today: BrowserTab
        let keep: BrowserTab
        let split: BrowserSplitLayout
        let pinned: SidebarContainerLocation
        let secondLocation: SidebarContainerLocation
        let sessionURL: URL
        let store: BrowserStore
        let initial: BrowserState
        let proposed: [SidebarItemReference]
        let target: SidebarDuplicateTarget
        let references: [UUID: SidebarDocumentReference]
        let urls: [UUID: String]
        let encoder = JSONEncoder()

        static func tab(_ title: String, space: BrowserSpace, profile: BrowserProfile, parent: UUID? = nil, kind: TabKind = .pinned, url: String? = nil) -> BrowserTab {
            let url = url ?? "https://saved.invalid/" + title
            return .init(id: UUID(), spaceID: space.id, profileID: profile.id, url: url, title: title, kind: kind, folderID: parent,
                         createdAt: Date(timeIntervalSince1970: 10), lastAccessed: Date(timeIntervalSince1970: 10), savedURL: url, savedTitle: title)
        }

        init() throws {
            encoder.dateEncodingStrategy = .iso8601
            let space = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            self.space = space
            first = BrowserFolder(id: UUID(), spaceID: space.id, name: "First", isExpanded: false)
            nested = BrowserFolder(id: UUID(), spaceID: space.id, name: "Nested", parentID: first.id, isExpanded: false)
            second = BrowserFolder(id: UUID(), spaceID: space.id, name: "Second")
            empty = BrowserFolder(id: UUID(), spaceID: space.id, name: "Empty")
            let notesFolder = root.appendingPathComponent("Parc Notes")
            try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
            noteFile = notesFolder.appendingPathComponent("Original Note.md")
            try Data("Original body\n".utf8).write(to: noteFile)
            easels = try EaselStore(directory: root.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Shared Easel")
            asset = try easel.importPNG(png)
            let assetID = asset
            try easel.perform("Image") { $0.items = [EaselItem(kind: .image, frame: .init(x: 0, y: 0, width: 100, height: 80), assetID: assetID)] }
            noteBytes = try Data(contentsOf: noteFile)
            assetBytes = try Data(contentsOf: easel.assetURL(asset))
            let profile = self.profile
            n = Self.tab("Note", space: space, profile: profile, parent: nested.id, url: InternalPage.note(noteFile).urlString)
            w = Self.tab("Web", space: space, profile: profile, parent: nested.id)
            e = Self.tab("Easel", space: space, profile: profile, parent: second.id, url: InternalPage.easel(easel.document.id).urlString)
            loose = Self.tab("Loose", space: space, profile: profile, parent: second.id)
            today = Self.tab("Today", space: space, profile: profile, kind: .today)
            keep = Self.tab("Keep", space: space, profile: profile)
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Mixed", spaceID: space.id, tabIDs: [n.id, w.id],
                                       orientation: .vertical, widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile], spaces: [space], activeSpaceID: space.id)
            state.folders = [first, nested, second, empty]
            state.tabs = [n, w, e, loose, today, keep]
            state.splitLayouts = [split]
            pinned = SidebarContainerLocation(spaceID: space.id, folderID: nil, section: .pinned)
            secondLocation = SidebarContainerLocation(spaceID: space.id, folderID: second.id, section: .pinned)
            state.sidebarItemOrder[pinned.key] = [.tab(keep.id), .folder(first.id), .folder(second.id), .folder(empty.id)]
            state.sidebarItemOrder[secondLocation.key] = [.tab(loose.id), .tab(e.id)]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace[space.id.uuidString] = split.tabIDs
            sessionURL = root.appendingPathComponent("session.json")
            try encoder.encode(state).write(to: sessionURL)
            store = try BrowserStore(directory: root, now: { Date(timeIntervalSince1970: 1000) })
            initial = store.state
            proposed = [.folder(first.id), .folder(nested.id), .split(split.id), .folder(empty.id), .tab(loose.id), .tab(e.id), .tab(today.id)]
            target = SidebarDuplicateTarget(items: proposed, spaceID: space.id, profileID: profile.id, state: initial)!
            let noteFile = self.noteFile
            let easels = self.easels
            let easelID = easel.document.id
            references = [n.id: SidebarDocumentReference(page: .note(noteFile), profileID: profile.id) {
                guard FileManager.default.fileExists(atPath: noteFile.path) else { throw CocoaError(.fileNoSuchFile) }
            }, e.id: SidebarDocumentReference(page: .easel(easelID), profileID: profile.id) { try easels.validateReference(easelID) }]
            urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, InternalPage(urlString: $0.savedURL) == nil ? "https://live.invalid/" + $0.id.uuidString : $0.savedURL) })
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func target(for items: [SidebarItemReference], state: BrowserState? = nil, profile: UUID? = nil) -> SidebarDuplicateTarget? {
            SidebarDuplicateTarget(items: items, spaceID: space.id, profileID: profile ?? self.profile.id, state: state ?? initial)
        }

        func committed() throws -> (SidebarDuplicateResult, BrowserState) {
            let copy = try store.duplicateSidebarItems(target, destinations: urls, documents: references)!
            return (copy, store.state)
        }
    }

    @Test func anAncestorOwnsANestedSelectedFolderAndSplitOnceInOriginalInputOrder() throws {
        let w = try World()
        #expect(w.target.roots == [.folder(w.first.id), .folder(w.empty.id), .tab(w.loose.id), .tab(w.e.id), .tab(w.today.id)])
    }

    @Test func originalDescendantAndRootOrderIsCaptured() throws {
        let w = try World()
        #expect(w.target.tabs.map(\.id) == [w.n.id, w.w.id, w.loose.id, w.e.id, w.today.id])
    }

    @Test func emptyFoldersAndTheCompleteSplitAreRetained() throws {
        let w = try World()
        #expect(w.target.folderIDs == [w.first.id, w.nested.id, w.empty.id])
        #expect(w.target.groups == [w.split])
    }

    @Test func aPartialSplitPaneIsRefused() throws {
        let w = try World()
        #expect(w.target(for: [.tab(w.n.id)]) == nil)
    }

    @Test func duplicateExplicitRootsAreRefused() throws {
        let w = try World()
        #expect(w.target(for: [.folder(w.first.id), .folder(w.first.id)]) == nil)
    }

    @Test func aForeignProfileIsRefused() throws {
        let w = try World()
        #expect(w.target(for: w.proposed, profile: UUID()) == nil)
    }

    @Test func aForeignNestedChildCannotPartiallyCopy() throws {
        let w = try World()
        var malformed = w.initial
        malformed.tabs[0].profileID = UUID()
        #expect(w.target(for: w.proposed, state: malformed) == nil)
    }

    @Test func folderDescendantsMustRemainSaved() throws {
        let w = try World()
        var malformed = w.initial
        malformed.tabs[0].kind = .today
        #expect(w.target(for: w.proposed, state: malformed) == nil)
    }

    @Test func aMalformedSplitIsRefused() throws {
        let w = try World()
        var malformed = w.initial
        malformed.splitLayouts[0].tabIDs = [w.n.id, w.n.id]
        #expect(w.target(for: w.proposed, state: malformed) == nil)
    }

    @Test func aFavoriteContextIsOutsideThisOwner() throws {
        let w = try World()
        var malformed = w.initial
        malformed.tabs[5].kind = .favorite
        #expect(w.target(for: [.tab(w.keep.id)], state: malformed) == nil)
    }

    @Test func aMissingTypedCapabilityRefusesTheEntireMixedCollection() throws {
        let w = try World()
        #expect(try w.store.duplicateSidebarItems(w.target, destinations: w.urls) == nil)
        #expect(w.store.state == w.initial)
    }

    @Test func thereIsNoFakeWebToDocumentURLCopy() throws {
        let w = try World()
        var bad = w.urls
        bad[w.w.id] = w.n.savedURL
        #expect(try w.store.duplicateSidebarItems(w.target, destinations: bad, documents: w.references) == nil)
        #expect(w.store.state == w.initial)
    }

    @Test func aWrongOriginalDocumentProfileRefusesAllRoots() throws {
        let w = try World()
        var bad = w.references
        bad[w.n.id] = SidebarDocumentReference(page: .note(w.noteFile), profileID: UUID()) {}
        #expect(try w.store.duplicateSidebarItems(w.target, destinations: w.urls, documents: bad) == nil)
        #expect(w.store.state == w.initial)
    }

    @Test func oneRetiringOriginalBlocksTheCompleteCopy() throws {
        let w = try World()
        var completion: ((Bool) -> Void)?
        w.store.requestPageRetirement = { _, _, done in completion = done }
        w.store.closeTabs([w.w.id]) { _ in }
        #expect(try w.store.duplicateSidebarItems(w.target, destinations: w.urls, documents: w.references) == nil)
        completion?(false)
    }

    private func failingSession(_ w: World) throws -> Data {
        let before = try Data(contentsOf: w.sessionURL)
        try FileManager.default.removeItem(at: w.sessionURL)
        try FileManager.default.createDirectory(at: w.sessionURL, withIntermediateDirectories: false)
        return before
    }

    @Test func aRealPersistenceFailurePublishesNoPartialRoots() throws {
        let w = try World()
        _ = try failingSession(w)
        #expect(throws: (any Error).self) { try w.store.duplicateSidebarItems(w.target, destinations: w.urls, documents: w.references) }
        #expect(w.store.state == w.initial)
        #expect(FileManager.default.fileExists(atPath: w.sessionURL.path))
    }

    @Test func aFailedSidebarSaveNeverWritesOriginalDocumentData() throws {
        let w = try World()
        _ = try failingSession(w)
        _ = try? w.store.duplicateSidebarItems(w.target, destinations: w.urls, documents: w.references)
        #expect(try Data(contentsOf: w.noteFile) == w.noteBytes)
        #expect(try Data(contentsOf: w.easel.assetURL(w.asset)) == w.assetBytes)
    }

    @Test func allNormalizedRootsCommitTogether() throws {
        let w = try World()
        let (copy, _) = try w.committed()
        #expect(copy.roots.count == 5)
        #expect(copy.tabIDs.count == 5)
    }

    @Test func copiedTabsAreFreshAliases() throws {
        let w = try World()
        let (copy, _) = try w.committed()
        #expect(Set(copy.tabIDs).isDisjoint(with: w.initial.tabs.map(\.id)))
    }

    @Test func allOriginalRecordsAreUnchanged() throws {
        let w = try World()
        let (_, after) = try w.committed()
        #expect(after.tabs.prefix(w.initial.tabs.count).elementsEqual(w.initial.tabs))
        #expect(after.folders.prefix(w.initial.folders.count).elementsEqual(w.initial.folders))
    }

    @Test func theOriginalSplitIsRetainedAndCopiedOnce() throws {
        let w = try World()
        let (_, after) = try w.committed()
        #expect(after.splitLayouts.first == w.split)
        #expect(after.splitLayouts.count == 2)
    }

    @Test func noSelectedPageOrSpaceChanges() throws {
        let w = try World()
        let (_, after) = try w.committed()
        #expect(after.selectedTabIDs == w.initial.selectedTabIDs)
        #expect(after.selectionBySpace == w.initial.selectionBySpace)
        #expect(after.activeSpaceID == w.initial.activeSpaceID)
    }

    @Test func eachRootCopyIsAdjacentInTheOriginalMixedRootOrder() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        #expect(SidebarHierarchy.children(in: w.pinned, state: after)
                == [.tab(w.keep.id), .folder(w.first.id), copy.roots[0], .folder(w.second.id), .folder(w.empty.id), copy.roots[1]])
    }

    @Test func multipleRootsSharingAParentAccumulateInOneOrderProposal() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        #expect(SidebarHierarchy.children(in: w.secondLocation, state: after) == [.tab(w.loose.id), copy.roots[2], .tab(w.e.id), copy.roots[3]])
    }

    @Test func theExactResolvedLiveURLOrTypedIdentityIsPreserved() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let copied = copy.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        #expect(copied.map { $0.savedURL } == w.target.tabs.map { w.urls[$0.id]! })
    }

    @Test func todayAndSavedKindsRemainOriginal() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let copied = copy.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        #expect(copied.map { $0.kind } == w.target.tabs.map { $0.kind })
    }

    @Test func newCopiedRecordMetadata() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let copied = copy.tabIDs.map { id in after.tabs.first { $0.id == id }! }
        #expect(copied.allSatisfy { $0.isUnread && $0.createdAt == Date(timeIntervalSince1970: 1000) })
    }

    @Test func theOriginalRecursiveEffectOrderOpensOnlyOrdinaryPages() throws {
        let w = try World()
        let (copy, _) = try w.committed()
        #expect(copy.openTabIDs == [copy.tabIDs[1], copy.tabIDs[2], copy.tabIDs[4]])
    }

    @Test func theWholeSplitReceivesFreshMappedIDs() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let group = after.splitLayouts[1]
        #expect(group.id != w.split.id)
        #expect(group.tabIDs == Array(copy.tabIDs.prefix(2)))
    }

    @Test func theOriginalSplitAnchorAndRenderedLayoutArePreserved() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let group = after.splitLayouts[1]
        #expect(group.sidebarAnchorID == copy.tabIDs[0])
        #expect(group.widthFactors == w.split.widthFactors)
        #expect(group.orientation == w.split.orientation)
        #expect(group.customTitle == w.split.customTitle)
    }

    @Test func originalFilesRemainIdenticalAfterACommittedCopy() throws {
        let w = try World()
        _ = try w.committed()
        #expect(try Data(contentsOf: w.noteFile) == w.noteBytes)
        #expect(try Data(contentsOf: w.easel.assetURL(w.asset)) == w.png)
    }

    @Test func copiedAliasesRetainTheSameRealSharedSessions() throws {
        let w = try World()
        _ = try w.committed()
        let loaded = try w.easels.load(w.easel.document.id)
        #expect(loaded === w.easel)
    }

    @Test func anAliasObservesTheSameOriginalNoteFile() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let copied = after.tabs.first { $0.id == copy.tabIDs[0] }!
        try Data("Shared later edit\n".utf8).write(to: w.noteFile)
        #expect(try String(contentsOf: InternalPage(urlString: copied.savedURL)!.noteURL!, encoding: .utf8) == "Shared later edit\n")
    }

    @Test func theOriginalMenuSnapshotCannotExecuteAgainAfterTheHierarchyChanged() throws {
        let w = try World()
        _ = try w.committed()
        #expect(try w.store.duplicateSidebarItems(w.target, destinations: w.urls, documents: w.references) == nil)
    }

    @Test func allCommittedIdentitiesDurablyReload() throws {
        let w = try World()
        let (copy, after) = try w.committed()
        let reload = try BrowserStore(directory: w.root)
        #expect(copy.tabIDs.allSatisfy { id in reload.state.tabs.contains { $0.id == id } })
        #expect(reload.state.splitLayouts.contains(after.splitLayouts[1]))
    }

    @Test func sevenRootsAreSavedAndExactlyTheFirstFiveOrdinaryRootsRequestOpening() throws {
        let w = try World()
        var many = w.initial
        many.folders = []
        many.splitLayouts = []
        many.tabs = (0..<7).map { World.tab("root\($0)", space: w.space, profile: w.profile, kind: .today) }
        many.sidebarItemOrder = [:]
        many.selectedTabIDs = [many.tabs[0].id]
        many.selectionBySpace = [:]
        let other = w.root.appendingPathComponent("Many")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try w.encoder.encode(many).write(to: other.appendingPathComponent("session.json"))
        let manyStore = try BrowserStore(directory: other)
        let manyTarget = SidebarDuplicateTarget(items: many.tabs.map { .tab($0.id) }, spaceID: w.space.id, profileID: w.profile.id, state: manyStore.state)!
        let manyCopy = try manyStore.duplicateSidebarItems(manyTarget, destinations: Dictionary(uniqueKeysWithValues: many.tabs.map { ($0.id, $0.savedURL) }))!
        #expect(manyCopy.tabIDs.count == 7)
        #expect(manyCopy.openTabIDs == Array(manyCopy.tabIDs.prefix(5)))
    }
}
