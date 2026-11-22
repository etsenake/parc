import AppKit
import CoreText
import Testing
@testable import Parc
@testable import ParcCore

enum EaselTextStyleTestsSupport {
    static let bundledFonts: Void = {
        let names = ["SpaceMono-Regular", "SpaceMono-Bold", "EBGaramond-VariableFont_wght",
                     "ParcWide-Regular", "ParcWide-SemiBold", "ParcWide-Black"]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "EaselFonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    @MainActor
    static func setRTF(_ text: NSAttributedString, on board: NSPasteboard) throws {
        let rtf = try text.data(from: NSRange(location: 0, length: text.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        board.clearContents()
        board.setData(rtf, forType: .rtf)
    }

    @MainActor
    final class Editor {
        let view = EaselStyledTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let usesMarkdownTyping: Bool

        init(usesMarkdownTyping: Bool = false) {
            self.usesMarkdownTyping = usesMarkdownTyping
            view.isRichText = true
            view.isEditable = true
            view.allowsUndo = true
            view.localUndo.groupsByEvent = false
        }

        func grouped(_ action: () -> Void) {
            view.localUndo.beginUndoGrouping()
            action()
            view.localUndo.endUndoGrouping()
        }

        func load(_ string: String) {
            view.textStorage!.setAttributedString(EaselTextAppearance.attributed(string, style: .init(), color: "#252525"))
            if usesMarkdownTyping {
                view.typingAttributes = EaselTextAppearance.attributed("a", style: .init(), color: "#252525").attributes(at: 0, effectiveRange: nil)
            }
            view.localUndo.removeAllActions()
            let length = (string as NSString).length
            view.setSelectedRange(usesMarkdownTyping ? NSRange(location: length, length: 0) : NSRange(location: 0, length: length))
        }

        func type(_ string: String) {
            for character in string {
                grouped { view.insertText(String(character), replacementRange: view.selectedRange()) }
            }
        }
    }
}
