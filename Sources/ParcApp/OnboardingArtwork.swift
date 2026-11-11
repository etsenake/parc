import AppKit
import AVFoundation
import CoreText
import SwiftUI

enum OnboardingArtwork {
    static func url(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Onboarding")
    }

    static func image(_ name: String) -> NSImage? {
        url(name, extension: "png").flatMap(NSImage.init(contentsOf:))
    }

    static func cgImage(_ name: String) -> CGImage? {
        image(name)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static let headlineFont: NSFont = {
        if let url = url("MarlinSoftSQ-ExtraBold", extension: "otf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        if let font = NSFont(name: "MarlinSoftSQ-ExtraBold", size: 65) { return font }
        NSLog("Parc welcome font unavailable; using the system fallback.")
        return .systemFont(ofSize: 65, weight: .heavy)
    }()
}

struct OnboardingBackgroundView: View {
    let reduceMotion: Bool
    var startsSettled = false
    @State private var backgroundOpacity = 0.0
    @State private var maskRadius = 0.0
    @State private var orbOpacity = 0.0
    @State private var orbScale = 1.0
    @State private var blobScale = 0.0
    @State private var rotation = 0.0
    @State private var settled = false
    private let mask = OnboardingArtwork.image("orb-mask")

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                OnboardingVideo(name: "background", animates: !reduceMotion)
                    .frame(width: geometry.size.width + 100, height: geometry.size.width + 100)
                    .blur(radius: 75, opaque: true)
                    .opacity(backgroundOpacity)
                ZStack {
                    OnboardingVideo(name: "orb", animates: !reduceMotion && !settled)
                        .frame(width: geometry.size.width + 100, height: geometry.size.width + 100)
                        .blur(radius: 30)
                        .opacity(orbOpacity)
                        .scaleEffect(orbScale)
                    OnboardingGrain(animates: !reduceMotion)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .mask {
                    ZStack {
                        RadialGradient(colors: [.black, .clear], center: .center,
                                       startRadius: 0, endRadius: max(0.01, maskRadius))
                            .blur(radius: 20)
                        if let mask {
                            Image(nsImage: mask).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 300, height: 300)
                                .scaleEffect(blobScale).opacity(orbOpacity)
                                .rotationEffect(.degrees(rotation)).blur(radius: 50)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if reduceMotion || startsSettled { settle(); return }
            withAnimation(.easeOut(duration: 1)) {
                maskRadius = 160; orbOpacity = 1; blobScale = 1.2
            }
            withAnimation(.linear(duration: 6)) { rotation = Bool.random() ? 360 : -360 }
            do {
                try await Task.sleep(nanoseconds: 3_700_000_000)
                guard !settled else { return }
                withAnimation(.easeInOut(duration: 0.75)) { backgroundOpacity = 1 }
                try await Task.sleep(nanoseconds: 50_000_000)
                guard !settled else { return }
                withAnimation(.easeInOut(duration: 1)) {
                    orbScale = 8; orbOpacity = 0; maskRadius = 2_000; blobScale = 30
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                settled = true
            } catch { }
        }
        .onChange(of: reduceMotion) { reduced in if reduced { settle() } }
    }

    private func settle() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            settled = true; backgroundOpacity = 1; maskRadius = 2_000
            orbOpacity = 0; orbScale = 8; blobScale = 30; rotation = 0
        }
    }
}

private struct OnboardingGrain: NSViewRepresentable {
    let animates: Bool
    func makeNSView(context: Context) -> GrainView { GrainView() }
    func updateNSView(_ view: GrainView, context: Context) { view.animates = animates }
    static func dismantleNSView(_ view: GrainView, coordinator: ()) { view.stop() }

    final class GrainView: NSView {
        private var frames: [CGImage] = []
        var animates = false { didSet { updatePlayback() } }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            frames = (1...4).compactMap { OnboardingArtwork.cgImage("grain-\($0)") }
            layer?.contents = frames.first
            layer?.contentsGravity = .resize
            layer?.opacity = 0.4
        }
        convenience init() { self.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePlayback() }
        private func updatePlayback() {
            guard window != nil, animates, frames.count == 4 else {
                layer?.removeAnimation(forKey: "welcome.grain")
                layer?.contents = frames.first
                return
            }
            guard layer?.animation(forKey: "welcome.grain") == nil else { return }
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames
            animation.calculationMode = .discrete
            animation.duration = 0.175
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            layer?.add(animation, forKey: "welcome.grain")
        }
        func stop() {
            animates = false; layer?.removeAllAnimations(); layer?.contents = nil
            frames.removeAll()
        }
    }
}

enum OnboardingVideoHandoff {
    static let posterFadeDuration: TimeInterval = 0.5
    static let imageOpacityKey = "imageOpacity"

    enum Action: Equatable {
        case cutToVideo
        case fadeVideo(from: Float, duration: TimeInterval)
    }

    static func recoveredDuration(imageBeginTime: TimeInterval, now: TimeInterval) -> TimeInterval {
        min(imageBeginTime + posterFadeDuration - now, 0)
    }

    static func mediaDuration(recovered: TimeInterval) -> TimeInterval {
        max(recovered, 0)
    }

    static func action(
        presentationOpacity: Float?,
        imageBeginTime: TimeInterval?,
        now: TimeInterval
    ) -> Action {
        guard let presentationOpacity, presentationOpacity < 1, let imageBeginTime else {
            return .cutToVideo
        }
        let duration = mediaDuration(
            recovered: recoveredDuration(imageBeginTime: imageBeginTime, now: now)
        )
        return .fadeVideo(from: presentationOpacity, duration: duration)
    }

    static func reveal(
        poster: CALayer,
        video: CALayer,
        now: TimeInterval = CACurrentMediaTime(),
        presentationOpacity: Float? = nil
    ) {
        let imageBeginTime = poster.animation(forKey: imageOpacityKey)?.beginTime
        switch action(
            presentationOpacity: presentationOpacity ?? poster.presentation()?.opacity,
            imageBeginTime: imageBeginTime,
            now: now
        ) {
        case .cutToVideo:
            CATransaction.begin(); CATransaction.setDisableActions(true)
            video.opacity = 1
            CATransaction.commit()
        case .fadeVideo(let from, let duration):
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from
            animation.toValue = 1
            animation.duration = duration
            animation.beginTime = CACurrentMediaTime()
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.autoreverses = false
            animation.repeatCount = 0
            video.add(animation, forKey: nil)
        }
        poster.removeFromSuperlayer()
    }
}

private struct OnboardingVideo: NSViewRepresentable {
    let name: String
    let animates: Bool
    func makeNSView(context: Context) -> VideoView { VideoView(name: name) }
    func updateNSView(_ view: VideoView, context: Context) { view.animates = animates }
    static func dismantleNSView(_ view: VideoView, coordinator: ()) { view.stop() }

    final class VideoView: NSView {
        private let player = AVQueuePlayer()
        private let videoLayer = AVPlayerLayer()
        private let posterLayer = CALayer()
        private var looper: AVPlayerLooper?
        private var readyObserver: NSKeyValueObservation?
        private var hasEntered = false
        private var videoRevealed = false
        private var stopped = false
        var animates = false { didSet { updatePlayback() } }

        init(name: String) {
            super.init(frame: .zero)
            wantsLayer = true
            posterLayer.contents = OnboardingArtwork.cgImage("\(name)-poster")
            posterLayer.contentsGravity = .resizeAspectFill
            layer?.addSublayer(posterLayer)
            videoLayer.player = player
            videoLayer.videoGravity = .resizeAspectFill
            videoLayer.opacity = 0
            layer?.addSublayer(videoLayer)
            player.isMuted = true
            if let url = OnboardingArtwork.url(name, extension: "mp4") {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
            readyObserver = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.updatePlayback() }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            videoLayer.frame = bounds; posterLayer.frame = bounds
            CATransaction.commit()
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePlayback() }
        private func updatePlayback() {
            guard !stopped else { return }
            guard animates, window != nil else {
                player.pause()
                posterLayer.removeAllAnimations(); videoLayer.removeAllAnimations()
                showPoster()
                videoRevealed = false
                return
            }
            if !hasEntered {
                hasEntered = true
                fadePosterIn()
            }
            guard videoLayer.isReadyForDisplay else {
                player.pause()
                if videoRevealed {
                    videoLayer.removeAllAnimations()
                    showPoster()
                    videoRevealed = false
                }
                return
            }
            if !videoRevealed {
                OnboardingVideoHandoff.reveal(poster: posterLayer, video: videoLayer)
                videoRevealed = true
            }
            if videoLayer.animation(forKey: "welcome.videoRotation") == nil {
                let rotation = CABasicAnimation(keyPath: "transform.rotation")
                rotation.fromValue = 0; rotation.toValue = Double.pi * 2
                rotation.duration = 32; rotation.repeatCount = .infinity
                rotation.timingFunction = CAMediaTimingFunction(name: .linear)
                videoLayer.add(rotation, forKey: "welcome.videoRotation")
            }
            player.play()
        }

        private func showPoster() {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if posterLayer.superlayer == nil {
                layer?.insertSublayer(posterLayer, at: 0)
            }
            posterLayer.frame = bounds
            posterLayer.opacity = 1
            videoLayer.opacity = 0
            CATransaction.commit()
        }

        private func fadePosterIn() {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = OnboardingVideoHandoff.posterFadeDuration
            animation.beginTime = CACurrentMediaTime()
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.autoreverses = false
            animation.repeatCount = 0
            posterLayer.add(animation, forKey: OnboardingVideoHandoff.imageOpacityKey)
        }

        func stop() {
            stopped = true
            readyObserver?.invalidate(); readyObserver = nil
            player.pause(); looper?.disableLooping(); looper = nil
            player.removeAllItems(); videoLayer.player = nil
            posterLayer.removeAllAnimations(); videoLayer.removeAllAnimations()
            posterLayer.contents = nil
        }
    }
}
