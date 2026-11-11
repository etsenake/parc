import Foundation

enum SettingsPrettyJSONPersistSkip {
    static func shouldSkip(previous: Data?, next: Data) -> Bool {
        previous == next
    }
}
