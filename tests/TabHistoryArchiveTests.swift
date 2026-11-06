import Foundation

/// TabHistoryArchive on a real temporary directory: what a relaunch reads
/// back, when a record is refused, and what removes records.
@main
struct TabHistoryArchiveTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) throws {
        count += 1; if !value { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("parc-tab-history-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = UUID(), other = UUID()
        let kept = UUID(), moved = UUID(), archived = UUID(), paged = UUID(), closed = UUID()
        let bytes = Data([1, 2, 3])
        func names() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) }
        do {
            let session = TabHistoryArchive(directory: root)
            for id in [kept, moved, archived, paged, closed] {
                session.store(.init(url: "https://a.invalid/", profileID: profile, navigation: bytes), for: id)
            }
            session.store(.init(url: "https://b.invalid/", profileID: profile, navigation: Data([4])), for: kept)
            session.remove(closed)
            session.prune(keeping: [kept, moved, paged, closed])
            session.flush()
            try check(try names() == Set([kept, moved, paged].map(\.uuidString)),
                      "prune removes gone tabs and remove drops a closed one")
            try FileManager.default.removeItem(at: root.appendingPathComponent(paged.uuidString))
            session.store(.init(url: "https://a.invalid/", profileID: profile, navigation: bytes), for: paged)
            session.flush()
            try check(!(try names()).contains(paged.uuidString), "an unchanged record is not written again")
            session.store(.init(url: "https://a.invalid/", profileID: profile, navigation: Data([5])), for: paged)
            session.flush()
            try check((try names()).contains(paged.uuidString), "a changed record is written")
        }
        let relaunch = TabHistoryArchive(directory: root)
        try check(relaunch.takeLaunchNavigation(for: kept, url: "https://b.invalid/", profileID: profile) == Data([4]),
                  "the latest record comes back after a relaunch")
        try check(relaunch.takeLaunchNavigation(for: kept, url: "https://b.invalid/", profileID: profile) == nil,
                  "only the tab's first page gets it")
        try check(relaunch.takeLaunchNavigation(for: moved, url: "https://c.invalid/", profileID: profile) == nil,
                  "a tab now at another address gets nothing")
        try check(relaunch.takeLaunchNavigation(for: archived, url: "https://a.invalid/", profileID: profile) == nil,
                  "a pruned tab gets nothing")
        relaunch.pageCreated(paged)
        try check(relaunch.takeLaunchNavigation(for: paged, url: "https://a.invalid/", profileID: profile) == nil,
                  "a tab that already had a page this launch gets nothing")
        let profileMoved = TabHistoryArchive(directory: root)
        try check(profileMoved.takeLaunchNavigation(for: moved, url: "https://a.invalid/", profileID: other) == nil,
                  "a tab now in another Profile gets nothing")
        profileMoved.removeAll()
        profileMoved.flush()
        try check(try names().isEmpty, "a history deletion drops every record")
        print("TabHistoryArchive: \(count) checks passed")
    }
}
