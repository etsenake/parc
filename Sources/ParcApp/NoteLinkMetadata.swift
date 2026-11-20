import Foundation

struct NoteLinkPreview: Hashable {
    var title: String?
    var summary: String?
    var siteName: String?
    var iconURL: String?
    var imageURL: String?

    var bookmark: NoteBookmark {
        NoteBookmark(title: title, summary: summary, siteName: siteName, iconURL: iconURL, imageURL: imageURL)
    }

    var isEmpty: Bool { title == nil && summary == nil && siteName == nil && iconURL == nil && imageURL == nil }
}

enum NoteLinkMetadataParser {
    struct Tag {
        var name: String
        var attributes: [String: String]
    }

    static func parse(html: String, baseURL: URL) -> NoteLinkPreview {
        var meta: [String: String] = [:]
        var icons: [(rel: String, href: String, size: Int)] = []
        var title: String?
        var base = baseURL
        var inBody = false
        var index = html.startIndex
        let end = html.endIndex
        while index < end, let open = html[index...].firstIndex(of: "<") {
            var cursor = html.index(after: open)
            guard cursor < end else { break }
            if html[cursor...].hasPrefix("!--") {
                guard let close = html.range(of: "-->", range: cursor..<end) else { break }
                index = close.upperBound
                continue
            }
            guard let close = tagEnd(in: html, from: cursor) else { break }
            let body = html[cursor..<close]
            cursor = html.index(after: close)
            index = cursor
            guard let tag = parseTag(body) else { continue }
            switch tag.name {
            case "title":
                guard title == nil, !inBody, let finish = html.range(of: "</title", options: .caseInsensitive, range: cursor..<end) else { continue }
                title = clean(decodeEntities(String(html[cursor..<finish.lowerBound])))
                index = finish.upperBound
            case "base":
                if let href = tag.attributes["href"], let url = URL(string: href, relativeTo: baseURL) { base = url.absoluteURL }
            case "meta":
                let key = (tag.attributes["property"] ?? tag.attributes["name"] ?? tag.attributes["itemprop"])?.lowercased()
                guard let key, let content = tag.attributes["content"], meta[key] == nil else { continue }
                meta[key] = decodeEntities(content)
            case "link":
                guard let rel = tag.attributes["rel"]?.lowercased(), let href = tag.attributes["href"], !href.isEmpty else { continue }
                let relations = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
                guard relations.contains("icon") || relations.contains("apple-touch-icon")
                        || relations.contains("apple-touch-icon-precomposed") else { continue }
                let link = decodeEntities(href)
                let path = link.lowercased().split(separator: "?").first.map(String.init) ?? ""
                guard !path.hasSuffix(".svg"), tag.attributes["type"]?.lowercased().contains("svg") != true else { continue }
                icons.append((rel, link, iconSize(tag.attributes["sizes"])))
            case "script", "style", "template", "textarea":
                guard let finish = html.range(of: "</" + tag.name, options: .caseInsensitive, range: cursor..<end) else { index = end; continue }
                index = finish.upperBound
            case "body":
                inBody = true
                if !meta.isEmpty || title != nil { index = end }
            default:
                continue
            }
        }
        func value(_ keys: String...) -> String? {
            for key in keys { if let found = meta[key].flatMap(clean) { return found } }
            return nil
        }
        func absolute(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  !value.lowercased().hasPrefix("data:"), !value.lowercased().hasPrefix("javascript:") else { return nil }
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(CharacterSet(charactersIn: "#%"))) ?? value
            guard let url = URL(string: value, relativeTo: base) ?? URL(string: encoded, relativeTo: base),
                  let scheme = url.absoluteURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return url.absoluteURL.absoluteString
        }
        var preview = NoteLinkPreview()
        preview.title = value("og:title", "twitter:title") ?? title ?? value("title")
        preview.summary = value("og:description", "twitter:description", "description")
        preview.siteName = value("og:site_name", "application-name", "apple-mobile-web-app-title")
        preview.imageURL = absolute(value("og:image:secure_url", "og:image", "og:image:url", "twitter:image", "twitter:image:src", "image"))
        let bestIcon = icons.max { lhs, rhs in iconScore(lhs) < iconScore(rhs) }
        preview.iconURL = absolute(bestIcon?.href) ?? defaultIcon(for: base)
        if preview.title == nil, let host = baseURL.host { preview.title = host }
        return preview
    }

    static func defaultIcon(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/favicon.ico"
        return components.url?.absoluteString
    }

    static func charset(contentType: String?, head: Data) -> String.Encoding {
        if let contentType, let found = charsetName(in: contentType.lowercased()), let encoding = encoding(named: found) { return encoding }
        let sniff = String(decoding: head.prefix(4096), as: UTF8.self).lowercased()
        if let range = sniff.range(of: "charset=") {
            let rest = sniff[range.upperBound...].drop { $0 == "\"" || $0 == "'" }
            let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            if let encoding = encoding(named: name) { return encoding }
        }
        return .utf8
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
                                       "ndash": "–", "mdash": "—", "hellip": "…", "rsquo": "’", "lsquo": "‘",
                                       "rdquo": "”", "ldquo": "“", "middot": "·", "bull": "•", "copy": "©", "reg": "®",
                                       "trade": "™", "laquo": "«", "raquo": "»", "times": "×"]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let entity = text[text.index(after: index)..<semicolon]
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[entity.lowercased()]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func clean(_ text: String) -> String? {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > 400 ? String(collapsed.prefix(400)) + "…" : collapsed
    }

    private static func tagEnd(in html: String, from start: String.Index) -> String.Index? {
        var quote: Character?
        var index = start
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    static func parseTag(_ body: Substring) -> Tag? {
        var scanner = body.drop { $0.isWhitespace }
        guard let first = scanner.first, first.isLetter else { return nil }
        let name = scanner.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
        scanner = scanner.dropFirst(name.count)
        var attributes: [String: String] = [:]
        while true {
            scanner = scanner.drop { $0.isWhitespace || $0 == "/" }
            guard !scanner.isEmpty else { break }
            let key = scanner.prefix { !$0.isWhitespace && $0 != "=" && $0 != "/" }
            guard !key.isEmpty else { scanner = scanner.dropFirst(); continue }
            scanner = scanner.dropFirst(key.count).drop { $0.isWhitespace }
            var value = ""
            if scanner.first == "=" {
                scanner = scanner.dropFirst().drop { $0.isWhitespace }
                if let quote = scanner.first, quote == "\"" || quote == "'" {
                    let inner = scanner.dropFirst()
                    let content = inner.prefix { $0 != quote }
                    value = String(content)
                    scanner = inner.dropFirst(content.count).dropFirst()
                } else {
                    let content = scanner.prefix { !$0.isWhitespace }
                    value = String(content)
                    scanner = scanner.dropFirst(content.count)
                }
            }
            let normalized = key.lowercased()
            if attributes[normalized] == nil { attributes[normalized] = value }
        }
        return Tag(name: name.lowercased(), attributes: attributes)
    }

    private static func iconSize(_ sizes: String?) -> Int {
        guard let sizes = sizes?.lowercased() else { return 0 }
        if sizes == "any" { return 512 }
        return sizes.split(separator: " ").compactMap { token in token.split(separator: "x").first.flatMap { Int($0) } }.max() ?? 0
    }

    private static func iconScore(_ icon: (rel: String, href: String, size: Int)) -> Int {
        let lower = icon.href.lowercased()
        var score = icon.size == 0 ? 16 : min(icon.size, 196)
        if icon.rel.contains("apple-touch-icon") { score += icon.size == 0 ? 160 : 20 }
        if lower.hasSuffix(".ico") { score -= 2 }
        return score
    }

    private static func charsetName(in contentType: String) -> String? {
        guard let range = contentType.range(of: "charset=") else { return nil }
        let rest = contentType[range.upperBound...].drop { $0 == "\"" || $0 == "'" }
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    private static func encoding(named name: String) -> String.Encoding? {
        guard !name.isEmpty else { return nil }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }
}

@MainActor
final class NoteLinkMetadata {
    enum Failure: Error, Equatable {
        case notWeb, badStatus(Int), notHTML, unreadable
    }

    static let shared = NoteLinkMetadata()
    nonisolated static let byteLimit = 786_432
    nonisolated static let timeout: TimeInterval = 10

    private let session: URLSession
    private var cache: [URL: NoteLinkPreview] = [:]
    private var failures: [URL: Failure] = [:]
    private var waiting: [URL: [(Result<NoteLinkPreview, Failure>) -> Void]] = [:]

    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout * 2
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        ]
        self.session = URLSession(configuration: configuration)
    }

    func cached(_ url: URL) -> NoteLinkPreview? { cache[url] }

    func failure(for url: URL) -> Failure? { failures[url] }

    func remember(_ preview: NoteLinkPreview, for url: URL) {
        guard !preview.isEmpty else { return }
        cache[url] = preview
    }

    func fetch(_ url: URL, completion: @escaping (Result<NoteLinkPreview, Failure>) -> Void) {
        if let hit = cache[url] { completion(.success(hit)); return }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            completion(.failure(.notWeb))
            return
        }
        if waiting[url] != nil { waiting[url]?.append(completion); return }
        waiting[url] = [completion]
        failures.removeValue(forKey: url)
        let task = session.dataTask(with: Self.request(for: url))
        task.delegate = NoteLinkFetch(url: url, limit: Self.byteLimit) { [weak self] outcome in
            DispatchQueue.main.async { self?.finish(url, outcome) }
        }
        task.resume()
    }

    nonisolated static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        return request
    }

    nonisolated static func admits(contentType: String) -> Bool {
        contentType.isEmpty || contentType.contains("html") || contentType.contains("xml") || contentType.hasPrefix("image/")
    }

    nonisolated static func interpret(data: Data, response: HTTPURLResponse, url: URL) -> Result<NoteLinkPreview, Failure> {
        guard (200..<300).contains(response.statusCode) else { return .failure(.badStatus(response.statusCode)) }
        let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let page = response.url ?? url
        guard admits(contentType: type) else { return .failure(.notHTML) }
        if type.hasPrefix("image/") {
            var preview = NoteLinkPreview()
            preview.title = page.lastPathComponent.removingPercentEncoding ?? page.lastPathComponent
            preview.siteName = NoteMediaFormat.displayHost(page)
            preview.imageURL = page.absoluteString
            preview.iconURL = NoteLinkMetadataParser.defaultIcon(for: page)
            return .success(preview)
        }
        let slice = data.prefix(byteLimit)
        let encoding = NoteLinkMetadataParser.charset(contentType: type, head: slice)
        let html = String(data: slice, encoding: encoding) ?? String(decoding: slice, as: UTF8.self)
        return .success(NoteLinkMetadataParser.parse(html: html, baseURL: page))
    }

    private func finish(_ url: URL, _ outcome: Result<NoteLinkPreview, Failure>) {
        switch outcome {
        case .success(let preview): cache[url] = preview; failures.removeValue(forKey: url)
        case .failure(let failure): failures[url] = failure
        }
        let callbacks = waiting.removeValue(forKey: url) ?? []
        for callback in callbacks { callback(outcome) }
    }
}

private final class NoteLinkFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let limit: Int
    private let completion: (Result<NoteLinkPreview, NoteLinkMetadata.Failure>) -> Void
    private let lock = NSLock()
    private var data = Data()
    private var response: HTTPURLResponse?
    private var finished = false

    init(url: URL, limit: Int, completion: @escaping (Result<NoteLinkPreview, NoteLinkMetadata.Failure>) -> Void) {
        self.url = url
        self.limit = limit
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            complete(.failure(.unreadable))
            completionHandler(.cancel)
            return
        }
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard (200..<300).contains(http.statusCode) else {
            complete(.failure(.badStatus(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        guard NoteLinkMetadata.admits(contentType: type) else {
            complete(.failure(.notHTML))
            completionHandler(.cancel)
            return
        }
        lock.withLock { self.response = http }
        if type.hasPrefix("image/") {
            complete(NoteLinkMetadata.interpret(data: Data(), response: http, url: url))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let full: Bool = lock.withLock {
            data.append(chunk)
            return data.count >= limit || headIsComplete
        }
        guard full else { return }
        dataTask.cancel()
        deliverCollected()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as? URLError)?.code != .cancelled {
            let collected = lock.withLock { data.isEmpty }
            if collected { complete(.failure(.unreadable)); return }
        }
        deliverCollected()
    }

    private var headIsComplete: Bool {
        guard data.count > 2048, let tail = String(data: data.suffix(min(data.count, 65_536)), encoding: .isoLatin1) else { return false }
        return tail.range(of: "</head", options: .caseInsensitive) != nil
    }

    private func deliverCollected() {
        let snapshot: (Data, HTTPURLResponse?) = lock.withLock { (data, response) }
        guard let response = snapshot.1 else { complete(.failure(.unreadable)); return }
        complete(NoteLinkMetadata.interpret(data: snapshot.0, response: response, url: url))
    }

    private func complete(_ outcome: Result<NoteLinkPreview, NoteLinkMetadata.Failure>) {
        let first: Bool = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if first { completion(outcome) }
    }
}
