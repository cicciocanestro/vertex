import AppKit
import SwiftUI

@main
struct VertexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Preferences.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 980, minHeight: 760)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 800)
        .commands {
            AppCommands()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppAppearance.apply()
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        scheduleSnapshotIfNeeded()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            TorrentEngine.shared.shutdown()
        }
        return .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let paused = UserDefaults.standard.bool(forKey: PrefKey.startPaused)
        let sequential = UserDefaults.standard.bool(forKey: PrefKey.sequentialDefault)
        Task { @MainActor in
            for url in urls where url.pathExtension.lowercased() == "torrent" {
                _ = TorrentEngine.shared.addTorrentFile(
                    url,
                    destination: nil,
                    startPaused: paused,
                    sequential: sequential
                )
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}


#if DEBUG
extension AppDelegate {
    private func scheduleSnapshotIfNeeded() {
        guard let path = ProcessInfo.processInfo.environment["VERTEX_SNAPSHOT"] else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)

            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
               let view = window.contentView {
                window.display()
                view.layoutSubtreeIfNeeded()
                let scale = window.backingScaleFactor
                let width = Int(view.bounds.width * scale)
                let height = Int(view.bounds.height * scale)

                if let layer = view.layer,
                   let context = CGContext(
                       data: nil,
                       width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                   ) {
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: 0, y: view.bounds.height)
                    context.scaleBy(x: 1, y: -1)
                    layer.render(in: context)

                    if let image = context.makeImage(),
                       let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                }
            }

            #if DEBUG
            exit(0)
            #else
            NSApp.terminate(nil)
            #endif
        }
    }
}
#endif
