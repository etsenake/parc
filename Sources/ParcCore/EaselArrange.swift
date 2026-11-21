import Foundation

enum EaselAlignment: String, CaseIterable {
    case left, center, right, top, middle, bottom

    var title: String {
        switch self {
        case .left: return "Align Left"
        case .center: return "Align Center"
        case .right: return "Align Right"
        case .top: return "Align Top"
        case .middle: return "Align Middle"
        case .bottom: return "Align Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .center: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .middle: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
}

enum EaselAxis: String, CaseIterable {
    case horizontal, vertical

    var distributeTitle: String { self == .horizontal ? "Distribute Horizontally" : "Distribute Vertically" }
    var symbol: String { self == .horizontal ? "distribute.horizontal.center" : "distribute.vertical.center" }
}

enum EaselLayerMove: String, CaseIterable {
    case front, forward, backward, back

    var title: String {
        switch self {
        case .front: return "Bring to Front"
        case .forward: return "Bring Forward"
        case .backward: return "Send Backward"
        case .back: return "Send to Back"
        }
    }

    var symbol: String {
        switch self {
        case .front: return "square.3.layers.3d.top.filled"
        case .forward: return "square.2.layers.3d.top.filled"
        case .backward: return "square.2.layers.3d.bottom.filled"
        case .back: return "square.3.layers.3d.bottom.filled"
        }
    }

    var shortcut: String {
        switch self {
        case .front: return "]"
        case .forward: return "⌘]"
        case .backward: return "⌘["
        case .back: return "["
        }
    }
}

struct EaselClipboardPayload: Codable, Equatable {
    static let currentVersion = 1
    static let typeIdentifier = "org.parc.easel-objects.v1"
    static let maximumBytes = 128 * 1024 * 1024
    static let maximumItems = 10_000
    static let maximumAssetBytes = 30 * 1024 * 1024

    var version = currentVersion
    var documentID: UUID?
    var items: [EaselItem]
    var assets: [String: Data] = [:]

    static func assetIDs(of selected: Set<UUID>, in document: EaselDocument) -> Set<String> {
        let ids = EaselArrange.withFollowers(selected, in: document)
        return Set(document.items.filter { ids.contains($0.id) }.compactMap(\.assetID))
    }

    static func capturing(_ selected: Set<UUID>, in document: EaselDocument, assets available: [String: Data]) throws -> EaselClipboardPayload? {
        let ids = EaselArrange.withFollowers(selected, in: document)
        let chosen = EaselArrange.paintOrder(document).filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let whole = EaselArrange.completeGroups(ids, in: document)
        let items = chosen.map { item -> EaselItem in
            var copy = item
            if let group = copy.groupID, !whole.contains(group) { copy.groupID = nil }
            copy.movedToFrontAt = nil
            return copy
        }
        var assets: [String: Data] = [:]
        for id in Set(items.compactMap(\.assetID)) { assets[id] = available[id] }
        let payload = EaselClipboardPayload(documentID: document.id, items: items, assets: assets)
        try payload.validate()
        return payload
    }

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw EaselStoreError.tooLarge }
        return data
    }

    static func decoded(_ data: Data) throws -> EaselClipboardPayload {
        guard data.count <= maximumBytes else { throw EaselStoreError.tooLarge }
        let payload = try PropertyListDecoder().decode(Self.self, from: data)
        try payload.validate()
        return payload
    }

    func validate() throws {
        guard version == Self.currentVersion, !items.isEmpty, items.count <= Self.maximumItems,
              Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ $0.assetID.map { assets[$0] != nil } ?? true }),
              assets.count <= items.count, assets.values.allSatisfy({ !$0.isEmpty && $0.count <= Self.maximumAssetBytes }),
              assets.keys.allSatisfy({ $0.count <= 64 && !$0.contains("/") }) else {
            throw EaselStoreError.invalidDocument("pasted Easel objects")
        }
    }
}

struct EaselDuplication: Equatable {
    var document: EaselDocument
    var copies: [UUID]
}

enum EaselArrange {
    static let duplicateOffset = 24.0
    static let tidySpacing = 24.0

    struct Unit: Equatable {
        var ids: [UUID]
        var frame: EaselRect
    }

    static func visualFrame(_ item: EaselItem) -> EaselRect {
        let r = item.frame, degrees = item.resolvedRotation
        guard degrees.isFinite, degrees.truncatingRemainder(dividingBy: 360) != 0 else { return r }
        let radians = degrees * .pi / 180
        let c = abs(cos(radians)), s = abs(sin(radians))
        let width = r.width * c + r.height * s, height = r.width * s + r.height * c
        return EaselRect(x: r.x + r.width / 2 - width / 2, y: r.y + r.height / 2 - height / 2, width: width, height: height)
    }

    static func union(_ frames: [EaselRect]) -> EaselRect? {
        guard let first = frames.first else { return nil }
        var minX = first.x, minY = first.y, maxX = first.x + first.width, maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width); maxY = max(maxY, frame.y + frame.height)
        }
        return EaselRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func paintOrder(_ document: EaselDocument) -> [EaselItem] {
        document.items.enumerated().sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }.map(\.element)
    }

    static func members(of group: UUID, in document: EaselDocument) -> Set<UUID> {
        Set(document.items.filter { $0.groupID == group }.map(\.id))
    }

    static func expandingGroups(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        let groups = Set(document.items.filter { ids.contains($0.id) }.compactMap(\.groupID))
        return Set(document.items.filter { ids.contains($0.id) || $0.groupID.map(groups.contains) == true }.map(\.id))
    }

    static func completeGroups(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        var complete: [UUID: Bool] = [:]
        for item in document.items {
            guard let group = item.groupID else { continue }
            complete[group] = (complete[group] ?? true) && ids.contains(item.id)
        }
        return Set(complete.filter { $0.value }.keys)
    }

    static func wholeGroup(_ ids: Set<UUID>, in document: EaselDocument) -> UUID? {
        let selected = document.items.filter { ids.contains($0.id) }
        guard selected.count >= 2, selected.count == ids.count, let group = selected.first?.groupID,
              selected.allSatisfy({ $0.groupID == group }), members(of: group, in: document) == ids else { return nil }
        return group
    }

    static func sharedGroup(_ ids: Set<UUID>, in document: EaselDocument) -> UUID? {
        let selected = document.items.filter { ids.contains($0.id) }
        guard !selected.isEmpty, let group = selected.first?.groupID, selected.allSatisfy({ $0.groupID == group }) else { return nil }
        return group
    }

    struct ClickResult: Equatable {
        var selection: Set<UUID>
        var enteredGroup: UUID?
        var enteredByClick: Bool
    }

    static func unlocked(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        Set(document.items.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
    }

    static func isInside(_ group: UUID, entered: UUID?, selection: Set<UUID>, in document: EaselDocument) -> Bool {
        entered == group && !selection.isDisjoint(with: members(of: group, in: document))
    }

    static func clickSelection(hit: EaselItem, selection current: Set<UUID>, entered: UUID?, extending: Bool,
                               clickCount: Int, in document: EaselDocument) -> ClickResult {
        guard let group = hit.groupID, !isInside(group, entered: entered, selection: current, in: document) else {
            var next = current
            if extending { if !next.insert(hit.id).inserted { next.remove(hit.id) } }
            else if !next.contains(hit.id) { next = [hit.id] }
            return ClickResult(selection: next, enteredGroup: entered != nil && entered == hit.groupID ? entered : nil, enteredByClick: false)
        }
        if clickCount >= 2, !extending { return ClickResult(selection: [hit.id], enteredGroup: group, enteredByClick: true) }
        let reach = unlocked(members(of: group, in: document), in: document).union([hit.id])
        var next = current
        if extending {
            if reach.isSubset(of: next) { next.subtract(reach) } else { next.formUnion(reach) }
        } else if !reach.isSubset(of: next) {
            next = reach
        }
        return ClickResult(selection: next, enteredGroup: nil, enteredByClick: false)
    }

    static func marqueeSelection(hits: Set<UUID>, original: Set<UUID>, operation: EaselCanvasSelection.Operation,
                                 entered: UUID?, in document: EaselDocument) -> Set<UUID> {
        let caughtHits = unlocked(hits, in: document)
        let inside = Set(document.items.filter { caughtHits.contains($0.id) && entered != nil && $0.groupID == entered }.map(\.id))
        let caught = unlocked(expandingGroups(caughtHits.subtracting(inside), in: document), in: document).union(inside)
        let available = Set(document.items.map(\.id))
        switch operation {
        case .replace: return caught
        case .add: return original.union(caught).intersection(available)
        case .subtract: return original.subtracting(caught).intersection(available)
        }
    }

    static func follows(_ item: EaselItem, present: Set<UUID>) -> Bool {
        if let target = item.attachedTo, present.contains(target) { return true }
        guard item.kind == .arrow else { return false }
        return [item.startConnection?.itemID, item.endConnection?.itemID].contains { $0.map(present.contains) == true }
    }

    static func units(_ ids: Set<UUID>, in document: EaselDocument) -> [Unit] {
        let present = Set(document.items.map(\.id))
        let whole = completeGroups(ids, in: document)
        var units: [Unit] = [], slots: [UUID: Int] = [:]
        for item in document.items where ids.contains(item.id) && !item.isLocked && !follows(item, present: present) {
            let frame = visualFrame(item)
            if let group = item.groupID, whole.contains(group) {
                if let slot = slots[group] {
                    units[slot].ids.append(item.id)
                    units[slot].frame = union([units[slot].frame, frame]) ?? frame
                    continue
                }
                slots[group] = units.count
            }
            units.append(Unit(ids: [item.id], frame: frame))
        }
        return units
    }

    static func axisLocked(_ translation: EaselPoint, when locked: Bool) -> EaselPoint {
        guard locked else { return translation }
        return abs(translation.x) >= abs(translation.y) ? EaselPoint(x: translation.x, y: 0) : EaselPoint(x: 0, y: translation.y)
    }

    static func move(_ item: inout EaselItem, dx: Double, dy: Double) {
        item.frame.x += dx; item.frame.y += dy
        if let waypoints = item.waypoints { item.waypoints = waypoints.map { EaselPoint(x: $0.x + dx, y: $0.y + dy) } }
    }

    static func translating(_ document: EaselDocument, by deltas: [UUID: EaselPoint]) -> EaselDocument? {
        var next = document, changed = false
        for index in next.items.indices {
            guard let delta = deltas[next.items[index].id], delta.x.isFinite, delta.y.isFinite,
                  abs(delta.x) > 1e-9 || abs(delta.y) > 1e-9 else { continue }
            move(&next.items[index], dx: delta.x, dy: delta.y)
            changed = true
        }
        return changed ? next : nil
    }

    private static func deltas(_ moves: [(Unit, EaselPoint)]) -> [UUID: EaselPoint] {
        var result: [UUID: EaselPoint] = [:]
        for (unit, delta) in moves { for id in unit.ids { result[id] = delta } }
        return result
    }

    static func canAlign(_ ids: Set<UUID>, in document: EaselDocument) -> Bool { units(ids, in: document).count >= 2 }

    static func aligned(_ document: EaselDocument, ids: Set<UUID>, to alignment: EaselAlignment) -> EaselDocument? {
        let units = units(ids, in: document)
        guard units.count >= 2, let bounds = union(units.map(\.frame)) else { return nil }
        return translating(document, by: deltas(units.map { unit in
            let f = unit.frame
            switch alignment {
            case .left: return (unit, EaselPoint(x: bounds.x - f.x, y: 0))
            case .center: return (unit, EaselPoint(x: bounds.x + bounds.width / 2 - (f.x + f.width / 2), y: 0))
            case .right: return (unit, EaselPoint(x: bounds.x + bounds.width - (f.x + f.width), y: 0))
            case .top: return (unit, EaselPoint(x: 0, y: bounds.y - f.y))
            case .middle: return (unit, EaselPoint(x: 0, y: bounds.y + bounds.height / 2 - (f.y + f.height / 2)))
            case .bottom: return (unit, EaselPoint(x: 0, y: bounds.y + bounds.height - (f.y + f.height)))
            }
        }))
    }

    static func canDistribute(_ ids: Set<UUID>, in document: EaselDocument) -> Bool { units(ids, in: document).count >= 3 }

    static func distributed(_ document: EaselDocument, ids: Set<UUID>, along axis: EaselAxis) -> EaselDocument? {
        let units = units(ids, in: document)
        guard units.count >= 3 else { return nil }
        let horizontal = axis == .horizontal
        func start(_ f: EaselRect) -> Double { horizontal ? f.x : f.y }
        func size(_ f: EaselRect) -> Double { horizontal ? f.width : f.height }
        let sorted = units.enumerated().sorted { a, b in
            let ca = start(a.element.frame) + size(a.element.frame) / 2, cb = start(b.element.frame) + size(b.element.frame) / 2
            return (ca, a.offset) < (cb, b.offset)
        }.map(\.element)
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let span = start(last.frame) + size(last.frame) - start(first.frame)
        let gap = (span - sorted.map { size($0.frame) }.reduce(0, +)) / Double(sorted.count - 1)
        guard gap.isFinite else { return nil }
        var cursor = start(first.frame)
        var moves: [(Unit, EaselPoint)] = []
        for unit in sorted {
            let shift = cursor - start(unit.frame)
            moves.append((unit, horizontal ? EaselPoint(x: shift, y: 0) : EaselPoint(x: 0, y: shift)))
            cursor += size(unit.frame) + gap
        }
        return translating(document, by: deltas(moves))
    }

    static func tidyUnits(_ ids: Set<UUID>, in document: EaselDocument) -> [Unit] {
        let kinds = Dictionary(document.items.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        return units(ids, in: document).filter { unit in unit.ids.allSatisfy { kinds[$0] != .arrow && kinds[$0] != .section } }
    }

    static func canTidy(_ ids: Set<UUID>, in document: EaselDocument) -> Bool { tidyUnits(ids, in: document).count >= 3 }

    static func tidyColumns(_ units: [Unit]) -> (columns: Int, order: [Unit]) {
        let byCenter = units.enumerated().sorted { a, b in
            let fa = a.element.frame, fb = b.element.frame
            return (fa.y + fa.height / 2, fa.x + fa.width / 2, a.offset) < (fb.y + fb.height / 2, fb.x + fb.width / 2, b.offset)
        }.map(\.element)
        guard let bounds = union(units.map(\.frame)), !units.isEmpty else { return (1, byCenter) }
        let area = units.map { $0.frame.width * $0.frame.height }.reduce(0, +)
        if area > bounds.width * bounds.height {
            return (max(1, Int(Double(units.count).squareRoot().rounded(.up))), byCenter)
        }
        var rows: [[Unit]] = [], bottom = -Double.infinity
        for unit in byCenter {
            let f = unit.frame
            if rows.isEmpty || f.y + f.height / 2 > bottom {
                rows.append([unit]); bottom = f.y + f.height
            } else {
                rows[rows.count - 1].append(unit); bottom = max(bottom, f.y + f.height)
            }
        }
        let ordered = rows.flatMap { row in
            row.enumerated().sorted { ($0.element.frame.x + $0.element.frame.width / 2, $0.offset) <
                ($1.element.frame.x + $1.element.frame.width / 2, $1.offset) }.map(\.element)
        }
        return (max(1, rows.map(\.count).max() ?? 1), ordered)
    }

    static func tidied(_ document: EaselDocument, ids: Set<UUID>, spacing: Double = tidySpacing) -> EaselDocument? {
        let units = tidyUnits(ids, in: document)
        guard units.count >= 3, spacing.isFinite, spacing >= 0, let bounds = union(units.map(\.frame)) else { return nil }
        let (columns, order) = tidyColumns(units)
        let cellWidth = units.map(\.frame.width).max() ?? 0, cellHeight = units.map(\.frame.height).max() ?? 0
        var moves: [(Unit, EaselPoint)] = []
        for (index, unit) in order.enumerated() {
            let row = index / columns, column = index % columns
            let x = bounds.x + Double(column) * (cellWidth + spacing) + (cellWidth - unit.frame.width) / 2
            let y = bounds.y + Double(row) * (cellHeight + spacing) + (cellHeight - unit.frame.height) / 2
            moves.append((unit, EaselPoint(x: x - unit.frame.x, y: y - unit.frame.y)))
        }
        return translating(document, by: deltas(moves))
    }

    static func layerUnits(_ ids: Set<UUID>, in document: EaselDocument) -> [Set<UUID>] {
        let whole = completeGroups(ids, in: document)
        var units: [Set<UUID>] = [], slots: [UUID: Int] = [:]
        for item in document.items where ids.contains(item.id) && !item.isLocked {
            if let group = item.groupID, whole.contains(group) {
                if let slot = slots[group] { units[slot].insert(item.id); continue }
                slots[group] = units.count
            }
            units.append([item.id])
        }
        let locked = Set(document.items.filter(\.isLocked).map(\.id))
        var claimed = units.reduce(into: ids) { $0.formUnion($1) }
        return units.map { unit in
            let followers = EaselAttachments.dependents(of: unit, in: document).subtracting(claimed).subtracting(locked)
            claimed.formUnion(followers)
            return unit.union(followers)
        }
    }

    static func canMoveLayer(_ ids: Set<UUID>, in document: EaselDocument) -> Bool { !layerUnits(ids, in: document).isEmpty }

    static func layered(_ document: EaselDocument, ids: Set<UUID>, _ move: EaselLayerMove) -> EaselDocument? {
        let units = layerUnits(ids, in: document)
        guard !units.isEmpty else { return nil }
        let chosen = units.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        let painted = paintOrder(document)
        let frames = Dictionary(painted.map { ($0.id, visualFrame($0)) }, uniquingKeysWith: { first, _ in first })
        let original = painted.map(\.id)
        var order = original
        switch move {
        case .front: order = order.filter { !chosen.contains($0) } + order.filter { chosen.contains($0) }
        case .back: order = order.filter { chosen.contains($0) } + order.filter { !chosen.contains($0) }
        case .forward, .backward:
            let up = move == .forward
            let ranked = units.map { unit -> (Set<UUID>, Int) in
                let positions = unit.compactMap { order.firstIndex(of: $0) }
                return (unit, up ? positions.max() ?? 0 : positions.min() ?? 0)
            }.sorted { up ? $0.1 > $1.1 : $0.1 < $1.1 }
            for (unit, _) in ranked {
                let positions = unit.compactMap { order.firstIndex(of: $0) }
                guard let edge = up ? positions.max() : positions.min(),
                      let bounds = union(unit.compactMap { frames[$0] }) else { continue }
                let candidates = up ? Array(order.indices.dropFirst(edge + 1)) : Array(order.indices.prefix(edge).reversed())
                guard let hit = candidates.first(where: { index in
                    !ids.contains(order[index]) && !chosen.contains(order[index])
                        && frames[order[index]].map { EaselContentHitTest.intersects(bounds, $0) } == true
                }) else { continue }
                let target = order[hit]
                let moving = order.filter(unit.contains)
                order.removeAll(where: unit.contains)
                guard let anchor = order.firstIndex(of: target) else { continue }
                order.insert(contentsOf: moving, at: up ? anchor + 1 : anchor)
            }
        }
        guard order != original else { return nil }
        return reindexed(document, order: order)
    }

    static func reindexed(_ document: EaselDocument, order: [UUID]) -> EaselDocument {
        var rank: [UUID: Int] = [:]
        for (index, id) in order.enumerated() where rank[id] == nil { rank[id] = index }
        var next = document
        for index in next.items.indices {
            guard let value = rank[next.items[index].id], next.items[index].zIndex != value else { continue }
            next.items[index].zIndex = value
        }
        return next
    }

    static func canGroup(_ ids: Set<UUID>, in document: EaselDocument) -> Bool {
        let movable = document.items.filter { ids.contains($0.id) && !$0.isLocked }
        guard movable.count >= 2 else { return false }
        return wholeGroup(Set(movable.map(\.id)), in: document) == nil
    }

    static func grouped(_ document: EaselDocument, ids: Set<UUID>, groupID: UUID = UUID()) -> EaselDocument? {
        guard canGroup(ids, in: document) else { return nil }
        var next = document
        for index in next.items.indices where ids.contains(next.items[index].id) && !next.items[index].isLocked {
            next.items[index].groupID = groupID
        }
        return dissolvingSingletonGroups(next)
    }

    static func canUngroup(_ ids: Set<UUID>, in document: EaselDocument) -> Bool {
        document.items.contains { ids.contains($0.id) && $0.groupID != nil && !$0.isLocked }
    }

    static func ungrouped(_ document: EaselDocument, ids: Set<UUID>) -> EaselDocument? {
        guard canUngroup(ids, in: document) else { return nil }
        let groups = Set(document.items.filter { ids.contains($0.id) }.compactMap(\.groupID))
        var next = document
        for index in next.items.indices where next.items[index].groupID.map(groups.contains) == true {
            next.items[index].groupID = nil
        }
        return next
    }

    static func dissolvingSingletonGroups(_ document: EaselDocument) -> EaselDocument {
        var counts: [UUID: Int] = [:]
        for item in document.items { if let group = item.groupID { counts[group, default: 0] += 1 } }
        guard counts.values.contains(1) else { return document }
        var next = document
        for index in next.items.indices where next.items[index].groupID.map({ counts[$0] == 1 }) == true {
            next.items[index].groupID = nil
        }
        return next
    }

    static func shouldLock(_ ids: Set<UUID>, in document: EaselDocument) -> Bool {
        document.items.contains { ids.contains($0.id) && !$0.isLocked }
    }

    static func settingLock(_ locked: Bool, ids: Set<UUID>, in document: EaselDocument) -> EaselDocument? {
        var next = document, changed = false
        let value: Bool? = locked ? true : nil
        for index in next.items.indices where ids.contains(next.items[index].id) && next.items[index].locked != value {
            next.items[index].locked = value; changed = true
        }
        return changed ? next : nil
    }

    static func copies(of originals: [EaselItem], offset: EaselPoint, firstZIndex: Int, keepingGroups kept: Set<UUID> = []) -> [EaselItem] {
        var ids: [UUID: UUID] = [:]
        var fresh: [UUID] = []
        for item in originals {
            let id = UUID()
            if ids[item.id] == nil { ids[item.id] = id }
            fresh.append(id)
        }
        var groups: [UUID: UUID] = [:]
        for group in originals.compactMap(\.groupID) where !kept.contains(group) && groups[group] == nil { groups[group] = UUID() }
        func remap(_ connection: EaselConnection?) -> EaselConnection? {
            guard var connection, let target = ids[connection.itemID] else { return nil }
            connection.itemID = target
            return connection
        }
        return originals.enumerated().map { index, item in
            var copy = item
            copy.id = fresh[index]
            copy.groupID = item.groupID.flatMap { kept.contains($0) ? $0 : groups[$0] }
            if item.kind == .arrow {
                copy.startConnection = remap(item.startConnection)
                copy.endConnection = remap(item.endConnection)
            }
            copy.attachedTo = item.attachedTo.flatMap { ids[$0] }
            copy.zIndex = firstZIndex + index
            copy.movedToFrontAt = nil
            move(&copy, dx: offset.x, dy: offset.y)
            return copy
        }
    }

    static func appending(_ originals: [EaselItem], to document: EaselDocument, offset: EaselPoint,
                          keepingGroups kept: Set<UUID> = []) -> EaselDuplication? {
        guard !originals.isEmpty, offset.x.isFinite, offset.y.isFinite else { return nil }
        var base = document
        if (base.items.map(\.zIndex).max() ?? 0) > Int.max - originals.count - 1 {
            base = reindexed(base, order: paintOrder(base).map(\.id))
        }
        let first = (base.items.map(\.zIndex).max() ?? 0) + 1
        let copies = copies(of: originals, offset: offset, firstZIndex: first, keepingGroups: kept)
        base.items.append(contentsOf: copies)
        return EaselDuplication(document: dissolvingSingletonGroups(base), copies: copies.map(\.id))
    }

    static func withFollowers(_ ids: Set<UUID>, in document: EaselDocument) -> Set<UUID> {
        ids.union(EaselAttachments.dependents(of: ids, in: document))
    }

    static func duplicating(_ selected: Set<UUID>, in document: EaselDocument,
                            offset: EaselPoint = EaselPoint(x: duplicateOffset, y: duplicateOffset)) -> EaselDuplication? {
        let ids = withFollowers(selected, in: document)
        let originals = paintOrder(document).filter { ids.contains($0.id) }
        let whole = completeGroups(ids, in: document)
        let partial = Set(originals.compactMap(\.groupID)).subtracting(whole)
        return appending(originals, to: document, offset: offset, keepingGroups: partial)
    }

    static func repeatOffset(sources: [UUID], copies: [UUID], in document: EaselDocument) -> EaselPoint? {
        let frames = Dictionary(document.items.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let from = sources.compactMap { frames[$0] }, to = copies.compactMap { frames[$0] }
        guard from.count == sources.count, to.count == copies.count, !from.isEmpty,
              let a = union(from), let b = union(to) else { return nil }
        let offset = EaselPoint(x: b.x - a.x, y: b.y - a.y)
        guard offset.x.isFinite, offset.y.isFinite, abs(offset.x) + abs(offset.y) >= 1 else { return nil }
        return offset
    }

    enum PasteAnchor: Equatable {
        case pointer(EaselPoint)
        case source(step: Int)
        case inPlace
        case viewport
    }

    static func pasteOffset(content: EaselRect, anchor: PasteAnchor, viewport: EaselRect) -> EaselPoint {
        var dx = 0.0, dy = 0.0
        switch anchor {
        case .pointer(let point):
            dx = point.x - (content.x + content.width / 2); dy = point.y - (content.y + content.height / 2)
        case .source(let step):
            dx = duplicateOffset * Double(max(1, step)); dy = dx
        case .inPlace:
            break
        case .viewport:
            dx = viewport.x + viewport.width / 2 - (content.x + content.width / 2)
            dy = viewport.y + viewport.height / 2 - (content.y + content.height / 2)
        }
        guard dx.isFinite, dy.isFinite else { return EaselPoint(x: 0, y: 0) }
        dx = max(dx, -content.x); dy = max(dy, -content.y)
        return EaselPoint(x: dx.rounded(), y: dy.rounded())
    }
}
