import Foundation
import Testing
@testable import Parc

struct CaptureListPlanTests {
    private typealias View = CaptureLibraryView

    private static func file(_ name: String, modified: Int, local: Bool = true) -> ExternalMediaFile {
        var value = stat()
        value.st_dev = 1
        value.st_ino = UInt64(name.utf8.reduce(1) { ($0 &* 31) &+ Int($1) }.magnitude)
        value.st_size = 1
        value.st_mtimespec.tv_sec = modified
        value.st_ctimespec.tv_sec = modified
        return ExternalMediaFile(url: URL(fileURLWithPath: "/media/" + name), folder: URL(fileURLWithPath: "/media"),
            revision: ExternalMediaFile.Revision(value), kind: .image, isScreenshot: false, isScreenRecording: false, isLocal: local)
    }

    private static func fixtures(count: Int = 24) -> [ExternalMediaFile] {
        (0..<count).map { file(String(format: "fixture-%02d.png", $0), modified: 1_700_000_000 - $0 * 60) }
    }

    private static func base(_ files: [ExternalMediaFile]) throws -> [View.Item] {
        try View.plan(from: [], captures: [], files: files, query: "").items
    }

    private static func plan(_ files: [ExternalMediaFile], from original: [ExternalMediaFile], query: String = "") throws -> View.ListPlan {
        try View.plan(from: try base(original), captures: [], files: files, query: query)
    }

    @Test func aSingleArrivalInsertsOneTileInsteadOfReloadingTheGrid() throws {
        let original = Self.fixtures()
        let plan = try Self.plan(original + [Self.file("arrival.png", modified: 1_700_000_060)], from: original)
        #expect(plan.inserted == [IndexPath(item: 0, section: 0)] && plan.removed.isEmpty && !plan.reload && plan.items.count == 25)
    }

    @Test func aRenameSwapsJustThatTile() throws {
        let original = Self.fixtures()
        let renamed = original.map { $0.title == "fixture-10.png" ? Self.file("fixture-10b.png", modified: 1_700_000_000 - 10 * 60) : $0 }
        let plan = try Self.plan(renamed, from: original)
        #expect(plan.removed.count == 1 && plan.inserted.count == 1 && !plan.reload && plan.items.count == 24)
    }

    @Test func anInPlaceChangeMovesJustThatTileToTheTop() throws {
        let original = Self.fixtures()
        let edited = original.map { $0.title == "fixture-07.png" ? Self.file("fixture-07.png", modified: 1_700_000_100) : $0 }
        let plan = try Self.plan(edited, from: original)
        #expect(plan.inserted == [IndexPath(item: 0, section: 0)] && plan.removed == [IndexPath(item: 7, section: 0)])
        #expect(plan.items[0].title == "fixture-07.png")
    }

    @Test func anICloudDownloadStatusChangeReplacesJustThatTileInPlace() throws {
        let original = Self.fixtures()
        let evicted = original.map { $0.title == "fixture-12.png" ? Self.file("fixture-12.png", modified: 1_700_000_000 - 12 * 60, local: false) : $0 }
        let plan = try Self.plan(evicted, from: original)
        #expect(plan.removed == [IndexPath(item: 12, section: 0)] && plan.inserted == [IndexPath(item: 12, section: 0)])
    }

    @Test func removingAFileDropsOnlyItsTile() throws {
        let original = Self.fixtures()
        let plan = try Self.plan(original.filter { $0.title != "fixture-07.png" }, from: original)
        #expect(plan.removed == [IndexPath(item: 7, section: 0)] && plan.inserted.isEmpty && plan.items.count == 23)
    }

    @Test func aPlanWithManyChangesReloadsTheGrid() throws {
        let original = Self.fixtures(count: 150)
        let replacements = (0..<150).map { Self.file("later-\($0).png", modified: 1_600_000_000 - $0) }
        let plan = try Self.plan(replacements, from: original)
        #expect(plan.reload)
    }

    @Test func aSearchKeepsOnlyTheMatchingFiles() throws {
        let files = Self.fixtures()
        let plan = try Self.plan(files, from: files, query: "fixture-1")
        #expect(plan.items.count == 10 && plan.query == "fixture-1")
    }

    @Test func onlyTheRemovedFilesThumbnailsAreEvicted() throws {
        let original = Self.fixtures()
        let remaining = original.filter { $0.title != "fixture-07.png" }
        let plan = try Self.plan(remaining, from: original)
        let gone = try #require(original.first { $0.title == "fixture-07.png" })
        #expect(plan.evicted == [View.Item.file(gone).cacheKey])
    }

    @Test func aReplacedFileKeepsNoThumbnailOfItsOldRevision() throws {
        let original = Self.fixtures()
        let edited = original.map { $0.title == "fixture-07.png" ? Self.file("fixture-07.png", modified: 1_700_000_100) : $0 }
        let plan = try Self.plan(edited, from: original)
        let old = try #require(original.first { $0.title == "fixture-07.png" })
        #expect(plan.evicted.contains(View.Item.file(old).cacheKey))
    }

    @Test func thePlanMapsEveryItemToItsIndex() throws {
        let files = Self.fixtures()
        let plan = try Self.plan(files, from: [])
        #expect(plan.positions.count == 24 && plan.items.enumerated().allSatisfy { plan.positions[$1.id] == $0 })
    }
}
