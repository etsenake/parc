import AppKit

@MainActor
enum NoteTurnIntoMenu {
    static let title = "Turn Into"

    static func icon(for option: NoteTurnIntoOption) -> NoteIcon {
        switch option {
        case .text: return .symbol("textformat")
        case .heading1: return .glyph("H1")
        case .heading2: return .glyph("H2")
        case .heading3: return .glyph("H3")
        case .heading4: return .glyph("H4")
        case .bulletedList: return .symbol("list.bullet")
        case .numberedList: return .symbol("list.number")
        case .todoList: return .symbol("checkmark.square")
        case .toggleList: return .symbol("arrowtriangle.right.fill")
        case .code: return .symbol("chevron.left.forwardslash.chevron.right")
        case .quote: return .symbol("text.quote")
        case .callout: return .symbol("lightbulb")
        case .blockEquation: return .symbol("function")
        case .toggleHeading1: return .glyph("▸H1")
        case .toggleHeading2: return .glyph("▸H2")
        case .toggleHeading3: return .glyph("▸H3")
        }
    }

    static func items(for state: NoteFormatState) -> [NoteMenuList.Item] {
        NoteTurnIntoOption.allCases.map { option in
            var item = NoteMenuList.Item(id: option.rawValue, title: option.title)
            item.icon = icon(for: option)
            item.shortcut = option.chord?.display
            item.section = title
            item.isChecked = state.isTurnIntoUniform && state.turnInto == option
            item.accessibilityLabel = "Turn into " + option.title
            return item
        }
    }

    static func makeList(for state: NoteFormatState, origin: NoteMenuList.Origin,
                         onPick: @escaping (NoteTurnIntoOption) -> Void, onCancel: @escaping () -> Void) -> NoteMenuList {
        let list = NoteMenuList(items: items(for: state))
        list.minimumWidth = 236
        list.maximumHeight = 440
        list.onActivate = { item in
            if let option = NoteTurnIntoOption(rawValue: item.id) { onPick(option) }
        }
        list.onCancel = onCancel
        list.prepare(origin: origin)
        if origin == .keyboard, state.isTurnIntoUniform, let current = state.turnInto {
            list.highlight(id: current.rawValue, animated: false)
        }
        list.setAccessibilityLabel(title)
        return list
    }
}
