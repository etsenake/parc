import Foundation

extension EaselStampDesign {
    var title: String {
        switch self {
        case .plusOne: return "Plus one"
        case .dot: return "Dot"
        case .heart: return "Heart"
        case .question: return "Question"
        case .star: return "Star"
        case .thumbsUp: return "Thumbs up"
        case .thumbsDown: return "Thumbs down"
        case .smiley: return "Smiley"
        }
    }
}

extension EaselStampFace {
    func title(emojiName: String? = nil) -> String {
        switch self {
        case .design(let design): return design.title
        case .emoji(let character): return emojiName.map(EaselStamps.sentenceCased) ?? character
        case .icon(let name): return EaselStampIcons.icon(named: name)?.title ?? EaselStamps.readableSymbolName(name)
        }
    }

    func accessibilityLabel(emojiName: String? = nil) -> String {
        title(emojiName: emojiName) + (isIcon ? " icon" : " stamp")
    }
}

enum EaselStamps {
    static let sizes: [Double] = [64, 96, 136, 184]
    static let growthStep = 0.3
    static let tiltRange = 3.0...10.0
    static let recentsLimit = 8
    static let hubCount = 3
    static let ring: [EaselStampDesign] = [.thumbsUp, .heart, .plusOne, .star, .smiley, .question, .dot, .thumbsDown]
    static let emojiScale = 0.82
    static let iconInset = 0.06

    static func stage(heldFor seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return min(sizes.count - 1, Int(seconds / growthStep))
    }

    static func side(heldFor seconds: Double) -> Double { sizes[stage(heldFor: seconds)] }

    static func frame(centeredAt point: EaselPoint, side: Double) -> EaselRect {
        let value = side.isFinite && side >= 1 ? side : sizes[0]
        let x = point.x.isFinite ? point.x : 0, y = point.y.isFinite ? point.y : 0
        return EaselRect(x: max(0, x - value / 2), y: max(0, y - value / 2), width: value, height: value)
    }

    static func tilt<G: RandomNumberGenerator>(using generator: inout G) -> Double {
        let magnitude = Double.random(in: tiltRange, using: &generator)
        let sign: Double = Bool.random(using: &generator) ? 1 : -1
        return (magnitude * sign * 10).rounded() / 10
    }

    static func carriesStamps(_ item: EaselItem) -> Bool { item.kind != .stamp && EaselDrawing.canHold(item) }

    static func centre(of item: EaselItem) -> EaselPoint {
        EaselPoint(x: item.frame.x + item.frame.width / 2, y: item.frame.y + item.frame.height / 2)
    }

    static func attachmentTarget(at point: EaselPoint, in items: [EaselItem], excluding: Set<UUID> = []) -> UUID? {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = items.enumerated().sorted {
            $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex
        }
        for (_, item) in ordered.reversed() where !excluding.contains(item.id) {
            guard EaselDrawing.covers(item, point) else { continue }
            if item.kind == .stamp {
                guard let target = item.attachedTo.flatMap({ root(of: $0, in: byID) }), !excluding.contains(target) else { continue }
                return target
            }
            guard carriesStamps(item), let target = root(of: item.id, in: byID), !excluding.contains(target) else { continue }
            return target
        }
        return nil
    }

    private static func root(of id: UUID, in items: [UUID: EaselItem]) -> UUID? {
        var current = id
        var visited: Set<UUID> = []
        while let item = items[current] {
            guard visited.insert(current).inserted else { return nil }
            guard let next = item.attachedTo, items[next] != nil else { return carriesStamps(item) ? current : nil }
            current = next
        }
        return nil
    }

    static func stamped(_ face: EaselStampFace, at point: EaselPoint, side: Double = sizes[0], tilt: Double,
                        color: String = EaselVectorExport.automaticInk, in document: EaselDocument) -> EaselItem {
        var item = EaselItem(kind: .stamp, frame: frame(centeredAt: point, side: side),
                             zIndex: (document.items.map(\.zIndex).max() ?? 0) + 1)
        face.apply(to: &item)
        if face.isIcon, let ink = EaselPalette.normalized(color) { item.color = ink }
        let angle = tilt.isFinite ? max(-360, min(360, tilt)) : 0
        item.rotation = angle == 0 ? nil : angle
        item.attachedTo = attachmentTarget(at: point, in: document.items)
        return item
    }

    static func recording(_ face: EaselStampFace, in recents: [String]) -> [String] {
        let token = face.token
        var seen: Set<String> = [token]
        let kept = recents.filter { EaselStampFace(token: $0) != nil && seen.insert($0).inserted }
        return Array(([token] + kept).prefix(recentsLimit))
    }

    static func hubFaces(_ recents: [String]) -> [EaselStampFace] {
        var faces: [EaselStampFace] = []
        for token in recents {
            guard let face = EaselStampFace(token: token), face.stamp == nil, !faces.contains(face) else { continue }
            faces.append(face)
            if faces.count == hubCount { break }
        }
        return faces
    }

    static func wheelOffset(of index: Int, radius: Double) -> EaselPoint {
        let angle = Double(index) / Double(ring.count) * 2 * .pi
        return EaselPoint(x: sin(angle) * radius, y: -cos(angle) * radius)
    }

    static func wheelIndex(dx: Double, dy: Double, inner: Double, outer: Double) -> Int? {
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance.isFinite, distance >= inner, distance <= outer else { return nil }
        var turns = atan2(dx, -dy) / (2 * .pi)
        if turns < 0 { turns += 1 }
        return Int((turns * Double(ring.count) + 0.5).rounded(.down)) % ring.count
    }

    static func pinnedPoint(on item: EaselItem, side: Double, slot: Int) -> EaselPoint {
        let frame = item.frame
        let halfWidth = frame.width / 2, halfHeight = frame.height / 2
        let inset = min(side * 0.4, halfWidth, halfHeight)
        let step = side * 0.6
        let lanes = max(1, Int(((frame.width - inset * 2) / step).rounded(.down)) + 1)
        let index = max(0, slot)
        let x = max(-halfWidth + inset, halfWidth - inset - Double(index % lanes) * step)
        let y = min(halfHeight - inset, -halfHeight + inset + Double(index / lanes) * step)
        let radians = item.resolvedRotation * .pi / 180
        let turnedX = x * cos(radians) - y * sin(radians), turnedY = x * sin(radians) + y * cos(radians)
        return EaselPoint(x: frame.x + halfWidth + turnedX, y: frame.y + halfHeight + turnedY)
    }

    static func keyboardTargets(_ selection: Set<UUID>, in items: [EaselItem]) -> [UUID] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<UUID> = []
        return items.filter { selection.contains($0.id) }.compactMap { item -> UUID? in
            let start = item.kind == .stamp ? item.attachedTo : item.id
            guard let start, let target = root(of: start, in: byID), let held = byID[target], !held.isLocked,
                  seen.insert(target).inserted else { return nil }
            return target
        }
    }

    static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func readableSymbolName(_ name: String) -> String {
        let words = name.split(separator: ".").filter { !["fill", "circle", "square"].contains($0) }.map(String.init)
        return sentenceCased((words.isEmpty ? [name] : words).joined(separator: " "))
    }
}

struct EaselStampIcon: Hashable {
    let symbol: String
    let title: String
    let keywords: [String]

    init(_ symbol: String, _ title: String, _ keywords: [String] = []) {
        self.symbol = symbol
        self.title = title
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return ([title.lowercased(), symbol] + keywords).contains { $0.contains(needle) }
    }
}

enum EaselStampIcons {
    struct Section: Equatable {
        let title: String
        let icons: [EaselStampIcon]
    }

    static let sections: [Section] = [
        Section(title: "Systems", icons: [
            EaselStampIcon("cloud", "Cloud", ["hosting", "internet", "aws", "storage"]),
            EaselStampIcon("server.rack", "Server", ["backend", "host", "machine", "rack"]),
            EaselStampIcon("cylinder.split.1x2", "Database", ["db", "data", "sql", "table"]),
            EaselStampIcon("externaldrive", "Storage", ["disk", "drive", "backup", "volume"]),
            EaselStampIcon("cpu", "Service", ["chip", "processor", "compute", "worker"]),
            EaselStampIcon("memorychip", "Memory", ["ram", "cache", "chip"]),
            EaselStampIcon("network", "Network", ["nodes", "graph", "topology"]),
            EaselStampIcon("terminal", "Terminal", ["shell", "command line", "cli", "console"]),
            EaselStampIcon("chevron.left.forwardslash.chevron.right", "Code", ["html", "developer", "frontend", "tag"]),
            EaselStampIcon("curlybraces", "Data", ["json", "object", "api", "braces"]),
            EaselStampIcon("macwindow", "App window", ["frontend", "ui", "browser", "screen"]),
            EaselStampIcon("arrow.triangle.branch", "Branch", ["git", "flow", "split", "fork"]),
        ]),
        Section(title: "Devices", icons: [
            EaselStampIcon("desktopcomputer", "Desktop", ["computer", "monitor", "pc"]),
            EaselStampIcon("laptopcomputer", "Laptop", ["computer", "notebook"]),
            EaselStampIcon("iphone", "Phone", ["mobile", "smartphone", "cell"]),
            EaselStampIcon("ipad", "Tablet", ["mobile", "slate"]),
            EaselStampIcon("applewatch", "Watch", ["wearable", "wrist"]),
            EaselStampIcon("display", "Display", ["screen", "monitor", "tv"]),
            EaselStampIcon("printer", "Printer", ["print", "paper"]),
        ]),
        Section(title: "People", icons: [
            EaselStampIcon("person", "Person", ["user", "account", "customer", "member"]),
            EaselStampIcon("person.2", "People", ["users", "group", "pair", "friends"]),
            EaselStampIcon("person.3", "Team", ["users", "group", "crowd"]),
            EaselStampIcon("person.crop.circle", "Profile", ["avatar", "user", "account"]),
            EaselStampIcon("person.badge.key", "Sign in", ["authentication", "login", "auth", "access"]),
            EaselStampIcon("briefcase", "Work", ["business", "job", "office"]),
        ]),
        Section(title: "Security", icons: [
            EaselStampIcon("lock", "Lock", ["security", "private", "secure", "closed"]),
            EaselStampIcon("lock.open", "Unlocked", ["open", "public"]),
            EaselStampIcon("key", "Key", ["password", "secret", "credential"]),
            EaselStampIcon("shield", "Shield", ["security", "protect", "defence"]),
            EaselStampIcon("checkmark.shield", "Verified", ["security", "trusted", "safe"]),
            EaselStampIcon("lock.shield", "Secure", ["security", "encrypted", "protected"]),
            EaselStampIcon("eye", "Visible", ["view", "watch", "see", "monitor"]),
        ]),
        Section(title: "Messages", icons: [
            EaselStampIcon("envelope", "Email", ["mail", "message", "letter", "inbox"]),
            EaselStampIcon("paperplane", "Send", ["submit", "deliver", "message"]),
            EaselStampIcon("bubble.left", "Chat", ["message", "comment", "talk"]),
            EaselStampIcon("bubble.left.and.bubble.right", "Conversation", ["chat", "discussion", "talk"]),
            EaselStampIcon("phone", "Call", ["telephone", "ring"]),
            EaselStampIcon("bell", "Notification", ["alert", "alarm", "reminder"]),
            EaselStampIcon("megaphone", "Announcement", ["broadcast", "marketing", "news"]),
            EaselStampIcon("bolt", "Instant", ["fast", "power", "lightning", "event", "trigger"]),
        ]),
        Section(title: "Money", icons: [
            EaselStampIcon("cart", "Cart", ["shopping", "checkout", "buy", "store"]),
            EaselStampIcon("creditcard", "Payment", ["card", "pay", "billing", "checkout"]),
            EaselStampIcon("wallet.pass", "Wallet", ["pass", "ticket", "pay"]),
            EaselStampIcon("banknote", "Cash", ["money", "price", "cost"]),
            EaselStampIcon("bag", "Shopping bag", ["shop", "buy", "store"]),
            EaselStampIcon("gift", "Gift", ["present", "reward"]),
            EaselStampIcon("dollarsign.circle", "Dollar", ["money", "price", "usd"]),
            EaselStampIcon("eurosign.circle", "Euro", ["money", "price", "eur"]),
        ]),
        Section(title: "Files", icons: [
            EaselStampIcon("folder", "Folder", ["directory", "files"]),
            EaselStampIcon("doc", "File", ["page", "blank"]),
            EaselStampIcon("doc.text", "Document", ["page", "text", "report"]),
            EaselStampIcon("doc.on.doc", "Copies", ["duplicate", "documents", "files"]),
            EaselStampIcon("archivebox", "Archive", ["box", "store", "old"]),
            EaselStampIcon("tray.full", "Inbox", ["queue", "tray", "messages"]),
            EaselStampIcon("shippingbox", "Package", ["box", "delivery", "shipping", "module"]),
            EaselStampIcon("paperclip", "Attachment", ["clip", "attach"]),
        ]),
        Section(title: "Tools", icons: [
            EaselStampIcon("gearshape", "Settings", ["gear", "preferences", "config", "cog"]),
            EaselStampIcon("wrench.and.screwdriver", "Tools", ["maintenance", "fix", "repair"]),
            EaselStampIcon("hammer", "Build", ["make", "construct", "tool"]),
            EaselStampIcon("magnifyingglass", "Search", ["find", "lookup", "zoom"]),
            EaselStampIcon("link", "Link", ["url", "chain", "connect"]),
            EaselStampIcon("puzzlepiece", "Integration", ["plugin", "extension", "piece"]),
            EaselStampIcon("cube", "Component", ["module", "block", "box", "3d"]),
            EaselStampIcon("square.stack.3d.up", "Layers", ["stack", "levels"]),
        ]),
        Section(title: "Charts and time", icons: [
            EaselStampIcon("chart.bar", "Bar chart", ["chart", "graph", "stats", "analytics"]),
            EaselStampIcon("chart.pie", "Pie chart", ["chart", "graph", "share"]),
            EaselStampIcon("chart.line.uptrend.xyaxis", "Trend", ["chart", "growth", "graph", "line"]),
            EaselStampIcon("waveform.path.ecg", "Activity", ["pulse", "health", "monitor", "heartbeat"]),
            EaselStampIcon("calendar", "Calendar", ["date", "schedule", "event", "day"]),
            EaselStampIcon("clock", "Clock", ["time", "hour", "schedule"]),
            EaselStampIcon("timer", "Timer", ["stopwatch", "countdown", "time"]),
            EaselStampIcon("hourglass", "Waiting", ["hourglass", "time", "pending", "loading"]),
        ]),
        Section(title: "Places", icons: [
            EaselStampIcon("globe", "Web", ["internet", "world", "website", "global"]),
            EaselStampIcon("mappin.and.ellipse", "Location", ["pin", "place", "map", "address"]),
            EaselStampIcon("map", "Map", ["directions", "route"]),
            EaselStampIcon("house", "Home", ["house", "start"]),
            EaselStampIcon("building.2", "Office", ["company", "building", "city"]),
            EaselStampIcon("building.columns", "Bank", ["institution", "government", "museum"]),
            EaselStampIcon("airplane", "Travel", ["flight", "plane", "trip"]),
            EaselStampIcon("car", "Car", ["drive", "vehicle", "transport"]),
            EaselStampIcon("wifi", "Wi-Fi", ["wireless", "internet", "signal"]),
            EaselStampIcon("antenna.radiowaves.left.and.right", "Signal", ["broadcast", "radio", "wireless"]),
        ]),
        Section(title: "Signs", icons: [
            EaselStampIcon("star", "Star", ["favourite", "favorite", "rating"]),
            EaselStampIcon("flag", "Flag", ["milestone", "goal", "report"]),
            EaselStampIcon("lightbulb", "Idea", ["light", "insight", "tip"]),
            EaselStampIcon("checkmark.circle", "Done", ["yes", "complete", "check", "ok"]),
            EaselStampIcon("xmark.circle", "No", ["cancel", "close", "error", "wrong"]),
            EaselStampIcon("exclamationmark.triangle", "Warning", ["alert", "caution", "risk"]),
            EaselStampIcon("questionmark.circle", "Unknown", ["help", "question", "unsure"]),
            EaselStampIcon("heart", "Love", ["like", "favourite", "favorite"]),
            EaselStampIcon("flame", "Hot", ["fire", "trending", "popular"]),
            EaselStampIcon("sparkles", "Sparkles", ["magic", "new", "shiny"]),
            EaselStampIcon("trophy", "Trophy", ["win", "award", "prize"]),
            EaselStampIcon("target", "Target", ["goal", "aim", "focus"]),
            EaselStampIcon("rosette", "Award", ["badge", "prize", "ribbon"]),
            EaselStampIcon("bookmark", "Bookmark", ["save", "later"]),
            EaselStampIcon("tag", "Tag", ["label", "price", "category"]),
            EaselStampIcon("ladybug", "Bug", ["issue", "defect", "problem"]),
        ]),
    ]

    static let all: [EaselStampIcon] = sections.flatMap(\.icons)

    private static let index: [String: EaselStampIcon] = Dictionary(all.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })

    static func icon(named symbol: String) -> EaselStampIcon? { index[symbol] }

    static func search(_ query: String) -> [EaselStampIcon] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let lowered = trimmed.lowercased()
        let titled = all.filter { $0.title.lowercased().hasPrefix(lowered) }
        return titled + all.filter { !titled.contains($0) && $0.matches(trimmed) }
    }
}

struct EaselStampPath: Equatable {
    enum Element: Equatable {
        case move(EaselPoint)
        case line(EaselPoint)
        case curve(EaselPoint, EaselPoint, EaselPoint)
        case close
    }

    var elements: [Element] = []

    mutating func move(_ x: Double, _ y: Double) { elements.append(.move(EaselPoint(x: x, y: y))) }
    mutating func line(_ x: Double, _ y: Double) { elements.append(.line(EaselPoint(x: x, y: y))) }
    mutating func curve(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double, _ y: Double) {
        elements.append(.curve(EaselPoint(x: x1, y: y1), EaselPoint(x: x2, y: y2), EaselPoint(x: x, y: y)))
    }
    mutating func close() { elements.append(.close) }

    static func + (lhs: EaselStampPath, rhs: EaselStampPath) -> EaselStampPath {
        EaselStampPath(elements: lhs.elements + rhs.elements)
    }

    func mapped(_ transform: (EaselPoint) -> EaselPoint) -> EaselStampPath {
        EaselStampPath(elements: elements.map { element in
            switch element {
            case .move(let point): return .move(transform(point))
            case .line(let point): return .line(transform(point))
            case .curve(let a, let b, let point): return .curve(transform(a), transform(b), transform(point))
            case .close: return .close
            }
        })
    }

    func rotated(by degrees: Double, around centre: EaselPoint) -> EaselStampPath {
        let angle = degrees * .pi / 180, c = cos(angle), s = sin(angle)
        return mapped { point in
            let dx = point.x - centre.x, dy = point.y - centre.y
            return EaselPoint(x: centre.x + dx * c - dy * s, y: centre.y + dx * s + dy * c)
        }
    }

    func translated(_ dx: Double, _ dy: Double) -> EaselStampPath { mapped { EaselPoint(x: $0.x + dx, y: $0.y + dy) } }

    var points: [EaselPoint] {
        elements.flatMap { element -> [EaselPoint] in
            switch element {
            case .move(let point), .line(let point): return [point]
            case .curve(let a, let b, let point): return [a, b, point]
            case .close: return []
            }
        }
    }

    static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> EaselStampPath {
        let k = 0.5522847498
        var path = EaselStampPath()
        path.move(cx + rx, cy)
        path.curve(cx + rx, cy + ry * k, cx + rx * k, cy + ry, cx, cy + ry)
        path.curve(cx - rx * k, cy + ry, cx - rx, cy + ry * k, cx - rx, cy)
        path.curve(cx - rx, cy - ry * k, cx - rx * k, cy - ry, cx, cy - ry)
        path.curve(cx + rx * k, cy - ry, cx + rx, cy - ry * k, cx + rx, cy)
        path.close()
        return path
    }

    static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> EaselStampPath { ellipse(cx, cy, r, r) }

    static func roundedRect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ radius: Double) -> EaselStampPath {
        let r = max(0, min(radius, width / 2, height / 2)), k = 0.5522847498 * r
        var path = EaselStampPath()
        path.move(x + r, y)
        path.line(x + width - r, y)
        path.curve(x + width - r + k, y, x + width, y + r - k, x + width, y + r)
        path.line(x + width, y + height - r)
        path.curve(x + width, y + height - r + k, x + width - r + k, y + height, x + width - r, y + height)
        path.line(x + r, y + height)
        path.curve(x + r - k, y + height, x, y + height - r + k, x, y + height - r)
        path.line(x, y + r)
        path.curve(x, y + r - k, x + r - k, y, x + r, y)
        path.close()
        return path
    }

    static func capsule(from start: EaselPoint, to end: EaselPoint, thickness: Double) -> EaselStampPath {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x) * 180 / .pi
        let centre = EaselPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let width = length + thickness
        return roundedRect(centre.x - width / 2, centre.y - thickness / 2, width, thickness, thickness / 2)
            .rotated(by: angle, around: centre)
    }

    static func roundedPolygon(_ corners: [EaselPoint], rounding: [Double]) -> EaselStampPath {
        guard corners.count >= 3, rounding.count == corners.count else { return EaselStampPath() }
        var path = EaselStampPath()
        let count = corners.count
        func lerp(_ a: EaselPoint, _ b: EaselPoint, _ t: Double) -> EaselPoint {
            EaselPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        for index in 0..<count {
            let corner = corners[index]
            let previous = corners[(index + count - 1) % count], next = corners[(index + 1) % count]
            let t = max(0, min(0.5, rounding[index]))
            let entry = lerp(corner, previous, t), exit = lerp(corner, next, t)
            if index == 0 { path.move(entry.x, entry.y) } else { path.line(entry.x, entry.y) }
            let c1 = lerp(entry, corner, 2.0 / 3.0), c2 = lerp(exit, corner, 2.0 / 3.0)
            path.curve(c1.x, c1.y, c2.x, c2.y, exit.x, exit.y)
        }
        path.close()
        return path
    }

    static func star(centre: EaselPoint, outer: Double, inner: Double, points: Int = 5,
                     outerRounding: Double = 0.2, innerRounding: Double = 0.12) -> EaselStampPath {
        let count = max(3, points) * 2
        var corners: [EaselPoint] = []
        var rounding: [Double] = []
        for index in 0..<count {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -Double.pi / 2 + Double(index) * .pi / Double(count / 2)
            corners.append(EaselPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
            rounding.append(index.isMultiple(of: 2) ? outerRounding : innerRounding)
        }
        return roundedPolygon(corners, rounding: rounding)
    }

    static func ring(centre: EaselPoint, outer: Double, inner: Double, from start: Double, to end: Double) -> EaselStampPath {
        func point(_ degrees: Double, _ radius: Double) -> EaselPoint {
            EaselPoint(x: centre.x + cos(degrees * .pi / 180) * radius, y: centre.y + sin(degrees * .pi / 180) * radius)
        }
        let first = point(start, outer), innerFirst = point(end, inner)
        var path = EaselStampPath()
        path.move(first.x, first.y)
        path.elements += arcCurves(centre: centre, radius: outer, from: start, to: end)
        path.line(innerFirst.x, innerFirst.y)
        path.elements += arcCurves(centre: centre, radius: inner, from: end, to: start)
        path.close()
        return path
    }

    private static func arcCurves(centre: EaselPoint, radius: Double, from start: Double, to end: Double) -> [Element] {
        let sweep = end - start
        let segments = max(1, Int((abs(sweep) / 90).rounded(.up)))
        let step = sweep / Double(segments) * .pi / 180
        let k = 4.0 / 3.0 * tan(step / 4)
        var elements: [Element] = []
        var angle = start * .pi / 180
        for _ in 0..<segments {
            let next = angle + step
            let p0 = EaselPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            let p3 = EaselPoint(x: centre.x + cos(next) * radius, y: centre.y + sin(next) * radius)
            let c1 = EaselPoint(x: p0.x - sin(angle) * radius * k, y: p0.y + cos(angle) * radius * k)
            let c2 = EaselPoint(x: p3.x + sin(next) * radius * k, y: p3.y - cos(next) * radius * k)
            elements.append(.curve(c1, c2, p3))
            angle = next
        }
        return elements
    }

    func svgData(in frame: EaselRect, box: Double = EaselStampArt.box) -> String {
        let sx = frame.width / box, sy = frame.height / box
        let n = EaselVectorExport.number
        func point(_ p: EaselPoint) -> String { n(frame.x + p.x * sx) + " " + n(frame.y + p.y * sy) }
        var data = ""
        for element in elements {
            switch element {
            case .move(let p): data += "M" + point(p)
            case .line(let p): data += "L" + point(p)
            case .curve(let a, let b, let p): data += "C" + point(a) + " " + point(b) + " " + point(p)
            case .close: data += "Z"
            }
        }
        return data
    }
}

enum EaselStampTone: Equatable { case rim, shadow, base, shade, light, glyph, detail, accent }

struct EaselStampLayer: Equatable {
    var path: EaselStampPath
    var tone: EaselStampTone
    var opacity: Double = 1
    var filled = true
    var outline: Double?
}

struct EaselStampColors: Equatable {
    var base: String
    var shade: String
    var light = "#FFFFFF"
    var glyph = "#FFFFFF"
    var detail = "#FFFFFF"
    var accent = "#FFFFFF"
}

enum EaselStampArt {
    static let box = 100.0
    static let rim = "#FFFFFF"
    static let shadow = "#000000"
    static let rimWidth = 9.0
    private static let centre = EaselPoint(x: 50, y: 50)

    static func colors(_ design: EaselStampDesign) -> EaselStampColors {
        switch design {
        case .plusOne: return EaselStampColors(base: "#3D7EF0", shade: "#2C5FC4")
        case .dot: return EaselStampColors(base: "#8B5CF6", shade: "#6B3FD6")
        case .heart: return EaselStampColors(base: "#F2506A", shade: "#CF3550")
        case .question: return EaselStampColors(base: "#F7931E", shade: "#D5760A")
        case .star: return EaselStampColors(base: "#FFC233", shade: "#E59E12", light: "#FFE08A")
        case .thumbsUp: return EaselStampColors(base: "#22B573", shade: "#178F59")
        case .thumbsDown: return EaselStampColors(base: "#F2674A", shade: "#CC4B30")
        case .smiley: return EaselStampColors(base: "#FFCA3A", shade: "#EDA91B", detail: "#5C3B12", accent: "#F27C7C")
        }
    }

    static func hex(_ tone: EaselStampTone, for design: EaselStampDesign) -> String {
        let palette = colors(design)
        switch tone {
        case .rim: return rim
        case .shadow: return shadow
        case .base: return palette.base
        case .shade: return palette.shade
        case .light: return palette.light
        case .glyph: return palette.glyph
        case .detail: return palette.detail
        case .accent: return palette.accent
        }
    }

    static func silhouette(_ design: EaselStampDesign) -> EaselStampPath {
        switch design {
        case .heart: return heart
        case .star: return star(outer: 42, inner: 21)
        default: return .circle(50, 50, 42)
        }
    }

    static func layers(_ design: EaselStampDesign) -> [EaselStampLayer] {
        let outline = silhouette(design)
        var result = [
            EaselStampLayer(path: outline.translated(0, 3), tone: .shadow, opacity: 0.09, outline: rimWidth),
            EaselStampLayer(path: outline.translated(0, 1.4), tone: .shadow, opacity: 0.12, outline: rimWidth),
            EaselStampLayer(path: outline, tone: .rim, outline: rimWidth),
        ]
        switch design {
        case .heart:
            result += [
                EaselStampLayer(path: heart, tone: .shade),
                EaselStampLayer(path: heart.mapped { EaselPoint(x: 50 + ($0.x - 50) * 0.97, y: 47 + ($0.y - 47) * 0.95) }, tone: .base),
                EaselStampLayer(path: EaselStampPath.ellipse(32, 31, 8, 5).rotated(by: -35, around: EaselPoint(x: 32, y: 31)),
                                tone: .light, opacity: 0.5),
            ]
        case .star:
            result += [
                EaselStampLayer(path: star(outer: 42, inner: 21), tone: .shade),
                EaselStampLayer(path: star(outer: 40, inner: 20).translated(0, -1.2), tone: .base),
                EaselStampLayer(path: star(outer: 24, inner: 12).translated(0, 1), tone: .light, opacity: 0.9),
            ]
        default:
            result += disc
            result += glyph(design)
        }
        return result
    }

    private static var disc: [EaselStampLayer] {
        [
            EaselStampLayer(path: .circle(50, 50, 42), tone: .shade),
            EaselStampLayer(path: .circle(50, 48.6, 40.6), tone: .base),
            EaselStampLayer(path: .ellipse(50, 28, 25, 11), tone: .light, opacity: 0.16),
        ]
    }

    private static func glyph(_ design: EaselStampDesign) -> [EaselStampLayer] {
        switch design {
        case .plusOne:
            let plus = EaselStampPath.roundedRect(29, 45.25, 23, 7.5, 3.75) + EaselStampPath.roundedRect(36.75, 37.5, 7.5, 23, 3.75)
            let one = EaselStampPath.roundedRect(60, 30, 9.5, 39, 3.5)
                + EaselStampPath.capsule(from: EaselPoint(x: 64, y: 33.5), to: EaselPoint(x: 55.5, y: 39.5), thickness: 8)
            return [EaselStampLayer(path: plus + one, tone: .glyph)]
        case .question:
            let hook = EaselStampPath.ring(centre: EaselPoint(x: 50, y: 40), outer: 15.5, inner: 7, from: 180, to: 450)
                + EaselStampPath.circle(38.75, 40, 4.25)
                + EaselStampPath.capsule(from: EaselPoint(x: 50, y: 51.5), to: EaselPoint(x: 50, y: 57.5), thickness: 8.5)
            return [EaselStampLayer(path: hook + EaselStampPath.circle(50, 70, 5.5), tone: .glyph)]
        case .thumbsUp:
            return thumb
        case .thumbsDown:
            return thumb.map { layer in
                var flipped = layer
                flipped.path = layer.path.rotated(by: 180, around: centre)
                return flipped
            }
        case .smiley:
            var smile = EaselStampPath()
            smile.move(33, 57)
            smile.curve(39, 70, 61, 70, 67, 57)
            return [
                EaselStampLayer(path: .circle(29.5, 60, 6), tone: .accent, opacity: 0.45),
                EaselStampLayer(path: .circle(70.5, 60, 6), tone: .accent, opacity: 0.45),
                EaselStampLayer(path: .ellipse(38.5, 42, 4.5, 6.5), tone: .detail),
                EaselStampLayer(path: .ellipse(61.5, 42, 4.5, 6.5), tone: .detail),
                EaselStampLayer(path: smile, tone: .detail, filled: false, outline: 6.5),
            ]
        case .dot:
            return [
                EaselStampLayer(path: EaselStampPath.ellipse(37, 34, 11, 7).rotated(by: -35, around: EaselPoint(x: 37, y: 34)),
                                tone: .light, opacity: 0.55),
                EaselStampLayer(path: .circle(29.5, 46, 2.6), tone: .light, opacity: 0.45),
            ]
        case .heart, .star:
            return []
        }
    }

    private static var thumb: [EaselStampLayer] {
        let hand = EaselStampPath.roundedRect(28, 50, 10, 25, 2.5)
            + EaselStampPath.roundedRect(40.5, 48, 32.5, 27, 6.5)
            + EaselStampPath.capsule(from: EaselPoint(x: 48, y: 50), to: EaselPoint(x: 55, y: 30.5), thickness: 11)
        let gaps = [55.0, 61.5, 68].reduce(EaselStampPath()) { path, y in
            path + EaselStampPath.capsule(from: EaselPoint(x: 59, y: y), to: EaselPoint(x: 76, y: y), thickness: 2.4)
        }
        return [EaselStampLayer(path: hand, tone: .glyph), EaselStampLayer(path: gaps, tone: .base)]
    }

    private static var heart: EaselStampPath {
        var path = EaselStampPath()
        path.move(50, 86)
        path.curve(44, 81, 12, 62, 12, 38)
        path.curve(12, 23, 22, 13, 34, 13)
        path.curve(41, 13, 47, 17, 50, 24)
        path.curve(53, 17, 59, 13, 66, 13)
        path.curve(78, 13, 88, 23, 88, 38)
        path.curve(88, 62, 56, 81, 50, 86)
        path.close()
        return path
    }

    private static func star(outer: Double, inner: Double) -> EaselStampPath {
        .star(centre: EaselPoint(x: 50, y: 53), outer: outer, inner: inner)
    }
}

extension EaselVectorExport {
    static func stamp(_ item: EaselItem, _ picture: EaselVectorImage?) -> String {
        guard let face = EaselStampFace(item: item) else { return "" }
        let f = item.frame
        switch face {
        case .design(let design):
            let scale = min(f.width, f.height) / EaselStampArt.box
            var result = "<g class=\"easel-stamp\">"
            for layer in EaselStampArt.layers(design) {
                let color = EaselStampArt.hex(layer.tone, for: design)
                var style = layer.filled ? "fill:" + color : "fill:none"
                if let width = layer.outline {
                    style += ";stroke:" + color + ";stroke-width:" + number(width * scale) + ";stroke-linejoin:round;stroke-linecap:round"
                }
                if layer.opacity < 1 { style += ";opacity:" + number(layer.opacity) }
                result += "<path d=\"" + layer.path.svgData(in: f) + "\" style=\"" + style + "\"/>"
            }
            return result + "</g>"
        case .emoji(let character):
            let size = min(f.width, f.height) * EaselStamps.emojiScale
            if EaselStampFace.customName(in: character) != nil, let picture {
                let geometry = "x=\"" + number(f.x + (f.width - size) / 2) + "\" y=\"" + number(f.y + (f.height - size) / 2) + "\" width=\""
                    + number(size) + "\" height=\"" + number(size) + "\""
                return "<image " + geometry + " preserveAspectRatio=\"xMidYMid meet\" href=\"" + picture.dataURI + "\"/>"
            }
            let shown = EaselStampFace.customName(in: character) == nil ? size : min(size, f.width * 0.9 / (Double(character.count) * 0.55))
            return "<text x=\"" + number(f.x + f.width / 2) + "\" y=\"" + number(f.y + f.height / 2)
                + "\" text-anchor=\"middle\" dominant-baseline=\"central\" style=\"font-family:'Apple Color Emoji','Segoe UI Emoji','Noto Color Emoji',sans-serif;font-size:"
                + number(shown) + "px\">" + escape(character) + "</text>"
        case .icon:
            guard let picture else { return "" }
            let id = "stamp-" + item.id.uuidString.lowercased()
            let geometry = "x=\"" + number(f.x) + "\" y=\"" + number(f.y) + "\" width=\"" + number(f.width) + "\" height=\"" + number(f.height) + "\""
            return "<mask id=\"" + id + "\" maskUnits=\"userSpaceOnUse\" " + geometry + "><image " + geometry
                + " preserveAspectRatio=\"none\" href=\"" + picture.dataURI + "\"/></mask><rect " + geometry + " mask=\"url(#" + id
                + ")\" style=\"fill:" + paint(item.color) + "\"/>"
        }
    }
}
