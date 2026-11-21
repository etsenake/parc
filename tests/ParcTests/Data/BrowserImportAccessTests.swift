import Foundation
import Testing
@testable import Parc

struct BrowserImportAccessTests {
    private func withBrowserBundle(_ bundleIdentifier: String, _ check: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = root.appendingPathComponent("Browser.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let information = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": "Safari",
            "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0)
        try information.write(to: contents.appendingPathComponent("Info.plist"))
        try check(bundle)
    }

    @MainActor @Test(arguments: [("com.apple.Safari", true), ("test.not-safari", false)])
    func safariAttributionUsesTheApplicationBundleRatherThanItsDisplayName(_ bundleID: String, _ expected: Bool) throws {
        try withBrowserBundle(bundleID) { bundle in
            #expect(BrowserImportCoordinator.isSafari(applicationAt: bundle) == expected)
        }
    }

    @MainActor @Test(arguments: [
        ("com.google.Chrome", "com.google.Chrome", "Safe Storage key" as String?),
        ("net.imput.helium", "net.imput.helium", "Storage Key"),
        ("com.openai.atlas", "com.openai.atlas", nil),
        ("org.mozilla.firefox", "org.mozilla.firefox", nil),
        ("app.zen-browser.zen", "app.zen-browser.zen", nil),
        ("synthetic safari token", "com.apple.Safari", nil),
    ])
    func aBrowserOnlyGetsTheKeychainPromptItsDataCanNeed(_ sourceID: String, _ bundleID: String, _ key: String?) throws {
        try withBrowserBundle(bundleID) { bundle in
            let note = BrowserImportCoordinator.keychainNote(identifier: sourceID, name: "Example", applicationAt: bundle)
            #expect(note?.contains("Example’s " + (key ?? "")) == key.map { _ in true })
        }
    }

    @MainActor @Test(arguments: [
        ("synthetic safari token", "com.apple.Safari", BrowserPasswordExport.safari as BrowserPasswordExport?),
        ("org.mozilla.firefox", "test.browser", .firefox),
        ("app.zen-browser.zen", "test.browser", .zen),
        ("com.apple.Safari", "test.browser", nil),
        ("com.google.Chrome", "test.browser", nil),
    ])
    func passwordHelpUsesTheActualBrowserExportFormat(_ sourceID: String, _ bundleID: String, _ format: BrowserPasswordExport?) throws {
        try withBrowserBundle(bundleID) { bundle in
            #expect(BrowserImportCoordinator.passwordExport(identifier: sourceID, applicationAt: bundle) == format)
        }
    }
}
