import AppKit
import Foundation
import os

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var httpServer: HTTPServer?
    private var fileWatcher: FileWatcher?
    private let logger = Logger(subsystem: "com.claude-gate", category: "app")

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/config.json")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("claude-gate launching")

        let tracker = SubagentTracker()
        let store   = PermissionStore()
        let config  = (try? PolicyConfig.load(from: configURL)) ?? PolicyConfig.defaultConfig()

        let server = HTTPServer(config: config, tracker: tracker, store: store)
        self.httpServer = server

        Task {
            do { try await server.start() }
            catch { logger.error("Server start failed: \(error)") }
        }

        let ctrl = StatusItemController(store: store, config: config, configURL: configURL)
        self.statusController = ctrl

        // Badge + auto-open refresh — use .common so it fires even during modal dialogs
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak ctrl] _ in
            Task { @MainActor in
                ctrl?.refreshBadge()
                ctrl?.autoOpenIfNeeded()
                ctrl?.autoCloseIfEmpty()
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        // Hot-reload: push new config to both server and UI when file changes
        let configURL = self.configURL
        self.fileWatcher = FileWatcher(url: configURL) { [weak self, weak server, weak ctrl] in
            if let newCfg = try? PolicyConfig.load(from: configURL) {
                server?.updateConfig(newCfg)
                Task { @MainActor in ctrl?.updateConfig(newCfg) }
                self?.logger.info("Config reloaded")
            } else {
                self?.logger.error("Config reload failed from \(configURL.path)")
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        httpServer?.stop()
    }
}
