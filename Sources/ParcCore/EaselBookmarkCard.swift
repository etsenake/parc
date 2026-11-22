import Foundation

package enum EaselBookmarkCard {
    static let summaryLimit = 160

    package static func host(_ url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    package static func title(of item: EaselItem) -> String {
        if let title = trimmed(item.preview?.title) ?? trimmed(item.text) { return title }
        guard let raw = item.url, let url = URL(string: raw) else { return "Bookmark" }
        return host(url)
    }

    package static func summary(of item: EaselItem) -> String? {
        guard let summary = trimmed(item.preview?.summary) else { return nil }
        guard summary.count > summaryLimit else { return summary }
        return String(summary.prefix(summaryLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    package static func siteLine(of item: EaselItem) -> String {
        guard var text = item.url else { return "" }
        if text.hasPrefix("https://") { text.removeFirst(8) } else if text.hasPrefix("http://") { text.removeFirst(7) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    package static func preview(title: String?, summary: String?, siteName: String?, imageURL: String?, iconURL: String?) -> EaselLinkPreviewData? {
        func text(_ value: String?) -> String? {
            guard let value = trimmed(value) else { return nil }
            let scalars = value.unicodeScalars.filter { $0.properties.generalCategory != .control || $0 == "\n" || $0 == "\t" }
            var clipped = "", bytes = 0
            for character in String(String.UnicodeScalarView(scalars)) {
                bytes += String(character).utf8.count
                guard bytes <= EaselLinkPreviewData.maximumTextBytes else { break }
                clipped.append(character)
            }
            return trimmed(clipped)
        }
        func address(_ value: String?) -> String? { value.flatMap { EaselLinkPreviewData.isAddress($0) ? $0 : nil } }
        let preview = EaselLinkPreviewData(title: text(title), summary: text(summary), siteName: text(siteName),
                                           image: address(imageURL), icon: address(iconURL))
        return preview.isValid ? preview : nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
