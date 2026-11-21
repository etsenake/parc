import AppKit
import Combine
import ParcCore
import ParcEngine

@MainActor
final class RecentTabSwitcher {
    struct Component {
        let id: UUID
        let title: String
        let page: PCNativePage?
        let localPreview: NSImage?
        var template: RecentTabSwitcherView.Template? = nil
        var favicon: NSImage? = nil
        var faviconRequest: ((@escaping (NSImage?) -> Void) -> Void)? = nil
        var isRecordingMedia = false
    }
    struct Item {
        let selection: RecentTabOrder.Item
        let components: [Component]
        let spaceName: String
        var customInfo: RecentTabSwitcherView.CustomInfo? = nil
        var overlay: Component? = nil
        var id: String { selection.id }
        var allComponents: [Component] { components + (overlay.map { [$0] } ?? []) }
    }
    enum CloseResult { case closed([Item], theme: SpaceTheme), refused }
    var onComplete: ((RecentTabOrder.Item?) -> Void)?
    var onCloseItem: ((RecentTabOrder.Item, @escaping (CloseResult?) -> Void) -> Void)?
    var isCurrent: (([Item]) -> Bool)?
    private weak var parent: NSWindow?
    private let panel = RecentTabPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let surface = RecentTabSwitcherView()
    private var items: [Item]
    private var selection: RecentTabSwitcherSelection
    private var focused: Int { selection.focusedIndex }
    private var displayedItems: [Item] { Array(items.prefix(RecentTabSwitcherSelection.maximumDisplayedItems)) }
    private let next: KeyboardShortcut?
    private let previous: KeyboardShortcut?
    private let input: RecentTabSwitcherInput
    private let revision: Int
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var registryObserver: AnyCancellable?
    private var presentation: DispatchWorkItem?
    private var previews: [UUID: PCNativeTabPreview] = [:]
    private var requestedFavicons = Set<UUID>()
    private var ended = false
    private var presented = false
    private var closing = false

    init(items: [Item], currentTabIDs: [UUID], parent: NSWindow, theme: SpaceTheme, forward: Bool,
         event: NSEvent?, next: KeyboardShortcut?, previous: KeyboardShortcut?) {
        let currentID = items.first(where: { $0.selection.tabIDs == currentTabIDs })?.id
        let selection = RecentTabSwitcherSelection(itemIDs: items.map(\.id), currentID: currentID, forward: forward)
        self.selection = selection
        self.items = selection.itemIDs.compactMap { id in items.first { $0.id == id } }
        self.parent = parent; self.next = next; self.previous = previous
        revision = KeyboardShortcuts.shared.revision
        input = RecentTabSwitcherInput(next: next?.flags.rawValue, previous: previous?.flags.rawValue)
        panel.isReleasedWhenClosed = false; panel.isRestorable = false
        panel.hasShadow = false; panel.animationBehavior = .none
        panel.backgroundColor = .clear; panel.isOpaque = false
        panel.level = .floating; panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = surface; panel.appearance = parent.effectiveAppearance
        configureSurface(theme: theme, appearance: parent.effectiveAppearance)
        surface.onHover = { [weak self] index in self?.focus(index) }
        surface.onChoose = { [weak self] index in self?.focus(index); self?.finish(select: true) }
        surface.canInteract = { [weak self] in self?.valid() == true }
        surface.onVisibleItemsChanged = { [weak self] in self?.refreshPreviews() }
    }

    func start(event: NSEvent?) {
        guard valid(), !items.isEmpty else { finish(select: false); return }
        if displayedItems.count == 1 || !holding {
            finish(select: true); return
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.willBeginSheetNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(select: false) }
            })
        }
        observers.append(center.addObserver(forName: PCNativeBrowserApplication.tabSwitcherAvailabilityDidChangeNotification,
                                            object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfInvalid() }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(select: false) }
        })
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        registryObserver = KeyboardShortcuts.shared.$revision.dropFirst().sink { [weak self] revision in
            guard let self, revision != self.revision else { return }; self.finish(select: false)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated { if let self { result = self.handle(event) } }
            return result
        }
        let elapsed = event.map { max(0, ProcessInfo.processInfo.systemUptime - $0.timestamp) } ?? 0
        let work = DispatchWorkItem { [weak self] in self?.show() }
        presentation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.1 - elapsed), execute: work)
    }

    private func valid() -> Bool {
        !ended && !closing && parent.map { PCNativeBrowserApplication.canPresentTabSwitcher(in: $0) } == true
            && isCurrent?(items) == true && KeyboardShortcuts.shared.revision == revision
    }
    func dismissIfInvalid() { if !closing && !valid() { finish(select: false) } }
    func cancel() { finish(select: false) }
    func cycle(forward: Bool) { focus(focused + (forward ? 1 : -1)) }
    private var holding: Bool { input.isHolding(NSEvent.modifierFlags.rawValue) }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let shortcut = event.type == .keyDown ? KeyboardShortcuts.shared.chord(for: event) : nil
        let action = event.type == .keyDown ? input.keyDown(
            matchesNext: next != nil && shortcut == next, matchesPrevious: previous != nil && shortcut == previous,
            keyCode: event.keyCode, flags: event.modifierFlags.rawValue) : nil
        if closing {
            if event.type == .flagsChanged {
                if !input.continues(event.modifierFlags.rawValue) { finish(select: false) }
                return event
            }
            switch action {
            case .cancel: finish(select: false); return nil
            case .forward, .backward, .close: return nil
            default: finish(select: false); return event
            }
        }
        guard valid() else { finish(select: false); return event }
        guard event.window == nil || event.window === parent || event.window === panel else {
            finish(select: false); return event
        }
        if event.type == .flagsChanged {
            if !input.continues(event.modifierFlags.rawValue) { finish(select: true) }
            return nil
        }
        switch action {
        case .forward: cycle(forward: true)
        case .backward: cycle(forward: false)
        case .cancel: finish(select: false)
        case .close: closeItem(focused)
        case .consume, nil: break
        }
        return nil
    }

    private func show() {
        presentation = nil
        guard valid(), let parent else { finish(select: false); return }
        if !holding { finish(select: true); return }
        let shown = displayedItems.count
        surface.setItems(items.enumerated().map { Self.presentation($1, hidden: $0 >= shown) }, focused: focused)
        layout(); parent.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil); presented = true
        refreshPreviews(); requestFavicons()
        announce()
    }
    private func layout() {
        guard let parent else { return }
        let screen = parent.screen?.visibleFrame ?? parent.frame
        let frame = RecentTabSwitcherView.panelFrame(itemCount: displayedItems.count,
                                                     parent: parent.frame, screen: screen)
        panel.setFrame(frame, display: true)
        surface.focus(focused)
    }
    private func configureSurface(theme: SpaceTheme, appearance: NSAppearance) {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let palette = ThemeChromePalette(theme: theme, isDark: dark)
        surface.configure(isDark: dark, focus: palette.focus, hover: palette.hover,
                          maxContrast: palette.maxContrastColor, cutout: palette.cutoutColor)
    }
    private static func presentation(_ item: Item, hidden: Bool) -> RecentTabSwitcherView.Item {
        func component(_ value: Component) -> RecentTabSwitcherView.Component {
            .init(id: value.id, title: value.title, image: value.localPreview, template: value.template,
                  favicon: value.favicon, isRecordingMedia: value.isRecordingMedia)
        }
        return .init(id: item.id, title: item.customInfo?.title ?? item.components.map(\.title).joined(separator: " · "),
                     spaceName: item.spaceName, vertical: item.selection.orientation == .vertical,
                     components: item.components.map(component), customInfo: item.customInfo,
                     overlay: item.overlay.map(component), isHidden: hidden, slotSizes: item.selection.slotSizes)
    }
    private func requestFavicons() {
        for component in items.flatMap(\.components) where !requestedFavicons.contains(component.id) {
            guard let request = component.faviconRequest else { continue }
            requestedFavicons.insert(component.id)
            let id = component.id
            request { [weak self] image in
                guard let self else { return }
                guard self.valid() else { self.requestedFavicons.remove(id); return }
                guard let image, self.items.contains(where: { $0.components.contains { $0.id == id } }) else { return }
                self.surface.updateFavicon(image, component: id)
            }
        }
    }
    private func focus(_ index: Int) {
        guard !closing else { return }
        guard valid(), !items.isEmpty else { finish(select: false); return }
        selection.focus(index)
        if presented { surface.focus(focused); refreshPreviews(); announce() }
    }
    private func refreshPreviews() {
        guard presented, let parent else { return }
        let visible = surface.visibleItemIndexes.union([focused])
        let components = visible.flatMap { displayedItems.indices.contains($0) ? items[$0].allComponents : [] }
        let ids = Set(components.map(\.id))
        let wanted = Set(components.compactMap { component -> UUID? in
            guard let page = component.page, !page.isClosed else { return nil }
            return component.id
        })
        if wanted == Set(previews.keys) { return }
        for id in Array(previews.keys) where !ids.contains(id) { previews.removeValue(forKey: id)?.invalidate() }
        for component in components where previews[component.id] == nil {
            guard let page = component.page, !page.isClosed else { continue }
            let componentID = component.id
            let lease = page.observePreview(in: parent) { [weak self, weak page] image in
                guard let self, self.valid(), let page,
                      self.items.contains(where: { $0.allComponents.contains(where: { $0.id == componentID && $0.page === page }) }) else { return }
                self.surface.updatePreview(image, component: componentID)
            }
            if let lease { previews[component.id] = lease }
        }
    }
    private func closeItem(_ index: Int) {
        guard valid(), displayedItems.indices.contains(index), let action = onCloseItem else { return }
        let item = items[index]
        selection.focus(index)
        closing = true
        presentation?.cancel(); presentation = nil
        previews.values.forEach { $0.invalidate() }; previews.removeAll()
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil); presented = false
        action(item.selection) { [weak self] result in
            guard let self, !self.ended else { return }
            self.closing = false
            guard let result else { self.finish(select: false); return }
            if case .closed(let available, let theme) = result {
                self.selection.didClose(item.id, availableIDs: available.map(\.id))
                self.items = self.selection.itemIDs.compactMap { id in available.first { $0.id == id } }
                if let parent = self.parent {
                    self.configureSurface(theme: theme, appearance: parent.effectiveAppearance)
                }
            }
            guard !self.items.isEmpty, self.valid(), self.holding else {
                self.finish(select: false); return
            }
            self.show()
        }
    }
    private func announce() {
        guard items.indices.contains(focused) else { return }
        let title = items[focused].customInfo?.title ?? items[focused].components.map(\.title).joined(separator: ", ")
        NSAccessibility.post(element: surface, notification: .announcementRequested,
            userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    private func finish(select: Bool) {
        guard !ended else { return }
        let selection = select && valid() && items.indices.contains(focused) ? items[focused].selection : nil
        ended = true; surface.retire(); presentation?.cancel(); presentation = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers.removeAll()
        registryObserver = nil
        previews.values.forEach { $0.invalidate() }; previews.removeAll()
        panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
        let completion = onComplete; onComplete = nil; isCurrent = nil; onCloseItem = nil
        completion?(selection)
    }
}

private final class RecentTabPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
