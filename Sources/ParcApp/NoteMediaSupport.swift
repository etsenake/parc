import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum NoteMediaEdge: Hashable {
    case leading, trailing
}

enum NoteMediaLayout {
    static let minimumWidth: CGFloat = 72
    static let rubberBandDimension: CGFloat = 90
    static let fallbackAspect: CGFloat = 9.0 / 16.0
    static let snapTolerance: CGFloat = 6

    static func pointSize(pixelWidth: Int, pixelHeight: Int, dpiWidth: Double?, dpiHeight: Double?) -> CGSize {
        let horizontal = (dpiWidth ?? 72) > 0 ? (dpiWidth ?? 72) : 72
        let vertical = (dpiHeight ?? horizontal) > 0 ? (dpiHeight ?? horizontal) : horizontal
        return CGSize(width: CGFloat(Double(pixelWidth) * 72 / horizontal), height: CGFloat(Double(pixelHeight) * 72 / vertical))
    }

    static func aspect(of size: CGSize?) -> CGFloat {
        guard let size, size.width > 0, size.height > 0 else { return fallbackAspect }
        return size.height / size.width
    }

    static func displayWidth(fraction: Double?, natural: CGSize?, columnWidth: CGFloat) -> CGFloat {
        guard columnWidth > 0 else { return 0 }
        let floor = min(minimumWidth, columnWidth)
        if let fraction, fraction.isFinite, fraction > 0 {
            return min(columnWidth, max(floor, (CGFloat(fraction) * columnWidth).rounded()))
        }
        guard let natural, natural.width > 0 else { return columnWidth }
        return min(columnWidth, max(floor, natural.width.rounded()))
    }

    static func displayHeight(width: CGFloat, natural: CGSize?) -> CGFloat {
        (width * aspect(of: natural)).rounded()
    }

    static func originX(width: CGFloat, alignment: NoteAlignment, columnWidth: CGFloat) -> CGFloat {
        switch alignment {
        case .left: return 0
        case .center: return ((columnWidth - width) / 2).rounded()
        case .right: return (columnWidth - width).rounded()
        }
    }

    static func rawResize(start: CGFloat, dragDelta: CGFloat, edge: NoteMediaEdge, alignment: NoteAlignment) -> CGFloat {
        let direction: CGFloat = edge == .trailing ? 1 : -1
        let factor: CGFloat = alignment == .center ? 2 : 1
        return start + dragDelta * direction * factor
    }

    static func rubberBanded(_ width: CGFloat, columnWidth: CGFloat) -> CGFloat {
        let floor = min(minimumWidth, columnWidth)
        if width > columnWidth { return columnWidth + rubberBand(width - columnWidth) }
        if width < floor { return floor - rubberBand(floor - width) }
        return width
    }

    static func clamped(_ width: CGFloat, columnWidth: CGFloat) -> CGFloat {
        min(columnWidth, max(min(minimumWidth, columnWidth), width))
    }

    static func storedFraction(width: CGFloat, columnWidth: CGFloat) -> Double {
        guard columnWidth > 0 else { return 1 }
        let settled = clamped(width, columnWidth: columnWidth)
        if columnWidth - settled <= snapTolerance { return 1 }
        return (Double(settled / columnWidth) * 1000).rounded() / 1000
    }

    static func rubberBand(_ excess: CGFloat) -> CGFloat {
        guard excess > 0 else { return 0 }
        return (1 - 1 / (excess * 0.55 / rubberBandDimension + 1)) * rubberBandDimension
    }
}

enum NoteMediaFormat {
    static func fileSize(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "" }
        if bytes < 1000 { return bytes == 1 ? "1 byte" : "\(bytes) bytes" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1000
        var unit = 0
        while value >= 999.95, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        let trimmed = rounded.hasSuffix(".0") ? String(rounded.dropLast(2)) : rounded
        return trimmed + " " + units[unit]
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600, minutes = total / 60 % 60, remainder = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%d:%02d", minutes, remainder)
    }

    static func displayHost(_ url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum NoteMediaSource: Equatable {
    case empty
    case local(URL)
    case remote(URL)
    case unresolved(String)

    init(_ source: String?, resolve: (String) -> URL?) {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { self = .empty; return }
        guard let url = resolve(trimmed) else { self = .unresolved(trimmed); return }
        if url.isFileURL { self = .local(url.absoluteURL.standardizedFileURL); return }
        switch url.scheme?.lowercased() {
        case "http", "https": self = .remote(url)
        default: self = .unresolved(trimmed)
        }
    }

    var url: URL? {
        switch self {
        case .local(let url), .remote(let url): return url
        case .empty, .unresolved: return nil
        }
    }

    var isEmpty: Bool { self == .empty }

    func displayPath(original: String?) -> String {
        switch self {
        case .empty: return ""
        case .local(let url): return (url.path as NSString).abbreviatingWithTildeInPath
        case .remote(let url): return url.absoluteString
        case .unresolved(let value): return original ?? value
        }
    }

    var fileName: String {
        switch self {
        case .empty: return ""
        case .local(let url): return url.lastPathComponent
        case .remote(let url):
            let last = url.lastPathComponent
            return last.isEmpty || last == "/" ? NoteMediaFormat.displayHost(url) : (last.removingPercentEncoding ?? last)
        case .unresolved(let value):
            let last = (value as NSString).lastPathComponent
            return last.removingPercentEncoding ?? last
        }
    }

    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           url.host?.isEmpty == false { return url }
        guard trimmed.contains("."), !trimmed.contains("://"), let url = URL(string: "https://" + trimmed),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url
    }
}

enum NoteMediaFileType {
    static func blockKind(for url: URL) -> NoteBlockKind {
        blockKind(forExtension: url.pathExtension)
    }

    static func blockKind(forExtension ext: String) -> NoteBlockKind {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext.lowercased()) else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .file
    }

    static func accepts(_ url: URL, for kind: NoteBlockKind) -> Bool {
        kind == .file || blockKind(for: url) == kind
    }

    static func contentTypes(for kind: NoteBlockKind) -> [UTType] {
        switch kind {
        case .image: return [.image]
        case .video: return [.movie, .video]
        case .audio: return [.audio]
        default: return [.item]
        }
    }

    static func isAnimatable(_ url: URL) -> Bool {
        ["gif", "png", "apng", "webp", "heics"].contains(url.pathExtension.lowercased())
    }
}
