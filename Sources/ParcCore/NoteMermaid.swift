import Foundation

enum NoteMermaid {
    static let languageID = "mermaid"
    static let typingDelay: TimeInterval = 0.3
    static let renderTimeout: TimeInterval = 12

    static func isMermaid(_ language: String) -> Bool {
        NoteCodeLanguage.named(language)?.id == languageID
    }

    static func isDiagram(_ block: NoteBlock) -> Bool {
        block.kind == .code && isMermaid(block.props.language)
    }

    static func storedMode(of block: NoteBlock) -> NoteDiagramMode {
        block.props.diagramMode ?? .preview
    }

    static func presentedMode(stored: NoteDiagramMode, editing: Bool) -> NoteDiagramMode {
        stored == .preview && editing ? .split : stored
    }

    static func normalizedSource(_ text: String) -> String {
        guard text.contains("\r") else { return text }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func hasContent(_ source: String) -> Bool {
        source.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }

    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct NoteMermaidTheme: Hashable, Sendable {
    var dark: Bool
    var fontFamily: String
    var fontSize: Double
    var faces: [String]
    var variables: [String: String]
    var chartPalette: [String]

    static func note(dark: Bool, font: NotePageFont = .standard, small: Bool = false) -> NoteMermaidTheme {
        let type = NoteMermaidPalette.typeface(font, small: small)
        var variables = dark ? NoteMermaidPalette.dark : NoteMermaidPalette.light
        variables["fontFamily"] = type.family
        variables["fontSize"] = NoteMermaidPalette.cssSize(type.size)
        return NoteMermaidTheme(dark: dark, fontFamily: type.family, fontSize: type.size, faces: type.faces,
                                variables: variables, chartPalette: dark ? NoteMermaidPalette.darkChart : NoteMermaidPalette.lightChart)
    }

    func configuration(seed: String) -> [String: Any] {
        var themeVariables: [String: Any] = variables
        themeVariables["darkMode"] = dark
        let palette = chartPalette.joined(separator: ", ")
        themeVariables["xyChart"] = ["plotColorPalette": palette, "backgroundColor": "transparent",
                                     "titleColor": variables["titleColor"] ?? "", "xAxisLabelColor": variables["textColor"] ?? "",
                                     "yAxisLabelColor": variables["textColor"] ?? "", "xAxisLineColor": variables["lineColor"] ?? "",
                                     "yAxisLineColor": variables["lineColor"] ?? "", "xAxisTickColor": variables["lineColor"] ?? "",
                                     "yAxisTickColor": variables["lineColor"] ?? "", "xAxisTitleColor": variables["textColor"] ?? "",
                                     "yAxisTitleColor": variables["textColor"] ?? ""]
        themeVariables["radar"] = ["curveOpacity": 0.35, "graticuleColor": variables["lineColor"] ?? ""] as [String: Any]
        return [
            "startOnLoad": false,
            "theme": "base",
            "darkMode": dark,
            "look": "classic",
            "securityLevel": "strict",
            "suppressErrorRendering": true,
            "deterministicIds": true,
            "deterministicIDSeed": seed,
            "fontFamily": fontFamily,
            "fontSize": fontSize,
            "themeVariables": themeVariables,
        ]
    }

    var signature: String { NoteMermaid.json(configuration(seed: "")) + "\u{1}" + faces.joined(separator: "\u{2}") }
    var facesJSON: String { NoteMermaid.json(faces) }
}

enum NoteMermaidPalette {
    static func typeface(_ font: NotePageFont, small: Bool) -> (family: String, size: Double, faces: [String]) {
        switch font {
        case .standard:
            return ("\"Nunito\", ui-rounded, \"SF Pro Rounded\", -apple-system, BlinkMacSystemFont, \"Segoe UI\", \"Helvetica Neue\", Arial, sans-serif",
                    small ? 14 : 16, ["400 16px \"Nunito\"", "700 16px \"Nunito\""])
        case .serif:
            return ("\"EB Garamond\", Georgia, \"Times New Roman\", serif", small ? 15 : 17,
                    ["400 16px \"EB Garamond\"", "700 16px \"EB Garamond\""])
        case .mono:
            return ("\"Space Mono\", ui-monospace, \"SF Mono\", Menlo, Consolas, monospace", small ? 12 : 13.5,
                    ["400 16px \"Space Mono\"", "700 16px \"Space Mono\""])
        case .wide:
            return ("\"ParcWide\", -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Arial, sans-serif", small ? 12.5 : 14,
                    ["400 16px \"ParcWide\"", "600 16px \"ParcWide\""])
        }
    }

    static func cssSize(_ size: Double) -> String {
        size.rounded() == size ? String(Int(size)) + "px" : String(size) + "px"
    }

    static let lightChart = ["#7B66E0", "#3D8FC4", "#4F9A6E", "#E8B53A", "#E8892E", "#E05A52", "#D45A9A", "#9A6FC4",
                             "#A8765E", "#8C8B87", "#3FA39A", "#B59A4A"]
    static let darkChart = ["#9380E0", "#3D9CDB", "#52A877", "#D9A94A", "#D98A4E", "#E5605A", "#DB5C9F", "#A374DB",
                            "#BA856F", "#9B9B9B", "#4FB3A9", "#C2B07A"]
    private static let lightScale = ["#D9D2F7", "#CFE3F1", "#D3E8DA", "#F6E6B4", "#F6D6B8", "#F6CFCC", "#F1CFE1", "#E2D5EE",
                                     "#E6D6CE", "#E0DFDC", "#C9E7E3", "#E8E1C6"]
    private static let darkScale = ["#3C3566", "#1E4257", "#23443A", "#554623", "#5A3B22", "#5A2E2B", "#522C40", "#3E2E52",
                                    "#4A3228", "#3A3A3A", "#1F4A47", "#4A4430"]
    private static let lightPeers = ["#9E8DE4", "#6FA8CF", "#78AE8D", "#D9B65A", "#DE9E62", "#DE837D", "#D688B0", "#AE8FCB",
                                     "#B8917E", "#A7A6A2", "#6DB3AB", "#BFA968"]
    private static let darkPeers = ["#8C7BDB", "#3F86B3", "#4C9470", "#B8923F", "#B9773F", "#C25550", "#B9548A", "#9168BE",
                                    "#9C705C", "#7E7E7E", "#3F9890", "#A3925F"]

    private static func scale(_ fills: [String], peers: [String], label: String) -> [String: String] {
        var result: [String: String] = [:]
        for (index, fill) in fills.enumerated() {
            result["cScale\(index)"] = fill
            result["cScalePeer\(index)"] = peers[index]
            result["cScaleLabel\(index)"] = label
        }
        return result
    }

    private static func chart(_ colors: [String], text: String) -> [String: String] {
        var result: [String: String] = [:]
        for (index, color) in colors.enumerated() {
            result["pie\(index + 1)"] = color
            if index < 8 {
                result["git\(index)"] = color
                result["gitBranchLabel\(index)"] = text
            }
        }
        return result
    }

    static let light: [String: String] = {
        let ink = "#1F1B2E", card = "#F4F4F5", line = "#6E6880"
        var values: [String: String] = [
            "background": card, "textColor": ink, "titleColor": "#220C7F", "lineColor": line, "defaultLinkColor": line,
            "primaryColor": "#ECE9FB", "primaryBorderColor": "#9E8DE4", "primaryTextColor": ink,
            "secondaryColor": "#FBF3DB", "secondaryBorderColor": "#D9C27A", "secondaryTextColor": ink,
            "tertiaryColor": "#E7F3F8", "tertiaryBorderColor": "#8FBFDA", "tertiaryTextColor": ink,
            "mainBkg": "#ECE9FB", "nodeBorder": "#9E8DE4", "nodeTextColor": ink,
            "clusterBkg": "#F7F6FD", "clusterBorder": "#C9C1F0", "edgeLabelBackground": card,
            "noteBkgColor": "#FBF3DB", "noteBorderColor": "#D9C27A", "noteTextColor": ink,
            "actorBkg": "#ECE9FB", "actorBorder": "#9E8DE4", "actorTextColor": ink, "actorLineColor": line,
            "signalColor": ink, "signalTextColor": ink, "labelBoxBkgColor": "#ECE9FB", "labelBoxBorderColor": "#9E8DE4",
            "labelTextColor": ink, "loopTextColor": ink, "activationBkgColor": "#DCD5F8", "activationBorderColor": "#9E8DE4",
            "sequenceNumberColor": "#FFFFFF",
            "sectionBkgColor": "#ECE9FB", "altSectionBkgColor": card, "sectionBkgColor2": "#E7F3F8",
            "taskBkgColor": "#9E8DE4", "taskBorderColor": "#7B66E0", "taskTextColor": "#FFFFFF", "taskTextLightColor": "#FFFFFF",
            "taskTextOutsideColor": ink, "taskTextClickableColor": "#2702C2", "activeTaskBkgColor": "#D9D2F7",
            "activeTaskBorderColor": "#7B66E0", "doneTaskBkgColor": "#D3E8DA", "doneTaskBorderColor": "#78AE8D",
            "critBkgColor": "#F6CFCC", "critBorderColor": "#E05A52", "gridColor": "#D9D7DE", "todayLineColor": "#E05A52",
            "excludeBkgColor": "#EFEFF1",
            "pieStrokeColor": card, "pieOuterStrokeColor": card, "pieTitleTextColor": ink, "pieSectionTextColor": "#FFFFFF",
            "pieLegendTextColor": ink, "pieStrokeWidth": "2px", "pieOuterStrokeWidth": "0px", "pieOpacity": "1",
            "commitLabelColor": ink, "commitLabelBackground": card, "tagLabelColor": ink, "tagLabelBackground": "#ECE9FB",
            "tagLabelBorder": "#9E8DE4",
            "quadrant1Fill": "#ECE9FB", "quadrant2Fill": "#E7F3F8", "quadrant3Fill": "#EDF3EC", "quadrant4Fill": "#FBF3DB",
            "quadrant1TextFill": ink, "quadrant2TextFill": ink, "quadrant3TextFill": ink, "quadrant4TextFill": ink,
            "quadrantPointFill": "#7B66E0", "quadrantPointTextFill": ink, "quadrantXAxisTextFill": ink,
            "quadrantYAxisTextFill": ink, "quadrantInternalBorderStrokeFill": "#C9C1F0",
            "quadrantExternalBorderStrokeFill": "#9E8DE4", "quadrantTitleFill": ink,
            "relationColor": line, "relationLabelColor": ink, "relationLabelBackground": card,
            "requirementBackground": "#ECE9FB", "requirementBorderColor": "#9E8DE4", "requirementTextColor": ink,
            "personBorder": "#9E8DE4", "personBkg": "#ECE9FB",
            "errorBkgColor": "#FDEBEC", "errorTextColor": "#D0300F",
        ]
        values.merge(scale(lightScale, peers: lightPeers, label: ink)) { _, new in new }
        values.merge(chart(lightChart, text: "#FFFFFF")) { _, new in new }
        return values
    }()

    static let dark: [String: String] = {
        let ink = "#EDEBFA", card = "#242230", line = "#A7A3B8"
        var values: [String: String] = [
            "background": card, "textColor": ink, "titleColor": "#E6E6FF", "lineColor": line, "defaultLinkColor": line,
            "primaryColor": "#37315A", "primaryBorderColor": "#8C7BDB", "primaryTextColor": ink,
            "secondaryColor": "#4A3F22", "secondaryBorderColor": "#8A7440", "secondaryTextColor": ink,
            "tertiaryColor": "#183B4C", "tertiaryBorderColor": "#3F7FA3", "tertiaryTextColor": ink,
            "mainBkg": "#37315A", "nodeBorder": "#8C7BDB", "nodeTextColor": ink,
            "clusterBkg": "#2B2840", "clusterBorder": "#574E8C", "edgeLabelBackground": card,
            "noteBkgColor": "#4A3F22", "noteBorderColor": "#8A7440", "noteTextColor": ink,
            "actorBkg": "#37315A", "actorBorder": "#8C7BDB", "actorTextColor": ink, "actorLineColor": line,
            "signalColor": ink, "signalTextColor": ink, "labelBoxBkgColor": "#37315A", "labelBoxBorderColor": "#8C7BDB",
            "labelTextColor": ink, "loopTextColor": ink, "activationBkgColor": "#403A66", "activationBorderColor": "#8C7BDB",
            "sequenceNumberColor": "#16141F",
            "sectionBkgColor": "#37315A", "altSectionBkgColor": card, "sectionBkgColor2": "#183B4C",
            "taskBkgColor": "#6F5FC7", "taskBorderColor": "#9380E0", "taskTextColor": ink, "taskTextLightColor": ink,
            "taskTextOutsideColor": ink, "taskTextClickableColor": "#B9ABF0", "activeTaskBkgColor": "#3C3566",
            "activeTaskBorderColor": "#9380E0", "doneTaskBkgColor": "#23443A", "doneTaskBorderColor": "#4C9470",
            "critBkgColor": "#5A2E2B", "critBorderColor": "#E5605A", "gridColor": "#3D3A4C", "todayLineColor": "#E5605A",
            "excludeBkgColor": "#2C2A38",
            "pieStrokeColor": card, "pieOuterStrokeColor": card, "pieTitleTextColor": ink, "pieSectionTextColor": "#16141F",
            "pieLegendTextColor": ink, "pieStrokeWidth": "2px", "pieOuterStrokeWidth": "0px", "pieOpacity": "1",
            "commitLabelColor": ink, "commitLabelBackground": card, "tagLabelColor": ink, "tagLabelBackground": "#37315A",
            "tagLabelBorder": "#8C7BDB",
            "quadrant1Fill": "#37315A", "quadrant2Fill": "#183B4C", "quadrant3Fill": "#243D30", "quadrant4Fill": "#4A3F22",
            "quadrant1TextFill": ink, "quadrant2TextFill": ink, "quadrant3TextFill": ink, "quadrant4TextFill": ink,
            "quadrantPointFill": "#9380E0", "quadrantPointTextFill": ink, "quadrantXAxisTextFill": ink,
            "quadrantYAxisTextFill": ink, "quadrantInternalBorderStrokeFill": "#574E8C",
            "quadrantExternalBorderStrokeFill": "#8C7BDB", "quadrantTitleFill": ink,
            "relationColor": line, "relationLabelColor": ink, "relationLabelBackground": card,
            "requirementBackground": "#37315A", "requirementBorderColor": "#8C7BDB", "requirementTextColor": ink,
            "personBorder": "#8C7BDB", "personBkg": "#37315A",
            "errorBkgColor": "#522E2A", "errorTextColor": "#FF7B5E",
        ]
        values.merge(scale(darkScale, peers: darkPeers, label: ink)) { _, new in new }
        values.merge(chart(darkChart, text: "#16141F")) { _, new in new }
        return values
    }()
}

struct NoteMermaidRequest: Hashable, Sendable {
    let source: String
    let theme: NoteMermaidTheme
    let key: String
    let layoutKey: String

    init(source: String, theme: NoteMermaidTheme) {
        let normalized = NoteMermaid.normalizedSource(source)
        self.source = normalized
        self.theme = theme
        key = NoteMermaid.fingerprint(theme.signature + "\u{0}" + normalized)
        layoutKey = NoteMermaid.fingerprint(theme.fontFamily + "\u{0}" + String(theme.fontSize) + "\u{0}" + normalized)
    }

    var elementID: String { "parc-mermaid-" + key }
    var configurationJSON: String { NoteMermaid.json(theme.configuration(seed: elementID)) }

    static func == (lhs: NoteMermaidRequest, rhs: NoteMermaidRequest) -> Bool {
        lhs.key == rhs.key && lhs.source == rhs.source && lhs.theme == rhs.theme
    }

    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

struct NoteMermaidDrawing: Sendable {
    var svg: String
    var size: CGSize
    var pdf: Data

    var cost: Int { svg.utf8.count + pdf.count }
}

enum NoteMermaidOutcome: Sendable {
    case drawing(NoteMermaidDrawing)
    case failure(String)
    case unavailable(String)

    var isCacheable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var drawing: NoteMermaidDrawing? {
        if case .drawing(let drawing) = self { return drawing }
        return nil
    }

    var cost: Int {
        switch self {
        case .drawing(let drawing): return drawing.cost
        case .failure(let message), .unavailable(let message): return message.utf8.count
        }
    }

    static func parse(_ reply: Any?) -> (outcome: NoteMermaidOutcome, origin: CGPoint)? {
        guard let reply = reply as? [String: Any] else { return nil }
        if reply["ok"] as? Bool != true {
            let message = (reply["message"] as? String).map(NoteMermaidProblem.clean) ?? ""
            return (.failure(message.isEmpty ? NoteMermaidProblem.fallback : message), .zero)
        }
        guard let svg = reply["svg"] as? String, !svg.isEmpty,
              let width = (reply["width"] as? NSNumber)?.doubleValue, let height = (reply["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        let x = (reply["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (reply["y"] as? NSNumber)?.doubleValue ?? 0
        let drawing = NoteMermaidDrawing(svg: svg, size: CGSize(width: ceil(width), height: ceil(height)), pdf: Data())
        return (.drawing(drawing), CGPoint(x: x.isFinite ? x : 0, y: y.isFinite ? y : 0))
    }
}

struct NoteMermaidProblem: Equatable, Sendable {
    static let fallback = "Mermaid couldn't draw this diagram."

    var headline: String
    var detail: String?
    var line: Int?

    init(message: String) {
        let lines = Self.clean(message).components(separatedBy: "\n")
        var first = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        if first.hasSuffix(":") { first.removeLast() }
        headline = first.isEmpty ? Self.fallback : first
        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
        detail = rest.isEmpty ? nil : rest
        line = Self.lineNumber(in: first)
    }

    static func clean(_ message: String) -> String {
        NoteMermaid.normalizedSource(message).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func lineNumber(in text: String) -> Int? {
        let lowered = text.lowercased()
        guard let marker = lowered.range(of: "on line ") else { return nil }
        let digits = lowered[marker.upperBound...].prefix(while: { $0.isASCII && $0.isNumber })
        return Int(digits).flatMap { $0 > 0 ? $0 : nil }
    }

    func range(in source: String) -> Range<Int>? {
        guard let line else { return nil }
        let text = source as NSString
        var starts: [Int] = [0]
        var index = 0
        while index < text.length {
            if text.character(at: index) == 10 { starts.append(index + 1) }
            index += 1
        }
        func bounds(_ row: Int) -> Range<Int> {
            let start = starts[row]
            let end = row + 1 < starts.count ? starts[row + 1] - 1 : text.length
            return start..<max(start, end)
        }
        var row = min(line, starts.count) - 1
        while row > 0, bounds(row).isEmpty || !NoteMermaid.hasContent(text.substring(with: NSRange(location: bounds(row).lowerBound, length: bounds(row).count))) {
            row -= 1
        }
        let found = bounds(row)
        return found.isEmpty ? nil : found
    }
}

struct NoteMermaidCache<Value> {
    let capacity: Int
    let costLimit: Int
    private var entries: [String: (value: Value, cost: Int, stamp: UInt64)] = [:]
    private var clock: UInt64 = 0
    private(set) var totalCost = 0

    init(capacity: Int, costLimit: Int) {
        self.capacity = max(1, capacity)
        self.costLimit = max(1, costLimit)
    }

    var count: Int { entries.count }
    var keys: [String] { entries.sorted { $0.value.stamp < $1.value.stamp }.map(\.key) }

    func peek(_ key: String) -> Value? { entries[key]?.value }

    mutating func value(for key: String) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.stamp = clock
        entries[key] = entry
        return entry.value
    }

    mutating func insert(_ value: Value, for key: String, cost: Int) {
        clock &+= 1
        if let old = entries[key] { totalCost -= old.cost }
        let weight = max(0, cost)
        entries[key] = (value, weight, clock)
        totalCost += weight
        while entries.count > 1, entries.count > capacity || totalCost > costLimit,
              let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key, oldest != key {
            remove(oldest)
        }
    }

    mutating func remove(_ key: String) {
        guard let old = entries.removeValue(forKey: key) else { return }
        totalCost -= old.cost
    }

    mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}

struct NoteMermaidQueue {
    private(set) var running: NoteMermaidRequest?
    private(set) var pending: [NoteMermaidRequest] = []
    private var interest: [Int: String] = [:]

    var isIdle: Bool { running == nil }
    var pendingKeys: [String] { pending.map(\.key) }

    func wants(_ key: String) -> Bool { interest.values.contains(key) }
    func key(for client: Int) -> String? { interest[client] }

    mutating func submit(_ request: NoteMermaidRequest, client: Int) {
        let previous = interest[client]
        interest[client] = request.key
        if let previous, previous != request.key { dropIfUnwanted(previous) }
        guard running?.key != request.key, !pending.contains(where: { $0.key == request.key }) else { return }
        pending.append(request)
    }

    mutating func withdraw(_ client: Int) {
        guard let key = interest.removeValue(forKey: client) else { return }
        dropIfUnwanted(key)
    }

    mutating func start() -> NoteMermaidRequest? {
        guard running == nil, !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        running = next
        return next
    }

    mutating func finish(_ key: String) -> [Int] {
        if running?.key == key { running = nil }
        pending.removeAll { $0.key == key }
        let clients = interest.filter { $0.value == key }.map(\.key).sorted()
        for client in clients { interest.removeValue(forKey: client) }
        return clients
    }

    mutating func requeueRunning() {
        guard let running else { return }
        self.running = nil
        if wants(running.key), !pending.contains(where: { $0.key == running.key }) { pending.insert(running, at: 0) }
    }

    mutating func failAll() -> [Int] {
        running = nil
        pending.removeAll()
        let clients = interest.keys.sorted()
        interest.removeAll()
        return clients
    }

    private mutating func dropIfUnwanted(_ key: String) {
        guard !wants(key) else { return }
        pending.removeAll { $0.key == key }
    }
}

struct NoteDiagramArt: Sendable {
    var light: String
    var dark: String?
}
