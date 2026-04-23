import Foundation

public enum InstallerError: Error, LocalizedError {
    case settingsWriteFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .settingsWriteFailed(let e):
            return "Could not write ~/.claude/settings.json: \(e)"
        }
    }
}

public struct Installer {

    // MARK: - Paths

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-gate")
    }

    static var configURL: URL { configDir.appendingPathComponent("config.json") }

    private static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.claude-gate.plist")
    }

    // MARK: - Install

    public static func install() throws {
        // 1. Create ~/.claude-gate/
        try FileManager.default.createDirectory(
            at: configDir, withIntermediateDirectories: true
        )

        // Create log directory for LaunchAgent stdout/stderr
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/claude-gate")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // 2. Write default config if absent
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try PolicyConfig.defaultConfig().save(to: configURL)
        }

        // 3. Register hooks in ~/.claude/settings.json
        try modifySettings { hooks in
            // Register PermissionRequest hook (idempotent)
            var permReq = (hooks["PermissionRequest"] as? [[String: Any]]) ?? []
            let alreadyRegistered = permReq.contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains {
                    $0["url"] as? String == "http://127.0.0.1:9191/permission"
                }
            }
            if !alreadyRegistered {
                permReq.append([
                    "matcher": ".*",
                    "hooks": [["type": "http", "url": "http://127.0.0.1:9191/permission"]]
                ])
                hooks["PermissionRequest"] = permReq
            }
            // Clean up any stale PreToolUse http entries from previous installs
            if var preToolUse = hooks["PreToolUse"] as? [[String: Any]] {
                preToolUse.removeAll { entry in
                    (entry["hooks"] as? [[String: Any]] ?? []).contains {
                        $0["url"] as? String == "http://127.0.0.1:9191/permission"
                    }
                }
                hooks["PreToolUse"] = preToolUse
            }
            hooks["SubagentStart"] = [
                [
                    "matcher": ".*",
                    "hooks": [
                        ["type": "command", "command": "/usr/local/bin/claude-gate subagent-start"]
                    ]
                ]
            ]
            hooks["SubagentStop"] = [
                [
                    "matcher": ".*",
                    "hooks": [
                        ["type": "command", "command": "/usr/local/bin/claude-gate subagent-stop"]
                    ]
                ]
            ]
        }

        // 4. LaunchAgent for login item
        try installLaunchAgent()
    }

    // MARK: - Uninstall

    public static func uninstall() throws {
        try modifySettings { hooks in
            // Remove PermissionRequest entry
            if var permReq = hooks["PermissionRequest"] as? [[String: Any]] {
                permReq.removeAll { entry in
                    (entry["hooks"] as? [[String: Any]] ?? []).contains {
                        $0["url"] as? String == "http://127.0.0.1:9191/permission"
                    }
                }
                hooks["PermissionRequest"] = permReq
            }
            // Also clean up any stale PreToolUse http entries
            if var preToolUse = hooks["PreToolUse"] as? [[String: Any]] {
                preToolUse.removeAll { entry in
                    (entry["hooks"] as? [[String: Any]] ?? []).contains {
                        $0["url"] as? String == "http://127.0.0.1:9191/permission"
                    }
                }
                hooks["PreToolUse"] = preToolUse
            }
            hooks.removeValue(forKey: "SubagentStart")
            hooks.removeValue(forKey: "SubagentStop")
        }
        removeLaunchAgent()
    }

    // MARK: - Helpers

    private static func modifySettings(_ modify: (inout [String: Any]) -> Void) throws {
        var root = loadSettings()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        modify(&hooks)
        root["hooks"] = hooks
        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            let claudeDir = claudeSettingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: claudeDir, withIntermediateDirectories: true
            )
            try data.write(to: claudeSettingsURL, options: .atomic)
        } catch {
            throw InstallerError.settingsWriteFailed(error)
        }
    }

    private static func loadSettings() -> [String: Any] {
        guard FileManager.default.fileExists(atPath: claudeSettingsURL.path),
              let data = try? Data(contentsOf: claudeSettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func installLaunchAgent() throws {
        let dir = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.claude-gate</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/claude-gate</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>StandardOutPath</key>
            <string>\(home)/Library/Logs/claude-gate/stdout.log</string>
            <key>StandardErrorPath</key>
            <string>\(home)/Library/Logs/claude-gate/stderr.log</string>
        </dict>
        </plist>
        """
        try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)

        // Unload first if already loaded (idempotent)
        let uid = getuid()
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(uid)/com.claude-gate"]
        bootout.standardOutput = FileHandle.nullDevice
        bootout.standardError = FileHandle.nullDevice
        try? bootout.run(); bootout.waitUntilExit()

        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", launchAgentURL.path]
        try bootstrap.run(); bootstrap.waitUntilExit()
    }

    private static func removeLaunchAgent() {
        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "gui/\(uid)/com.claude-gate"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        try? FileManager.default.removeItem(at: launchAgentURL)
    }
}
