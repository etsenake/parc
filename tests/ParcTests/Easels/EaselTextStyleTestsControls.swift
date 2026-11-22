import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcNotes
@testable import ParcEasels

struct EaselTextStyleTestsControls {
    @MainActor @Test
    func emptyLocalHistoryFallsBackToDocumentUndo() {
        let view = EaselStyledTextView(frame: .zero)
        #expect(view.undoManager === view.localUndo, "Text input owns its native undo manager")
        var fallback = 0
        view.onUndoDocument = { fallback += 1 }
        view.undo(nil)
        #expect(fallback == 1, "Empty local history reaches document undo")
    }

    @MainActor @Test
    func theToolbarScrollsWithoutReducingControlHeight() {
        let toolbar = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 44))
        toolbar.scrollerStyle = .legacy
        EaselAppearance.configureToolbarScroll(toolbar)
        toolbar.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 448, height: 44))
        toolbar.tile()
        #expect(toolbar.scrollerStyle == .overlay, "Tool strip explicitly overrides legacy scrollbars with overlay presentation")
        #expect(toolbar.contentSize.height >= 44 && toolbar.contentSize.width < 448, "Narrow native toolbar preserves full control height while requiring horizontal scrolling")
    }

    @MainActor @Test
    func bodyTextCanOnlyGrow() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        #expect(!EaselTextStyleState.canResize(by: -1, styles: [.init()], editor: nil)
               && EaselTextStyleState.canResize(by: 1, styles: [.init()], editor: nil), "Body style offers only the bigger step")
    }

    @MainActor @Test
    func theLargestTextCanOnlyShrink() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        #expect(EaselTextStyleState.canResize(by: -1, styles: [.init(size: .ultra)], editor: nil)
               && !EaselTextStyleState.canResize(by: 1, styles: [.init(size: .ultra)], editor: nil), "Largest text style offers only the smaller step")
    }

    @MainActor @Test
    func theDisplayedFamilyMustBeSharedAcrossTheSelection() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        #expect(EaselTextStyleState.family(of: [.init(family: .mono), .init(family: .mono)], editor: nil) == .mono
               && EaselTextStyleState.family(of: [.init(family: .mono), .init(family: .hip)], editor: nil) == nil, "Typeface shows only when every object shares it")
    }

    @MainActor @Test
    func theDisplayedSizeMustBeSharedAcrossTheSelection() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        #expect(EaselTextStyleState.size(of: [.init(size: .h1)], editor: nil) == .h1
               && EaselTextStyleState.size(of: [.init(size: .h1), .init()], editor: nil) == nil, "Size shows only when every object shares it")
    }

    @MainActor @Test
    func editingShowsTheSelectedRangeStyle() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        let editor = EaselStyledTextView(frame: NSRect(x: 400, y: 20, width: 300, height: 100))
        editor.textStorage?.setAttributedString(EaselTextAppearance.attributed("Keep original text", style: .init(family: .fancy), color: "#194B93"))
        editor.setSelectedRange(NSRange(location: 0, length: 4)); root.addSubview(editor)
        #expect(EaselTextStyleState.family(of: [.init()], editor: editor) == .fancy, "Editing reads the selected range's typeface, not the object's")
        #expect(EaselTextStyleState.size(of: [.init(size: .ultra)], editor: editor) == .body, "Editing reads the selected range's size")
    }

    @MainActor @Test
    func editingBodyTextCannotShrinkTheRange() {
        _ = EaselTextStyleTestsSupport.bundledFonts
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        let editor = EaselStyledTextView(frame: NSRect(x: 400, y: 20, width: 300, height: 100))
        editor.textStorage?.setAttributedString(EaselTextAppearance.attributed("Keep original text", style: .init(family: .fancy), color: "#194B93"))
        editor.setSelectedRange(NSRange(location: 0, length: 4)); root.addSubview(editor)
        #expect(!EaselTextStyleState.canResize(by: -1, styles: [.init(size: .ultra)], editor: editor), "Body-size ranges cannot shrink further")
    }

    @MainActor @Test
    func toolbarDrawingUsesTheNotePalette() {
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        let pill = EaselToolbarPill(frame: NSRect(x: 20, y: 220, width: 260, height: EaselAppearance.toolbarHeight))
        root.addSubview(pill)
        let selectedTool = EaselPaletteButton(title: "A", target: nil, action: nil)
        selectedTool.usesToolbarInk = true; selectedTool.font = NoteTheme.nunitoExtraBold(16)
        selectedTool.frame = NSRect(x: 8, y: 6, width: EaselAppearance.toolbarButton, height: EaselAppearance.toolbarButton)
        selectedTool.state = .on; pill.addSubview(selectedTool)
        root.appearance = NSAppearance(named: .aqua)
        root.layoutSubtreeIfNeeded()
        func pixels(_ view: NSView) -> NSBitmapImageRep {
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        let fill = pixels(pill).colorAt(x: 240, y: 18)!.usingColorSpace(.sRGB)!
        #expect(fill.redComponent > 0.95 && fill.greenComponent > 0.95 && fill.blueComponent > 0.95 && fill.alphaComponent > 0.9,
               "Easel tool pill is the Notes format-bar card in light appearance")
        let selected = pixels(selectedTool).colorAt(x: 14, y: 14)!.usingColorSpace(.sRGB)!
        #expect(selected.blueComponent > selected.redComponent && selected.blueComponent > selected.greenComponent && selected.alphaComponent > 0,
               "The selected tool cell takes the Notes checked fill")
    }

    @MainActor @Test
    func theDocumentInheritsItsSpacesAppearance() {
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        root.inheritSpaceContentAppearance(nil)
        #expect(root.appearance == nil, "Easel paper inherits owner appearance without forcing Aqua")
        let dark = NSAppearance(named: .darkAqua)!
        root.inheritSpaceContentAppearance(dark)
        #expect(root.appearance == dark, "Document host applies Space contentOverBackgroundAppearance DarkAqua")
        var paperHex = "", notesPaperHex = ""
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            paperHex = (try? EaselRichTextCodec.hex(EaselAppearance.paper)) ?? "unresolved"
            notesPaperHex = (try? EaselRichTextCodec.hex(NoteTheme.paper)) ?? "unresolved"
        }
        #expect(paperHex == notesPaperHex && paperHex == "#00000080", "Inherited dark appearance resolves Easel paper to the Notes paper")
    }

    @MainActor @Test
    func removingTheSpacesAppearanceClearsTheOverride() {
        let root = EaselDocumentView(frame: NSRect(x: 0, y: 0, width: 760, height: 300))
        let dark = NSAppearance(named: .darkAqua)!
        root.inheritSpaceContentAppearance(dark)
        root.inheritSpaceContentAppearance(nil)
        #expect(root.appearance == nil, "Absent contentOverBackgroundAppearance clears the local override")
    }
}
