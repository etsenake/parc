import Foundation
import Testing
@testable import ParcCore

struct SidebarDocumentPreviewTests {
    let id = UUID()
    let note = URL(fileURLWithPath: "/Users/someone/Notes/Plan.md")
    var easel: SidebarDocumentKind { .easel(id) }
    var page: SidebarDocumentKind { .note(note) }

    typealias Cache = SidebarThumbnailCache<String, Int>
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    let light = Cache.Key(document: "a", appearance: "light")
    let dark = Cache.Key(document: "a", appearance: "dark")

    @Test func aMarkdownOrTextFileIsANoteAndOtherFilesStayWebTabs() {
        #expect(SidebarDocumentKind(url: note) == .note(note), "a Markdown file is a note")
        #expect(SidebarDocumentKind(url: URL(fileURLWithPath: "/tmp/list.txt")) != nil, "a text file is a note")
        #expect(SidebarDocumentKind(url: URL(fileURLWithPath: "/tmp/paper.pdf")) == nil, "other files stay web tabs")
        #expect(SidebarDocumentKind(url: URL(string: "https://example.com/a.md")!) == nil, "web Markdown is a web tab")
    }

    @Test func anEaselAddressNeedsAnExactIDAndOtherInternalPagesAreNotDocuments() {
        #expect(SidebarDocumentKind(url: URL(string: "parc://easel/" + id.uuidString.lowercased())!) == .easel(id), "Easel address")
        #expect(SidebarDocumentKind(url: URL(string: "parc://easel/" + id.uuidString + "?x=1")!) == nil, "Easel address with a query")
        #expect(SidebarDocumentKind(url: URL(string: "parc://easel/nope")!) == nil, "Easel address without an ID")
        #expect(SidebarDocumentKind(url: URL(string: "parc://settings/")!) == nil, "other internal pages")
    }

    @Test func noteKeysUseTheStandardizedPathAndKindsNeverShareKeys() {
        #expect(SidebarDocumentKind.note(note).cacheKey == SidebarDocumentKind.note(URL(fileURLWithPath: "/Users/someone/Notes/./Plan.md")).cacheKey, "note keys use the standardized path")
        #expect(SidebarDocumentKind.easel(id).cacheKey != SidebarDocumentKind.note(note).cacheKey, "kinds never share keys")
    }

    @Test func missingDocumentsAndObjectCountsAreDescribed() {
        #expect(SidebarDocumentPreviewText.missing(page) == "This note moved or was deleted", "missing note")
        #expect(SidebarDocumentPreviewText.missing(easel) == "This Easel was deleted", "missing Easel")
        #expect(SidebarDocumentPreviewText.objects(0) == "No objects yet", "no objects")
        #expect(SidebarDocumentPreviewText.objects(1) == "1 object", "one object")
        #expect(SidebarDocumentPreviewText.objects(12) == "12 objects", "many objects")
    }

    @Test func subtitlesAndBodiesFollowTheDocumentContent() {
        #expect(SidebarDocumentPreviewText.subtitle(easel, content: .init(objectCount: 3)) == "Easel · 3 objects", "Easel subtitle counts objects")
        #expect(SidebarDocumentPreviewText.subtitle(easel, content: .init()) == "Easel", "Easel subtitle before the count")
        #expect(SidebarDocumentPreviewText.subtitle(easel, content: .init(availability: .missing, objectCount: 3)) == "Easel", "missing Easel has no count")
        #expect(SidebarDocumentPreviewText.subtitle(page, content: .init(snippet: "Hello")) == "Note", "note subtitle")
        #expect(SidebarDocumentPreviewText.body(page, content: .init(snippet: "  Hello  ")) == "Hello", "note body is the snippet")
        #expect(SidebarDocumentPreviewText.body(page, content: .init()) == "Empty note", "empty note body")
        #expect(SidebarDocumentPreviewText.body(page, content: .init(availability: .missing, snippet: "Old")) == "This note moved or was deleted", "missing note body")
        #expect(SidebarDocumentPreviewText.body(easel, content: .init(objectCount: 0)) == "No objects yet", "empty Easel body")
    }

    @Test func previewButtonsFollowAvailabilityAndPeekAdmission() {
        #expect(SidebarDocumentPreviewButtons.buttons(availability: .available, peekAdmitsDocuments: false) == [.copyLink, .split], "documents offer Copy Link and Split View")
        #expect(SidebarDocumentPreviewButtons.buttons(availability: .available, peekAdmitsDocuments: true) == [.peek, .copyLink, .split], "Peek only when it admits documents")
        #expect(SidebarDocumentPreviewButtons.buttons(availability: .missing, peekAdmitsDocuments: true).isEmpty, "a missing document offers nothing")
    }

    @Test func theThumbnailCacheServesFreshHitsAndKeepsStaleOnesShowable() {
        var cache = Cache(capacity: 2, interval: 1)
        #expect(cache.renderDelay(light, now: start) == 0, "first render is immediate")
        cache.store("a1", for: light, revision: 1, now: start)
        #expect(cache.fresh(light, revision: 1) == "a1", "fresh hit")
        #expect(cache.fresh(light, revision: 2) == nil, "an edit makes the thumbnail stale")
        #expect(cache.latest(light) == "a1", "the stale thumbnail stays showable")
        #expect(cache.fresh(dark, revision: 1) == nil, "appearances are separate")
    }

    @Test func theThumbnailCacheThrottlesRendersAndHandlesClockSteps() {
        var cache = Cache(capacity: 2, interval: 1)
        cache.store("a1", for: light, revision: 1, now: start)
        #expect(abs(cache.renderDelay(light, now: start.addingTimeInterval(0.25)) - 0.75) < 0.0001, "renders are throttled")
        #expect(cache.renderDelay(light, now: start.addingTimeInterval(1.5)) == 0, "throttle expires")
        #expect(cache.renderDelay(light, now: start.addingTimeInterval(-5)) == 1, "a clock step back waits a full interval")
    }

    @Test func invalidationDropsEveryAppearanceButKeepsTheThrottle() {
        var cache = Cache(capacity: 2, interval: 1)
        cache.store("a1", for: light, revision: 1, now: start)
        cache.store("a2", for: dark, revision: 1, now: start)
        cache.invalidate(document: "a")
        #expect(cache.latest(light) == nil && cache.latest(dark) == nil, "invalidation drops every appearance")
        #expect(cache.renderDelay(light, now: start.addingTimeInterval(0.5)) > 0, "invalidation keeps the throttle")
    }

    @Test func theLeastRecentlyUsedThumbnailIsEvictedAndRemoveAllClears() {
        var cache = Cache(capacity: 2, interval: 1)
        let b = Cache.Key(document: "b", appearance: "light"), c = Cache.Key(document: "c", appearance: "light")
        cache.store("a", for: light, revision: 1, now: start)
        cache.store("b", for: b, revision: 1, now: start)
        cache.touch(light)
        cache.store("c", for: c, revision: 1, now: start)
        #expect(cache.count == 2 && cache.latest(b) == nil && cache.latest(light) == "a", "least recently used thumbnail is evicted")
        cache.removeAll()
        #expect(cache.count == 0 && cache.renderDelay(light, now: start) == 0, "remove all")
    }
}
