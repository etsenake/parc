import Foundation
import ParcCore

extension CommandBarRanking {
    static func commandCandidate(key: String, texts: [String], menuCommandID: String? = nil, menuText: String? = nil,
                                 typed: CommandBarTypedCommand? = nil) -> Candidate {
        var texts = texts
        var bump: Double? = nil
        if let id = menuCommandID {
            if let menuText { texts.append(menuText) }
            texts += CommandBarTypedCommand.rankingPhrases(forMenuCommand: id)
            bump = CommandBarMenuItemInfo.candidateBump(forMenuCommand: id)
        }
        if let typed { texts += typed.rankingTexts; bump = typed.candidateBump }
        return Candidate(archetype: .typeTravel, key: key, texts: texts, bump: CommandBarMenuItemInfo.rankingBump(bump))
    }
}
