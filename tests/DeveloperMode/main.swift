import AppKit
import Foundation
try MainActor.assumeIsolated {
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
print("Developer Mode preference checks: \(checks) passed")
}
