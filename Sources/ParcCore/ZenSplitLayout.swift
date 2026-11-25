import Foundation

indirect enum ZenSplitLayout {
    typealias Item = SidebarImport.Item
    typealias Tab = SidebarImport.Tab

    case leaf(String, Double)
    case splitter(SplitOrientation, Double, [ZenSplitLayout])

    var size: Double {
        switch self {
        case .leaf(_, let size), .splitter(_, let size, _): return size
        }
    }

    static func parse(_ value: Any?, depth: Int) -> ZenSplitLayout? {
        guard depth < 16, let node = value as? [String: Any] else { return nil }
        let raw = (node["sizeInParent"] as? NSNumber)?.doubleValue ?? 1
        let size = raw.isFinite && raw > 0 ? raw : 1
        switch node["type"] as? String {
        case "leaf":
            return (node["tabId"] as? String).map { .leaf($0, size) }
        case "splitter":
            let children = (node["children"] as? [Any] ?? []).compactMap { parse($0, depth: depth + 1) }
            guard !children.isEmpty else { return nil }
            return .splitter(node["direction"] as? String == "column" ? .vertical : .horizontal, size, children)
        default:
            return nil
        }
    }

    static func grid(_ type: String?, ids: [String]) -> ZenSplitLayout {
        let leaves = ids.map { ZenSplitLayout.leaf($0, 1) }
        switch type {
        case "hsep": return .splitter(.vertical, 1, leaves)
        case "vsep": return .splitter(.horizontal, 1, leaves)
        default:
            switch leaves.count {
            case 3: return .splitter(.horizontal, 1, [leaves[0], .splitter(.vertical, 1, Array(leaves[1...]))])
            case 4: return .splitter(.vertical, 1, [.splitter(.horizontal, 1, Array(leaves[..<2])),
                                                    .splitter(.horizontal, 1, Array(leaves[2...]))])
            default: return .splitter(.horizontal, 1, leaves)
            }
        }
    }

    func resized(_ size: Double) -> ZenSplitLayout {
        switch self {
        case .leaf(let id, _): return .leaf(id, size)
        case .splitter(let orientation, _, let children): return .splitter(orientation, size, children)
        }
    }

    func pruned(keeping ids: inout Set<String>) -> ZenSplitLayout? {
        switch self {
        case .leaf(let id, _):
            return ids.remove(id) == nil ? nil : self
        case .splitter(let orientation, let size, let children):
            var kept: [ZenSplitLayout] = []
            for child in children {
                if let child = child.pruned(keeping: &ids) { kept.append(child) }
            }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0].resized(size) }
            return .splitter(orientation, size, kept)
        }
    }

    func leaves(weight: Double) -> [(id: String, weight: Double)] {
        switch self {
        case .leaf(let id, _): return [(id, weight)]
        case .splitter(_, _, let children):
            let total = children.reduce(0) { $0 + $1.size }
            return children.flatMap { $0.leaves(weight: weight * $0.size / total) }
        }
    }

    func items(tabs: [String: Tab]) -> [Item] {
        let flat = leaves(weight: 1)
        guard case .splitter(let orientation, _, let children) = self else {
            return flat.compactMap { leaf in tabs[leaf.id].map(Item.tab) }
        }
        let deeper = children.contains { child in
            guard case .splitter(_, _, let grandchildren) = child else { return false }
            return grandchildren.contains { if case .splitter = $0 { return true }; return false }
        }
        if flat.count <= 4, !deeper {
            var units: [(tabs: [Tab], factor: Double, stack: [Double])] = []
            for child in children {
                switch child {
                case .leaf(let id, let size):
                    if let tab = tabs[id] { units.append(([tab], size, [1])) }
                case .splitter(let inner, let size, let grandchildren):
                    let members = grandchildren.compactMap { node -> (tab: Tab, size: Double)? in
                        guard case .leaf(let id, let share) = node, let tab = tabs[id] else { return nil }
                        return (tab, share)
                    }
                    if inner == orientation {
                        let total = members.reduce(0) { $0 + $1.size }
                        for member in members { units.append(([member.tab], size * member.size / total, [1])) }
                    } else {
                        units.append((members.map(\.tab), size, members.map(\.size)))
                    }
                }
            }
            let shaped = BrowserSplitLayout.shape(orientation: orientation, sizes: units.map(\.tabs.count),
                                                  factors: units.map(\.factor), stackFactors: units.map(\.stack))
            let all = units.flatMap(\.tabs)
            if let stacks = shaped.stacks {
                return [.stackedSplit(title: nil, icon: nil, tabs: all, orientation: shaped.orientation, stacks: stacks)]
            }
            return [.split(title: nil, icon: nil, tabs: all, orientation: shaped.orientation, widthFactors: shaped.widthFactors)]
        }
        let members = flat.compactMap { leaf in tabs[leaf.id].map { (tab: $0, weight: leaf.weight) } }
        let head = Array(members.prefix(4)), rest = members.dropFirst(4).map { Item.tab($0.tab) }
        let factors = BrowserSplitLayout.normalized(head.map(\.weight), count: head.count)
            ?? Array(repeating: 1 / Double(head.count), count: head.count)
        return [.split(title: nil, icon: nil, tabs: head.map(\.tab), orientation: orientation, widthFactors: factors)] + rest
    }
}
