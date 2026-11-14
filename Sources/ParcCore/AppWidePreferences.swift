import Foundation

struct AppWidePreferences: Codable, Equatable {
    var searchKeyword: String?
    var searchSuggestions: Bool?
    var downloadDirectory: String?
    var promptForDownload: Bool?
}

struct AppWideSearchEngine: Equatable {
    let identifier: String
    let keyword: String
    let canMakeDefault: Bool
}

struct AppWideProfileState: Equatable {
    var engines: [AppWideSearchEngine]
    var defaultKeyword: String?
    var defaultEditable: Bool
    var suggestionsEnabled: Bool
    var suggestionsEditable: Bool
    var downloadDirectory: String
    var directoryEditable: Bool
    var promptForDownload: Bool
    var promptEditable: Bool
}

struct AppWideChanges: Equatable {
    var engineIdentifier: String?
    var suggestions: Bool?
    var downloadDirectory: String?
    var promptForDownload: Bool?
    var isEmpty: Bool { self == AppWideChanges() }
}

extension AppWidePreferences {
    static func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func engineIdentifier(forKeyword keyword: String, among engines: [AppWideSearchEngine]) -> String? {
        let wanted = normalizedKeyword(keyword)
        guard !wanted.isEmpty else { return nil }
        return engines.first { $0.canMakeDefault && normalizedKeyword($0.keyword) == wanted }?.identifier
    }

    static func recorded(from state: AppWideProfileState) -> AppWidePreferences {
        AppWidePreferences(
            searchKeyword: state.defaultEditable ? state.defaultKeyword.flatMap { $0.isEmpty ? nil : $0 } : nil,
            searchSuggestions: state.suggestionsEditable ? state.suggestionsEnabled : nil,
            downloadDirectory: state.directoryEditable ? state.downloadDirectory : nil,
            promptForDownload: state.promptEditable ? state.promptForDownload : nil)
    }

    func adoptingSearch(from state: AppWideProfileState) -> AppWidePreferences {
        var next = self
        if state.defaultEditable, let keyword = state.defaultKeyword, !keyword.isEmpty,
           Self.normalizedKeyword(keyword) != Self.normalizedKeyword(searchKeyword ?? "") {
            next.searchKeyword = keyword
        }
        if state.suggestionsEditable { next.searchSuggestions = state.suggestionsEnabled }
        return next
    }

    func changes(for state: AppWideProfileState) -> AppWideChanges {
        var changes = AppWideChanges()
        if let keyword = searchKeyword, state.defaultEditable,
           Self.normalizedKeyword(state.defaultKeyword ?? "") != Self.normalizedKeyword(keyword),
           let identifier = Self.engineIdentifier(forKeyword: keyword, among: state.engines) {
            changes.engineIdentifier = identifier
        }
        if let wanted = searchSuggestions, state.suggestionsEditable, state.suggestionsEnabled != wanted {
            changes.suggestions = wanted
        }
        if let wanted = downloadDirectory, state.directoryEditable,
           URL(fileURLWithPath: wanted).standardizedFileURL.path != URL(fileURLWithPath: state.downloadDirectory).standardizedFileURL.path {
            changes.downloadDirectory = wanted
        }
        if let wanted = promptForDownload, state.promptEditable, state.promptForDownload != wanted {
            changes.promptForDownload = wanted
        }
        return changes
    }
}
