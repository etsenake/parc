import Foundation

struct EaselRichText: Codable, Equatable {
    struct Image: Codable, Equatable {
        var data: Data
        var fileType: String
        var width: Double
        var height: Double
        func validate() throws {
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
    struct Font: Codable, Equatable {
        var name: String
        var size: Double
        var traits: UInt32 = 0
        var weight: Double = 0
        var width: Double = 0
        var slant: Double = 0
        var variations: [String: Double] = [:]
        var style: EaselTextStyle?
    }
    struct Paragraph: Codable, Equatable {
        struct Tab: Codable, Equatable { var alignment: Int; var location: Double }
        struct List: Codable, Equatable { var marker: String; var options: UInt; var start: Int }
        var alignment: Int
        var direction: Int
        var lineBreak: Int
        var firstIndent: Double
        var headIndent: Double
        var tailIndent: Double
        var lineSpacing: Double
        var before: Double
        var after: Double
        var minimumHeight: Double
        var maximumHeight: Double
        var heightMultiple: Double
        var hyphenation: Float
        var tightening: Float
        var allowsTightening: Bool
        var defaultHyphenation: Bool
        var defaultTab: Double
        var tabs: [Tab]
        var lists: [List]
        var heading: Int? = nil
    }
    enum SemanticInk: String, Codable { case noteBody }
    struct Attributes: Codable, Equatable {
        var font: Font
        var ink: String
        var semanticInk: SemanticInk? = nil
        var background: String?
        var underline: Int = 0
        var strike: Int = 0
        var underlineColor: String?
        var strikeColor: String?
        var link: String?
        var kern: Double = 0
        var baseline: Double = 0
        var paragraph: Paragraph?
        var image: Image? = nil
    }
    struct Run: Codable, Equatable {
        var location: Int
        var length: Int
        var attributes: Attributes
    }
    var runs: [Run]

    static let noteLinkExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "txt", "text"]

    static func validLink(_ value: String) -> Bool {
        if isInternalLink(value) { return true }
        guard value.utf8.count <= 16_384, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return false }
        return scheme == "mailto" || scheme == "tel" || url.host?.isEmpty == false
    }

    static func isInternalLink(_ value: String) -> Bool {
        guard value.utf8.count <= 16_384, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil else { return false }
        if scheme == "file" {
            return [nil, "", "localhost"].contains(url.host?.lowercased()) && url.path.hasPrefix("/")
                && noteLinkExtensions.contains(url.pathExtension.lowercased())
        }
        guard scheme == "parc", url.host?.lowercased() == "easel", url.query == nil, url.path.hasPrefix("/"),
              UUID(uuidString: String(url.path.dropFirst())) != nil else { return false }
        return url.fragment.map { UUID(uuidString: $0) != nil } ?? true
    }
    func validate(text: String) throws {
        let units = Array(text.utf16)
        guard units.count <= 1_048_576, runs.count <= 16_384 else { throw EaselStoreError.tooLarge }
        func validBoundary(_ position: Int) -> Bool {
            position == 0 || position == units.count || !(0xD800...0xDBFF).contains(units[position - 1]) || !(0xDC00...0xDFFF).contains(units[position])
        }
        func color(_ value: String?) -> Bool {
            value == nil || value!.range(of: "^#[0-9A-Fa-f]{8}$", options: .regularExpression) != nil
        }
        var end = 0, imageBytes = 0
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
                guard imageBytes <= 4_194_304 else { throw EaselStoreError.tooLarge }
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
