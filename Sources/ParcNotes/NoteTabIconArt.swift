import AppKit
import Combine
import ImageIO
import ParcCore
import ParcKit

@MainActor
package final class NoteTabIconArt {
    package enum Art {
        case image(NSImage)
        case standard
        case pending
    }

    struct ThumbnailStamp: Hashable {
        var path: String
        var modified: Date?
        var bytes: Int?

        init(path: String, modified: Date?, bytes: Int?) {
            self.path = path
            self.modified = modified
            self.bytes = bytes
        }

        init(_ file: URL) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            self.init(path: file.path, modified: attributes?[.modificationDate] as? Date,
                      bytes: (attributes?[.size] as? NSNumber)?.intValue)
        }

        var id: String { "\(path)|\(modified?.timeIntervalSinceReferenceDate ?? -1)|\(bytes ?? -1)" }
    }

    private struct Sighting {
        var stamp: ThumbnailStamp
        var checked: Date
    }

    package enum Subject: Hashable {
        case note(URL)
        case easel(directory: URL, id: UUID)

        @MainActor
        package init?(tab: BrowserTab) {
            self.init(address: tab.url, profile: tab.profileID)
        }

        package var mark: DocumentDefaultIcon {
            switch self {
            case .note: return .note
            case .easel: return .easel
            }
        }

        @MainActor
        package init?(address: String, profile: UUID, easels: EaselTabIcons? = nil) {
            switch InternalPage(urlString: address) {
            case .note(let file)?: self = .note(InternalPage.noteFile(file) ?? file)
            case .easel(let id)?:
                guard let directory = (easels ?? .shared).directory(profile) else { return nil }
                self = .easel(directory: directory, id: id)
            case nil: return nil
            }
        }
    }

    private struct Waiter {
        var subject: Subject
        var size: CGFloat
        var completion: (NSImage?) -> Void
    }

    package static let shared = NoteTabIconArt(icons: .shared, easels: .shared)
    package nonisolated static let side: CGFloat = 16
    nonisolated static let thumbnailPixels = 96
    nonisolated static let thumbnailBytes = 40 * 1024 * 1024
    nonisolated static let restampInterval: TimeInterval = 1
    nonisolated static let unreadableRetryDelay: TimeInterval = 5

    package let changes: AnyPublisher<Set<String>?, Never>
    private let icons: NoteTabIcons
    package let easels: EaselTabIcons
    private let thumbnailsChanged = PassthroughSubject<Set<String>?, Never>()
    private let thumbnails = NSCache<NSString, CGImage>()
    private var sightings: [String: Sighting] = [:]
    private var unreadableThumbnails: [ThumbnailStamp: Date] = [:]
    private var loadingThumbnails: [ThumbnailStamp: Set<String>] = [:]
    private var images: [String: NSImage] = [:]
    private var waiters: [Int: Waiter] = [:]
    private var waiterCounter = 0
    private var waiterSubscription: AnyCancellable?

    init(icons: NoteTabIcons, easels: EaselTabIcons? = nil) {
        let easels = easels ?? EaselTabIcons.shared
        self.icons = icons
        self.easels = easels
        changes = icons.changes.merge(with: easels.changes, thumbnailsChanged).eraseToAnyPublisher()
        waiterSubscription = changes.sink { [weak self] change in self?.settleWaiters(change) }
    }

    func art(forNote note: URL, size: CGFloat = side) -> Art {
        art(for: .note(note), size: size)
    }

    package func touches(_ change: Set<String>?, _ subject: Subject) -> Bool {
        switch subject {
        case .note(let note): return NoteTabIcons.touches(change, note: note)
        case .easel(let directory, let id): return EaselTabIcons.touches(change, key: EaselTabIcons.key(directory: directory, id: id))
        }
    }

    private func key(of subject: Subject) -> String {
        switch subject {
        case .note(let note): return NoteTabIcons.key(note)
        case .easel(let directory, let id): return EaselTabIcons.key(directory: directory, id: id)
        }
    }

    package func art(for subject: Subject, size: CGFloat = side) -> Art {
        let lookup: NoteTabIcons.Lookup
        switch subject {
        case .note(let note): lookup = icons.lookup(note)
        case .easel(let directory, let id): lookup = easels.lookup(directory: directory, id: id)
        }
        switch lookup {
        case .pending: return .pending
        case .known(nil): return .standard
        case .known(.emoji(let value)?): return emojiImage(value, size: size).map(Art.image) ?? .standard
        case .known(.image(let file)?): return thumbnailArt(file, key: key(of: subject), size: size)
        }
    }

    private func standardImage(_ subject: Subject, size: CGFloat) -> NSImage {
        subject.mark.image(size: size)
    }

    package func image(emoji value: String) -> NSImage? {
        NoteTabIcon.emoji(value.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { emojiImage($0, size: Self.side) }
    }

    func image(forNote note: URL, size: CGFloat = side) -> NSImage? {
        image(for: .note(note), size: size)
    }

    package func requestImage(forNote note: URL, size: CGFloat = side, completion: @escaping (NSImage?) -> Void) {
        requestImage(for: .note(note), size: size, completion: completion)
    }

    package func image(for subject: Subject, size: CGFloat = side) -> NSImage? {
        switch art(for: subject, size: size) {
        case .image(let image): return image
        case .standard: return standardImage(subject, size: size)
        case .pending: return nil
        }
    }

    package func requestImage(for subject: Subject, size: CGFloat = side, completion: @escaping (NSImage?) -> Void) {
        switch art(for: subject, size: size) {
        case .image(let image): completion(image)
        case .standard: completion(standardImage(subject, size: size))
        case .pending:
            waiterCounter += 1
            waiters[waiterCounter] = Waiter(subject: subject, size: size, completion: completion)
        }
    }

    private func settleWaiters(_ change: Set<String>?) {
        for (id, waiter) in waiters.sorted(by: { $0.key < $1.key }) where EaselTabIcons.touches(change, key: key(of: waiter.subject)) {
            switch art(for: waiter.subject, size: waiter.size) {
            case .pending: continue
            case .image(let image):
                waiters[id] = nil
                waiter.completion(image)
            case .standard:
                waiters[id] = nil
                waiter.completion(standardImage(waiter.subject, size: waiter.size))
            }
        }
    }

    private func emojiImage(_ value: String, size: CGFloat) -> NSImage? {
        let key = "emoji|\(size)|\(value)"
        if let image = images[key] { return image }
        guard let image = SidebarGroupIcon.emoji(value).image(size: size) else { return nil }
        image.accessibilityDescription = value
        remember(image, key: key)
        return image
    }

    private func thumbnailArt(_ file: URL, key owner: String, size: CGFloat) -> Art {
        let stamp = currentStamp(of: file)
        if let thumbnail = thumbnails.object(forKey: stamp.id as NSString) {
            let key = "image|\(size)|\(stamp.id)"
            if let image = images[key] { return .image(image) }
            let image = Self.rounded(thumbnail, size: size)
            remember(image, key: key)
            return .image(image)
        }
        if let failed = unreadableThumbnails[stamp] {
            if icons.clock.now.timeIntervalSince(failed) < Self.unreadableRetryDelay { return .standard }
            unreadableThumbnails[stamp] = nil
        }
        let key = owner
        if loadingThumbnails[stamp] != nil {
            loadingThumbnails[stamp]?.insert(key)
            return .pending
        }
        loadingThumbnails[stamp] = [key]
        icons.worker.perform({ Self.thumbnail(file) }) { [weak self] thumbnail in
            guard let self else { return }
            let notes = self.loadingThumbnails.removeValue(forKey: stamp) ?? [key]
            if let thumbnail {
                self.thumbnails.setObject(thumbnail, forKey: stamp.id as NSString)
            } else {
                if self.unreadableThumbnails.count >= 1_024 { self.unreadableThumbnails.removeAll() }
                self.unreadableThumbnails[stamp] = self.icons.clock.now
            }
            self.thumbnailsChanged.send(notes)
        }
        return loadingThumbnails[stamp] == nil ? thumbnailArt(file, key: owner, size: size) : .pending
    }

    private func currentStamp(of file: URL) -> ThumbnailStamp {
        let now = icons.clock.now
        if let sighting = sightings[file.path], abs(now.timeIntervalSince(sighting.checked)) < Self.restampInterval {
            return sighting.stamp
        }
        let stamp = ThumbnailStamp(file)
        if let previous = sightings[file.path]?.stamp, previous != stamp { forget(previous) }
        if sightings.count >= 1_024, sightings[file.path] == nil { sightings.removeAll() }
        sightings[file.path] = Sighting(stamp: stamp, checked: now)
        return stamp
    }

    private func forget(_ stamp: ThumbnailStamp) {
        thumbnails.removeObject(forKey: stamp.id as NSString)
        unreadableThumbnails[stamp] = nil
        let suffix = "|" + stamp.id
        images = images.filter { !($0.key.hasPrefix("image|") && $0.key.hasSuffix(suffix)) }
    }

    private func remember(_ image: NSImage, key: String) {
        if images.count >= 512 { images.removeAll() }
        images[key] = image
    }

    nonisolated static func thumbnail(_ file: URL) -> CGImage? {
        guard !NoteFilePaths.isDataless(file),
              let bytes = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes <= thumbnailBytes,
              let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let side = min(image.width, image.height)
        guard side > 0 else { return nil }
        return image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side))
    }

    static func rounded(_ thumbnail: CGImage, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let radius = rect.width * 0.22
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
            context.interpolationQuality = .high
            context.draw(thumbnail, in: rect)
            context.restoreGState()
            return true
        }
    }
}
