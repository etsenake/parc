import AppKit
import ParcCore

extension NoteIcon {
    @MainActor
    static func easel(_ id: UUID, directory: URL) -> NoteIcon {
        switch EaselTabIcons.shared.lookup(directory: directory, id: id) {
        case .known(.emoji(let value)?): return .emoji(value)
        case .known(.image(let url)?): return NoteCustomEmojiImages.image(at: url) != nil ? .image(url) : .easelMark
        case .known(nil), .pending: return .easelMark
        }
    }
}
