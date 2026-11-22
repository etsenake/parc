import AppKit
import ParcCore
import ParcKit
import ParcNotes

@MainActor
package final class EaselSelectionToolbar: EaselSelectionToolbarPresenting {
    private let host = EaselSelectionToolbarHost(frame: .zero)
    private let bar = EaselSelectionToolbarView(frame: .zero)
    private var madePanel: NoteFloatingPanel?
    private var panel: NoteFloatingPanel {
        if let madePanel { return madePanel }
        let made = NoteFloatingPanel(content: bar)
        made.alignment = .center
        made.gap = EaselSelectionToolbarPlacement.gap
        made.margin = EaselSelectionToolbarPlacement.margin
        made.setAccessibilityElement(false)
        madePanel = made
        host.accessibilityExcluded = made
        return made
    }
    private var isPresented: Bool { madePanel?.isPresented == true }
    private weak var canvas: EaselCanvasView?
    private weak var observedScroll: NSScrollView?
    private weak var observedOuter: NSClipView?
    private weak var observedWindow: NSWindow?
    private var viewportObservers: [NSObjectProtocol] = []
    private var responderObservation: NSKeyValueObservation?
    private var content: EaselSelectionToolbarContent?
    private var menu: (control: EaselToolbarControl, popover: NotePagePopover, keys: (NSEvent) -> Bool, isList: Bool)?
    private var refreshing = false

    package init() {
        bar.onPress = { [weak self] model, button, origin in self?.press(model, button: button, origin: origin) }
        bar.onExitKeyboard = { [weak self] in self?.exitKeyboard() }
        bar.keyInterceptor = { [weak self] event in self?.menuKey(event) ?? false }
    }

    package func refresh(for canvas: EaselCanvasView) {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if self.canvas !== canvas { detach(); self.canvas = canvas; bar.accessibilityOwner = canvas }
        guard let next = canvas.selectionToolbarContent, attach(to: canvas) else {
            if canvas.window == nil { detach() } else { hide(animated: true) }
            return
        }
        let reselected = content?.selection != next.selection
        if reselected || canvas.start != nil { closeMenu(animated: true) }
        content = next
        bar.update(next.groups)
        if let menu, bar.button(for: menu.control) == nil { closeMenu(animated: false) }
        place(animated: true, reselected: reselected)
    }

    package func detach() {
        closeMenu(animated: false)
        if isPresented { panel.dismiss(animated: false) }
        bar.isKeyboardActive = false
        content = nil
        stopObserving()
        host.removeFromSuperview()
    }

    package func settle() {
        guard let madePanel else { return }
        NoteAnimation.settle(madePanel)
    }

    package func owns(_ responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view === host || view.isDescendant(of: host)
    }

    package var accessibilityToolbar: Any? { isPresented ? bar : nil }

    package func focusFromKeyboard() -> Bool {
        guard let canvas, content != nil else { return false }
        if !isPresented { place(animated: false, reselected: false) }
        guard isPresented, let window = bar.window, window === canvas.window, bar.acceptsFirstResponder else { return false }
        return window.makeFirstResponder(bar)
    }

    private func attach(to canvas: EaselCanvasView) -> Bool {
        guard let scroll = canvas.enclosingScrollView, let window = canvas.window,
              let container = canvas.selectionToolbarContainer ?? scroll.superview,
              let below = sequence(first: scroll as NSView, next: \.superview).first(where: { $0.superview === container }) else { return false }
        if host.superview !== container {
            host.removeFromSuperview()
            container.addSubview(host, positioned: .above, relativeTo: below)
        } else if let hostIndex = container.subviews.firstIndex(of: host), let belowIndex = container.subviews.firstIndex(of: below),
                  hostIndex < belowIndex {
            container.addSubview(host, positioned: .above, relativeTo: below)
        }
        fitHost(to: scroll)
        observe(scroll: scroll, window: window)
        return true
    }

    private func fitHost(to scroll: NSScrollView) {
        guard let container = host.superview else { return }
        let frame = container === scroll.superview ? scroll.frame : container.bounds
        if host.frame != frame { host.frame = frame }
    }

    private func observe(scroll: NSScrollView, window: NSWindow) {
        let outer = scroll.superview?.enclosingScrollView?.contentView
        if observedScroll !== scroll || observedOuter !== outer {
            for observer in viewportObservers { NotificationCenter.default.removeObserver(observer) }
            observedScroll = scroll
            observedOuter = outer
            scroll.contentView.postsBoundsChangedNotifications = true
            scroll.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            if let outer {
                outer.postsBoundsChangedNotifications = true
                viewportObservers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: outer, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.viewportChanged() }
                })
            }
            viewportObservers += [
                center.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.viewportChanged() }
                },
                center.addObserver(forName: NSView.frameDidChangeNotification, object: scroll, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.viewportChanged() }
                },
            ]
        }
        if observedWindow !== window {
            observedWindow = window
            responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let canvas = self.canvas else { return }
                    DispatchQueue.main.async { [weak self, weak canvas] in
                        guard let self, let canvas, self.canvas === canvas else { return }
                        self.refresh(for: canvas)
                    }
                }
            }
        }
    }

    private func stopObserving() {
        for observer in viewportObservers { NotificationCenter.default.removeObserver(observer) }
        viewportObservers.removeAll()
        observedScroll = nil
        observedOuter = nil
        responderObservation = nil
        observedWindow = nil
    }

    private func viewportChanged() {
        guard let canvas, let scroll = observedScroll, canvas.enclosingScrollView === scroll, content != nil else { return }
        fitHost(to: scroll)
        place(animated: false, reselected: false)
        if let menu, let button = bar.button(for: menu.control) {
            menu.popover.reposition(anchor: host.convert(button.bounds, from: button), edge: .below)
        }
    }

    private func place(animated: Bool, reselected: Bool) {
        guard let canvas, let content, host.superview != nil, let scroll = canvas.enclosingScrollView else { return }
        fitHost(to: scroll)
        let size = bar.fittingSize
        let selection = host.convert(content.anchor, from: canvas)
        var open = scroll.bounds
        let covered = CGFloat(EaselFloatingBar.cover(Double(canvas.toolState.coveredBottom), viewportHeight: Double(open.height)))
        open.size.height -= covered
        if !scroll.isFlipped { open.origin.y += covered }
        let area = host.convert(open, from: scroll).intersection(host.bounds)
        let clipped = host.visibleRect.intersection(area)
        let visible = clipped.isEmpty ? area : clipped
        guard let placement = EaselSelectionToolbarPlacement.place(selection: Self.easelRect(selection), width: size.width,
                                                                   height: size.height, visible: Self.easelRect(visible)) else {
            closeMenu(animated: false)
            if isPresented { panel.dismiss(animated: false); canvas.selectionToolbarStructureChanged() }
            return
        }
        let frame = NSRect(x: placement.frame.x, y: placement.frame.y, width: placement.frame.width, height: placement.frame.height)
        let gap = EaselSelectionToolbarPlacement.gap
        let anchor: NSRect
        let edge: NoteFloatingPanel.Edge
        switch placement.edge {
        case .above:
            anchor = NSRect(x: frame.midX, y: frame.maxY + gap, width: 0, height: 0)
            edge = .above
        case .below, .inside:
            anchor = NSRect(x: frame.midX, y: frame.minY - gap, width: 0, height: 0)
            edge = .below
        }
        bar.tooltipAnchor = edge == .above ? .top : .bottom
        if isPresented, panel.superview === host {
            panel.reposition(anchor: anchor, edge: edge, animated: animated && !reselected)
            if reselected {
                NoteAnimation.cancelHUD(panel)
                NoteAnimation.presentHUD(panel, about: panel.scaleOrigin)
            }
        } else {
            panel.present(in: host, anchor: anchor, edge: edge, animated: true)
            canvas.selectionToolbarStructureChanged()
        }
    }

    private static func easelRect(_ rect: NSRect) -> EaselRect {
        EaselRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    private func hide(animated: Bool) {
        closeMenu(animated: animated)
        content = nil
        let hadFocus = bar.window?.firstResponder === bar
        bar.isKeyboardActive = false
        guard isPresented else { return }
        panel.dismiss(animated: animated)
        if hadFocus { canvas?.returnFocusFromSelectionToolbar() }
        canvas?.selectionToolbarStructureChanged()
    }

    private func press(_ model: EaselToolbarButtonModel, button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let canvas, model.isEnabled else { return }
        if let menu {
            let same = menu.control == model.control
            closeMenu(animated: true)
            if same { return }
        }
        switch model.opens {
        case .menu: openMenu(model.control, from: button, origin: origin)
        case .stylePicker: openStylePicker(model.control, from: button, origin: origin)
        case .shapePicker: openShapePicker(model.control, from: button, origin: origin)
        case .highlightPicker: openHighlightPicker(model.control, from: button, origin: origin)
        case .nothing: canvas.performSelectionToolbar(model.control, anchor: button)
        }
    }

    private func openStylePicker(_ control: EaselToolbarControl, from button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let picker = canvas?.makeStylePicker() else { return }
        picker.onCancel = { [weak self] in self?.closeMenu(animated: true) }
        picker.prepare(origin: origin)
        present(picker, control: control, from: button, isList: false) { [weak picker] event in picker?.handleKeyDown(event) ?? false }
    }

    private func openHighlightPicker(_ control: EaselToolbarControl, from button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let canvas, canvas.highlightMenuState != nil else { return }
        let picker = NoteColorMenuView(model: highlightModel(for: canvas))
        picker.onPick = { [weak self, weak canvas] choice in
            self?.closeMenu(animated: true)
            canvas?.applyHighlight(choice.color)
            canvas?.returnFocusFromSelectionToolbar()
        }
        picker.onCancel = { [weak self] in self?.closeMenu(animated: true) }
        picker.prepare(origin: origin)
        present(picker, control: control, from: button, isList: false) { [weak picker] event in picker?.handleKeyDown(event) ?? false }
    }

    private func highlightModel(for canvas: EaselCanvasView) -> NoteColorMenuModel {
        let summary: NoteColorSummary
        switch canvas.highlightMenuState {
        case .color(let color)?: summary = NoteColorSummary(background: color, uniform: .background(color))
        case .mixed?: summary = NoteColorSummary(isBackgroundMixed: true)
        default: summary = .plain
        }
        return NoteColorMenuModel(recents: NoteColorRecents.load(), summary: summary, backgroundsOnly: true)
    }

    private func openShapePicker(_ control: EaselToolbarControl, from button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let picker = canvas?.makeSelectionToolbarShapePicker() else { return }
        let pick = picker.onPick
        picker.onPick = { [weak self] shape in
            self?.closeMenu(animated: true)
            pick?(shape)
        }
        picker.onCancel = { [weak self] in self?.closeMenu(animated: true) }
        picker.prepare(origin: origin)
        present(picker, control: control, from: button, isList: false) { [weak picker] event in picker?.handleKeyDown(event) ?? false }
    }

    private func openMenu(_ control: EaselToolbarControl, from button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard let canvas else { return }
        let entries = canvas.selectionToolbarMenu(for: control)
        guard !entries.isEmpty else { return }
        let list = NoteMenuList(items: entries.map { entry in
            let turnInto = control == .paragraph ? EaselParagraphEditing.Kind(rawValue: entry.id)?.turnInto : nil
            var item = NoteMenuList.Item(id: entry.id, title: entry.title,
                                         icon: turnInto.map(NoteTurnIntoMenu.icon(for:)) ?? entry.symbol.map { .symbol($0) }, shortcut: entry.shortcut,
                                         isChecked: entry.isChecked, isEnabled: entry.isEnabled, isDestructive: entry.isDestructive)
            item.separatorBefore = entry.separatorBefore
            item.iconTint = entry.tint
            return item
        })
        list.minimumWidth = 180
        list.prepare(origin: origin)
        list.onActivate = { [weak self, weak canvas] item in
            guard let self else { return }
            self.closeMenu(animated: true)
            canvas?.performSelectionToolbarMenu(control, entry: item.id)
        }
        list.onCancel = { [weak self] in self?.closeMenu(animated: true) }
        present(list, control: control, from: button, isList: true) { [weak list] event in list?.handleKeyDown(event) ?? false }
        if origin == .keyboard { list.moveHighlight(by: 1) }
    }

    private func present(_ content: NSView, control: EaselToolbarControl, from button: NoteToolbarButton, isList: Bool,
                         keys: @escaping (NSEvent) -> Bool) {
        let popover = NotePagePopover(content: content)
        popover.exempt(button)
        popover.onKeyDown = keys
        popover.onClose = { [weak self, weak popover] in
            guard let self, let popover, self.menu?.popover === popover else { return }
            self.menu = nil
            self.bar.openControl = nil
        }
        menu = (control, popover, keys, isList)
        bar.openControl = control
        popover.present(in: host, anchor: host.convert(button.bounds, from: button), edge: .below, alignment: .leading)
    }

    private func closeMenu(animated: Bool) {
        guard let current = menu else { return }
        menu = nil
        bar.openControl = nil
        current.popover.close(animated: animated)
    }

    private func menuKey(_ event: NSEvent) -> Bool {
        guard let menu else { return false }
        if menu.isList, event.keyCode == 123 || event.keyCode == 124 { closeMenu(animated: true); return false }
        if event.keyCode == 53 { closeMenu(animated: true); return true }
        return menu.keys(event)
    }

    private func exitKeyboard() {
        closeMenu(animated: true)
        bar.isKeyboardActive = false
        canvas?.returnFocusFromSelectionToolbar()
    }
}

@MainActor
final class EaselSelectionToolbarHost: NSView {
    weak var accessibilityExcluded: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    override func accessibilityChildren() -> [Any]? {
        NSAccessibility.unignoredChildren(from: subviews.filter { $0 !== accessibilityExcluded })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class EaselSelectionToolbarView: NSView, NoteFloatingPanelContent {
    var preferredSizeDidChange: (() -> Void)?
    weak var accessibilityOwner: NSView?
    var onPress: ((EaselToolbarButtonModel, NoteToolbarButton, NoteMenuList.Origin) -> Void)?
    var onExitKeyboard: (() -> Void)?
    var keyInterceptor: ((NSEvent) -> Bool)?
    private(set) var groups: [[EaselToolbarButtonModel]] = []
    private var buttons: [EaselToolbarControl: NoteToolbarButton] = [:]
    private var dividers: [NSView] = []
    private let focusRing = CALayer()
    private(set) var focusedIndex: Int?
    var isKeyboardActive = false {
        didSet {
            guard oldValue != isKeyboardActive else { return }
            if !isKeyboardActive { setFocus(nil) }
        }
    }
    var tooltipAnchor: TooltipConfiguration.Anchor = .top {
        didSet { if oldValue != tooltipAnchor { refreshTooltips() } }
    }
    var openControl: EaselToolbarControl? {
        didSet { if oldValue != openControl { applyChecks() } }
    }

    private var models: [EaselToolbarButtonModel] { groups.flatMap { $0 } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRing.cornerRadius = NoteTheme.controlRadius + 1.5
        focusRing.cornerCurve = .continuous
        focusRing.borderWidth = 1.5
        focusRing.opacity = 0
        layer?.addSublayer(focusRing)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Selection tools")
        NoteAnimation.observeReduceMotion(self) { [weak self] in
            guard let self, let layer = self.layer else { return }
            NoteAnimation.settle(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { models.contains(where: \.isEnabled) }
    override func accessibilityParent() -> Any? {
        accessibilityOwner.flatMap { NSAccessibility.unignoredAncestor(of: $0) } ?? super.accessibilityParent()
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override var intrinsicContentSize: NSSize {
        var width = NoteFormatBarView.padding * 2
        for (index, group) in groups.enumerated() {
            if index > 0 { width += NoteFormatBarView.dividerSlot }
            for (offset, model) in group.enumerated() {
                if offset > 0 { width += NoteFormatBarView.spacing }
                width += buttons[model.control]?.intrinsicContentSize.width ?? 0
            }
        }
        return NSSize(width: ceil(width), height: NoteTheme.toolbarHeight)
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    func button(for control: EaselToolbarControl) -> NoteToolbarButton? { buttons[control] }

    func update(_ next: [[EaselToolbarButtonModel]]) {
        let rebuild = next.map { $0.map(\.control) } != groups.map { $0.map(\.control) }
        let previous = rebuild ? [] : models
        groups = next
        if rebuild { rebuildButtons() }
        for model in models {
            guard let button = buttons[model.control] else { continue }
            let old = previous.first { $0.control == model.control }
            let content = button.content
            if case .text(let title) = model.face, button.content != .text(title) { button.content = .text(title) }
            if case .symbolAndText(let symbol, let title) = model.face, button.content != .iconAndText(.symbol(symbol), title) {
                button.content = .iconAndText(.symbol(symbol), title)
            }
            if case .symbol(let symbol) = model.face, button.content != .icon(.symbol(symbol)) { button.content = .icon(.symbol(symbol)) }
            if button.content != content, old != nil { EaselControlSurface.crossfade(button, duration: NoteAnimation.hoverDuration, pops: nil) }
            if button.iconTint != model.tint {
                let recolored = button.iconTint != nil && model.tint != nil && old != nil
                button.iconTint = model.tint
                if recolored, button.window != nil { NoteAnimation.pop(button, from: 0.78, spring: .check) }
            }
            button.isEnabled = model.isEnabled
            if old?.value != model.value || old == nil { button.setAccessibilityValue(model.value) }
            guard old?.name != model.name || old?.shortcut != model.shortcut || old?.commandID != model.commandID || old?.face != model.face else { continue }
            button.setAccessibilityLabel(Self.accessibilityLabel(model))
            button.setToolTip(model.name, shortcut: model.shortcut, commandID: model.commandID, anchor: tooltipAnchor)
        }
        applyChecks()
        if let focusedIndex, !(models.indices.contains(focusedIndex) && models[focusedIndex].isEnabled) {
            setFocus(NoteFormatBarFocus.move(from: nil, by: 1, enabled: models.map(\.isEnabled)))
        }
        relayout()
    }

    private static func accessibilityLabel(_ model: EaselToolbarButtonModel) -> String {
        if case .text(let title) = model.face { return model.name + ", " + title }
        return model.name
    }

    private func applyChecks() {
        for model in models { buttons[model.control]?.isChecked = model.control == openControl || model.isChecked }
    }

    private func rebuildButtons() {
        for button in buttons.values { button.removeFromSuperview() }
        for divider in dividers { divider.removeFromSuperview() }
        buttons.removeAll()
        dividers.removeAll()
        for (index, group) in groups.enumerated() {
            if index > 0 {
                let divider = EaselSelectionToolbarDivider(frame: .zero)
                dividers.append(divider)
                addSubview(divider)
            }
            for model in group {
                let button = Self.makeButton(for: model)
                let control = model.control
                button.onPress = { [weak self, weak button] in
                    guard let self, let button, let current = self.models.first(where: { $0.control == control }) else { return }
                    self.press(current, button: button, origin: .pointer)
                }
                buttons[control] = button
                addSubview(button)
            }
        }
        focusedIndex = nil
        placeFocusRing(animated: false)
    }

    private static func makeButton(for model: EaselToolbarButtonModel) -> NoteToolbarButton {
        let button: NoteToolbarButton
        switch model.face {
        case .symbol(let name): button = NoteToolbarButton(icon: .symbol(name), label: model.name)
        case .glyph(let glyph):
            button = NoteToolbarButton(icon: .glyph(glyph), label: model.name)
            button.iconPointSize = 15
        case .text(let title): button = NoteToolbarButton(.text(title), label: model.name)
        case .symbolAndText(let symbol, let title): button = NoteToolbarButton(.iconAndText(.symbol(symbol), title), label: model.name)
        }
        switch model.mark {
        case .none: break
        case .italic: button.decoration = [.italic]
        case .underline: button.decoration = [.underline, .regularWeight]
        case .strikethrough: button.decoration = [.strikethrough, .regularWeight]
        }
        button.showsDisclosure = model.showsDisclosure
        if model.opens != .nothing { button.setAccessibilityRole(.menuButton) }
        button.iconTint = model.tint
        button.setFrameSize(button.intrinsicContentSize)
        return button
    }

    private func relayout() {
        let before = frame.size
        var x = NoteFormatBarView.padding
        var dividerIndex = 0
        let height = NoteTheme.toolbarHeight
        NoteAnimation.withoutAnimation {
            for (index, group) in groups.enumerated() {
                if index > 0, dividers.indices.contains(dividerIndex) {
                    dividers[dividerIndex].frame = NSRect(x: x + (NoteFormatBarView.dividerSlot - 1) / 2, y: (height - 18) / 2, width: 1, height: 18)
                    dividerIndex += 1
                    x += NoteFormatBarView.dividerSlot
                }
                for (offset, model) in group.enumerated() {
                    guard let button = buttons[model.control] else { continue }
                    if offset > 0 { x += NoteFormatBarView.spacing }
                    let size = button.intrinsicContentSize
                    button.frame = NSRect(x: x, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
                    x += size.width
                }
            }
        }
        invalidateIntrinsicContentSize()
        if intrinsicContentSize != before {
            setFrameSize(intrinsicContentSize)
            preferredSizeDidChange?()
        }
        placeFocusRing(animated: false)
    }

    private func refreshTooltips() {
        for model in models {
            buttons[model.control]?.setToolTip(model.name, shortcut: model.shortcut, commandID: model.commandID, anchor: tooltipAnchor)
        }
    }

    private func press(_ model: EaselToolbarButtonModel, button: NoteToolbarButton, origin: NoteMenuList.Origin) {
        guard button.isEnabled else { return }
        if origin == .keyboard, let index = models.firstIndex(where: { $0.control == model.control }) { setFocus(index) }
        onPress?(model, button, origin)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isKeyboardActive = true
            if focusedIndex == nil { setFocus(NoteFormatBarFocus.move(from: nil, by: 1, enabled: models.map(\.isEnabled))) }
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, openControl == nil { isKeyboardActive = false }
        return resigned
    }

    private func setFocus(_ index: Int?) {
        let previous = focusedIndex
        focusedIndex = index
        placeFocusRing(animated: previous != nil)
        if let index, models.indices.contains(index), let button = buttons[models[index].control] {
            NSAccessibility.post(element: button, notification: .focusedUIElementChanged)
        }
    }

    private func placeFocusRing(animated: Bool) {
        guard isKeyboardActive, let index = focusedIndex, models.indices.contains(index), let button = buttons[models[index].control] else {
            NoteAnimation.fade(focusRing, to: 0, duration: animated ? NoteAnimation.hoverDuration : 0)
            return
        }
        NoteAnimation.withoutAnimation { focusRing.borderColor = NoteTheme.resolved(NoteTheme.accent.withAlphaComponent(0.75), in: self) }
        let target = button.frame.insetBy(dx: -1.5, dy: -1.5)
        if animated, focusRing.opacity > 0 {
            NoteAnimation.slideLayer(focusRing, to: target, spring: .glide)
        } else {
            NoteAnimation.withoutAnimation { focusRing.frame = target }
            NoteAnimation.fade(focusRing, to: 1, duration: NoteAnimation.hoverDuration)
        }
    }

    private func activateFocused() -> Bool {
        guard let index = focusedIndex, models.indices.contains(index), let button = buttons[models[index].control],
              button.isEnabled else { return false }
        press(models[index], button: button, origin: .keyboard)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if keyInterceptor?(event) == true { return }
        if !handleKeyboard(event) { super.keyDown(with: event) }
    }

    private func handleKeyboard(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let enabled = models.map(\.isEnabled)
        switch event.keyCode {
        case 123: setFocus(NoteFormatBarFocus.move(from: focusedIndex, by: -1, enabled: enabled)); return true
        case 124: setFocus(NoteFormatBarFocus.move(from: focusedIndex, by: 1, enabled: enabled)); return true
        case 115: setFocus(NoteFormatBarFocus.move(from: nil, by: 1, enabled: enabled)); return true
        case 119: setFocus(NoteFormatBarFocus.move(from: nil, by: -1, enabled: enabled)); return true
        case 36, 76, 49, 125: return activateFocused()
        case 53: onExitKeyboard?(); return true
        default: return false
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        placeFocusRing(animated: false)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

@MainActor
private final class EaselSelectionToolbarDivider: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NoteTheme.resolved(NoteTheme.menuSeparator, in: self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension EaselParagraphEditing.Kind {
    var turnInto: NoteTurnIntoOption {
        switch self {
        case .text: return .text
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        case .heading4: return .heading4
        case .bullets: return .bulletedList
        case .numbers: return .numberedList
        case .checklist: return .todoList
        case .quote: return .quote
        }
    }
}
