// Films a page frame by frame on a virtual clock (scripts/vclock.js), so every transition is rendered exactly, at 60 fps,
// however long each frame takes to draw: timers, frames and CSS animations all move on time this sets, one frame at a time.
// Headless, as record-design.swift: a borderless panel beyond every screen, occlusion detection off (WebKit SPI).
// Usage: swift scripts/film-design.swift <url> <frames dir> <seconds> <width> <height>   (points; frames come at the screen's scale)
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 6, let url = URL(string: args[1]), let seconds = Double(args[3]), let w = Double(args[4]), let h = Double(args[5]) else {
    FileHandle.standardError.write("usage: film-design.swift <url> <dir> <seconds> <width> <height>\n".data(using: .utf8)!); exit(2)
}
guard let clockJS = (try? String(contentsOfFile: (args[0] as NSString).deletingLastPathComponent + "/vclock.js", encoding: .utf8))
    ?? (try? String(contentsOfFile: "scripts/vclock.js", encoding: .utf8)) else { FileHandle.standardError.write("no scripts/vclock.js\n".data(using: .utf8)!); exit(1) }

final class Filmer: NSObject, WKNavigationDelegate {
    let panel: NSPanel, web: WKWebView
    let queue = DispatchQueue(label: "film.encode", attributes: .concurrent), group = DispatchGroup()
    let dir: String, frames: Int, fps = 60.0
    var started = false

    init(size: NSSize, dir: String, seconds: Double, clock: String) {
        self.dir = dir; frames = Int((seconds * fps).rounded())
        let all = NSScreen.screens.map(\.frame).reduce(NSRect.zero) { $0.union($1) }
        panel = NSPanel(contentRect: NSRect(x: all.maxX + 1000, y: all.maxY + 1000, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(source: clock, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard web.responds(to: occlusion) else { FileHandle.standardError.write("WebKit can no longer film off screen\n".data(using: .utf8)!); exit(1) }
        typealias SetBool = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(web.method(for: occlusion), to: SetBool.self)(web, occlusion, false)
        super.init()
        web.navigationDelegate = self
        panel.contentView = web
        panel.orderFrontRegardless()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !started else { return }
        started = true
        // the wallpaper and fonts load on the wall clock; the page's own time stays at 0 meanwhile
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.web.evaluateJavaScript("window.__noReducedMotion && __noReducedMotion()") { _, _ in self.frame(0) }
        }
    }

    func frame(_ i: Int) {
        guard i < frames else { group.notify(queue: .main) { exit(0) }; return }
        let ms = Double(i) * 1000 / fps
        web.evaluateJavaScript("__vt.to(\(ms)); 0") { _, err in
            if let err { FileHandle.standardError.write("frame \(i): \(err)\n".data(using: .utf8)!) }
            let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(self.web.bounds.width))
            self.web.takeSnapshot(with: cfg) { image, _ in
                if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let path = String(format: "%@/f%05d.png", self.dir, i + 1)
                    self.group.enter()
                    self.queue.async { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)); self.group.leave() }
                }
                self.frame(i + 1)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
let filmer = Filmer(size: NSSize(width: w, height: h), dir: args[2], seconds: seconds, clock: clockJS)
filmer.web.load(URLRequest(url: url))
app.run()
