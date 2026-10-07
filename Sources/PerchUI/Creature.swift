import SwiftUI

/// A warm circle with eyes. Asleep it breathes with closed eyes, awake it blinks and glances around,
/// happy it squints into arcs and hops.
public struct Creature: View {
    public enum Mood: Equatable { case sleep, awake, happy }
    let mood: Mood
    let hop: Int
    @State private var blink = false
    @State private var look: CGFloat = 0

    public init(mood: Mood, hop: Int = 0) { self.mood = mood; self.hop = hop }

    public var body: some View {
        GeometryReader { geo in
            let d = geo.size.width
            TimelineView(.animation(minimumInterval: 1 / 30, paused: mood != .sleep)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let breath = mood == .sleep ? 1 + 0.035 * sin(t * 2.1) : 1
                face(d: d)
                    .scaleEffect(breath, anchor: .bottom)
            }
            .keyframeAnimator(initialValue: Hop(), trigger: hop) { content, v in
                content.scaleEffect(x: v.sx, y: v.sy, anchor: .bottom).offset(y: v.y * d)
            } keyframes: { _ in
                KeyframeTrack(\.sx) { CubicKeyframe(1.12, duration: 0.1); CubicKeyframe(0.92, duration: 0.16); CubicKeyframe(1.06, duration: 0.14); CubicKeyframe(1, duration: 0.2) }
                KeyframeTrack(\.sy) { CubicKeyframe(0.84, duration: 0.1); CubicKeyframe(1.12, duration: 0.16); CubicKeyframe(0.92, duration: 0.14); CubicKeyframe(1, duration: 0.2) }
                KeyframeTrack(\.y) { CubicKeyframe(0, duration: 0.1); CubicKeyframe(-0.28, duration: 0.16); CubicKeyframe(0, duration: 0.14); CubicKeyframe(0, duration: 0.2) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(Motion.snappy, value: mood)
        .task(id: mood) { await life() }
    }

    private struct Hop { var sx: CGFloat = 1; var sy: CGFloat = 1; var y: CGFloat = 0 }

    private func face(d: CGFloat) -> some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.9, blue: 0.6), Palette.saffron, Color(red: 0.89, green: 0.57, blue: 0.1)],
                                         center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: d * 0.8))
            Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: max(0.5, d * 0.02)).blendMode(.plusLighter)
            Ellipse().fill(Color.white.opacity(0.55)).frame(width: d * 0.2, height: d * 0.11)
                .rotationEffect(.degrees(-28)).offset(x: -d * 0.22, y: -d * 0.3)
            HStack(spacing: d * 0.2) { eye(d: d); eye(d: d) }
                .offset(x: look * d * 0.07, y: d * 0.03)
            HStack(spacing: d * 0.5) { cheek(d: d); cheek(d: d) }.offset(y: d * 0.17)
        }
        .frame(width: d, height: d)
    }

    private func cheek(d: CGFloat) -> some View {
        Capsule().fill(Color(red: 0.94, green: 0.45, blue: 0.3).opacity(mood == .happy ? 0.5 : 0.28))
            .frame(width: d * 0.15, height: d * 0.09)
    }

    private func eye(d: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(Palette.ink).frame(width: d * 0.15, height: d * 0.24)
                .scaleEffect(y: blink ? 0.08 : 1)
                .opacity(mood == .awake ? 1 : 0)
            Arc(up: false).stroke(Palette.ink, style: StrokeStyle(lineWidth: d * 0.055, lineCap: .round))
                .frame(width: d * 0.17, height: d * 0.07).opacity(mood == .sleep ? 1 : 0)
            Arc(up: true).stroke(Palette.ink, style: StrokeStyle(lineWidth: d * 0.06, lineCap: .round))
                .frame(width: d * 0.19, height: d * 0.1).opacity(mood == .happy ? 1 : 0)
        }
        .frame(width: d * 0.19, height: d * 0.26)
    }

    private struct Arc: Shape {
        let up: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: up ? r.maxY : r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: up ? r.maxY : r.minY), control: CGPoint(x: r.midX, y: up ? r.minY - r.height * 0.3 : r.maxY + r.height * 0.3))
            return p
        }
    }

    private func life() async {
        blink = false; look = 0
        guard mood == .awake else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.6...3.4)))
            if Task.isCancelled { return }
            if Bool.random() {
                withAnimation(.easeInOut(duration: 0.06)) { blink = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { look = CGFloat.random(in: -1...1) }
            }
        }
    }
}
