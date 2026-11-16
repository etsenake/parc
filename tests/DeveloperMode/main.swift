import AppKit
import Foundation
MainActor.assumeIsolated { exitOnFailure {
let suite = "Parc.DeveloperModeChecks." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
let preferences = DeveloperModePreferences(defaults: defaults)
check(preferences.isEnabled(host: "LOCALHOST"), "localhost default is case-insensitive")
check(preferences.isEnabled(host: "127.0.0.1"), "loopback default")
check(!preferences.isEnabled(host: "www.example.test"), "ordinary host starts off")
try preferences.setEnabled(true, host: "WWW.Example.Test")
check(preferences.isEnabled(host: "www.example.test"), "normalized host enabled")
check(!preferences.isEnabled(host: "sub.www.example.test"), "subdomain remains independent")
try preferences.setEnabled(false, host: "localhost")
check(!preferences.isEnabled(host: "localhost"), "default can be disabled")
let restored = DeveloperModePreferences(defaults: defaults)
check(restored.isEnabled(host: "www.example.test"), "explicit host persists")
check(!restored.isEnabled(host: "localhost"), "default exclusion persists")
try restored.setEnabled(true, host: "LOCALHOST")
check(restored.isEnabled(host: "localhost"), "default exclusion can be removed")
try restored.setEnabled(false, host: "www.example.test")
check(!restored.isEnabled(host: "www.example.test"), "explicit host can be removed")
let key = "parc.developerMode.v1"
let invalid = Data("{\"version\":99,\"enabledHosts\":[],\"disabledDefaultHosts\":[]}".utf8)
defaults.set(invalid, forKey: key)
let unavailable = DeveloperModePreferences(defaults: defaults)
check(unavailable.loadError, "unknown version rejected")
do { try unavailable.setEnabled(true, host: "example.test"); preconditionFailure("unknown data overwritten") } catch { checks += 1 }
check(defaults.data(forKey: key) == invalid, "unknown data preserved")
let toolbar = DeveloperToolbarView(frame: NSRect(x: 0, y: 0, width: 900, height: 40))
func button(_ label: String) -> DeveloperToolbarButton? {
    toolbar.subviews.compactMap { $0 as? DeveloperToolbarButton }.first { $0.accessibilityLabel() == label }
}
toolbar.layoutSubtreeIfNeeded()
check(button("Blocked")?.isHidden == true, "no blocked sign without blocked content")
let blocked = BlockedPageContent(snapshot: ["revision": NSNumber(value: 1),
    "items": [["kind": "popup", "identifier": NSNumber(value: 0), "url": "https://popup.example/"]]])
toolbar.updateBlockedContent(blocked)
toolbar.layoutSubtreeIfNeeded()
let sign = button("Pop-up blocked"), extensions = button("Extensions Menu")
check(sign?.isHidden == false && sign?.isAccessibilityHidden() == false, "the blocked sign shows and reaches VoiceOver")
check(sign?.accessibilityHelp() == BlockedContentSign.help, "the blocked sign explains itself to VoiceOver")
check(sign.map { abs($0.frame.maxX - (extensions?.frame.minX ?? 0)) < 0.01 } == true, "the blocked sign sits just left of Extensions")
var received: DeveloperToolbarView.Action?
toolbar.onAction = { action, _ in received = action }
sign?.actionBlock?()
check(received == .blocked, "the blocked sign asks for the Site Control Center")
toolbar.frame.size.width = 370
toolbar.layoutSubtreeIfNeeded()
check(extensions?.isHidden == true && sign?.frame == DeveloperToolbarLayout.frames(in: NSRect(x: 0, y: 0, width: 370, height: 40)).trailing[6],
      "a narrow strip gives the blocked sign the Extensions button's place")
toolbar.updateBlockedContent(nil)
toolbar.layoutSubtreeIfNeeded()
check(sign?.isHidden == true && sign?.isAccessibilityHidden() == true && extensions?.isHidden == false,
      "clearing blocked content hides the sign and brings Extensions back")
print("Developer Mode preference checks: \(checks) passed")
} }
