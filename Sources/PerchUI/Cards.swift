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
            .animation(on ? .spring(response: 0.5, dampingFraction: 0.86).delay(0.16 + 0.06 * Double(index))
                          : .easeOut(duration: 0.12), value: on)
    }
}
extension View { func reveal(_ on: Bool, _ index: Int = 0) -> some View { modifier(Reveal(on: on, index: index)) } }

struct Keycap: View {
    let label: String
    var body: some View {
        Text(label).font(Typo.key).foregroundStyle(Color(white: 0.83))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.keycap))
            .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.2)).frame(height: 1).padding(.horizontal, 3).offset(y: 1) }
    }
}

struct KeyHint: View {
    let key: String, text: String
    var body: some View {
        HStack(spacing: 6) { Keycap(label: key); Text(text).font(Typo.small).foregroundStyle(Palette.textTertiary) }
    }
}

struct CardHeader: View {
    let title: String, subtitle: String, branch: String?
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typo.title).foregroundStyle(.white).tracking(-0.2)
                Text(subtitle).font(Typo.sub).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            if let branch {
                Text("⎇ \(branch)").font(Typo.mono).foregroundStyle(Color(white: 0.7))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.115)))
            }
        }
        .padding(.leading, 66).padding(.top, 22)
    }
}

struct OpenCard: View {
    let project: Project
    let shown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: project.name, subtitle: "Back after \(project.away)", branch: project.branch)
                .reveal(shown, 0)
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 11) {
                row("GOAL", project.goal, 1)
                row("DECIDED", project.decided, 2)
                row("NEXT", project.next, 3)
            }
            .padding(.top, 14)
            HStack(spacing: 18) {
                ForEach(Array(project.agents.enumerated()), id: \.offset) { _, a in
                    HStack(spacing: 7) {
                        Circle().fill(color(a.kind)).frame(width: 7, height: 7)
                        Text(a.text).font(Typo.small).foregroundStyle(Color(white: 0.72))
                    }
                }
            }
            .padding(.top, 13).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 1) }
            .padding(.top, 14)
            .reveal(shown, 4)
            Spacer(minLength: 0)
            HStack(spacing: 16) {
                KeyHint(key: "Return", text: "Restore"); KeyHint(key: "Tab", text: "Next project"); KeyHint(key: "Esc", text: "Dismiss")
            }
            .padding(.bottom, 16).reveal(shown, 5)
        }
        .padding(.horizontal, 28)
    }

    private func row(_ label: String, _ text: String, _ i: Int) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).font(Typo.label).tracking(1).foregroundStyle(Palette.textTertiary).frame(width: 70, alignment: .leading)
            Text(text).font(Typo.body).foregroundStyle(Palette.textPrimary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .reveal(shown, i)
    }

    private func color(_ k: AgentStatus.Kind) -> Color {
        switch k { case .done: Palette.done; case .needsYou: Palette.attention; case .idle: Color(white: 0.42) }
    }
}

struct SwitcherCard: View {
    let projects: [Project]
    let selected: Int
    let shown: Bool
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Parked projects").font(Typo.title).foregroundStyle(.white).tracking(-0.2)
                Text("Arrow keys to choose").font(Typo.sub).foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 66).padding(.top, 22).reveal(shown, 0)
            VStack(spacing: 3) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(.white)
                            Text(p.goal).font(Typo.small).foregroundStyle(Palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if p.needsAttention { Circle().fill(Palette.attention).frame(width: 7, height: 7) }
                        Text("\(p.away) ago").font(Typo.small).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(i == selected ? Palette.rowSelected : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { choose(i) }
                    .reveal(shown, i + 1)
                }
            }
            .padding(.top, 14).animation(Motion.snappy, value: selected)
            Spacer(minLength: 0)
            HStack(spacing: 16) { KeyHint(key: "Return", text: "Open"); KeyHint(key: "Esc", text: "Close") }
                .padding(.bottom, 16).reveal(shown, 4)
        }
        .padding(.horizontal, 22)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Setting up \(project.name)").font(Typo.title).foregroundStyle(.white).tracking(-0.2)
                Text("One moment").font(Typo.sub).foregroundStyle(Palette.textSecondary)
            }
            .padding(.leading, 66).padding(.top, 22)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(project.restoreSteps.enumerated()), id: \.offset) { i, step in
                    HStack(spacing: 11) {
                        ZStack {
                            Circle().fill(Palette.done).frame(width: 18, height: 18)
                                .scaleEffect(shown ? 1 : 0.2)
                            CheckMark().trim(from: 0, to: shown ? 1 : 0)
                                .stroke(Color(red: 0.03, green: 0.13, blue: 0.06), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 18, height: 18)
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(shown ? 0.5 + 0.3 * Double(i) : 0), value: shown)
                        Text(step).font(Typo.body).foregroundStyle(Palette.textPrimary)
                            .opacity(shown ? 1 : 0)
                            .animation(.easeOut(duration: 0.3).delay(shown ? 0.5 + 0.3 * Double(i) : 0), value: shown)
                    }
                }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
    }
}
