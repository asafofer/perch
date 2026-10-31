// Films a page frame by frame on a virtual clock (scripts/vclock.js), so every transition is rendered exactly, at 60 fps,
// however long each frame takes to draw: timers, frames and CSS animations all move on time this sets, one frame at a time.
// Headless, as record-design.swift: a borderless panel beyond every screen, occlusion detection off (WebKit SPI).
// Usage: swift scripts/film-design.swift <url> <frames dir> <seconds> <width> <height> [<out w px> <out h px>]   (points)
// Without an output size each frame is the whole page at the screen's scale. With one, CAM moves a camera over the page and
// each frame is the camera's view at that size, drawn by WebKit at that zoom (sharp, however close): CAM is a list of
// time:width:target[:ease], seconds, how many points wide the view is, and what it looks at, n (the notch: the view's top on
// the page's top, centred) or cr (the character's middle), with how it comes into that key (io by default, out, in).
// Zoom moves on a log scale and the view drifts toward its target as it closes in, so a push of 50x still feels even.
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 6, let url = URL(string: args[1]), let seconds = Double(args[3]), let w = Double(args[4]), let h = Double(args[5]) else {
    FileHandle.standardError.write("usage: film-design.swift <url> <dir> <seconds> <width> <height> [<out w> <out h>]\n".data(using: .utf8)!); exit(2)
}
let out: NSSize? = args.count >= 8 ? NSSize(width: Double(args[6]) ?? 0, height: Double(args[7]) ?? 0) : nil
guard let clockJS = (try? String(contentsOfFile: (args[0] as NSString).deletingLastPathComponent + "/vclock.js", encoding: .utf8))
    ?? (try? String(contentsOfFile: "scripts/vclock.js", encoding: .utf8)) else { FileHandle.standardError.write("no scripts/vclock.js\n".data(using: .utf8)!); exit(1) }

struct Key { let t: Double, w: Double, target: String, ease: String }
let keys: [Key] = (ProcessInfo.processInfo.environment["CAM"] ?? "").split(separator: " ").compactMap { k in
    let f = k.split(separator: ":").map(String.init)
    guard f.count >= 3, let t = Double(f[0]), let w = Double(f[1]) else { return nil }
    return Key(t: t, w: w, target: f[2], ease: f.count > 3 ? f[3] : "io")
}

func eased(_ p: Double, _ kind: String) -> Double {
    switch kind {
    case "out": return 1 - pow(1 - p, 4)
    case "in": return pow(p, 3)
    default: return p < 0.5 ? 4 * p * p * p : 1 - pow(2 - 2 * p, 3) / 2
    }
}

final class Filmer: NSObject, WKNavigationDelegate {
    let panel: NSPanel, web: WKWebView
    let queue = DispatchQueue(label: "film.encode", attributes: .concurrent), group = DispatchGroup()
    let dir: String, frames: Int, fps = Double(ProcessInfo.processInfo.environment["FPS"] ?? "") ?? 60   // FPS=180: three frames to each of a 60 fps film, for motion blur
    var started = false, z = 1.0, notch = NSPoint.zero

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

    // where a target is, for a view this wide: the notch holds the view's top on the page's top
    func point(_ target: String, _ vw: Double, _ cr: NSPoint, _ o: NSSize) -> NSPoint {
        // cr+N: N points right of the character, so a close-up keeps the row's words beside it
        target.hasPrefix("cr") ? NSPoint(x: cr.x + (Double(target.dropFirst(3)) ?? 0) * z, y: cr.y)
            : NSPoint(x: notch.x + (Double(target.dropFirst(1)) ?? 0) * z, y: notch.y + vw * o.height / o.width / 2)   // n-N: N points left of the notch's middle
    }

    // the camera's view at a time, in page points
    func view(_ t: Double, _ cr: NSPoint, _ o: NSSize) -> NSRect {
        let keys = keys.map { Key(t: $0.t, w: $0.w * z, target: $0.target, ease: $0.ease) }
        var vw = keys[0].w, c = point(keys[0].target, vw, cr, o)
        if let i = keys.lastIndex(where: { $0.t <= t }) {
            let a = keys[i]
            vw = a.w; c = point(a.target, vw, cr, o)
            if i + 1 < keys.count {
                let b = keys[i + 1], p = eased(min(max((t - a.t) / (b.t - a.t), 0), 1), b.ease)
                vw = a.w * pow(b.w / a.w, p)
                // drift toward the target as the view closes in, so the point zoomed into stays put
                let u = a.w == b.w ? p : (a.w - vw) / (a.w - b.w)
                let pa = point(a.target, vw, cr, o), pb = point(b.target, vw, cr, o)
                c = NSPoint(x: pa.x + (pb.x - pa.x) * u, y: pa.y + (pb.y - pa.y) * u)
            }
        }
        let vh = vw * o.height / o.width
        return NSRect(x: c.x - vw / 2, y: max(notch.y, c.y - vh / 2), width: vw, height: vh)
    }

    func frame(_ i: Int) {
        guard i < frames else { group.notify(queue: .main) { exit(0) }; return }
        let ms = Double(i) * 1000 / fps
        // where the character and the notch are, the camera off; with the desk zoomed (design.html's &zoom=) in its points
        let js = """
            document.documentElement.style.transform = ''; __vt.to(\(ms));
            var z = parseFloat(document.querySelector('.desk').style.zoom) || 1, c = document.querySelector('.cr').getBoundingClientRect(), n = document.querySelector('.n').getBoundingClientRect();
            [c.left + c.width / 2, c.top + c.height / 2, n.left + n.width / 2, n.top, z]
            """
        web.evaluateJavaScript(js) { res, err in
            if let err { FileHandle.standardError.write("frame \(i): \(err)\n".data(using: .utf8)!) }
            guard let o = out, !keys.isEmpty, let p = res as? [Double], p.count == 5 else {
                let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(self.web.bounds.width))
                return self.shoot(i, cfg)
            }
            // the camera is a transform on the page, scaling the zoomed desk back down (or less, for a close-up)
            self.z = p[4]; self.notch = NSPoint(x: p[2], y: p[3])
            let v = self.view(ms / 1000, NSPoint(x: p[0], y: p[1]), o)
            let tw = min(self.web.bounds.width, self.web.bounds.height * o.width / o.height), th = tw * o.height / o.width, k = tw / v.width
            let t = "document.documentElement.style.transformOrigin = '0 0'; document.documentElement.style.transform = 'translate(\(-v.minX * k)px, \(-v.minY * k)px) scale(\(k))'; 0"
            self.web.evaluateJavaScript(t) { _, _ in
                let cfg = WKSnapshotConfiguration()
                cfg.rect = NSRect(x: 0, y: 0, width: tw, height: th)
                cfg.snapshotWidth = NSNumber(value: Double(o.width) / Double(self.panel.backingScaleFactor))
                self.shoot(i, cfg)
            }
        }
    }

    func shoot(_ i: Int, _ cfg: WKSnapshotConfiguration) {
        web.takeSnapshot(with: cfg) { image, _ in
            if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let path = String(format: "%@/f%05d.png", self.dir, i + 1)
                self.group.enter()
                self.queue.async { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)); self.group.leave() }
            }
            self.frame(i + 1)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
try? FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
let filmer = Filmer(size: NSSize(width: w, height: h), dir: args[2], seconds: seconds, clock: clockJS)
filmer.web.load(URLRequest(url: url))
app.run()
