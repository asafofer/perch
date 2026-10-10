// Draws an SVG with WebKit, filters and all (the app icon's character wears an SVG filter, its coat), into a PNG.
// A borderless corner panel that never takes the keyboard: WebKit only draws what it can show, so the screen must be unlocked.
// Usage: swift scripts/render-svg.swift <in.svg> <out.png> <points>   (the PNG comes at the screen's scale: 512 pt is 1024 px on Retina)
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 4, let svg = try? String(contentsOfFile: args[1], encoding: .utf8), let pt = Double(args[3]) else {
    FileHandle.standardError.write("usage: render-svg.swift <in.svg> <out.png> <points>\n".data(using: .utf8)!); exit(2)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let panel: NSPanel, web: WKWebView, out: String
    init(points: Double, out: String) {
        self.out = out
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel = NSPanel(contentRect: NSRect(x: screen.maxX - points - 16, y: screen.minY + 16, width: points, height: points),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: points, height: points))
        web.setValue(false, forKey: "drawsBackground")
        super.init()
        web.navigationDelegate = self
        panel.contentView = web
        panel.orderFrontRegardless()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // a moment for the filters to draw
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(self.web.bounds.width))
            self.web.takeSnapshot(with: cfg) { image, _ in
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { exit(1) }
                try? png.write(to: URL(fileURLWithPath: self.out)); exit(0)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let r = Renderer(points: pt, out: args[2])
r.web.loadHTMLString("<html><body style=\"margin:0;background:transparent\"><style>svg{display:block;width:100vw;height:100vh}</style>" + svg + "</body></html>", baseURL: nil)
app.run()
