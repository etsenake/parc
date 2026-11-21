import Foundation

@main
struct EaselCrashHardeningTests {
    @MainActor static var assertions = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor static func main() {
        exportScale()
        print("EaselCrashHardeningTests: \(assertions) assertions passed")
    }

    @MainActor static func exportScale() {
        expect(EaselExportScale.capped(2, width: 1200, height: 900) == 2, "Ordinary boards export at full density")
        let tall = EaselExportScale.capped(2, width: 1500, height: 2_000_000)
        expect(tall > 0 && 2_000_000 * tall <= EaselExportScale.maximumSide + 0.5, "A giant board keeps every side within the export limit")
        let wide = EaselExportScale.capped(2, width: 20_000, height: 20_000)
        expect(20_000 * wide * 20_000 * wide <= EaselExportScale.maximumPixels * 1.000_001, "A huge board stays within the pixel budget")
        expect(wide > 0, "A huge board still exports at a positive scale")
        expect(EaselExportScale.capped(2, width: 0, height: 900) == 2, "Empty sizes leave the scale for the caller's own guard")
        expect(EaselExportScale.capped(.nan, width: 100, height: 100).isNaN, "Invalid scales pass through for the caller's own guard")
    }
}
