import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SidebarWindowMoveTests {
    @MainActor final class Fixture {
        let directory: URL
        let profile = BrowserProfile(id: UUID(), name: "Original")
        let otherProfile = BrowserProfile(id: UUID(), name: "Other")
        let source: BrowserSpace, target: BrowserSpace, foreign: BrowserSpace
        let folder: BrowserFolder, child: BrowserFolder, empty: BrowserFolder, destinationFolder: BrowserFolder
        let noteFile: URL
        let easels: EaselStore
        let easel: EaselSession
        let n: BrowserTab, e: BrowserTab, web: BrowserTab, keep: BrowserTab
        let split: BrowserSplitLayout
        let top: SidebarContainerLocation
        let location: SidebarContainerLocation
        let file: URL
        let store: BrowserStore
        let initial: BrowserState
        let move: SidebarWindowMove

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-window-move-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            source = BrowserSpace(id: UUID(), name: "Source", symbol: "circle", color: "AABBCC", profileID: profile.id)
            target = BrowserSpace(id: UUID(), name: "Target", symbol: "circle", color: "AABBCC", profileID: profile.id)
            foreign = BrowserSpace(id: UUID(), name: "Foreign", symbol: "circle", color: "AABBCC", profileID: otherProfile.id)
            folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Folder", isExpanded: false)
            child = BrowserFolder(id: UUID(), spaceID: source.id, name: "Child", parentID: folder.id, isExpanded: true)
            empty = BrowserFolder(id: UUID(), spaceID: source.id, name: "Empty")
            destinationFolder = BrowserFolder(id: UUID(), spaceID: target.id, name: "Destination")
            let profile = self.profile, source = self.source
            func tab(_ title: String, parent: UUID? = nil, url: String? = nil) -> BrowserTab {
                let url = url ?? "https://original.invalid/" + title
                return BrowserTab(id: UUID(), spaceID: source.id, profileID: profile.id, url: url, title: title,
                    kind: .pinned, folderID: parent, createdAt: Date(timeIntervalSince1970: 1), lastAccessed: Date(timeIntervalSince1970: 1),
                    savedURL: url, savedTitle: title)
            }
            noteFile = directory.appendingPathComponent("Original.md")
            try Data("Original\n".utf8).write(to: noteFile)
            easels = try EaselStore(directory: directory.appendingPathComponent("Easels"))
            easel = try easels.create(title: "Original")
            n = tab("Note", parent: child.id, url: InternalPage.note(noteFile).urlString)
            var e = tab("Easel", url: InternalPage.easel(easel.document.id).urlString)
            e.kind = .today
            self.e = e
            web = tab("Web", parent: folder.id)
            keep = tab("Keep")
            split = BrowserSplitLayout(sidebarAnchorID: n.id, customTitle: "Original split", spaceID: source.id,
                tabIDs: [n.id, e.id], orientation: .vertical, widthFactors: [0.3, 0.7])
            var state = BrowserState(profiles: [profile, otherProfile], spaces: [source, target, foreign], activeSpaceID: source.id)
            state.tabs = [n, e, web, keep]
            state.folders = [folder, child, empty, destinationFolder]
            state.splitLayouts = [split]
            state.selectedTabIDs = split.tabIDs
            state.selectionBySpace[source.id.uuidString] = split.tabIDs
            top = SidebarContainerLocation(spaceID: source.id, folderID: nil, section: .pinned)
            state.sidebarItemOrder[top.key] = [.folder(folder.id), .tab(keep.id), .folder(empty.id)]
            let nested = SidebarContainerLocation(spaceID: source.id, folderID: folder.id, section: .pinned)
            state.sidebarItemOrder[nested.key] = [.tab(web.id), .folder(child.id)]
            location = SidebarContainerLocation(spaceID: target.id, folderID: destinationFolder.id, section: .pinned)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            file = directory.appendingPathComponent("session.json")
            try encoder.encode(state).write(to: file)
            store = try BrowserStore(directory: directory)
            initial = store.state
            move = SidebarWindowMove(items: [.folder(folder.id), .folder(child.id), .split(split.id), .folder(empty.id)],
                sourceSpaceID: source.id, profileID: profile.id, to: location, before: nil, state: initial)!
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func rootMove() -> SidebarWindowMove {
            SidebarWindowMove(items: [.split(split.id)], sourceSpaceID: source.id, profileID: profile.id,
                to: location, before: nil, state: initial)!
        }

        func collection(in state: BrowserState) -> SidebarMoveCollection? {
            SidebarMoveCollection(items: [.split(split.id)], spaceID: source.id, profileID: profile.id, state: state)
        }

        func proposal(_ items: [SidebarItemReference], to destination: SidebarContainerLocation) -> SidebarWindowMove? {
            SidebarWindowMove(items: items, sourceSpaceID: source.id, profileID: profile.id, to: destination, before: nil, state: initial)
        }

        func commit() throws {
            #expect(try store.commitSidebarWindowMove(move))
        }
    }

    @Test func aWholeOrdinaryMixedPlacementSplitIsAdmittedThroughItsOriginalFolder() throws {
        let fixture = try Fixture()
        let proposal = SidebarWindowMove(items: [.folder(fixture.folder.id), .folder(fixture.child.id), .split(fixture.split.id), .folder(fixture.empty.id)],
            sourceSpaceID: fixture.source.id, profileID: fixture.profile.id, to: fixture.location, before: nil, state: fixture.initial)
        #expect(proposal != nil)
    }

    @Test func ancestorDeduplicationPreservesOrderedRoots() throws {
        let fixture = try Fixture()
        #expect(fixture.move.roots == [.folder(fixture.folder.id), .folder(fixture.empty.id)])
    }

    @Test func originalHierarchicalOrderIncludesTheCompleteSplitOnce() throws {
        let fixture = try Fixture()
        #expect(fixture.move.tabIDs == [fixture.web.id, fixture.n.id, fixture.e.id])
    }

    @Test func aPartialSplitRefuses() throws {
        let fixture = try Fixture()
        #expect(fixture.proposal([.tab(fixture.n.id)], to: fixture.location) == nil)
    }

    @Test func aCrossProfileDestinationRefuses() throws {
        let fixture = try Fixture()
        let wrong = SidebarContainerLocation(spaceID: fixture.foreign.id, folderID: nil, section: .pinned)
        #expect(fixture.proposal([.folder(fixture.folder.id)], to: wrong) == nil)
    }

    @Test func aDescendantCycleIsRefused() throws {
        let fixture = try Fixture()
        let cycle = SidebarContainerLocation(spaceID: fixture.source.id, folderID: fixture.child.id, section: .pinned)
        #expect(fixture.proposal([.folder(fixture.folder.id)], to: cycle) == nil)
    }

    @Test func aRestoredMixedChildEntersItsSplitAnchorsFolder() throws {
        let fixture = try Fixture()
        let migrated = try #require(fixture.initial.tabs.first { $0.id == fixture.e.id })
        #expect(migrated.kind == .pinned)
        #expect(migrated.folderID == fixture.child.id)
        #expect(migrated.url == fixture.e.url)
    }

    @Test func aRootReceiptRetainsEveryOriginalChildInPaneOrder() throws {
        let fixture = try Fixture()
        let migrated = try #require(fixture.initial.tabs.first { $0.id == fixture.e.id })
        let rootMove = fixture.rootMove()
        #expect(rootMove.tabIDs == fixture.split.tabIDs)
        #expect(rootMove.collection.tabs == [fixture.n, migrated])
    }

    @Test func anExplicitDestinationNormalizesEveryRootChildWithoutForeignFolderReferences() throws {
        let fixture = try Fixture()
        let rootAfter = try #require(fixture.rootMove().applying(to: fixture.initial))
        #expect(fixture.split.tabIDs.allSatisfy { id in
            rootAfter.tabs.contains { $0.id == id && $0.spaceID == fixture.target.id && $0.kind == .pinned && $0.folderID == fixture.destinationFolder.id }
        })
        #expect(rootAfter.folders == fixture.initial.folders)
    }

    @Test func aSecondWindowInTheSameSpaceUsesTheActualExplicitContainer() throws {
        let fixture = try Fixture()
        let sameSpace = try #require(SidebarWindowMove(items: [.split(fixture.split.id)], sourceSpaceID: fixture.source.id,
            profileID: fixture.profile.id, to: fixture.top, before: .folder(fixture.folder.id), state: fixture.initial))
        let sameAfter = try #require(sameSpace.applying(to: fixture.initial))
        #expect(fixture.split.tabIDs.allSatisfy { id in
            sameAfter.tabs.contains { $0.id == id && $0.spaceID == fixture.source.id && $0.kind == .pinned && $0.folderID == nil }
        })
        #expect(sameAfter.splitLayouts == fixture.initial.splitLayouts)
    }

    @Test func anOrdinaryAndFavoriteMixedGroupRemainsExcluded() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.tabs[1].kind = .favorite
        #expect(fixture.collection(in: invalid) == nil)
    }

    @Test func aForeignProfileChildCannotEnterTheCollection() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.tabs[1].profileID = fixture.otherProfile.id
        #expect(fixture.collection(in: invalid) == nil)
    }

    @Test func anAlreadyRelocatedChildInvalidatesWholeGroupAdmission() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.tabs[1].spaceID = fixture.target.id
        #expect(fixture.collection(in: invalid) == nil)
    }

    @Test func anArchivedChildCannotBeOmittedFromAWholeGroupTransfer() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.tabs[1].archivedAt = Date()
        #expect(fixture.collection(in: invalid) == nil)
    }

    @Test func originalPaneOrderIsPartOfTheImmutableReceipt() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.splitLayouts[0].tabIDs.reverse()
        #expect(fixture.rootMove().applying(to: invalid) == nil)
    }

    @Test func changingANonAnchorOriginalPlacementExpiresTheReceipt() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.tabs[1].folderID = fixture.folder.id
        #expect(fixture.rootMove().applying(to: invalid) == nil)
    }

    @Test func originalDividerGeometryIsBoundByTheReceipt() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.splitLayouts[0].widthFactors = [0.5, 0.5]
        #expect(fixture.rootMove().applying(to: invalid) == nil)
    }

    @Test func duplicateChildIdentitiesRemainInvalid() throws {
        let fixture = try Fixture()
        var invalid = fixture.initial
        invalid.splitLayouts[0].tabIDs = [fixture.n.id, fixture.n.id]
        #expect(fixture.collection(in: invalid) == nil)
    }

    @Test func theDestinationSnapshotExpires() throws {
        let fixture = try Fixture()
        var changed = fixture.initial
        changed.folders[3].name = "Changed"
        #expect(fixture.move.applying(to: changed) == nil)
    }

    @Test func exactOriginalRecordsAreCaptured() throws {
        let fixture = try Fixture()
        var changed = fixture.initial
        changed.tabs[0].url = "https://changed.invalid"
        #expect(fixture.move.applying(to: changed) == nil)
    }

    @Test func aFailedRealSavePublishesNothing() throws {
        let fixture = try Fixture()
        try FileManager.default.removeItem(at: fixture.file)
        try FileManager.default.createDirectory(at: fixture.file, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try fixture.store.commitSidebarWindowMove(fixture.move) }
        #expect(fixture.store.state == fixture.initial)
    }

    @Test func aCommittedMoveClonesNoTabAndReplaysNoURL() throws {
        let fixture = try Fixture()
        try fixture.commit()
        let after = fixture.store.state
        #expect(Set(after.tabs.map(\.id)) == Set(fixture.initial.tabs.map(\.id)))
        #expect(after.tabs.count == fixture.initial.tabs.count)
        #expect(after.tabs.first { $0.id == fixture.n.id }?.url == fixture.n.url)
        #expect(after.tabs.first { $0.id == fixture.e.id }?.url == fixture.e.url)
    }

    @Test func originalLocalDocumentsSurviveTheMove() throws {
        let fixture = try Fixture()
        try fixture.commit()
        #expect(FileManager.default.fileExists(atPath: fixture.noteFile.path))
        #expect(try fixture.easels.load(fixture.easel.document.id) === fixture.easel)
    }

    @Test func nestedSplitDescendantsAdoptTheMovedOriginalAnchorContainer() throws {
        let fixture = try Fixture()
        try fixture.commit()
        #expect(fixture.store.state.tabs.filter { fixture.split.tabIDs.contains($0.id) }
            .allSatisfy { $0.folderID == fixture.child.id && $0.kind == .pinned && $0.spaceID == fixture.target.id })
    }

    @Test func foldersKeepTheirExactParentsAndEmptyFoldersParticipate() throws {
        let fixture = try Fixture()
        try fixture.commit()
        let after = fixture.store.state
        #expect(after.folders.first { $0.id == fixture.folder.id }?.parentID == fixture.destinationFolder.id)
        #expect(after.folders.first { $0.id == fixture.child.id }?.parentID == fixture.folder.id)
        #expect(after.folders.first { $0.id == fixture.empty.id }?.spaceID == fixture.target.id)
    }

    @Test func theWholeSplitKeepsItsIdentityOrderAndGeometry() throws {
        let fixture = try Fixture()
        try fixture.commit()
        var expectedSplit = fixture.split
        expectedSplit.spaceID = fixture.target.id
        #expect(fixture.store.state.splitLayouts == [expectedSplit])
    }

    @Test func theOriginalRootOrderIsKeptAtTheTargetAndUnrelatedTabsAreUnchanged() throws {
        let fixture = try Fixture()
        try fixture.commit()
        let after = fixture.store.state
        #expect(SidebarHierarchy.children(in: fixture.location, state: after) == [.folder(fixture.folder.id), .folder(fixture.empty.id)])
        #expect(after.tabs.first { $0.id == fixture.keep.id } == fixture.keep)
    }

    @Test func oneCoherentDurableSnapshotIsStoredAndReloads() throws {
        let fixture = try Fixture()
        try fixture.commit()
        let after = fixture.store.state
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(BrowserState.self, from: Data(contentsOf: fixture.file)) == after)
        let reloaded = try BrowserStore(directory: fixture.directory).state
        #expect(reloaded.folders == after.folders)
        #expect(reloaded.splitLayouts == after.splitLayouts)
        #expect(reloaded.tabs == after.tabs)
    }

    @Test func aStaleMoveCannotReplay() throws {
        let fixture = try Fixture()
        try fixture.commit()
        #expect(try !fixture.store.commitSidebarWindowMove(fixture.move))
    }

    @Test func aSameSpacePhysicalTransferHasAValidModelProposal() throws {
        let fixture = try Fixture()
        try fixture.commit()
        let after = fixture.store.state
        let same = try #require(SidebarWindowMove(items: [.tab(fixture.keep.id)], sourceSpaceID: fixture.source.id,
            profileID: fixture.profile.id, to: fixture.top, before: nil, state: after))
        #expect(same.applying(to: after) != nil)
    }

    @MainActor final class Ownership {
        let ownership = NativePageOwnership()
        let a = UUID(), b = UUID(), c = UUID()
        let n = UUID(), e = UUID(), web = UUID()

        init() {
            _ = ownership.claim(n, owner: a, page: "n")
            _ = ownership.claim(e, owner: a)
        }
    }

    @Test func originalClaimsAreMadeAndForeignOrDuplicateReservationsRefuse() {
        let owner = Ownership()
        #expect(owner.ownership.reserveCollection([owner.n, owner.n], from: owner.a, to: owner.b) == nil)
        #expect(owner.ownership.reserveCollection([owner.n], from: owner.c, to: owner.b) == nil)
    }

    @Test func aReservationCapturesAllOriginalClaimsAndBlocksInterleaving() throws {
        let owner = Ownership()
        let reservation = try #require(owner.ownership.reserveCollection([owner.n, owner.e, owner.web], from: owner.a, to: owner.b))
        #expect(owner.ownership.isCurrent(reservation))
        #expect(!owner.ownership.claim(owner.web, owner: owner.c))
        #expect(owner.ownership.reserveTransfer(owner.n, page: "n", from: owner.a, to: owner.c) == nil)
        #expect(owner.ownership.reserveCollection([owner.web], from: owner.a, to: owner.c) == nil)
    }

    @Test func rollbackReleasesAllReservationsAndRetainsOriginalClaims() throws {
        let owner = Ownership()
        let reservation = try #require(owner.ownership.reserveCollection([owner.n, owner.e, owner.web], from: owner.a, to: owner.b))
        #expect(owner.ownership.finishCollection(reservation, moved: false))
        #expect(owner.ownership.claimSnapshot(owner.n).owner == owner.a)
        #expect(owner.ownership.claimSnapshot(owner.web).owner == nil)
    }

    @Test func aCollectionPublishesAtomicallyRetainsPagesAndCompletesOnce() throws {
        let owner = Ownership()
        let moved = try #require(owner.ownership.reserveCollection([owner.n, owner.e, owner.web], from: owner.a, to: owner.b))
        #expect(owner.ownership.finishCollection(moved, moved: true))
        #expect([owner.n, owner.e, owner.web].allSatisfy { owner.ownership.claimSnapshot($0).owner == owner.b })
        #expect(owner.ownership.claimSnapshot(owner.n).pages == ["n"])
        #expect(!owner.ownership.finishCollection(moved, moved: true))
    }

    @Test func aRealCloseNeedsExplicitAccountingAndDoesNotStrandOtherOriginals() throws {
        let owner = Ownership()
        let moved = try #require(owner.ownership.reserveCollection([owner.n, owner.e], from: owner.a, to: owner.b))
        #expect(owner.ownership.finishCollection(moved, moved: true))
        let closing = try #require(owner.ownership.reserveCollection([owner.n, owner.e], from: owner.b, to: owner.a))
        owner.ownership.release(owner.n, owner: owner.b)
        #expect(!owner.ownership.isCurrent(closing))
        #expect(owner.ownership.isCurrent(closing, closed: [owner.n]))
        #expect(owner.ownership.finishCollection(closing, moved: true, closed: [owner.n]))
        #expect(owner.ownership.claimSnapshot(owner.n).owner == nil)
        #expect(owner.ownership.claimSnapshot(owner.e).owner == owner.a)
    }

    @Test func anEmptyFolderOwnsARealOneShotWindowTransaction() throws {
        let owner = Ownership()
        let emptyTransfer = try #require(owner.ownership.reserveCollection([], from: owner.a, to: owner.b))
        #expect(owner.ownership.isCurrent(emptyTransfer))
        #expect(owner.ownership.finishCollection(emptyTransfer, moved: true))
        #expect(!owner.ownership.finishCollection(emptyTransfer, moved: true))
    }
}
