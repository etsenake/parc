import AppKit
import ParcCore

@MainActor
final class EaselQuickActionsView: NSView, NoteFloatingPanelContent {
    var preferredSizeDidChange: (() -> Void)?
    let field = NoteSearchField(placeholder: "Add, draw or zoom…")
    let list = NoteMenuList()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.textField.setAccessibilityLabel("Quick actions")
        list.minimumWidth = 300
        list.maximumWidth = 340
        list.maximumHeight = 360
        list.noResultsTitle = "Nothing by that name. Try “sticky” or “zoom”?"
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        addSubview(field)
        addSubview(list)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let menu = list.intrinsicContentSize
        return NSSize(width: max(300, menu.width), height: NoteTheme.menuInset * 2 + NoteTheme.fieldHeight + menu.height)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    override func layout() {
        super.layout()
        let inset = NoteTheme.menuInset
        field.frame = NSRect(x: inset * 2, y: inset * 2, width: max(0, bounds.width - inset * 4), height: NoteTheme.fieldHeight)
        list.frame = NSRect(x: 0, y: field.frame.maxY, width: bounds.width, height: max(0, bounds.height - field.frame.maxY))
    }
}

@MainActor
final class EaselQuickActions {
    struct Action {
        let id: String
        let title: String
        let icon: NoteIcon
        let shortcut: String?
        let keywords: [String]
        let section: String
        var isEnabled = true
        let run: () -> Void
    }

    private static var recentIDs: [String] = []
    private static let recentPrefix = "recent:"
    private var popover: NotePagePopover?
    var isOpen: Bool { popover?.isOpen == true }

    func toggle(in host: NSView, anchor: NSRect, edge: NoteFloatingPanel.Edge = .below, actions: [Action], onClose: @escaping () -> Void) {
        if isOpen { popover?.close(); return }
        let view = EaselQuickActionsView(frame: .zero)
        let recents = Self.recentIDs.compactMap { id in actions.first { $0.id == id && $0.isEnabled } }
        let all = actions.map { Self.item(for: $0, id: $0.id, section: $0.section) }
        let withRecents = recents.map { Self.item(for: $0, id: Self.recentPrefix + $0.id, section: "Recent") } + all
        view.list.items = withRecents
        view.field.onChange = { [weak view] text in
            guard let view else { return }
            let filtering = !text.trimmingCharacters(in: .whitespaces).isEmpty
            view.list.setItems(filtering ? all : withRecents, keepingHighlight: false)
            view.list.filterText = text
            view.list.prepare(origin: .keyboard)
        }
        view.field.onCommand = { [weak view] selector in view?.list.handle(command: selector) ?? false }
        view.list.onActivate = { [weak self] item in
            let id = item.id.hasPrefix(Self.recentPrefix) ? String(item.id.dropFirst(Self.recentPrefix.count)) : item.id
            guard let action = actions.first(where: { $0.id == id }), action.isEnabled else { return }
            self?.popover?.close()
            Self.recentIDs.removeAll { $0 == id }
            Self.recentIDs.insert(id, at: 0)
            if Self.recentIDs.count > 3 { Self.recentIDs.removeLast(Self.recentIDs.count - 3) }
            action.run()
        }
        view.list.onCancel = { [weak self] in self?.popover?.close() }
        let next = NotePagePopover(content: view)
        next.panel.maximumHeight = 420
        next.onClose = { [weak self, weak next] in
            guard let self, self.popover === next else { return }
            self.popover = nil
            onClose()
        }
        popover = next
        next.present(in: host, anchor: anchor, edge: edge, alignment: .center)
        view.list.prepare(origin: .keyboard)
        view.field.focus()
    }

    func close() { popover?.close() }

    private static func item(for action: Action, id: String, section: String) -> NoteMenuList.Item {
        var item = NoteMenuList.Item(id: id, title: action.title, icon: action.icon, shortcut: action.shortcut, section: section,
                                     isEnabled: action.isEnabled)
        item.keywords = action.keywords
        return item
    }
}

extension EaselQuickActions {
    static func catalogInserts(canvas: EaselCanvasView, canInsert: ((EaselInsertKind) -> Bool)? = nil, focus: @escaping () -> Void) -> [Action] {
        guard canvas.fixedCanvasSize == nil else { return [] }
        return EaselInsertKind.allCases.compactMap { kind in
            guard let itemKind = kind.itemKind else { return nil }
            return Action(id: "insert-" + kind.rawValue, title: kind.title, icon: kind.icon, shortcut: nil, keywords: kind.keywords,
                          section: "Add",
                          isEnabled: canInsert?(kind) ?? (kind != .embed || canvas.pageObjects != nil)) { [weak canvas] in
                canvas?.placeEmptyObject(itemKind)
                focus()
            }
        }
    }

    static func boardActions(canvas: EaselCanvasView, inserts: [Action] = [], focus: @escaping () -> Void) -> [Action] {
        var actions: [Action] = []
        func tool(_ tool: EaselTool, _ keywords: [String], section: String) {
            guard tool.isAvailable else { return }
            actions.append(.init(id: tool.rawValue, title: tool.title, icon: EaselToolPalette.icon(for: tool), shortcut: tool.key?.label,
                                 keywords: keywords, section: section) { [weak canvas] in
                canvas?.activateTool(tool); focus()
            })
        }
        tool(.sticky, ["note", "card", "idea"], section: "Objects")
        for shape in EaselToolPalette.shapeTools {
            let shapeTool: EaselTool = shape == .ellipse ? .ellipse : .rectangle
            actions.append(.init(id: "shape-" + shape.rawValue,
                                 title: shape == .ellipse ? shapeTool.title : EaselToolPalette.shapeTitle(shape),
                                 icon: EaselToolPalette.icon(for: shape),
                                 shortcut: shape == .ellipse || shape == .rectangle ? shapeTool.key?.label : nil,
                                 keywords: ["shape", shape == .ellipse ? "circle oval" : shape == .rectangle ? "square box" : ""],
                                 section: "Objects") { [weak canvas] in
                canvas?.armShape(shape); focus()
            })
        }
        for connector in EaselToolPalette.connectorTools { tool(connector, ["arrow", "line", "connector", "link"], section: "Objects") }
        tool(.text, ["type", "words", "label", "title"], section: "Objects")
        tool(.section, ["frame", "area", "group", "region"], section: "Objects")
        tool(.table, ["grid", "rows", "columns", "cells"], section: "Objects")
        for drawing in EaselToolPalette.drawTools { tool(drawing, ["draw", "pen", "pencil", "doodle"], section: "Tools") }
        tool(.stamp, ["emoji", "sticker", "vote", "react"], section: "Tools")
        tool(.select, ["move", "pointer", "cursor", "arrow"], section: "Tools")
        tool(.hand, ["pan", "scroll", "move", "grab"], section: "Tools")
        actions += inserts
        tool(.codeBlock, ["code", "snippet", "monospace", "program"], section: "Add")
        if canvas.fixedCanvasSize == nil {
            actions.append(.init(id: "mind-map", title: "Mind map", icon: .symbol(EaselToolPalette.mindMapSymbol), shortcut: nil,
                                 keywords: ["mindmap", "tree", "brainstorm", "ideas", "branches"], section: "Add") { [weak canvas] in
                _ = canvas?.insertMindMap()
            })
        }
        let zoomSymbols: [EaselZoomCommand: String] = [.zoomIn: "plus.magnifyingglass", .zoomOut: "minus.magnifyingglass",
                                                       .fit: "viewfinder", .selection: "scope", .actualSize: "1.magnifyingglass"]
        for command in [EaselZoomCommand.zoomIn, .zoomOut, .fit, .selection, .actualSize] {
            actions.append(.init(id: "zoom-" + command.rawValue, title: command.title, icon: .symbol(zoomSymbols[command] ?? "magnifyingglass"),
                                 shortcut: command.shortcut, keywords: ["zoom", "view", "scale"], section: "View",
                                 isEnabled: command != .selection || canvas.canZoomToSelection) { [weak canvas] in
                canvas?.zoom(command); focus()
            })
        }
        return actions
    }
}
