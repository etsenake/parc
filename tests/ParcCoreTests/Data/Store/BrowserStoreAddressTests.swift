import Foundation
import Testing
@testable import ParcCore

struct BrowserStoreAddressTests {
    struct Projection: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let source: String
        let expected: String
    }

    private static let chromeSettings = "chrome://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"
    private static let parcSettings = "parc://settings/content/siteDetails?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#privacy"

    private static let projections = [
        Projection(testDescription: "Escaped Chromium settings", source: chromeSettings, expected: parcSettings),
        Projection(testDescription: "Unsupported Chromium host", source: "chrome://easel/not-a-uuid", expected: "chrome://easel/not-a-uuid"),
        Projection(testDescription: "Embedded Chromium URLs", source: "https://example.test/?next=chrome://settings/#chrome://flags",
                   expected: "https://example.test/?next=chrome://settings/#chrome://flags"),
        Projection(testDescription: "Untrusted origin", source: "chrome-untrusted://example/", expected: "chrome-untrusted://example/"),
    ]

    @Test(arguments: projections)
    static func onlySupportedChromiumOriginsProjectToPublicAddresses(_ projection: Projection) {
        #expect(BrowserInternalURL.publicString(projection.source) == projection.expected)
    }

    struct Navigation: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let input: String
        let expected: String?
    }

    private static let publicRoutes = [
        Navigation(testDescription: "Legacy Chromium input", input: chromeSettings, expected: parcSettings),
        Navigation(testDescription: "Typed Parc WebUI", input: parcSettings, expected: parcSettings),
        Navigation(testDescription: "Arc scheme", input: "arc://settings/", expected: nil),
        Navigation(testDescription: "Hostless Parc address", input: "parc:", expected: nil),
    ]

    @Test(arguments: publicRoutes)
    static func publicNavigationResolvesOnlyAcceptedSchemesAndHosts(_ route: Navigation) {
        #expect(NavigationInput.resolve(route.input)?.absoluteString == route.expected)
    }

    @Test static func chromiumDecidesWhetherAnUnknownControllerIsAvailable() {
        #expect(NavigationInput.resolve("parc://unknown-controller/path")?.host == "unknown-controller")
    }

    @Test static func browserWebUIIsNotAnAppDocument() {
        #expect(!InternalPage.isInternal(parcSettings))
    }

    @Test static func typedAppDocumentsRetainTheirPublicIdentity() {
        #expect(BrowserInternalURL.publicString(InternalPage.easel(UUID()).urlString).hasPrefix("parc://easel/"))
    }

    @Test @MainActor static func adoptingAChromiumURLUsesItsPublicScheme() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: chromeSettings)!, kind: .pinned)
            #expect(store.state.tabs.first { $0.id == id }?.url == parcSettings, "Direct adopted metadata uses the public scheme")
        }
    }

    @Test @MainActor static func nativeNavigationProjectsTheURLWithoutChangingThePin() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: chromeSettings)!, kind: .pinned)
            store.updateTab(id, url: "chrome://flags/#experiment")
            #expect(store.state.tabs.first { $0.id == id }?.url == "parc://flags/#experiment", "Native updates project only the display URL")
            #expect(store.state.tabs.first { $0.id == id }?.savedURL == parcSettings, "Navigation keeps the distinct saved pin destination")
        }
    }

    @Test @MainActor static func aLegacySessionMigratesChromiumURLsWithoutChangingTabIdentity() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(string: chromeSettings)!, kind: .pinned)
            store.updateTab(id, url: "chrome://flags/#experiment")
            try store.save()
            let file = directory.appendingPathComponent("session.json")
            var old = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var tabs = old["tabs"] as! [[String: Any]]
            let i = tabs.firstIndex { $0["id"] as? String == id.uuidString }!
            tabs[i]["url"] = "chrome://flags/#experiment"; tabs[i]["savedURL"] = chromeSettings
            old["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: old).write(to: file)
            let reopened = try BrowserStore(directory: directory)
            let restored = reopened.state.tabs.first { $0.id == id }!
            #expect(restored.url == "parc://flags/#experiment" && restored.savedURL == parcSettings, "Legacy sessions migrate current and saved addresses independently")
            #expect(restored.profileID == store.state.tabs.first { $0.id == id }?.profileID && restored.id == id, "Scheme migration preserves original Profile and item identity")
            let again = try BrowserStore(directory: directory)
            #expect(again.state.tabs.first { $0.id == id } == restored, "Migration persists idempotently")
        }
    }

    @Test @MainActor static func aSessionRestoresEveryDocumentVisitAndTheCurrentPosition() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let note = directory.appendingPathComponent("Plan.md"), easel = UUID()
            try Data("# Plan\n".utf8).write(to: note)
            let page: UUID
            do {
                let store = try BrowserStore(directory: directory)
                page = store.open("https://example.test/docs")
                store.updateTab(page, title: "Docs", url: "https://example.test/docs")
                #expect(store.openDocumentOverPage(page, page: .note(note), title: "Plan")
                           && store.openDocumentOverPage(page, page: .easel(easel), title: "Board")
                           && store.stepNoteVisit(page, forward: false), "A page holds a note and an Easel, showing the note")
                try store.save()
            }
            let reopened = try BrowserStore(directory: directory)
            let restored = reopened.state.tab(page)!
            #expect(restored.url == InternalPage.note(note).urlString && restored.noteVisit?.position == 1
                       && restored.noteVisit?.documents.count == 2 && restored.hasVisitStepAhead, "A session restores every document step and where the tab stood")
        }
    }

    @Test @MainActor static func forwardAfterRestartReachesTheNextDocument() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let note = directory.appendingPathComponent("Plan.md"), easel = UUID()
            try Data("# Plan\n".utf8).write(to: note)
            let page: UUID
            do {
                let store = try BrowserStore(directory: directory)
                page = store.open("https://example.test/docs")
                store.updateTab(page, title: "Docs", url: "https://example.test/docs")
                try #require(store.openDocumentOverPage(page, page: .note(note), title: "Plan")
                           && store.openDocumentOverPage(page, page: .easel(easel), title: "Board")
                           && store.stepNoteVisit(page, forward: false), "A page holds a note and an Easel, showing the note")
                try store.save()
            }
            let reopened = try BrowserStore(directory: directory)
            #expect(reopened.stepNoteVisit(page, forward: true) && reopened.state.tab(page)?.url == InternalPage.easel(easel).urlString, "Forward after a restart reaches the Easel")
        }
    }

    @Test @MainActor static func aSavedVisitKeepsTheShownDocumentForOlderVersions() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let note = directory.appendingPathComponent("Plan.md"), easel = UUID()
            try Data("# Plan\n".utf8).write(to: note)
            let page: UUID
            do {
                let store = try BrowserStore(directory: directory)
                page = store.open("https://example.test/docs")
                store.updateTab(page, title: "Docs", url: "https://example.test/docs")
                try #require(store.openDocumentOverPage(page, page: .note(note), title: "Plan")
                           && store.openDocumentOverPage(page, page: .easel(easel), title: "Board")
                           && store.stepNoteVisit(page, forward: false), "A page holds a note and an Easel, showing the note")
                try store.save()
            }
            let reopened = try BrowserStore(directory: directory)
            try #require(reopened.stepNoteVisit(page, forward: true) && reopened.state.tab(page)?.url == InternalPage.easel(easel).urlString, "Forward after a restart reaches the Easel")
            try reopened.save()

            let file = directory.appendingPathComponent("session.json")
            let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let tabs = saved["tabs"] as! [[String: Any]]
            let index = tabs.firstIndex { $0["id"] as? String == page.uuidString }!
            let record = tabs[index]["noteVisit"] as! [String: Any]
            #expect((record["note"] as? [String: Any])?["url"] as? String == InternalPage.easel(easel).urlString
                       && record["showsNote"] as? Bool == true, "Older Parc versions still find the shown document in the saved record")
        }
    }

    @Test @MainActor static func aLegacyDocumentVisitLoadsAsAOneStepStack() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let note = directory.appendingPathComponent("Plan.md"), easel = UUID()
            try Data("# Plan\n".utf8).write(to: note)
            let page: UUID
            do {
                let store = try BrowserStore(directory: directory)
                page = store.open("https://example.test/docs")
                store.updateTab(page, title: "Docs", url: "https://example.test/docs")
                try #require(store.openDocumentOverPage(page, page: .note(note), title: "Plan")
                           && store.openDocumentOverPage(page, page: .easel(easel), title: "Board")
                           && store.stepNoteVisit(page, forward: false), "A page holds a note and an Easel, showing the note")
                try store.save()
            }
            let reopened = try BrowserStore(directory: directory)
            try #require(reopened.stepNoteVisit(page, forward: true) && reopened.state.tab(page)?.url == InternalPage.easel(easel).urlString, "Forward after a restart reaches the Easel")
            try reopened.save()

            let file = directory.appendingPathComponent("session.json")
            var saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            var tabs = saved["tabs"] as! [[String: Any]]
            let index = tabs.firstIndex { $0["id"] as? String == page.uuidString }!
            let record = tabs[index]["noteVisit"] as! [String: Any]
            tabs[index]["noteVisit"] = ["page": record["page"]!, "note": record["note"]!, "showsNote": false]
            saved["tabs"] = tabs
            try JSONSerialization.data(withJSONObject: saved).write(to: file)
            let legacy = try BrowserStore(directory: directory)
            let migrated = legacy.state.tab(page)!.noteVisit!
            #expect(migrated.documents == [.init(url: InternalPage.easel(easel).urlString, title: "Board")]
                       && migrated.position == 0 && !migrated.showsNote && migrated.page.url == "https://example.test/docs", "A session saved with one document step loads as a one-step stack")
        }
    }

    @Test @MainActor static func aLocalFileOpensWithItsFileName() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let id = store.openResolvedURL(URL(fileURLWithPath: "/Users/me/Desktop/Lease Agreement.pdf"))
            #expect(store.state.tab(id)?.title == "Lease Agreement.pdf", "A local file opens titled by its file name")
        }
    }

    @Test @MainActor static func aWebPageOpensWithItsHostname() throws {
        try BrowserStoreTestsSupport.withDirectory { directory in
            let store = try BrowserStore(directory: directory)
            let web = store.openResolvedURL(URL(string: "https://example.test/start")!)
            #expect(store.state.tab(web)?.title == "example.test", "A web page still opens titled by its host")
        }
    }
}
