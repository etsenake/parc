import Foundation

extension NoteButton {
    package var summary: String {
        guard !actions.isEmpty else { return "Does nothing yet" }
        return actions.map { action -> String in
            switch action {
            case .insert(let placement, let blocks):
                let count = NotePage(blocks: blocks).allBlocks().count
                let noun = count == 1 ? "1 block" : "\(count) blocks"
                return "Adds \(noun) " + placement.phrase
            case .confirm: return "Asks first"
            case .open(let target): return target.isEmpty ? "Opens nothing yet" : "Opens " + NoteButton.targetLabel(target)
            }
        }.joined(separator: ", then ")
    }

    package static func targetLabel(_ target: String) -> String {
        if let url = URL(string: target), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return url.host ?? target
        }
        if NoteMDLinks.isRelativeMarkdown(target) { return NoteMDLinks.stem(target) }
        return target.removingPercentEncoding ?? target
    }
}

extension NotePage {
    func buttonInsertion(for id: NoteBlockID, placement: NoteButtonPlacement, carrying blocks: [NoteBlock]) -> NoteInsertion? {
        guard contains(id) else { return nil }
        switch placement {
        case .top: return .top(0)
        case .bottom: return .top(self.blocks.count)
        case .below, .above:
            var anchor = id
            if blocks.contains(where: { $0.kind.isColumnStructure }),
               let outer = ancestors(of: id).last(where: { block($0)?.kind == .columns }) {
                anchor = outer
            }
            return placement == .below ? .after(anchor) : .before(anchor)
        }
    }
}

extension NotePageSession {
    static let buttonPressName = "Press Button"

    @discardableResult
    func insertFromButton(_ id: NoteBlockID, blocks template: [NoteBlock], placement: NoteButtonPlacement, press token: UUID) -> [NoteBlockID] {
        guard !template.isEmpty, let position = page.buttonInsertion(for: id, placement: placement, carrying: template) else { return [] }
        let copies = template.map { $0.withFreshIDs() }
        edit(Self.buttonPressName, coalescing: .lasting(id, token), selecting: { $0.clamped(self.selection) }) { page in
            page.insert(copies, position)
        }
        return copies.map(\.id)
    }

    package func setButton(_ id: NoteBlockID, name: String? = nil, icon: String?? = nil, actions: [NoteButtonAction]? = nil,
                   undoName: String = "Edit Button", coalescing: NoteEditCoalescing = .none) {
        guard let block = page.block(id), block.kind == .button else { return }
        var button = block.buttonValue
        if let name { button.name = name }
        if let actions { button.actions = actions }
        let nextIcon = icon ?? block.props.icon
        guard button != block.props.button || nextIcon != block.props.icon else { return }
        edit(undoName, kind: .text, coalescing: coalescing, affected: [id], selecting: { $0.clamped(self.selection) }) { page in
            page.update(id) { block in
                block.props.button = button
                block.props.icon = nextIcon
            }
        }
    }

    @discardableResult
    package func unwrapButton(_ id: NoteBlockID) -> [NoteBlockID] {
        guard let block = page.block(id), block.kind == .button else { return [] }
        let blocks = block.buttonValue.templateBlocks.map { $0.withFreshIDs() }
        let landing: NotePageSelection = blocks.isEmpty ? selection : Self.landing(after: blocks)
        edit("Turn into Blocks", selecting: { $0.clamped(landing) }) { page in
            if !blocks.isEmpty { page.insert(blocks, .after(id)) }
            page.removeBlocks([id])
            page.collapseEmptyColumns()
        }
        return blocks.map(\.id)
    }
}

@MainActor
package final class NoteButtonPress {
    package typealias Confirm = @MainActor (String, @escaping @MainActor (Bool) -> Void) -> Void
    package typealias Open = @MainActor (String) -> Void

    package let session: NotePageSession
    package let button: NoteBlockID
    package let actions: [NoteButtonAction]
    private let token = UUID()
    private let confirm: Confirm
    private let open: Open
    package private(set) var inserted: [NoteBlockID] = []
    package private(set) var isFinished = false
    package private(set) var wasCancelled = false
    package var onFinish: (@MainActor (NoteButtonPress) -> Void)?

    package init?(session: NotePageSession, button: NoteBlockID, confirm: @escaping Confirm, open: @escaping Open) {
        guard let block = session.page.block(button), block.kind == .button else { return nil }
        self.session = session
        self.button = button
        self.actions = block.buttonValue.actions
        self.confirm = confirm
        self.open = open
    }

    package func start() {
        advance(from: 0)
    }

    private func advance(from start: Int) {
        var index = start
        while index < actions.count {
            guard session.page.contains(button) else { break }
            let action = actions[index]
            index += 1
            switch action {
            case .insert(let placement, let blocks):
                inserted += session.insertFromButton(button, blocks: blocks, placement: placement, press: token)
            case .open(let target):
                let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { open(trimmed) }
            case .confirm(let message):
                let next = index
                confirm(message) { [self] proceed in
                    if proceed {
                        advance(from: next)
                    } else {
                        wasCancelled = true
                        finish()
                    }
                }
                return
            }
        }
        finish()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinish?(self)
    }
}
