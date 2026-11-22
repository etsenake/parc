import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

struct EaselTextStyleTestsEmphasis {
    @MainActor @Test(arguments: [EaselStyledTextView.Emphasis.bold, .italic])
    func authoredFontEmphasisSurvivesNativeFallback(_ emphasis: EaselStyledTextView.Emphasis) throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        var failures = 0
        view.onClipboardError = { _ in failures += 1 }
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        load([.font: fallback, key: original, .foregroundColor: NSColor.black])
        toggle(emphasis)
        #expect(failures == 0 && view.hasEmphasis(emphasis), "Rendered emoji edits the original authored font's trait")
        let payload = try EaselRichTextCodec.snapshot(view.attributedString())
        let font = payload.runs.first!.attributes.font
        #expect(font.size == 26 && font.name != fallback.fontName, "Formatting persists authored size and face instead of glyph fallback")
        #expect(NSFontDescriptor.SymbolicTraits(rawValue: font.traits).contains(emphasis == .bold ? .bold : .italic), "Durable range carries the requested authored emphasis")
    }

    @MainActor @Test(arguments: [EaselStyledTextView.Emphasis.bold, .italic])
    func undoAndRedoRestoreEmphasisDespiteNativeFallback(_ emphasis: EaselStyledTextView.Emphasis) {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        load([.font: fallback, key: original, .foregroundColor: NSColor.black])
        let before = NSAttributedString(attributedString: view.attributedString())
        toggle(emphasis)
        view.undo(nil)
        #expect(view.attributedString().isEqual(to: before), "Native undo restores the original attributed glyph and layout metadata")
        view.redo(nil)
        #expect(view.hasEmphasis(emphasis), "Native redo restores the authored formatting")
    }

    @MainActor @Test(arguments: [EaselStyledTextView.Emphasis.bold, .italic])
    func aFallbackRunReflectsItsAuthoredEmphasis(_ emphasis: EaselStyledTextView.Emphasis) {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        let authored = NSFontManager.shared.convert(original, toHaveTrait: emphasis == .bold ? .boldFontMask : .italicFontMask)
        load([.font: fallback, key: authored])
        #expect(view.hasEmphasis(emphasis), "Checked state follows authored emphasis after native fallback")
    }

    @MainActor @Test(arguments: [EaselStyledTextView.Emphasis.bold, .italic])
    func togglingAFallbackRunRemovesItsAuthoredEmphasis(_ emphasis: EaselStyledTextView.Emphasis) {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        let authored = NSFontManager.shared.convert(original, toHaveTrait: emphasis == .bold ? .boldFontMask : .italicFontMask)
        load([.font: fallback, key: authored])
        toggle(emphasis)
        #expect(!view.hasEmphasis(emphasis), "Toggling a fallback run removes the authored trait")
    }

    @MainActor @Test
    func emphasisKeepsTheExplicitFontFaceAndSize() throws {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        let explicit = NSFont(name: "Times-Roman", size: 21)!
        load([.font: explicit], text: "Authored")
        toggle(.italic)
        let changed = try EaselRichTextCodec.snapshot(view.attributedString()).runs.first!.attributes.font
        #expect(changed.size == 21 && changed.name.hasPrefix("Times"), "Explicit user family and size survive emphasis without fallback metadata")
    }

    enum UnsuitableFont: Int, CaseIterable, CustomTestStringConvertible {
        case unsupportedFace = 1, malformedOriginalFont, unsupportedAttribute

        var testDescription: String {
            switch self {
            case .unsupportedFace: "Unsupported emoji font"
            case .malformedOriginalFont: "Malformed original font metadata"
            case .unsupportedAttribute: "Unsupported attribute on an authored font"
            }
        }
    }

    @MainActor @Test(arguments: UnsuitableFont.allCases)
    func invalidFontMetadataRefusesTheEdit(_ input: UnsuitableFont) {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true
        view.isEditable = true
        view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        var failures = 0
        var boundaries = 0
        view.onClipboardError = { _ in failures += 1 }
        view.onEditBoundary = { boundaries += 1 }

        func load(_ sample: UnsuitableFont) {
            let attributes: [NSAttributedString.Key: Any]
            switch sample {
            case .unsupportedFace:
                attributes = [.font: fallback]
            case .malformedOriginalFont:
                attributes = [.font: original, key: "invalid"]
            case .unsupportedAttribute:
                attributes = [.font: fallback, key: original, NSAttributedString.Key("unsupported-local-attribute"): 1]
            }
            let text = sample == .malformedOriginalFont ? "Authored" : "👋"
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }

        func toggle(_ sample: UnsuitableFont) {
            if sample == .unsupportedFace {
                view.localUndo.beginUndoGrouping()
                view.toggle(.italic)
                view.localUndo.endUndoGrouping()
            } else {
                view.toggle(.bold)
            }
        }

        var beforeRefusal = boundaries
        for preceding in UnsuitableFont.allCases.prefix(while: { $0 != input }) {
            load(preceding)
            if preceding == .malformedOriginalFont { beforeRefusal = boundaries }
            toggle(preceding)
        }
        load(input)
        if input == .malformedOriginalFont { beforeRefusal = boundaries }
        let before = NSAttributedString(attributedString: view.attributedString())
        toggle(input)
        #expect(failures == input.rawValue && view.attributedString().isEqual(to: before))
        if input != .unsupportedFace {
            #expect(boundaries == beforeRefusal)
        }
    }

    @MainActor @Test
    func caretFormattingLeavesTheAuthoredTextInPlace() {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = true; view.isEditable = true; view.localUndo.groupsByEvent = false
        let key = NSAttributedString.Key("NSOriginalFont")
        let original = NSFont.systemFont(ofSize: 26)
        let fallback = NSFont(name: "AppleColorEmoji", size: 26)!
        func load(_ attributes: [NSAttributedString.Key: Any], text: String = "👋") {
            view.textStorage!.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            view.localUndo.removeAllActions()
            view.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        }
        func toggle(_ emphasis: EaselStyledTextView.Emphasis) {
            view.localUndo.beginUndoGrouping(); view.toggle(emphasis); view.localUndo.endUndoGrouping()
        }
        load([.font: fallback, key: original])
        view.setSelectedRange(NSRange(location: view.attributedString().length, length: 0))
        view.typingAttributes = [.font: fallback, key: original]
        toggle(.italic)
        #expect(view.hasEmphasis(.italic) && view.typingAttributes[key] == nil, "Collapsed formatting normalizes only native original-font metadata")
        #expect(view.string == "👋", "Collapsed formatting preserves existing text")
    }
}
