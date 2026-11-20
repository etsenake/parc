import Foundation

enum NoteMDButtonFormat {
    static let flag = "button"
    static let insertKey = "insert"
    static let confirmKey = "confirm"
    static let openKey = "open"

    static func action(_ node: NoteMDBlock) -> NoteButtonAction? {
        guard node.kind == .html, let attributes = NoteMDAttributes.parse(NoteMDByte.string(node.content)) else { return nil }
        return action(attributes)
    }

    static func action(_ attributes: NoteMDAttributes) -> NoteButtonAction? {
        guard attributes.kind == nil, !attributes.flags.contains(flag) else { return nil }
        if let value = attributes.values[insertKey] {
            return .insert(placement: NoteButtonPlacement(rawValue: value.lowercased()) ?? .below, blocks: [])
        }
        if attributes.flags.contains(insertKey) { return .insert(placement: .below, blocks: []) }
        if let message = attributes.values[confirmKey] { return .confirm(message: message) }
        if attributes.flags.contains(confirmKey) { return .confirm(message: "") }
        if let target = attributes.values[openKey] { return .open(target: target) }
        return nil
    }

    static func marker(for action: NoteButtonAction) -> (String, String?) {
        switch action {
        case .insert(let placement, _): return (insertKey, placement.rawValue)
        case .confirm(let message): return (confirmKey, message)
        case .open(let target): return (openKey, target)
        }
    }

    static func usesImplicitInsert(_ actions: [NoteButtonAction]) -> Bool {
        guard actions.count == 1, case .insert(.below, let blocks) = actions[0] else { return false }
        return blocks.contains { !NoteMDWriter.isBareEmptyParagraph($0) }
    }

    static func label(name: String, icon: String?) -> String {
        [icon ?? "", name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func name(fromLabel label: String, icon: String?) -> String {
        guard let icon, !icon.isEmpty else { return label }
        if label == icon { return "" }
        let prefix = icon + " "
        return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : label
    }
}

extension NoteMDReader {
    func button(_ opener: DetailsOpener, label: NoteText, attributes: NoteMDAttributes, children: ArraySlice<NoteMDBlock>,
                trailing: Int) -> NoteBlock {
        var block = NoteBlock(.button)
        apply(attributes, to: &block)
        block.props.expanded = opener.open
        let name = NoteMDButtonFormat.name(fromLabel: label.plainText, icon: block.props.icon)
        block.props.button = NoteButton(name: name, actions: buttonActions(children, trailing: trailing))
        return block
    }

    private func buttonActions(_ children: ArraySlice<NoteMDBlock>, trailing: Int) -> [NoteButtonAction] {
        var markers: [(index: Int, action: NoteButtonAction)] = []
        var probe = children.startIndex
        while probe < children.endIndex {
            let node = children[probe]
            if node.kind == .html, let opener = Self.details(node.content), !opener.closed,
               let close = matchingDetailsClose(children, after: probe) {
                probe = close + 1
                continue
            }
            if let action = NoteMDButtonFormat.action(node) { markers.append((probe, action)) }
            probe += 1
        }
        guard let first = markers.first else {
            guard !children.isEmpty || trailing > 0 else { return [] }
            return [.insert(placement: .below, blocks: sequence(children, documentEdges: false, trailingBlank: trailing + 1))]
        }
        var actions: [NoteButtonAction] = []
        let leading = children[children.startIndex..<first.index]
        if !leading.isEmpty {
            actions.append(.insert(placement: .below, blocks: sequence(leading, documentEdges: false, trailingBlank: children[first.index].blankBefore)))
        }
        for (offset, marker) in markers.enumerated() {
            let end = offset + 1 < markers.count ? markers[offset + 1].index : children.endIndex
            let segment = children[(marker.index + 1)..<end]
            let trailingBlank = end < children.endIndex ? children[end].blankBefore : trailing + 1
            switch marker.action {
            case .insert(let placement, _):
                actions.append(.insert(placement: placement, blocks: sequence(segment, documentEdges: false, trailingBlank: trailingBlank)))
            case .confirm, .open:
                actions.append(marker.action)
                if !segment.isEmpty {
                    actions.append(.insert(placement: .below, blocks: sequence(segment, documentEdges: false, trailingBlank: trailingBlank)))
                }
            }
        }
        return actions
    }
}

extension NoteMDWriter {
    func button(_ block: NoteBlock) -> [String] {
        let button = block.buttonValue
        let icon = block.props.icon.flatMap { $0.isEmpty ? nil : $0 }
        var items: [(String, String?)] = [(NoteMDButtonFormat.flag, nil)]
        if let icon { items.append(("icon", icon)) }
        items += blockAttributes(block)
        let label = NoteMDButtonFormat.label(name: button.name, icon: icon)
        let content = inline.write(NoteText(label), style: NoteMDInlineStyle(shape: .line, htmlSafe: true, trailingComment: true)) + suffix(items)
        let opener = block.props.expanded ? "<details open>" : "<details>"
        let summary = "<summary>" + content + "</summary>"
        if button.actions.isEmpty { return [opener, summary, "</details>"] }
        if NoteMDButtonFormat.usesImplicitInsert(button.actions) {
            return [opener, summary] + sequence(button.actions[0].blocks, frame: .container(leading: 1, trailing: 1)) + ["</details>"]
        }
        var lines = [opener, summary]
        for action in button.actions {
            if lines.last != "" { lines.append("") }
            lines.append(attributes([NoteMDButtonFormat.marker(for: action)]))
            if case .insert(_, let blocks) = action {
                lines += sequence(blocks, frame: .container(leading: 1, trailing: 1))
            }
        }
        if lines.last != "" { lines.append("") }
        lines.append("</details>")
        return lines
    }
}
