import Foundation
import os

public struct DangerSignal {
    public let reason: String
    public let severity: String  // "warning" or "critical"
}

public final class DangerDetector {
    private static let destructiveBashPatterns: [(pattern: String, reason: String)] = [
        ("rm\\s+-[^\\s]*r[^\\s]*f", "Recursive force delete (rm -rf)"),
        ("rm\\s+-[^\\s]*f[^\\s]*r", "Recursive force delete (rm -fr)"),
        ("git\\s+push\\s+.*--force", "Git force push"),
        ("git\\s+push\\s+-f", "Git force push"),
        ("git\\s+reset\\s+--hard", "Git hard reset"),
        ("git\\s+clean\\s+-[^\\s]*f", "Git clean force"),
        ("DROP\\s+(TABLE|DATABASE)", "SQL drop"),
        ("pkill\\s+-f", "Kill by full command match (broad)"),
        ("chmod\\s+777", "World-writable permissions"),
        (">(\\s|$)/dev/sd", "Direct device write"),
    ]

    private static let sensitivePathPrefixes: [String] = [
        "/etc/", "/usr/", "/System/",
    ]

    private static let sensitiveFileNames: Set<String> = [
        ".env", ".env.local", ".env.production",
        "credentials.json", "secrets.json", "service-account.json",
        "id_rsa", "id_ed25519", "authorized_keys",
    ]

    public static func check(toolName: String, inputPreview: String, filePath: String?, cwd: String?) -> DangerSignal? {
        if toolName == "Bash" {
            for (pattern, reason) in destructiveBashPatterns {
                if inputPreview.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    return DangerSignal(reason: reason, severity: "critical")
                }
            }
        }

        if let path = filePath, (toolName == "Write" || toolName == "Edit") {
            for prefix in sensitivePathPrefixes {
                if path.hasPrefix(prefix) {
                    return DangerSignal(reason: "Write to system path: \(path)", severity: "critical")
                }
            }

            let fileName = (path as NSString).lastPathComponent
            if sensitiveFileNames.contains(fileName) {
                return DangerSignal(reason: "Write to sensitive file: \(fileName)", severity: "warning")
            }

            if path.contains("/.ssh/") {
                return DangerSignal(reason: "Write to SSH directory", severity: "critical")
            }

            if let cwd = cwd, !path.hasPrefix(cwd + "/") && path != cwd {
                return DangerSignal(reason: "Write outside workspace: \(path)", severity: "warning")
            }
        }

        return nil
    }
}

public final class DangerNotifier {
    private let logger = Logger(subsystem: "com.claude-gate", category: "danger")
    private var ntfyEndpoint: String?

    public init() {}

    public func updateNtfyEndpoint(_ endpoint: String?) {
        self.ntfyEndpoint = endpoint
    }

    public func notify(signal: DangerSignal, toolName: String, inputPreview: String) {
        sendMacOSNotification(signal: signal, toolName: toolName, inputPreview: inputPreview)

        if let endpoint = ntfyEndpoint, !endpoint.isEmpty {
            sendNtfy(endpoint: endpoint, signal: signal, toolName: toolName, inputPreview: inputPreview)
        }
    }

    private func sendMacOSNotification(signal: DangerSignal, toolName: String, inputPreview: String) {
        let title = "claude-gate: \(signal.severity == "critical" ? "Critical" : "Warning")"
        let body = "\(signal.reason) — \(toolName): \(inputPreview.prefix(100))"
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escaped)\" with title \"\(title)\" sound name \"Funk\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    private func sendNtfy(endpoint: String, signal: DangerSignal, toolName: String, inputPreview: String) {
        guard let url = URL(string: endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(signal.severity == "critical" ? "5" : "3", forHTTPHeaderField: "Priority")
        request.setValue("claude-gate: \(signal.reason)", forHTTPHeaderField: "Title")
        request.setValue(signal.severity == "critical" ? "warning" : "triangular_flag_on_post", forHTTPHeaderField: "Tags")
        request.httpBody = "\(toolName): \(inputPreview.prefix(200))".data(using: .utf8)
        URLSession.shared.dataTask(with: request).resume()
    }
}
