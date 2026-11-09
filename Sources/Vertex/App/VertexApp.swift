import AppKit
import SwiftUI
import VertexKit

@main
struct VertexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Preferences.registerDefaults()
    }

    var body: some Scene {
        Window("Vertex", id: "main") {
            RootView()
                .frame(
                    minWidth: WindowMetrics.minimumWidth,
                    minHeight: WindowMetrics.minimumHeight
                )
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
    /// Apply the saved appearance before AppKit creates/shows the window, so
    /// the first frame is already in the right theme instead of transitioning
    /// from the system/restored snapshot.
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppAppearance.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
            for window in sender.windows {
                window.orderOut(nil)
            }
            TorrentEngine.shared.shutdown {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let paused = Preferences.startPaused
        let sequential = Preferences.sequentialDefault
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }

            // The session is created off the main actor. A file opened from
            // Finder can arrive before it is ready, so wait briefly instead of
            // dropping the add.
            let deadline = Date().addingTimeInterval(5)
            while !TorrentEngine.shared.isEngineReady,
                  TorrentEngine.shared.engineStartupError == nil,
                  Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            for url in urls {
                if TorrentInput.isMagnet(url.absoluteString) {
                    _ = TorrentEngine.shared.addMagnet(
                        url.absoluteString,
                        destination: nil,
                        startPaused: paused,
                        sequential: sequential
                    )
                } else if TorrentInput.isTorrentFile(url) {
                    _ = TorrentEngine.shared.addTorrentFile(
                        url,
                        destination: nil,
                        startPaused: paused,
                        sequential: sequential
                    )
                }
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

            exit(0)
        }
    }
}
#endif
