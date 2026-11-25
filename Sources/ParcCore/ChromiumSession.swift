import Foundation

package struct ChromiumToken: Hashable, Sendable {
    package let high: UInt64
    package let low: UInt64

    package init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }
}

package struct ChromiumSession: Equatable {
    package struct Tab: Equatable {
        package var id: Int32
        package var url: String
        package var title: String
        package var pinned = false
        package var group: ChromiumToken? = nil
        package var split: ChromiumToken? = nil
        package var extraData: [String: String] = [:]

        package init(id: Int32, url: String, title: String, pinned: Bool = false, group: ChromiumToken? = nil,
                     split: ChromiumToken? = nil, extraData: [String: String] = [:]) {
            self.id = id
            self.url = url
            self.title = title
            self.pinned = pinned
            self.group = group
            self.split = split
            self.extraData = extraData
        }
    }

    package struct Window: Equatable {
        package var id: Int32
        package var userTitle: String? = nil
        package var selectedIndex = 0
        package var tabs: [Tab] = []
        package var extraData: [String: String] = [:]

        package init(id: Int32, userTitle: String? = nil, selectedIndex: Int = 0, tabs: [Tab] = [],
                     extraData: [String: String] = [:]) {
            self.id = id
            self.userTitle = userTitle
            self.selectedIndex = selectedIndex
            self.tabs = tabs
            self.extraData = extraData
        }
    }

    package struct Group: Equatable {
        package var title: String
        package var color: Int
        package var collapsed: Bool
        package var savedGUID: String?

        package init(title: String, color: Int, collapsed: Bool, savedGUID: String? = nil) {
            self.title = title
            self.color = color
            self.collapsed = collapsed
            self.savedGUID = savedGUID
        }
    }

    package struct Split: Equatable {
        package var ratio: Double
        package var sideBySide: Bool

        package init(ratio: Double, sideBySide: Bool) {
            self.ratio = ratio
            self.sideBySide = sideBySide
        }
    }

    package struct ClosedTab: Equatable {
        package var url: String
        package var title: String
        package var closedAt: Date?

        package init(url: String, title: String, closedAt: Date?) {
            self.url = url
            self.title = title
            self.closedAt = closedAt
        }
    }

    package var windows: [Window] = []
    package var groups: [ChromiumToken: Group] = [:]
    package var splits: [ChromiumToken: Split] = [:]
    package var closedTabs: [ClosedTab] = []

    package init(windows: [Window] = [], groups: [ChromiumToken: Group] = [:], splits: [ChromiumToken: Split] = [:],
                 closedTabs: [ClosedTab] = []) {
        self.windows = windows
        self.groups = groups
        self.splits = splits
        self.closedTabs = closedTabs
    }
}
