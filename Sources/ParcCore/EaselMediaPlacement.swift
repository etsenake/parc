import Foundation

enum EaselMediaPlacement {
    static let mediaWidth = 480.0
    static let placeholderHeight = 52.0
    static let embedSize = (width: 640.0, height: 420.0)
    static let audioHeight = 72.0
    static let fileHeight = 60.0
    static let bookmarkHeight = 120.0
    static let minimumSide = 24.0

    static func placesEmpty(_ kind: EaselItemKind) -> Bool {
        kind.isMedia || kind == .link || kind == .browser || kind == .equation
    }

    static func placeholderSize(for kind: EaselItemKind) -> (width: Double, height: Double) {
        kind == .equation ? (360, 72) : (mediaWidth, placeholderHeight)
    }

    static func addName(for kind: EaselItemKind) -> String {
        switch kind {
        case .image: return "Add image"
        case .video: return "Add video"
        case .audio: return "Add audio"
        case .file: return "Add file"
        case .pdf: return "Add PDF"
        case .link: return "Add bookmark"
        case .browser: return "Add embed"
        case .equation: return "Add block equation"
        default: return "Add " + kind.rawValue
        }
    }

    static func replaceName(for kind: EaselItemKind) -> String { "Replace " + sentenceName(for: kind) }

    static func embedName(for kind: EaselItemKind) -> String { "Embed " + sentenceName(for: kind) }

    private static func sentenceName(for kind: EaselItemKind) -> String {
        let name = displayName(for: kind)
        guard name.count > 1, name.dropFirst().first?.isUppercase != true else { return name }
        return name.prefix(1).lowercased() + name.dropFirst()
    }

    static func displayName(for kind: EaselItemKind) -> String {
        switch kind {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .file: return "File"
        case .pdf: return "PDF"
        case .link: return "Bookmark"
        case .browser: return "Embed"
        case .equation: return "Block equation"
        default: return kind.rawValue.capitalized
        }
    }

    static func accessibilityLabel(_ item: EaselItem) -> String {
        let name = displayName(for: item.kind)
        if item.isEmptyPlaceholder { return "Empty " + (item.kind == .pdf ? name : name.lowercased()) }
        if item.kind == .equation && item.text.isEmpty { return "Empty block equation" }
        return name
    }

    static func placeholderFrame(for kind: EaselItemKind, visible: EaselRect, occupied: [EaselRect]) -> EaselRect? {
        let size = placeholderSize(for: kind)
        guard [visible.x, visible.y, visible.width, visible.height].allSatisfy(\.isFinite) else { return nil }
        var frame = EaselRect(x: max(0, (visible.x + visible.width / 2 - size.width / 2).rounded()),
                              y: max(0, (visible.y + visible.height / 2 - size.height / 2).rounded()),
                              width: size.width, height: size.height)
        for _ in 0..<12 where occupied.contains(where: { abs($0.x - frame.x) < 1 && abs($0.y - frame.y) < 1 }) {
            frame.x += 24; frame.y += 24
        }
        guard abs(frame.x) <= EaselRect.maximumCoordinate - size.width, abs(frame.y) <= EaselRect.maximumCoordinate - size.height else { return nil }
        return frame
    }

    static func fitted(width naturalWidth: Double, height naturalHeight: Double, maximumWidth: Double = mediaWidth) -> (width: Double, height: Double) {
        guard naturalWidth.isFinite, naturalHeight.isFinite, naturalWidth > 0, naturalHeight > 0 else { return (maximumWidth, maximumWidth * 9 / 16) }
        let width = min(maximumWidth, max(minimumSide, naturalWidth))
        let height = max(minimumSide, (width * naturalHeight / naturalWidth).rounded())
        return (width.rounded(), min(height, 4 * maximumWidth))
    }

    static func filledSize(for kind: EaselItemKind, natural: (width: Double, height: Double)? = nil) -> (width: Double, height: Double) {
        switch kind {
        case .image, .pdf:
            return natural.map { fitted(width: $0.width, height: $0.height, maximumWidth: mediaWidth) } ?? (mediaWidth, mediaWidth * 3 / 4)
        case .video:
            return natural.map { fitted(width: mediaWidth, height: mediaWidth * $0.height / max(1, $0.width)) } ?? (mediaWidth, mediaWidth * 9 / 16)
        case .audio: return (mediaWidth, audioHeight)
        case .file: return (mediaWidth, fileHeight)
        case .link: return (mediaWidth, bookmarkHeight)
        case .browser: return embedSize
        default: return placeholderSize(for: kind)
        }
    }

    static func resized(_ frame: EaselRect, width: Double, height: Double) -> EaselRect {
        let width = max(1, width.isFinite ? width : frame.width), height = max(1, height.isFinite ? height : frame.height)
        let x = frame.x + frame.width / 2 - width / 2, y = frame.y + frame.height / 2 - height / 2
        return EaselRect(x: max(0, x.rounded()), y: max(0, y.rounded()), width: width.rounded(), height: height.rounded())
    }

    static func row(of sizes: [(width: Double, height: Double)], centredAt centre: EaselPoint, gap: Double = 24) -> [EaselRect] {
        guard !sizes.isEmpty else { return [] }
        let total = sizes.reduce(0) { $0 + $1.width } + gap * Double(sizes.count - 1)
        let tallest = sizes.map(\.height).max() ?? 0
        var x = centre.x - total / 2
        return sizes.map { size in
            defer { x += size.width + gap }
            return EaselRect(x: max(0, x.rounded()), y: max(0, (centre.y - tallest / 2 + (tallest - size.height) / 2).rounded()),
                             width: size.width, height: size.height)
        }
    }
}
