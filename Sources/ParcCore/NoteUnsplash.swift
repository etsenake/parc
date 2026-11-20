import Foundation

struct NoteUnsplashPhoto: Hashable, Decodable, Identifiable, Sendable {
    struct URLs: Hashable, Decodable, Sendable {
        var raw: String?
        var full: String?
        var regular: String?
        var small: String?
        var thumb: String?
    }

    struct Links: Hashable, Decodable, Sendable {
        var html: String?
        var downloadLocation: String?
    }

    struct User: Hashable, Decodable, Sendable {
        struct Links: Hashable, Decodable, Sendable {
            var html: String?
        }

        var name: String?
        var username: String
        var links: Links?
    }

    var id: String
    var width: Int?
    var height: Int?
    var color: String?
    var description: String?
    var altDescription: String?
    var urls: URLs
    var links: Links
    var user: User

    var aspectRatio: Double {
        guard let width, let height, width > 0, height > 0 else { return 1.5 }
        return Double(width) / Double(height)
    }

    var photographer: String {
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? user.username : name
    }

    var placeholderColor: (red: Double, green: Double, blue: Double)? {
        guard var hex = color?.trimmingCharacters(in: .whitespaces) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

enum NoteUnsplashError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case rateLimited
    case unavailable(Int)
    case offline
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Unsplash needs an access key before it can share photos."
        case .unauthorized: return "Unsplash didn’t accept Parc’s access key."
        case .rateLimited: return "Unsplash needs a breather. Try again in a bit."
        case .unavailable(let status): return "Unsplash is having a moment (\(status)). Try again soon."
        case .offline: return "Can’t reach Unsplash right now. Are you online?"
        case .unreadable: return "Unsplash sent back something Parc couldn’t read."
        }
    }
}

enum NoteUnsplash {
    enum Orientation: String, Sendable {
        case landscape, portrait, squarish
    }

    struct Page: Equatable, Sendable {
        var photos: [NoteUnsplashPhoto]
        var hasMore: Bool
    }

    static let builtInAccessKey = ""
    static let accessKeyDefaultsKey = "NoteUnsplashAccessKey"
    static let apiBase = URL(string: "https://api.unsplash.com")!
    static let pageSize = 30
    static let coverWidth = 2400
    static let imageWidth = 2000

    static func accessKey(defaults: UserDefaults = .standard) -> String? {
        let stored = defaults.string(forKey: accessKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = stored.isEmpty ? builtInAccessKey.trimmingCharacters(in: .whitespacesAndNewlines) : stored
        return key.isEmpty ? nil : key
    }

    static var isAvailable: Bool { accessKey() != nil }

    static func request(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("Client-ID " + key, forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func listRequest(query: String, page: Int, orientation: Orientation?, key: String) -> URLRequest {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "page", value: String(max(1, page))), URLQueryItem(name: "per_page", value: String(pageSize))]
        if trimmed.isEmpty {
            components.path = "/photos"
        } else {
            components.path = "/search/photos"
            items.insert(URLQueryItem(name: "query", value: trimmed), at: 0)
            items.append(URLQueryItem(name: "content_filter", value: "high"))
            if let orientation { items.append(URLQueryItem(name: "orientation", value: orientation.rawValue)) }
        }
        components.queryItems = items
        return request(components.url!, key: key)
    }

    static func trackingRequest(for photo: NoteUnsplashPhoto, key: String) -> URLRequest? {
        guard let location = photo.links.downloadLocation, let url = URL(string: location), isUnsplashAPI(url) else { return nil }
        return request(url, key: key)
    }

    static func isUnsplashAPI(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.unsplash.com"
    }

    static func sizedURL(_ base: String?, width: Int, quality: Int) -> URL? {
        guard let base, var components = URLComponents(string: base), components.scheme?.lowercased() == "https" else { return nil }
        let replaced: Set<String> = ["w", "h", "q", "fm", "fit", "crop", "dpr"]
        var items = (components.queryItems ?? []).filter { !replaced.contains($0.name) }
        items.append(URLQueryItem(name: "w", value: String(width)))
        items.append(URLQueryItem(name: "q", value: String(quality)))
        items.append(URLQueryItem(name: "fm", value: "jpg"))
        items.append(URLQueryItem(name: "fit", value: "max"))
        components.queryItems = items
        return components.url
    }

    static func imageURL(for photo: NoteUnsplashPhoto, width: Int) -> URL? {
        sizedURL(photo.urls.raw, width: width, quality: 82) ?? photo.urls.full.flatMap(URL.init(string:)) ?? photo.urls.regular.flatMap(URL.init(string:))
    }

    static func thumbnailURL(for photo: NoteUnsplashPhoto, width: Int) -> URL? {
        sizedURL(photo.urls.raw, width: width, quality: 70) ?? photo.urls.small.flatMap(URL.init(string:)) ?? photo.urls.thumb.flatMap(URL.init(string:))
    }

    static func credit(for photo: NoteUnsplashPhoto) -> NoteMediaCredit {
        let profile = photo.user.links?.html.flatMap { $0.isEmpty ? nil : $0 } ?? "https://unsplash.com/@" + photo.user.username
        return NoteMediaCredit(name: photo.photographer, link: profile)
    }

    static func photoPageURL(for photo: NoteUnsplashPhoto) -> URL? {
        let page = photo.links.html.flatMap(URL.init(string:)) ?? URL(string: "https://unsplash.com/photos/" + photo.id)
        return page.map(NoteMediaCredit.referral)
    }

    static func suggestedName(for photo: NoteUnsplashPhoto) -> String {
        "Photo by " + photo.photographer
    }

    static func altText(for photo: NoteUnsplashPhoto) -> String? {
        for candidate in [photo.altDescription, photo.description] {
            let text = (candidate ?? "").split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            return text.prefix(1).uppercased() + text.dropFirst()
        }
        return nil
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private struct SearchResults: Decodable {
        var total: Int?
        var totalPages: Int?
        var results: [NoteUnsplashPhoto]
    }

    static func page(from data: Data, searching: Bool, page: Int) throws -> Page {
        do {
            if searching {
                let results = try decoder().decode(SearchResults.self, from: data)
                let hasMore = results.totalPages.map { page < $0 } ?? (results.results.count >= pageSize)
                return Page(photos: results.results, hasMore: hasMore && !results.results.isEmpty)
            }
            let photos = try decoder().decode([NoteUnsplashPhoto].self, from: data)
            return Page(photos: photos, hasMore: photos.count >= pageSize)
        } catch {
            throw NoteUnsplashError.unreadable
        }
    }

    static func error(status: Int, remaining: String?, body: Data?) -> NoteUnsplashError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403, 429:
            let text = body.flatMap { String(data: $0, encoding: .utf8) }?.lowercased() ?? ""
            if status == 429 || remaining == "0" || text.contains("rate limit") { return .rateLimited }
            return .unauthorized
        default: return .unavailable(status)
        }
    }

    static func fileExtension(for data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if bytes.count == 12, Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WEBP".utf8) { return "webp" }
        if bytes.count == 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(decoding: bytes[8..<12], as: UTF8.self)
            if brand == "avif" || brand == "avis" { return "avif" }
            if ["heic", "heix", "mif1", "msf1"].contains(brand) { return "heic" }
        }
        return nil
    }

    static func merge(_ existing: [NoteUnsplashPhoto], _ incoming: [NoteUnsplashPhoto]) -> [NoteUnsplashPhoto] {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }
}
