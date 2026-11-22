import Foundation
import Testing
@testable import Parc
@testable import ParcCore
@testable import ParcSidebar

extension SidebarRescueTestsSupport {
    @MainActor
    struct SidebarRescueWordingTests {
        nonisolated private static let hoursAgo = base.addingTimeInterval(-7_200)

        private static func wording(_ trouble: SidebarRescue.Trouble, date: Date = hoursAgo,
                                    skippedNewer: Bool = false) -> SidebarRescue.Wording {
            SidebarRescue.wording(for: .init(trouble: trouble, date: date, skippedNewer: skippedNewer, now: base))
        }

        @Test func aMissingFileHasItsOwnTitleAndOffersAnEmptySidebarInsteadOfQuitting() {
            let wording = Self.wording(.missing)
            #expect(wording.title == "Parc couldn’t find your saved sidebar")
            #expect(wording.alternative == "Start Empty")
        }

        @Test(arguments: ["damaged", "couldn’t be read", "unreadable"])
        func aMissingFileIsNotCalledDamagedOrUnreadable(word: String) {
            #expect(Self.wording(.missing).message.contains("is missing"))
            #expect(!Self.wording(.missing).message.contains(word))
        }

        @Test func theMessageSaysHowOldTheBackupIs() throws {
            let age = try #require(SidebarRescue.backupAge(Self.hoursAgo, now: SidebarRescueTestsSupport.base))
            #expect(Self.wording(.missing).message.contains("is from \(age)."))
        }

        @Test func skippedCopiesAreMentionedWithoutBlamingTheMissingFile() {
            let message = Self.wording(.missing, skippedNewer: true).message
            #expect(message.contains("Newer backups couldn’t be read, so the most recent one that works is from"))
        }

        @Test func aSkippedCopiesMessageWithAFutureStampStillReadsAsOneSentence() {
            let message = Self.wording(.missing, date: SidebarRescueTestsSupport.base.addingTimeInterval(86_400), skippedNewer: true).message
            #expect(message.contains("the most recent one that works is dated after your Mac’s current time; its age isn’t known."))
        }

        @Test func aDamagedFileKeepsItsWordingAndItsQuitButton() {
            let wording = Self.wording(.unreadable, skippedNewer: true)
            #expect(wording.title == "Parc couldn’t read your saved sidebar")
            #expect(wording.alternative == "Quit")
            #expect(wording.message.contains("damaged"))
            #expect(wording.message.contains("couldn’t be read either"))
        }

        @Test func aCopyStampedInTheFutureSaysItsAgeIsUnknown() {
            let ahead = SidebarRescueTestsSupport.base.addingTimeInterval(365 * 86_400)
            #expect(SidebarRescue.backupAge(ahead, now: SidebarRescueTestsSupport.base) == nil)
            #expect(Self.wording(.unreadable, date: ahead).message
                .contains("The most recent backup is dated after your Mac’s current time; its age isn’t known."))
        }

        @Test func aFutureDateIsNeverPresentedAsHowOldTheCopyIs() {
            let message = Self.wording(.unreadable, date: SidebarRescueTestsSupport.base.addingTimeInterval(365 * 86_400)).message
            #expect(!message.contains("2027"))
            #expect(!message.contains("from"))
        }

        @Test(arguments: [30.0, -30.0])
        func secondsOfClockDriftEitherWayReadAsAMomentAgo(drift: Double) {
            #expect(SidebarRescue.backupAge(SidebarRescueTestsSupport.base.addingTimeInterval(drift), now: SidebarRescueTestsSupport.base) == "a moment ago")
        }
    }
}
