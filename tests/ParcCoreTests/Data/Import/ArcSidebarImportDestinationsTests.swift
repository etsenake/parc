import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

struct ArcSidebarImportDestinationsTests {
    private typealias Support = ArcSidebarImportTestsSupport

    @Test func onlyArcsChromeSchemePagesBecomeParcPages() throws {
        let links = try SidebarImport(arcData: Support.document(items: [
            "N", ["id": "N", "data": ["tab": ["savedURL": "parc://note/0B3E", "savedTitle": "Note"]]],
            "C", ["id": "C", "data": ["tab": ["savedURL": "chrome://settings/", "savedTitle": "Settings"]]],
            "X", ["id": "X", "childrenIds": ["Y"], "data": ["splitView": [:]]],
            "Y", ["id": "Y", "childrenIds": ["Y1", "Y2"], "data": ["list": [:]]],
            "Y1", ["id": "Y1", "data": ["tab": ["savedURL": "https://example.test/y1"]]],
            "Y2", ["id": "Y2", "data": ["tab": ["savedURL": "https://example.test/y2"]]],
        ], pinned: ["N", "C", "X"]))
        #expect(links.spaces[0].pinned.map { if case .tab(let tab) = $0 { return tab.url } else { return "" } }
                == ["parc://settings/"])
        #expect(links.skippedItemCount == 4)
    }

    @MainActor
    @Test func aSplitPageAlreadyInFavoritesIsNotAddedTwice() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let arc = try SidebarImport(arcData: JSONSerialization.data(withJSONObject: ["sidebar": ["containers": [[
                "items": ["F", ["id": "F", "childrenIds": ["A", "S"], "data": ["itemContainer": [:]]],
                          "A", ["id": "A", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                          "S", ["id": "S", "childrenIds": ["A2", "B"], "data": ["splitView": [:]]],
                          "A2", ["id": "A2", "data": ["tab": ["savedURL": "https://a.example.test/"]]],
                          "B", ["id": "B", "data": ["tab": ["savedURL": "https://b.example.test/"]]]],
                "spaces": [], "topAppsContainerIDs": [["default": true], "F"]]]]]))
            _ = try store.importSidebar(arc, profiles: [(.standard, "Personal")],
                                           standardProfileID: store.state.profiles[0].id)
            #expect(store.state.tabs.filter { $0.kind == .favorite }.map(\.savedURL)
                    == ["https://a.example.test/", "https://b.example.test/"] && store.state.splitLayouts.isEmpty)
        }
    }

    @MainActor
    @Test func anUnknownStandardProfileIsRefused() throws {
        try Support.withImport { imported, _ in
            #expect(throws: (any Error).self) {
                try imported.store.importSidebar(imported.arc, profiles: Support.allProfiles, standardProfileID: UUID())
            }
        }
    }

    @Test func arcsPerProfileArchiveAgeWinsOverItsArcWideOne() {
        let preferences: [String: Any] = [
            "autoArchiveTimeThreshold": "\"sevenDays\"",
            "autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[{"default":{}},"oneHour",{"custom":{"_0":{"directoryBasename":"Profile 1","machineID":"M"}}},{"never":{}}]}"#]
        let hours = SidebarImport.autoArchiveHours(preferences: preferences, profiles: [.standard, Support.profileOne, Support.profileTwo])
        #expect(hours == [.standard: 1, Support.profileOne: 0, Support.profileTwo: 168])
    }

    @Test func withoutArcsArchiveSettingEachProfileKeepsParcs() {
        #expect(SidebarImport.autoArchiveHours(preferences: ["autoArchiveTimeThresholdsPerProfile": #"{"thresholds":[]}"#],
                                                  profiles: [.standard]).isEmpty)
    }

    @MainActor
    @Test func arcsArchiveAgeAppliesToTheProfileTheDefaultAndEducation() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let store = try BrowserStore(directory: directory)
            var timed = try Support.loadArc()
            timed.autoArchiveHours = [.standard: 168]
            _ = try store.importSidebar(timed, profiles: [(.standard, "Personal")],
                                           standardProfileID: store.state.profiles[0].id)
            #expect(store.state.profiles[0].autoArchiveHours == 168 && store.state.autoArchiveDefaultHours == 168
                    && !store.state.autoArchiveEducationEligible)
        }
    }

    @MainActor
    @Test func anImportFromBeforeTheRecordMatchesSpacesByNameAndPinnedPages() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try Support.loadArc()
            let store = try BrowserStore(directory: directory)
            let profile = store.state.profiles[0].id
            _ = try store.importSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: profile)
            var legacy = store.state
            legacy.arcImportedSpaces = [:]
            let result = try arc.inserting(into: legacy, profiles: [(.standard, "Personal")], standardProfileID: profile,
                                           at: Support.importedAt)
            let pinnedSpaces = arc.spaces.filter { $0.profile == .standard && !$0.pinned.isEmpty }.count
            #expect(result.state.spaces.count == legacy.spaces.count + 4 - pinnedSpaces
                    && result.state.arcImportedSpaces.count == 4)
        }
    }

    @MainActor
    @Test func aChosenTargetProfileTakesTheArcProfilesSpaces() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try Support.loadArc()
            let store = try BrowserStore(directory: directory)
            let original = BrowserImportDestination(spaceID: store.activeSpace.id, profileID: store.activeSpace.profileID)
            let chosenID = store.createProfile(name: "Elsewhere")
            try store.save()
            let profilesBeforeChoice = store.state.profiles.count
            let result = try store.importSidebar(arc, profiles: [(Support.profileOne, "Work Profile")],
                standardProfileID: original.profileID, primary: Support.profileOne, into: chosenID)
            let workSpaces = arc.spaces.filter { $0.profile == Support.profileOne }.count
            #expect(result[Support.profileOne]?.profileID == chosenID && store.state.profiles.count == profilesBeforeChoice
                    && store.state.spaces.filter { $0.profileID == chosenID }.count == workSpaces)
        }
    }

    @MainActor
    @Test func aTargetProfileThatDoesNotExistIsRefusedAndWritesNothing() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try Support.loadArc()
            let store = try BrowserStore(directory: directory)
            let profileID = store.activeSpace.profileID
            let before = store.state
            #expect(throws: (any Error).self) {
                try store.importSidebar(arc, profiles: [(.standard, "Personal")], standardProfileID: profileID,
                                           primary: .standard, into: UUID())
            }
            #expect(store.state == before)
        }
    }

    @MainActor
    @Test func aTargetProfileBeingRemovedIsRefused() throws {
        try DataFixtures.withTemporaryDirectory { directory in
            let arc = try Support.loadArc()
            let store = try BrowserStore(directory: directory)
            let profileID = store.activeSpace.profileID
            let chosenID = store.createProfile(name: "Elsewhere")
            var retiring = store.state
            retiring.profileRemovals.append(.init(id: UUID(), profileID: chosenID, profileName: "Elsewhere"))
            #expect(throws: (any Error).self) {
                try arc.inserting(into: retiring, profiles: [(.standard, "Personal")], standardProfileID: profileID,
                                  target: (.standard, chosenID), at: Support.importedAt)
            }
        }
    }
}
