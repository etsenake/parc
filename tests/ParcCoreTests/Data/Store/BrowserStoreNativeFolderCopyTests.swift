import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativeFolderCopyTests {
    private struct CopyFixture {
        let directory: URL
        let store: BrowserStore
        let date: Date
        let space: UUID
        let profile: UUID
        let parent: UUID
        let nested: UUID
        let first: UUID
        let group: BrowserSplitLayout
        let root: SidebarContainerLocation
        let original: BrowserState
        let target: FolderDuplicateTarget
        let urls: [UUID: String]
    }

    @MainActor
    private static func withCopyFixture(_ body: (CopyFixture) throws -> Void) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Research")
            let nested = store.createFolder(name: "Articles", parentID: parent)
            _ = store.createFolder(name: "Empty", parentID: nested)
            let first = store.open("https://example.org/saved", kind: .pinned)
            let splitA = store.open("https://example.org/a")
            let splitB = store.open("https://example.org/b")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTestsSupport.savedSplit(store, [splitA, splitB], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(splitA)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let group = store.activeSplitLayout!
            let root = SidebarContainerLocation(spaceID: space, folderID: nil, section: .pinned)
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            let snap = SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first), expected: snap)
            store.toggleFolder(nested)
            store.updateTab(first, title: "Live title", url: "https://example.org/current")
            let original = store.state
            let target = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: original)!
            let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, $0.id == first ? "https://example.org/live-at-command" : $0.savedURL) })
            try body(CopyFixture(directory: directory, store: store, date: date, space: space, profile: profile,
                                 parent: parent, nested: nested, first: first, group: group, root: root, original: original,
                                 target: target, urls: urls))
        }
    }

    @Test @MainActor static func duplicatingTheWholeTreePublishesOnceAfterSaving() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let copy = try store.duplicateFolder(fixture.target, destinations: fixture.urls)!
            #expect(publications == 1, "Whole duplicate tree publishes once after its save")
            _ = copy
            observation.cancel()
        }
    }

    @Test @MainActor static func aFolderCopyGetsFreshIdentitiesAndKeepsTheOriginalTreeAndSelection() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let parent = fixture.parent
            let target = fixture.target
            let original = fixture.original
            let group = fixture.group
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            #expect(copy.folderID != parent && Set(copy.tabIDs).isDisjoint(with: Set(target.tabs.map(\.id))), "Copies receive fresh identities")
            #expect(original.tabs.allSatisfy { value in store.state.tabs.contains(value) }, "Original saved tabs remain byte-for-byte values")
            #expect(original.folders.allSatisfy { store.state.folders.contains($0) } && store.state.splitLayouts.contains(group), "Original folder and split identity/geometry remain intact")
            #expect(store.state.selectedTabIDs == original.selectedTabIDs && store.state.activeSpaceID == original.activeSpaceID, "Copy leaves active original page selection unchanged")
            #expect(store.state.history == original.history && store.state.downloads == original.downloads, "Duplication does not fabricate browsing/download history")
        }
    }

    @Test @MainActor static func aFolderCopyKeepsNestedAndEmptyFoldersAndTheirDisclosure() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let nested = fixture.nested
            let original = fixture.original
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            let copiedParent = store.state.folders.first { $0.id == copy.folderID }!
            let copiedNested = store.state.folders.first { $0.parentID == copy.folderID }!
            let copiedEmpty = store.state.folders.first { $0.parentID == copiedNested.id }!
            #expect(copiedParent.name == "Research" && copiedNested.name == "Articles" && copiedEmpty.name == "Empty", "Nested and empty folder names survive without an invented suffix")
            #expect(copiedNested.isExpanded == original.folders.first { $0.id == nested }!.isExpanded, "Collapsed descendant contents and disclosure survive")
        }
    }

    @Test @MainActor static func copiedTabsKeepTheResolvedDestinationAndSavedTitle() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let first = fixture.first
            let urls = fixture.urls
            let target = fixture.target
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            let currentCopy = newTabs.first { $0.folderID == copy.folderID }!
            #expect(currentCopy.url == urls[first] && currentCopy.savedURL == urls[first], "Resolved original page destination becomes the copied saved destination")
            #expect(currentCopy.savedTitle == target.tabs.first { $0.id == first }!.savedTitle, "Saved title is distinct from current page title")
        }
    }

    @Test @MainActor static func copiedTabsKeepTheirProfileSpaceAndFreshLifecycleMetadata() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let profile = fixture.profile
            let space = fixture.space
            let date = fixture.date
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            #expect(newTabs.allSatisfy { $0.profileID == profile && $0.spaceID == space && $0.kind == .pinned && $0.createdAt == date && $0.archivedAt == nil }, "New saved records keep exact Profile/Space and fresh lifecycle metadata")
        }
    }

    @Test @MainActor static func aCopiedSplitKeepsItsGeometryAndRequestsItsBackgroundPages() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let group = fixture.group
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            let currentCopy = newTabs.first { $0.folderID == copy.folderID }!
            let copiedGroup = store.state.splitLayouts.first { $0.id != group.id && Set($0.tabIDs).isSubset(of: Set(copy.tabIDs)) }!
            #expect(copiedGroup.orientation == group.orientation && copiedGroup.widthFactors == group.widthFactors, "Copied split preserves orientation and widths")
            #expect(copiedGroup.sidebarAnchorID == copiedGroup.tabIDs[group.tabIDs.firstIndex(of: group.sidebarAnchorID!)!], "Split anchor maps to the corresponding new child")
            #expect(copy.openTabIDs == copiedGroup.tabIDs && !copy.openTabIDs.contains(currentCopy.id), "Only copied split descendants request background page creation")
        }
    }

    @Test @MainActor static func aCopiedTreeKeepsItsMixedOrderAndSitsBesideTheOriginal() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let space = fixture.space
            let root = fixture.root
            let parent = fixture.parent
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            let copiedNested = store.state.folders.first { $0.parentID == copy.folderID }!
            let newTabs = copy.tabIDs.compactMap { id in store.state.tabs.first { $0.id == id } }
            let currentCopy = newTabs.first { $0.folderID == copy.folderID }!
            let copiedInside = SidebarContainerLocation(spaceID: space, folderID: copy.folderID, section: .pinned)
            #expect(SidebarHierarchy.children(in: copiedInside, state: store.state) == [.folder(copiedNested.id), .tab(currentCopy.id)], "Mixed folder/tab sibling order survives recursion")
            let siblingRows = SidebarHierarchy.children(in: root, state: store.state)
            #expect(siblingRows.firstIndex(of: .folder(copy.folderID)) == siblingRows.firstIndex(of: .folder(parent))!.advanced(by: 1), "Parc inserts the new root adjacent to its original")
        }
    }

    @Test @MainActor static func aCopiedTreeAndItsOrderSurviveRestart() throws {
        try withCopyFixture { fixture in
            let store = fixture.store
            let copy = try #require(try store.duplicateFolder(fixture.target, destinations: fixture.urls))
            _ = copy
            let loaded = try BrowserStore(directory: fixture.directory).state
            #expect(loaded.tabs == store.state.tabs && loaded.folders == store.state.folders
                && loaded.sidebarItemOrder == store.state.sidebarItemOrder
                && Dictionary(uniqueKeysWithValues: loaded.splitLayouts.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: store.state.splitLayouts.map { ($0.id, $0) }), "Entire tree and order survive durable model reload; active-group cache ordering is independent")
        }
    }

    @MainActor
    private static func withFolderToDuplicate(
        _ body: (BrowserStore, FolderDuplicateTarget, [UUID: String]) throws -> Void
    ) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { date })
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let parent = store.createFolder(name: "Research")
            let nested = store.createFolder(name: "Articles", parentID: parent)
            let first = store.open("https://example.org/saved", kind: .pinned)
            let splitA = store.open("https://example.org/a")
            let splitB = store.open("https://example.org/b")
            store.moveTab(first, toSpace: space, folderID: parent)
            try BrowserStoreTestsSupport.savedSplit(store, [splitA, splitB], in: .init(spaceID: space, folderID: nested, section: .pinned))
            store.selectTab(splitA)
            _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.3, 0.7])
            let inside = SidebarContainerLocation(spaceID: space, folderID: parent, section: .pinned)
            let snap = SidebarHierarchySnapshot(state: store.state, spaceID: space, profileID: profile)!
            _ = try store.moveSidebarItem(.folder(nested), to: inside, before: .tab(first), expected: snap)
            store.toggleFolder(nested)
            store.updateTab(first, title: "Live title", url: "https://example.org/current")
            let original = store.state
            let target = FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: profile, state: original)!
            let urls = Dictionary(uniqueKeysWithValues: target.tabs.map { ($0.id, $0.id == first ? "https://example.org/live-at-command" : $0.savedURL) })
            try body(store, target, urls)
        }
    }

    @Test @MainActor static func aFolderCopyCannotReuseAStaleCapability() throws {
        try withFolderToDuplicate { store, target, urls in
            let copy = try store.duplicateFolder(target, destinations: urls)
            _ = try #require(copy)
            let stable = store.state
            #expect(try store.duplicateFolder(target, destinations: urls) == nil, "An old folder capability cannot duplicate after hierarchy changes")
            #expect(store.state == stable, "Stale command has no partial effects")
        }
    }

    enum CopyDestinationDamage: CaseIterable { case missing, extra, typedDocument }

    @Test(arguments: CopyDestinationDamage.allCases)
    @MainActor static func aFolderCopyRefusesInvalidDestinations(_ damage: CopyDestinationDamage) throws {
        try withFolderToDuplicate { store, target, urls in
            var destinations = urls
            switch damage {
            case .missing: destinations.removeAll()
            case .extra: destinations[UUID()] = "https://foreign.example"
            case .typedDocument:
                let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" })
                destinations[first.id] = InternalPage.easel(UUID()).urlString
            }
            let stable = store.state
            #expect(try store.duplicateFolder(target, destinations: destinations) == nil)
            #expect(store.state == stable)
        }
    }

    @Test @MainActor static func aFolderCopyCannotDuplicateAPageAwaitingRetirement() throws {
        try withFolderToDuplicate { store, target, urls in
            let stable = store.state
            let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" }).id
            var retirementReply: ((Bool) -> Void)?
            store.requestPageRetirement = { _, _, completion in retirementReply = completion }
            store.closeTabs([first]) { _ in }
            #expect(try store.retiringTabIDs.contains(first) && (try store.duplicateFolder(target, destinations: urls)) == nil, "A source waiting for genuine retirement consent cannot be duplicated")
            retirementReply?(false)
            #expect(store.state == stable && store.retiringTabIDs.isEmpty, "Refused retirement preserves originals and releases the duplicate guard")
        }
    }

    @Test @MainActor static func aFolderCopyRequiresTheFoldersOwnProfile() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let parent = store.createFolder(name: "Research")
            let space = store.activeSpaceID
            #expect(FolderDuplicateTarget(folderID: parent, spaceID: space, profileID: UUID(), state: store.state) == nil, "Foreign Profile cannot acquire folder command")
        }
    }

    enum CopyHierarchyDamage: CaseIterable { case cycle, splitCrossingContainers }

    @Test(arguments: CopyHierarchyDamage.allCases)
    @MainActor static func aMalformedHierarchyCannotProduceAFolderCopyTarget(_ damage: CopyHierarchyDamage) throws {
        try withFolderToDuplicate { store, target, _ in
            var corrupt = store.state
            let parent = target.folderID
            switch damage {
            case .cycle:
                let index = try #require(corrupt.folders.firstIndex { $0.id == parent })
                let descendant = try #require(corrupt.folders.first { $0.parentID == parent })
                corrupt.folders[index].parentID = descendant.id
            case .splitCrossingContainers:
                let first = try #require(target.tabs.first { $0.savedURL == "https://example.org/saved" })
                corrupt.splitLayouts[0].tabIDs.append(first.id)
            }
            #expect(FolderDuplicateTarget(folderID: parent, spaceID: store.activeSpaceID,
                profileID: store.activeSpace.profileID, state: corrupt) == nil)
        }
    }

    @Test @MainActor static func aFailedFolderCopySaveLeavesTheOriginalStateAndDoesNotPublish() throws {
        try withFolderToDuplicate { store, target, urls in
            let stable = store.state
            var publications = 0
            let observation = store.statePublisher.dropFirst().sink { _ in publications += 1 }
            let file = store.directory.appendingPathComponent("session.json"), backup = store.directory.appendingPathComponent("backup.json")
            try FileManager.default.moveItem(at: file, to: backup)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            var failed = false
            do { _ = try store.duplicateFolder(target, destinations: urls) } catch { failed = true }
            #expect(failed && store.state == stable && publications == 0, "Disk refusal leaves all original/new IDs and publication untouched")
            try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: backup, to: file)
            observation.cancel()
        }
    }

    @Test @MainActor static func copyingAnEmptyFolderDoesNotCreateAPlaceholderPage() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let space = store.activeSpaceID, profile = store.activeSpace.profileID
            let empty = store.createFolder(name: "Empty")
            let emptyTarget = FolderDuplicateTarget(folderID: empty, spaceID: space, profileID: profile, state: store.state)!
            let emptyCopy = try store.duplicateFolder(emptyTarget, destinations: [:])!
            #expect(emptyCopy.tabIDs.isEmpty && emptyCopy.openTabIDs.isEmpty, "Empty folder copy is real without creating a placeholder page")
        }
    }
}
