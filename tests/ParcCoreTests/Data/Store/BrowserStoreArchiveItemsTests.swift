import Foundation
import Testing
@testable import ParcCore

@MainActor
struct BrowserStoreArchiveItemsTests {
    @Test static func archiveAcrossSpacesAndProfiles() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let firstSpace = store.activeSpaceID
            let short = store.open("https://short.example")
            let secondSpace = store.createSpace(name: "Day-long")
            let profile = store.createProfile(name: "Day-long")
            store.assignProfile(profile, toSpace: secondSpace)
            store.setAutoArchiveInterval(.twentyFourHours, for: profile)
            let long = store.open("https://long.example")
            _ = store.open("https://selected.example")
            now.addTimeInterval(13 * 3600)
            #expect(store.archiveExpiredTabs() == [short], "A background Space must expire by its own profile's shorter duration")
            #expect(store.state.selectionBySpace[firstSpace.uuidString]?.isEmpty == true, "Automatic closure must remove stale remembered selection in inactive Spaces")
            #expect(try BrowserStoreTestsSupport.tab(long, in: store).archivedAt == nil, "A different profile's longer interval must remain independent")
            now.addTimeInterval(11 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "The second profile's exact day boundary must be retained")
            now.addTimeInterval(1)
            #expect(store.archiveExpiredTabs() == [long], "The second profile must expire only beyond its own day threshold")
        }
    }

    @Test static func archiveSavedSplitConstituents() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://first.example")
            let second = store.open("https://second.example")
            store.setSplit([first, second])
            _ = store.open("https://outside.example")
            now.addTimeInterval(13 * 3600)
            #expect(store.archiveExpiredTabs(protectedTabIDs: [second]).isEmpty, "One protected constituent must keep the saved pane group from partial automatic closure")
            store.refreshVisibleTabs([second])
            #expect(store.archiveExpiredTabs().isEmpty, "A recently active constituent must preserve an otherwise old saved pane group")
            now.addTimeInterval(12 * 3600)
            #expect(store.archiveExpiredTabs().isEmpty, "Every constituent must be strictly older than the interval")
            now.addTimeInterval(1)
            #expect(Set(store.archiveExpiredTabs()) == [first, second], "An entirely inactive unprotected Today pane group must expire together")
            #expect(store.state.splitLayouts.isEmpty, "Expired pane groups must leave no dangling saved geometry")
        }
    }

    @Test static func archiveTypedItemsAndMixedGroups() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            store.archiveExpiredTabs()
            let first = store.open("https://mixed-today.example")
            let second = store.open("https://mixed-pinned.example")
            store.setSplit([first, second])
            let note = store.openResolvedURL(URL(string: InternalPage.note(URL(fileURLWithPath: NSTemporaryDirectory() + "Parc Notes/" + UUID().uuidString + ".md")).urlString)!)
            let easel = store.openResolvedURL(URL(string: InternalPage.easel(UUID()).urlString)!)
            let malformed = store.openResolvedURL(URL(string: "parc://note/not-a-document")!)
            let folder = store.createFolder(name: "Saved")
            let nested = store.open("https://saved-child.example")
            store.moveTab(nested, toSpace: store.activeSpaceID, folderID: folder)
            let favorite = store.open("https://favorite.example", kind: .favorite)
            _ = store.open("https://current.example")
            store.moveTab(second, toSpace: store.activeSpaceID, folderID: folder)
            now.addTimeInterval(13 * 3600)
            #expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] }, "The original mixed split is retained by the model before eligibility")
            #expect(Set(store.archiveExpiredTabs()) == [note, easel], "Eligible Note/Easel roots archive; structural/saved/malformed items and a mixed split remain whole")
            #expect([first, second, malformed, nested, favorite].allSatisfy { id in
                store.state.tabs.contains { $0.id == id && $0.archivedAt == nil }
            }, "Automatic archive cannot detach a Today pane from a retained saved sibling")
            #expect(store.state.splitLayouts.contains { $0.tabIDs == [first, second] }, "An excluded split keeps its original identity and geometry")
        }
    }

    @Test(arguments: ["space", "document", "title"])
    static func archiveRevalidatesTheOriginalItem(change: String) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            var now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let source = store.activeSpaceID
            let destination = store.createSpace(name: "Destination")
            store.selectSpace(source)
            let original = store.open("https://original.example")
            _ = store.open("https://current.example")
            store.archiveExpiredTabs()
            now.addTimeInterval(13 * 3600)
            var request: (() -> Bool)?, finish: ((Bool) -> Void)?
            var result: [[UUID]] = []
            store.requestPageRetirement = { ids, validate, complete in
                if ids == [original] { request = validate; finish = complete }
            }
            store.archiveExpiredTabs(protectedTabIDs: []) { result.append($0) }
            #expect(request != nil && result.isEmpty, "The original item waits for native retirement")
            switch change {
            case "space": store.moveTab(original, toSpace: destination)
            case "document": store.updateTab(original, url: "https://replacement.example")
            default: store.updateTab(original, title: "Updated page title")
            }
            let accepted = request?() == true
            #expect(accepted == (change == "title"), "A changed original \(change) is distinguished from a metadata-only title refresh")
            finish?(accepted)
            finish?(accepted)
            #expect(result == [accepted ? [original] : []] && store.retiringTabIDs.isEmpty, "Original-item revalidation completes once and releases its reservation")
            #expect(((try BrowserStoreTestsSupport.tab(original, in: store)).archivedAt != nil) == accepted, "Only an unchanged original item follows accepted retirement into Archive")
        }
    }

    @Test(arguments: ["archive", "refresh", "policy"])
    static func anUnchangedArchiveOperationKeepsTheSessionFile(operation: String) throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try BrowserStore(directory: directory, now: { now })
            let scheduler = DataFixtures.DeferredSave(store)
            store.archiveExpiredTabs()
            let selected = store.open("https://selected.example")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            let original = try Data(contentsOf: file)
            let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)
            switch operation {
            case "archive": #expect(store.archiveExpiredTabs().isEmpty)
            case "refresh": store.refreshVisibleTabs([selected])
            default: store.setAutoArchiveInterval(.twelveHours, for: store.activeSpace.profileID)
            }
            scheduler.run(on: store)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(try attributes[.modificationDate] as? Date == oldDate && (try Data(contentsOf: file)) == original, "No-op checks, identical activity timestamps and unchanged policies must not rewrite the session")
        }
    }
}
