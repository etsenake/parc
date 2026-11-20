import Foundation

struct NotePageMathNumbering: Equatable {
    struct Entry: Equatable {
        var firstNumber = 0
        var numbers = 0
        var duplicateLabels: Set<String> = []
    }

    var entries: [NoteBlockID: Entry] = [:]
    var references: [String: [NoteMathNode]] = [:]
    var targets: [String: NoteBlockID] = [:]
    var referenceDigest = ""
    var total = 0

    func context(for id: NoteBlockID) -> NoteMathNumberingContext {
        let entry = entries[id] ?? Entry(firstNumber: total)
        return NoteMathNumberingContext(firstNumber: entry.firstNumber, references: references, takenLabels: entry.duplicateLabels,
                                        referenceDigest: referenceDigest)
    }

    var inlineContext: NoteMathNumberingContext {
        NoteMathNumberingContext(firstNumber: 0, references: references, takenLabels: [], referenceDigest: referenceDigest)
    }
}

final class NotePageMathNumberer {
    private struct Scan {
        var numbers: Int
        var labels: [NoteMathLabel]
    }

    private var scans: [String: Scan?] = [:]

    func numbering(for page: NotePage) -> NotePageMathNumbering {
        var result = NotePageMathNumbering()
        var used: Set<String> = []
        var count = 0
        for block in page.allBlocks() where block.kind == .equation {
            let source = block.text.string
            var entry = NotePageMathNumbering.Entry(firstNumber: count)
            if let scan = scan(source) {
                let duplicates = Set(scan.labels.map(\.key)).intersection(result.targets.keys)
                if duplicates.isEmpty {
                    entry.numbers = scan.numbers
                    for label in scan.labels {
                        result.targets[label.key] = block.id
                        switch label.target {
                        case .automatic(let index): result.references[label.key] = [.text("\(count + index)", .roman)]
                        case .tag(let nodes): result.references[label.key] = nodes
                        }
                    }
                    count += scan.numbers
                } else {
                    entry.duplicateLabels = duplicates
                }
            }
            used.insert(source)
            result.entries[block.id] = entry
        }
        result.total = count
        result.referenceDigest = NoteMathNumberingContext.digest(result.references)
        if scans.count > used.count * 2 + 64 { scans = scans.filter { used.contains($0.key) } }
        return result
    }

    private func scan(_ source: String) -> Scan? {
        if let cached = scans[source] { return cached }
        let scanned: Scan?
        if source.contains("begin") || source.contains("label") || source.contains("tag") {
            scanned = (try? NoteMathParser.parseEquation(source, display: true)).map { Scan(numbers: $0.automaticNumbers, labels: $0.labels) }
        } else {
            scanned = Scan(numbers: 0, labels: [])
        }
        scans[source] = scanned
        return scanned
    }
}
