import Foundation
import Testing
@testable import ParcCore

struct EaselRichTextFontStyleTests {
    @MainActor private static func session(style: EaselTextStyle?) throws -> EaselSession {
        let font = EaselRichText.Font(name: "Helvetica", size: 14, style: style)
        let run = EaselRichText.Run(location: 0, length: 5, attributes: .init(font: font, ink: "#000000FF"))
        let item = EaselItem(kind: .text, frame: EaselRect(x: 0, y: 0, width: 200, height: 40), text: "Hello", richText: EaselRichText(runs: [run]))
        let date = Date(timeIntervalSinceReferenceDate: 0)
        return try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Styled", createdAt: date, modifiedAt: date, items: [item]), assets: [:])
    }

    @MainActor @Test(arguments: [1e300, -1e300, 400.5, 7.0, 0.0, -12.0])
    func aRunWhoseSavedFontStyleHasAnAbsurdSizeIsRefusedInsteadOfReachingTheFontSystem(size: Double) {
        #expect(throws: EaselStoreError.self) { try Self.session(style: EaselTextStyle(customSize: size)) }
    }

    @MainActor @Test(arguments: [0.1, 9.0, 1e300, -1.0])
    func aRunWhoseSavedFontStyleHasABrokenTextScaleIsRefused(scale: Double) {
        #expect(throws: EaselStoreError.self) { try Self.session(style: EaselTextStyle(textScale: scale)) }
    }

    @MainActor @Test func ordinaryFontStylesStillLoad() throws {
        let presets = EaselTextStyle.Family.allCases.flatMap { family in
            EaselTextStyle.Size.allCases.map { EaselTextStyle(family: family, size: $0) }
        }
        for style in presets + [EaselTextStyle(customSize: 8), EaselTextStyle(customSize: 400), EaselTextStyle(textScale: 2)] {
            _ = try Self.session(style: style)
        }
        _ = try Self.session(style: nil)
    }
}
