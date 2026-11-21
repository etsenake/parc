import Foundation

package enum NoteBacklinkRewriter {
    package static func isWikiStyle(target: String, title: String) -> Bool {
        !(NoteMDLinks.isRelativeMarkdown(target) && title == NoteMDLinks.stem(target) && title != target)
    }

    package static func retitled(_ title: String, target: String, next: String) -> String {
        if title == target { return next }
        if title == NoteMDLinks.stem(target) { return NoteMDLinks.stem(next) }
        return title
    }

    package static func target(_ raw: String, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove, wiki: Bool) -> String? {
        guard NoteBacklinkScanner.targetKey(raw, from: folder) == move.fromKey else { return nil }
        return replacement(for: raw, writingFrom: newFolder, to: move.to, wiki: wiki)
    }

    package static func replacement(for raw: String, writingFrom folder: URL, to note: URL, wiki: Bool) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var angled = false
        if value.count >= 2, value.hasPrefix("<"), value.hasSuffix(">") {
            angled = true
            value = String(value.dropFirst().dropLast())
        }
        var fragment = ""
        if let hash = value.firstIndex(of: "#") {
            fragment = String(value[hash...])
            value = String(value[..<hash])
        }
        let decoded = value.removingPercentEncoding ?? value
        let plain = wiki || angled
        let file = URL(fileURLWithPath: note.path)
        var result: String
        if NoteBacklinkScanner.scheme(of: value) == "file" {
            result = file.absoluteString
        } else if decoded.hasPrefix("/") {
            result = plain ? file.path : encodedPath(file.pathComponents.dropFirst(), prefix: "/")
        } else if decoded == "~" || decoded.hasPrefix("~/"),
                  let relative = NoteFilePaths.relativePath(from: FileManager.default.homeDirectoryForCurrentUser, to: file),
                  !relative.hasPrefix("..") {
            result = "~/" + (plain ? (relative.removingPercentEncoding ?? relative) : relative)
        } else if let relative = NoteFilePaths.relativePath(from: folder, to: file) {
            result = plain ? (relative.removingPercentEncoding ?? relative) : relative
        } else {
            result = file.absoluteString
        }
        if wiki, NoteFileKind(pathExtension: (decoded as NSString).pathExtension) == nil,
           (result as NSString).pathExtension.lowercased() == "md" {
            result = (result as NSString).deletingPathExtension
        }
        return (angled ? "<" + result + ">" : result) + fragment
    }

    private static func encodedPath(_ components: ArraySlice<String>, prefix: String) -> String {
        prefix + components.map(NoteFilePaths.encodedSegment).joined(separator: "/")
    }

    @discardableResult
    package static func rewrite(_ block: inout NoteBlock, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> Bool {
        var changed = false
        if block.kind == .pageLink, let current = block.props.target,
           let next = target(current, resolvingFrom: folder, writingFrom: newFolder, move: move, wiki: false) {
            if block.text.plainText == NoteMDLinks.stem(current) { block.text = NoteText(NoteMDLinks.stem(next)) }
            block.props.target = next
            changed = true
        }
        for field in NotePageFinder.fields(of: block) {
            guard var text = block.text(in: field), rewrite(&text, resolvingFrom: folder, writingFrom: newFolder, move: move) else { continue }
            block.setText(text, in: field)
            changed = true
        }
        return changed
    }

    package static func rewrite(_ text: inout NoteText, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> Bool {
        var changed = false
        for run in text.runs() {
            if let atom = run.marks.atom {
                guard case .page(let current, let title) = atom,
                      let next = target(current, resolvingFrom: folder, writingFrom: newFolder, move: move,
                                        wiki: isWikiStyle(target: current, title: title)) else { continue }
                let replacement = NoteText.atom(.page(target: next, title: retitled(title, target: current, next: next)), marks: run.marks.withoutAtom)
                for offset in run.range { text.replace(offset..<(offset + 1), with: replacement) }
                changed = true
            } else if let link = run.marks.link,
                      let next = target(link, resolvingFrom: folder, writingFrom: newFolder, move: move, wiki: false) {
                text.updateMarks(in: run.range) { $0.link = next }
                changed = true
            }
        }
        return changed
    }

    package static func rewrite(_ page: NotePage, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> NotePage? {
        var changed = false
        func walk(_ list: inout [NoteBlock]) {
            for index in list.indices {
                if rewrite(&list[index], resolvingFrom: folder, writingFrom: newFolder, move: move) { changed = true }
                walk(&list[index].children)
            }
        }
        var next = page
        var blocks = next.blocks
        walk(&blocks)
        guard changed else { return nil }
        next.blocks = blocks
        return next
    }

    package static func rewriteFile(at url: URL, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> Bool {
        guard NoteFileKind(url: url) == .markdown, let read = try? NoteFileIO.readStamped(url, kind: .markdown) else { return false }
        let original = read.contents.text
        guard let text = rewritten(original, format: read.contents.format, resolvingFrom: folder, writingFrom: newFolder, move: move) else { return false }
        let encoded = NoteFileText.encode(text, format: read.contents.format)
        var coordination: NSError?
        var outcome = NoteFileWriteOutcome.failed("")
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordination) { target in
            outcome = NoteFileIO.writeNow(encoded.data, text: text, to: target, kind: .markdown, expecting: original, force: false)
        }
        return coordination == nil && outcome.succeeded
    }

    package static func rewritten(_ original: String, format: NoteFileFormat? = nil, resolvingFrom folder: URL, writingFrom newFolder: URL,
                          move: NoteBacklinkMove) -> String? {
        let normalized = NoteFileText.normalizedLineEndings(original)
        guard let page = rewrite(NoteMarkdown.parse(normalized), resolvingFrom: folder, writingFrom: newFolder, move: move) else { return nil }
        let expected = NoteMarkdown.serialize(page)
        if let surgical = rewriteMarkdown(original, resolvingFrom: folder, writingFrom: newFolder, move: move),
           NoteMarkdown.serialize(NoteMarkdown.parse(NoteFileText.normalizedLineEndings(surgical))) == expected {
            return surgical
        }
        let fallback = format ?? NoteFileText.decode(Data(original.utf8), kind: .markdown)?.format ?? .standard
        return NoteFileText.fileText(expected, format: fallback, kind: .markdown)
    }

    package static func rewriteMarkdown(_ source: String, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> String? {
        var lines = source.components(separatedBy: "\n")
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\r"))
        var fence: (marker: Character, count: Int)?
        var frontMatter = lines.first?.trimmingCharacters(in: edges) == "---"
        var changed = false
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: edges)
            if frontMatter {
                if index > 0, trimmed == "---" || trimmed == "..." { frontMatter = false }
                continue
            }
            let content = trimmed.drop(while: { $0 == ">" || $0 == " " || $0 == "\t" })
            if let marker = content.first, marker == "`" || marker == "~" {
                let count = content.prefix(while: { $0 == marker }).count
                if count >= 3 {
                    if let open = fence {
                        if open.marker == marker, count >= open.count, content.drop(while: { $0 == marker }).allSatisfy(\.isWhitespace) { fence = nil }
                    } else {
                        fence = (marker, count)
                    }
                    continue
                }
            }
            guard fence == nil else { continue }
            if let next = rewriteLine(line, resolvingFrom: folder, writingFrom: newFolder, move: move) {
                lines[index] = next
                changed = true
            }
        }
        return changed ? lines.joined(separator: "\n") : nil
    }

    package static func rewriteLine(_ line: String, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> String? {
        let characters = Array(line)
        var output = ""
        var changed = false
        var index = 0
        var copied = 0
        func flush(upTo end: Int) {
            if end > copied { output += String(characters[copied..<end]) }
            copied = max(copied, end)
        }
        if let definition = referenceDefinition(characters) {
            let raw = String(characters[definition])
            if let next = target(raw, resolvingFrom: folder, writingFrom: newFolder, move: move, wiki: false) {
                flush(upTo: definition.lowerBound)
                output += next
                copied = definition.upperBound
                changed = true
            }
            index = characters.count
        }
        var opens: [Int] = []
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if character == "`" {
                let run = characters[index...].prefix(while: { $0 == "`" }).count
                var probe = index + run
                var closedAt: Int?
                while probe < characters.count {
                    if characters[probe] == "`" {
                        let length = characters[probe...].prefix(while: { $0 == "`" }).count
                        if length == run {
                            closedAt = probe + length
                            break
                        }
                        probe += length
                    } else {
                        probe += 1
                    }
                }
                index = closedAt ?? (index + run)
                continue
            }
            if character == "[", index + 1 < characters.count, characters[index + 1] == "[",
               let close = wikiClose(characters, from: index + 2) {
                let inner = String(characters[(index + 2)..<close])
                if let next = rewriteWiki(inner, resolvingFrom: folder, writingFrom: newFolder, move: move) {
                    flush(upTo: index + 2)
                    output += next
                    copied = close
                    changed = true
                }
                index = close + 2
                continue
            }
            if character == "[" {
                opens.append(index)
                index += 1
                continue
            }
            if character == "]", let open = opens.popLast() {
                if index + 1 < characters.count, characters[index + 1] == "(",
                   let destination = inlineDestination(characters, from: index + 2) {
                    let isImage = open > 0 && characters[open - 1] == "!"
                    if !isImage, destination.titled == false {
                        let raw = String(characters[destination.range])
                        if let next = target(raw, resolvingFrom: folder, writingFrom: newFolder, move: move, wiki: false) {
                            let label = String(characters[(open + 1)..<index])
                            if label == NoteMDLinks.stem(raw), !label.contains(where: { "\\*_`~[]<>&!$=".contains($0) }) {
                                flush(upTo: open + 1)
                                output += escaped(NoteMDLinks.stem(next))
                                copied = index
                            }
                            flush(upTo: destination.range.lowerBound)
                            output += next
                            copied = destination.range.upperBound
                            changed = true
                        }
                    }
                    opens.removeAll()
                    index = destination.end
                    continue
                }
            }
            index += 1
        }
        guard changed else { return nil }
        flush(upTo: characters.count)
        return output
    }

    private static func rewriteWiki(_ inner: String, resolvingFrom folder: URL, writingFrom newFolder: URL, move: NoteBacklinkMove) -> String? {
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let current = parts[0].trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty else { return nil }
        let alias = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        let title = alias ?? current
        guard let next = target(current, resolvingFrom: folder, writingFrom: newFolder, move: move,
                                wiki: isWikiStyle(target: current, title: title)) else { return nil }
        guard let alias else { return next }
        return next + "|" + retitled(alias, target: current, next: next)
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<>&!$=~|".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func wikiClose(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        while index + 1 < characters.count {
            let character = characters[index]
            if character == "]" { return characters[index + 1] == "]" && index > start ? index : nil }
            if character == "[" { return nil }
            index += 1
        }
        return nil
    }

    private static func inlineDestination(_ characters: [Character], from start: Int) -> (range: Range<Int>, end: Int, titled: Bool)? {
        var index = start
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        guard index < characters.count else { return nil }
        let begin = index
        if characters[index] == "<" {
            index += 1
            while index < characters.count, characters[index] != ">", characters[index] != "<" {
                index += characters[index] == "\\" ? 2 : 1
            }
            guard index < characters.count, characters[index] == ">" else { return nil }
            index += 1
        } else {
            var depth = 0
            while index < characters.count {
                let character = characters[index]
                if character == "\\" { index += 2; continue }
                if character == " " || character == "\t" { break }
                if character == "(" { depth += 1 }
                if character == ")" {
                    if depth == 0 { break }
                    depth -= 1
                }
                index += 1
            }
        }
        let range = begin..<min(index, characters.count)
        guard !range.isEmpty else { return nil }
        var probe = range.upperBound
        while probe < characters.count, characters[probe] == " " || characters[probe] == "\t" { probe += 1 }
        guard probe < characters.count else { return nil }
        if characters[probe] == ")" { return (range, probe + 1, false) }
        guard "\"'(".contains(characters[probe]) else { return nil }
        var close = probe + 1
        while close < characters.count, characters[close] != ")" { close += 1 }
        guard close < characters.count else { return nil }
        return (range, close + 1, true)
    }

    private static func referenceDefinition(_ characters: [Character]) -> Range<Int>? {
        var index = 0
        while index < characters.count, index < 3, characters[index] == " " { index += 1 }
        guard index < characters.count, characters[index] == "[", index + 1 < characters.count, characters[index + 1] != "^" else { return nil }
        index += 1
        let labelStart = index
        while index < characters.count, characters[index] != "]" {
            if characters[index] == "[" { return nil }
            index += characters[index] == "\\" ? 2 : 1
        }
        guard index < characters.count, index > labelStart, index + 1 < characters.count, characters[index + 1] == ":" else { return nil }
        index += 2
        while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
        guard index < characters.count else { return nil }
        let begin = index
        if characters[index] == "<" {
            while index < characters.count, characters[index] != ">" { index += 1 }
            guard index < characters.count else { return nil }
            index += 1
        } else {
            while index < characters.count, !characters[index].isWhitespace { index += 1 }
        }
        return begin < index ? begin..<index : nil
    }
}
