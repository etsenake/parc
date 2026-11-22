import AppKit
@testable import Parc
import ParcCore

@MainActor final class TextDrag {
    let editor: NotePageEditor
    let anchor: NoteBlockID
    let range: Range<Int>
    var result: NotePageSelection

    init(editor: NotePageEditor, mouseDown event: NSEvent, view: NoteTextView) {
        self.editor = editor
        let controller = editor.selection!
        let canvas = editor.canvas!
        let host = view.host!
        let point = canvas.convert(event.locationInWindow, from: nil)
        let offset = controller.layout.offset(in: host.blockID, at: point) ?? 0
        anchor = host.blockID
        range = offset..<offset
        result = .text(anchor: NotePosition(anchor, offset), head: NotePosition(anchor, offset))
        controller.goal.reset()
        controller.beginTracking()
        let column = canvas.contentRect
        let anchor = self.anchor, range = self.range
        let text = { (head: NotePosition) -> NotePageSelection in
            let nav = controller.navigator()
            let headRange = nav.granularRange(at: head, granularity: .character, layout: controller.layout)
            let ends = nav.span(anchor: anchor, anchorRange: range, head: head.block, headRange: headRange)
            return .text(anchor: ends.anchor, head: ends.head)
        }
        controller.trackingUpdate = { [unowned self] windowPoint in
            let nav = controller.navigator()
            let point = canvas.convert(windowPoint, from: nil)
            let outside = point.x < column.minX - NoteSelectionController.columnEscape || point.x > column.maxX + NoteSelectionController.columnEscape
            let pointer = controller.pointerItem(at: point, nav: nav)
            switch nav.dragTarget(anchor: anchor, pointer: pointer, outsideColumn: outside, layout: controller.layout) {
            case .blocks(let ids):
                controller.blockRange = NoteBlockRange(anchor: anchor, head: pointer?.id ?? anchor)
                self.result = .blocks(ids)
            case .position(let position):
                self.result = text(position)
            case .text(let id):
                self.result = text(NotePosition(id, Self.textOffset(in: id, at: point, nav: nav, layout: controller.layout)))
            }
            controller.preview(self.result)
        }
        controller.preview(result)
        controller.trackingEvent = event
    }

    static func textOffset(in id: NoteBlockID, at point: NSPoint, nav: NoteSelectionNavigator, layout: NoteSelectionCanvasLayout) -> Int {
        let length = layout.length(of: NotePosition(id, 0))
        let steppable = nav.items.filter { $0.role.isSteppable && !$0.frame.isEmpty }
        if let first = steppable.first, first.id == id, point.y < first.frame.minY { return 0 }
        if let last = steppable.last, last.id == id, point.y > last.frame.maxY { return length }
        if let offset = layout.offset(in: id, at: point) { return offset }
        let frame = nav.item(id)?.frame ?? .zero
        return point.y < frame.midY ? 0 : length
    }

    func dragged(_ event: NSEvent) {
        let controller = editor.selection!
        controller.trackingEvent = event
        controller.trackingUpdate?(event.locationInWindow)
    }

    func up(_ event: NSEvent) {
        let controller = editor.selection!
        controller.trackingEvent = event
        controller.trackingUpdate?(event.locationInWindow)
        controller.endTracking(with: result)
    }
}

@MainActor final class BlockDrag {
    let editor: NotePageEditor
    var dragged: [NoteBlockID] = []
    var ghost: NoteDragGhostView?
    var ghostHome = NSRect.zero
    var grabOffset = CGPoint.zero
    var leadingOffset: CGFloat = 0
    var target: NoteCanvasDropTarget?
    var pointer = NSPoint.zero

    init(editor: NotePageEditor) { self.editor = editor }

    func run(grabbing id: NoteBlockID, mouseDown: NSEvent, current: NSEvent) {
        let canvas = editor.canvas!
        let page = editor.session.page
        let ids = NoteDragPlan.draggedBlocks(grabbing: id, selection: editor.session.selection, page: page)
        guard !ids.isEmpty else { return }
        dragged = ids
        let start = canvas.convert(mouseDown.locationInWindow, from: nil)
        let affected = NoteDragPlan.affectedBlocks(ids, page: page)
        let snapshot = makeSnapshot(of: affected, around: start)
        ghostHome = snapshot?.frame ?? NSRect(origin: start, size: .zero)
        grabOffset = CGPoint(x: start.x - ghostHome.minX, y: start.y - ghostHome.minY)
        leadingOffset = (canvas.frame(of: ids[0])?.minX ?? ghostHome.minX) - ghostHome.minX
        if let snapshot {
            let view = NoteDragGhostView(image: snapshot.image, frame: canvas.overlayView.convert(snapshot.frame, from: canvas))
            canvas.overlayView.addSubview(view)
            view.lift()
            ghost = view
        }
        canvas.setDragSources(ids)
        pointer = canvas.convert(current.locationInWindow, from: nil)
        update()
        NSCursor.closedHand.push()
    }

    func moved(_ event: NSEvent) {
        pointer = editor.canvas.convert(event.locationInWindow, from: nil)
        update()
    }

    func update() {
        let canvas = editor.canvas!
        let origin = NoteDragPlan.ghostOrigin(pointer: pointer, grabOffset: grabOffset)
        if let ghost {
            let frame = canvas.overlayView.convert(NSRect(origin: origin, size: ghostHome.size), from: canvas)
            NoteAnimation.withoutAnimation { ghost.frame = frame }
        }
        let next = canvas.dropTarget(at: pointer, dragging: dragged, leadingX: origin.x + leadingOffset)
        if next != target {
            target = next
            canvas.showDropIndicator(next)
        }
    }

    func drop() {
        NSCursor.pop()
        let canvas = editor.canvas!
        canvas.showDropIndicator(nil)
        let ids = dragged
        let chosen = target
        target = nil
        if let chosen {
            let origin = ghost.map { canvas.convert($0.frame, from: canvas.overlayView).origin } ?? pointer
            canvas.prepareDropSettle(ids, ghostOrigin: origin)
            chosen.perform(moving: ids, in: editor.session)
            canvas.setDragSources([])
            ghost?.removeFromSuperview()
            ghost = nil
        }
        dragged = []
        editor.handles.drag.onFinish?()
    }

    func makeSnapshot(of ids: [NoteBlockID], around point: NSPoint) -> (image: NSImage, frame: NSRect)? {
        let canvas = editor.canvas!
        var union: NSRect?
        var pieces: [NoteDragGhostRenderer.Piece] = []
        for id in ids {
            guard let frame = canvas.frame(of: id) else { continue }
            let outer = canvas.outerFrame(of: id) ?? frame
            union = union.map { $0.union(outer) } ?? outer
            if let view = canvas.existingBlockView(for: id), !view.isHidden { pieces.append(.init(view: view, frame: view.frame)) }
        }
        let decorations = canvas.decorations(of: ids)
        for decoration in decorations { union = union.map { $0.union(decoration.rect) } ?? decoration.rect }
        guard var rect = union?.integral, rect.width >= 1, rect.height >= 1 else { return nil }
        let reach: CGFloat = 360
        rect = rect.intersection(NSRect(x: rect.minX, y: point.y - reach, width: rect.width, height: reach * 2))
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        guard let image = Self.render(pieces, decorations: decorations, clip: rect, in: canvas, scale: 2) else { return nil }
        return (image, rect)
    }

    static func capture(_ view: NSView, _ local: NSRect, scale: CGFloat) -> NSBitmapImageRep? {
        guard let parent = view.superview, let index = parent.subviews.firstIndex(of: view) else { return nil }
        let frame = view.frame
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(local.width * scale)), pixelsHigh: Int(ceil(local.height * scale)),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = local.size
        view.removeFromSuperview()
        if let rep { parent.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: local, to: rep) } }
        var subviews = parent.subviews
        subviews.insert(view, at: min(index, subviews.count))
        parent.subviews = subviews
        view.frame = frame
        return rep
    }

    static func render(_ pieces: [NoteDragGhostRenderer.Piece], decorations: [NoteCanvasDecoration], clip rect: NSRect, in container: NSView,
                       scale: CGFloat) -> NSImage? {
        guard rect.width >= 1, rect.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(rect.width * scale)),
                                         pixelsHigh: Int(ceil(rect.height * scale)), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = rect.size
        let context = bitmap.cgContext
        context.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
        context.scaleBy(x: CGFloat(rep.pixelsWide) / rect.width, y: -CGFloat(rep.pixelsHigh) / rect.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            for decoration in decorations {
                NoteCanvasDecorationView.draw(decoration.style, in: decoration.rect.offsetBy(dx: -rect.minX, dy: -rect.minY))
            }
        }
        for piece in pieces {
            let visible = piece.frame.intersection(rect)
            guard visible.width >= 1, visible.height >= 1 else { continue }
            let local = piece.view.convert(visible, from: piece.view.superview ?? container)
            guard let capture = capture(piece.view, local, scale: scale) else { continue }
            capture.draw(in: visible.offsetBy(dx: -rect.minX, dy: -rect.minY), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }
}

struct Move {
    let start: Double
    let end: Double
    let to: () -> NSPoint
    var from: NSPoint?
    var resolved: NSPoint?
}

struct Action {
    let time: Double
    let beat: String?
    let run: () -> Void
    var done = false
}

@MainActor final class NotesScene {
    let scene: BrowserScene
    let controller: NotePageViewController
    let editor: NotePageEditor
    let root: NSView
    let file: NoteFileSession
    let folder: URL
    let input = FilmInput.shared
    let motion = FilmMotion.shared
    var editorImage: NSImage?
    var responder: NSResponder?
    var caretReset = 0.0
    var pointerHidden = false
    var hidePoint = NSPoint.zero
    var textDrag: TextDrag?
    var blockDrag: BlockDrag?
    var gripDown: NSEvent?
    var held: [(Double, Double)] = []
    var log: [String] = []
    var paragraphID: NoteBlockID!
    var firstTodoID: NoteBlockID!
    var kiteID: NoteBlockID?
    var card: NSRect { scene.surface.pageCard }

    static let markdown = """
    ---
    icon: 🧺
    cover: Attachments/Cover%20Sunset%20Strip.jpg
    ---

    Pack the good sandwiches and find the bench by the pond.

    - [ ] Pick up lemonade
    - [ ] Charge the speaker

    > [!TIP]
    > Bring a blanket. The grass is always damp before noon.

    """

    static func scenario(file: URL) -> Scenario {
        var made = ScenarioBuilder.make()
        let home = made.spaces[1]
        made.state.activeSpaceID = home.id
        let note = ScenarioBuilder.tab(CanonTab("Picnic plan", file.absoluteString, .today, "note.text", 0xC2552D), in: home, order: 900)
        made.state.tabs.append(note)
        SidebarHierarchy.placingCreatedTab(note.id, insertion: .automatic, in: &made.state)
        made.state.selectedTabIDs = [note.id]
        made.state.selectionBySpace[home.id.uuidString] = [note.id]
        made.work = home
        made.selected = note
        made.selectedBySpace[home.id] = note
        made.todayTitles = [note.title] + Canon.homeToday.map(\.title)
        return made
    }

    init() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("parc-film-notes-" + UUID().uuidString)
        let attachments = folder.appendingPathComponent(NoteAttachments.folderName)
        try! FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let style = NoteCoverGallery.style(id: "sunset-strip")!
        try! NoteCoverGallery.assetData(for: style)!.write(to: attachments.appendingPathComponent(NoteCoverGallery.suggestedName(for: style) + "." + NoteCoverGallery.fileExtension))
        let url = folder.appendingPathComponent("Picnic plan.md")
        try! Self.markdown.write(to: url, atomically: true, encoding: .utf8)
        scene = BrowserScene(size: NSSize(width: 1440, height: 900), windowRect: NSRect(x: 80, y: 18, width: 1280, height: 840),
                             scale: 2, pagePath: "", scenario: Self.scenario(file: url))
        file = try! NoteFileSession.open(url)
        NoteBlockViewFactory.boards = NoteEaselProvider()
        controller = NotePageViewController(file: file)
        root = controller.view
        editor = controller.editor
        root.frame = NSRect(origin: .zero, size: scene.surface.pageCard.size)
        controller.inheritSpaceContentAppearance(scene.themeSurface.palette.contentAppearance)
        controller.spaceFocus = scene.themeSurface.palette.focus
        editor.formatBar.colorDefaults = UserDefaults(suiteName: "parc-film-notes")!
        editor.formatBar.colorDefaults.removePersistentDomain(forName: "parc-film-notes")
        input.root = root
        input.stageOffset = NSPoint(x: scene.windowRect.minX + card.minX, y: scene.windowRect.minY + card.minY)
        for _ in 0..<6 { settle(); RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        let blocks = editor.session.page.blocks
        paragraphID = blocks.first { $0.kind == .paragraph }!.id
        firstTodoID = blocks.first { $0.kind == .todo }!.id
        scene.surface.drawPage = { [weak self] rect in
            guard let self, let image = self.editorImage else { NSColor.white.setFill(); rect.fill(); return }
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    func settle() {
        root.layoutSubtreeIfNeeded()
        editor.canvas.updateLayoutIfNeeded()
        root.layoutSubtreeIfNeeded()
    }

    func toRoot(_ rect: NSRect, from view: NSView) -> NSRect { root.convert(rect, from: view) }

    func canvasPoint(_ point: NSPoint) -> NSPoint { root.convert(point, from: editor.canvas) }

    func textRect(_ id: NoteBlockID, _ range: Range<Int>) -> NSRect {
        let rects = editor.selection.layout.selectionRects(for: NotePosition(id, 0), range: range)
        let union = rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
        return root.convert(union, from: editor.canvas)
    }

    func range(of text: String, in id: NoteBlockID) -> Range<Int> {
        let string = (editor.session.page.block(id)?.text.string ?? "") as NSString
        let found = string.range(of: text)
        return found.location..<(found.location + found.length)
    }

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    func center(_ view: NSView) -> NSPoint {
        let rect = root.convert(view.bounds, from: view)
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func checkbox(_ id: NoteBlockID) -> NoteTodoCheckbox? {
        editor.canvas.existingBlockView(for: id).flatMap { descendants($0).compactMap { $0 as? NoteTodoCheckbox }.first }
    }

    var formatBar: NoteFormatBarView? { descendants(root).compactMap { $0 as? NoteFormatBarView }.first }

    func swatch(_ choice: NoteColorChoice) -> NSView? {
        descendants(root).first { $0.accessibilityLabel() == choice.title && $0.superview is NoteColorMenuView }
    }

    func textView(_ id: NoteBlockID) -> NoteTextView? { editor.canvas.textHost(for: NotePosition(id, 0))?.textView }

    func makeFirstResponder(_ next: NSResponder?) {
        guard next !== responder else { return }
        _ = responder?.resignFirstResponder()
        responder = next
        _ = next?.becomeFirstResponder()
    }

    func syncFocus() {
        let selection = editor.session.selection
        let controller = editor.selection!
        if controller.isTracking { makeFirstResponder(controller.responder); return }
        switch selection {
        case .text(let anchor, let head) where anchor.block == head.block && anchor.field == head.field:
            guard let host = controller.layout.host(for: head, materialize: true) else { return }
            let view = host.textView
            makeFirstResponder(view)
            let length = (view.string as NSString).length
            let lower = min(max(0, min(anchor.offset, head.offset)), length)
            let upper = min(max(lower, max(anchor.offset, head.offset)), length)
            if view.selectedOffsets != lower..<upper, !view.hasMarkedText() {
                view.setSelectedRange(NSRange(location: lower, length: upper - lower), affinity: .downstream, stillSelecting: false)
            }
        case .blocks, .text, .cells:
            makeFirstResponder(controller.responder)
        case .none:
            break
        }
    }

    func activeSelection() {
        for view in descendants(root).compactMap({ $0 as? NoteTextView }) {
            view.noteLayoutManager?.inactiveSelectionColor = NoteTheme.selection
        }
    }

    func type(_ text: String) {
        for character in text {
            let string = String(character)
            guard let caret = editor.session.selection.caret, let view = textView(caret.block) else { log.append("no caret for \(string)"); return }
            makeFirstResponder(view)
            if view.selectedOffsets != caret.offset..<caret.offset { view.selectedOffsets = caret.offset..<caret.offset }
            input.currentEvent = input.key(string)
            view.insertText(string, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        caretReset = input.time
        pointerHidden = true
        hidePoint = input.point
    }

    func command(_ selector: Selector, key: String, code: UInt16) {
        guard let caret = editor.session.selection.caret, let view = textView(caret.block) else { log.append("no caret for \(selector)"); return }
        makeFirstResponder(view)
        if view.selectedOffsets != caret.offset..<caret.offset { view.selectedOffsets = caret.offset..<caret.offset }
        input.currentEvent = input.key(key, code: code)
        view.doCommand(by: selector)
        caretReset = input.time
        pointerHidden = true
        hidePoint = input.point
    }

    func caretRect() -> NSRect? {
        guard case .text(let anchor, let head) = editor.session.selection, anchor == head, !editor.selection.isTracking,
              let view = textView(head.block), view === responder, let layout = view.layoutManager, let container = view.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let length = (view.string as NSString).length
        let offset = min(head.offset, length)
        let font = (offset > 0 && offset <= length ? view.textStorage?.attribute(.font, at: offset - 1, effectiveRange: nil) as? NSFont : nil)
            ?? view.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
        var x: CGFloat, baseline: CGFloat
        if length == 0 || (offset == length && (view.string as NSString).character(at: length - 1) == 10) {
            let extra = layout.extraLineFragmentRect
            let line = extra.height > 0 ? extra : NSRect(x: 0, y: 0, width: 1, height: NoteTextRendering.lineHeight(view.presentation))
            x = line.minX + (view.textContainer?.lineFragmentPadding ?? 0)
            let ascent = font.ascender, descent = -font.descender
            baseline = line.minY + (line.height - (ascent + descent)) / 2 + ascent
        } else {
            let glyph = layout.glyphIndexForCharacter(at: offset)
            let lineGlyph = min(glyph, max(0, layout.numberOfGlyphs - 1))
            let fragment = layout.lineFragmentRect(forGlyphAt: offset == length ? lineGlyph : glyph, effectiveRange: nil)
            let location = layout.location(forGlyphAt: lineGlyph)
            var insertion = NSRect.zero
            layout.enumerateEnclosingRects(forGlyphRange: NSRange(location: glyph, length: 0),
                                           withinSelectedGlyphRange: NSRange(location: glyph, length: 0), in: container) { rect, stop in
                insertion = rect
                stop.pointee = true
            }
            x = insertion.minX
            baseline = fragment.minY + location.y
        }
        let origin = view.textContainerOrigin
        let rect = NSRect(x: origin.x + x - 1, y: origin.y + baseline - font.ascender, width: 2, height: font.ascender - font.descender)
        return root.convert(rect, from: view)
    }

    func clickText(at point: NSPoint) {
        let controller = editor.selection!
        let canvasPoint = editor.canvas.convert(point, from: root)
        let nav = controller.navigator()
        guard let item = controller.pointerItem(at: canvasPoint, nav: nav), item.role == .text else { return }
        let length = controller.layout.length(of: NotePosition(item.id, 0))
        let offset = controller.layout.offset(in: item.id, at: canvasPoint) ?? (canvasPoint.y < item.frame.midY ? 0 : length)
        controller.goal.reset()
        controller.select(.text(anchor: NotePosition(item.id, offset), head: NotePosition(item.id, offset)))
        caretReset = input.time
    }

    func caretVisible(_ time: Double) -> Bool {
        let idle = time - caretReset
        guard idle > 0.5 else { return true }
        return Int((idle - 0.5) / 0.5) % 2 == 1
    }

    func renderEditor() {
        settle()
        activeSelection()
        let size = root.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        root.effectiveAppearance.performAsCurrentDrawingAppearance { root.cacheDisplay(in: root.bounds, to: rep) }
        if let caret = caretRect(), caretVisible(input.time), let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let flipped = NSRect(x: caret.minX, y: size.height - caret.maxY, width: caret.width, height: caret.height)
            root.effectiveAppearance.performAsCurrentDrawingAppearance { NoteTheme.caret.setFill() }
            NSBezierPath(roundedRect: flipped, xRadius: 1, yRadius: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        editorImage = image
        scene.surface.needsDisplay = true
    }

    func renderStage() -> CGImage {
        motion.apply(in: nil)
        renderEditor()
        let local = NSPoint(x: card.minX + input.point.x, y: card.minY + input.point.y)
        scene.pointer.cursor = input.shownCursor
        scene.pointer.location = pointerHidden ? nil : local
        let image = scene.render(NSRect(origin: .zero, size: NSSize(width: 1440, height: 900)), pixelsWide: 2880, pixelsHigh: 1800).cgImage!
        motion.restore()
        return image
    }

    func run(out: String, still: Bool) {
        let duration = 11.9
        let fps = Film.fps
        let frames = Int(duration * fps)
        var beats: [Beat] = []
        let rest = NSPoint(x: card.width * 0.78, y: card.height * 0.72)
        input.point = rest
        var moves: [Move] = []
        var actions: [Action] = []
        func move(_ start: Double, _ end: Double, _ to: @escaping () -> NSPoint) { moves.append(Move(start: start, end: end, to: to)) }
        func at(_ time: Double, _ beat: String? = nil, _ run: @escaping () -> Void) { actions.append(Action(time: time, beat: beat, run: run)) }
        func click(_ time: Double, _ beat: String? = nil, up gap: Double = 0.1) {
            at(time, beat) { [unowned self] in _ = self.input.down() }
            at(time + gap) { [unowned self] in self.input.up() }
        }
        func hold(_ start: Double, _ end: Double) { held.append((start, end)) }

        at(0, "Picnic plan note open in the Home Space: Sunset Strip cover, basket icon, title, paragraph, two to-dos, tip callout") {}
        let below = { [unowned self] () -> NSPoint in
            let column = self.root.convert(self.editor.canvas.contentRect, from: self.editor.canvas)
            let last = self.editor.session.page.blocks.last!.id
            let frame = self.root.convert(self.editor.canvas.frame(of: last) ?? .zero, from: self.editor.canvas)
            return NSPoint(x: column.minX + 60, y: frame.maxY + 34)
        }
        move(0.6, 1.05, below)
        click(1.1, "Click the empty space below the callout: a fresh paragraph takes the caret")
        at(1.35, "Type \"/\": the slash menu pops in (0.95 to 1 over 0.1 s, 0.05 s fade)") { [unowned self] in self.type("/") }
        for (index, letter) in "todo".enumerated() {
            at(1.65 + Double(index) * 0.15, index == 0 ? "Type \"todo\": the list filters live and the highlight glides" : nil) { [unowned self] in self.type(String(letter)) }
        }
        at(2.55, "Return turns the line into a to-do") { [unowned self] in
            self.command(#selector(NSResponder.insertNewline(_:)), key: "\r", code: 36)
            self.kiteID = self.editor.session.selection.caret?.block
        }
        for (index, letter) in "Bring the kite".enumerated() {
            at(2.85 + Double(index) * 0.06, index == 0 ? "Type \"Bring the kite\"" : nil) { [unowned self] in self.type(String(letter)) }
        }
        let phraseStart = { [unowned self] () -> NSPoint in
            let rect = self.textRect(self.paragraphID, self.range(of: "the good sandwiches", in: self.paragraphID))
            return NSPoint(x: rect.minX + 1, y: rect.midY)
        }
        let phraseEnd = { [unowned self] () -> NSPoint in
            let rect = self.textRect(self.paragraphID, self.range(of: "the good sandwiches", in: self.paragraphID))
            return NSPoint(x: rect.maxX - 1, y: rect.midY + 1)
        }
        move(3.9, 4.35, phraseStart)
        at(4.4, "Drag across \"the good sandwiches\"") { [unowned self] in _ = self.input.press() }
        move(4.45, 4.95, phraseEnd)
        at(5.0, "Release: the floating format bar pops above the selection") { [unowned self] in
            let event = self.input.release()
            self.textDrag?.up(event)
            self.textDrag = nil
        }
        hold(5.0, 5.03)
        move(5.25, 5.6) { [unowned self] in self.formatBar?.button(for: .bold).map(self.center) ?? self.input.point }
        click(5.65, "Click B: the words turn bold")
        move(5.95, 6.3) { [unowned self] in self.formatBar?.button(for: .color).map(self.center) ?? self.input.point }
        click(6.35, "Click the colour A: the colour grid pops")
        move(6.65, 7.05) { [unowned self] in self.swatch(.background(.orange)).map(self.center) ?? self.input.point }
        click(7.1, "Pick the orange background: the highlight lands")
        let afterPond = { [unowned self] () -> NSPoint in
            let rect = self.textRect(self.paragraphID, self.range(of: "pond.", in: self.paragraphID))
            return NSPoint(x: rect.maxX + 46, y: rect.midY)
        }
        move(7.4, 7.8, afterPond)
        at(7.85, "Click after \"pond.\": the selection collapses, the bar tucks away and the orange highlight shows") { [unowned self] in
            _ = self.input.press()
            self.clickText(at: self.input.point)
        }
        at(7.93) { [unowned self] in _ = self.input.release() }
        move(8.15, 8.55) { [unowned self] in self.checkbox(self.firstTodoID).map(self.center) ?? self.input.point }
        at(8.6, "Click the first to-do's checkbox") { [unowned self] in _ = self.input.down() }
        at(8.7, "The check pops (0.85 to 1) while the strikethrough and grey ink fade in") { [unowned self] in
            let box = self.checkbox(self.firstTodoID)
            let view = self.textView(self.firstTodoID)
            if let layer = view?.layer {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = 0.2
                transition.timingFunction = NoteCurve.easeOut
                layer.add(transition, forKey: NoteAnimation.fadeKey)
            }
            self.input.up()
            if let mark = box?.layer?.sublayers?.first, self.editor.session.page.block(self.firstTodoID)?.props.checked == true {
                NoteAnimation.pop(mark, from: NoteAnimation.checkPopScale, spring: .check)
            }
        }
        let kiteText = { [unowned self] () -> NSPoint in
            guard let id = self.kiteID else { return self.input.point }
            let rect = self.textRect(id, self.range(of: "Bring the kite", in: id))
            return NSPoint(x: rect.minX + rect.width * 0.55, y: rect.midY)
        }
        move(8.95, 9.35, kiteText)
        at(9.0, "Hover \"Bring the kite\": its handles fade in") {}
        let grip = { [unowned self] () -> NSPoint in
            let button = self.editor.handles.bar.grip
            return button.superview != nil ? self.center(button) : self.input.point
        }
        move(9.55, 9.8, grip)
        at(9.85, "Press the grip") { [unowned self] in
            self.gripDown = self.input.press()
            self.editor.handles.bar.grip.setPressed(true)
        }
        let dropPoint = { [unowned self] () -> NSPoint in
            let frame = self.root.convert(self.editor.canvas.frame(of: self.firstTodoID) ?? .zero, from: self.editor.canvas)
            let start = self.gripDown.map { self.root.convert($0.locationInWindow, from: nil) } ?? self.input.point
            return NSPoint(x: start.x + 6, y: frame.minY + 4)
        }
        move(9.9, 10.6, dropPoint)
        at(9.9, "Drag the grip up: the ghost lifts to 1.02 and the drop line springs between blocks") {}
        at(10.7, "Release above the first to-do: the block settles into place (0.34/0.86 spring)") { [unowned self] in
            _ = self.input.release()
            self.blockDrag?.drop()
            self.blockDrag = nil
            self.gripDown = nil
        }
        at(11.4, "Rest") {}
        at(duration, "End") {}

        let stripTimes = [0.3, 1.2, 1.5, 2.2, 2.7, 3.7, 4.8, 5.2, 5.8, 6.6, 7.3, 8.1, 8.75, 9.4, 10.3, 11.0]
        let keyTimes: [(String, Double)] = [("slash", 1.45), ("filter", 2.2), ("formatbar", 5.3), ("bold", 5.85), ("colors", 6.8),
                                            ("highlight", 8.1), ("check", 8.77), ("handles", 9.45), ("drag", 10.3), ("settle", 10.85), ("end", 11.7)]
        var strip: [(Double, CGImage)] = []
        let writer = still ? nil : try! AlphaVideoWriter(path: out + "/notes.mov", width: 2880, height: 1800)
        var lastPoint = input.point
        let dump = ProcessInfo.processInfo.environment["NOTES_DUMP"].map { $0.split(separator: ":").compactMap { Double($0) } } ?? []
        if dump.count == 3 { try? FileManager.default.createDirectory(atPath: out + "/dump", withIntermediateDirectories: true) }
        for frame in 0..<frames {
            let time = Double(frame) / fps
            motion.now = time
            input.time = time
            motion.advance()
            for index in moves.indices where time >= moves[index].start - 1e-9 && time <= moves[index].end + 1e-9 {
                if moves[index].from == nil { moves[index].from = input.point; moves[index].resolved = moves[index].to() }
                let p = Film.easeInOut(Film.progress(time, moves[index].start, moves[index].end))
                let a = moves[index].from!, b = moves[index].resolved!
                input.point = NSPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p)
            }
            if pointerHidden && hypot(input.point.x - hidePoint.x, input.point.y - hidePoint.y) > 0.5 { pointerHidden = false }
            for index in actions.indices where !actions[index].done && time >= actions[index].time - 1e-9 {
                actions[index].done = true
                if let beat = actions[index].beat { beats.append(Beat(time: time, frame: frame, beat: beat)) }
                actions[index].run()
            }
            if input.pressed && input.point != lastPoint {
                let event = input.mouse(.leftMouseDragged)
                input.currentEvent = event
                if let textDrag { textDrag.dragged(event) }
                else if let blockDrag { blockDrag.moved(event) }
                else if let down = gripDown, let id = editor.handles.activeBlock {
                    if NoteDragPlan.crossesThreshold(from: down.locationInWindow, to: event.locationInWindow) {
                        editor.handles.bar.grip.setPressed(false)
                        editor.handles.hide(animated: true)
                        let drag = BlockDrag(editor: editor)
                        drag.run(grabbing: id, mouseDown: down, current: event)
                        blockDrag = drag
                    }
                } else if let down = input.downEvent, hypot(event.locationInWindow.x - down.locationInWindow.x,
                                                                   event.locationInWindow.y - down.locationInWindow.y) >= NoteSelectionController.dragThreshold,
                          let view = editor.canvas.hitTest(editor.canvas.superview!.convert(editor.canvas.convert(down.locationInWindow, from: nil), from: editor.canvas))
                            .flatMap({ sequence(first: $0, next: { $0.superview }).compactMap { $0 as? NoteTextView }.first }) {
                    let drag = TextDrag(editor: editor, mouseDown: down, view: view)
                    textDrag = drag
                    drag.dragged(event)
                } else {
                    input.drag()
                }
            }
            lastPoint = input.point
            input.hover()
            if !held.contains(where: { time >= $0.0 - 1e-9 && time < $0.1 - 1e-9 }) {
                RunLoop.main.run(until: Date())
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
            }
            motion.deliverStops()
            syncFocus()
            let dumping = dump.count == 3 && time >= dump[0] - 1e-9 && time <= dump[1] + 1e-9 && (frame - Int((dump[0] * fps).rounded())) % max(1, Int(dump[2])) == 0
            let wanted = still ? keyTimes.contains { Int(($0.1 * fps).rounded()) == frame } || stripTimes.contains { Int(($0 * fps).rounded()) == frame } || dumping : true
            guard wanted else { continue }
            let image = renderStage()
            if dumping, let crop = image.cropping(to: CGRect(x: 2 * (scene.windowRect.minX + card.minX), y: 2 * (scene.windowRect.minY + card.minY),
                                                                width: 2 * card.width, height: 2 * card.height)) {
                Film.writePNG(crop, out + String(format: "/dump/%04d.png", frame))
                log.append(String(format: "frame %d t=%.3f pointer=(%.1f, %.1f) cursor=%@ selection=%@", frame, time, input.point.x, input.point.y,
                                  input.shownCursor === NSCursor.iBeam ? "ibeam" : input.shownCursor === NSCursor.pointingHand ? "hand" : input.shownCursor === NSCursor.closedHand ? "closed" : input.shownCursor === NSCursor.arrow ? "arrow" : "other",
                                  String(describing: editor.session.selection)))
                if let ghost = descendants(root).compactMap({ $0 as? NoteDragGhostView }).first, let layer = ghost.content.layer {
                    log.append("   ghost frame=\(ghost.frame) content=\(ghost.content.frame) image=\(ghost.content.image.size) reps=\(ghost.content.image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }) model=\(layer.transform.m11),\(layer.transform.m41) present=\(motion.current(layer, "transform").map { ($0 as! NSValue).caTransform3DValue.m11 } ?? -1) anchor=\(layer.anchorPoint) bounds=\(layer.bounds) pos=\(layer.position)")
                }
            }
            writer?.append(image)
            if let key = keyTimes.first(where: { Int(($0.1 * fps).rounded()) == frame }) { Film.writePNG(image, out + "/notes-\(key.0).png") }
            if stripTimes.contains(where: { Int(($0 * fps).rounded()) == frame }) { strip.append((time, image)) }
            if frame % 60 == 0 { print("notes frame", frame, String(format: "%.2f s", time)) }
        }
        log.append("final page:\n" + editor.session.page.flattened(includingCollapsed: true).compactMap { flat in
            editor.session.page.block(flat.id).map { "  " + $0.kind.rawValue + " \"" + $0.text.string + "\" checked=\($0.props.checked)" }
        }.joined(separator: "\n"))
        log.append("markdown:\n" + NoteMarkdown.serialize(editor.session.page))
        try? (log + ["animations:"] + motion.history).joined(separator: "\n").write(toFile: out + "/notes-probe.txt", atomically: true, encoding: .utf8)
        Film.writeStrip(strip, path: out + "/notes-strip.png")
        Film.writeBeats(beats, path: out + "/notes-beats.json")
        if let writer {
            let result = writer.finish()
            print("wrote", out + "/notes.mov", result.frames, "frames status", result.status.rawValue, result.error?.localizedDescription ?? "")
        }
        try? file.flush()
        try? FileManager.default.removeItem(at: folder)
    }
}
