import Foundation

package struct NoteUnsplashPhoto: Hashable, Decodable, Identifiable, Sendable {
    struct URLs: Hashable, Decodable, Sendable {
        var raw: String?
        var full: String?
        var regular: String?
        var small: String?
        var thumb: String?

        init(raw: String? = nil, full: String? = nil, regular: String? = nil, small: String? = nil, thumb: String? = nil) {
            self.raw = raw
            self.full = full
            self.regular = regular
            self.small = small
            self.thumb = thumb
        }
    }

    package struct Links: Hashable, Decodable, Sendable {
        package var html: String?
        var downloadLocation: String?

        init(html: String? = nil, downloadLocation: String? = nil) {
            self.html = html
            self.downloadLocation = downloadLocation
        }
    }

    struct User: Hashable, Decodable, Sendable {
        package struct Links: Hashable, Decodable, Sendable {
            var html: String?

            init(html: String? = nil) {
                self.html = html
            }
        }

        var name: String?
        var username: String
        var links: Links?

        init(name: String? = nil, username: String, links: Links? = nil) {
            self.name = name
            self.username = username
            self.links = links
        }
    }

    package var id: String
    var width: Int?
    var height: Int?
    var color: String?
    var description: String?
    var altDescription: String?
    var urls: URLs
    package var links: Links
    var user: User

    init(id: String, width: Int? = nil, height: Int? = nil, color: String? = nil, description: String? = nil, altDescription: String? = nil, urls: URLs, links: Links, user: User) {
        self.id = id
        self.width = width
        self.height = height
        self.color = color
        self.description = description
        self.altDescription = altDescription
        self.urls = urls
        self.links = links
        self.user = user
    }

    var aspectRatio: Double {
        guard let width, let height, width > 0, height > 0 else { return 1.5 }
        return Double(width) / Double(height)
    }

    package var photographer: String {
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? user.username : name
    }

    package var placeholderColor: (red: Double, green: Double, blue: Double)? {
        guard var hex = color?.trimmingCharacters(in: .whitespaces) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

package enum NoteUnsplashError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case rateLimited
    case unavailable(Int)
    case offline
    case unreadable

    package var errorDescription: String? {
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

package enum NoteUnsplash {
    package enum Orientation: String, Sendable {
        case landscape, portrait, squarish
    }

    package struct Page: Equatable, Sendable {
        package var photos: [NoteUnsplashPhoto]
        package var hasMore: Bool

        init(photos: [NoteUnsplashPhoto], hasMore: Bool) {
            self.photos = photos
            self.hasMore = hasMore
        }
    }

    static let builtInAccessKey = ""
    static let accessKeyDefaultsKey = "NoteUnsplashAccessKey"
    static let apiBase = URL(string: "https://api.unsplash.com")!
    static let pageSize = 30
    package static let coverWidth = 2400
    package static let imageWidth = 2000

    package static func accessKey(defaults: UserDefaults = .standard) -> String? {
        let stored = defaults.string(forKey: accessKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundled = (Bundle.main.object(forInfoDictionaryKey: accessKeyDefaultsKey) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = bundled.isEmpty ? builtInAccessKey.trimmingCharacters(in: .whitespacesAndNewlines) : bundled
        let key = stored.isEmpty ? fallback : stored
        return key.isEmpty ? nil : key
    }

    package static var isAvailable: Bool { accessKey() != nil }

    static func request(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.setValue("Client-ID " + key, forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    package static func listRequest(query: String, page: Int, orientation: Orientation?, key: String) -> URLRequest {
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

    package static func trackingRequest(for photo: NoteUnsplashPhoto, key: String) -> URLRequest? {
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

    package static func imageURL(for photo: NoteUnsplashPhoto, width: Int) -> URL? {
        sizedURL(photo.urls.raw, width: width, quality: 82) ?? photo.urls.full.flatMap(URL.init(string:)) ?? photo.urls.regular.flatMap(URL.init(string:))
    }

    package static func thumbnailURL(for photo: NoteUnsplashPhoto, width: Int) -> URL? {
        sizedURL(photo.urls.raw, width: width, quality: 70) ?? photo.urls.small.flatMap(URL.init(string:)) ?? photo.urls.thumb.flatMap(URL.init(string:))
    }

    package static func credit(for photo: NoteUnsplashPhoto) -> NoteMediaCredit {
        let profile = photo.user.links?.html.flatMap { $0.isEmpty ? nil : $0 } ?? "https://unsplash.com/@" + photo.user.username
        return NoteMediaCredit(name: photo.photographer, link: profile)
    }

    static func photoPageURL(for photo: NoteUnsplashPhoto) -> URL? {
        let page = photo.links.html.flatMap(URL.init(string:)) ?? URL(string: "https://unsplash.com/photos/" + photo.id)
        return page.map(NoteMediaCredit.referral)
    }

    package static func suggestedName(for photo: NoteUnsplashPhoto) -> String {
        "Photo by " + photo.photographer
    }

    package static func altText(for photo: NoteUnsplashPhoto) -> String? {
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

    package static func page(from data: Data, searching: Bool, page: Int) throws -> Page {
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

    package static func error(status: Int, remaining: String?, body: Data?) -> NoteUnsplashError? {
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

    package static func fileExtension(for data: Data) -> String? {
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

    package static func merge(_ existing: [NoteUnsplashPhoto], _ incoming: [NoteUnsplashPhoto]) -> [NoteUnsplashPhoto] {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }
}
