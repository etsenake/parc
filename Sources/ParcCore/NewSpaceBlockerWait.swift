enum NewSpaceBlockerWait {
    enum PeekState: Equatable {
        case none, awaitingConfirmation, closing, open
    }

    enum Step: Equatable {
        case retry
        case waitForConfirmation
        case giveUp
    }

    enum Press: Equatable {
        case dismissAndWait
        case waitWithoutDismissing
        case bringForward
    }

    static func press(peek: PeekState, waitActive: Bool) -> Press {
        guard peek == .awaitingConfirmation else { return .dismissAndWait }
        return waitActive ? .bringForward : .waitWithoutDismissing
    }

    static func next(peek: PeekState, confirmationShown: Bool, attemptsLeft: Int) -> Step {
        switch peek {
        case .awaitingConfirmation: return .waitForConfirmation
        case .open where confirmationShown: return .giveUp
        case .none, .closing, .open: return attemptsLeft > 0 ? .retry : .giveUp
        }
    }
}
