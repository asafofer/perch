import SwiftUI
import PerchCore

/// Fades, lifts and un-blurs content in after the card has grown. `index` staggers siblings.
struct Reveal: ViewModifier {
    let on: Bool
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 8)
            .blur(radius: on ? 0 : 5)
            .animation(on ? .spring(response: 0.46, dampingFraction: 0.86).delay(0.12 + 0.055 * Double(index))
                          : .easeOut(duration: 0.12), value: on)
    }
}
extension View { func reveal(_ on: Bool, _ index: Int = 0) -> some View { modifier(Reveal(on: on, index: index)) } }

/// Where the hardware notch sits, so text can flank it instead of hiding behind it.
struct CardMetrics {
    let band: CGFloat   // height of the strip level with the notch
    let gap: CGFloat    // width reserved for the notch plus breathing room
}

struct Band: View {
    let metrics: CardMetrics
    let left: String
    let right: String
    var body: some View {
        HStack(spacing: 0) {
            Text(left).font(Typo.band).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 38)
            Color.clear.frame(width: metrics.gap)
            Text(right).font(Typo.bandSub).foregroundStyle(Palette.textSecondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: metrics.band)
    }
}

struct Keycap: View {
    let label: String
    var onLight = false
    var body: some View {
        Text(label).font(Typo.key)
            .foregroundStyle(onLight ? Palette.ink : Color(white: 0.78))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(onLight ? Palette.ink.opacity(0.14) : Color.white.opacity(0.09)))
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct OpenCard: View {
    let project: Project
    let shown: Bool
    let metrics: CardMetrics
    let confirm: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Band(metrics: metrics, left: project.name, right: "back after \(project.away)").reveal(shown, 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(project.headline).font(Typo.hero).tracking(-0.4).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true).reveal(shown, 1)
                Text(project.context).font(Typo.body).foregroundStyle(Palette.textSecondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8).reveal(shown, 2)
                nextRow.padding(.top, 18).reveal(shown, 3)
            }
            .padding(.horizontal, 28).padding(.top, 16)
            Spacer(minLength: 0)
            footer.padding(.horizontal, 28).padding(.bottom, 20).reveal(shown, 4)
        }
    }

    private var nextRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.saffron)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.saffron.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Up next").font(Typo.label).foregroundStyle(Color(white: 0.52))
                Text(project.next).font(Typo.strong).foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Palette.surfaceStroke, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(Array(project.agents.enumerated()), id: \.offset) { _, a in
                HStack(spacing: 6) {
                    Circle().fill(color(a.kind)).frame(width: 7, height: 7)
                    Text(a.text).font(Typo.chip).foregroundStyle(Color(white: 0.76)).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.07)))
            }
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Text("Not now").font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                    .foregroundStyle(Palette.textSecondary).padding(.horizontal, 10).padding(.vertical, 8)
            }.buttonStyle(PressStyle())
            Button(action: confirm) {
                HStack(spacing: 9) { Text("Pick up").font(Typo.button).lineLimit(1).fixedSize(); Keycap(label: "↩", onLight: true) }
                    .foregroundStyle(Palette.ink).padding(.leading, 16).padding(.trailing, 8).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.saffron))
            }.buttonStyle(PressStyle())
        }
    }

    private func color(_ k: AgentStatus.Kind) -> Color {
        switch k { case .done: Palette.done; case .needsYou: Palette.attention; case .idle: Color(white: 0.42) }
    }
}

struct SwitcherCard: View {
    let projects: [Project]
    let selected: Int
    let shown: Bool
    let metrics: CardMetrics
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Band(metrics: metrics, left: "Parked", right: "\(projects.count) projects").reveal(shown, 0)
            VStack(spacing: 2) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        Text(String(p.name.prefix(1))).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Palette.ink)
                            .frame(width: 36, height: 36)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.tiles[i % Palette.tiles.count]))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(Typo.strong).foregroundStyle(.white)
                            Text(p.subtitle).font(Typo.bandSub).foregroundStyle(Color(white: 0.55)).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if p.needsAttention { Circle().fill(Palette.attention).frame(width: 7, height: 7) }
                        Text(p.away).font(Typo.chip).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(i == selected ? Palette.rowSelected : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { choose(i) }
                    .reveal(shown, i + 1)
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).animation(Motion.snappy, value: selected)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                hint("↑↓", "choose"); hint("return", "open"); hint("esc", "close")
            }
            .frame(maxWidth: .infinity).padding(.bottom, 20).reveal(shown, 4)
        }
    }

    private func hint(_ k: String, _ t: String) -> some View {
        HStack(spacing: 6) { Keycap(label: k); Text(t).font(Typo.chip).foregroundStyle(Palette.textTertiary) }
    }
}

struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.28, y: r.height * 0.52))
        p.addLine(to: CGPoint(x: r.width * 0.44, y: r.height * 0.68))
        p.addLine(to: CGPoint(x: r.width * 0.74, y: r.height * 0.34))
        return p
    }
}

struct RestoringCard: View {
    let project: Project
    let shown: Bool
    let metrics: CardMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Band(metrics: metrics, left: project.name, right: "one moment").reveal(shown, 0)
            Text("Picking up where you left off").font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(-0.3)
                .foregroundStyle(.white).padding(.horizontal, 28).padding(.top, 16).reveal(shown, 1)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(project.restoreSteps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Palette.done).frame(width: 22, height: 22).scaleEffect(shown ? 1 : 0.2)
                            CheckMark().trim(from: 0, to: shown ? 1 : 0)
                                .stroke(Color(red: 0.03, green: 0.16, blue: 0.08), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                                .frame(width: 22, height: 22)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(shown ? 0.45 + 0.3 * Double(i) : 0), value: shown)
                        Text(step).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Palette.textPrimary)
                            .opacity(shown ? 1 : 0).offset(x: shown ? 0 : -4)
                            .animation(.easeOut(duration: 0.3).delay(shown ? 0.45 + 0.3 * Double(i) : 0), value: shown)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 16)
        }
    }
}
