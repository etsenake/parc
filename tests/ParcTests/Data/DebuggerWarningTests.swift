import AppKit
import Testing
@testable import Parc

struct DebuggerWarningTests {
    private final class Token {}

    @Test(arguments: [0, 1, 2])
    func eachVisibleWarningReservesADeveloperToolbarRow(_ count: Int) {
        #expect(DebuggerWarningLayout.height(rows: count) == CGFloat(count) * DeveloperToolbarLayout.height)
    }

    @Test func aWideWarningPlacesItsMessageBetweenTheIconAndCancel() {
        let frames = DebuggerWarningLayout.frames(in: CGRect(x: 0, y: 0, width: 800, height: 40), cancelWidth: 66)

        #expect(frames.showsIcon)
        #expect(frames.icon == CGRect(x: 12, y: 12, width: 16, height: 16))
        #expect(frames.message.minX == 36)
        #expect(frames.message.maxX == 684)
    }

    @Test(arguments: [800.0, 150.0, 60.0])
    func spaceToReadTheWarningNeverShrinksItsButtons(_ width: CGFloat) {
        let frames = DebuggerWarningLayout.frames(in: CGRect(x: 0, y: 0, width: width, height: 40), cancelWidth: 66)

        #expect(frames.close == CGRect(x: width - 34, y: 6, width: 28, height: 28))
        #expect(frames.cancel == CGRect(x: width - 104, y: 7, width: 66, height: 26))
    }

    @Test(arguments: [150.0, 60.0])
    func narrowWarningsGiveTheIconSpaceToTheMessage(_ width: CGFloat) {
        let frames = DebuggerWarningLayout.frames(in: CGRect(x: 0, y: 0, width: width, height: 40), cancelWidth: 66)
        #expect(!frames.showsIcon)
        #expect(frames.icon == .zero)
        #expect(frames.message.minX == 12)
        #expect(frames.message.width == max(0, width - 128))
    }

    @MainActor @Test func aVisiblePageAnnouncesItsNewWarning() {
        let warning = Token()
        let announcements = DebuggerWarningAnnouncements<Token>()
        #expect(announcements.claim([warning]).elementsEqual([warning], by: ===))
    }

    @MainActor @Test func aWarningAlreadyAnnouncedDoesNotRepeatAfterBecomingVisibleAgain() {
        let first = Token(), second = Token()
        let announcements = DebuggerWarningAnnouncements<Token>()
        _ = announcements.claim([first, second])
        _ = announcements.claim([])

        #expect(announcements.claim([second, first]).isEmpty)
    }

    @MainActor @Test func onlyTheNewWarningIsAnnouncedWhenAnotherWasAlreadyVisible() {
        let first = Token(), second = Token()
        let announcements = DebuggerWarningAnnouncements<Token>()
        _ = announcements.claim([first])

        #expect(announcements.claim([first, second]).elementsEqual([second], by: ===))
    }

    enum RowChange: CaseIterable {
        case unchanged, inserted, removed, reordered, shown, hidden
    }

    @Test(arguments: RowChange.allCases)
    func theKeyViewLoopIsRelinkedExactlyWhenItsRowsChange(_ change: RowChange) {
        let first = Token(), second = Token()
        let previous: [Token] = change == .removed || change == .reordered ? [first, second] : [first]
        let next: [Token]
        switch change {
        case .inserted: next = [first, second]
        case .removed: next = [second]
        case .reordered: next = [second, first]
        case .hidden: next = []
        default: next = [first]
        }

        #expect(DebuggerWarningLayout.keyViewsChanged(next, previous: previous,
            hidden: change == .hidden, wasHidden: change == .shown) == (change != .unchanged))
    }

    @Test(arguments: [true, false])
    func aPaneLayoutIsCurrentWhenItsPageStartsBelowTheWarning(_ offsetForWarning: Bool) {
        let y: CGFloat = offsetForWarning ? 80 : 40
        #expect(DeveloperChromeGeometry.paneIsCurrent(bounds: CGRect(x: 0, y: 0, width: 500, height: 400),
            developerHeight: 0, browserHeight: 40,
            developerFrame: CGRect(x: 0, y: 0, width: 500, height: 0),
            browserFrame: CGRect(x: 0, y: 0, width: 500, height: 40),
            contentFrame: CGRect(x: 0, y: y, width: 500, height: 400 - y), warningHeight: 40) == offsetForWarning)
    }

    @Test func aShortPeekClampsTheWarningToAvailableRoom() {
        #expect(DeveloperChromeGeometry.peekIsCurrent(card: CGRect(x: 0, y: 0, width: 500, height: 60),
            developerHeight: 40, browserHeight: 0,
            developerFrame: CGRect(x: 0, y: 0, width: 500, height: 40),
            browserFrame: CGRect(x: 0, y: 0, width: 500, height: 0),
            contentFrame: CGRect(x: 0, y: 60, width: 500, height: 0), warningHeight: 40))
    }
}
