import Foundation

package enum EaselWebItemChrome {
    package enum State: Equatable {
        case snapshot(canGoLive: Bool)
        case live
        case page
    }

    static let headerHeight: Double = 38
    static let minimumHeaderWidth: Double = 320
    package static let makeLiveTitle = "Make live"
    package static let backToSnapshotTitle = "Back to snapshot"
    package static let makeLiveHelp = "Show this captured region from the live webpage"
    static let makeLivePageHelp = "Show the live webpage, ready to scroll"
    package static let backToSnapshotHelp = "Return to the original captured image"
    static let snapshotOnlyHelp = "Cropped, marked-up and Portrait-framed captures, and older cards, keep just their image."
    static let fullPageSnapshotHelp = "The image you captured. Make live shows the current webpage, ready to scroll."
    package static let liveHelp = "Showing the live webpage. The original captured image is kept."

    package static func makeLiveHelp(for item: EaselItem) -> String {
        item.captureLayout?.isFullPage == true ? makeLivePageHelp : makeLiveHelp
    }

    package static func liveEducation(fullPage: Bool, backTitle: String) -> String {
        (fullPage ? "See an up-to-date, interactive view of the page you captured, ready to scroll."
            : "See an up-to-date, interactive view of the region you captured.")
            + " This does not work on all sites. You can always return to the original screenshot with " + backTitle + "."
    }

    package static func canMakeLive(_ item: EaselItem) -> Bool {
        guard item.kind == .webCard, item.assetID != nil, let layout = item.captureLayout, layout.isValid,
              let raw = item.url, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func state(of item: EaselItem) -> State? {
        switch item.kind {
        case .browser: return .page
        case .webCard where item.ownsEmbeddedPage: return .live
        case .webCard where item.assetID != nil: return .snapshot(canGoLive: canMakeLive(item))
        default: return nil
        }
    }

    package static func isSnapshot(_ item: EaselItem) -> Bool {
        if case .snapshot = state(of: item) { return true }
        return false
    }

    package static func badge(for item: EaselItem, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String? {
        switch state(of: item) {
        case .live: return "Live"
        case .snapshot(let canGoLive):
            let name = canGoLive ? "Snapshot" : "Snapshot only"
            guard let date = item.capturedAt else { return name }
            return name + " · captured " + capturedPhrase(date, now: now, calendar: calendar, locale: locale)
        case .page, nil: return nil
        }
    }

    package static func badgeHelp(for item: EaselItem) -> String? {
        switch state(of: item) {
        case .live: return liveHelp
        case .snapshot(let canGoLive):
            guard canGoLive else { return snapshotOnlyHelp }
            return item.captureLayout?.isFullPage == true ? fullPageSnapshotHelp
                : "The image you captured. Make live shows the same region from the current webpage."
        case .page, nil: return nil
        }
    }

    static func capturedPhrase(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = locale; formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }

    package static func title(for item: EaselItem, pageTitle: String? = nil) -> String {
        let live = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !live.isEmpty { return live }
        let saved = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        return item.url.flatMap(URL.init(string:)).map(displayHost) ?? "Webpage"
    }

    package static func displayHost(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    package static func headerFrame(item: EaselRect, visible: EaselRect, height: Double = headerHeight,
                            minimumWidth: Double = minimumHeaderWidth) -> EaselRect {
        let width = max(item.width, min(minimumWidth, max(visible.width, 1)))
        var x = item.x + (item.width - width) / 2
        x = min(max(x, visible.x), max(visible.x, visible.x + visible.width - width))
        let y: Double
        if item.height >= height {
            y = min(max(item.y, visible.y), item.y + item.height - height)
        } else if item.y - height >= visible.y {
            y = item.y - height
        } else {
            y = item.y + item.height
        }
        return EaselRect(x: x, y: y, width: width, height: height)
    }
}

package enum EmbeddedPageStatusText {
    package static func friendly(_ text: String, document: String) -> String {
        switch text {
        case "Loading webpage…": return "Waking the page up…"
        case "Webpage closed": return "This page closed. Give it another go?"
        case "This webpage owner is unavailable.": return "Live pages wake up when the \(document) is open in a window."
        case "Positioning live capture…": return "Lining up the region you captured…"
        case "This page could not align with the captured region.": return "This page has changed, so the region you captured can't line up. Try again, or go back to the snapshot."
        case "Live capture is unavailable for this page.": return "This page can't show the region live. Try again, or go back to the snapshot."
        default: return text
        }
    }
}
