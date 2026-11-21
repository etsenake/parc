import Foundation
import Combine

package enum LinkMatchStyle: String, Codable, CaseIterable {
    case matches, contains
}

package struct LinkRouteCondition: Codable, Equatable, Identifiable {
    package var id = UUID()
    package var style: LinkMatchStyle = .contains
    package var pattern = ""

    package init(id: UUID = UUID(), style: LinkMatchStyle = .contains, pattern: String = "") {
        self.id = id
        self.style = style
        self.pattern = pattern
    }

    package func accepts(_ url: URL) -> Bool {
        switch style {
        case .matches:
            guard let incoming = LinkRouteCondition.siteURL(Self.normalized(url).absoluteString),
                  let patternURL = Self.siteURL(pattern) else { return false }
            let expected = Self.normalized(patternURL)
            return incoming.host == expected.host && incoming.path == expected.path
        case .contains:
            let text = url.absoluteString.lowercased()
            if let candidate = Self.looseWebURL(pattern) {
                let normalized = Self.normalized(candidate)
                if normalized.scheme == "https", normalized.host?.isEmpty == false,
                   text.contains(normalized.absoluteString.lowercased()) { return true }
            }
            let needle = pattern.lowercased()
            return text.contains(needle) || Self.normalized(url).absoluteString.lowercased().contains(needle)
        }
    }

    private static func looseWebURL(_ text: String) -> URL? {
        let prefix = #"^(http(s)?:\/\/)?"#
        let suffix = #"(:[0-9]{1,5})?((\?|\/|#).*)?"#
        let hosts = [#"(localhost|127\.0\.0\.1)"#,
                     #"(([0-9]{1,3})\.){3}([0-9]{1,3})"#,
                     #"(([a-z0-9\-]+)\.)+[a-z]{2,}"#]
        guard hosts.contains(where: { text.lowercased().range(of: prefix + $0 + suffix, options: .regularExpression) != nil }) else { return nil }
        let withScheme = text.range(of: #"^http(s)?:\/\/"#, options: .regularExpression) == nil ? "http://" + text : text
        var allowed = CharacterSet(charactersIn: "#")
        for set in [CharacterSet.urlUserAllowed, .urlPasswordAllowed, .urlHostAllowed,
                    .urlPathAllowed, .urlQueryAllowed, .urlFragmentAllowed] { allowed.formUnion(set) }
        guard let decoded = withScheme.removingPercentEncoding,
              let encoded = decoded.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URLComponents(string: encoded)?.url
    }

    package static func siteURL(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text) else { return nil }
        if parts.scheme == nil { parts = URLComponents(string: "https://" + text) ?? parts }
        guard parts.host?.isEmpty == false else { return nil }
        if parts.host?.hasPrefix("www.") == true { parts.host = String(parts.host!.dropFirst(4)) }
        return parts.url
    }

    package static func normalized(_ url: URL) -> URL {
        guard var parts = URLComponents(string: url.absoluteString.lowercased()) else { return url }
        if parts.scheme == nil || parts.scheme == "http" { parts.scheme = "https" }
        if parts.host?.hasPrefix("www.") == true { parts.host = String(parts.host!.dropFirst(4)) }
        var trimPath = true
        if let fragment = parts.fragment, fragment.hasPrefix("!") {
            trimPath = false
            if fragment.hasSuffix("/") { parts.fragment = String(fragment.dropLast()) }
        } else { parts.fragment = nil }
        if trimPath && parts.path.hasSuffix("/") { parts.path = String(parts.path.dropLast()) }
        if let items = parts.queryItems {
            let kept = items.filter { !$0.name.hasPrefix("utm_") && !($0.value ?? "").isEmpty }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return parts.url ?? url
    }
}

package enum LinkRouteDestination: Codable, Equatable {
    case mostRecent
    case space(UUID)
    case profile(UUID)
}

package struct LinkRoute: Codable, Equatable, Identifiable {
    package var id = UUID()
    package var conditions = [LinkRouteCondition()]
    package var destination = LinkRouteDestination.mostRecent

    package init(id: UUID = UUID(), conditions: [LinkRouteCondition] = [LinkRouteCondition()], destination: LinkRouteDestination = LinkRouteDestination.mostRecent) {
        self.id = id
        self.conditions = conditions
        self.destination = destination
    }
}

package struct LinkRoutingState: Codable, Equatable {
    package var version = 1
    package var rules: [LinkRoute] = []
    package var defaultDestination = LinkRouteDestination.mostRecent
    package var recentSpaceIDs: [UUID] = []
}

extension LinkRoutingState {
    package func convertingProfileDestinations(spaces: [LinkRoutingSpace]) -> LinkRoutingState {
        func converted(_ destination: LinkRouteDestination) -> LinkRouteDestination {
            guard case .profile(let id) = destination else { return destination }
            return spaces.first { $0.profileID == id }.map { .space($0.id) } ?? .mostRecent
        }
        var next = self
        for index in next.rules.indices { next.rules[index].destination = converted(next.rules[index].destination) }
        next.defaultDestination = converted(defaultDestination)
        return next
    }
}

package enum LinkRoutingDraft {
    package static func savable(_ rules: [LinkRoute], editing: Set<UUID> = [], saved: [LinkRoute] = []) -> [LinkRoute] {
        let savedPatterns = Dictionary(saved.flatMap(\.conditions).map { ($0.id, $0.pattern) },
                                       uniquingKeysWith: { first, _ in first })
        return rules.compactMap { rule in
            var rule = rule
            rule.conditions = rule.conditions.compactMap { condition in
                var condition = condition
                if editing.contains(condition.id) { condition.pattern = savedPatterns[condition.id] ?? "" }
                return condition.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : condition
            }
            return rule.conditions.isEmpty ? nil : rule
        }
    }
}

package struct LinkRoutingSpace: Equatable {
    package let id: UUID
    package let profileID: UUID

    package init(id: UUID, profileID: UUID) {
        self.id = id
        self.profileID = profileID
    }
}

package struct LinkRoutingDecision: Equatable {
    package let spaceID: UUID
    package let matchedRuleID: UUID?
    package let usedUnavailableDestinationFallback: Bool
}

package enum LinkRoutingUnavailableSpace {
    package static func firstEligibleWindow<ID: Hashable>(ordered: [ID], eligible: Set<ID>) -> ID? {
        ordered.first { eligible.contains($0) }
    }

    package static func newWindowSpace(lastFocused: UUID?, available: [UUID]) -> UUID? {
        if let lastFocused, available.contains(lastFocused) { return lastFocused }
        return available.first
    }
}

@MainActor
package final class LinkRoutingStore: ObservableObject {
    private static let unreadableMessage = "Saved routes couldn’t be read. Links will open in the most recent Space. Reset Routes to replace the unreadable file."
    @Published package private(set) var state = LinkRoutingState()
    @Published package private(set) var errorMessage: String?
    private let file: URL
    private var unreadableFile = false
    private var lastWrittenBytes: Data?

    package init(directory: URL) {
        file = directory.appendingPathComponent("link-routing.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(LinkRoutingState.self, from: Data(contentsOf: file))
            guard loaded.version == 1, loaded.defaultDestination == .mostRecent,
                  Set(loaded.rules.map(\.id)).count == loaded.rules.count,
                  loaded.rules.allSatisfy({ Set($0.conditions.map(\.id)).count == $0.conditions.count }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            state = loaded
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            lastWrittenBytes = try? encoder.encode(loaded)
        } catch {
            unreadableFile = true
            errorMessage = Self.unreadableMessage
        }
    }

    package func decision(for url: URL, spaces: [LinkRoutingSpace], currentSpaceID: UUID?) -> LinkRoutingDecision? {
        guard !spaces.isEmpty else { return nil }
        let rule = state.rules.first { $0.conditions.allSatisfy { $0.accepts(url) } }
        let destination = rule?.destination ?? state.defaultDestination
        func mostRecent(in candidates: [LinkRoutingSpace]) -> UUID? {
            if let currentSpaceID, candidates.contains(where: { $0.id == currentSpaceID }) { return currentSpaceID }
            return state.recentSpaceIDs.first(where: { id in candidates.contains { $0.id == id } }) ?? candidates.first?.id
        }
        let requested: UUID?
        switch destination {
        case .mostRecent: requested = mostRecent(in: spaces)
        case .space(let id): requested = spaces.first(where: { $0.id == id })?.id
        case .profile(let id): requested = mostRecent(in: spaces.filter { $0.profileID == id })
        }
        guard let target = requested ?? mostRecent(in: spaces) else { return nil }
        return LinkRoutingDecision(spaceID: target, matchedRuleID: rule?.id,
            usedUnavailableDestinationFallback: requested == nil)
    }

    @discardableResult
    package func save(_ rule: LinkRoute) -> Bool {
        guard !rule.conditions.isEmpty,
              rule.conditions.allSatisfy({ !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  ($0.style != .matches || LinkRouteCondition.siteURL($0.pattern) != nil) }) else {
            errorMessage = "Enter a URL or text for every condition. “Is equal to” needs a site address, such as example.com/path."
            return false
        }
        var next = state
        if let index = next.rules.firstIndex(where: { $0.id == rule.id }) { next.rules[index] = rule }
        else { next.rules.append(rule) }
        return commit(next)
    }

    @discardableResult
    package func commitEditor(_ rules: [LinkRoute], basedOn original: [LinkRoute]) -> Bool {
        let filtered = LinkRoutingDraft.savable(rules)
        if filtered == original { return true }
        guard state.rules == original else {
            errorMessage = "Routes changed in another window. Reopen Air Traffic Control to review the latest routes."
            return false
        }
        var next = state; next.rules = filtered
        return commit(next)
    }

    @discardableResult
    package func remove(_ id: UUID) -> Bool {
        var next = state; next.rules.removeAll { $0.id == id }; return commit(next)
    }

    @discardableResult
    package func move(_ id: UUID, by offset: Int) -> Bool {
        guard let from = state.rules.firstIndex(where: { $0.id == id }),
              state.rules.indices.contains(from + offset) else { return false }
        var next = state; next.rules.swapAt(from, from + offset); return commit(next)
    }

    package func noteVisitedSpace(_ id: UUID) {
        guard !unreadableFile, state.recentSpaceIDs.first != id else { return }
        var next = state; next.recentSpaceIDs.removeAll { $0 == id }
        next.recentSpaceIDs.insert(id, at: 0)
        next.recentSpaceIDs = Array(next.recentSpaceIDs.prefix(256))
        if !commit(next) { state.recentSpaceIDs = next.recentSpaceIDs }
    }

    @discardableResult
    package func reset(basedOn original: [LinkRoute]) -> Bool {
        guard state.rules == original else {
            errorMessage = "Routes changed in another window. Reopen Air Traffic Control to review the latest routes."
            return false
        }
        let blocked = unreadableFile; unreadableFile = false
        var next = state; next.rules.removeAll(); next.defaultDestination = .mostRecent
        if commit(next) { return true }
        unreadableFile = blocked; return false
    }

    @discardableResult
    package func convertProfileDestinations(spaces: [LinkRoutingSpace]) -> Bool {
        let next = state.convertingProfileDestinations(spaces: spaces)
        return next == state || commit(next)
    }

    private func commit(_ next: LinkRoutingState) -> Bool {
        guard !unreadableFile else { errorMessage = Self.unreadableMessage; return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(next)
            if SettingsPrettyJSONPersistSkip.shouldSkip(previous: lastWrittenBytes, next: data) {
                state = next; errorMessage = nil; return true
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            lastWrittenBytes = data
            state = next; errorMessage = nil; return true
        } catch {
            errorMessage = "Couldn’t save routes: " + error.localizedDescription
            return false
        }
    }
}
