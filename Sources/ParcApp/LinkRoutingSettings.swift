import AppKit
import Combine

@MainActor
final class LinksSettingsView: NSView {
    private let store: BrowserStore
    private var routes: LinkRoutingWindow?
    private let automaticPeek = NSSwitch()
    private let shiftPeek = NSSwitch()
    private var settingsSubscription: AnyCancellable?
    override var isFlipped: Bool { true }

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 684, height: 562))
        let group = SettingsGroupView(frame: NSRect(x: 64, y: 202, width: 556, height: 88))
        let label = NSTextField(wrappingLabelWithString: "Choose which Space opens your links.")
        label.font = .systemFont(ofSize: 13)
        label.frame = NSRect(x: 12, y: 14, width: 340, height: 46)
        group.addSubview(label)
        let open = ActionButton("Air Traffic Control…") { [weak self] in _ = self?.showRoutes() }
        open.focusRingType = .exterior
        open.isBordered = true; open.bezelStyle = .rounded; open.contentTintColor = .labelColor
        open.frame = NSRect(x: 360, y: 22, width: 184, height: 30)
        group.addSubview(open); addSubview(group)
        //
        // inset divider, trailing switches and the pinned/favorite note.
        let explanation = NSTextField(wrappingLabelWithString: "Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet.")
        explanation.font = .systemFont(ofSize: 13)
        explanation.frame = NSRect(x: 74, y: 20, width: 536, height: 38)
        addSubview(explanation)
        let peekGroup = SettingsGroupView(frame: NSRect(x: 64, y: 74, width: 556, height: 90))
        let titles = ["Open a Peek window when clicking on links with Shift held",
                      "Open a Peek window when clicking on links to other sites"]
        for (index, toggle) in [shiftPeek, automaticPeek].enumerated() {
            let label = NSTextField(labelWithString: titles[index])
            label.font = .systemFont(ofSize: 13)
            label.frame = NSRect(x: 10, y: 9 + CGFloat(index) * 36, width: 492, height: 20)
            peekGroup.addSubview(label)
            toggle.controlSize = .small
            toggle.frame = NSRect(x: 512, y: 9 + CGFloat(index) * 44, width: 34, height: 22)
            toggle.target = self
            toggle.action = index == 0 ? #selector(changeShiftPeek(_:)) : #selector(changeAutomaticPeek(_:))
            toggle.setAccessibilityLabel(titles[index])
            peekGroup.addSubview(toggle)
        }
        let rowDivider = NSBox(frame: NSRect(x: 10, y: 36, width: 536, height: 1))
        rowDivider.boxType = .separator; peekGroup.addSubview(rowDivider)
        let note = NSTextField(labelWithString: "Note: This only affects Favorites and Pinned tabs")
        note.font = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 10, y: 66, width: 492, height: 18)
        peekGroup.addSubview(note)
        automaticPeek.setAccessibilityHelp(note.stringValue)
        addSubview(peekGroup)
        let separator = NSBox(frame: NSRect(x: 64, y: 182, width: 556, height: 1))
        separator.boxType = .separator; addSubview(separator)
        settingsSubscription = store.statePublisher.map(\.settings).removeDuplicates().receive(on: RunLoop.main).sink { [weak self] settings in
            self?.automaticPeek.state = settings.automaticPeekEnabled ? .on : .off
            self?.shiftPeek.state = settings.shiftPeekEnabled ? .on : .off
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func changeAutomaticPeek(_ sender: NSSwitch) {
        store.updateSettings { $0.automaticPeekEnabled = sender.state == .on }
    }
    @objc private func changeShiftPeek(_ sender: NSSwitch) {
        store.updateSettings { $0.shiftPeekEnabled = sender.state == .on }
    }
    func prepareForParentClose() -> Bool {
        routes?.prepareForParentClose() ?? true
    }
    @discardableResult func showRoutes() -> Bool {
        guard let window, window.attachedSheet == nil else { return false }
        let controller = LinkRoutingWindow(store: store)
        routes = controller
        controller.onClose = { [weak self] in self?.routes = nil }
        controller.present(on: window)
        return true
    }
}

//
// Persistence and conflict recovery remain explicit Parc adaptations.
@MainActor
final class LinkRoutingWindow: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuDelegate {
    private let browserStore: BrowserStore
    private var routing: LinkRoutingStore { browserStore.linkRouting }
    private let content = LayoutView(frame: NSRect(x: 0, y: 0, width: 508, height: 500))
    private let scroll = NSScrollView(frame: NSRect(x: 20, y: 82, width: 468, height: 320))
    private let listContent = LayoutView(frame: NSRect(x: 0, y: 0, width: 468, height: 320))
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let newRoute = ActionButton("New Route") {}
    private let closeButton = ActionButton("", symbol: "xmark") {}
    private let discardButton = ActionButton("Discard Changes") {}
    private let errorDetailsButton = ActionButton("Details…") {}
    private let resetButton = ActionButton("Reset…") {}
    private var subscriptions: [AnyCancellable] = []
    private struct DestinationSnapshot: Equatable {
        let spaces: [BrowserSpace]
        let profiles: [BrowserProfile]
    }
    private struct ConditionField {
        let ruleID: UUID
        let conditionID: UUID
        let field: NSTextField
        let style: NSPopUpButton
    }
    private struct DestinationField {
        let ruleID: UUID
        let popup: NSPopUpButton
        let choices: [LinkRouteDestination]
    }
    private enum RowControlRole: Hashable { case style, field, remove, destination, options }
    private struct RowControlID: Hashable {
        let ruleID: UUID
        let conditionID: UUID?
        let role: RowControlRole
    }
    private var originalRules: [LinkRoute]
    private var workingRules: [LinkRoute]
    private var conditionFields: [ConditionField] = []
    private var destinationFields: [DestinationField] = []
    private var rowViews: [UUID: NSView] = [:]
    private var rowControls: [RowControlID: NSView] = [:]
    private var keyViews: [NSView] = []
    private var pendingDestinationRefresh = false
    private var destinationRefreshScheduled = false
    private var pendingErrorUpdate = false
    private var errorUpdateScheduled = false
    private var openMenus: Set<ObjectIdentifier> = []
    private var finished = false
    var onClose: (() -> Void)?

    init(store: BrowserStore) {
        browserStore = store
        originalRules = store.linkRouting.state.rules
        workingRules = store.linkRouting.state.rules
        let window = NSPanel(contentRect: content.bounds,
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Air Traffic Control"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self; window.contentView = content
        label("Air Traffic Control", frame: NSRect(x: 24, y: 33, width: 260, height: 28), in: content, size: 19, weight: .semibold)
        newRoute.frame = NSRect(x: 306, y: 33, width: 122, height: 28)
        style(newRoute); newRoute.actionBlock = { [weak self] in self?.startRoute() }; content.addSubview(newRoute)
        closeButton.frame = NSRect(x: 452, y: 33, width: 32, height: 28)
        style(closeButton); closeButton.isBordered = false; closeButton.keyEquivalent = "\u{1b}"
        closeButton.setAccessibilityLabel("Close Air Traffic Control")
        closeButton.actionBlock = { [weak self] in self?.dismiss() }; content.addSubview(closeButton)
        let topDivider = NSBox(frame: NSRect(x: 24, y: 84, width: 460, height: 1)); topDivider.boxType = .separator; content.addSubview(topDivider)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = listContent; content.addSubview(scroll)
        let divider = NSBox(frame: NSRect(x: 24, y: 410, width: 460, height: 1)); divider.boxType = .separator; content.addSubview(divider)
        label("Default", frame: NSRect(x: 60, y: 435, width: 90, height: 24), in: content)
        label("Most Recent Space", frame: NSRect(x: 164, y: 435, width: 200, height: 24), in: content, weight: .medium)
        resetButton.frame = NSRect(x: 382, y: 432, width: 102, height: 28); style(resetButton)
        resetButton.setAccessibilityLabel("Reset all Air Traffic Control routes")
        resetButton.actionBlock = { [weak self] in self?.confirmReset() }; content.addSubview(resetButton)
        discardButton.frame = NSRect(x: 382, y: 466, width: 102, height: 26); style(discardButton)
        discardButton.isHidden = true; discardButton.actionBlock = { [weak self] in self?.discardChanges() }; content.addSubview(discardButton)
        errorDetailsButton.frame = NSRect(x: 300, y: 466, width: 74, height: 26); style(errorDetailsButton)
        errorDetailsButton.isHidden = true
        errorDetailsButton.setAccessibilityLabel("Show Air Traffic Control error details")
        errorDetailsButton.actionBlock = { [weak self] in
            guard let self else { return }
            LinkRoutingErrorDetails.present(self.routing.errorMessage, in: self.window)
        }
        content.addSubview(errorDetailsButton)
        errorLabel.font = .systemFont(ofSize: 11); errorLabel.textColor = .systemRed
        errorLabel.frame = NSRect(x: 24, y: 466, width: 270, height: 30); content.addSubview(errorLabel)
        routing.$errorMessage.dropFirst().receive(on: RunLoop.main).sink { [weak self] error in
            guard let self else { return }
            self.errorLabel.stringValue = error ?? ""
            self.applyErrorControlState()
            LinkRoutingInteraction.announceError(error, in: self.window)
        }.store(in: &subscriptions)
        store.statePublisher.map { DestinationSnapshot(spaces: $0.spaces, profiles: $0.profiles) }.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshDestinationsIfSafe()
        }.store(in: &subscriptions)
        render()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func present(on parent: NSWindow) {
        guard let window, parent.attachedSheet == nil else { return }
        errorLabel.stringValue = routing.errorMessage ?? ""
        applyErrorControlState()
        parent.beginSheet(window) { [weak self, weak window] _ in
            window?.orderOut(nil)
            self?.finishDismissal()
        }
        updateKeyViews()
        LinkRoutingInteraction.announceError(routing.errorMessage, in: window)
    }
    private func finishDismissal() {
        guard !finished else { return }
        finished = true
        subscriptions.removeAll()
        let completion = onClose; onClose = nil; completion?()
    }
    private func endSheet() {
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil); finishDismissal()
    }
    func dismiss() { _ = prepareForParentClose() }
    @discardableResult
    func prepareForParentClose() -> Bool {
        guard let window else { return true }
        guard window.attachedSheet == nil else { return false }
        let focus = LinkRoutingInteraction.captureFocus(in: window, fields: conditionFields.map { (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field) })
        window.makeFirstResponder(nil); captureEditor()
        guard routing.commitEditor(workingRules, basedOn: originalRules) else {
            discardButton.isHidden = false
            updateKeyViews()
            if focus == nil { LinkRoutingInteraction.focus(closeButton, in: window) }
            else { LinkRoutingInteraction.restoreFocus(focus, in: window, fields: conditionFields.map { (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field) }) }
            return false
        }
        endSheet(); return true
    }
    private func discardChanges() { endSheet() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }

    private func style(_ button: NSButton) {
        button.focusRingType = .exterior
        button.isBordered = true; button.bezelStyle = .rounded; button.contentTintColor = .labelColor
    }
    private func updateKeyViews() {
        var views = keyViews
        if !errorDetailsButton.isHidden { views.append(errorDetailsButton) }
        if !discardButton.isHidden { views.append(discardButton) }
        LinkRoutingInteraction.linkKeyViews(views, in: window)
    }
    private func applyErrorControlState() {
        guard !finished else { return }
        if routing.errorMessage?.isEmpty == false {
            pendingErrorUpdate = false
            errorDetailsButton.isHidden = false
            updateKeyViews()
            return
        }
        let detailsFocused = window?.firstResponder === errorDetailsButton
        if window?.attachedSheet != nil || (detailsFocused && window?.isKeyWindow != true) {
            pendingErrorUpdate = true
            return
        }
        pendingErrorUpdate = false
        if detailsFocused { LinkRoutingInteraction.focus(closeButton, in: window) }
        errorDetailsButton.isHidden = true
        updateKeyViews()
    }
    private func scheduleErrorControlUpdate() {
        guard pendingErrorUpdate, !errorUpdateScheduled, !finished else { return }
        errorUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.errorUpdateScheduled = false
            self.applyErrorControlState()
        }
    }
    @discardableResult
    private func label(_ text: String, frame: NSRect, in parent: NSView, size: CGFloat = 13,
                       weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let view = NSTextField(wrappingLabelWithString: text)
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = secondary ? .secondaryLabelColor : .labelColor
        view.frame = frame; parent.addSubview(view); return view
    }
    @discardableResult
    private func button(_ title: String, symbol: String? = nil, frame: NSRect, in parent: NSView,
                        action: @escaping () -> Void) -> ActionButton {
        let result = ActionButton(title, symbol: symbol, action: action)
        style(result); result.frame = frame; parent.addSubview(result); keyViews.append(result); return result
    }
    private func destinationTitle(_ destination: LinkRouteDestination) -> String {
        switch destination {
        case .mostRecent: return "Most Recent Space"
        case .space(let id): return browserStore.state.spaces.first { $0.id == id }?.name ?? "Unavailable Space"
        case .profile(let id):
            return browserStore.state.profiles.first { $0.id == id }.map { $0.name + " · Most Recent Space" } ?? "Unavailable Profile"
        }
    }
    private func captureEditor() {
        for item in conditionFields {
            guard let ri = workingRules.firstIndex(where: { $0.id == item.ruleID }),
                  let ci = workingRules[ri].conditions.firstIndex(where: { $0.id == item.conditionID }) else { continue }
            workingRules[ri].conditions[ci].pattern = item.field.stringValue
            workingRules[ri].conditions[ci].style = item.style.indexOfSelectedItem == 0 ? .matches : .contains
        }
        for item in destinationFields {
            guard let ri = workingRules.firstIndex(where: { $0.id == item.ruleID }),
                  item.choices.indices.contains(item.popup.indexOfSelectedItem) else { continue }
            workingRules[ri].destination = item.choices[item.popup.indexOfSelectedItem]
        }
    }
    private func render() {
        let focus = LinkRoutingInteraction.captureFocus(in: window, fields: conditionFields.map { (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field) })
        let responder = window?.firstResponder as? NSView
        let controlID = rowControls.first(where: { $0.value === responder })?.key
        listContent.subviews.forEach { $0.removeFromSuperview() }
        conditionFields.removeAll(); destinationFields.removeAll(); rowViews.removeAll(); rowControls.removeAll()
        keyViews = [newRoute, closeButton]
        if workingRules.isEmpty {
            let icon = NSImageView(frame: NSRect(x: 202, y: 68, width: 64, height: 64))
            icon.image = NSImage(systemSymbolName: "airplane.circle", accessibilityDescription: nil)
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = .secondaryLabelColor; listContent.addSubview(icon)
            let explanation = label("Routes let you choose where specific sites open inside Parc. For example, you can route Spotify links to always open inside your Personal Space.",
                frame: NSRect(x: 48, y: 150, width: 372, height: 100), in: listContent, secondary: true)
            explanation.alignment = .center; listContent.setFrameSize(NSSize(width: 468, height: 320))
        } else {
            var y: CGFloat = 24
            for (index, rule) in workingRules.enumerated() {
                let height = CGFloat(34 + 29 * rule.conditions.count + 32)
                let row = LayoutView(frame: NSRect(x: 0, y: y, width: 468, height: height))
                listContent.addSubview(row); rowViews[rule.id] = row
                let menu = NSMenu()
                menu.delegate = self
                func menuItem(_ title: String, action: Selector, enabled: Bool = true) {
                    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    item.target = self; item.representedObject = rule.id.uuidString; item.isEnabled = enabled
                    menu.addItem(item)
                }
                menu.autoenablesItems = false
                menuItem("Add Condition", action: #selector(addConditionFromMenu(_:)))
                menuItem("Move Route Up", action: #selector(moveRouteUpFromMenu(_:)), enabled: index > 0)
                menuItem("Move Route Down", action: #selector(moveRouteDownFromMenu(_:)), enabled: index + 1 < workingRules.count)
                menuItem("Delete Route", action: #selector(deleteRouteFromMenu(_:)))
                row.menu = menu
                var cy: CGFloat = 0
                for (conditionIndex, condition) in rule.conditions.enumerated() {
                    if conditionIndex == 0 {
                        let icon = NSImageView(frame: NSRect(x: 36, y: cy + 5, width: 16, height: 16))
                        icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
                        icon.contentTintColor = .secondaryLabelColor; row.addSubview(icon)
                    }
                    label(conditionIndex == 0 ? "URL" : "and", frame: NSRect(x: 56, y: cy + 4, width: 36, height: 21), in: row, secondary: true)
                    let popup = NSPopUpButton(frame: NSRect(x: 92, y: cy, width: 110, height: 26))
                    popup.addItems(withTitles: ["Is equal to", "Contains"]); popup.selectItem(at: condition.style == .matches ? 0 : 1)
                    popup.menu?.delegate = self
                    popup.setAccessibilityLabel("Matching style for route \(index + 1), condition \(conditionIndex + 1)")
                    row.addSubview(popup); keyViews.append(popup)
                    rowControls[RowControlID(ruleID: rule.id, conditionID: condition.id, role: .style)] = popup
                    let field = NSTextField(frame: NSRect(x: 210, y: cy + 1, width: 212, height: 24))
                    field.stringValue = condition.pattern; field.placeholderString = "example.com"; field.delegate = self
                    field.setAccessibilityLabel("URL pattern for route \(index + 1), condition \(conditionIndex + 1)")
                    row.addSubview(field); keyViews.append(field)
                    rowControls[RowControlID(ruleID: rule.id, conditionID: condition.id, role: .field)] = field
                    conditionFields.append(ConditionField(ruleID: rule.id, conditionID: condition.id, field: field, style: popup))
                    let remove = button("", symbol: "minus.circle.fill", frame: NSRect(x: 429, y: cy, width: 20, height: 26), in: row) { [weak self] in self?.removeCondition(rule.id, condition.id) }
                    remove.isBordered = false; remove.setAccessibilityLabel("Remove condition \(conditionIndex + 1) from route \(index + 1)")
                    rowControls[RowControlID(ruleID: rule.id, conditionID: condition.id, role: .remove)] = remove
                    cy += 29
                }
                let arrow = NSImageView(frame: NSRect(x: 110, y: cy + 5, width: 16, height: 16))
                arrow.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)
                arrow.contentTintColor = .secondaryLabelColor; row.addSubview(arrow)
                label("Open in", frame: NSRect(x: 129, y: cy + 4, width: 58, height: 21), in: row, secondary: true)
                let popup = NSPopUpButton(frame: NSRect(x: 187, y: cy, width: 165, height: 26))
                popup.menu?.autoenablesItems = false; popup.setAccessibilityLabel("Destination for route \(index + 1)")
                popup.menu?.delegate = self
                var choices: [LinkRouteDestination] = []
                func addChoice(_ title: String, _ destination: LinkRouteDestination) {
                    popup.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")); choices.append(destination)
                }
                addChoice("Most Recent Space", .mostRecent)
                for profile in browserStore.state.profiles {
                    let spaces = browserStore.state.spaces.filter { $0.profileID == profile.id }
                    guard !spaces.isEmpty else { continue }
                    addChoice(profile.name + " · Most Recent Space", .profile(profile.id))
                    for space in spaces { addChoice(profile.name + " · " + space.name, .space(space.id)) }
                }
                //
                // Spaces, so a rule whose Space was removed keeps it and shows
                // no title; nothing rewrites the rule.
                if !choices.contains(rule.destination) {
                    addChoice("", rule.destination); popup.lastItem?.isEnabled = false
                    popup.setAccessibilityValueDescription(destinationTitle(rule.destination))
                }
                popup.selectItem(at: choices.firstIndex(of: rule.destination) ?? 0)
                row.addSubview(popup); keyViews.append(popup)
                rowControls[RowControlID(ruleID: rule.id, conditionID: nil, role: .destination)] = popup
                let menuY = cy + 26
                let options = button("", symbol: "ellipsis", frame: NSRect(x: 429, y: cy, width: 20, height: 26), in: row) { [weak row] in
                    guard let row else { return }
                    menu.popUp(positioning: nil, at: NSPoint(x: 429, y: menuY), in: row)
                }
                options.isBordered = false; options.setAccessibilityLabel("More actions for route \(index + 1)")
                rowControls[RowControlID(ruleID: rule.id, conditionID: nil, role: .options)] = options
                destinationFields.append(DestinationField(ruleID: rule.id, popup: popup, choices: choices))
                y += height
            }
            listContent.setFrameSize(NSSize(width: 468, height: max(320, y)))
        }
        keyViews.append(resetButton)
        updateKeyViews()
        if let controlID {
            if !LinkRoutingInteraction.focus(rowControls[controlID], in: window) {
                let fallback = rowControls[RowControlID(ruleID: controlID.ruleID, conditionID: nil, role: .options)] ?? newRoute
                LinkRoutingInteraction.focus(fallback, in: window)
            }
        } else {
            LinkRoutingInteraction.restoreFocus(focus, in: window, fields: conditionFields.map { (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field) })
        }
    }
    private func startRoute() {
        captureEditor(); let rule = LinkRoute(); workingRules.append(rule); render()
        LinkRoutingInteraction.focus(conditionFields.first(where: { $0.ruleID == rule.id })?.field, in: window)
        if let row = rowViews[rule.id] { LinkRoutingInteraction.revealAddedRule(row, in: scroll) }
    }
    private func addCondition(_ ruleID: UUID) {
        guard !finished else { return }
        captureEditor(); guard let index = workingRules.firstIndex(where: { $0.id == ruleID }) else { return }
        let condition = LinkRouteCondition(); workingRules[index].conditions.append(condition); render()
        LinkRoutingInteraction.focus(conditionFields.first(where: { $0.ruleID == ruleID && $0.conditionID == condition.id })?.field, in: window)
    }
    private func removeCondition(_ ruleID: UUID, _ conditionID: UUID) {
        let responder = window?.firstResponder as? NSView
        let removedControlFocused = rowControls.contains {
            $0.key.ruleID == ruleID && $0.key.conditionID == conditionID && $0.value === responder
        }
        let focusedText = LinkRoutingInteraction.captureFocus(in: window, fields: conditionFields.map {
            (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field)
        })
        captureEditor(); guard let index = workingRules.firstIndex(where: { $0.id == ruleID }) else { return }
        workingRules[index].conditions.removeAll { $0.id == conditionID }
        if workingRules[index].conditions.isEmpty { workingRules.remove(at: index) }
        render()
        if removedControlFocused || focusedText?.id == LinkRoutingInteraction.FieldID(ruleID: ruleID, conditionID: conditionID) {
            let next: NSView = conditionFields.first(where: { $0.ruleID == ruleID })?.field
                ?? conditionFields.first?.field ?? newRoute as NSView
            LinkRoutingInteraction.focus(next, in: window)
        }
    }
    private func moveRule(_ id: UUID, by offset: Int) {
        guard !finished else { return }
        captureEditor(); guard let from = workingRules.firstIndex(where: { $0.id == id }),
              workingRules.indices.contains(from + offset) else { return }
        workingRules.swapAt(from, from + offset); render()
    }
    private func menuRuleID(_ sender: NSMenuItem) -> UUID? {
        (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    }
    @objc private func addConditionFromMenu(_ sender: NSMenuItem) {
        guard let id = menuRuleID(sender) else { return }
        DispatchQueue.main.async { [weak self] in self?.addCondition(id) }
    }
    @objc private func moveRouteUpFromMenu(_ sender: NSMenuItem) {
        guard let id = menuRuleID(sender) else { return }
        DispatchQueue.main.async { [weak self] in self?.moveRule(id, by: -1) }
    }
    @objc private func moveRouteDownFromMenu(_ sender: NSMenuItem) {
        guard let id = menuRuleID(sender) else { return }
        DispatchQueue.main.async { [weak self] in self?.moveRule(id, by: 1) }
    }
    @objc private func deleteRouteFromMenu(_ sender: NSMenuItem) {
        guard let id = menuRuleID(sender) else { return }
        DispatchQueue.main.async { [weak self] in self?.deleteRoute(id) }
    }
    private func deleteRoute(_ id: UUID) {
        guard !finished else { return }
        let responder = window?.firstResponder as? NSView
        let removedControlFocused = rowControls.contains { $0.key.ruleID == id && $0.value === responder }
        let focusedText = LinkRoutingInteraction.captureFocus(in: window, fields: conditionFields.map {
            (LinkRoutingInteraction.FieldID(ruleID: $0.ruleID, conditionID: $0.conditionID), $0.field)
        })
        captureEditor(); workingRules.removeAll { $0.id == id }; render()
        if removedControlFocused || focusedText?.id.ruleID == id {
            let next: NSView = conditionFields.first?.field ?? newRoute as NSView
            LinkRoutingInteraction.focus(next, in: window)
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        LinkRoutingTextEditing.handle(commandSelector, in: textView) { _ = window?.makeFirstResponder(nil) }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard pendingDestinationRefresh else { return }
        scheduleDestinationRefresh()
    }
    func menuWillOpen(_ menu: NSMenu) { openMenus.insert(ObjectIdentifier(menu)) }
    func menuDidClose(_ menu: NSMenu) {
        openMenus.remove(ObjectIdentifier(menu))
        guard pendingDestinationRefresh else { return }
        scheduleDestinationRefresh()
    }
    func windowDidBecomeKey(_ notification: Notification) {
        scheduleDestinationRefresh(); scheduleErrorControlUpdate()
    }
    func windowDidEndSheet(_ notification: Notification) {
        scheduleDestinationRefresh(); scheduleErrorControlUpdate()
    }
    func windowDidUpdate(_ notification: Notification) {
        if pendingDestinationRefresh && canRefreshDestinations { scheduleDestinationRefresh() }
    }
    private var canRefreshDestinations: Bool {
        guard !finished, let window, window.isVisible, window.isKeyWindow,
              window.attachedSheet == nil, openMenus.isEmpty,
              !conditionFields.contains(where: { $0.field.currentEditor() != nil }) else { return false }
        let responder = window.firstResponder as? NSView
        let unknownRowResponder = responder.map {
            ($0 === listContent || $0.isDescendant(of: listContent)) && !rowControls.values.contains(where: { $0 === responder })
        } ?? false
        return !unknownRowResponder
    }
    private func scheduleDestinationRefresh() {
        guard pendingDestinationRefresh, !destinationRefreshScheduled, !finished else { return }
        destinationRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.destinationRefreshScheduled = false
            self.refreshDestinationsIfSafe()
        }
    }
    private func refreshDestinationsIfSafe() {
        guard !finished else { return }
        guard canRefreshDestinations else {
            pendingDestinationRefresh = true; return
        }
        pendingDestinationRefresh = false
        captureEditor(); render()
    }
    private func confirmReset() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "Reset all routes?"
        alert.informativeText = "Your Air Traffic Control routes will be removed. Tabs, Spaces and profiles stay unchanged."
        alert.addButton(withTitle: "Reset Routes"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            guard response == .alertFirstButtonReturn, let self, self.routing.reset(basedOn: self.originalRules) else { return }
            self.originalRules = self.routing.state.rules; self.workingRules = self.originalRules
            self.discardButton.isHidden = true; self.render()
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, !self.finished, let window, self.window === window,
                      window.isVisible, window.isKeyWindow, window.attachedSheet == nil else { return }
                LinkRoutingInteraction.focus(self.newRoute, in: window)
            }
        }
    }
}
