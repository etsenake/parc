import Foundation

enum EaselObjectLink {
    static let badgeSize = 18.0
    static let badgeOffset = 14.0

    static func canLink(_ item: EaselItem) -> Bool { item.kind.holdsText }

    static func hasLink(_ item: EaselItem) -> Bool { item.url != nil && canLink(item) }

    static func link(of item: EaselItem) -> URL? {
        guard canLink(item), let raw = item.url, let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    static func normalized(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 16_384, !text.contains(where: { $0.isWhitespace }) else { return nil }
        let explicit = text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        guard let url = URL(string: explicit ? text : "https://" + text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        if !explicit && !host.contains(".") && host.lowercased() != "localhost" { return nil }
        return url.absoluteString
    }

    static func linking(_ document: EaselDocument, id: UUID, to raw: String?) -> EaselDocument? {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = document.items[index]
        guard canLink(item), !item.isLocked else { return nil }
        let value: String?
        if let raw {
            guard let normalized = normalized(raw) else { return nil }
            value = normalized
        } else { value = nil }
        guard item.url != value else { return nil }
        var next = document
        next.items[index].url = value
        return next
    }

    static func badgeRect(for frame: EaselRect, scale: Double) -> EaselRect {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let size = badgeSize / scale, offset = badgeOffset / scale
        let x = frame.x + frame.width + offset - size / 2
        let y = max(0, frame.y - offset - size / 2)
        return EaselRect(x: x, y: y, width: size, height: size)
    }

    static func badgeAllowance(_ item: EaselItem, scale: Double) -> Double {
        guard hasLink(item) else { return 0 }
        let scale = scale.isFinite && scale > 0 ? scale : 1
        return (badgeOffset + badgeSize) / scale
    }

    static func item(at point: EaselPoint, in items: [EaselItem], scale: Double) -> EaselItem? {
        items.reversed().first { item in
            hasLink(item) && EaselContentHitTest.contains(point, rect: badgeRect(for: EaselRotation.bounds(of: item), scale: scale)) && link(of: item) != nil
        }
    }
}
