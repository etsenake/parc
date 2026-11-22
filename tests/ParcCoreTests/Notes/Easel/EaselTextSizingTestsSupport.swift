import Foundation
import Testing
@testable import ParcCore

enum EaselTextSizingTestsSupport {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    static func expectThrows(_ message: String, _ body: () throws -> Void) {
        #expect(throws: (any Error).self, Comment(rawValue: message)) { try body() }
    }

    static func text(_ frame: EaselRect = EaselRect(x: 100, y: 100, width: 200, height: 28),
                     style: EaselTextStyle? = nil, kind: EaselItemKind = .text) -> EaselItem {
        var item = EaselItem(kind: kind, frame: frame, text: "Hello")
        item.textStyle = style
        return item
    }

    static func paragraph(indent: Double) -> EaselRichText.Paragraph {
        EaselRichText.Paragraph(alignment: 4, direction: -1, lineBreak: 0, firstIndent: 0, headIndent: indent, tailIndent: 0,
                                lineSpacing: 0, before: 4, after: 8, minimumHeight: 0, maximumHeight: 0, heightMultiple: 1.25,
                                hyphenation: 0, tightening: 0, allowsTightening: false, defaultHyphenation: false, defaultTab: 0,
                                tabs: [.init(alignment: 2, location: 16), .init(alignment: 0, location: indent)],
                                lists: [.init(marker: "{disc}", options: 0, start: 1)])
    }
}
