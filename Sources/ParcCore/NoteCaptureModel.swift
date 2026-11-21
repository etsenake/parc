import Foundation

package struct NoteCaptureGeometry: Hashable, Codable {
    package var viewportWidth: Double
    package var viewportHeight: Double
    package var scrollX: Double
    package var scrollY: Double
    package var regionX: Double
    package var regionY: Double
    package var regionWidth: Double
    package var regionHeight: Double
    package var scrollers: String?

    package var isValid: Bool {
        [viewportWidth, viewportHeight, scrollX, scrollY, regionX, regionY, regionWidth, regionHeight]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && viewportWidth >= 1 && viewportHeight >= 1 && viewportWidth <= 16_384 && viewportHeight <= 16_384
            && regionX >= 0 && regionY >= 0 && regionWidth > 0 && regionHeight > 0
            && regionX + regionWidth <= viewportWidth + 1 && regionY + regionHeight <= viewportHeight + 1
            && scrollers.map { !$0.isEmpty && $0.utf8.count <= 24_576 } != false
    }

    package var aspectRatio: Double { regionWidth / regionHeight }

    package init(viewportWidth: Double, viewportHeight: Double, scrollX: Double, scrollY: Double,
         regionX: Double, regionY: Double, regionWidth: Double, regionHeight: Double, scrollers: String? = nil) {
        self.viewportWidth = viewportWidth; self.viewportHeight = viewportHeight
        self.scrollX = scrollX; self.scrollY = scrollY
        self.regionX = regionX; self.regionY = regionY; self.regionWidth = regionWidth; self.regionHeight = regionHeight
        self.scrollers = scrollers
    }

    package init?(viewport: String?, scroll: String?, region: String?, scrollers: String? = nil) {
        guard let viewport = Self.numbers(viewport, count: 2), let scroll = Self.numbers(scroll, count: 2),
              let region = Self.numbers(region, count: 4) else { return nil }
        self.init(viewportWidth: viewport[0], viewportHeight: viewport[1], scrollX: scroll[0], scrollY: scroll[1],
                  regionX: region[0], regionY: region[1], regionWidth: region[2], regionHeight: region[3], scrollers: scrollers)
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
    package var capturedAt: Date?
    package var geometry: NoteCaptureGeometry?
    package var live = false

    package static let sourceKey = "capture", dateKey = "captured", viewportKey = "viewport", scrollKey = "scroll", regionKey = "region"
    package static let scrollersKey = "scrollers"
    package static let liveFlag = "live"

    package var sourceAddress: URL? {
        guard let url = URL(string: sourceURL), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    package var canMakeLive: Bool { sourceAddress != nil && geometry?.isValid == true }

    package var attributes: [(String, String?)] {
        var items: [(String, String?)] = [(Self.sourceKey, sourceURL)]
        if let capturedAt { items.append((Self.dateKey, Self.dateFormatter.string(from: capturedAt))) }
        if let geometry, geometry.isValid {
            items += [(Self.viewportKey, geometry.viewportAttribute), (Self.scrollKey, geometry.scrollAttribute),
                      (Self.regionKey, geometry.regionAttribute)]
            if let scrollers = geometry.scrollers { items.append((Self.scrollersKey, scrollers)) }
            if live { items.append((Self.liveFlag, nil)) }
        }
        return items
    }

    package init(sourceURL: String, capturedAt: Date? = nil, geometry: NoteCaptureGeometry? = nil, live: Bool = false) {
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt.flatMap { $0.timeIntervalSinceReferenceDate.isFinite ? Self.wholeSeconds($0) : nil }
        self.geometry = geometry?.isValid == true ? geometry : nil
        self.live = live && self.geometry != nil
    }

    package init?(values: [String: String], flags: Set<String>) {
        guard let source = values[Self.sourceKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else { return nil }
        self.init(sourceURL: source, capturedAt: values[Self.dateKey].flatMap(Self.dateFormatter.date(from:)),
                  geometry: NoteCaptureGeometry(viewport: values[Self.viewportKey], scroll: values[Self.scrollKey],
                                                region: values[Self.regionKey], scrollers: values[Self.scrollersKey]),
                  live: flags.contains(Self.liveFlag))
    }

    package static func block(source: String, title: String, capture: NoteCapture) -> NoteBlock {
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

package enum NoteCaptureInsertion {
    package static func placement(in page: NotePage, caret: NoteBlockID?) -> NoteInsertion {
        if let caret, page.block(caret) != nil { return .after(caret) }
        return .top(page.blocks.count)
    }

    package static func replacesEmptyParagraph(_ id: NoteBlockID?, in page: NotePage) -> Bool {
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
