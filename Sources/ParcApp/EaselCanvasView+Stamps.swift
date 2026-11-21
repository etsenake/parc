import AppKit
import ParcCore
import QuartzCore

@MainActor
protocol EaselStampPanelsPresenting: AnyObject {
    var isWheelOpen: Bool { get }
    var isPickerOpen: Bool { get }
    var onPick: ((EaselStampFace) -> Void)? { get set }
    var onPickerClose: (() -> Void)? { get set }
    var emojiLibrary: NoteEmojiLibrary? { get set }
    func presentWheel(in host: NSView, at point: NSPoint, below control: NSRect?, recents: [EaselStampFace], current: EaselStampFace)
    func presentPicker(in host: NSView, at point: NSPoint)
    func close(animated: Bool)
}

@MainActor
final class EaselCanvasStampState {
    struct Press {
        let id: UUID
        let face: EaselStampFace
        var point: NSPoint
        let began: CFTimeInterval
        let tilt: Double
        var side: Double
        var stage = 0
        var stageStart: CFTimeInterval = 0
        var stageFrom: Double = 0
    }

    static let recentsKey = "easel.stampRecents"
    static let faceKey = "easel.stampFace"

    var press: Press?
    var timer: Timer?
    var panels: EaselStampPanelsPresenting?
    var random = SystemRandomNumberGenerator()
    private var cursors: [String: NSCursor] = [:]

    var face: EaselStampFace {
        get { UserDefaults.standard.string(forKey: Self.faceKey).flatMap(EaselStampFace.init(token:)) ?? .design(EaselStamps.ring[0]) }
        set { UserDefaults.standard.set(newValue.token, forKey: Self.faceKey) }
    }

    var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.recentsKey) }
    }

    func cursor(for face: EaselStampFace, library: NoteEmojiLibrary?) -> NSCursor {
        if let cached = cursors[face.token] { return cached }
        let side: CGFloat = 30
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            EaselStampArtwork.draw(face, in: rect.insetBy(dx: 4, dy: 4), ink: NoteTheme.menuInk, library: library)
            return true
        }
        let made = NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        if cursors.count > 32 { cursors.removeAll() }
        cursors[face.token] = made
        return made
    }
}

extension EaselCanvasView {
    var stampCursor: NSCursor { stamps.cursor(for: stamps.face, library: stampEmojiLibrary) }

    var stampEmojiLibrary: NoteEmojiLibrary? { notesFolder?().map { NoteEmojiLibrary.library(for: $0.appendingPathComponent("Easel", isDirectory: false)) } }

    static var stampPanelsFactory: (@MainActor () -> EaselStampPanelsPresenting)?

    private var stampPanels: EaselStampPanelsPresenting? {
        if let existing = stamps.panels { return existing }
        guard let made = Self.stampPanelsFactory?() else { return nil }
        made.onPick = { [weak self] face in self?.chooseStampFace(face) }
        made.onPickerClose = { [weak self] in
            guard let self, self.window?.firstResponder !== self else { return }
            self.window?.makeFirstResponder(self)
        }
        stamps.panels = made
        return made
    }

    func stampToolActivated(from control: NSView?) {
        guard let panels = stampPanels, window != nil else { return }
        if panels.isWheelOpen { openStampPicker(); return }
        guard !panels.isPickerOpen else { return }
        openStampWheel(from: control)
    }

    func dismissStampPanels(animated: Bool = true) {
        stamps.panels?.close(animated: animated)
    }

    private func stampAnchor() -> NSPoint {
        if let window, window.isKeyWindow {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if visibleRect.contains(point), isTopmost(atWindowPoint: window.mouseLocationOutsideOfEventStream) { return point }
        }
        let visible = visibleRect.isEmpty ? bounds : visibleRect
        return NSPoint(x: visible.midX, y: visible.midY)
    }

    func openStampWheel(from control: NSView? = nil) {
        guard tool == .stamp, window != nil, let panels = stampPanels else { return }
        let host = menuHost
        panels.emojiLibrary = stampEmojiLibrary
        let below: NSRect? = control.flatMap { $0.window === window ? host.convert($0.bounds, from: $0) : nil }
        panels.presentWheel(in: host, at: host.convert(stampAnchor(), from: self), below: below,
                            recents: EaselStamps.hubFaces(stamps.recents), current: stamps.face)
        announceStamp("Stamp wheel. Arrow keys pick a stamp, E for every emoji.")
    }

    func openStampPicker() {
        guard tool == .stamp, window != nil, let panels = stampPanels else { return }
        let host = menuHost
        panels.emojiLibrary = stampEmojiLibrary
        panels.presentPicker(in: host, at: host.convert(stampAnchor(), from: self))
    }

    func chooseStampFace(_ face: EaselStampFace) {
        stamps.face = face
        if tool != .stamp { tool = .stamp }
        window?.makeFirstResponder(self)
        refreshToolCursor()
        announceStamp("\(EaselStampArtwork.title(face)). Click to stamp, hold to grow.")
    }

    func beginStampPress(at point: NSPoint, event: NSEvent) -> Bool {
        guard tool == .stamp else { return false }
        guard !session.isClosed, !session.isDeleted, fixedCanvasSize == nil else { return true }
        dismissStampPanels(animated: false)
        selection.removeAll()
        hidePlacementPreview()
        stamps.press = EaselCanvasStampState.Press(id: UUID(), face: stamps.face, point: point, began: CACurrentMediaTime(),
                                                   tilt: EaselStamps.tilt(using: &stamps.random), side: EaselStamps.sizes[0])
        refreshStampDraft()
        if let id = stamps.press?.id { raiseStampDraft(id) }
        stamps.timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated { self.growStamp() }
        }
        RunLoop.main.add(timer, forMode: .common)
        stamps.timer = timer
        return true
    }

    func moveStampPress(to point: NSPoint) -> Bool {
        guard stamps.press != nil else { return false }
        stamps.press?.point = point
        refreshStampDraft()
        return true
    }

    func finishStampPress(at point: NSPoint) -> Bool {
        guard let press = stamps.press else { return false }
        stamps.timer?.invalidate()
        stamps.timer = nil
        let side = EaselStamps.side(heldFor: CACurrentMediaTime() - press.began)
        seedStampSlam(press.id, drawnSide: press.side, placedSide: side)
        guard placeStamp(press.face, at: point, side: side, tilt: press.tilt, id: press.id, pointer: true) else { return false }
        stopStampPress()
        return true
    }

    func cancelStampPress() {
        guard stamps.press != nil else { return }
        stopStampPress()
    }

    private func stopStampPress() {
        if let id = stamps.press?.id { lowerStampDraft(id) }
        stamps.timer?.invalidate()
        stamps.timer = nil
        stamps.press = nil
        draft = nil
        invalidateIncrementalDisplay(layout: true)
    }

    private func growStamp() {
        guard let press = stamps.press, start != nil else { cancelStampPress(); return }
        let now = CACurrentMediaTime()
        let stage = EaselStamps.stage(heldFor: now - press.began)
        if stage != press.stage {
            stamps.press?.stage = stage
            stamps.press?.stageStart = now
            stamps.press?.stageFrom = press.side
            EaselCanvasHaptics.snap()
        }
        guard let current = stamps.press else { return }
        let side = EaselStampGrowth.side(from: current.stage == 0 ? current.side : current.stageFrom, to: EaselStamps.sizes[current.stage],
                                         since: now - current.stageStart,
                                         reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard abs(side - press.side) > 0.01 else { return }
        stamps.press?.side = side
        refreshStampDraft()
    }

    private func refreshStampDraft() {
        guard let press = stamps.press else { return }
        draft = [stampItem(press.face, at: press.point, side: press.side, tilt: press.tilt, id: press.id)]
        invalidateIncrementalDisplay(layout: true)
    }

    private func stampItem(_ face: EaselStampFace, at point: NSPoint, side: Double, tilt: Double, id: UUID) -> EaselItem {
        var item = EaselStamps.stamped(face, at: EaselPoint(x: Double(point.x), y: Double(point.y)), side: side, tilt: tilt,
                                       color: insertionColor, in: session.document)
        item.id = id
        return item
    }

    @discardableResult
    func placeStamp(at point: NSPoint) -> Bool {
        guard stamps.press == nil else { return false }
        return placeStamp(stamps.face, at: point, side: EaselStamps.sizes[0], tilt: EaselStamps.tilt(using: &stamps.random), id: UUID())
    }

    @discardableResult
    private func placeStamp(_ face: EaselStampFace, at point: NSPoint, side: Double, tilt: Double, id: UUID, pointer: Bool = false) -> Bool {
        guard !session.isClosed, !session.isDeleted, fixedCanvasSize == nil, finishEditing() else { return false }
        let item = stampItem(face, at: point, side: side, tilt: tilt, id: id)
        guard withObjectMotion(.appear, { commit("Add stamp", { $0.items.append(item) }) }) else { return false }
        if pointer { EaselCanvasHaptics.thud() }
        stamps.recents = EaselStamps.recording(face, in: stamps.recents)
        window?.makeFirstResponder(self)
        announceStamp("Added \(EaselStampArtwork.accessibilityLabel(face).lowercased())")
        return true
    }

    var stampChordReady: Bool {
        tool == .stamp && window?.isKeyWindow == true && canvasOwnsKeyFocus && editor == nil && start == nil
            && !session.isClosed && !session.isDeleted && fixedCanvasSize == nil
    }

    @discardableResult
    func stampSelection() -> Bool {
        let document = session.document
        let targets = EaselStamps.keyboardTargets(selection, in: document.items)
        guard !targets.isEmpty, finishEditing() else { return false }
        let face = stamps.face, side = EaselStamps.sizes[0]
        var placed: [EaselItem] = []
        for target in targets {
            guard let item = document.items.first(where: { $0.id == target }) else { continue }
            let slot = document.items.filter { $0.kind == .stamp && $0.attachedTo == target }.count
            let point = EaselStamps.pinnedPoint(on: item, side: side, slot: slot)
            var stamp = EaselStamps.stamped(face, at: point, side: side, tilt: EaselStamps.tilt(using: &stamps.random),
                                            color: insertionColor, in: document)
            stamp.zIndex += placed.count
            stamp.attachedTo = target
            placed.append(stamp)
        }
        guard !placed.isEmpty, withObjectMotion(.appear, { commit(placed.count == 1 ? "Add stamp" : "Add stamps", { $0.items.append(contentsOf: placed) }) })
        else { return false }
        stamps.recents = EaselStamps.recording(face, in: stamps.recents)
        announceStamp("Added \(EaselStampArtwork.accessibilityLabel(face).lowercased())")
        return true
    }

    private func announceStamp(_ message: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
