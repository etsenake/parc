import AppKit
import Testing
@testable import Parc

struct NavigationLoadingTestsAppearance {
    @MainActor private static func spaceHost(_ appearance: NSAppearance.Name) -> (PageLoadingIndicatorHost, UUID, UUID) {
        _ = NSApplication.shared
        let a = UUID(), b = UUID()
        let host = PageLoadingIndicatorHost(frame: NSRect(x: 0, y: 0, width: 400, height: 10))
        host.appearance = NSAppearance(named: appearance)
        host.update([.init(id: a, minX: 0, width: 200, loading: false), .init(id: b, minX: 200, width: 200, loading: true)])
        return (host, a, b)
    }

    @MainActor private static func colors(_ host: PageLoadingIndicatorHost, _ id: UUID) -> (fill: CGColor, bar: CGColor) {
        let layers = host.indicators[id]!.layer!.sublayers!.first!.sublayers!
        return (layers.first!.backgroundColor!, (layers.last as! CAShapeLayer).strokeColor!)
    }

    @MainActor private static func showsLight(_ host: PageLoadingIndicatorHost, _ id: UUID) -> Bool {
        let (fill, bar) = colors(host, id)
        return fill == bar && fill.colorSpace?.name == CGColorSpace.displayP3 && fill.components == [14.0 / 255, 15.0 / 255, 16.0 / 255, 0.9]
    }

    @MainActor private static func showsDark(_ host: PageLoadingIndicatorHost, _ id: UUID) -> Bool {
        let (fill, bar) = colors(host, id)
        return fill == bar && fill.colorSpace?.name == CGColorSpace.sRGB && fill.components == [1, 1, 1, 0.8]
    }

    @MainActor @Test func lightContentFillsAndBarsAreDisplayP3NearBlackAtPointNine() {
        let (host, a, b) = Self.spaceHost(.aqua)
        #expect(host.indicators.count == 2)
        #expect(Self.showsLight(host, a))
        #expect(Self.showsLight(host, b))
    }

    @MainActor @Test func darkContentFillsAndBarsAreWhiteAtPointEight() {
        let (host, a, b) = Self.spaceHost(.aqua)
        host.appearance = NSAppearance(named: .darkAqua)
        #expect(Self.showsDark(host, a))
        #expect(Self.showsDark(host, b))
    }

    @MainActor @Test func returningToLightContentRestoresNearBlack() {
        let (host, a, b) = Self.spaceHost(.aqua)
        host.appearance = NSAppearance(named: .darkAqua)
        host.appearance = NSAppearance(named: .aqua)
        #expect(Self.showsLight(host, a))
        #expect(Self.showsLight(host, b))
    }
}
