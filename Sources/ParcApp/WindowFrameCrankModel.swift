import AppKit
import SceneKit
import simd

private typealias V2 = SIMD2<Float>
private typealias V3 = SIMD3<Float>
private typealias Displace = (_ s: Float, _ theta: Float, _ r: Float) -> Float

private struct LatheBand {
    var points: [V2]
    var density: Float = 0
    var displace: Displace?
    var material: SCNMaterial
}

private struct CrankTemplate {
    var root: SCNNode
    var cap: SCNMaterial
}

private struct EnvironmentKey: Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var dark: Bool
}

private struct ShadowPart {
    var geometry: SCNGeometry
    var transform: SCNMatrix4
    var turns: Bool
}

@MainActor
final class WindowFrameCrankModel {
    static let scale: CGFloat = 1.5
    static let armLength: CGFloat = 48
    static let paddleDepth: CGFloat = 5
    static let paddleLift: Float = 6
    static let shadowOffset = CGVector(dx: 7, dy: -9)
    static let shadowSpread: [(CGFloat, CGFloat)] = [(0, 0), (2.2, 0), (-2.2, 0), (0, 2.2), (0, -2.2),
                                                       (1.6, 1.6), (-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6)]
    static let shadowBase: CGFloat = 0.05
    static let shadowLayer: CGFloat = 0.01
    static let shadowFlatness: CGFloat = 0.0001
    static let shadowMinimumExtent: CGFloat = 2
    static let shadowOrder = -10_000
    static let environmentCacheLimit = 8
    private static var paddles: [CGFloat: SCNGeometry] = [:]
    private static var template: CrankTemplate?
    private static var environments: [EnvironmentKey: CGImage] = [:]

    let scene = SCNScene()
    let camera = SCNNode()
    let root: SCNNode
    let rotor: SCNNode
    let knob: SCNNode
    private(set) var ghostRotors: [SCNNode] = []
    private(set) var shadowParts = 0
    private(set) var armDegrees: Double = 90
    private let cap: SCNMaterial
    private let shade = SCNMaterial()
    private let key = SCNLight()
    private var palette: WindowFrameCrankPalette

    init(side: CGFloat, palette: WindowFrameCrankPalette) {
        self.palette = palette
        cap = SCNMaterial()
        cap.lightingModel = .physicallyBased
        cap.metalness.contents = 0.0
        cap.roughness.contents = 0.6
        let template = Self.crankTemplate()
        root = template.root.clone()
        rotor = root.childNode(withName: "rotor", recursively: true) ?? SCNNode()
        knob = rotor.childNode(withName: "knob", recursively: true) ?? SCNNode()
        Self.replace(template.cap, with: cap, in: root)
        root.scale = SCNVector3(Self.scale, Self.scale, Self.scale)
        root.position = SCNVector3(0, 0, 0.2)
        scene.rootNode.addChildNode(root)
        buildShadow()
        scene.background.contents = NSColor.clear
        let keyNode = SCNNode()
        key.type = .directional
        keyNode.light = key
        keyNode.simdPosition = SIMD3<Float>(-120, 150, 400)
        keyNode.look(at: SCNVector3(40, 30, 0))
        scene.rootNode.addChildNode(keyNode)
        let lens = SCNCamera()
        lens.usesOrthographicProjection = true
        lens.orthographicScale = Double(side / 2)
        lens.zNear = 1
        lens.zFar = 3000
        lens.wantsHDR = false
        camera.camera = lens
        camera.position = SCNVector3(0, 0, 1000)
        scene.rootNode.addChildNode(camera)
        apply(palette, force: true)
        setArm(degrees: armDegrees)
    }

    func apply(_ next: WindowFrameCrankPalette, force: Bool = false) {
        guard force || next != palette else { return }
        palette = next
        cap.diffuse.contents = Self.srgb(next.cap)
        shade.transparency = next.dark ? 0.09 : 0.06
        key.intensity = next.dark ? 700 : 900
        scene.lightingEnvironment.contents = Self.cachedEnvironment(deep: next.deep, dark: next.dark)
        scene.lightingEnvironment.intensity = next.dark ? 1.6 : 1.15
    }

    func setArm(degrees: Double) {
        armDegrees = degrees
        let angle = CGFloat(degrees * .pi / 180)
        rotor.eulerAngles = SCNVector3(0, 0, angle)
        for ghost in ghostRotors { ghost.eulerAngles = SCNVector3(0, 0, angle) }
    }

    var knobCenter: CGPoint {
        let p = knob.convertPosition(SCNVector3Zero, to: scene.rootNode)
        return CGPoint(x: p.x, y: p.y)
    }

    var arm: SCNNode? { rotor.childNode(withName: "arm", recursively: false) }

    static var cachedEnvironmentCount: Int { environments.count }

    static func cachedEnvironment(deep: NSColor, dark: Bool) -> CGImage? {
        let color = srgb(deep)
        let key = EnvironmentKey(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent, dark: dark)
        if let cached = environments[key] { return cached }
        guard let made = environment(deep: color, dark: dark) else { return nil }
        if environments.count >= environmentCacheLimit { environments.removeAll() }
        environments[key] = made
        return made
    }

    private static func crankTemplate() -> CrankTemplate {
        if let template { return template }
        let matte = metal(NSColor(srgbRed: 0.80, green: 0.81, blue: 0.83, alpha: 1), roughness: 0.46)
        let satin = metal(NSColor(srgbRed: 0.83, green: 0.84, blue: 0.86, alpha: 1), roughness: 0.34)
        let cap = SCNMaterial()
        let made = CrankTemplate(root: buildCrank(matte: matte, satin: satin, cap: cap), cap: cap)
        template = made
        return made
    }

    private static func replace(_ placeholder: SCNMaterial, with material: SCNMaterial, in node: SCNNode) {
        if let geometry = node.geometry, geometry.materials.contains(where: { $0 === placeholder }),
           let copy = geometry.copy() as? SCNGeometry {
            copy.materials = geometry.materials.map { $0 === placeholder ? material : $0 }
            node.geometry = copy
        }
        node.childNodes.forEach { replace(placeholder, with: material, in: $0) }
    }

    private static func buildCrank(matte: SCNMaterial, satin: SCNMaterial, cap: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        let rotor = SCNNode()
        let knob = SCNNode()
        var dome: [V2] = []
        for i in 0...14 {
            let a = Float(i) / 14 * (.pi / 2)
            dome.append(V2(0.6 + 2.4 * sin(a), 13 + 4.6 * cos(a)))
        }
        root.addChildNode(alongZ(part([
            LatheBand(points: [V2(0, 17.9), V2(0.6, 17.6)], material: satin),
            LatheBand(points: dome, density: 1, material: satin),
            LatheBand(points: [V2(3.0, 13), V2(3.0, 0)], material: satin),
        ])))

        let depth = paddleDepth
        let armZ: Float = 6.6
        let paddle = (paddleGeometry(depth: depth).copy() as? SCNGeometry) ?? paddleGeometry(depth: depth)
        paddle.materials = [matte]
        let arm = SCNNode(geometry: paddle)
        arm.name = "arm"
        arm.position = SCNVector3(0, 0, CGFloat(armZ))
        rotor.addChildNode(arm)

        let topZ = armZ + Float(depth) / 2
        var hubCap: [V2] = []
        for i in 0...12 {
            let f = Float(i) / 12
            hubCap.append(V2(topZ + 0.75 + 0.55 * (1 - (1 - f) * (1 - f)), 8.1 * (1 - f)))
        }
        rotor.addChildNode(alongZ(part([
            LatheBand(points: [V2(topZ - 0.3, 9.7), V2(topZ + 0.6, 9.7)], material: satin),
            LatheBand(points: [V2(topZ + 0.6, 9.7), V2(topZ + 1.0, 9.3)], material: satin),
            LatheBand(points: [V2(topZ + 1.0, 9.3), V2(topZ + 1.0, 8.4)], material: satin),
            LatheBand(points: [V2(topZ + 1.0, 8.4), V2(topZ + 0.75, 8.1)], material: satin),
            LatheBand(points: hubCap, density: 1, material: cap),
        ])))

        let z0 = topZ + 6 - 0.4
        let ribLength: Float = 7.2
        var knobCap: [V2] = []
        for i in 0...12 {
            let f = Float(i) / 12
            knobCap.append(V2(z0 + 7.5 + 0.6 * (1 - (1 - f) * (1 - f)), 7.7 * (1 - f)))
        }
        knob.addChildNode(alongZ(part([
            LatheBand(points: [V2(z0, 10.0), V2(z0 + ribLength, 10.0)], density: 8,
                      displace: straightKnurl(length: ribLength, teeth: 56, depth: 0.28, fade: 0.35), material: matte),
            LatheBand(points: [V2(z0 + ribLength, 10.0), V2(z0 + 8.0, 9.2)], material: satin),
            LatheBand(points: [V2(z0 + 8.0, 9.2), V2(z0 + 8.0, 7.9)], material: satin),
            LatheBand(points: [V2(z0 + 8.0, 7.9), V2(z0 + 7.5, 7.7)], material: satin),
            LatheBand(points: knobCap, density: 1, material: cap),
        ], segments: 448)))
        knob.name = "knob"
        knob.position = SCNVector3(armLength, 0, 0)
        rotor.addChildNode(knob)

        let label = SCNPlane(width: 12, height: 3.1)
        let etch = SCNMaterial()
        etch.lightingModel = .physicallyBased
        etch.diffuse.contents = NSColor(srgbRed: 0.42, green: 0.43, blue: 0.45, alpha: 1)
        etch.transparent.contents = engraveImage("PARC")
        etch.transparencyMode = .aOne
        etch.metalness.contents = 1.0
        etch.roughness.contents = 0.78
        etch.writesToDepthBuffer = false
        label.materials = [etch]
        let labelNode = SCNNode(geometry: label)
        labelNode.name = "label"
        labelNode.position = SCNVector3(19.5, 0, CGFloat(topZ) + 0.04)
        rotor.addChildNode(labelNode)

        rotor.name = "rotor"
        root.addChildNode(rotor)
        return root
    }

    private func buildShadow() {
        shade.lightingModel = .constant
        shade.diffuse.contents = NSColor.black
        shade.writesToDepthBuffer = true
        shade.readsFromDepthBuffer = true
        let parts = Self.silhouette(in: root, rotor: rotor).map { part -> ShadowPart in
            var shaded = part
            if let copy = part.geometry.copy() as? SCNGeometry {
                copy.materials = [shade]
                shaded.geometry = copy
            }
            return shaded
        }
        shadowParts = parts.count
        let layers = parts.count + 1
        for (index, spread) in Self.shadowSpread.enumerated() {
            let ghost = SCNNode()
            ghost.scale = SCNVector3(Self.scale, Self.scale, 1)
            ghost.position = SCNVector3(Self.shadowOffset.dx + spread.0, Self.shadowOffset.dy + spread.1,
                                        Self.shadowBase + CGFloat(index * layers) * Self.shadowLayer)
            let ghostRotor = SCNNode()
            ghostRotor.name = "rotor"
            ghost.addChildNode(ghostRotor)
            for (rank, part) in parts.enumerated() {
                let layer = SCNNode()
                layer.position = SCNVector3(0, 0, CGFloat(parts.count - rank) * Self.shadowLayer)
                layer.scale = SCNVector3(1, 1, Self.shadowFlatness)
                let piece = SCNNode(geometry: part.geometry)
                piece.transform = part.transform
                piece.renderingOrder = Self.shadowOrder + index * layers + rank
                layer.addChildNode(piece)
                (part.turns ? ghostRotor : ghost).addChildNode(layer)
            }
            scene.rootNode.addChildNode(ghost)
            ghostRotors.append(ghostRotor)
        }
    }

    private static func silhouette(in root: SCNNode, rotor: SCNNode) -> [ShadowPart] {
        var parts: [ShadowPart] = []
        func visit(_ node: SCNNode, frame: SCNNode, turns: Bool) {
            guard node.name != "label" else { return }
            if let geometry = node.geometry, extent(of: node, in: frame) >= shadowMinimumExtent {
                parts.append(ShadowPart(geometry: geometry, transform: node.convertTransform(SCNMatrix4Identity, to: frame), turns: turns))
            }
            for child in node.childNodes { visit(child, frame: frame, turns: turns) }
        }
        for child in root.childNodes {
            if child === rotor {
                rotor.childNodes.forEach { visit($0, frame: rotor, turns: true) }
            } else {
                visit(child, frame: root, turns: false)
            }
        }
        return parts
    }

    private static func extent(of node: SCNNode, in frame: SCNNode) -> CGFloat {
        let (low, high) = node.boundingBox
        var minX = CGFloat.infinity, maxX = -CGFloat.infinity, minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for x in [low.x, high.x] {
            for y in [low.y, high.y] {
                for z in [low.z, high.z] {
                    let p = node.convertPosition(SCNVector3(x, y, z), to: frame)
                    minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }
        return max(maxX - minX, maxY - minY)
    }

    static func paddleGeometry(depth: CGFloat) -> SCNGeometry {
        if let cached = paddles[depth] { return cached }
        let shape = SCNShape(path: paddlePath(r1: 13, r2: 10.5, length: armLength, pull: 7), extrusionDepth: depth)
        shape.chamferRadius = 1.9
        let profile = NSBezierPath()
        profile.move(to: CGPoint(x: 0, y: 1))
        profile.appendArc(withCenter: CGPoint(x: 1, y: 1), radius: 1, startAngle: 180, endAngle: 270, clockwise: false)
        profile.flatness = 0.01
        shape.chamferProfile = profile
        let lift = paddleLift
        let made = bent(shape) { x in lift * smooth(25, 42, x) }
        paddles[depth] = made
        return made
    }

    static func positions(_ geometry: SCNGeometry) -> [SIMD3<Float>] {
        geometry.sources(for: .vertex).first.map(readVectors) ?? []
    }

    private static func metal(_ color: NSColor, roughness: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = 1.0
        m.roughness.contents = roughness
        return m
    }

    static func srgb(_ color: NSColor) -> NSColor { color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1) }

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func environment(deep: NSColor, dark: Bool) -> CGImage? {
        let w = 1024, h = 512
        guard let ctx = context(w, h), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let k: CGFloat = dark ? 0.55 : 1
        func band(_ y0: CGFloat, _ y1: CGFloat, _ c0: NSColor, _ c1: NSColor) {
            guard let g = CGGradient(colorsSpace: space, colors: [c0.cgColor, c1.cgColor] as CFArray, locations: nil) else { return }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: y0 * CGFloat(h), width: CGFloat(w), height: (y1 - y0) * CGFloat(h)))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0 * CGFloat(h)), end: CGPoint(x: 0, y: y1 * CGFloat(h)), options: [])
            ctx.restoreGState()
        }
        func grey(_ v: CGFloat) -> NSColor { NSColor(white: min(1, v * k), alpha: 1) }
        band(0.00, 0.10, grey(1.0), grey(0.95))
        band(0.10, 0.28, grey(0.55), grey(0.28))
        band(0.28, 0.35, grey(0.98), grey(0.9))
        band(0.35, 0.47, grey(0.16), grey(0.10))
        band(0.47, 0.50, grey(0.75), grey(0.6))
        band(0.50, 0.60, grey(0.10), grey(0.08))
        let bounce: CGFloat = dark ? 0.45 : 0.85
        let mid = mix(deep, .white, 0.3)
        band(0.60, 1.00, scaled(mix(mid, .white, 0.15), bounce), scaled(deep, bounce * 0.7))
        ctx.setFillColor(grey(0.92).cgColor)
        ctx.fill(CGRect(x: 0.19 * CGFloat(w), y: 0.14 * CGFloat(h), width: 0.09 * CGFloat(w), height: 0.36 * CGFloat(h)))
        ctx.setFillColor(grey(0.7).cgColor)
        ctx.fill(CGRect(x: 0.71 * CGFloat(w), y: 0.18 * CGFloat(h), width: 0.05 * CGFloat(w), height: 0.30 * CGFloat(h)))
        return ctx.makeImage()
    }

    static func engraveImage(_ text: String) -> CGImage? {
        let w = 1300, h = 340
        guard let ctx = context(w, h) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.systemFont(ofSize: 240, weight: .heavy)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: 1), .kern: 46])
        let size = string.size()
        string.draw(at: CGPoint(x: (CGFloat(w) - size.width) / 2 + 23, y: (CGFloat(h) - size.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let a = srgb(a), b = srgb(b)
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }

    private static func scaled(_ c: NSColor, _ k: CGFloat) -> NSColor {
        let c = srgb(c)
        return NSColor(srgbRed: c.redComponent * k, green: c.greenComponent * k, blue: c.blueComponent * k, alpha: 1)
    }
}

private func tri(_ g: Float) -> Float { 1 - 2 * abs(g - floor(g) - 0.5) }

private func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

private func alongZ(_ node: SCNNode) -> SCNNode {
    node.eulerAngles = SCNVector3(0, -CGFloat.pi / 2, 0)
    return node
}

private func straightKnurl(length: Float, teeth: Int, depth: Float, fade: Float) -> Displace {
    { s, theta, _ in
        let h = tri(theta * Float(teeth) / (2 * .pi))
        let f = smooth(0, fade, s) * smooth(0, fade, length - s)
        return -depth * (1 - h) * f
    }
}

private func part(_ bands: [LatheBand], segments: Int = 256) -> SCNNode {
    let node = SCNNode()
    for band in bands { node.addChildNode(latheNode(band, segments: segments)) }
    return node
}

private func latheNode(_ band: LatheBand, segments: Int) -> SCNNode {
    var rows: [V2] = [band.points[0]]
    var along: [Float] = [0]
    var s: Float = 0
    for k in 1..<band.points.count {
        let a = band.points[k - 1], c = band.points[k]
        let length = simd_length(c - a)
        let n = max(1, Int(ceil(length * band.density)))
        for t in 1...n {
            let f = Float(t) / Float(n)
            rows.append(a + (c - a) * f)
            along.append(s + length * f)
        }
        s += length
    }
    let total = max(s, 1e-6)
    let cols = segments + 1
    var pos = [V3](repeating: .zero, count: rows.count * cols)
    for i in rows.indices {
        for j in 0..<cols {
            let theta = Float(j % segments) / Float(segments) * 2 * .pi
            var r = rows[i].y
            if let displace = band.displace, r > 0 { r += displace(along[i], theta, r) }
            pos[i * cols + j] = V3(rows[i].x, r * cos(theta), r * sin(theta))
        }
    }
    var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = []
    verts.reserveCapacity(pos.count); norms.reserveCapacity(pos.count); uvs.reserveCapacity(pos.count)
    for i in rows.indices {
        let ip = min(i + 1, rows.count - 1), im = max(i - 1, 0)
        for j in 0..<cols {
            let jj = j % segments
            let jp = (jj + 1) % segments, jm = (jj - 1 + segments) % segments
            let theta = Float(jj) / Float(segments) * 2 * .pi
            let tj = pos[i * cols + jp] - pos[i * cols + jm]
            let ti = pos[ip * cols + jj] - pos[im * cols + jj]
            var n = simd_cross(tj, ti)
            if simd_length(n) < 1e-9 {
                let d = rows[ip] - rows[im]
                let nn = simd_normalize(V2(-d.y, d.x))
                n = V3(nn.x, nn.y * cos(theta), nn.y * sin(theta))
            }
            n = simd_normalize(n)
            let p = pos[i * cols + j]
            verts.append(SCNVector3(CGFloat(p.x), CGFloat(p.y), CGFloat(p.z)))
            norms.append(SCNVector3(CGFloat(n.x), CGFloat(n.y), CGFloat(n.z)))
            uvs.append(CGPoint(x: 1 - CGFloat(j) / CGFloat(segments), y: CGFloat(along[i] / total)))
        }
    }
    var indices: [UInt32] = []
    indices.reserveCapacity((rows.count - 1) * segments * 6)
    for i in 0..<(rows.count - 1) {
        for j in 0..<segments {
            let a = UInt32(i * cols + j), b = UInt32(i * cols + j + 1)
            let c = UInt32((i + 1) * cols + j + 1), d = UInt32((i + 1) * cols + j)
            indices += [a, b, c, a, c, d]
        }
    }
    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                         SCNGeometrySource(textureCoordinates: uvs)],
                               elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    geometry.materials = [band.material]
    return SCNNode(geometry: geometry)
}

private func paddlePath(r1: CGFloat, r2: CGFloat, length: CGFloat, pull k: CGFloat) -> NSBezierPath {
    func on(_ c: CGPoint, _ r: CGFloat, _ deg: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * cos(deg * .pi / 180), y: c.y + r * sin(deg * .pi / 180))
    }
    func clockwise(_ deg: CGFloat) -> CGPoint { CGPoint(x: sin(deg * .pi / 180), y: -cos(deg * .pi / 180)) }
    let c1 = CGPoint.zero, c2 = CGPoint(x: length, y: 0)
    let p1 = on(c1, r1, 60), p2 = on(c2, r2, 120), q2 = on(c2, r2, -120), q1 = on(c1, r1, -60)
    let d1 = clockwise(60), d2 = clockwise(120), d3 = clockwise(-120), d4 = clockwise(-60)
    let path = NSBezierPath()
    path.move(to: p1)
    path.curve(to: p2, controlPoint1: CGPoint(x: p1.x + d1.x * k, y: p1.y + d1.y * k),
               controlPoint2: CGPoint(x: p2.x - d2.x * k, y: p2.y - d2.y * k))
    path.appendArc(withCenter: c2, radius: r2, startAngle: 120, endAngle: -120, clockwise: true)
    path.curve(to: q1, controlPoint1: CGPoint(x: q2.x + d3.x * k, y: q2.y + d3.y * k),
               controlPoint2: CGPoint(x: q1.x - d4.x * k, y: q1.y - d4.y * k))
    path.appendArc(withCenter: c1, radius: r1, startAngle: -60, endAngle: -300, clockwise: true)
    path.close()
    path.flatness = 0.04
    return path
}

private func readVectors(_ source: SCNGeometrySource) -> [V3] {
    let width = source.bytesPerComponent
    let count = source.vectorCount
    guard source.usesFloatComponents, width == 4 || width == 8, source.componentsPerVector >= 3, count > 0,
          source.dataOffset >= 0, source.dataStride >= 3 * width,
          source.dataOffset + (count - 1) * source.dataStride + 3 * width <= source.data.count else { return [] }
    var out: [V3] = []
    out.reserveCapacity(count)
    source.data.withUnsafeBytes { raw in
        for i in 0..<count {
            let base = source.dataOffset + i * source.dataStride
            if width == 8 {
                out.append(V3(Float(raw.loadUnaligned(fromByteOffset: base, as: Double.self)),
                              Float(raw.loadUnaligned(fromByteOffset: base + 8, as: Double.self)),
                              Float(raw.loadUnaligned(fromByteOffset: base + 16, as: Double.self))))
            } else {
                out.append(V3(raw.loadUnaligned(fromByteOffset: base, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: base + 4, as: Float.self),
                              raw.loadUnaligned(fromByteOffset: base + 8, as: Float.self)))
            }
        }
    }
    return out
}

@MainActor
private func bent(_ geometry: SCNGeometry, lift: @escaping (Float) -> Float) -> SCNGeometry {
    let warm = SCNScene()
    warm.rootNode.addChildNode(SCNNode(geometry: geometry))
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = warm
    _ = renderer.snapshot(atTime: 0, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
    guard let vertexSource = geometry.sources(for: .vertex).first, let normalSource = geometry.sources(for: .normal).first else { return geometry }
    let vertices = readVectors(vertexSource), normals = readVectors(normalSource)
    guard !vertices.isEmpty, vertices.count == normals.count else { return geometry }
    let slope: (Float) -> Float = { x in (lift(x + 0.01) - lift(x - 0.01)) / 0.02 }
    let moved = vertices.map { SCNVector3(CGFloat($0.x), CGFloat($0.y), CGFloat($0.z + lift($0.x))) }
    let tilted = zip(vertices, normals).map { p, q -> SCNVector3 in
        let r = simd_normalize(V3(q.x - slope(p.x) * q.z, q.y, q.z))
        return SCNVector3(CGFloat(r.x), CGFloat(r.y), CGFloat(r.z))
    }
    let out = SCNGeometry(sources: [SCNGeometrySource(vertices: moved), SCNGeometrySource(normals: tilted)] + geometry.sources(for: .texcoord),
                          elements: geometry.elements)
    out.materials = geometry.materials
    return out
}
