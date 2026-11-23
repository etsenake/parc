import Foundation

package enum ChromiumNewTabPage {
    package static let hosts: Set<String> = ["newtab", "new-tab-page", "new-tab-page-third-party"]

    package static func matches(_ address: String?) -> Bool {
        guard let address, let value = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = value.scheme?.lowercased(), scheme == "parc" || scheme == "chrome",
              let host = value.host?.lowercased() else { return false }
        return hosts.contains(host)
    }
}
