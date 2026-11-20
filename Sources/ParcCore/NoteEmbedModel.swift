import Foundation

enum NoteEmbedSizing {
    static let defaultHeight: Double = 420
    static let minimumHeight: Double = 160
    static let maximumHeight: Double = 1600

    static func clamped(_ height: Double?) -> Double {
        guard let height, height.isFinite else { return defaultHeight }
        return min(maximumHeight, max(minimumHeight, height.rounded()))
    }

    static func height(of props: NoteBlockProps) -> Double { clamped(props.height) }

    static func resized(from start: Double?, by delta: Double) -> Double {
        clamped(clamped(start) + (delta.isFinite ? delta : 0))
    }

    static func stored(_ height: Double) -> Double? {
        let value = clamped(height)
        return value == defaultHeight ? nil : value
    }
}

enum NoteEmbedAddress {
    static func liveURL(for url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              var host = components.host?.lowercased() else { return url }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        let path = components.path.split(separator: "/").map(String.init)
        switch host {
        case "youtube.com", "music.youtube.com":
            if path.first == "embed" { return url }
            if path.first == "watch", let id = components.queryItems?.first(where: { $0.name == "v" })?.value, valid(id) {
                return youTube(id, start: components.queryItems?.first(where: { $0.name == "t" })?.value) ?? url
            }
            if ["shorts", "live"].contains(path.first ?? ""), path.count > 1, valid(path[1]) { return youTube(path[1], start: nil) ?? url }
        case "youtu.be":
            if let id = path.first, valid(id) { return youTube(id, start: components.queryItems?.first(where: { $0.name == "t" })?.value) ?? url }
        case "vimeo.com":
            if let id = path.last, !id.isEmpty, id.allSatisfy(\.isNumber) { return URL(string: "https://player.vimeo.com/video/" + id) ?? url }
        case "loom.com":
            if path.first == "share", path.count > 1, valid(path[1]) { return URL(string: "https://www.loom.com/embed/" + path[1]) ?? url }
        case "open.spotify.com":
            if path.first != "embed", path.count >= 2, ["track", "album", "playlist", "episode", "show", "artist"].contains(path[path.count - 2]),
               valid(path[path.count - 1]) {
                return URL(string: "https://open.spotify.com/embed/" + path[path.count - 2] + "/" + path[path.count - 1]) ?? url
            }
        case "figma.com":
            if ["file", "design", "proto", "board"].contains(path.first ?? ""), path.count > 1 {
                var embed = URLComponents()
                embed.scheme = "https"
                embed.host = "www.figma.com"
                embed.path = "/embed"
                embed.queryItems = [URLQueryItem(name: "embed_host", value: "parc"), URLQueryItem(name: "url", value: url.absoluteString)]
                return embed.url ?? url
            }
        default:
            break
        }
        return url
    }

    private static func valid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func youTube(_ id: String, start: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/embed/" + id
        let seconds = start.flatMap { Int($0.hasSuffix("s") ? String($0.dropLast()) : $0) }
        if let seconds, seconds > 0 { components.queryItems = [URLQueryItem(name: "start", value: String(seconds))] }
        return components.url
    }
}
