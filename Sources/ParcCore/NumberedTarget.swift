import Foundation

enum NumberedTarget {
    static let excludeFavoritesKey = "excludeFavoritesInSwitchToNthTab"
    static let ninthItemKey = "switchToNinthSidebarItemEnabled"
    static let numbers = 1...9

    static func itemBindingID(_ number: Int) -> String { "item\(number)" }
    static func spaceBindingID(_ number: Int) -> String { "space\(number)" }
    static func itemNumber(_ id: String) -> Int? {
        guard let value = number(id, prefix: "item"), numbers.contains(value) else { return nil }
        return value
    }
    static func spaceNumber(_ id: String) -> Int? { number(id, prefix: "space") }
    private static func number(_ id: String, prefix: String) -> Int? {
        guard id.hasPrefix(prefix), let value = Int(id.dropFirst(prefix.count)),
              value > 0, id == prefix + String(value) else { return nil }
        return value
    }

    static func description(for id: String, excludeFavorites: Bool, ninthItemEnabled: Bool) -> String? {
        if let number = itemNumber(id) {
            if number == 9, !ninthItemEnabled { return "Jumps to the last item at the bottom of your Sidebar." }
            let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
            let suffix = excludeFavorites ? "after your Favorites at the top." : "starting with your Favorites at the top."
            return "Jumps to the \(ordinals[number - 1]) item in your Sidebar, \(suffix)"
        }
        if let number = spaceNumber(id) {
            let formatter = NumberFormatter(); formatter.numberStyle = .ordinal
            let ordinal = formatter.string(from: NSNumber(value: number)) ?? String(number)
            return "Jumps over to your \(ordinal) Space without needing to swipe."
        }
        return nil
    }

    static func destination<Item>(_ items: [Item], number: Int, ninthItemEnabled: Bool) -> Item? {
        guard numbers.contains(number) else { return nil }
        if number == 9, !ninthItemEnabled { return items.last }
        return items.indices.contains(number - 1) ? items[number - 1] : nil
    }
}
