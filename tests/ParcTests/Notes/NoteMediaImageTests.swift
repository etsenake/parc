import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ParcCore
@testable import ParcNotes

@MainActor
struct NoteMediaImageTests {
    let folder: NoteEditorTemporaryFolder

    init() throws { folder = try NoteEditorTemporaryFolder("note-media-image") }

    func bitmap(width: Int, height: Int, shade: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: shade, green: 0.4, blue: 1 - shade, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func write(_ frames: [CGImage], type: UTType, name: String, properties: [CFString: Any] = [:],
               frameProperties: [CFString: Any] = [:]) throws -> URL {
        let url = folder.url.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames.count, nil))
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        for frame in frames { CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    func retina() throws -> URL {
        try write([bitmap(width: 2000, height: 1000, shade: 0.2)], type: .png, name: "retina.png",
                  frameProperties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
    }

    func dance(delay: Double) throws -> URL {
        let frames = [0.1, 0.5, 0.9].map { bitmap(width: 40, height: 20, shade: $0) }
        return try write(frames, type: .gif, name: "dance-\(delay).gif",
                         properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
                         frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]])
    }

    @Test(arguments: [(1, 128), (513, 1024), (99_999, 4096)] as [(Int, Int)])
    func requestsRoundUpToABucketAndCapAtTheLargest(request: Int, bucket: Int) {
        #expect(NoteMediaImageLoader.bucket(for: request) == bucket)
    }

    @Test func pixelsFollowTheLongSideAndScale() {
        #expect(NoteMediaImageLoader.pixels(for: CGSize(width: 300, height: 200), scale: 2) == 600)
    }

    @Test func scaleNeverDropsBelowOne() {
        #expect(NoteMediaImageLoader.pixels(for: CGSize(width: 100, height: 400), scale: 0.5) == 400)
    }

    @Test func highDpiImagesReportPointSizes() throws {
        #expect(NoteMediaImageDecoder.naturalSize(of: try retina()) == CGSize(width: 1000, height: 500))
    }

    @Test func decodingDownsamplesToTheBucket() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try retina(), maxPixel: 512))
        #expect(max(decoded.first.width, decoded.first.height) == 512)
    }

    @Test func downsamplingKeepsTheNaturalPointSize() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try retina(), maxPixel: 512))
        #expect(decoded.pointSize == CGSize(width: 1000, height: 500))
    }

    @Test func stillsHaveOneFrame() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try retina(), maxPixel: 512))
        #expect(!decoded.isAnimated)
        #expect(decoded.frames.count == 1)
    }

    @Test func decodedSizeAndCostAreTracked() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try retina(), maxPixel: 512))
        #expect(decoded.decodedPixels == 512)
        #expect(decoded.cost > 0)
    }

    @Test func exifRotationSwapsWidthAndHeight() throws {
        let rotated = try write([bitmap(width: 300, height: 100, shade: 0.5)], type: .jpeg, name: "rotated.jpg",
                                frameProperties: [kCGImagePropertyOrientation: 6])
        #expect(NoteMediaImageDecoder.naturalSize(of: rotated) == CGSize(width: 100, height: 300))
    }

    func garbage() throws -> URL { try folder.write("definitely not a picture", to: "garbage.png") }

    @Test func garbageDoesNotDecode() throws {
        #expect(NoteMediaImageDecoder.decode(url: try garbage(), maxPixel: 256) == nil)
    }

    @Test func garbageHasNoSize() throws {
        #expect(NoteMediaImageDecoder.naturalSize(of: try garbage()) == nil)
    }

    @Test func inMemoryDataDecodesToo() throws {
        let data = try Data(contentsOf: try retina())
        #expect(NoteMediaImageDecoder.decode(data: data, maxPixel: 128)?.decodedPixels == 128)
    }

    @Test func gifsKeepEveryFrame() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        #expect(decoded.isAnimated)
        #expect(decoded.frames.count == 3)
    }

    @Test func gifDelaysAreRead() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        #expect(decoded.delays.allSatisfy { abs($0 - 0.25) < 0.01 })
    }

    @Test func durationsAddUp() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        #expect(abs(decoded.duration - 0.75) < 0.03)
    }

    @Test func zeroDelaysSlowDownToAtenthOfASecondLikeBrowsers() throws {
        let quick = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0), maxPixel: 128))
        #expect(quick.delays.allSatisfy { abs($0 - 0.1) < 0.001 })
    }

    @Test func discreteKeyframesHaveOneMoreTimeThanValues() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        let animation = NoteImageFrames.animation(for: decoded)
        #expect(animation.keyTimes?.count == 4)
        #expect(animation.values?.count == 3)
    }

    @Test func keyframesSpanTheWholeLoop() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        let animation = NoteImageFrames.animation(for: decoded)
        #expect(animation.keyTimes?.first == 0)
        #expect(animation.keyTimes?.last == 1)
    }

    @Test func gifsLoopFrameByFrame() throws {
        let decoded = try #require(NoteMediaImageDecoder.decode(url: try dance(delay: 0.25), maxPixel: 128))
        let animation = NoteImageFrames.animation(for: decoded)
        #expect(animation.repeatCount == .infinity)
        #expect(animation.calculationMode == .discrete)
    }

    func loaded(_ loader: NoteMediaImageLoader, _ url: URL, pixels: Int) async -> Result<NoteMediaImage, NoteMediaImageError> {
        await withCheckedContinuation { continuation in
            loader.load(url, pixels: pixels) { continuation.resume(returning: $0) }
        }
    }

    func asyncImage() throws -> URL { try write([bitmap(width: 800, height: 400, shade: 0.7)], type: .png, name: "async.png") }

    @Test func localSizesReadSynchronouslyFromTheHeader() throws {
        #expect(NoteMediaImageLoader().naturalSize(of: try asyncImage()) == CGSize(width: 800, height: 400))
    }

    @Test func nothingIsCachedBeforeALoad() throws {
        #expect(NoteMediaImageLoader().cached(try asyncImage(), pixels: 200) == nil)
    }

    @Test func loadsDecodeAtTheBucketSize() async throws {
        let loader = NoteMediaImageLoader()
        let url = try asyncImage()
        guard case .success(let image) = await loaded(loader, url, pixels: 200) else {
            Issue.record("local loads succeed")
            return
        }
        #expect(image.decodedPixels == 256)
    }

    @Test func smallerRequestsReuseTheBiggerDecode() async throws {
        let loader = NoteMediaImageLoader()
        let url = try asyncImage()
        _ = await loaded(loader, url, pixels: 200)
        #expect(loader.cached(url, pixels: 100) != nil)
    }

    @Test func biggerRequestsNeedASharperDecode() async throws {
        let loader = NoteMediaImageLoader()
        let url = try asyncImage()
        _ = await loaded(loader, url, pixels: 200)
        #expect(loader.cached(url, pixels: 600) == nil)
    }

    @Test func theBestCachedDecodeIsOffered() async throws {
        let loader = NoteMediaImageLoader()
        let url = try asyncImage()
        _ = await loaded(loader, url, pixels: 200)
        #expect(loader.bestCached(url)?.decodedPixels == 256)
    }

    @Test func missingFilesReportMissingAndRememberTheFailure() async {
        let loader = NoteMediaImageLoader()
        let gone = folder.url.appendingPathComponent("gone.png")
        guard case .failure(let error) = await loaded(loader, gone, pixels: 100) else {
            Issue.record("missing files fail")
            return
        }
        #expect(error == .missing)
        #expect(loader.failure(for: gone) == .missing)
    }

    @Test func forgettingClearsAFailure() async {
        let loader = NoteMediaImageLoader()
        let gone = folder.url.appendingPathComponent("gone.png")
        _ = await loaded(loader, gone, pixels: 100)
        loader.forget(gone)
        #expect(loader.failure(for: gone) == nil)
    }

    @Test(arguments: [
        ("---\ntitle: x\nicon: 🧳\n---\nbody", "🧳"),
        ("---\nicon: \"🌊\" # beach\n---\n", "🌊"),
        ("\u{FEFF}---\nIcon: 'x'\n---\n", "x"),
    ] as [(String, String)])
    func frontMatterIconsAreReadAndTidied(text: String, icon: String) {
        #expect(NoteLinkedNote.frontMatterIcon(in: text) == icon)
    }

    @Test(arguments: ["---\ntitle: x\n---\nicon: 🧳\n", "icon: 🧳\n", "---\nicon:\n---\n"])
    func textWithoutFrontMatterIconsHasNone(text: String) {
        #expect(NoteLinkedNote.frontMatterIcon(in: text) == nil)
    }

    @Test func iconsComeFromTheFile() throws {
        let note = try folder.write("---\nicon: 🧳\n---\n- Sunscreen\n", to: "Packing List.md")
        #expect(NoteLinkedNote.icon(for: note) == "🧳")
    }

    @Test func linkTitlesComeFromFileNames() {
        #expect(NoteLinkedNote.title(fromTarget: "Trips/Packing%20List.md") == "Packing List")
    }

    @Test func aURLErrorIsANetworkFailure() {
        #expect(NoteMediaFileType.isNetworkFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
    }

    @Test func aWrappedURLErrorIsANetworkFailure() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(NoteMediaFileType.isNetworkFailure(NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: offline])))
    }

    @Test func anUnplayableFileIsNotANetworkFailure() {
        #expect(!NoteMediaFileType.isNetworkFailure(NSError(domain: "AVFoundationErrorDomain", code: -11828)))
    }
}
