import AppKit

///
/// through the Notes paragraph formats, bold, italic, underline, strikethrough,
/// links and embedded images on top of the Notes body style. AppKit's HTML
/// reader would fetch remote resources, so they are removed first; a remote
/// image is counted rather than downloaded.
@MainActor
enum ArcNoteHTML {
    struct Converted {
        let title: String?
        let body: NoteBody
        let droppedImages: Int
    }

    static func convert(_ html: String) throws -> Converted {
        let (local, dropped) = sanitized(html)
        guard let data = local.data(using: .utf8),
              let parsed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                  .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else {
            throw ArcNotesExport.Failure.unreadable
        }
        // AppKit's reader does not report <title>.
        let title = html.range(of: "(?is)<title[^>]*>(.*?)</title>", options: .regularExpression).map { range in
            let raw = String(html[range]).replacingOccurrences(of: "(?is)</?title[^>]*>", with: "", options: .regularExpression)
            return (CFXMLCreateStringByUnescapingEntities(nil, raw as CFString, nil) as String)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let (value, failedImages) = rebuilt(parsed)
        let body = NoteBody(text: value.string, richText: try EaselRichTextCodec.snapshot(value))
        return Converted(title: title?.isEmpty == false ? title : nil, body: body, droppedImages: dropped + failedImages)
    }

    /// Only text-formatting tags survive, with a link's address, an image's
    /// embedded bytes and inline styles that cannot name a resource; scripts,
    /// styles, SVG, frames and media are removed with their contents.
    private static let unsafeStyle = "(?i)url|image|import|expression|src|\\\\|@|&|<"

    static func sanitized(_ html: String) -> (String, Int) {
        var value = html.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?is)<(script|svg|math|object|iframe|frameset|noscript|template|video|audio|canvas)\\b.*?</\\1\\s*>",
                                           with: "", options: .regularExpression)
        // A style sheet stays only when it cannot name another resource.
        // Kept sheets wait outside the markup as placeholders; anything still
        // opening a style sheet (unclosed) is cut with the rest of the file.
        var keptSheets: [String] = []
        let sheets = try! NSRegularExpression(pattern: "(?is)<style\\b[^>]*>(.*?)</style\\s*>")
        for sheet in sheets.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let whole = Range(sheet.range, in: value), let css = Range(sheet.range(at: 1), in: value) else { continue }
            let safe = value[css].range(of: unsafeStyle, options: .regularExpression) == nil
            keptSheets.append(safe ? String(value[css]) : "")
            value.replaceSubrange(whole, with: "\u{E000}\(keptSheets.count - 1)\u{E001}")
        }
        value = value.replacingOccurrences(of: "(?is)<style\\b.*", with: "", options: .regularExpression)
        let allowed: Set<String> = ["html", "head", "title", "body", "p", "br", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6",
            "b", "strong", "i", "em", "u", "s", "strike", "del", "ins", "a", "ul", "ol", "li", "blockquote", "pre", "code",
            "hr", "img", "sub", "sup", "mark", "small"]
        let tag = try! NSRegularExpression(pattern: "<(/?)([A-Za-z][A-Za-z0-9]*)\\b((?:[^>\"']|\"[^\"]*\"|'[^']*')*)>")
        let attribute = try! NSRegularExpression(pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*(?:=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'>]+))?")
        var dropped = 0, result = "", last = value.startIndex
        for match in tag.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let whole = Range(match.range, in: value), let closing = Range(match.range(at: 1), in: value),
                  let nameRange = Range(match.range(at: 2), in: value), let body = Range(match.range(at: 3), in: value) else { continue }
            result += text(value[last..<whole.lowerBound]); last = whole.upperBound
            let name = value[nameRange].lowercased()
            var attributes: [String: String] = [:]
            let text = String(value[body])
            for found in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let key = Range(found.range(at: 1), in: text) else { continue }
                var raw = Range(found.range(at: 2), in: text).map { String(text[$0]) } ?? ""
                if raw.hasPrefix("\"") || raw.hasPrefix("'") { raw = String(raw.dropFirst().dropLast()) }
                attributes[text[key].lowercased()] = CFXMLCreateStringByUnescapingEntities(nil, raw as CFString, nil) as String
            }
            if name == "input", attributes["type"]?.lowercased() == "checkbox" {
                result += attributes["checked"] != nil ? "\u{2611} " : "\u{2610} "; continue
            }
            guard allowed.contains(name) else {
                if name == "image" || name == "input" { dropped += 1 }
                continue
            }
            if !value[closing].isEmpty { result += "</" + name + ">"; continue }
            var kept: [(String, String)] = []
            if name == "a", let href = attributes["href"], EaselRichText.validLink(href) { kept.append(("href", href)) }
            if name == "img" {
                guard let source = attributes["src"], source.range(of: "^data:image/(png|jpe?g|tiff|gif);base64,[A-Za-z0-9+/=\\s]+$",
                    options: [.regularExpression, .caseInsensitive]) != nil else { dropped += 1; continue }
                kept.append(("src", source))
            }
            if name == "ol", let start = attributes["start"], Int(start) != nil { kept.append(("start", start)) }
            if let style = attributes["style"], style.range(of: unsafeStyle, options: .regularExpression) == nil {
                kept.append(("style", style))
            }
            if let names = attributes["class"], names.range(of: "^[A-Za-z0-9 _-]*$", options: .regularExpression) != nil {
                kept.append(("class", names))
            }
            func escaped(_ text: String) -> String {
                text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                    .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            }
            result += "<" + name + kept.map { " \($0.0)=\"\(escaped($0.1))\"" }.joined() + ">"
        }
        result += text(value[last...])
        for (index, css) in keptSheets.enumerated() where !css.isEmpty {
            result = result.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: "<style>" + css + "</style>")
        }
        result = result.replacingOccurrences(of: "\u{E000}[0-9]+\u{E001}", with: "", options: .regularExpression)
        return (result, dropped)
    }

    /// Text between rebuilt tags never opens another tag, even a malformed one.
    private static func text(_ value: Substring) -> String {
        value.replacingOccurrences(of: "<(?=[A-Za-z/!?])", with: "&lt;", options: .regularExpression)
    }

    private static func rebuilt(_ parsed: NSAttributedString) -> (NSAttributedString, Int) {
        let source = parsed.string as NSString
        let result = NSMutableAttributedString()
        var formats: [(range: NSRange, kind: EaselParagraphEditing.Kind, depth: Int)] = []
        var failedImages = 0, position = 0
        while position < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(paragraph)
            let style = parsed.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            var content = paragraph
            // AppKit writes each list item's marker as "\t•\t" text.
            if let style, !style.textLists.isEmpty,
               let marker = source.substring(with: paragraph).range(of: "^\\t[^\\t\\r\\n]*\\t", options: .regularExpression) {
                let length = (String(source.substring(with: paragraph)[marker]) as NSString).length
                content = NSRange(location: paragraph.location + length, length: paragraph.length - length)
            }
            let start = result.length
            parsed.enumerateAttributes(in: content) { attributes, range, _ in
                var run = NoteDocumentAppearance.bodyAttributes
                if let attachment = attributes[.attachment] as? NSTextAttachment {
                    if let image = try? EaselTextAttachments.source(attachment) {
                        result.append(EaselTextAttachments.character(image, attributes: run))
                    } else { failedImages += 1 }
                    return
                }
                let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
                var font = traits.contains(.monoSpace)
                    ? NSFont.monospacedSystemFont(ofSize: NoteDocumentAppearance.bodyFont.pointSize * 0.9, weight: .regular)
                    : NoteDocumentAppearance.bodyFont
                if traits.contains(.bold) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if traits.contains(.italic) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                run[.font] = font
                if ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0 { run[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if ((attributes[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0 { run[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
                if let link, EaselRichText.validLink(link) { run[.link] = link }
                // The reader inks every run; only a colour that isn't its default black is authored.
                if run[.link] == nil, let ink = (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB),
                   max(ink.redComponent, ink.greenComponent, ink.blueComponent) > 0.2 { run[.foregroundColor] = ink }
                if let mark = (attributes[.backgroundColor] as? NSColor)?.usingColorSpace(.sRGB), mark.alphaComponent > 0 {
                    run[.backgroundColor] = mark
                }
                result.append(NSAttributedString(string: source.substring(with: range), attributes: run))
            }
            let kind: EaselParagraphEditing.Kind
            if let list = style?.textLists.last {
                kind = EaselParagraphEditing.isNumbered(list) || [.decimal, .lowercaseAlpha, .uppercaseAlpha, .lowercaseRoman,
                    .uppercaseRoman].contains(list.markerFormat) ? .numbers : .bullets
            } else {
                switch style?.headerLevel ?? 0 {
                case 1: kind = .heading1
                case 2: kind = .heading2
                case 0: kind = .text
                default: kind = .heading3
                }
            }
            if kind != .text {
                formats.append((NSRange(location: start, length: result.length - start), kind, max(1, style?.textLists.count ?? 1)))
            }
        }
        while result.length > 0, (result.string as NSString).substring(from: result.length - 1).rangeOfCharacter(from: .newlines) != nil {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        var value: NSAttributedString = result
        // Later paragraphs first, so a marker never shifts one still to format.
        for format in formats.reversed() where format.range.location < value.length {
            let selection = NSRange(location: format.range.location, length: 0)
            value = EaselParagraphEditing.apply(format.kind, to: value, selection: selection, typing: NoteDocumentAppearance.bodyAttributes,
                                                base: EaselTextStyle(), bodyPointSize: NoteDocumentAppearance.bodyFont.pointSize).text
            // A nested list item keeps its depth.
            for _ in 1..<format.depth {
                guard let nested = EaselParagraphEditing.indent(value, selection: selection, typing: NoteDocumentAppearance.bodyAttributes,
                                                                outdent: false, base: EaselTextStyle()) else { break }
                value = nested.text
            }
        }
        return (value, failedImages)
    }
}
