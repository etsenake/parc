import Foundation
import CoreGraphics
import CoreImage

struct CameraKey { let t: Double; let v: Vec3; let ease: Ease }

struct ScenePlan {
    var name: String
    var file: String
    var segments: [(Double, Double)]
    var join: Double
    var camera: [CameraKey]
    var optional = false
    var relative = false
    var lead = 0.0
    var share = 0.0
    var fromEnd = 0.0
    var tight: [(Double, Double)] = []
}

let home = Vec3(640, 420, 1)
func key(_ t: Double, _ x: Double, _ y: Double, _ z: Double, _ e: Ease = .bezier(0.45, 0, 0.3, 1)) -> CameraKey { CameraKey(t: t, v: Vec3(x, y, z), ease: e) }
let settle = Ease.spring(response: 1.1, damping: 1)

let defaultPlan: [ScenePlan] = [
    ScenePlan(name: "collapse", file: "collapse/out/collapse.mov", segments: [(1.6, 8.0)], join: 0, camera: [
        key(1.6, 640, 420, 1), key(8.0, 640, 420, 1, .hold)
    ]),
    ScenePlan(name: "spaces", file: "spaces/out/spaces.mov", segments: [(0.7, 2.25), (2.65, 4.3), (4.55, 8.35)], join: 0, camera: [
        key(0.7, 640, 420, 1), key(0.75, 640, 420, 1, .hold), key(1.6, 380, 400, 1.2), key(4.2, 380, 405, 1.2, .linear),
        key(6.1, 380, 405, 1.2, .hold), key(7.0, 380, 400, 1.2, .linear), key(8.15, 640, 420, 1)
    ]),
    ScenePlan(name: "peek", file: "peek/out/peek.mov", segments: [(0.3, 4.7), (6.55, 7.6)], join: 0, camera: [
        key(0.3, 640, 420, 1), key(0.45, 640, 420, 1, .hold), key(1.0, 560, 610, 1.22), key(1.25, 560, 610, 1.22, .hold),
        key(1.58, 640, 420, 1, .bezier(0.4, 0, 0.25, 1)), key(7.6, 640, 420, 1, .hold)
    ]),
    ScenePlan(name: "split", file: "split/out/split.mov", segments: [(1.1, 8.3)], join: 0, camera: [
        key(1.1, 640, 420, 1), key(8.3, 640, 420, 1, .hold)
    ]),
    ScenePlan(name: "commandbar", file: "commandbar-easel/out/commandbar.mov", segments: [(0.5, 2.5), (4.2, 5.6)], join: 0, camera: [
        key(0.5, 640, 420, 1), key(0.8, 640, 420, 1, .hold), key(1.6, 640, 380, 1.3), key(2.5, 640, 385, 1.3, .linear),
        key(4.2, 640, 385, 1.3, .hold), key(4.65, 640, 385, 1.3, .hold), key(5.55, 640, 420, 1)
    ]),
    ScenePlan(name: "easel", file: "commandbar-easel/out/easel.mov", segments: [(2.45, 7.55)], join: 0, camera: [
        key(2.45, 640, 420, 1), key(2.65, 640, 420, 1, .hold), key(3.7, 780, 465, 1.22, settle), key(7.55, 780, 462, 1.22, .linear)
    ]),
    ScenePlan(name: "mini", file: "mini-card/out/mini.mov", segments: [(0.25, 3.9)], join: 0, camera: [
        key(0.25, 640, 420, 1), key(0.6, 640, 420, 1, .hold), key(1.6, 300, 700, 1.4), key(2.3, 300, 700, 1.4, .linear),
        key(2.8, 640, 420, 1, .bezier(0.4, 0, 0.25, 1)), key(3.9, 640, 420, 1, .hold)
    ])
]

@main
struct Hero {
    static func main() throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let scratch = root.deletingLastPathComponent()
        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out.appendingPathComponent("hero-frames"), withIntermediateDirectories: true)
        let only = ProcessInfo.processInfo.environment["FILM_STILLS"]
        let cutsURL = root.appendingPathComponent("cuts.json")
        var plan = defaultPlan
        if let data = try? Data(contentsOf: cutsURL), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], obj["source"] as? String == "hero-plan", let list = obj["scenes"] as? [[String: Any]] {
            for entry in list {
                guard let name = entry["name"] as? String, let i = plan.firstIndex(where: { $0.name == name }) else { continue }
                if let segs = entry["segments"] as? [[Double]] { plan[i].segments = segs.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil } }
                if let j = entry["dissolveIn"] as? Double { plan[i].join = min(j, 0.25) }
            }
            let order = list.compactMap { $0["name"] as? String }
            let natural = defaultPlan.map(\.name)
            func rank(_ name: String) -> Double {
                if let i = order.firstIndex(of: name) { return Double(i) }
                guard let d = natural.firstIndex(of: name) else { return 99 }
                let before = natural[..<d].reversed().first { order.contains($0) }
                return before.map { Double(order.firstIndex(of: $0)!) + 0.5 } ?? -0.5
            }
            plan.sort { rank($0.name) < rank($1.name) }
        }

        let tail = 0.6
        var tailDissolve = 0.0
        var settings = FilmSettings()
        settings.width = 1920
        settings.height = 1260
        settings.supersample = 1
        settings.grain = 0
        settings.vignette = 0
        settings.motionMinimum = 14
        settings.maxMotionSamples = 32
        let plate = CGSize(width: settings.width, height: settings.height)
        let ci = CIContext()
        let looper = WindowLoop(context: ci)

        struct Ready { let plan: ScenePlan; let source: VideoSource; let segments: [(Double, Double)] }
        var ready: [Ready] = []
        var statusByName: [String: [String: Any]] = [:]
        for p in plan {
            let url = scratch.appendingPathComponent(p.file)
            guard FileManager.default.fileExists(atPath: url.path), let src = try? VideoSource(url), src.duration > 0.5 else {
                statusByName[p.name] = ["name": p.name, "file": p.file, "status": "pending: file not ready, left as a named gap", "segments": p.segments.map { [$0.0, $0.1] }, "dissolveIn": p.join]
                continue
            }
            var segs = p.segments
            if segs.isEmpty && p.fromEnd > 0 {
                segs = [(max(0, src.duration - p.fromEnd), src.duration - 1.0 / 60)]
            } else if segs.isEmpty {
                let lead = min(p.lead, src.duration / 4)
                segs = [(lead, p.share > 0 ? min(src.duration, lead + p.share) : src.duration)]
            }
            ready.append(Ready(plan: p, source: src, segments: segs))
        }
        let budget = 45.0, optionalBudget = 32.0
        func length(_ list: [Ready]) -> Double { list.reduce(0.4) { $0 + $1.segments.reduce(0) { $0 + ($1.1 - $1.0) } } }
        for (i, r) in ready.enumerated().reversed() where r.plan.optional && length(ready) > optionalBudget {
            statusByName[r.plan.name] = ["name": r.plan.name, "file": r.plan.file, "status": "left out: over the \(Int(optionalBudget)) s budget (card loop only)", "segments": r.segments.map { [$0.0, $0.1] }, "dissolveIn": r.plan.join]
            ready.remove(at: i)
        }
        for i in ready.indices where length(ready) > budget && !ready[i].plan.tight.isEmpty {
            ready[i] = Ready(plan: ready[i].plan, source: ready[i].source, segments: ready[i].plan.tight)
        }
        if length(ready) > budget {
            let flexible = ready.indices.filter { ready[$0].plan.share > 0 }
            let over = length(ready) - budget
            let room = flexible.reduce(0.0) { $0 + max(0, ready[$1].segments.last!.1 - ready[$1].segments.last!.0 - 2.5) }
            if room > 0 {
                for i in flexible {
                    let s = ready[i].segments.last!
                    let cut = min(max(0, s.1 - s.0 - 2.5), over * max(0, s.1 - s.0 - 2.5) / room)
                    var segs = ready[i].segments
                    segs[segs.count - 1] = (s.0, s.1 - cut)
                    ready[i] = Ready(plan: ready[i].plan, source: ready[i].source, segments: segs)
                }
            }
        }
        guard let first = ready.first else { print("no scenes ready"); return }
        if let last = ready.last {
            let a = looper.thumb(looper.plate(last.source.image(at: last.segments.last!.1)), 160, 105)
            let b = looper.thumb(looper.plate(first.source.image(at: first.segments[0].0)), 160, 105)
            let d = looper.diff(a, b)
            tailDissolve = 0.45
            print(String(format: "loop join %@ end → opening frame: difference %.2f → %@", last.plan.name, d, tailDissolve > 0 ? String(format: "%.2f s dissolve", tailDissolve) : "straight cut"))
        }

        var t = 0.0
        var shots: [(Shot, Double, Double)] = []
        var timeline: [[String: Any]] = []
        for (i, r) in ready.enumerated() {
            let len = r.segments.reduce(0) { $0 + ($1.1 - $1.0) }
            let nextJoin = i + 1 < ready.count ? ready[i + 1].plan.join : tailDissolve
            let shot = Shot(r.plan.name, start: t, duration: len + nextJoin)
            if r.plan.join > 0 && i > 0 { shot.transitionIn = .dissolve(r.plan.join) }
            var map = Track<Double>(r.segments[0].0)
            var local = 0.0
            var srcToLocal: [(Double, Double, Double)] = []
            for (k, s) in r.segments.enumerated() {
                if k > 0 { map = map.keyed(local + 1e-6, s.0, .hold) }
                srcToLocal.append((s.0, s.1, local))
                local += s.1 - s.0
                map = map.keyed(local, s.1, .linear)
            }
            let extra = min(nextJoin, max(0, r.source.duration - r.segments.last!.1 - 1.0 / 60))
            map = map.keyed(local + extra, r.segments.last!.1 + extra, .linear)
            let source = r.source
            let layer = Layer("window", size: plate, at: .zero) { lt in looper.plate(source.image(at: map.value(at: lt))) }
            layer.edgeClamp = true
            layer.depthOfField = false
            shot.add(layer)
            func toLocal(_ s: Double) -> Double {
                for (a, b, l) in srcToLocal where s >= a - 1e-6 && s <= b + 1e-6 { return l + s - a }
                if let lastSeg = srcToLocal.last, s > lastSeg.1 { return lastSeg.2 + lastSeg.1 - lastSeg.0 + (s - lastSeg.1) }
                return 0
            }
            var cam = Camera.inside(plate: plate, start: r.plan.camera.first?.v ?? home)
            var track = Track(r.plan.camera.first?.v ?? home)
            var lastLocal = 0.0
            let span = (r.segments.first!.0, r.segments.last!.1)
            func sourceTime(_ k: Double) -> Double { r.plan.relative ? span.0 + k * (span.1 - span.0) : k }
            for ck in r.plan.camera.dropFirst() {
                let lt = toLocal(sourceTime(ck.t))
                if lt <= lastLocal + 1e-4 { continue }
                track = track.keyed(lt, ck.v, ck.ease)
                lastLocal = lt
            }
            cam.crop = track
            shot.camera = cam
            shots.append((shot, t, t + len))
            timeline.append(["name": r.plan.name, "start": (t * 1000).rounded() / 1000, "end": ((t + len) * 1000).rounded() / 1000, "segments": r.segments.map { [$0.0, $0.1] }, "join": r.plan.join > 0 && i > 0 ? "dissolve \(r.plan.join) s" : (i == 0 ? "opens the film" : "straight cut")])
            statusByName[r.plan.name] = ["name": r.plan.name, "file": r.plan.file, "status": "included", "segments": r.segments.map { [$0.0, $0.1] }, "dissolveIn": r.plan.join]
            t += len
        }
        let opening = Shot("opening-frame", start: t, duration: tail)
        if tailDissolve > 0 { opening.transitionIn = .dissolve(tailDissolve) }
        let firstSource = first.source
        let firstIn = first.segments[0].0
        let ol = Layer("window", size: plate, at: .zero) { _ in looper.plate(firstSource.image(at: firstIn)) }
        ol.edgeClamp = true
        ol.depthOfField = false
        opening.add(ol)
        opening.camera = .inside(plate: plate, start: home)
        timeline.append(["name": "opening frame (loop)", "start": (t * 1000).rounded() / 1000, "end": ((t + tail) * 1000).rounded() / 1000, "join": tailDissolve > 0 ? "dissolve \(tailDissolve) s" : "straight cut"])
        let length = t + tail

        let film = Film(duration: length, settings: settings)
        for (s, _, _) in shots { film.add(s) }
        film.add(opening)

        let cutsObj: [String: Any] = [
            "source": "hero-plan",
            "note": "Editable scene plan for build/hero. Order, source in/out segments (seconds in each MOV; consecutive segments cut inside a scene on matching resting states) and dissolveIn (≤ 0.25 s, only between near-identical frames; 0 = straight cut). Pending scenes are slotted in automatically once their MOV opens.",
            "scenes": plan.compactMap { statusByName[$0.name] },
            "timeline": timeline,
            "length": (length * 1000).rounded() / 1000
        ]
        try JSONSerialization.data(withJSONObject: cutsObj, options: [.prettyPrinted, .sortedKeys]).write(to: cutsURL)
        print(String(format: "hero length %.2f s; scenes: %@", length, ready.map { $0.plan.name }.joined(separator: " → ")))

        let stripTimes = (0..<8).map { (Double($0) + 0.5) / 8 * length }
        var out_ = OutputPlan(master: out.appendingPathComponent("hero-master.mp4"), scratch: root.appendingPathComponent("build"))
        out_.masterBitrate = 16_000_000
        out_.web = out.appendingPathComponent("hero-web.mp4")
        out_.webSize = (1920, 1260)
        out_.webBitrate = 6_500_000
        out_.webHEVC = out.appendingPathComponent("hero-web-hevc.mp4")
        out_.webHEVCBitrate = 3_800_000
        out_.webPoster = out.appendingPathComponent("hero-poster.jpg")
        out_.strip = (stripTimes, out.appendingPathComponent("hero-strip.png"))
        var stills: [Double] = [0]
        for (s, a, b) in shots { stills += [a + 0.02, (a + b) / 2, b - 0.05]; _ = s }
        stills.append(length - 1.0 / 60)
        out_.stills = stills.map { ($0, out.appendingPathComponent(String(format: "hero-frames/h%05.2f.png", $0))) }
        if let only {
            let r = FilmRenderer(film: film)
            for s in only.split(separator: ",") {
                autoreleasepool {
                    let tt = Double(s)!
                    let img = r.frame(Int((tt * 60).rounded()))
                    let cg = r.context.createCGImage(img, from: CGRect(x: 0, y: 0, width: settings.width, height: settings.height), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
                    Images.write(cg, to: out.appendingPathComponent(String(format: "hero-frames/q%05.2f.png", tt)))
                }
            }
            return
        }
        try FilmOutput.render(film, plan: out_)
    }
}
