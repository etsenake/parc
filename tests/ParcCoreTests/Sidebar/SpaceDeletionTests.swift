import Foundation
import Testing
@testable import ParcCore

@MainActor
struct SpaceDeletionTests {
    @MainActor final class Fixture {
        let directory: URL
        let initial: BrowserState
        let source: BrowserSpace
        let profile: UUID
        let otherProfile: BrowserProfile
        let other: BrowserSpace
        let folder: BrowserFolder
        let saved: BrowserTab, today: BrowserTab, favorite1: BrowserTab, favorite2: BrowserTab, note: BrowserTab
        let page: InternalPage
        let favorites: BrowserSplitLayout
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store: BrowserStore
        var documentAvailable = true
        var requests: [(Set<UUID>, () -> Bool, (Bool) -> Void)] = []
        var record: SpaceDeletionUndo?
        var completed: Bool?
        var failure: Error?
        var references: [UUID: SidebarDocumentReference] = [:]

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var initial = BrowserState.initial()
            let source = initial.spaces[0], profile = source.profileID
            let otherProfile = BrowserProfile(id: UUID(), name: "Other")
            var other = BrowserSpace(id: UUID(), name: "Other", symbol: "circle.fill", color: "AACCEE", profileID: otherProfile.id)
            other.updateDisplayName(position: 1)
            initial.profiles.append(otherProfile)
            initial.spaces.append(other)
            let folder = BrowserFolder(id: UUID(), spaceID: source.id, name: "Saved")
            initial.folders.append(folder)
            let now = self.now
            func tab(_ kind: TabKind, _ folderID: UUID? = nil, _ url: String = "https://example.test") -> BrowserTab {
                BrowserTab(id: UUID(), spaceID: source.id, profileID: profile, url: url, title: url,
                    kind: kind, folderID: folderID, createdAt: now, lastAccessed: now, savedURL: url, savedTitle: url)
            }
            let saved = tab(.pinned, folder.id), today = tab(.today), favorite1 = tab(.favorite), favorite2 = tab(.favorite)
            let page = InternalPage.easel(UUID())
            let note = tab(.pinned, folder.id, page.urlString)
            initial.tabs = [saved, today, favorite1, favorite2, note]
            let favorites = BrowserSplitLayout(sidebarAnchorID: favorite1.id, spaceID: source.id,
                tabIDs: [favorite1.id, favorite2.id], widthFactors: [0.4, 0.6])
            initial.splitLayouts = [favorites]
            initial.selectedTabIDs = [today.id]
            initial.selectionBySpace[source.id.uuidString] = [today.id]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(initial).write(to: directory.appendingPathComponent("session.json"))
            self.initial = initial
            self.source = source; self.profile = profile
            self.otherProfile = otherProfile; self.other = other
            self.folder = folder
            self.saved = saved; self.today = today; self.favorite1 = favorite1; self.favorite2 = favorite2; self.note = note
            self.page = page
            self.favorites = favorites
            store = try BrowserStore(directory: directory)
            references = [note.id: SidebarDocumentReference(page: page, profileID: profile, validate: { [unowned self] in
                if !self.documentAvailable { throw CocoaError(.fileNoSuchFile) }
            })]
            store.requestPageRetirement = { [unowned self] in requests.append(($0, $1, $2)) }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func remove(_ target: SpaceDeletionTarget, documents: [UUID: SidebarDocumentReference]? = nil) {
            completed = nil
            failure = nil
            store.deleteSpace(target, documents: documents ?? references, shouldCommit: { true }, didCommit: { [unowned self] in record = $0 }) { [unowned self] in
                switch $0 { case .success(let value): completed = value; case .failure(let error): failure = error }
            }
        }

        func target() -> SpaceDeletionTarget { SpaceDeletionTarget(spaceID: source.id, state: store.state)! }

        func deleteSource() -> SpaceDeletionUndo {
            remove(target())
            _ = requests[0].1()
            requests.removeFirst().2(true)
            return record!
        }
    }

    func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func scratchDirectory(writing state: BrowserState) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder().encode(state).write(to: directory.appendingPathComponent("session.json"))
        return directory
    }

    @Test func deletionRequiresATypedDocumentCapabilityBeforeClosing() throws {
        let fixture = try Fixture()
        fixture.remove(fixture.target(), documents: [:])
        #expect(fixture.completed == false)
        #expect(fixture.requests.isEmpty)
    }

    @Test func onlyOriginalNonFavoriteContentsRetireAndNothingMutatesBeforeConsent() throws {
        let fixture = try Fixture()
        fixture.remove(fixture.target())
        #expect(fixture.requests.count == 1)
        #expect(fixture.requests[0].0 == [fixture.saved.id, fixture.today.id, fixture.note.id])
        #expect(fixture.completed == nil)
        #expect(fixture.store.state.spaces.count == 2)
    }

    @Test func refusalPreservesTheWholeSpace() throws {
        let fixture = try Fixture()
        fixture.remove(fixture.target())
        fixture.requests.removeFirst().2(false)
        #expect(fixture.completed == false)
        #expect(fixture.store.state.spaces.count == 2)
    }

    @Test func oneDurableDeletionCommitsAfterConsent() throws {
        let fixture = try Fixture()
        fixture.remove(fixture.target())
        #expect(fixture.requests[0].1())
        fixture.requests.removeFirst().2(true)
        #expect(fixture.completed == true)
        #expect(fixture.failure == nil)
        #expect(fixture.record != nil)
    }

    @Test func onlyTheOriginalSpaceAndItsFoldersAreRemoved() throws {
        let fixture = try Fixture()
        _ = fixture.deleteSource()
        #expect(fixture.store.state.spaces.map(\.id) == [fixture.other.id])
        #expect(fixture.store.state.folders.isEmpty)
    }

    @Test func theArchiveRetainsOriginalProvenance() throws {
        let fixture = try Fixture()
        let target = fixture.target()
        _ = fixture.deleteSource()
        let archived = fixture.store.state.tabs.filter { target.tabIDs.contains($0.id) }
        #expect(!archived.isEmpty)
        #expect(archived.allSatisfy { $0.archivedAt != nil && $0.archiveProvenance?.spaceID == fixture.source.id })
    }

    @Test func profileFavoritesAreRetained() throws {
        let fixture = try Fixture()
        _ = fixture.deleteSource()
        let favorites = fixture.store.state.tabs.filter { $0.kind == .favorite }
        #expect(favorites.count == 2)
        #expect(favorites.allSatisfy { $0.archivedAt == nil && $0.profileID == fixture.profile })
    }

    @Test func theFavoriteSplitStaysIntactAndSurvivesPersistence() throws {
        let fixture = try Fixture()
        _ = fixture.deleteSource()
        #expect(fixture.store.state.splitLayouts.first?.id == fixture.favorites.id)
        #expect(fixture.store.state.splitLayouts.first?.widthFactors == [0.4, 0.6])
        let reload = try BrowserStore(directory: fixture.directory)
        #expect(reload.state.splitLayouts.first?.id == fixture.favorites.id)
    }

    @Test func theLastSpaceCannotBeDeleted() throws {
        let fixture = try Fixture()
        _ = fixture.deleteSource()
        #expect(SpaceDeletionTarget(spaceID: fixture.other.id, state: fixture.store.state) == nil)
    }

    @Test func aForeignProfileFavoriteAnchorDoesNotPreventSubsequentDeletion() throws {
        let fixture = try Fixture()
        _ = fixture.deleteSource()
        var parked = fixture.store.state
        let third = BrowserSpace(id: UUID(), name: "Third", symbol: "circle", color: "AABBCC", profileID: fixture.otherProfile.id)
        parked.spaces.append(third)
        let parkedTarget = SpaceDeletionTarget(spaceID: fixture.other.id, state: parked)
        #expect(parkedTarget != nil)
        let parkedDeletion = parkedTarget.flatMap { SpaceDeletionUndo.make(target: $0, state: parked, now: fixture.now, documents: [:]) }
        #expect(parkedDeletion?.1.splitLayouts.first?.spaceID == third.id)
    }

    @Test func aMissingDocumentDisablesUndoWithoutConsumingHistory() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        fixture.documentAvailable = false
        #expect(try !fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
        fixture.documentAvailable = true
        #expect(try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
    }

    @Test func undoRestoresTheOriginalSpacePositionAndFolders() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        fixture.store.updateTab(fixture.favorite1.id, title: "Live favorite title")
        #expect(try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true }))
        #expect(fixture.store.state.spaces.map(\.id) == [fixture.source.id, fixture.other.id])
        #expect(fixture.store.state.folders == [fixture.folder])
    }

    @Test func undoDoesNotRewindLiveFavorites() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        fixture.store.updateTab(fixture.favorite1.id, title: "Live favorite title")
        _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
        #expect(fixture.store.state.tabs.first { $0.id == fixture.favorite1.id }?.title == "Live favorite title")
    }

    @Test func aTypedAliasRetainsItsDocumentIdentityAfterUndo() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
        #expect(fixture.store.state.tabs.first { $0.id == fixture.note.id }?.savedURL == fixture.page.urlString)
    }

    @Test func undoRestoresTheOriginalFavoriteStorageAnchor() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
        #expect(fixture.store.state.splitLayouts.first?.spaceID == fixture.source.id)
    }

    @Test func redoBindsOriginalMembershipUntilANewChildAppears() throws {
        let fixture = try Fixture()
        let undo = fixture.deleteSource()
        _ = try fixture.store.undoSpaceDeletion(undo, shouldCommit: { true })
        #expect(undo.redoTarget(in: fixture.store.state) != nil)
        fixture.store.selectSpace(fixture.source.id)
        _ = fixture.store.openResolvedURL(URL(string: "https://new.test")!)
        #expect(undo.redoTarget(in: fixture.store.state) == nil)
    }

    @Test func reorderingSpacesSavesTheOriginalOrderAndRefusesAStaleOne() throws {
        let fixture = try Fixture()
        let originalOrder = fixture.store.state.spaces.map(\.id)
        #expect(try fixture.store.reorderSpace(fixture.other.id, before: fixture.source.id, expectedOrder: originalOrder))
        #expect(try !fixture.store.reorderSpace(fixture.source.id, before: fixture.other.id, expectedOrder: originalOrder))
    }

    @Test func aDiskFailurePublishesNoPartialDeletionOrNewProfile() throws {
        let fixture = try Fixture()
        let beforeFailure = fixture.store.state
        fixture.remove(fixture.target())
        #expect(fixture.requests[0].1())
        try FileManager.default.removeItem(at: fixture.directory)
        try Data().write(to: fixture.directory)
        fixture.requests.removeFirst().2(true)
        #expect(fixture.failure != nil)
        #expect(fixture.store.state == beforeFailure)
        #expect(throws: (any Error).self) { try fixture.store.createProfilePersisted(name: "Not saved") }
        #expect(fixture.store.state == beforeFailure)
    }

    @Test func folderRenamesSaveImmediatelyAndRefuseStaleNames() throws {
        let initial = try Fixture().initial
        let directory = try scratchDirectory(writing: initial)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let expected = initial.folders[0], profile = initial.spaces[0].profileID
        #expect(try store.renameFolder(expected, profileID: profile, name: "Renamed"))
        #expect(try BrowserStore(directory: directory).state.folders[0].name == "Renamed")
        #expect(try !store.renameFolder(expected, profileID: profile, name: "Stale"))
    }

    @Test func folderRenamesRefuseMovedReparentedAndReassignedTargets() throws {
        let initial = try Fixture().initial
        let directory = try scratchDirectory(writing: initial)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let profile = initial.spaces[0].profileID
        let current = store.state.folders[0]
        var moved = current
        moved.spaceID = initial.spaces[1].id
        #expect(try !store.renameFolder(moved, profileID: initial.spaces[1].profileID, name: "Stale"))
        var reparented = current
        reparented.parentID = UUID()
        #expect(try !store.renameFolder(reparented, profileID: profile, name: "Stale"))
        #expect(try !store.renameFolder(current, profileID: initial.profiles.last!.id, name: "Stale"))
    }

    @Test func folderRenamesPreserveIndependentDisclosure() throws {
        let initial = try Fixture().initial
        let directory = try scratchDirectory(writing: initial)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let profile = initial.spaces[0].profileID
        let current = store.state.folders[0]
        store.toggleFolder(current.id)
        #expect(try store.renameFolder(current, profileID: profile, name: "Disclosure kept"))
        #expect(store.state.folders[0].isExpanded != current.isExpanded)
    }

    @Test func aFolderRenameWriteFailurePreservesPublishedState() throws {
        let initial = try Fixture().initial
        let directory = try scratchDirectory(writing: initial)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try BrowserStore(directory: directory)
        let before = store.state
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        #expect(throws: (any Error).self) {
            try store.renameFolder(before.folders[0], profileID: initial.spaces[0].profileID, name: "Not saved")
        }
        #expect(store.state == before)
        try FileManager.default.removeItem(at: directory)
    }

    @MainActor struct Conversion {
        let state: BrowserState
        let store: BrowserStore
        let directory: URL
        let source: BrowserSpace
        let destinationID: UUID
        let conversion: SpaceFolderConversion
        let today: BrowserTab

        init(fixture: Fixture) throws {
            var state = fixture.initial
            source = state.spaces[0]
            destinationID = state.spaces[1].id
            state.spaces[1].profileID = source.profileID
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: directory)
            conversion = SpaceFolderConversion(source: source.id, destination: destinationID, state: store.state,
                                               documents: fixture.references)!
            today = state.tabs.filter { $0.kind != .favorite }.first { $0.kind == .today }!
            self.state = state
        }
    }

    @Test func aSameProfileConversionRetainsPhysicalPageOwners() throws {
        let fixture = try Fixture()
        let conversion = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: conversion.directory) }
        var retirement = false
        conversion.store.requestPageRetirement = { _, _, _ in retirement = true }
        _ = try conversion.store.convertSpaceToFolder(conversion.conversion)
        #expect(!retirement)
    }

    @Test func conversionRemovesOnlyTheOriginalSpaceAndBuildsTheFolderTree() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        _ = try c.store.convertSpaceToFolder(c.conversion)
        #expect(c.store.state.spaces.count == 1)
        #expect(c.store.state.spaces[0].id == c.destinationID)
        #expect(c.store.state.folders.contains { $0.id == c.conversion.folderID && $0.name == c.source.name && $0.parentID == nil })
        #expect(c.store.state.folders.contains { $0.id == c.conversion.todayFolderID && $0.name == "Today" && $0.parentID == c.conversion.folderID })
    }

    @Test func conversionKeepsOriginalTabsLivePinnedAndPlacedAndLeavesFavoritesOut() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        _ = try c.store.convertSpaceToFolder(c.conversion)
        let converted = c.store.state.tabs.filter { c.conversion.tabIDs.contains($0.id) }
        #expect(converted.allSatisfy { $0.spaceID == c.destinationID && $0.kind == .pinned && $0.archivedAt == nil })
        #expect(c.store.state.tabs.first { $0.id == c.today.id }?.folderID == c.conversion.todayFolderID)
        #expect(c.store.state.tabs.filter { $0.kind == .favorite }.map(\.id) == c.state.tabs.filter { $0.kind == .favorite }.map(\.id))
    }

    @Test func aConversionSurvivesSessionNormalization() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        _ = try c.store.convertSpaceToFolder(c.conversion)
        let loaded = try BrowserStore(directory: c.directory)
        #expect(loaded.state.folders == c.store.state.folders)
        #expect(loaded.state.tabs == c.store.state.tabs)
    }

    @Test func undoingAConversionRestoresPositionAndTreeWithoutRewindingNavigation() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        let undo = try #require(try c.store.convertSpaceToFolder(c.conversion))
        c.store.updateTab(c.today.id, title: "New live title")
        #expect(try c.store.undoSpaceFolderConversion(undo))
        #expect(c.store.state.folders == c.state.folders)
        #expect(c.store.state.spaces.map(\.id) == c.state.spaces.map(\.id))
        #expect(c.store.state.tabs.first { $0.id == c.today.id }?.title == "New live title")
        #expect(c.store.state.tabs.first { $0.id == c.today.id }?.kind == .today)
    }

    @Test func aNewDescendantInvalidatesDestructiveUndoOfARedoneConversion() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        let undo = try #require(try c.store.convertSpaceToFolder(c.conversion))
        _ = try c.store.undoSpaceFolderConversion(undo)
        let redo = try #require(undo.redo(in: c.store.state))
        let redone = try #require(try c.store.convertSpaceToFolder(redo))
        let root = try #require(c.store.state.folders.first { $0.id == c.conversion.folderID })
        _ = try c.store.createFolder(name: "Added later", in: c.store.state.spaces[0], parent: root)
        #expect(redone.restoring(in: c.store.state) == nil)
    }

    @Test func aChangedDestinationProfileRefusesConversion() throws {
        let fixture = try Fixture()
        let c = try Conversion(fixture: fixture)
        defer { try? FileManager.default.removeItem(at: c.directory) }
        var stale = c.state
        stale.spaces[1].profileID = UUID()
        #expect(c.conversion.applying(to: stale) == nil)
    }

    @Test func aCrossProfileProposalChangesOriginalRecordsTogetherAndCannotBeUndone() throws {
        let fixture = try Fixture()
        let initial = fixture.initial
        let cross = try #require(SpaceFolderConversion(source: initial.spaces[0].id, destination: initial.spaces[1].id,
                                                       state: initial, documents: fixture.references))
        #expect(cross.crossesProfiles)
        let applied = try #require(cross.applying(to: initial))
        #expect(applied.0.tabs.filter { cross.tabIDs.contains($0.id) }.allSatisfy { $0.profileID == initial.spaces[1].profileID })
        #expect(applied.1.restoring(in: applied.0) == nil)
    }

    @MainActor final class AssignmentHarness {
        let store: BrowserStore
        let directory: URL
        let initial: BrowserState
        let source: BrowserSpace
        let destination: UUID
        var requests: [(() -> Bool, (Bool) -> Void)] = []
        var result: Result<Bool, Error>?
        var moves = 0
        var rollbacks = 0
        var ownerValid = true

        init(initial: BrowserState) throws {
            self.initial = initial
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-delete-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(initial).write(to: directory.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: directory)
            source = initial.spaces[0]
            destination = initial.spaces[1].profileID
            store.requestPageRetirement = { [unowned self] _, valid, done in requests.append((valid, done)) }
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func installRelocationOwner() {
            store.relocateLocalDocuments = { [unowned self] ids, pages, from, to in
                moves += 1
                #expect(!ids.isEmpty && pages.count == 1 && from == source.profileID && to == destination)
                #expect(store.state.spaces.first { $0.id == source.id }?.profileID == source.profileID)
                return { self.rollbacks += 1 }
            }
        }

        func commit() {
            assign()
            _ = requests[0].0()
            requests.removeFirst().1(true)
        }

        func assign() {
            result = nil
            store.assignProfile(destination, toSpace: source.id, shouldCommit: { [unowned self] in ownerValid }) { [unowned self] in result = $0 }
        }
    }

    @Test func assignmentRefusesTypedStorageWithoutARelocationOwner() throws {
        let harness = try AssignmentHarness(initial: Fixture().initial)
        harness.store.assignProfile(harness.destination, toSpace: harness.source.id, completion: { harness.result = $0 })
        #expect(try harness.result?.get() == false)
        #expect(harness.requests.isEmpty)
    }

    @Test func assignmentWaitsForNativeRetirementAndRefusalRetainsAllData() throws {
        let harness = try AssignmentHarness(initial: Fixture().initial)
        harness.installRelocationOwner()
        harness.assign()
        #expect(harness.result == nil)
        #expect(harness.moves == 0)
        #expect(harness.requests.count == 1)
        harness.ownerValid = false
        #expect(!harness.requests[0].0())
        harness.requests.removeFirst().1(false)
        #expect(try harness.result?.get() == false)
        #expect(harness.moves == 0)
        #expect(harness.store.state == harness.initial)
    }

    @Test func assignmentCommitsAfterTheNativeAndDocumentOwnersAct() throws {
        let harness = try AssignmentHarness(initial: Fixture().initial)
        harness.installRelocationOwner()
        harness.assign()
        #expect(harness.requests[0].0())
        harness.requests.removeFirst().1(true)
        #expect(try harness.result?.get() == true)
        #expect(harness.moves == 1)
        #expect(harness.rollbacks == 0)
    }

    @Test func assignmentMovesOrdinaryAliasesAndLeavesFavoritesInTheOriginalProfile() throws {
        let harness = try AssignmentHarness(initial: Fixture().initial)
        harness.installRelocationOwner()
        harness.commit()
        #expect(harness.store.state.tabs.filter { $0.kind != .favorite }.allSatisfy { $0.profileID == harness.destination })
        #expect(harness.store.state.tabs.filter { $0.kind == .favorite }.allSatisfy { $0.profileID == harness.source.profileID })
    }

    @Test func anUnusedProfileFavoriteSplitPersistsAfterAssignment() throws {
        let harness = try AssignmentHarness(initial: Fixture().initial)
        harness.installRelocationOwner()
        harness.commit()
        let reload = try BrowserStore(directory: harness.directory)
        #expect(reload.state.splitLayouts.map(\.id) == harness.initial.splitLayouts.map(\.id))
    }
}
