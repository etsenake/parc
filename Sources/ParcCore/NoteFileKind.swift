import Foundation

package enum NoteFileKind: String, Hashable, Codable {
    case markdown, plainText

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"]
    static let plainTextExtensions: Set<String> = ["txt", "text"]

    package init?(pathExtension: String) {
        let value = pathExtension.lowercased()
        if Self.markdownExtensions.contains(value) { self = .markdown }
        else if Self.plainTextExtensions.contains(value) { self = .plainText }
        else { return nil }
    }

    package init?(url: URL) {
        guard url.isFileURL else { return nil }
        self.init(pathExtension: url.pathExtension)
    }
}
