import CoreGraphics
import Foundation
import Testing
@testable import ParcCore

enum NotePDFBlockTestsSupport {
    static func pdf(_ configure: (inout NoteBlockProps) -> Void) -> NoteBlock {
        var props = NoteBlockProps()
        configure(&props)
        return NoteBlock(.pdf, props: props)
    }
}
