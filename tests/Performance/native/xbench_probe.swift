// Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.

import AppKit
import IOKit
func hidIdle() -> Double {
  let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
  guard service != 0 else { return -1 }
  defer { IOObjectRelease(service) }
  let ns = (IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue ?? -1e9
  return ns / 1e9
}
func state() -> [String: Any] {
  let session = CGSessionCopyCurrentDictionary() as? [String: Any]
  return ["hid": (hidIdle() * 100).rounded() / 100, "locked": (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false,
          "asleep": CGDisplayIsAsleep(CGMainDisplayID()) != 0, "front": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
          "at": (Date().timeIntervalSince1970 * 1000).rounded()]
}
func emit(_ v: Any) {
  print(String(data: try! JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]), encoding: .utf8)!)
  fflush(stdout)
}
func cover(_ pid: Int32) -> [[String: Any]] {
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
  func rect(_ w: [String: Any]) -> CGRect {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
  }
  var above: [CGRect] = []
  var result: [[String: Any]] = []
  for w in list {
    let owner = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
    let r = rect(w)
    let alpha = w[kCGWindowAlpha as String] as? Double ?? 0
    if owner == pid && r.width >= 300 && r.height >= 200 && alpha > 0 {
      var covered = 0, total = 0
      for i in 0..<40 { for j in 0..<25 {
        let p = CGPoint(x: r.minX + (Double(i) + 0.5) * r.width / 40, y: r.minY + (Double(j) + 0.5) * r.height / 25)
        total += 1
        if above.contains(where: { $0.contains(p) }) { covered += 1 }
      } }
      result.append(["id": w[kCGWindowNumber as String] ?? 0, "layer": w[kCGWindowLayer as String] ?? 0, "x": r.minX, "y": r.minY,
                     "w": r.width, "h": r.height, "covered": Double(covered) / Double(total)])
    }
    if alpha > 0 && owner != pid { above.append(r) }
  }
  return result
}
let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "state": emit(state())
case "watch":
  emit(state())
  Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in emit(state()) }
  RunLoop.main.run()
case "screen":
  let f = NSScreen.screens.first?.frame ?? .zero
  emit(["w": f.width, "h": f.height])
case "cover": emit(cover(Int32(args[2]) ?? 0))
default: exit(64)
}
