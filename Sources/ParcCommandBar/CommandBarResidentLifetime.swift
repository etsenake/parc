enum CommandBarLifetime {
    package enum Event: Equatable {
        case resignedKey(ownAlert: Bool)
        case focusMoved
        case closing
        case miniaturizing
        case sheetBegan(ownAlert: Bool)
        case securityChanged
        case appDeactivated
        case resized
        case moved
        case ownerInvalid
        case escape(scoped: Bool)
        case scopeExitFailed
        case submitted
    }

    enum Response: Equatable {
        case keep
        case reposition
        case retireScopeMenu
        case leaveScope
        case reset
        case resetForAction
        case dismiss
        case dismissRestoringFocus
    }

    static func response(to event: Event, resident: Bool) -> Response {
        switch event {
        case .resized, .moved: return .reposition
        case .closing: return .dismiss
        case .escape(let scoped): return scoped ? .leaveScope : resident ? .reset : .dismissRestoringFocus
        case .scopeExitFailed: return resident ? .reset : .dismissRestoringFocus
        case .submitted: return resident ? .resetForAction : .dismissRestoringFocus
        case .resignedKey(let ownAlert): return ownAlert || resident ? .keep : .dismiss
        case .sheetBegan(let ownAlert): return ownAlert ? .keep : resident ? .retireScopeMenu : .dismiss
        case .securityChanged: return resident ? .retireScopeMenu : .dismiss
        case .focusMoved, .miniaturizing, .appDeactivated, .ownerInvalid: return resident ? .keep : .dismiss
        }
    }
}
