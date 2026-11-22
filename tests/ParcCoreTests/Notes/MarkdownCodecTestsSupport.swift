import Foundation
import Testing
@testable import ParcCore

enum MarkdownCodecTestsSupport {
    struct SourceCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let markdown: String

        init(_ label: String, _ markdown: String) {
            testDescription = label
            self.markdown = markdown
        }
    }
}
