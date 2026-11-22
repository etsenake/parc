import Foundation

package struct NotePageMathNumbering: Equatable {
    package struct Entry: Equatable {
        var firstNumber = 0
        var numbers = 0
        var labels: [String] = []
        var duplicateLabels: Set<String> = []

        init(firstNumber: Int = 0, numbers: Int = 0, labels: [String] = [], duplicateLabels: Set<String> = []) {
            self.firstNumber = firstNumber
            self.numbers = numbers
            self.labels = labels
            self.duplicateLabels = duplicateLabels
        }
    }

    var entries: [NoteBlockID: Entry] = [:]
    var references: [String: [NoteMathNode]] = [:]
    package var targets: [String: NoteBlockID] = [:]
    var referenceDigest = ""
    var total = 0

    package init(entries: [NoteBlockID: Entry] = [:], references: [String: [NoteMathNode]] = [:], targets: [String: NoteBlockID] = [:], referenceDigest: String = "", total: Int = 0) {
        self.entries = entries
        self.references = references
        self.targets = targets
        self.referenceDigest = referenceDigest
        self.total = total
    }

    package func context(for id: NoteBlockID) -> NoteMathNumberingContext {
        let entry = entries[id] ?? Entry(firstNumber: total)
        return NoteMathNumberingContext(firstNumber: entry.firstNumber, references: references, takenLabels: entry.duplicateLabels,
                                        referenceDigest: referenceDigest)
    }

    package var inlineContext: NoteMathNumberingContext {
        NoteMathNumberingContext(firstNumber: 0, references: references, takenLabels: [], referenceDigest: referenceDigest)
    }
}

package final class NotePageMathNumberer {
    private struct Scan {
        var numbers: Int
        var labels: [NoteMathLabel]
    }

    private var scans: [String: Scan?] = [:]

    package init() {}

    package func numbering(for page: NotePage, drafts: [NoteBlockID: String] = [:]) -> NotePageMathNumbering {
        var result = NotePageMathNumbering()
        var used: Set<String> = []
        var count = 0
        for block in page.allBlocks() where block.kind == .equation {
            let source = drafts[block.id] ?? block.text.string
            var entry = NotePageMathNumbering.Entry(firstNumber: count)
            if let scan = scan(source) {
                let duplicates = Set(scan.labels.map(\.key)).intersection(result.targets.keys)
                if duplicates.isEmpty {
                    entry.numbers = scan.numbers
                    entry.labels = scan.labels.map(\.key)
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
