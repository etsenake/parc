import AppKit
import ParcCore

struct FaviconSpec {
    let symbol: String
    let fill: NSColor
    let glyph: NSColor
}

@MainActor enum Favicons {
    static var specs: [String: FaviconSpec] = [:]

    static func image(_ spec: FaviconSpec) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let plate = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            spec.fill.setFill(); plate.fill()
            let config = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [spec.glyph]))
            if let symbol = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = symbol.size
                symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }

    static func image(for tab: BrowserTab) -> NSImage? {
        specs[tab.url].map(image)
    }
}

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: alpha)
}

struct Scenario {
    var state: BrowserState
    var work: BrowserSpace
    var selected: BrowserTab
    var todayTitles: [String]
}

@MainActor enum ScenarioBuilder {
    static func make() -> Scenario {
        var state = BrowserState.initial()
        let profileID = state.spaces[0].profileID
        func space(_ name: String, _ symbol: String, _ color: String, colors: Int, wheel: SpaceTheme.Wheel, intensity: Double) -> BrowserSpace {
            var made = BrowserSpace(id: UUID(), name: name, symbol: symbol, color: color, profileID: profileID)
            let srgb = ThemeColor(hex: color)!
            made.theme = SpaceTheme(primaryColor: ThemeColor(red: srgb.red, green: srgb.green, blue: srgb.blue, colorSpace: .displayP3),
                                    colorCount: colors, wheel: wheel, intensity: intensity)
            made.autoArchiveHours = state.spaces[0].autoArchiveHours
            return made
        }
        let work = space("Work", "briefcase.fill", "78B4E7", colors: 3, wheel: .analogous, intensity: 0.8)
        let home = space("Home", "house.fill", "F6CB5B", colors: 1, wheel: .analogous, intensity: 0.8)
        let quest = space("Side quest", "sparkles", "78DBA7", colors: 1, wheel: .analogous, intensity: 0.8)
        state.spaces = [work, home, quest]
        state.activeSpaceID = work.id
        let base = Date(timeIntervalSince1970: 1_794_000_000)
        var order = 0.0
        func tab(_ title: String, _ url: String, _ kind: TabKind, _ icon: FaviconSpec) -> BrowserTab {
            order += 1
            Favicons.specs[url] = icon
            return BrowserTab(id: UUID(), spaceID: work.id, profileID: profileID, url: url, title: title, kind: kind,
                              createdAt: base.addingTimeInterval(order * 60), lastAccessed: base.addingTimeInterval(order * 60),
                              savedURL: url, savedTitle: title)
        }
        let white = NSColor.white
        let favorites = [
            tab("Mail", "https://mail.example.com/inbox", .favorite, FaviconSpec(symbol: "envelope.fill", fill: hex(0x3B82F6), glyph: white)),
            tab("Calendar", "https://calendar.example.com/week", .favorite, FaviconSpec(symbol: "calendar", fill: hex(0xEF4444), glyph: white)),
            tab("Docs", "https://docs.example.com/home", .favorite, FaviconSpec(symbol: "doc.text.fill", fill: hex(0x6366F1), glyph: white)),
            tab("Chat", "https://chat.example.com/team", .favorite, FaviconSpec(symbol: "bubble.left.and.bubble.right.fill", fill: hex(0x10B981), glyph: white)),
        ]
        let pinned = [
            tab("Q4 planning", "https://docs.example.com/q4-planning", .pinned, FaviconSpec(symbol: "chart.bar.fill", fill: hex(0x2563EB), glyph: white)),
            tab("Design review notes", "https://notes.example.com/design-review", .pinned, FaviconSpec(symbol: "pencil", fill: hex(0x9333EA), glyph: white)),
            tab("Team calendar", "https://calendar.example.com/team", .pinned, FaviconSpec(symbol: "calendar", fill: hex(0xEF4444), glyph: white)),
        ]
        let selected = tab("The quiet genius of the city park", "https://fieldnotes.example/long-reads/city-park", .today,
                           FaviconSpec(symbol: "leaf.fill", fill: hex(0x1F2937), glyph: white))
        let today = [
            selected,
            tab("Urban park — Wikipedia", "https://en.wikipedia.org/wiki/Urban_park", .today,
                FaviconSpec(symbol: "book.closed.fill", fill: hex(0x6B7280), glyph: white)),
            tab("Quarterly roadmap draft", "https://docs.example.com/roadmap", .today, FaviconSpec(symbol: "map.fill", fill: hex(0x059669), glyph: white)),
            tab("Release checklist", "https://tracker.example.com/release", .today, FaviconSpec(symbol: "checklist", fill: hex(0xF59E0B), glyph: white)),
            tab("Weekly sync agenda", "https://notes.example.com/weekly-sync", .today, FaviconSpec(symbol: "person.2.fill", fill: hex(0x0EA5E9), glyph: white)),
        ]
        state.tabs = favorites + pinned + today
        state.selectedTabIDs = [selected.id]
        return Scenario(state: state, work: work, selected: selected, todayTitles: today.map(\.title))
    }
}
