import AppKit
import ParcCore
import ParcNotes

@MainActor
final class EaselIconEnvironment: NoteEnvironment {
    private let session: EaselSession
    let files: NoteFiles
    let emojiLibrary: NoteEmojiLibrary?

    init(session: EaselSession, easelIcons: EaselTabIcons? = nil) {
        self.session = session
        let easelIcons = easelIcons ?? .shared
        files = easelIcons.files
        emojiLibrary = session.storeDirectory
            .flatMap(easelIcons.notesFolder)
            .map(easelIcons.files.emojiLibrary(root:))
    }

    var documentURL: URL? { nil }
    var isPlainText: Bool { false }

    func resolve(_ source: String) -> URL? {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = NoteCustomEmojiName.name(inReference: value) { return emojiLibrary?.imageURL(named: name) }
        if EaselAssetType.of(assetID: value) != nil { return try? session.assetURL(value) }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    func importAsset(from url: URL) throws -> String {
        guard url.isFileURL else { return url.absoluteString }
        guard let data = NoteCustomEmojiImages.preparedPNG(contentsOf: url) else { throw EaselStoreError.invalidImage }
        return try session.importAsset(data, type: .png)
    }

    func importAsset(data: Data, fileExtension: String, suggestedName: String?) throws -> String {
        guard let png = NoteCustomEmojiImages.preparedPNG(from: data) else { throw EaselStoreError.invalidImage }
        return try session.importAsset(png, type: .png)
    }

    func searchNotes(_ query: String, limit: Int) -> [NoteReference] { [] }
    func linkTarget(for note: URL) -> String { note.absoluteString }
    func resolveNoteLink(_ target: String) -> URL? { nil }
}

extension EaselPageIcon {
    init?(raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = NoteCustomEmojiName.name(inReference: value), let icon = EaselPageIcon.custom(named: name) {
            self = icon
        } else if let icon = EaselPageIcon.emoji(value) ?? EaselPageIcon.image(assetID: value) {
            self = icon
        } else {
            return nil
        }
    }

    var raw: String {
        kind == .custom ? NoteCustomEmojiName.reference(value) : value
    }
}
