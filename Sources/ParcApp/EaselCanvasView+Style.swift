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
    func applyStyle(_ change: EaselStyleChange) -> Bool {
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
        let saved = commit(change.actionName) { document in
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
final class EaselStyleMenuTarget: NSObject, NSMenuItemValidation {
    final class Choice: NSObject {
        let change: EaselStyleChange
        init(_ change: EaselStyleChange) { self.change = change }
    }

    weak var canvas: EaselCanvasView?
    let selection: Set<UUID>

    init(canvas: EaselCanvasView, selection: Set<UUID>) {
        self.canvas = canvas
        self.selection = selection
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let canvas, canvas.selection == selection, let choice = sender.representedObject as? Choice else { return }
        canvas.applyStyle(choice.change)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let canvas, canvas.selection == selection, let choice = menuItem.representedObject as? Choice else { return false }
        return canvas.styleTargets.contains { EaselStyle.applies(choice.change, to: $0) }
    }
}

extension EaselCanvasView {
    func styleMenuItems() -> [NSMenuItem] {
        guard let controls = styleControls else { return [] }
        let summary = styleSummary, dark = NoteTheme.isDark(effectiveAppearance)
        let target = EaselStyleMenuTarget(canvas: self, selection: selection)
        func row(_ title: String, _ change: EaselStyleChange, checked: Bool, image: NSImage? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(EaselStyleMenuTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = EaselStyleMenuTarget.Choice(change)
            item.state = checked ? .on : .off
            item.image = image
            return item
        }
        func parent(_ title: String, _ rows: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            rows.forEach(menu.addItem)
            item.submenu = menu
            item.representedObject = target
            return item
        }
        var items = [parent("Color", controls.colors.map { color in
            row(color.title(dark: dark), .color(.palette(color)), checked: summary.color == .palette(color),
                image: Self.swatchImage(EaselInk.color(EaselPalette.stored(color, role: controls.colorRole), adaptive: true, role: controls.colorRole),
                                        role: controls.colorRole))
        })]
        if controls.fill {
            items.append(parent("Fill", EaselFillMode.allCases.map { row($0.title, .fill($0), checked: summary.fill == $0) }))
        }
        if !controls.weights.isEmpty || controls.dash {
            var rows = controls.weights.map { weight in
                row(weight == .none ? "No Outline" : weight.title, .weight(weight), checked: summary.weight == weight)
            }
            if controls.dash {
                if !rows.isEmpty { rows.append(.separator()) }
                rows += EaselStrokeDash.allCases.map { row($0.rawValue.capitalized, .dash($0), checked: summary.dash == $0) }
            }
            if controls.labelBackground {
                rows.append(.separator())
                rows.append(row("Label Background", .labelBackground(summary.labelBackground != true), checked: summary.labelBackground == true))
            }
            items.append(parent(controls.lineTitle, rows))
        }
        return items
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
