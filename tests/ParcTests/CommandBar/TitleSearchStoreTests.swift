import Foundation
import Testing
@testable import ParcCore

struct TitleSearchStoreTests {
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    @MainActor private final class Fixture {
        let directory: URL
        let store: BrowserStore
        let space: UUID
        let profile: UUID
        let open: UUID
        let single: UUID
        let members: [UUID]

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("parc-title-search-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let now = TitleSearchStoreTests.now
            let profile = BrowserProfile(id: UUID(), name: "Original")
            let here = BrowserSpace(id: UUID(), name: "Here", symbol: "circle", color: "ABCDEF", profileID: profile.id)
            let other = BrowserSpace(id: UUID(), name: "There", symbol: "circle", color: "123456", profileID: profile.id)
            let archivedAt = now.addingTimeInterval(-3 * 86_400)
            func tab(_ title: String) -> BrowserTab {
                let url = "https://\(title.lowercased()).example/"
                var tab = BrowserTab(id: UUID(), spaceID: other.id, profileID: profile.id, url: url, title: title, kind: .today,
                                     folderID: nil, createdAt: now.addingTimeInterval(-86_400 * 9), lastAccessed: archivedAt,
                                     archivedAt: archivedAt, savedURL: url, savedTitle: title)
                tab.archiveProvenance = ArchiveProvenance(reason: .automatic, spaceID: other.id, spaceName: other.name)
                return tab
            }
            let single = tab("Single")
            var left = tab("Left"), right = tab("Right")
            let layout = BrowserSplitLayout(spaceID: other.id, tabIDs: [left.id, right.id], widthFactors: [0.5, 0.5])
            let group = UUID()
            for member in [0, 1] {
                var changed = member == 0 ? left : right
                changed.archiveProvenance?.groupID = group
                changed.archiveProvenance?.split = layout
                if member == 0 { left = changed } else { right = changed }
            }
            let open = BrowserTab(id: UUID(), spaceID: here.id, profileID: profile.id, url: "https://open.example/", title: "Open",
                                  kind: .today, folderID: nil, createdAt: now, lastAccessed: now, savedURL: "https://open.example/",
                                  savedTitle: "Open")
            var state = BrowserState(profiles: [profile], spaces: [here, other], activeSpaceID: here.id)
            state.tabs = [open, single, left, right]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: directory.appendingPathComponent("session.json"))
            store = try BrowserStore(directory: directory, now: { now })
            space = here.id
            self.profile = profile.id
            self.open = open.id
            self.single = single.id
            members = [left.id, right.id]
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        func putBack(_ id: UUID) -> [UUID] {
            store.restoreArchivedTab(id, destination: .putBack(currentSpaceID: space, requestedSpaceID: nil))
        }
    }

    @Test @MainActor func puttingBackAnArchivedRowRestoresItsTabToTheCurrentSpaceSelected() throws {
        let fixture = try Fixture()
        #expect(fixture.putBack(fixture.single) == [fixture.single])
        let restored = fixture.store.state.tab(fixture.single)
        #expect(restored?.archivedAt == nil)
        #expect(restored?.spaceID == fixture.space)
        #expect(fixture.store.state.selectedTabIDs == [fixture.single])
    }

    @Test @MainActor func puttingBackASplitMemberRestoresTheWholeSplit() throws {
        let fixture = try Fixture()
        #expect(fixture.putBack(fixture.members[1]) == fixture.members)
        #expect(fixture.store.state.splitLayouts.contains { $0.tabIDs == fixture.members && $0.spaceID == fixture.space })
    }

    @Test @MainActor func newVisitsRemoveNothingFromTheBar() throws {
        let fixture = try Fixture()
        let start = fixture.store.historyRemovalRevision
        fixture.store.updateTab(fixture.open, title: "A", url: "https://a.example/")
        fixture.store.updateTab(fixture.open, title: "B", url: "https://b.example/")
        #expect(fixture.store.removedHistoryURLs(profileID: fixture.profile, after: start) == [])
    }

    @Test @MainActor func deletingEveryVisitToAPageNamesThePageForThatProfileOnly() throws {
        let fixture = try Fixture()
        let start = fixture.store.historyRemovalRevision
        fixture.store.updateTab(fixture.open, title: "A", url: "https://a.example/")
        fixture.store.updateTab(fixture.open, title: "B", url: "https://b.example/")
        let visits = Set(fixture.store.state.history.filter { $0.url == "https://a.example/" }.map(\.id))
        fixture.store.deleteHistory(visits, profileID: fixture.profile)
        #expect(fixture.store.removedHistoryURLs(profileID: fixture.profile, after: start) == ["https://a.example/"])
        #expect(fixture.store.removedHistoryURLs(profileID: UUID(), after: start) == [])
    }

    @Test @MainActor func removingOneOfSeveralVisitsKeepsThePage() throws {
        let fixture = try Fixture()
        fixture.store.updateTab(fixture.open, title: "B", url: "https://b.example/")
        fixture.store.updateTab(fixture.open, title: "A", url: "https://a.example/")
        fixture.store.updateTab(fixture.open, title: "B again", url: "https://b.example/")
        let start = fixture.store.historyRemovalRevision
        let one = Set(fixture.store.state.history.filter { $0.url == "https://b.example/" }.prefix(1).map(\.id))
        fixture.store.deleteHistory(one, profileID: fixture.profile)
        #expect(fixture.store.removedHistoryURLs(profileID: fixture.profile, after: start) == [])
    }

    @Test @MainActor func clearingHistoryHidesEveryPastPageUntilANewIndexIsBuilt() throws {
        let fixture = try Fixture()
        fixture.store.updateTab(fixture.open, title: "A", url: "https://a.example/")
        let start = fixture.store.historyRemovalRevision
        fixture.store.clearHistory(profileID: fixture.profile)
        #expect(fixture.store.removedHistoryURLs(profileID: fixture.profile, after: start) == nil)
        #expect(fixture.store.removedHistoryURLs(profileID: fixture.profile, after: fixture.store.historyRemovalRevision) == [])
    }
}
