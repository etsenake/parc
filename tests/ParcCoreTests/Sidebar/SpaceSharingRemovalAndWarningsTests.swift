import Foundation
import Testing
@testable import ParcCore

extension SpaceSharingTestsSupport {
    @MainActor
    struct SpaceSharingRemovalAndWarningsTests {
        struct Deletion {
            let folder: Folder
            let store: BrowserStore
            let b: BrowserSpace, c: BrowserSpace
            let q: BrowserProfile
            let defaultProfile: BrowserProfile

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                q = BrowserProfile(id: UUID(), name: "Q")
                defaultProfile = state.profiles[0]
                b = BrowserSpace(id: UUID(), name: "B", symbol: "circle", color: "B9B5D4", profileID: state.profiles[0].id)
                c = BrowserSpace(id: UUID(), name: "C", symbol: "circle", color: "B9B5D4", profileID: q.id)
                state.profiles.append(q)
                state.spaces += [b, c]
                try folder.write(state)
                store = try folder.store()
            }

            @MainActor func delete(_ id: UUID) -> SpaceDeletionUndo? {
                var undo: SpaceDeletionUndo?
                store.deleteSpace(SpaceDeletionTarget(spaceID: id, state: store.state)!, documents: [:],
                                  shouldCommit: { true }, didCommit: { undo = $0 }) { _ in }
                return undo
            }
        }

        struct Warnings {
            let store: BrowserStore
            let a: BrowserSpace, b: BrowserSpace, c: BrowserSpace
            let folder: Folder

            @MainActor init() throws {
                folder = try Folder()
                var state = BrowserState.initial()
                let p = state.profiles[0], q = BrowserProfile(id: UUID(), name: "Q")
                state.spaces[0].name = "Alpha"
                a = state.spaces[0]
                b = BrowserSpace(id: UUID(), name: "Beta", symbol: "circle", color: "B9B5D4", profileID: p.id)
                c = BrowserSpace(id: UUID(), name: "Gamma", symbol: "circle", color: "B9B5D4", profileID: q.id)
                state.profiles.append(q)
                state.spaces += [b, c]
                try folder.write(state)
                store = try folder.store()
            }
        }

        @Test func deletingASharingSpaceReportsNothing() throws {
            let deletion = try Deletion()
            #expect(!deletion.store.wouldOrphanProfile(ifDeletingSpace: deletion.b.id))
        }

        @Test func deletingTheLastSpaceReportsItsProfile() throws {
            let deletion = try Deletion()
            #expect(deletion.store.unusedProfile(ifDeletingSpace: deletion.c.id) == UnusedProfile(id: deletion.q.id, name: "Q"))
        }

        @Test func aSharedDeletionLeavesTheProfileInUseAndKeepsItsUndo() throws {
            let deletion = try Deletion()
            let shared = deletion.delete(deletion.b.id)
            #expect(shared != nil)
            #expect(deletion.store.unusedProfile(deletion.defaultProfile.id) == nil)
            #expect(shared.flatMap { $0.restoring(in: deletion.store.state) } != nil)
        }

        @Test func theProfileIsUnusedAfterTheLastSpaceDeletesAndItsRemovalStages() throws {
            let deletion = try Deletion()
            #expect(deletion.delete(deletion.c.id) != nil)
            let unused = try #require(deletion.store.unusedProfile(deletion.q.id))
            #expect(unused == UnusedProfile(id: deletion.q.id, name: "Q"))
            #expect(try deletion.store.stageRemoval(of: unused).profileID == deletion.q.id)
            #expect(deletion.store.isProfileRemovalPending(deletion.q.id))
        }

        @Test func aLegacyRemovalKeepsTheDefaultItWasJournaledWith() throws {
            let folder = try Folder()
            var state = BrowserState.initial()
            let p = state.profiles[0]
            state.settings.defaultProfileID = p.id
            let r = BrowserProfile(id: UUID(), name: "R")
            state.profiles.append(r)
            state.profileRemovals = [ProfileRemovalRecord(id: UUID(), profileID: r.id, profileName: "R", fallbackProfileID: nil)]
            try folder.write(state)
            let store = try folder.store()
            #expect(store.state.profileRemovals.first?.fallbackProfileID == p.id)
            #expect(try folder.store().state.profileRemovals.first?.fallbackProfileID == p.id)
        }

        @Test func joiningOtherDataWhileTheOldDataStaysInUseOnlyWarnsAboutTheReload() throws {
            let warnings = try Warnings()
            let reload = warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: warnings.c.id))
            #expect(reload == .share(target: "Gamma", space: "Alpha", discardsOwnData: false))
            #expect(reload?.title == "Share Gamma’s data with Alpha?")
            #expect(reload?.confirm == "Share Data")
            #expect(reload?.destructive == false)
            #expect(reload?.message == "Alpha’s pages will reload with Gamma’s logins, history, extensions and Favorites.")
        }

        @Test func joiningOtherDataWhileTheOldDataBecomesUnusedAsksForADestructiveConfirmation() throws {
            let warnings = try Warnings()
            let discard = warnings.store.sharingWarning(forSpace: warnings.c.id, to: .share(withSpace: warnings.a.id))
            #expect(discard == .share(target: "Alpha", space: "Gamma", discardsOwnData: true))
            #expect(discard?.title == "Share Alpha’s data with Gamma?")
            #expect(discard?.confirm == "Share Data")
            #expect(discard?.destructive == true)
            #expect(discard?.message == "Gamma’s pages will reload signed in as Alpha. Gamma’s own logins, saved passwords and history will be deleted. This can’t be undone.")
        }

        @Test func choosingTheDataASpaceAlreadyHasAsksNothing() throws {
            let warnings = try Warnings()
            #expect(warnings.store.sharingWarning(forSpace: warnings.b.id, to: .share(withSpace: warnings.a.id)) == nil)
        }

        @Test func anUnknownOrOwnSpaceAsksNothing() throws {
            let warnings = try Warnings()
            #expect(warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: warnings.a.id)) == nil)
            #expect(warnings.store.sharingWarning(forSpace: warnings.a.id, to: .share(withSpace: UUID())) == nil)
        }

        @Test func separatingASharingSpaceWarnsThatItStartsFresh() throws {
            let warnings = try Warnings()
            let keep = warnings.store.sharingWarning(forSpace: warnings.a.id, to: .separate)
            #expect(keep == .keepSeparate(space: "Alpha"))
            #expect(keep?.title == "Keep Alpha separate?")
            #expect(keep?.confirm == "Keep Separate")
            #expect(keep?.destructive == false)
            #expect(keep?.message == "It starts fresh: signed out of every site, with no history, extensions or Favorites.")
        }

        @Test func keepingAnAlreadySeparateSpaceAsksNothing() throws {
            let warnings = try Warnings()
            #expect(warnings.store.sharingWarning(forSpace: warnings.c.id, to: .separate) == nil)
        }

        @Test func theDeletionNoteNamesWhatIsLost() {
            #expect(SpaceSharingWarning.deletionNote == "This also deletes its logins, saved passwords and history. This can’t be undone.")
        }

        @Test func anOldSettingsFileWithTheRetiredAppWideKeyStillLoads() throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(BrowserState.initial())) as? [String: Any])
            var settings = object["settings"] as? [String: Any] ?? [:]
            settings["appWidePreferences"] = ["searchKeyword": "g", "promptForDownload": true, "version": 1]
            object["settings"] = settings
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect((try? decoder.decode(BrowserState.self, from: data)) != nil)
        }
    }
}
