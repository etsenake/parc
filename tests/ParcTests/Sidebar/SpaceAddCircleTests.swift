import AppKit
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcKit
@testable import ParcSidebar

@MainActor
struct SpaceAddCircleTests {
    private let light = NSAppearance(named: .aqua)!
    private let dark = NSAppearance(named: .darkAqua)!

    private func components(_ color: CGColor?) -> [CGFloat] {
        guard let color, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil) else { return [] }
        return converted.components ?? []
    }

    private func same(_ a: CGColor?, _ b: CGColor?) -> Bool {
        let x = components(a), y = components(b)
        return x.count == 4 && y.count == 4 && zip(x, y).allSatisfy { abs($0 - $1) < 0.002 }
    }

    private func fill(_ manager: SpaceManagerView) -> CGColor? {
        let add = sidebarDescendants(manager).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Create a Space" }
        return add?.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first?.fillColor
    }

    private func expected(_ theme: SpaceTheme, _ appearance: NSAppearance) -> CGColor {
        let palette = ThemeChromePalette(theme: theme, appearance: appearance)
        var color = NSColor.clear.cgColor
        (palette.contentAppearance ?? appearance).performAsCurrentDrawingAppearance { color = palette.cutoutColor.cgColor }
        return color
    }

    @MainActor private final class Pages {
        var state = BrowserState.initial()
        let blue: BrowserSpace
        let red: BrowserSpace
        var windows: [NSWindow] = []

        init(light: NSAppearance) {
            var blue = state.spaces[0]
            blue.theme = .singleColor(ThemeColor(hex: "3366CC")!)
            var red = BrowserSpace(id: UUID(), name: "Red", symbol: "star.fill", color: "CC3333", profileID: blue.profileID)
            red.theme = .singleColor(ThemeColor(hex: "CC3333")!)
            self.blue = blue
            self.red = red
            state.spaces = [blue, red]
            state.activeSpaceID = blue.id
        }

        func page(showing id: UUID, appearance: NSAppearance) -> SpaceManagerView {
            let manager = SpaceManagerView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
            let window = sidebarTestWindow(containing: manager)
            window.appearance = appearance
            windows.append(window)
            manager.ownerValid = { true }
            manager.windowSpaceID = { id }
            manager.reload(state)
            manager.layoutSubtreeIfNeeded()
            return manager
        }

        deinit { MainActor.assumeIsolated { for window in windows { window.contentView = nil } } }
    }

    @Test func theWindowOnTheBlueSpacePaintsItsAddCircleBlue() {
        let pages = Pages(light: light)
        let blue = pages.page(showing: pages.blue.id, appearance: light)
        #expect(same(fill(blue), expected(pages.blue.theme, light)))
    }

    @Test func theWindowOnTheRedSpaceUsesItsOwnSpaceNotTheStoresActiveSpace() {
        let pages = Pages(light: light)
        let blue = pages.page(showing: pages.blue.id, appearance: light)
        let red = pages.page(showing: pages.red.id, appearance: light)
        #expect(same(fill(red), expected(pages.red.theme, light)))
        #expect(!same(fill(red), fill(blue)))
    }

    @Test func anUnthemedSpaceResolvesItsAddCircleInAqua() {
        let pages = Pages(light: light)
        let blue = pages.page(showing: pages.blue.id, appearance: light)
        var plain = pages.state
        plain.spaces[0].theme = SpaceTheme()
        blue.reload(plain)
        blue.layoutSubtreeIfNeeded()
        #expect(same(fill(blue), expected(SpaceTheme(), light)))
    }

    @Test func anAppearanceChangeReResolvesTheAddCircleInDarkAqua() {
        let pages = Pages(light: light)
        let blue = pages.page(showing: pages.blue.id, appearance: light)
        var plain = pages.state
        plain.spaces[0].theme = SpaceTheme()
        blue.reload(plain)
        blue.layoutSubtreeIfNeeded()
        pages.windows[0].appearance = dark
        blue.layoutSubtreeIfNeeded()
        #expect(same(fill(blue), expected(SpaceTheme(), dark)))
        #expect(!same(fill(blue), expected(SpaceTheme(), light)))
    }
}
