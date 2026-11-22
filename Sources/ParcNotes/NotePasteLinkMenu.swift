import AppKit
import ParcCore

@MainActor
package final class NotePasteLinkMenu {
    package enum Choice: String {
        case dismiss, link, mention, bookmark, embed, easel, pdf, image, video, audio

        var blockKind: NoteBlockKind {
            switch self {
            case .pdf: return .pdf
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            case .bookmark: return .bookmark
            case .easel: return .easel
            case .dismiss, .link, .mention, .embed: return .embed
            }
        }

        var title: String {
            switch self {
            case .dismiss: return "Dismiss"
            case .link: return "Link"
            case .mention: return "Mention"
            case .bookmark: return "Bookmark"
            case .embed: return "Embed"
            case .easel: return "Easel"
            case .pdf: return "PDF"
            case .image: return "Image"
            case .video: return "Video"
            case .audio: return "Audio"
            }
        }
    }

    package enum Place {
        case note, easel

        var phrase: String { self == .note ? "in the note" : "on the Easel" }
    }

    let url: URL
    package let list: NoteMenuList
    private let panel: NoteFloatingPanel
    private let place: Place
    private let onChoose: (Choice) -> Void

    package init(url: URL, leading: [Choice], embeddable: Bool, media: NoteBlockKind? = nil, place: Place = .note,
         easelIcon: NoteIcon = .easelMark, onChoose: @escaping (Choice) -> Void) {
        self.url = url
        self.place = place
        self.onChoose = onChoose
        let list = NoteMenuList()
        self.list = list
        list.rowStyle = .detailed
        list.items = Self.items(for: url, leading: leading, embeddable: embeddable, media: media, place: place, easelIcon: easelIcon)
        list.prepare(origin: .keyboard)
        panel = NoteFloatingPanel(content: list)
        list.onActivate = { [weak self] item in
            guard let choice = Choice(rawValue: item.id) else { return }
            self?.onChoose(choice)
        }
        list.onCancel = { [weak self] in self?.onChoose(.dismiss) }
        list.setAccessibilityLabel("Paste link as")
    }

    static func items(for url: URL, leading: [Choice], embeddable: Bool, media: NoteBlockKind?, place: Place,
                      easelIcon: NoteIcon = .easelMark) -> [NoteMenuList.Item] {
        var items = leading.compactMap { row(for: $0, place: place) }
        if let media { insert(media, into: &items, place: place) }
        if place == .note, NoteEaselAddress.id(from: url) != nil {
            items.removeAll { $0.id == Choice.bookmark.rawValue }
            items.append(.init(id: Choice.easel.rawValue, title: "Easel", subtitle: "Show the Easel right in the note",
                               icon: easelIcon, section: "Paste as"))
        }
        if embeddable, let embed = row(for: .embed, place: place) { items.append(embed) }
        return items
    }

    static func row(for choice: Choice, place: Place) -> NoteMenuList.Item? {
        switch choice {
        case .dismiss: return .init(id: choice.rawValue, title: "Dismiss", subtitle: "Keep it as a link", icon: .symbol("link"), section: "Paste as")
        case .link: return .init(id: choice.rawValue, title: "Link", subtitle: "Text that opens it", icon: .symbol("link"), section: "Paste as")
        case .mention: return .init(id: choice.rawValue, title: "Mention", subtitle: "A tidy inline chip", icon: .symbol("at"), section: "Paste as")
        case .bookmark: return .init(id: choice.rawValue, title: "Bookmark", subtitle: "A card with a preview", icon: .symbol("bookmark"), section: "Paste as")
        case .embed: return .init(id: choice.rawValue, title: "Embed", subtitle: "Show it right " + place.phrase, icon: .symbol("play.rectangle"), section: "Paste as")
        case .image: return .init(id: choice.rawValue, title: "Image", subtitle: "Show the picture " + place.phrase, icon: .symbol("photo"), section: "Paste as")
        case .video: return .init(id: choice.rawValue, title: "Video", subtitle: "Play it right " + place.phrase, icon: .symbol("play.rectangle"), section: "Paste as")
        case .audio: return .init(id: choice.rawValue, title: "Audio", subtitle: "Play it right " + place.phrase, icon: .symbol("waveform"), section: "Paste as")
        case .pdf: return .init(id: choice.rawValue, title: "PDF", subtitle: "Read it right " + place.phrase, icon: .symbol("doc.richtext"), section: "Paste as")
        case .easel: return nil
        }
    }

    static func choice(for kind: NoteBlockKind) -> Choice? {
        switch kind {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .pdf: return .pdf
        default: return nil
        }
    }

    package func present(in host: NSView, anchor: NSRect, edge: NoteFloatingPanel.Edge = .below) {
        panel.present(in: host, anchor: anchor, edge: edge, animated: true)
    }

    func reposition(anchor: NSRect) {
        panel.reposition(anchor: anchor, edge: panel.resolvedEdge, animated: false)
    }

    package var isPresented: Bool { panel.isPresented }

    package func contains(windowPoint point: NSPoint) -> Bool {
        panel.window != nil && panel.bounds.contains(panel.convert(point, from: nil))
    }

    package func offer(_ kind: NoteBlockKind) {
        var items = list.items
        let highlighted = list.highlightedIndex.flatMap { items.indices.contains($0) ? items[$0].id : nil }
        guard Self.insert(kind, into: &items, place: place) else { return }
        list.items = items
        if let highlighted, let index = items.firstIndex(where: { $0.id == highlighted }) { list.highlightedIndex = index }
    }

    @discardableResult
    private static func insert(_ kind: NoteBlockKind, into items: inout [NoteMenuList.Item], place: Place) -> Bool {
        guard let choice = choice(for: kind), let row = row(for: choice, place: place),
              !items.contains(where: { $0.id == row.id }) else { return false }
        if kind == .pdf { items.append(row) } else { items.insert(row, at: min(1, items.count)) }
        return true
    }

    package func dismiss() {
        panel.dismiss(animated: true)
    }
}
