import Foundation
import Testing
@testable import ParcCore

@MainActor
enum SpaceDeletionTestsSupport {
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

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
