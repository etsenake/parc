import AppKit
import Foundation
import Testing
@testable import ParcCore
@testable import ParcEasels

@MainActor
struct EaselMainActorDeinitTests {
    private final class Holder<Value>: @unchecked Sendable {
        var value: Value?
        init(_ value: Value) { self.value = value }
    }

    private func releaseOffTheMainThread<Value>(_ holder: Holder<Value>) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                holder.value = nil
                continuation.resume()
            }
        }
    }

    @Test func aTimerButtonLeftToABackgroundThreadIsReleasedSafely() async {
        let holder = Holder(EaselTimerButton(documentID: UUID()))
        await releaseOffTheMainThread(holder)
        #expect(holder.value == nil)
    }

    @Test func theEaselPanelsLeftToABackgroundThreadAreReleasedSafely() async {
        let holder = Holder(EaselPanels(container: { nil }, search: { _, _ in [] }))
        await releaseOffTheMainThread(holder)
        #expect(holder.value == nil)
    }
}
