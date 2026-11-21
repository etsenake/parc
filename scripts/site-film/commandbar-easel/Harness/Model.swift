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

struct CanonTab {
    let title: String
    let url: String
    let kind: TabKind
    let icon: FaviconSpec

    init(_ title: String, _ url: String, _ kind: TabKind, _ symbol: String, _ fill: UInt32, glyph: NSColor = .white) {
        self.title = title; self.url = url; self.kind = kind
        icon = FaviconSpec(symbol: symbol, fill: hex(fill), glyph: glyph)
    }
}

@MainActor enum Canon {
    static let favorites = [
        CanonTab("Mail", "https://mail.example.com/inbox", .favorite, "envelope.fill", 0x3B82F6),
        CanonTab("Calendar", "https://calendar.example.com/week", .favorite, "calendar", 0xEF4444),
        CanonTab("Docs", "https://docs.example.com/home", .favorite, "doc.text.fill", 0x6366F1),
        CanonTab("Chat", "https://chat.example.com/team", .favorite, "bubble.left.and.bubble.right.fill", 0x10B981),
    ]
    static let workPinned = [
        CanonTab("Q4 planning", "https://docs.example.com/q4-planning", .pinned, "chart.bar.fill", 0x2563EB),
        CanonTab("Design review notes", "https://notes.example.com/design-review", .pinned, "pencil", 0x9333EA),
        CanonTab("Team calendar", "https://calendar.example.com/team", .pinned, "calendar", 0xEF4444),
    ]
    static let cityPark = CanonTab("The quiet genius of the city park", "https://fieldnotes.example/long-reads/city-park", .today, "leaf.fill", 0x1F2937)
    static let urbanParks = CanonTab("Urban parks — Field Notes", "https://fieldnotes.example/cities/urban-parks", .today, "leaf.fill", 0x1F2937)
    static let roadmap = CanonTab("Quarterly roadmap draft", "https://docs.example.com/roadmap", .today, "map.fill", 0x059669)
    static let checklist = CanonTab("Release checklist", "https://tracker.example.com/release", .today, "checklist", 0xF59E0B)
    static let weeklySync = CanonTab("Weekly sync agenda", "https://notes.example.com/weekly-sync", .today, "person.2.fill", 0x0EA5E9)
    static let workToday = [cityPark, urbanParks, roadmap, checklist, weeklySync]

    static let homePinned = [
        CanonTab("Sunday roast", "https://sundaytable.example/recipes/sunday-roast", .pinned, "fork.knife", 0xC2410C),
        CanonTab("Library holds", "https://library.example.org/account/holds", .pinned, "books.vertical.fill", 0x7C3AED),
    ]
    static let picnic = CanonTab("The perfect park picnic", "https://sundaytable.example/plans/park-picnic", .today, "basket.fill", 0xC2552D)
    static let homeToday = [picnic, CanonTab("Flights to Lisbon", "https://flights.example.com/search/lisbon", .today, "airplane", 0x0284C7)]

    static let questPinned = [
        CanonTab("Pottery wheel notes", "https://notes.example.com/pottery-wheel", .pinned, "hands.sparkles.fill", 0xB45309),
        CanonTab("Synth patch ideas", "https://notes.example.com/synth-patches", .pinned, "pianokeys", 0x334155),
    ]
    static let kite = CanonTab("How to fly a kite", "https://openair.example/guides/fly-a-kite", .today, "wind", 0x1F5136)
    static let bikeRoute = CanonTab("Weekend bike route", "https://routes.example.com/weekend-loop", .today, "bicycle", 0x16A34A)
    static let questToday = [kite, bikeRoute]

    static let meadow = CanonTab("East Meadow Park", "https://maps.example/place/east-meadow-park", .today, "mappin", 0x3E9B57)
    static let video = CanonTab("Golden hour over the hills — a slow film", "https://reel.example/watch/golden-hour", .today, "play.fill", 0xFF4A57)

    static func register() {
        for item in favorites + workPinned + workToday + homePinned + homeToday + questPinned + questToday + [meadow, video] {
            Favicons.specs[item.url] = item.icon
        }
    }
}

struct Scenario {
    var state: BrowserState
    var work: BrowserSpace
    var spaces: [BrowserSpace] = []
    var selected: BrowserTab
    var selectedBySpace: [UUID: BrowserTab] = [:]
    var todayTitles: [String]
    var panes: [BrowserTab] = []
    var named: [String: BrowserTab] = [:]
}

@MainActor enum ScenarioBuilder {
    static let base = Date(timeIntervalSince1970: 1_794_000_000)

    static func tab(_ item: CanonTab, in space: BrowserSpace, order: Double) -> BrowserTab {
        Favicons.specs[item.url] = item.icon
        return BrowserTab(id: UUID(), spaceID: space.id, profileID: space.profileID, url: item.url, title: item.title, kind: item.kind,
                          createdAt: base.addingTimeInterval(order * 60), lastAccessed: base.addingTimeInterval(order * 60),
                          savedURL: item.url, savedTitle: item.title)
    }

    static func make() -> Scenario {
        Canon.register()
        var state = BrowserState.initial()
        let profileID = state.spaces[0].profileID
        func space(_ name: String, _ symbol: String, _ color: String, colors: Int, wheel: SpaceTheme.Wheel = .analogous) -> BrowserSpace {
            var made = BrowserSpace(id: UUID(), name: name, symbol: symbol, color: color, profileID: profileID)
            let srgb = ThemeColor(hex: color)!
            made.theme = SpaceTheme(primaryColor: ThemeColor(red: srgb.red, green: srgb.green, blue: srgb.blue, colorSpace: .displayP3),
                                    colorCount: colors, wheel: wheel, intensity: 0.8)
            made.autoArchiveHours = state.spaces[0].autoArchiveHours
            return made
        }
        let work = space("Work", "briefcase.fill", "78B4E7", colors: 3)
        let home = space("Home", "house.fill", "F6CB5B", colors: 1)
        let quest = space("Side quest", "sparkles", "78DBA7", colors: 3, wheel: .complimentary)
        state.spaces = [work, home, quest]
        state.activeSpaceID = work.id
        var order = 0.0
        func tabs(_ items: [CanonTab], _ space: BrowserSpace) -> [BrowserTab] {
            items.map { item in order += 1; return tab(item, in: space, order: order) }
        }
        let favorites = tabs(Canon.favorites, work)
        let workPinned = tabs(Canon.workPinned, work)
        let workToday = tabs(Canon.workToday, work)
        let homeTabs = tabs(Canon.homePinned + Canon.homeToday, home)
        let questTabs = tabs(Canon.questPinned + Canon.questToday, quest)
        state.tabs = favorites + workPinned + workToday + homeTabs + questTabs
        let selected = workToday[0]
        let homeSelected = homeTabs[Canon.homePinned.count]
        let questSelected = questTabs[Canon.questPinned.count]
        let selectedBySpace = [work.id: selected, home.id: homeSelected, quest.id: questSelected]
        for (id, tab) in selectedBySpace { state.selectionBySpace[id.uuidString] = [tab.id] }
        state.selectedTabIDs = [selected.id]
        let panes = [Canon.picnic, Canon.meadow, Canon.kite].map { item in order += 1; return tab(item, in: work, order: order + 500) }
        return Scenario(state: state, work: work, spaces: [work, home, quest], selected: selected, selectedBySpace: selectedBySpace,
                        todayTitles: workToday.map(\.title), panes: panes,
                        named: ["kite": questSelected, "picnic": homeSelected])
    }
}

@MainActor enum MiniScenario {
    static func make() -> Scenario {
        var made = ScenarioBuilder.make()
        let quest = made.spaces[2]
        made.state.activeSpaceID = quest.id
        let video = ScenarioBuilder.tab(Canon.video, in: quest, order: 900)
        made.state.tabs.append(video)
        SidebarHierarchy.placingCreatedTab(video.id, insertion: .automatic, in: &made.state)
        made.state.selectedTabIDs = [video.id]
        made.state.selectionBySpace[quest.id.uuidString] = [video.id]
        made.work = quest
        made.selected = video
        made.selectedBySpace[quest.id] = video
        made.todayTitles = [video.title] + Canon.questToday.map(\.title)
        made.named["video"] = video
        return made
    }
}
