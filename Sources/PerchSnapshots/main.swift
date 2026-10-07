import SwiftUI
import AppKit
import PerchCore
import PerchUI

@MainActor func render() {
    let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let screen = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchSize: CGSize(width: 185, height: 32))
    let cases: [(String, NotchPhase, Int)] = [
        ("idle", .idle, 0), ("open-0", .open, 0), ("open-1", .open, 1), ("open-2", .open, 2),
        ("switcher", .switcher, 1), ("restoring", .restoring, 0),
    ]
    for (name, phase, index) in cases {
        let model = NotchViewModel(projects: FakeSessionProvider().parkedProjects(), screen: screen)
        model.force(phase: phase, selected: index)
        model.barProgress = 0.6
        let panel = model.panelSize
        let view = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.2, green: 0.33, blue: 0.3), Color(red: 0.33, green: 0.22, blue: 0.17)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: 34).frame(maxHeight: .infinity, alignment: .top)
            NotchRootView(model: model)
        }
        .frame(width: panel.width, height: panel.height)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("failed \(name)"); continue }
        try? png.write(to: outDir.appendingPathComponent("\(name).png"))
        print("wrote \(name).png")
    }
}
MainActor.assumeIsolated { render() }
