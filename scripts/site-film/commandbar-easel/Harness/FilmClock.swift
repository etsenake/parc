import QuartzCore

enum FilmClock {
    nonisolated(unsafe) static var now: CFTimeInterval = 1000
}

func CACurrentMediaTime() -> CFTimeInterval { FilmClock.now }
