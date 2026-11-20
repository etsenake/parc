import AppKit
import ImageIO
import UniformTypeIdentifiers

final class NoteMediaImage: @unchecked Sendable {
    let frames: [CGImage]
    let delays: [Double]
    let pointSize: CGSize
    let decodedPixels: Int

    init(frames: [CGImage], delays: [Double], pointSize: CGSize, decodedPixels: Int) {
        self.frames = frames
        self.delays = delays
        self.pointSize = pointSize
        self.decodedPixels = decodedPixels
    }

    var first: CGImage { frames[0] }
    var isAnimated: Bool { frames.count > 1 }
    var duration: Double { delays.reduce(0, +) }
    var cost: Int { frames.reduce(0) { $0 + $1.bytesPerRow * $1.height } }
}

enum NoteMediaImageError: Error, Equatable {
    case missing, unreadable, tooLarge, badStatus(Int), offline
}

enum NoteMediaImageDecoder {
    static let maximumFrames = 360
    static let maximumAnimatedBytes = 160_000_000

    static func naturalSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let size = NoteMediaLayout.pointSize(pixelWidth: width, pixelHeight: height,
                                             dpiWidth: (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
                                             dpiHeight: (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue)
        return orientation >= 5 && orientation <= 8 ? CGSize(width: size.height, height: size.width) : size
    }

    static func naturalSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return NSImage(contentsOf: url).map(\.size).flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        }
        return naturalSize(of: source)
    }

    static func decode(data: Data, maxPixel: Int) -> NoteMediaImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) != .statusInvalidData else {
            return rasterize(NSImage(data: data), maxPixel: maxPixel)
        }
        return decode(source: source, maxPixel: maxPixel) ?? rasterize(NSImage(data: data), maxPixel: maxPixel)
    }

    static func decode(url: URL, maxPixel: Int) -> NoteMediaImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            return rasterize(NSImage(contentsOf: url), maxPixel: maxPixel)
        }
        return decode(source: source, maxPixel: maxPixel) ?? rasterize(NSImage(contentsOf: url), maxPixel: maxPixel)
    }

    static func decode(source: CGImageSource, maxPixel: Int) -> NoteMediaImage? {
        guard let type = CGImageSourceGetType(source) as String?, type != UTType.pdf.identifier else { return nil }
        let natural = naturalSize(of: source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        let count = CGImageSourceGetCount(source)
        guard let first = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let pointSize = natural ?? CGSize(width: first.width, height: first.height)
        var frames = [first]
        var delays = [delay(of: source, at: 0)]
        if count > 1 {
            let budget = maximumAnimatedBytes / max(1, first.bytesPerRow * first.height)
            let limit = min(count, maximumFrames, max(1, budget))
            for index in 1..<limit {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { break }
                frames.append(frame)
                delays.append(delay(of: source, at: index))
            }
        }
        return NoteMediaImage(frames: frames, delays: delays, pointSize: pointSize, decodedPixels: max(first.width, first.height))
    }

    static func delay(of source: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (container, unclamped, clamped) in containers {
            guard let values = properties[container] as? [CFString: Any] else { continue }
            let value = (values[unclamped] as? NSNumber)?.doubleValue ?? (values[clamped] as? NSNumber)?.doubleValue ?? 0
            return value < 0.02 ? 0.1 : value
        }
        return 0.1
    }

    static func rasterize(_ image: NSImage?, maxPixel: Int) -> NoteMediaImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let size = image.size
        let scale = min(1, CGFloat(maxPixel) / max(size.width * 2, size.height * 2)) * 2
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let rendered = context.makeImage() else { return nil }
        return NoteMediaImage(frames: [rendered], delays: [0.1], pointSize: size, decodedPixels: max(width, height))
    }
}

@MainActor
final class NoteMediaImageLoader {
    typealias Completion = (Result<NoteMediaImage, NoteMediaImageError>) -> Void

    static let shared = NoteMediaImageLoader()
    static let buckets = [128, 256, 512, 1024, 1600, 2400, 3200, 4096]
    nonisolated static let downloadLimit = 60_000_000

    private final class Box {
        let image: NoteMediaImage
        init(_ image: NoteMediaImage) { self.image = image }
    }

    private let images = NSCache<NSString, Box>()
    private let downloads = NSCache<NSURL, NSData>()
    private var decodedBuckets: [URL: Set<Int>] = [:]
    private var sizes: [URL: CGSize] = [:]
    private var failures: [URL: NoteMediaImageError] = [:]
    private var waiting: [String: [Completion]] = [:]
    private var fetching: [URL: [(Result<Data, NoteMediaImageError>) -> Void]] = [:]
    private let queue = DispatchQueue(label: "parc.notes.media.decode", qos: .userInitiated, attributes: .concurrent)
    private let session: URLSession

    init() {
        images.totalCostLimit = 320_000_000
        downloads.totalCostLimit = 120_000_000
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = URLCache(memoryCapacity: 24_000_000, diskCapacity: 0)
        session = URLSession(configuration: configuration)
    }

    static func bucket(for pixels: Int) -> Int {
        buckets.first { $0 >= pixels } ?? buckets.last!
    }

    static func pixels(for size: CGSize, scale: CGFloat) -> Int {
        Int((max(size.width, size.height) * max(1, scale)).rounded(.up))
    }

    func naturalSize(of url: URL) -> CGSize? {
        if let size = sizes[url] { return size }
        guard url.isFileURL else { return nil }
        guard let size = NoteMediaImageDecoder.naturalSize(of: url) else { return nil }
        sizes[url] = size
        return size
    }

    func failure(for url: URL) -> NoteMediaImageError? { failures[url] }

    func forget(_ url: URL) {
        failures.removeValue(forKey: url)
        downloads.removeObject(forKey: url as NSURL)
    }

    func cached(_ url: URL, pixels: Int) -> NoteMediaImage? {
        let wanted = Self.bucket(for: pixels)
        guard let available = decodedBuckets[url]?.filter({ $0 >= wanted }).sorted() else { return nil }
        for bucket in available {
            if let box = images.object(forKey: key(url, bucket) as NSString) { return box.image }
            decodedBuckets[url]?.remove(bucket)
        }
        return nil
    }

    func bestCached(_ url: URL) -> NoteMediaImage? {
        guard let available = decodedBuckets[url]?.sorted(by: >) else { return nil }
        for bucket in available {
            if let box = images.object(forKey: key(url, bucket) as NSString) { return box.image }
        }
        return nil
    }

    func load(_ url: URL, pixels: Int, completion: @escaping Completion) {
        if let hit = cached(url, pixels: pixels) { completion(.success(hit)); return }
        let bucket = Self.bucket(for: pixels)
        let identity = key(url, bucket)
        if waiting[identity] != nil { waiting[identity]?.append(completion); return }
        waiting[identity] = [completion]
        failures.removeValue(forKey: url)
        if url.isFileURL {
            queue.async { [weak self] in
                let outcome: Result<NoteMediaImage, NoteMediaImageError>
                if !FileManager.default.fileExists(atPath: url.path) { outcome = .failure(.missing) }
                else if let image = NoteMediaImageDecoder.decode(url: url, maxPixel: bucket) { outcome = .success(image) }
                else { outcome = .failure(.unreadable) }
                DispatchQueue.main.async { self?.finish(url, bucket: bucket, outcome) }
            }
            return
        }
        data(for: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): self.finish(url, bucket: bucket, .failure(error))
            case .success(let data):
                self.queue.async { [weak self] in
                    let image = NoteMediaImageDecoder.decode(data: data, maxPixel: bucket)
                    DispatchQueue.main.async { self?.finish(url, bucket: bucket, image.map { .success($0) } ?? .failure(.unreadable)) }
                }
            }
        }
    }

    func data(for url: URL, completion: @escaping (Result<Data, NoteMediaImageError>) -> Void) {
        if let hit = downloads.object(forKey: url as NSURL) { completion(.success(hit as Data)); return }
        if fetching[url] != nil { fetching[url]?.append(completion); return }
        fetching[url] = [completion]
        let task = session.dataTask(with: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20))
        task.delegate = NoteMediaDownload(limit: Self.downloadLimit) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let data) = result { self.downloads.setObject(data as NSData, forKey: url as NSURL, cost: data.count) }
                let callbacks = self.fetching.removeValue(forKey: url) ?? []
                for callback in callbacks { callback(result) }
            }
        }
        task.resume()
    }

    func store(_ data: Data, for url: URL) {
        downloads.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
    }

    private func finish(_ url: URL, bucket: Int, _ outcome: Result<NoteMediaImage, NoteMediaImageError>) {
        let identity = key(url, bucket)
        switch outcome {
        case .success(let image):
            images.setObject(Box(image), forKey: identity as NSString, cost: image.cost)
            decodedBuckets[url, default: []].insert(bucket)
            sizes[url] = image.pointSize
            failures.removeValue(forKey: url)
        case .failure(let error):
            failures[url] = error
        }
        let callbacks = waiting.removeValue(forKey: identity) ?? []
        for callback in callbacks { callback(outcome) }
    }

    private func key(_ url: URL, _ bucket: Int) -> String { url.absoluteString + "#" + String(bucket) }
}

final class NoteMediaDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let completion: (Result<Data, NoteMediaImageError>) -> Void
    private let lock = NSLock()
    private var data = Data()
    private var finished = false

    init(limit: Int, completion: @escaping (Result<Data, NoteMediaImageError>) -> Void) {
        self.limit = limit
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            complete(.failure(.badStatus(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > Int64(limit) {
            complete(.failure(.tooLarge))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let overflow: Bool = lock.withLock {
            data.append(chunk)
            return data.count > limit
        }
        guard overflow else { return }
        dataTask.cancel()
        complete(.failure(.tooLarge))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as? URLError {
            let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut]
            complete(.failure(offline.contains(error.code) ? .offline : .unreadable))
            return
        }
        if error != nil { complete(.failure(.unreadable)); return }
        let collected = lock.withLock { data }
        complete(collected.isEmpty ? .failure(.unreadable) : .success(collected))
    }

    private func complete(_ outcome: Result<Data, NoteMediaImageError>) {
        let first: Bool = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if first { completion(outcome) }
    }
}

@MainActor
enum NoteImageFrames {
    static func animation(for image: NoteMediaImage) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = image.frames
        let total = max(image.duration, 0.02)
        var elapsed = 0.0
        var times: [NSNumber] = []
        for delay in image.delays {
            times.append(NSNumber(value: elapsed / total))
            elapsed += delay
        }
        times.append(1)
        animation.keyTimes = times
        animation.calculationMode = .discrete
        animation.duration = total
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}
