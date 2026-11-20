import Foundation

enum SidebarAddressText {
    static let placeholder = "Search or Enter URL…"
    static let easel = "Easel"

    static func host(of url: URL) -> String? {
        guard let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func label(forPage address: String?) -> String {
        guard let address else { return placeholder }
        if let page = InternalPage(urlString: address) { return page.noteURL?.lastPathComponent ?? easel }
        guard let url = URL(string: address) else { return placeholder }
        return url.isFileURL ? url.lastPathComponent : host(of: url) ?? placeholder
    }
}
