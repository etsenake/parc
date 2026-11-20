import AppKit

@MainActor
final class NoteEmbedBlockView: NoteLinkBlockView {
    override var style: Style { .embed }
}
