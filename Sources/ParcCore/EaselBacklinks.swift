import Foundation

enum EaselBacklinkScanner {
    static let readLimit = 8 * 1024 * 1024
    private static let root = URL(fileURLWithPath: "/", isDirectory: true)

    static func mayLink(_ data: Data) -> Bool {
        data.range(of: Data("file:".utf8)) != nil
    }

    static func read(fileAt url: URL) -> (title: String, links: [NoteOutgoingLink])? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= readLimit,
              let document = try? JSONDecoder().decode(EaselDocument.self, from: data) else { return nil }
        return (document.title, mayLink(data) ? outgoing(in: document) : [])
    }

    static func outgoing(in document: EaselDocument) -> [NoteOutgoingLink] {
        var result: [NoteOutgoingLink] = []
        for item in EaselFinder.readingOrder(document.items) { result += outgoing(of: item) }
        return result
    }

    static func outgoing(of item: EaselItem) -> [NoteOutgoingLink] {
        let anchor = item.id.uuidString.lowercased()
        var result: [NoteOutgoingLink] = []
        if item.kind.holdsText, let raw = item.url, let key = NoteBacklinkScanner.targetKey(raw, from: root) {
            let label = item.text.isEmpty ? "Linked object" : item.text
            result.append(NoteOutgoingLink(target: key, kind: .link, snippet: .whole(label), anchor: anchor))
        }
        guard let rich = item.richText else { return result }
        var open: (key: String, link: String, start: Int, end: Int)?
        func close() {
            guard let current = open else { return }
            result.append(NoteOutgoingLink(target: current.key, kind: .link,
                                           snippet: .around(current.start..<current.end, in: item.text), anchor: anchor))
            open = nil
        }
        for run in rich.runs {
            guard let link = run.attributes.link, let key = NoteBacklinkScanner.targetKey(link, from: root) else {
                close()
                continue
            }
            if let current = open, current.link == link, current.end == run.location {
                open?.end = run.location + run.length
            } else {
                close()
                open = (key, link, run.location, run.location + run.length)
            }
        }
        close()
        return result
    }
}

enum EaselBacklinkRewriter {
    private static let root = URL(fileURLWithPath: "/", isDirectory: true)

    static func replacement(for raw: String, move: NoteBacklinkMove) -> String? {
        guard NoteBacklinkScanner.targetKey(raw, from: root) == move.fromKey else { return nil }
        var fragment = ""
        if let hash = raw.firstIndex(of: "#") { fragment = String(raw[hash...]) }
        return URL(fileURLWithPath: move.to.path).absoluteString + fragment
    }

    static func rewrite(_ document: EaselDocument, move: NoteBacklinkMove) -> EaselDocument? {
        var next = document
        var changed = false
        for index in next.items.indices {
            if next.items[index].kind.holdsText, let raw = next.items[index].url,
               let replaced = replacement(for: raw, move: move), EaselRichText.isInternalLink(replaced) {
                next.items[index].url = replaced
                changed = true
            }
            guard var rich = next.items[index].richText else { continue }
            var touched = false
            for run in rich.runs.indices {
                guard let link = rich.runs[run].attributes.link, let replaced = replacement(for: link, move: move),
                      EaselRichText.isInternalLink(replaced) else { continue }
                rich.runs[run].attributes.link = replaced
                touched = true
            }
            if touched {
                next.items[index].richText = rich
                changed = true
            }
        }
        return changed ? next : nil
    }
}
