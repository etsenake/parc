import AppKit
import ParcCore
import ParcKit

@MainActor
final class NotePropertiesView: NSView {
    static let gutter: CGFloat = 24
    static let rowHeight: CGFloat = 32
    static let keyWidth: CGFloat = 156

    unowned let editor: NotePageEditor
    var onHeightChange: (() -> Void)?
    var isRevealed = false { didSet { if isRevealed != oldValue { rebuildFooter(); onHeightChange?() } } }
    var isEditable = true { didSet { if isEditable != oldValue { for row in rows { row.isEditable = isEditable }; rebuildFooter() } } }
    private(set) var properties: [NotePageProperty] = []
    private var rows: [NotePropertyRowView] = []
    private let addChip = NoteChip("Add a property", icon: .symbol("plus"), style: .ghost)
    private var popover: NotePagePopover?
    private var drag: (row: NotePropertyRowView, start: NSPoint, origin: CGFloat, index: Int, target: Int)?

    init(editor: NotePageEditor) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Properties")
        addChip.onPress = { [weak self] in self?.beginAdding() }
        addSubview(addChip)
        rebuildFooter()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var showsAddChip: Bool { isEditable && (isRevealed || !properties.isEmpty) }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let valueWidth = max(80, width - Self.gutter - Self.keyWidth - 8)
        var height: CGFloat = 0
        for row in rows { height += row.preferredHeight(valueWidth: valueWidth) }
        if showsAddChip { height += Self.rowHeight }
        return height
    }

    func reload(_ next: [NotePageProperty]) {
        if next != properties { cancelDrag() }
        let previousCount = properties.count
        properties = next
        if next.isEmpty && previousCount > 0 { isRevealed = false }
        while rows.count > next.count { rows.removeLast().removeFromSuperview() }
        while rows.count < next.count {
            let row = NotePropertyRowView(owner: self)
            row.isEditable = isEditable
            rows.append(row)
            addSubview(row)
            if previousCount > 0, window != nil { NoteAnimation.insert(row) }
        }
        for (index, property) in next.enumerated() { rows[index].configure(property, index: index) }
        rebuildFooter()
        needsLayout = true
        onHeightChange?()
    }

    private func rebuildFooter() {
        addChip.isHidden = !showsAddChip
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard drag == nil else { return }
        layoutRows(animated: false)
    }

    private func layoutRows(animated: Bool, skipping skipped: NotePropertyRowView? = nil, gapAt gap: Int? = nil) {
        let valueWidth = max(80, bounds.width - Self.gutter - Self.keyWidth - 8)
        var y: CGFloat = 0
        var ordered = rows
        if let skipped, let gap, let index = ordered.firstIndex(where: { $0 === skipped }) {
            ordered.remove(at: index)
            ordered.insert(skipped, at: min(gap, ordered.count))
        }
        for row in ordered {
            let height = row.preferredHeight(valueWidth: valueWidth)
            let frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
            guard row !== skipped else { continue }
            if animated && !NoteAnimation.reduceMotion && row.frame.width > 0 {
                NoteAnimation.slide(row, to: frame, spring: .reorder)
            } else {
                NoteAnimation.withoutAnimation { row.frame = frame }
            }
        }
        let chipSize = addChip.intrinsicContentSize
        addChip.frame = NSRect(x: Self.gutter - 8, y: y + (Self.rowHeight - chipSize.height) / 2, width: chipSize.width, height: chipSize.height)
    }

    func update(_ name: String, _ transform: @escaping ([NotePageProperty]) -> [NotePageProperty]?) {
        guard isEditable else { return }
        guard let next = transform(editor.session.page.settings.properties) else { NSSound.beep(); return }
        guard next != editor.session.page.settings.properties else { return }
        editor.session.updateSettings(name: name) { $0.properties = next }
    }

    func setValue(_ value: NotePropertyValue, at index: Int) {
        update("Edit Property") { properties in
            guard properties.indices.contains(index) else { return nil }
            var copy = properties
            copy[index].value = value
            return copy
        }
    }

    func beginAdding() {
        guard isEditable else { return }
        let list = NoteMenuList(items: NotePropertyKind.allCases.map { kind in
            NoteMenuList.Item(id: kind.rawValue, title: kind.displayName, icon: .symbol(kind.symbolName), section: "Property type")
        })
        list.minimumWidth = 200
        let popover = NotePagePopover(content: list)
        popover.exempt(addChip)
        list.onActivate = { [weak self, weak popover] item in
            guard let self, let kind = NotePropertyKind(rawValue: item.id) else { return }
            popover?.close(animated: false)
            self.add(kind)
        }
        list.onCancel = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak list] event in list?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self] in
            guard let self else { return }
            self.popover = nil
            if self.properties.isEmpty && self.isRevealed && self.window?.firstResponder?.isKind(of: NSText.self) != true {
                self.isRevealed = false
            }
        }
        present(popover, from: addChip.isHidden ? self : addChip)
    }

    private func add(_ kind: NotePropertyKind) {
        let index = properties.count
        isRevealed = true
        update("Add Property") { NotePropertyEditing.adding(kind, to: $0) }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.rows.indices.contains(index) else { return }
            self.window?.layoutIfNeeded()
            self.presentMenu(for: index, renaming: true)
        }
    }

    func presentMenu(for index: Int, renaming: Bool) {
        guard isEditable, rows.indices.contains(index), properties.indices.contains(index) else { return }
        let property = properties[index]
        let menu = NotePropertyMenu(property: property)
        let popover = NotePagePopover(content: menu)
        popover.exempt(rows[index].keyButton)
        menu.onRename = { [weak self] name in
            self?.update("Rename Property") { NotePropertyEditing.renaming($0, at: index, to: name) }
        }
        menu.onKind = { [weak self, weak popover] kind in
            self?.endValueEditing()
            self?.update("Change Property Type") { NotePropertyEditing.changingKind($0, at: index, to: kind) }
            popover?.close()
        }
        menu.onDelete = { [weak self, weak popover] in
            popover?.close(animated: false)
            self?.endValueEditing(discardingAt: index)
            self?.update("Delete Property") { NotePropertyEditing.removing($0, at: index) }
        }
        menu.onDone = { [weak popover] in popover?.close() }
        popover.onKeyDown = { [weak menu] event in menu?.handleKeyDown(event) ?? false }
        popover.onClose = { [weak self, weak menu] in
            menu?.commitName()
            self?.popover = nil
        }
        present(popover, from: rows[index].keyButton)
        if renaming { menu.focusName() }
    }

    private func endValueEditing(discardingAt discarded: Int? = nil) {
        for (position, row) in rows.enumerated() { row.endValueEditing(committing: position != discarded) }
    }

    func presentDatePicker(for index: Int, from anchor: NSView) {
        guard isEditable, properties.indices.contains(index), case .date(let value) = properties[index].value else { return }
        let content = NotePropertyDatePanel(value: value)
        let popover = NotePagePopover(content: content)
        popover.exempt(anchor)
        content.onChange = { [weak self] next in self?.setValue(.date(next), at: index) }
        content.onDone = { [weak popover] in popover?.close() }
        popover.onClose = { [weak self] in self?.popover = nil }
        present(popover, from: anchor)
    }

    private func present(_ next: NotePagePopover, from anchor: NSView) {
        popover?.close(animated: false)
        popover = next
        let overlay = editor.canvas.overlayView
        next.present(in: overlay, anchor: overlay.convert(anchor.bounds, from: anchor), edge: .below)
    }

    func beginDrag(_ row: NotePropertyRowView, event: NSEvent) {
        guard isEditable, let index = rows.firstIndex(where: { $0 === row }) else { return }
        drag = (row, convert(event.locationInWindow, from: nil), row.frame.minY, index, index)
        addSubview(row, positioned: .above, relativeTo: nil)
        row.setLifted(true)
    }

    func continueDrag(event: NSEvent) {
        guard var current = drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let maxY = max(0, CGFloat(rows.count - 1) * Self.rowHeight)
        let top = min(max(current.origin + point.y - current.start.y, -6), maxY + 6)
        NoteAnimation.withoutAnimation { current.row.setFrameOrigin(NSPoint(x: 0, y: top)) }
        var target = 0
        var y: CGFloat = 0
        for row in rows where row !== current.row {
            let mid = y + row.frame.height / 2
            if top + current.row.frame.height / 2 > mid { target += 1 }
            y += row.frame.height
        }
        if target != current.target {
            current.target = target
            drag = current
            layoutRows(animated: true, skipping: current.row, gapAt: target)
        } else {
            drag = current
        }
    }

    private func cancelDrag() {
        guard let current = drag else { return }
        drag = nil
        current.row.setLifted(false)
    }

    func endDrag() {
        guard let current = drag else { return }
        drag = nil
        current.row.setLifted(false)
        if current.target != current.index {
            let row = rows.remove(at: current.index)
            rows.insert(row, at: current.target)
            layoutRows(animated: true)
            update("Move Property") { NotePropertyEditing.moving($0, from: current.index, to: current.target) }
        } else {
            layoutRows(animated: true)
        }
    }

    static func tagColor(_ tag: String) -> NoteColor {
        var hash: UInt32 = 2_166_136_261
        for byte in tag.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let colors = NoteColor.allCases
        return colors[Int(hash % UInt32(colors.count))]
    }
}

@MainActor
final class NotePropertyRowView: NSView, NSTextFieldDelegate {
    unowned let owner: NotePropertiesView
    let keyButton = NoteToolbarButton(.iconAndText(.symbol("text.alignleft"), ""), label: "Property")
    private let handle = NotePropertyHandle()
    private let valueField = NoteInputField()
    private let checkButton = NoteToolbarButton(icon: .symbol("circle"), label: "Checkbox")
    private let dateButton = NotePropertyValueButton(label: "Date")
    private let tags = NotePropertyTagsView()
    private(set) var property = NotePageProperty(key: "", value: .text(""))
    private(set) var index = 0
    var isEditable = true { didSet { refreshEditable() } }
    private var isHovered = false
    private var isLifted = false
    private var hoverArea: NSTrackingArea?
    private var editingOriginal: String?
    private var discardsEdit = false

    init(owner: NotePropertiesView) {
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NoteTheme.controlRadius
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        handle.onBegin = { [weak self] event in
            guard let self else { return }
            self.owner.beginDrag(self, event: event)
        }
        handle.onDrag = { [weak self] event in self?.owner.continueDrag(event: event) }
        handle.onEnd = { [weak self] in self?.owner.endDrag() }
        keyButton.onPress = { [weak self] in
            guard let self else { return }
            self.owner.presentMenu(for: self.index, renaming: false)
        }
        valueField.isBordered = false
        valueField.isBezeled = false
        valueField.drawsBackground = false
        valueField.focusRingType = .none
        valueField.font = NoteTheme.nunitoRegular(14.5)
        valueField.textColor = NoteTheme.ink
        valueField.usesSingleLineMode = true
        valueField.lineBreakMode = .byTruncatingTail
        valueField.cell?.isScrollable = true
        valueField.delegate = self
        checkButton.iconPointSize = 16
        checkButton.onPress = { [weak self] in self?.toggleCheck() }
        dateButton.onPress = { [weak self] in
            guard let self else { return }
            self.owner.presentDatePicker(for: self.index, from: self.dateButton)
        }
        tags.onChange = { [weak self] items in
            guard let self else { return }
            self.owner.setValue(.list(items), at: self.index)
        }
        tags.onHeightChange = { [weak self] in self?.owner.onHeightChange?() }
        for view in [handle, keyButton, valueField, checkButton, dateButton, tags] as [NSView] { addSubview(view) }
        handle.layer?.opacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ next: NotePageProperty, index: Int) {
        let kindChanged = next.value.kind != property.value.kind
        property = next
        self.index = index
        keyButton.content = .iconAndText(.symbol(next.value.kind.symbolName), next.key)
        keyButton.setAccessibilityLabel("\(next.key), \(next.value.kind.displayName) property")
        setAccessibilityLabel(next.key)
        let kind = next.value.kind
        valueField.isHidden = kind != .text && kind != .number
        checkButton.isHidden = kind != .checkbox
        dateButton.isHidden = kind != .date
        tags.isHidden = kind != .list
        switch next.value {
        case .text(let value):
            if valueField.currentEditor() == nil { valueField.stringValue = value }
        case .number:
            if valueField.currentEditor() == nil { valueField.stringValue = next.value.displayText }
        case .checkbox(let value):
            let wasChecked = checkButton.isChecked
            checkButton.content = .icon(.symbol(value ? "checkmark.circle.fill" : "circle"))
            checkButton.iconTint = value ? NoteTheme.todoCheckFill : NoteTheme.todoBox
            checkButton.setAccessibilityValue(value ? "Checked" : "Unchecked")
            if !kindChanged, wasChecked != value, value, window != nil { NoteAnimation.pop(checkButton, from: NoteAnimation.checkPopScale, spring: .check) }
            checkButton.isChecked = false
            checkButtonState = value
        case .date:
            dateButton.value = next.value.isEmpty ? nil : next.value.displayText
        case .list(let items):
            tags.items = items
        }
        let placeholder = kind == .number ? "0" : "Empty"
        valueField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NoteTheme.nunitoRegular(14.5), .foregroundColor: NoteTheme.tertiaryInk])
        valueField.setAccessibilityLabel(next.key)
        refreshEditable()
        needsLayout = true
    }

    private var checkButtonState = false

    private func refreshEditable() {
        valueField.isEditable = isEditable
        valueField.isSelectable = isEditable
        keyButton.isEnabled = isEditable
        checkButton.isEnabled = isEditable
        dateButton.isEnabled = isEditable
        tags.isEditable = isEditable
        handle.isHidden = !isEditable
        keyButton.alphaValue = 1
    }

    func preferredHeight(valueWidth: CGFloat) -> CGFloat {
        guard property.value.kind == .list else { return NotePropertiesView.rowHeight }
        return max(NotePropertiesView.rowHeight, tags.preferredHeight(width: valueWidth) + 4)
    }

    override func layout() {
        super.layout()
        let row = NotePropertiesView.rowHeight
        handle.frame = NSRect(x: 2, y: (row - 22) / 2, width: 18, height: 22)
        let keyHeight = NoteTheme.toolbarButtonSize.height
        keyButton.frame = NSRect(x: NotePropertiesView.gutter - 6, y: (row - keyHeight) / 2,
                                 width: min(NotePropertiesView.keyWidth, max(60, keyButton.intrinsicContentSize.width)), height: keyHeight)
        let valueX = NotePropertiesView.gutter + NotePropertiesView.keyWidth
        let valueWidth = max(60, bounds.width - valueX - 4)
        let fieldHeight = ceil(valueField.intrinsicContentSize.height)
        valueField.frame = NSRect(x: valueX + 2, y: (row - fieldHeight) / 2, width: valueWidth - 4, height: fieldHeight)
        checkButton.frame = NSRect(x: valueX - 4, y: (row - keyHeight) / 2, width: keyHeight, height: keyHeight)
        let dateWidth = min(valueWidth, dateButton.intrinsicContentSize.width)
        dateButton.frame = NSRect(x: valueX - 6, y: (row - keyHeight) / 2, width: dateWidth, height: keyHeight)
        tags.frame = NSRect(x: valueX - 2, y: 2, width: valueWidth, height: max(row - 4, tags.preferredHeight(width: valueWidth)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        guard value != isHovered else { return }
        isHovered = value
        if let layer = handle.layer { NoteAnimation.fade(layer, to: value && isEditable ? 1 : 0, duration: NoteAnimation.hoverDuration) }
        refreshBackground()
    }

    private func refreshBackground() {
        NoteAnimation.withoutAnimation {
            if isLifted {
                layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuFill, in: self)
            } else {
                layer?.backgroundColor = isHovered && isEditable ? NoteTheme.resolved(NoteTheme.hoverFill.withAlphaComponent(0.5), in: self) : nil
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
        redisplayChromeSubtree()
    }

    func setLifted(_ lifted: Bool) {
        guard let layer else { return }
        isLifted = lifted
        NoteAnimation.withoutAnimation {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowRadius = lifted ? 8 : 0
            layer.shadowOffset = CGSize(width: 0, height: 3)
        }
        refreshBackground()
        let center = NoteAnimation.layerPoint(NSPoint(x: bounds.midX, y: bounds.midY), in: self)
        let target = lifted ? NoteAnimation.scaleTransform(NoteAnimation.liftScale, about: center) : CATransform3DIdentity
        NoteAnimation.animate(layer, "transform", to: NSValue(caTransform3D: target), spring: lifted ? .lift : .settle,
                              key: NoteAnimation.keyPrefix + "property.lift")
        NoteAnimation.animate(layer, "shadowOpacity", to: lifted ? Float(0.18) : Float(0), spring: .lift,
                              key: NoteAnimation.keyPrefix + "property.shadow")
    }

    private func toggleCheck() {
        guard isEditable else { return }
        owner.setValue(.checkbox(!checkButtonState), at: index)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        editingOriginal = valueField.stringValue
        if let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView {
            editor.insertionPointColor = NoteTheme.caret
            editor.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        defer { editingOriginal = nil }
        guard !discardsEdit else { return }
        commitField()
    }

    func endValueEditing(committing: Bool) {
        guard valueField.currentEditor() != nil else { return }
        discardsEdit = !committing
        defer { discardsEdit = false }
        if window?.makeFirstResponder(nil) != true { valueField.abortEditing() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            valueField.stringValue = editingOriginal ?? valueField.stringValue
            window?.makeFirstResponder(nil)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            window?.makeFirstResponder(nil)
            return true
        default:
            return false
        }
    }

    private func commitField() {
        let text = valueField.stringValue
        switch property.value.kind {
        case .text:
            owner.setValue(.text(text), at: index)
        case .number:
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                owner.setValue(.number(0), at: index)
            } else if let number = NotePropertyEditing.parseNumber(text) {
                owner.setValue(.number(number), at: index)
            } else {
                NSSound.beep()
                valueField.stringValue = property.value.displayText
            }
        default:
            break
        }
    }
}

@MainActor
final class NotePropertyHandle: NSView {
    var onBegin: ((NSEvent) -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    var onEnd: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        addCursorUpdateArea()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            NoteTheme.handleInk.setFill()
            for column in 0..<2 {
                for row in 0..<3 {
                    let center = NSPoint(x: bounds.midX - 2.5 + CGFloat(column) * 5, y: bounds.midY - 5 + CGFloat(row) * 5)
                    NSBezierPath(ovalIn: NSRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)).fill()
                }
            }
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !applyNoteCursor(.openHand, for: event) { super.cursorUpdate(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        onBegin?(event)
    }

    override func mouseDragged(with event: NSEvent) { onDrag?(event) }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
        if !applyNoteCursor(.openHand, for: event) { window?.refreshCursorUnderPointer() }
    }
}

@MainActor
final class NotePropertyTagsView: NSView, NSTextFieldDelegate {
    var items: [String] = [] { didSet { if items != oldValue { rebuild() } } }
    var isEditable = true { didSet { field.isHidden = !isEditable; rebuild() } }
    var onChange: (([String]) -> Void)?
    var onHeightChange: (() -> Void)?
    private var chips: [NotePropertyTagChip] = []
    private let field = NoteInputField()
    private var lastHeight: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteTheme.nunitoRegular(14)
        field.textColor = NoteTheme.ink
        field.placeholderAttributedString = NSAttributedString(string: "Add a tag", attributes: [
            .font: NoteTheme.nunitoRegular(14), .foregroundColor: NoteTheme.tertiaryInk])
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityLabel("Add a tag")
        addSubview(field)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Tags")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func rebuild() {
        while chips.count > items.count { chips.removeLast().removeFromSuperview() }
        while chips.count < items.count {
            let chip = NotePropertyTagChip()
            chips.append(chip)
            addSubview(chip)
        }
        for (index, item) in items.enumerated() {
            chips[index].configure(item, removable: isEditable)
            chips[index].onRemove = { [weak self] in self?.remove(at: index) }
        }
        needsLayout = true
        let height = preferredHeight(width: bounds.width)
        if abs(height - lastHeight) > 0.5 {
            lastHeight = height
            onHeightChange?()
        }
    }

    private func positions(width: CGFloat) -> (frames: [NSRect], field: NSRect, height: CGFloat) {
        let line: CGFloat = 24, gap: CGFloat = 4
        var x: CGFloat = 0, y: CGFloat = 4
        var frames: [NSRect] = []
        for chip in chips {
            let size = chip.intrinsicContentSize
            if x > 0 && x + size.width > width { x = 0; y += line + gap }
            frames.append(NSRect(x: x, y: y, width: min(size.width, width), height: line))
            x += size.width + gap
        }
        let fieldWidth: CGFloat = isEditable ? 96 : 0
        if isEditable && x > 0 && x + fieldWidth > width { x = 0; y += line + gap }
        let fieldHeight = ceil(field.intrinsicContentSize.height)
        let fieldRect = NSRect(x: x + 4, y: y + (line - fieldHeight) / 2, width: max(fieldWidth, width - x - 4), height: fieldHeight)
        return (frames, fieldRect, y + line + 2)
    }

    func preferredHeight(width: CGFloat) -> CGFloat {
        positions(width: max(1, width)).height
    }

    override func layout() {
        super.layout()
        let placed = positions(width: bounds.width)
        for (chip, frame) in zip(chips, placed.frames) { chip.frame = frame }
        field.frame = placed.field
    }

    private func remove(at index: Int) {
        guard isEditable, items.indices.contains(index) else { return }
        var next = items
        next.remove(at: index)
        onChange?(next)
    }

    private func commit() {
        let text = field.stringValue
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        var next = items
        for piece in text.split(separator: ",") { next = NotePropertyEditing.addingTag(String(piece), to: next) }
        field.stringValue = ""
        if next != items { onChange?(next) } else { NSSound.beep() }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        if let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView {
            editor.insertionPointColor = NoteTheme.caret
            editor.selectedTextAttributes = [.backgroundColor: NoteTheme.selection]
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if field.stringValue.contains(",") { commit() }
    }

    func controlTextDidEndEditing(_ notification: Notification) { commit() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            commit()
            return commandSelector == #selector(NSResponder.insertNewline(_:))
        case #selector(NSResponder.deleteBackward(_:)):
            guard field.stringValue.isEmpty, !items.isEmpty else { return false }
            remove(at: items.count - 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            field.stringValue = ""
            window?.makeFirstResponder(nil)
            return true
        default:
            return false
        }
    }
}

@MainActor
final class NotePropertyTagChip: NSView {
    var onRemove: (() -> Void)?
    private var label = ""
    private var removable = true
    private var isHovered = false
    private var hoverArea: NSTrackingArea?
    private let remove = NoteToolbarButton(icon: .symbol("xmark"), label: "Remove tag")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        remove.iconPointSize = 8
        remove.cornerRadius = 4
        remove.onPress = { [weak self] in self?.onRemove?() }
        remove.isHidden = true
        addSubview(remove)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private var chipFont: NSFont { NoteTheme.nunitoBold(12.5) }

    func configure(_ value: String, removable: Bool) {
        label = value
        self.removable = removable
        setAccessibilityLabel(value)
        remove.setAccessibilityLabel("Remove \(value)")
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let width = ceil((label as NSString).size(withAttributes: [.font: chipFont]).width)
        return NSSize(width: width + 16, height: 24)
    }

    override func layout() {
        super.layout()
        remove.frame = NSRect(x: bounds.width - 20, y: (bounds.height - 18) / 2, width: 18, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseMoved(with event: NSEvent) { setHovered(NoteFloatingPanel.allowsHover(for: self, at: event.locationInWindow)) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        remove.isHidden = !(hovered && removable)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInOwnAppearance {
            let color = NotePropertiesView.tagColor(label)
            let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 2), xRadius: 6, yRadius: 6)
            NoteTheme.color(.background(color)).setFill()
            pill.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: chipFont, .foregroundColor: NoteTheme.color(.text(color))]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(with: NSRect(x: 8, y: (bounds.height - size.height) / 2, width: bounds.width - 16, height: size.height),
                                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
            guard isHovered, removable else { return }
            NoteTheme.color(.background(color)).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 22, y: 2, width: 22, height: bounds.height - 4), xRadius: 6, yRadius: 6).fill()
        }
    }
}

@MainActor
final class NotePropertyValueButton: NoteControlButton {
    var value: String? { didSet { if value != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true; refreshAccessibility() } } }
    private let label: String

    init(label: String) {
        self.label = label
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: NoteTheme.toolbarButtonSize.height))
        pressedScale = NoteAnimation.rowPressedScale
        refreshAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var valueFont: NSFont { NoteTheme.nunitoRegular(14.5) }

    private var shown: String { value ?? "Empty" }

    private func refreshAccessibility() {
        setAccessibilityLabel(label)
        setAccessibilityValue(value ?? "Empty")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((shown as NSString).size(withAttributes: [.font: valueFont]).width) + 16, height: NoteTheme.toolbarButtonSize.height)
    }

    override func drawContent(in bounds: NSRect, ink: NSColor) {
        drawInOwnAppearance {
            let color = value == nil ? NoteTheme.tertiaryInk : NoteTheme.ink
            let attributes: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: color]
            let size = (shown as NSString).size(withAttributes: attributes)
            (shown as NSString).draw(with: NSRect(x: 8, y: (bounds.height - size.height) / 2, width: bounds.width - 16, height: size.height),
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        }
    }
}

@MainActor
final class NotePropertyMenu: NSView, NoteFloatingPanelContent {
    var onRename: ((String) -> Void)?
    var onKind: ((NotePropertyKind) -> Void)?
    var onDelete: (() -> Void)?
    var onDone: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    private let property: NotePageProperty
    private let nameField = NoteSearchField(placeholder: "Property name")
    private let list: NoteMenuList
    private var committedName: String

    init(property: NotePageProperty) {
        self.property = property
        committedName = property.key
        var items = NotePropertyKind.allCases.map { kind in
            NoteMenuList.Item(id: kind.rawValue, title: kind.displayName, icon: .symbol(kind.symbolName), section: "Type",
                              isChecked: kind == property.value.kind)
        }
        var delete = NoteMenuList.Item(id: "delete", title: "Delete Property", icon: .symbol("trash"), isDestructive: true)
        delete.separatorBefore = true
        items.append(delete)
        list = NoteMenuList(items: items)
        list.minimumWidth = 230
        super.init(frame: .zero)
        nameField.showsIcon = false
        nameField.text = property.key
        nameField.textField.setAccessibilityLabel("Property name")
        nameField.onSubmit = { [weak self] _ in
            self?.commitName()
            self?.onDone?()
        }
        nameField.onCommand = { [weak self] selector in
            guard let self else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
                return self.list.handle(command: selector)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return self.list.hasKeyboardHighlight && self.list.activateHighlighted()
            case #selector(NSResponder.cancelOperation(_:)):
                self.nameField.text = self.committedName
                self.onDone?()
                return true
            default:
                return false
            }
        }
        list.onActivate = { [weak self] item in
            guard let self else { return }
            self.commitName()
            if item.id == "delete" { self.onDelete?(); return }
            if let kind = NotePropertyKind(rawValue: item.id) { self.onKind?(kind) }
        }
        list.onCancel = { [weak self] in self?.onDone?() }
        list.preferredSizeDidChange = { [weak self] in self?.preferredSizeDidChange?() }
        addSubview(nameField)
        addSubview(list)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let size = list.fittingSize
        return NSSize(width: max(230, size.width), height: size.height + NoteTheme.fieldHeight + 16)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        nameField.frame = NSRect(x: 8, y: 8, width: bounds.width - 16, height: NoteTheme.fieldHeight)
        list.frame = NSRect(x: 0, y: nameField.frame.maxY + 6, width: bounds.width, height: bounds.height - nameField.frame.maxY - 6)
    }

    func focusName() {
        nameField.focus()
        nameField.textField.currentEditor()?.selectAll(nil)
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard nameField.textField.currentEditor() == nil else { return false }
        return list.handleKeyDown(event)
    }

    func commitName() {
        let name = NotePropertyEditing.normalizedKey(nameField.text)
        guard name != committedName else { return }
        guard !name.isEmpty else { nameField.text = committedName; return }
        committedName = name
        onRename?(name)
    }
}

@MainActor
final class NotePropertyDatePanel: NSView, NoteFloatingPanelContent {
    var onChange: ((String) -> Void)?
    var onDone: (() -> Void)?
    var preferredSizeDidChange: (() -> Void)?
    private let picker = NSDatePicker()
    private let today = NoteChip("Today", style: .ghost)
    private let clear = NoteChip("Clear", style: .ghost)

    init(value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 230))
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.calendar = NotePropertyEditing.calendar
        picker.timeZone = NotePropertyEditing.calendar.timeZone
        picker.dateValue = NotePropertyEditing.date(from: value) ?? NotePropertyEditing.date(from: NotePropertyEditing.localDateString(from: Date())) ?? Date()
        picker.target = self
        picker.action = #selector(dateChanged)
        picker.setAccessibilityLabel("Date")
        today.onPress = { [weak self] in
            guard let self else { return }
            let value = NotePropertyEditing.localDateString(from: Date())
            if let date = NotePropertyEditing.date(from: value) { self.picker.dateValue = date }
            self.onChange?(value)
        }
        clear.onPress = { [weak self] in
            self?.onChange?("")
            self?.onDone?()
        }
        addSubview(picker)
        addSubview(today)
        addSubview(clear)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let size = picker.fittingSize
        return NSSize(width: max(220, size.width + 20), height: size.height + NoteTheme.chipHeight + 28)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func layout() {
        super.layout()
        let size = picker.fittingSize
        picker.frame = NSRect(x: (bounds.width - size.width) / 2, y: 8, width: size.width, height: size.height)
        let todayWidth = today.intrinsicContentSize.width, clearWidth = clear.intrinsicContentSize.width
        let y = picker.frame.maxY + 8
        today.frame = NSRect(x: 10, y: y, width: todayWidth, height: NoteTheme.chipHeight)
        clear.frame = NSRect(x: bounds.width - 10 - clearWidth, y: y, width: clearWidth, height: NoteTheme.chipHeight)
    }

    @objc private func dateChanged() {
        onChange?(NotePropertyEditing.dateString(from: picker.dateValue))
    }
}
