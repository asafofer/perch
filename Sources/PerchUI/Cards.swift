import SwiftUI
import PerchCore

/// Fades, lifts and un-blurs content in after the card has grown. `index` staggers siblings.
struct Reveal: ViewModifier {
    let on: Bool
    let index: Int
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 6)
            .blur(radius: on ? 0 : 4)
            .animation(on ? .spring(response: 0.44, dampingFraction: 0.88).delay(0.12 + 0.05 * Double(index))
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
            Text(left).font(Typo.title).tracking(-0.1).foregroundStyle(Palette.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 36)
            Color.clear.frame(width: metrics.gap)
            Text(right).font(Typo.meta).monospacedDigit().foregroundStyle(Palette.textSecondary).lineLimit(1)
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
            .foregroundStyle(onLight ? Palette.ink.opacity(0.8) : Color(white: 0.7))
            .frame(minWidth: 16).padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(onLight ? Palette.ink.opacity(0.12) : Color.white.opacity(0.08)))
    }
}

private struct PressStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering ? 0.08 : 0)
            .opacity(configuration.isPressed ? 0.75 : 1).scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct Hairline: View { var body: some View { Rectangle().fill(Palette.hairline).frame(height: 1) } }

struct OpenCard: View {
    let project: Project
    let shown: Bool
    let metrics: CardMetrics
    let confirm: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Band(metrics: metrics, left: project.name, right: "Back after \(project.away)").reveal(shown, 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(project.headline).font(Typo.hero).tracking(-0.5).foregroundStyle(Palette.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).reveal(shown, 1)
                Text(project.context).font(Typo.body).tracking(-0.1).foregroundStyle(Palette.textSecondary).lineSpacing(3)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 6).reveal(shown, 2)
                nextRow.padding(.top, 16).reveal(shown, 3)
            }
            .padding(.horizontal, 28).padding(.top, 14)
            Spacer(minLength: 0)
            Hairline().reveal(shown, 4)
            footer.padding(.horizontal, 28).frame(height: 56).reveal(shown, 4)
        }
    }

    private var nextRow: some View {
        HStack(spacing: 12) {
            Text("Next").font(Typo.label).foregroundStyle(Palette.textTertiary).frame(width: 34, alignment: .leading)
            Text(project.next).font(Typo.row).foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ForEach(Array(project.agents.enumerated()), id: \.offset) { _, a in
                HStack(spacing: 6) {
                    Circle().fill(color(a.kind)).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(a.text).font(Typo.chip).foregroundStyle(Color(white: 0.7)).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 9).frame(height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            }
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Text("Not now").font(Typo.button.weight(.medium)).lineLimit(1).fixedSize()
                    .foregroundStyle(Palette.textSecondary).padding(.horizontal, 10).frame(height: 30)
            }.buttonStyle(PressStyle()).accessibilityLabel("Not now")
            Button(action: confirm) {
                HStack(spacing: 8) { Text("Pick up").font(Typo.button).lineLimit(1).fixedSize(); Keycap(label: "↩", onLight: true) }
                    .foregroundStyle(Palette.ink).padding(.leading, 12).padding(.trailing, 6).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.saffron))
            }.buttonStyle(PressStyle()).accessibilityLabel("Pick up where you left off")
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
                    let tint = Palette.tiles[i % Palette.tiles.count]
                    HStack(spacing: 12) {
                        Text(String(p.name.prefix(1))).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(Typo.row).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            Text(p.subtitle).font(Typo.meta).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if p.needsAttention { Circle().fill(Palette.attention).frame(width: 6, height: 6) }
                        Text(p.away).font(Typo.meta).monospacedDigit().foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 10).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == selected ? Palette.rowSelected : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { choose(i) }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                    .reveal(shown, i + 1)
                }
            }
            .padding(.horizontal, 18).padding(.top, 10).animation(Motion.snappy, value: selected)
            Spacer(minLength: 0)
            Hairline().reveal(shown, 4)
            HStack(spacing: 18) { hint("↑↓", "Choose"); hint("↩", "Open"); hint("esc", "Close") }
                .frame(maxWidth: .infinity).frame(height: 44).reveal(shown, 4)
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
            Band(metrics: metrics, left: project.name, right: "Restoring…").reveal(shown, 0)
            Text("Picking up where you left off").font(Typo.hero).tracking(-0.5).foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 28).padding(.top, 14).reveal(shown, 1)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(project.restoreSteps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Palette.done.opacity(0.16)).frame(width: 18, height: 18).scaleEffect(shown ? 1 : 0.3)
                            CheckMark().trim(from: 0, to: shown ? 1 : 0)
                                .stroke(Palette.done, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                .frame(width: 18, height: 18)
                        }
                        .animation(.spring(response: 0.38, dampingFraction: 0.7).delay(shown ? 0.45 + 0.28 * Double(i) : 0), value: shown)
                        Text(step).font(Typo.row).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            .opacity(shown ? 1 : 0).offset(x: shown ? 0 : -4)
                            .animation(.easeOut(duration: 0.3).delay(shown ? 0.45 + 0.28 * Double(i) : 0), value: shown)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 18)
        }
    }
}
