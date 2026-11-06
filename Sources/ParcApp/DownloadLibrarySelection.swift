import Foundation

// Commands carry the copied original row. The window resolves its live
// profile/GUID/incarnation before dispatch; menu tracking cannot retarget it.
enum DownloadLibraryAction {
    case open, reveal, copyFile, copyLink, openSource, toggleOpen
    case pause, resume, cancel, retry, review, remove, trash
}


/// The manager GUID can be reused after retirement. Selection and commands keep
/// its live incarnation as well as the owning profile and public record ID.
struct DownloadLibraryIdentity: Hashable {
    let record: String
    let profile: UUID?
    let guid: String?
    let incarnation: String?
    let privateContext: String?

    init(_ item: BrowserDownload) {
        record = item.id; profile = item.profileID
        guid = item.nativeID; incarnation = item.nativeIdentity; privateContext = item.privateContextID
    }
}

struct DownloadLibrarySelection {
    static func retainedRows(_ selected: [BrowserDownload], in rows: [BrowserDownload?]) -> IndexSet {
        guard selected.count == 1 else { return [] }
        let identities = Set(selected.map(DownloadLibraryIdentity.init))
        return IndexSet(rows.indices.filter { index in
            rows[index].map { identities.contains(DownloadLibraryIdentity($0)) } ?? false
        })
    }

    /// Resolve the whole captured set before dispatch. A vanished/replaced item
    /// refuses the command rather than silently applying it to a subset.
    static func resolve(_ originals: [BrowserDownload], in current: [BrowserDownload],
                        profiles: Set<UUID>) -> [BrowserDownload]? {
        guard !originals.isEmpty else { return nil }
        var seen = Set<DownloadLibraryIdentity>()
        var result: [BrowserDownload] = []
        for original in originals {
            let identity = DownloadLibraryIdentity(original)
            guard seen.insert(identity).inserted, let profile = identity.profile,
                  profiles.contains(profile),
                  let item = current.first(where: { DownloadLibraryIdentity($0) == identity }) else { return nil }
            result.append(item)
        }
        return result
    }

    static func resolve(_ originals: [BrowserDownload], for action: DownloadLibraryAction,
                        in state: BrowserState) -> [BrowserDownload]? {
        // The recovered container, row and DownloadMenu carry one optional
        // original item, not a range. A fabricated plural command is refused.
        guard originals.count == 1,
              let current = resolve(originals, in: state.downloads, profiles: Set(state.profiles.map(\.id))),
              current.allSatisfy({ eligible($0, action, spaces: state.spaces) }) else { return nil }
        if action != .copyLink && action != .openSource,
           !current.allSatisfy({ !($0.nativeID?.isEmpty ?? true) && !($0.nativeIdentity?.isEmpty ?? true) }) { return nil }
        if [.review, .openSource, .copyLink].contains(action), current.count != 1 { return nil }
        if action == .copyLink || action == .openSource,
           zip(originals, current).contains(where: { $0.sourceURL != $1.sourceURL }) { return nil }
        // Chromium toggles each original; mixed values have no shared outcome.
        if action == .toggleOpen,
           Set(current.map(\.openWhenComplete)).count != 1 ||
           zip(originals, current).contains(where: { $0.openWhenComplete != $1.openWhenComplete }) { return nil }
        return current
    }

    static func eligible(_ item: BrowserDownload, _ action: DownloadLibraryAction, spaces: [BrowserSpace]) -> Bool {
        switch action {
        case .open: return item.canOpen
        case .reveal: return item.canReveal
        case .copyFile: return item.canCopyFile
        case .copyLink: return item.profileID != nil && item.sourceURL.flatMap(URL.init(string:)) != nil
        case .openSource:
            guard let profileID = item.profileID, let url = item.sourceURL.flatMap(URL.init(string:)),
                  ["http", "https", "parc", "chrome", "chrome-extension"].contains(url.scheme?.lowercased() ?? "") else { return false }
            // A live OTR owner need not have a remaining regular Space. Its
            // context lease is revalidated again by the original window route.
            return item.privateContextID != nil || spaces.contains(where: { $0.profileID == profileID })
        case .toggleOpen: return item.canToggleOpen
        case .pause: return item.canPause
        case .resume: return item.canResume
        case .cancel: return item.canCancel
        case .retry: return item.canRetry
        case .review: return item.canReview
        case .remove: return item.canRemove
        case .trash: return item.canRemove && item.canCopyFile
        }
    }
    /// Ordinary arrow movement follows displayed items, not date-header rows.
    /// The original Library reducer selects the first item from no selection
    /// and stops at each end. Shift-arrow moves that same single cursor.
    static func nextRow(in selectable: IndexSet, selected: IndexSet, forward: Bool) -> Int? {
        guard let first = selectable.first else { return nil }
        let existing = selected.intersection(selectable)
        guard let edge = forward ? existing.last : existing.first else { return first }
        return forward ? (selectable.first(where: { $0 > edge }) ?? edge)
            : (selectable.last(where: { $0 < edge }) ?? edge)
    }
}
