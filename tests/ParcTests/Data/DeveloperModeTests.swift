import AppKit
import Testing
@testable import Parc

struct DeveloperModeTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "Parc.DeveloperModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor @Test(arguments: [("LOCALHOST", true), ("127.0.0.1", true), ("www.example.test", false)])
    func developerModeStartsOnForLoopbackOnly(_ host: String, _ enabled: Bool) {
        withDefaults { defaults in
            #expect(DeveloperModePreferences(defaults: defaults).isEnabled(host: host) == enabled)
        }
    }

    @MainActor @Test func anExplicitHostIsNormalizedAndPersistsWithoutEnablingItsSubdomain() throws {
        try withDefaults { defaults in
            try DeveloperModePreferences(defaults: defaults).setEnabled(true, host: "WWW.Example.Test")

            let restored = DeveloperModePreferences(defaults: defaults)
            #expect(restored.isEnabled(host: "www.example.test"))
            #expect(!restored.isEnabled(host: "sub.www.example.test"))
        }
    }

    @MainActor @Test(arguments: [("localhost", true), ("www.example.test", false)])
    func aPreviouslyChangedHostCanReturnToItsDefault(_ host: String, _ enabled: Bool) throws {
        try withDefaults { defaults in
            try DeveloperModePreferences(defaults: defaults).setEnabled(!enabled, host: host)
            let restored = DeveloperModePreferences(defaults: defaults)
            #expect(restored.isEnabled(host: host) == !enabled)

            try restored.setEnabled(enabled, host: host.uppercased())

            #expect(DeveloperModePreferences(defaults: defaults).isEnabled(host: host) == enabled)
        }
    }

    @MainActor @Test func anUnknownPreferencesVersionIsPreserved() {
        withDefaults { defaults in
            let key = "parc.developerMode.v1"
            let invalid = Data(#"{"version":99,"enabledHosts":[],"disabledDefaultHosts":[]}"#.utf8)
            defaults.set(invalid, forKey: key)
            let preferences = DeveloperModePreferences(defaults: defaults)

            #expect(preferences.loadError)
            #expect(throws: (any Error).self) { try preferences.setEnabled(true, host: "example.test") }
            #expect(defaults.data(forKey: key) == invalid)
        }
    }

    @MainActor
    private struct Toolbar {
        let view: DeveloperToolbarView

        init(width: CGFloat = 900, showsPopup: Bool = true) {
            _ = NSApplication.shared
            view = DeveloperToolbarView(frame: CGRect(x: 0, y: 0, width: width, height: 40))
            if showsPopup {
                view.updateBlockedContent(BlockedPageContent(snapshot: ["revision": NSNumber(value: 1),
                    "items": [["kind": "popup", "identifier": NSNumber(value: 0), "url": "https://popup.example/"]]]))
            }
            view.layoutSubtreeIfNeeded()
        }

        func button(_ label: String) -> DeveloperToolbarButton? {
            view.subviews.compactMap { $0 as? DeveloperToolbarButton }.first { $0.accessibilityLabel() == label }
        }
    }

    @MainActor @Test func noBlockedContentLeavesTheSignHidden() {
        #expect(Toolbar(showsPopup: false).button("Blocked")?.isHidden == true)
    }

    @MainActor @Test func aBlockedPopupGetsAVisibleAndAccessibleSign() throws {
        let toolbar = Toolbar()
        let sign = try #require(toolbar.button("Pop-up blocked"))
        let extensions = try #require(toolbar.button("Extensions Menu"))

        #expect(!sign.isHidden)
        #expect(!sign.isAccessibilityHidden())
        #expect(sign.accessibilityHelp() == BlockedContentSign.help)
        #expect(sign.frame.maxX == extensions.frame.minX)
    }

    @MainActor @Test func aBlockedSignOpensTheSiteControlCenter() throws {
        let toolbar = Toolbar()
        let sign = try #require(toolbar.button("Pop-up blocked"))
        var received: DeveloperToolbarView.Action?
        toolbar.view.onAction = { action, _ in received = action }

        sign.actionBlock?()

        #expect(received == .blocked)
    }

    @MainActor @Test func aNarrowToolbarLendsTheExtensionsSlotToTheBlockedSign() throws {
        let toolbar = Toolbar()
        let sign = try #require(toolbar.button("Pop-up blocked"))
        let extensions = try #require(toolbar.button("Extensions Menu"))
        toolbar.view.frame.size.width = 370
        toolbar.view.layoutSubtreeIfNeeded()

        #expect(extensions.isHidden)
        #expect(sign.frame == DeveloperToolbarLayout.frames(in: toolbar.view.bounds).trailing[6])
    }

    @MainActor @Test func clearingBlockedContentRestoresTheExtensionsButton() throws {
        let toolbar = Toolbar()
        let sign = try #require(toolbar.button("Pop-up blocked"))
        let extensions = try #require(toolbar.button("Extensions Menu"))
        toolbar.view.updateBlockedContent(nil)
        toolbar.view.layoutSubtreeIfNeeded()

        #expect(sign.isHidden)
        #expect(sign.isAccessibilityHidden())
        #expect(!extensions.isHidden)
    }
}
