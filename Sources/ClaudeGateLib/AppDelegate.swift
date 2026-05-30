import AppKit
import Foundation
import os

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var httpServer: HTTPServer?
    private var fileWatcher: FileWatcher?
    private var refreshTimer: Timer?
    private let logger = Logger(subsystem: "com.claude-gate", category: "app")
    private var modeState: GateModeState?

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/config.json")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("claude-gate launching")

        let modeState = GateModeState()
        self.modeState = modeState

        let tracker        = SubagentTracker()
        let store          = PermissionStore()
        let activityLog    = ActivityLog()
        let dangerNotifier = DangerNotifier()
        let config         = (try? PolicyConfig.load(from: configURL)) ?? PolicyConfig.defaultConfig()

        dangerNotifier.updateNtfyEndpoint(config.server.ntfyEndpoint)

        let server = HTTPServer(config: config, tracker: tracker, store: store, modeState: modeState, activityLog: activityLog, dangerNotifier: dangerNotifier)
        self.httpServer = server

        startServer(server)

        let ctrl = StatusItemController(store: store, config: config, configURL: configURL, modeState: modeState, activityLog: activityLog)
        self.statusController = ctrl

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak ctrl] _ in
            Task { @MainActor in
                ctrl?.refreshBadge()
                ctrl?.autoOpenIfNeeded()
                ctrl?.autoCloseIfEmpty()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.refreshTimer = timer

        // Hot-reload: push new config to both server and UI when file changes
        let configURL = self.configURL
        self.fileWatcher = FileWatcher(url: configURL) { [weak self, weak server, weak ctrl] in
            if let newCfg = try? PolicyConfig.load(from: configURL) {
                server?.updateConfig(newCfg)
                dangerNotifier.updateNtfyEndpoint(newCfg.server.ntfyEndpoint)
                Task { @MainActor in ctrl?.updateConfig(newCfg) }
                self?.logger.info("Config reloaded")
            } else {
                self?.logger.error("Config reload failed from \(configURL.path)")
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        httpServer?.stop()
    }

    private func startServer(_ server: HTTPServer) {
        Task {
            do {
                try await server.start()
                logger.info("Server started successfully")
            } catch {
                logger.error("Server start failed: \(error)")
                await handleServerStartFailure(server: server, error: error)
            }
        }
    }

    @MainActor
    private func handleServerStartFailure(server: HTTPServer, error: Error) {
        let alert = NSAlert()
        alert.messageText = "claude-gate: Port In Use"
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate/config.json")
        let port = (try? PolicyConfig.load(from: configURL))?.server.port ?? 9191
        alert.informativeText = "Another process may be using port \(port). Kill it and retry?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Kill & Retry")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Kill whatever holds the port
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            kill.arguments = ["bash", "-c", "lsof -ti :\(port) | xargs kill -9 2>/dev/null"]
            kill.standardOutput = FileHandle.nullDevice
            kill.standardError = FileHandle.nullDevice
            try? kill.run(); kill.waitUntilExit()

            // Brief delay then retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startServer(server)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}
