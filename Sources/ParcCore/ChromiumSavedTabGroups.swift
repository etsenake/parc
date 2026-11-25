import Foundation

package struct ChromiumSavedTabGroup: Equatable {
    package struct Tab: Equatable {
        package let url: String
        package let title: String
        package let position: Int

        package init(url: String, title: String, position: Int) {
            self.url = url
            self.title = title
            self.position = position
        }
    }

    package let guid: String
    package let title: String
    package let color: Int
    package let position: Int
    package let tabs: [Tab]

    package init(guid: String, title: String, color: Int, position: Int, tabs: [Tab]) {
        self.guid = guid
        self.title = title
        self.color = color
        self.position = position
        self.tabs = tabs
    }
}

package enum ChromiumSavedTabGroups {
    package static func read(profileDirectory: URL) throws -> [ChromiumSavedTabGroup] { [] }
}
