import Combine
import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreNativePutBackTests {
    enum Destination: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case all = "All Spaces uses the current Space"
        case filtered = "A surviving filter uses its Space"
        case missing = "A deleted filter falls back to the current Space"
        case reassigned = "A filter in another profile falls back to the current Space"
        case originalMoved = "A reassigned original Space falls back to the current Space"
        case foreignProfile = "Another profile cannot restore the group"
        case noCompatibleSpace = "Missing destinations cannot restore the group"
        case recent = "Recently Closed returns to the original Space"

        var testDescription: String { rawValue }
    }

    @Test(arguments: Destination.allCases)
    @MainActor static func archivePutBackResolvesTheRequestedDestination(scenario: Destination) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
            let originalSpace = store.activeSpaceID, profile = store.activeSpace.profileID
            let a = store.open("https://archive-a.example"), b = store.open("https://archive-b.example")
            store.setSplit([a, b]); _ = store.setSplitLayout(orientation: .vertical, widthFactors: [0.35, 0.65])
            let originalSplit = store.activeSplitLayout!
            store.closeTabs([a, b])
            let currentSpace = store.createSpace(name: "Current window")
            let filteredSpace = store.createSpace(name: "Selected filter")
            let otherProfile = store.createProfile(name: "Other profile")
            store.selectSpace(currentSpace)
            if scenario == .reassigned { store.assignProfile(otherProfile, toSpace: filteredSpace) }
            if scenario == .originalMoved { store.assignProfile(otherProfile, toSpace: originalSpace) }
            let destination: ArchiveRestoreDestination
            let expected: UUID?
            let requestedProfile: UUID
            switch scenario {
            case .filtered:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                expected = filteredSpace; requestedProfile = profile
            case .missing:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: UUID())
                expected = currentSpace; requestedProfile = profile
            case .reassigned:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: filteredSpace)
                expected = currentSpace; requestedProfile = profile
            case .foreignProfile:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                expected = nil; requestedProfile = otherProfile
            case .noCompatibleSpace:
                destination = .putBack(currentSpaceID: UUID(), requestedSpaceID: UUID())
                expected = nil; requestedProfile = profile
            case .recent:
                destination = .previousSpace(fallbackSpaceID: currentSpace)
                expected = originalSpace; requestedProfile = profile
            case .all, .originalMoved:
                destination = .putBack(currentSpaceID: currentSpace, requestedSpaceID: nil)
                expected = currentSpace; requestedProfile = profile
            }
            let before = store.state
            var publications: [BrowserState] = []
            let observation = store.statePublisher.dropFirst().sink { publications.append($0) }
            let restored = store.restoreArchivedTab(a, profileID: requestedProfile, destination: destination)
            if let expected {
                #expect(restored == originalSplit.tabIDs && store.activeSpaceID == expected, "Put Back \(scenario) selects the original group in its resolved destination")
                #expect(!publications.isEmpty && publications.allSatisfy { snapshot in
                    snapshot.tabs.filter { [a, b].contains($0.id) }.allSatisfy { $0.archivedAt == nil && $0.spaceID == expected }
                }, "Put Back publishes the complete original group without partially restored siblings")
                let tabs = store.state.tabs.filter { [a, b].contains($0.id) }
                #expect(tabs.count == 2 && tabs.allSatisfy { $0.spaceID == expected && $0.profileID == profile && $0.archivedAt == nil && $0.archiveProvenance == nil }, "Put Back retains original identities/profile and clears only archive metadata")
                var expectedSplit = originalSplit; expectedSplit.spaceID = expected
                let restoredLayout = store.activeSplitLayout
                var restoredShape = restoredLayout; restoredShape?.widthFactors = expectedSplit.widthFactors
                #expect(restoredShape == expectedSplit && zip(restoredLayout?.widthFactors ?? [], expectedSplit.widthFactors).allSatisfy { abs($0 - $1) < 1e-12 }, "Put Back preserves original split order, orientation, ratios and identity")
                #expect(!store.state.recentlyClosedIDs.contains(a) && !store.state.recentlyClosedIDs.contains(b), "Restored group leaves the recent-closed stack")
                try store.save()
                let loaded = try BrowserStore(directory: directory, now: { Date(timeIntervalSince1970: 1_900_000_000) })
                #expect(loaded.state.tabs == store.state.tabs && loaded.state.splitLayouts == store.state.splitLayouts, "Put Back destination persists with the original group")
            } else {
                #expect(restored.isEmpty && store.state == before && publications.isEmpty, "Invalid Put Back \(scenario) preserves every archived record and selection")
            }
            _ = observation
        }
    }
}
