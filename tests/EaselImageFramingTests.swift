import CoreGraphics
import Foundation

@main
struct EaselImageFramingTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    static func close(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat = 0.01) -> Bool {
        close(a.minX, b.minX, tolerance) && close(a.minY, b.minY, tolerance) && close(a.width, b.width, tolerance) && close(a.height, b.height, tolerance)
    }
    static func close(_ a: EaselRect?, _ b: EaselRect?, _ tolerance: Double = 0.0002) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3uoAAAAASUVORK5CYII=")!
    static let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!

    static func image(_ frame: EaselRect = .init(x: 100, y: 100, width: 200, height: 100)) -> EaselItem {
        EaselItem(kind: .image, frame: frame, assetID: UUID().uuidString.lowercased() + ".png")
    }

    @MainActor static func main() {
        turning()
        pictures()
        drafts()
        rotation()
        presets()
        replacingAndMasking()
        validation()
        videos()
        assets()
        coding()
        export()
        print("EaselImageFramingTests: \(assertions) assertions passed")
    }

    @MainActor static func turning() {
        let crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.5)
        for turns in 0...3 {
            let turned = EaselImageFraming.turnedCrop(crop, turns: turns)
            expect(close(EaselImageFraming.sourceCrop(turned, turns: turns), crop), "a crop survives a round trip through \(turns) quarter turns")
        }
        let quarter = EaselImageFraming.turnedCrop(crop, turns: 1)
        expect(abs(quarter.x - 0.3) < 0.0001 && abs(quarter.y - 0.1) < 0.0001 && abs(quarter.width - 0.5) < 0.0001 && abs(quarter.height - 0.3) < 0.0001,
               "a clockwise turn moves the source's left edge to the top")
        expect(EaselImageFraming.turnedSize(CGSize(width: 40, height: 10), turns: 3) == CGSize(width: 10, height: 40), "odd turns swap width and height")
        expect(EaselImageFraming.turns(-1) == 3 && EaselImageFraming.turns(5) == 1, "turns wrap around")
        expect(EaselImageFraming.sourceCrop(.full, turns: 2) == nil, "a whole picture has no crop")
        let aspect = EaselImageFraming.displayAspect(natural: CGSize(width: 400, height: 200), crop: EaselRect(x: 0, y: 0, width: 0.5, height: 1), turns: 1)
        expect(aspect.map { close($0, 1) } == true, "a half-width crop of a 2:1 picture turned once is square")
    }

    @MainActor static func pictures() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let picture = EaselImageFraming.pictureRect(frame: frame, crop: EaselRect(x: 0.25, y: 0, width: 0.5, height: 1), turns: 0)
        expect(close(picture, CGRect(x: 0, y: 100, width: 400, height: 100)), "the whole picture extends beyond a cropped frame")
        let source = EaselImageFraming.sourceRect(picture: CGRect(x: 0, y: 0, width: 100, height: 40), turns: 1)
        expect(close(source, CGRect(x: 30, y: -30, width: 40, height: 100)), "a turned picture draws its source rotated about the centre")
        let rotated = EaselImageFraming.rotatedClockwise(CGRect(x: 0, y: 0, width: 100, height: 40), around: CGPoint(x: 50, y: 20))
        expect(close(rotated, CGRect(x: 30, y: -30, width: 40, height: 100)), "rotating a rect clockwise swaps its sides about the pivot")
    }

    @MainActor static func drafts() {
        var draft = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        expect(draft.isWhole && close(draft.zoom, 1) && draft.picture == draft.frame, "an uncropped image starts whole at zoom 1")
        draft.setZoom(2)
        expect(close(draft.zoom, 2) && close(draft.frame, CGRect(x: 100, y: 100, width: 200, height: 100)), "zooming scales the picture under a fixed frame")
        expect(close(draft.picture, CGRect(x: 0, y: 50, width: 400, height: 200)), "zoom scales about the frame's centre")
        expect(close(draft.result.crop, EaselRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)), "a 2× zoom keeps the middle half")
        draft.move(by: CGSize(width: 500, height: -500))
        expect(close(draft.picture.minX, 100) && close(draft.picture.maxY, 200), "panning stops before the picture uncovers the frame")
        draft.setZoom(100)
        expect(close(draft.zoom, EaselImageCropDraft.maximumZoom), "zoom stops at its maximum")
        draft.setZoom(0.1)
        expect(close(draft.zoom, 1), "zoom never goes below a covering picture")
        var resized = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        resized.resize(.left, from: resized.frame, by: CGSize(width: 50, height: 0), lockingAspect: false)
        expect(close(resized.frame, CGRect(x: 150, y: 100, width: 150, height: 100)), "the left handle trims the left edge")
        expect(close(resized.result.crop, EaselRect(x: 0.25, y: 0, width: 0.75, height: 1)), "trimming becomes a normalised crop")
        resized.resize(.left, from: resized.frame, by: CGSize(width: -500, height: 0), lockingAspect: false)
        expect(close(resized.frame.minX, 100), "a handle can't pull the frame past the picture")
        resized.resize(.bottomRight, from: resized.frame, by: CGSize(width: -1000, height: -1000), lockingAspect: false)
        expect(resized.frame.width >= EaselImageCropDraft.minimumSide - 0.01 && resized.frame.height >= EaselImageCropDraft.minimumSide - 0.01,
               "the frame keeps a grabbable minimum size")
        var locked = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        locked.resize(.bottomRight, from: locked.frame, by: CGSize(width: -100, height: 0), lockingAspect: true)
        expect(close(locked.frame.width / locked.frame.height, 2), "Shift keeps the frame's ratio")
        var reset = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        reset.setZoom(3)
        reset.resize(.top, from: reset.frame, by: CGSize(width: 0, height: 40), lockingAspect: false)
        reset.reset()
        expect(reset.isWhole && close(reset.zoom, 1), "reset shows the whole picture again")
        var item = image()
        item.crop = EaselRect(x: 0.25, y: 0, width: 0.5, height: 1)
        let cropped = EaselImageCropDraft(item: item, natural: CGSize(width: 400, height: 100))
        expect(close(cropped.picture, CGRect(x: 0, y: 100, width: 400, height: 100)), "an existing crop opens showing the whole picture")
        expect(cropped.applying(to: item) == item, "saving an untouched draft changes nothing")
        var tight = image()
        tight.crop = EaselRect(x: 0.48, y: 0.48, width: 0.04, height: 0.04)
        tight.frame = EaselRect(x: 0, y: 0, width: 100, height: 100)
        var zoomed = EaselImageCropDraft(item: tight, natural: CGSize(width: 1000, height: 1000))
        expect(close(zoomed.zoom, 25) && zoomed.zoomLimit >= 25, "a tight saved crop reopens at its real zoom")
        let before = zoomed.picture.width
        zoomed.setZoom(zoomed.zoom * 1.25)
        expect(zoomed.picture.width >= before - 0.01, "zooming in on a tight crop never zooms out")
        zoomed.setZoom(zoomed.zoom / 1.25)
        expect(zoomed.picture.width < before + 0.01 && zoomed.picture.width > before * 0.7, "zooming back out steps down from the real zoom")
    }

    @MainActor static func rotation() {
        var draft = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        draft.rotate()
        expect(draft.turns == 1 && close(draft.frame, CGRect(x: 150, y: 50, width: 100, height: 200)), "rotating turns the frame about its centre")
        expect(draft.result.turns == 1 && draft.result.crop == nil, "a turned whole picture stores a turn and no crop")
        draft.setAspect(.square)
        let square = draft.result
        draft.rotate(); draft.rotate(); draft.rotate()
        expect(draft.turns == 0 && draft.result.turns == nil, "four turns come back to the start")
        expect(close(draft.frame.width, CGFloat(square.frame.width)) && close(draft.frame.height, CGFloat(square.frame.height)), "a square crop stays square while turning")
        var wide = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        wide.setAspect(.wide169)
        wide.rotate()
        expect(wide.aspect == .tall916, "a 16:9 crop becomes 9:16 when turned")
        var item = image()
        item.quarterTurns = 1
        item.frame = EaselRect(x: 0, y: 0, width: 100, height: 200)
        var turned = EaselImageCropDraft(item: item, natural: CGSize(width: 400, height: 200))
        turned.resize(.top, from: turned.frame, by: CGSize(width: 0, height: 100), lockingAspect: false)
        let applied = turned.applying(to: item)
        expect(applied.quarterTurns == 1 && close(applied.crop, EaselRect(x: 0.5, y: 0, width: 0.5, height: 1)),
               "a crop made on a turned picture is stored against the original image")
    }

    @MainActor static func presets() {
        var draft = EaselImageCropDraft(item: image(), natural: CGSize(width: 400, height: 200))
        draft.setAspect(.square)
        expect(close(draft.frame.width, draft.frame.height) && draft.picture.contains(draft.frame), "square fits inside the picture")
        draft.setAspect(.original)
        expect(close(draft.frame.width / draft.frame.height, 2), "original uses the picture's own ratio")
        draft.setAspect(.free)
        draft.setMask(.circle)
        expect(draft.mask == .circle && draft.aspect == .square && close(draft.frame.width, draft.frame.height), "a circle mask squares the crop")
        draft.setMask(.rounded)
        expect(draft.aspect == .free, "leaving a square mask frees the ratio again")
        expect(draft.result.mask == .rounded, "the mask is saved with the crop")
    }

    @MainActor static func replacingAndMasking() {
        var item = image()
        item.mask = .heart
        item.quarterTurns = 2
        item.altText = "A dog"
        item.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let replaced = EaselImageFraming.replacing(item, natural: CGSize(width: 100, height: 100))
        expect(replaced.frame == item.frame, "a replaced image keeps its size and spot")
        expect(replaced.quarterTurns == nil && replaced.mask == .heart && replaced.altText == nil,
               "replacing keeps the mask and drops the turn and the old picture's description")
        expect(close(replaced.crop, EaselRect(x: 0, y: 0.25, width: 1, height: 0.5)), "the new picture fills the old frame from its middle")
        let sameShape = EaselImageFraming.replacing(item, natural: CGSize(width: 800, height: 400))
        expect(sameShape.crop == nil, "a picture with the same shape needs no crop")
        let masked = EaselImageFraming.masking(image(), with: .circle)
        expect(masked.frame == EaselRect(x: 150, y: 100, width: 100, height: 100) && close(masked.crop, EaselRect(x: 0.25, y: 0, width: 0.5, height: 1)),
               "a circle mask squares a wide image from its middle")
        let rounded = EaselImageFraming.masking(image(), with: .rounded)
        expect(rounded.frame == image().frame && rounded.crop == nil && rounded.mask == .rounded, "a rounded mask keeps the frame")
        expect(EaselImageFraming.masking(masked, with: nil).mask == nil, "removing a mask keeps the crop")
        expect(EaselImageMask.allCases.allSatisfy { NoteImageMask(rawValue: $0.rawValue) != nil }, "every Easel mask is a Notes mask")
    }

    @MainActor static func session(_ items: [EaselItem], assets: [String: Data] = [:]) throws -> EaselSession {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        return try EaselSession(inMemory: EaselDocument(id: UUID(), title: "Images", createdAt: date, modifiedAt: date, items: items), assets: assets)
    }

    @MainActor static func accepts(_ item: EaselItem) -> Bool {
        (try? session([item], assets: item.assetID.map { [$0: png] } ?? [:])) != nil
    }

    @MainActor static func validation() {
        var item = image()
        item.crop = EaselRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        item.mask = .star
        item.altText = "Stars"
        item.quarterTurns = 3
        expect(accepts(item), "an image with every framing field opens")
        var bad = item; bad.crop = EaselRect(x: 0.6, y: 0, width: 0.5, height: 1)
        expect(!accepts(bad), "a crop past the picture is refused")
        bad = item; bad.crop = EaselRect(x: 0, y: 0, width: 0, height: 1)
        expect(!accepts(bad), "an empty crop is refused")
        bad = item; bad.crop = EaselRect(x: .nan, y: 0, width: 0.5, height: 1)
        expect(!accepts(bad), "a non-finite crop is refused")
        bad = item; bad.quarterTurns = 4
        expect(!accepts(bad), "turns stay between one and three")
        bad = item; bad.altText = String(repeating: "a", count: 5000)
        expect(!accepts(bad), "alt text has a size limit")
        var shape = EaselItem(kind: .rectangle, frame: .init(x: 0, y: 0, width: 10, height: 10))
        shape.mask = .circle
        expect(!accepts(shape), "masks belong to images")
        shape.mask = nil; shape.altText = "Box"
        expect(!accepts(shape), "alt text belongs to images")
        shape.altText = nil; shape.crop = EaselRect(x: 0, y: 0, width: 1, height: 1)
        expect(!accepts(shape), "crops belong to images")
        shape.crop = nil; shape.quarterTurns = 1
        expect(!accepts(shape), "turns belong to images")
        var animated = image()
        animated.assetID = UUID().uuidString.lowercased() + ".gif"
        expect(accepts(animated), "an image can hold a GIF")
        var card = EaselItem(kind: .webCard, frame: .init(x: 0, y: 0, width: 10, height: 10), url: "https://example.com")
        card.assetID = UUID().uuidString.lowercased() + ".gif"
        expect(!accepts(card), "GIFs only live in images")
    }

    @MainActor static func videos() {
        let movie = UUID().uuidString.lowercased() + ".mp4", poster = UUID().uuidString.lowercased() + ".png"
        var video = EaselItem(kind: .video, frame: .init(x: 0, y: 0, width: 320, height: 180), assetID: movie)
        video.poster = poster
        video.altText = "A demo"
        expect((try? session([video], assets: [movie: png, poster: png])) != nil, "a video with a poster and alt text opens")
        var bare = video; bare.poster = nil
        expect((try? session([bare], assets: [movie: png])) != nil, "a poster is optional")
        var noAsset = video; noAsset.assetID = nil
        expect((try? session([noAsset], assets: [poster: png])) == nil, "a poster needs its movie")
        noAsset.poster = nil
        expect((try? session([noAsset], assets: [:])) != nil, "an empty video is a placeholder")
        var stillVideo = video; stillVideo.assetID = poster
        expect((try? session([stillVideo], assets: [poster: png])) == nil, "a video's asset must be a movie")
        var gifPoster = video; gifPoster.poster = UUID().uuidString.lowercased() + ".gif"
        expect((try? session([gifPoster], assets: [movie: png, gifPoster.poster ?? "": gif])) == nil, "posters are PNGs")
        var moviePicture = image(); moviePicture.assetID = movie
        expect((try? session([moviePicture], assets: [movie: png])) == nil, "an image can't hold a movie")
        var posterOnImage = image(); posterOnImage.poster = poster
        expect((try? session([posterOnImage], assets: [posterOnImage.assetID ?? "": png, poster: png])) == nil, "only videos have posters")
        var croppedVideo = video; croppedVideo.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 0.5)
        expect((try? session([croppedVideo], assets: [movie: png, poster: png])) == nil, "videos don't crop")
        let html = EaselVectorExport.element(video, art: EaselVectorArt(images: [video.id: EaselVectorImage(data: png, mimeType: "image/png")]))
        expect(html.contains("aria-label=\"A demo\"") && html.contains("<image "), "a video exports as its labelled poster")
        expect(EaselVectorExport.element(video, art: EaselVectorArt()).isEmpty, "a video without a poster exports nothing")
        var mp4 = Data([0, 0, 0, 0x18]); mp4.append(contentsOf: Array("ftypmp42".utf8)); mp4.append(Data(count: 12))
        guard let board = try? session([]) else { fatalError("an empty Easel opens") }
        guard let stored = try? board.importAsset(mp4, type: .mp4) else { fatalError("movie bytes import") }
        expect(stored.hasSuffix(".mp4"), "movies keep their type")
        board.discardUnusedAssets([stored])
        expect((try? board.assetData(stored)) == nil, "an unused imported movie can be thrown away")
    }

    @MainActor static func assets() {
        expect(EaselAssetType.sniff(png) == .png && EaselAssetType.sniff(gif) == .gif, "PNG and GIF are recognised by their bytes")
        var mp4 = Data([0, 0, 0, 0x18]); mp4.append(contentsOf: Array("ftypisom".utf8)); mp4.append(Data(count: 12))
        var mov = Data([0, 0, 0, 0x14]); mov.append(contentsOf: Array("ftypqt  ".utf8)); mov.append(Data(count: 12))
        var old = Data([0, 0, 0, 0x08]); old.append(contentsOf: Array("wide".utf8)); old.append(Data(count: 12))
        var stranger = Data([0, 0, 0, 0x18]); stranger.append(contentsOf: Array("ftypabcd".utf8)); stranger.append(Data(count: 12))
        var compatible = Data([0, 0, 0, 0x18]); compatible.append(contentsOf: Array("ftypabcd".utf8)); compatible.append(Data(count: 4))
        compatible.append(contentsOf: Array("mp41".utf8)); compatible.append(Data(count: 4))
        var flat = gif; flat.replaceSubrange(6..<10, with: [0, 0, 0, 0])
        var webm = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x84]); webm.append(contentsOf: Array("webm".utf8))
        var mkv = Data([0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x88]); mkv.append(contentsOf: Array("matroska".utf8))
        expect(EaselAssetType.sniff(mp4) == .mp4 && EaselAssetType.sniff(mov) == .mov, "MP4 and QuickTime movies are recognised by their ftyp box")
        expect(EaselAssetType.sniff(old) == .mov, "an older QuickTime movie without an ftyp box still counts")
        expect(EaselAssetType.sniff(stranger) == .mp4 && EaselAssetType.sniff(compatible) == .mp4, "any non-still ftyp brand is an MP4")
        expect(EaselAssetType.sniff(flat) == nil, "a GIF needs a real size")
        expect(EaselAssetType.sniff(webm) == nil && EaselAssetType.sniff(mkv) == nil, "WebM and other Matroska files aren't stored, since macOS can't play them")
        expect(EaselAssetType.sniff(Data("hello world, not media".utf8)) == nil, "text is not media")
        expect(EaselAssetType.of(assetID: "abc.mov") == .mov && EaselAssetType.of(assetID: "abc.webm") == nil && EaselAssetType.of(assetID: "abc") == nil,
               "asset names carry their type")
        guard let board = try? session([]) else { fatalError("an empty Easel opens") }
        expect((try? board.importAsset(gif, type: .gif))?.hasSuffix(".gif") == true, "GIF bytes import as a GIF asset")
        expect((try? board.importAsset(png, type: .gif)) == nil, "bytes must match the declared type")
        do { _ = try board.importAsset(Data(count: EaselStore.maximumAssetBytes + 1), type: .mp4); expect(false, "huge videos are refused") }
        catch { expect((error as? EaselStoreError).map { if case .videoTooLarge = $0 { return true } else { return false } } == true, "huge videos get the video message") }
        do { _ = try board.importAsset(png, type: .mov); expect(false, "a PNG is not a movie") }
        catch { expect((error as? EaselStoreError).map { if case .invalidVideo = $0 { return true } else { return false } } == true, "a fake movie gets the video message") }
        expect(EaselStoreError.videoTooLarge.errorDescription?.contains("30 MB") == true, "the size message says how big videos can be")
    }

    @MainActor static func coding() {
        var item = image()
        item.crop = EaselRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        item.mask = .squircle
        item.altText = "Sunset"
        item.quarterTurns = 2
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(item), let decoded = try? JSONDecoder().decode(EaselItem.self, from: data) else {
            fatalError("framed images encode and decode")
        }
        expect(decoded == item, "framing fields round-trip")
        let plain = (try? encoder.encode(image())).map { String(decoding: $0, as: UTF8.self) } ?? ""
        expect(!plain.contains("crop") && !plain.contains("mask") && !plain.contains("altText") && !plain.contains("quarterTurns"),
               "unframed images save exactly as before")
        let unknown = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"squircle\"", with: "\"blob\"")
        expect((try? JSONDecoder().decode(EaselItem.self, from: Data(unknown.utf8))) == nil, "an unknown mask is refused")
    }

    @MainActor static func export() {
        let picture = EaselVectorImage(data: png, mimeType: "image/png")
        var item = image()
        let plain = EaselVectorExport.element(item, art: EaselVectorArt(images: [item.id: picture]))
        expect(plain.hasPrefix("<image ") && !plain.contains("clipPath"), "an unframed image exports as a plain image")
        item.altText = "A <cat>"
        item.mask = .circle
        item.quarterTurns = 1
        item.crop = EaselRect(x: 0, y: 0, width: 0.5, height: 1)
        let framed = EaselVectorExport.element(item, art: EaselVectorArt(images: [item.id: picture]))
        expect(framed.contains("<clipPath") && framed.contains("clip-path=\"url(#frame-"), "a framed image clips to its frame")
        expect(framed.contains("transform=\"rotate(90 "), "turns export as a rotation")
        expect(framed.contains("aria-label=\"A &lt;cat&gt;\"") && framed.contains("<title>A &lt;cat&gt;</title>"), "alt text exports escaped as a label and title")
        expect(framed.contains("<path d=\"M"), "a mask exports as its outline")
    }
}
