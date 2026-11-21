import Foundation
import Testing
@testable import ParcCore

struct NoteFileKindTests {
    @Test(arguments: ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "MD"])
    func everyMarkdownExtensionTheAppClaimsOpensAsMarkdown(_ pathExtension: String) {
        #expect(NoteFileKind(pathExtension: pathExtension) == .markdown)
    }

    @Test(arguments: ["txt", "text"])
    func plainTextExtensionsOpenAsPlainText(_ pathExtension: String) {
        #expect(NoteFileKind(pathExtension: pathExtension) == .plainText)
    }

    @Test func otherFilesAndWebAddressesAreNotNotes() {
        #expect(NoteFileKind(pathExtension: "html") == nil)
        #expect(NoteFileKind(url: URL(string: "https://example.test/readme.md")!) == nil)
        #expect(NoteFileKind(url: URL(fileURLWithPath: "/tmp/readme.md")) == .markdown)
    }
}
