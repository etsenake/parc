import AppKit

@MainActor
enum EaselStyleDefaults {
    static var defaults = UserDefaults.standard
    private static var current: EaselStyleMemory?

    static var memory: EaselStyleMemory {
        if let current { return current }
        var generator = SystemRandomNumberGenerator()
        let made = EaselStyleMemory(families: EaselStyleMemory.persistentFamilies(from: defaults.data(forKey: EaselStyleMemory.defaultsKey)),
                                    sticky: EaselStyleMemory.randomSticky(using: &generator))
        current = made
        return made
    }

    static func record(_ change: EaselStyleChange, for families: Set<EaselStyleFamily>, document: UUID) {
        guard !families.isEmpty else { return }
        var next = memory
        for family in families { next.record(change, for: family, document: document) }
        current = next
        if !families.isDisjoint(with: EaselStyleMemory.rememberedAcrossLaunches), let data = next.persistentData {
            defaults.set(data, forKey: EaselStyleMemory.defaultsKey)
        }
    }
}

extension EaselCanvasView {
    var styleTargets: [EaselItem] {
        session.document.items.filter { selection.contains($0.id) && !$0.isLocked && EaselStyleFamily.of($0) != nil }
    }

    var styleControls: EaselStyleControls? {
        guard adaptsInk, !session.isClosed else { return nil }
        if let id = editingID, let item = session.document.items.first(where: { $0.id == id }), item.kind.holdsText {
            return EaselStyleControls(families: [.text])
        }
        return EaselStyleControls(items: styleTargets)
    }

    var styleSummary: EaselStyleSummary {
        if let editor, let id = editingID, let item = session.document.items.first(where: { $0.id == id }), item.kind.holdsText {
            return EaselStyleSummary(color: editingColorChoice(editor, item: item))
        }
        return EaselStyleSummary(items: styleTargets)
    }

    @discardableResult func applyColor(_ choice: EaselColorChoice) -> Bool { applyStyle(.color(choice)) }
    @discardableResult func applyFill(_ mode: EaselFillMode) -> Bool { applyStyle(.fill(mode)) }
    @discardableResult func applyFillOpacity(_ opacity: Double) -> Bool { applyStyle(.fillOpacity(opacity)) }
    @discardableResult func applyStrokeWeight(_ weight: EaselStrokeWeight) -> Bool { applyStyle(.weight(weight)) }
    @discardableResult func applyStrokeDash(_ dash: EaselStrokeDash) -> Bool { applyStyle(.dash(dash)) }

    @discardableResult
    func applyStyle(_ change: EaselStyleChange, coalescing group: UUID? = nil) -> Bool {
        guard adaptsInk, !session.isClosed, !session.isDeleted, editor?.hasMarkedText() != true else { return false }
        if case .color(let choice) = change, let editor, let id = editingID,
           session.document.items.contains(where: { $0.id == id && $0.kind.holdsText && !$0.isLocked }) {
            colorEditedText(choice, in: editor)
            return true
        }
        let targets = styleTargets.filter { EaselStyle.applies(change, to: $0) }
        guard !targets.isEmpty, finishImageEditing() else { return false }
        let ids = Set(targets.map(\.id))
        var families = Set<EaselStyleFamily>()
        let saved = commit(change.actionName, coalescing: group) { document in
            for index in document.items.indices where ids.contains(document.items[index].id) && !document.items[index].isLocked {
                var item = document.items[index]
                guard EaselStyle.apply(change, to: &item) else { continue }
                if let family = EaselStyleFamily.of(item) { families.insert(family) }
                document.items[index] = item
            }
        }
        guard saved else { return false }
        EaselStyleDefaults.record(change, for: families, document: session.document.id)
        return true
    }

    func stampNewConnectorStyle(on item: inout EaselItem) {
        item.color = insertionColor
        stampRememberedStyle(on: &item)
    }

    func stampRememberedStyle(on item: inout EaselItem) {
        guard adaptsInk else { return }
        EaselStyleDefaults.memory.stamp(&item, document: session.document.id)
    }

    private func editingColorChoice(_ editor: EaselStyledTextView, item: EaselItem) -> EaselColorChoice? {
        let range = editor.selectedRange()
        let text = editor.attributedString()
        var colors: [NSColor] = []
        if range.length == 0 || range.location >= text.length {
            if let color = editor.typingAttributes[.foregroundColor] as? NSColor { colors = [color] }
        } else {
            text.enumerateAttribute(.foregroundColor, in: range) { value, _, _ in
                if let color = value as? NSColor { colors.append(color) }
            }
        }
        let hexes = Set(colors.compactMap { EaselInk.canonicalHex(of: $0) ?? (try? EaselRichTextCodec.hex($0)).flatMap(EaselPalette.normalized) })
        guard hexes.count == 1, let hex = hexes.first else { return colors.isEmpty ? .recognizing(item.color, role: .ink) : nil }
        return .recognizing(hex, role: .ink)
    }

    private func colorEditedText(_ choice: EaselColorChoice, in editor: EaselStyledTextView) {
        editor.applyTextColor(EaselInk.color(choice.hex(role: .ink), adaptive: adaptsInk))
        EaselStyleDefaults.record(.color(choice), for: [.text], document: session.document.id)
    }
}

@MainActor
final class EaselStyleMenuTarget: NSObject {
    final class Action: NSObject {
        let perform: (() -> Void)?
        init(_ perform: (() -> Void)?) { self.perform = perform }
    }

    @objc func choose(_ sender: NSMenuItem) { (sender.representedObject as? Action)?.perform?() }
}

extension EaselCanvasView {
    func styleMenuRows(_ context: EaselMenuContext) -> [EaselMenuRow] {
        guard context.target != .canvas else { return [] }
        return styleRows(textColor: false)
    }

    func styleRows(textColor: Bool) -> [EaselMenuRow] {
        guard let controls = styleControls else { return [] }
        let summary = styleSummary, dark = NoteTheme.isDark(effectiveAppearance)
        func row(_ id: String, _ title: String, _ change: EaselStyleChange, checked: Bool, separated: Bool = false) -> EaselMenuRow {
            EaselMenuRow(id: "style." + id, title: title, isChecked: checked, separatorBefore: separated,
                         perform: guardedMenuAction { $0.applyStyle(change) })
        }
        var rows: [EaselMenuRow] = []
        if textColor || Set(styleTargets.compactMap(EaselStyleFamily.of)) != [.text] {
            rows.append(EaselMenuRow(id: "style.color", title: "Color", symbol: "paintpalette", children: controls.colors.map { color in
                row("color." + color.id, color.title(dark: dark), .color(.palette(color)), checked: summary.color == .palette(color))
            }))
        }
        if controls.fill {
            rows.append(EaselMenuRow(id: "style.fill", title: "Fill", symbol: "square.fill", children: EaselFillMode.allCases.map {
                row("fill." + $0.rawValue, $0.title, .fill($0), checked: summary.fill == $0)
            }))
        }
        if !controls.weights.isEmpty || controls.dash || controls.labelBackground {
            var children = controls.weights.map { weight in
                row("weight." + weight.rawValue, weight == .none ? "No Outline" : weight.title, .weight(weight), checked: summary.weight == weight)
            }
            if controls.dash {
                children += EaselStrokeDash.allCases.enumerated().map { index, dash in
                    row("dash." + dash.rawValue, dash.rawValue.capitalized, .dash(dash), checked: summary.dash == dash,
                        separated: index == 0 && !children.isEmpty)
                }
            }
            if controls.labelBackground {
                children.append(row("label", "Label Background", .labelBackground(summary.labelBackground != true),
                                    checked: summary.labelBackground == true, separated: !children.isEmpty))
            }
            rows.append(EaselMenuRow(id: "style.line", title: controls.lineTitle, symbol: "line.diagonal", children: children))
        }
        return rows
    }

    func styleMenuItems() -> [NSMenuItem] {
        let rows = styleRows(textColor: true)
        guard !rows.isEmpty, let controls = styleControls else { return [] }
        let target = EaselStyleMenuTarget()
        func item(_ row: EaselMenuRow) -> NSMenuItem {
            let made = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            made.state = row.isChecked ? .on : .off
            if row.children.isEmpty {
                made.action = #selector(EaselStyleMenuTarget.choose(_:))
                made.target = target
                made.representedObject = EaselStyleMenuTarget.Action(row.perform)
            } else {
                let menu = NSMenu(title: row.title)
                for child in row.children {
                    if child.separatorBefore { menu.addItem(.separator()) }
                    menu.addItem(item(child))
                }
                made.submenu = menu
                made.representedObject = target
            }
            let prefix = "style.color."
            if row.id.hasPrefix(prefix), let color = EaselPaletteColor(id: String(row.id.dropFirst(prefix.count))) {
                made.showImage(Self.swatchImage(EaselInk.color(EaselPalette.stored(color, role: controls.colorRole), adaptive: true,
                                                               role: controls.colorRole), role: controls.colorRole))
            }
            return made
        }
        return rows.map(item)
    }

    static func swatchImage(_ color: NSColor, role: EaselColorRole) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let shape = rect.insetBy(dx: 1, dy: 1)
            let path = role == .fill || role == .sticky ? NSBezierPath(roundedRect: shape, xRadius: 3, yRadius: 3) : NSBezierPath(ovalIn: shape)
            color.setFill(); path.fill()
            NoteTheme.menuHairline.setStroke(); path.lineWidth = 1; path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
