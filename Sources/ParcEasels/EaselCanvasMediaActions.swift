import AppKit
import ParcCore

struct EaselMediaAction {
    var action: EaselHostedAction
    var title: String
    var symbol: String

    var id: String { "media." + Self.key(action) }

    static func key(_ action: EaselHostedAction) -> String {
        switch action {
        case .play: return "play"
        case .pause: return "pause"
        case .stopAll: return "stop"
        case .quickLook: return "quick-look"
        case .fullScreen: return "full-screen"
        case .download: return "download"
        case .replace: return "replace"
        case .upload: return "upload"
        case .unsplash: return "unsplash"
        case .embedLink: return "embed-link"
        case .viewOriginal: return "view-original"
        }
    }

    static let catalog: [EaselMediaAction] = [
        EaselMediaAction(action: .upload, title: "Upload…", symbol: "square.and.arrow.up"),
        EaselMediaAction(action: .embedLink, title: "Embed link", symbol: "link"),
        EaselMediaAction(action: .unsplash, title: "Unsplash…", symbol: "photo.on.rectangle.angled"),
        EaselMediaAction(action: .replace, title: "Replace…", symbol: "arrow.triangle.2.circlepath"),
        EaselMediaAction(action: .quickLook, title: "Quick Look", symbol: "eye"),
        EaselMediaAction(action: .fullScreen, title: "Full Screen", symbol: "arrow.up.left.and.arrow.down.right"),
        EaselMediaAction(action: .download, title: "Download", symbol: "arrow.down.to.line"),
        EaselMediaAction(action: .viewOriginal, title: "View Original", symbol: "arrow.up.right.square"),
    ]

    static func offered(for item: EaselItem) -> [EaselHostedAction] {
        if item.isEmptyPlaceholder { return item.kind == .image ? [.upload, .embedLink, .unsplash] : [.upload, .embedLink] }
        switch item.kind {
        case .image: return [.replace, .quickLook, .fullScreen, .download, .viewOriginal]
        case .pdf: return [.replace, .fullScreen, .download, .viewOriginal]
        case .video, .audio, .file: return [.replace, .quickLook, .download, .viewOriginal]
        default: return []
        }
    }
}

extension EaselCanvasView {
    func mediaActions(for item: EaselItem) -> [EaselMediaAction] {
        guard item.kind.isMedia, imageEditing.crop == nil else { return [] }
        let offered = EaselMediaAction.offered(for: item)
        return EaselMediaAction.catalog.filter { offered.contains($0.action) && canPerformHostedAction($0.action, on: item) }
    }

    var soleMediaSelection: EaselItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return session.document.items.first { $0.id == id && $0.kind.isMedia }
    }

    func mediaToolbarEntries(ready: Bool) -> [EaselToolbarMenuEntry] {
        guard let item = soleMediaSelection else { return [] }
        return mediaActions(for: item).enumerated().map { index, action in
            EaselToolbarMenuEntry(id: action.id, title: action.title, symbol: action.symbol, isEnabled: ready, separatorBefore: index == 0)
        }
    }

    func performMediaToolbarEntry(_ id: String) -> Bool? {
        guard id.hasPrefix("media."), let item = soleMediaSelection else { return nil }
        guard let action = mediaActions(for: item).first(where: { $0.id == id }) else { return false }
        return performHostedAction(action.action, on: item.id)
    }

    func mediaActionRows(_ item: EaselItem, separated: Bool) -> [EaselMenuRow] {
        mediaActions(for: item).enumerated().map { index, action in
            EaselMenuRow(id: action.id, title: action.title, symbol: action.symbol, separatorBefore: separated && index == 0,
                         perform: guardedMenuAction { canvas in _ = canvas.performHostedAction(action.action, on: item.id) })
        }
    }
}
