import Foundation

struct EaselMermaidSize: Equatable {
    var width: Double
    var height: Double
}

typealias EaselMermaidMeasure = (_ text: String, _ maximumWidth: Double) -> EaselMermaidSize

struct EaselMermaidLayout: Equatable {
    var nodes: [String: EaselRect] = [:]
    var groups: [String: EaselRect] = [:]
    var edgeDirections: [Int: EaselMermaidDirection] = [:]
    var width = 0.0
    var height = 0.0
}

struct EaselMermaidDrawing: Equatable {
    var items: [EaselItem]
    var width: Double
    var height: Double
    var headings: Set<UUID> = []

    func moved(by dx: Double, _ dy: Double) -> EaselMermaidDrawing {
        var copy = self
        for index in copy.items.indices {
            copy.items[index].frame.x += dx
            copy.items[index].frame.y += dy
        }
        return copy
    }
}

enum EaselMermaidLayoutEngine {
    static let nodeGap = 56.0
    static let rankGap = 84.0
    static let edgeGap = 24.0
    static let sectionPadding = 32.0
    static let sectionTitleBand = 48.0
    static let minimumSection = EaselMermaidSize(width: 200, height: 120)
    static let dummyBudget = 12_000

    struct Edge: Equatable {
        var from: Int
        var to: Int
        var length = 1
        var label: EaselMermaidSize?
    }

    private struct Graph {
        let diagram: EaselMermaidDiagram
        let nodeCount: Int
        var container: [Int?] = []
        var order: [Double] = []
        var children: [Int: [Int]] = [:]
        var topLevel: [Int] = []
        var nodeLookup: [String: Int] = [:]
        var groupLookup: [String: Int] = [:]
        var edgesByLevel: [Int: [(index: Int, from: Int, to: Int)]] = [:]

        init(_ diagram: EaselMermaidDiagram) {
            self.diagram = diagram
            nodeCount = diagram.nodes.count
            for (index, node) in diagram.nodes.enumerated() where nodeLookup[node.id] == nil { nodeLookup[node.id] = index }
            for (index, group) in diagram.groups.enumerated() where groupLookup[group.id] == nil { groupLookup[group.id] = nodeCount + index }
            container = diagram.nodes.map { node in node.group.flatMap { groupLookup[$0] } }
                + diagram.groups.enumerated().map { index, group in
                    group.parent.flatMap { groupLookup[$0] }.flatMap { $0 == nodeCount + index ? nil : $0 }
                }
            order = (0..<(nodeCount + diagram.groups.count)).map { Double($0) + ($0 >= nodeCount ? 0.5 : 0) }
            for node in 0..<nodeCount {
                var current = container[node], steps = 0
                while let group = current, steps <= diagram.groups.count {
                    order[group] = min(order[group], Double(node) - 0.5)
                    current = container[group]; steps += 1
                }
            }
            for element in 0..<container.count {
                if let parent = container[element] { children[parent, default: []].append(element) } else { topLevel.append(element) }
            }
            let rank = order
            topLevel.sort { rank[$0] < rank[$1] }
            for key in children.keys { children[key]?.sort { rank[$0] < rank[$1] } }
            for (index, edge) in diagram.edges.enumerated() {
                guard let a = resolve(edge.from), let b = resolve(edge.to) else { continue }
                let above = Set(ancestors(of: b))
                guard let level = ancestors(of: a).first(where: { above.contains($0) }),
                      let first = representative(a, in: level), let second = representative(b, in: level) else { continue }
                edgesByLevel[level ?? -1, default: []].append((index, first, second))
            }
        }

        func ancestors(of element: Int) -> [Int?] {
            var result: [Int?] = [], current = container[element], steps = 0
            while let group = current, steps <= container.count {
                result.append(group); current = container[group]; steps += 1
            }
            result.append(nil)
            return result
        }

        func resolve(_ id: String) -> Int? { nodeLookup[id] ?? groupLookup[id] }

        func representative(_ element: Int, in level: Int?) -> Int? {
            var current = element, steps = 0
            while container[current] != level {
                guard let parent = container[current], steps <= container.count else { return nil }
                current = parent; steps += 1
            }
            return current
        }

        func members(of level: Int?) -> [Int] { level.map { children[$0] ?? [] } ?? topLevel }
    }

    static func layout(_ diagram: EaselMermaidDiagram, nodeSizes: [String: EaselMermaidSize],
                       labelSizes: [Int: EaselMermaidSize]) -> EaselMermaidLayout {
        let graph = Graph(diagram)
        var directions: [Int: EaselMermaidDirection] = [:]
        let result = level(nil, direction: diagram.direction, graph: graph, nodeSizes: nodeSizes,
                           labelSizes: labelSizes, directions: &directions, depth: 0)
        var layout = EaselMermaidLayout(edgeDirections: directions, width: result.size.width, height: result.size.height)
        for (element, frame) in result.frames {
            if element < graph.nodeCount { layout.nodes[diagram.nodes[element].id] = frame }
            else { layout.groups[diagram.groups[element - graph.nodeCount].id] = frame }
        }
        return layout
    }

    private static func level(_ group: Int?, direction: EaselMermaidDirection, graph: Graph, nodeSizes: [String: EaselMermaidSize],
                              labelSizes: [Int: EaselMermaidSize], directions: inout [Int: EaselMermaidDirection],
                              depth: Int) -> (frames: [Int: EaselRect], size: EaselMermaidSize) {
        let members = graph.members(of: group)
        var sizes: [EaselMermaidSize] = [], inner: [Int: (frames: [Int: EaselRect], size: EaselMermaidSize)] = [:]
        var position: [Int: Int] = [:]
        for (index, element) in members.enumerated() {
            position[element] = index
            if element >= graph.nodeCount {
                let child = graph.diagram.groups[element - graph.nodeCount]
                let content = depth < 24
                    ? level(element, direction: child.direction ?? direction, graph: graph, nodeSizes: nodeSizes,
                            labelSizes: labelSizes, directions: &directions, depth: depth + 1)
                    : (frames: [:], size: EaselMermaidSize(width: 0, height: 0))
                inner[element] = content
                sizes.append(EaselMermaidSize(width: max(minimumSection.width, content.size.width + 2 * sectionPadding),
                                              height: max(minimumSection.height, content.size.height + sectionTitleBand + sectionPadding)))
            } else {
                sizes.append(nodeSizes[graph.diagram.nodes[element].id] ?? EaselMermaidSize(width: 128, height: 60))
            }
        }
        var edges: [Edge] = []
        for entry in graph.edgesByLevel[group ?? -1] ?? [] {
            directions[entry.index] = direction
            guard entry.from != entry.to, let from = position[entry.from], let to = position[entry.to] else { continue }
            edges.append(Edge(from: from, to: to, length: graph.diagram.edges[entry.index].length, label: labelSizes[entry.index]))
        }
        let placed = layered(sizes: sizes, edges: edges, direction: direction)
        var frames: [Int: EaselRect] = [:]
        for (index, element) in members.enumerated() {
            let center = placed.centers[index], size = sizes[index]
            let frame = EaselRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            frames[element] = frame
            guard let content = inner[element] else { continue }
            let dx = frame.x + (frame.width - content.size.width) / 2, dy = frame.y + sectionTitleBand
            for (child, rect) in content.frames {
                frames[child] = EaselRect(x: rect.x + dx, y: rect.y + dy, width: rect.width, height: rect.height)
            }
        }
        return (frames, placed.size)
    }

    static func layered(sizes: [EaselMermaidSize], edges: [Edge], direction: EaselMermaidDirection) -> (centers: [EaselPoint], size: EaselMermaidSize) {
        guard !sizes.isEmpty else { return ([], EaselMermaidSize(width: 0, height: 0)) }
        let vertical = direction.isVertical
        let cross = sizes.map { vertical ? $0.width : $0.height }, rank = sizes.map { vertical ? $0.height : $0.width }
        let turned = edges.map { edge in
            Edge(from: edge.from, to: edge.to, length: edge.length,
                 label: edge.label.map { vertical ? $0 : EaselMermaidSize(width: $0.height, height: $0.width) })
        }
        let solved = arrange(cross: cross, rank: rank, edges: turned)
        var centers = zip(solved.cross, solved.rank).map { value -> EaselPoint in
            switch direction {
            case .down: return EaselPoint(x: value.0, y: value.1)
            case .up: return EaselPoint(x: value.0, y: -value.1)
            case .right: return EaselPoint(x: value.1, y: value.0)
            case .left: return EaselPoint(x: -value.1, y: value.0)
            }
        }
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for (center, size) in zip(centers, sizes) {
            minX = min(minX, center.x - size.width / 2); maxX = max(maxX, center.x + size.width / 2)
            minY = min(minY, center.y - size.height / 2); maxY = max(maxY, center.y + size.height / 2)
        }
        for index in centers.indices { centers[index].x -= minX; centers[index].y -= minY }
        return (centers, EaselMermaidSize(width: maxX - minX, height: maxY - minY))
    }

    static func arrange(cross: [Double], rank: [Double], edges: [Edge]) -> (cross: [Double], rank: [Double]) {
        let count = cross.count
        let links = edges.filter { $0.from != $0.to && (0..<count).contains($0.from) && (0..<count).contains($0.to) }
        var outgoing = Array(repeating: [Int](), count: count)
        for (index, link) in links.enumerated() { outgoing[link.from].append(index) }
        var state = Array(repeating: 0, count: count), reversed = Array(repeating: false, count: links.count)
        for root in 0..<count where state[root] == 0 {
            state[root] = 1
            var stack = [(node: root, next: 0)]
            while let top = stack.last {
                if top.next < outgoing[top.node].count {
                    stack[stack.count - 1].next += 1
                    let index = outgoing[top.node][top.next], target = links[index].to
                    if state[target] == 1 { reversed[index] = true }
                    else if state[target] == 0 { state[target] = 1; stack.append((target, 0)) }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }
        let dag = links.enumerated().map { index, link in
            reversed[index] ? Edge(from: link.to, to: link.from, length: link.length, label: link.label) : link
        }
        var successors = Array(repeating: [Int](), count: count), predecessors = Array(repeating: [Int](), count: count)
        for (index, edge) in dag.enumerated() { successors[edge.from].append(index); predecessors[edge.to].append(index) }
        var indegree = predecessors.map(\.count), queue = (0..<count).filter { indegree[$0] == 0 }, head = 0
        while head < queue.count {
            let node = queue[head]; head += 1
            for index in successors[node] {
                let target = dag[index].to
                indegree[target] -= 1
                if indegree[target] == 0 { queue.append(target) }
            }
        }
        if queue.count < count { queue += (0..<count).filter { indegree[$0] > 0 } }
        var level = Array(repeating: 0, count: count)
        for node in queue {
            for index in successors[node] {
                let edge = dag[index]
                level[edge.to] = max(level[edge.to], level[node] + 2 * max(1, edge.length))
            }
        }
        for node in queue.reversed() where !successors[node].isEmpty && successors[node].count > predecessors[node].count {
            let limit = successors[node].map { level[dag[$0].to] - 2 * max(1, dag[$0].length) }.min() ?? level[node]
            if limit > level[node] { level[node] = limit }
        }
        let lowest = level.min() ?? 0
        level = level.map { $0 - lowest }

        var sizeCross = cross, sizeRank = rank, dummy = Array(repeating: false, count: count), layerOf = level
        var segments: [(upper: Int, lower: Int, weight: Double)] = []
        func weight(_ a: Int, _ b: Int) -> Double { dummy[a] && dummy[b] ? 8 : dummy[a] || dummy[b] ? 2 : 1 }
        let spans = dag.map { max(0, level[$0.to] - level[$0.from] - 1) }
        var kept = Set<Int>(), budget = dummyBudget
        for index in dag.indices.sorted(by: { (spans[$0], $0) < (spans[$1], $1) }) where spans[index] <= budget {
            kept.insert(index); budget -= spans[index]
        }
        for (edgeIndex, edge) in dag.enumerated() where kept.contains(edgeIndex) {
            let start = layerOf[edge.from], end = layerOf[edge.to]
            var previous = edge.from
            if end - start > 1 {
                let middle = start + (end - start) / 2
                for layer in (start + 1)..<end {
                    let index = sizeCross.count
                    let label = layer == middle ? edge.label : nil
                    sizeCross.append(label?.width ?? 0); sizeRank.append(label?.height ?? 0)
                    dummy.append(true); layerOf.append(layer)
                    segments.append((previous, index, weight(previous, index)))
                    previous = index
                }
            }
            segments.append((previous, edge.to, weight(previous, edge.to)))
        }
        let total = sizeCross.count, layerCount = (layerOf.max() ?? 0) + 1
        var upper = Array(repeating: [(node: Int, weight: Double)](), count: total), lower = upper
        for segment in segments {
            lower[segment.upper].append((segment.lower, segment.weight))
            upper[segment.lower].append((segment.upper, segment.weight))
        }

        var layers = Array(repeating: [Int](), count: layerCount), seen = Array(repeating: false, count: total)
        for root in (0..<count).sorted(by: { (layerOf[$0], $0) < (layerOf[$1], $1) }) where !seen[root] {
            var stack = [root]
            while let node = stack.popLast() {
                if seen[node] { continue }
                seen[node] = true
                layers[layerOf[node]].append(node)
                for child in lower[node].reversed() where !seen[child.node] { stack.append(child.node) }
            }
        }
        for node in 0..<total where !seen[node] { layers[layerOf[node]].append(node) }
        var position = Array(repeating: 0, count: total)
        func reindex() { for layer in layers { for (index, node) in layer.enumerated() { position[node] = index } } }
        reindex()

        func crossings() -> Int {
            var result = 0
            for layer in 0..<max(0, layerCount - 1) {
                var pairs: [(Int, Int)] = []
                for node in layers[layer] { for child in lower[node] { pairs.append((position[node], position[child.node])) } }
                pairs.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
                let size = layers[layer + 1].count
                var tree = Array(repeating: 0, count: size + 1), inserted = 0
                for pair in pairs {
                    var index = pair.1 + 1, below = 0
                    while index > 0 { below += tree[index]; index -= index & -index }
                    result += inserted - below
                    index = pair.1 + 1
                    while index <= size { tree[index] += 1; index += index & -index }
                    inserted += 1
                }
            }
            return result
        }

        func reorder(_ layer: Int, fromAbove: Bool) {
            let nodes = layers[layer]
            var movable: [(node: Int, value: Double, original: Int)] = [], fixed = Set<Int>()
            for (index, node) in nodes.enumerated() {
                let neighbours = fromAbove ? upper[node] : lower[node]
                guard !neighbours.isEmpty else { fixed.insert(index); continue }
                var sum = 0.0, weights = 0.0
                for neighbour in neighbours { sum += Double(position[neighbour.node]) * neighbour.weight; weights += neighbour.weight }
                movable.append((node, sum / weights, index))
            }
            movable.sort { $0.value != $1.value ? $0.value < $1.value : $0.original < $1.original }
            var result: [Int] = [], cursor = 0
            for index in nodes.indices {
                if fixed.contains(index) { result.append(nodes[index]) } else { result.append(movable[cursor].node); cursor += 1 }
            }
            layers[layer] = result
            for (index, node) in result.enumerated() { position[node] = index }
        }

        func pairCrossings(_ left: Int, _ right: Int) -> Int {
            var result = 0
            for a in upper[left] { for b in upper[right] where position[a.node] > position[b.node] { result += 1 } }
            for a in lower[left] { for b in lower[right] where position[a.node] > position[b.node] { result += 1 } }
            return result
        }

        func transpose() {
            var improved = true, passes = 0
            while improved && passes < 4 {
                improved = false; passes += 1
                for layer in 0..<layerCount where layers[layer].count > 1 {
                    for index in 0..<(layers[layer].count - 1) {
                        let a = layers[layer][index], b = layers[layer][index + 1]
                        if pairCrossings(b, a) < pairCrossings(a, b) {
                            layers[layer].swapAt(index, index + 1)
                            position[a] = index + 1; position[b] = index
                            improved = true
                        }
                    }
                }
            }
        }

        var best = layers, bestCount = crossings(), stall = 0
        let large = total > 4_000
        if bestCount > 0 {
            for iteration in 0..<(large ? 8 : 24) {
                if iteration % 2 == 0 {
                    for layer in stride(from: 1, to: layerCount, by: 1) { reorder(layer, fromAbove: true) }
                } else {
                    for layer in stride(from: layerCount - 2, through: 0, by: -1) { reorder(layer, fromAbove: false) }
                }
                if total <= 400 { transpose() }
                let current = crossings()
                if current < bestCount { best = layers; bestCount = current; stall = 0 } else { stall += 1 }
                if bestCount == 0 || stall >= 4 { break }
            }
        }
        layers = best
        reindex()

        func gap(_ a: Int, _ b: Int) -> Double {
            dummy[a] && dummy[b] ? edgeGap : dummy[a] || dummy[b] ? (edgeGap + nodeGap) / 2 : nodeGap
        }
        var coordinate = Array(repeating: 0.0, count: total)
        for nodes in layers {
            var x = 0.0
            for (index, node) in nodes.enumerated() {
                if index > 0 { x += (sizeCross[nodes[index - 1]] + sizeCross[node]) / 2 + gap(nodes[index - 1], node) }
                coordinate[node] = x
            }
            for node in nodes { coordinate[node] -= x / 2 }
        }
        for iteration in 0..<(large ? 9 : 18) {
            let mode = iteration % 3
            let sweep = mode == 1 ? Array((0..<layerCount).reversed()) : Array(0..<layerCount)
            for layer in sweep where !layers[layer].isEmpty {
                let nodes = layers[layer]
                var desired: [Double] = [], weights: [Double] = [], gaps: [Double] = []
                for (index, node) in nodes.enumerated() {
                    let neighbours = mode == 0 ? upper[node] : mode == 1 ? lower[node] : upper[node] + lower[node]
                    var sum = 0.0, total = 0.0
                    for neighbour in neighbours { sum += coordinate[neighbour.node] * neighbour.weight; total += neighbour.weight }
                    desired.append(total > 0 ? sum / total : coordinate[node])
                    weights.append(total > 0 ? total : 0.01)
                    if index > 0 { gaps.append((sizeCross[nodes[index - 1]] + sizeCross[node]) / 2 + gap(nodes[index - 1], node)) }
                }
                for (index, value) in isotonic(desired, weights: weights, gaps: gaps).enumerated() { coordinate[nodes[index]] = value }
            }
        }

        var thickness = Array(repeating: 0.0, count: layerCount)
        for node in 0..<total { thickness[layerOf[node]] = max(thickness[layerOf[node]], sizeRank[node]) }
        var centers = Array(repeating: 0.0, count: layerCount), top = 0.0
        for layer in 0..<layerCount {
            centers[layer] = top + thickness[layer] / 2
            top += thickness[layer] + rankGap / 2
        }
        return ((0..<count).map { coordinate[$0] }, (0..<count).map { centers[layerOf[$0]] })
    }

    static func isotonic(_ desired: [Double], weights: [Double], gaps: [Double]) -> [Double] {
        guard !desired.isEmpty, weights.count == desired.count, gaps.count == desired.count - 1 else { return desired }
        var offsets = [0.0]
        for gap in gaps { offsets.append(offsets[offsets.count - 1] + gap) }
        var blocks: [(weight: Double, total: Double, count: Int)] = []
        for index in desired.indices {
            let weight = max(weights[index], 1e-6)
            blocks.append((weight, weight * (desired[index] - offsets[index]), 1))
            while blocks.count > 1 {
                let last = blocks[blocks.count - 1], previous = blocks[blocks.count - 2]
                guard previous.total / previous.weight > last.total / last.weight else { break }
                blocks.removeLast(2)
                blocks.append((previous.weight + last.weight, previous.total + last.total, previous.count + last.count))
            }
        }
        var result: [Double] = [], index = 0
        for block in blocks {
            let mean = block.total / block.weight
            for _ in 0..<block.count { result.append(mean + offsets[index]); index += 1 }
        }
        return result
    }
}

extension EaselMermaid {
    static let textWidth = 220.0
    static let labelWidth = 180.0
    static let thickStroke = 6.0
    static let doubleStroke = 5.0

    static func estimate(_ text: String, maximumWidth: Double) -> EaselMermaidSize {
        let character = 8.2, lineHeight = 20.0, limit = max(character, maximumWidth)
        var lines = 0, widest = 0.0
        for paragraph in text.components(separatedBy: "\n") {
            lines += 1
            var current = 0.0
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                var width = Double(word.count) * character
                if width > limit {
                    if current > 0 { lines += 1 }
                    let extra = Int((width / limit).rounded(.up)) - 1
                    lines += extra
                    widest = limit
                    width -= Double(extra) * limit
                    current = width
                    continue
                }
                let next = current == 0 ? width : current + character + width
                if next > limit, current > 0 {
                    widest = max(widest, current); lines += 1; current = width
                } else {
                    current = next
                }
            }
            widest = max(widest, current)
        }
        return EaselMermaidSize(width: min(limit, widest), height: Double(max(1, lines)) * lineHeight)
    }

    static func displayText(_ node: EaselMermaidNode) -> String {
        guard node.shape == .entity, !node.attributes.isEmpty else { return node.label }
        return ([node.label] + node.attributes.map(\.line)).joined(separator: "\n")
    }

    static func appearance(_ shape: EaselMermaidShape) -> (kind: EaselItemKind, shape: EaselShape?, flipped: Bool, strokeWidth: Double?) {
        switch shape {
        case .rectangle, .entity: return (.rectangle, nil, false, nil)
        case .rounded, .stadium: return (.rectangle, .roundedRectangle, false, nil)
        case .subroutine: return (.rectangle, .predefinedProcess, false, nil)
        case .cylinder: return (.rectangle, .cylinder, false, nil)
        case .circle, .ellipse: return (.circle, nil, false, nil)
        case .doubleCircle: return (.circle, nil, false, doubleStroke)
        case .crossedCircle: return (.rectangle, .summingJunction, false, nil)
        case .asymmetric: return (.rectangle, .chevron, false, nil)
        case .diamond: return (.rectangle, .diamond, false, nil)
        case .hexagon: return (.rectangle, .hexagon, false, nil)
        case .leanRight: return (.rectangle, .parallelogram, false, nil)
        case .leanLeft: return (.rectangle, .parallelogramLeft, false, nil)
        case .trapezoid: return (.rectangle, .trapezoid, false, nil)
        case .invertedTrapezoid: return (.rectangle, .trapezoid, true, nil)
        case .document: return (.rectangle, .document, false, nil)
        case .documents: return (.rectangle, .documents, false, nil)
        case .card: return (.rectangle, .file, false, nil)
        case .horizontalCylinder: return (.rectangle, .cylinderHorizontal, false, nil)
        case .manualInput: return (.rectangle, .manualInput, false, nil)
        case .internalStorage: return (.rectangle, .internalStorage, false, nil)
        case .triangle: return (.rectangle, .triangle, false, nil)
        case .flippedTriangle: return (.rectangle, .triangleDown, false, nil)
        case .text: return (.text, nil, false, nil)
        }
    }

    static func frameSize(_ shape: EaselMermaidShape, text: EaselMermaidSize) -> EaselMermaidSize {
        let look = appearance(shape)
        let round = shape == .circle || shape == .doubleCircle || shape == .crossedCircle
        let minimum: EaselMermaidSize
        switch shape {
        case .circle, .doubleCircle, .crossedCircle: minimum = EaselMermaidSize(width: 72, height: 72)
        case .diamond: minimum = EaselMermaidSize(width: 128, height: 88)
        case .triangle, .flippedTriangle: minimum = EaselMermaidSize(width: 120, height: 96)
        case .text: minimum = EaselMermaidSize(width: 40, height: 28)
        case .entity: minimum = EaselMermaidSize(width: 180, height: 64)
        default: minimum = EaselMermaidSize(width: 128, height: 60)
        }
        if look.kind == .text {
            return EaselMermaidSize(width: max(minimum.width, ceil(text.width + 16)), height: max(minimum.height, ceil(text.height + 8)))
        }
        let outline = look.kind == .circle ? EaselShape.ellipse : look.shape ?? .rectangle
        let target = EaselMermaidSize(width: text.width + 20, height: text.height + 12)
        var width = max(minimum.width, target.width + 16), height = max(minimum.height, target.height + 16)
        if round { width = max(width, height); height = width }
        for _ in 0..<12 {
            let rect = EaselShapeGeometry.textRect(outline, in: EaselRect(x: 0, y: 0, width: width, height: height))
            let missingWidth = target.width - rect.width, missingHeight = target.height - rect.height
            if missingWidth <= 0.5 && missingHeight <= 0.5 { break }
            if missingWidth > 0.5 { width += missingWidth * max(1, width / max(rect.width, 1)) }
            if missingHeight > 0.5 { height += missingHeight * max(1, height / max(rect.height, 1)) }
            if round { width = max(width, height); height = width }
        }
        return EaselMermaidSize(width: ceil(width), height: ceil(height))
    }

    static func drawing(_ diagram: EaselMermaidDiagram, zIndex: Int = 1, ink: String = EaselPalette.automaticInk,
                        measure: EaselMermaidMeasure = EaselMermaid.estimate) -> EaselMermaidDrawing {
        var nodeSizes: [String: EaselMermaidSize] = [:], labelSizes: [Int: EaselMermaidSize] = [:]
        for node in diagram.nodes where nodeSizes[node.id] == nil {
            nodeSizes[node.id] = frameSize(node.shape, text: measure(displayText(node), textWidth))
        }
        for (index, edge) in diagram.edges.enumerated() where edge.line != .invisible && !edge.label.isEmpty {
            let size = measure(edge.label, labelWidth)
            labelSizes[index] = EaselMermaidSize(width: size.width + 16, height: size.height + 10)
        }
        let layout = EaselMermaidLayoutEngine.layout(diagram, nodeSizes: nodeSizes, labelSizes: labelSizes)
        var z = zIndex, sections: [EaselItem] = [], connectors: [EaselItem] = [], shapes: [EaselItem] = []
        var nodeItems: [String: EaselItem] = [:], groupItems: [String: EaselItem] = [:], headings = Set<UUID>()

        var depth: [String: Int] = [:], parents: [String: String] = [:]
        for group in diagram.groups where parents[group.id] == nil { parents[group.id] = group.parent ?? "" }
        for group in diagram.groups {
            var level = 0, parent = group.parent
            while let current = parent, !current.isEmpty, level <= diagram.groups.count { level += 1; parent = parents[current] }
            depth[group.id] = level
        }
        for group in diagram.groups.sorted(by: { depth[$0.id] ?? 0 < depth[$1.id] ?? 0 }) {
            guard groupItems[group.id] == nil, let frame = layout.groups[group.id] else { continue }
            let title = EaselBoardObjects.sectionTitle(group.title.isEmpty ? group.id : group.title)
            var item = EaselItem(kind: .section, frame: frame, zIndex: 0, text: title, color: group.style.stroke ?? ink)
            item.fill = group.style.fill
            groupItems[group.id] = item
            sections.append(item)
        }
        for node in diagram.nodes {
            guard nodeItems[node.id] == nil, let frame = layout.nodes[node.id] else { continue }
            let look = appearance(node.shape)
            var item = EaselItem(kind: look.kind, frame: frame, zIndex: 0, text: displayText(node), color: node.style.stroke ?? ink)
            if look.kind == .rectangle { item.shape = look.shape }
            if look.flipped { item.flipVertical = true }
            if look.kind != .text {
                item.fill = node.style.fill
                if let width = node.style.strokeWidth { item.strokeWidth = min(EaselPaintRules.maximumWidth, width * 1.25) }
                else if let width = look.strokeWidth { item.strokeWidth = width }
                if node.style.dashed == true { item.strokeDash = .dashed }
            }
            if node.shape == .entity, !node.attributes.isEmpty {
                var style = EaselTextStyle()
                style.alignment = .left
                item.textStyle = style
                headings.insert(item.id)
            }
            nodeItems[node.id] = item
            shapes.append(item)
        }
        func target(_ id: String) -> EaselItem? { nodeItems[id] ?? groupItems[id] }
        for (index, edge) in diagram.edges.enumerated() where edge.line != .invisible {
            guard let start = target(edge.from), let end = target(edge.to) else { continue }
            connectors.append(connector(edge, from: start, to: end, direction: layout.edgeDirections[index] ?? diagram.direction, ink: ink))
        }
        var items = sections + connectors + shapes
        for index in items.indices { items[index].zIndex = z; z += 1 }
        var lookup: [UUID: EaselItem] = [:]
        for item in items where item.kind != .arrow { lookup[item.id] = item }
        for index in items.indices where items[index].kind == .arrow {
            items[index] = EaselConnectorRouter.settled(items[index], lookup: { lookup[$0] })
        }
        return EaselMermaidDrawing(items: items, width: layout.width, height: layout.height, headings: headings)
    }

    static func sides(from a: EaselRect, to b: EaselRect, direction: EaselMermaidDirection,
                      loop: Bool) -> (start: EaselConnection.Side?, end: EaselConnection.Side?) {
        if loop { return direction.isVertical ? (.right, .top) : (.bottom, .left) }
        let forward: Bool
        switch direction {
        case .down: forward = b.y >= a.y + a.height - 1
        case .up: forward = b.y + b.height <= a.y + 1
        case .right: forward = b.x >= a.x + a.width - 1
        case .left: forward = b.x + b.width <= a.x + 1
        }
        guard forward else { return (nil, nil) }
        switch direction {
        case .down: return (.bottom, .top)
        case .up: return (.top, .bottom)
        case .right: return (.right, .left)
        case .left: return (.left, .right)
        }
    }

    static func attachment(_ item: EaselItem, side: EaselConnection.Side?, toward target: EaselPoint) -> EaselPoint {
        let r = item.frame
        if let side {
            if item.resolvedShape != nil, let point = EaselShapeGeometry.anchorPoint(of: item, side: side) { return point }
            switch side {
            case .top: return EaselPoint(x: r.x + r.width / 2, y: r.y)
            case .bottom: return EaselPoint(x: r.x + r.width / 2, y: r.y + r.height)
            case .left: return EaselPoint(x: r.x, y: r.y + r.height / 2)
            case .right: return EaselPoint(x: r.x + r.width, y: r.y + r.height / 2)
            }
        }
        if item.resolvedShape != nil, let point = EaselShapeGeometry.edgePoint(of: item, toward: target) { return point }
        let center = EaselShapeGeometry.center(of: r), dx = target.x - center.x, dy = target.y - center.y
        guard abs(dx) > 1e-9 || abs(dy) > 1e-9 else { return EaselPoint(x: center.x, y: r.y) }
        let scale = min(abs(dx) > 1e-9 ? r.width / 2 / abs(dx) : .infinity, abs(dy) > 1e-9 ? r.height / 2 / abs(dy) : .infinity)
        return EaselPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    static func head(_ head: EaselMermaidHead) -> EaselArrowHead {
        switch head {
        case .none: return .none
        case .arrow: return .arrow
        case .circle: return .circle
        case .cross: return .bar
        case .zeroOrOne: return .erdZeroOrOne
        case .exactlyOne: return .erdExactlyOne
        case .zeroOrMore: return .erdZeroOrMore
        case .oneOrMore: return .erdOneOrMore
        }
    }

    private static func connector(_ edge: EaselMermaidEdge, from start: EaselItem, to end: EaselItem,
                                  direction: EaselMermaidDirection, ink: String) -> EaselItem {
        let side = sides(from: start.frame, to: end.frame, direction: direction, loop: start.id == end.id)
        let a = attachment(start, side: side.start, toward: EaselShapeGeometry.center(of: end.frame))
        let b = attachment(end, side: side.end, toward: EaselShapeGeometry.center(of: start.frame))
        let geometry = EaselToolGeometry.lineItemGeometry(from: a, to: b)
        var item = EaselItem(kind: .arrow, frame: geometry.frame, zIndex: 0, text: edge.label, color: edge.style.stroke ?? ink,
                             points: geometry.points)
        item.routing = .elbow
        item.startConnection = EaselConnection(itemID: start.id, side: side.start)
        item.endConnection = EaselConnection(itemID: end.id, side: side.end)
        if edge.startHead != .none { item.startHead = head(edge.startHead) }
        if edge.endHead != .arrow { item.endHead = head(edge.endHead) }
        if edge.line == .dotted || edge.style.dashed == true { item.strokeDash = .dashed }
        if edge.line == .thick || (edge.style.strokeWidth ?? 0) >= 3 { item.strokeWidth = thickStroke }
        return item
    }
}
