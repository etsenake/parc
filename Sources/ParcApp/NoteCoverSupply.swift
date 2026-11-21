import Foundation

@MainActor
final class NoteCoverSupply {
    static let shared = NoteCoverSupply()

    private var encoded: [String: Data] = [:]
    private var warming: Set<String> = []
    private var next: String?

    static func install() {
        NoteLibrary.newNoteCover = { shared.take() }
    }

    func take() -> NoteNewCover? {
        defer { warmNext() }
        guard let (style, data) = pick() else { return nil }
        return NoteNewCover(data: data, fileExtension: NoteCoverGallery.fileExtension,
                            suggestedName: NoteCoverGallery.suggestedName(for: style))
    }

    private func pick() -> (NoteCoverStyle, Data)? {
        if let id = next, let data = encoded[id], let style = NoteCoverGallery.style(id: id) {
            next = nil
            return (style, data)
        }
        if let id = encoded.keys.randomElement(), let data = encoded[id], let style = NoteCoverGallery.style(id: id) {
            return (style, data)
        }
        let style = NoteCoverGallery.randomStyle()
        guard let data = NoteCoverGallery.assetData(for: style) else { return nil }
        encoded[style.id] = data
        return (style, data)
    }

    private func warmNext() {
        let id = NoteCoverGallery.randomStyle().id
        next = id
        guard encoded[id] == nil, !warming.contains(id) else { return }
        warming.insert(id)
        Task { @MainActor in
            let data = await Task.detached(priority: .utility) { () -> Data? in
                NoteCoverGallery.style(id: id).flatMap { NoteCoverGallery.assetData(for: $0) }
            }.value
            warming.remove(id)
            if let data { encoded[id] = data }
        }
    }
}
