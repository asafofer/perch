import Foundation
import PerchCore

/// What Swift tells the web UI. The UI never decides anything; it only draws this.
struct UISnapshot: Encodable {
    struct Screen: Encodable { let hasNotch: Bool; let notchW: CGFloat; let notchH: CGFloat }
    struct Status: Encodable { let kind: String; let text: String; let app: String }
    struct Step: Encodable { let icon: String; let text: String }
    /// What the agent is asking, for the card to answer: permission, question or plan.
    struct UIQuestion: Encodable { let text: String; let header: String; let multi: Bool; let options: [String]; let notes: [String] }
    struct UIAsk: Encodable { let kind: String; let title: String; let subject: String; let brief: String; let questions: [UIQuestion]; let answerable: Bool
        /// Why a question with choices cannot be answered here, for the card to say under them.
        let why: String? }
    struct UIProject: Encodable {
        let id, name: String
        let branch: String?
        let away, at, headline, context, next, topic, app: String
        let attention: Bool
        /// Changed since you last looked. Only then does a finished session glow green.
        let fresh: Bool
        /// What happened, measured against your break: "Finished 12m after you left".
        let line: String
        let status: Status
        let steps: [Step]
        let ask: UIAsk?
        /// While it works: the step it is on.
        let now: String?
        /// A terminal session: the icon of the terminal it runs in ("ghostty", "terminal").
        let via: String?
        /// The multiplexer it runs in inside that terminal: "herdr".
        let host: String?
        /// The app it opens in when that is not the agent's own: "conductor".
        let opens: String?
        /// The list's section: "Needs you", "Today" or "Earlier".
        let section: String
        /// The agent's own last message, shown while you reply.
        let said: String?
        /// Your last message, shown above it.
        let asked: String?
        /// It came after the agent's last message (not answered yet): shown below it.
        let askedLast: Bool
        /// A session started from the list, before it is a real session: "starting", "started", "failed", "gone".
        var pending: String? = nil
    }

    /// A new session: the agents to start one with, the folders to offer, what to start on, and where it was opened from.
    struct NewSession: Encodable {
        struct Model: Encodable { let id: String; let name: String; let note: String; let more: Bool }
        /// `models`: what a terminal agent can start on, its own default first (none for the apps); `model`: the one chosen last.
        struct App: Encodable { let id: String; let app: String; let via: String?; let name: String; let models: [Model]; let model: String }
        struct Folder: Encodable { let name: String; let path: String; let label: String; let away: String }
        let apps: [App]
        let projects: [Folder]
        let agent: String?
        let project: String?
        /// "list" when opened from the list (it goes back there), "anywhere" otherwise.
        let from: String
    }

    struct Character: Encodable { let shape: String; let color: String }
    struct Display: Encodable { let id: String; let name: String; let connected: Bool }
    struct Source: Encodable { let id: String; let name: String; let count: Int; let names: [String]; let enabled: Bool }
    /// A place Perch follows a session into (Conductor, herdr, tmux, cmux), shown by name and mark where it is on this Mac.
    struct Place: Encodable { let id: String; let name: String }
    struct Onboarding: Encodable {
        let step: Int
        let total: Int
        let accessibility: Bool
        let scanning: Bool
        let sources: [Source]
        let places: [Place]
        /// Only the character step, opened from Settings or the menu: no step count, and Done instead of Next.
        let only: Bool
        /// Perch's hook is in every enabled app: "on" or "off".
        let live: String
        let shortcut: ShortcutState
    }
    /// The shortcut that opens Perch, as the page draws it: the key caps, and where recording stands.
    struct ShortcutState: Encodable { let keys: [String]; let kind: String; let custom: Bool; let recording: Bool; let error: String; let tried: Bool; let saved: Bool
        /// Whether Perch can hear it: a tap needs Accessibility, a combo must not be held by another app. `why` says so in a sentence.
        let works: Bool; let why: String
        /// The keys of the last shortcut that was refused (the card keeps showing them) and how many refusals so far (each shakes them).
        let attempt: [String]; let refusals: Int
        /// Recording: the shortcut pressed so far. It saves only on Return; pressing another replaces it.
        let pending: [String]
        /// How many shortcuts were chosen in this recording, so choosing the same one again still counts as new.
        let picks: Int
        /// Which shortcut this is: "open" (opens Perch) or "new" (starts a new session).
        var which = "open" }
    /// New session's shortcut, as Settings shows it.
    struct NewShortcut: Encodable { let keys: [String]; let custom: Bool }

    /// `live`: "on" when every enabled app has Perch's hook, "off" otherwise.
    struct Settings: Encodable { let sources: [Source]; let places: [Place]; let accessibility: Bool; let idleMinutes: Int; let questionSeconds: Int; let login: Bool; let live: String
        /// A display without a notch is connected, and whether hovering its top edge opens Perch there.
        let hasExternal: Bool; let hoverExternal: Bool
        /// Show Perch on: "mouse", "window" or a display's id, and the displays to choose from (a chosen one that is not
        /// connected stays listed, greyed).
        let showOn: String; let displays: [Display]
        let shortcut: ShortcutState
        var newShortcut: NewShortcut? = nil
        /// Perch had Accessibility before: the row says needs access again.
        var accessWas = false
        /// It came from the card or the list, so Esc goes back there.
        var back = false }
    var newSession: NewSession?

    /// A question Perch shows but cannot answer says why: Live status is off (so Settings is the way), or it is answered in the app.
    static func why(_ a: Ask) -> String? {
        guard a.kind == .question, !a.answerable, a.questions.contains(where: { !$0.options.isEmpty }) else { return nil }
        let agent = Agent.of(a.agent)
        return agent.answersFromNotch && !HookInstaller.isInstalled(a.agent) ? "Perch can't answer this one. Turn on Live status in Settings." : "Answer in \(agent.short)."
    }

    /// How long an unanswered question stays as wings in the notch, after its first nine seconds in full.
    let questionSeconds = Prefs.questionSeconds
    /// The kinds of live activity the notch does not announce (Settings, Notify me about); the page filters its live activity by them.
    let notifyOff = Prefs.notifyOff.sorted()
    let phase: String
    let settings: Settings?
    let character: Character
    let onboarding: Onboarding?
    var selected: Int
    let autoCollapse: Bool
    let timerToken: Int
    let screen: Screen
    var projects: [UIProject]
    /// Real app icons as data URLs. Sent once, with the first snapshot.
    let icons: [String: String]?
    /// The session you are in right now. It never nudges you about itself.
    let activeId: String?
    /// The sessions you are in or may be in, when Perch cannot tell which of an app's sessions is in front: none of them is nudged.
    let activeIds: [String]
    /// The first scan is still running, so an empty list means "looking", not "nothing".
    let scanning: Bool
    /// Perch can type a reply for you (Accessibility). Without it, Send asks for it first.
    let canSend: Bool
    /// Send asked for Accessibility and holds the reply until it is on.
    var allowing = false
    /// Replies typed and not sent, by project id: the reply field opens with them.
    var drafts: [String: String] = [:]
    /// Perch opened the card by itself (you came back, or a Not now came due): it offers Not now, not the Up and Down hint.
    var proactive = false
    /// What you typed in the list, and the rows that match it (all of them when nil).
    var query = ""
    var shown: [Int]?
    /// On a call, on camera or presenting: the notch keeps what arrives to small wings.
    var quiet = false
    /// An update of Perch itself: checking, offered, downloading, restarting, updated.
    var update: UpdateInfo?
    /// The first start after an update: what is new (phase "whatsnew").
    var whatsNew: WhatsNewCard?
    struct WhatsNewCard: Encodable { let version: String; let headline: String; let bullets: [String]
        /// The update lost Accessibility Perch had: lost, asked (Allow pressed) or granted. The card says so with Allow.
        var access: String? = nil }
    /// Accessibility Perch had, gone (AccessLoss): the notch row's phase (lost, asked, granted), whether an update brought it
    /// about, and which loss it is, so the page tells a new one from one it put away. Only at rest, once per loss.
    var access: AccessRow?
    struct AccessRow: Encodable { let phase: String; let afterUpdate: Bool; let since: Int }
    /// This build can look for updates, so Settings offers it.
    var canUpdate = false
    /// The version and build, "0.1.0 (198)", shown small at the foot of the list.
    /// "branch @ commit" on a test build; the page says so beside the notch.
    var testBuild: String? = TestBuild.label
    /// PERCH_NOTCH_GUIDE=1 paints the resting notch magenta at the full size the system reports; =2 paints the shape Perch really draws.
    /// Either way any overhang past the hardware shows.
    var guide: String? = ProcessInfo.processInfo.environment["PERCH_NOTCH_GUIDE"]
    /// The macOS this is, "26.1": Send feedback says it goes along, when you let it.
    var macOS: String = UISnapshot.macOSVersion
    var version: String? = UISnapshot.appVersion
    static let macOSVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
    }()
    static let appVersion: String? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return nil }
        return (info["CFBundleVersion"] as? String).map { "\(short) (\($0))" } ?? short
    }()

    init(machine: NotchMachine, projects: [Project], screen: ScreenInfo, timerToken: Int, icons: [String: String]? = nil, allowAutoCollapse: Bool = true, activeId: String? = nil, activeIds: [String] = [], scanning: Bool = false, canSend: Bool = true, fresh: Set<String> = [], lines: [String: String] = [:], onboarding: Onboarding? = nil, settings: Settings? = nil) {
        self.onboarding = onboarding; self.settings = settings
        // PERCH_CHARACTER="shape,#colour" picks the character for screenshots without touching your settings.
        let pick = ProcessInfo.processInfo.environment["PERCH_CHARACTER"]?.split(separator: ",").map(String.init)
        character = pick?.count == 2 ? Character(shape: pick![0], color: pick![1]) : Character(shape: Prefs.shape, color: Prefs.color)
        self.icons = icons; self.activeId = activeId; self.activeIds = activeIds; self.scanning = scanning; self.canSend = canSend
        phase = switch machine.phase { case .idle: "idle"; case .open: "open"; case .switcher: "switcher"; case .restoring: "restoring"; case .onboarding: "onboarding"; case .settings: "settings"; case .whatsNew: "whatsnew"; case .newSession: "newSession" }
        selected = machine.selected
        autoCollapse = machine.autoCollapses && allowAutoCollapse
        self.timerToken = timerToken
        self.screen = Screen(hasNotch: screen.notchSize != nil, notchW: screen.notchSize?.width ?? 0, notchH: screen.notchSize?.height ?? NotchGeometry.idleSize(for: screen).height)
        let now = Date()
        self.projects = projects.map { p in
            UIProject(id: p.id, name: p.name, branch: p.branch, away: p.away, at: p.at, headline: p.headline,
                      context: p.context, next: p.next, topic: p.topic, app: p.app, attention: p.needsAttention,
                      fresh: fresh.contains(p.id), line: lines[p.id] ?? "",
                      status: Status(kind: p.status.kind, text: p.status.text, app: p.status.app),
                      steps: p.steps.map { Step(icon: $0.icon, text: $0.text) },
                      ask: p.ask.map { UIAsk(kind: $0.kind.rawValue, title: $0.title, subject: $0.subject, brief: $0.brief,
                                                 questions: $0.questions.map { UIQuestion(text: $0.text, header: $0.header, multi: $0.multiSelect, options: $0.options, notes: $0.notes) },
                                                 answerable: $0.answerable, why: Self.why($0)) },
                      now: p.now, via: p.terminal ? p.via.flatMap { Terminals.keys[$0] } ?? "terminal" : nil, host: p.host, opens: p.conductor == nil ? nil : "conductor",
                      section: ListFilter.section(p, now: now).rawValue, said: p.said, asked: p.asked, askedLast: p.askedLast)
        }
    }
}

/// Set by scripts/run.sh on any build that is not a release: "branch @ commit", "+" when it has uncommitted changes.
enum TestBuild {
    static let label: String? = Bundle.main.infoDictionary?["PerchTestBuild"] as? String
}
