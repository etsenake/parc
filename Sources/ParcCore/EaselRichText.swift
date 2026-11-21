import Foundation

package struct EaselRichText: Codable, Equatable {
    package struct Image: Codable, Equatable {
        package var data: Data
        package var fileType: String
        package var width: Double
        package var height: Double
        package init(data: Data, fileType: String, width: Double, height: Double) {
            self.data = data
            self.fileType = fileType
            self.width = width
            self.height = height
        }
        package func validate() throws {
            let signature: Bool
            switch fileType {
            case "public.png": signature = data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
            case "public.jpeg": signature = data.starts(with: [255, 216, 255])
            case "public.tiff": signature = data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42])
            default: signature = false
            }
            guard signature, !data.isEmpty, data.count <= 4_194_304,
                  [width, height].allSatisfy({ $0.isFinite && (1...20_000).contains($0) }),
                  width * height <= 16_777_216 else { throw EaselStoreError.invalidImage }
        }
    }
    package struct Font: Codable, Equatable {
        package var name: String
        package var size: Double
        package var traits: UInt32 = 0
        package var weight: Double = 0
        package var width: Double = 0
        package var slant: Double = 0
        package var variations: [String: Double] = [:]
        package var style: EaselTextStyle?
        package init(name: String, size: Double, traits: UInt32 = 0, weight: Double = 0, width: Double = 0, slant: Double = 0, variations: [String: Double] = [:], style: EaselTextStyle? = nil) {
            self.name = name
            self.size = size
            self.traits = traits
            self.weight = weight
            self.width = width
            self.slant = slant
            self.variations = variations
            self.style = style
        }
    }
    package struct Paragraph: Codable, Equatable {
        package struct Tab: Codable, Equatable { package var alignment: Int; package var location: Double; package init(alignment: Int, location: Double) { self.alignment = alignment; self.location = location } }
        package struct List: Codable, Equatable { package var marker: String; package var options: UInt; package var start: Int; package init(marker: String, options: UInt, start: Int) { self.marker = marker; self.options = options; self.start = start } }
        package var alignment: Int
        package var direction: Int
        package var lineBreak: Int
        package var firstIndent: Double
        package var headIndent: Double
        package var tailIndent: Double
        package var lineSpacing: Double
        package var before: Double
        package var after: Double
        package var minimumHeight: Double
        package var maximumHeight: Double
        package var heightMultiple: Double
        package var hyphenation: Float
        package var tightening: Float
        package var allowsTightening: Bool
        package var defaultHyphenation: Bool
        package var defaultTab: Double
        package var tabs: [Tab]
        package var lists: [List]
        package var heading: Int? = nil
        package init(alignment: Int, direction: Int, lineBreak: Int, firstIndent: Double, headIndent: Double, tailIndent: Double, lineSpacing: Double, before: Double, after: Double, minimumHeight: Double, maximumHeight: Double, heightMultiple: Double, hyphenation: Float, tightening: Float, allowsTightening: Bool, defaultHyphenation: Bool, defaultTab: Double, tabs: [Tab], lists: [List], heading: Int? = nil) {
            self.alignment = alignment
            self.direction = direction
            self.lineBreak = lineBreak
            self.firstIndent = firstIndent
            self.headIndent = headIndent
            self.tailIndent = tailIndent
            self.lineSpacing = lineSpacing
            self.before = before
            self.after = after
            self.minimumHeight = minimumHeight
            self.maximumHeight = maximumHeight
            self.heightMultiple = heightMultiple
            self.hyphenation = hyphenation
            self.tightening = tightening
            self.allowsTightening = allowsTightening
            self.defaultHyphenation = defaultHyphenation
            self.defaultTab = defaultTab
            self.tabs = tabs
            self.lists = lists
            self.heading = heading
        }
    }
    package struct Inline: Codable, Equatable {
        package enum Kind: String, Codable { case note, date, equation, emoji }
        package struct Moment: Codable, Equatable {
            package var year: Int
            package var month: Int
            package var day: Int
            package var hour: Int?
            package var minute: Int?
            package init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
                self.year = year
                self.month = month
                self.day = day
                self.hour = hour
                self.minute = minute
            }
            package var isValid: Bool {
                guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
                      hour.map({ (0...23).contains($0) }) ?? (minute == nil), minute.map({ (0...59).contains($0) }) ?? true else { return false }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
                return DateComponents(calendar: calendar, year: year, month: month, day: day).isValidDate
            }
        }
        package static let dateFormats: Set<String> = ["full", "short", "mdy", "dmy", "ymd"]
        package static let timeFormats: Set<String> = ["12h", "24h"]
        package static let maximumImageBytes = 1_048_576
        package var kind: Kind
        package var target: String?
        package var title: String?
        package var tex: String?
        package var start: Moment?
        package var end: Moment?
        package var remind: Bool?
        package var remindBefore: Int?
        package var timeZone: String?
        package var format: String?
        package var timeFormat: String?
        package var image: Data?
        package init(kind: Kind, target: String? = nil, title: String? = nil, tex: String? = nil, start: Moment? = nil, end: Moment? = nil, remind: Bool? = nil, remindBefore: Int? = nil, timeZone: String? = nil, format: String? = nil, timeFormat: String? = nil, image: Data? = nil) {
            self.kind = kind
            self.target = target
            self.title = title
            self.tex = tex
            self.start = start
            self.end = end
            self.remind = remind
            self.remindBefore = remindBefore
            self.timeZone = timeZone
            self.format = format
            self.timeFormat = timeFormat
            self.image = image
        }

        package static let maximumPayloadBytes = 262_144
        package static func validTarget(_ value: String) -> Bool { value.utf8.count <= 4_096 && EaselRichText.isInternalLink(value) }
        package var payloadBytes: Int { (target?.utf8.count ?? 0) + (title?.utf8.count ?? 0) + (tex?.utf8.count ?? 0) + (timeZone?.utf8.count ?? 0) }
        package static func validEmojiName(_ name: String) -> Bool {
            let bytes = Array(name.utf8)
            guard !bytes.isEmpty, bytes.count <= 48 else { return false }
            return bytes.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 || $0 == 45 || $0 == 43 }
                && bytes.contains { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
        }
        package func validate() throws {
            let dateFields = start != nil || end != nil || remind != nil || remindBefore != nil || timeZone != nil || format != nil || timeFormat != nil
            let valid: Bool
            switch kind {
            case .note:
                valid = target.map(Self.validTarget) == true && (title?.utf8.count ?? 0) <= 1_024
                    && tex == nil && image == nil && !dateFields
            case .equation:
                valid = (tex?.utf8.count ?? 0) <= 4_096 && target == nil && title == nil && image == nil && !dateFields
            case .emoji:
                valid = title.map(Self.validEmojiName) == true && target == nil && tex == nil && !dateFields
                    && image.map { !$0.isEmpty && $0.count <= Self.maximumImageBytes && $0.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) } ?? true
            case .date:
                valid = target == nil && title == nil && tex == nil && image == nil
                    && start?.isValid == true && end.map(\.isValid) ?? true
                    && remindBefore.map { remind == true && (0...10_080).contains($0) } ?? true
                    && timeZone.map { $0.utf8.count <= 64 && TimeZone(identifier: $0) != nil } ?? true
                    && format.map(Self.dateFormats.contains) ?? true && timeFormat.map(Self.timeFormats.contains) ?? true
            }
            guard valid else { throw EaselStoreError.invalidDocument("inline rich text run") }
        }
    }
    package enum SemanticInk: String, Codable { case noteBody }
    package struct Attributes: Codable, Equatable {
        package var font: Font
        package var ink: String
        package var semanticInk: SemanticInk? = nil
        package var background: String?
        package var underline: Int = 0
        package var strike: Int = 0
        package var underlineColor: String?
        package var strikeColor: String?
        package var link: String?
        package var kern: Double = 0
        package var baseline: Double = 0
        package var paragraph: Paragraph?
        package var image: Image? = nil
        package var inline: Inline? = nil
        package init(font: Font, ink: String, semanticInk: SemanticInk? = nil, background: String? = nil, underline: Int = 0, strike: Int = 0, underlineColor: String? = nil, strikeColor: String? = nil, link: String? = nil, kern: Double = 0, baseline: Double = 0, paragraph: Paragraph? = nil, image: Image? = nil, inline: Inline? = nil) {
            self.font = font
            self.ink = ink
            self.semanticInk = semanticInk
            self.background = background
            self.underline = underline
            self.strike = strike
            self.underlineColor = underlineColor
            self.strikeColor = strikeColor
            self.link = link
            self.kern = kern
            self.baseline = baseline
            self.paragraph = paragraph
            self.image = image
            self.inline = inline
        }
        package var isAtomic: Bool { image != nil || inline != nil }
    }
    package struct Run: Codable, Equatable {
        package var location: Int
        package var length: Int
        package var attributes: Attributes
        package init(location: Int, length: Int, attributes: Attributes) {
            self.location = location
            self.length = length
            self.attributes = attributes
        }
    }
    package var runs: [Run]
    package init(runs: [Run]) {
        self.runs = runs
    }

    package static func validLink(_ value: String) -> Bool {
        if isInternalLink(value) { return true }
        guard value.utf8.count <= 16_384, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return false }
        return scheme == "mailto" || scheme == "tel" || url.host?.isEmpty == false
    }

    package static func isInternalLink(_ value: String) -> Bool {
        guard value.utf8.count <= 16_384, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil else { return false }
        if scheme == "file" {
            return [nil, "", "localhost"].contains(url.host?.lowercased()) && url.path.hasPrefix("/")
                && NoteFileKind(pathExtension: url.pathExtension) != nil
        }
        guard scheme == "parc", url.host?.lowercased() == "easel", url.query == nil, url.path.hasPrefix("/"),
              UUID(uuidString: String(url.path.dropFirst())) != nil else { return false }
        return url.fragment.map { UUID(uuidString: $0) != nil } ?? true
    }
    package func validate(text: String) throws {
        let units = Array(text.utf16)
        guard units.count <= 1_048_576, runs.count <= 16_384 else { throw EaselStoreError.textTooLarge }
        func validBoundary(_ position: Int) -> Bool {
            position == 0 || position == units.count || !(0xD800...0xDBFF).contains(units[position - 1]) || !(0xDC00...0xDFFF).contains(units[position])
        }
        func color(_ value: String?) -> Bool {
            value == nil || value!.range(of: "^#[0-9A-Fa-f]{8}$", options: .regularExpression) != nil
        }
        var end = 0, imageBytes = 0, inlineBytes = 0
        for run in runs {
            let a = run.attributes
            guard run.location == end, run.length > 0, run.length <= units.count - end,
                  validBoundary(run.location), validBoundary(run.location + run.length),
                  !a.font.name.isEmpty, a.font.name.utf8.count <= 256,
                  a.font.size.isFinite, (1...512).contains(a.font.size),
                  [a.font.weight, a.font.width, a.font.slant].allSatisfy({ $0.isFinite && (-1...1).contains($0) }),
                  a.font.variations.count <= 32,
                  a.font.variations.allSatisfy({ UInt32($0.key).map(String.init) == $0.key && $0.value.isFinite && abs($0.value) <= 1_000_000 }),
                  a.semanticInk == nil || a.ink == "#000000FF",
                  color(a.ink), color(a.background), color(a.underlineColor), color(a.strikeColor),
                  a.underline >= 0, a.underline <= 0xFFFF, a.strike >= 0, a.strike <= 0xFFFF,
                  [a.kern, a.baseline].allSatisfy({ $0.isFinite && abs($0) <= 10_000 }),
                  a.link == nil || Self.validLink(a.link!) else { throw EaselStoreError.invalidDocument("rich text range or attributes") }
            if let image = a.image {
                try image.validate()
                guard run.length == 1, units[run.location] == 0xFFFC else {
                    throw EaselStoreError.invalidDocument("inline image range")
                }
                imageBytes += image.data.count
                guard imageBytes <= 4_194_304 else { throw EaselStoreError.textPictureTooLarge }
            }
            if let inline = a.inline {
                try inline.validate()
                guard a.image == nil, run.length == 1, units[run.location] == 0xFFFC else {
                    throw EaselStoreError.invalidDocument("inline rich text range")
                }
                imageBytes += inline.image?.count ?? 0
                inlineBytes += inline.payloadBytes
                guard imageBytes <= 4_194_304, inlineBytes <= Inline.maximumPayloadBytes else { throw EaselStoreError.textPictureTooLarge }
            }
            if let p = a.paragraph {
                guard (0...4).contains(p.alignment), (-1...1).contains(p.direction), (0...5).contains(p.lineBreak),
                      [p.firstIndent, p.headIndent, p.tailIndent, p.lineSpacing, p.before, p.after, p.minimumHeight,
                       p.maximumHeight, p.heightMultiple, p.defaultTab].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                      p.hyphenation.isFinite, (0...1).contains(p.hyphenation), p.tightening.isFinite, (0...1).contains(p.tightening), p.tabs.count <= 256, p.lists.count <= 16,
                      p.tabs.allSatisfy({ (0...4).contains($0.alignment) && $0.location.isFinite && abs($0.location) <= 100_000 }),
                      (p.heading == nil || (0...6).contains(p.heading!)),
                      p.lists.allSatisfy({ !$0.marker.isEmpty && $0.marker.utf8.count <= 128 && $0.options <= 1 && (-100_000...100_000).contains($0.start) }) else {
                    throw EaselStoreError.invalidDocument("rich text paragraph")
                }
            }
            end += run.length
        }
        guard end == units.count else { throw EaselStoreError.invalidDocument("rich text ranges do not cover text") }
    }
}
