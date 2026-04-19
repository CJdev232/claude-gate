import AppKit
import Foundation

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var httpServer: HTTPServer?
    private var fileWatcher: FileWatcher?

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/config.json")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let tracker = SubagentTracker()
        let store   = PermissionStore()
        let config  = (try? PolicyConfig.load(from: configURL)) ?? PolicyConfig.defaultConfig()

        let server = HTTPServer(config: config, tracker: tracker, store: store)
        self.httpServer = server

        Task {
            do { try await server.start() }
            catch { NSLog("claude-gate: server start failed: \(error)") }
        }

        let ctrl = StatusItemController(store: store, config: config, configURL: configURL)
        self.statusController = ctrl

        // Badge refresh — 0.2s poll is fine for ambient UI
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak ctrl] _ in
            Task { @MainActor in ctrl?.refreshBadge() }
        }

        // Hot-reload: push new config to running server when file changes
        let configURL = self.configURL
        self.fileWatcher = FileWatcher(url: configURL) { [weak server] in
            if let newCfg = try? PolicyConfig.load(from: configURL) {
                server?.updateConfig(newCfg)
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        httpServer?.stop()
    }
}
