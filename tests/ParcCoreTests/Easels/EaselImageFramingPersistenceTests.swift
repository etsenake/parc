import Foundation
import CoreGraphics
import Testing
@testable import ParcCore

struct EaselImageFramingPersistenceTests {
    @MainActor func session(_ items: [EaselItem], assets: [String: Data] = [:]) throws -> EaselSession {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        return try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Images", createdAt: date, modifiedAt: date, items: items), assets: assets)
    }

    @MainActor func accepts(_ item: EaselItem) -> Bool {
        (try? session([item], assets: item.assetID.map { [$0: EaselImageFramingTestsSupport.png] } ?? [:])) != nil
    }

    @MainActor @Test
    func anImageWithFramingFieldsCanBeOpened() {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        item.mask = .star
        item.altText = "Stars"
        item.quarterTurns = 3
        #expect(accepts(item), "an image with every framing field opens")
    }

    @MainActor @Test
    func invalidCropsCannotBeOpened() {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        item.mask = .star
        item.altText = "Stars"
        item.quarterTurns = 3
        var bad = item; bad.crop = EaselRect(x: 0.6, y: 0, width: 0.5, height: 1)
        #expect(!accepts(bad), "a crop past the picture is refused")
        bad = item; bad.crop = EaselRect(x: 0, y: 0, width: 0, height: 1)
        #expect(!accepts(bad), "an empty crop is refused")
        bad = item; bad.crop = EaselRect(x: .nan, y: 0, width: 0.5, height: 1)
        #expect(!accepts(bad), "a non-finite crop is refused")
    }

    @MainActor @Test
    func turnsOutsideTheSavedRangeAreRefused() {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        item.mask = .star
        item.altText = "Stars"
        item.quarterTurns = 3
        var bad = item; bad.quarterTurns = 4
        #expect(!accepts(bad), "turns stay between one and three")
    }

    @MainActor @Test
    func altTextHasAByteLimit() {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        item.mask = .star
        item.altText = "Stars"
        item.quarterTurns = 3
        var bad = item; bad.altText = String(repeating: "a", count: 5000)
        #expect(!accepts(bad), "alt text has a size limit")
    }

    @MainActor @Test
    func framingFieldsBelongToImages() {
        var shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10))
        shape.mask = .circle
        #expect(!accepts(shape), "masks belong to images")
        shape.mask = nil; shape.altText = "Box"
        #expect(!accepts(shape), "alt text belongs to images")
        shape.altText = nil; shape.crop = EaselRect(x: 0, y: 0, width: 1, height: 1)
        #expect(!accepts(shape), "crops belong to images")
        shape.crop = nil; shape.quarterTurns = 1
        #expect(!accepts(shape), "turns belong to images")
    }

    @MainActor @Test
    func animatedAssetsBelongToImages() {
        var animated = EaselImageFramingTestsSupport.image()
        animated.assetID = UUID().uuidString.lowercased() + ".gif"
        #expect(accepts(animated), "an image can hold a GIF")
        var card = EaselItem(kind: .webCard, frame: .init(x: 0, y: 0, width: 10, height: 10), url: "https://example.com")
        card.assetID = UUID().uuidString.lowercased() + ".gif"
        #expect(!accepts(card), "GIFs only live in images")
    }

    @MainActor @Test
    func aVideoCanOpenWithOrWithoutAPoster() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        #expect((try? session([video], assets: [movie: EaselImageFramingTestsSupport.png, poster: EaselImageFramingTestsSupport.png])) != nil, "a video with a poster and alt text opens")
        var bare = video; bare.poster = nil
        #expect((try? session([bare], assets: [movie: EaselImageFramingTestsSupport.png])) != nil, "a poster is optional")
    }

    @MainActor @Test
    func aVideoNeedsAMovieAsset() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        var noAsset = video; noAsset.assetID = nil
        #expect((try? session([noAsset], assets: [poster: EaselImageFramingTestsSupport.png])) == nil, "a video needs its movie")
        var stillVideo = video; stillVideo.assetID = poster
        #expect((try? session([stillVideo], assets: [poster: EaselImageFramingTestsSupport.png])) == nil, "a video's asset must be a movie")
    }

    @MainActor @Test
    func aVideoPosterMustBePNG() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        var gifPoster = video; gifPoster.poster = UUID().uuidString.lowercased() + ".gif"
        #expect((try? session([gifPoster], assets: [movie: EaselImageFramingTestsSupport.png, gifPoster.poster ?? "": EaselImageFramingTestsSupport.gif])) == nil, "posters are PNGs")
    }

    @MainActor @Test
    func anImageCannotHoldAMovieOrAPoster() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var moviePicture = EaselImageFramingTestsSupport.image(); moviePicture.assetID = movie
        #expect((try? session([moviePicture], assets: [movie: EaselImageFramingTestsSupport.png])) == nil, "an image can't hold a movie")
        var posterOnImage = EaselImageFramingTestsSupport.image(); posterOnImage.poster = poster
        #expect((try? session([posterOnImage], assets: [posterOnImage.assetID ?? "": EaselImageFramingTestsSupport.png, poster: EaselImageFramingTestsSupport.png])) == nil, "only videos have posters")
    }

    @MainActor @Test
    func videosCannotBeCropped() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        var croppedVideo = video; croppedVideo.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 0.5)
        #expect((try? session([croppedVideo], assets: [movie: EaselImageFramingTestsSupport.png, poster: EaselImageFramingTestsSupport.png])) == nil, "videos don't crop")
    }

    @Test
    func aVideoExportsAsItsLabelledPoster() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        let html = EaselVectorExport.element(video, art: EaselVectorArt(images: [video.id: EaselVectorImage(data: EaselImageFramingTestsSupport.png, mimeType: "image/EaselImageFramingTestsSupport.png")]))
        #expect(html.contains("aria-label=\"A demo\"") && html.contains("<image "), "a video exports as its labelled poster")
        #expect(EaselVectorExport.element(video, art: EaselVectorArt()).isEmpty, "a video without a poster exports nothing")
    }

    @MainActor @Test
    func anImportedMovieKeepsItsTypeAndCanBeDiscardedWhenUnused() throws {
        var mp4 = Data([0, 0, 0, 0x18]); mp4.append(contentsOf: Array("ftypmp42".utf8)); mp4.append(Data(count: 12))
        let board = try session([])
        let stored = try board.importAsset(mp4, type: .mp4)
        #expect(stored.hasSuffix(".mp4"), "movies keep their type")
        board.discardUnusedAssets([stored])
        #expect((try? board.assetData(stored)) == nil, "an unused imported movie can be thrown away")
    }

    @Test
    func pngAndGifAreIdentifiedByTheirBytes() {
        #expect(EaselAssetType.sniff(EaselImageFramingTestsSupport.png) == .png && EaselAssetType.sniff(EaselImageFramingTestsSupport.gif) == .gif, "PNG and GIF are recognised by their bytes")
    }

    @Test
    func quickTimeAndMP4AreIdentifiedByTheirContainer() {
        var mp4 = Data([0, 0, 0, 0x18]); mp4.append(contentsOf: Array("ftypisom".utf8)); mp4.append(Data(count: 12))
        var mov = Data([0, 0, 0, 0x14]); mov.append(contentsOf: Array("ftypqt  ".utf8)); mov.append(Data(count: 12))
        var old = Data([0, 0, 0, 0x08]); old.append(contentsOf: Array("wide".utf8)); old.append(Data(count: 12))
        var stranger = Data([0, 0, 0, 0x18]); stranger.append(contentsOf: Array("ftypabcd".utf8)); stranger.append(Data(count: 12))
        var compatible = Data([0, 0, 0, 0x18]); compatible.append(contentsOf: Array("ftypabcd".utf8)); compatible.append(Data(count: 4))
        compatible.append(contentsOf: Array("mp41".utf8)); compatible.append(Data(count: 4))
        #expect(EaselAssetType.sniff(mp4) == .mp4 && EaselAssetType.sniff(mov) == .mov, "MP4 and QuickTime movies are recognised by their ftyp box")
        #expect(EaselAssetType.sniff(old) == .mov, "an older QuickTime movie without an ftyp box still counts")
        #expect(EaselAssetType.sniff(stranger) == .mp4 && EaselAssetType.sniff(compatible) == .mp4, "any non-still ftyp brand is an MP4")
    }

    @Test
    func gifBytesNeedRealDimensions() {
        var flat = EaselImageFramingTestsSupport.gif; flat.replaceSubrange(6..<10, with: [0, 0, 0, 0])
        #expect(EaselAssetType.sniff(flat) == nil, "a GIF needs a real size")
    }

    @Test
    func matroskaContainersAreRefused() {
        var webm = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x84]); webm.append(contentsOf: Array("webm".utf8))
        var mkv = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x88]); mkv.append(contentsOf: Array("matroska".utf8))
        #expect(EaselAssetType.sniff(webm) == nil && EaselAssetType.sniff(mkv) == nil, "WebM and other Matroska files aren't stored, since macOS can't play them")
    }

    @Test
    func plainTextIsNotAMediaAsset() {
        #expect(EaselAssetType.sniff(Data("hello world, not media".utf8)) == nil, "text is not media")
    }

    @Test
    func assetNamesIdentifyTheirSupportedType() {
        #expect(EaselAssetType.of(assetID: "abc.mov") == .mov && EaselAssetType.of(assetID: "abc.webm") == nil && EaselAssetType.of(assetID: "abc") == nil,
               "asset names carry their type")
    }

    @MainActor @Test
    func importedBytesMustMatchTheDeclaredType() throws {
        let board = try session([])
        #expect((try? board.importAsset(EaselImageFramingTestsSupport.gif, type: .gif))?.hasSuffix(".gif") == true, "GIF bytes import as a GIF asset")
        #expect((try? board.importAsset(EaselImageFramingTestsSupport.png, type: .gif)) == nil, "bytes must match the declared type")
    }

    @MainActor @Test
    func oversizedMoviesReportTheVideoLimit() throws {
        let board = try session([])
        do { _ = try board.importAsset(Data(count: EaselStore.maximumAssetBytes + 1), type: .mp4); Issue.record("huge videos are refused") }
        catch { #expect((error as? EaselStoreError).map { if case .videoTooLarge = $0 { return true } else { return false } } == true, "huge videos get the video message") }
        #expect(EaselStoreError.videoTooLarge.errorDescription?.contains("30 MB") == true, "the size message says how big videos can be")
    }

    @MainActor @Test
    func invalidMoviesReportTheVideoError() throws {
        let board = try session([])
        do { _ = try board.importAsset(EaselImageFramingTestsSupport.png, type: .mov); Issue.record("a PNG is not a movie") }
        catch { #expect((error as? EaselStoreError).map { if case .invalidVideo = $0 { return true } else { return false } } == true, "a fake movie gets the video message") }
    }

    @Test
    func savedImageFramingFieldsRoundTrip() throws {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        item.mask = .squircle
        item.altText = "Sunset"
        item.quarterTurns = 2
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(item)
        let decoded = try JSONDecoder().decode(EaselItem.self, from: data)
        #expect(decoded == item, "framing fields round-trip")
    }

    @Test
    func unframedImagesOmitFramingFields() {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let plain = (try? encoder.encode(EaselImageFramingTestsSupport.image())).map { String(decoding: $0, as: UTF8.self) } ?? ""
        #expect(!plain.contains("crop") && !plain.contains("mask") && !plain.contains("altText") && !plain.contains("quarterTurns"),
               "unframed images save exactly as before")
    }

    @Test
    func anUnknownSavedMaskIsRefused() throws {
        var item = EaselImageFramingTestsSupport.image()
        item.crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        item.mask = .squircle
        item.altText = "Sunset"
        item.quarterTurns = 2
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(item)
        let unknown = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"squircle\"", with: "\"blob\"")
        #expect((try? JSONDecoder().decode(EaselItem.self, from: Data(unknown.utf8))) == nil, "an unknown mask is refused")
    }
}
