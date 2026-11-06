import Foundation

/// Settings pretty-JSON persist skip for keyboard shortcuts and link-routing.
/// Encode still produces the same pretty/sorted bytes; when those bytes match
/// the last successful write, skip the atomic replace. A first persist or any
/// byte change still writes.
enum SettingsPrettyJSONPersistSkip {
    /// True no-op: identical encoded payload. Nil previous never skips.
    static func shouldSkip(previous: Data?, next: Data) -> Bool {
        previous == next
    }
}
