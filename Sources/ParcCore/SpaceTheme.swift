import Foundation

package struct ThemeColor: Codable, Equatable {
    package enum ColorSpace: String, Codable { case sRGB, displayP3, linearSRGB }
    package let red: Double
    package let green: Double
    package let blue: Double
    package let colorSpace: ColorSpace

    package init?(red: Double, green: Double, blue: Double, colorSpace: ColorSpace = .sRGB) {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        self.red = red; self.green = green; self.blue = blue
        self.colorSpace = colorSpace
    }

    package init?(hex: String) {
        guard hex.utf8.count == 6, hex.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }

    package var hex: String {
        String(format: "%02X%02X%02X", Int((red * 255).rounded()),
               Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    package var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2, delta = high - low
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = min(1, max(0, delta / (1 - abs(2 * lightness - 1))))
        let segment: Double
        if high == red { segment = (green - blue) / delta }
        else if high == green { segment = (blue - red) / delta + 2 }
        else { segment = (red - green) / delta + 4 }
        let hue = (segment / 6).truncatingRemainder(dividingBy: 1)
        return (hue < 0 ? hue + 1 : hue, saturation, lightness)
    }

    package static func hsl(hue: Double, saturation: Double, lightness: Double, colorSpace: ColorSpace = .sRGB) -> Self? {
        guard hue.isFinite, saturation.isFinite, lightness.isFinite,
              (0...1).contains(saturation), (0...1).contains(lightness) else { return nil }
        if saturation == 0 { return Self(red: lightness, green: lightness, blue: lightness, colorSpace: colorSpace) }
        let wrapped = hue.truncatingRemainder(dividingBy: 1)
        let h = wrapped < 0 ? wrapped + 1 : wrapped
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ offset: Double) -> Double {
            var t = h + offset
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            let result: Double
            if t < 1 / 6 { result = p + (q - p) * 6 * t }
            else if t < 1 / 2 { result = q }
            else if t < 2 / 3 { result = p + (q - p) * (2 / 3 - t) * 6 }
            else { result = p }
            return min(1, max(0, result))
        }
        return Self(red: channel(1 / 3), green: channel(0), blue: channel(-1 / 3), colorSpace: colorSpace)
    }

    private enum CodingKeys: String, CodingKey { case red, green, blue, colorSpace }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let color = Self(red: try c.decode(Double.self, forKey: .red),
                               green: try c.decode(Double.self, forKey: .green),
                               blue: try c.decode(Double.self, forKey: .blue),
                               colorSpace: try c.decode(ColorSpace.self, forKey: .colorSpace)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Theme color components must be finite values in 0...1."))
        }
        self = color
    }
}

package enum ThemeTexturePitch { package static let points: Double = 100 }

package struct SpaceTheme: Codable, Equatable {
    package enum Appearance: String, Codable, CaseIterable { case automatic, light, dark }
    package enum Wheel: String, Codable, CaseIterable { case complimentary, analogous }
    package enum Texture: String, Codable, CaseIterable { case grain, sand, denim, tweed }

    package var primaryColor: ThemeColor?
    package var colorCount: Int
    package var wheel: Wheel
    package var appearance: Appearance
    package var noise: Double
    package var intensity: Double
    package var texture: Texture

    package init(primaryColor: ThemeColor? = nil, colorCount: Int = 0, wheel: Wheel = .complimentary,
         appearance: Appearance = .automatic, noise: Double = 0, intensity: Double = 0.8,
         texture: Texture = .grain) {
        self.primaryColor = primaryColor; self.colorCount = colorCount; self.wheel = wheel
        self.appearance = appearance; self.noise = noise; self.intensity = intensity; self.texture = texture
    }

    package static func singleColor(_ color: ThemeColor) -> Self { Self(primaryColor: color, colorCount: 1) }

    package func textureStrength(isActive: Bool) -> Double {
        let maximum: Double
        switch texture { case .grain: maximum = 0.8; case .sand: maximum = 0.15; case .denim: maximum = 0.6; case .tweed: maximum = 0.4 }
        return noise * maximum * (isActive ? 1 : 0.25)
    }

    package var isValid: Bool {
        (0...3).contains(colorCount) && (primaryColor == nil) == (colorCount == 0)
            && noise.isFinite && (0...1).contains(noise)
            && intensity.isFinite && (0...1).contains(intensity)
    }

    package var colors: [ThemeColor] {
        guard isValid, let primaryColor else { return [] }
        let hsl = primaryColor.hsl
        let offsets: [Double]
        switch (wheel, colorCount) {
        case (_, 1): offsets = []
        case (.complimentary, 2): offsets = [0.5]
        case (.complimentary, 3): offsets = [5.0 / 12, 7.0 / 12]
        case (.analogous, 2): offsets = [1.0 / 9]
        case (.analogous, 3): offsets = [1.0 / 9, -1.0 / 9]
        default: return []
        }
        return [primaryColor] + offsets.compactMap {
            ThemeColor.hsl(hue: hsl.hue + $0, saturation: hsl.saturation, lightness: hsl.lightness,
                           colorSpace: primaryColor.colorSpace)
        }
    }

    package mutating func removeColor() {
        guard colorCount > 0 else { return }
        colorCount -= 1
        if colorCount == 1 { wheel = .complimentary }
        if colorCount == 0 {
            primaryColor = nil; noise = 0; intensity = 0.8; texture = .grain
        }
    }

    package mutating func setNoise(_ value: Double, rotating: Bool = false) {
        guard value.isFinite else { return }
        let bounded = min(1, max(0, value))
        noise = rotating ? bounded : (bounded * 20).rounded() / 20
    }

    private enum CodingKeys: String, CodingKey {
        case primaryColor, colorCount, wheel, appearance, noise, intensity, texture
    }
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryColor = try c.decodeIfPresent(ThemeColor.self, forKey: .primaryColor)
        colorCount = try c.decode(Int.self, forKey: .colorCount)
        wheel = try c.decode(Wheel.self, forKey: .wheel)
        appearance = try c.decode(Appearance.self, forKey: .appearance)
        noise = try c.decode(Double.self, forKey: .noise)
        intensity = try c.decode(Double.self, forKey: .intensity)
        texture = try c.decode(Texture.self, forKey: .texture)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Theme colors and modifiers are inconsistent or outside their supported ranges."))
        }
    }
}
