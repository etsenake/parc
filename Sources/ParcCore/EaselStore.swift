import Foundation
import Combine
import Darwin

enum EaselItemKind: String, Codable, CaseIterable {
    case text, image, rectangle, circle, arrow, freehand, webCard, browser, link, sticky, section, table, code, stamp, video

    var holdsText: Bool { self == .text || self == .sticky || self == .rectangle || self == .circle }
}

enum EaselShape: String, Codable, CaseIterable {
    case rectangle, roundedRectangle, ellipse, diamond, triangle, triangleDown, parallelogram, trapezoid,
         pentagon, hexagon, octagon, star, plus, speechBubble, arrowLeft, arrowRight, arrowUp, arrowDown,
         chevron, cylinder, parallelogramLeft, cylinderHorizontal, file, folder, document, documents,
         predefinedProcess, shield, manualInput, internalStorage, or, summingJunction
}

enum EaselStrokeDash: String, Codable, CaseIterable { case solid, dashed, dotted }

enum EaselArrowHead: String, Codable, CaseIterable {
    case none, arrow, triangle, circle, diamond, bar, solidArrow,
         erdOne, erdMany, erdExactlyOne, erdZeroOrOne, erdOneOrMore, erdZeroOrMore
}

enum EaselConnectorRouting: String, Codable, CaseIterable { case straight, elbow, curved }

enum EaselBrush: String, Codable, CaseIterable { case marker, highlighter, washi }

enum EaselImageMask: String, Codable, CaseIterable { case rounded, circle, squircle, arch, diamond, hexagon, star, heart }

enum EaselAssetType: String, CaseIterable {
    case png, gif, mp4, mov

    var isVideo: Bool { self == .mp4 || self == .mov }

    static func of(assetID: String) -> EaselAssetType? {
        guard let dot = assetID.lastIndex(of: ".") else { return nil }
        return EaselAssetType(rawValue: String(assetID[assetID.index(after: dot)...]))
    }

    static func sniff(_ data: Data) -> EaselAssetType? {
        let head = [UInt8](data.prefix(64))
        if head.count >= 24, head.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), Array(head[12..<16]) == Array("IHDR".utf8) { return .png }
        if head.count >= 13, head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) {
            let width = Int(head[6]) | Int(head[7]) << 8, height = Int(head[8]) | Int(head[9]) << 8
            return width > 0 && height > 0 ? .gif : nil
        }
        guard head.count >= 16, String(decoding: head[4..<8], as: UTF8.self) == "ftyp" else { return nil }
        let size = head[0..<4].reduce(0) { $0 << 8 | Int($1) }
        guard size >= 16, size % 4 == 0, size <= 4096 else { return nil }
        var brands = [String(decoding: head[8..<12], as: UTF8.self)]
        var offset = 16
        while offset + 4 <= min(size, head.count) {
            brands.append(String(decoding: head[offset..<(offset + 4)], as: UTF8.self))
            offset += 4
        }
        if brands.contains("qt  ") { return .mov }
        return brands.contains(where: movieBrands.contains) ? .mp4 : nil
    }

    private static let movieBrands: Set<String> = ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "mp41", "mp42", "avc1", "M4V ", "M4VP",
                                                   "M4VH", "MSNV", "NDAS", "dash", "f4v ", "mmp4", "3gp4", "3gp5", "3gp6", "3g2a", "hvc1", "hev1"]
}

enum EaselStampDesign: String, CaseIterable { case plusOne, dot, heart, question, star, thumbsUp, thumbsDown, smiley }

enum EaselStampFace: Hashable {
    case design(EaselStampDesign)
    case emoji(String)
    case icon(String)

    static let iconPrefix = "icon:"
    static let maximumEmojiBytes = 64
    static let maximumSymbolLength = 96

    init?(item: EaselItem) {
        guard item.kind == .stamp else { return nil }
        if let name = item.stamp {
            guard item.text.isEmpty, let design = EaselStampDesign(rawValue: name) else { return nil }
            self = .design(design)
        } else {
            guard let face = EaselStampFace(text: item.text) else { return nil }
            self = face
        }
    }

    init?(text: String) {
        if text.hasPrefix(Self.iconPrefix) {
            let name = String(text.dropFirst(Self.iconPrefix.count))
            guard Self.isSymbolName(name) else { return nil }
            self = .icon(name)
        } else {
            guard Self.isEmoji(text) else { return nil }
            self = .emoji(text)
        }
    }

    init?(token: String) {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let value = String(token[token.index(after: colon)...])
        switch String(token[..<colon]) {
        case "stamp":
            guard let design = EaselStampDesign(rawValue: value) else { return nil }
            self = .design(design)
        case "emoji":
            guard Self.isEmoji(value) else { return nil }
            self = .emoji(value)
        case "icon":
            guard Self.isSymbolName(value) else { return nil }
            self = .icon(value)
        default:
            return nil
        }
    }

    var token: String {
        switch self {
        case .design(let design): return "stamp:" + design.rawValue
        case .emoji(let character): return "emoji:" + character
        case .icon(let name): return "icon:" + name
        }
    }

    var stamp: String? {
        if case .design(let design) = self { return design.rawValue }
        return nil
    }

    var text: String {
        switch self {
        case .design: return ""
        case .emoji(let character): return character
        case .icon(let name): return Self.iconPrefix + name
        }
    }

    var isIcon: Bool {
        if case .icon = self { return true }
        return false
    }

    func apply(to item: inout EaselItem) {
        item.stamp = stamp
        item.text = text
    }

    init?(emoji text: String) {
        var scalars = Array(text.unicodeScalars)
        if let first = scalars.first, !first.isASCII, first.properties.isEmoji, !first.properties.isEmojiPresentation,
           scalars.count == 1 || !Self.qualifies(scalars[1]) {
            scalars.insert("\u{FE0F}", at: 1)
        }
        var normalized = ""
        normalized.unicodeScalars.append(contentsOf: scalars)
        guard Self.isEmoji(normalized) else { return nil }
        self = .emoji(normalized)
    }

    private static func qualifies(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0xFE0F || (0x1F3FB...0x1F3FF).contains(scalar.value)
    }

    static func isEmoji(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.count <= maximumEmojiBytes, text.count == 1 else { return false }
        let scalars = Array(text.unicodeScalars)
        guard let first = scalars.first,
              !scalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.isWhitespace }) else { return false }
        if first.isASCII { return scalars.count == 3 && scalars[1].value == 0xFE0F && scalars[2].value == 0x20E3 && first.properties.isEmoji }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && scalars.count > 1 && qualifies(scalars[1])
    }

    static func isSymbolName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= maximumSymbolLength, !name.hasPrefix("."), !name.hasSuffix("."),
              !name.contains("..") else { return false }
        return name.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 46 }
    }

    static func validationProblem(_ item: EaselItem) -> String? {
        guard item.kind == .stamp else { return item.stamp == nil ? nil : "stamp face on a non-stamp object" }
        guard EaselStampFace(item: item) != nil else { return "stamp face" }
        guard item.points.isEmpty, item.url == nil, item.assetID == nil, item.richText == nil, item.textStyle == nil else {
            return "stamp contents"
        }
        return nil
    }
}

struct EaselConnection: Codable, Equatable {
    enum Side: String, Codable, CaseIterable { case top, right, bottom, left }
    var itemID: UUID
    var side: Side?
    var anchor: EaselPoint?
}

struct EaselPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct EaselRect: Codable, Equatable {
    static let maximumCoordinate = 1_000_000.0
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct EaselScrollContainer: Codable, Equatable {
    static let maximumCount = 8

    var anchorID: String?
    var path: String
    var scroll: EaselPoint
    var frame: EaselRect

    var isValid: Bool {
        [scroll.x, scroll.y, frame.x, frame.y, frame.width, frame.height].allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && frame.width >= 0 && frame.height >= 0 && (anchorID.map(Self.isValidAnchor) ?? true) && Self.isValidPath(path)
    }

    static func isValidAnchor(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, id.utf8.count <= 128, first.isASCII, CharacterSet.letters.contains(first) else { return false }
        var digits = 0
        for scalar in id.unicodeScalars {
            guard scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" else { return false }
            digits = CharacterSet.decimalDigits.contains(scalar) ? digits + 1 : 0
            if digits >= 3 { return false }
        }
        return true
    }

    static func isValidPath(_ path: String) -> Bool {
        if path.isEmpty { return true }
        let steps = path.split(separator: ">", omittingEmptySubsequences: false)
        guard path.utf8.count <= 2048, steps.count <= 128 else { return false }
        return steps.allSatisfy { step in
            if step == "^" { return true }
            let parts = step.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, (1...64).contains(parts[0].utf8.count), (1...5).contains(parts[1].utf8.count) else { return false }
            return parts[0].unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)) }
                && parts[1].unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.decimalDigits.contains($0) }
        }
    }

    static func encode(_ containers: [EaselScrollContainer]) -> String {
        containers.map { container in
            [container.anchorID.map { "#" + $0 } ?? "-", container.path.isEmpty ? "-" : container.path,
             number([container.scroll.x, container.scroll.y]),
             number([container.frame.x, container.frame.y, container.frame.width, container.frame.height])].joined(separator: " ")
        }.joined(separator: ";")
    }

    static func decode(_ text: String) -> [EaselScrollContainer]? {
        guard !text.isEmpty, text.utf8.count <= 24_576 else { return nil }
        let entries = text.split(separator: ";", omittingEmptySubsequences: false)
        guard entries.count <= maximumCount else { return nil }
        var containers: [EaselScrollContainer] = []
        for entry in entries {
            let fields = entry.split(separator: " ", omittingEmptySubsequences: false)
            guard fields.count == 4, fields[0] == "-" || fields[0].hasPrefix("#"),
                  let scroll = numbers(fields[2], count: 2), let frame = numbers(fields[3], count: 4) else { return nil }
            let container = EaselScrollContainer(anchorID: fields[0] == "-" ? nil : String(fields[0].dropFirst()),
                path: fields[1] == "-" ? "" : String(fields[1]), scroll: EaselPoint(x: scroll[0], y: scroll[1]),
                frame: EaselRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]))
            guard container.isValid else { return nil }
            containers.append(container)
        }
        return containers
    }

    private static func numbers(_ text: Substring, count: Int) -> [Double]? {
        let values = text.split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) }
        return values.count == count && text.split(separator: ",", omittingEmptySubsequences: false).count == count
            && values.allSatisfy(\.isFinite) ? values : nil
    }

    private static func number(_ values: [Double]) -> String {
        values.map { value in
            let rounded = value.isFinite ? (value * 100).rounded() / 100 : 0
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }.joined(separator: ",")
    }
}

struct EaselCaptureLayout: Codable, Equatable {
    var viewport: EaselPoint
    var scroll: EaselPoint
    var region: EaselRect
    var scrollContainers: [EaselScrollContainer]? = nil

    var isValid: Bool {
        [viewport.x, viewport.y, scroll.x, scroll.y, region.x, region.y, region.width, region.height]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && viewport.x >= 1 && viewport.y >= 1 && viewport.x <= 16_384 && viewport.y <= 16_384
            && region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
            && region.x + region.width <= viewport.x + 1 && region.y + region.height <= viewport.y + 1
            && (scrollContainers.map { !$0.isEmpty && $0.count <= EaselScrollContainer.maximumCount && $0.allSatisfy(\.isValid) } ?? true)
    }
}

struct EaselTextStyle: Codable, Equatable {
    enum Family: String, Codable, CaseIterable { case mono, fancy, hip, clean }
    enum Size: String, Codable, CaseIterable {
        case body, h2, h1, h0, ultra
        var index: Int { Self.allCases.firstIndex(of: self)! }
        func shifted(by delta: Int) -> Size { Self.allCases[min(4, max(0, index + delta))] }
    }
    enum Fill: String, Codable { case none, contentHugging }
    enum Alignment: String, Codable, CaseIterable { case left, center, right }
    static let textScales = 0.25...8.0
    static let customSizes: ClosedRange<Double> = 8...400
    var fill: Fill?
    var resolvedFill: Fill { fill ?? .none }
    var alignment: Alignment?
    var textScale: Double?
    var family: Family = .clean
    var size: Size = .body
    var customSize: Double?
    var autoWidth: Bool?
    var presetPointSize: Double {
        switch family {
        case .mono, .clean: return [15, 24, 44, 60, 80][size.index]
        case .fancy: return [16, 28, 48, 60, 80][size.index]
        case .hip: return [18, 21, 44, 60, 80][size.index]
        }
    }
    var pointSize: Double { customSize ?? presetPointSize }
}

struct EaselMindMapLink: Codable, Equatable {
    enum Side: String, Codable, CaseIterable { case left, right }
    var parent: UUID?
    var side: Side?
    var collapsed: Bool?

    static func holdsNode(_ kind: EaselItemKind) -> Bool {
        kind == .text || kind == .sticky || kind == .rectangle || kind == .circle
    }

    static func validationProblem(_ item: EaselItem) -> String? {
        guard let link = item.mindMap else { return nil }
        guard link.parent != item.id else { return "a mind map node that is its own parent" }
        if item.kind == .arrow {
            return link.parent != nil && link.side == nil && link.collapsed == nil ? nil : "mind map branch"
        }
        guard holdsNode(item.kind) else { return "mind map link on an object that can't be a node" }
        return link.side == nil || link.parent != nil ? nil : "mind map side on a root"
    }
}

struct EaselItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: EaselItemKind
    var frame: EaselRect
    var zIndex: Int = 0
    var movedToFrontAt: Date?
    var text: String = ""
    var textStyle: EaselTextStyle?
    var richText: EaselRichText?
    var resolvedTextStyle: EaselTextStyle { textStyle ?? EaselTextStyle() }
    var url: String?
    var assetID: String?
    var color: String = "#252525"
    var points: [EaselPoint] = []
    var capturedAt: Date?
    var captureLayout: EaselCaptureLayout?
    var liveCapture: Bool?
    var shape: EaselShape?
    var fill: String?
    var fillOpacity: Double?
    var strokeWidth: Double?
    var strokeDash: EaselStrokeDash?
    var startHead: EaselArrowHead?
    var endHead: EaselArrowHead?
    var routing: EaselConnectorRouting?
    var startConnection: EaselConnection?
    var endConnection: EaselConnection?
    var groupID: UUID?
    var locked: Bool?
    var rotation: Double?
    var flipHorizontal: Bool?
    var flipVertical: Bool?
    var labelPosition: Double?
    var labelBackground: Bool?
    var waypoints: [EaselPoint]?
    var brush: EaselBrush?
    var pattern: String?
    var attachedTo: UUID?
    var contentsHidden: Bool?
    var crop: EaselRect?
    var mask: EaselImageMask?
    var altText: String?
    var quarterTurns: Int?
    var table: EaselTable?
    var language: String?
    var stamp: String?
    var poster: String?
    var mindMap: EaselMindMapLink?
    var ownsEmbeddedPage: Bool { kind == .browser || (kind == .webCard && captureLayout != nil && liveCapture == true) }
    var resolvedShape: EaselShape? {
        switch kind {
        case .rectangle: return shape ?? .rectangle
        case .circle: return .ellipse
        default: return nil
        }
    }
    var isLocked: Bool { locked == true }
    var resolvedRotation: Double { rotation ?? 0 }
    var resolvedStartHead: EaselArrowHead { startHead ?? .none }
    var resolvedEndHead: EaselArrowHead { endHead ?? .arrow }
    var resolvedRouting: EaselConnectorRouting { routing ?? .straight }
    var resolvedBrush: EaselBrush { brush ?? .marker }
    var resolvedLabelPosition: Double { labelPosition ?? 0.5 }
    var resolvedQuarterTurns: Int { quarterTurns ?? 0 }
    static func isValidLanguage(_ value: String) -> Bool {
        (1...32).contains(value.utf8.count)
            && value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-") }
    }
}

struct EaselDocument: Codable, Identifiable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var items: [EaselItem] = []
}

struct EaselSummary: Identifiable, Equatable {
    var id: UUID
    var title: String
    var modifiedAt: Date
    var itemCount: Int
}

enum EaselStoreError: Error, LocalizedError {
    case invalidDocument(String), unsupportedVersion(Int), unsafePath, invalidImage, tooLarge, invalidVideo, videoTooLarge
    case missingDocument, deletedDocument, closedDocument, browserInUse

    var errorDescription: String? {
        switch self {
        case .invalidDocument(let reason): return "The Easel is invalid: \(reason)."
        case .unsupportedVersion(let version): return "This Easel uses unsupported format version \(version)."
        case .unsafePath: return "The Easel storage path is unsafe."
        case .invalidImage: return "The image could not be imported."
        case .tooLarge: return "The Easel or image exceeds the local storage limit."
        case .invalidVideo: return "That video can't play on an Easel. MP4 and MOV videos can."
        case .videoTooLarge: return "That video is a bit big for an Easel. Videos up to 30 MB fit."
        case .missingDocument: return "The Easel does not exist."
        case .deletedDocument: return "This Easel was deleted."
        case .closedDocument: return "This Easel editor is closed. Reopen the Easel to edit it."
        case .browserInUse: return "Finish closing the embedded webpage before changing this Easel."
        }
    }
}

@MainActor
final class EaselStore {
    static let maximumAssetBytes = 30 * 1024 * 1024
    static let maximumDocumentBytes = 8 * 1024 * 1024
    let directory: URL
    private let now: () -> Date
    private var sessions: [UUID: WeakSession] = [:]
    var documentsDirectory: URL { directory.appendingPathComponent("documents", isDirectory: true) }
    private var assetsDirectory: URL { directory.appendingPathComponent("assets", isDirectory: true) }
    private let documentWriter = EaselDocumentWriter()
    var onSessionCreated: ((EaselSession) -> Void)?
    var onDocumentRemoved: ((UUID) -> Void)?

    init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        self.directory = directory.standardizedFileURL
        self.now = now
        guard self.directory.isFileURL else { throw EaselStoreError.unsafePath }
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try ensureDirectory(self.directory)
        for child in [documentsDirectory, assetsDirectory] {
            if !FileManager.default.fileExists(atPath: child.path) {
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            }
            try ensureDirectory(child)
        }
    }

    func list() throws -> [EaselSummary] {
        try checkDirectories()
        return try FileManager.default.contentsOfDirectory(at: documentsDirectory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let document = try? read(id) else { return nil }
                return EaselSummary(id: id, title: document.title,
                                    modifiedAt: document.modifiedAt, itemCount: document.items.count)
            }
            .sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }

    func create(title: String = "Untitled Easel") throws -> EaselSession {
        let date = now()
        let document = EaselDocument(id: UUID(), title: title, createdAt: date, modifiedAt: date)
        try persist(document)
        return session(document)
    }

    func load(_ id: UUID) throws -> EaselSession {
        if let session = sessions[id]?.value { return session }
        return session(try read(id))
    }

    func validateReference(_ id: UUID) throws {
        let saved = try read(id)
        if let live = sessions[id]?.value, live.document != saved {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
    }
    func delete(_ id: UUID) throws {
        try checkDirectories()
        let url = documentURL(id)
        try ensureRegularFile(url)
        try sessions[id]?.value?.validateReplacement(nil)
        try FileManager.default.removeItem(at: url)
        documentWriter.forget(url)
        syncDirectory(documentsDirectory)
        sessions.removeValue(forKey: id)?.value?.markDeleted()
        onDocumentRemoved?(id)
    }

    fileprivate func timestamp() -> Date { now() }

    fileprivate func persist(_ document: EaselDocument, wait: Bool = true) throws {
        try checkDirectories()
        try validate(document)
        let url = documentURL(document.id)
        let maximumBytes = Self.maximumDocumentBytes
        if wait {
            var caught: Error?
            documentWriter.write(document, to: url, maximumBytes: maximumBytes, wait: true) { caught = $0 }
            if let caught { throw caught }
            return
        }
        documentWriter.write(document, to: url, maximumBytes: maximumBytes, wait: false) { _ in }
    }

    fileprivate func importAsset(_ data: Data, type: EaselAssetType) throws -> String {
        try Self.checkAsset(data, type: type)
        try checkDirectories()
        let id = UUID().uuidString.lowercased() + "." + type.rawValue
        try atomicWrite(data, to: assetsDirectory.appendingPathComponent(id))
        return id
    }

    fileprivate static func checkAsset(_ data: Data, type: EaselAssetType) throws {
        guard data.count <= maximumAssetBytes else { throw type.isVideo ? EaselStoreError.videoTooLarge : EaselStoreError.tooLarge }
        guard EaselAssetType.sniff(data) == type else { throw type.isVideo ? EaselStoreError.invalidVideo : EaselStoreError.invalidImage }
    }

    fileprivate func assetURL(_ id: String) throws -> URL {
        guard id == id.lowercased(), let type = EaselAssetType.of(assetID: id),
              UUID(uuidString: String(id.dropLast(type.rawValue.count + 1))) != nil,
              id.count == 37 + type.rawValue.count else { throw EaselStoreError.unsafePath }
        try checkDirectories()
        let url = assetsDirectory.appendingPathComponent(id)
        try ensureRegularFile(url, maximumBytes: Self.maximumAssetBytes)
        return url
    }

    func relocate(_ id: UUID, to destination: EaselStore) throws -> [String] {
        guard destination !== self, sessions[id]?.value == nil, destination.sessions[id]?.value == nil else {
            throw EaselStoreError.invalidDocument("the document is open")
        }
        let document = try read(id)
        try destination.checkDirectories()
        let target = destination.documentURL(id)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw EaselStoreError.invalidDocument("the destination already has this document")
        }
        var copied: [String] = []
        do {
            for asset in Set(document.items.flatMap { [$0.assetID, $0.poster].compactMap { $0 } }).sorted() {
                let url = destination.assetsDirectory.appendingPathComponent(asset)
                let original = try Data(contentsOf: assetURL(asset))
                if FileManager.default.fileExists(atPath: url.path) {
                    guard try Data(contentsOf: destination.assetURL(asset)) == original else {
                        throw EaselStoreError.invalidDocument("a destination asset has different contents")
                    }
                    continue
                }
                try destination.atomicWrite(original, to: url)
                copied.append(asset)
            }
            guard Darwin.rename(documentURL(id).path, target.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            documentWriter.forget(documentURL(id))
        } catch {
            destination.removeAssets(copied)
            throw error
        }
        syncDirectory(documentsDirectory); destination.syncDirectory(destination.documentsDirectory)
        sessions.removeValue(forKey: id); destination.sessions.removeValue(forKey: id)
        onDocumentRemoved?(id)
        return copied
    }

    func retireSessionForRelocation(_ id: UUID) throws {
        guard let current = sessions[id]?.value else { return }
        try current.validateReplacement(nil)
        guard current.document == (try read(id)) else {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
        sessions.removeValue(forKey: id)
        current.markClosed()
    }

    func removeAssets(_ ids: [String]) {
        for asset in ids { try? FileManager.default.removeItem(at: assetsDirectory.appendingPathComponent(asset)) }
        if !ids.isEmpty { syncDirectory(assetsDirectory) }
    }

    private func session(_ document: EaselDocument) -> EaselSession {
        let value = EaselSession(store: self, document: document)
        sessions[document.id] = WeakSession(value)
        onSessionCreated?(value)
        return value
    }

    private func read(_ id: UUID) throws -> EaselDocument {
        try checkDirectories()
        let url = documentURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw EaselStoreError.missingDocument }
        try ensureRegularFile(url, maximumBytes: Self.maximumDocumentBytes)
        let document = Self.repairingDuplicateIDs(try JSONDecoder().decode(EaselDocument.self, from: Data(contentsOf: url)))
        guard document.id == id else { throw EaselStoreError.invalidDocument("document ID does not match its file") }
        try validate(document)
        return document
    }

    static func repairingDuplicateIDs(_ document: EaselDocument) -> EaselDocument {
        let taken = Set(document.items.map(\.id))
        guard taken.count != document.items.count else { return document }
        var next = document, seen = Set<UUID>()
        for index in next.items.indices {
            let base = next.items[index].id
            var id = base, salt: UInt32 = 0
            while seen.contains(id) || (id != base && taken.contains(id)) {
                salt &+= 1
                var raw = base.uuid
                withUnsafeMutableBytes(of: &raw) { bytes in
                    withUnsafeBytes(of: salt.bigEndian) { for (offset, byte) in $0.enumerated() { bytes[12 + offset] ^= byte } }
                }
                id = UUID(uuid: raw)
            }
            seen.insert(id)
            next.items[index].id = id
        }
        return next
    }

    private func validate(_ document: EaselDocument) throws {
        try Self.validate(document) { _ = try self.assetURL($0) }
    }

    fileprivate static func validate(_ document: EaselDocument, asset: (String) throws -> Void) throws {
        guard document.version == EaselDocument.currentVersion else { throw EaselStoreError.unsupportedVersion(document.version) }
        guard document.title.utf8.count <= 4096,
              !document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              document.createdAt.timeIntervalSinceReferenceDate.isFinite,
              document.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
              document.items.count <= 10_000 else { throw EaselStoreError.invalidDocument("document metadata") }
        guard Set(document.items.map(\.id)).count == document.items.count else { throw EaselStoreError.invalidDocument("duplicate object ID") }
        for item in document.items {
            let r = item.frame
            guard [r.x, r.y, r.width, r.height].allSatisfy({ $0.isFinite && abs($0) <= EaselRect.maximumCoordinate }),
                  r.width >= 1, r.height >= 1,
                  item.points.count <= 100_000,
                  item.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),
                  item.text.utf8.count <= 1_048_576,
                  item.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
                  item.movedToFrontAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  item.capturedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw EaselStoreError.invalidDocument("object geometry or appearance")
            }
            if let richText = item.richText {
                guard item.kind.holdsText || item.kind == .arrow else { throw EaselStoreError.invalidDocument("rich text on an object without text") }
                try richText.validate(text: item.text)
            }
            try validateStyle(item)
            try validateMedia(item)
            if let id = item.assetID { try asset(id) }
            if let id = item.poster { try asset(id) }
            if let layout = item.captureLayout {
                guard item.kind == .webCard, item.assetID != nil, layout.isValid else {
                    throw EaselStoreError.invalidDocument("captured webpage geometry")
                }
            }
            if item.liveCapture == true && (item.kind != .webCard || item.captureLayout == nil) {
                throw EaselStoreError.invalidDocument("live capture has no original geometry")
            }
            if let rawURL = item.url {
                guard rawURL.utf8.count <= 16_384, let url = URL(string: rawURL),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty else { throw EaselStoreError.invalidDocument("card URL") }
            }
            if (item.kind == .image || item.kind == .video) && item.assetID == nil { throw EaselStoreError.invalidDocument("image has no asset") }
            if [.link, .webCard, .browser].contains(item.kind) && item.url == nil { throw EaselStoreError.invalidDocument("card has no URL") }
            if [.arrow, .freehand].contains(item.kind) && item.points.count < 2 { throw EaselStoreError.invalidDocument("drawing has fewer than two points") }
            if (item.kind == .table) != (item.table != nil) { throw EaselStoreError.invalidDocument("table grid on the wrong object") }
            try item.table?.validate()
        }
    }

    private static func validateStyle(_ item: EaselItem) throws {
        let hex = "^#[0-9A-Fa-f]{6}$"
        guard item.fill.map({ $0.range(of: hex, options: .regularExpression) != nil }) != false,
              item.fillOpacity.map({ $0.isFinite && $0 >= 0 && $0 <= 1 }) != false,
              item.strokeWidth.map({ $0.isFinite && $0 >= 0 && $0 <= 64 }) != false,
              item.rotation.map({ $0.isFinite && abs($0) <= 360 }) != false else {
            throw EaselStoreError.invalidDocument("object style")
        }
        if item.shape != nil && item.kind != .rectangle { throw EaselStoreError.invalidDocument("shape outline on a non-shape object") }
        let connector = item.startHead != nil || item.endHead != nil || item.routing != nil
            || item.startConnection != nil || item.endConnection != nil
        if connector && item.kind != .arrow { throw EaselStoreError.invalidDocument("connector style on a non-arrow object") }
        if item.startConnection?.itemID == item.id || item.endConnection?.itemID == item.id {
            throw EaselStoreError.invalidDocument("an arrow connected to itself")
        }
        let unit: (EaselPoint) -> Bool = { $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }
        guard [item.startConnection?.anchor, item.endConnection?.anchor].allSatisfy({ $0.map(unit) != false }),
              item.labelPosition.map({ $0.isFinite && $0 >= 0 && $0 <= 1 }) != false,
              item.waypoints.map({ $0.count <= 64 && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 } }) != false,
              item.pattern.map({ $0.count <= 64 && $0.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil }) != false else {
            throw EaselStoreError.invalidDocument("connector or brush geometry")
        }
        if (item.labelPosition != nil || item.labelBackground != nil || item.waypoints != nil) && item.kind != .arrow {
            throw EaselStoreError.invalidDocument("connector label or bend on a non-arrow object")
        }
        if (item.brush != nil || item.pattern != nil) && item.kind != .freehand {
            throw EaselStoreError.invalidDocument("brush on a non-drawing object")
        }
        if item.attachedTo == item.id { throw EaselStoreError.invalidDocument("an object attached to itself") }
        if let scale = item.textStyle?.textScale {
            guard item.kind == .sticky, scale.isFinite, EaselTextStyle.textScales.contains(scale) else {
                throw EaselStoreError.invalidDocument("text scale")
            }
        }
        if item.contentsHidden != nil && item.kind != .section { throw EaselStoreError.invalidDocument("hidden contents on a non-section object") }
        if let language = item.language {
            guard item.kind == .code else { throw EaselStoreError.invalidDocument("code language on a non-code object") }
            guard EaselItem.isValidLanguage(language) else { throw EaselStoreError.invalidDocument("code language") }
        }
        if let style = item.textStyle {
            guard style.customSize.map({ EaselTextStyle.customSizes.contains($0) }) != false else {
                throw EaselStoreError.invalidDocument("text size")
            }
            if style.autoWidth != nil && item.kind != .text { throw EaselStoreError.invalidDocument("auto width on a non-text object") }
        }
        if let problem = EaselStampFace.validationProblem(item) { throw EaselStoreError.invalidDocument(problem) }
        if let problem = EaselMindMapLink.validationProblem(item) { throw EaselStoreError.invalidDocument(problem) }
    }

    private static func validateMedia(_ item: EaselItem) throws {
        if let crop = item.crop {
            guard item.kind == .image, [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite),
                  crop.x >= 0, crop.y >= 0, crop.width >= 0.01, crop.height >= 0.01,
                  crop.x + crop.width <= 1.000_001, crop.y + crop.height <= 1.000_001 else {
                throw EaselStoreError.invalidDocument("image crop")
            }
        }
        if item.mask != nil && item.kind != .image { throw EaselStoreError.invalidDocument("mask on a non-image object") }
        if let turns = item.quarterTurns, item.kind != .image || !(1...3).contains(turns) {
            throw EaselStoreError.invalidDocument("image turn")
        }
        if let alt = item.altText, (item.kind != .image && item.kind != .video) || alt.utf8.count > 4096 {
            throw EaselStoreError.invalidDocument("alt text")
        }
        let type = item.assetID.flatMap(EaselAssetType.of(assetID:))
        if (type?.isVideo == true) != (item.kind == .video) || (type == .gif && item.kind != .image) {
            throw EaselStoreError.invalidDocument("media on an object that can't play it")
        }
        if let poster = item.poster, item.kind != .video || EaselAssetType.of(assetID: poster) != .png {
            throw EaselStoreError.invalidDocument("video poster")
        }
    }

    private func documentURL(_ id: UUID) -> URL {
        documentsDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json")
    }

    private func checkDirectories() throws {
        try ensureDirectory(directory)
        try ensureDirectory(documentsDirectory)
        try ensureDirectory(assetsDirectory)
    }

    private func ensureDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
    }

    private func ensureRegularFile(_ url: URL, maximumBytes: Int? = nil) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
        if let maximumBytes, (values.fileSize ?? Int.max) > maximumBytes { throw EaselStoreError.tooLarge }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try EaselAtomicFile.write(data, to: destination)
    }

    private func syncDirectory(_ url: URL) {
        EaselAtomicFile.syncDirectory(url)
    }

    private final class WeakSession {
        weak var value: EaselSession?
        init(_ value: EaselSession) { self.value = value }
    }
}

private enum EaselAtomicFile {
    static func write(_ data: Data, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw EaselStoreError.unsafePath
            }
        }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".write-" + UUID().uuidString)
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: temporary) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                written += count
            }
        }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        syncDirectory(destination.deletingLastPathComponent())
    }

    static func syncDirectory(_ url: URL) {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if fd >= 0 { _ = fsync(fd); Darwin.close(fd) }
    }
}

private final class EaselDocumentWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.parc.easel-save", qos: .utility)
    private var lastWrittenBytes: [String: Data] = [:]

    func write(_ document: EaselDocument, to url: URL, maximumBytes: Int, wait: Bool,
               completion: @escaping (Error?) -> Void) {
        let work = {
            do {
                try self.encodeAndReplace(document, to: url, maximumBytes: maximumBytes)
                completion(nil)
            } catch {
                completion(error)
            }
        }
        if wait {
            let group = DispatchGroup()
            group.enter()
            queue.async {
                work()
                group.leave()
            }
            group.wait()
        } else {
            queue.async(execute: work)
        }
    }

    func forget(_ url: URL) {
        let group = DispatchGroup()
        group.enter()
        queue.async {
            self.lastWrittenBytes.removeValue(forKey: url.path)
            group.leave()
        }
        group.wait()
    }

    private func encodeAndReplace(_ document: EaselDocument, to url: URL, maximumBytes: Int) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw EaselStoreError.tooLarge }
        let key = url.path
        if lastWrittenBytes[key] == data {
            return
        }
        try EaselAtomicFile.write(data, to: url)
        lastWrittenBytes[key] = data
    }
}

@MainActor
final class EaselSession: ObservableObject {
    @Published private(set) var document: EaselDocument
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private let store: EaselStore?
    private var memoryAssets: [String: Data] = [:]
    private static let maximumMemoryAssetBytes = 256 * 1024 * 1024
    private var undoStack: [EaselDocument] = []
    private var redoStack: [EaselDocument] = []
    private var deleted = false
    private var closed = false
    var isClosed: Bool { closed }
    var isDeleted: Bool { deleted }
    private var lastUndoGroup: UUID?
    private var replacementGuards: [UUID: (EaselDocument?) -> Bool] = [:]
    var undoDestination: EaselDocument? { undoStack.last }
    var redoDestination: EaselDocument? { redoStack.last }
    func observeReplacement(_ guardChange: @escaping (EaselDocument?) -> Bool) -> UUID {
        let token = UUID(); replacementGuards[token] = guardChange; return token
    }
    func removeReplacementObserver(_ token: UUID) { replacementGuards.removeValue(forKey: token) }
    fileprivate func validateReplacement(_ next: EaselDocument?) throws {
        guard replacementGuards.values.allSatisfy({ $0(next) }) else { throw EaselStoreError.browserInUse }
    }

    fileprivate init(store: EaselStore, document: EaselDocument) {
        self.store = store
        self.document = document
    }

    init(inMemory document: EaselDocument, assets: [String: Data]) throws {
        store = nil; self.document = document; memoryAssets = assets
        try persist(document)
    }

    var inMemoryAssets: [String: Data] { memoryAssets }
    private func persist(_ document: EaselDocument) throws {
        try requireWritable()
        if let store { try store.persist(document); return }
        guard memoryAssets.values.reduce(0, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.tooLarge }
        try EaselStore.validate(document) { id in
            guard self.memoryAssets[id] != nil else { throw EaselStoreError.invalidImage }
        }
        guard try JSONEncoder().encode(document).count <= EaselStore.maximumDocumentBytes else { throw EaselStoreError.tooLarge }
    }

    func assetData(_ id: String) throws -> Data {
        if let store { return try Data(contentsOf: store.assetURL(id)) }
        guard let data = memoryAssets[id] else { throw EaselStoreError.invalidImage }
        return data
    }

    func perform(_ name: String, coalescing group: UUID? = nil, _ mutation: (inout EaselDocument) throws -> Void) throws {
        try requireWritable()
        var next = document
        try mutation(&next)
        guard next.id == document.id, next.createdAt == document.createdAt else {
            throw EaselStoreError.invalidDocument("immutable document identity")
        }
        guard next != document else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        if group == nil || lastUndoGroup != group { undoStack.append(document) }
        lastUndoGroup = group
        trimUndo()
        redoStack.removeAll()
        document = next
        updateHistoryState()
    }

    private var recordingBrowserURL: (id: UUID, from: String, to: String)?
    func isRecordingBrowserNavigation(_ id: UUID, from: String, to: String) -> Bool {
        guard let change = recordingBrowserURL else { return false }
        return change.id == id && change.from == from && change.to == to
    }
    @discardableResult
    func recordBrowserNavigation(_ url: URL, itemID: UUID, expectedURL: String) throws -> Bool {
        try requireWritable()
        guard recordingBrowserURL == nil, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              let index = document.items.firstIndex(where: { $0.id == itemID && $0.kind == .browser && $0.url == expectedURL }) else { return false }
        let value = url.absoluteString
        guard value != expectedURL else { return true }
        var next = document; next.items[index].url = value; next.modifiedAt = (store?.timestamp() ?? Date())
        recordingBrowserURL = (itemID, expectedURL, value)
        defer { recordingBrowserURL = nil }
        try validateReplacement(next)
        try persist(next)
        func refresh(_ snapshot: inout EaselDocument) {
            if let i = snapshot.items.firstIndex(where: { $0.id == itemID && $0.kind == .browser && $0.url == expectedURL }) {
                snapshot.items[i].url = value
            }
        }
        for i in undoStack.indices { refresh(&undoStack[i]) }
        for i in redoStack.indices { refresh(&redoStack[i]) }
        document = next
        return true
    }

    func undo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var previous = undoStack.last else { return }
        previous.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(previous)
        try persist(previous)
        undoStack.removeLast()
        redoStack.append(document)
        document = previous
        updateHistoryState()
    }

    func redo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var next = redoStack.last else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        redoStack.removeLast()
        undoStack.append(document)
        trimUndo()
        document = next
        updateHistoryState()
    }

    func save() throws {
        try requireWritable()
        try persist(document)
    }

    func importPNG(_ data: Data) throws -> String { try importAsset(data, type: .png) }

    func importAsset(_ data: Data, type: EaselAssetType) throws -> String {
        try requireWritable()
        if let store { return try store.importAsset(data, type: type) }
        try EaselStore.checkAsset(data, type: type)
        guard memoryAssets.values.reduce(data.count, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.tooLarge }
        let id = UUID().uuidString.lowercased() + "." + type.rawValue; memoryAssets[id] = data
        return id
    }

    func assetURL(_ assetID: String) throws -> URL {
        guard let store else { throw EaselStoreError.unsafePath }
        return try store.assetURL(assetID)
    }

    func discardUnusedAssets(_ ids: [String]) {
        let used = Set(([document] + undoStack + redoStack).flatMap { $0.items.flatMap { [$0.assetID, $0.poster].compactMap { $0 } } })
        let unused = ids.filter { !used.contains($0) }
        guard !unused.isEmpty else { return }
        if let store { store.removeAssets(unused) } else { for id in unused { memoryAssets.removeValue(forKey: id) } }
    }

    private func requireWritable() throws {
        guard !deleted else { throw EaselStoreError.deletedDocument }
        guard !closed else { throw EaselStoreError.closedDocument }
    }

    fileprivate func markClosed() {
        closed = true
        undoStack.removeAll(); redoStack.removeAll(); lastUndoGroup = nil
        updateHistoryState()
    }

    fileprivate func markDeleted() {
        deleted = true
        undoStack.removeAll()
        redoStack.removeAll()
        updateHistoryState()
    }

    private func trimUndo() {
        while undoStack.count > 50 { undoStack.removeFirst() }
        var retainedBytes = 0
        for index in undoStack.indices.reversed() {
            retainedBytes += (try? JSONEncoder().encode(undoStack[index]).count) ?? EaselStore.maximumDocumentBytes
            if retainedBytes > 32 * 1024 * 1024 {
                undoStack.removeFirst(index + 1)
                break
            }
        }
    }

    private func updateHistoryState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
