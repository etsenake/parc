import Foundation

package struct OnboardingDraft: Codable, Equatable {
    package enum Stage: Int, Codable, CaseIterable {
        case introAnimation, sellIntro, sellCompleted, introduction, theme, favorites, bookmarks, ready
        case defaultBrowser
        case adBlockers
        case windowFrame
        case continuedImport
        package var isWelcome: Bool { rawValue <= Self.sellCompleted.rawValue }
        package var holdsImport: Bool { self == .bookmarks || self == .favorites || self == .continuedImport }
        package var showsImport: Bool { self == .bookmarks || self == .continuedImport }

        package static var setupOrder: [Self] { setupOrder(includingAdBlockers: false) }
        package static func setupOrder(includingAdBlockers: Bool, continuingImport: Bool = false,
                               retaining current: Self? = nil) -> [Self] {
            var order: [Self] = [.bookmarks, .favorites]
            if continuingImport || current == .continuedImport { order.append(.continuedImport) }
            order.append(contentsOf: [.theme, .windowFrame])
            if includingAdBlockers || current == .adBlockers { order.append(.adBlockers) }
            order.append(contentsOf: [.defaultBrowser, .ready])
            return order
        }
        package var current: Self { self == .introduction ? .bookmarks : self }
        package var next: Self? { next(includingAdBlockers: false) }
        package func next(includingAdBlockers: Bool, continuingImport: Bool = false) -> Self? {
            switch self {
            case .introAnimation: return .sellIntro
            case .sellIntro: return .sellCompleted
            case .sellCompleted, .introduction: return .bookmarks
            default:
                let order = Self.setupOrder(includingAdBlockers: includingAdBlockers,
                    continuingImport: continuingImport, retaining: self)
                guard let index = order.firstIndex(of: self), index + 1 < order.count else { return nil }
                return order[index + 1]
            }
        }
        package var previous: Self? { previous(includingAdBlockers: false) }
        package func previous(includingAdBlockers: Bool) -> Self? {
            let order = Self.setupOrder(includingAdBlockers: includingAdBlockers, retaining: current)
            guard let index = order.firstIndex(of: current), index > 0 else { return nil }
            return order[index - 1]
        }
    }
    package struct Bookmark: Codable, Equatable {
        package var title: String
        package var url: String

        package init(title: String, url: String) {
            self.title = title
            self.url = url
        }
    }
    package enum ImportPage: String, Codable {
        case progress, bookmarks, passwordChoice, passwordFile
    }
    package var version = 1
    package var spaceID: UUID
    package var stage: Stage = .introAnimation
    package var spaceName: String
    package var theme: SpaceTheme
    package var favoriteURLs: Set<String> = ["https://youtube.com", "https://calendar.google.com"]
    package var favoriteOrder: [String]? = ["https://youtube.com", "https://calendar.google.com"]
    package var bookmarks: [Bookmark] = []
    package var bookmarkFileName: String?
    package var defaultBrowserChoice: Bool?
    package var iCloudPasswordsProfileID: UUID?
    package var importedAdBlockers: [ImportedAdBlocker] = []
    package var adBlockerChoice: AdBlockerChoice?
    package var windowFrameThickness: Int?
    package var replayBaseName: String?
    package var replayBaseTheme: SpaceTheme?
    package var replayAppearance: String?
    package var importPages: [ImportPage] = []
    package var wantsDefaultBrowser: Bool { defaultBrowserChoice ?? true }
    package var showsAdBlockers: Bool {
        Set(importedAdBlockers.map(\.identifier)) != [OnboardingAdBlocker.uBlockOrigin] || stage.current == .adBlockers
    }
    package func nextStage(continuingImport: Bool = false) -> Stage? {
        stage.next(includingAdBlockers: showsAdBlockers, continuingImport: continuingImport)
    }
    package func previousStage() -> Stage? { stage.previous(includingAdBlockers: showsAdBlockers) }
    package func visibleSetupOrder() -> [Stage] {
        Stage.setupOrder(includingAdBlockers: showsAdBlockers, retaining: stage.current)
    }
    package func displayedSetupCount(importSteps: Int? = nil) -> Int {
        visibleSetupOrder().filter { $0 != .ready && $0 != .continuedImport }.count + (importSteps ?? importPages.count)
    }
    package func displayedStepNumber(importSteps: Int? = nil) -> Int {
        let counted = visibleSetupOrder().filter { $0 != .continuedImport }
        let favorites = counted.firstIndex(of: .favorites) ?? 1
        if stage == .continuedImport { return favorites + 1 + importPages.count }
        let index = counted.firstIndex(of: stage.current) ?? 0
        return index + 1 + (index > favorites ? importSteps ?? importPages.count : 0)
    }
    package func importSteps(current: ImportPage?, ahead: [ImportPage]) -> Int {
        let waiting = current.map { $0 != .progress && $0 != importPages.last } ?? false
        return importPages.count + (waiting ? 1 : 0) + ahead.count
    }
    package mutating func recordImportPage(_ page: ImportPage) {
        if page != .progress, let index = importPages.lastIndex(of: page) {
            importPages.removeSubrange(importPages.index(after: index)...)
        } else if importPages.last != page {
            importPages.append(page)
        }
    }
    package func savedForResume(importInProgress: Bool) -> Self {
        var saved = self
        if stage == .continuedImport || (importInProgress && stage == .favorites) { saved.stage = .bookmarks }
        if saved.stage == .bookmarks { saved.importPages = [] }
        return saved
    }
    package func windowFrameValue(saved: Int) -> Int {
        WindowFrameThickness.clamped(windowFrameThickness ?? saved)
    }
    package mutating func chooseWindowFrame(_ value: Int) {
        windowFrameThickness = WindowFrameThickness.clamped(value)
    }
    package mutating func skipWindowFrame() { windowFrameThickness = nil }

    package struct ImportedAdBlocker: Codable, Equatable, Identifiable {
        package var identifier: String
        package var displayName: String
        package var profileIDs: [UUID]? = nil
        package var id: String { identifier }

        package init(identifier: String, displayName: String, profileIDs: [UUID]? = nil) {
            self.identifier = identifier
            self.displayName = displayName
            self.profileIDs = profileIDs
        }
    }

    package enum AdBlockerChoice: Codable, Equatable {
        case none
        case keep(String)
        case uBlock
        case keepAll
        package var keptIdentifier: String? {
            if case .keep(let identifier) = self { return identifier }
            return nil
        }
        package func isSelected(_ identifier: String) -> Bool {
            if case .keep(let kept) = self { return kept == identifier }
            return false
        }
        package static func settled(_ choice: Self?, for blockers: [ImportedAdBlocker]) -> Self {
            guard let first = blockers.first else { return choice == AdBlockerChoice.none ? .none : .uBlock }
            switch choice {
            case .some(.none): return .none
            case .some(.keep(let kept)) where blockers.contains(where: { $0.identifier == kept }): return .keep(kept)
            default: return .keep(first.identifier)
            }
        }
        package func plan(for blockers: [ImportedAdBlocker], setupProfileID: UUID) -> AdBlockerPlan {
            var removals: [UUID: Set<String>] = [:]
            if self != .uBlock && self != .keepAll {
                for blocker in blockers where blocker.identifier != keptIdentifier {
                    for profileID in blocker.profileIDs ?? [setupProfileID] {
                        removals[profileID, default: []].insert(blocker.identifier)
                    }
                }
            }
            return AdBlockerPlan(removals: removals,
                installProfileID: self == .uBlock && blockers.isEmpty ? setupProfileID : nil)
        }
    }

    package struct AdBlockerPlan: Equatable {
        package var removals: [UUID: Set<String>]
        package var installProfileID: UUID?
    }

    package struct FavoriteChoice: Identifiable {
        package let id: String
        package let title: String
        package let url: String
        package var artwork: String { "favorite-" + id }
        package var bookmark: Bookmark { .init(title: title, url: url) }

        package init(id: String, title: String, url: String) {
            self.id = id
            self.title = title
            self.url = url
        }
    }
    package static let favoriteChoices: [FavoriteChoice] = [
        .init(id: "twitter", title: "Twitter", url: "https://twitter.com"),
        .init(id: "gmail", title: "Gmail", url: "https://mail.google.com"),
        .init(id: "gcal", title: "Google Calendar", url: "https://calendar.google.com"),
        .init(id: "spotify", title: "Spotify", url: "https://spotify.com"),
        .init(id: "youtube", title: "YouTube", url: "https://youtube.com"),
        .init(id: "notion", title: "Notion", url: "https://notion.so"),
        .init(id: "slack", title: "Slack", url: "https://slack.com"),
        .init(id: "figma", title: "Figma", url: "https://figma.com"),
        .init(id: "outlook", title: "Outlook", url: "https://outlook.live.com")
    ]
    private static let legacyFavorites: [Bookmark] = [
        .init(title: "Google", url: "https://www.google.com"),
        .init(title: "GitHub", url: "https://github.com")
    ]
    package static func favoriteKey(_ url: String) -> String {
        switch url {
        case "https://www.youtube.com": return "https://youtube.com"
        case "https://www.notion.so": return "https://notion.so"
        default: return url
        }
    }
    package static func choiceURL(forSaved url: String) -> String {
        let key = SavedTabURLComparison.key(favoriteKey(url))
        return favoriteChoices.first { SavedTabURLComparison.key($0.url) == key }?.url ?? favoriteKey(url)
    }
    package func isFavoriteSelected(_ choice: FavoriteChoice) -> Bool {
        favoriteURLs.contains { Self.favoriteKey($0) == choice.url }
    }
    package var selectedFavorites: [Bookmark] {
        let selected = Set(favoriteURLs.map(Self.favoriteKey))
        let available = Self.favoriteChoices.map(\.bookmark) + Self.legacyFavorites
        let byURL = Dictionary(uniqueKeysWithValues: available.map { ($0.url, $0) })
        var seen = Set<String>()
        return ((favoriteOrder ?? []) + available.map(\.url)).compactMap { raw in
            let key = Self.favoriteKey(raw)
            guard selected.contains(key), let item = byURL[key], seen.insert(key).inserted else { return nil }
            return item
        }
    }
    package mutating func toggleFavorite(_ choice: FavoriteChoice) {
        guard Self.favoriteChoices.contains(where: { $0.id == choice.id && $0.url == choice.url }) else { return }
        var order = selectedFavorites.map(\.url)
        if isFavoriteSelected(choice) {
            favoriteURLs = favoriteURLs.filter { Self.favoriteKey($0) != choice.url }
            order.removeAll { $0 == choice.url }
        } else {
            favoriteURLs.insert(choice.url)
            order.insert(choice.url, at: 0)
        }
        favoriteOrder = order
    }
    package enum CodingKeys: String, CodingKey {
        case version, spaceID, stage, spaceName, theme, favoriteURLs, favoriteOrder
        case bookmarks, bookmarkFileName, defaultBrowserChoice, iCloudPasswordsProfileID
        case importedAdBlockers, adBlockerChoice, windowFrameThickness
        case replayBaseName, replayBaseTheme, replayAppearance, importPages
    }

    package init(spaceID: UUID, spaceName: String, theme: SpaceTheme,
         favoriteURLs: Set<String> = ["https://youtube.com", "https://calendar.google.com"]) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.theme = theme
        self.favoriteURLs = favoriteURLs
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        spaceID = try container.decode(UUID.self, forKey: .spaceID)
        stage = try container.decode(Stage.self, forKey: .stage)
        spaceName = try container.decode(String.self, forKey: .spaceName)
        theme = try container.decode(SpaceTheme.self, forKey: .theme)
        favoriteURLs = try container.decode(Set<String>.self, forKey: .favoriteURLs)
        favoriteOrder = try container.decodeIfPresent([String].self, forKey: .favoriteOrder)
        bookmarks = try container.decode([Bookmark].self, forKey: .bookmarks)
        bookmarkFileName = try container.decodeIfPresent(String.self, forKey: .bookmarkFileName)
        defaultBrowserChoice = try container.decodeIfPresent(Bool.self, forKey: .defaultBrowserChoice)
        iCloudPasswordsProfileID = try container.decodeIfPresent(UUID.self, forKey: .iCloudPasswordsProfileID)
        importedAdBlockers = try container.decodeIfPresent([ImportedAdBlocker].self, forKey: .importedAdBlockers) ?? []
        adBlockerChoice = try container.decodeIfPresent(AdBlockerChoice.self, forKey: .adBlockerChoice)
        windowFrameThickness = try container.decodeIfPresent(Int.self, forKey: .windowFrameThickness)
        replayBaseName = try container.decodeIfPresent(String.self, forKey: .replayBaseName)
        replayBaseTheme = try container.decodeIfPresent(SpaceTheme.self, forKey: .replayBaseTheme)
        replayAppearance = try container.decodeIfPresent(String.self, forKey: .replayAppearance)
        importPages = try container.decodeIfPresent([String].self, forKey: .importPages)?
            .compactMap(ImportPage.init(rawValue:)) ?? []
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(spaceID, forKey: .spaceID)
        try container.encode(stage, forKey: .stage)
        try container.encode(spaceName, forKey: .spaceName)
        try container.encode(theme, forKey: .theme)
        try container.encode(favoriteURLs, forKey: .favoriteURLs)
        try container.encodeIfPresent(favoriteOrder, forKey: .favoriteOrder)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encodeIfPresent(bookmarkFileName, forKey: .bookmarkFileName)
        try container.encodeIfPresent(defaultBrowserChoice, forKey: .defaultBrowserChoice)
        try container.encodeIfPresent(iCloudPasswordsProfileID, forKey: .iCloudPasswordsProfileID)
        try container.encode(importedAdBlockers, forKey: .importedAdBlockers)
        try container.encodeIfPresent(adBlockerChoice, forKey: .adBlockerChoice)
        try container.encodeIfPresent(windowFrameThickness, forKey: .windowFrameThickness)
        try container.encodeIfPresent(replayBaseName, forKey: .replayBaseName)
        try container.encodeIfPresent(replayBaseTheme, forKey: .replayBaseTheme)
        try container.encodeIfPresent(replayAppearance, forKey: .replayAppearance)
        if !importPages.isEmpty { try container.encode(importPages, forKey: .importPages) }
    }

    package static let introDuration: TimeInterval = 3.3
    package static let sellDuration: TimeInterval = 6.5

    package static let replayRestartFileName = "onboarding-replay.json"

    package static func load(directory: URL, space: BrowserSpace, fileName: String = "onboarding.json") throws -> Self {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(spaceID: space.id, spaceName: space.name, theme: space.theme)
        }
        var draft = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard draft.version == 1, draft.spaceID == space.id, draft.theme.isValid,
              draft.bookmarks.count <= 50_000,
              draft.importedAdBlockers.count <= 64, draft.importPages.count <= 8 else { throw CocoaError(.fileReadCorruptFile) }
        if draft.stage == .continuedImport { draft.stage = .bookmarks }
        if draft.stage.current == .bookmarks { draft.importPages = [] }
        draft.importedAdBlockers = draft.importedAdBlockers.filter {
            OnboardingAdBlocker.isKnown($0.identifier) && !$0.identifier.isEmpty && !$0.displayName.isEmpty
        }
        if let choice = draft.adBlockerChoice {
            let order = Stage.setupOrder(includingAdBlockers: true)
            let passed = (order.firstIndex(of: draft.stage.current) ?? 0) > (order.firstIndex(of: .adBlockers) ?? 0)
            let valid = passed
                ? choice.keptIdentifier.map(OnboardingAdBlocker.isKnown) ?? (choice != .uBlock || draft.importedAdBlockers.isEmpty)
                : choice == .keepAll || AdBlockerChoice.settled(choice, for: draft.importedAdBlockers) == choice
            if !valid { draft.adBlockerChoice = nil }
        }
        if let thickness = draft.windowFrameThickness, !WindowFrameThickness.range.contains(thickness) {
            draft.windowFrameThickness = nil
        }
        draft.stage = draft.stage.current
        return draft
    }
    package func save(directory: URL, fileName: String = "onboarding.json") throws {
        let url = directory.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    package static func remove(directory: URL, fileName: String = "onboarding.json") throws {
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    package static func takeReplayRestart(directory: URL, space: BrowserSpace) -> Self? {
        defer { try? remove(directory: directory, fileName: replayRestartFileName) }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(replayRestartFileName).path),
              var draft = try? load(directory: directory, space: space, fileName: replayRestartFileName) else { return nil }
        draft.stage = .bookmarks; draft.importPages = []
        return draft
    }
}

package enum OnboardingAdBlocker {
    package static let chromeExtensionIDs: Set<String> = [
        "cfhdojbkjhnklbpkdaibdccddilifddb",
        "aemffjkmgcepimloclpkecifcnipnodh",
        "mlomiejdfkolichcflejclcbmpeaniij",
        "pkehgijcmpdhfbdbbnkijodmdjhbjlgp",
        "cjpalhdlnbpafiamejdnhcphjbkeiagm",
        "ddkjiahejlhfcafbddmgiahcphecmpfh",
        "bgnkhhnnamicmpeenaelnjfhikgbkllg",
        "gighmmpiobklfepjocnamgkkbiglidom",
        "ohahllgiabjaoigichmmfljhkcfikeof",
        "lgblnfidahcdcjddiepkckcfdhpknnjh",
        "bkkbcggnhapdmkeljlodobbkopceiche",
        "pmekfefnodgilnnjcfkkdjlebokonhpm",
        "gekdekpbfehejjiecgonmgmepbdnaggp",
        "ggdpplfehdighdpleoegjefnpefgpgfh",
        "onomjaelhagjjojbkcafidnepbfkpnee",
        "ojjjflcdgjegkdcojbahlbgeiinpbfgf",
        "jhkhlgaomejplkanglolfpcmfknnomle",
        "gekoepiplklhniacchbbgbhilidiojmb",
        "amgmhmoikcefmalfmbpkpnnpebhmhfnd"
    ]
    package static let uBlockOrigin = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    package static func isKnown(_ identifier: String) -> Bool { chromeExtensionIDs.contains(identifier) }
}
