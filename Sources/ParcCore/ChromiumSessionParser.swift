import Foundation

package enum ChromiumSessionParser {
    package struct Outcome: Equatable {
        package var session: ChromiumSession?
        package var encryptedUnreadable = false

        package init(session: ChromiumSession?, encryptedUnreadable: Bool = false) {
            self.session = session
            self.encryptedUnreadable = encryptedUnreadable
        }
    }

    struct Command {
        let id: UInt8
        let payload: [UInt8]
    }

    static let maximumFileBytes = 128 * 1024 * 1024
    static let signature: UInt32 = 0x5353_4E53
    static let markerID: UInt8 = 255
    static let operaMarkerID: UInt8 = 252

    package static func read(profileDirectory: URL, flavor: ChromiumFlavor, decrypt: SidebarDecryptor?) -> Outcome {
        let plain = profileDirectory.appendingPathComponent("Sessions", isDirectory: true)
        let encrypted = profileDirectory.appendingPathComponent("Sessions_Encrypted", isDirectory: true)
        var unreadable = false
        var decryptFailed = false

        func newest<T>(prefix: String, parse: (Data) -> T?) -> T? {
            if let found: T = firstValid(in: plain, prefix: prefix, load: { try readFile($0) }, parse: parse) { return found }
            guard !files(in: encrypted, prefix: prefix).isEmpty else { return nil }
            guard let decrypt, !decryptFailed else { unreadable = true; return nil }
            return firstValid(in: encrypted, prefix: prefix, load: { url in
                guard !decryptFailed else { throw CocoaError(.userCancelled) }
                do { return try decrypt(url, .chromiumSession) } catch {
                    decryptFailed = true
                    unreadable = true
                    throw error
                }
            }, parse: parse)
        }

        var found = newest(prefix: "Session_") { Self.session($0, flavor: flavor) }
        if let closed = newest(prefix: "Tabs_", parse: { Self.closedTabs($0, flavor: flavor) }), !closed.isEmpty {
            if found == nil { found = ChromiumSession() }
            found?.closedTabs = closed
        }
        return Outcome(session: found, encryptedUnreadable: unreadable && found?.windows.isEmpty != false)
    }

    package static func session(_ data: Data, flavor: ChromiumFlavor) -> ChromiumSession? {
        let opera = flavor == .opera || flavor == .operaGX
        let marker: (Command) -> Bool = {
            opera ? $0.id == Self.operaMarkerID || ($0.id == Self.markerID && $0.payload.isEmpty) : $0.id == Self.markerID
        }
        guard let stream = commands(in: data, isMarker: marker), stream.marker else { return nil }
        var replay = SessionReplay(flavor: flavor)
        replay.run(stream.commands)
        return replay.session()
    }

    package static func closedTabs(_ data: Data, flavor: ChromiumFlavor) -> [ChromiumSession.ClosedTab]? {
        guard let stream = commands(in: data, isMarker: { $0.id == Self.markerID }), stream.marker else { return nil }
        var replay = ClosedTabReplay()
        replay.run(stream.commands)
        return replay.closedTabs()
    }

    static func commands(in data: Data, isMarker: (Command) -> Bool) -> (commands: [Command], marker: Bool)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, ChromiumBytes.uint32(bytes, at: 0) == signature,
              ChromiumBytes.int32(bytes, at: 4) == 3 else { return nil }
        var offset = 8, list: [Command] = [], marker = false
        while bytes.count - offset >= 2 {
            let size = Int(ChromiumBytes.uint16(bytes, at: offset))
            guard size >= 1, size <= bytes.count - offset - 2 else { break }
            let command = Command(id: bytes[offset + 2], payload: Array(bytes[(offset + 3)..<(offset + 2 + size)]))
            offset += 2 + size
            if isMarker(command) { marker = true } else { list.append(command) }
        }
        return (list, marker)
    }

    static func files(in directory: URL, prefix: String) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { name -> (UInt64, URL)? in
            guard name.hasPrefix(prefix) else { return nil }
            let suffix = name.dropFirst(prefix.count)
            guard !suffix.isEmpty, suffix.allSatisfy(\.isASCII), suffix.allSatisfy(\.isNumber),
                  let stamp = UInt64(suffix) else { return nil }
            return (stamp, directory.appendingPathComponent(name))
        }.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private static func firstValid<T>(in directory: URL, prefix: String, load: (URL) throws -> Data,
                                      parse: (Data) -> T?) -> T? {
        for _ in 0..<2 {
            var vanished = false
            for url in files(in: directory, prefix: prefix) {
                let data: Data
                do { data = try load(url) } catch {
                    if isMissing(error) { vanished = true; continue }
                    return nil
                }
                if let value = parse(data) { return value }
            }
            if !vanished { break }
        }
        return nil
    }

    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) {
            return true
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }

    private static func readFile(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumFileBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    static func date(windowsMicroseconds value: Int64) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(value) / 1_000_000 - 11_644_473_600)
    }
}

private struct Navigation {
    var index: Int32
    var url: String
    var title: String

    static func read(_ pickle: inout ChromiumPickle) -> Navigation? {
        guard let index = pickle.int32(), let url = pickle.string(), let title = pickle.string16(),
              pickle.string() != nil, pickle.int32() != nil else { return nil }
        return Navigation(index: index, url: url, title: title)
    }
}

private struct SessionReplay {
    enum Kind {
        case setTabWindow, tabIndex, prunedFromBack, navigation, selectedNavigation, selectedTab, windowType
        case windowBounds2, prunedFromFront, pinned, extensionAppID, windowBounds3, windowAppName, tabClosed, windowClosed
        case userAgent, sessionStorage, activeWindow, lastActive, workspace, pruned, tabGroup, groupMetadata, tabGuid
        case userAgent2, tabData, windowTitle, allWorkspaces, tabExtra, windowExtra, platformSessionID, splitTab, splitData
        case vivaldiTabExtension, vivaldiWindowExtension, operaTabData, operaWindowData, ignored
    }

    struct TabState {
        var window: Int32 = 0
        var visualIndex: Int32 = -1
        var currentIndex: Int32 = -1
        var navigations: [Navigation] = []
        var pinned = false
        var group: ChromiumToken?
        var split: ChromiumToken?
        var extraData: [String: String] = [:]

        func closest(_ index: Int32) -> Int {
            navigations.firstIndex { $0.index >= index } ?? navigations.count
        }
    }

    struct WindowState {
        var type: Int32 = 0
        var constrained = true
        var selected: Int32 = -1
        var userTitle = ""
        var extraData: [String: String] = [:]
    }

    let flavor: ChromiumFlavor
    var tabs: [Int32: TabState] = [:]
    var windows: [Int32: WindowState] = [:]
    var groups: [ChromiumToken: ChromiumSession.Group] = [:]
    var splits: [ChromiumToken: ChromiumSession.Split] = [:]

    init(flavor: ChromiumFlavor) {
        self.flavor = flavor
    }

    static let stock: [UInt8: Kind] = [
        0: .setTabWindow, 2: .tabIndex, 5: .prunedFromBack, 6: .navigation, 7: .selectedNavigation, 8: .selectedTab,
        9: .windowType, 10: .windowBounds2, 11: .prunedFromFront, 12: .pinned, 13: .extensionAppID, 14: .windowBounds3,
        15: .windowAppName, 16: .tabClosed, 17: .windowClosed, 18: .userAgent, 19: .sessionStorage, 20: .activeWindow,
        21: .lastActive, 23: .workspace, 24: .pruned, 25: .tabGroup, 27: .groupMetadata, 28: .tabGuid, 29: .userAgent2,
        30: .tabData, 31: .windowTitle, 32: .allWorkspaces, 33: .tabExtra, 34: .windowExtra, 35: .platformSessionID,
        36: .splitTab, 37: .splitData,
    ]

    func kind(_ id: UInt8) -> Kind? {
        if flavor == .opera || flavor == .operaGX {
            switch id {
            case 255: return .operaTabData
            case 254: return .operaWindowData
            case 251, 253: return .ignored
            default: return Self.stock[id]
            }
        }
        guard flavor == .vivaldi else { return Self.stock[id] }
        switch id {
        case 21: return .vivaldiTabExtension
        case 22: return .vivaldiWindowExtension
        case 23...39: return Self.stock[id - 2]
        case 200...202: return .ignored
        default: return Self.stock[id]
        }
    }

    mutating func run(_ commands: [ChromiumSessionParser.Command]) {
        for command in commands {
            guard let mapped = kind(command.id), apply(mapped, command.payload) else { return }
        }
    }

    private static func pair(_ payload: [UInt8]) -> (Int32, Int32)? {
        guard payload.count == 8 else { return nil }
        return (ChromiumBytes.int32(payload, at: 0), ChromiumBytes.int32(payload, at: 4))
    }

    private static func assignment(_ payload: [UInt8]) -> (tab: Int32, token: ChromiumToken?)? {
        guard payload.count == 32 else { return nil }
        let token = ChromiumToken(high: ChromiumBytes.uint64(payload, at: 8), low: ChromiumBytes.uint64(payload, at: 16))
        return (ChromiumBytes.int32(payload, at: 0), payload[24] != 0 ? token : nil)
    }

    private static func idAndString(_ payload: [UInt8]) -> (Int32, String)? {
        var pickle = ChromiumPickle(payload)
        guard let id = pickle.int32(), let text = pickle.string() else { return nil }
        return (id, text)
    }

    private mutating func prune(tab id: Int32, index: Int32, count: Int32) {
        var tab = tabs[id] ?? TabState()
        if tab.currentIndex >= index && tab.currentIndex < index &+ count {
            tab.currentIndex = index &- 1
        } else if tab.currentIndex >= index &+ count {
            tab.currentIndex = tab.currentIndex &- count
        }
        let start = tab.closest(index), end = max(start, tab.closest(index &+ count))
        tab.navigations.removeSubrange(start..<end)
        for position in tab.navigations.indices where tab.navigations[position].index >= index {
            tab.navigations[position].index = tab.navigations[position].index &- count
        }
        tabs[id] = tab
    }

    private mutating func apply(_ kind: Kind, _ payload: [UInt8]) -> Bool {
        switch kind {
        case .setTabWindow:
            guard case let (window, tab)? = Self.pair(payload) else { return false }
            tabs[tab, default: TabState()].window = window
        case .tabIndex:
            guard case let (tab, index)? = Self.pair(payload) else { return false }
            tabs[tab, default: TabState()].visualIndex = index
        case .selectedNavigation:
            guard case let (tab, index)? = Self.pair(payload) else { return false }
            tabs[tab, default: TabState()].currentIndex = index
        case .selectedTab:
            guard case let (window, index)? = Self.pair(payload) else { return false }
            windows[window, default: WindowState()].selected = index
        case .windowType:
            guard case let (window, type)? = Self.pair(payload) else { return false }
            windows[window, default: WindowState()].constrained = false
            windows[window, default: WindowState()].type = type
        case .prunedFromBack:
            guard case let (id, index)? = Self.pair(payload) else { return false }
            var tab = tabs[id] ?? TabState()
            tab.navigations.removeSubrange(tab.closest(index)...)
            tabs[id] = tab
        case .prunedFromFront:
            guard case let (id, count)? = Self.pair(payload), count > 0 else { return false }
            prune(tab: id, index: 0, count: count)
        case .pruned:
            guard payload.count == 12 else { return false }
            let id = ChromiumBytes.int32(payload, at: 0), index = ChromiumBytes.int32(payload, at: 4)
            let count = ChromiumBytes.int32(payload, at: 8)
            guard index >= 0, count > 0 else { return false }
            prune(tab: id, index: index, count: count)
        case .navigation:
            var pickle = ChromiumPickle(payload)
            guard let id = pickle.int32(), let navigation = Navigation.read(&pickle) else { return false }
            var tab = tabs[id] ?? TabState()
            let position = tab.closest(navigation.index)
            if position < tab.navigations.count, tab.navigations[position].index == navigation.index {
                tab.navigations[position] = navigation
            } else {
                tab.navigations.insert(navigation, at: position)
            }
            tabs[id] = tab
        case .pinned:
            guard payload.count == 8 else { return false }
            tabs[ChromiumBytes.int32(payload, at: 0), default: TabState()].pinned = payload[4] != 0
        case .tabClosed, .windowClosed:
            guard payload.count == 16 else { return false }
            let id = ChromiumBytes.int32(payload, at: 0)
            if kind == .tabClosed { tabs[id] = nil } else { windows[id] = nil }
        case .windowBounds2, .windowBounds3:
            guard payload.count == 24 else { return false }
        case .activeWindow:
            guard payload.count == 4 else { return false }
        case .lastActive:
            guard payload.count == 16 else { return false }
        case .allWorkspaces:
            guard payload.count == 8 else { return false }
        case .tabGroup, .splitTab:
            guard case let (tab, token)? = Self.assignment(payload) else { return false }
            if kind == .tabGroup { tabs[tab, default: TabState()].group = token } else { tabs[tab, default: TabState()].split = token }
        case .groupMetadata:
            var pickle = ChromiumPickle(payload)
            guard let token = pickle.token() else { return false }
            var group = groups[token] ?? ChromiumSession.Group(title: "", color: 0, collapsed: false)
            groups[token] = group
            guard let title = pickle.string16(), let color = pickle.uint32() else { return false }
            group.title = title
            group.color = Int(color)
            group.collapsed = pickle.bool() ?? false
            if pickle.bool() == true {
                guard let guid = pickle.string() else { return false }
                group.savedGUID = guid
            } else {
                group.savedGUID = nil
            }
            groups[token] = group
        case .splitData:
            var pickle = ChromiumPickle(payload)
            guard let token = pickle.token() else { return false }
            if splits[token] == nil { splits[token] = ChromiumSession.Split(ratio: 0.5, sideBySide: true) }
            guard let ratio = pickle.double(), let layout = pickle.string() else { return false }
            splits[token] = ChromiumSession.Split(ratio: ratio, sideBySide: layout != "Horizontal")
        case .windowTitle:
            guard case let (window, title)? = Self.idAndString(payload) else { return false }
            windows[window, default: WindowState()].userTitle = title
        case .windowAppName, .workspace, .extensionAppID, .userAgent, .sessionStorage:
            guard Self.idAndString(payload) != nil else { return false }
        case .tabGuid:
            guard case let (_, guid)? = Self.idAndString(payload), UUID(uuidString: guid) != nil else { return false }
        case .userAgent2:
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, pickle.string() != nil, let more = pickle.bool() else { return false }
            if more, pickle.string() == nil { return false }
        case .tabData:
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, let count = pickle.int32() else { return false }
            for _ in 0..<max(count, 0) {
                guard pickle.string() != nil, pickle.string() != nil else { return false }
            }
        case .tabExtra, .windowExtra:
            var pickle = ChromiumPickle(payload)
            guard let id = pickle.int32(), let key = pickle.string(), let value = pickle.string() else { return false }
            if kind == .tabExtra {
                tabs[id, default: TabState()].extraData[key] = value
            } else {
                windows[id, default: WindowState()].extraData[key] = value
            }
        case .platformSessionID:
            var pickle = ChromiumPickle(payload)
            guard pickle.string() != nil else { return false }
        case .vivaldiTabExtension:
            guard case let (tab, json)? = Self.idAndString(payload) else { return false }
            tabs[tab, default: TabState()].extraData[ChromiumSessionParser.vivaldiExtensionKey] = json
        case .vivaldiWindowExtension:
            guard case let (window, json)? = Self.idAndString(payload) else { return false }
            windows[window, default: WindowState()].extraData[ChromiumSessionParser.vivaldiExtensionKey] = json
        case .operaTabData, .operaWindowData:
            var pickle = ChromiumPickle(payload)
            guard let id = pickle.int32(), let key = pickle.string(), let value = pickle.string() else { return false }
            guard key == ChromiumSessionParser.operaWorkspaceKey else { break }
            if kind == .operaTabData {
                tabs[id, default: TabState()].extraData[key] = value
            } else {
                windows[id, default: WindowState()].extraData[key] = value
            }
        case .ignored:
            break
        }
        return true
    }

    func session() -> ChromiumSession {
        var members: [Int32: [(id: Int32, state: TabState)]] = [:]
        for (id, tab) in tabs where tab.window != 0 && !tab.navigations.isEmpty {
            members[tab.window, default: []].append((id, tab))
        }
        var result = ChromiumSession()
        for (id, window) in windows.sorted(by: { $0.key < $1.key }) {
            guard !window.constrained, window.type == 0, let found = members[id], !found.isEmpty else { continue }
            let ordered = found.sorted { ($0.state.visualIndex, $0.id) < ($1.state.visualIndex, $1.id) }
            let list = ordered.map { entry -> ChromiumSession.Tab in
                let state = entry.state
                let position = state.closest(state.currentIndex)
                let current = state.navigations[position < state.navigations.count ? position : state.navigations.count - 1]
                return ChromiumSession.Tab(id: entry.id, url: current.url, title: current.title, pinned: state.pinned,
                                           group: state.group, split: state.split, extraData: state.extraData)
            }
            let selected = ordered.firstIndex { $0.state.visualIndex == window.selected } ?? 0
            result.windows.append(ChromiumSession.Window(id: id, userTitle: window.userTitle.isEmpty ? nil : window.userTitle,
                                                         selectedIndex: selected, tabs: list, extraData: window.extraData))
            for tab in list {
                if let token = tab.group, result.groups[token] == nil {
                    result.groups[token] = groups[token] ?? ChromiumSession.Group(title: "", color: 0, collapsed: false)
                }
                if let token = tab.split, result.splits[token] == nil {
                    result.splits[token] = splits[token] ?? ChromiumSession.Split(ratio: 0.5, sideBySide: true)
                }
            }
        }
        return result
    }
}

private struct ClosedTabReplay {
    struct TabState {
        var currentIndex: Int32 = 0
        var navigations: [Navigation] = []

        var current: Navigation? {
            guard currentIndex >= 0, Int(currentIndex) < navigations.count else { return nil }
            return navigations[Int(currentIndex)]
        }
    }

    enum Kind { case tab, window, group, split }

    struct Entry {
        let kind: Kind
        let id: Int32
        let timestamp: Int64
        var normal = true
        var selected: Int32 = 0
        var tabs: [TabState] = []
    }

    var entries: [Entry] = []
    var currentTab: (entry: Int, tab: Int)?
    var pending: (entry: Int, remaining: Int)?

    private mutating func remove(_ id: Int32) {
        entries.removeAll { $0.id == id }
        currentTab = nil
    }

    private mutating func begin(_ entry: Entry, tabs count: Int) {
        remove(entry.id)
        entries.append(entry)
        pending = (entries.count - 1, count)
    }

    mutating func run(_ commands: [ChromiumSessionParser.Command]) {
        for command in commands {
            guard apply(command.id, command.payload) else { return }
        }
    }

    private mutating func apply(_ id: UInt8, _ payload: [UInt8]) -> Bool {
        switch id {
        case 2:
            if let waiting = pending, entries[waiting.entry].kind != .split { return false }
            pending = nil
            guard payload.count == 4 else { return false }
            remove(ChromiumBytes.int32(payload, at: 0))
        case 3:
            guard pending == nil, payload.count == 24 || payload.count == 12 else { return false }
            let count = ChromiumBytes.int32(payload, at: 8)
            guard count > 0 else { return false }
            let stamp = payload.count == 24 ? ChromiumBytes.int64(payload, at: 16) : 0
            begin(Entry(kind: .window, id: ChromiumBytes.int32(payload, at: 0), timestamp: stamp,
                       selected: ChromiumBytes.int32(payload, at: 4)), tabs: Int(count))
        case 9:
            guard pending == nil else { return false }
            var pickle = ChromiumPickle(payload)
            guard let window = pickle.int32(), let selected = pickle.int32(), let count = pickle.int32(),
                  let stamp = pickle.int64(), pickle.int32() != nil, pickle.int32() != nil,
                  let width = pickle.int32(), let height = pickle.int32(), let show = pickle.int32(),
                  pickle.string() != nil else { return false }
            let type = pickle.int32() ?? 0
            guard width >= 0, height >= 0, (0...5).contains(show), (0...4).contains(type), count > 0 else { return false }
            begin(Entry(kind: .window, id: window, timestamp: stamp, normal: type == 0, selected: selected), tabs: Int(count))
        case 13:
            guard pending == nil else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.token() != nil, let group = pickle.int32(), let count = pickle.int32(), pickle.int32() != nil,
                  pickle.string16() != nil, pickle.uint32() != nil else { return false }
            if pickle.bool() == true {
                guard let saved = pickle.string(), !saved.isEmpty else { return false }
            }
            guard let stamp = pickle.int64(), count > 0 else { return false }
            begin(Entry(kind: .group, id: group, timestamp: stamp), tabs: Int(count))
        case 15:
            guard pending == nil else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.token() != nil, let split = pickle.int32(), let stamp = pickle.int64() else { return false }
            begin(Entry(kind: .split, id: split, timestamp: stamp), tabs: 2)
        case 4:
            guard payload.count == 16 || payload.count == 8 else { return false }
            let tabID = ChromiumBytes.int32(payload, at: 0)
            let state = TabState(currentIndex: ChromiumBytes.int32(payload, at: 4))
            if let waiting = pending {
                entries[waiting.entry].tabs.append(state)
                currentTab = (waiting.entry, entries[waiting.entry].tabs.count - 1)
                pending = nil
                if waiting.remaining > 1 { pending = (waiting.entry, waiting.remaining - 1) }
            } else {
                remove(tabID)
                let stamp = payload.count == 16 ? ChromiumBytes.int64(payload, at: 8) : 0
                entries.append(Entry(kind: .tab, id: tabID, timestamp: stamp, tabs: [state]))
                currentTab = (entries.count - 1, 0)
            }
        case 1:
            guard let current = currentTab else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, var navigation = Navigation.read(&pickle) else { return false }
            navigation.index = Int32(entries[current.entry].tabs[current.tab].navigations.count)
            entries[current.entry].tabs[current.tab].navigations.append(navigation)
        case 5, 10, 16:
            guard currentTab != nil else { return false }
        case 6, 8, 14:
            guard currentTab != nil else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, pickle.string() != nil else { return false }
            if id == 14, pickle.string() == nil { return false }
        case 11:
            guard currentTab != nil else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, pickle.string() != nil, let more = pickle.bool() else { return false }
            if more, pickle.string() == nil { return false }
        case 7, 12:
            guard let waiting = pending, entries[waiting.entry].kind == .window else { return false }
            var pickle = ChromiumPickle(payload)
            guard pickle.int32() != nil, pickle.string() != nil else { return false }
        default:
            return false
        }
        return true
    }

    func closedTabs() -> [ChromiumSession.ClosedTab] {
        var result: [ChromiumSession.ClosedTab] = []
        for entry in entries.reversed() {
            let valid: Bool
            switch entry.kind {
            case .tab: valid = entry.tabs.count == 1 && entry.tabs[0].current != nil
            case .window: valid = entry.selected >= 0 && Int(entry.selected) < entry.tabs.count && entry.tabs.allSatisfy { $0.current != nil }
            case .group: valid = entry.tabs.allSatisfy { $0.current != nil }
            case .split: valid = entry.tabs.count == 2 && entry.tabs.allSatisfy { $0.current != nil }
            }
            guard valid, entry.normal else { continue }
            let closedAt = ChromiumSessionParser.date(windowsMicroseconds: entry.timestamp)
            result += entry.tabs.compactMap(\.current).map {
                ChromiumSession.ClosedTab(url: $0.url, title: $0.title, closedAt: closedAt)
            }
        }
        return result
    }
}

extension ChromiumSessionParser {
    package static let vivaldiExtensionKey = "vivaldi.ext"
    package static let operaWorkspaceKey = "workspaces_state"
}
