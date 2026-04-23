import Foundation

public enum PolicyValue: String, Codable, CaseIterable, Equatable {
    case allow, ask, deny
}

public struct ToolPolicy: Codable, Equatable {
    public var parent: PolicyValue
    public var subagent: PolicyValue
    public var timeout: PolicyValue

    public init(parent: PolicyValue, subagent: PolicyValue, timeout: PolicyValue) {
        self.parent = parent
        self.subagent = subagent
        self.timeout = timeout
    }
}

public struct ServerConfig: Codable, Equatable {
    public var port: Int
    public var timeout: Int
    public init(port: Int = 9191, timeout: Int = 30) {
        self.port = port; self.timeout = timeout
    }
}

public struct PolicyConfig: Codable {
    public var server: ServerConfig
    public var policies: [String: ToolPolicy]

    public init(server: ServerConfig, policies: [String: ToolPolicy]) {
        self.server = server; self.policies = policies
    }

    public static func defaultConfig() -> PolicyConfig {
        let allowAll    = ToolPolicy(parent: .allow, subagent: .allow, timeout: .allow)
        let askAskDeny  = ToolPolicy(parent: .ask,   subagent: .ask,   timeout: .deny)
        let askDenyDeny = ToolPolicy(parent: .ask,   subagent: .deny,  timeout: .deny)
        return PolicyConfig(server: ServerConfig(), policies: [
            "Read":             allowAll,
            "Glob":             allowAll,
            "Grep":             allowAll,
            "WebFetch":         allowAll,
            "WebSearch":        allowAll,
            "Task":             allowAll,
            "AskUserQuestion":  allowAll,
            "Write":            askAskDeny,
            "Edit":             askAskDeny,
            "Bash":             askDenyDeny,
        ])
    }

    /// Returns stored policy, or ask/ask/deny for unknown tools.
    public func policy(for toolName: String) -> ToolPolicy {
        policies[toolName] ?? ToolPolicy(parent: .ask, subagent: .ask, timeout: .deny)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> PolicyConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return defaultConfig()
        }
        return try JSONDecoder().decode(PolicyConfig.self, from: Data(contentsOf: url))
    }
}

// MARK: - FileWatcher

public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?

    public init(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
    }

    deinit { source?.cancel() }
}
