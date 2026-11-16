import Foundation
import CoreGraphics
import CoreImage

public enum LayerSpace { case background, world, overlay }

public struct ShadowStyle {
    public var opacity: Double
    public var radius: Double
    public var offset: Double
    public var contactOpacity: Double
    public var contactRadius: Double
    public var contactOffset: Double

    public init(opacity: Double, radius: Double, offset: Double, contactOpacity: Double, contactRadius: Double, contactOffset: Double) {
        self.opacity = opacity; self.radius = radius; self.offset = offset
        self.contactOpacity = contactOpacity; self.contactRadius = contactRadius; self.contactOffset = contactOffset
    }

    public static let window = ShadowStyle(opacity: 0.30, radius: 42, offset: 30, contactOpacity: 0.20, contactRadius: 5, contactOffset: 2)
    public static let card = ShadowStyle(opacity: 0.34, radius: 34, offset: 24, contactOpacity: 0.18, contactRadius: 3, contactOffset: 1.5)
}

public final class Layer {
    public let name: String
    public var content: (Double) -> CIImage
    public var size: CGSize
    public var space: LayerSpace
    public var position: Track<Vec3>
    public var rotation = Track<Vec3>(.zero)
    public var scale = Track<Double>(1)
    public var opacity = Track<Double>(1)
    public var blur = Track<Double>(0)
    public var exposure = Track<Double>(0)
    public var elevation = Track<Double>(1)
    public var anchor = CGPoint(x: 0.5, y: 0.5)
    public var shadow: ShadowStyle?
    public var depthOfField = true
    public var backgroundDepth: Double = 0
    public var edgeClamp = false

    public init(_ name: String, space: LayerSpace = .world, size: CGSize, at position: Vec3 = .zero, image: CIImage) {
        self.name = name
        self.space = space
        self.size = size
        self.position = Track(position)
        self.content = { _ in image }
    }

    public init(_ name: String, space: LayerSpace = .world, size: CGSize, at position: Vec3 = .zero, provider: @escaping (Double) -> CIImage) {
        self.name = name
        self.space = space
        self.size = size
        self.position = Track(position)
        self.content = provider
    }
}

public struct Camera {
    public var position = Track<Vec3>(.zero)
    public var rotation = Track<Vec3>(.zero)
    public var focalLength = Track<Double>(2400)
    public var focus = Track<Double>(0)
    public var aperture = Track<Double>(0)
    public var crop: Track<Vec3>?
    public var cropSpace = CGSize(width: 1280, height: 840)
    public var cropPlate = CGSize(width: 1920, height: 1260)
    public init() {}

    public static func inside(plate: CGSize, space: CGSize = CGSize(width: 1280, height: 840), start: Vec3) -> Camera {
        var c = Camera()
        c.cropPlate = plate
        c.cropSpace = space
        c.crop = Track(start)
        return c
    }

    public func eyePosition(at t: Double) -> Vec3 {
        guard let crop else { return position.value(at: t) }
        let v = crop.value(at: t)
        let zoom = max(1, v.z)
        let kx = Double(cropPlate.width / cropSpace.width), ky = Double(cropPlate.height / cropSpace.height)
        let mx = Double(cropPlate.width) / 2 * (1 - 1 / zoom), my = Double(cropPlate.height) / 2 * (1 - 1 / zoom)
        let x = min(max((v.x - Double(cropSpace.width) / 2) * kx, -mx), mx)
        let y = min(max((v.y - Double(cropSpace.height) / 2) * ky, -my), my)
        return Vec3(x, y, focalLength.value(at: t) * (1 - 1 / zoom))
    }
}

public enum Transition {
    case cut
    case dissolve(Double)
    case flood(color: CIColor, duration: Double, origin: CGPoint)

    var duration: Double {
        switch self {
        case .cut: return 0
        case let .dissolve(d): return d
        case let .flood(_, d, _): return d
        }
    }
}

public final class Shot {
    public let name: String
    public var start: Double
    public var duration: Double
    public var layers: [Layer] = []
    public var camera = Camera()
    public var transitionIn: Transition = .cut
    public var backdrop = CIColor(red: 0, green: 0, blue: 0)
    public var exposure = Track<Double>(0)

    public init(_ name: String, start: Double, duration: Double) {
        self.name = name; self.start = start; self.duration = duration
    }

    public var end: Double { start + duration }

    @discardableResult
    public func add(_ layer: Layer) -> Layer { layers.append(layer); return layer }
}

public struct FilmSettings {
    public var width = 1920
    public var height = 1080
    public var fps = 60
    public var supersample = 2
    public var motionBlur = true
    public var maxMotionSamples = 32
    public var shutter = 0.5
    public var motionThreshold = 1.25
    public var motionMinimum = 0.0
    public var grain = 0.022
    public var vignette = 0.10
    public init() {}
}

public final class Film {
    public var settings: FilmSettings
    public var duration: Double
    public var shots: [Shot] = []

    public init(duration: Double, settings: FilmSettings = FilmSettings()) {
        self.duration = duration
        self.settings = settings
    }

    @discardableResult
    public func add(_ shot: Shot) -> Shot { shots.append(shot); shots.sort { $0.start < $1.start }; return shot }

    public var frameCount: Int { Int((duration * Double(settings.fps)).rounded()) }
}
