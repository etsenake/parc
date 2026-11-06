import AppKit
import QuickLookThumbnailing

/// The Library owns the cache; a file path alone is never a cache identity.
/// Only policy-approved completed files enter Quick Look, and no directory is
/// enumerated or file decoded synchronously on the main thread.
@MainActor final class DownloadThumbnailProvider {
    struct Key: Hashable {
        let item: DownloadLibraryIdentity
        let url: URL
        let bytes: Int64
        func admits(_ current: BrowserDownload, url currentURL: URL?) -> Bool {
            current.canCopyFile && DownloadLibraryIdentity(current) == item
                && current.receivedBytes == bytes && currentURL == url
        }
    }
    enum Delivery {
        case provisional(NSImage)
        case finished(NSImage?)
    }
    typealias Loader = @MainActor (URL, @escaping @MainActor (Delivery) -> Void) -> (() -> Void)
    private let loader: Loader
    private var cache: [Key: NSImage] = [:]
    private var order: [Key] = []
    private var pending: [UUID: () -> Void] = [:]
    private var generation: UInt64 = 0

    init(loader: @escaping Loader = DownloadThumbnailProvider.quickLook) { self.loader = loader }

    @discardableResult func request(_ key: Key, valid: @escaping () -> Bool,
                                    completion: @escaping (NSImage?) -> Void) -> UUID? {
        guard valid() else { return nil }
        if let image = cache[key] { completion(image); return nil }
        let token = UUID(), originalGeneration = generation
        pending[token] = {}
        let cancel = loader(key.url) { [weak self] delivery in
            guard let self, self.generation == originalGeneration,
                  self.pending[token] != nil else { return }
            guard valid() else { self.cancel(token); return }
            // Validation can call the original native file owner and reenter.
            guard self.generation == originalGeneration, self.pending[token] != nil else { return }
            let image: NSImage?
            switch delivery {
            case let .provisional(value): image = value
            case let .finished(value):
                self.pending.removeValue(forKey: token)
                image = value
                if let image {
                    self.cache[key] = image; self.order.removeAll { $0 == key }; self.order.append(key)
                    while self.order.count > 64 { self.cache.removeValue(forKey: self.order.removeFirst()) }
                }
            }
            completion(image)
        }
        // An injected/native completion may already have finished synchronously.
        if pending[token] != nil { pending[token] = cancel } else { cancel() }
        return token
    }
    func cancel(_ token: UUID?) {
        guard let token, let cancel = pending.removeValue(forKey: token) else { return }
        cancel()
    }
    func invalidate() {
        generation &+= 1
        let requests = pending.values; pending.removeAll()
        cache.removeAll(); order.removeAll()
        for cancel in requests { cancel() }
    }
    private static func quickLook(_ url: URL, completion: @escaping @MainActor (Delivery) -> Void) -> () -> Void {
        let request = DownloadArtworkRequest(url: url, completion: completion)
        request.start()
        return { request.cancel() }
    }
}

/// File icon and low-quality thumbnail are independent original-file producers.
/// The icon may appear first; a late icon never overwrites a real thumbnail.
@MainActor final class DownloadArtworkRequest {
    typealias ImageLoader = @MainActor (URL, @escaping @MainActor (NSImage?) -> Void) -> (() -> Void)
    private let url: URL
    private let iconLoader: ImageLoader, thumbnailLoader: ImageLoader
    private var completion: (@MainActor (DownloadThumbnailProvider.Delivery) -> Void)?
    private var cancelIcon: (() -> Void)?, cancelThumbnail: (() -> Void)?
    private var fallback: NSImage?
    private var iconFinished = false, thumbnailFinished = false, finished = false, started = false

    init(url: URL, iconLoader: @escaping ImageLoader = DownloadArtworkRequest.fileIcon,
         thumbnailLoader: @escaping ImageLoader = DownloadArtworkRequest.thumbnail,
         completion: @escaping @MainActor (DownloadThumbnailProvider.Delivery) -> Void) {
        self.url = url; self.completion = completion
        self.iconLoader = iconLoader; self.thumbnailLoader = thumbnailLoader
    }
    func start() {
        guard !started, !finished else { return }; started = true
        let icon = iconLoader(url) { [weak self] image in
            guard let self, !self.finished else { return }
            self.iconFinished = true; self.fallback = image
            if self.thumbnailFinished { self.finish(image) }
            else if let image { self.completion?(.provisional(image)) }
        }
        if finished { icon(); return }; cancelIcon = icon
        let thumbnail = thumbnailLoader(url) { [weak self] image in
            guard let self, !self.finished else { return }
            self.thumbnailFinished = true
            if let image { self.finish(image) }
            else if self.iconFinished { self.finish(self.fallback) }
        }
        if finished { thumbnail() } else { cancelThumbnail = thumbnail }
    }
    private func finish(_ image: NSImage?) {
        guard !finished else { return }
        finished = true; cancelIcon?(); cancelIcon = nil; cancelThumbnail = nil
        let callback = completion; completion = nil
        callback?(.finished(image))
    }
    func cancel() {
        guard !finished else { return }
        finished = true; completion = nil
        let icon = cancelIcon, thumbnail = cancelThumbnail
        cancelIcon = nil; cancelThumbnail = nil
        icon?(); thumbnail?()
    }
    private static func fileIcon(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> () -> Void {
        let path = url.path
        let work = DispatchWorkItem {
            let image = NSWorkspace.shared.icon(forFile: path)
            DispatchQueue.main.async { completion(image) }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
        return { work.cancel() }
    }

    private static func thumbnail(_ url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> () -> Void {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: NSSize(width: 24, height: 24),
            scale: 2, representationTypes: .lowQualityThumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            DispatchQueue.main.async { completion(image) }
        }
        return { QLThumbnailGenerator.shared.cancel(request) }
    }
}
