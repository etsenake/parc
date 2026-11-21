import Foundation

package enum EaselWebNavigation {
    package enum Mode: Int, CaseIterable { case address, search }
    package enum Category: String, CaseIterable {
        case all, images, video, news, maps, shopping
        package var title: String {
            switch self {
            case .all: return "All"
            case .images: return "Images"
            case .video: return "Videos"
            case .news: return "News"
            case .maps: return "Maps"
            case .shopping: return "Shopping"
            }
        }
    }
    package struct Draft: Equatable {
        package var mode: Mode = .address
        package var text = ""
        package var category: Category = .images
        package init(mode: Mode = .address, text: String = "", category: Category = .images) {
            self.mode = mode
            self.text = text
            self.category = category
        }
    }
    package static func address(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 16_384,
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !text.contains(where: { $0.isWhitespace }) else { return nil }
        let qualified = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: qualified), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    package enum Entry: Equatable { case empty, address(URL), search(String) }
    package static func entry(_ raw: String) -> Entry {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        if text.contains("://") || text.lowercased().hasPrefix("localhost") {
            return address(text).map(Entry.address) ?? .search(text)
        }
        guard let url = address(text), let host = url.host, !host.hasPrefix("."), !host.hasSuffix(".") else { return .search(text) }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let named = parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } && parts.last.map { $0.count >= 2 && $0.allSatisfy(\.isLetter) } == true
        let numeric = parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) }
        return named || numeric ? .address(url) : .search(text)
    }
    package static func destination(_ draft: Draft) -> URL? {
        if draft.mode == .address { return address(draft.text) }
        let query = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 4096,
              !query.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        var values = [URLQueryItem(name: "q", value: query)]
        switch draft.category {
        case .all: values += [URLQueryItem(name: "ia", value: "web")]
        case .images: values += [URLQueryItem(name: "iax", value: "images"), URLQueryItem(name: "ia", value: "images")]
        case .video: values += [URLQueryItem(name: "iax", value: "videos"), URLQueryItem(name: "ia", value: "videos")]
        case .news: values += [URLQueryItem(name: "iar", value: "news"), URLQueryItem(name: "ia", value: "news")]
        case .maps: values += [URLQueryItem(name: "iaxm", value: "maps")]
        case .shopping: values += [URLQueryItem(name: "iax", value: "shopping"), URLQueryItem(name: "ia", value: "shopping")]
        }
        components.queryItems = values
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
