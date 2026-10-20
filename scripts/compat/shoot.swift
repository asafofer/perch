// Films design-page scenarios in this Mac's own WebKit, a few frames each, so two macOS versions can be compared.
// swift scripts/compat/shoot.swift <base url of ui/> <out dir> <scenario>...   (scenario as in pr-demo.sh: Group/Name)
import AppKit
import WebKit

let args = CommandLine.arguments
let base = args[1], out = args[2], scenarios = Array(args.dropFirst(3))
let frames: [Double] = [0.6, 1.4, 3.2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
// Errors the page throws, read back after each scenario: a script this WebKit cannot run shows up here, not as a blank shot.
let config = WKWebViewConfiguration()
config.userContentController.addUserScript(WKUserScript(source: "window.__errs = []; addEventListener('error', function (e) { __errs.push(e.message + ' @' + e.lineno) }); addEventListener('unhandledrejection', function (e) { __errs.push('rejection: ' + e.reason) });", injectionTime: .atDocumentStart, forMainFrameOnly: true))
let web = WKWebView(frame: win.contentView!.bounds, configuration: config)
win.contentView!.addSubview(web)
win.makeKeyAndOrderFront(nil)

func save(_ name: String, _ done: @escaping () -> Void) {
    web.takeSnapshot(with: nil) { image, error in
        if let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out + "/" + name + ".png"))
            if png.count < 40_000 { print("blank? \(name)") }
        } else { print("snapshot failed: \(name) \(error?.localizedDescription ?? "")") }
        done()
    }
}

func file(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "--").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "_").filter { $0.isASCII } }

func run(_ i: Int) {
    guard i < scenarios.count else {
        web.evaluateJavaScript("navigator.userAgent") { ua, _ in print("userAgent: \(ua ?? "")"); exit(0) }
        return
    }
    let s = scenarios[i]
    let q = s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    web.load(URLRequest(url: URL(string: "\(base)/design.html?record&play=\(q)&hold=60")!))
    // Frames start once the page, its fonts and its wallpaper have loaded (a cold runner takes a while), plus a moment to play.
    var waited = 0.0
    func ready() {
        web.evaluateJavaScript("document.readyState === 'complete' && document.fonts.status === 'loaded'") { r, _ in
            if (r as? Bool) == true || waited > 30 { if waited > 30 { print("not loaded after 30 s: \(s)") }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: shoot) }
            else { waited += 0.25; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: ready) }
        }
    }
    func shoot() {
        var k = 0
        func next() {
            guard k < frames.count else {
                return web.evaluateJavaScript("window.__errs.join(' | ')") { e, _ in
                    print("\(s): loaded in \(waited) s\((e as? String).map { $0.isEmpty ? "" : ", errors: " + $0 } ?? "")"); run(i + 1)
                }
            }
            let at = frames[k]; let prev = k == 0 ? 0 : frames[k - 1]; k += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + (at - prev)) { save("\(file(s))@\(at)", next) }
        }
        next()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: ready)
}

// A fresh WebKit on a CI runner hands back blank snapshots for its first minute or so: warm up on the first scenario until
// a snapshot has something in it, and say how long that took.
let started = Date()
func warm() {
    web.takeSnapshot(with: nil) { image, _ in
        let size = image?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])?.count } ?? 0
        if size > 40_000 || Date().timeIntervalSince(started) > 180 { print("warm after \(Int(Date().timeIntervalSince(started))) s"); run(0) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: warm) }
    }
}
web.load(URLRequest(url: URL(string: "\(base)/design.html?record&play=\(scenarios[0].addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)&hold=600")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: warm)
app.run()
