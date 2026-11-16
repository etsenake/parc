import Foundation

struct BlockedPageContent: Equatable {
    enum Kind: String { case popup, redirect }

    struct Item: Equatable, Identifiable {
        let kind: Kind
        let identifier: Int
        let url: URL?
        var id: String { kind.rawValue + ":" + String(identifier) }
        var title: String {
            let name = BlockedPageContent.displayName(url)
            return name.isEmpty ? (kind == .popup ? "Blank pop-up" : "Blank page") : name
        }
        var subtitle: String { kind == .popup ? "Pop-up" : "Redirect" }
        var actionTitle: String { kind == .popup ? "Open" : "Go" }
        var glyphName: String { kind == .popup ? "popup-blocked" : "redirect-blocked" }
        var actionHelp: String {
            kind == .popup ? "Open this pop-up" : "Go to the page this site tried to send you to"
        }
    }

    let revision: UInt
    let items: [Item]
    let site: URL?
    let allowed: Bool
    let canAllow: Bool

    init?(snapshot: [String: Any]?) {
        guard let snapshot, let revision = (snapshot["revision"] as? NSNumber)?.uintValue,
              let rows = snapshot["items"] as? [Any] else { return nil }
        let items = rows.compactMap { $0 as? [String: Any] }.compactMap { row -> Item? in
            guard let kind = (row["kind"] as? String).flatMap(Kind.init(rawValue:)),
                  let identifier = (row["identifier"] as? NSNumber)?.intValue else { return nil }
            return Item(kind: kind, identifier: identifier, url: (row["url"] as? String).flatMap(URL.init(string:)))
        }
        guard !items.isEmpty else { return nil }
        self.revision = revision
        self.items = items
        site = (snapshot["site"] as? String).flatMap(URL.init(string:))
        allowed = (snapshot["allowed"] as? NSNumber)?.boolValue ?? false
        canAllow = !allowed && (snapshot["canAllow"] as? NSNumber)?.boolValue == true
    }

    var displayItems: [Item] { items.filter { $0.kind == .redirect } + items.filter { $0.kind == .popup } }
    var popupCount: Int { items.filter { $0.kind == .popup }.count }
    var redirectCount: Int { items.count - popupCount }
    var glyphName: String { popupCount == 0 ? "redirect-blocked" : "popup-blocked" }
    var siteName: String { Self.displayName(site) }

    var summary: String {
        let popups = popupCount, redirects = redirectCount
        let popupText = popups == 1 ? (redirects == 0 ? "pop-up" : "a pop-up") : "\(popups) pop-ups"
        let redirectText = redirects == 1 ? "redirect" : "\(redirects) redirects"
        let text: String
        switch (popups, redirects) {
        case (0, _): text = redirectText + " blocked"
        case (_, 0): text = popupText + " blocked"
        default: text = popupText + " and " + (redirects == 1 ? "a redirect" : redirectText) + " blocked"
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var allowTitle: String { "Always Allow Pop-ups" }
    var allowDetail: String { siteName.isEmpty ? "" : "from " + siteName }
    var allowTooltip: String {
        "Allows pop-ups and redirects" + (siteName.isEmpty ? "" : " from " + siteName) + " until you change it in Settings"
    }
    static let allowHint = "Sign-in or payment window? Allow, then try again."
    static let allowedTitle = "Pop-ups allowed"
    static let allowedDetail = "Try again on the page"

    static func displayName(_ url: URL?) -> String {
        guard let url else { return "" }
        if let host = url.host(percentEncoded: false), !host.isEmpty { return host }
        return url.absoluteString
    }
}
