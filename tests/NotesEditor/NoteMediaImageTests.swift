import AppKit
import ImageIO
import UniformTypeIdentifiers

@main @MainActor
struct NoteMediaImageTests {
    static func expect(_ value: Bool, _ message: String) {
        if !value { failTest(message) }
    }

    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteMediaImageTests-" + UUID().uuidString, isDirectory: true)

    static func main() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        buckets()
        stillImages()
        animatedImages()
        asyncLoading()
        frontMatterIcons()
        networkFailures()
        print("NoteMediaImageTests passed")
    }

    static func bitmap(width: Int, height: Int, shade: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: shade, green: 0.4, blue: 1 - shade, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func write(_ frames: [CGImage], type: UTType, name: String, properties: [CFString: Any] = [:],
                      frameProperties: [CFString: Any] = [:]) -> URL {
        let url = folder.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames.count, nil)!
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        for frame in frames { CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary) }
        expect(CGImageDestinationFinalize(destination), "wrote \(name)")
        return url
    }

    static func buckets() {
        expect(NoteMediaImageLoader.bucket(for: 1) == 128, "tiny requests use the smallest bucket")
        expect(NoteMediaImageLoader.bucket(for: 513) == 1024, "requests round up to the next bucket")
        expect(NoteMediaImageLoader.bucket(for: 99_999) == 4096, "huge requests cap at the largest bucket")
        expect(NoteMediaImageLoader.pixels(for: CGSize(width: 300, height: 200), scale: 2) == 600, "pixels follow the long side and scale")
        expect(NoteMediaImageLoader.pixels(for: CGSize(width: 100, height: 400), scale: 0.5) == 400, "scale never drops below one")
    }

    static func stillImages() {
        let retina = write([bitmap(width: 2000, height: 1000, shade: 0.2)], type: .png, name: "retina.png",
                           frameProperties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
        let natural = NoteMediaImageDecoder.naturalSize(of: retina)
        expect(natural == CGSize(width: 1000, height: 500), "144 dpi images report point sizes: \(String(describing: natural))")
        guard let decoded = NoteMediaImageDecoder.decode(url: retina, maxPixel: 512) else { expect(false, "png decodes"); return }
        expect(max(decoded.first.width, decoded.first.height) == 512, "decoding downsamples to the bucket: \(decoded.first.width)")
        expect(decoded.pointSize == CGSize(width: 1000, height: 500), "downsampling keeps the natural point size")
        expect(!decoded.isAnimated && decoded.frames.count == 1, "stills have one frame")
        expect(decoded.decodedPixels == 512 && decoded.cost > 0, "decoded size and cost are tracked")
        let rotated = write([bitmap(width: 300, height: 100, shade: 0.5)], type: .jpeg, name: "rotated.jpg",
                            frameProperties: [kCGImagePropertyOrientation: 6])
        expect(NoteMediaImageDecoder.naturalSize(of: rotated) == CGSize(width: 100, height: 300), "EXIF rotation swaps width and height")
        let garbage = folder.appendingPathComponent("garbage.png")
        try? Data("definitely not a picture".utf8).write(to: garbage)
        expect(NoteMediaImageDecoder.decode(url: garbage, maxPixel: 256) == nil, "garbage does not decode")
        expect(NoteMediaImageDecoder.naturalSize(of: garbage) == nil, "garbage has no size")
        let data = try! Data(contentsOf: retina)
        expect(NoteMediaImageDecoder.decode(data: data, maxPixel: 128)?.decodedPixels == 128, "in-memory data decodes too")
    }

    static func animatedImages() {
        let frames = [0.1, 0.5, 0.9].map { bitmap(width: 40, height: 20, shade: $0) }
        let gif = write(frames, type: .gif, name: "dance.gif",
                        properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
                        frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]])
        guard let decoded = NoteMediaImageDecoder.decode(url: gif, maxPixel: 128) else { expect(false, "gif decodes"); return }
        expect(decoded.isAnimated && decoded.frames.count == 3, "gifs keep every frame: \(decoded.frames.count)")
        expect(decoded.delays.allSatisfy { abs($0 - 0.25) < 0.01 }, "gif delays are read: \(decoded.delays)")
        expect(abs(decoded.duration - 0.75) < 0.03, "durations add up")
        let fast = write(frames, type: .gif, name: "fast.gif",
                         frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.0]])
        let quick = NoteMediaImageDecoder.decode(url: fast, maxPixel: 128)
        expect(quick?.delays.allSatisfy { abs($0 - 0.1) < 0.001 } == true, "zero delays slow down to 0.1 s like browsers")
        let animation = NoteImageFrames.animation(for: decoded)
        expect(animation.keyTimes?.count == 4 && animation.values?.count == 3, "discrete keyframes have one more time than values")
        expect(animation.keyTimes?.first == 0 && animation.keyTimes?.last == 1, "keyframes span the whole loop")
        expect(animation.repeatCount == .infinity && animation.calculationMode == .discrete, "gifs loop frame by frame")
    }

    static func asyncLoading() {
        let url = write([bitmap(width: 800, height: 400, shade: 0.7)], type: .png, name: "async.png")
        let loader = NoteMediaImageLoader()
        expect(loader.naturalSize(of: url) == CGSize(width: 800, height: 400), "local sizes read synchronously from the header")
        expect(loader.cached(url, pixels: 200) == nil, "nothing is cached before a load")
        var results: [Result<NoteMediaImage, NoteMediaImageError>] = []
        loader.load(url, pixels: 200) { results.append($0) }
        loader.load(url, pixels: 220) { results.append($0) }
        spin { results.count == 2 }
        expect(results.count == 2, "both requests finish")
        if case .success(let image) = results.first {
            expect(image.decodedPixels == 256, "loads decode at the bucket size")
        } else {
            expect(false, "local loads succeed")
        }
        expect(loader.cached(url, pixels: 100) != nil, "smaller requests reuse the bigger decode")
        expect(loader.cached(url, pixels: 600) == nil, "bigger requests need a sharper decode")
        expect(loader.bestCached(url)?.decodedPixels == 256, "the best cached decode is offered")
        var missing: Result<NoteMediaImage, NoteMediaImageError>?
        let gone = folder.appendingPathComponent("gone.png")
        loader.load(gone, pixels: 100) { missing = $0 }
        spin { missing != nil }
        if case .failure(let error) = missing { expect(error == .missing, "missing files report missing") } else { expect(false, "missing files fail") }
        expect(loader.failure(for: gone) == .missing, "failures are remembered")
        loader.forget(gone)
        expect(loader.failure(for: gone) == nil, "forgetting clears the failure")
    }

    static func frontMatterIcons() {
        expect(NoteLinkedNote.frontMatterIcon(in: "---\ntitle: x\nicon: 🧳\n---\nbody") == "🧳", "front matter icons are read")
        expect(NoteLinkedNote.frontMatterIcon(in: "---\nicon: \"🌊\" # beach\n---\n") == "🌊", "quotes and comments are trimmed")
        expect(NoteLinkedNote.frontMatterIcon(in: "\u{FEFF}---\nIcon: 'x'\n---\n") == "x", "BOMs and key case are tolerated")
        expect(NoteLinkedNote.frontMatterIcon(in: "---\ntitle: x\n---\nicon: 🧳\n") == nil, "icons after the front matter don't count")
        expect(NoteLinkedNote.frontMatterIcon(in: "icon: 🧳\n") == nil, "no front matter means no icon")
        expect(NoteLinkedNote.frontMatterIcon(in: "---\nicon:\n---\n") == nil, "empty icons are nil")
        let note = folder.appendingPathComponent("Packing List.md")
        try? "---\nicon: 🧳\n---\n- Sunscreen\n".write(to: note, atomically: true, encoding: .utf8)
        expect(NoteLinkedNote.icon(for: note) == "🧳", "icons come from the file")
        expect(NoteLinkedNote.title(fromTarget: "Trips/Packing%20List.md") == "Packing List", "link titles come from file names")
    }

    static func networkFailures() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        expect(NoteMediaFileType.isNetworkFailure(offline), "a URL error is a network failure")
        let wrapped = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: offline])
        expect(NoteMediaFileType.isNetworkFailure(wrapped), "a wrapped URL error is a network failure")
        let unplayable = NSError(domain: "AVFoundationErrorDomain", code: -11828)
        expect(!NoteMediaFileType.isNetworkFailure(unplayable), "an unplayable file is not a network failure")
    }

    static func spin(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
}
