import Foundation
import Testing
@testable import ParcCore

extension SidebarSpaceMoveTestsSupport {
    struct SidebarSpaceMovePersistenceTests {
        @MainActor @Test func theAtomicStoreMoveCommitsAndPersists() throws {
            let fixture = Fixture()
            let directory = try fixture.directory(writing: fixture.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            #expect(try store.moveSidebarItemsAcrossSpaces(fixture.move))
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.state.tabs.first { $0.id == fixture.a.id }?.spaceID == fixture.destination.id)
            #expect(reopened.state.splitLayouts.contains(fixture.expectedGroup))
        }

        @MainActor @Test func theActualRevealPersistsDisclosureWithoutSelectingAMovedPage() throws {
            let fixture = Fixture()
            let directory = try fixture.directory(writing: fixture.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            _ = try store.moveSidebarItemsAcrossSpaces(fixture.move)
            let reopened = try BrowserStore(directory: directory)
            let reveal = try #require(SidebarItemReveal(item: .split(fixture.group.id), spaceID: fixture.destination.id,
                                                        profileID: fixture.source.profileID, state: fixture.moved))
            let selectionBeforeReveal = reopened.state.selectedTabIDs
            #expect(try reopened.revealSidebarItem(reveal))
            #expect(reopened.state.folders.first { $0.id == fixture.folder.id }?.isExpanded == true)
            #expect(reopened.state.selectedTabIDs == selectionBeforeReveal)
        }

        @MainActor @Test func aFailedWriteCannotPublishAPartialHierarchy() throws {
            let fixture = Fixture()
            let directory = try fixture.directory(writing: fixture.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("session.json")
            let failing = try BrowserStore(directory: directory)
            let prior = failing.state
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try failing.moveSidebarItemsAcrossSpaces(fixture.move) }
            #expect(failing.state == prior)
        }

        @Test func aNewSpaceDraftSuppliesAllOriginalChildrenToTheSameWindowOwnerGates() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            var draft = try #require(SidebarNewSpaceDraft(items: [.folder(fixture.folder.id)], from: nestedFrom, state: mixed.state))
            draft.name = "Original group"
            #expect(Set(draft.tabIDs) == Set(mixed.move.tabIDs))
            #expect(draft.groupIDs == mixed.move.groupIDs)
        }

        @Test func aNewSpaceConsumesTheCompleteNestedGroupMoveAndKeepsSplitIdentityAndInsertion() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            var draft = try #require(SidebarNewSpaceDraft(items: [.folder(fixture.folder.id)], from: nestedFrom, state: mixed.state))
            draft.name = "Original group"
            let result = try #require(draft.applying(to: mixed.state))
            #expect(result.tabs[0].spaceID == draft.spaceID)
            #expect(result.tabs[0].folderID == fixture.nested.id)
            #expect(result.splitLayouts[0].id == fixture.group.id)
            #expect(result.splitLayouts[0].spaceID == draft.spaceID)
            #expect(result.spaces.firstIndex { $0.id == draft.spaceID } == result.spaces.firstIndex { $0.id == fixture.source.id }! + 1)
        }

        @Test func aRefusedDraftCannotPersistAnEmptySpace() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let nestedFrom = SidebarHierarchySnapshot(state: mixed.state, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            var cancelled = try #require(SidebarNewSpaceDraft(items: [.folder(fixture.folder.id)], from: nestedFrom, state: mixed.state))
            cancelled.name = ""
            #expect(cancelled.applying(to: mixed.state) == nil)
            #expect(mixed.state.spaces.count == fixture.state.spaces.count)
        }

        @MainActor @Test func theActualStoreAcceptsTheCompleteMixedGroupTransactionAndReloadsNormalizedPlacement() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let directory = try fixture.directory(writing: mixed.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let actualMove = try #require(fixture.proposed(store.state, [.folder(fixture.folder.id)]))
            #expect(try store.moveSidebarItemsAcrossSpaces(actualMove))
            let persisted = try BrowserStore(directory: directory)
            #expect(persisted.state.tabs[0].folderID == fixture.nested.id)
            #expect(persisted.state.tabs[0].spaceID == fixture.destination.id)
            #expect(persisted.state.tabs[0].savedURL == mixed.state.tabs[0].savedURL)
        }

        @MainActor @Test func theActualNewSpaceCommandCommitsTheMixedGroupWithoutRecreatingIt() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let directory = try fixture.directory(writing: mixed.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try BrowserStore(directory: directory)
            let storeFrom = SidebarHierarchySnapshot(state: store.state, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            var storeDraft = try #require(SidebarNewSpaceDraft(items: [.split(fixture.group.id)], from: storeFrom, state: store.state))
            storeDraft.name = "One transaction"
            let created = try store.createSpaceAndMoveSidebarItems(storeDraft)
            #expect(created == storeDraft.spaceID)
            let persisted = try BrowserStore(directory: directory)
            #expect(persisted.state.tabs[0].spaceID == created)
            #expect(persisted.state.tabs[0].folderID == nil)
            #expect(persisted.state.splitLayouts[0].id == fixture.group.id)
        }

        @MainActor @Test func aFailedNewSpaceSavePublishesNothing() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let directory = try fixture.directory(writing: mixed.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("session.json")
            let failed = try BrowserStore(directory: directory)
            let before = failed.state
            let failureSource = SidebarHierarchySnapshot(state: before, spaceID: fixture.source.id, profileID: fixture.source.profileID)!
            var failureDraft = try #require(SidebarNewSpaceDraft(items: [.folder(fixture.folder.id)], from: failureSource, state: before))
            failureDraft.name = "Failure"
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try failed.createSpaceAndMoveSidebarItems(failureDraft) }
            #expect(failed.state == before)
        }

        @MainActor @Test func aFailedMoveSavePublishesNothing() throws {
            let fixture = Fixture()
            let mixed = fixture.nestedMixed()
            let directory = try fixture.directory(writing: mixed.state)
            defer { try? FileManager.default.removeItem(at: directory) }
            let file = directory.appendingPathComponent("session.json")
            let failed = try BrowserStore(directory: directory)
            let before = failed.state
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            let actualMove = try #require(fixture.proposed(before, [.folder(fixture.folder.id)]))
            #expect(throws: (any Error).self) { try failed.moveSidebarItemsAcrossSpaces(actualMove) }
            #expect(failed.state == before)
        }
    }
}
