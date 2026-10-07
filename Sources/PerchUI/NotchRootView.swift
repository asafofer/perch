import SwiftUI
import PerchCore

public struct NotchRootView: View {
    @Bindable var model: NotchViewModel
    public init(model: NotchViewModel) { self.model = model }

    public var body: some View {
        let phase = model.phase
        let size = model.bodySize
        let panel = model.panelSize
        let topR: CGFloat = phase == .idle ? 0 : 20
        let botR: CGFloat = phase == .idle ? 10 : 34
        let visible = model.hasNotch || phase != .idle

        ZStack(alignment: .top) {
            NotchShape(topRadius: topR, bottomRadius: botR)
                .fill(Color.black)
                .frame(width: size.width + topR * 2, height: size.height)
                .shadow(color: .black.opacity(phase == .idle ? 0 : 0.5), radius: 26, y: 14)
                .opacity(visible ? 1 : 0)

            content(phase: phase)
                .frame(width: size.width, height: size.height, alignment: .top)
                .overlay(alignment: .bottomLeading) { timerLine(width: size.width, phase: phase) }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: botR, bottomTrailingRadius: botR, style: .continuous))

            bird(phase: phase, panelWidth: panel.width)
        }
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .onHover { model.send(.hoverChanged($0)) }
    }

    @ViewBuilder private func content(phase: NotchPhase) -> some View {
        ZStack(alignment: .top) {
            if let p = model.project {
                OpenCard(project: p, shown: phase == .open)
                    .id(p.id).transition(.blurReplace)
                    .opacity(phase == .open ? 1 : 0)
                SwitcherCard(projects: model.projects, selected: model.selected, shown: phase == .switcher,
                             choose: { model.choose($0) })
                    .opacity(phase == .switcher ? 1 : 0)
                RestoringCard(project: p, shown: phase == .restoring)
                    .opacity(phase == .restoring ? 1 : 0)
            }
        }
        .animation(Motion.snappy, value: model.selected)
    }

    private func timerLine(width: CGFloat, phase: NotchPhase) -> some View {
        Rectangle().fill(Palette.saffron)
            .frame(width: width * model.barProgress, height: 2)
            .opacity(phase == .open ? 1 : 0)
    }

    private func bird(phase: NotchPhase, panelWidth: CGFloat) -> some View {
        let perched = phase == .idle
        let idle = NotchGeometry.idleSize(for: model.screen)
        let bs: CGFloat = perched ? 26 : 50
        let bx: CGFloat = perched
            ? (model.hasNotch ? panelWidth / 2 - idle.width / 2 - bs - 8 : panelWidth / 2 - bs / 2)
            : panelWidth / 2 - model.bodySize.width / 2 + 24
        let by: CGFloat = perched ? (model.hasNotch ? (idle.height - bs) / 2 : 4) : 20
        return BirdView(mood: model.birdMood, nod: model.nodCount)
            .frame(width: bs, height: bs)
            .position(x: bx + bs / 2, y: by + bs / 2)
            .frame(width: panelWidth, height: model.panelSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
    }
}
