import SwiftUI

/// Drawn in a 48 x 48 space and scaled to fit.
private struct P48: Shape {
    let build: @Sendable (inout Path) -> Void
    func path(in rect: CGRect) -> Path {
        var p = Path(); build(&p)
        return p.applying(CGAffineTransform(scaleX: rect.width / 48, y: rect.height / 48))
    }
}

public struct BirdView: View {
    public enum Mood: Equatable { case sleep, awake, happy }
    let mood: Mood
    let nod: Int
    @State private var blink = false

    public init(mood: Mood, nod: Int = 0) { self.mood = mood; self.nod = nod }

    public var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 48
            ZStack(alignment: .topLeading) {
                P48 { $0.move(to: CGPoint(x: 10, y: 27)); $0.addLine(to: CGPoint(x: 1, y: 21))
                      $0.addLine(to: CGPoint(x: 3, y: 33)); $0.closeSubpath() }
                    .fill(Palette.saffronDeep)
                P48 { $0.move(to: CGPoint(x: 19, y: 41)); $0.addLine(to: CGPoint(x: 19, y: 46))
                      $0.move(to: CGPoint(x: 26, y: 41)); $0.addLine(to: CGPoint(x: 26, y: 46)) }
                    .stroke(Palette.coral, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                P48 { $0.addEllipse(in: CGRect(x: 7, y: 18, width: 30, height: 24)) }
                    .fill(Palette.saffron)
                P48 { $0.move(to: CGPoint(x: 12, y: 31))
                      $0.addQuadCurve(to: CGPoint(x: 30, y: 29), control: CGPoint(x: 20, y: 22))
                      $0.addQuadCurve(to: CGPoint(x: 12, y: 31), control: CGPoint(x: 24, y: 38))
                      $0.closeSubpath() }
                    .fill(Palette.saffronDeep)
                head(s: s)
                    .rotationEffect(.degrees(mood == .sleep ? -14 : 0), anchor: UnitPoint(x: 26 / 48, y: 28 / 48))
                    .offset(x: mood == .sleep ? -5 * s : 0, y: mood == .sleep ? 5 * s : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: nod) { content, v in
                content.offset(y: v * s)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(6, duration: 0.17); CubicKeyframe(0, duration: 0.17)
                    CubicKeyframe(6, duration: 0.17); CubicKeyframe(0, duration: 0.2)
                }
            }
            .overlay(alignment: .topTrailing) { zzz(s: s) }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(Motion.bird, value: mood)
        .task(id: mood) { await blinkLoop() }
    }

    private func head(s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            P48 { $0.addEllipse(in: CGRect(x: 19.5, y: 7.5, width: 21, height: 21)) }.fill(Palette.saffron)
            P48 { $0.move(to: CGPoint(x: 39.5, y: 16)); $0.addLine(to: CGPoint(x: 47.5, y: 19))
                  $0.addLine(to: CGPoint(x: 39.5, y: 22)); $0.closeSubpath() }.fill(Palette.coral)
            P48 { $0.addEllipse(in: CGRect(x: 25.4, y: 19.1, width: 4.8, height: 4.8)) }
                .fill(Palette.cheek.opacity(0.55))
            ZStack(alignment: .topLeading) {
                P48 { $0.addEllipse(in: CGRect(x: 31.1, y: 13.7, width: 4.6, height: 4.6)) }.fill(Palette.ink)
                    .scaleEffect(x: 1, y: blink ? 0.08 : 1, anchor: UnitPoint(x: 33.4 / 48, y: 16 / 48))
                P48 { $0.addEllipse(in: CGRect(x: 33.45, y: 14.45, width: 1.5, height: 1.5)) }.fill(.white)
            }.opacity(mood == .awake ? 1 : 0)
            P48 { $0.move(to: CGPoint(x: 31, y: 16.6))
                  $0.addQuadCurve(to: CGPoint(x: 36, y: 16.6), control: CGPoint(x: 33.5, y: 21.6)) }
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                .opacity(mood == .sleep ? 1 : 0)
            P48 { $0.move(to: CGPoint(x: 31, y: 17))
                  $0.addQuadCurve(to: CGPoint(x: 36, y: 17), control: CGPoint(x: 33.5, y: 10.6)) }
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                .opacity(mood == .happy ? 1 : 0)
        }
    }

    @ViewBuilder private func zzz(s: CGFloat) -> some View {
        if mood == .sleep {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                Text("z").font(.system(size: max(8, 11 * s * 0.5), weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .opacity(t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7)
                    .offset(x: 6 * t * s * 0.5, y: -9 * t * s * 0.5 - 4)
            }
            .allowsHitTesting(false)
        }
    }

    private func blinkLoop() async {
        blink = false
        guard mood == .awake else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.8...5)))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.06)) { blink = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeInOut(duration: 0.08)) { blink = false }
        }
    }
}
