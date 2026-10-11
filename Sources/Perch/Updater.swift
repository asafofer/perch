import AppKit
import Sparkle

/// Keeps a released Perch up to date with Sparkle: checks once a day, downloads in the background and installs without asking.
/// The update is signed with Perch's own key (SUPublicEDKey), so it needs no Apple notarization. Test builds never update themselves.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    private var driver: SPUStandardUpdaterController?
    private var install: (() -> Void)?
    private var timer: Timer?
    /// Asked before a downloaded update restarts Perch: true when nothing is on screen and no reply is half written.
    var isQuiet: () -> Bool = { true }

    /// The menu's "Check for updates…", nil on a build that does not update.
    var checkItem: NSMenuItem? {
        guard let driver else { return nil }
        let item = NSMenuItem(title: "Check for updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = driver
        return item
    }

    func start() {
        guard driver == nil, TestBuild.label == nil else { return }
        driver = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    // A downloaded update waits for Perch to quit. Perch seldom does, so restart it ourselves, but only at a quiet moment.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            install = immediateInstallHandler
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let go = self.install, self.isQuiet() else { return }
                    self.timer?.invalidate(); self.install = nil
                    go()
                }
            }
        }
        return true
    }
}
