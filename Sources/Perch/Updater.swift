import AppKit
import PerchCore
import Sparkle

/// What the page draws of an update: the phase (checking, available, downloading, ready, restarting, updated, current, failed),
/// how far the download is, and what the release says about itself.
struct UpdateInfo: Encodable, Equatable {
    var version: String
    var phase: String
    var progress = 0.0
    var notes = ""
    var bullets: [String] = []
    /// Counts up to say an offer again (Check for updates while one waits): the page treats it as new.
    var nudge = 0
    /// A failed update (phase "failed"): one line for the notch, a few words for Settings, what you can do (retry, move, none), and
    /// whether it was looking ("check") or getting one in ("update").
    var problem = ""
    var short = ""
    var fix = ""
    var during = ""
}

/// Keeps a released Perch up to date with Sparkle, with Perch's own face instead of Sparkle's windows: the notch says what is
/// happening (ui/app.js, "an update of Perch itself"). A check on a schedule that finds a new version downloads it and restarts
/// at a quiet moment; one you asked for (Check for updates) offers it first. The update is signed with Perch's own key
/// (SUPublicEDKey), so it needs no Apple notarization. Test builds never update themselves.
@MainActor
final class Updater: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    private var updater: SPUUpdater?
    private var offer: ((SPUUserUpdateChoice) -> Void)?      // an update you can take or leave
    private var relaunch: ((SPUUserUpdateChoice) -> Void)?   // downloaded, waiting for a quiet moment to restart
    private var expected: UInt64 = 0, received: UInt64 = 0
    private var quietTimer: Timer?, clearTimer: Timer?, quitTimer: Timer?
    private var retryQuit: (() -> Void)?                     // Sparkle's way to ask Perch to quit again
    private var demoTask: Task<Void, Never>?

    /// The state for the page, nil when there is nothing to say.
    private(set) var info: UpdateInfo? { didSet { if info != oldValue { onChange(info) } } }
    var onChange: (UpdateInfo?) -> Void = { _ in }
    /// Asked before a downloaded update restarts Perch: true when nothing is on screen and no reply is half written.
    var isQuiet: () -> Bool = { true }

    private var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// This build can look for updates (a release; a test build cannot).
    var canCheck: Bool { updater != nil || demoTask != nil }

    /// The menu's "Check for updates…", nil on a build that does not update.
    var checkItem: NSMenuItem? {
        guard updater != nil || demoTask != nil else { return nil }
        let item = NSMenuItem(title: "Check for updates…", action: #selector(check), keyEquivalent: "")
        item.target = self
        return item
    }

    func start() {
        guard updater == nil, TestBuild.label == nil else { return }
        let u = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do { try u.start() } catch { NSLog("Perch updates: \(error.localizedDescription)"); return }
        updater = u
        announceUpdated()
    }

    @objc func check() {
        // The demo has no Sparkle: a check just says you are up to date.
        if updater == nil, demoTask != nil, info == nil || info?.phase == "current" {
            info = UpdateInfo(version: shortVersion, phase: "checking")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard self?.info?.phase == "checking" else { return }
                self?.info = UpdateInfo(version: self?.shortVersion ?? "", phase: "current"); self?.clear(after: 5)
            }
            return
        }
        guard let updater else { return }
        // Already on it: say so rather than doing nothing.
        switch info?.phase {
        case "available": info?.nudge += 1; return   // the offer is still there: say it again
        case "ready": restartNow(); return
        case "downloading", "restarting", "checking": return
        default: break
        }
        clearTimer?.invalidate(); info = nil
        updater.checkForUpdates()
    }

    /// What the page's buttons do: Update, Later, Restart to update.
    func handle(_ action: String) {
        switch action {
        case "install": if let offer { self.offer = nil; offer(.install) }
        case "later": if let offer { self.offer = nil; offer(.dismiss) }; if ["available", "failed"].contains(info?.phase ?? "") { clearTimer?.invalidate(); info = nil }
        case "retry": retry()
        case "reveal": revealApp()
        case "restart": if relaunch == nil, updater == nil, demoTask != nil { demoRestart() } else { restartNow() }
        case "check": check()
        default: break
        }
    }

    /// Back on a newer build than the last run: a small row says so, and goes.
    private func announceUpdated() {
        let key = "lastRunBuild", build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let was = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(build, forKey: key)
        guard let was, was != build else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.info == nil else { return }
            self.info = UpdateInfo(version: self.shortVersion, phase: "updated"); self.clear(after: 8)
        }
    }

    private func clear(after seconds: TimeInterval) {
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if ["current", "failed", "updated"].contains(self?.info?.phase ?? "") { self?.info = nil } }
        }
    }

    /// Downloaded: restart at the first quiet moment, or when you press Restart.
    private func waitForQuiet() {
        quietTimer?.invalidate()
        quietTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isQuiet() == true { self?.restartNow() } }
        }
    }

    private func restartNow() {
        quietTimer?.invalidate()
        guard let go = relaunch else { return }
        relaunch = nil
        info?.phase = "restarting"
        // The notch says Updating for a moment before Perch goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { go(.install) }
        // Perch goes within a moment. Still here after this long: something is holding it back from quitting.
        quitTimer?.invalidate()
        quitTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if self?.info?.phase == "restarting" { self?.fail(.couldNotQuit) } }
        }
    }

    /// Say what went wrong: the row in the notch, the words in Settings. It stays a while, then goes.
    private func fail(_ p: UpdateProblem) {
        offer = nil; relaunch = nil; quietTimer?.invalidate(); quitTimer?.invalidate()
        let v = info?.version.isEmpty == false ? info!.version : shortVersion
        info = UpdateInfo(version: v, phase: "failed", problem: p.line, short: p.short, fix: p.fix.rawValue, during: p.during)
        clear(after: 120)
    }

    /// Try again: ask Perch to quit once more when that is what failed, else look for the update again.
    private func retry() {
        if let retryQuit, info?.short == UpdateProblem.couldNotQuit.short {
            self.retryQuit = nil
            clearTimer?.invalidate(); info = UpdateInfo(version: info?.version ?? shortVersion, phase: "restarting")
            quitTimer?.invalidate()
            quitTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { if self?.info?.phase == "restarting" { self?.fail(.couldNotQuit) } }
            }
            retryQuit()
        } else { check() }
    }

    /// Show Perch.app in Finder, where it was unzipped: macOS runs a downloaded app from a read-only copy, and the original is what moves.
    private func revealApp() {
        var url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/"), let original = Self.originalURL(of: url) { url = original }
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) }
    }

    /// Security's own answer to where a translocated app came from (the call is not in a header, so it is looked up).
    private static func originalURL(of url: URL) -> URL? {
        guard let h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(h, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let f = unsafeBitCast(sym, to: Fn.self)
        return f(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    // MARK: SPUUpdaterDelegate

    /// A different address on every check: GitHub keeps the feed in a cache for up to five minutes, and a new address goes past it,
    /// so a release is there the moment it is published. The server ignores the extra part.
    nonisolated func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] {
        [["key": "t", "value": String(Int(Date().timeIntervalSince1970)), "displayKey": "t", "displayValue": ""]]
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        info = UpdateInfo(version: shortVersion, phase: "checking")
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let notes = UpdateNotes.parse(appcastItem.itemDescription)
        let version = appcastItem.displayVersionString
        if state.userInitiated, state.stage == .notDownloaded {
            offer = reply
            info = UpdateInfo(version: version, phase: "available", notes: notes.headline, bullets: notes.bullets)
        } else {
            reply(.install)
            info = UpdateInfo(version: version, phase: "downloading", notes: notes.headline, bullets: notes.bullets)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if info?.phase == "checking" {
            // "Up to date" is only true when it is: an Intel Mac, or a macOS too old, is told the newer version is not for it.
            let ns = error as NSError
            let reason = (ns.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue ?? 0
            let item = ns.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem
            if let p = UpdateProblem.noUpdate(reason: reason, minimumOS: item?.minimumSystemVersion) { fail(p) }
            else { info = UpdateInfo(version: shortVersion, phase: "current"); clear(after: 5) }
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        NSLog("Perch updates: \(error.localizedDescription)")
        // A check you asked for, or an update you were told about, says why it did not go through. A failed check on a schedule
        // (offline at night) is none of your business.
        let phase = info?.phase ?? ""
        if phase == "checking" || ["available", "downloading", "ready", "restarting"].contains(phase) {
            var chain: [UpdateProblem.ErrorRef] = [], e: NSError? = error as NSError
            while let x = e, chain.count < 6 { chain.append(.init(domain: x.domain, code: x.code)); e = x.userInfo[NSUnderlyingErrorKey] as? NSError }
            fail(UpdateProblem.classify(chain, updating: phase != "checking"))
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expected = 0; received = 0
        info = UpdateInfo(version: info?.version ?? "", phase: "downloading", notes: info?.notes ?? "", bullets: info?.bullets ?? [])
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        guard expected > 0, var i = info, i.phase == "downloading" else { return }
        let p = min(1, Double(received) / Double(expected))
        if p - i.progress >= 0.01 || p == 1 { i.progress = p; info = i }
    }

    func showDownloadDidStartExtractingUpdate() { if var i = info, i.phase == "downloading" { i.progress = 1; info = i } }
    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        relaunch = reply
        if info == nil { info = UpdateInfo(version: "", phase: "ready") }
        info?.phase = "ready"
        // Nothing open: restart now, so the notch goes straight from downloading to updating. Otherwise at the first quiet moment.
        if isQuiet() { restartNow() } else { waitForQuiet() }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        retryQuit = retryTerminatingApplication
        info?.phase = "restarting"
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }

    func dismissUpdateInstallation() {
        offer = nil
        if !["current", "failed", "updated", "restarting", "ready"].contains(info?.phase ?? "") { info = nil }
    }

    // MARK: --update-demo

    /// Restart in the demo: what the real one does after the click, without quitting anything.
    private func demoRestart() {
        let v = info?.version ?? "0.3.1"
        demoTask?.cancel()
        demoTask = Task { @MainActor [weak self] in
            func wait(_ s: Double) async -> Bool { try? await Task.sleep(for: .seconds(s)); return !Task.isCancelled }
            guard let self else { return }
            self.info = UpdateInfo(version: v, phase: "restarting"); guard await wait(2.4) else { return }
            self.info = nil; guard await wait(1.4) else { return }
            self.info = UpdateInfo(version: v, phase: "updated"); guard await wait(6) else { return }
            self.info = nil
        }
    }

    /// Plays an update over the real notch, with no Sparkle and nothing downloaded: checking, offered, downloading, restarting, updated.
    func demo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor [weak self] in
            func wait(_ s: Double) async -> Bool { try? await Task.sleep(for: .seconds(s)); return !Task.isCancelled }
            guard let self else { return }
            let v = "0.3.1", notes = UpdateNotes(headline: "Record your own shortcut to open Perch", bullets: ["Record your own shortcut to open Perch", "Shortcuts work on non-Latin keyboard layouts", "A notch that fits the hardware, on every display"])
            guard await wait(2) else { return }
            self.info = UpdateInfo(version: self.shortVersion, phase: "checking"); guard await wait(1.8) else { return }
            self.info = UpdateInfo(version: v, phase: "available", notes: notes.headline, bullets: notes.bullets); guard await wait(7) else { return }
            for k in 0...24 { self.info = UpdateInfo(version: v, phase: "downloading", progress: Double(k) / 24); guard await wait(0.4) else { return } }
            self.info = UpdateInfo(version: v, phase: "restarting"); guard await wait(2.4) else { return }
            self.info = nil; guard await wait(1.4) else { return }
            self.info = UpdateInfo(version: v, phase: "updated"); guard await wait(6) else { return }
            self.info = nil
            guard await wait(1) else { return }
            self.info = UpdateInfo(version: v, phase: "ready")   // and the chip, for as long as you are in the list
        }
    }
}
