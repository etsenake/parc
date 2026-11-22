import Foundation

package enum EaselBlockText {
    package enum Kind: Equatable {
        case text
        case heading(Int)
        case bullet
        case number
        case quote
    }

    package struct Paragraph: Equatable {
        package var kind: Kind
        package var depth: Int
        package var text: NoteText
        package init(kind: Kind, depth: Int, text: NoteText) {
            self.kind = kind
            self.depth = depth
            self.text = text
        }
    }

    static let maximumParagraphs = 5_000

    package static func paragraphs(from blocks: [NoteBlock]) -> [Paragraph] {
        var result: [Paragraph] = []
        func add(_ kind: Kind, _ depth: Int, _ text: NoteText) {
            guard result.count < maximumParagraphs else { return }
            result.append(Paragraph(kind: kind, depth: depth, text: flattened(text)))
        }
        func walk(_ list: [NoteBlock], depth: Int) {
            for block in list {
                switch block.kind {
                case .paragraph, .callout, .toggle:
                    add(.text, depth, block.text)
                    walk(block.children, depth: depth)
                case .heading:
                    add(.heading(min(max(block.props.level, 1), 4)), 0, block.text)
                    walk(block.children, depth: depth)
                case .bulletedItem:
                    add(.bullet, depth, block.text)
                    walk(block.children, depth: depth + 1)
                case .numberedItem:
                    add(.number, depth, block.text)
                    walk(block.children, depth: depth + 1)
                case .todo:
                    add(.bullet, depth, NoteText(block.props.checked ? "\u{2611} " : "\u{2610} ") + block.text)
                    walk(block.children, depth: depth + 1)
                case .quote:
                    add(.quote, 0, block.text)
                    walk(block.children, depth: depth)
                case .divider:
                    add(.text, depth, NoteText("\u{2014}\u{2014}\u{2014}"))
                case .code:
                    var marks = NoteMarks()
                    marks.code = true
                    for line in block.text.string.components(separatedBy: "\n") { add(.text, depth, NoteText(line, marks: marks)) }
                case .equation:
                    add(.text, depth, NoteText("$" + block.text.string + "$"))
                case .table:
                    for row in block.props.table?.rows ?? [] {
                        add(.text, depth, NoteText(row.map(\.plainText).joined(separator: " | ")))
                    }
                case .image, .video, .audio, .file, .pdf, .bookmark, .embed, .easel, .pageLink:
                    if let line = reference(block) { add(.text, depth, line) }
                case .tableOfContents, .breadcrumb, .html, .raw, .button:
                    continue
                case .columns, .column, .synced:
                    walk(block.children, depth: depth)
                }
            }
        }
        walk(blocks, depth: 0)
        return result
    }

    package static func reference(_ block: NoteBlock) -> NoteText? {
        let source = block.props.source ?? block.props.target ?? ""
        let label = [block.text.plainText, block.props.bookmark?.title ?? "", block.props.alt ?? "", block.props.caption.plainText]
            .first { !$0.isEmpty } ?? ""
        let linkable = source.hasPrefix("http://") || source.hasPrefix("https://")
        if label.isEmpty { return source.isEmpty ? nil : NoteText(source, marks: linkMarks(linkable ? source : nil)) }
        return NoteText(label, marks: linkMarks(linkable ? source : nil))
    }

    static func linkMarks(_ link: String?) -> NoteMarks {
        var marks = NoteMarks()
        marks.link = link
        return marks
    }

    package static func flattened(_ text: NoteText) -> NoteText {
        var pieces: [(String, NoteMarks)] = []
        for run in text.runs() {
            var marks = run.marks
            guard let atom = marks.atom else {
                pieces.append(((text.string as NSString).substring(with: NSRange(location: run.range.lowerBound, length: run.range.count)), marks))
                continue
            }
            marks.atom = nil
            var face = atom.fallbackText
            switch atom {
            case .equation(let source): face = "$" + source + "$"
            case .link(let url, let title): marks.link = url; face = title.isEmpty ? url : title
            case .page(_, let title): face = title.isEmpty ? "Untitled" : title
            default: break
            }
            pieces.append((face, marks))
        }
        return NoteText(pieces: pieces)
    }
}
