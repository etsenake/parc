import AppKit
import CoreText
import Combine

@main @MainActor
struct NoteEditorTests {
    static var assertions = 0
    private final class EditorRef { weak var value: NoteEditorViewController?; init(_ value: NoteEditorViewController) { self.value = value } }
    private static var editors: [EditorRef] = []
    static func makeEditor(directory: URL, documentID: UUID) throws -> NoteEditorViewController {
        let editor = try NoteEditorViewController(directory: directory, documentID: documentID)
        editors.append(EditorRef(editor)); return editor
    }
    static func drainPublications() throws {
        let deadline = Date().addingTimeInterval(2)
        while editors.contains(where: { $0.value?.hasPendingBodyPublication == true }) {
            guard Date() < deadline else { throw NSError(domain: "Real main-queue body publication did not settle", code: 1) }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1; if try !value() { throw NSError(domain: message, code: 1) }
    }
    static func expectPublished(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        try drainPublications(); try expect(try value(), message)
    }
    static func highlight(of button: NoteFormatButton) -> NSView? {
        button.superview?.subviews.first { !($0 is NoteFormatButton) && $0.frame == button.frame.insetBy(dx: 2, dy: 2) }
    }
    static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw NSError(domain: message, code: 1) }; return value
    }
    static func main() throws {
        _ = NSApplication.shared
        let fontURL = URL(fileURLWithPath: try require(CommandLine.arguments.dropFirst().first, "Actual bundled Notes title font input"))
        for url in try FileManager.default.contentsOfDirectory(at: fontURL.deletingLastPathComponent(), includingPropertiesForKeys: nil) where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        try expect(NoteDocumentAppearance.titleFont.fontName == "Nunito-ExtraBold" && NoteDocumentAppearance.titleFont.pointSize == 34, "Actual shipped Nunito font resolves at recovered size")
        let light = try require(NSAppearance(named: .aqua), "Native light appearance")
        let dark = try require(NSAppearance(named: .darkAqua), "Native dark appearance")
        func rgba(_ color: NSColor, under appearance: NSAppearance) -> String {
            var value = ""
            appearance.performAsCurrentDrawingAppearance { value = (try? EaselRichTextCodec.hex(color)) ?? "unresolved" }
            return value
        }
        try expect(rgba(NoteDocumentAppearance.backgroundColor, under: light) == "#FFFFFFD9" && rgba(NoteDocumentAppearance.backgroundColor, under: dark) == "#00000080", "Actual Notes background resolves original light/dark alpha independently")
        try expect(rgba(NoteDocumentAppearance.bodyColor, under: light) == "#000000FF" && rgba(NoteDocumentAppearance.bodyColor, under: dark) == "#FFFFFFFF", "Native named body ink follows appearance")
        try expect(rgba(NoteDocumentAppearance.titleColor, under: light) == "#220C7FFF" && rgba(NoteDocumentAppearance.titleColor, under: dark) == "#E6E6FFFF", "Original title color pairs")
        try expect(rgba(NoteDocumentAppearance.placeholderColor, under: dark) == "#E6E6FF66", "Original placeholder color remains forty percent opacity")
        try expect(rgba(NoteDocumentAppearance.cursorColor, under: dark) == "#9380E0FF" && rgba(NoteDocumentAppearance.selectionColor, under: dark) == "#5235CEFF", "Cursor and native selection retain their own dark styles")
        try checkFormattingAppearance(light: light, dark: dark)
        let namedBody = NSAttributedString(string: "semantic", attributes: NoteDocumentAppearance.bodyAttributes)
        let namedRich = try EaselRichTextCodec.snapshot(namedBody)
        try expect(namedRich.runs.first?.attributes.semanticInk == .noteBody && namedRich.runs.first?.attributes.ink == "#000000FF", "Only original native named body ink gets the explicit semantic carrier")
        let encodedNamed = try JSONEncoder().encode(namedRich)
        let restoredNamed = try JSONDecoder().decode(EaselRichText.self, from: encodedNamed)
        let semanticBoard = NSPasteboard.withUniqueName(); defer { semanticBoard.releaseGlobally() }
        let semanticPayload = try EaselStyledText.capture(namedBody, style: .init(), color: "#000000")
        try semanticPayload.write(to: semanticBoard)
        try expect(EaselStyledText.read(from: semanticBoard) == semanticPayload, "Actual private rich clipboard preserves semantic ink without touching the global board")
        let restoredColor = try require(EaselRichTextCodec.attributes(restoredNamed.runs[0].attributes)[.foregroundColor] as? NSColor, "Decoded semantic native ink")
        try expect(restoredNamed == namedRich && rgba(restoredColor, under: dark) == "#FFFFFFFF", "Semantic ink survives durable Codable roundtrip without saving current appearance")
        for color in [NSColor.black, .white, NSColor(srgbRed: 0.3, green: 0.2, blue: 0.1, alpha: 1)] {
            var attributes = NoteDocumentAppearance.bodyAttributes; attributes[.foregroundColor] = color
            let explicit = try EaselRichTextCodec.snapshot(NSAttributedString(string: "authored", attributes: attributes))
            let restored = try require(EaselRichTextCodec.attributes(explicit.runs[0].attributes)[.foregroundColor] as? NSColor, "Explicit authored ink")
            try expect(explicit.runs[0].attributes.semanticInk == nil && rgba(restored, under: light) == rgba(restored, under: dark), "Explicit black/white/custom ink never becomes inferred semantic ink")
        }
        var inconsistent = namedRich; inconsistent.runs[0].attributes.ink = "#FFFFFFFF"
        do { try inconsistent.validate(text: namedBody.string); try expect(false, "Inconsistent semantic fallback must reject") } catch EaselStoreError.invalidDocument { assertions += 1 }
        var legacy = namedRich; legacy.runs[0].attributes.semanticInk = nil
        let legacyBytes = try JSONEncoder().encode(legacy)
        try expect(!String(decoding: legacyBytes, as: UTF8.self).contains("semanticInk") && JSONDecoder().decode(EaselRichText.self, from: legacyBytes) == legacy, "Existing fixed-run documents decode without a new required key")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-editor-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        let first = try makeEditor(directory: directory, documentID: session.document.id)
        let second = try makeEditor(directory: directory, documentID: session.document.id)
        first.loadView(); second.loadView()
        first.view.frame = NSRect(x: 0, y: 0, width: 340, height: 600); first.view.layoutSubtreeIfNeeded()
        let text = first.text
        text.localUndo.groupsByEvent = false
        func type(_ value: String) { text.localUndo.beginUndoGrouping(); text.insertText(value, replacementRange: text.selectedRange()); text.localUndo.endUndoGrouping() }
        type("Hello 👋")
        try expectPublished(session.document.body.text == "Hello 👋", "Real native text edit publishes through recovered body throttle")
        try expect(second.text.string == "Hello 👋", "Other live editor receives original session text")
        try expect(text.localUndo.canUndo, "Body owns native undo")
        try session.updateTitle("Renamed elsewhere", replacing: session.document.title)
        try expect(text.localUndo.canUndo, "Independent title update preserves body undo")
        text.undo(nil)
        try expectPublished(session.document.body.text.isEmpty && second.text.string.isEmpty, "Native Undo persists and updates peer")
        text.redo(nil)
        try expectPublished(session.document.body.text == "Hello 👋", "Native Redo restores original Unicode text")
        text.setSelectedRange(NSRange(location: 0, length: 5)); text.localUndo.beginUndoGrouping(); text.toggle(.bold); text.localUndo.endUndoGrouping()
        try expectPublished(session.document.body.richText.runs.contains { $0.attributes.font.traits != 0 }, "Formatting reaches durable rich ranges")
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString(" pasted", forType: .string); text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.localUndo.beginUndoGrouping(); let pasted = text.pasteContent(from: board); text.localUndo.endUndoGrouping()
        try expectPublished(pasted && session.document.body.text.hasSuffix(" pasted"), "Actual native paste persists without global clipboard")
        let beforeFailure = session.document
        let file = directory.appendingPathComponent(session.document.id.uuidString.lowercased() + ".json")
        let data = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0)); type(" draft")
        try expectPublished(text.string.hasSuffix(" draft") && session.document == beforeFailure, "Failed disk write keeps draft and previous saved revision")
        try expect(!first.prepareToClose(), "Original editor refuses closure while draft cannot save")
        try FileManager.default.removeItem(at: file); try data.write(to: file)
        try expect(first.prepareToClose(), "Original editor can finish after storage recovers")
        try expectPublished(session.document.body.text.hasSuffix(" draft") && second.text.string.hasSuffix(" draft"), "Recovered write saves original draft and publishes to peer")
        let reopened = try makeEditor(directory: directory, documentID: session.document.id); reopened.loadView()
        try expect(EaselRichTextCodec.snapshot(reopened.text.attributedString()) == EaselRichTextCodec.snapshot(text.attributedString()), "Reopen retains original authored attributes despite layout glyph substitution")

        let window = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = first.view
        first.view.frame = NSRect(x: 0, y: 0, width: 340, height: 600); first.view.layoutSubtreeIfNeeded()
        text.setSelectedRange(NSRange(location: 0, length: 0))
        let geometry = try require(NoteParagraphGeometry.target(in: text, containing: 0), "Actual first paragraph geometry")
        let admitted = try require(NoteFormattingTarget(text: text, document: session.document, range: geometry.range), "Live attributed target")
        try expectPublished(admitted.matches(text: text, document: session.document), "Exact range/document admission")
        text.textStorage?.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 0, length: 1))
        try expectPublished(!admitted.matches(text: text, document: session.document), "Attribute-only replacement invalidates delayed target")
        text.textStorage?.setAttributedString(admitted.contents)
        var other = session.document; other.body.id = UUID()
        try expect(!admitted.matches(text: text, document: other), "Body replacement cannot reuse a range")
        other = session.document; other.revision += 1
        try expect(!admitted.matches(text: text, document: other), "Cross-window document revision invalidates menu")
        other = session.document; other.deleted = true
        try expect(!admitted.matches(text: text, document: other), "Tombstone invalidates a pending format")
        try expectPublished(NoteFormattingTarget(text: text, document: session.document, range: NSRange(location: NSNotFound, length: 0)) == nil, "Reject NSNotFound without overflow")
        try expect(NoteFormatAction.allCases.count == 12 && NoteFormatAction.allCases.last?.title == "Link", "Notes exposes recovered twelve options")
        window.componentKey = false
        first.formatting.present(range: geometry.range)
        try expect(!first.formatting.isPresentingMenu, "Inactive owner cannot open format menu")
        window.componentKey = true
        first.formatting.present(range: geometry.range)
        try expect(first.formatting.isPresentingMenu && text.selectedRange() == geometry.range, "Gutter selects exact original paragraph")
        let selectedBefore = text.selectedRange()
        first.formatting.dismiss()
        try expect(!first.formatting.isPresentingMenu && text.selectedRange() == selectedBefore, "First dismissal preserves selected paragraph")
        first.formatting.present(range: geometry.range)
        try expect(window.firstResponder === text && first.formatting.isPresentingMenu, "Gutter presentation keeps the original body responder")
        first.formatting.present(range: geometry.range, focus: true)
        let beforeMenu = session.document.body
        let down = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125), "Component menu Down")
        let enter = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36), "Component menu Return")
        try expect(window.firstResponder is NoteFormatMenu, "Footer/AX entry focuses the original paragraph menu")
        text.localUndo.beginUndoGrouping(); window.firstResponder?.keyDown(with: down); window.firstResponder?.keyDown(with: down); window.firstResponder?.keyDown(with: enter); text.localUndo.endUndoGrouping()
        try expect(!first.formatting.isPresentingMenu && text.paragraphKind() == .heading2, "Real gutter action formats original paragraph")
        try expectPublished(session.document.body.id == beforeMenu.id && session.document.body.richText != beforeMenu.richText, "Menu saves formatting without replacing body identity")
        text.undo(nil)
        try expectPublished(session.document.body == beforeMenu, "Gutter action belongs to native body Undo")
        first.formatting.present(range: geometry.range)
        try session.updateTitle("A concurrent title", replacing: session.document.title)
        try expect(!first.formatting.isPresentingMenu, "Concurrent session publication cancels inline menu")
        window.beforeNextFocus = { try! session.updateTitle("Title committed on focus", replacing: session.document.title) }
        first.formatting.present(range: geometry.range)
        text.localUndo.beginUndoGrouping(); first.formatting.perform(.italic); text.localUndo.endUndoGrouping()
        try expect(text.hasEmphasis(.italic), "Menu admission follows native focus-triggered title publication")
        text.undo(nil); try drainPublications()
        let afterConcurrent = session.document.body
        first.formatting.perform(.bold)
        try expectPublished(session.document.body == afterConcurrent, "Canceled menu cannot format stale contents")
        first.formatting.present(range: geometry.range)
        text.setSelectedRange(NSRange(location: 1, length: 0)); first.formatting.selectionChanged()
        try expect(!first.formatting.isPresentingMenu, "Native caret transition cancels original range owner")
        first.formatting.present(range: geometry.range)
        text.frame.size.width -= 20; first.formatting.reconcileGeometry()
        try expect(!first.formatting.isPresentingMenu, "Actual text geometry change cancels anchored menu")
        first.view.needsLayout = true; first.view.layoutSubtreeIfNeeded()
        first.formatting.present(range: geometry.range)
        try expect(first.prepareToClose() && !first.formatting.isPresentingMenu, "Retirement dismisses transient UI before closing")
        let nativePoint = text.convert(NSPoint(x: text.bounds.maxX - 2, y: 40), to: first.formatting.superview)
        try expect(first.formatting.hitTest(nativePoint) == nil, "Inactive gutter overlay preserves original native text hit-testing")
        text.setSelectedRange(NSRange(location: 0, length: 5))
        first.formatting.formatSelection()
        try expect(first.formatting.isPresentingMenu && text.selectedRange().length == 5, "Accessible fallback retains exact inline selection")
        first.formatting.dismiss()
        _ = window.makeFirstResponder(text)
        first.formatting.selection.present()
        try expect(first.formatting.selection.isPresenting && window.firstResponder === text, "Automatic selection formatting preserves the original text responder")
        let beforeMenuReturn = text.string
        try expect(first.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))) && text.string == beforeMenuReturn && first.formatting.selection.isPresenting && window.firstResponder === text, "Body Return with an open selection menu is didPressEnter: nil keyboard index consumes Return without inserting a newline")
        try expect(!first.textView(text, doCommandBy: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))), "Alternate Return is not the recovered body menu command")
        let returnBar = try require(first.formatting.subviews.compactMap { $0 as? NoteSelectionBar }.first, "Automatic selection owner for body Return")
        returnBar.restoreKeyboardSelection(1)
        let beforeReturnAction = session.document.body, returnRanges = text.selectedRanges
        text.localUndo.beginUndoGrouping()
        try expect(first.textView(text, doCommandBy: #selector(NSResponder.insertNewline(_:))), "Body Return with a keyboard index sends didPressEnter")
        text.localUndo.endUndoGrouping()
        try expectPublished(session.document.body != beforeReturnAction, "didPressEnter applies the selected original control through the body dispatcher")
        try expect(text.selectedRanges == returnRanges, "didPressEnter keeps the original body selection")
        text.undo(nil); try drainPublications()
        try expectPublished(session.document.body == beforeReturnAction && text.selectedRanges == returnRanges, "didPressEnter formatting is a real native Undo")
        _ = window.makeFirstResponder(text); first.formatting.selection.present()
        let selectionFrame = try require(first.formatting.selection.frame, "Selection menu geometry")
        try expect(selectionFrame.size == NoteSelectionGeometry.size, "Recovered selection menu dimensions")
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let selectionButtons = buttons(in: first.formatting).filter { ["Format Selection", "Bold", "Italic", "Underline", "Strikethrough", "Link"].contains($0.accessibilityLabel() ?? "") }
        try expect(selectionButtons.map { $0.accessibilityLabel() ?? "" } == ["Format Selection", "Bold", "Italic", "Underline", "Strikethrough", "Link"], "Selection controls expose the recovered order and native accessibility labels")
        let selectionBar = try require(first.formatting.subviews.compactMap { $0 as? NoteSelectionBar }.first, "Actual horizontal selection owner")
        selectionBar.layoutSubtreeIfNeeded()
        let nativeButtons = selectionButtons.compactMap { $0 as? NoteFormatButton }
        try expect(nativeButtons.count == 6 && nativeButtons[0].showsDisclosure && nativeButtons.dropFirst().allSatisfy { !$0.showsDisclosure }, "Actual selection controls use shared original glyph owner with only Aa disclosure")
        try expect(selectionBar.selectedIndex == nil && nativeButtons.allSatisfy { !$0.keyboardSelected }, "Original selection menu starts with no selected keyboard action")
        nativeButtons[1].updateTrackingAreas()
        let barHover = NoteComponentTrackingEvent(); barHover.area = nativeButtons[1].trackingAreas.first { $0.options == [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect] }
        nativeButtons[1].mouseEntered(with: barHover)
        let selectionDocument = session.document, selectionUndo = text.localUndo.canUndo
        selectionBar.appearance = dark; selectionBar.viewDidChangeEffectiveAppearance()
        let selectionSurface = try require(selectionBar.subviews.first, "Horizontal original menu surface")
        let selectionFill = try require(selectionSurface.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)), "Horizontal menu fill")
        let selectionBorder = try require(selectionSurface.layer?.borderColor.flatMap(NSColor.init(cgColor:)), "Horizontal menu border")
        try expect(rgba(selectionFill, under: light) == "#120F2EFF" && rgba(selectionBorder, under: light) == "#34334DFF" && selectionSurface.layer?.borderWidth == 0.5, "Same horizontal factory receives actual dark named background and half-point border")
        try expect(selectionSurface.frame.height == 34 && selectionBar.frame.size == NoteSelectionGeometry.size, "Recovered inner cross-axis and original selection host geometry are distinct")
        try expect(buttons(in: selectionBar).compactMap { $0 as? NoteFormatButton }.elementsEqual(nativeButtons, by: { $0 === $1 }) && nativeButtons[1].hovered && selectionBar.selectedIndex == nil, "Horizontal appearance refresh preserves actual buttons and hover without selecting or invoking an action")
        try expect(window.firstResponder === text && text.localUndo.canUndo == selectionUndo && session.document == selectionDocument, "Horizontal appearance preserves original body focus, Undo and durability")
        selectionBar.appearance = light; selectionBar.viewDidChangeEffectiveAppearance()
        try expect(selectionSurface.layer?.borderColor.flatMap(NSColor.init(cgColor:))?.alphaComponent == 0, "Light horizontal surface removes only the dark border")
        nativeButtons[1].mouseExited(with: barHover)
        let retiredSelector = try require(selectionButtons[3].action, "Original inline action"), retiredOwner = selectionButtons[3].target
        let originalRanges = text.selectedRanges, originalBody = session.document.body
        text.localUndo.beginUndoGrouping(); selectionButtons[3].performClick(nil); text.localUndo.endUndoGrouping()
        try expect(first.formatting.selection.isPresenting && text.selectedRanges == originalRanges, "Emphasis retains native selection and republishes a live menu")
        try drainPublications()
        let afterLiveAction = session.document
        NSApp.sendAction(retiredSelector, to: retiredOwner, from: selectionButtons[3])
        try expect(session.document == afterLiveAction && !selectionButtons[3].isEnabled && selectionButtons[3].target == nil, "Retained prior button cannot retarget a replacement selection menu")
        try expectPublished(session.document.body != originalBody && session.document.body.id == originalBody.id, "Selection action persists actual formatting without replacing body identity")
        text.undo(nil)
        try expectPublished(session.document.body == originalBody && text.selectedRanges == originalRanges, "Selection action Undo restores exact contents and selection")
        first.formatting.selection.present()
        let escaped = first.textView(text, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        try expect(escaped && !first.formatting.isPresentingMenu && text.selectedRanges == originalRanges, "First Escape dismisses only the selection menu")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        try expect(!first.formatting.isPresentingMenu, "Canceled queued publication cannot reopen the escaped menu")
        first.formatting.selection.present()
        let staleMenu = try require(first.formatting.selection.makeParagraphMenu(), "Native Format Selection submenu")
        try expect(staleMenu.items.map(\.title) == ["Plain Text", "Heading 1", "Heading 2", "Heading 3", "", "Bulleted List", "Numbered List"], "Native submenu contains the recovered paragraph choices and separator")
        let staleItem = staleMenu.items[1]
        text.setSelectedRange(NSRange(location: 1, length: 2)); first.formatting.selectionChanged()
        let unchanged = session.document.body
        NSApp.sendAction(staleItem.action!, to: staleItem.target, from: staleItem)
        try expectPublished(session.document.body == unchanged, "A retained old submenu cannot format a different native selection")
        _ = window.makeFirstResponder(text); first.formatting.selection.present()
        try session.updateTitle("Another editor changed the title", replacing: session.document.title)
        try expect(!first.formatting.isPresentingMenu, "Another document revision retires selection formatting")
        first.formatting.selection.present(focus: true)
        let keyBar = try require(window.firstResponder as? NoteSelectionBar, "Explicit native selection keyboard entry")
        func selectionKey(_ code: UInt16) throws -> NSEvent {
            try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code), "Native selection key")
        }
        keyBar.keyDown(with: try selectionKey(124)); keyBar.keyDown(with: try selectionKey(124))
        try expect(keyBar.selectedIndex == 1, "Keyboard entry moves only optional original control selection")
        let beforeKeyboard = session.document.body, keyboardRanges = text.selectedRanges
        text.localUndo.beginUndoGrouping(); keyBar.keyDown(with: try selectionKey(49)); text.localUndo.endUndoGrouping()
        let renewedKeyBar = try require(window.firstResponder as? NoteSelectionBar, "Keyboard format retains native menu responder")
        try expect(renewedKeyBar !== keyBar && renewedKeyBar.selectedIndex == 1 && text.selectedRanges == keyboardRanges, "Successful keyboard format re-admits current range and retains chosen control focus")
        try expectPublished(session.document.body != beforeKeyboard, "Original keyboard action publishes real formatting")
        text.undo(nil); try drainPublications()
        try expect(session.document.body == beforeKeyboard && text.selectedRanges == keyboardRanges, "Keyboard formatting restores original ranges and text with real native Undo")
        first.formatting.selection.present()
        first.formatting.retire()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        try expect(!first.formatting.isPresentingMenu, "Retirement invalidates queued selection work")
        first.findInDocument()
        try expect(text.enclosingScrollView?.isFindBarVisible == true, "Note Find opens original native text finder")
        window.contentView = nil

        let multiSession = try store.create()
        let multiEditor = try makeEditor(directory: directory, documentID: multiSession.document.id)
        multiEditor.loadView(); window.contentView = multiEditor.view
        multiEditor.view.frame = NSRect(x: 0, y: 0, width: 340, height: 600); multiEditor.view.layoutSubtreeIfNeeded()
        let multi = multiEditor.text
        multi.localUndo.groupsByEvent = false
        multi.localUndo.beginUndoGrouping(); multi.insertText("First 👩🏽‍💻 line\nSecond untouched\nThird line", replacementRange: NSRange(location: 0, length: 0)); multi.localUndo.endUndoGrouping()
        _ = window.makeFirstResponder(multi)
        let source = multi.string as NSString
        let ranges = [source.range(of: "First"), source.range(of: "Third")]
        multi.selectedRanges = ranges.map(NSValue.init(range:))
        try drainPublications()
        let multiBefore = multiSession.document.body
        multiEditor.formatting.selection.present()
        try expect(multiEditor.formatting.selection.isPresenting, "Discontiguous native selection has one actual menu owner")
        multi.localUndo.beginUndoGrouping(); multiEditor.formatting.selection.perform(.bold); multi.localUndo.endUndoGrouping()
        try expect(multi.hasEmphasis(.bold, ranges: ranges), "Selection action formats all native ranges")
        let middle = source.range(of: "Second")
        try expect(!multi.hasEmphasis(.bold, ranges: [middle]), "Unselected content between ranges is untouched")
        try expectPublished(multi.selectedRanges.map(\.rangeValue) == ranges && multiSession.document.revision > 0, "Multi-range formatting retains selection and persists")
        multi.undo(nil)
        try expectPublished(multiSession.document.body == multiBefore && multi.selectedRanges.map(\.rangeValue) == ranges, "One Undo restores the whole multi-range action")
        multiEditor.formatting.selection.present()
        let paragraphMenu = try require(multiEditor.formatting.selection.makeParagraphMenu(), "Multi-range paragraph menu")
        try expect(paragraphMenu.items[0].state == .on, "Uniform actual paragraph state is checked")
        let heading = paragraphMenu.items[2]
        multi.localUndo.beginUndoGrouping(); NSApp.sendAction(heading.action!, to: heading.target, from: heading); multi.localUndo.endUndoGrouping()
        let styled = multi.attributedString()
        try expect(EaselParagraphEditing.kind(styled.attributes(at: ranges[0].location, effectiveRange: nil)) == .heading2 && EaselParagraphEditing.kind(styled.attributes(at: ranges[1].location, effectiveRange: nil)) == .heading2, "Native paragraph submenu updates both selected paragraphs")
        try expect(EaselParagraphEditing.kind(styled.attributes(at: middle.location, effectiveRange: nil)) == .text, "Disjoint paragraph formatting preserves the middle paragraph")
        multi.undo(nil)
        try expectPublished(multiSession.document.body == multiBefore && multi.selectedRanges.map(\.rangeValue) == ranges, "Paragraph action Undo restores all original selection ranges")
        multiEditor.formatting.selection.present()
        let lists = try require(multiEditor.formatting.selection.makeParagraphMenu(), "List submenu")
        multi.localUndo.beginUndoGrouping(); NSApp.sendAction(lists.items[6].action!, to: lists.items[6].target, from: lists.items[6]); multi.localUndo.endUndoGrouping()
        let afterRanges = multi.selectedRanges.map(\.rangeValue)
        try expect(afterRanges.count == 2 && (multi.string as NSString).substring(with: afterRanges[0]) == "First" && (multi.string as NSString).substring(with: afterRanges[1]) == "Third", "Marker insertion maps every original UTF-16 selection")
        multi.undo(nil)
        try expectPublished(multiSession.document.body == multiBefore, "List transformation is one durable Undo")
        multi.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0))]
        try expectPublished(NoteSelectionTarget(text: multi, document: multiSession.document) == nil, "Caret-only selection never opens selection menu")
        let whitespace = source.range(of: " ")
        multi.setSelectedRange(whitespace)
        try expectPublished(NoteSelectionTarget(text: multi, document: multiSession.document) == nil, "Whitespace-only selection is excluded")
        multi.textStorage?.setAttributedString(NSAttributedString(string: "👋", attributes: [.font: NSFont.systemFont(ofSize: 15)])); multi.setSelectedRange(NSRange(location: 0, length: 1))
        try expectPublished(NoteSelectionTarget(text: multi, document: multiSession.document) == nil, "A partial UTF-16 surrogate cannot become a menu target")
        multi.textStorage?.setAttributedString(NSAttributedString(string: "\u{fffc}", attributes: [.font: NSFont.systemFont(ofSize: 15)])); multi.setSelectedRange(NSRange(location: 0, length: 1))
        try expectPublished(NoteSelectionTarget(text: multi, document: multiSession.document) == nil, "A sole attachment replacement character is excluded")
        window.contentView = nil

        let refusing = EaselStyledTextView(frame: .zero)
        let unsupported = NSMutableAttributedString(string: "good bad", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        unsupported.addAttribute(NSAttributedString.Key("UnsupportedNoteAttribute"), value: "unsupported", range: NSRange(location: 5, length: 3))
        refusing.textStorage?.setAttributedString(unsupported)
        refusing.selectedRanges = [NSValue(range: NSRange(location: 0, length: 4)), NSValue(range: NSRange(location: 5, length: 3))]
        var refusal = false; refusing.onClipboardError = { _ in refusal = true }
        refusing.toggle(.bold, ranges: refusing.selectedRanges.map(\.rangeValue))
        try expect(refusal && refusing.attributedString().isEqual(to: unsupported) && !refusing.localUndo.canUndo, "Multi-range codec refusal is atomic")
        try expect(!EaselStyledTextView.validFormattingRanges([NSRange(location: 0, length: 3), NSRange(location: 2, length: 2)], length: 10), "Overlapping target ranges are refused")
        try expect(!EaselStyledTextView.validFormattingRanges([NSRange(location: Int.max, length: 2)], length: 10), "Invalid range bounds are checked before arithmetic")

        let wrapped = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 900))
        wrapped.textContainer?.widthTracksTextView = true
        wrapped.textContainer?.containerSize = NSSize(width: 120, height: 900)
        wrapped.textStorage?.setAttributedString(NSAttributedString(string: "Unicode 👩🏽‍💻 paragraph wraps across several lines.\nSecond\n", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        let firstParagraph = try require(NoteParagraphGeometry.target(in: wrapped, containing: 2), "Wrapped layout")
        try expect(firstParagraph.bounds.height > firstParagraph.firstLine.height, "Gutter range spans actual wrapped paragraph")
        let fromLastLine = try require(NoteParagraphGeometry.target(in: wrapped, at: NSPoint(x: 7, y: firstParagraph.bounds.maxY - 2)), "Wrapped point target")
        try expect(fromLastLine.range == firstParagraph.range, "Hovering a later visual line retains original paragraph identity")
        try expect(NoteParagraphGeometry.target(in: wrapped, at: NSPoint(x: 7, y: 800)) == nil, "Empty document space cannot target the last paragraph")
        let trailing = try require(NoteParagraphGeometry.target(in: wrapped, containing: wrapped.string.utf16.count), "Trailing empty paragraph")
        try expect(trailing.range.length == 0 && trailing.firstLine.height > 0, "Final empty paragraph has real insertion geometry")
        try expect(NoteParagraphGeometry.target(in: wrapped, containing: -1) == nil, "Reject invalid character index")


        let keySession = try store.create()
        try keySession.updateTitle("Head 👩🏽‍💻 tail", replacing: keySession.document.title)
        let keyboard = try makeEditor(directory: directory, documentID: keySession.document.id)
        let peer = try makeEditor(directory: directory, documentID: keySession.document.id)
        keyboard.loadView(); peer.loadView(); window.contentView = keyboard.view
        keyboard.view.frame = NSRect(x: 0, y: 0, width: 340, height: 600); keyboard.view.layoutSubtreeIfNeeded()
        let title = keyboard.titleText, body = keyboard.text
        title.localUndo.groupsByEvent = false; body.localUndo.groupsByEvent = false
        func command(_ selector: Selector, from input: NSTextView) -> Bool {
            title.localUndo.beginUndoGrouping(); body.localUndo.beginUndoGrouping()
            defer { title.localUndo.endUndoGrouping(); body.localUndo.endUndoGrouping() }
            return keyboard.textView(input, doCommandBy: selector)
        }
        body.localUndo.beginUndoGrouping(); body.insertText("Body\nNext", replacementRange: NSRange(location: 0, length: 0)); body.localUndo.endUndoGrouping()
        _ = window.makeFirstResponder(title); title.setSelectedRange(NSRange(location: 5, length: 0))
        let beforeTransfer = keySession.document
        try expect(command(#selector(NSResponder.insertNewline(_:)), from: title), "Title Return is consumed by the original editor")
        try expect(title.string == "Head " && body.string == "👩🏽‍💻 tail\nBody\nNext", "Return moves Unicode suffix from caret to body, before its existing content")
        try expectPublished(keySession.document.revision == beforeTransfer.revision + 1 && peer.titleText.string == "Head " && peer.text.string == body.string, "Paired title/body transfer is one durable publication to peers")
        try expect(window.firstResponder === body && body.selectedRange() == NSRange(location: 0, length: 0), "Return focuses body at zero")
        try expect(title.localUndo !== body.localUndo && title.localUndo.canUndo && body.localUndo.canUndo, "Title and body retain independent actual Undo managers")
        body.localUndo.undo()
        try expect(body.string == "Body\nNext" && title.string == "Head ", "Body Undo reverses only the body half, matching original separate Undo owners")
        title.localUndo.undo()
        try expectPublished(title.string == beforeTransfer.title && keySession.document.title == title.string, "Title Undo restores original suffix independently and persists")
        body.localUndo.redo(); title.localUndo.redo()
        try expect(body.string.hasPrefix("👩🏽‍💻 tail\n") && title.string == "Head ", "Both field-local Redo paths retain original transfers")
        _ = window.makeFirstResponder(title); title.setSelectedRange(NSRange(location: 2, length: 2))
        try expect(command(#selector(NSResponder.insertTab(_:)), from: title) && title.string == "Head " && window.firstResponder === body && body.selectedRange().location == 0, "Title Tab focuses body start without replacing selected title text")
        _ = window.makeFirstResponder(title); title.setSelectedRange(NSRange(location: 1, length: 0))
        try expect(!command(#selector(NSResponder.moveRight(_:)), from: title), "Ordinary title Right stays native inside text")
        title.setSelectedRange(NSRange(location: title.string.utf16.count, length: 0))
        try expect(command(#selector(NSResponder.moveRight(_:)), from: title) && window.firstResponder === body, "Title Right at end enters body")
        body.setSelectedRange(NSRange(location: 0, length: 0))
        try expect(command(#selector(NSResponder.moveLeft(_:)), from: body) && window.firstResponder === title && title.selectedRange().location == title.string.utf16.count, "Body Left at start enters title at its UTF-16 end")
        title.setSelectedRange(NSRange(location: 1, length: 3))
        try expect(command(#selector(NSResponder.cancelOperation(_:)), from: title) && title.selectedRange() == NSRange(location: 1, length: 0), "Title Escape collapses the current selection at its start")
        try expect(command(#selector(NSResponder.insertTabIgnoringFieldEditor(_:)), from: title) && title.string == "Head ", "Literal Tab command is consumed without title mutation")
        let titleBoard = NSPasteboard.withUniqueName(); defer { titleBoard.releaseGlobally() }
        titleBoard.setString("one\r\ntwo\nthree", forType: .string)
        title.localUndo.beginUndoGrouping(); let titlePaste = title.pasteTitle(from: titleBoard); title.localUndo.endUndoGrouping()
        try expect(titlePaste && title.string.contains("one  two three") && !title.string.contains("\n"), "Title paste uses native plain string and recovered per-newline spacing")
        try expect(title.readablePasteboardTypes == [.string], "Title does not advertise rich or image clipboard types")
        title.localUndo.undo()
        try expect(title.string == "Head ", "Title paste owns a real reversible native text edit")
        _ = window.makeFirstResponder(body); body.setSelectedRange(NSRange(location: 0, length: 0))
        try expect(NoteKeyboardEditing.hasDefaultTyping(body), "Default body typing is eligible for the recovered Backspace boundary")
        let mergedBefore = keySession.document
        try expect(command(#selector(NSResponder.deleteBackward(_:)), from: body), "Default body Backspace at zero is handled")
        try expect(title.string == "Head 👩🏽‍💻 tail" && body.string == "Body\nNext" && title.selectedRange() == NSRange(location: 5, length: 0), "Body first line joins title with caret at original boundary")
        try expectPublished(keySession.document.revision == mergedBefore.revision + 1, "Backspace merge persists title/body once")
        _ = window.makeFirstResponder(body); body.setSelectedRange(NSRange(location: 0, length: 0))
        body.typingAttributes[.underlineStyle] = 1
        try expect(!command(#selector(NSResponder.deleteBackward(_:)), from: body), "Explicit emphasis keeps the normal body-edit command")
        body.typingAttributes.removeValue(forKey: .underlineStyle)
        body.setSelectedRange(NSRange(location: 1, length: 2))
        try expect(!command(#selector(NSResponder.moveLeft(_:)), from: body), "Noncollapsed body selection keeps native Left")
        keyboard.formatting.retire()
        try expect(command(#selector(NSResponder.cancelOperation(_:)), from: body) && body.selectedRange() == NSRange(location: 1, length: 0), "Body Escape without a menu collapses body selection")
        body.setSelectedRange(NSRange(location: 1, length: 0))
        try expect(command(#selector(NSResponder.moveUp(_:)), from: body) && window.firstResponder === title, "Body Up from first visual line returns to title")
        _ = window.makeFirstResponder(body); body.setSelectedRange(NSRange(location: 6, length: 0))
        try expect(!command(#selector(NSResponder.moveUp(_:)), from: body), "Later body line keeps native Up")
        try expect(!command(#selector(NSResponder.insertNewline(_:)), from: body), "Body Return without a format menu stays native")
        try expect(!command(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), from: body), "Alternate body Return is not a Notes dispatcher selector")
        _ = window.makeFirstResponder(body)
        body.localUndo.beginUndoGrouping(); body.insertText("hello world", replacementRange: NSRange(location: 0, length: body.string.utf16.count)); body.localUndo.endUndoGrouping()
        body.setSelectedRange(NSRange(location: 8, length: 0))
        try expect(keyboard.textView(body, doCommandBy: #selector(NSResponder.moveToBeginningOfLine(_:))) && body.selectedRange() == NSRange(location: 5, length: 0), "Cmd-Left uses the recovered five-unit line prefix")
        body.setSelectedRange(NSRange(location: 8, length: 0))
        try expect(keyboard.textView(body, doCommandBy: #selector(NSResponder.moveToLeftEndOfLine(_:))) && body.selectedRange().location == 5, "moveToLeftEndOfLine shares that prefix caret")
        body.setSelectedRange(NSRange(location: 8, length: 0))
        try expect(keyboard.textView(body, doCommandBy: #selector(NSResponder.moveToBeginningOfParagraph(_:))) && body.selectedRange().location == 5, "moveToBeginningOfParagraph shares that prefix caret")
        try expect(!keyboard.textView(title, doCommandBy: #selector(NSResponder.moveToBeginningOfLine(_:))), "Title keeps native beginning-of-line")
        body.localUndo.undo()
        _ = window.makeFirstResponder(title); title.setSelectedRange(NSRange(location: 0, length: 0))
        title.localUndo.beginUndoGrouping()
        title.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0), replacementRange: title.selectedRange())
        let markedDocument = keySession.document
        try expect(title.hasMarkedText() && !command(#selector(NSResponder.insertNewline(_:)), from: title) && keySession.document == markedDocument, "IME owns Return during composition, with no transfer or draft publication")
        title.unmarkText(); title.didChangeText(); title.localUndo.endUndoGrouping()
        try expect(!title.hasMarkedText() && keySession.document.title == title.string, "Committed native title composition persists")
        window.componentKey = false
        try expect(!command(#selector(NSResponder.insertTab(_:)), from: title), "Inactive window cannot redirect the original responder")
        window.componentKey = true
        try expect(!command(#selector(NSResponder.moveDown(_:)), from: body), "A nonfocused field cannot move the real first responder")
        let keyFile = directory.appendingPathComponent(keySession.document.id.uuidString.lowercased() + ".json")
        let keyBytes = try Data(contentsOf: keyFile), durable = keySession.document
        try FileManager.default.removeItem(at: keyFile); try FileManager.default.createDirectory(at: keyFile, withIntermediateDirectories: false)
        title.setSelectedRange(NSRange(location: 0, length: 0))
        try expect(command(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), from: title), "Alternate Return uses the same original transfer")
        try expect(keySession.document == durable && title.string.isEmpty && !body.string.isEmpty && !keyboard.prepareToClose(), "Write failure retains both transfer drafts, publishes neither and refuses close")
        try FileManager.default.removeItem(at: keyFile); try keyBytes.write(to: keyFile)
        try expect(keyboard.prepareToClose() && keySession.document.title.isEmpty && keySession.document.body.text == body.string, "Retry commits the original paired draft together")
        _ = window.makeFirstResponder(nil); keyboard.focusContent()
        try expect(window.firstResponder === title, "A blank title receives initial forwarded focus")
        let line = NoteKeyboardEditing.firstLine("α\r\nβ")
        try expect(line.text == "α" && line.removal == NSRange(location: 0, length: 3), "Current native CRLF is consumed as one line boundary")
        try expect(NoteKeyboardEditing.beginningOfLineCaret(in: "", selection: NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 0), "Empty body beginning-of-line stays at zero")
        try expect(NoteKeyboardEditing.beginningOfLineCaret(in: "hi", selection: NSRange(location: 1, length: 0)) == NSRange(location: 0, length: 0), "A line shorter than five UTF-16 units keeps the line start")
        try expect(NoteKeyboardEditing.beginningOfLineCaret(in: "hello world", selection: NSRange(location: 8, length: 0)) == NSRange(location: 5, length: 0), "A long line places the caret after five composed units from line start")
        try expect(NoteKeyboardEditing.beginningOfLineCaret(in: "ab\ncd", selection: NSRange(location: 0, length: 0)) == NSRange(location: 4, length: 0), "Five-unit prefix is measured against the whole string, so it may cross a newline")
        try expect(NoteKeyboardEditing.beginningOfLineCaret(in: "hello world", selection: NSRange(location: 8, length: 2)) == NSRange(location: 5, length: 0), "Beginning-of-line collapses any original selection")
        try expect(NoteKeyboardEditing.isBeginningOfLine(#selector(NSResponder.moveToBeginningOfLine(_:)))
            && NoteKeyboardEditing.isBeginningOfLine(#selector(NSResponder.moveToLeftEndOfLine(_:)))
            && NoteKeyboardEditing.isBeginningOfLine(#selector(NSResponder.moveToBeginningOfParagraph(_:)))
            && !NoteKeyboardEditing.isBeginningOfLine(#selector(NSResponder.moveToBeginningOfDocument(_:))),
                   "Only the three recovered body dispatcher selectors share the line-prefix caret")
        try expect(NoteKeyboardEditing.titleSuffix("👋tail", selection: NSRange(location: 1, length: 0)) == nil, "Partial UTF-16 surrogate cannot become a transfer range")
        window.contentView = nil
        try store.delete(session.document.id, expectedRevision: session.document.revision)
        try expect(!first.text.isEditable && !second.text.isEditable && first.prepareToClose(), "Tombstone disables all original editors without resurrection")
        let presentationSession = try store.create(), presentation = try makeEditor(directory: directory, documentID: presentationSession.document.id)
        presentation.loadView(); window.contentView = presentation.view
        let nativeTitle = presentation.titleText, nativeBody = presentation.text
        let initialTitle = presentationSession.document.title
        nativeTitle.localUndo.groupsByEvent = false; nativeBody.localUndo.groupsByEvent = false
        _ = window.makeFirstResponder(nativeTitle)
        nativeTitle.localUndo.beginUndoGrouping(); nativeTitle.insertText("A long original title that must wrap in a narrow split pane", replacementRange: NSRange(location: 0, length: 0)); nativeTitle.localUndo.endUndoGrouping()
        _ = window.makeFirstResponder(nativeBody)
        nativeBody.localUndo.beginUndoGrouping(); nativeBody.insertText("Original body 👋\nLast line\n", replacementRange: NSRange(location: 0, length: 0)); nativeBody.localUndo.endUndoGrouping()
        nativeBody.setSelectedRange(NSRange(location: 2, length: 5))
        try drainPublications()
        let originalDocument = presentationSession.document, originalNativeBody = nativeBody.attributedString(), originalSelected = nativeBody.selectedRanges
        let nativeLayout = try require(nativeTitle.superview?.superview?.superview as? NoteDocumentLayout, "Original title is in the document's constrained column")
        presentation.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800); presentation.view.layoutSubtreeIfNeeded()
        let wideTitle = nativeTitle.convert(nativeTitle.bounds, to: nativeLayout), wideBody = nativeBody.convert(nativeBody.bounds, to: nativeLayout)
        try expect(abs(nativeLayout.column.frame.width - 900) < 0.5 && abs(wideTitle.width - 700) < 0.5, "Wide document uses actual 900 column and 700 title/body width")
        try expect(abs(wideTitle.minY - 64) < 0.5 && abs(wideBody.minY - wideTitle.maxY - 16) < 0.5, "Recovered top and title/body spacing are actual native frames")
        try expect(abs(nativeLayout.bounds.maxY - wideBody.maxY - 64) < 0.5, "Original bottom padding and full-height document")
        try expect(nativeTitle.typingAttributes[.paragraphStyle].flatMap { $0 as? NSParagraphStyle }?.lineHeightMultiple == 1.25, "Recovered title paragraph metrics remain native typing attributes")
        for width in [500.0, 340.0, 240.0, 100.0] {
            presentation.view.frame.size.width = width; presentation.view.needsLayout = true; presentation.view.layoutSubtreeIfNeeded()
            let titleFrame = nativeTitle.convert(nativeTitle.bounds, to: nativeLayout), bodyFrame = nativeBody.convert(nativeBody.bounds, to: nativeLayout)
            try expect(titleFrame.minX >= 19.5 && titleFrame.maxX <= nativeLayout.bounds.width - 19.5 && titleFrame.width > 0, "Soft width yields inside narrow pane instead of overflowing")
            try expect(abs(titleFrame.width - bodyFrame.width) < 0.5 && abs(bodyFrame.minY - titleFrame.maxY - 16) < 0.5, "Both fields retain the same column and genuine measured title gap")
            try expect(titleFrame.height >= wideTitle.height, "Wrapped title grows from native glyph measurement")
        }
        try expectPublished(presentationSession.document == originalDocument && nativeBody.attributedString().isEqual(to: originalNativeBody) && nativeBody.selectedRanges == originalSelected, "Responsive layout preserves original durable body, attributes and selection")
        try expect(nativeTitle.localUndo.canUndo && nativeBody.localUndo.canUndo, "Layout preserves both native Undo owners")
        _ = window.makeFirstResponder(nativeTitle)
        nativeTitle.localUndo.undo()
        try expectPublished(presentationSession.document.title == initialTitle && nativeBody.attributedString().isEqual(to: originalNativeBody), "Title Undo still targets only original title after reflow")
        nativeTitle.localUndo.redo()
        try expectPublished(presentationSession.document.title == originalDocument.title, "Title Redo retains original local session after reflow")
        let appearanceBytes = try Data(contentsOf: directory.appendingPathComponent(presentationSession.document.id.uuidString.lowercased() + ".json"))
        let appearanceBody = nativeBody.attributedString(), appearanceSelection = nativeBody.selectedRanges
        let appearanceRevision = presentationSession.document.revision, appearanceUndo = nativeBody.localUndo.canUndo
        try expect(presentation.view.appearance == nil && presentation.view is NoteCanvasView && !presentation.view.isOpaque, "Standalone document inherits owner appearance without forcing Aqua and stays translucent over the Space underlay")
        let canvas = try require(presentation.view as? NoteCanvasView, "Original Note canvas")
        canvas.inheritSpaceContentAppearance(dark)
        try expect(canvas.appearance == dark && nativeBody.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, "Document host applies Space contentOverBackgroundAppearance DarkAqua")
        try expect(rgba(NoteDocumentAppearance.backgroundColor, under: canvas.effectiveAppearance) == "#00000080", "Inherited dark appearance still resolves named NotesBackground, not a Space palette fill")
        try expect(nativeBody.attributedString().isEqual(to: appearanceBody) && nativeBody.selectedRanges == appearanceSelection && nativeBody.localUndo.canUndo == appearanceUndo, "Appearance never rewrites original attributed text, selection or Undo")
        try expectPublished(presentationSession.document.revision == appearanceRevision && Data(contentsOf: directory.appendingPathComponent(presentationSession.document.id.uuidString.lowercased() + ".json")) == appearanceBytes, "Appearance changes never publish a local save")
        canvas.inheritSpaceContentAppearance(nil)
        try expect(canvas.appearance == nil, "Absent contentOverBackgroundAppearance clears the local override")
        let nativeScroll = try require(nativeBody.enclosingScrollView, "Both original fields remain in the native scroll view")
        try expect(!nativeScroll.automaticallyAdjustsContentInsets && nativeScroll.contentInsets.top == 0 && !nativeScroll.drawsBackground && !nativeScroll.contentView.drawsBackground, "Recovered transparent scroll and zero automatic insets")
        let loadFailure = NoteLoadErrorView(error: NoteError.deleted); window.contentView = loadFailure
        loadFailure.frame = NSRect(x: 0, y: 0, width: 700, height: 500); loadFailure.layoutSubtreeIfNeeded()
        try expect(loadFailure.appearance == nil && !loadFailure.isOpaque, "Load failure retains the same adaptive translucent canvas owner")
        loadFailure.inheritSpaceContentAppearance(dark)
        try expect(loadFailure.appearance == dark && loadFailure.heading.font == NoteDocumentAppearance.titleFont, "Load-error title keeps recovered typography under Space content appearance")
        loadFailure.inheritSpaceContentAppearance(nil)
        try expect(loadFailure.appearance == nil, "Load-error canvas restores inherited appearance when the Space override is absent")
        try expect(loadFailure.heading.stringValue == "Can't load this note" && loadFailure.detail.stringValue == NoteError.deleted.localizedDescription, "Load error keeps original document presentation with truthful local error")
        try expect(loadFailure.accessibilityRole() == .group && loadFailure.accessibilityLabel() == "Can't load this note", "Load-error group uses the recovered heading as its accessibility name")
        try expect(loadFailure.heading.accessibilityRole() == .staticText && loadFailure.heading.accessibilityLabel() == "Can't load this note", "Load-error heading remains a named static text")
        try expect(loadFailure.heading.alignmentRect(forFrame: loadFailure.heading.frame).width <= 500.5 && loadFailure.heading.alignment == .center && loadFailure.detail.isSelectable, "Load failure is centered, bounded and copyable")
        window.contentView = presentation.view
        let layoutFile = directory.appendingPathComponent(presentationSession.document.id.uuidString.lowercased() + ".json")
        let layoutBytes = try Data(contentsOf: layoutFile)
        try FileManager.default.removeItem(at: layoutFile); try FileManager.default.createDirectory(at: layoutFile, withIntermediateDirectories: false)
        _ = window.makeFirstResponder(nativeBody)
        nativeBody.localUndo.beginUndoGrouping(); nativeBody.insertText(" failed draft", replacementRange: NSRange(location: nativeBody.string.utf16.count, length: 0)); nativeBody.localUndo.endUndoGrouping()
        try drainPublications()
        presentation.view.frame.size.width = 180; presentation.view.needsLayout = true; presentation.view.layoutSubtreeIfNeeded()
        let failureButtons = buttons(in: presentation.view).filter { !$0.isHidden && ["Retry", "Discard Draft"].contains($0.title) }
        try expect(failureButtons.count == 2 && failureButtons.allSatisfy { $0.frame.minX >= 0 && $0.frame.maxX <= 180 }, "Narrow split save-failure actions remain inside the original pane")
        try expect(failureButtons.map { $0.accessibilityLabel() ?? "" } == ["Retry", "Discard Draft"], "Footer recovery actions expose their native titles to accessibility")
        try expect(presentation.titleText.nextKeyView === presentation.text, "Title tabs into the original body")
        try expect(presentation.text.nextKeyView === failureButtons[0] && failureButtons[0].nextKeyView === failureButtons[1] && failureButtons[1].nextKeyView !== presentation.titleText, "Narrow save-failure Retry/Discard stay in the original chain without closing a pane-local key loop")
        try expect(!presentation.prepareToClose() && nativeBody.isEditable && nativeBody.string.hasSuffix(" failed draft"), "Save failure keeps the original editable draft rather than installing a load-error view")
        try FileManager.default.removeItem(at: layoutFile); try layoutBytes.write(to: layoutFile)
        try expect(presentation.prepareToClose(), "Responsive failure footer retains the original retryable save owner")
        let displayedTitle = nativeTitle.string, displayedBody = nativeBody.attributedString(), displayedSelection = nativeBody.selectedRanges
        try store.delete(presentationSession.document.id, expectedRevision: presentationSession.document.revision)
        presentation.view.layoutSubtreeIfNeeded()
        try expect(!nativeTitle.isEditable && !nativeBody.isEditable && nativeTitle.isSelectable && nativeBody.isSelectable && !presentation.formatting.isPresentingMenu, "Read-only tombstone preserves original selectable text and retires controls")
        try expect(nativeTitle.string == displayedTitle && nativeBody.attributedString().isEqual(to: displayedBody) && nativeBody.selectedRanges == displayedSelection, "Durable tombstone never replaces original copyable text with cleared storage fields")
        window.contentView = nil
        let styledSession = try store.create()
        let untouched = try Data(contentsOf: directory.appendingPathComponent(styledSession.document.id.uuidString.lowercased() + ".json"))
        let styledController = try makeEditor(directory: directory, documentID: styledSession.document.id)
        styledController.loadView()
        let bodyEditor = styledController.text
        bodyEditor.localUndo.groupsByEvent = false
        try expect(NoteKeyboardEditing.hasDefaultTyping(bodyEditor), "Recovered body default admits original keyboard join gate")
        let previousTyping = bodyEditor.typingAttributes
        bodyEditor.typingAttributes = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: EaselTextAppearance.color("#252525")]
        try expect(!NoteKeyboardEditing.hasDefaultTyping(bodyEditor), "Legacy explicit15-point formatting is not silently treated as new Notes default")
        bodyEditor.typingAttributes = previousTyping
        let defaultFont = try require(bodyEditor.typingAttributes[.font] as? NSFont, "Native Notes typing font")
        try expect(defaultFont.fontName == "Nunito-Regular" && defaultFont.pointSize == 18, "Empty Note uses bundled original body font at18")
        let defaultParagraph = try require(bodyEditor.typingAttributes[.paragraphStyle] as? NSParagraphStyle, "Native Notes typing paragraph")
        try expect(defaultParagraph.lineHeightMultiple == 1.25 && defaultParagraph.paragraphSpacingBefore == 4 && defaultParagraph.paragraphSpacing == 8, "Body constructor paragraph defaults survive empty load")
        try expect(bodyEditor.insertionPointColor == NoteDocumentAppearance.cursorColor && bodyEditor.selectedTextAttributes[.backgroundColor] as? NSColor == NoteDocumentAppearance.selectionColor, "Native cursor and selection use recovered named style")
        try expect(bodyEditor.linkTextAttributes?[.foregroundColor] as? NSColor == NoteDocumentAppearance.linkColor && bodyEditor.usesFontPanel && bodyEditor.isContinuousSpellCheckingEnabled, "Native link display and supported editing configuration are attached")
        try expectPublished(Data(contentsOf: directory.appendingPathComponent(styledSession.document.id.uuidString.lowercased() + ".json")) == untouched, "Opening styled empty Note never rewrites durable document")
        bodyEditor.localUndo.beginUndoGrouping(); bodyEditor.insertText("Default body", replacementRange: NSRange(location: 0, length: 0)); bodyEditor.localUndo.endUndoGrouping()
        try expectPublished(styledSession.document.body.richText.runs.first?.attributes.font.name == "Nunito-Regular" && styledSession.document.body.richText.runs.first?.attributes.font.size == 18, "First real edit persists authored Nunito18")
        bodyEditor.setSelectedRange(NSRange(location: 0, length: bodyEditor.string.utf16.count))
        bodyEditor.localUndo.beginUndoGrouping(); bodyEditor.toggle(.bold); bodyEditor.toggle(.italic); bodyEditor.localUndo.endUndoGrouping()
        let boldItalic = try require(bodyEditor.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont, "Emphasis font")
        try expect(boldItalic.familyName == "Nunito" && boldItalic.fontDescriptor.symbolicTraits.contains([.bold, .italic]), "Actual bundled family supports both native emphasis traits")
        try drainPublications()
        let emphasized = styledSession.document.body
        let styledReopen = try makeEditor(directory: directory, documentID: styledSession.document.id); styledReopen.loadView()
        styledReopen.view.appearance = dark
        let reopenedInk = try require(styledReopen.text.attributedString().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, "Real reopened body ink")
        try expect(emphasized.richText.runs.allSatisfy { $0.attributes.semanticInk == .noteBody } && rgba(reopenedInk, under: dark) == "#FFFFFFFF", "Actual saved/reopened/emphasized default body stays semantic in dark appearance")

        try expect(EaselRichTextCodec.snapshot(styledReopen.text.attributedString()) == emphasized.richText, "Reopen preserves original authored Nunito emphasis")
        bodyEditor.localUndo.beginUndoGrouping(); bodyEditor.changeParagraph(.heading1); bodyEditor.changeParagraph(.text); bodyEditor.localUndo.endUndoGrouping()
        let restoredBody = try require(bodyEditor.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont, "Restored body font")
        try expect(restoredBody.pointSize == 18 && restoredBody.familyName == "Nunito" && restoredBody.fontDescriptor.symbolicTraits.contains([.bold, .italic]), "Text action returns to Notes18 while preserving authored family/emphasis")
        bodyEditor.localUndo.beginUndoGrouping(); bodyEditor.changeParagraph(.heading1); bodyEditor.localUndo.endUndoGrouping()
        bodyEditor.setSelectedRange(NSRange(location: bodyEditor.string.utf16.count, length: 0))
        bodyEditor.localUndo.beginUndoGrouping(); bodyEditor.insertNewline(nil); bodyEditor.localUndo.endUndoGrouping()
        try expect((bodyEditor.typingAttributes[.font] as? NSFont)?.pointSize == 18 && EaselParagraphEditing.kind(bodyEditor.typingAttributes) == .text, "Heading Return enters original Notes body size")
        let custom = NSAttributedString(string: "authored link", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 27, weight: .regular), .foregroundColor: NSColor.red, .link: URL(string: "https://example.invalid/")!, .paragraphStyle: NSParagraphStyle.default])
        try drainPublications()
        var customBody = styledSession.document.body; customBody.text = custom.string; customBody.richText = try EaselRichTextCodec.snapshot(custom)
        try styledSession.updateBody(customBody, replacing: styledSession.document.body)
        let customEditor = try makeEditor(directory: directory, documentID: styledSession.document.id); customEditor.loadView()
        try expect(EaselRichTextCodec.snapshot(customEditor.text.attributedString()) == customBody.richText, "Display defaults preserve every explicit authored font/ink/link/paragraph run")
        try expect((customEditor.text.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 27, "Existing authored typography is not migrated")
        let bodyError = NoteLoadErrorView(error: NoteError.missing)
        try expect(bodyError.detail.font?.fontName == "Nunito-Regular" && bodyError.detail.font?.pointSize == 18, "Original load subtitle shares actual body font getter")
        for name in ["Nunito-Regular", "Nunito-Bold", "Nunito-Italic", "Nunito-BoldItalic"] {
            let font = try require(NSFont(name: name, size: 18), "Bundled family face " + name)
            let license = CTFontCopyName(font as CTFont, kCTFontLicenseNameKey) as String? ?? ""
            try expect(license.localizedCaseInsensitiveContains("Open Font License"), "Used body family retains embedded OFL license")
        }
        let hintSession = try store.create()
        try hintSession.updateTitle("", replacing: hintSession.document.title)
        let hintEditor = try makeEditor(directory: directory, documentID: hintSession.document.id)
        hintEditor.loadView(); window.contentView = hintEditor.view
        hintEditor.view.frame = NSRect(x: 0, y: 0, width: 600, height: 500); hintEditor.view.layoutSubtreeIfNeeded()
        let hint = hintEditor.titleText, emptyDocument = hintSession.document
        hint.localUndo.groupsByEvent = false
        let placeholder = try require(hint.placeholderAttributedString, "Original title constructor installs a real attributed placeholder")
        try expect(placeholder.string == "Title", "Recovered localized English placeholder is distinct from the saved-tab fallback")
        try expect((placeholder.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Nunito-ExtraBold" && (placeholder.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 34, "Hint uses original title typography")
        let hintParagraph = try require(placeholder.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle, "Attributed hint has actual paragraph metrics")
        try expect(hintParagraph.lineHeightMultiple == 1.25 && hintParagraph.paragraphSpacingBefore == 4 && hintParagraph.paragraphSpacing == 8, "Native placeholder inherits original complete title metrics")
        try expect(hint.accessibilityPlaceholderValue() == "Title" && hint.string.isEmpty, "Accessibility hint stays separate from actual empty native text")
        try expect(hint.accessibilityRole() == .textArea && hint.accessibilityLabel() == "Title", "Title field uses the recovered placeholder as its accessibility name")
        try expect(hintEditor.text.accessibilityRole() == .textArea && hintEditor.text.accessibilityLabel() != "Note body", "Body remains a native text area without an invented Notes label")
        try expect(hint.insertionPointColor.isEqual(NoteDocumentAppearance.cursorColor) && (hint.selectedTextAttributes[.backgroundColor] as? NSColor)?.isEqual(NoteDocumentAppearance.selectionColor) == true, "Title constructor applies original cursor/selection styles")
        func hintPixels() throws -> Int {
            hint.needsDisplay = true
            let bitmap = try require(hint.bitmapImageRepForCachingDisplay(in: hint.bounds), "Native title bitmap")
            hint.cacheDisplay(in: hint.bounds, to: bitmap)
            var pixels = 0
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.05,
                   color.blueComponent > color.redComponent + 0.08, color.blueComponent > color.greenComponent + 0.08 { pixels += 1 }
            } }
            return pixels
        }
        window.componentKey = false
        let emptyPixels = try hintPixels()
        try expect(emptyPixels > 0, "AppKit itself draws exported placeholder on original empty title")
        hint.placeholderAttributedString = nil
        try expect(try hintPixels() == 0 && hint.accessibilityPlaceholderValue() == nil, "Removing hint removes its native pixels and accessibility hint without text mutation")
        hint.placeholderAttributedString = placeholder
        _ = window.makeFirstResponder(hint)
        try expect(try hintPixels() == emptyPixels, "Native focus does not suppress empty title placeholder")
        try expectPublished(hintSession.document == emptyDocument && !hint.localUndo.canUndo, "Drawing, focus and placeholder changes do not save or create Undo")
        hint.localUndo.beginUndoGrouping()
        hint.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 0))
        let markedPixels = try hintPixels()
        hint.placeholderAttributedString = nil
        try expect(hint.hasMarkedText() && markedPixels == (try hintPixels()) && hintSession.document == emptyDocument, "Native marked text suppresses hint and remains an unpublished draft")
        hint.placeholderAttributedString = placeholder
        hint.unmarkText(); hint.didChangeText(); hint.localUndo.endUndoGrouping()
        try expectPublished(hintSession.document.title == "漢", "IME commit saves actual title without placeholder text")
        hint.localUndo.undo()
        try expectPublished(hint.string.isEmpty && hintSession.document.title.isEmpty && (try hintPixels()) > 0, "Native title Undo restores empty title and placeholder")
        hint.localUndo.redo()
        let authoredPixels = try hintPixels()
        hint.placeholderAttributedString = nil
        try expect(hint.string == "漢" && authoredPixels == (try hintPixels()), "Redo restores authored title, with no overlaid placeholder")
        hint.placeholderAttributedString = placeholder
        hint.localUndo.undo()
        let hintFile = directory.appendingPathComponent(hintSession.document.id.uuidString.lowercased() + ".json")
        let hintBytes = try Data(contentsOf: hintFile)
        try FileManager.default.removeItem(at: hintFile); try FileManager.default.createDirectory(at: hintFile, withIntermediateDirectories: false)
        hint.localUndo.beginUndoGrouping(); hint.insertText("draft", replacementRange: NSRange(location: 0, length: 0)); hint.localUndo.endUndoGrouping()
        let draftPixels = try hintPixels(); hint.placeholderAttributedString = nil
        try expect(hintSession.document.title.isEmpty && hint.string == "draft" && draftPixels == (try hintPixels()) && !hintEditor.prepareToClose(), "Save failure retains visible title draft without showing hint or saving it")
        hint.placeholderAttributedString = placeholder
        try FileManager.default.removeItem(at: hintFile); try hintBytes.write(to: hintFile)
        try expect(hintEditor.prepareToClose() && hintSession.document.title == "draft", "Retry publishes actual retained title draft")
        hint.localUndo.beginUndoGrouping(); hint.insertText("", replacementRange: NSRange(location: 0, length: hint.string.utf16.count)); hint.localUndo.endUndoGrouping()
        try store.delete(hintSession.document.id, expectedRevision: hintSession.document.revision)
        try expect(!hint.isEditable && hint.string.isEmpty && (try hintPixels()) > 0, "Empty read-only tombstone retains native hint without resurrecting document")
        do {
        let gutterSession = try store.create()
        let gutterEditor = try makeEditor(directory: directory, documentID: gutterSession.document.id)
        gutterEditor.loadView()
        let gutterWindow = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        gutterWindow.isReleasedWhenClosed = false; gutterWindow.contentView = gutterEditor.view
        gutterEditor.view.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        let body = gutterEditor.text
        let host = try require(gutterEditor.formatting, "Original formatting owner")
        body.localUndo.groupsByEvent = false; body.localUndo.beginUndoGrouping()
        body.insertText("Paragraph one\nParagraph two\n", replacementRange: body.selectedRange()); body.localUndo.endUndoGrouping()
        body.setSelectedRange(NSRange(location: 0, length: 0))
        try drainPublications()
        gutterEditor.view.layoutSubtreeIfNeeded(); host.updateTrackingAreas()
        let control = try require(host.subviews.compactMap { $0 as? NoteGutterButton }.first, "Actual native gutter control")
        let ownedArea = try require(host.trackingAreas.first, "Original host tracking area")
        let unrelatedArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways], owner: nil)
        func moveGutter(to index: Int) throws {
            let paragraph = try require(NoteParagraphGeometry.target(in: body, containing: index), "Native pointer target")
            let point = body.convert(NSPoint(x: paragraph.firstLine.minX + 2, y: paragraph.firstLine.minY + 3), to: nil)
            let event = try require(NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: gutterWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0), "Native component pointer event")
            host.mouseMoved(with: event)

        }
        let enterTracking = NoteComponentTrackingEvent(); enterTracking.area = ownedArea
        let foreignTracking = NoteComponentTrackingEvent(); foreignTracking.area = unrelatedArea
        host.mouseEntered(with: enterTracking)
        try expect(control.isHidden, "Entry alone does not invent paragraph metadata")
        try moveGutter(to: 0)
        try expect(!control.isHidden && control.frame.size == NSSize(width: 42, height: 30), "Native move exposes recovered gutter size")
        let nativeInk = host.convert(gutterWindow.convertFromScreen(body.firstRect(forCharacterRange: NSRange(location: 0, length: 13), actualRange: nil)), from: nil)
        try expect(control.frame.maxX < nativeInk.minX && !control.showsPlus, "Gutter stays left of actual first-character geometry and text uses disclosure")
        try expect(control.contentOpacity == 0.33, "Idle original paragraph control is one-third opacity")
        host.mouseExited(with: foreignTracking)
        try expect(!control.isHidden, "Unrelated tracking exit cannot dismiss owned gutter")
        host.mouseExited(with: enterTracking)
        try expect(control.isHidden, "Owned exit hides the control")
        host.reconcileGeometry()
        try expect(control.isHidden, "Scroll/layout does not revive an exited control")
        host.mouseEntered(with: enterTracking)
        try expect(!control.isHidden, "Owned reentry restores retained valid paragraph metadata")
        control.updateTrackingAreas()
        let controlTracking = NoteComponentTrackingEvent(); controlTracking.area = control.trackingAreas.first { $0.options == [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect] }
        control.mouseEntered(with: controlTracking)
        try expect(control.hovered && control.contentOpacity == 1, "Only actual control hover reveals full-opacity glyph")
        let bitmap = try require(control.bitmapImageRepForCachingDisplay(in: control.bounds), "Actual gutter native bitmap")
        control.cacheDisplay(in: control.bounds, to: bitmap)
        let fill = try require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 3)?.usingColorSpace(.sRGB), "Native gutter hover pixels")
        let darkGutter = control.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        try expect(abs(fill.redComponent - (darkGutter ? 1 : 0.922)) < 0.03 && abs(fill.alphaComponent - (darkGutter ? 0.15 : 1)) < 0.03, "Recovered named hover fill reaches actual owning appearance: \(fill), dark=\(darkGutter)")
        control.mouseExited(with: controlTracking)
        try expect(!control.hovered && control.contentOpacity == 0.33, "Control exit restores idle rendering")
        let idleButton = NoteGutterButton()
        let idleImage = NSImage(size: idleButton.bounds.size, flipped: true) { rect in idleButton.draw(rect); return true }
        let idleBitmap = try require(idleImage.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)), "Native idle symbol pixels")
        var maximumInkAlpha: CGFloat = 0
        for y in 0..<idleBitmap.pixelsHigh { for x in 0..<idleBitmap.pixelsWide {
            maximumInkAlpha = max(maximumInkAlpha, idleBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
        } }
        try expect(maximumInkAlpha > 0.2 && maximumInkAlpha < 0.4, "Idle native plus pixels retain recovered opacity rather than opaque tint compositing")
        try drainPublications()
        let priorBody = gutterSession.document.body
        try moveGutter(to: 0)
        control.performClick(nil)
        try expectPublished(host.isPresentingMenu && body.selectedRange().location == 0 && gutterSession.document.body == priorBody && control.showsSelected, "Native button opens original range menu without changing body and marks displayAsSelected")
        try moveGutter(to: 14)
        try expect(body.selectedRange().location == 0, "Pointer movement cannot retarget an open paragraph menu")
        host.mouseExited(with: enterTracking)
        try expect(!control.isHidden && control.showsSelected, "Owned exit retains selected gutter fill for the visible paragraph menu")
        host.dismiss()
        try expect(!control.showsSelected, "Dismissing the paragraph menu clears displayAsSelected")
        try moveGutter(to: 14)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: gutterWindow)
        try expect(control.isHidden && !host.isPresentingMenu, "Hover-only ownership retires with exact window key loss")
        try moveGutter(to: 14); host.mouseExited(with: enterTracking)
        try gutterSession.updateTitle("Other window title", replacing: gutterSession.document.title)
        host.mouseEntered(with: enterTracking)
        try expect(control.isHidden, "A new durable revision revokes retained hover metadata")
        try moveGutter(to: body.string.utf16.count)
        try expect(control.showsPlus, "Empty default paragraph uses plus without disclosure")
        body.setSelectedRange(NSRange(location: body.string.utf16.count, length: 0))
        body.localUndo.beginUndoGrouping(); body.changeParagraph(.heading2); body.localUndo.endUndoGrouping()
        try moveGutter(to: body.string.utf16.count)
        try expect(!control.showsPlus && control.paragraphKind == .heading2, "Empty selected heading retains actual typing-format icon")
        body.isEditable = false; try moveGutter(to: 0)
        try expect(control.isHidden, "Read-only body cannot retain actionable gutter")
        body.isEditable = true; body.setSelectedRange(NSRange(location: 0, length: 0))
        body.localUndo.beginUndoGrouping()
        body.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0), replacementRange: body.selectedRange())
        try moveGutter(to: 0)
        try expect(control.isHidden && body.hasMarkedText(), "Marked text remains owned by IME without gutter action")
        body.unmarkText(); body.localUndo.endUndoGrouping(); host.retire(); gutterWindow.contentView = nil
        }
        do {
        let menuSession = try store.create()
        try menuSession.updateTitle("Compact menu", replacing: menuSession.document.title)
        let menuEditor = try makeEditor(directory: directory, documentID: menuSession.document.id)
        menuEditor.loadView()
        let menuWindow = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        menuWindow.isReleasedWhenClosed = false
        menuWindow.contentView = menuEditor.view
        menuEditor.view.frame = NSRect(x: 0, y: 0, width: 700, height: 720); menuEditor.view.needsLayout = true; menuEditor.view.layoutSubtreeIfNeeded()
        let body = menuEditor.text
        _ = menuWindow.makeFirstResponder(body)
        body.localUndo.groupsByEvent = false; body.localUndo.beginUndoGrouping()
        body.insertText("Paragraph", replacementRange: NSRange(location: 0, length: 0)); body.localUndo.endUndoGrouping()
        try drainPublications()
        menuEditor.view.layoutSubtreeIfNeeded()
        let range = NSRange(location: 0, length: body.string.utf16.count)
        menuEditor.formatting.present(range: range)
        try expect(menuWindow.firstResponder === body, "Gutter presentation keeps the original body responder")
        let menu = try require(menuEditor.formatting.subviews.compactMap { $0 as? NoteFormatMenu }.first, "Actual paragraph menu")
        menu.layoutSubtreeIfNeeded()
        try expect(menu.items.count == 11 && menu.items[7] == .emphasis && menu.items.filter { $0 == .separator }.count == 2, "Original six paragraphs, expandable emphasis and two final actions retain separators")
        try expect(menu.selectedIndex == nil, "Opening the original optional keyboard index does not invent a selected action")
        try expect(menu.frame.width == 34 && menu.frame.height == menu.preferredHeight, "Actual compact vertical menu uses recovered fixed cross-axis: \(menu.frame), expectedHeight=\(menu.preferredHeight), visible=\(menuEditor.formatting.visibleRect)")
        let full = menuEditor.formatting.visibleRect
        try expect(menu.frame.minY >= full.minY + 10 && menu.frame.maxY <= full.maxY - 10 && menu.frame.minX >= full.minX, "Original containment bounds constrain centered menu")
        let narrow = NoteFormatMenu.frame(anchoredTo: NSRect(x: -4, y: 90, width: 42, height: 30), in: NSRect(x: 0, y: 0, width: 24, height: 100), preferredHeight: menu.preferredHeight)
        try expect(narrow == NSRect(x: 0, y: 10, width: 24, height: 80), "Short narrow split clips scrolling presentation without negative or overflowing geometry")
        func menuButtons(_ view: NSView) -> [NoteFormatButton] {
            view.subviews.flatMap { child in (child as? NoteFormatButton).map { [$0] } ?? menuButtons(child) }
        }
        let initial = menuButtons(menu)
        try expect(initial.map(\.toolTip) == ["Heading 1", "Heading 2", "Heading 3", "Text", "Bulleted List", "Numbered List", "Text Formatting", "Insert Image", "Link"], "Native icon controls retain actual accessible action labels")
        let textButton = try require(initial.first { $0.item == .action(.text) }, "Original text icon")
        try expect(textButton.state == .on && textButton.frame.height == 34 && textButton.frame.width == 34, "Actual attributed paragraph selection is on-state without a text-row checkmark")
        let expansion = try require(initial.first { $0.item == .emphasis }, "Actual expandable emphasis button")
        expansion.updateTrackingAreas()
        let hover = NoteComponentTrackingEvent(); hover.area = expansion.trackingAreas.first { $0.options == [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect] }
        expansion.mouseEntered(with: hover)
        try expect(expansion.hovered && menu.selectedIndex == nil, "Hover highlights only its original control, without changing keyboard selection or text")
        let beforeAppearance = menuSession.document, originalSelection = body.selectedRanges
        let originalUndo = body.localUndo.canUndo, originalItems = menu.items
        menu.appearance = dark; menu.viewDidChangeEffectiveAppearance()
        let menuFill = try require(menu.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)), "Actual native menu layer fill")
        let menuBorder = try require(menu.layer?.borderColor.flatMap(NSColor.init(cgColor:)), "Actual native menu layer border")
        try expect(rgba(menuFill, under: light) == "#120F2EFF" && rgba(menuBorder, under: light) == "#34334DFF" && menu.layer?.borderWidth == 0.5, "Existing menu resolves dark named fill and half-point border into real CGColors")
        try expect(menuButtons(menu).elementsEqual(initial, by: { $0 === $1 }) && expansion.hovered && menu.selectedIndex == nil && menu.items == originalItems && textButton.state == .on, "Appearance redraw preserves original control identities, hover, checked state and optional keyboard index")
        try expect(menuWindow.firstResponder === body && menuEditor.formatting.isPresentingMenu && body.selectedRanges == originalSelection && body.localUndo.canUndo == originalUndo, "Pointer presentation keeps original body focus, exact paragraph selection and original Undo")
        try expectPublished(menuSession.document == beforeAppearance, "Control appearance does not publish a body/title revision")
        menu.appearance = light; menu.viewDidChangeEffectiveAppearance()
        let lightFill = try require(menu.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)), "Restored light menu fill")
        let lightBorder = try require(menu.layer?.borderColor.flatMap(NSColor.init(cgColor:)), "Restored light menu border")
        try expect(rgba(lightFill, under: dark) == "#FFFFFFFF" && lightBorder.alphaComponent == 0 && menuButtons(menu).elementsEqual(initial, by: { $0 === $1 }), "Light redraw removes only dark border and retains the same actionable menu")
        menu.appearance = nil
        expansion.mouseExited(with: hover)
        try expect(!expansion.hovered, "Owned menu item exit restores normal rendering")
        let beforeExpansion = menuSession.document
        expansion.performClick(nil); menu.layoutSubtreeIfNeeded()
        try expect(menu.items.count == 14 && Array(menu.items[7...10]) == [.action(.bold), .action(.italic), .action(.underline), .action(.strikethrough)], "Expansion replaces only the clicked container in place with its genuine four child options")
        try expectPublished(menuSession.document == beforeExpansion && body.selectedRange() == range && menuEditor.formatting.isPresentingMenu, "Expansion retains exact live paragraph and makes no persistent edit")
        expansion.performClick(nil)
        try expect(menu.items.count == 14, "A retained removed expansion button cannot dispatch again")
        let bold = try require(menuButtons(menu).first { $0.item == .action(.bold) }, "Expanded original bold action")
        body.localUndo.beginUndoGrouping(); bold.performClick(nil); body.localUndo.endUndoGrouping()
        try expect(!menuEditor.formatting.isPresentingMenu && body.hasEmphasis(.bold) && menuWindow.firstResponder === body, "Expanded native action edits and returns focus to the same original body")
        menuEditor.formatting.present(range: range, focus: true)
        let keyMenu = try require(menuWindow.firstResponder as? NoteFormatMenu, "Footer/AX entry focuses the original paragraph menu")
        try expect(keyMenu.selectedIndex == nil, "Explicit keyboard entry still starts with a nil selectedIndex")
        func menuKey(_ code: UInt16) throws -> NSEvent {
            try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: menuWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code), "Paragraph menu key")
        }
        keyMenu.keyDown(with: try menuKey(125))
        try expect(keyMenu.selectedIndex == 0, "didPressEnter path first Down selects the first enabled action")
        keyMenu.keyDown(with: try menuKey(53))
        try expect(!menuEditor.formatting.isPresentingMenu && menuWindow.firstResponder === body, "didDismissMenu returns focus to the original body")
        try expect(NoteAccessibility.nextIndex(from: nil, enabled: [0, 1, 2], step: 1) == 0, "Nil keyboard index advances to the first enabled action")
        try expect(NoteAccessibility.nextIndex(from: nil, enabled: [0, 1, 2], step: -1) == 2, "Nil keyboard index retreats to the last enabled action")
        try expect(NoteAccessibility.nextIndex(from: 1, enabled: [0, 1, 2], step: 1) == 2, "Keyboard index wraps through enabled actions only")
        try expect(NoteGutterButton().refusesFirstResponder && NoteGutterButton().accessibilityLabel() == "Format Paragraph", "Hover gutter is an AX press target, not a key-loop stop")
        _ = menuWindow.makeFirstResponder(menuEditor.titleText)
        NoteAccessibility.restoreBodyIfMenuRelinquished(body, owned: nil)
        try expect(menuWindow.firstResponder === menuEditor.titleText, "Link-popover close never steals an original title responder")
        let stray = NSButton(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        stray.setButtonType(.momentaryPushIn); stray.refusesFirstResponder = false; menuEditor.view.addSubview(stray)
        _ = menuWindow.makeFirstResponder(stray)
        NoteAccessibility.restoreBodyIfMenuRelinquished(body, owned: nil)
        try expect(menuWindow.firstResponder === stray, "Dismiss without an owned menu does not steal a live non-text responder")
        let ownedMenu = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        menuEditor.view.addSubview(ownedMenu)
        _ = menuWindow.makeFirstResponder(stray)
        NoteAccessibility.restoreBodyIfMenuRelinquished(body, owned: ownedMenu)
        try expect(menuWindow.firstResponder === stray, "Menu-close restore does not steal a live control that is not the owned menu")
        _ = menuWindow.makeFirstResponder(nil)
        NoteAccessibility.restoreBodyIfMenuRelinquished(body, owned: ownedMenu)
        try expect(menuWindow.firstResponder === body, "Menu-close restore returns the original body after AppKit resigns to the window")
        _ = menuWindow.makeFirstResponder(nil)
        let dummyPopover = NSPopover(); dummyPopover.contentViewController = NSViewController()
        let linkPopover = NSPopover(); linkPopover.contentViewController = EaselLinkEditor(value: "")
        let popoverToken = NoteAccessibility.observePopoverClose(positioning: ownedMenu, restore: body)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: dummyPopover)
        try expect(menuWindow.firstResponder !== body, "Unrelated popover close does not restore the original body")
        _ = menuWindow.makeFirstResponder(nil)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: linkPopover)
        try expect(menuWindow.firstResponder === body, "Link-popover close restores the original body")
        _ = menuWindow.makeFirstResponder(nil)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: linkPopover)
        try expect(menuWindow.firstResponder !== body, "Link-popover observer is one-shot")
        popoverToken.invalidate()
        _ = menuWindow.makeFirstResponder(nil)
        let stopped = NoteAccessibility.observePopoverClose(positioning: ownedMenu, restore: body)
        stopped.invalidate()
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: linkPopover)
        try expect(menuWindow.firstResponder !== body, "Invalidating the observer before close leaves the original responder")
        weak var leaked: NoteAccessibility.PopoverCloseObserver?
        do {
            let released = NoteAccessibility.observePopoverClose(positioning: ownedMenu, restore: body)
            leaked = released
            released.invalidate()
        }
        try expect(leaked == nil, "An invalidated link-popover observer does not retain itself")
        stray.removeFromSuperview(); ownedMenu.removeFromSuperview()
        try drainPublications()
        let afterBold = menuSession.document
        menuEditor.formatting.present(range: range)
        bold.performClick(nil)
        try expectPublished(menuSession.document == afterBold && menuEditor.formatting.isPresentingMenu, "Detached old menu cannot act through a newly admitted paragraph owner")
        let replacement = try require(menuEditor.formatting.subviews.compactMap { $0 as? NoteFormatMenu }.first, "New exact menu owner")
        try expect(menuWindow.firstResponder === body, "Replacement gutter menu still leaves the original body responder")
        let freshExpand = try require(menuButtons(replacement).first { $0.item == .emphasis }, "New expandable item")
        try menuSession.updateTitle("Other window", replacing: menuSession.document.title)
        freshExpand.performClick(nil)
        try expect(!menuEditor.formatting.isPresentingMenu && replacement.items.count == 11, "Cross-window publication revokes even non-editing expansion")
        body.undo(nil)
        try expectPublished(!body.hasEmphasis(.bold) && menuSession.document.body.id == beforeExpansion.body.id, "Formatting Undo retains original durable body identity")
        menuEditor.formatting.retire()
        body.localUndo.beginUndoGrouping()
        body.insertText(String(repeating: "Line\n", count: 60), replacementRange: NSRange(location: (body.string as NSString).length, length: 0))
        body.localUndo.endUndoGrouping()
        menuEditor.view.needsLayout = true; menuEditor.view.layoutSubtreeIfNeeded()
        let below = NSRange(location: (body.string as NSString).length, length: 0)
        body.setSelectedRange(below); NoteAccessibility.reveal(below, in: body)
        let shownCaret = body.visibleRect
        body.scrollRangeToVisible(NSRange(location: 0, length: 1))
        let hiddenCaret = body.visibleRect
        try expect(hiddenCaret.origin.y != shownCaret.origin.y, "A tall body can hide the caret from the current viewport")
        _ = menuWindow.makeFirstResponder(nil)
        menuEditor.focusContent()
        try expect(menuWindow.firstResponder === body && body.visibleRect.origin.y == hiddenCaret.origin.y, "Automatic forwarded focus restores the original body without scrolling")
        _ = menuWindow.makeFirstResponder(nil)
        try expect(NoteAccessibility.returnFocus(to: body, in: menuWindow) && body.visibleRect.origin.y == hiddenCaret.origin.y, "Image-sheet completion restores the original body without scrolling")
        let offscreen = try require(NoteParagraphGeometry.target(in: body, containing: max(0, below.location - 1)), "Off-screen last paragraph")
        menuEditor.formatting.present(range: offscreen.range, focus: true)
        try expect(body.visibleRect.origin.y != hiddenCaret.origin.y, "Footer/AX presentation reveals the off-screen paragraph")
        menuEditor.formatting.retire()
        body.scrollRangeToVisible(NSRange(location: 0, length: 1))
        let hiddenAgain = body.visibleRect
        menuEditor.formatting.present(range: offscreen.range)
        try expect(body.visibleRect.origin.y == hiddenAgain.origin.y, "Pointer presentation does not reveal an off-screen paragraph")
        menuEditor.formatting.retire(); menuWindow.contentView = nil
        }
        do {
        let hitSession = try store.create()
        let hitEditor = try makeEditor(directory: directory, documentID: hitSession.document.id)
        hitEditor.loadView()
        let hitWindow = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        hitWindow.isReleasedWhenClosed = false; hitWindow.contentView = hitEditor.view
        hitEditor.view.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        let body = hitEditor.text
        body.localUndo.groupsByEvent = false; body.localUndo.beginUndoGrouping()
        body.insertText("First\nSecond\n", replacementRange: NSRange(location: 0, length: 0)); body.localUndo.endUndoGrouping()
        hitEditor.view.needsLayout = true; hitEditor.view.layoutSubtreeIfNeeded()
        let normal = try require(NoteParagraphGeometry.target(in: body, containing: 5), "Original native newline line")
        try expect(normal.range == NSRange(location: 0, length: 5) && normal.iconRange == normal.range, "Original NSString contentsEnd excludes line terminator from action range")
        let nativeFirst = hitWindow.convertFromScreen(body.firstRect(forCharacterRange: normal.range, actualRange: nil))
        let originalAnchor = try require(normal.windowAnchor, "Original body window anchor")
        let boundary = originalAnchor.y - nativeFirst.height / 2
        let upper = try require(NoteParagraphGeometry.resolveHit(in: body, index: 5, windowPoint: NSPoint(x: nativeFirst.minX, y: boundary + 0.25)), "Upper newline half")
        let lower = try require(NoteParagraphGeometry.resolveHit(in: body, index: 5, windowPoint: NSPoint(x: nativeFirst.minX, y: boundary)), "Lower newline boundary")
        try expect(upper.range == normal.range && !upper.afterNewline, "Upper newline keeps original content span")
        try expect(lower.range == NSRange(location: 6, length: 0) && lower.iconRange == NSRange(location: 5, length: 0) && lower.afterNewline, "Boundary creates exact zero-length next insertion with distinct original icon location")
        let refreshed = try require(NoteParagraphGeometry.refresh(lower, in: body), "Retained newline metadata refresh")
        try expect(refreshed.range == lower.range && refreshed.afterNewline && refreshed.sourceRange == normal.range, "Geometry refresh cannot retarget insertion as following text paragraph")
        let layout = try require(body.layoutManager, "Actual native layout")
        let container = try require(body.textContainer, "Actual native container")
        let glyphs = layout.glyphRange(forCharacterRange: normal.range, actualCharacterRange: nil)
        var enclosingHeight: CGFloat = 0
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container) { rect, _ in if rect.height > 0 { enclosingHeight += rect.height } }
        let insertionAnchor = try require(lower.windowAnchor, "Original newline insertion anchor")
        try expect(abs(insertionAnchor.y - (originalAnchor.y - enclosingHeight - 8)) < 0.01 && insertionAnchor.x == originalAnchor.x, "Original enclosing native rectangles and eight-point adjustment position the insertion control")
        try drainPublications()
        let beforeFormat = hitSession.document.body
        hitEditor.formatting.present(range: lower.range, source: lower)
        try expect(body.selectedRange() == lower.range && hitEditor.formatting.isPresentingMenu && hitWindow.firstResponder === body, "Actual menu admits zero-length original target without selecting following text")
        hitEditor.formatting.present(range: lower.range, source: lower, focus: true)
        let hitDown = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: hitWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125), "Targeted menu Down")
        let hitReturn = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: hitWindow.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36), "Targeted menu Return")
        body.localUndo.beginUndoGrouping(); hitWindow.firstResponder?.keyDown(with: hitDown); hitWindow.firstResponder?.keyDown(with: hitDown); hitWindow.firstResponder?.keyDown(with: hitReturn); body.localUndo.endUndoGrouping()
        let firstAttributes = body.attributedString().attributes(at: 0, effectiveRange: nil)
        let nextAttributes = body.attributedString().attributes(at: 6, effectiveRange: nil)
        try expect(EaselParagraphEditing.kind(firstAttributes) == .text && EaselParagraphEditing.kind(nextAttributes) == .heading2, "Caret paragraph command preserves preceding original paragraph and formats only its actual destination")
        body.undo(nil)
        try expectPublished(hitSession.document.body == beforeFormat, "Insertion menu formatting Undo preserves original body and exact text")
        let classification = "\n\r\u{000b}\u{000c}\u{0085}\u{2028}\u{2029}\t👩"
        for index in [0, 1, 2, 3, 4, 5, 6] {
            let range = Range(NSRange(location: index, length: 1), in: classification)
            try expect(NoteParagraphGeometry.isNewline(in: classification, at: index) == (range != nil), "Recovered newline set preserves actual range conversion")
        }
        try expect(!NoteParagraphGeometry.isNewline(in: classification, at: 7) && !NoteParagraphGeometry.isNewline(in: classification, at: 8), "Tab and surrogate fragments are not newline insertion targets")
        let native = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        native.textStorage?.setAttributedString(NSAttributedString(string: "A\u{fffc}B\nplain\u{2028}soft\u{2029}last\n", attributes: NoteDocumentAppearance.bodyAttributes))
        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: NSImage(size: NSSize(width: 12, height: 12)))
        attachment.attachmentCell = cell
        native.textStorage?.addAttribute(.attachment, value: attachment, range: NSRange(location: 1, length: 1))
        try expect(NoteParagraphGeometry.target(in: native, containing: 0) == nil && NoteParagraphGeometry.target(in: native, containing: 2) == nil, "An image anywhere in the original line suppresses its whole gutter range")
        try expect(NoteParagraphGeometry.target(in: native, containing: 4)?.range == NSRange(location: 4, length: 5), "Image in another line does not suppress original neighboring text")
        try expect(NoteParagraphGeometry.target(in: native, containing: 10)?.range == NSRange(location: 10, length: 4), "Unicode line separator uses original line contents range, not a broader paragraph")
        cell.image = nil
        try expect(NoteParagraphGeometry.target(in: native, containing: 0)?.range == NSRange(location: 0, length: 3), "Attachment cell without an actual image does not invent the image eligibility refusal")
        attachment.attachmentCell = nil
        try expect(NoteParagraphGeometry.target(in: native, containing: 0) != nil, "Missing attachment cell retains original non-image eligibility")
        try expect(NoteParagraphGeometry.target(in: native, containing: Int.max) == nil, "Native range admission rejects overflow before NSString lookup")
        hitEditor.formatting.retire(); hitWindow.contentView = nil
        }
        window.contentView = nil
        try testBodyScheduling(directory: directory.appendingPathComponent("scheduling"))
        try testGutterIcons()
        try testPublishedFormattingOwner(directory: directory.appendingPathComponent("published-formatting"))
        try testImageAuthoring(directory: directory.appendingPathComponent("image-authoring"))
        try checkNoteMotion(directory: directory.appendingPathComponent("motion"))
        print("NoteEditor: \(assertions) assertions passed (no displayed window)")
    }
    static func testImageAuthoring(directory: URL) throws {
        let panel = NoteImageImport.makePanel(), defaults = NSOpenPanel()
        try expect(panel.canChooseFiles && !panel.canChooseDirectories && !panel.allowsMultipleSelection, "Actual Notes panel uses original single-file flags")
        try expect(panel.allowedContentTypes.map(\.identifier) == ["public.jpeg", "public.png", "com.adobe.pdf", "com.microsoft.bmp", "public.tiff"], "Actual Notes panel preserves recovered five-type order")
        try expect(panel.title == defaults.title && panel.prompt == defaults.prompt && panel.accessoryView == nil, "Original native title/prompt/options are not replaced by invented picker chrome")
        let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Actual import source pixels")
        bitmap.size = NSSize(width: 12, height: 8)
        for y in 0..<8 { for x in 0..<12 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        for format: NSBitmapImageRep.FileType in [.png, .jpeg, .tiff] {
            let original = try require(bitmap.representation(using: format, properties: [:]), "Existing encoded raster")
            try expect(try NoteImageImport.attachmentData(original) == original, "Original supported raster bytes survive import unchanged")
        }
        let bmp = try require(bitmap.representation(using: .bmp, properties: [:]), "Actual BMP bytes")
        let converted = try NoteImageImport.attachmentData(bmp)
        let decoded = try EaselTextAttachments.image(data: converted)
        let pixels = try require(NSBitmapImageRep(data: converted), "Actual BMP conversion pixels")
        try expect(decoded.fileType == "public.png" && pixels.pixelsWide == 12 && pixels.pixelsHigh == 8, "BMP becomes validated original-sized PNG carrier")
        try expect((pixels.colorAt(x: 4, y: 4)?.redComponent ?? 0) > 0.9, "BMP conversion retains actual source red pixels")
        func pdf(size: CGSize, colors: [CGColor]) throws -> Data {
            let bytes = NSMutableData()
            let consumer = try require(CGDataConsumer(data: bytes as CFMutableData), "PDF data consumer")
            var bounds = CGRect(origin: .zero, size: size)
            let context = try require(CGContext(consumer: consumer, mediaBox: &bounds, nil), "Actual local PDF context")
            for color in colors {
                context.beginPDFPage(nil); context.setFillColor(color); context.fill(bounds); context.endPDFPage()
            }
            context.closePDF(); return bytes as Data
        }
        let sourcePDF = try pdf(size: CGSize(width: 30, height: 20), colors: [NSColor.red.cgColor, NSColor.blue.cgColor])
        let firstPage = try NoteImageImport.attachmentData(sourcePDF)
        let pdfPixels = try require(NSBitmapImageRep(data: firstPage), "Actual first PDF page pixels")
        try expect(pdfPixels.pixelsWide == 30 && pdfPixels.pixelsHigh == 20, "PDF native first page renders at explicit one-pixel-per-point storage scale")
        let center = try require(pdfPixels.colorAt(x: 15, y: 10)?.usingColorSpace(.sRGB), "PDF center pixel")
        try expect(center.redComponent > 0.9 && center.blueComponent < 0.1, "Multi-page PDF imports its first image page, not the later blue page")
        func refuses(_ bytes: Data, _ message: String) throws {
            do { _ = try NoteImageImport.attachmentData(bytes); try expect(false, message) }
            catch is EaselStoreError { assertions += 1 }
        }
        try refuses(Data("not an image".utf8), "Malformed image must refuse")
        try refuses(Data(repeating: 0, count: 4_194_305), "Oversized input must refuse before decode")
        let gif = try require(bitmap.representation(using: .gif, properties: [:]), "Unsupported GIF fixture")
        try refuses(gif, "Unlisted GIF must not enter through generic decoder")
        try refuses(try pdf(size: CGSize(width: 20_001, height: 1), colors: [.init(gray: 0, alpha: 1)]), "Oversized PDF must refuse before raster allocation")
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        let file = directory.appendingPathComponent("native.pdf")
        try sourcePDF.write(to: file)
        let imported = try NoteImageImport.attachmentData(from: file)
        try FileManager.default.removeItem(at: file)
        try expect(imported == firstPage, "One local file read produces self-contained image bytes")
        do { _ = try NoteImageImport.attachmentData(from: directory); try expect(false, "Directory import must refuse") }
        catch is EaselStoreError { assertions += 1 }
        do { _ = try NoteImageImport.attachmentData(from: URL(string: "https://example.invalid/picture.png")!); try expect(false, "Image import must never fetch a URL") }
        catch is EaselStoreError { assertions += 1 }
        let editor = try makeEditor(directory: directory, documentID: session.document.id)
        editor.loadView(); let text = editor.text
        text.localUndo.groupsByEvent = false
        text.localUndo.beginUndoGrouping(); text.insertText("before", replacementRange: NSRange(location: 0, length: 0)); text.localUndo.endUndoGrouping()
        try drainPublications()
        let previous = session.document.body
        text.setSelectedRange(NSRange(location: 0, length: 6))
        text.localUndo.beginUndoGrouping(); let inserted = try text.insertImage(imported); text.localUndo.endUndoGrouping()
        try expectPublished(inserted && session.document.body.richText.runs.contains { $0.attributes.image?.data == imported }, "Real Notes insertion publishes exact imported attachment through existing save owner")
        try expect(session.document.body.text.contains("\u{FFFC}") && !session.document.body.text.contains("before"), "Original selected text is replaced once by native image and boundary")
        text.undo(nil)
        try expectPublished(session.document.body == previous, "Native Undo restores exact original body after image insertion")
        text.redo(nil)
        try expectPublished(session.document.body.richText.runs.contains { $0.attributes.image?.data == imported }, "Native Redo restores same self-contained image bytes")
        let savedFile = directory.appendingPathComponent(session.document.id.uuidString.lowercased() + ".json")
        let reloaded = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: savedFile))
        try expect(reloaded.body == session.document.body, "Durable image survives source deletion and store reload")
    }

    static func pump(for interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        while Date() < deadline { _ = RunLoop.current.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01))) }
    }
    static func testGutterIcons() throws {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        func contents(_ string: String, size: CGFloat = 18, header: Int = 0) {
            let paragraph = NSMutableParagraphStyle(); paragraph.headerLevel = header
            text.textStorage?.setAttributedString(NSAttributedString(string: string,
                attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph]))
            text.setSelectedRange(NSRange(location: 0, length: 0))
            text.typingAttributes = [.font: NoteDocumentAppearance.bodyFont]
        }
        func icon(_ range: NSRange? = nil) -> NoteGutterIcon {
            NoteGutterIcon.resolve(in: text, range: range ?? NSRange(location: 0, length: text.string.utf16.count))
        }
        for (size, expected) in [(32.0, NoteGutterIcon.heading1), (26.0, .heading2), (22.0, .heading3)] {
            contents("Heading", size: size)
            try expect(icon() == expected, "Heading icon follows exact first font size without paragraph metadata")
        }
        contents("Semantic heading", header: 1)
        try expect(icon() == .text, "Header metadata alone cannot fabricate a heading icon")
        contents("Near heading", size: 31.999)
        try expect(icon() == .text, "Heading size comparison remains exact")
        contents("Mixed", size: 26)
        text.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 32), range: NSRange(location: 1, length: 4))
        try expect(icon() == .heading2, "First actual font run owns mixed-font icon")
        text.textStorage?.removeAttribute(.font, range: NSRange(location: 0, length: 1))
        try expect(icon() == .heading1, "Font enumeration skips a missing font and stops at first actual font")
        contents("No font", header: 3); text.textStorage?.removeAttribute(.font, range: NSRange(location: 0, length: 7))
        try expect(icon() == .text, "Missing fonts use recovered body font instead of heading metadata")
        for value in ["\t●\titem", "\t✺\titem"] {
            contents(value, size: 32); try expect(icon() == .bullets, "Original bullet prefix takes priority over heading font")
        }
        for value in ["\t1\titem", "\t123\titem", "\t-1\titem", "\t+2\titem"] {
            contents(value, size: 32); try expect(icon() == .numbers, "Original five-character decimal marker selects numbered icon")
        }
        for value in ["\t1234\titem", "● item", "\t1.\titem", "\t•\titem"] {
            contents(value); try expect(icon() == .text, "Unrecognized authored prefix is ordinary text without a genuine native list")
        }
        for (format, expected) in [(NSTextList.MarkerFormat.disc, NoteGutterIcon.bullets), (NSTextList.MarkerFormat(rawValue: "{decimal}."), .numbers)] {
            let list = NSTextList(markerFormat: format, options: 0)
            contents("\t" + list.marker(forItemNumber: 1) + "\titem", size: 32)
            let paragraph = NSMutableParagraphStyle(); paragraph.textLists = [list]
            text.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.string.utf16.count))
            try expect(icon() == expected, "Current AppKit exact authored list marker retains its list icon")
            text.textStorage?.replaceCharacters(in: NSRange(location: 0, length: text.string.utf16.count), with: "Unmarked")
            try expect(icon() == .heading1, "Native list metadata without its marker does not override actual font")
        }
        contents(""); try expect(icon() == .plus, "Empty default insertion uses plus")
        text.typingAttributes = [.font: NSFont.systemFont(ofSize: 26)]
        try expect(icon() == .heading2, "Exact collapsed empty caret uses typing font")
        contents("\n"); text.typingAttributes = [.font: NSFont.systemFont(ofSize: 22)]
        try expect(icon() == .heading3, "Newline-only content can use original typing font")
        text.setSelectedRange(NSRange(location: 1, length: 0))
        try expect(icon() == .plus, "A caret on another range cannot own empty icon")
        text.setSelectedRange(NSRange(location: 0, length: 1))
        try expect(icon() == .plus, "Noncollapsed selection cannot supply empty typing icon")
        contents(" "); text.typingAttributes = [.font: NSFont.systemFont(ofSize: 32)]
        try expect(icon() == .text, "Whitespace is content and never trimmed into plus or typing heading")
        contents("😀x", size: 32)
        try expect(icon(NSRange(location: 1, length: 1)) == .heading1, "Native UTF-16 range conversion retains the first actual font without crashing")
        try expect(icon(NSRange(location: NSNotFound, length: 0)) == .text, "Invalid sentinel cannot overflow attributed access")
        try expect(icon(NSRange(location: 0, length: Int.max)) == .text, "Oversized original range fails safely")

        func pixels(numbered: Bool) throws -> NSBitmapImageRep {
            let rep = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Glyph bitmap")
            let context = try require(NSGraphicsContext(bitmapImageRep: rep), "Glyph graphics context")
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            let image = NoteListGlyph.image(numbered: numbered)
            try expect(image.size == NSSize(width: 14.4, height: 14.4), "Recovered shared list frame is 14.4 points")
            image.draw(in: NSRect(x: 0, y: 0, width: 80, height: 80), from: .zero, operation: .sourceOver, fraction: 1)
            context.flushGraphics(); return rep
        }
        let bullets = try pixels(numbered: false), numbers = try pixels(numbered: true)
        func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        try expect(alpha(bullets, 40, 20) > 0.9 && alpha(bullets, 40, 40) > 0.9 && alpha(bullets, 40, 60) > 0.9,
                   "Recovered vector draws all three horizontal strokes")
        try expect(alpha(bullets, 40, 30) == 0 && alpha(bullets, 0, 0) == 0, "List artwork keeps transparent line gaps and border")
        try expect(bullets.representation(using: .png, properties: [:]) != numbers.representation(using: .png, properties: [:]),
                   "Numbered glyph uses real numeral contours rather than reusing bullets")
        try expect(text.string == "😀x" && text.selectedRange() == NSRange(location: 0, length: 0),
                   "Display classification and drawing never edit text or selection")
    }

    static func testPublishedFormattingOwner(directory: URL) throws {
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        var saved = session.document.body; saved.text = "Original paragraph"
        saved.richText = try EaselRichTextCodec.snapshot(NSAttributedString(string: saved.text, attributes: NoteDocumentAppearance.bodyAttributes))
        try session.updateBody(saved, replacing: session.document.body)
        let editor = try makeEditor(directory: directory, documentID: session.document.id); editor.loadView()
        let window = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = editor.view
        defer { window.contentView = nil }
        editor.view.frame = NSRect(x: 0, y: 0, width: 700, height: 600); editor.view.layoutSubtreeIfNeeded(); pump(for: 0.02)
        let body = editor.text; _ = window.makeFirstResponder(body)
        body.localUndo.groupsByEvent = false
        let range = NSRange(location: 0, length: saved.text.utf16.count)
        body.setSelectedRange(range)
        body.localUndo.beginUndoGrouping(); body.toggle(.underline); body.localUndo.endUndoGrouping()
        editor.view.layoutSubtreeIfNeeded()
        editor.formatting.selection.present()
        let menu = try require(editor.formatting.selection.makeParagraphMenu(), "Original menu admitted before its body publication")
        let heading = menu.items[1]
        try expect(editor.hasPendingBodyPublication, "Formatting menu is admitted against an unsaved original body")
        try drainPublications()
        try expect(editor.formatting.selection.isPresenting && body.selectedRange() == range, "Own successful body publication preserves exact native selection owner")
        body.localUndo.beginUndoGrouping(); NSApp.sendAction(heading.action!, to: heading.target, from: heading); body.localUndo.endUndoGrouping()
        try expect(body.paragraphKind() == .heading1, "The retained exact menu choice remains actionable across its own body save")
        try drainPublications()
        try expect(session.document.body.id == saved.id && session.document.body.text == saved.text, "Retained action saves on original durable body without retargeting")
        body.undo(nil); try drainPublications()
        try expect(body.paragraphKind() == .text && body.hasEmphasis(.underline), "Menu action and preceding edit retain separate native Undo after coalescing")
        editor.formatting.selection.present()
        let stale = try require(editor.formatting.selection.makeParagraphMenu(), "Original menu before other-window update").items[1]
        try session.updateTitle("Other window", replacing: session.document.title)
        NSApp.sendAction(stale.action!, to: stale.target, from: stale)
        try expect(body.paragraphKind() == .text && !editor.formatting.selection.isPresenting, "External publication does not acquire the local durability advancement")
    }

    static func testBodyScheduling(directory: URL) throws {
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        let editor = try makeEditor(directory: directory, documentID: session.document.id)
        let peer = try makeEditor(directory: directory, documentID: session.document.id)
        editor.loadView(); peer.loadView()
        let component = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        component.isReleasedWhenClosed = false; component.contentView = editor.view
        defer { component.contentView = nil }
        let body = editor.text, title = editor.titleText
        _ = component.makeFirstResponder(body)
        body.localUndo.groupsByEvent = false; title.localUndo.groupsByEvent = false
        func type(_ value: String) {
            body.breakUndoCoalescing()
            body.localUndo.beginUndoGrouping()
            body.insertText(value, replacementRange: body.selectedRange())
            body.localUndo.endUndoGrouping()
        }
        var published: [NoteDocument] = []
        let observation = session.$document.dropFirst().sink { published.append($0) }
        defer { observation.cancel() }
        editor.view.layoutSubtreeIfNeeded()
        let chromeBeforeTyping = editor.chromeLayoutCount
        type("A")
        try expect(editor.chromeLayoutCount == chromeBeforeTyping, "Body typing does not relayout footer chrome, format control or the key loop")
        try expect(editor.hasPendingBodyPublication && session.document.body.text.isEmpty, "Body delivery is queued on the recovered main scheduler")
        try drainPublications()
        try expect(session.document.body.text == "A" && peer.text.string == "A" && published.count == 1, "Initial body event publishes once to the actual shared session")
        type("B"); type("C")
        _ = component.makeFirstResponder(title)
        title.localUndo.beginUndoGrouping(); title.insertText("Immediate title", replacementRange: NSRange(location: 0, length: title.string.utf16.count)); title.localUndo.endUndoGrouping()
        try expect(session.document.title == "Immediate title" && session.document.body.text == "A" && editor.hasPendingBodyPublication, "Title publishes immediately without flushing or dropping a pending body")
        let burstStart = published.count
        pump(for: 0.06)
        try expect(session.document.body.text == "A", "Subsequent body burst respects the half-second throttle rather than immediate per-keystroke writes")
        try drainPublications()
        try expect(published.count == burstStart + 1 && session.document.body.text == "ABC" && peer.text.string == "ABC", "Throttle keeps the latest entire body and emits no intermediate B document")
        try expect(published.last?.title == "Immediate title", "Delayed body publication preserves independent title update")
        _ = component.makeFirstResponder(body)
        body.undo(nil); try drainPublications()
        try expect(session.document.body.text == "AB", "Save coalescing does not merge native body Undo groups: native=\(body.string) saved=\(session.document.body.text) undo=\(body.localUndo.canUndo)")
        body.undo(nil); try drainPublications()
        try expect(session.document.body.text == "A", "The prior native edit remains independently undoable")
        body.redo(nil); try drainPublications()
        try expect(session.document.body.text == "AB", "Native Redo republishes through the same bounded body owner")
        _ = component.makeFirstResponder(title); title.localUndo.undo()
        try expect(session.document.title == "Untitled Note" && body.localUndo.canRedo, "Title Undo remains separate from body history and its schedule")
        _ = component.makeFirstResponder(body)
        type(" close")
        try expect(editor.hasPendingBodyPublication, "An outstanding body token exists before the explicit close/export barrier")
        try expect(editor.prepareToClose() && session.document.body.text == "AB close" && !editor.hasPendingBodyPublication, "Close/export barrier synchronously commits exact latest body")
        let afterFlush = session.document
        pump(for: 0.55)
        try expect(session.document == afterFlush, "A queued token cannot publish again after explicit flush")

        type(" before composition")
        body.setMarkedText("入力", selectedRange: NSRange(location: 2, length: 0), replacementRange: body.selectedRange())
        try expect(body.hasMarkedText(), "Native composition remains in its original body owner")
        pump(for: 0.55)
        try expect(session.document == afterFlush && body.string.contains("入力") && !editor.hasPendingBodyPublication, "Composition stays in the native draft rather than leaking through an older callback")
        try expect(editor.prepareToClose() && !body.hasMarkedText() && session.document.body.text.contains("入力"), "Original close barrier commits composition and latest body together")

        let beforeFailure = session.document
        let file = directory.appendingPathComponent(session.document.id.uuidString.lowercased() + ".json")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file); try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        type(" failed")
        try drainPublications()
        try expect(session.document == beforeFailure && body.string.hasSuffix(" failed") && !editor.hasPendingBodyPublication, "Actual scheduled disk failure retains draft and clears the attempted token")
        pump(for: 0.55)
        try expect(session.document == beforeFailure && !editor.prepareToClose(), "Failure neither spins automatic retries nor permits closure")
        try FileManager.default.removeItem(at: file); try saved.write(to: file)
        try expect(editor.prepareToClose() && session.document.body.text.hasSuffix(" failed"), "Explicit retry persists the same failed draft")

        type(" local draft")
        let draft = body.string
        var external = session.document.body; external.text = "Other window"; external.richText = try EaselRichTextCodec.snapshot(NSAttributedString(string: external.text, attributes: NoteDocumentAppearance.bodyAttributes))
        try session.updateBody(external, replacing: session.document.body)
        try drainPublications()
        try expect(session.document.body.text == "Other window" && body.string == draft && !editor.prepareToClose(), "A competing body publication cannot be overwritten by delayed stale input")
        func findButton(_ view: NSView, title: String) -> NSButton? {
            if let button = view as? NSButton, button.title == title { return button }
            return view.subviews.lazy.compactMap { findButton($0, title: title) }.first
        }
        try require(findButton(editor.view, title: "Discard Draft"), "Original discard control").performClick(nil)
        try expect(body.string == "Other window" && !editor.hasPendingBodyPublication && !body.localUndo.canUndo, "Explicit discard adopts original saved contents and retires stale Undo/token")
        type(" never resurrect")
        try store.delete(session.document.id, expectedRevision: session.document.revision)
        let tombstone = session.document
        pump(for: 0.55)
        try expect(session.document == tombstone && tombstone.deleted && !body.isEditable && !editor.hasPendingBodyPublication, "Tombstone cancels pending publication without resurrecting local content")

        let delayDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("parc-note-editor-delay-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: delayDirectory) }
        let delayedStore = try NoteStore.sharedStore(directory: delayDirectory, diskSaveDelay: 60)
        let delayedSession = try delayedStore.create()
        let delayedEditor = try makeEditor(directory: delayDirectory, documentID: delayedSession.document.id)
        delayedEditor.loadView()
        delayedEditor.view.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        delayedEditor.view.layoutSubtreeIfNeeded()
        let delayedTitle = delayedEditor.titleText
        let chromeBeforeTitle = delayedEditor.chromeLayoutCount
        FileOperations.install()
        func replaces(_ calls: [FileOperation]) -> Int { Set(calls.filter { $0.fileName.hasPrefix(".write-") }.map(\.path)).count }
        let titleTyping = FileOperations.during(delayDirectory) {
            delayedTitle.localUndo.beginUndoGrouping()
            delayedTitle.insertText("Delayed title", replacementRange: NSRange(location: 0, length: delayedTitle.string.utf16.count))
            delayedTitle.localUndo.endUndoGrouping()
        }
        try expect(delayedEditor.chromeLayoutCount == chromeBeforeTitle, "Title typing does not relayout footer chrome")
        try expect(delayedSession.document.title == "Delayed title" && delayedSession.hasDelayedDiskSave, "Title publication is immediate while the recovered disk save stays pending")
        try expect(replaces(titleTyping) == 0, "Immediate title publication does not write; create remains the only persist so far")
        func footer(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.stringValue.contains("on this Mac") { return field }
            return view.subviews.lazy.compactMap { footer($0) }.first
        }
        try expect(try require(footer(delayedEditor.view), "Local save footer").stringValue == "Saving on this Mac…", "Footer reports a pending delayed disk save")
        let delayedPath = delayDirectory.appendingPathComponent(delayedSession.document.id.uuidString.lowercased() + ".json")
        let stale = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: delayedPath))
        try expect(stale.title == "Untitled Note", "Disk still has the immediately persisted create until close flush")
        var closed = false
        let closing = FileOperations.during(delayDirectory) { closed = delayedEditor.prepareToClose() }
        try expect(closed && !delayedSession.hasDelayedDiskSave, "Close barrier flushes the recovered delayed disk save")
        try expect(replaces(closing) == 1, "Close flush writes the delayed title document once")
        let flushed = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: delayedPath))
        try expect(flushed.title == "Delayed title", "Flushed close writes the live document")
        try expect(try require(footer(delayedEditor.view), "Saved footer").stringValue == "Saved on this Mac", "Footer reports Saved after the delayed write flushes")
    }


    static func checkNoteMotion(directory: URL) throws {
        SystemOverrides.install()
        defer { SystemOverrides.reduceMotion = nil }
        let omega = 2 * Double.pi / Double(NoteMotion.selectedIndexResponse)
        let sample = NoteMotion.selectedIndexSpring(keyPath: "opacity", from: Float(0), to: Float(1))
        try expect(NoteMotion.selectedIndexResponse == 0.15 && NoteMotion.selectedIndexDamping == 0.825, "Recovered selected-index spring uses response 0.15 and damping 0.825")
        try expect(abs(sample.mass - 1) < 0.001 && abs(sample.stiffness - omega * omega) < 0.05
                   && abs(sample.damping - 2 * 0.825 * omega) < 0.05 && NoteMotion.matchesRecovered(sample),
                   "AppKit spring conversion matches SwiftUI Animation.spring mass/stiffness/damping")
        let store = try NoteStore.sharedStore(directory: directory, diskSaveDelay: 0), session = try store.create()
        try session.updateTitle("Motion", replacing: session.document.title)
        let editor = try makeEditor(directory: directory, documentID: session.document.id)
        editor.loadView()
        let window = NoteComponentWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 720), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = editor.view
        editor.view.frame = NSRect(x: 0, y: 0, width: 700, height: 720); editor.view.layoutSubtreeIfNeeded()
        let body = editor.text
        _ = window.makeFirstResponder(body)
        body.localUndo.groupsByEvent = false; body.localUndo.beginUndoGrouping()
        body.insertText("Paragraph", replacementRange: NSRange(location: 0, length: 0)); body.localUndo.endUndoGrouping()
        try drainPublications(); editor.view.layoutSubtreeIfNeeded()
        let range = NSRange(location: 0, length: body.string.utf16.count)
        SystemOverrides.reduceMotion = false
        editor.formatting.present(range: range, focus: true)
        let menu = try require(window.firstResponder as? NoteFormatMenu, "Paragraph menu for motion")
        try expect(menu.layer?.animationKeys()?.isEmpty != false && menu.alphaValue == 1, "Original presenter installs the menu without a presentation animation")
        let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125)
        func menuButtons(_ view: NSView) -> [NoteFormatButton] {
            view.subviews.flatMap { child in (child as? NoteFormatButton).map { [$0] } ?? menuButtons(child) }
        }
        func menuHighlights() -> [NSView] {
            menu.layoutSubtreeIfNeeded()
            return menuButtons(menu).compactMap(highlight(of:))
        }
        try expect(!menuButtons(menu).isEmpty && menuHighlights().count == menuButtons(menu).count,
                   "Every format row has its highlight sibling under it")
        menu.keyDown(with: down!)
        let selectedHighlight = try require(menuHighlights().first { ($0.layer?.animation(forKey: NoteMotion.highlightKey) as? CASpringAnimation) != nil },
                                            "Selected-index highlight owner")
        let selectedSpring = try require(selectedHighlight.layer?.animation(forKey: NoteMotion.highlightKey) as? CASpringAnimation,
                                         "Keyboard selected-index installs the recovered spring")
        try expect(NoteMotion.matchesRecovered(selectedSpring) && menu.selectedIndex == 0,
                   "Selected-index spring belongs to the original optional keyboard highlight")
        var hops = 0
        while hops < 8, menuButtons(menu).first(where: { $0.tag == menu.selectedIndex })?.state != .on {
            menu.keyDown(with: down!); hops += 1
        }
        menu.layoutSubtreeIfNeeded()
        let checked = try require(menuButtons(menu).first { $0.tag == menu.selectedIndex && $0.state == .on },
                                  "Checked paragraph item under keyboard selection")
        let checkedHighlight = try require(highlight(of: checked), "Highlight sibling of the checked control")
        let fadingIn = (checkedHighlight.layer?.animation(forKey: NoteMotion.highlightKey) as? CASpringAnimation)
            .map { ($0.toValue as? Float) == 1 } ?? false
        try expect(checkedHighlight.alphaValue == 0 && !fadingIn,
                   "Checked keyboard selection does not show a hover highlight over selected fill")
        SystemOverrides.reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        try expect(menuHighlights().allSatisfy { $0.layer?.animation(forKey: NoteMotion.highlightKey) == nil }
                   && menuButtons(menu).allSatisfy { $0.alphaValue == 1 && $0.layer?.animation(forKey: NoteMotion.insertionKey) == nil },
                   "Reduce Motion notification settles selected-index and item springs")
        SystemOverrides.reduceMotion = false
        menu.keyDown(with: down!)
        try expect(menu.selectedIndex != nil, "Keyboard index still advances after Reduce Motion")
        let expansion = try require(menuButtons(menu).first { $0.item == .emphasis }, "Expandable emphasis for opacity transition")
        expansion.performClick(nil); menu.layoutSubtreeIfNeeded()
        try expect(menu.items.count == 14, "Expansion still replaces the group in place")
        let fading = try require(menuButtons(menu).first { $0.item == .emphasis }, "Replaced emphasis remains for opacity fade")
        let fadeOut = try require(fading.layer?.animation(forKey: NoteMotion.insertionKey) as? CASpringAnimation,
                                  "Replaced item uses insertion fade-out")
        try expect(NoteMotion.matchesRecovered(fadeOut), "Removed item opacity uses the recovered spring")
        let inserted = try require(menuButtons(menu).first { $0.item == .action(.bold) }, "Inserted emphasis child")
        let fadeIn = try require(inserted.layer?.animation(forKey: NoteMotion.insertionKey) as? CASpringAnimation,
                                 "Inserted item uses recovered opacity transition")
        try expect(NoteMotion.matchesRecovered(fadeIn), "Item opacity transition uses the menu selected-index spring")
        menu.settleMotion()
        try expect(!menuButtons(menu).contains { $0.item == .emphasis }, "Settled expansion removes the faded source item")
        editor.formatting.dismiss()
        try expect(!editor.formatting.isPresentingMenu,
                   "Original dismiss removes the menu immediately without a dismissal spring")
        editor.formatting.present(range: range, focus: true)
        let presented = try require(window.firstResponder as? NoteFormatMenu, "Re-presented menu")
        try expect(presented.layer?.animation(forKey: NoteMotion.insertionKey) == nil
                   && presented.layer?.animation(forKey: NoteMotion.highlightKey) == nil,
                   "Re-presentation does not invent a menu fade")
        editor.formatting.dismiss()
        body.setSelectedRange(NSRange(location: 0, length: 9))
        editor.formatting.selection.present(focus: true)
        try expect(editor.formatting.selection.isPresenting, "Selection presenter still admits nonempty original text")
        func bars(_ view: NSView) -> [NoteSelectionBar] {
            view.subviews.flatMap { child in (child as? NoteSelectionBar).map { [$0] } ?? bars(child) }
        }
        if let bar = bars(editor.formatting).first {
            try expect(bar.layer?.animation(forKey: NoteMotion.insertionKey) == nil
                       && bar.alphaValue == 1, "Selection presenter adds the bar without a fade")
        }
        editor.formatting.dismiss()
        editor.formatting.retire(); window.contentView = nil
    }

    static func checkFormattingAppearance(light: NSAppearance, dark: NSAppearance) throws {
        func hex(_ color: NSColor, _ appearance: NSAppearance) -> String {
            var result = ""
            appearance.performAsCurrentDrawingAppearance { result = (try? EaselRichTextCodec.hex(color)) ?? "unresolved" }
            return result
        }
        let pairs: [(NSColor, String, String)] = [
            (NoteFormattingAppearance.text, "#6E678DFF", "#8795C1FF"),
            (NoteFormattingAppearance.selectedInk, "#2702C2FF", "#B6C9FAFF"),
            (NoteFormattingAppearance.hover, "#EBEBECFF", "#FFFFFF26"),
            (NoteFormattingAppearance.selected, "#2702C21A", "#062E79FF"),
            (NoteFormattingAppearance.gutterSelected, "#D9D9E0FF", "#FFFFFF4D"),
            (NoteFormattingAppearance.background, "#FFFFFFFF", "#120F2EFF"),
            (NoteFormattingAppearance.border, "#CDCCDFFF", "#34334DFF")
        ]
        for (color, expectedLight, expectedDark) in pairs {
            try expect(hex(color, light) == expectedLight && hex(color, dark) == expectedDark, "Actual named control color retains both shipped variants: \(expectedLight) / \(expectedDark)")
        }
        for action in [NoteFormatAction.text, .heading1, .heading2, .heading3] {
            try expect(hex(NoteFormattingAppearance.ink(for: .action(action), checked: true), dark) == "#8795C1FF", "Factory text/heading foreground overrides checked outer environment")
        }
        for action in [NoteFormatAction.bullets, .numbers, .bold, .italic, .underline, .strikethrough] {
            try expect(hex(NoteFormattingAppearance.ink(for: .action(action), checked: true), dark) == "#B6C9FAFF" && hex(NoteFormattingAppearance.ink(for: .action(action), checked: false), dark) == "#8795C1FF", "Only actual checked glyphs use SelectedMenuItem")
        }
        func render(_ view: NSView, _ appearance: NSAppearance) throws -> NSBitmapImageRep {
            view.appearance = appearance; view.viewDidChangeEffectiveAppearance()
            let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Native control bitmap")
            let context = try require(NSGraphicsContext(bitmapImageRep: bitmap), "Native control drawing context")
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            NSColor.clear.setFill(); view.bounds.fill(using: .copy)
            appearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
            return bitmap
        }
        func pixel(_ image: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
            try require(image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), "Actual rendered control pixel")
        }
        try expect(NoteFormatGlyph.font(for: .bold).fontName == "Nunito-Bold" && NoteFormatGlyph.font(for: .bold).pointSize == 14.4, "Bold uses Nunito-Bold 14.4")
        try expect(NoteFormatGlyph.font(for: .italic).fontName == "Nunito-Italic" && NoteFormatGlyph.font(for: .italic).pointSize == 14.4, "Italic uses Nunito-Italic 14.4")
        try expect(NoteFormatGlyph.font(for: .underline).fontName == "Nunito-Regular" && NoteFormatGlyph.decoration(for: .underline) == .underlineStyle, "Underline is Nunito-Regular with decoration")
        try expect(NoteFormatGlyph.font(for: .strikethrough).fontName == "Nunito-Regular" && NoteFormatGlyph.decoration(for: .strikethrough) == .strikethroughStyle, "Strikethrough is Nunito-Regular with decoration")
        try expect(NoteFormatGlyph.letter(for: .bold) == "B" && NoteFormatGlyph.letter(for: .text) == "Aa", "Recovered compact B/Aa letters")
        let linkGlyph = NoteFormatGlyph.formattedHyperlink(), imageGlyph = NoteFormatGlyph.insertImage()
        try expect(NoteFormatGlyph.iconFontDirectory == Bundle.main.resourceURL?.appendingPathComponent("CustomInfoPicker", isDirectory: true)
                   && FileManager.default.fileExists(atPath: NoteFormatGlyph.iconFontDirectory?.appendingPathComponent("icomoon.ttf").path ?? ""),
                   "Feather glyphs load from the bundle's CustomInfoPicker icomoon.ttf")
        try expect(linkGlyph.size == NSSize(width: 20, height: 20) && linkGlyph.isTemplate, "formattedHyperlink is IconFontImageCache 20pt template")
        try expect(imageGlyph.size == NSSize(width: 20, height: 20) && imageGlyph.isTemplate, "insertImage is IconFontImageCache 20pt template")
        func raster(_ image: NSImage) throws -> [UInt8] {
            let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Glyph bitmap")
            let context = try require(NSGraphicsContext(bitmapImageRep: bitmap), "Glyph drawing context")
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context
            NSColor.clear.setFill(); NSRect(origin: .zero, size: image.size).fill(using: .copy)
            image.draw(in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            return [UInt8](bitmap.tiffRepresentation ?? Data())
        }
        try expect(try raster(linkGlyph) != raster(imageGlyph), "insertImage and formattedHyperlink are distinct Feather contours")
        try expect(NoteFormatGlyph.font(for: .heading1).fontName == "Nunito-Bold", "Heading letters use Nunito-Bold 14.4")
        let gutter = NoteGutterButton(); gutter.highlight(true)
        try expect(gutter.focusRingType == .none, "Gutter does not invent an AppKit focus ring")
        let gutterDark = try render(gutter, dark), gutterLight = try render(gutter, light)
        let darkFill = try pixel(gutterDark, x: 5, y: 5), lightFill = try pixel(gutterLight, x: 5, y: 5)
        try expect(abs(darkFill.alphaComponent - 0.15) < 0.02 && darkFill.redComponent > 0.95 && abs(lightFill.redComponent - 0.922) < 0.03 && lightFill.alphaComponent > 0.98, "Pressed gutter uses hover fill; press is not a unique selected style")
        try expect(gutter.isHighlighted && gutter.contentOpacity == 1, "Gutter redraw does not clear original press state")
        gutter.highlight(false); gutter.showsSelected = true
        let selectedGutter = try render(gutter, dark), selectedGutterFill = try pixel(selectedGutter, x: 5, y: 5)
        try expect(abs(selectedGutterFill.alphaComponent - 0.3) < 0.02 && selectedGutterFill.redComponent > 0.95 && gutter.contentOpacity == 1, "displayAsSelected uses GutterMenuItemSelected independently of press")
        gutter.highlight(true)
        let selectedPressed = try render(gutter, dark), selectedPressedFill = try pixel(selectedPressed, x: 5, y: 5)
        try expect(abs(selectedPressedFill.alphaComponent - 0.3) < 0.02 && selectedPressedFill.redComponent > 0.95 && gutter.isHighlighted && gutter.showsSelected, "Pressed selected gutter keeps GutterMenuItemSelected over hover")
        gutter.highlight(false); gutter.showsSelected = false
        let row = NoteFormatButton(item: .action(.bullets), target: nil, action: nil)
        row.frame = NSRect(x: 0, y: 0, width: 34, height: 34); row.state = .on
        let rowDark = try render(row, dark), selectedFill = try pixel(rowDark, x: 5, y: 5)
        try expect(abs(selectedFill.redComponent - 0.024) < 0.02 && abs(selectedFill.blueComponent - 0.475) < 0.02 && selectedFill.alphaComponent > 0.98, "Actual checked list row uses opaque dark selected background")
        var selectedInk = false, strongest = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        for y in 5..<29 { for x in 5..<29 {
            let c = try pixel(rowDark, x: x, y: y)
            if c.redComponent > strongest.redComponent { strongest = c }
            let coverage = (c.redComponent - 0.024) / (0.714 - 0.024)
            let expectedGreen = 0.180 + coverage * (0.788 - 0.180)
            let expectedBlue = 0.475 + coverage * (0.980 - 0.475)
            if coverage > 0.45 && abs(c.greenComponent - expectedGreen) < 0.04 && abs(c.blueComponent - expectedBlue) < 0.04 { selectedInk = true }
        } }
        try expect(selectedInk, "Real source-owned vector list glyph receives selected dark ink; strongest pixel \(strongest)")
        let selectionText = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let linkedText = NSMutableAttributedString(string: "linked plain", attributes: NoteDocumentAppearance.bodyAttributes)
        linkedText.addAttribute(.link, value: URL(string: "https://example.com/original")!, range: NSRange(location: 0, length: 6))
        selectionText.textStorage?.setAttributedString(linkedText)
        func linkButton(_ range: NSRange) throws -> NoteFormatButton {
            selectionText.setSelectedRange(range)
            let owner = NoteSelectionBar(text: selectionText, ranges: [range], canInteract: { true },
                onFormat: {}, onEmphasis: { _ in }, onLink: {}, onCancel: {})
            func descendants(_ view: NSView) -> [NoteFormatButton] {
                view.subviews.flatMap { ($0 as? NoteFormatButton).map { [$0] } ?? descendants($0) }
            }
            return try require(descendants(owner).first { $0.item == .action(.link) }, "Original Link control")
        }
        let selectedLink = try linkButton(NSRange(location: 0, length: linkedText.length))
        try expect(selectedLink.state == .on, "Mixed primary range starting in real link uses recovered first-character Link flag")
        let plainLink = try linkButton(NSRange(location: 7, length: 5))
        try expect(plainLink.state == .off, "Primary range starting in plain text clears Link checked state")
        selectedLink.frame = NSRect(x: 0, y: 0, width: 34, height: 34)
        selectedLink.highlight(true)
        let pressedLink = try render(selectedLink, dark), linkFill = try pixel(pressedLink, x: 5, y: 5)
        try expect(abs(linkFill.redComponent - 0.024) < 0.02 && abs(linkFill.blueComponent - 0.475) < 0.02 && selectedLink.state == .on, "Actual pressed checked Link keeps selected fill instead of hover and never toggles on mouse-down")
        try expect(selectedLink.focusRingType == .none, "Link control does not invent an AppKit focus ring")
        var linkInk = false
        for y in 5..<29 { for x in 5..<29 {
            let c = try pixel(pressedLink, x: x, y: y)
            let coverage = (c.redComponent - 0.024) / (0.714 - 0.024)
            let expectedGreen = 0.180 + coverage * (0.788 - 0.180)
            let expectedBlue = 0.475 + coverage * (0.980 - 0.475)
            if coverage > 0.45 && abs(c.greenComponent - expectedGreen) < 0.04 && abs(c.blueComponent - expectedBlue) < 0.04 { linkInk = true }
        } }
        try expect(linkInk, "Recovered Feather formattedHyperlink receives selected dark ink")
        row.state = .off; row.highlight(true)
        let pressedRow = try render(row, dark), pressedFill = try pixel(pressedRow, x: 5, y: 5)
        try expect(abs(pressedFill.alphaComponent - 0.15) < 0.02 && pressedFill.redComponent > 0.95 && row.state == .off, "Pressed unchecked menu item uses hover fill, never a unique pressed style")
        row.highlight(false); row.state = .on; row.keyboardSelected = true
        let checkedKeyboard = try render(row, dark), checkedKeyboardFill = try pixel(checkedKeyboard, x: 5, y: 5)
        try expect(abs(checkedKeyboardFill.redComponent - selectedFill.redComponent) < 0.01
                   && abs(checkedKeyboardFill.blueComponent - selectedFill.blueComponent) < 0.01
                   && abs(checkedKeyboardFill.alphaComponent - selectedFill.alphaComponent) < 0.01,
                   "Checked plus keyboard keeps selected fill")
        row.keyboardSelected = false
        let keyboardRange = NSRange(location: 7, length: 5)
        selectionText.setSelectedRange(keyboardRange)
        let keyboardBar = NoteSelectionBar(text: selectionText, ranges: [keyboardRange], canInteract: { true },
            onFormat: {}, onEmphasis: { _ in }, onLink: {}, onCancel: {})
        keyboardBar.appearance = dark; keyboardBar.viewDidChangeEffectiveAppearance()
        keyboardBar.frame = NSRect(x: 0, y: 0, width: 225.5, height: 50.5); keyboardBar.layoutSubtreeIfNeeded()
        func barButtons(_ view: NSView) -> [NoteFormatButton] {
            view.subviews.flatMap { ($0 as? NoteFormatButton).map { [$0] } ?? barButtons($0) }
        }
        let bold = try require(barButtons(keyboardBar).first { $0.item == .action(.bold) && $0.state == .off }, "Unchecked Bold in the selection bar")
        let boldHighlight = try require(highlight(of: bold), "Bold's highlight sibling")
        func renderLayer(_ view: NSView) throws -> NSBitmapImageRep {
            let layer = try require(view.layer, "Layer-backed highlight")
            let bitmap = try require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), "Highlight bitmap")
            let context = try require(NSGraphicsContext(bitmapImageRep: bitmap), "Highlight drawing context")
            layer.render(in: context.cgContext); context.flushGraphics()
            return bitmap
        }
        keyboardBar.restoreKeyboardSelection(bold.tag)
        let hoverFill = try pixel(try renderLayer(boldHighlight), x: 3, y: 3), boldFill = try pixel(try render(bold, dark), x: 5, y: 5)
        try expect(boldHighlight.alphaValue == 1 && abs(hoverFill.alphaComponent - 0.15) < 0.02 && hoverFill.redComponent > 0.95
                   && boldFill.alphaComponent < 0.01 && bold.keyboardSelected && bold.state == .off,
                   "Keyboard focus shows the bar's highlight in the native hover fill; the row draws none and the format stays off")
        bold.highlight(true)
        let pressedBold = try pixel(try render(bold, dark), x: 5, y: 5)
        try expect(pressedBold.alphaComponent < 0.01 && boldHighlight.alphaValue == 1,
                   "Pressing a keyboard-selected row adds no fill of its own: the hover fill shows once, from the highlight")
        bold.highlight(false)
        keyboardBar.restoreKeyboardSelection(nil)
        try expect(boldHighlight.alphaValue == 0 && !bold.keyboardSelected, "Clearing the keyboard selection hides the highlight")
    }

}

@MainActor
private final class NoteComponentWindow: NSWindow {
    var componentKey = true
    var beforeNextFocus: (() -> Void)?
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let commit = beforeNextFocus; beforeNextFocus = nil; commit?()
        return super.makeFirstResponder(responder)
    }
    override var isKeyWindow: Bool { componentKey }
}

private final class NoteComponentTrackingEvent: NSEvent {
    var area: NSTrackingArea?
    override var trackingArea: NSTrackingArea? { area }
}
