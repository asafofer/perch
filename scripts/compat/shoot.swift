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
let web = WKWebView(frame: win.contentView!.bounds)
win.contentView!.addSubview(web)
win.makeKeyAndOrderFront(nil)

func save(_ name: String, _ done: @escaping () -> Void) {
    web.takeSnapshot(with: nil) { image, error in
        if let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out + "/" + name + ".png"))
        } else { print("snapshot failed: \(name) \(error?.localizedDescription ?? "")") }
        done()
    }
}

func file(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "--").replacingOccurrences(of: " ", with: "_").filter { $0.isASCII } }

func run(_ i: Int) {
    guard i < scenarios.count else {
        web.evaluateJavaScript("navigator.userAgent") { ua, _ in print("userAgent: \(ua ?? "")"); exit(0) }
        return
    }
    let s = scenarios[i]
    let q = s.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    web.load(URLRequest(url: URL(string: "\(base)/design.html?record&play=\(q)&hold=60")!))
    // Each frame a fixed time after the scenario starts playing (the page waits 300 ms before it plays).
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        var k = 0
        func next() {
            guard k < frames.count else { return run(i + 1) }
            let at = frames[k]; let prev = k == 0 ? 0 : frames[k - 1]; k += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + (at - prev)) { save("\(file(s))@\(at)", next) }
        }
        next()
    }
}

web.evaluateJavaScript("1") { _, _ in run(0) }
app.run()
