import Foundation
import Testing
@testable import ParcCore

extension SpaceDeletionTestsSupport {
    @MainActor
    struct SpaceDeletionProfileAssignmentTests {
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
}
