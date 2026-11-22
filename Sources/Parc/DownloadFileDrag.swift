import AppKit

@MainActor final class DownloadFileDrag: NSObject {
    let item = NSPasteboardItem()
    private var resolve: (() -> URL?)?
    private let originalURL: URL
    private let provider = Provider()
    init?(resolve: @escaping () -> URL?) {
        guard let url = resolve(), url.isFileURL else { return nil }
        originalURL = url; self.resolve = resolve
        super.init()
        provider.owner = self
        item.setDataProvider(provider, forTypes: [.fileURL])
    }
    func invalidate() { resolve = nil; provider.owner = nil }
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .fileURL, item === self.item, let url = resolve?(), url == originalURL else { return }
        item.setString(url.absoluteString, forType: .fileURL)
    }

    @MainActor private final class Provider: NSObject, NSPasteboardItemDataProvider {
        weak var owner: DownloadFileDrag?
        nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                                    provideDataForType type: NSPasteboard.PasteboardType) {
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { owner?.pasteboard(pasteboard, item: item, provideDataForType: type) }
        }
        nonisolated func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            if Thread.isMainThread { MainActor.assumeIsolated { owner?.invalidate() } }
            else { Task { @MainActor [weak self] in self?.owner?.invalidate() } }
        }
    }
}
