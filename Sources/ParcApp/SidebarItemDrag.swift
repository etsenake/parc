import AppKit

@MainActor
protocol SidebarItemDragSource: AnyObject {
    var sidebarDrag: SidebarMoveSession? { get }
}

/// An item row whose move, Duplicate and Delete actions are made when an
/// accessibility client asks for them: each move checks the window's lease
/// for every destination, too costly to repeat for every row on each render.
@MainActor
protocol SidebarDeferredAccessibilityActions: NSView {
    /// The actions set on the row, without the deferred ones.
    var storedAccessibilityActions: [NSAccessibilityCustomAction] { get }
    var deferredAccessibilityActions: (index: Int, make: () -> [NSAccessibilityCustomAction])? { get set }
}

extension SidebarDeferredAccessibilityActions {
    /// The deferred actions follow the actions set so far and precede any set later.
    func deferAccessibilityActions(_ make: @escaping () -> [NSAccessibilityCustomAction]) {
        deferredAccessibilityActions = (storedAccessibilityActions.count, make)
    }
    var mergedAccessibilityActions: [NSAccessibilityCustomAction] {
        var actions = storedAccessibilityActions
        guard let deferred = deferredAccessibilityActions else { return actions }
        actions.insert(contentsOf: deferred.make(), at: min(deferred.index, actions.count))
        return actions
    }
}

/// A process-local source capability. The pasteboard only identifies this exact
/// one-shot session. Another window must obtain a separate original-owner grant;
/// external text and stale rows never authorize a move.
@MainActor
final class SidebarMoveSession {
    static let pasteboardType = NSPasteboard.PasteboardType("org.parc.sidebar-item-move")
    let identifier = UUID()
    let items: [SidebarItemReference]
    var item: SidebarItemReference { items[0] }
    weak var window: NSWindow?
    weak var owner: BrowserWindowController?
    private let validate: () -> Bool
    private let validateTransfer: () -> Bool
    private let propose: (SidebarContainerLocation, SidebarItemReference?) -> Bool
    private let commit: (SidebarContainerLocation, SidebarItemReference?) -> Bool
    private(set) var ended = false
    ///
    ///
    ///
    /// against this session's owner and validity.
    let allowsCopy: Bool
    init(items: [SidebarItemReference], window: NSWindow, validate: @escaping () -> Bool,
         validateTransfer: (() -> Bool)? = nil, allowsCopy: Bool = false,
         propose: @escaping (SidebarContainerLocation, SidebarItemReference?) -> Bool,
         commit: @escaping (SidebarContainerLocation, SidebarItemReference?) -> Bool) {
        precondition(!items.isEmpty)
        self.items = items; self.window = window; self.validate = validate; self.validateTransfer = validateTransfer ?? validate; self.propose = propose; self.commit = commit
        self.allowsCopy = allowsCopy
    }
    var isValid: Bool { !ended && validate() }
    var isValidForWindowTransfer: Bool { !ended && validateTransfer() }
    func canMove(to location: SidebarContainerLocation, before: SidebarItemReference?) -> Bool {
        isValid && propose(location, before)
    }
    func move(to location: SidebarContainerLocation, before: SidebarItemReference?) -> Bool {
        guard canMove(to: location, before: before) else { return false }
        ended = true
        return commit(location, before)
    }
    func moveToAnotherWindow(_ commit: () -> Bool) -> Bool {
        guard isValidForWindowTransfer else { return false }
        ended = true
        return commit()
    }
    /// A destination that finishes preparing its transfer against this
    /// still-live session (a dock Space it first shows), then ends the drag.
    func transferThenEnd(_ commit: () -> Bool) -> Bool {
        guard isValidForWindowTransfer else { return false }
        defer { ended = true }
        return commit()
    }
    /// A prepared copy runs once and ends the drag; the originals never move.
    func copy(_ commit: () -> Bool) -> Bool {
        guard allowsCopy, isValidForWindowTransfer else { return false }
        ended = true
        return commit()
    }
    func end() { ended = true }
}

@MainActor
class SidebarMoveHandle: NSView, NSDraggingSource, SidebarItemDragSource {
    var beginMove: (() -> SidebarMoveSession?)?
    private(set) var sidebarDrag: SidebarMoveSession?
    var activate: (() -> Void)?
    var selectionClick: ((NSEvent) -> Bool)?
    var selectionContext: (() -> NSMenu?)?
    /// Takes a plain double-click's second press before selection and
    /// activation; true when it handled it.
    var doubleClick: ((NSEvent) -> Bool)?
    /// The view a drag's preview captures, when it is not the handle itself.
    weak var dragPreview: NSView?
    /// Renders the preview's drag image in place of a live capture.
    var makeDragImage: (() -> NSImage?)?
    private var down: NSPoint?
    private var selectionEvent: NSEvent?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { down = convert(event.locationInWindow, from: nil); selectionEvent = event }
    override func mouseUp(with event: NSEvent) {
        let pressed = down != nil, originalEvent = selectionEvent ?? event
        down = nil; selectionEvent = nil
        guard pressed && bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if originalEvent.clickCount == 2, originalEvent.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control]),
           doubleClick?(originalEvent) == true { return }
        if selectionClick?(originalEvent) != true { activate?() }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - down.x, point.y - down.y) > 4 else { return }
        self.down = nil; selectionEvent = nil
        guard let session = beginMove?(), session.isValid else { return }
        sidebarDrag = session
        let item = NSPasteboardItem(); item.setString(session.identifier.uuidString, forType: SidebarMoveSession.pasteboardType)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        let previewView = dragPreview ?? self
        let image: NSImage
        if let rendered = makeDragImage?() { image = rendered } else {
            image = NSImage(size: previewView.bounds.size)
            if let bitmap = previewView.bitmapImageRepForCachingDisplay(in: previewView.bounds) {
                previewView.cacheDisplay(in: previewView.bounds, to: bitmap); image.addRepresentation(bitmap)
            }
        }
        if session.items.count > 1 {
            image.lockFocus()
            NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: image.size)).fill()
            ("\(session.items.count) Items" as NSString).draw(at: NSPoint(x: 12, y: 9), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
            image.unlockFocus()
        }
        dragging.setDraggingFrame(convert(previewView.bounds, from: previewView), contents: image)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        sidebarDrag?.end(); sidebarDrag = nil
    }
    override func accessibilityPerformPress() -> Bool { activate?(); return activate != nil }
    override func menu(for event: NSEvent) -> NSMenu? { selectionContext?() ?? super.menu(for: event) }
}

///
/// `FolderIcon.FolderIconView` in the tab cell's 24-point image slot, the title
/// at the tab title inset in `FontSet.listHeader` (system 14 semibold,
///
/// `CellSelectionStateView` fills as a tab row for hover, multi-selection and
///
/// with the "Folder Title" placeholder. The row outlives renders, so a
/// disclosure change animates its icon open or closed.
@MainActor
final class SidebarFolderRow: SidebarMoveHandle, SidebarDeferredAccessibilityActions {
    static let titlePlaceholder = "Folder Title"
    /// The folder's context menu, built when it opens.
    var makeMenu: (() -> NSMenu?)?
    override var menu: NSMenu? {
        get { makeMenu?() ?? super.menu }
        set { super.menu = newValue }
    }
    var deferredAccessibilityActions: (index: Int, make: () -> [NSAccessibilityCustomAction])?
    var storedAccessibilityActions: [NSAccessibilityCustomAction] { super.accessibilityCustomActions() ?? [] }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        window != nil && !isHiddenOrHasHiddenAncestor ? mergedAccessibilityActions : []
    }
    static let untitled = SidebarFolderFromItems.defaultName
    static let iconSize: CGFloat = 17
    let folderID: UUID
    private let background = SidebarRowBackgroundView()
    private let icon = SidebarFolderIconView()
    private let label = SidebarChromeLabel(labelWithString: "")
    private let titleField = SidebarTitleField()
    /// The trailing button of a peeked folder (`FolderTrailingButtonType
    /// .closePeek`), a SidebarCellButton with a system image and the "Close
    ///
    private let closePeekButton = SidebarRowActionButton("Close This Folder")
    private(set) var expanded: Bool
    private var hover = false
    /// `isLeadingRegionHovered`: the pointer is over the icon slot.
    private var leadingHover = false
    private var tracking: NSTrackingArea?
    /// The window the row last refreshed its fill in.
    private weak var trackedWindow: NSWindow?
    private var keyObservers: [NSObjectProtocol] = []
    var palette: ThemeChromePalette? { didSet { updateColor() } }
    var multiSelected = false { didSet { if multiSelected != oldValue { updateColor() } } }
    var keyboardHighlighted = false { didSet { if keyboardHighlighted != oldValue { updateColor() } } }
    var listFocusRing = false { didSet { if listFocusRing != oldValue { updateColor() } } }
    ///
    /// icon until it leaves or the folder springs open.
    var dropTarget = false { didSet { if dropTarget != oldValue { updateIconState(animated: true) } } }
    ///
    /// `SidebarItemExpansionState.peeked`, `ListHeaderCellState.isPeeked`).
    var peeked = false { didSet { if peeked != oldValue { updateIconState(animated: true); updateClosePeek() } } }
    /// Hides the folder's peeked items.
    var closePeek: (() -> Void)?
    var iconFrame: NSRect { icon.frame }

    init(folder: BrowserFolder) {
        folderID = folder.id; expanded = folder.isExpanded
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: SidebarRowAppearance.titleFontSize, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
        label.setAccessibilityElement(false)
        titleField.setAccessibilityLabel("Folder name")
        closePeekButton.symbol = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closePeekButton.prepareAction = { [weak self] in
            guard let self, self.closePeek != nil else { return nil }
            return { [weak self] in self?.closePeek?(); return true }
        }
        closePeekButton.isHidden = true
        addSubview(background); addSubview(icon); addSubview(label); addSubview(titleField); addSubview(closePeekButton)
        setAccessibilityElement(true); setAccessibilityRole(.disclosureTriangle)
        setAccessibilityChildren([])
        update(folder, animated: false)
        updateColor()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Takes the folder's current name and disclosure; an animated change
    /// opens or closes the icon on Core Animation's implicit actions.
    func update(_ folder: BrowserFolder, animated: Bool) {
        if label.stringValue != folder.name { label.stringValue = folder.name }
        icon.customIcon = folder.customIcon
        setAccessibilityLabel(folder.name); setAccessibilityValue(folder.isExpanded ? 1 : 0)
        guard expanded != folder.isExpanded else { updateIconState(animated: false); return }
        expanded = folder.isExpanded
        if expanded { dropTarget = false }
        updateIconState(animated: animated)
        updateClosePeek()
    }

    ///
    /// folder shows its ellipsis, half open while its icon is hovered.
    private func updateIconState(animated: Bool) {
        let state: SidebarFolderIconView.State
        if expanded || dropTarget { state = .expanded }
        else if !peeked { state = .collapsed }
        else { state = leadingHover ? .peekedOpen : .peekedClosed }
        icon.setState(state, animated: animated)
    }

    private func updateClosePeek() {
        let visible = peeked && !expanded && hover && window?.isKeyWindow == true && !titleField.editingTitle
        guard closePeekButton.isHidden == visible else { return }
        closePeekButton.isHidden = !visible
        closePeekButton.refreshAvailability()
        needsLayout = true
    }

    @discardableResult func beginTitleEditing(_ title: String, finished: @escaping (String?) -> Void) -> Bool {
        titleField.font = label.font; titleField.textColor = label.textColor
        titleField.onFinish = { [weak self] value in
            self?.label.isHidden = false; self?.needsLayout = true
            self?.updateColor()
            finished(value)
        }
        layoutSubtreeIfNeeded()
        guard titleField.begin(title: title, placeholder: Self.titlePlaceholder) else { titleField.onFinish = nil; return false }
        label.isHidden = true; needsLayout = true
        updateColor()
        return true
    }
    func cancelTitleEditing() { titleField.cancel() }

    private func updateColor() {
        let dark = palette?.isDark ?? (effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let title = palette?.title ?? .parcInk
        label.textColor = title
        if titleField.editingTitle { titleField.textColor = title }
        //
        // maxContrastColor, foregroundSecondary and cutoutColor.
        icon.strokeColor = palette?.maxContrastColor ?? .labelColor
        icon.backFillColor = palette?.foregroundSecondary ?? .secondaryLabelColor
        icon.frontFillColor = palette?.cutoutColor ?? .windowBackgroundColor
        background.dark = dark
        background.ringColor = palette?.maxContrastColor ?? .labelColor
        closePeekButton.dark = dark
        updateClosePeek()
        background.appearanceState = SidebarRowAppearance(
            multiSelected: multiSelected, hovered: hover && window?.isKeyWindow == true && !titleField.editingTitle,
            highlighted: keyboardHighlighted || listFocusRing)
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        //
        // 24-point image slot.
        let slot = SidebarRowAppearance.iconSlotFrame(in: bounds)
        icon.frame = NSRect(x: slot.midX - Self.iconSize / 2, y: slot.midY - Self.iconSize / 2,
                            width: Self.iconSize, height: Self.iconSize)
        closePeekButton.frame = SidebarRowAppearance.closeFrame(in: bounds)
        let (titleX, width) = SidebarRowAppearance.titleLabelSpan(
            resettable: false, trailing: SidebarRowAppearance.titleTrailingEdge(in: bounds, closeVisible: !closePeekButton.isHidden))
        let title = NSRect(x: titleX, y: ((bounds.height - 18) / 2).rounded(.down), width: width, height: 18)
        label.frame = title; titleField.frame = title
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        // A row can be rebuilt or moved under a stationary pointer.
        let point = window.flatMap { $0.isKeyWindow ? convert($0.mouseLocationOutsideOfEventStream, from: nil) : nil }
        let wasHover = hover
        hover = point.map { bounds.contains($0) } ?? false
        updateLeadingHover(point)
        // AppKit asks every row again as the list scrolls or resizes.
        guard window !== trackedWindow || hover != wasHover else { return }
        trackedWindow = window
        updateColor()
    }
    override func mouseEntered(with event: NSEvent) {
        updateLeadingHover(convert(event.locationInWindow, from: nil))
        guard !hover else { return }; hover = true; updateColor()
    }
    override func mouseMoved(with event: NSEvent) { updateLeadingHover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) {
        updateLeadingHover(nil)
        guard hover else { return }; hover = false; updateColor()
    }
    /// A kept page's outline hides, or leaves the screen, with its rows under the pointer.
    override func viewDidHide() { super.viewDidHide(); resetPointer() }
    func resetPointer() {
        updateLeadingHover(nil)
        guard hover else { return }; hover = false; updateColor()
    }
    private func updateLeadingHover(_ point: NSPoint?) {
        let slot = SidebarRowAppearance.iconSlotFrame(in: bounds)
        let next = point.map { bounds.contains($0) && $0.x < slot.maxX } ?? false
        guard next != leadingHover else { return }
        leadingHover = next
        updateIconState(animated: true)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        trackedWindow = nil
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
        guard let newWindow else { return }
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateColor() }
            }
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    // The field editor takes its own presses while the title is edited; the
    // row's press neither toggles nor drags meanwhile.
    override func mouseDown(with event: NSEvent) {
        // A Control-click opens the row's menu, as the tab row's does.
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        guard !titleField.editingTitle else { return }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) { guard !titleField.editingTitle else { return }; super.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { guard !titleField.editingTitle else { return }; super.mouseUp(with: event) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        if titleField.editingTitle, let hit = super.hitTest(point), hit !== self, hit !== label, hit !== icon, hit !== background { return hit }
        if !closePeekButton.isHidden, closePeekButton.frame.contains(convert(point, from: superview)) { return closePeekButton }
        return self
    }
    override func accessibilityTitle() -> String? { label.stringValue }
}

@MainActor
final class SidebarDropFeedbackView: NSView {
    var tint = NSColor.controlAccentColor { didSet { needsDisplay = true } }
    var targetRect: NSRect? { didSet { needsDisplay = true } }
    var isInsertion = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    ///
    /// at an open circle on its leading end.
    static let insertionCircle: CGFloat = 6
    override func draw(_ dirtyRect: NSRect) {
        guard let rect = targetRect else { return }
        tint.withAlphaComponent(isInsertion ? 0.9 : 0.5).setFill()
        guard isInsertion, rect.width > rect.height else {
            NSBezierPath(roundedRect: rect, xRadius: isInsertion ? 1 : 6, yRadius: isInsertion ? 1 : 6).fill()
            return
        }
        let diameter = Self.insertionCircle
        let circle = NSRect(x: rect.minX, y: rect.midY - diameter / 2, width: diameter, height: diameter).insetBy(dx: 1, dy: 1)
        tint.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: circle); ring.lineWidth = 2; ring.stroke()
        let line = NSRect(x: circle.maxX + 1, y: rect.minY, width: max(0, rect.maxX - circle.maxX - 1), height: rect.height)
        NSBezierPath(roundedRect: line, xRadius: 1, yRadius: 1).fill()
    }
}
