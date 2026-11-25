import Foundation

package struct SidebarImport: Equatable {
    package enum ProfileKey: Hashable { case standard; case custom(directory: String); case extra(String) }

    package struct Tab: Equatable {
        let title: String
        let url: String
        var customTitle: String? = nil
        var isMuted = false
        var isUnread = false

        package init(title: String, url: String, customTitle: String? = nil, isMuted: Bool = false, isUnread: Bool = false) {
            self.title = title
            self.url = url
            self.customTitle = customTitle
            self.isMuted = isMuted
            self.isUnread = isUnread
        }

        package static func web(url raw: String, title: String?, customTitle: String? = nil, isMuted: Bool = false,
                                isUnread: Bool = false) -> Tab? {
            let value = BrowserInternalURL.publicString(raw)
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
                  ["https", "http", "file"].contains(scheme) || (scheme == "parc" && raw.lowercased().hasPrefix("chrome://")),
                  scheme == "file" || url.host?.isEmpty == false else { return nil }
            let named = title.flatMap { $0.isEmpty ? nil : $0 }
            let custom = customTitle.flatMap { $0.isEmpty ? nil : $0 }
            return Tab(title: named ?? url.host ?? value, url: value, customTitle: custom, isMuted: isMuted, isUnread: isUnread)
        }
    }

    package indirect enum Item: Equatable {
        case tab(Tab)
        case folder(title: String, icon: SidebarGroupIcon?, children: [Item], isExpanded: Bool = true)
        case split(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation, widthFactors: [Double])
        case stackedSplit(title: String?, icon: SidebarGroupIcon?, tabs: [Tab], orientation: SplitOrientation, stacks: BrowserSplitStacks)

        var splitTabs: [Tab]? {
            switch self {
            case .split(_, _, let tabs, _, _), .stackedSplit(_, _, let tabs, _, _): return tabs
            case .tab, .folder: return nil
            }
        }
    }

    package enum SpacePlacement: Equatable { case new, profileHome }

    package struct Space: Equatable {
        let title: String?
        let icon: SidebarGroupIcon?
        let theme: SpaceTheme?
        let profile: ProfileKey
        let pinned: [Item]
        var id: String? = nil
        var today: [Item] = []
        var pinnedCollapsed = false
        var placement = SpacePlacement.new

        package init(title: String?, icon: SidebarGroupIcon?, theme: SpaceTheme?, profile: ProfileKey, pinned: [Item],
                     id: String? = nil, today: [Item] = [], pinnedCollapsed: Bool = false,
                     placement: SpacePlacement = .new) {
            self.title = title
            self.icon = icon
            self.theme = theme
            self.profile = profile
            self.pinned = pinned
            self.id = id
            self.today = today
            self.pinnedCollapsed = pinnedCollapsed
            self.placement = placement
        }
    }

    package struct ExtraProfile: Equatable {
        let key: ProfileKey
        let name: String

        package init(key: ProfileKey, name: String) {
            self.key = key
            self.name = name
        }
    }

    package struct ArchivedTab: Equatable {
        let tab: Tab
        let archivedAt: Date
        let reason: ArchiveReason
        let spaceID: String?
        let profile: ProfileKey

        package init(tab: Tab, archivedAt: Date, reason: ArchiveReason, spaceID: String?, profile: ProfileKey) {
            self.tab = tab
            self.archivedAt = archivedAt
            self.reason = reason
            self.spaceID = spaceID
            self.profile = profile
        }
    }

    package struct Route: Equatable {
        package struct Condition: Equatable {
            let style: LinkMatchStyle
            let pattern: String

            package init(style: LinkMatchStyle, pattern: String) {
                self.style = style
                self.pattern = pattern
            }
        }

        package enum Destination: Equatable { case mostRecent; case space(String); case profile(ProfileKey) }

        let conditions: [Condition]
        let destination: Destination

        package init(conditions: [Condition], destination: Destination) {
            self.conditions = conditions
            self.destination = destination
        }
    }

    let spaces: [Space]
    let favorites: [ProfileKey: [Item]]
    package var autoArchiveHours: [ProfileKey: Double] = [:]
    package var extraProfiles: [ExtraProfile] = []
    package var archive: [ArchivedTab] = []
    package var routes: [Route] = []
    package var warnings: [String] = []
    let skippedItemCount: Int
    private let favoriteOrder: [ProfileKey]

    package init(spaces: [Space], favorites: [(key: ProfileKey, items: [Item])] = [], extraProfiles: [ExtraProfile] = [],
                 archive: [ArchivedTab] = [], routes: [Route] = [], skippedItemCount: Int = 0) {
        var map: [ProfileKey: [Item]] = [:], order: [ProfileKey] = []
        for entry in favorites where map[entry.key] == nil {
            map[entry.key] = entry.items
            order.append(entry.key)
        }
        self.spaces = spaces
        self.favorites = map
        favoriteOrder = order
        self.extraProfiles = extraProfiles
        self.archive = archive
        self.routes = routes
        self.skippedItemCount = skippedItemCount
    }

    var profiles: [ProfileKey] {
        let referenced = spaces.map(\.profile) + favoriteOrder
        var result: [ProfileKey] = []
        for key in (referenced.contains(.standard) ? [.standard] : []) + referenced where !result.contains(key) {
            result.append(key)
        }
        return result
    }

    package static func merged(_ parts: [SidebarImport]) -> SidebarImport {
        var result = SidebarImport(spaces: parts.flatMap(\.spaces),
            favorites: parts.flatMap { part in part.favoriteOrder.compactMap { key in part.favorites[key].map { (key, $0) } } },
            extraProfiles: parts.flatMap(\.extraProfiles), archive: parts.flatMap(\.archive), routes: parts.flatMap(\.routes),
            skippedItemCount: parts.reduce(0) { $0 + $1.skippedItemCount })
        for part in parts {
            result.autoArchiveHours.merge(part.autoArchiveHours) { current, _ in current }
            result.warnings += part.warnings
        }
        return result
    }

    package static func profileKey(directory: String) -> ProfileKey {
        directory == "Default" ? .standard : .custom(directory: directory)
    }

    static let maximumDepth = 128
    static let maximumItems = 50_000
    static let maximumFavorites = 12
}
