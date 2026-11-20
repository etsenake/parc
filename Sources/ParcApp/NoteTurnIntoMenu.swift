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
        case .toggleHeading4: return .glyph("▸H4")
        }
    }

    static let columnsPrefix = "columns"

    static func items(for state: NoteFormatState, columns: Int = 0) -> [NoteMenuList.Item] {
        let options = NoteTurnIntoOption.allCases.map { option in
            var item = NoteMenuList.Item(id: option.rawValue, title: option.title)
            item.icon = icon(for: option)
            item.shortcut = option.chord?.display
            item.section = title
            item.isChecked = state.isTurnIntoUniform && state.turnInto == option
            item.accessibilityLabel = "Turn into " + option.title
            return item
        }
        guard columns >= 2 else { return options }
        return options + (2...min(columns, NotePageSession.maximumColumns)).map { count in
            var item = NoteMenuList.Item(id: columnsPrefix + String(count), title: "\(count) Columns")
            item.icon = .symbol("rectangle.split.\(min(count, 3))x1")
            item.section = title
            item.accessibilityLabel = "Turn into \(count) columns"
            return item
        }
    }

    static func columnCount(for id: String) -> Int? {
        guard id.hasPrefix(columnsPrefix), let count = Int(id.dropFirst(columnsPrefix.count)) else { return nil }
        return count
    }

    static func makeList(for state: NoteFormatState, origin: NoteMenuList.Origin, columns: Int = 0,
                         onPick: @escaping (NoteTurnIntoOption) -> Void, onColumns: @escaping (Int) -> Void = { _ in },
                         onCancel: @escaping () -> Void) -> NoteMenuList {
        let list = NoteMenuList(items: items(for: state, columns: columns))
        list.minimumWidth = 236
        list.maximumHeight = 440
        list.onActivate = { item in
            if let option = NoteTurnIntoOption(rawValue: item.id) { onPick(option) }
            else if let count = columnCount(for: item.id) { onColumns(count) }
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
