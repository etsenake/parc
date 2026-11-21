import Foundation

package enum SettingsPrettyJSONPersistSkip {
    package static func shouldSkip(previous: Data?, next: Data) -> Bool {
        previous == next
    }
}
