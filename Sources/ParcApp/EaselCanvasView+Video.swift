import AppKit
import AVFoundation
import UniformTypeIdentifiers

@MainActor
enum EaselVideoFacts {
    static func load(_ url: URL) async throws -> (size: CGSize, poster: CGImage?) {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw EaselStoreError.invalidVideo
        }
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let turned = size.applying(transform)
        let natural = CGSize(width: abs(turned.width), height: abs(turned.height))
        guard natural.width >= 1, natural.height >= 1, natural.width.isFinite, natural.height.isFinite else { throw EaselStoreError.invalidVideo }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        let poster = try? await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600)).image
        return (natural, poster)
    }
}

extension EaselCanvasView {
    static let movieTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie]

    func insertMediaFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        let movie = values.contentType?.conforms(to: .movie) == true
        guard values.isRegularFile == true, let size = values.fileSize else { throw EaselStoreError.invalidImage }
        guard size <= EaselStore.maximumAssetBytes else { throw movie ? EaselStoreError.videoTooLarge : EaselStoreError.assetImageTooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if movie || EaselAssetType.sniff(data)?.isVideo == true {
            try insertVideo(data, from: url)
        } else {
            try insertImageData(data)
        }
    }

    private func insertVideo(_ data: Data, from url: URL) throws {
        guard let type = EaselAssetType.sniff(data), type.isVideo, fixedCanvasSize == nil else { throw EaselStoreError.invalidVideo }
        let owner = window, document = session.document.id
        Task { @MainActor [weak self] in
            do {
                let facts = try await EaselVideoFacts.load(url)
                guard let self, self.window === owner, !self.session.isClosed, !self.session.isDeleted,
                      self.session.document.id == document else { return }
                try self.placeVideo(data, type: type, natural: facts.size, poster: facts.poster)
            } catch {
                self?.onError?(error)
            }
        }
    }

    private func placeVideo(_ data: Data, type: EaselAssetType, natural: CGSize, poster: CGImage?) throws {
        cancelPointerInteraction()
        guard finishEditing() else { throw EaselStoreError.invalidDocument("finish the current text edit") }
        if drawing { drawing = false }
        let assetID = try session.importAsset(data, type: type)
        var posterID: String?
        if let poster, let png = NSBitmapImageRep(cgImage: poster).representation(using: .png, properties: [:]) {
            posterID = try? session.importAsset(png, type: .png)
        }
        let width = min(480.0, Double(natural.width)), visible = visibleRect
        var item = EaselItem(kind: .video, frame: EaselRect(x: max(24, visible.midX - width / 2), y: visible.minY + 70,
                             width: width, height: max(1, width * Double(natural.height) / Double(natural.width))),
                             zIndex: (session.document.items.map(\.zIndex).max() ?? 0) + 1, assetID: assetID)
        item.poster = posterID
        do {
            try session.perform("Add video") { $0.items.append(item) }
        } catch {
            session.discardUnusedAssets([assetID] + [posterID].compactMap { $0 })
            throw error
        }
        selection = [item.id]
    }

    func drawVideoObject(_ item: EaselItem, in r: NSRect, controls: Bool) {
        let radius = min(8, r.width / 4, r.height / 4)
        let shape = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.black.setFill()
        r.fill()
        if let poster = item.poster.flatMap({ image($0) }), poster.size.width > 0, poster.size.height > 0 {
            let scale = max(r.width / poster.size.width, r.height / poster.size.height)
            let size = NSSize(width: poster.size.width * scale, height: poster.size.height * scale)
            poster.draw(in: NSRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard controls, let disc = videoPlayRect(in: r) else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = disc.width / 7
        shadow.shadowOffset = NSSize(width: 0, height: -disc.width / 28)
        shadow.set()
        NSColor(white: 0.05, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: disc).fill()
        NSGraphicsContext.restoreGraphicsState()
        let side = disc.width * 0.34, center = NSPoint(x: disc.midX + disc.width * 0.03, y: disc.midY)
        let triangle = NSBezierPath()
        triangle.move(to: NSPoint(x: center.x - side * 0.42, y: center.y - side / 2))
        triangle.line(to: NSPoint(x: center.x + side * 0.58, y: center.y))
        triangle.line(to: NSPoint(x: center.x - side * 0.42, y: center.y + side / 2))
        triangle.close()
        triangle.lineJoinStyle = .round
        triangle.lineWidth = side * 0.12
        NSColor.white.setFill()
        NSColor.white.setStroke()
        triangle.fill()
        triangle.stroke()
    }

    func videoPlayRect(in r: NSRect) -> NSRect? {
        let diameter = min(56 / CGFloat(canvasScale), min(r.width, r.height) * 0.6)
        guard diameter >= 12 else { return nil }
        return NSRect(x: r.midX - diameter / 2, y: r.midY - diameter / 2, width: diameter, height: diameter)
    }

    func videoPlayTarget(at point: NSPoint) -> EaselItem? {
        guard let item = items.last(where: {
            !$0.isLocked && NSRect(x: $0.frame.x, y: $0.frame.y, width: $0.frame.width, height: $0.frame.height).contains(point)
        }), item.kind == .video, !isPlayingVideo(item.id),
              let disc = videoPlayRect(in: NSRect(x: item.frame.x, y: item.frame.y, width: item.frame.width, height: item.frame.height)),
              disc.contains(point) else { return nil }
        return item
    }

    @discardableResult
    func playVideo(_ id: UUID) -> Bool {
        guard session.document.items.contains(where: { $0.id == id && $0.kind == .video }), window != nil, !session.isClosed else { return false }
        finishImageCrop(save: true)
        if selection != [id] { selection = [id] }
        needsLayout = true
        layoutSubtreeIfNeeded()
        let played = performHostedAction(.play, on: id)
        if played { NSAccessibility.post(element: self, notification: .layoutChanged) }
        return played
    }

    func pauseVideo(returningFocus: Bool = false) {
        guard let id = playingHostedVideo else { return }
        performHostedAction(.pause, on: id)
        if returningFocus { window?.makeFirstResponder(self) }
    }

    func stopVideoPlayback() {
        guard playingHostedVideo != nil else { return }
        performHostedAction(.stopAll, on: nil)
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }
}
