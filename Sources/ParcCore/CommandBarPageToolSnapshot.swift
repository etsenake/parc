import Foundation

/// The engine allows a page tool only while the page's window is key, and an
/// open command bar's own panel holds key. While that bar is open its rows use
/// what the engine allowed for the same page just before it opened; once it
/// closes, the engine is asked again before anything runs.
struct CommandBarPageToolSnapshot: Equatable {
    let panel: ObjectIdentifier
    let page: ObjectIdentifier
    let tools: Set<Int>

    /// The snapshot's answer, or nil when it doesn't apply (no bar, another
    /// bar) and the engine must be asked.
    func allows(_ tool: Int, openPanel: ObjectIdentifier?, page: ObjectIdentifier) -> Bool? {
        guard let openPanel, openPanel == panel else { return nil }
        return self.page == page && tools.contains(tool)
    }
}
