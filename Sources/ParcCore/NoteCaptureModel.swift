import Foundation

package struct NoteCaptureGeometry: Hashable, Codable {
    var viewportWidth: Double
    var viewportHeight: Double
    var scrollX: Double
    var scrollY: Double
    var regionX: Double
    var regionY: Double
    var regionWidth: Double
    var regionHeight: Double
    var scrollers: String?
    var fullPage = false

    var isValid: Bool {
        [viewportWidth, viewportHeight, scrollX, scrollY, regionX, regionY, regionWidth, regionHeight]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && viewportWidth >= 1 && viewportHeight >= 1 && viewportWidth <= 16_384 && viewportHeight <= 16_384
            && regionX >= 0 && regionY >= 0 && regionWidth > 0 && regionHeight > 0
            && regionX + regionWidth <= viewportWidth + 1 && regionY + regionHeight <= viewportHeight + 1
            && scrollers.map { !$0.isEmpty && $0.utf8.count <= 24_576 } != false
    }

    var aspectRatio: Double { regionWidth / regionHeight }

    init(viewportWidth: Double, viewportHeight: Double, scrollX: Double, scrollY: Double,
         regionX: Double, regionY: Double, regionWidth: Double, regionHeight: Double, scrollers: String? = nil, fullPage: Bool = false) {
        self.viewportWidth = viewportWidth; self.viewportHeight = viewportHeight
        self.scrollX = scrollX; self.scrollY = scrollY
        self.regionX = regionX; self.regionY = regionY; self.regionWidth = regionWidth; self.regionHeight = regionHeight
        self.scrollers = scrollers
        self.fullPage = fullPage
    }

    init?(viewport: String?, scroll: String?, region: String?, scrollers: String? = nil, fullPage: Bool = false) {
        guard let viewport = Self.numbers(viewport, count: 2), let scroll = Self.numbers(scroll, count: 2),
              let region = Self.numbers(region, count: 4) else { return nil }
        self.init(viewportWidth: viewport[0], viewportHeight: viewport[1], scrollX: scroll[0], scrollY: scroll[1],
                  regionX: region[0], regionY: region[1], regionWidth: region[2], regionHeight: region[3], scrollers: scrollers,
                  fullPage: fullPage)
        guard isValid else { return nil }
    }

    package var viewportAttribute: String { Self.join([viewportWidth, viewportHeight]) }
    package var scrollAttribute: String { Self.join([scrollX, scrollY]) }
    package var regionAttribute: String { Self.join([regionX, regionY, regionWidth, regionHeight]) }

    private static func numbers(_ text: String?, count: Int) -> [Double]? {
        guard let parts = text?.split(separator: ",", omittingEmptySubsequences: false), parts.count == count else { return nil }
        let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return values.count == count && values.allSatisfy(\.isFinite) ? values : nil
    }

    private static func join(_ values: [Double]) -> String {
        values.map { value in
            let rounded = (value * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }.joined(separator: ",")
    }
}

package struct NoteCapture: Hashable, Codable {
    package var sourceURL: String
    var capturedAt: Date?
    package var geometry: NoteCaptureGeometry?
    package var live = false
    package var snapshot: String?

    static let sourceKey = "capture", dateKey = "captured", viewportKey = "viewport", scrollKey = "scroll", regionKey = "region"
    static let scrollersKey = "scrollers", snapshotKey = "snapshot"
    static let liveFlag = "live"
    static let fullPageFlag = "fullpage"

    package var sourceAddress: URL? {
        guard let url = URL(string: sourceURL), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    var canMakeLive: Bool { sourceAddress != nil && geometry?.isValid == true }

    var attributes: [(String, String?)] {
        var items: [(String, String?)] = [(Self.sourceKey, sourceURL)]
        if let capturedAt { items.append((Self.dateKey, Self.dateFormatter.string(from: capturedAt))) }
        if let geometry, geometry.isValid {
            items += [(Self.viewportKey, geometry.viewportAttribute), (Self.scrollKey, geometry.scrollAttribute),
                      (Self.regionKey, geometry.regionAttribute)]
            if let scrollers = geometry.scrollers { items.append((Self.scrollersKey, scrollers)) }
            if geometry.fullPage { items.append((Self.fullPageFlag, nil)) }
            if live { items.append((Self.liveFlag, nil)) }
        }
        if let snapshot { items.append((Self.snapshotKey, snapshot)) }
        return items
    }

    init(sourceURL: String, capturedAt: Date? = nil, geometry: NoteCaptureGeometry? = nil, live: Bool = false, snapshot: String? = nil) {
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? Self.wholeSeconds($0) : nil }
        self.geometry = geometry?.isValid == true ? geometry : nil
        self.live = live && self.geometry != nil
        self.snapshot = snapshot.flatMap(Self.validSnapshot)
    }

    static func validSnapshot(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 4096, trimmed.lowercased().hasSuffix(".pdf"),
              !trimmed.contains("://") || trimmed.lowercased().hasPrefix("file://") else { return nil }
        return trimmed
    }

    init?(values: [String: String], flags: Set<String>) {
        guard let source = values[Self.sourceKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
        self.init(sourceURL: source, capturedAt: values[Self.dateKey].flatMap(Self.dateFormatter.date(from:)),
                  geometry: NoteCaptureGeometry(viewport: values[Self.viewportKey], scroll: values[Self.scrollKey],
                                                region: values[Self.regionKey], scrollers: values[Self.scrollersKey],
                                                fullPage: flags.contains(Self.fullPageFlag)),
                  live: flags.contains(Self.liveFlag), snapshot: values[Self.snapshotKey])
    }

    static func block(source: String, title: String, capture: NoteCapture) -> NoteBlock {
        var props = NoteBlockProps()
        props.source = source
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        props.alt = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
        props.capture = capture
        return NoteBlock(.image, props: props)
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum NoteCaptureInsertion {
    static func placement(in page: NotePage, caret: NoteBlockID?) -> NoteInsertion {
        if let caret, page.block(caret) != nil { return .after(caret) }
        return .top(page.blocks.count)
    }

    static func replacesEmptyParagraph(_ id: NoteBlockID?, in page: NotePage) -> Bool {
        guard let id, let block = page.block(id) else { return false }
        return block.kind == .paragraph && block.text.isEmpty && block.children.isEmpty
    }
}

package enum NoteCaptureText {
    package static func displayHost(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    package static func title(for capture: NoteCapture, alt: String?, pageTitle: String? = nil) -> String {
        for candidate in [pageTitle, alt] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return capture.sourceAddress.map(displayHost) ?? "Webpage"
    }
}
