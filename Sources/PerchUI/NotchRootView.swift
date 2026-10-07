import SwiftUI
import PerchCore

public struct NotchRootView: View {
    @Bindable var model: NotchViewModel
    public init(model: NotchViewModel) { self.model = model }

    public var body: some View {
        let phase = model.phase
        let size = model.bodySize
        let panel = model.panelSize
        let idle = NotchGeometry.idleSize(for: model.screen)
        let metrics = CardMetrics(band: max(idle.height, 32), gap: idle.width + 20)
        let topR: CGFloat = phase == .idle ? 0 : 12
        let botR: CGFloat = phase == .idle ? 10 : 26
        let visible = model.hasNotch || phase != .idle

        ZStack(alignment: .top) {
            NotchShape(topRadius: topR, bottomRadius: botR)
                .fill(Color.black)
                .overlay(NotchShape(topRadius: topR, bottomRadius: botR).stroke(Color.white.opacity(phase == .idle ? 0 : 0.07), lineWidth: 1))
                .frame(width: size.width + topR * 2, height: size.height)
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.55), radius: 28, y: 16)
                .opacity(visible ? 1 : 0)

            content(phase: phase, metrics: metrics)
                .frame(width: size.width, height: size.height, alignment: .top)
                .overlay(alignment: .bottomLeading) { timerLine(width: size.width, phase: phase) }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: botR, bottomTrailingRadius: botR, style: .continuous))

            creature(phase: phase, panelWidth: panel.width, idle: idle, metrics: metrics)
        }
        .frame(width: panel.width, height: panel.height, alignment: .top)
    }

    @ViewBuilder private func content(phase: NotchPhase, metrics: CardMetrics) -> some View {
        ZStack(alignment: .top) {
            if let p = model.project {
                OpenCard(project: p, shown: phase == .open, metrics: metrics,
                         confirm: { model.send(.confirm) }, dismiss: { model.send(.dismiss) })
                    .id(p.id).transition(.blurReplace)
                    .opacity(phase == .open ? 1 : 0).allowsHitTesting(phase == .open)
                SwitcherCard(projects: model.projects, selected: model.selected, shown: phase == .switcher,
                             metrics: metrics, choose: { model.choose($0) })
                    .opacity(phase == .switcher ? 1 : 0).allowsHitTesting(phase == .switcher)
                RestoringCard(project: p, shown: phase == .restoring, metrics: metrics)
                    .opacity(phase == .restoring ? 1 : 0)
            }
        }
        .animation(Motion.snappy, value: model.selected)
    }

    private func timerLine(width: CGFloat, phase: NotchPhase) -> some View {
        Rectangle().fill(Palette.saffron.opacity(0.7))
            .frame(width: width * model.barProgress, height: 1.5)
            .opacity(phase == .open ? 1 : 0)
    }

    /// Idle: peeking out from behind the notch. In a card: level with the notch, left of the title.
    private func creature(phase: NotchPhase, panelWidth: CGFloat, idle: CGSize, metrics: CardMetrics) -> some View {
        let perched = phase == .idle
        let d: CGFloat = perched ? 22 : 24
        let cx = panelWidth / 2
        let x: CGFloat = perched
            ? (model.hasNotch ? cx - idle.width / 2 - d + 8 : cx - d / 2)
            : cx - model.bodySize.width / 2 + 24
        let y: CGFloat = perched ? (model.hasNotch ? (idle.height - d) / 2 : 5) : (metrics.band - d) / 2
        return Creature(mood: model.creatureMood, hop: model.hopCount)
            .frame(width: d, height: d)
            .position(x: x + d / 2, y: y + d / 2)
            .frame(width: panelWidth, height: model.panelSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}
