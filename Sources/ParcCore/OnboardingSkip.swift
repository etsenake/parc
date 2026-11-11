extension OnboardingDraft {
    mutating func skipTheme(replayBase: SpaceTheme?) {
        theme = replayBase ?? SpaceTheme(wheel: theme.wheel, appearance: theme.appearance)
    }

    mutating func skipFavorites(keeping existing: Set<String> = []) {
        favoriteURLs = existing
        favoriteOrder = []
    }
}
