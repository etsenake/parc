import Foundation
import Combine
import Darwin

package enum EaselItemKind: String, Codable, CaseIterable {
    case text, image, rectangle, circle, arrow, freehand, webCard, browser, link, sticky, section, table, code, stamp, video
    case audio, file, pdf, equation

    package var holdsText: Bool { self == .text || self == .sticky || self == .rectangle || self == .circle }
    package var isMedia: Bool { self == .image || self == .video || self == .audio || self == .file || self == .pdf }
    package var takesFileName: Bool { self == .video || self == .audio || self == .file || self == .pdf }
    var takesMediaLink: Bool { self == .video || self == .audio }
}

package enum EaselShape: String, Codable, CaseIterable {
    case rectangle, roundedRectangle, ellipse, diamond, triangle, triangleDown, parallelogram, trapezoid,
         pentagon, hexagon, octagon, star, plus, speechBubble, arrowLeft, arrowRight, arrowUp, arrowDown,
         chevron, cylinder, parallelogramLeft, cylinderHorizontal, file, folder, document, documents,
         predefinedProcess, shield, manualInput, internalStorage, or, summingJunction
}

package enum EaselStrokeDash: String, Codable, CaseIterable { case solid, dashed, dotted }

package enum EaselArrowHead: String, Codable, CaseIterable {
    case none, arrow, triangle, circle, diamond, bar, solidArrow,
         erdOne, erdMany, erdExactlyOne, erdZeroOrOne, erdOneOrMore, erdZeroOrMore
}

package enum EaselConnectorRouting: String, Codable, CaseIterable { case straight, elbow, curved }

package enum EaselBrush: String, Codable, CaseIterable { case marker, highlighter, washi }

package enum EaselImageMask: String, Codable, CaseIterable { case rounded, circle, squircle, arch, diamond, hexagon, star, heart }

package enum EaselAssetType: String, CaseIterable {
    case png, gif, mp4, mov, m4a, mp3, wav, aac, aiff, pdf, file

    static let maximumExtensionLength = 16

    package var isVideo: Bool { self == .mp4 || self == .mov }
    var isAudio: Bool { self == .m4a || self == .mp3 || self == .wav || self == .aac || self == .aiff }
    var isPicture: Bool { self == .png || self == .gif }

    var kind: EaselItemKind? {
        if isVideo { return .video }
        if isAudio { return .audio }
        switch self {
        case .pdf: return .pdf
        case .file: return .file
        default: return nil
        }
    }

    package static func of(assetID: String) -> EaselAssetType? {
        let parts = assetID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let last = parts[parts.count - 1]
        if parts.count >= 3, parts[parts.count - 2] == EaselAssetType.file.rawValue, isSafeExtension(last) { return .file }
        return EaselAssetType(rawValue: last)
    }

    static func isSafeAssetID(_ id: String) -> Bool { assetParts(id) != nil }

    package static func fileExtension(of assetID: String) -> String? {
        guard let parts = assetParts(assetID) else { return nil }
        return parts.type == .file ? parts.fileExtension : parts.type.rawValue
    }

    static func isSafeExtension(_ value: String) -> Bool {
        (1...maximumExtensionLength).contains(value.utf8.count)
            && value.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
    }

    package static func safeExtension(_ raw: String?) -> String? {
        guard let lowered = raw?.lowercased(), isSafeExtension(lowered) else { return nil }
        return lowered
    }

    static func assetID(_ uuid: UUID, type: EaselAssetType, fileExtension: String? = nil) -> String {
        let stem = uuid.uuidString.lowercased() + "." + type.rawValue
        guard type == .file, let ext = safeExtension(fileExtension) else { return stem }
        return stem + "." + ext
    }

    private static func assetParts(_ id: String) -> (type: EaselAssetType, fileExtension: String?)? {
        let uuidLength = 36
        guard id.utf8.count > uuidLength + 1, id == id.lowercased(),
              UUID(uuidString: String(id.prefix(uuidLength))) != nil else { return nil }
        let rest = id.dropFirst(uuidLength)
        guard rest.first == "." else { return nil }
        let pieces = rest.dropFirst().split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let first = pieces.first, let type = EaselAssetType(rawValue: first) else { return nil }
        if pieces.count == 1 { return (type, nil) }
        guard type == .file, pieces.count == 2, isSafeExtension(pieces[1]) else { return nil }
        return (type, pieces[1])
    }

    static func audioType(forExtension raw: String?) -> EaselAssetType? {
        switch raw?.lowercased() {
        case "m4a", "m4b", "mp4a": return .m4a
        case "mp3": return .mp3
        case "wav", "wave": return .wav
        case "aac", "adts": return .aac
        case "aif", "aiff", "aifc": return .aiff
        default: return nil
        }
    }

    package static func sniff(_ data: Data) -> EaselAssetType? {
        let head = [UInt8](data.prefix(64))
        if head.count >= 24, head.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), Array(head[12..<16]) == Array("IHDR".utf8) { return .png }
        if head.count >= 13, head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8)) {
            let width = Int(head[6]) | Int(head[7]) << 8, height = Int(head[8]) | Int(head[9]) << 8
            return width > 0 && height > 0 ? .gif : nil
        }
        if head.count >= 5, head.starts(with: Array("%PDF-".utf8)) { return .pdf }
        if head.count >= 12, head.starts(with: Array("RIFF".utf8)), Array(head[8..<12]) == Array("WAVE".utf8) { return .wav }
        if head.count >= 12, head.starts(with: Array("FORM".utf8)),
           Array(head[8..<12]) == Array("AIFF".utf8) || Array(head[8..<12]) == Array("AIFC".utf8) { return .aiff }
        if head.count >= 10, head.starts(with: Array("ID3".utf8)), head[3] < 0xFF, head[4] < 0xFF { return .mp3 }
        if head.count >= 4, head[0] == 0xFF, head[1] & 0xF6 == 0xF0, head[2] & 0x3C != 0x3C { return .aac }
        if head.count >= 4, head[0] == 0xFF, head[1] & 0xE0 == 0xE0, head[1] & 0x06 != 0, head[1] & 0x18 != 0x08,
           head[2] & 0xF0 != 0xF0, head[2] & 0x0C != 0x0C { return .mp3 }
        guard head.count >= 12 else { return nil }
        let size = head[0..<4].reduce(0) { $0 << 8 | Int($1) }, box = String(decoding: head[4..<8], as: UTF8.self)
        guard box == "ftyp" else {
            return (size == 1 || size >= 8) && ["moov", "mdat", "wide", "free", "skip", "pnot"].contains(box) ? .mov : nil
        }
        guard head.count >= 16, size >= 16, size % 4 == 0, size <= 4096 else { return nil }
        var brands = [String(decoding: head[8..<12], as: UTF8.self)]
        var offset = 16
        while offset + 4 <= min(size, head.count) {
            brands.append(String(decoding: head[offset..<(offset + 4)], as: UTF8.self))
            offset += 4
        }
        if brands.contains("qt  ") { return .mov }
        if audioBrands.contains(brands[0]) { return .m4a }
        return stillImageBrands.contains(brands[0]) ? nil : .mp4
    }

    static func accepts(_ data: Data, as type: EaselAssetType) -> Bool {
        guard type != .file else { return !data.isEmpty }
        return sniff(data) == type
    }

    private static let stillImageBrands: Set<String> = ["heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1", "avif", "avis"]
    private static let audioBrands: Set<String> = ["M4A ", "M4B ", "M4P "]
}

package struct EaselLinkPreviewData: Codable, Equatable {
    static let maximumTextBytes = 2048
    static let maximumAddressBytes = 4096
    package var title: String?
    package var summary: String?
    package var siteName: String?
    package var image: String?
    package var icon: String?
    init(title: String? = nil, summary: String? = nil, siteName: String? = nil, image: String? = nil, icon: String? = nil) {
        self.title = title
        self.summary = summary
        self.siteName = siteName
        self.image = image
        self.icon = icon
    }

    var isEmpty: Bool { [title, summary, siteName, image, icon].allSatisfy { $0 == nil } }

    var assetIDs: [String] {
        [image, icon].compactMap { $0 }.filter(Self.isAssetID)
    }

    static func isAssetID(_ value: String) -> Bool {
        EaselAssetType.isSafeAssetID(value) && EaselAssetType.of(assetID: value) == .png
    }

    package static func isAddress(_ raw: String) -> Bool {
        guard raw.utf8.count <= maximumAddressBytes, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { return false }
        return true
    }

    var isValid: Bool {
        guard !isEmpty, [title, summary, siteName].allSatisfy({ $0.map(EaselMediaText.isValid) != false }) else { return false }
        return [image, icon].allSatisfy { value in
            guard let value else { return true }
            return Self.isAssetID(value) || Self.isAddress(value)
        }
    }
}

package struct EaselMediaCredit: Codable, Equatable {
    package var name: String
    package var profileURL: String?
    var photoURL: String?
    package init(name: String, profileURL: String? = nil, photoURL: String? = nil) {
        self.name = name
        self.profileURL = profileURL
        self.photoURL = photoURL
    }

    var isValid: Bool {
        EaselMediaText.isValid(name) && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && [profileURL, photoURL].allSatisfy { $0.map(EaselLinkPreviewData.isAddress) != false }
    }
}

enum EaselMediaText {
    static let maximumBytes = 2048

    static func isValid(_ text: String) -> Bool {
        text.utf8.count <= maximumBytes
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t" }
    }

    static func isValidFileName(_ name: String) -> Bool {
        isValid(name) && !name.contains("\n") && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 1024
    }
}

package enum EaselStampDesign: String, CaseIterable { case plusOne, dot, heart, question, star, thumbsUp, thumbsDown, smiley }

package enum EaselStampFace: Hashable {
    case design(EaselStampDesign)
    case emoji(String)
    case icon(String)

    static let iconPrefix = "icon:"
    static let maximumEmojiBytes = 64
    static let maximumSymbolLength = 96

    package init?(item: EaselItem) {
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

    package init?(token: String) {
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

    package var token: String {
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

    package init?(emoji text: String) {
        if Self.customName(in: text) != nil {
            self = .emoji(text)
            return
        }
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

    package static func customName(in text: String) -> String? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 3, bytes.count <= 50, bytes.first == 58, bytes.last == 58 else { return nil }
        let name = bytes.dropFirst().dropLast()
        func alphanumeric(_ byte: UInt8) -> Bool { (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) }
        guard name.allSatisfy({ alphanumeric($0) || $0 == 95 || $0 == 45 || $0 == 43 }), name.contains(where: alphanumeric) else { return nil }
        return String(decoding: name, as: UTF8.self)
    }

    package var customEmojiName: String? {
        if case .emoji(let text) = self { return Self.customName(in: text) }
        return nil
    }

    static func isEmoji(_ text: String) -> Bool {
        if customName(in: text) != nil { return true }
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

package struct EaselConnection: Codable, Equatable {
    package enum Side: String, Codable, CaseIterable { case top, right, bottom, left }
    package var itemID: UUID
    package var side: Side?
    package var anchor: EaselPoint?
    package init(itemID: UUID, side: Side? = nil, anchor: EaselPoint? = nil) {
        self.itemID = itemID
        self.side = side
        self.anchor = anchor
    }
}

package struct EaselPoint: Codable, Equatable {
    package var x: Double
    package var y: Double
    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

package struct EaselRect: Codable, Equatable {
    package static let maximumCoordinate = 1_000_000.0
    package var x: Double
    package var y: Double
    package var width: Double
    package var height: Double
    package init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

package struct EaselScrollContainer: Codable, Equatable {
    static let maximumCount = 8

    package var anchorID: String?
    package var path: String
    package var scroll: EaselPoint
    package var frame: EaselRect
    package init(anchorID: String? = nil, path: String, scroll: EaselPoint, frame: EaselRect) {
        self.anchorID = anchorID
        self.path = path
        self.scroll = scroll
        self.frame = frame
    }

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

package struct EaselCaptureLayout: Codable, Equatable {
    package var viewport: EaselPoint
    package var scroll: EaselPoint
    package var region: EaselRect
    package var scrollContainers: [EaselScrollContainer]? = nil
    package var fullPage: Bool? = nil
    init(viewport: EaselPoint, scroll: EaselPoint, region: EaselRect, scrollContainers: [EaselScrollContainer]? = nil,
         fullPage: Bool? = nil) {
        self.viewport = viewport
        self.scroll = scroll
        self.region = region
        self.scrollContainers = scrollContainers
        self.fullPage = fullPage == true ? true : nil
    }

    package var isFullPage: Bool { fullPage == true }

    package var screenAspect: Double { viewport.y / viewport.x }

    var isValid: Bool {
        [viewport.x, viewport.y, scroll.x, scroll.y, region.x, region.y, region.width, region.height]
            .allSatisfy { $0.isFinite && abs($0) <= 1_000_000 }
            && viewport.x >= 1 && viewport.y >= 1 && viewport.x <= 16_384 && viewport.y <= 16_384
            && region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
            && region.x + region.width <= viewport.x + 1 && region.y + region.height <= viewport.y + 1
            && (scrollContainers.map { !$0.isEmpty && $0.count <= EaselScrollContainer.maximumCount && $0.allSatisfy(\.isValid) } ?? true)
    }
}

package struct EaselTextStyle: Codable, Equatable {
    package enum Family: String, Codable, CaseIterable { case mono, fancy, hip, clean }
    package enum Size: String, Codable, CaseIterable {
        case body, h2, h1, h0, ultra
        package var index: Int { Self.allCases.firstIndex(of: self)! }
        package func shifted(by delta: Int) -> Size { Self.allCases[min(4, max(0, index + delta))] }
    }
    package enum Fill: String, Codable { case none, contentHugging }
    package enum Alignment: String, Codable, CaseIterable { case left, center, right }
    package static let textScales = 0.25...8.0
    package static let customSizes: ClosedRange<Double> = 8...400
    package var fill: Fill?
    package var resolvedFill: Fill { fill ?? .none }
    var alignment: Alignment?
    package var textScale: Double?
    package var family: Family = .clean
    package var size: Size = .body
    package var customSize: Double?
    package var autoWidth: Bool?
    package init(fill: Fill? = nil, alignment: Alignment? = nil, textScale: Double? = nil, family: Family = .clean, size: Size = .body, customSize: Double? = nil, autoWidth: Bool? = nil) {
        self.fill = fill
        self.alignment = alignment
        self.textScale = textScale
        self.family = family
        self.size = size
        self.customSize = customSize
        self.autoWidth = autoWidth
    }
    var presetPointSize: Double {
        switch family {
        case .mono, .clean: return [15, 24, 44, 60, 80][size.index]
        case .fancy: return [16, 28, 48, 60, 80][size.index]
        case .hip: return [18, 21, 44, 60, 80][size.index]
        }
    }
    package var pointSize: Double { customSize ?? presetPointSize }
}

package struct EaselMindMapLink: Codable, Equatable {
    package enum Side: String, Codable, CaseIterable { case left, right }
    var parent: UUID?
    var side: Side?
    var collapsed: Bool?
    init(parent: UUID? = nil, side: Side? = nil, collapsed: Bool? = nil) {
        self.parent = parent
        self.side = side
        self.collapsed = collapsed
    }

    static func holdsNode(_ kind: EaselItemKind) -> Bool {
        kind == .text || kind == .sticky || kind == .rectangle || kind == .circle
    }

    static func validationProblem(_ item: EaselItem) -> String? {
        guard let link = item.mindMap else { return nil }
        if item.kind == .arrow {
            return link.parent != nil && link.side == nil && link.collapsed == nil ? nil : "mind map branch"
        }
        guard holdsNode(item.kind) else { return "mind map link on an object that can't be a node" }
        return link.side == nil || link.parent != nil ? nil : "mind map side on a root"
    }
}

package struct EaselItem: Codable, Identifiable, Equatable {
    package var id = UUID()
    package var kind: EaselItemKind
    package var frame: EaselRect
    package var zIndex: Int = 0
    package var movedToFrontAt: Date?
    package var text: String = ""
    package var textStyle: EaselTextStyle?
    package var richText: EaselRichText?
    package var resolvedTextStyle: EaselTextStyle { textStyle ?? EaselTextStyle() }
    package var url: String?
    package var assetID: String?
    package var color: String = "#252525"
    package var points: [EaselPoint] = []
    package var capturedAt: Date?
    package var captureLayout: EaselCaptureLayout?
    package var liveCapture: Bool?
    package var shape: EaselShape?
    package var fill: String?
    package var fillOpacity: Double?
    package var strokeWidth: Double?
    package var strokeDash: EaselStrokeDash?
    package var startHead: EaselArrowHead?
    package var endHead: EaselArrowHead?
    package var routing: EaselConnectorRouting?
    package var startConnection: EaselConnection?
    package var endConnection: EaselConnection?
    package var groupID: UUID?
    var locked: Bool?
    package var rotation: Double?
    package var flipHorizontal: Bool?
    package var flipVertical: Bool?
    package var labelPosition: Double?
    package var labelBackground: Bool?
    package var waypoints: [EaselPoint]?
    package var brush: EaselBrush?
    package var pattern: String?
    package var attachedTo: UUID?
    package var contentsHidden: Bool?
    package var crop: EaselRect?
    package var mask: EaselImageMask?
    package var altText: String?
    var quarterTurns: Int?
    package var table: EaselTable?
    package var language: String?
    var stamp: String?
    package var poster: String?
    package var mindMap: EaselMindMapLink?
    package var page: UUID?
    package var fileName: String?
    package var preview: EaselLinkPreviewData?
    package var credit: EaselMediaCredit?
    package init(id: UUID = UUID(), kind: EaselItemKind, frame: EaselRect, zIndex: Int = 0, movedToFrontAt: Date? = nil, text: String = "", textStyle: EaselTextStyle? = nil, richText: EaselRichText? = nil, url: String? = nil, assetID: String? = nil, color: String = "#252525", points: [EaselPoint] = [], capturedAt: Date? = nil, captureLayout: EaselCaptureLayout? = nil, liveCapture: Bool? = nil, shape: EaselShape? = nil, fill: String? = nil, fillOpacity: Double? = nil, strokeWidth: Double? = nil, strokeDash: EaselStrokeDash? = nil, startHead: EaselArrowHead? = nil, endHead: EaselArrowHead? = nil, routing: EaselConnectorRouting? = nil, startConnection: EaselConnection? = nil, endConnection: EaselConnection? = nil, groupID: UUID? = nil, locked: Bool? = nil, rotation: Double? = nil, flipHorizontal: Bool? = nil, flipVertical: Bool? = nil, labelPosition: Double? = nil, labelBackground: Bool? = nil, waypoints: [EaselPoint]? = nil, brush: EaselBrush? = nil, pattern: String? = nil, attachedTo: UUID? = nil, contentsHidden: Bool? = nil, crop: EaselRect? = nil, mask: EaselImageMask? = nil, altText: String? = nil, quarterTurns: Int? = nil, table: EaselTable? = nil, language: String? = nil, stamp: String? = nil, poster: String? = nil, mindMap: EaselMindMapLink? = nil, page: UUID? = nil, fileName: String? = nil, preview: EaselLinkPreviewData? = nil, credit: EaselMediaCredit? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.zIndex = zIndex
        self.movedToFrontAt = movedToFrontAt
        self.text = text
        self.textStyle = textStyle
        self.richText = richText
        self.url = url
        self.assetID = assetID
        self.color = color
        self.points = points
        self.capturedAt = capturedAt
        self.captureLayout = captureLayout
        self.liveCapture = liveCapture
        self.shape = shape
        self.fill = fill
        self.fillOpacity = fillOpacity
        self.strokeWidth = strokeWidth
        self.strokeDash = strokeDash
        self.startHead = startHead
        self.endHead = endHead
        self.routing = routing
        self.startConnection = startConnection
        self.endConnection = endConnection
        self.groupID = groupID
        self.locked = locked
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        self.labelPosition = labelPosition
        self.labelBackground = labelBackground
        self.waypoints = waypoints
        self.brush = brush
        self.pattern = pattern
        self.attachedTo = attachedTo
        self.contentsHidden = contentsHidden
        self.crop = crop
        self.mask = mask
        self.altText = altText
        self.quarterTurns = quarterTurns
        self.table = table
        self.language = language
        self.stamp = stamp
        self.poster = poster
        self.mindMap = mindMap
        self.page = page
        self.fileName = fileName
        self.preview = preview
        self.credit = credit
    }
    package var ownsEmbeddedPage: Bool { (kind == .browser && url != nil) || (kind == .webCard && captureLayout != nil && liveCapture == true) }
    package var isEmptyPlaceholder: Bool {
        switch kind {
        case .image, .video, .audio, .file, .pdf: return assetID == nil && url == nil
        case .link, .browser: return url == nil
        default: return false
        }
    }
    var assetReferences: [String] {
        [assetID, poster].compactMap { $0 } + (preview?.assetIDs ?? [])
    }
    package var resolvedShape: EaselShape? {
        switch kind {
        case .rectangle: return shape ?? .rectangle
        case .circle: return .ellipse
        default: return nil
        }
    }
    package var isLocked: Bool { locked == true }
    var resolvedRotation: Double { rotation ?? 0 }
    package var resolvedStartHead: EaselArrowHead { startHead ?? .none }
    package var resolvedEndHead: EaselArrowHead { endHead ?? .arrow }
    package var resolvedRouting: EaselConnectorRouting { routing ?? .straight }
    package var resolvedBrush: EaselBrush { brush ?? .marker }
    package var resolvedLabelPosition: Double { labelPosition ?? 0.5 }
    package var resolvedQuarterTurns: Int { quarterTurns ?? 0 }
    static func isValidLanguage(_ value: String) -> Bool {
        (1...32).contains(value.utf8.count)
            && value.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "-") }
    }
}

package struct EaselPageIcon: Codable, Hashable, Sendable {
    package enum Kind: String, Codable, Sendable { case emoji, custom, image }

    static let maximumEmojiBytes = 64
    static let maximumNameLength = 48

    package var kind: Kind
    package var value: String
    init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    package static func emoji(_ value: String) -> EaselPageIcon? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isEmoji(trimmed) ? EaselPageIcon(kind: .emoji, value: trimmed) : nil
    }

    package static func custom(named name: String) -> EaselPageIcon? {
        isCustomName(name) ? EaselPageIcon(kind: .custom, value: name) : nil
    }

    package static func image(assetID: String) -> EaselPageIcon? {
        EaselAssetType.of(assetID: assetID) == .png ? EaselPageIcon(kind: .image, value: assetID) : nil
    }

    static func isEmoji(_ value: String) -> Bool {
        guard value.utf8.count <= maximumEmojiBytes, value.count == 1, let first = value.unicodeScalars.first,
              first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || value.unicodeScalars.count > 1
    }

    static func isCustomName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty, bytes.count <= maximumNameLength else { return false }
        let letterOrDigit: (UInt8) -> Bool = { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
        return bytes.allSatisfy { letterOrDigit($0) || $0 == 95 || $0 == 45 || $0 == 43 } && bytes.contains(where: letterOrDigit)
    }

    var assetID: String? { kind == .image ? value : nil }

    var isValid: Bool {
        switch kind {
        case .emoji: return Self.isEmoji(value)
        case .custom: return Self.isCustomName(value)
        case .image: return EaselAssetType.of(assetID: value) == .png
        }
    }
}

package struct EaselDocument: Codable, Identifiable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    package var id: UUID
    package var title: String
    var createdAt: Date
    package var modifiedAt: Date
    package var items: [EaselItem] = []
    package var pages: [EaselPage]?
    package var icon: EaselPageIcon?
    package var locked: Bool?
    package var defaultFamily: EaselTextStyle.Family?
    package init(version: Int = currentVersion, id: UUID, title: String, createdAt: Date, modifiedAt: Date, items: [EaselItem] = [], pages: [EaselPage]? = nil, icon: EaselPageIcon? = nil, locked: Bool? = nil, defaultFamily: EaselTextStyle.Family? = nil) {
        self.version = version
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.items = items
        self.pages = pages
        self.icon = icon
        self.locked = locked
        self.defaultFamily = defaultFamily
    }
    package var isLocked: Bool { locked == true }
    package var resolvedDefaultFamily: EaselTextStyle.Family { defaultFamily ?? .clean }
}

package struct EaselSummary: Identifiable, Equatable {
    package var id: UUID
    package var title: String
    package var modifiedAt: Date
    package var itemCount: Int
    package var icon: EaselPageIcon? = nil
    init(id: UUID, title: String, modifiedAt: Date, itemCount: Int, icon: EaselPageIcon? = nil) {
        self.id = id
        self.title = title
        self.modifiedAt = modifiedAt
        self.itemCount = itemCount
        self.icon = icon
    }
}

package enum EaselStoreError: Error, LocalizedError {
    case invalidDocument(String), unsupportedVersion(Int), unsafePath, invalidImage, imageTooLarge(megabytes: Int), easelTooLarge(megabytes: Int), tooMuch(String), invalidVideo, videoTooLarge
    case invalidAudio, audioTooLarge, invalidPDF, pdfTooLarge, invalidFile, fileTooLarge
    case missingDocument, deletedDocument, closedDocument, browserInUse, lockedDocument
    case invalidWebLink, imageDownloadFailed, pdfDownloadFailed, staleObject

    package var errorDescription: String? {
        switch self {
        case .invalidDocument(let reason): return "The Easel is invalid: \(reason)."
        case .unsupportedVersion(let version): return "This Easel uses unsupported format version \(version)."
        case .unsafePath: return "The Easel storage path is unsafe."
        case .invalidImage: return "Parc couldn’t read that picture, so it wasn’t added."
        case .imageTooLarge(let megabytes): return "That picture is a bit big for an Easel. Pictures up to \(megabytes) MB fit."
        case .easelTooLarge(let megabytes): return "This Easel is a bit big to save. Easels up to \(megabytes) MB fit."
        case .tooMuch(let sentence): return sentence
        case .invalidVideo: return "That video can’t play on an Easel. MP4 and MOV videos can."
        case .videoTooLarge: return "That video is a bit big for an Easel. Videos up to 30 MB fit."
        case .invalidAudio: return "That audio can’t play on an Easel. M4A, MP3, WAV, AAC and AIFF files can."
        case .audioTooLarge: return "That audio is a bit big for an Easel. Audio up to 30 MB fits."
        case .invalidPDF: return "That PDF won’t open on an Easel."
        case .pdfTooLarge: return "That PDF is a bit big for an Easel. PDFs up to 30 MB fit."
        case .invalidFile: return "That file couldn’t be added to the Easel."
        case .fileTooLarge: return "That file is a bit big for an Easel. Files up to 30 MB fit."
        case .missingDocument: return "The Easel does not exist."
        case .deletedDocument: return "This Easel was deleted."
        case .closedDocument: return "This Easel editor is closed. Reopen the Easel to edit it."
        case .browserInUse: return "Finish closing the embedded webpage before changing this Easel."
        case .lockedDocument: return "This Easel is locked. Unlock it to make changes."
        case .staleObject: return nil
        case .invalidWebLink: return "Enter a full web link, like example.com."
        case .imageDownloadFailed: return "That image couldn’t be downloaded."
        case .pdfDownloadFailed: return "That PDF couldn’t be downloaded."
        }
    }
}

extension EaselStoreError {
    package static var assetImageTooLarge: EaselStoreError { .imageTooLarge(megabytes: EaselStore.maximumAssetBytes / 1_048_576) }
    static var documentTooLarge: EaselStoreError { .easelTooLarge(megabytes: EaselStore.maximumDocumentBytes / 1_048_576) }
    static var memoryTooLarge: EaselStoreError { .easelTooLarge(megabytes: 256) }
    package static var textPictureTooLarge: EaselStoreError { .imageTooLarge(megabytes: 4) }
    static let tableTooLarge = EaselStoreError.tooMuch("That table has a lot of text. Tables hold up to 1 MB of it.")
    package static let cellTooLarge = EaselStoreError.tooMuch("That's a lot of text for one cell. Cells hold up to 64 KB.")
    static let textTooLarge = EaselStoreError.tooMuch("That's a lot of text for one object. About a million characters fit.")
    package static let pasteTooLarge = EaselStoreError.tooMuch("That's a bit much to copy or paste at once. Text up to 1 MB fits, or 8 MB with pictures.")
    static let objectsTooLarge = EaselStoreError.tooMuch("That's a lot of objects to copy or paste at once. Up to 128 MB fits.")
    package static let templateTooLarge = EaselStoreError.tooMuch("That doesn't fit on this Easel. Easels hold up to 10,000 objects.")
    package static let exportTooLarge = EaselStoreError.tooMuch("That image is too big to export. Up to 32,768 pixels a side and 128 million in all fit.")
}

extension Notification.Name {
    package static let easelDocumentRemoved = Notification.Name("ParcEaselDocumentRemoved")
    package static let easelDocumentChanged = Notification.Name("ParcEaselDocumentChanged")
    static let easelAssetsRemoved = Notification.Name("ParcEaselAssetsRemoved")
}

@MainActor
package final class EaselStore {
    package nonisolated static let maximumAssetBytes = 30 * 1024 * 1024
    package nonisolated static let directoryKey = "directory"
    package nonisolated static let maximumDocumentBytes = 8 * 1024 * 1024
    package let directory: URL
    private let now: () -> Date
    private var sessions: [UUID: WeakSession] = [:]
    package var documentsDirectory: URL { directory.appendingPathComponent("documents", isDirectory: true) }
    private var assetsDirectory: URL { directory.appendingPathComponent("assets", isDirectory: true) }
    private let documentWriter: EaselDocumentWriter
    package var onSessionCreated: ((EaselSession) -> Void)?
    package var onListed: (([EaselSummary]) -> Void)?
    package var onDocumentRemoved: ((UUID) -> Void)?

    package convenience init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        try self.init(directory: directory, now: now, replaceDocument: EaselAtomicFile.write)
    }

    init(directory: URL, now: @escaping () -> Date, replaceDocument: @escaping (Data, URL) throws -> Void) throws {
        self.documentWriter = EaselDocumentWriter(replace: replaceDocument)
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

    package func list() throws -> [EaselSummary] {
        let summaries = try listFromDisk()
        onListed?(summaries)
        return summaries
    }

    private func listFromDisk() throws -> [EaselSummary] {
        try checkDirectories()
        return try FileManager.default.contentsOfDirectory(at: documentsDirectory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let document = try? read(id) else { return nil }
                return EaselSummary(id: id, title: document.title,
                                    modifiedAt: document.modifiedAt, itemCount: document.items.count, icon: document.icon)
            }
            .sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }

    package func create(title: String = "Untitled Easel") throws -> EaselSession {
        let date = now()
        let document = EaselDocument(id: UUID(), title: title, createdAt: date, modifiedAt: date)
        try persist(document)
        let created = session(document)
        NotificationCenter.default.post(name: .easelDocumentChanged, object: document.id, userInfo: [Self.directoryKey: directory])
        return created
    }

    package func load(_ id: UUID) throws -> EaselSession {
        if let session = sessions[id]?.value { return session }
        return session(try read(id))
    }

    func existingSession(_ id: UUID) -> EaselSession? { sessions[id]?.value }

    func assetFileURL(_ assetID: String) -> URL? { try? assetURL(assetID) }

    nonisolated static func readIcon(directory: URL, id: UUID) -> EaselPageIcon? {
        struct Head: Decodable { var icon: EaselPageIcon? }
        let url = directory.appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased() + ".json")
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximumDocumentBytes,
              let data = try? Data(contentsOf: url),
              let icon = (try? JSONDecoder().decode(Head.self, from: data))?.icon, icon.isValid else { return nil }
        return icon
    }

    package nonisolated static func summaries(directory: URL) -> [EaselSummary] {
        struct Skip: Decodable { init(from decoder: Decoder) throws {} }
        struct Head: Decodable {
            var version: Int?
            var id: UUID
            var title: String
            var modifiedAt: Date
            var items: [Skip]?
            var icon: EaselPageIcon?
        }
        let documents = directory.standardizedFileURL.appendingPathComponent("documents", isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url -> EaselSummary? in
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= maximumDocumentBytes,
                  let data = try? Data(contentsOf: url), let head = try? JSONDecoder().decode(Head.self, from: data),
                  head.id == id, (head.version ?? EaselDocument.currentVersion) == EaselDocument.currentVersion,
                  !head.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return EaselSummary(id: id, title: head.title, modifiedAt: head.modifiedAt, itemCount: head.items?.count ?? 0,
                                icon: head.icon.flatMap { $0.isValid ? $0 : nil })
        }
        .sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
    }

    package func validateReference(_ id: UUID) throws {
        let saved = try read(id)
        if let live = sessions[id]?.value, live.document != saved {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
    }
    package func delete(_ id: UUID) throws {
        try checkDirectories()
        let url = documentURL(id)
        try ensureRegularFile(url)
        try sessions[id]?.value?.validateReplacement(nil)
        try FileManager.default.removeItem(at: url)
        documentWriter.forget(url)
        syncDirectory(documentsDirectory)
        sessions.removeValue(forKey: id)?.value?.markDeleted()
        onDocumentRemoved?(id)
        NotificationCenter.default.post(name: .easelDocumentRemoved, object: id, userInfo: [Self.directoryKey: directory])
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

    fileprivate func importAsset(_ data: Data, type: EaselAssetType, fileExtension: String? = nil) throws -> String {
        try Self.checkAsset(data, type: type)
        try checkDirectories()
        let id = EaselAssetType.assetID(UUID(), type: type, fileExtension: fileExtension)
        try atomicWrite(data, to: assetsDirectory.appendingPathComponent(id))
        return id
    }

    fileprivate static func checkAsset(_ data: Data, type: EaselAssetType) throws {
        guard data.count <= maximumAssetBytes else {
            if type.isVideo { throw EaselStoreError.videoTooLarge }
            if type.isAudio { throw EaselStoreError.audioTooLarge }
            if type == .pdf { throw EaselStoreError.pdfTooLarge }
            if type == .file { throw EaselStoreError.fileTooLarge }
            throw EaselStoreError.assetImageTooLarge
        }
        guard EaselAssetType.accepts(data, as: type) else {
            if type.isVideo { throw EaselStoreError.invalidVideo }
            if type.isAudio { throw EaselStoreError.invalidAudio }
            if type == .pdf { throw EaselStoreError.invalidPDF }
            if type == .file { throw EaselStoreError.invalidFile }
            throw EaselStoreError.invalidImage
        }
    }

    fileprivate func assetURL(_ id: String) throws -> URL {
        guard EaselAssetType.isSafeAssetID(id) else { throw EaselStoreError.unsafePath }
        try checkDirectories()
        let url = assetsDirectory.appendingPathComponent(id)
        try ensureRegularFile(url, maximumBytes: Self.maximumAssetBytes)
        return url
    }

    package func relocate(_ id: UUID, to destination: EaselStore) throws -> [String] {
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
            for asset in Set(document.items.flatMap(\.assetReferences) + [document.icon?.assetID].compactMap { $0 }).sorted() {
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

    package func retireSessionForRelocation(_ id: UUID) throws {
        guard let current = sessions[id]?.value else { return }
        try current.validateReplacement(nil)
        guard current.document == (try read(id)) else {
            throw EaselStoreError.invalidDocument("the shared document changed outside its session")
        }
        sessions.removeValue(forKey: id)
        current.markClosed()
    }

    package func removeAssets(_ ids: [String]) {
        for asset in ids { try? FileManager.default.removeItem(at: assetsDirectory.appendingPathComponent(asset)) }
        NotificationCenter.default.post(name: .easelAssetsRemoved, object: directory)
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
        try ensureRegularFile(url, maximumBytes: Self.maximumDocumentBytes, tooLarge: .documentTooLarge)
        let document = Self.repairingStackOrder(Self.repairingDuplicateIDs(try JSONDecoder().decode(EaselDocument.self, from: Data(contentsOf: url))))
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

    static let maximumStackIndex = 1_000_000_000

    static func repairingStackOrder(_ document: EaselDocument) -> EaselDocument {
        guard document.items.contains(where: { $0.zIndex > maximumStackIndex || $0.zIndex < -maximumStackIndex }) else { return document }
        var next = document
        let order = document.items.indices.sorted { (document.items[$0].zIndex, $0) < (document.items[$1].zIndex, $1) }
        for (rank, index) in order.enumerated() { next.items[index].zIndex = rank }
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
        if let problem = EaselPages.validationProblem(document) { throw EaselStoreError.invalidDocument(problem) }
        if let icon = document.icon {
            guard icon.isValid else { throw EaselStoreError.invalidDocument("page icon") }
            if let id = icon.assetID { try asset(id) }
        }
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
            for id in item.assetReferences { try asset(id) }
            if let layout = item.captureLayout {
                guard item.kind == .webCard, item.assetID != nil, layout.isValid else {
                    throw EaselStoreError.invalidDocument("captured webpage geometry")
                }
            }
            if item.liveCapture == true && (item.kind != .webCard || item.captureLayout == nil) {
                throw EaselStoreError.invalidDocument("live capture has no original geometry")
            }
            if let rawURL = item.url, !(item.kind.holdsText && EaselRichText.isInternalLink(rawURL)) {
                guard rawURL.utf8.count <= 16_384, let url = URL(string: rawURL),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host, !host.isEmpty else { throw EaselStoreError.invalidDocument("card URL") }
            }
            if item.kind == .webCard && item.url == nil { throw EaselStoreError.invalidDocument("card has no URL") }
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
        if let type, type.isVideo != (item.kind == .video) || (type == .gif && item.kind != .image) {
            throw EaselStoreError.invalidDocument("media on an object that can't play it")
        }
        if let poster = item.poster, item.kind != .video || EaselAssetType.of(assetID: poster) != .png || item.isEmptyPlaceholder {
            throw EaselStoreError.invalidDocument("video poster")
        }
        if let type, let owner = type.kind, owner != item.kind { throw EaselStoreError.invalidDocument("media on an object that can't play it") }
        if [.audio, .file, .pdf].contains(item.kind), let type, type.kind != item.kind {
            throw EaselStoreError.invalidDocument("media on an object that can't play it")
        }
        if item.kind == .image, let type, !type.isPicture { throw EaselStoreError.invalidDocument("image asset") }
        if item.url != nil, [.file, .pdf, .equation].contains(item.kind) { throw EaselStoreError.invalidDocument("link on an object that can't hold one") }
        if let name = item.fileName, !item.kind.takesFileName || !EaselMediaText.isValidFileName(name) {
            throw EaselStoreError.invalidDocument("file name")
        }
        if let preview = item.preview, item.kind != .link || !preview.isValid { throw EaselStoreError.invalidDocument("link preview") }
        if let credit = item.credit, item.kind != .image || !credit.isValid { throw EaselStoreError.invalidDocument("image credit") }
        if item.kind == .equation, item.assetID != nil || item.richText != nil || item.poster != nil {
            throw EaselStoreError.invalidDocument("equation contents")
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

    private func ensureRegularFile(_ url: URL, maximumBytes: Int? = nil, tooLarge: EaselStoreError = .fileTooLarge) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw EaselStoreError.unsafePath }
        if let maximumBytes, (values.fileSize ?? Int.max) > maximumBytes { throw tooLarge }
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
    private let replace: (Data, URL) throws -> Void
    private var lastWrittenBytes: [String: Data] = [:]

    init(replace: @escaping (Data, URL) throws -> Void) {
        self.replace = replace
    }

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
        guard data.count <= maximumBytes else { throw EaselStoreError.documentTooLarge }
        let key = url.path
        if lastWrittenBytes[key] == data {
            return
        }
        try replace(data, url)
        lastWrittenBytes[key] = data
    }
}

@MainActor
package final class EaselSession: ObservableObject {
    @Published package private(set) var document: EaselDocument
    @Published package private(set) var canUndo = false
    @Published package private(set) var canRedo = false
    private let store: EaselStore?
    private var memoryAssets: [String: Data] = [:]
    private static let maximumMemoryAssetBytes = 256 * 1024 * 1024
    private var undoStack: [EaselDocument] = []
    private var redoStack: [EaselDocument] = []
    private var deleted = false
    private var closed = false
    package var isClosed: Bool { closed }
    package var isDeleted: Bool { deleted }
    private var lastUndoGroup: UUID?
    private var replacementGuards: [UUID: (EaselDocument?) -> Bool] = [:]
    package var undoDestination: EaselDocument? { undoStack.last }
    package var redoDestination: EaselDocument? { redoStack.last }
    package func observeReplacement(_ guardChange: @escaping (EaselDocument?) -> Bool) -> UUID {
        let token = UUID(); replacementGuards[token] = guardChange; return token
    }
    package func removeReplacementObserver(_ token: UUID) { replacementGuards.removeValue(forKey: token) }
    fileprivate func validateReplacement(_ next: EaselDocument?) throws {
        guard replacementGuards.values.allSatisfy({ $0(next) }) else { throw EaselStoreError.browserInUse }
    }

    fileprivate init(store: EaselStore, document: EaselDocument) {
        self.store = store
        self.document = document
    }

    package init(inMemory document: EaselDocument, assets: [String: Data]) throws {
        store = nil; self.document = document; memoryAssets = assets
        try persist(document)
    }

    package var inMemoryAssets: [String: Data] { memoryAssets }
    package var storeDirectory: URL? { store?.directory }
    private func persist(_ document: EaselDocument) throws {
        try requireWritable()
        if let store { try store.persist(document); return }
        guard memoryAssets.values.reduce(0, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.memoryTooLarge }
        try EaselStore.validate(document) { id in
            guard self.memoryAssets[id] != nil else { throw EaselStoreError.invalidImage }
        }
        guard try JSONEncoder().encode(document).count <= EaselStore.maximumDocumentBytes else { throw EaselStoreError.documentTooLarge }
    }

    package func assetData(_ id: String) throws -> Data {
        if let store { return try Data(contentsOf: store.assetURL(id)) }
        guard let data = memoryAssets[id] else { throw EaselStoreError.invalidImage }
        return data
    }

    package func perform(_ name: String, coalescing group: UUID? = nil, _ mutation: (inout EaselDocument) throws -> Void) throws {
        try requireWritable()
        var next = document
        try mutation(&next)
        guard next.id == document.id, next.createdAt == document.createdAt else {
            throw EaselStoreError.invalidDocument("immutable document identity")
        }
        if document.isLocked {
            var probe = next
            probe.locked = document.locked
            guard probe == document else { throw EaselStoreError.lockedDocument }
        }
        guard next != document else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        if group == nil || lastUndoGroup != group {
            undoStack.append(document); lastUndoGroup = group
        } else if var start = undoStack.last {
            start.modifiedAt = next.modifiedAt
            if start == next { undoStack.removeLast(); lastUndoGroup = nil }
        }
        trimUndo()
        redoStack.removeAll()
        document = next
        updateHistoryState()
    }

    private var recordingBrowserURL: (id: UUID, from: String, to: String)?
    package func isRecordingBrowserNavigation(_ id: UUID, from: String, to: String) -> Bool {
        guard let change = recordingBrowserURL else { return false }
        return change.id == id && change.from == from && change.to == to
    }
    @discardableResult
    package func recordBrowserNavigation(_ url: URL, itemID: UUID, expectedURL: String) throws -> Bool {
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

    package func recordLinkPreview(_ preview: EaselLinkPreviewData, itemID: UUID, url: String) throws -> Bool {
        try requireWritable()
        guard preview.isValid, let index = document.items.firstIndex(where: { $0.id == itemID && $0.kind == .link && $0.url == url }),
              document.items[index].preview == nil else { return false }
        var next = document; next.items[index].preview = preview; next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        func refresh(_ snapshot: inout EaselDocument) {
            if let i = snapshot.items.firstIndex(where: { $0.id == itemID && $0.kind == .link && $0.url == url && $0.preview == nil }) {
                snapshot.items[i].preview = preview
            }
        }
        for i in undoStack.indices { refresh(&undoStack[i]) }
        for i in redoStack.indices { refresh(&redoStack[i]) }
        document = next
        return true
    }

    func updateLinks(_ rewrite: (EaselDocument) -> EaselDocument?) throws {
        try requireWritable()
        func relinked(_ snapshot: EaselDocument) -> EaselDocument? {
            guard let rewritten = rewrite(snapshot), rewritten.items != snapshot.items else { return nil }
            var copy = snapshot
            copy.items = rewritten.items
            return copy
        }
        guard var next = relinked(document) else { return }
        next.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(next)
        try persist(next)
        for index in undoStack.indices { if let copy = relinked(undoStack[index]) { undoStack[index] = copy } }
        for index in redoStack.indices { if let copy = relinked(redoStack[index]) { redoStack[index] = copy } }
        document = next
        updateHistoryState()
    }

    package func undo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var previous = undoStack.last else { return }
        guard !document.isLocked || Self.differsOnlyInLock(previous, document) else { throw EaselStoreError.lockedDocument }
        previous.modifiedAt = (store?.timestamp() ?? Date())
        try validateReplacement(previous)
        try persist(previous)
        undoStack.removeLast()
        redoStack.append(document)
        document = previous
        updateHistoryState()
    }

    package func retractLastStep() throws {
        try undo()
        guard !redoStack.isEmpty else { return }
        redoStack.removeLast()
        updateHistoryState()
    }

    package func redo() throws {
        lastUndoGroup = nil
        try requireWritable()
        guard var next = redoStack.last else { return }
        guard !document.isLocked || Self.differsOnlyInLock(next, document) else { throw EaselStoreError.lockedDocument }
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

    package func importPNG(_ data: Data) throws -> String { try importAsset(data, type: .png) }

    package func importAsset(_ data: Data, type: EaselAssetType, fileExtension: String? = nil) throws -> String {
        try requireWritable()
        if let store { return try store.importAsset(data, type: type, fileExtension: fileExtension) }
        try EaselStore.checkAsset(data, type: type)
        guard memoryAssets.values.reduce(data.count, { $0 + $1.count }) <= Self.maximumMemoryAssetBytes else { throw EaselStoreError.memoryTooLarge }
        let id = EaselAssetType.assetID(UUID(), type: type, fileExtension: fileExtension); memoryAssets[id] = data
        return id
    }

    func hasAsset(_ id: String) -> Bool {
        if let store { return (try? store.assetURL(id)) != nil }
        return memoryAssets[id] != nil
    }

    package func restorableIcon(_ icon: EaselPageIcon?) -> EaselPageIcon? {
        guard let icon else { return nil }
        if icon.kind == .image, !hasAsset(icon.value) { return document.icon }
        return icon
    }

    package func assetURL(_ assetID: String) throws -> URL {
        guard let store else { throw EaselStoreError.unsafePath }
        return try store.assetURL(assetID)
    }

    package func discardUnusedAssets(_ ids: [String]) {
        let used = Set(([document] + undoStack + redoStack).flatMap { snapshot in
            snapshot.items.flatMap(\.assetReferences) + [snapshot.icon?.assetID].compactMap { $0 }
        })
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

    private static func differsOnlyInLock(_ a: EaselDocument, _ b: EaselDocument) -> Bool {
        guard a.isLocked != b.isLocked else { return false }
        var probe = a
        probe.locked = b.locked
        probe.modifiedAt = b.modifiedAt
        return probe == b
    }

    private func updateHistoryState() {
        let editable = !document.isLocked
        canUndo = undoStack.last.map { editable || Self.differsOnlyInLock($0, document) } ?? false
        canRedo = redoStack.last.map { editable || Self.differsOnlyInLock($0, document) } ?? false
        NotificationCenter.default.post(name: .easelDocumentChanged, object: document.id,
                                        userInfo: store.map { [EaselStore.directoryKey: $0.directory] })
    }
}
