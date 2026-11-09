import Foundation

///
/// welcome reducer supplies the three introduction phases; setup is local.
struct OnboardingDraft: Codable, Equatable {
    enum Stage: Int, Codable, CaseIterable {
        case introAnimation, sellIntro, sellCompleted, introduction, theme, favorites, bookmarks, ready
        // Keep every persisted version-one tag stable. The old introduction
        // card is a migration alias; screen order is not enum declaration order.
        case defaultBrowser
        // allSteps tag 7. Appended so existing drafts keep their integer tags.
        case adBlockers
        var isWelcome: Bool { rawValue <= Self.sellCompleted.rawValue }

        /// Account-free allSteps without arcMax and without the excluded
        /// skip-and-auto-select-onboarding-favorites remote flag. Import
        /// substeps remain nested in `.bookmarks`.
        static var setupOrder: [Self] { setupOrder(includingAdBlockers: false) }
        static func setupOrder(includingAdBlockers: Bool, retaining current: Self? = nil) -> [Self] {
            var order: [Self] = [.bookmarks, .favorites, .theme]
            if includingAdBlockers || current == .adBlockers { order.append(.adBlockers) }
            order.append(contentsOf: [.defaultBrowser, .ready])
            return order
        }
        var current: Self { self == .introduction ? .bookmarks : self }
        var next: Self? { next(includingAdBlockers: false) }
        func next(includingAdBlockers: Bool) -> Self? {
            switch self {
            case .introAnimation: return .sellIntro
            case .sellIntro: return .sellCompleted
            case .sellCompleted, .introduction: return .bookmarks
            default:
                let order = Self.setupOrder(includingAdBlockers: includingAdBlockers, retaining: self)
                guard let index = order.firstIndex(of: self), index + 1 < order.count else { return nil }
                return order[index + 1]
            }
        }
        var previous: Self? { previous(includingAdBlockers: false) }
        func previous(includingAdBlockers: Bool) -> Self? {
            let order = Self.setupOrder(includingAdBlockers: includingAdBlockers, retaining: current)
            guard let index = order.firstIndex(of: current), index > 0 else { return nil }
            return order[index - 1]
        }
    }
    struct Bookmark: Codable, Equatable {
        var title: String
        var url: String
    }
    var version = 1
    var spaceID: UUID
    var stage: Stage = .introAnimation
    var spaceName: String
    var theme: SpaceTheme
    // Setup's static initial OrderedSet is [YouTube, Google Calendar].
    var favoriteURLs: Set<String> = ["https://youtube.com", "https://calendar.google.com"]
    // Setup.State.selectedTopApps is an OrderedSet. Keep the earlier draft's
    // set readable while recording the user's selection order from now on.
    var favoriteOrder: [String]? = ["https://youtube.com", "https://calendar.google.com"]
    var bookmarks: [Bookmark] = []
    var bookmarkFileName: String?
    //
    // this is only a pending choice, never proof of the macOS default handler.
    var defaultBrowserChoice: Bool?
    // Explicitly accepted on the Safari password-choice step. A pending choice
    // survives setup resume but never means the extension has been installed.
    var iCloudPasswordsProfileID: UUID?
    // Known ad-blocker extensions actually submitted with the first-launch
    // import. Empty means allSteps omits tag 7.
    var importedAdBlockers: [ImportedAdBlocker] = []
    // Pending AdBlockersSelection. Next accepts it; Skip leaves it unchanged.
    var adBlockerChoice: AdBlockerChoice?
    // Replay only: the Space name and saved theme it started from, so Finish
    // applies only what replay changed, and its unsaved light/dark preview.
    var replayBaseName: String?
    var replayBaseTheme: SpaceTheme?
    var replayAppearance: String?
    var wantsDefaultBrowser: Bool { defaultBrowserChoice ?? true }
    //
    // {uBlock Origin}, so an empty import shows the YES/NO choice.
    var showsAdBlockers: Bool {
        Set(importedAdBlockers.map(\.identifier)) != [OnboardingAdBlocker.uBlockOrigin] || stage.current == .adBlockers
    }
    func nextStage() -> Stage? { stage.next(includingAdBlockers: showsAdBlockers) }
    func previousStage() -> Stage? { stage.previous(includingAdBlockers: showsAdBlockers) }
    func visibleSetupOrder() -> [Stage] {
        Stage.setupOrder(includingAdBlockers: showsAdBlockers, retaining: stage.current)
    }
    /// Numbered setup steps exclude Ready, which still displays as "Ready".
    func displayedSetupCount() -> Int {
        visibleSetupOrder().filter { $0 != .ready }.count
    }

    struct ImportedAdBlocker: Codable, Equatable, Identifiable {
        var identifier: String
        var displayName: String
        // Destination Profiles it was imported into; nil in older drafts.
        var profileIDs: [UUID]? = nil
        var id: String { identifier }
    }

    /// AdBlockersSelection.Selection without arcNative and keepAll.
    enum AdBlockerChoice: Codable, Equatable {
        /// noAdBlock: "Don't block ads", or NO when nothing was imported.
        case none
        /// userSelected: keeps this imported blocker and removes the rest.
        case keep(String)
        /// uBlock: YES when nothing was imported.
        case uBlock
        /// keepAll: "Use all imported ad blockers" leaves every one installed.
        case keepAll
        var keptIdentifier: String? {
            if case .keep(let identifier) = self { return identifier }
            return nil
        }
        func isSelected(_ identifier: String) -> Bool {
            if case .keep(let kept) = self { return kept == identifier }
            return false
        }
        ///
        /// current choice still names one of its rows.
        static func settled(_ choice: Self?, for blockers: [ImportedAdBlocker]) -> Self {
            guard let first = blockers.first else { return choice == AdBlockerChoice.none ? .none : .uBlock }
            switch choice {
            case .some(.none): return .none
            case .some(.keep(let kept)) where blockers.contains(where: { $0.identifier == kept }): return .keep(kept)
            default: return .keep(first.identifier)
            }
        }
        ///
        /// blocker the choice doesn't keep is removed; YES installs uBlock in
        /// the setup Space's Profile.
        func plan(for blockers: [ImportedAdBlocker], setupProfileID: UUID) -> AdBlockerPlan {
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

    struct AdBlockerPlan: Equatable {
        var removals: [UUID: Set<String>]
        var installProfileID: UUID?
    }

    struct FavoriteChoice: Identifiable {
        let id: String
        let title: String
        let url: String
        var artwork: String { "favorite-" + id }
        var bookmark: Bookmark { .init(title: title, url: url) }
    }
    // The onboarding grid is a fixed nine-item subset of BaseModels.TopApp,
    //
    static let favoriteChoices: [FavoriteChoice] = [
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
    static func favoriteKey(_ url: String) -> String {
        // Migrate only the two aliases present in older Parc setup drafts.
        switch url {
        case "https://www.youtube.com": return "https://youtube.com"
        case "https://www.notion.so": return "https://notion.so"
        default: return url
        }
    }
    /// The grid choice a saved Favorite URL matches under the saved-tab comparison
    /// the session commit dedupes with, or its alias-migrated URL.
    static func choiceURL(forSaved url: String) -> String {
        let key = SavedTabURLComparison.key(favoriteKey(url))
        return favoriteChoices.first { SavedTabURLComparison.key($0.url) == key }?.url ?? favoriteKey(url)
    }
    func isFavoriteSelected(_ choice: FavoriteChoice) -> Bool {
        favoriteURLs.contains { Self.favoriteKey($0) == choice.url }
    }
    var selectedFavorites: [Bookmark] {
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
    mutating func toggleFavorite(_ choice: FavoriteChoice) {
        guard Self.favoriteChoices.contains(where: { $0.id == choice.id && $0.url == choice.url }) else { return }
        var order = selectedFavorites.map(\.url)
        if isFavoriteSelected(choice) {
            favoriteURLs = favoriteURLs.filter { Self.favoriteKey($0) != choice.url }
            order.removeAll { $0 == choice.url }
        } else {
            favoriteURLs.insert(choice.url)
            // Setup.topAppTapped inserts an absent item at index zero.
            order.insert(choice.url, at: 0)
        }
        favoriteOrder = order
    }
    enum CodingKeys: String, CodingKey {
        case version, spaceID, stage, spaceName, theme, favoriteURLs, favoriteOrder
        case bookmarks, bookmarkFileName, defaultBrowserChoice, iCloudPasswordsProfileID
        case importedAdBlockers, adBlockerChoice
        case replayBaseName, replayBaseTheme, replayAppearance
    }

    init(spaceID: UUID, spaceName: String, theme: SpaceTheme,
         favoriteURLs: Set<String> = ["https://youtube.com", "https://calendar.google.com"]) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.theme = theme
        self.favoriteURLs = favoriteURLs
    }

    init(from decoder: Decoder) throws {
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
        replayBaseName = try container.decodeIfPresent(String.self, forKey: .replayBaseName)
        replayBaseTheme = try container.decodeIfPresent(SpaceTheme.self, forKey: .replayBaseTheme)
        replayAppearance = try container.decodeIfPresent(String.self, forKey: .replayAppearance)
    }

    func encode(to encoder: Encoder) throws {
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
        try container.encodeIfPresent(replayBaseName, forKey: .replayBaseName)
        try container.encodeIfPresent(replayBaseTheme, forKey: .replayBaseTheme)
        try container.encodeIfPresent(replayAppearance, forKey: .replayAppearance)
    }

    static let introDuration: TimeInterval = 3.3
    static let sellDuration: TimeInterval = 6.5

    /// A replay's Safari restart saves its draft here so relaunch reopens replay at the import.
    static let replayRestartFileName = "onboarding-replay.json"

    static func load(directory: URL, space: BrowserSpace, fileName: String = "onboarding.json") throws -> Self {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(spaceID: space.id, spaceName: space.name, theme: space.theme)
        }
        var draft = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard draft.version == 1, draft.spaceID == space.id, draft.theme.isValid,
              draft.bookmarks.count <= 50_000,
              draft.importedAdBlockers.count <= 64 else { throw CocoaError(.fileReadCorruptFile) }
        draft.importedAdBlockers = draft.importedAdBlockers.filter {
            OnboardingAdBlocker.isKnown($0.identifier) && !$0.identifier.isEmpty && !$0.displayName.isEmpty
        }
        if let choice = draft.adBlockerChoice {
            // Past the step a made choice stands, as it does without a restart:
            // a kept blocker that later failed still removes the others.
            let order = Stage.setupOrder(includingAdBlockers: true)
            let passed = (order.firstIndex(of: draft.stage.current) ?? 0) > (order.firstIndex(of: .adBlockers) ?? 0)
            let valid = passed
                ? choice.keptIdentifier.map(OnboardingAdBlocker.isKnown) ?? (choice != .uBlock || draft.importedAdBlockers.isEmpty)
                : choice == .keepAll || AdBlockerChoice.settled(choice, for: draft.importedAdBlockers) == choice
            if !valid { draft.adBlockerChoice = nil }
        }
        draft.stage = draft.stage.current
        return draft
    }
    func save(directory: URL, fileName: String = "onboarding.json") throws {
        let url = directory.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func remove(directory: URL, fileName: String = "onboarding.json") throws {
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    /// Consumes a saved replay draft for its own Space, resuming at the import.
    static func takeReplayRestart(directory: URL, space: BrowserSpace) -> Self? {
        defer { try? remove(directory: directory, fileName: replayRestartFileName) }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(replayRestartFileName).path),
              var draft = try? load(directory: directory, space: space, fileName: replayRestartFileName) else { return nil }
        draft.stage = .bookmarks
        return draft
    }
}

///
///
/// not implement.
enum OnboardingAdBlocker {
    static let chromeExtensionIDs: Set<String> = [
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
    static let uBlockOrigin = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
    static func isKnown(_ identifier: String) -> Bool { chromeExtensionIDs.contains(identifier) }
}
