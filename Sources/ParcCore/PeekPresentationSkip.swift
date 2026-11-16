import Foundation

enum PeekPresentationSkip {
    static func shouldSkip(previous: String?, next: String) -> Bool {
        previous == next
    }

    static func displayTitle(browserTitle: String, urlHost: String?) -> String {
        browserTitle.isEmpty ? (urlHost ?? "Peek") : browserTitle
    }

    static func captureToken(active: Bool, camera: Bool, microphone: Bool, tab: Bool,
                             window: Bool, display: Bool, mirrored: Bool, shared: Bool) -> String {
        guard active else { return "c0" }
        return [
            "c1",
            camera ? "cam1" : "cam0",
            microphone ? "mic1" : "mic0",
            tab ? "tab1" : "tab0",
            window ? "win1" : "win0",
            display ? "dis1" : "dis0",
            mirrored ? "mir1" : "mir0",
            shared ? "sha1" : "sha0",
        ].joined(separator: "|")
    }

    static func crashToken(identity: ObjectIdentifier?, terminationStatus: Int, errorCode: Int) -> String {
        guard let identity else { return "crash-" }
        return "crash:\(identity)|\(terminationStatus)|\(errorCode)"
    }

    static func faviconToken(_ data: Data?) -> String {
        guard let data else { return "fav-" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        data.withUnsafeBytes { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return "fav:\(data.count).\(String(hash, radix: 16))"
    }

    static func fingerprint(
        title: String,
        url: String,
        loading: Bool,
        canGoBack: Bool,
        canGoForward: Bool,
        closePending: Bool,
        canExpand: Bool,
        canSplit: Bool,
        splitToolTip: String?,
        capture: String,
        crash: String,
        favicon: String
    ) -> String {
        [
            "t:\(title)",
            "u:\(url)",
            loading ? "l1" : "l0",
            canGoBack ? "b1" : "b0",
            canGoForward ? "f1" : "f0",
            closePending ? "p1" : "p0",
            canExpand ? "e1" : "e0",
            canSplit ? "s1" : "s0",
            "st:\(splitToolTip ?? "")",
            capture,
            crash,
            favicon,
        ].joined(separator: "\u{1f}")
    }
}
