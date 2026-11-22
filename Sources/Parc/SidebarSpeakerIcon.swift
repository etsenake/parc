import AppKit
import SwiftUI

@MainActor final class SidebarSpeakerModel: ObservableObject {
    @Published var muted: Bool
    @Published var color: NSColor = .labelColor
    init(muted: Bool) { self.muted = muted }
}

@MainActor final class SidebarSpeakerHost: NSHostingView<SidebarSpeakerIcon> {
    let model: SidebarSpeakerModel
    convenience init(muted: Bool) {
        self.init(rootView: SidebarSpeakerIcon(model: SidebarSpeakerModel(muted: muted)))
    }
    required init(rootView: SidebarSpeakerIcon) {
        model = rootView.model
        super.init(rootView: rootView)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct SidebarSpeakerIcon: View {
    @ObservedObject var model: SidebarSpeakerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let speed = 0.6
    var body: some View {
        let muted = model.muted
        ZStack {
            Image(systemName: "speaker")
                .font(.system(size: 14, weight: .medium))
                .clipShape(SpeakerCutout(progress: muted ? 1 : 0), style: FillStyle(eoFill: true))
                .offset(x: muted ? 0 : -4)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6).delay(muted ? speed * 0.12 : 0), value: muted)
            ForEach(0..<3) { index in
                SpeakerWave(index: index)
                    .frame(width: 8, height: 12)
                    .offset(x: muted ? CGFloat(index + 2) : 5)
                    .opacity(muted ? 0 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)
                        .delay(speed * (muted ? Double(index) * 0.05 : 0.1 + Double(index) * 0.05)), value: muted)
            }
        }
        .foregroundColor(Color(nsColor: model.color))
        .animation(reduceMotion ? nil : .spring(response: muted ? 0.3 : 0.25, dampingFraction: muted ? 0.65 : 0.7)
            .delay(muted ? speed * 0.12 : 0), value: muted)
        .accessibilityHidden(true)
    }
}

private struct SpeakerCutout: Shape {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path(); path.addRect(rect)
        let thickness = rect.maxX * 3.5 / 20
        let inset = thickness / 4.5
        let slash = CGRect(x: -inset, y: -thickness / 2,
                           width: 2 * inset + progress * sqrt(2) * rect.width,
                           height: thickness)
        path.addRoundedRect(in: slash, cornerSize: CGSize(width: thickness / 2, height: thickness / 2),
                            transform: CGAffineTransform(rotationAngle: .pi / 4))
        return path
    }
}

private struct SpeakerWave: Shape {
    let index: Int
    private typealias Curve = (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    func path(in rect: CGRect) -> Path {
        let curves: [Curve]
        let start: CGPoint
        switch index {
        case 0:
            start = CGPoint(x: 0.30312, y: 0.50959)
            curves = [(0.1915,0.32037,0.30312,0.43928,0.2627,0.3731),(0.07373,0.31623,0.15986,0.29659,0.10449,0.29607),(0.08428,0.38293,0.04473,0.33536,0.05439,0.35863),(0.15283,0.50959,0.1291,0.41757,0.15283,0.46151),(0.08428,0.63626,0.15283,0.55767,0.1291,0.60162),(0.07373,0.70244,0.05439,0.66004,0.04473,0.68331),(0.1915,0.6983,0.10449,0.72312,0.15986,0.7226),(0.30312,0.50959,0.2627,0.64608,0.30312,0.57991)]
        case 1:
            start = CGPoint(x: 0.62393, y: 0.50959)
            curves = [(0.41299,0.18336,0.62393,0.38551,0.54834,0.27022),(0.29609,0.1813,0.37783,0.16113,0.32686,0.16062),(0.3084,0.24747,0.26709,0.20043,0.275,0.22576),(0.47363,0.50959,0.41475,0.3183,0.47363,0.40929),(0.3084,0.77171,0.47363,0.60938,0.41475,0.70088),(0.29609,0.83789,0.275,0.79343,0.26709,0.81825),(0.41299,0.83531,0.32686,0.85805,0.37783,0.85805),(0.62393,0.50959,0.54834,0.74896,0.62393,0.63368)]
        default:
            start = CGPoint(x: 0.94385, y: 0.50959)
            curves = [(0.63975,0.05618,0.94385,0.33536,0.8331,0.17509),(0.52725,0.05463,0.60547,0.03447,0.55537,0.03602),(0.53691,0.12081,0.49824,0.07324,0.50352,0.10013),(0.79356,0.50959,0.70303,0.22317,0.79356,0.36018),(0.53691,0.89838,0.79356,0.65901,0.70303,0.79601),(0.52725,0.96404,0.50352,0.91906,0.49824,0.94595),(0.63975,0.96301,0.55537,0.98317,0.60547,0.98472),(0.94385,0.50959,0.8331,0.84358,0.94385,0.68382)]
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path(); path.move(to: point(start.x, start.y))
        for (x,y,c1x,c1y,c2x,c2y) in curves { path.addCurve(to: point(x,y), control1: point(c1x,c1y), control2: point(c2x,c2y)) }
        path.closeSubpath(); return path
    }
}
