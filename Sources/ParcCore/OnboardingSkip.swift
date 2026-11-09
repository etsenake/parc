///
/// before advancing. Replay is Parc's own: skipping there returns to what the
/// Space already had rather than clearing it.
extension OnboardingDraft {
    ///
    /// 0.8, undo cleared; the colour wheel and light/dark choice stay.
    mutating func skipTheme(replayBase: SpaceTheme?) {
        theme = replayBase ?? SpaceTheme(wheel: theme.wheel, appearance: theme.appearance)
    }

    ///
    /// never removes tabs, so the profile's existing Favorites stay selected.
    mutating func skipFavorites(keeping existing: Set<String> = []) {
        favoriteURLs = existing
        favoriteOrder = []
    }
}
