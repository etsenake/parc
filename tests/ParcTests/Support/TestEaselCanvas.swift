import ParcTestSupport
@testable import Parc
@testable import ParcCore
@testable import ParcEasels

@MainActor
func makeTestEaselCanvas(session: EaselSession) -> EaselCanvasView {
    let defaults = TestDefaults("ParcTests.EaselCanvas.")!
    return EaselCanvasView(session: session, preferences: EaselCanvasPreferences(defaults: defaults))
}
