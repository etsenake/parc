import Foundation
import Testing
@testable import ParcCore

@MainActor
enum SpaceSharingTestsSupport {
    @MainActor final class Folder {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("parc-space-sharing-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ state: BrowserState) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(state).write(to: url.appendingPathComponent("session.json"))
        }

        func store(now: (() -> Date)? = nil) throws -> BrowserStore {
            if let now { return try BrowserStore(directory: url, now: now) }
            return try BrowserStore(directory: url)
        }
    }

    static func tab(_ space: BrowserSpace, _ url: String, kind: TabKind = .today, accessed: Date = Date()) -> BrowserTab {
        BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: url, title: url, kind: kind,
                   createdAt: accessed, lastAccessed: accessed, savedURL: url, savedTitle: url)
    }

    struct Archive {
        let folder: Folder
        let store: BrowserStore
        let first: BrowserSpace
        let second: BrowserSpace
        let a: BrowserTab

        @MainActor init() throws {
            folder = try Folder()
            let now = Date()
            var state = BrowserState.initial()
            first = state.spaces[0]
            var second = BrowserSpace(id: UUID(), name: "Later", symbol: "circle", color: "B9B5D4", profileID: first.profileID)
            second.autoArchiveHours = AutoArchiveInterval.sevenDays.rawValue
            self.second = second
            state.spaces.append(second)
            let old = now.addingTimeInterval(-2 * 86_400)
            a = SpaceSharingTestsSupport.tab(first, "https://a.example", accessed: old)
            let b = SpaceSharingTestsSupport.tab(second, "https://b.example", accessed: old)
            let kept = SpaceSharingTestsSupport.tab(first, "https://kept.example", kind: .pinned)
            state.tabs = [a, b, kept]
            state.selectedTabIDs = [kept.id]
            state.selectionBySpace[first.id.uuidString] = [kept.id]
            state.autoArchiveStartedAt = now.addingTimeInterval(-30 * 86_400)
            try folder.write(state)
            store = try folder.store(now: { now })
        }
    }
}
