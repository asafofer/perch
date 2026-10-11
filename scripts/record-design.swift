// Films a page (the design page's ?record mode) as numbered PNG frames, for scripts/record.sh.
// Headless: a borderless panel placed beyond every screen, so nothing shows and the keyboard is never taken. WebKit stops
// drawing a window it thinks is hidden, so occlusion detection is turned off (WebKit SPI); without it frames freeze.
// Usage: swift scripts/record-design.swift <url> <frames dir> <seconds> <width> <height>
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 6, let url = URL(string: args[1]), let seconds = Double(args[3]), let w = Double(args[4]), let h = Double(args[5]) else {
    FileHandle.standardError.write("usage: record-design.swift <url> <dir> <seconds> <width> <height>\n".data(using: .utf8)!); exit(2)
}

final class Recorder: NSObject, WKNavigationDelegate {
    let panel: NSPanel, web: WKWebView
    let queue = DispatchQueue(label: "record.encode")
    let dir: String, seconds: Double, fps = 20.0
    var n = 0, started = false

    init(size: NSSize, dir: String, seconds: Double) {
        self.dir = dir; self.seconds = seconds
        let all = NSScreen.screens.map(\.frame).reduce(NSRect.zero) { $0.union($1) }
        panel = NSPanel(contentRect: NSRect(x: all.maxX + 1000, y: all.maxY + 1000, width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        web = WKWebView(frame: NSRect(origin: .zero, size: size))
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
        let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(web.bounds.width))   // points: the image comes at the screen's scale
        let timer = Timer(timeInterval: 1 / fps, repeats: true) { [unowned self] _ in
            n += 1
            let path = String(format: "%@/f%05d.png", dir, n)
            web.takeSnapshot(with: cfg) { image, _ in
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                self.queue.async { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            timer.invalidate()
            self.queue.async { DispatchQueue.main.async { exit(0) } }   // after the last frame is written
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
let recorder = Recorder(size: NSSize(width: w, height: h), dir: args[2], seconds: seconds)
recorder.web.load(URLRequest(url: url))
app.run()
